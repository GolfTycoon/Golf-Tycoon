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

## Patterns a catalogue entry may name. Anything else draws nothing (and the
## registry says so), so a mod that misses the list still fails softly.
const PATTERNS: Array[String] = [
	"none", "wash", "vignette", "glow", "split",
	"stripes", "grid", "scanlines", "dots", "sparkle",
]

## Steps used to build the soft falloffs (vignette, glow): enough to read as a
## gradient, few enough that a phone repaints them cheaply.
const FALLOFF_STEPS := 14
## A sparkle glint is a tiny diamond; this is its base half-extent in pixels.
const SPARKLE_SIZE := 2.0
## The fixed seed the sparkle scatter is drawn from, so the pattern is stable
## between repaints instead of shimmering.
const SPARKLE_SEED := 6017


## The default feature size for a pattern, in logical pixels, used when an
## entry names no scale of its own.
static func default_scale(pattern: String) -> float:
	match pattern:
		"stripes": return 54.0
		"grid": return 34.0
		"scanlines": return 3.0
		"dots": return 7.0
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
