extends Control
class_name DockArcBackdrop
## The bottom-left corner's backdrop: a quarter-green fan shaped around the
## dock's medallions, replacing the straight rectangle the bottom bar used
## to paint behind them.
##
## The six circles of BottomControlDock already describe a descending arc -
## Build, Manage and Golfers curving down from the corner, Menu, Pause and
## Speed echoing them underneath - so the backdrop is cut to that arc
## instead of to the bar's rectangle. Its rim is one smooth spline swept
## across the three section medallions - a single anchor per circle, part
## way from its centre toward the hub's outside - rather than a scalloped
## outline wrapped around each one, so the medallions sit astride the rim
## and poke out past it over the course. The turf fills everything below
## the rim to the screen's corner, and the course shows through above it
## where the old bar was dead space.
##
## The turf is mown like a green seen from its corner: concentric mowing
## rings around the hub alternate two deep greens, fainter wedge sectors
## cross them into a chequered fan, and each medallion sits in a dark
## socket so it reads as seated in the turf rather than pasted on it.
## Dotted ball-flight arcs join the medallions through the gaps between
## them, dew speckles catch the light, and a tiny flagstick stands in the
## corner pocket below Menu. The rim itself wears the pixel-frame bands of
## the rest of the UI - ink, accent trim, a lit bevel, a hard sheen step -
## with the trim in the open section's colour, so the corner announces
## which section is open before the shelf is even read. A collapsed
## section drops the trim back to the bar's sage.
##
## Like PixelCircleButton's faces, the art is generated as a half-size
## Image and drawn back up with nearest filtering, which keeps every step
## chunky at any window size. The generation is pure Image work (see
## arc_image), so it runs headless and tests can read it pixel by pixel;
## generated images and textures are cached on their geometry and accent,
## so a resize or a section switch repaints once and redraws are free.

## Display pixels per generated image pixel: the two-pixel grain the
## medallion faces are drawn at.
const PIXEL := 2
## How far across a section medallion the rim crosses it, as a fraction of
## its radius measured from the centre along the hub ray: the rim's anchor
## sits this far out, so the remaining fraction of the medallion pokes
## past the border over the course. One anchor per medallion is what keeps
## the rim one clean arc instead of a scallop around every circle.
const RIM_CROSS_FRACTION := 0.4
## The rim's synthetic end anchors run it off the top and right edges of
## the corner: this far above the first medallion, and this far beyond
## the last, so the arc sweeps in and out of frame instead of stopping
## dead at the end circles.
const RIM_EDGE_LIFT := 18.0
const RIM_EDGE_RUN := 42.0
## Rim band edges, inside distance from the rim in display pixels: the
## pixel frame's cross-section (ink, trim, bevel, sheen) bent along the arc.
const BAND_INK := 2.0
const BAND_TRIM := 4.0
const BAND_BEVEL := 6.0
const BAND_SHEEN := 10.0
## Width of one mowing ring around the corner hub, in display pixels.
const RING_WIDTH := 15.0
## Angular width of one chequer sector of the fan, in degrees.
const SECTOR_DEGREES := 15.0
## How much a chequer sector lifts its turf tone.
const SECTOR_LIFT := 1.10
## Width of the dark socket ring a medallion sits in, in display pixels.
const SOCKET_WIDTH := 5.0
## Spacing of the sampled dots along a ball-flight arc, and how many of
## each four samples are drawn (the dash).
const DOT_STEP := 3.0
const DOT_ON := 2
const DOT_CYCLE := 4
## Reach of the soft pixel shadow the rim throws onto the course.
const SHADOW_REACH := 3.0

## The frame's ink, shared with the medallion faces.
const INK := Color("081812")
const CREAM := Color("f4ecd0")
## The fan's two turf tones: deep enough that the medallions' own faces
## (192e26 / 284c3c) stand proud of them, and near the bar's old fill
## (101f19) so the corner still meets the shelf quietly.
const TURF_DARK := Color("10241a")
const TURF_LIGHT := Color("173423")
## The socket a medallion sits in, darker than either turf tone.
const SOCKET := Color("0a1811")
## Trim while no section is open: the bottom bar's sage.
const FALLBACK_ACCENT := Color("718f69")
## Dotted arc through the section medallions, and through the utilities.
const FLIGHT_GOLD := Color("e5bd66")
const FLIGHT_SAGE := Color("a2ba85")
## The corner pocket's flagstick.
const FLAG_RED := Color("d86a5a")
## The rim's shadow on the course: hard-edged, like everything else here.
const SHADOW := Color(4.0 / 255.0, 16.0 / 255.0, 10.0 / 255.0, 90.0 / 255.0)

## Which section's colour the rim trim wears. BottomControlDock keeps this
## in step with the open section (see its _sync_section).
var accent: Color = FALLBACK_ACCENT:
	set(value):
		if accent != value:
			accent = value
			if is_inside_tree():
				queue_redraw()

