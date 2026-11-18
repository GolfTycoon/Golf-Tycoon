shader_type canvas_item;

// Ground detail painted onto the course (the walking trail). The overlay draws
// over the surface in its own band, so without this a hill in front of a trail
// would be painted over by it. UV is not a texture coordinate here: every vertex
// carries the grid point of the ground it is painted on (WalkingPathOverlay), so
// each pixel knows where on the course it lies, and a nearer hill hides it with
// the same heightfield intersection the surface itself is drawn with.
uniform sampler2D vertex_elevation : filter_linear, repeat_disable;
uniform vec2 vertex_grid_size = vec2(129.0);
uniform vec2 grid_size = vec2(128.0);
uniform float elevation_step_y = 10.0;
uniform float elevation_texture_zero = 128.0;
uniform float elevation_texture_scale = 25.0;
uniform bool is_isometric = true;
uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_axis_x = vec2(64.0, 32.0);
uniform vec2 grid_axis_y = vec2(0.0, 32.0);
// Screen pixels of slack: a flat triangle of the trail only approximates the
// curved (bilinear) ground it is laid on, and must never be hidden by it.
uniform float occlusion_epsilon = 1.5;

#include "res://shaders/terrain_heightfield.gdshaderinc"

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Only whether the pixel is drawn is decided here: the paint keeps the
	// colour it was drawn with.
	vec2 ground = UV;
	// The painted point's ray parameter (the height it is drawn at), and the
	// ground's under it. A grass blade standing on the trail is above its ground,
	// like a sprite; paint on the ground is at the ground's own height.
	vec2 ground_flat = grid_origin + ground.x * grid_axis_x + ground.y * grid_axis_y;
	float painted_t = ground_flat.y - world_position.y;
	float decal_t = max(painted_t, elevation_at_grid(ground) * elevation_step_y);
	if (terrain_hides(world_position, decal_t + occlusion_epsilon)) {
		discard;
	}
}
