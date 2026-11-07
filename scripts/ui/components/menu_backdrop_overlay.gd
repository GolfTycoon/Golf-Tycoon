extends RefCounted
class_name MenuBackdropOverlay
## MenuBackdropOverlay - the patterns an overlay catalogue entry can name.
##
## A background overlay is a texture-free painter: MenuBackdrop asks for one by
## name and this class draws it with `draw_*` calls into the backdrop's own
## CanvasItem, so an overlay never allocates an image and never needs importing.
## That is what lets a mod ship a new overlay as a few numbers in a JSON file.
##
## Every painter takes the same arguments - the rectangle to fill, the ink
## colour (already carrying the entry's strength), the feature size in logical
## pixels and the entry's own `settings` values - so the catalogue stays data.
##
## The shipped patterns:
##   none      - draws nothing; the plain picture
##   wash      - one flat tint over the whole rectangle
##   vignette  - a soft darkening toward the corners
##   glow      - a soft glow rising from the bottom edge
##   split     - one half shaded, divided at `angle`
##   stripes   - mown-fairway bands
##   grid      - a square lattice
##   scanlines - thin horizontal lines
##   dots      - a coarse halftone dot screen
##   sparkle   - scattered deterministic glints
##   edges     - dark bands along the top and bottom edge
##   aurora    - layered, luminous ribbons flowing across the picture
##   sunburst  - fine championship rays fading out from a golden sun
##   contours  - an elegant topographic survey of an imaginary course
##   deco      - gilded 1920s corner fans and a fine architectural frame
##   argyle    - a tailored golf-club diamond knit
##   bokeh     - soft, out-of-focus clubhouse lights

## Patterns a catalogue entry may name. Anything else draws nothing (and the
## registry says so), so a mod that misses the list still fails softly.
const PATTERNS: Array[String] = [
	"none", "wash", "vignette", "glow", "split",
	"stripes", "grid", "scanlines", "dots", "sparkle", "edges",
	"aurora", "sunburst", "contours", "deco", "argyle", "bokeh",
]

## Steps used to build the soft falloffs (vignette, glow): enough to read as a
## gradient, few enough that a phone repaints them cheaply.
const FALLOFF_STEPS := 14
## A sparkle glint is a tiny diamond; this is its base half-extent in pixels.
const SPARKLE_SIZE := 2.0
## The fixed seed the sparkle scatter is drawn from, so the pattern is stable
## between repaints instead of shimmering.
const SPARKLE_SEED := 6017
## Bokeh gets its own fixed scatter, so changing the dew setting never moves
## the clubhouse lights (and a repaint never makes them swim).
const BOKEH_SEED := 9241
## Curved designs use enough samples to stay smooth on a large display without
## making a menu rebuild expensive on a phone.
const CURVE_STEPS := 64


## The default feature size for a pattern, in logical pixels, used when an
## entry names no scale of its own.
static func default_scale(pattern: String) -> float:
	match pattern:
		"stripes": return 54.0
		"grid": return 34.0
		"scanlines": return 3.0
		"dots": return 7.0
		"aurora": return 72.0
		"sunburst": return 64.0
		"contours": return 34.0
		"deco": return 64.0
		"argyle": return 92.0
		"bokeh": return 42.0
	return 1.0


static func is_pattern(pattern: String) -> bool:
	return pattern in PATTERNS


