extends Control
class_name ShelfFanBackdrop
## The bottom-right shelf's fairway, cut to a mirrored version of the
## bottom-left dock's quarter-ellipse. The rim joins the dock at the shelf's
## left edge and rises to its top, then runs above the scrolling pages.
## The tab medallions follow that curve, with the course visible outside it.
##
## The mowing rings still share the dock's bottom-left hub, and the rim uses
## the same ink, section-coloured trim, bevel, sheen and shadow as the dock.
## The image is generated at two-pixel grain and cached, just like the fan.

## Display pixels per generated image pixel: the two-pixel grain the medallion
## faces are drawn at, shared with the dock's fan.
const PIXEL := 2
## Width of one mowing ring around the shared hub, in display pixels. The same
## ring width as the dock's fan, so the two fairways mow at one rhythm.
const RING_WIDTH := 15.0
## Angular width of one chequer sector of the fan, in degrees.
const SECTOR_DEGREES := 15.0
## How much a chequer sector lifts its turf tone.
const SECTOR_LIFT := 1.10
## Width of the dark socket ring a medallion sits in, in display pixels.
const SOCKET_WIDTH := 5.0
## Spacing of the sampled dots along a ball-flight arc, and how many of each
## four samples are drawn (the dash).
const DOT_STEP := 3.0
const DOT_ON := 2
const DOT_CYCLE := 4

## The frame's ink, shared with the medallion faces and the dock's fan.
const INK := Color("081812")
## The fairway's two mowing tones: the same deep greens the dock's fan uses,
## so the shelf's turf is literally the same grass as the corner's.
const TURF_DARK := Color("10241a")
const TURF_LIGHT := Color("173423")
## The socket a medallion sits in, darker than either turf tone.
const SOCKET := Color("0a1811")
## The dotted ball-flight arc through the shelf's medallions, and the dew.
const FLIGHT_GOLD := Color("e5bd66")
## Trim while no section is open: the bottom bar's sage.
const FALLBACK_ACCENT := Color("718f69")

## Which section's colour the rim wears. TerrainToolbar keeps it in step
## with the open section (see its _sync_navigation).
var accent: Color = FALLBACK_ACCENT:
	set(value):
		if accent != value:
			accent = value
			if is_inside_tree():
				queue_redraw()

## The shared hub (the dock's bottom-left corner) in this control's own
## coordinates, and the medallions the fairway is laid out around (the tab
## rail's circles, each a Vector3 of centre x, centre y and radius). The page
## title's rect (in this control's coordinates) is held separately and its
## bottom edge wears a curved gold rule echoing the dock fan's rim.
var _hub := Vector2.ZERO
## Horizontal radius of the mirrored quarter-ellipse, in display pixels.
var curve_width := 0.0
## Part of the ellipse lies beyond the left dock's canvas. Tuck the same
## fraction behind the shelf edge so the two rims meet without a broken seam.
var seam_inset := 0.0
var circles: Array = []
var _rule := Rect2()

## A live window resize can produce hundreds of distinct shelf sizes. Keep
## only recent artwork rather than retaining every full-width image forever.
const CACHE_LIMIT := 12
static var _image_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}

func _init() -> void:
	name = "ShelfFanBackdrop"
	# Pure backdrop: the shelf's controls above it answer their own clicks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)

## Take the shared hub's position in this control's coordinates: the dock's
## bottom-left corner, which sits to the shelf's left.
func set_hub(hub: Vector2) -> void:
	if _hub != hub:
		_hub = hub
		if is_inside_tree():
			queue_redraw()

## The rail reserves this much width for the mirrored edge. `inset` accounts
## for the small part of the dock's ellipse clipped by the dock's right edge.
func set_curve(width: float, inset: float) -> void:
	width = maxf(width, 0.0)
	inset = clampf(inset, 0.0, width)
	if not is_equal_approx(curve_width, width) or not is_equal_approx(seam_inset, inset):
		curve_width = width
		seam_inset = inset
		if is_inside_tree():
			queue_redraw()

## Take the tab rail's current medallion geometry (centre x, centre y, radius
## in this control's coordinates). TerrainToolbar hands over fresh geometry
## whenever it lays its buttons out, so the sockets always hug the circles.
func set_circles(new_circles: Array) -> void:
	if circles != new_circles:
		circles = new_circles.duplicate()
		if is_inside_tree():
			queue_redraw()