## Medallions the rim sweeps across (the section circles), and the inner
## row echoing them (the utility circles), each a Vector3 of centre x,
## centre y and radius in this control's coordinates. BottomControlDock
## hands over fresh geometry whenever it lays its buttons out, so the arc
## always follows the buttons the player actually sees.
var _outer_circles: Array = []
var _inner_circles: Array = []

static var _image_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}

func _init() -> void:
	name = "ArcBackdrop"
	# Pure backdrop: clicks above the rim belong to the course, and clicks
	# below it to the medallions on top.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)

## Take the dock's current medallion geometry: the outer (section) circles
## the rim sweeps across, and the inner (utility) circles beneath them.
func set_circles(outer: Array, inner: Array) -> void:
	_outer_circles = outer.duplicate()
	_inner_circles = inner.duplicate()
	if is_inside_tree():
		queue_redraw()

func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	draw_texture_rect(
			texture_for(size, _outer_circles, _inner_circles, accent),
			Rect2(Vector2.ZERO, size), false)

# =============================================================================
# RIM GEOMETRY
# =============================================================================

## The rim's anchor points: one per outer medallion, part way across its
## face on the ray from the hub through its centre, so the spline through
## them is one smooth arc following the row's curve and the medallions -
## drawn on top - poke out past it. Synthetic anchors beyond the first
## and last circles run the arc off the top and right edges. Circles are
## ordered by their angle around the hub, so the spline sweeps from the
## top edge down to the shelf without doubling back.
static func rim_anchors(outer_circles: Array, hub: Vector2) -> Array:
	var ordered: Array = outer_circles.duplicate()
	ordered.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2(-(a.y - hub.y), a.x - hub.x) > atan2(-(b.y - hub.y), b.x - hub.x))
	var anchors: Array = []
	for circle: Vector3 in ordered:
		var center := Vector2(circle.x, circle.y)
		anchors.append(center + (center - hub).normalized() * circle.z * RIM_CROSS_FRACTION)
	if ordered.size() < 2:
		return anchors
	var first: Vector3 = ordered[0]
	var last: Vector3 = ordered[-1]
	var start := Vector2(first.x - first.z * 0.9, first.y - first.z - RIM_EDGE_LIFT)
	var end := Vector2(last.x + last.z + RIM_EDGE_RUN, last.y + last.z * 0.85)
	return [start] + anchors + [end]

## The rim as a densely sampled Catmull-Rom spline through its anchors.
## Samples land at most a couple of display pixels apart, close enough
## that stamping the rim bands along them leaves no gaps.
static func rim_curve(outer_circles: Array, hub: Vector2) -> PackedVector2Array:
	var anchors := rim_anchors(outer_circles, hub)
	var curve := PackedVector2Array()
	if anchors.size() < 2:
		for anchor: Vector2 in anchors:
			curve.append(anchor)
		return curve
	var pts: Array = [anchors[0]] + anchors + [anchors[-1]]
	for i in range(1, pts.size() - 2):
		var p0: Vector2 = pts[i - 1]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[i + 2]
		var steps := clampi(int(p1.distance_to(p2) / 2.0), 4, 48)
		for j in steps:
			var t := float(j) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			curve.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
					+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	curve.append(anchors[-1])
	return curve

## The rim's height at every display column: the highest (smallest y)
## spline sample in that column, interpolated across any column the
## spline skips on its steep drop beside the last medallion, and held
## flat beyond the spline's ends. Everything below this line is turf.
static func _rim_top(curve: PackedVector2Array, width: int) -> PackedFloat32Array:
	var top := PackedFloat32Array()
	top.resize(maxi(width, 1))
	top.fill(INF)
	for point in curve:
		var xi := clampi(int(round(point.x)), 0, top.size() - 1)
		top[xi] = minf(top[xi], point.y)
	var defined := -1
	for x in top.size():
		if top[x] < INF:
			if defined < 0:
				for back in x:
					top[back] = top[x]
			elif x - defined > 1:
				for gap in range(defined + 1, x):
					top[gap] = lerpf(top[defined], top[x],
							float(gap - defined) / float(x - defined))
			defined = x
	if defined >= 0:
		for x in range(defined + 1, top.size()):
			top[x] = top[defined]
	return top

# =============================================================================
# PAINTING THE FAN
# =============================================================================

## The generated texture for one geometry and accent, from the cache when
## this fan has been painted before.
static func texture_for(canvas_size: Vector2, outer_circles: Array,
		inner_circles: Array, trim: Color) -> ImageTexture:
	var key := _cache_key(canvas_size, outer_circles, inner_circles, trim)
	if _texture_cache.has(key):
		return _texture_cache[key]
	var texture := ImageTexture.create_from_image(
			arc_image(canvas_size, outer_circles, inner_circles, trim))
	_texture_cache[key] = texture
	return texture