## Draw `pattern` over `rect`. `ink` carries the opacity; `settings` is the
## entry's own settings dictionary (see data/menu_overlays.json).
static func draw(canvas: CanvasItem, pattern: String, rect: Rect2, ink: Color,
		scale: float, settings: Dictionary) -> void:
	if canvas == null or ink.a <= 0.0 or rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var feature := maxf(scale, 0.5)
	match pattern:
		"wash":
			canvas.draw_rect(rect, ink)
		"vignette":
			_draw_vignette(canvas, rect, ink)
		"glow":
			_draw_glow(canvas, rect, ink)
		"split":
			_draw_split(canvas, rect, ink, int(settings.get("angle", 0)))
		"stripes":
			_draw_stripes(canvas, rect, ink, feature, int(settings.get("angle", 0)))
		"grid":
			_draw_grid(canvas, rect, ink, feature, int(settings.get("angle", 0)))
		"scanlines":
			_draw_scanlines(canvas, rect, ink, feature)
		"dots":
			_draw_dots(canvas, rect, ink, feature)
		"sparkle":
			_draw_sparkle(canvas, rect, ink, int(settings.get("density", 1)))
		"edges":
			_draw_edges(canvas, rect, ink)
		"aurora":
			_draw_aurora(canvas, rect, ink, feature,
				int(settings.get("angle", 0)), int(settings.get("density", 1)))
		"sunburst":
			_draw_sunburst(canvas, rect, ink, feature,
				int(settings.get("angle", 0)), int(settings.get("density", 1)))
		"contours":
			_draw_contours(canvas, rect, ink, feature,
				int(settings.get("angle", 0)), int(settings.get("density", 1)))
		"deco":
			_draw_deco(canvas, rect, ink, feature)
		"argyle":
			_draw_argyle(canvas, rect, ink, feature, int(settings.get("angle", 0)))
		"bokeh":
			_draw_bokeh(canvas, rect, ink, feature, int(settings.get("density", 1)))


# ---------------------------------------------------------------------------
# Painters
# ---------------------------------------------------------------------------

## Dark corners, clear middle: a handful of concentric frames, each a step
## lighter than the last, so the falloff reads as a gradient while the edges
## stay hard (the look the rest of the game's pixel art uses).
static func _draw_vignette(canvas: CanvasItem, rect: Rect2, ink: Color) -> void:
	var inset := minf(rect.size.x, rect.size.y) * 0.5 / float(FALLOFF_STEPS)
	for step in range(FALLOFF_STEPS):
		var t := 1.0 - float(step) / float(FALLOFF_STEPS)
		var grow := inset * float(step)
		canvas.draw_rect(
			Rect2(rect.position.x - grow, rect.position.y - grow,
				rect.size.x + grow * 2.0, rect.size.y + grow * 2.0),
			Color(ink.r, ink.g, ink.b, ink.a * t * t / float(FALLOFF_STEPS) * 3.0))


## A band of light lifting off the bottom edge, so a button row has something
## to sit against wherever the picture is brightest.
static func _draw_glow(canvas: CanvasItem, rect: Rect2, ink: Color) -> void:
	var height := rect.size.y * 0.45
	var slice_h := height / float(FALLOFF_STEPS)
	for step in range(FALLOFF_STEPS):
		var t := float(step + 1) / float(FALLOFF_STEPS)
		canvas.draw_rect(
			Rect2(rect.position.x, rect.end.y - slice_h * float(step + 1),
				rect.size.x, slice_h + 1.0),
			Color(ink.r, ink.g, ink.b, ink.a * t * t))


## Dark bands along the top and bottom edge: the same stacked slices the
## backdrop always drew, so the heading and the version line have something to
## sit on wherever the picture is bright. Shipped as an overlay rather than
## baked into every picture, so a player who prefers the bare art can pick
## None and see it.
static func _draw_edges(canvas: CanvasItem, rect: Rect2, ink: Color) -> void:
	for band in edge_bands(rect, ink.a):
		var opacity: float = float(band["alpha"])
		canvas.draw_rect(band["rect"] as Rect2, Color(ink.r, ink.g, ink.b, opacity))