## Take the page title's rect in this control's own coordinates: its bottom
## edge wears a curved gold rule, so the shelf's one line of type sits on the
## same arc the dock's rim is drawn on.
func set_title_rule(rect: Rect2) -> void:
	if _rule != rect:
		_rule = rect
		if is_inside_tree():
			queue_redraw()

func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	draw_texture_rect(
		texture_for(size, _hub, circles, accent, _rule, curve_width, seam_inset),
		Rect2(Vector2.ZERO, size), false)

# ============================================================================
# MIRRORED RIM AND FAIRWAY
# ============================================================================

## The top of the shelf at x: the left dock's quarter-ellipse reflected across
## the rail, followed by a straight top edge over the pages. A zero width is a
## flat fallback while the rail is waiting for its first layout.
static func rim_top_at(x: float, canvas_size: Vector2, width: float, inset: float = 0.0) -> float:
	if width <= 0.0:
		return 0.0
	var horizontal := clampf((width - inset - x) / width, 0.0, 1.0)
	var radius_y := maxf(canvas_size.y + DockArcBackdrop.RIM_TOP_LIFT, 1.0)
	return canvas_size.y - radius_y * sqrt(maxf(0.0, 1.0 - horizontal * horizontal))

## Inverse of rim_top_at, used to seat the tabs on exactly the painted curve.
static func rim_x_at(y: float, canvas_size: Vector2, width: float, inset: float = 0.0) -> float:
	if width <= 0.0:
		return 0.0
	var radius_y := maxf(canvas_size.y + DockArcBackdrop.RIM_TOP_LIFT, 1.0)
	var vertical := clampf((canvas_size.y - y) / radius_y, 0.0, 1.0)
	return width * (1.0 - sqrt(maxf(0.0, 1.0 - vertical * vertical))) - inset

## Whether a point belongs to the turf, rather than the transparent course
## above its rim. The toolbar uses the same geometry for pointer hit testing.
static func contains_point(point: Vector2, canvas_size: Vector2, width: float,
		inset: float = 0.0) -> bool:
	return Rect2(Vector2.ZERO, canvas_size).has_point(point) \
		and point.y >= maxf(0.0, rim_top_at(point.x, canvas_size, width, inset))

## The generated texture for one geometry and accent, from the cache when this
## fairway has been painted before.
static func texture_for(canvas_size: Vector2, hub: Vector2, medallions: Array,
		trim: Color, rule: Rect2 = Rect2(), width: float = 0.0, inset: float = 0.0) -> ImageTexture:
	var key := _cache_key(canvas_size, hub, medallions, trim, rule, width, inset)
	if _texture_cache.has(key):
		return _texture_cache[key]
	var texture := ImageTexture.create_from_image(
		shelf_image(canvas_size, hub, medallions, trim, rule, width, inset))
	_cache_store(_texture_cache, key, texture)
	return texture

## The fairway at half size: transparent above the reflected rim, mown turf
## below it, sockets, dotted flight arc and the title's gold rule. `hub` is the
## dock's bottom-left corner in this canvas; `width` is the curve's horizontal
## radius and `inset` accounts for the dock's clipped rim. Pure Image work, so
## tests can inspect the silhouette pixel by pixel.
static func shelf_image(canvas_size: Vector2, hub: Vector2, medallions: Array,
		trim: Color, rule: Rect2 = Rect2(), width: float = 0.0, inset: float = 0.0) -> Image:
	var key := _cache_key(canvas_size, hub, medallions, trim, rule, width, inset)
	if _image_cache.has(key):
		return _image_cache[key]
	var w := maxi(1, int(ceil(canvas_size.x / float(PIXEL))))
	var h := maxi(1, int(ceil(canvas_size.y / float(PIXEL))))
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var dots := _flight_dots(medallions)
	var top := PackedFloat32Array()
	top.resize(maxi(1, int(ceil(canvas_size.x)) + 1))
	for x in top.size():
		top[x] = rim_top_at(float(x), canvas_size, width, inset)
	var inside := PackedByteArray()
	inside.resize(w * h)
	for py in h:
		for px in w:
			var point := Vector2(px * PIXEL + PIXEL * 0.5, py * PIXEL + PIXEL * 0.5)
			if point.y < top[clampi(int(point.x), 0, top.size() - 1)]:
				continue
			inside[py * w + px] = 1
			image.set_pixel(px, py, _turf_at(point, hub, medallions, px, py, dots))
	# Reuse the dock's painter, including its pixel shadow and four frame bands.
	DockArcBackdrop.stamp_rim(image, inside, PackedVector2Array(), canvas_size, top, trim)
	_draw_title_rule(image, rule, inside)
	_cache_store(_image_cache, key, image)
	return image