## The fan itself at half size: turf below the rim, air above it, rim
## bands bent along the rim, and the corner flag. Circles are Vector3
## (centre x, centre y, radius) in display coordinates of a canvas of
## `canvas_size`; the corner hub is the canvas's bottom-left. Pure Image
## work, so it runs headless and tests can inspect it pixel by pixel.
static func arc_image(canvas_size: Vector2, outer_circles: Array,
		inner_circles: Array, trim: Color) -> Image:
	var key := _cache_key(canvas_size, outer_circles, inner_circles, trim)
	if _image_cache.has(key):
		return _image_cache[key]
	var w := maxi(1, int(ceil(canvas_size.x / float(PIXEL))))
	var h := maxi(1, int(ceil(canvas_size.y / float(PIXEL))))
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var circles: Array = outer_circles + inner_circles
	if outer_circles.is_empty():
		# No medallions to shape around yet (the dock lays its buttons out
		# after this control first draws): plain turf, as the bar was.
		image.fill(TURF_DARK)
		_image_cache[key] = image
		return image
	var hub := Vector2(0.0, canvas_size.y)
	var curve := rim_curve(outer_circles, hub)
	var top := _rim_top(curve, int(canvas_size.x) + 1)
	var dots := _flight_dots(outer_circles, FLIGHT_GOLD)
	dots.append_array(_flight_dots(inner_circles, FLIGHT_SAGE))
	var inside := PackedByteArray()
	inside.resize(w * h)
	for py in h:
		for px in w:
			var point := Vector2(px * PIXEL + PIXEL * 0.5, py * PIXEL + PIXEL * 0.5)
			var column := clampi(int(point.x), 0, top.size() - 1)
			var socket_d := INF
			var filled := point.y >= top[column]
			# The section medallions deliberately get no turf beyond the
			# rim: the arc cuts across their faces and they poke out past
			# it. Their distance still feeds the socket shading below it.
			for circle: Vector3 in outer_circles:
				socket_d = minf(socket_d,
						point.distance_to(Vector2(circle.x, circle.y)) - circle.z)
			# The inner row lives below the rim, but keep its sockets whole
			# even if a future layout lets the spline clip one.
			for circle: Vector3 in inner_circles:
				var d := point.distance_to(Vector2(circle.x, circle.y))
				socket_d = minf(socket_d, d - circle.z)
				if d <= circle.z + SOCKET_WIDTH:
					filled = true
			if not filled:
				continue
			inside[py * w + px] = 1
			image.set_pixel(px, py, _turf_at(point, hub, socket_d,
					point.y - maxf(top[column], 0.0), px, py, dots))
	_stamp_rim(image, inside, curve, canvas_size, top, trim)
	_draw_flag(image, inside, circles)
	_image_cache[key] = image
	return image

## The turf colour at one point of the fan, before the rim bands are
## stamped over it: ring, chequer sector, socket, flight dots and dew.
static func _turf_at(point: Vector2, hub: Vector2, socket_d: float,
		rim_gap: float, px: int, py: int, dots: Array) -> Color:
	var hue := TURF_DARK if int(point.distance_to(hub) / RING_WIDTH) % 2 == 0 else TURF_LIGHT
	var angle := rad_to_deg(atan2(hub.y - point.y, point.x - hub.x))
	if int(angle / SECTOR_DEGREES) % 2 == 1:
		hue = _scaled(hue, SECTOR_LIFT)
	if socket_d >= 0.0 and socket_d <= SOCKET_WIDTH:
		return SOCKET
	for dot: Vector3 in dots:
		if point.distance_squared_to(Vector2(dot.x, dot.y)) < 2.6:
			return FLIGHT_GOLD if dot.z > 0.5 else FLIGHT_SAGE
	# Dew: a deterministic speckle, kept clear of the rim and the sockets
	# so it never muddies either edge.
	if rim_gap > 12.0 and socket_d > 8.0 and ((px * 73856093) ^ (py * 19349663)) & 0xff < 4:
		hue = _scaled(hue, 1.35)
	return hue

## Sampled points along the dashed arc through a row of medallion centres,
## as Vector3 (x, y, is_gold). Most of the arc hides under the medallions
## themselves; the dashes show in the gaps and join the row up.
static func _flight_dots(row: Array, color: Color) -> Array:
	var dots: Array = []
	var is_gold := 1.0 if color == FLIGHT_GOLD else 0.0
	for i in range(row.size() - 1):
		var a := Vector2((row[i] as Vector3).x, (row[i] as Vector3).y)
		var b := Vector2((row[i + 1] as Vector3).x, (row[i + 1] as Vector3).y)
		var count := maxi(1, int(a.distance_to(b) / DOT_STEP))
		for j in count + 1:
			if j % DOT_CYCLE < DOT_ON:
				var point := a.lerp(b, float(j) / float(count))
				dots.append(Vector3(point.x, point.y, is_gold))
	return dots