## The slices `edges` draws: 14 across the top, 14 across the bottom, the top
## and bottom pairs mirrored, each one weaker than the one nearer the edge.
## Returned rather than drawn straight away so the shape can be checked without
## a rendering context (`draw_*` is not virtual, so it cannot be stubbed).
static func edge_bands(rect: Rect2, strength: float) -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	var band_h := rect.size.y * 0.12 / float(FALLOFF_STEPS)
	for step in range(FALLOFF_STEPS):
		var t := 1.0 - float(step) / float(FALLOFF_STEPS)
		var alpha := strength * t * t
		bands.append({
			"rect": Rect2(rect.position.x, rect.position.y + band_h * float(step),
				rect.size.x, band_h + 1.0),
			"alpha": alpha,
		})
		bands.append({
			"rect": Rect2(rect.position.x, rect.end.y - band_h * float(step + 1),
				rect.size.x, band_h + 1.0),
			"alpha": alpha,
		})
	return bands


## One half of the picture in shade, split on a line at `angle` degrees.
static func _draw_split(canvas: CanvasItem, rect: Rect2, ink: Color, angle: int) -> void:
	var normal := Vector2.UP.rotated(deg_to_rad(float(angle)))
	var centre := rect.get_center()
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var shaded := _clip_half_plane(corners, centre, normal)
	if shaded.size() >= 3:
		canvas.draw_colored_polygon(PackedVector2Array(shaded), ink)