## The turf colour at one point of the fairway: ring, chequer sector, socket,
## flight dot and dew, in that order.
static func _turf_at(point: Vector2, hub: Vector2, medallions: Array,
		px: int, py: int, dots: Array) -> Color:
	var dist := point.distance_to(hub)
	var hue := TURF_DARK if int(dist / RING_WIDTH) % 2 == 0 else TURF_LIGHT
	var angle := rad_to_deg(atan2(hub.y - point.y, point.x - hub.x))
	if int(angle / SECTOR_DEGREES) % 2 == 1:
		hue = _scaled(hue, SECTOR_LIFT)
	var socket_d := INF
	for circle: Vector3 in medallions:
		socket_d = minf(socket_d,
			point.distance_to(Vector2(circle.x, circle.y)) - circle.z)
		if socket_d >= 0.0 and socket_d <= SOCKET_WIDTH:
			return SOCKET
	for dot: Vector3 in dots:
		if point.distance_squared_to(Vector2(dot.x, dot.y)) < 2.6:
			return FLIGHT_GOLD
	# Dew: a deterministic speckle, kept clear of the sockets so it never
	# muddies a medallion's seat.
	if socket_d > 8.0 and ((px * 73856093) ^ (py * 19349663)) & 0xff < 4:
		hue = _scaled(hue, 1.35)
	return hue

## Sampled points along the dashed gold arc through a row of medallion
## centres, as Vector3 (x, y, unused). Most of the arc hides under the
## medallions themselves; the dashes show in the gaps and join the row up.
static func _flight_dots(row: Array) -> Array:
	var dots: Array = []
	for i in range(row.size() - 1):
		var a := Vector2((row[i] as Vector3).x, (row[i] as Vector3).y)
		var b := Vector2((row[i + 1] as Vector3).x, (row[i + 1] as Vector3).y)
		var count := maxi(1, int(a.distance_to(b) / DOT_STEP))
		for j in count + 1:
			if j % DOT_CYCLE < DOT_ON:
				var point := a.lerp(b, float(j) / float(count))
				dots.append(Vector3(point.x, point.y, 0.0))
	return dots

## The page title's gold rule: a straight solid line along the title's bottom
## edge. Every step sits on the same row, so the rule has no bump in its
## middle. Drawn in generated-image pixels, one band thick.
static func _draw_title_rule(image: Image, rule: Rect2, inside: PackedByteArray) -> void:
	if rule.size.x < 6.0:
		return
	var w := image.get_width()
	var h := image.get_height()
	var x0 := rule.position.x
	var x1 := rule.end.x
	var steps := maxi(1, int((x1 - x0) / 2.0))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := x0 + (x1 - x0) * t
		var y := rule.end.y
		var px := int(round(x / float(PIXEL)))
		var py := int(round(y / float(PIXEL)))
		if px >= 0 and px < w and py >= 0 and py < h and inside[py * w + px] == 1:
			image.set_pixel(px, py, FLIGHT_GOLD)

## Multiply a colour's light without shifting its hue (unlike lightened,
## which walks toward white): the fairway's own steps, kept in family.
static func _scaled(color: Color, factor: float) -> Color:
	return Color(minf(color.r * factor, 1.0), minf(color.g * factor, 1.0),
		minf(color.b * factor, 1.0), color.a)

## Dictionary insertion order gives a simple bounded FIFO cache.
static func _cache_store(cache: Dictionary, key: String, value: Variant) -> void:
	if cache.size() >= CACHE_LIMIT:
		cache.erase(cache.keys()[0])
	cache[key] = value

static func _cache_key(canvas_size: Vector2, hub: Vector2, medallions: Array,
		trim: Color, rule: Rect2, width: float, inset: float) -> String:
	return "%dx%d|%s|%s|%s|%s|%.2f|%.2f" % [int(canvas_size.x), int(canvas_size.y),
		hub, str(medallions), trim.to_html(), str(rule), width, inset]