## The rim's shadow on the course and its frame bands on the turf,
## stamped as hard discs along the rim. Stamping largest first lets each
## inner band paint over the middle of the last, which keeps every band
## a constant thickness round the spline's bends for a fraction of the
## cost of a true per-pixel distance field. The stamp path follows the
## rim's columns (clamped onto the canvas, so the bands also run along
## the top edge where the spline leaves through it, as the old bar's top
## bands did) resampled evenly along its length.
static func _stamp_rim(image: Image, inside: PackedByteArray,
		curve: PackedVector2Array, canvas_size: Vector2,
		top: PackedFloat32Array, trim: Color) -> void:
	var path: Array = []
	var last := Vector2(0.0, clampf(top[0], 0.0, canvas_size.y))
	path.append(last)
	for x in range(PIXEL, top.size(), PIXEL):
		var point := Vector2(float(x), clampf(top[x], 0.0, canvas_size.y))
		var steps := maxi(1, int(last.distance_to(point) / 2.0))
		for j in range(1, steps + 1):
			path.append(last.lerp(point, float(j) / float(steps)))
		last = point
	if path.size() < 2:
		for point in curve:
			path.append(Vector2(clampf(point.x, 0.0, canvas_size.x),
					clampf(point.y, 0.0, canvas_size.y)))
	var bands: Array = [
		[-SHADOW_REACH, SHADOW],
		[BAND_SHEEN, _scaled(TURF_LIGHT, 1.35)],
		[BAND_BEVEL, _scaled(trim, 1.25)],
		[BAND_TRIM, trim],
		[BAND_INK, INK],
	]
	var w := image.get_width()
	var h := image.get_height()
	for band: Array in bands:
		var reach: float = band[0]
		var color: Color = band[1]
		var want_inside := reach > 0.0
		var radius := absf(reach)
		var span := int(ceil(radius / float(PIXEL)))
		for stamp: Vector2 in path:
			var cx := int(stamp.x / float(PIXEL))
			var cy := int(stamp.y / float(PIXEL))
			for py in range(maxi(cy - span, 0), mini(cy + span + 1, h)):
				for px in range(maxi(cx - span, 0), mini(cx + span + 1, w)):
					if (inside[py * w + px] == 1) != want_inside:
						continue
					var point := Vector2(px * PIXEL + PIXEL * 0.5, py * PIXEL + PIXEL * 0.5)
					if point.distance_to(stamp) < radius:
						image.set_pixel(px, py, color)

## The corner pocket's signature: a tiny flagstick on the fan's hub
## corner, with its cup's shadow and a ball resting beside it. Drawn in
## generated-image pixels, and only where no medallion crowds it.
static func _draw_flag(image: Image, inside: PackedByteArray, circles: Array) -> void:
	var h := image.get_height()
	var hx := 9
	var ground := h - 3
	if ground < 20 or image.get_width() < hx + 14:
		return
	var pole_top := Vector2(hx * PIXEL, (ground - 17) * PIXEL)
	for circle: Vector3 in circles:
		if pole_top.distance_to(Vector2(circle.x, circle.y)) <= circle.z + 2.0:
			return
	var w := image.get_width()
	var put := func(px: int, py: int, color: Color) -> void:
		if px >= 0 and px < w and py >= 0 and py < h and inside[py * w + px] == 1:
			image.set_pixel(px, py, color)
	for i in 18:
		put.call(hx, ground - i, CREAM)
	for dy in range(-3, 4):
		var flag_width := int(ceil(8.0 * (1.0 - absf(float(dy)) / 3.0)))
		for dx in range(1, flag_width + 1):
			put.call(hx + dx, ground - 14 + dy, FLAG_RED)
	for dx in range(-3, 11):
		put.call(hx + dx, ground - 1, SOCKET)
		put.call(hx + dx, ground, SOCKET)
	put.call(hx + 12, ground - 1, CREAM)

## Multiply a colour's light without shifting its hue (unlike lightened,
## which walks toward white): the turf's own steps, kept in family.
static func _scaled(color: Color, factor: float) -> Color:
	return Color(minf(color.r * factor, 1.0), minf(color.g * factor, 1.0),
			minf(color.b * factor, 1.0), color.a)

static func _cache_key(canvas_size: Vector2, outer_circles: Array,
		inner_circles: Array, trim: Color) -> String:
	return "%dx%d|%s|%s|%s" % [int(canvas_size.x), int(canvas_size.y),
			trim.to_html(), str(outer_circles), str(inner_circles)]