## The part of `polygon` on the positive side of the line through `origin`
## with normal `normal` (Sutherland-Hodgman against one half-plane).
static func _clip_half_plane(polygon: Array[Vector2], origin: Vector2,
		normal: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var count := polygon.size()
	for i in range(count):
		var current: Vector2 = polygon[i]
		var next: Vector2 = polygon[(i + 1) % count]
		var current_inside := (current - origin).dot(normal) >= 0.0
		var next_inside := (next - origin).dot(normal) >= 0.0
		if current_inside:
			result.append(current)
		if current_inside != next_inside:
			var denominator: float = (next - current).dot(normal)
			if not is_zero_approx(denominator):
				var t: float = (origin - current).dot(normal) / denominator
				result.append(current.lerp(next, clampf(t, 0.0, 1.0)))
	return result


## Mown fairway bands: alternating translucent stripes running at `angle`.
static func _draw_stripes(canvas: CanvasItem, rect: Rect2, ink: Color, width: float,
		angle: int) -> void:
	var band := maxf(width, 4.0)
	var centre := rect.get_center()
	var direction := Vector2.RIGHT.rotated(deg_to_rad(float(angle)))
	var normal := Vector2(-direction.y, direction.x)
	var reach := rect.size.length() * 0.5 + band
	var along := direction * reach
	var offset := -reach
	var index := 0
	while offset < reach:
		if index % 2 == 0:
			var near := centre + normal * offset
			var far := centre + normal * (offset + band)
			canvas.draw_colored_polygon(
				PackedVector2Array([near - along, near + along, far + along, far - along]), ink)
		offset += band
		index += 1


## A square lattice at `angle` - lines both along and across the given
## direction, so the result is a true grid however it is turned.
static func _draw_grid(canvas: CanvasItem, rect: Rect2, ink: Color, spacing: float,
		angle: int) -> void:
	var step := maxf(spacing, 6.0)
	var thickness := maxf(1.0, step * 0.06)
	var centre := rect.get_center()
	var direction := Vector2.RIGHT.rotated(deg_to_rad(float(angle)))
	var normal := Vector2(-direction.y, direction.x)
	var reach := rect.size.length() * 0.5 + step
	var offset := -reach
	while offset < reach:
		# A line across the stripes...
		var across_start := centre + normal * offset - direction * reach
		var across_end := centre + normal * offset + direction * reach
		_draw_thick_line(canvas, across_start, across_end, normal * thickness, ink)
		# ...and one along them, which closes the lattice into squares.
		var along_start := centre + direction * offset - normal * reach
		var along_end := centre + direction * offset + normal * reach
		_draw_thick_line(canvas, along_start, along_end, direction * thickness, ink)
		offset += step


static func _draw_thick_line(canvas: CanvasItem, from: Vector2, to: Vector2,
		shift: Vector2, ink: Color) -> void:
	canvas.draw_colored_polygon(
		PackedVector2Array([from, to, to + shift, from + shift]), ink)


## Thin horizontal lines, evenly spaced.
static func _draw_scanlines(canvas: CanvasItem, rect: Rect2, ink: Color, spacing: float) -> void:
	var step := maxf(spacing, 2.0)
	var thickness := maxf(1.0, floorf(step * 0.5))
	var y := rect.position.y
	while y < rect.end.y:
		canvas.draw_rect(Rect2(rect.position.x, y, rect.size.x, thickness), ink)
		y += step


## A coarse halftone: one square per cell, every other row offset by half a
## cell so the screen reads as printed rather than as a plain grid.
static func _draw_dots(canvas: CanvasItem, rect: Rect2, ink: Color, spacing: float) -> void:
	var step := maxf(spacing, 3.0)
	var dot := maxf(1.0, floorf(step * 0.42))
	var y := rect.position.y
	var row := 0
	while y < rect.end.y:
		var x := rect.position.x + (step * 0.5 if row % 2 == 1 else 0.0)
		while x < rect.end.x:
			canvas.draw_rect(Rect2(x, y, dot, dot), ink)
			x += step
		y += step
		row += 1


## Deterministic glints: a fixed pseudo-random scatter, so the backdrop looks
## the same every time it is painted.
static func _draw_sparkle(canvas: CanvasItem, rect: Rect2, ink: Color, density: int) -> void:
	var count: int = [18, 42, 90][clampi(density, 0, 2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = SPARKLE_SEED
	for i in range(count):
		var point := Vector2(
			rect.position.x + rng.randf() * rect.size.x,
			rect.position.y + rng.randf() * rect.size.y)
		var size := SPARKLE_SIZE * (0.6 + rng.randf() * 1.2)
		canvas.draw_colored_polygon(PackedVector2Array([
			point + Vector2(0.0, -size),
			point + Vector2(size * 0.55, 0.0),
			point + Vector2(0.0, size),
			point + Vector2(-size * 0.55, 0.0),
		]), ink)


# ---------------------------------------------------------------------------
# Signature designs
# ---------------------------------------------------------------------------

## Luminous ribbons, built as three nested translucent bands rather than a
## bitmap glow. Each band has a bright crest and a softer trailing edge; their
## different phases keep the result flowing instead of looking like sine-wave
## wallpaper. The fixed sparkle scatter reads as stars between the ribbons.
static func _draw_aurora(canvas: CanvasItem, rect: Rect2, ink: Color, scale: float,
		angle: int, density: int) -> void:
	var count: int = [3, 4, 6][clampi(density, 0, 2)]
	var centre := rect.get_center()
	var rotation := deg_to_rad(float(angle))
	var direction := Vector2.RIGHT.rotated(rotation)
	var normal := Vector2(-direction.y, direction.x)
	var reach := rect.size.length() * 0.72
	var unit := maxf(scale, 24.0)
	var amplitude := minf(rect.size.y * 0.12, unit * 1.25)
	var ribbon_width := maxf(rect.size.y * 0.035, unit * 0.62)
	var crest_ink := ink.lightened(0.38)
	crest_ink.a = ink.a

	for layer in range(count):
		var lane := (float(layer) / float(maxi(count - 1, 1)) - 0.5) * rect.size.y * 0.82
		var upper := PackedVector2Array()
		var lower := PackedVector2Array()
		var crest := PackedVector2Array()
		for sample in range(CURVE_STEPS + 1):
			var t := float(sample) / float(CURVE_STEPS)
			var along := lerpf(-reach, reach, t)
			var wave := sin(t * TAU * 1.18 + float(layer) * 0.72) * amplitude
			wave += sin(t * TAU * 2.65 - float(layer) * 0.43) * amplitude * 0.24
			var drift := lane + wave - rect.size.y * 0.12
			var middle := centre + direction * along + normal * drift
			var breadth := ribbon_width * (0.62 + sin(t * PI) * 0.38)
			var top := middle - normal * breadth * 0.5
			upper.append(top)
			lower.append(middle + normal * breadth * 0.5)
			crest.append(top + normal * breadth * 0.18)

		var weight := 0.72 + float(layer % 3) * 0.12
		canvas.draw_colored_polygon(_ribbon_band(upper, lower, 0.0, 1.0),
			_alpha(ink, 0.12 * weight))
		canvas.draw_colored_polygon(_ribbon_band(upper, lower, 0.16, 0.84),
			_alpha(ink, 0.10 * weight))
		canvas.draw_colored_polygon(_ribbon_band(upper, lower, 0.34, 0.62),
			_alpha(crest_ink, 0.13 * weight))
		canvas.draw_polyline(crest, _alpha(crest_ink, 0.48 * weight), 1.15, true)
		canvas.draw_polyline(lower, _alpha(ink, 0.12 * weight), 1.0, true)

	_draw_sparkle(canvas, rect, _alpha(crest_ink, 0.32), 0)


## The filled band between two matching paths. `from` and `to` are fractions
## across the ribbon, which lets the aurora paint a soft core without a shader.
static func _ribbon_band(upper: PackedVector2Array, lower: PackedVector2Array,
		from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(upper.size()):
		points.append(upper[index].lerp(lower[index], from))
	for index in range(lower.size() - 1, -1, -1):
		points.append(upper[index].lerp(lower[index], to))
	return points


## Alternating shafts of warm light. Every shaft is sliced along its radius so
## it can fade into the picture; a solid wedge would look like a flat cartoon
## sun and fight the menu cards. The small bloom is likewise concentric washes.
static func _draw_sunburst(canvas: CanvasItem, rect: Rect2, ink: Color, scale: float,
		angle: int, density: int) -> void:
	var ray_count: int = [12, 18, 26][clampi(density, 0, 2)]
	var origin := rect.position + Vector2(rect.size.x * 0.22, rect.size.y * 0.16)
	var rotation := deg_to_rad(float(angle))
	var reach := rect.size.length() * 1.35
	var bands := 9
	for ray in range(0, ray_count, 2):
		var a0 := rotation + TAU * float(ray) / float(ray_count)
		var a1 := rotation + TAU * float(ray + 1) / float(ray_count)
		var u := Vector2.from_angle(a0)
		var v := Vector2.from_angle(a1)
		for band in range(bands):
			var near := reach * float(band) / float(bands)
			var far := reach * float(band + 1) / float(bands) + 1.0
			var fade := pow(1.0 - float(band) / float(bands), 1.55)
			var points := PackedVector2Array()
			if band == 0:
				points = PackedVector2Array([origin, origin + u * far, origin + v * far])
			else:
				points = PackedVector2Array([
					origin + u * near, origin + u * far,
					origin + v * far, origin + v * near,
				])
			canvas.draw_colored_polygon(points, _alpha(ink, 0.20 * fade))

	var glow_radius := maxf(maxf(scale, 16.0) * 2.4, minf(rect.size.x, rect.size.y) * 0.22)
	var glow_ink := ink.lightened(0.28)
	glow_ink.a = ink.a
	for step in range(10):
		var fraction := 1.0 - float(step) / 10.0
		canvas.draw_circle(origin, glow_radius * fraction,
			_alpha(glow_ink, 0.018 + float(step) * 0.002))
	canvas.draw_circle(origin, maxf(scale, 16.0) * 0.15, _alpha(glow_ink, 0.34))


## A topographic survey drawn as nested, closed contours. All rings share the
## same three harmonics, so they stay nested instead of crossing each other.
## Every fourth contour is a stronger index line, just like a real course map.
static func _draw_contours(canvas: CanvasItem, rect: Rect2, ink: Color, scale: float,
		angle: int, density: int) -> void:
	var count: int = [11, 17, 24][clampi(density, 0, 2)]
	var spacing := maxf(scale, 12.0)
	var centre := rect.position + Vector2(rect.size.x * 0.68, rect.size.y * 0.46)
	var rotation := deg_to_rad(float(angle))
	for ring in range(count):
		var radius := spacing * (float(ring) + 1.0) * 0.82
		var points := PackedVector2Array()
		for sample in range(CURVE_STEPS + 1):
			var theta := TAU * float(sample) / float(CURVE_STEPS)
			var warp := 1.0 + sin(theta * 3.0 + 0.7) * 0.12
			warp += cos(theta * 5.0 - 1.4) * 0.055
			warp += sin(theta * 8.0 + 0.2) * 0.025
			var local := Vector2(cos(theta) * radius * 1.32,
				sin(theta) * radius * 0.76) * warp
			points.append(centre + local.rotated(rotation))
		var index_line := ring % 4 == 3
		canvas.draw_polyline(points, _alpha(ink, 0.86 if index_line else 0.46),
			1.25 if index_line else 0.85, true)

	# A tiny survey mark at the summit gives the linework a deliberate focal
	# point, especially on the small live-preview strip.
	canvas.draw_circle(centre, 2.1, _alpha(ink, 0.88))
	canvas.draw_line(centre - Vector2(8.0, 0.0), centre + Vector2(8.0, 0.0),
		_alpha(ink, 0.54), 1.0, true)
	canvas.draw_line(centre - Vector2(0.0, 8.0), centre + Vector2(0.0, 8.0),
		_alpha(ink, 0.54), 1.0, true)


## Gilded architectural fans in all four corners, tied together by a restrained
## double-rule frame. The motifs live at the edges so the central menu remains
## calm; on a portrait crop they still provide a complete, deliberate border.
static func _draw_deco(canvas: CanvasItem, rect: Rect2, ink: Color, scale: float) -> void:
	var unit := maxf(scale, 24.0)
	var inset := maxf(8.0, unit * 0.18)
	if rect.size.x > inset * 4.0 and rect.size.y > inset * 4.0:
		canvas.draw_rect(rect.grow(-inset), _alpha(ink, 0.30), false, 1.0)
		canvas.draw_rect(rect.grow(-inset - 4.0), _alpha(ink, 0.12), false, 1.0)

	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var starts: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
	for corner in range(corners.size()):
		var origin := corners[corner]
		var start := starts[corner]
		for ring in range(5):
			var radius := unit * (0.52 + float(ring) * 0.34)
			canvas.draw_arc(origin, radius, start, start + PI * 0.5, 28,
				_alpha(ink, 0.68 - float(ring) * 0.07), 1.05, true)
		for spoke in range(1, 6):
			var direction := Vector2.from_angle(start + PI * float(spoke) / 12.0)
			canvas.draw_line(origin + direction * unit * 0.24,
				origin + direction * unit * 1.94, _alpha(ink, 0.24), 0.85, true)
		var jewel := origin + Vector2.from_angle(start + PI * 0.25) * unit * 2.08
		_draw_diamond(canvas, jewel, unit * 0.13, _alpha(ink, 0.64))


static func _draw_diamond(canvas: CanvasItem, centre: Vector2, radius: float,
		ink: Color) -> void:
	var points := PackedVector2Array([
		centre + Vector2(0.0, -radius), centre + Vector2(radius, 0.0),
		centre + Vector2(0.0, radius), centre + Vector2(-radius, 0.0),
		centre + Vector2(0.0, -radius),
	])
	canvas.draw_polyline(points, ink, 1.0, true)


## A classic club knit: alternating translucent diamonds, fine outlines and a
## small stitched lozenge in the quieter cells. The whole repeat can be turned
## with Angle, and the generous clear ink keeps it usable over detailed art.
static func _draw_argyle(canvas: CanvasItem, rect: Rect2, ink: Color, scale: float,
		angle: int) -> void:
	var unit := maxf(scale, 24.0)
	var half_width := unit * 0.52
	var half_height := unit * 0.82
	var step_x := half_width * 2.0
	var step_y := half_height * 2.0
	var centre := rect.get_center()
	var direction := Vector2.RIGHT.rotated(deg_to_rad(float(angle)))
	var normal := Vector2(-direction.y, direction.x)
	var columns := ceili(rect.size.length() / step_x) + 2
	var rows := ceili(rect.size.length() / step_y) + 2
	for row in range(-rows, rows + 1):
		for column in range(-columns, columns + 1):
			var local := Vector2(float(column) * step_x + float(posmod(row, 2)) * half_width,
				float(row) * step_y)
			var middle := centre + direction * local.x + normal * local.y
			var top := middle - normal * half_height
			var right := middle + direction * half_width
			var bottom := middle + normal * half_height
			var left := middle - direction * half_width
			var diamond := PackedVector2Array([top, right, bottom, left])
			if posmod(row + column, 2) == 0:
				canvas.draw_colored_polygon(diamond, _alpha(ink, 0.13))
			var outline := diamond.duplicate()
			outline.append(top)
			canvas.draw_polyline(outline, _alpha(ink, 0.58), 0.9, true)
			if posmod(row + column, 2) == 1:
				var stitch := PackedVector2Array([
					middle - normal * half_height * 0.15,
					middle + direction * half_width * 0.15,
					middle + normal * half_height * 0.15,
					middle - direction * half_width * 0.15,
					middle - normal * half_height * 0.15,
				])
				canvas.draw_polyline(stitch, _alpha(ink, 0.30), 0.8, true)


## Soft clubhouse lights: layered discs make an inexpensive optical falloff,
## while a hairline rim gives a few orbs the familiar photographic bokeh edge.
## Orbs behind the central cards are deliberately quieter than those outside.
static func _draw_bokeh(canvas: CanvasItem, rect: Rect2, ink: Color, scale: float,
		density: int) -> void:
	var count: int = [12, 22, 36][clampi(density, 0, 2)]
	var unit := maxf(scale, 12.0)
	var quiet_centre := Rect2(rect.position + rect.size * 0.16, rect.size * 0.68)
	var rng := RandomNumberGenerator.new()
	rng.seed = BOKEH_SEED
	for index in range(count):
		var point := Vector2(
			rect.position.x + rng.randf() * rect.size.x,
			rect.position.y + rng.randf() * rect.size.y)
		var radius := unit * rng.randf_range(0.18, 1.0)
		var weight := 0.42 if quiet_centre.has_point(point) else 0.82
		var orb_ink := ink.lightened(rng.randf_range(0.0, 0.28))
		orb_ink.a = ink.a
		for layer in range(6):
			var fraction := 1.0 - float(layer) / 6.0
			var falloff := 0.024 + float(layer) * 0.006
			canvas.draw_circle(point, radius * fraction, _alpha(orb_ink, weight * falloff))
		if radius >= 7.0:
			canvas.draw_arc(point, radius * 0.88, 0.0, TAU, 36,
				_alpha(orb_ink, weight * 0.16), 0.9, true)
		if index % 4 == 0:
			var highlight := point + Vector2(-radius * 0.20, -radius * 0.20)
			canvas.draw_circle(highlight, maxf(1.0, radius * 0.055),
				_alpha(orb_ink, weight * 0.34))
		else:
			canvas.draw_circle(point, 1.0, _alpha(orb_ink, weight * 0.24))


static func _alpha(ink: Color, multiplier: float) -> Color:
	return Color(ink.r, ink.g, ink.b, clampf(ink.a * multiplier, 0.0, 1.0))
