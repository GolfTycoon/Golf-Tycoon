shader_type canvas_item;
// Receive the same day/night CanvasModulate as course objects.

// Shared by desktop and WebGL 2. No screen reads or per-tile draw calls.
uniform sampler2D terrain_data : filter_nearest, repeat_disable;
uniform sampler2D vertex_elevation : filter_linear, repeat_disable;
uniform vec2 vertex_grid_size = vec2(129.0);
uniform vec2 relief_light = vec2(-0.6, -0.8);
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(128.0);
uniform vec2 tile_size = vec2(64.0, 32.0);
uniform vec4 fringe_color : source_color = vec4(0.38, 0.65, 0.28, 1.0);

uniform float elevation_step_y = 10.0;
uniform float elevation_texture_zero = 128.0;
uniform float elevation_texture_scale = 25.0;
uniform bool is_isometric = true;

uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_axis_x = vec2(64.0, 32.0);
uniform vec2 grid_axis_y = vec2(0.0, 32.0);
uniform vec2 surface_origin = vec2(0.0);
uniform vec2 surface_size = vec2(8192.0, 4096.0);

#include "res://shaders/terrain_heightfield.gdshaderinc"

float hash(vec2 p) {
	// Keep intermediates small: large sin hashes form bands on mobile/GL drivers.
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

// Main channel half-width, shared by the Stream surface and its pond-mouth
// shoreline so the open part of their common edge matches the actual channel.
float stream_main_width(vec2 g, float channel_along, float channel_across) {
	return 0.024 + (noise(g * 1.7 + vec2(7.0, 3.0)) - 0.5) * 0.01
		+ (noise(vec2(channel_along * 6.0 + 13.0, channel_across * 3.0 + 5.0)) - 0.5) * 0.015;
}

// Terrain ids (TerrainTypes.Type) with looks of their own below.
const float T_FLOWER_BED = 12.0;
const float T_ROCKS = 13.0;
const float T_FIRM_FAIRWAY = 14.0;
const float T_POT_BUNKER = 15.0;
const float T_STREAM = 16.0;
const float T_DEEP_ROUGH = 17.0;
const float T_WASTE_BUNKER = 18.0;
const float T_BRUSH = 19.0;
const float T_SMALL_BOULDERS = 20.0;
const float T_LARGE_BOULDERS = 21.0;
// The tree catalogue: one id per species, 11 and 22..32, matching
// TerrainTypes.TREE_SPECIES_TILES. The canopies are drawn by the TreeOverlay;
// the surface paints what each species stands on.
const float T_TREES = 11.0;
const float T_OAK = 22.0;
const float T_PINE = 23.0;
const float T_MAPLE = 24.0;
const float T_BIRCH = 25.0;
const float T_CACTUS = 26.0;
const float T_FESCUE = 27.0;
const float T_CATTAILS = 28.0;
const float T_SHRUB = 29.0;
const float T_PALM = 30.0;
const float T_DEAD_TREE = 31.0;
const float T_HEATHER = 32.0;
// Light direction on the ground plane, in grid units (screen upper left).
const vec2 GROUND_LIGHT = vec2(-0.83, -0.55);
// Half width of the anti-aliased material boundary, and of the edge-treatment
// band every surface's `edge` fade runs in. EDGE_LIP_LO..HI are the coverage
// values that fade runs across: the Bunker's grass lip uses them, and the
// borders on stream banks, deep rough, waste bunkers, brush, stony grounds,
// wild flowers and woodland tiles copy them, so every border is the same size.
// Declared up here because the shading language wants every constant before
// its first use.
const float AA = 0.04;
const float FRINGE = 0.30;
const float EDGE_LIP_LO = 0.50;
const float EDGE_LIP_HI = 0.68;

// Stony ground: painted Rocks and the two boulder fields. Each fills the full
// tile with its own stone texture and draws its own border against other tiles.
bool is_rocks(float id) {
	return id == T_ROCKS || id == T_SMALL_BOULDERS || id == T_LARGE_BOULDERS;
}

// Woodland: the Trees tile and every species tile beside it. Each fills the
// full tile with its own ground texture and draws its own border.
bool is_tree(float id) {
	return id == T_TREES || (id >= T_OAK && id <= T_HEATHER);
}

// Full-tile rough, scrub, sand, stone, floral and woodland terrains that frame
// open edges with a border of the same size as the Bunker's lip instead of
// blending into neighbouring terrain types.
bool is_bordered_tile(float id) {
	return id == T_DEEP_ROUGH || id == T_WASTE_BUNKER || id == T_BRUSH
		|| is_rocks(id) || id == T_FLOWER_BED || is_tree(id);
}

// Stone cell density, radius and standing height for the three stony grounds.
float rocks_cell_scale(float id) {
	return id == T_SMALL_BOULDERS ? 2.8 : (id == T_LARGE_BOULDERS ? 1.85 : 5.0);
}

float rocks_radius(float id, float roll) {
	if (id == T_SMALL_BOULDERS) {
		return 0.082 + roll * 0.075;   // Rounded cobbles and fieldstones
	}
	if (id == T_LARGE_BOULDERS) {
		return 0.145 + roll * 0.105;   // Massive standing boulders
	}
	return 0.048 + roll * 0.040;       // Packed angular scree and gravel
}

// How much taller a stone stands than its footprint along the ground (1 = a
// stone lying flat on the ground, 1.45 = a boulder standing up).
float rocks_tallness(float id) {
	return id == T_LARGE_BOULDERS ? 1.45 : 1.0;
}

float tile_at(vec2 p) {
	vec4 data = texture(terrain_data, (clamp(p, vec2(0.0), grid_size - 1.0) + 0.5) / grid_size);
	return floor(data.r * 255.0 + 0.5);
}

// Boundary class: terrain that reads as one material across tile borders. A
// stream and pond remain linked as wet terrain, but keep separate boundary
// classes so pond water draws a bank against the stream's rough turf. The
// stream mouth cuts an opening in that bank (edge_between_at), keeping the
// water continuous. Every terrain tile type keeps its own id so connected tiles
// of the same type merge seamlessly while different types draw a border.
float boundary_class(float id) {
	if (id == T_STREAM) { return T_STREAM; }
	return id;
}

// 1 where two tiles need a material boundary between them.
float differs(float a, float b) {
	return step(0.5, abs(boundary_class(a) - boundary_class(b)));
}

// Short/unbordered grass surfaces that inset pits and channels can sit in.
bool is_turf(float id) {
	return id == 1.0 || id == 2.0 || id == 3.0 || id == 4.0 || id == T_FIRM_FAIRWAY;
}

// Terrain drawn as an inset feature (a pot bunker or stream channel) inside its
// own rough turf bank.
bool is_inset(float id) {
	return id == T_POT_BUNKER || id == T_STREAM;
}

// Whether an inset feature on `id` sits inside neighbouring `ground`.
bool carries(float ground, float id) {
	return is_turf(ground) && is_inset(id);
}

// Whether a tile of type `own` draws a boundary against its neighbour `other`.
// Unbordered turf runs straight into an inset pot or stream; bordered tiles
// always draw their boundary against any different terrain tile type.
float edge_between(float own, float other) {
	return (is_inset(other) && carries(own, other)) ? 0.0 : differs(own, other);
}

// Keep the bank along a Stream/Water border, but cut it back around the
// widening channel mouth. `stream_end` is 0 or 1 at the end of the stream
// tile touching this edge; `along_edge` runs across that edge from 0 to 1.
float edge_between_at(float own, float other, float along_edge, float stream_end, vec2 world) {
	float boundary = edge_between(own, other);
	if ((own == T_STREAM && other == 8.0) || (own == 8.0 && other == T_STREAM)) {
		float main_width = stream_main_width(world / tile_size, stream_end, along_edge);
		// The water mask fades to zero at estuary_width + 0.02. Keep the bank
		// open only through that active water, not across the muddy/rough banks.
		float mouth_radius = main_width * 11.0 + 0.02;
		float bank = smoothstep(mouth_radius, mouth_radius + 0.06, abs(along_edge - 0.5));
		return boundary * bank;
	}
	return boundary;
}

vec3 palette_color(float id) {
	// The palette holds one texel per terrain id; its width is the id count.
	float count = float(textureSize(palette, 0).x);
	return texture(palette, vec2((id + 0.5) / count, 0.5)).rgb;
}

// Polynomial smooth minimum: rounds the inside corner where two shapes meet.
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Cellular noise over grid-space `x`. Returns vec4(distance to the nearest
// feature point, distance to the cell border (F2 - F1), random id of the
// nearest cell, 0); `to_point` is the offset from `x` to that feature point.
vec4 cells(vec2 x, out vec2 to_point) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 nearest = n;
	to_point = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 o = vec2(hash(n + b), hash(n + b + vec2(17.3, 5.1))) * 0.8 + 0.1;
			vec2 r = b + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				nearest = n + b;
				to_point = r;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec4(sqrt(f1), sqrt(f2) - sqrt(f1), hash(nearest + vec2(3.7, 9.2)), 0.0);
}

// Sparse round dots (pebbles, blossoms): `density` of cells get one dot.
float dots(vec2 x, float density, float radius) {
	vec2 n = floor(x);
	vec2 o = vec2(hash(n + vec2(41.0, 7.0)), hash(n + vec2(3.0, 59.0))) * 0.5 + 0.25;
	float d = length(fract(x) - o);
	return (1.0 - smoothstep(radius * 0.6, radius, d)) * step(1.0 - density, hash(n + vec2(11.0, 23.0)));
}

// Full-tile stony surfaces: Rocks (packed angular slate scree), Small Boulders
// (rounded river cobbles over sandy loam), and Large Boulders (massive craggy
// granite boulders over fissured dark bedrock).
vec3 stony_surface(float id, vec3 base, vec2 g) {
	float scale = rocks_cell_scale(id);
	vec2 to_point;
	vec4 c = cells(g * scale, to_point);
	float tall = rocks_tallness(id);
	float radius = rocks_radius(id, c.z);
	float present = step(id == T_LARGE_BOULDERS ? 0.02 : 0.05, c.z);
	vec2 from_center = -to_point / scale;
	vec2 up = is_isometric ? vec2(-0.70710678) : vec2(0.0, -1.0);
	float rise = dot(from_center, up);
	vec2 lateral = from_center - up * rise;
	float r = sqrt((rise / tall) * (rise / tall) + dot(lateral, lateral));
	float outline_scale = id == T_SMALL_BOULDERS ? 0.22 : 0.36;
	float outline = (noise(g * (scale * 3.4) + vec2(id * 3.0, 1.0)) - 0.5) * radius * outline_scale;
	float body = (1.0 - smoothstep(radius - 0.010, radius + 0.010, r + outline)) * present;
	float lit = clamp(0.5 + dot(from_center / max(radius, 0.01), GROUND_LIGHT) * 0.58, 0.0, 1.0);
	float shade = (1.0 - smoothstep(radius * 0.88, radius * (1.55 + (tall - 1.0) * 0.85),
			length(from_center + GROUND_LIGHT * radius * 0.42))) * present;

	vec3 ground;
	vec3 stone_tint;
	if (id == T_ROCKS) {
		// Cool slate-gravel scree dusted with pale quartz grit.
		ground = mix(base * 0.60, vec3(0.35, 0.37, 0.42), 0.50) * (0.90 + noise(g * 10.5) * 0.18);
		ground = mix(ground, vec3(0.76, 0.78, 0.80), dots(g * 23.0, 0.36, 0.25) * 0.45);
		stone_tint = mix(base, vec3(0.56, 0.59, 0.65), 0.34) * (0.86 + c.z * 0.28);
	} else if (id == T_SMALL_BOULDERS) {
		// Warm sandy-loam matrix with mossy specks and rounded fieldstones.
		ground = mix(base * 0.62, vec3(0.45, 0.37, 0.26), 0.54) * (0.88 + noise(g * 7.5) * 0.22);
		ground = mix(ground, vec3(0.32, 0.44, 0.24), dots(g * 15.0 + vec2(4.0, 9.0), 0.26, 0.28) * 0.45);
		vec3 warm_cobble = mix(vec3(0.68, 0.58, 0.44), vec3(0.54, 0.51, 0.47), fract(c.z * 7.3));
		stone_tint = mix(base, warm_cobble, 0.52) * (0.90 + c.z * 0.22);
	} else {
		// Dark fissured granite bedrock with wedged stones beneath tall boulders.
		ground = mix(base * 0.46, vec3(0.24, 0.23, 0.22), 0.58) * (0.86 + noise(g * 5.8) * 0.24);
		float fissure = 1.0 - smoothstep(0.0, 0.055, abs(noise(g * 4.4 + vec2(6.0, 2.0)) - 0.5));
		ground *= 1.0 - fissure * 0.28;
		float wedged = dots(g * 5.2 + vec2(3.7, 8.1), 0.72, 0.36);
		ground = mix(ground, mix(base, vec3(0.46, 0.44, 0.42), 0.45), wedged * 0.75);
		vec3 crag_tone = mix(vec3(0.52, 0.50, 0.48), vec3(0.62, 0.56, 0.50), fract(c.z * 5.1));
		stone_tint = mix(base, crag_tone, 0.42) * (0.88 + c.z * 0.24);
	}
	ground *= 1.0 - shade * (0.30 + (tall - 1.0) * 0.20);
	vec3 feature = stone_tint * (0.62 + lit * 0.54) * (0.92 + noise(g * 32.0) * 0.14);
	float crown = clamp(rise / max(radius * tall, 0.01), -1.0, 1.0);
	feature *= 1.0 + (tall - 1.0) * 0.34 * crown;
	if (id == T_LARGE_BOULDERS) {
		// Lichen patches and crag striations on big boulders.
		float lichen = dots(g * 9.5 + vec2(2.0, 7.0), 0.26, 0.30) * step(0.15, crown);
		feature = mix(feature, vec3(0.58, 0.64, 0.42), lichen * 0.42);
	}
	return mix(ground, feature, body);
}

// Full-tile tangled scrub and gorse bushes with sunlit yellow blossoms.
vec3 brush_surface(vec3 base, vec2 g) {
	float scale = 3.2;
	vec2 to_point;
	vec4 c = cells(g * scale + vec2(3.1, 7.4), to_point);
	float radius = 0.105 + c.z * 0.048;
	vec2 from_center = -to_point / scale;
	float r = length(from_center);
	float outline = (noise(g * 22.0) - 0.5) * 0.036;
	float body = 1.0 - smoothstep(radius - 0.014, radius + 0.014, r + outline);
	float lit = clamp(0.5 + dot(from_center / max(radius, 0.01), GROUND_LIGHT) * 0.56, 0.0, 1.0);
	float shade = 1.0 - smoothstep(radius * 0.85, radius * 1.55,
			length(from_center + GROUND_LIGHT * radius * 0.40));

	vec3 undergrowth = mix(base * 0.48, vec3(0.24, 0.20, 0.12), 0.45) * (0.86 + noise(g * 11.0) * 0.24);
	float twigs = 1.0 - smoothstep(0.0, 0.06, abs(noise(vec2((g.x + g.y) * 14.0, (g.x - g.y) * 5.0)) - 0.5));
	undergrowth = mix(undergrowth, vec3(0.38, 0.28, 0.16), twigs * 0.40);
	undergrowth *= 1.0 - shade * 0.28;

	vec3 crown = mix(base, vec3(0.28, 0.42, 0.18), 0.28) * (0.60 + lit * 0.58)
		* (0.86 + noise(g * 26.0) * 0.26);
	float blossom = dots(g * 14.5, 0.20, 0.30) * step(0.42, lit);
	crown = mix(crown, vec3(0.95, 0.84, 0.28), blossom * 0.82);
	return mix(undergrowth, crown, body);
}

// Full-tile wildflower meadow: lush clover sward carpeted with multi-colour blooms.
vec3 flower_bed_surface(vec3 base, vec2 g) {
	vec3 clover = mix(palette_color(3.0) * 0.80, vec3(0.18, 0.44, 0.20), 0.48);
	clover = mix(clover, base * 0.82, 0.18);
	clover *= 0.86 + noise(g * 8.5) * 0.24 + (noise(g * 21.0) - 0.5) * 0.12;
	clover = mix(clover, vec3(0.93, 0.46, 0.62), dots(g * 9.5, 0.36, 0.32) * 0.82);
	clover = mix(clover, vec3(0.97, 0.80, 0.28), dots(g * 10.5 + vec2(4.3, 7.1), 0.34, 0.30) * 0.80);
	clover = mix(clover, vec3(0.72, 0.56, 0.92), dots(g * 8.8 + vec2(11.2, 2.7), 0.30, 0.32) * 0.78);
	clover = mix(clover, vec3(0.96, 0.95, 0.86), dots(g * 13.0 + vec2(6.7, 13.4), 0.28, 0.25) * 0.75);
	return clover;
}

// Each of the 12 woodland tiles paints its own full-tile ground texture beneath
// the TreeOverlay canopies, worked up from the theme palette so biomes stay
// cohesive while every tree tile remains distinct.
vec3 tree_ground(float id, vec3 base, vec2 g, float grain, float patch) {
	if (id == T_TREES) {
		// Woodland humus: rich dark forest earth, emerald moss cushions and twigs.
		vec3 humus = mix(base * 0.60, vec3(0.26, 0.21, 0.14), 0.58) * (0.88 + noise(g * 6.0) * 0.22);
		float moss = smoothstep(0.50, 0.78, noise(g * 3.8 + vec2(2.0, 6.0)));
		humus = mix(humus, mix(base, vec3(0.20, 0.44, 0.18), 0.55), moss * 0.62);
		humus = mix(humus, vec3(0.46, 0.35, 0.22), dots(g * 11.5, 0.28, 0.28) * 0.45);
		return humus * (0.96 + patch * 0.08);
	}
	if (id == T_OAK) {
		// Oak leaf litter: warm bronze-russet oak leaves and pale acorns.
		vec3 litter = mix(base * 0.56, vec3(0.44, 0.30, 0.17), 0.64) * (0.88 + noise(g * 5.5) * 0.22);
		litter = mix(litter, vec3(0.66, 0.45, 0.20), dots(g * 12.0, 0.48, 0.34) * 0.58);
		litter = mix(litter, vec3(0.50, 0.32, 0.15), dots(g * 8.5 + vec2(3.1, 6.4), 0.36, 0.38) * 0.45);
		litter = mix(litter, vec3(0.78, 0.66, 0.38), dots(g * 16.0 + vec2(8.0, 1.0), 0.20, 0.22) * 0.65);
		return litter * (0.96 + patch * 0.08);
	}
	if (id == T_PINE) {
		// Pine needles: rust-sienna needle drifts combed diagonally with woody cones.
		vec3 needles = mix(base * 0.54, vec3(0.38, 0.23, 0.14), 0.68);
		float drift = sin((g.x + g.y) * 7.0 + noise(g * 1.5) * 4.5);
		float fine = noise(vec2((g.x - g.y) * 26.0, (g.x + g.y) * 4.2));
		needles *= 0.88 + smoothstep(-0.4, 0.4, drift) * 0.10 + (fine - 0.5) * 0.14;
		needles = mix(needles, vec3(0.22, 0.13, 0.08), dots(g * 13.5, 0.26, 0.28) * 0.65);
		needles = mix(needles, vec3(0.58, 0.37, 0.19), dots(g * 19.0 + vec2(3.0, 5.0), 0.22, 0.24) * 0.52);
		return needles;
	}
	if (id == T_MAPLE) {
		// Fallen maple leaves: scarlet, burnt-orange and amber foliage carpet.
		vec3 earth = mix(base * 0.56, vec3(0.34, 0.23, 0.16), 0.60) * (0.90 + noise(g * 6.0) * 0.18);
		earth = mix(earth, vec3(0.78, 0.23, 0.18), dots(g * 11.5, 0.40, 0.34) * 0.72);
		earth = mix(earth, vec3(0.86, 0.46, 0.18), dots(g * 10.0 + vec2(5.2, 3.8), 0.38, 0.33) * 0.68);
		earth = mix(earth, vec3(0.90, 0.70, 0.24), dots(g * 13.5 + vec2(9.4, 7.1), 0.32, 0.28) * 0.62);
		return earth;
	}
	if (id == T_BIRCH) {
		// Birch grove floor: cool green moss strewn with papery white bark strips.
		vec3 loam = mix(base * 0.70, vec3(0.26, 0.37, 0.24), 0.54) * (0.88 + noise(g * 6.5) * 0.22);
		float moss = smoothstep(0.48, 0.78, noise(g * 4.2 + vec2(7.0, 2.0)));
		loam = mix(loam, vec3(0.34, 0.54, 0.26), moss * 0.52);
		loam = mix(loam, vec3(0.88, 0.87, 0.82), dots(g * 10.5, 0.36, 0.30) * 0.78);
		loam = mix(loam, vec3(0.80, 0.74, 0.30), dots(g * 14.5 + vec2(2.3, 8.9), 0.26, 0.25) * 0.55);
		return loam;
	}
	if (id == T_CACTUS) {
		// Desert caliche hardpan: sun-baked terracotta crust with red sandstone grit.
		vec3 caliche = mix(vec3(0.74, 0.54, 0.36), palette_color(T_WASTE_BUNKER), 0.32);
		caliche *= 0.92 + (noise(g * 4.5) - 0.5) * 0.14
			+ sin((g.x * 1.4 - g.y) * 9.0 + noise(g * 3.0) * 4.0) * 0.035;
		caliche = mix(caliche, vec3(0.54, 0.32, 0.20), dots(g * 11.0, 0.36, 0.28) * 0.65);
		caliche = mix(caliche, vec3(0.90, 0.82, 0.68), dots(g * 18.5 + vec2(4.0, 6.0), 0.30, 0.22) * 0.55);
		return caliche;
	}
	if (id == T_FESCUE) {
		// Golden fescue straw: wind-combed blonde links grass and oat plumes.
		vec3 straw = mix(vec3(0.75, 0.66, 0.38), palette_color(T_FIRM_FAIRWAY), 0.24);
		float sway = (noise(g * 3.0 + vec2(2.0, 7.0)) - 0.5) * 0.32;
		vec2 u = vec2(g.x - g.y + sway, g.x + g.y);
		float blades = noise(vec2(u.x * 24.0, u.y * 2.8 + noise(vec2(u.x * 2.2, u.y * 1.8)) * 1.6));
		straw *= 0.84 + blades * 0.30;
		straw = mix(straw, vec3(0.92, 0.86, 0.58), dots(g * 10.5 + vec2(1.7, 5.3), 0.30, 0.28) * 0.62);
		return straw;
	}
	if (id == T_CATTAILS) {
		// Waterlogged marsh silt: dark wetland mud, shallow teal puddles and reeds.
		vec3 silt = mix(base * 0.44, vec3(0.27, 0.24, 0.19), 0.68) * (0.90 + noise(g * 5.2) * 0.18);
		float puddle = smoothstep(0.50, 0.72, noise(g * 3.6 + vec2(3.0, 7.0)));
		vec3 water_tint = mix(palette_color(8.0), vec3(0.24, 0.48, 0.46), 0.52);
		silt = mix(silt, water_tint, puddle * 0.58);
		silt = mix(silt, vec3(0.38, 0.58, 0.24), dots(g * 15.0, 0.28, 0.26) * 0.52);
		silt = mix(silt, vec3(0.62, 0.54, 0.34), dots(g * 10.5 + vec2(6.0, 2.0), 0.24, 0.32) * 0.48);
		return silt * (0.96 + patch * 0.08);
	}
	if (id == T_SHRUB) {
		// Shredded garden bark mulch: dark cedar chips with dropped green leaves.
		vec3 mulch = mix(base * 0.40, vec3(0.28, 0.17, 0.11), 0.74);
		float chips = noise(vec2((g.x + g.y) * 22.0, (g.x - g.y) * 9.0));
		mulch *= 0.84 + chips * 0.30;
		mulch = mix(mulch, vec3(0.50, 0.31, 0.18), dots(g * 16.0, 0.40, 0.30) * 0.55);
		mulch = mix(mulch, mix(base, vec3(0.30, 0.54, 0.24), 0.60),
			dots(g * 9.5 + vec2(2.0, 5.0), 0.22, 0.28) * 0.55);
		return mulch;
	}
	if (id == T_PALM) {
		// Rippled tropical coral sand: bright ivory sand, shell grit and frond wisps.
		vec3 sand = mix(vec3(0.88, 0.82, 0.64), palette_color(7.0), 0.32);
		sand *= 1.0 + sin((g.x + g.y * 0.6) * 16.0 + noise(g * 2.5) * 3.0) * 0.055;
		sand = mix(sand, vec3(0.97, 0.95, 0.90), dots(g * 15.0, 0.34, 0.24) * 0.62);
		sand = mix(sand, vec3(0.36, 0.50, 0.24), dots(g * 7.5 + vec2(5.0, 9.0), 0.18, 0.32) * 0.45);
		return sand;
	}
	if (id == T_DEAD_TREE) {
		// Cracked parched earth: ashen drought polygons and bleached wood splinters.
		vec3 parched = mix(vec3(0.50, 0.45, 0.38), base * 0.92, 0.22) * (0.92 + noise(g * 5.0) * 0.16);
		vec2 tp;
		vec4 cr = cells(g * 4.2, tp);
		float crack = 1.0 - smoothstep(0.0, 0.075, cr.y);
		parched = mix(parched, vec3(0.19, 0.16, 0.13), crack * 0.72);
		parched = mix(parched, vec3(0.76, 0.72, 0.64), dots(g * 11.5, 0.26, 0.26) * 0.58);
		return parched;
	}
	// T_HEATHER: dark moorland peat richly carpeted with blooming purple heather.
	vec3 peat = mix(base * 0.46, vec3(0.25, 0.17, 0.21), 0.66) * (0.88 + noise(g * 6.0) * 0.20);
	peat = mix(peat, vec3(0.64, 0.28, 0.62), dots(g * 11.0, 0.46, 0.35) * 0.72);
	peat = mix(peat, vec3(0.80, 0.52, 0.80), dots(g * 15.5 + vec2(4.2, 8.1), 0.34, 0.28) * 0.62);
	peat = mix(peat, vec3(0.58, 0.56, 0.54), dots(g * 13.0 + vec2(9.0, 3.0), 0.18, 0.22) * 0.42);
	return peat * (0.96 + grain * 0.06);
}

// Distinct Bunker-sized border colour and micro-grain for each of the 19
// full-tile rough, scrub, sand, stone, floral and woodland terrains.
vec3 tile_border(float id, vec2 g, float grain) {
	float tex = (noise(g * 18.0 + vec2(id * 2.3, id * 1.7)) - 0.5) * 0.14 + (grain - 0.5) * 0.06;
	if (id == T_DEEP_ROUGH) {
		return vec3(0.72, 0.65, 0.34) * (1.0 + tex); // Golden straw-thatch rim
	}
	if (id == T_WASTE_BUNKER) {
		return vec3(0.44, 0.28, 0.15) * (1.0 + tex); // Weathered ochre-umber crust
	}
	if (id == T_BRUSH) {
		return vec3(0.58, 0.50, 0.13) * (1.0 + tex); // Thorny gorse-ochre hedge rim
	}
	if (id == T_ROCKS) {
		return vec3(0.17, 0.20, 0.30) * (1.0 + tex); // Dark blue-slate stone kerb
	}
	if (id == T_SMALL_BOULDERS) {
		return vec3(0.76, 0.72, 0.58) * (1.0 + tex); // Pale buff limestone rim
	}
	if (id == T_LARGE_BOULDERS) {
		return vec3(0.30, 0.37, 0.48) * (1.0 + tex); // Cool steely granite rim
	}
	if (id == T_FLOWER_BED) {
		return vec3(0.78, 0.36, 0.44) * (1.0 + tex); // Terracotta rose-clay garden edging
	}
	if (id == T_TREES) {
		return vec3(0.09, 0.25, 0.12) * (1.0 + tex); // Deep evergreen forest rim
	}
	if (id == T_OAK) {
		return vec3(0.72, 0.46, 0.18) * (1.0 + tex); // Warm honey-oak timber rim
	}
	if (id == T_PINE) {
		return vec3(0.10, 0.34, 0.34) * (1.0 + tex); // Cool blue-spruce needle rim
	}
	if (id == T_MAPLE) {
		return vec3(0.48, 0.11, 0.16) * (1.0 + tex); // Crimson-burgundy maple rim
	}
	if (id == T_BIRCH) {
		float lenticel = step(0.78, noise(vec2(g.x * 26.0, g.y * 8.0)));
		return mix(vec3(0.86, 0.84, 0.79) * (1.0 + tex * 0.6), vec3(0.30, 0.28, 0.26), lenticel * 0.45);
	}
	if (id == T_CACTUS) {
		return vec3(0.64, 0.28, 0.15) * (1.0 + tex); // Baked canyon red-adobe rim
	}
	if (id == T_FESCUE) {
		return vec3(0.28, 0.23, 0.12) * (1.0 + tex); // Dark coastal links-peat sod
	}
	if (id == T_CATTAILS) {
		return vec3(0.20, 0.54, 0.52) * (1.0 + tex); // Wetland sedge turquoise-reed rim
	}
	if (id == T_SHRUB) {
		return vec3(0.66, 0.52, 0.42) * (1.0 + tex); // Warm sandstone garden kerb
	}
	if (id == T_PALM) {
		return vec3(0.52, 0.39, 0.26) * (1.0 + tex); // Warm coconut-husk brown rim
	}
	if (id == T_DEAD_TREE) {
		return vec3(0.15, 0.14, 0.16) * (1.0 + tex); // Charred driftwood-ash rim
	}
	return vec3(0.60, 0.25, 0.58) * (1.0 + tex);     // Blooming orchid-plum heather rim
}

// ---------------------------------------------------------------------------
// Water: depth, and the bed seen through it.
//
// A water tile is a body of water, not a flat sheet of colour. Its floor is
// painted first — sand, silt, gravel, ripple marks and weed — and the water
// above it takes the light out of that floor in proportion to how deep the
// pixel is. The shallows therefore run clear over a bright, detailed bed, and
// the middle of a pond goes dark and still, with nothing to see but the
// surface. Depth is measured from the bank: the distance to the nearest tile
// that is not water, in tiles, so a painted pond needs no depth data of its
// own and a narrow arm stays shallow along its whole length.
// ---------------------------------------------------------------------------

// The deepest water worth measuring, in tiles. A pond wider than this has a
// floor that is out of sight anyway, so the walk away from the bank stops here.
const float WATER_MAX_DEPTH = 3.2;
// How much of the floor's light one tile of water takes out on its way back up.
const float WATER_ABSORB = 0.95;
// Fine detail is lost to scattering faster than the floor's own colour is, so
// ripple marks, gravel, weed and caustics die out well inside the deep water.
const float WATER_DETAIL_ABSORB = 2.4;
// The same absorption across a stream's channel, per tile of channel depth.
const float RIVER_ABSORB = 70.0;

// The depth of the water under a pixel, in tiles: its Euclidean distance to
// the nearest bank, so the shallows follow the shoreline in smooth rings
// instead of square steps. `g` is in grid units; each tile is the unit square
// [n, n+1). The nearest point on a dry tile's square to `g` is the shore,
// and the nearest of those over every dry tile within reach is the depth.
// A pixel outside the water is the shallows, wherever the water runs on to.
float water_depth(vec2 g) {
	vec2 cell = floor(g);
	if (abs(tile_at(cell) - 8.0) > 0.5) {
		return 0.0;
	}
	float best = WATER_MAX_DEPTH;
	for (int oy = -3; oy <= 3; oy++) {
		for (int ox = -3; ox <= 3; ox++) {
			vec2 ncell = cell + vec2(float(ox), float(oy));
			if (abs(tile_at(ncell) - 8.0) < 0.5) {
				continue;
			}
			vec2 closest = clamp(g, ncell, ncell + vec2(1.0));
			float d = length(g - closest);
			if (d < best) {
				best = d;
			}
		}
	}
	return best;
}

// The floor of a water tile: sand and silt with the gravel, ripple marks and
// weed a shallow bed carries. `g` is in grid units, so one continuous bed runs
// under every tile of the pond instead of each tile repeating a pattern;
// `clear` is 1 where the water is thin enough for the sun to reach the floor
// and 0 where it is not, which is how far the fine detail is carried; `river`
// coarsens the material, because a stream's floor is gravel swept by the
// current rather than silt settling out of still water.
vec3 water_bed(vec2 g, float clear, bool river) {
	vec3 bed = mix(palette_color(T_WASTE_BUNKER), vec3(0.42, 0.36, 0.27), 0.42);
	// Broad drifts of silt over the sand, so the floor is not one flat colour.
	bed *= 0.86 + noise(g * 5.0) * 0.22 + (noise(g * 1.6) - 0.5) * 0.12;
	// Ripple marks combed into the sediment along one world direction, warped
	// by the bed's own relief so they wander instead of running in straight
	// lines. Finer and closer together where the current cuts them.
	vec2 comb = vec2(g.x + g.y, g.y - g.x) * 0.7;
	bed *= 1.0 + sin(comb.x * (river ? 34.0 : 18.0) + noise(g * 2.3) * 4.0) * 0.1 * clear;
	// Grit, then the odd cobble: coarser and denser on a river floor.
	float grit = dots(g * (river ? 32.0 : 20.0), river ? 0.72 : 0.42, river ? 0.3 : 0.24);
	bed = mix(bed, bed * vec3(0.64, 0.62, 0.58), grit * (0.45 + clear * 0.5));
	float cobbles = dots(g * (river ? 11.0 : 7.0) + vec2(5.0, 2.0), river ? 0.32 : 0.15, 0.42);
	bed = mix(bed, bed * vec3(1.2, 1.16, 1.08), cobbles * (0.4 + clear * 0.5));
	// Weed grows only where the light reaches, so it hugs the shallows.
	float weed = dots(g * 5.5 + vec2(3.0, 8.0), 0.34, 0.46) * clear;
	bed = mix(bed, vec3(0.15, 0.27, 0.13), weed * 0.6);
	return bed;
}

// The net of light the moving surface throws on the floor: two sets of ripples
// crossing, bright where their crests meet. It reaches the bed only where the
// water is thin, which is what ties the light to the depth.
float water_caustics(vec2 g, float clear) {
	vec2 p = g * 2.3 + vec2(TIME * 0.17, TIME * 0.11);
	vec2 q = p + (noise(p * 0.8) - 0.5) * 2.4;
	float net = (1.0 - abs(sin(q.x * 3.3 + q.y * 1.1))) * (1.0 - abs(sin(q.y * 3.7 - q.x * 1.3)));
	return net * net * clear;
}

// The moving surface itself: a ripple field that both bends the floor seen
// through the water and carries the light. In grid units, so the whole pond
// ripples as one body of water instead of tile by tile.
vec2 water_ripple(vec2 g) {
	return vec2(noise(g * 5.0 + vec2(TIME * 0.85, TIME * 0.3)),
			noise(g * 5.0 + vec2(TIME * 0.25, -TIME * 0.7) + 31.0)) - 0.5;
}

// Pond water: a bed under a moving column that absorbs its light, with a wet
// margin where the water laps the bank. `edge` is the tile's own edge coverage,
// so the margin follows the material boundary exactly, and `base` is the
// theme's water colour, which keeps a tropical lagoon turquoise and a marshland
// pond murky while both still read as water over a bed.
vec3 water_surface(vec3 base, float edge, vec2 world, float patch) {
	vec2 g = world / tile_size;
	float depth = water_depth(g);
	float deep = 1.0 - exp(-depth * WATER_ABSORB);    // 0 in the shallows, 1 in the deep
	float clear = exp(-depth * WATER_DETAIL_ABSORB);  // sunlight still reaching the floor
	// The surface bends what lies under it, and most where the floor is near.
	vec2 bed_g = g + water_ripple(g) * 0.1 * clear;
	vec3 bed = water_bed(bed_g, clear, false);
	vec3 bed_lit = bed * (0.88 + noise(bed_g * 22.0) * 0.18)
		* (1.0 + water_caustics(bed_g, clear) * 1.6);
	// The column: pale and green over the shallows, dark blue over the deep.
	vec3 shallows_water = mix(base, vec3(0.44, 0.74, 0.68), 0.42) * (1.04 + (patch - 0.5) * 0.1);
	vec3 deep_water = base * vec3(0.4, 0.55, 0.72) * 0.72;
	vec3 column = mix(shallows_water, deep_water, deep);
	vec3 color = mix(bed_lit, column, deep);
	// The surface's own light: glints where a ripple catches the sun, and more
	// of them on the deep water, where there is no floor to look at instead.
	float wave = sin(world.y * 0.16 + sin(world.x * 0.024 + TIME * 0.3) * 2.3 + TIME * 0.8);
	float glint = smoothstep(0.93, 1.0, wave)
		* smoothstep(0.55, 0.8, noise(world * 0.04 + vec2(TIME * 0.07, 0.0)));
	color += vec3(0.30, 0.39, 0.33) * glint * (0.16 + deep * 0.22);
	// The waterline: the last of the floor, wet and darkened against the bank,
	// with the light the surface throws back along it.
	float bank = smoothstep(0.30, 1.0, edge);
	color = mix(color, bed_lit * 0.5 + column * 0.3, bank * 0.6);
	color += vec3(0.34, 0.4, 0.38) * smoothstep(0.80, 1.0, edge) * 0.16;
	return clamp(color, vec3(0.0), vec3(1.0));
}

// The rough turf a stream's banks keep either side of the channel, and the lip
// a pot bunker is cut into. Both tiles keep their own grass rather than melting
// into the terrain beside them, so they share one turf — painted side by side,
// or against the same fairway, they still show the same grass.
vec3 bank_turf(vec2 world, float grain, float patch) {
	float variation = (patch - 0.5) * 0.13 + (grain - 0.5) * 0.075;
	variation += (noise(world * vec2(0.32, 0.65)) - 0.5) * 0.045;
	vec3 base = palette_color(3.0);
	return clamp(base + vec3(variation * 0.78, variation, variation * 0.48), vec3(0.0), vec3(1.0));
}

// Inset terrain that paints its own turf instead of melting into the ground
// around it, and so takes no surround from the tiles beside it.
bool keeps_own_turf(float id) {
	return id == T_STREAM || id == T_POT_BUNKER;
}

vec3 surface(float id, float cover, vec2 world, float grain, float patch) {
	vec3 base = palette_color(id);
	float variation = (patch - 0.5) * 0.13 + (grain - 0.5) * 0.075;
	float edge = 1.0 - smoothstep(EDGE_LIP_LO, EDGE_LIP_HI, cover);
	if (id == 2.0 || id == 6.0) {
		// Broad diagonal mower passes continue across every tile boundary.
		float pass = sin((world.x + world.y * 1.7) * 0.078);
		float stripe = smoothstep(-0.15, 0.15, pass);
		base *= 0.97 + stripe * 0.035;
		variation *= 0.55;
		float cut_line = 1.0 - smoothstep(0.50, 0.53, cover);
		base *= 1.0 - edge * 0.14 - cut_line * 0.08;
	} else if (id == 5.0) {
		float stripe = smoothstep(-0.2, 0.2, sin((world.x - world.y * 1.5) * 0.10));
		base *= 0.98 + stripe * 0.035;
		base = mix(base, fringe_color.rgb, edge * 0.92);
		variation *= 0.18;
	} else if (id == 7.0) {
		// Recessed sand with a grass lip, warm bowl, and fine rake marks.
		base = mix(base * 1.12, vec3(0.35, 0.40, 0.24), edge * 0.78);
		float rake = sin(world.y * 1.15 + sin(world.x * 0.022) * 3.0);
		variation = (grain - 0.5) * 0.06 + rake * 0.012;
	} else if (id == 8.0) {
		// Water with depth in it: the bed shows through the shallows and the
		// pond darkens away from its bank. See water_surface().
		base = water_surface(base, edge, world, patch);
		variation = 0.0;
	} else if (id == 9.0) {
		variation = (grain - 0.5) * 0.045;
		base *= 1.0 - edge * 0.13;
	} else if (id == 3.0 || id == 4.0 || id == 1.0) {
		// Small irregular tufts, with larger color masses at landscape scale.
		variation += (noise(world * vec2(0.32, 0.65)) - 0.5) * 0.045;
	} else if (id == T_STREAM) {
		// A stream's banks keep their own rough turf; inset_tile() paints the
		// muddy margin and channel over it, and a pot bunker's lip is the same
		// grass.
		return bank_turf(world, grain, patch);
	} else if (id == T_FIRM_FAIRWAY) {
		// Fast links turf: the fairway's mower passes, paler, with sun-dried
		// straw patches.
		float pass = sin((world.x + world.y * 1.7) * 0.078);
		float stripe = smoothstep(-0.15, 0.15, pass);
		base *= 0.965 + stripe * 0.05;
		float dry = smoothstep(0.52, 0.8, noise(world * 0.03 + vec2(11.0, 4.0)));
		base = mix(base, base * vec3(1.08, 1.04, 0.86), dry * 0.5);
		variation *= 0.55;
		float cut_line = 1.0 - smoothstep(0.50, 0.53, cover);
		base *= 1.0 - edge * 0.12 - cut_line * 0.07;
	} else if (id == T_POT_BUNKER) {
		// The pot's sand floor; inset_tile() adds the wall and the lip.
		variation = (grain - 0.5) * 0.05;
	} else if (id == T_DEEP_ROUGH) {
		// Knee-high tussock grass: windswept upright blades, dark hollows and pale seed heads.
		vec2 g = world / tile_size;
		float sway = (noise(g * 3.4 + vec2(4.0, 9.0)) - 0.5) * 0.34;
		float u = g.x - g.y + sway;
		float v = g.x + g.y;
		float blades = noise(vec2(u * 26.0, v * 3.2 + noise(vec2(u * 3.0, v * 2.0)) * 1.6));
		float clump = noise(g * 3.2 + vec2(5.0, 1.0));
		base *= 0.76 + blades * 0.38 + (clump - 0.5) * 0.20;
		float heads = dots(g * 11.5 + vec2(3.1, 6.8), 0.28, 0.27);
		base = mix(base, base * vec3(1.52, 1.44, 0.96), heads * 0.62);
		variation *= 0.40;
	} else if (id == T_WASTE_BUNKER) {
		// Coarse unraked scrub sand across the full tile with gravel, grit and wiregrass tufts.
		vec2 g = world / tile_size;
		float drift = sin((g.x - g.y * 0.7) * 13.0 + noise(g * 2.6) * 3.5) * 0.035;
		base *= 0.92 + hash(floor(g * 40.0)) * 0.10 + (noise(g * 3.0) - 0.5) * 0.08 + drift;
		float pebbles = dots(g * 11.0, 0.42, 0.30);
		base = mix(base, base * vec3(0.58, 0.56, 0.54), pebbles * 0.80);
		base = mix(base, base * vec3(1.14, 1.12, 1.06), dots(g * 17.0, 0.32, 0.25) * 0.62);
		float tuft = dots(g * 4.5 + vec2(3.0, 8.0), 0.22, 0.40 + noise(g * 9.0) * 0.10);
		base = mix(base, palette_color(1.0) * (0.62 + noise(g * 26.0) * 0.30), tuft * 0.88);
		variation = (grain - 0.5) * 0.04;
	} else if (is_rocks(id)) {
		// Full-tile stony surfaces: angular scree, rounded cobbles or standing boulders.
		base = stony_surface(id, base, world / tile_size);
		variation = (grain - 0.5) * 0.035;
	} else if (id == T_BRUSH) {
		// Full-tile tangled scrub and gorse bushes with blossoms.
		base = brush_surface(base, world / tile_size);
		variation = (grain - 0.5) * 0.035;
	} else if (id == T_FLOWER_BED) {
		// Full-tile lush wildflower meadow beneath the seasonal FlowerOverlay blooms.
		base = flower_bed_surface(base, world / tile_size);
		variation = (grain - 0.5) * 0.035;
	} else if (is_tree(id)) {
		// Each woodland tile fills the full tile with its own species ground.
		base = tree_ground(id, base, world / tile_size, grain, patch);
		variation = (grain - 0.5) * 0.04;
	}
	if (is_bordered_tile(id)) {
		// Frame open edges with a tile-specific border of the exact same size as
		// the Bunker's lip instead of blending into neighbouring terrain types.
		base = mix(base, tile_border(id, world / tile_size, grain), edge * 0.88);
		variation = mix(variation, (grain - 0.5) * 0.035, edge);
	}
	return clamp(base + vec3(variation * 0.78, variation, variation * 0.48), vec3(0.0), vec3(1.0));
}

float is_wet(float id) {
	return (id == 8.0 || id == T_STREAM) ? 1.0 : 0.0;
}

// Distance from `q` (tile-local, 0..1) to the skeleton joining the tile
// center to each linked edge (e/s/w/n = 1 when linked). A corner with one
// horizontal and one vertical link is a quarter arc, so stepped lines of
// tiles read as smooth curves. `along_y` is 1 where the local run is
// north-south. An unlinked tile is a single round spot.
float link_distance(vec2 q, float e, float s, float w, float n, out float along_y) {
	float links = e + s + w + n;
	along_y = 0.0;
	if (links < 0.5) {
		return length(q - vec2(0.5));
	}
	if (links > 1.5 && links < 2.5 && e + w > 0.5 && e + w < 1.5) {
		vec2 corner = vec2(e, s);
		along_y = step(abs(q.y - corner.y), abs(q.x - corner.x));
		return abs(length(q - corner) - 0.5);
	}
	float run_x = 9.0;
	float run_y = 9.0;
	if (e > 0.5) { run_x = min(run_x, segment_distance(q, vec2(0.5), vec2(1.0, 0.5))); }
	if (w > 0.5) { run_x = min(run_x, segment_distance(q, vec2(0.5), vec2(0.0, 0.5))); }
	if (s > 0.5) { run_y = min(run_y, segment_distance(q, vec2(0.5), vec2(0.5, 1.0))); }
	if (n > 0.5) { run_y = min(run_y, segment_distance(q, vec2(0.5), vec2(0.5, 0.0))); }
	along_y = step(run_y, run_x);
	return smin(run_x, run_y, 0.12);
}

// 1 when the quadrant of the tile holding `q` belongs to a 2x2 block of linked
// tiles, which fills solid instead of showing a gap between the runs.
float corner_filled(vec2 q, vec2 cell, float e, float s, float w, float n, float self_id) {
	vec2 quadrant = step(vec2(0.5), q);
	float side_x = quadrant.x > 0.5 ? e : w;
	float side_y = quadrant.y > 0.5 ? s : n;
	if (side_x * side_y < 0.5) {
		return 0.0;
	}
	float diagonal = tile_at(cell + quadrant * 2.0 - 1.0);
	float linked = self_id == T_STREAM ? is_wet(diagonal) : step(abs(diagonal - self_id), 0.5);
	return linked;
}

// Terrain types the stream's grass draws its border against. Pond water keeps
// the bank and channel-mouth treatment it already has, and Rough — the bank's
// own turf colour — and Pot Bunker meet the bank with no border of any kind.
float stream_borders(float other) {
	return (other == 8.0 || other == 3.0 || other == T_POT_BUNKER) ? 0.0 : 1.0;
}

// The border itself, 1 on the rim and 0 on the bank's own turf. It is the same
// edge treatment the Bunker's grass lip uses — coverage fading across FRINGE,
// the rim showing where that coverage drops under the lip's own threshold — so
// a stream's border is exactly as wide as a bunker's. The coverage is built
// from each edge's boundary strength, so the rim dies away through the opening
// a channel mouth cuts in a Stream/Water border and never crosses an edge
// shared with another stream, and it stays inside the tile, so a lone stream
// tile still keeps its square footprint.
float stream_bank_border(vec2 q, vec4 open_edges, vec2 g) {
	float c_e = open_edges.x * smoothstep(-FRINGE, FRINGE, q.x - 1.0);
	float c_s = open_edges.y * smoothstep(-FRINGE, FRINGE, q.y - 1.0);
	float c_w = open_edges.z * smoothstep(-FRINGE, FRINGE, -q.x);
	float c_n = open_edges.w * smoothstep(-FRINGE, FRINGE, -q.y);
	float cover = (1.0 - c_e) * (1.0 - c_s) * (1.0 - c_w) * (1.0 - c_n);
	// A little irregularity along the rim, kept well below its width.
	float wobble = (noise(g * 11.0) - 0.5) * 0.03 + (noise(g * 29.0) - 0.5) * 0.012;
	return clamp(1.0 - smoothstep(EDGE_LIP_LO + wobble, EDGE_LIP_HI + wobble, cover), 0.0, 1.0);
}

// Features of inset terrain for the tile being drawn. `own` is the tile's
// interior ground, `outside` the turf around it (shown near `open_edges`, the
// edges shared with other materials, weighted by `edge_mix`); `q` is the
// position inside the tile and e/s/w/n the neighbouring terrain ids. A stream
// is the exception: it borders its open edges rather than blending into them,
// so it ignores `outside` and `edge_mix`.
vec3 inset_tile(float id, vec3 own, vec3 outside, float edge_mix, vec4 open_edges, vec2 q,
		vec2 cell, float e, float s, float w, float n, vec2 world, float grain, float patch) {
	vec2 g = world / tile_size;
	if (id == T_STREAM) {
		// Running water in a channel joining every neighbouring stream or pond.
		float ee = is_wet(e);
		float ss = is_wet(s);
		float ww = is_wet(w);
		float nn = is_wet(n);
		float along_y;
		float d = link_distance(q, ee, ss, ww, nn, along_y);  // first pass: also yields along_y
		// Where the stream meets a pond it opens into an estuary: the
		// channel widens toward the wet edge and the water deepens into
		// the still pond with a soft shoreline instead of a hard line.
		// The channel opening is applied after the squiggle re-measure
		// below so it survives.
		float pond = 0.0;
		float pond_edge = 9.0;
		if (e == 8.0) { pond_edge = min(pond_edge, 1.0 - q.x); pond = max(pond, smoothstep(0.30, 1.0, q.x)); }
		if (w == 8.0) { pond_edge = min(pond_edge, q.x); pond = max(pond, smoothstep(0.30, 1.0, 1.0 - q.x)); }
		if (s == 8.0) { pond_edge = min(pond_edge, 1.0 - q.y); pond = max(pond, smoothstep(0.30, 1.0, q.y)); }
		if (n == 8.0) { pond_edge = min(pond_edge, q.y); pond = max(pond, smoothstep(0.30, 1.0, 1.0 - q.y)); }

		// A thin main channel that snakes between tile edges instead of
		// running straight. Tiles stay as narrow channels even where
		// several stream tiles meet — they never fill into a pond just
		// because they form a square.
		float channel_along = mix(q.x, q.y, along_y);
		float channel_across = mix(q.y, q.x, along_y);
		float main_width = stream_main_width(g, channel_along, channel_across);

		// Squiggle the centerline: offset across the flow by a meander
		// that is strongest mid-run and fades toward tile center and edges
		// so neighbouring channels still join at the boundaries.
		float flow = channel_along;
		float t = abs(flow - 0.5) * 2.0;            // 0 at tile center, 1 at the edge
		float env = 4.0 * t * (1.0 - t);            // 0 at center & edge, peaks mid-run
		vec2 across_dir = vec2(along_y, 1.0 - along_y);  // perpendicular to flow
		float meander = (sin(channel_along * 14.0 + noise(g * 3.0) * 10.0)
			+ sin(channel_along * 7.0 + noise(g * 7.0 + 50.0) * 10.0)) * 0.09 * env;
		vec2 qm = q + across_dir * meander;
		// Re-measure the channel on the squiggled centerline.
		d = link_distance(qm, ee, ss, ww, nn, along_y);
		if (ee + ss + ww + nn < 0.5) { d += 0.06; }  // A lone tile is a small spring pool

		// Open the channel out to each pond edge so the stream mouth meets
		// the pond instead of stopping short of it. Only the channel's own
		// crossing point opens (via link_distance above) — the rest of the
		// shared edge stays dry, so no blue side strip appears.
		// Widen the channel toward a pond mouth (estuary): the water opens
		// up as it reaches the pond instead of pinching to a thin ribbon
		// at the bank.
		float mouth = smoothstep(0.55, 0.0, pond_edge);
		float estuary_width = main_width * (1.0 + mouth * 10.0);

		// Water mask for the main channel.
		float water_mask = 1.0 - smoothstep(estuary_width - 0.02, estuary_width + 0.02, d);
		float mud_mask = 1.0 - smoothstep(estuary_width + 0.02, estuary_width + 0.18, d);

		float half_width = estuary_width;
		// The riverbed under the channel. Across a stream the distance from the
		// centreline is the depth, so the gravel floor shows clear through the
		// shallow margins and is lost in the dark thread running down the
		// middle — the same bed the pond paints, coarsened to swept gravel.
		float clear = exp(-max(half_width - d, 0.0) * RIVER_ABSORB);
		float deep = 1.0 - clear;
		vec3 riverbed = water_bed(g, clear, true) * (0.85 + noise(g * 22.0) * 0.2)
			* (1.0 + water_caustics(g, clear) * 1.3);
		vec3 water = mix(riverbed,
			palette_color(T_STREAM) * (0.80 + deep * 0.26 + (patch - 0.5) * 0.06), deep);
		// Current: soft crests drifting downstream, broken up by moving noise.
		// The current fades where the stream spreads out into the still pond.
		float flow_speed = 1.0 - pond * 0.85;
		float along = mix(g.x, g.y, along_y);
		float across = mix(g.y, g.x, along_y);
		float crest = sin(along * 6.0 - TIME * 2.0 + noise(vec2(along * 1.4, across * 3.0)) * 4.0);
		float current = smoothstep(0.55, 1.0, crest)
			* smoothstep(0.4, 0.75, noise(vec2(along * 1.6 - TIME * 0.45, across * 4.0)));
		water += vec3(0.14, 0.2, 0.2) * current * deep * flow_speed * 0.6;
		float glint = smoothstep(0.93, 1.0, crest) * smoothstep(0.65, 0.85, noise(g * 3.0 + vec2(TIME * 0.2, 0.0)));
		water += vec3(0.3, 0.35, 0.3) * glint * 0.35 * flow_speed;
		// Confluence: where the moving stream meets the still pond, add
		// subtle turbulence and soften into deep pond water.
		float confluence = pond * (1.0 - deep) * 0.5;
		water += vec3(0.12, 0.16, 0.18) * noise(g * 8.0 + vec2(TIME * 0.15, 0.0)) * confluence;
		water = mix(water, surface(8.0, 1.0, world, grain, patch), pond * 0.95);

		// The bank keeps its own rough turf and is edged with a narrow, dark
		// "cut bank" rim wherever the tile meets terrain it borders, instead of
		// fading into it; Water, Rough and Pot Bunker meet it with no border.
		// The rim is laid under the mud and the water, so the channel and its
		// margin stay clean, and it thins out toward a pond's channel mouth,
		// where the boundary it follows is cut open.
		vec4 bordered = vec4(stream_borders(e), stream_borders(s),
			stream_borders(w), stream_borders(n));
		float border = stream_bank_border(q, open_edges * bordered, g);
		vec3 rim = mix(own * 0.55, vec3(0.26, 0.23, 0.17), 0.4);
		rim *= 0.9 + noise(g * 19.0) * 0.2;
		vec3 bank = mix(own, rim, border);
		vec3 mud = mix(palette_color(1.0) * 0.5, vec3(0.36, 0.31, 0.24), 0.6);
		mud = mix(mud, vec3(0.64, 0.62, 0.57), dots(g * 21.0, 0.3, 0.3) * 0.7);
		// Damp sediment hugging the water's edge, where the channel has cut in:
		// the bed the stream leaves bare as it moves across its floor.
		float damp = (1.0 - smoothstep(estuary_width + 0.02, estuary_width + 0.10, d)) * mud_mask;
		mud = mix(mud, mud * vec3(0.60, 0.58, 0.54), damp * 0.85);
		return mix(mix(bank, mud, mud_mask), clamp(water, vec3(0.0), vec3(1.0)), water_mask);
	} else if (id == T_POT_BUNKER) {
		// A small round pit: the turf lip, a stacked-turf wall whose far face
		// shows above the floor, and a shaded sand floor. The lip is cut into
		// the same rough turf a stream's banks keep, so a pot bunker laid in
		// Rough — or beside a stream — does not sit in a square of another
		// grass.
		float ee = step(abs(e - id), 0.5);
		float ss = step(abs(s - id), 0.5);
		float ww = step(abs(w - id), 0.5);
		float nn = step(abs(n - id), 0.5);
		float along_y;
		float fill = corner_filled(q, cell, ee, ss, ww, nn, id);
		float rim = fill > 0.5 ? -1.0 : link_distance(q, ee, ss, ww, nn, along_y);
		// The floor sits nearer the viewer (screen down = grid +x +y), which
		// exposes the far wall's face.
		vec2 fq = q - vec2(0.07);
		float floor_d = fill > 0.5 ? -1.0 : link_distance(fq, ee, ss, ww, nn, along_y);
		float wobble = (noise(g * 5.0) - 0.5) * 0.04;
		float in_rim = 1.0 - smoothstep(0.38 + wobble, 0.41 + wobble, rim);
		float on_floor = 1.0 - smoothstep(0.27 + wobble, 0.30 + wobble, floor_d);
		float courses = smoothstep(0.2, 0.8, abs(fract((g.x + g.y) * 7.0 + noise(g * 8.0) * 0.4) - 0.5) * 2.0);
		vec3 face = mix(vec3(0.30, 0.25, 0.16), palette_color(3.0) * 0.72, courses * 0.8);
		face *= 0.8 + 0.2 * noise(g * 20.0);
		float floor_light = smoothstep(0.0, 0.22, 0.27 - floor_d);
		float wall_shadow = smoothstep(0.1, 0.34, link_distance(q + GROUND_LIGHT * 0.12, ee, ss, ww, nn, along_y)) * (1.0 - fill);
		vec3 sand = own * (0.7 + floor_light * 0.3) * (1.0 - wall_shadow * 0.18);
		vec3 lip = bank_turf(world, grain, patch) * (1.0 - (1.0 - smoothstep(0.41, 0.48, rim)) * 0.22);  // a shadowed rim edge
		return mix(lip, mix(face, sand, on_floor), in_rim);
	}
	return own;
}

// A neighbouring tile's material inside the boundary band around tile
// `self_id`. Inset terrain (a stream channel or pot bunker) keeps its own rough
// turf bank right up to the boundary.
vec3 neighbour_surface(float tile, float cover, float self_id, vec2 world, float grain, float patch) {
	if (is_inset(tile) && !carries(tile, self_id)) {
		if (keeps_own_turf(tile)) {
			return bank_turf(world, grain, patch);
		}
		return surface(1.0, 1.0, world, grain, patch);
	}
	return surface(tile, cover, world, grain, patch);
}

void fragment() {
	vec2 world = surface_origin + UV * surface_size;
	bool surface_hit;
	vec2 p = surface_grid_at_world(world, surface_hit);
	if (!surface_hit || p.x < 0.0 || p.y < 0.0 || p.x > grid_size.x || p.y > grid_size.y) {
		COLOR = vec4(0.0);
	} else {
		vec2 tile_world = p * tile_size;
		// A restrained contour perturbation breaks stair steps without moving tile centers.
		vec2 warp = vec2(noise(p * 0.72), noise(p * 0.72 + 37.0)) - 0.5;
		vec2 sample_pos = p + warp * 0.08;
		vec2 cell = floor(sample_pos);
		vec2 f = fract(sample_pos);
		float a = tile_at(cell);
		float t_e = tile_at(cell + vec2(1.0, 0.0));
		float t_s = tile_at(cell + vec2(0.0, 1.0));
		float t_w = tile_at(cell + vec2(-1.0, 0.0));
		float t_n = tile_at(cell + vec2(0.0, -1.0));

		// Material boundaries sit on the shared tile edges inside a narrow
		// anti-aliased band. The old bilinear coverage field made the boundary
		// of an isolated tile bulge outward into a rounded blob; edge-aligned
		// bands keep every tile's full square footprint.
		float d_e = f.x - 1.0;
		float d_w = -f.x;
		float d_s = f.y - 1.0;
		float d_n = -f.y;
		// A Stream/Water edge is banked away from the stream mouth, but open
		// through it. E/S are q=1 and W/N q=0 on the Stream tile; if the
		// Stream is the neighbour, `stream_end_*` uses the opposite endpoint.
		float stream_end_e = a == T_STREAM ? 1.0 : 0.0;
		float stream_end_s = a == T_STREAM ? 1.0 : 0.0;
		float stream_end_w = a == T_STREAM ? 0.0 : 1.0;
		float stream_end_n = a == T_STREAM ? 0.0 : 1.0;
		float boundary_e = edge_between_at(a, t_e, f.y, stream_end_e, tile_world);
		float boundary_s = edge_between_at(a, t_s, f.x, stream_end_s, tile_world);
		float boundary_w = edge_between_at(a, t_w, f.y, stream_end_w, tile_world);
		float boundary_n = edge_between_at(a, t_n, f.x, stream_end_n, tile_world);
		vec4 open_edges = vec4(boundary_e, boundary_s, boundary_w, boundary_n);
		float m_e = open_edges.x * smoothstep(-AA, AA, d_e);
		float m_w = open_edges.z * smoothstep(-AA, AA, d_w);
		float m_s = open_edges.y * smoothstep(-AA, AA, d_s);
		float m_n = open_edges.w * smoothstep(-AA, AA, d_n);

		float w_c = (1.0 - m_e) * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_n);
		float w_e = m_e * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_n);
		float w_s = m_s * (1.0 - m_w) * (1.0 - m_e) * (1.0 - m_n);
		float w_w = m_w * (1.0 - m_e) * (1.0 - m_s) * (1.0 - m_n);
		float w_n = m_n * (1.0 - m_w) * (1.0 - m_s) * (1.0 - m_e);

		// Coverage for edge treatments (fringe, lip, shoreline): 1 well inside
		// the tile, fading across the boundary band. Square, like the boundary.
		float c_e = open_edges.x * smoothstep(-FRINGE, FRINGE, d_e);
		float c_w = open_edges.z * smoothstep(-FRINGE, FRINGE, d_w);
		float c_s = open_edges.y * smoothstep(-FRINGE, FRINGE, d_s);
		float c_n = open_edges.w * smoothstep(-FRINGE, FRINGE, d_n);
		float cov_c = (1.0 - c_e) * (1.0 - c_w) * (1.0 - c_s) * (1.0 - c_n);
		// A neighbour's own edge treatment, as that tile sees this one.
		float cov_e = 1.0 - edge_between_at(t_e, a, f.y, stream_end_e, tile_world)
			* (1.0 - smoothstep(-FRINGE, FRINGE, d_e));
		float cov_s = 1.0 - edge_between_at(t_s, a, f.x, stream_end_s, tile_world)
			* (1.0 - smoothstep(-FRINGE, FRINGE, d_s));
		float cov_w = 1.0 - edge_between_at(t_w, a, f.y, stream_end_w, tile_world)
			* (1.0 - smoothstep(-FRINGE, FRINGE, d_w));
		float cov_n = 1.0 - edge_between_at(t_n, a, f.x, stream_end_n, tile_world)
			* (1.0 - smoothstep(-FRINGE, FRINGE, d_n));

		float grain = hash(floor(tile_world));
		float patch = noise(tile_world * 0.009) * 0.65 + noise(tile_world * 0.035) * 0.35;
		float w_sum = w_c + w_e + w_s + w_w + w_n;
		// Neighbour materials only contribute inside their boundary band, so
		// skip them elsewhere: most pixels evaluate a single surface.
		vec3 color = vec3(0.0);
		if (w_c > 0.0) {
			vec3 own = surface(a, cov_c, tile_world, grain, patch);
			if (is_inset(a)) {
				// A stream's bank and a pot bunker's lip paint their own turf
				// rather than blending into the ground around them, so neither
				// needs the surrounding turf sampled.
				vec3 outside = own;
				float edge_mix = 0.0;
				if (!keeps_own_turf(a)) {
					vec3 native = surface(1.0, 1.0, tile_world, grain, patch);
					// The turf around the patch, blended toward each open edge.
					float e_e = open_edges.x * smoothstep(-0.5, 0.0, d_e);
					float e_s = open_edges.y * smoothstep(-0.5, 0.0, d_s);
					float e_w = open_edges.z * smoothstep(-0.5, 0.0, d_w);
					float e_n = open_edges.w * smoothstep(-0.5, 0.0, d_n);
					vec3 around = vec3(0.0);
					if (e_e > 0.0) { around += (carries(t_e, a) ? surface(t_e, 1.0, tile_world, grain, patch) : native) * e_e; }
					if (e_s > 0.0) { around += (carries(t_s, a) ? surface(t_s, 1.0, tile_world, grain, patch) : native) * e_s; }
					if (e_w > 0.0) { around += (carries(t_w, a) ? surface(t_w, 1.0, tile_world, grain, patch) : native) * e_w; }
					if (e_n > 0.0) { around += (carries(t_n, a) ? surface(t_n, 1.0, tile_world, grain, patch) : native) * e_n; }
					float around_w = e_e + e_s + e_w + e_n;
					outside = around_w > 0.0 ? around / around_w : native;
					edge_mix = clamp(max(max(e_e, e_s), max(e_w, e_n)), 0.0, 1.0);
				}
				own = inset_tile(a, own, outside, edge_mix, open_edges, f, cell,
					t_e, t_s, t_w, t_n, tile_world, grain, patch);
			}
			color += own * w_c;
		}
		if (w_e > 0.0) { color += neighbour_surface(t_e, cov_e, a, tile_world, grain, patch) * w_e; }
		if (w_s > 0.0) { color += neighbour_surface(t_s, cov_s, a, tile_world, grain, patch) * w_s; }
		if (w_w > 0.0) { color += neighbour_surface(t_w, cov_w, a, tile_world, grain, patch) * w_w; }
		if (w_n > 0.0) { color += neighbour_surface(t_n, cov_n, a, tile_world, grain, patch) * w_n; }
		color /= max(w_sum, 0.0001);
		// Elevation slopes & 3D relief normal
		float left_h = elevation_at_grid(p - vec2(0.6, 0.0));
		float right_h = elevation_at_grid(p + vec2(0.6, 0.0));
		float up_h = elevation_at_grid(p - vec2(0.0, 0.6));
		float down_h = elevation_at_grid(p + vec2(0.0, 0.6));
		float dh_x = (right_h - left_h) * (elevation_step_y * 0.8);
		float dh_y = (down_h - up_h) * (elevation_step_y * 0.8);
		float det = grid_axis_x.x * grid_axis_y.y - grid_axis_y.x * grid_axis_x.y;
		vec3 normal = vec3(
			(grid_axis_x.y * dh_y - grid_axis_y.y * dh_x) / det,
			(grid_axis_y.x * dh_x - grid_axis_x.x * dh_y) / det,
			1.0
		);
		normal = normalize(normal);
		vec3 sunlight = normalize(vec3(relief_light, 1.3));
		float ndotl = dot(normal, sunlight);
		float relief = clamp(1.0 + (dot(normal, sunlight) - sunlight.z) * 0.28, 0.84, 1.08);

		COLOR = vec4(color * relief, 1.0);
	}
}
