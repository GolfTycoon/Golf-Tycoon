extends Control
class_name GlobeMap
## GlobeMap - A draggable orthographic globe with a marker per course location.
##
## The globe is drawn in two layers so spinning, hovering and selecting never
## pay for the continents:
##
##  * **the planet** (`_planet`, a ColorRect running
##    `shaders/globe_planet.gdshader`): Natural Earth 1:50m land rings in
##    `data/world_land_polygons.json` are rasterised once into an equirectangular
##    land mask (`build_land_mask()`, cached for the whole run) and the shader turns that
##    mask back into a shaded sphere — sea depth and coastal shelf, fbm relief,
##    an arid band around the tropics, polar ice, a warm sun with a soft
##    day/night terminator, a specular glint on open water and a soft
##    atmosphere halo. One quad, one draw call, no texture assets.
##  * **the markers** (`_marker_layer`, a Control over the planet): the
##    destination pins and their labels, repainted only when the marker set
##    changes — a hover or a new selection leaves the planet untouched.
##
## `LandStyle.DOTS` keeps a lightweight, shader-free land-dot fallback; the
## planet is the default, and `LandStyle.PIXEL` is the same planet quantised
## into chunky hard-edged cells — the World Map screen's retro mode, matching
## the menu screens' pixel frames, sprites and Pixelify type.
##
## Drag to spin (with a little inertia), scroll or pinch to zoom, click a
## marker (or the list beside it) to select. On a touchscreen one finger spins
## and two fingers pinch open or closed to zoom, moving together to spin as
## well; a pinch never picks the marker under a lifted finger. The globe
## animates on wall-clock time rather than the simulation's, so it still turns
## when the screen hosting
## it has frozen the course behind it — and taking hold of it cancels any
## fly-to still in flight, so a drag always wins. Public API: `set_locations`,
## `set_selected`, `look_at_location`, `set_view_state` / `get_view_state`,
## `set_land_style`, `location_clicked(id)`, static `project_point`,
## `is_land`, `build_land_points`, `build_land_mask`, `mask_uv`.

signal location_clicked(location_id: String)

## How the continents are drawn: PLANET (baked mask + shader), DOTS (a
## shader-free rasterised land-dot fallback) or PIXEL (the same shader planet
## quantised into chunky hard-edged cells, with pixel-art pin sprites for the
## markers, to match the menu screens' 16-bit look).
enum LandStyle { PLANET, DOTS, PIXEL }

const DEFAULT_LAND_STYLE := LandStyle.PLANET
const PLANET_SHADER := preload("res://shaders/globe_planet.gdshader")
## The font the PIXEL globe's destination labels are set in: the same
## Pixelify Sans the menu screens use (SIL Open Font License 1.1).
const MARKER_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

## Size of the baked equirectangular land mask. 2048x1024 is about 20 km per
## texel at the equator, still much sharper than the globe is drawn.
const MASK_WIDTH := 2048
const MASK_HEIGHT := 1024
## Spacing of the shader-free land-dot fallback, in degrees.
const LAND_STEP_DEG := 3.0
const MIN_RADIUS_SCALE := 0.7
const MAX_RADIUS_SCALE := 1.6
const MAX_CENTER_LAT := 80.0
## One wheel notch / zoom button step.
const ZOOM_STEP := 1.12
## Spin inertia: how much of the drag's velocity the globe keeps, the cap on
## it, and how fast it bleeds off (per second).
const MAX_SPIN_DEG_PER_SEC := 320.0
const SPIN_DECAY := 0.02
## Seconds a "centre on this destination" move takes, and the settling rate
## used for zoom.
const CENTER_DURATION := 0.5
const ZOOM_SETTLE_RATE := 14.0
## Finger travel (px) past which a touch is a spin rather than a tap on a pin.
const TAP_SLOP := 6.0

const OCEAN_COLOR := Color("16314a")
const OCEAN_RIM := Color("0c1c2c")
const SHORE_COLOR := Color("8fb3c9")
const LAND_COLOR := Color("5f7d4a")
const LAND_SHADE_COLOR := Color("3f5530")
const GRATICULE_COLOR := Color(1.0, 1.0, 1.0, 0.10)
const MARKER_RADIUS := 6.0
const MARKER_HIT_RADIUS := 11.0

## The PIXEL planet's palette: the planet shader's own tunables re-mixed into
## the menu palette — a deep ink-teal sea with a pale shelf, golf greens for
## the land and sandy tropics — so the atlas sits inside the pixel-art
## screens instead of looking borrowed from a photograph.
const PIXEL_PALETTE: Dictionary = {
	"ocean_deep": Color("0e2430"),
	"ocean_mid": Color("15384a"),
	"ocean_shallow": Color("1f5468"),
	"shore_color": Color("93c4ad"),
	"land_low": Color("2b5c33"),
	"land_mid": Color("4f8f49"),
	"land_high": Color("7fb08a"),
	"land_dry": Color("b7a066"),
	"land_beach": Color("e0cf9d"),
	"ice_color": Color("edf4ec"),
	"atmosphere_color": Color("8fd0c2"),
}
## PIXEL light tuning: a higher ambient floor and a harder terminator keep the
## chunky cells bold rather than muddy; clouds and the glint stay quiet so
## the coastlines and pins carry the picture.
const PIXEL_TUNING: Dictionary = {
	"terminator_softness": 0.22,
	"specular_strength": 0.22,
	"cloud_amount": 0.10,
	"graticule_alpha": 0.09,
	"coast_glow": 0.50,
}
## Side of one pixel block on the PIXEL planet, per end of the clamp: the
## finer grid resolves coastlines at roughly 115 cells across a typical globe.
const PIXEL_BLOCK_MIN := 2.0
const PIXEL_BLOCK_MAX := 3.5
## Side of the destination pin sprite (one multiple of the 16px grid) and how
## far it floats above its point, for depth.
const PIN_SPRITE_SIDE := 16
const PIN_SPRITE_RAISE := 2.0

## Detailed Natural Earth 1:50m coastline rings (longitude, latitude),
## simplified offline to fit the globe's screen resolution.
const LAND_DATA_PATH := "res://data/world_land_polygons.json"

var _center_lon: float = -40.0
var _center_lat: float = 30.0
var _radius_scale: float = 1.0
## Where a zoom is settling to (the buttons and the wheel move this, _process
## eases _radius_scale towards it).
var _zoom_target: float = 1.0
var _locations: Array = []
var _selected_id: String = ""
var _hover_id: String = ""
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_last: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0
## Fingers on the globe, keyed by touch index (position in this control's
## space). One finger spins; two pinch to zoom. The global TouchInput adapter
## is for camera gestures; a touch on this control belongs to the atlas instead.
var _touches: Dictionary = {}
## The finger driving the spin.
var _touch_index: int = -1
## The pinch, measured against the view it started from: the span between the
## fingers, the midpoint, the radius scale, the centre and the sphere radius.
## Using that reference rather than the last event keeps the zoom steady when
## the two fingers' events interleave (their span appears to wobble between
## reports) and makes the gesture return exactly to the view it started from.
var _pinch_start_span: float = 0.0
var _pinch_mid: Vector2 = Vector2.ZERO
var _pinch_start_scale: float = 1.0
var _pinch_start_lon: float = 0.0
var _pinch_start_lat: float = 0.0
var _pinch_radius: float = 0.0
## True once a second finger has joined. It keeps the release of the last
## finger of a pinch from reading as a tap on a destination pin.
var _multi_touch_used: bool = false
var _marker_positions: Dictionary = {}
## Planet surface (shader) and the marker layer drawn over it.
var _planet: ColorRect = null
var _planet_material: ShaderMaterial = null
var _marker_layer: Control = null
var _land_style: int = DEFAULT_LAND_STYLE
## Degrees per second the globe keeps spinning after a flick, and the
## centring animation's endpoints.
var _spin_lon: float = 0.0
var _spin_lat: float = 0.0
var _anim_from_lon: float = 0.0
var _anim_from_lat: float = 0.0
var _anim_to_lon: float = 0.0
var _anim_to_lat: float = 0.0
var _anim_time: float = 0.0
var _animating: bool = false
## Wall-clock stamp of the previous animation frame, in microseconds. The
## globe keeps its own clock (see `_frame_seconds`) because the screens that
## host it — above all the Club tab's World Map, which freezes the course it
## opened over — hand it frames worth zero seconds. Negative means "no
## previous frame": the next one starts from nothing.
var _frame_usec: int = -1
static var _land_points: Array = []
static var _land_polygon_cache: Array = []
static var _land_polygon_cache_loaded: bool = false
## How often the planet surface has been re-shaded. Hovering and selecting a
## destination must not touch it — they are the marker layer's business.
var _view_syncs: int = 0
static var _mask_texture: ImageTexture = null
static var _mask_edges: Dictionary = {}
static var _mask_bake_count: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("native_touch_input")
	clip_contents = true
	# Screens that embed the globe may provide a tighter minimum for a phone;
	# keep a comfortable default for standalone previews and other callers.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(280, 240)
	_build_layers()
	_sync_planet()
	resized.connect(_on_resized)
	_stop_animating()

## The two drawing layers: the shader planet underneath, the markers on top.
func _build_layers() -> void:
	if _land_style == LandStyle.PLANET or _land_style == LandStyle.PIXEL:
		_planet_material = ShaderMaterial.new()
		_planet_material.shader = PLANET_SHADER
		_planet_material.set_shader_parameter("land_mask", get_land_mask_texture())
		_planet_material.set_shader_parameter("mask_size", Vector2(MASK_WIDTH, MASK_HEIGHT))
		if _land_style == LandStyle.PIXEL:
			_apply_pixel_palette()
		_planet = ColorRect.new()
		_planet.name = "PlanetSurface"
		_planet.color = Color.WHITE
		_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_planet.set_anchors_preset(Control.PRESET_FULL_RECT)
		_planet.material = _planet_material
		add_child(_planet)
	_marker_layer = Control.new()
	_marker_layer.name = "MarkerLayer"
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_layer.draw.connect(_draw_marker_layer)
	add_child(_marker_layer)

## Switch between the shader planet and the land-dot fallback. Set it before
## the globe enters the tree to decide the layers' first build; changing it on
## a live globe rebuilds them in place.
func set_land_style(style: int) -> void:
	if style == _land_style:
		return
	_land_style = style
	if is_inside_tree():
		if is_instance_valid(_planet):
			_planet.queue_free()
			_planet = null
			_planet_material = null
		if is_instance_valid(_marker_layer):
			_marker_layer.queue_free()
			_marker_layer = null
		_build_layers()
		_redraw_view()

func get_land_style() -> int:
	return _land_style

func _on_resized() -> void:
	_sync_planet()
	_redraw_view()

## Push the view into the planet shader. Changing a shader parameter is what
## makes the planet repaint, so this is the only cost of spinning the globe.
func _sync_planet() -> void:
	if _planet_material == null:
		return
	_view_syncs += 1
	_planet_material.set_shader_parameter("view_size", size)
	_planet_material.set_shader_parameter("center_lon_deg", _center_lon)
	_planet_material.set_shader_parameter("center_lat_deg", _center_lat)
	_planet_material.set_shader_parameter("radius_scale", _radius_scale)
	_planet_material.set_shader_parameter("pixel_block",
		_pixel_block_size() if _land_style == LandStyle.PIXEL else 0.0)

## The menu palette and the chunkier light, set once when the PIXEL planet's
## material is made (see PIXEL_PALETTE / PIXEL_TUNING).
func _apply_pixel_palette() -> void:
	for parameter in PIXEL_PALETTE:
		_planet_material.set_shader_parameter(parameter, PIXEL_PALETTE[parameter])
	for parameter in PIXEL_TUNING:
		_planet_material.set_shader_parameter(parameter, PIXEL_TUNING[parameter])

## Side of one retro cell on the PIXEL globe, in screen pixels: around 115
## cells across a typical sphere give the coastlines more resolution while
## keeping the toy-globe silhouette crisp on a phone and desktop.
func _pixel_block_size() -> float:
	return clampf(minf(size.x, size.y) / 125.0, PIXEL_BLOCK_MIN, PIXEL_BLOCK_MAX)

## The view moved: the planet needs new shading and the markers new positions.
func _redraw_view() -> void:
	_sync_planet()
	if _land_style == LandStyle.DOTS:
		queue_redraw()
	_redraw_markers()

## Only the pins changed (hover, selection, list): the planet is left alone.
func _redraw_markers() -> void:
	if is_instance_valid(_marker_layer):
		_marker_layer.queue_redraw()

## How many times the planet has been re-shaded (see _view_syncs).
func view_sync_count() -> int:
	return _view_syncs

## Current orientation and zoom, used to preserve the player's globe view when
## the responsive screen is rebuilt after a resize or device rotation.
func get_view_state() -> Dictionary:
	return {
		"center_lon": _center_lon,
		"center_lat": _center_lat,
		"radius_scale": _radius_scale,
	}

func set_view_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	_center_lon = float(state.get("center_lon", _center_lon))
	_center_lat = clampf(float(state.get("center_lat", _center_lat)), -MAX_CENTER_LAT, MAX_CENTER_LAT)
	_radius_scale = clampf(float(state.get("radius_scale", _radius_scale)), MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	_zoom_target = _radius_scale
	_animating = false
	_spin_lon = 0.0
	_spin_lat = 0.0
	_stop_animating()
	_redraw_view()

## Zoom steps ease to their target instead of jumping, which reads as the
## globe being pulled towards the player.
func zoom_in() -> void:
	_zoom_target = clampf(_zoom_target * ZOOM_STEP, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	_start_animating()

func zoom_out() -> void:
	_zoom_target = clampf(_zoom_target / ZOOM_STEP, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	_start_animating()

## Give the globe the locations to pin: array of dictionaries with
## id/name/lat/lon (plus any extra state the marker colour needs).
func set_locations(locations: Array) -> void:
	_locations = locations
	_redraw_markers()

func set_selected(location_id: String) -> void:
	_selected_id = location_id
	_redraw_markers()

## Fly the globe round to a location (used when the list selects it). The
## move takes CENTER_DURATION seconds and always goes the shortest way.
func look_at_location(location_id: String) -> void:
	for loc in _locations:
		if str(loc.get("id", "")) == location_id:
			_center_on(float(loc.get("lon", 0.0)), float(loc.get("lat", 0.0)))
			return

## Animate the centre to a lon/lat, picking the nearest copy of the longitude
## so the globe never unwinds the long way round.
func _center_on(lon: float, lat: float) -> void:
	while lon - _center_lon > 180.0:
		lon -= 360.0
	while lon - _center_lon < -180.0:
		lon += 360.0
	_anim_from_lon = _center_lon
	_anim_from_lat = _center_lat
	_anim_to_lon = lon
	_anim_to_lat = clampf(lat, -MAX_CENTER_LAT, MAX_CENTER_LAT)
	_anim_time = 0.0
	_animating = true
	_spin_lon = 0.0
	_spin_lat = 0.0
	_start_animating()

## Smoothly unwrap a longitude so animations can cross the antimeridian
## without a jump.
static func _unwrap_lon(lon: float, reference: float) -> float:
	while lon - reference > 180.0:
		lon -= 360.0
	while lon - reference < -180.0:
		lon += 360.0
	return lon

## Start the animation loop. The clock restarts with it, so the first frame
## after the globe has been sitting idle is not charged for the idle time.
func _start_animating() -> void:
	_frame_usec = -1
	set_process(true)

## Nothing left to animate: stop the loop, so an idle globe costs nothing.
func _stop_animating() -> void:
	_frame_usec = -1
	set_process(false)

## How many seconds this frame is worth. The engine's own delta, unless the
## simulation behind the map is frozen: the Club tab opens the World Map over a
## course it has paused, a paused simulation runs on `Engine.time_scale` 0, and
## a frozen clock hands out frames worth nothing at all. The globe is an
## interface rather than part of the simulation, so it keeps its own clock and
## turns at the same rate whatever the course behind it is doing.
func _frame_seconds(delta: float) -> float:
	if delta > 0.0:
		_frame_usec = -1
		return delta
	var now := Time.get_ticks_usec()
	var seconds := 0.0
	if _frame_usec > 0:
		seconds = float(now - _frame_usec) * 1e-6
	_frame_usec = now
	return maxf(seconds, 0.0)

## Flies the centring animation, settles the zoom and keeps a flicked globe
## spinning until it slows down.
func _process(delta: float) -> void:
	var step := _frame_seconds(delta)
	var changed := false

	if _animating:
		_anim_time = minf(_anim_time + step / CENTER_DURATION, 1.0)
		# Ease out cubic: quick off the mark, gentle on arrival.
		var t := 1.0 - pow(1.0 - _anim_time, 3.0)
		_center_lon = lerpf(_anim_from_lon, _anim_to_lon, t)
		_center_lat = lerpf(_anim_from_lat, _anim_to_lat, t)
		if _anim_time >= 1.0:
			_animating = false
			# Keep the centre in a sane range after a move that wrapped.
			_center_lon = _unwrap_lon(_center_lon, 0.0)
		changed = true

	if absf(_radius_scale - _zoom_target) > 0.0005:
		_radius_scale = lerpf(_radius_scale, _zoom_target, minf(1.0, ZOOM_SETTLE_RATE * step))
		if absf(_radius_scale - _zoom_target) <= 0.0005:
			_radius_scale = _zoom_target
		changed = true

	# Inertia, but never while the player is still holding the globe.
	if not _dragging and (absf(_spin_lon) > 0.05 or absf(_spin_lat) > 0.05):
		_center_lon = fposmod(_center_lon + _spin_lon * step, 360.0)
		_center_lat = clampf(_center_lat + _spin_lat * step, -MAX_CENTER_LAT, MAX_CENTER_LAT)
		var decay := pow(SPIN_DECAY, step)
		_spin_lon *= decay
		_spin_lat *= decay
		changed = true

	if not changed:
		_spin_lon = 0.0
		_spin_lat = 0.0
		_stop_animating()
		return
	_redraw_view()

## ── Projection ───────────────────────────────────────────────────────────

## Orthographic projection of a lon/lat point for a globe centred on
## (center_lon, center_lat). Returns a Vector3 where x/y are unit-sphere screen
## offsets (y grows up) and z is visibility (> 0 = facing the viewer).
static func project_point(lon_deg: float, lat_deg: float, center_lon: float, center_lat: float) -> Vector3:
	var phi := deg_to_rad(lat_deg)
	var lam := deg_to_rad(lon_deg - center_lon)
	var phi0 := deg_to_rad(center_lat)
	var z := sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(lam)
	var x := cos(phi) * sin(lam)
	var y := cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(lam)
	return Vector3(x, y, z)

## Rasterise the low-resolution land-dot fallback from the same coastline
## geometry as the planet mask. Sampling the mask avoids testing thousands of
## detailed coastline vertices for each display dot.
static func build_land_points() -> Array:
	var points: Array = []
	var columns := int(roundf(360.0 / LAND_STEP_DEG))
	var rows := int(roundf(180.0 / LAND_STEP_DEG))
	var mask := build_land_mask(columns, rows)
	for y in range(rows):
		var lat := 90.0 - (float(y) + 0.5) * LAND_STEP_DEG
		for x in range(columns):
			if mask.get_pixel(x, y).r > 0.5:
				var lon := -180.0 + (float(x) + 0.5) * LAND_STEP_DEG
				points.append(Vector2(lon, lat))
	return points

## Test whether a geographic point is land. Polygon holes (notably the Caspian
## Sea) are excluded, and multiple land shapes are treated as a union.
static func is_land(lon: float, lat: float) -> bool:
	var wrapped_lon := fposmod(lon + 180.0, 360.0) - 180.0
	var point := Vector2(wrapped_lon, lat)
	for polygon: Array in _get_polygons():
		if not Geometry2D.is_point_in_polygon(point, polygon[0]):
			continue
		var in_hole := false
		for hole_index in range(1, polygon.size()):
			if Geometry2D.is_point_in_polygon(point, polygon[hole_index]):
				in_hole = true
				break
		if not in_hole:
			return true
	return false

## ── Baked land mask (what the planet shader samples) ─────────────────────

## Rasterise the Natural Earth rings into an equirectangular coverage mask,
## white on land, which is what `shaders/globe_planet.gdshader` samples. Outer
## coastlines and lake rings share the scanline parity fill, so the water holes
## stay empty. A row's land spans are written in bulk with `fill_rect()`
## and only the two ends of each span are written pixel by pixel (with their
## analytic coverage, so coastlines get a soft texel instead of a staircase).
## Edges are bucketed only into the rows they can cross; this avoids testing
## every mask texel against thousands of polygon edges.
static func build_land_mask(width: int = MASK_WIDTH, height: int = MASK_HEIGHT) -> Image:
	var mask := Image.create(width, height, false, Image.FORMAT_R8)
	mask.fill(Color(0, 0, 0, 1))
	var coords: PackedFloat32Array = _get_mask_edges()["coords"]
	var deg_per_row := 180.0 / float(height)
	var to_x := float(width) / 360.0
	var crossings_by_row: Array[Array] = []
	for _row in range(height):
		crossings_by_row.append([])

	# Bucket each coastline edge only into the rows it can cross. The old
	# per-row polygon scan re-tested long shorelines hundreds of times; this
	# keeps the detailed 1:50m geometry quick to bake at the full mask size.
	@warning_ignore("integer_division")
	var edge_count := coords.size() / 4
	for edge in range(edge_count):
		var ax := coords[edge * 4]
		var ay := coords[edge * 4 + 1]
		var bx := coords[edge * 4 + 2]
		var by := coords[edge * 4 + 3]
		var low := minf(ay, by)
		var high := maxf(ay, by)
		var first_row := maxi(0, floori((90.0 - high) / deg_per_row - 0.5) + 1)
		var last_row := mini(height - 1, floori((90.0 - low) / deg_per_row - 0.5))
		for y in range(first_row, last_row + 1):
			var lat := 90.0 - (float(y) + 0.5) * deg_per_row
			if not ((ay <= lat and by > lat) or (by <= lat and ay > lat)):
				continue
			var t := (lat - ay) / (by - ay)
			var lon := ax + t * (bx - ax)
			crossings_by_row[y].append(lon)

	_mask_bake_count += 1
	for y in range(height):
		var crossings := crossings_by_row[y]
		crossings.sort()
		var i := 0
		while i + 1 < crossings.size():
			# Longitude where this scanline enters (odd crossing) or leaves
			# (even crossing) the land. Pixel centres sit at half integers.
			var x_start := (float(crossings[i]) + 180.0) * to_x - 0.5
			var x_end := (float(crossings[i + 1]) + 180.0) * to_x - 0.5
			i += 2
			if x_end <= 0.0 or x_start >= float(width - 1):
				continue
			x_start = maxf(x_start, 0.0)
			x_end = minf(x_end, float(width - 1))
			var first := int(x_start)
			var last := int(x_end)
			if first == last:
				_write_mask_coverage(mask, first, y, x_end - x_start)
				continue
			_write_mask_coverage(mask, first, y, 1.0 - (x_start - float(first)))
			_write_mask_coverage(mask, last, y, x_end - float(last))
			if last - first > 1:
				mask.fill_rect(Rect2i(first + 1, y, last - first - 1, 1), Color(1, 1, 1, 1))
	return mask

static func _write_mask_coverage(mask: Image, x: int, y: int, coverage: float) -> void:
	if x < 0 or x >= mask.get_width():
		return
	var value := int(roundf(clampf(coverage, 0.0, 1.0) * 255.0))
	if value > 0:
		mask.set_pixel(x, y, Color8(value, value, value, 255))

## The mask as a texture, baked once per run and shared by every GlobeMap.
## The mipmaps keep the coastline from shimmering when the globe is small.
static func get_land_mask_texture() -> ImageTexture:
	if _mask_texture == null:
		var mask := build_land_mask()
		mask.generate_mipmaps()
		_mask_texture = ImageTexture.create_from_image(mask)
	return _mask_texture

## UV of a lon/lat point in the mask: (0, 0) is the north-west corner. The
## longitude wraps, so any value works — and the mask width is therefore not
## needed; the latitude is kept half a texel inside the polar rows so the
## top/bottom edge is never sampled.
static func mask_uv(lon_deg: float, lat_deg: float, _width: int = MASK_WIDTH, height: int = MASK_HEIGHT) -> Vector2:
	var half_row := 0.5 / float(height)
	return Vector2(
		fposmod((lon_deg + 180.0) / 360.0, 1.0),
		clampf(0.5 - lat_deg / 180.0, half_row, 1.0 - half_row))

## Land coverage (0..1) of the mask at a lon/lat, read back for tests and the
## preview harness.
static func mask_coverage(mask: Image, lon_deg: float, lat_deg: float) -> float:
	var uv := mask_uv(lon_deg, lat_deg, mask.get_width(), mask.get_height())
	var x := clampi(int(uv.x * float(mask.get_width())), 0, mask.get_width() - 1)
	var y := clampi(int(uv.y * float(mask.get_height())), 0, mask.get_height() - 1)
	return mask.get_pixel(x, y).r

## How many times the mask rasteriser has run (tests use this to verify the
## full-resolution texture cache bakes just once).
static func mask_bake_count() -> int:
	return _mask_bake_count

## Reset the shared mask cache (tests only).
static func clear_mask_cache() -> void:
	_mask_texture = null
	_mask_bake_count = 0

## All Natural Earth rings as one flat array of non-horizontal edges — four
## floats [ax, ay, bx, by] per edge. Horizontal edges can never cross a
## scanline, so they are omitted from the cached edge list.
static func _get_mask_edges() -> Dictionary:
	if _mask_edges.is_empty():
		var coords := PackedFloat32Array()
		for polygon: Array in _get_polygons():
			for ring: PackedVector2Array in polygon:
				var count := ring.size()
				for i in range(count):
					var from: Vector2 = ring[i]
					var to: Vector2 = ring[(i + 1) % count]
					if absf(from.y - to.y) < 0.000001:
						continue
					coords.append(from.x)
					coords.append(from.y)
					coords.append(to.x)
					coords.append(to.y)
		_mask_edges = {"coords": coords}
	return _mask_edges

## Load and convert the bundled Natural Earth polygons once. Each polygon is
## an array of rings: the first ring is its coast, any remaining rings are holes.
static func _get_polygons() -> Array:
	if _land_polygon_cache_loaded:
		return _land_polygon_cache
	_land_polygon_cache_loaded = true

	var file := FileAccess.open(LAND_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open globe land data at %s" % LAND_DATA_PATH)
		return _land_polygon_cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Globe land data is not a JSON object: %s" % LAND_DATA_PATH)
		return _land_polygon_cache
	var source_polygons: Variant = parsed.get("polygons", [])
	if not source_polygons is Array:
		push_error("Globe land data has no polygon array: %s" % LAND_DATA_PATH)
		return _land_polygon_cache

	for source_polygon: Variant in source_polygons:
		if not source_polygon is Array or source_polygon.is_empty():
			continue
		var rings: Array = []
		var valid_polygon := true
		for source_ring: Variant in source_polygon:
			if not source_ring is Array or source_ring.size() < 4:
				valid_polygon = false
				break
			var points := PackedVector2Array()
			for source_point: Variant in source_ring:
				if not source_point is Array or source_point.size() < 2:
					valid_polygon = false
					break
				points.append(Vector2(float(source_point[0]), float(source_point[1])))
			if not valid_polygon:
				break
			rings.append(points)
		if valid_polygon and not rings.is_empty():
			_land_polygon_cache.append(rings)
	return _land_polygon_cache

func _project(lon: float, lat: float) -> Vector3:
	return project_point(lon, lat, _center_lon, _center_lat)

func _sphere_radius() -> float:
	return minf(size.x, size.y) * 0.5 * 0.92 * _radius_scale

func _sphere_center() -> Vector2:
	return size * 0.5

func _screen_for(v: Vector3, center: Vector2, radius: float) -> Vector2:
	return center + Vector2(v.x, -v.y) * radius

## ── Drawing ──────────────────────────────────────────────────────────────

## The land-dot fallback (LandStyle.DOTS). The planet styles (PLANET and
## PIXEL) are drawn by the shader on their own layer, so there is nothing to
## do here.
func _draw() -> void:
	if _land_style == LandStyle.PLANET or _land_style == LandStyle.PIXEL:
		return
	var center := _sphere_center()
	var radius := _sphere_radius()
	if radius <= 4.0:
		return
	if _land_points.is_empty():
		_land_points = build_land_points()

	# Ocean sphere with a darker rim so it reads as a ball, not a disc.
	draw_circle(center, radius + 3.0, OCEAN_RIM)
	draw_circle(center, radius, OCEAN_COLOR)
	draw_circle(center - Vector2(0.0, radius * 0.12), radius * 0.92, Color(OCEAN_COLOR.lightened(0.04)))

	_draw_graticule(center, radius)
	_draw_land(center, radius)
	draw_arc(center, radius, 0.0, TAU, 128, SHORE_COLOR, 1.5, true)

func _draw_graticule(center: Vector2, radius: float) -> void:
	# Meridians every 30 degrees.
	for lon in range(-180, 180, 30):
		var segment: PackedVector2Array = []
		for lat_step in range(-90, 91, 5):
			var v := _project(float(lon), float(lat_step))
			if v.z > 0.0:
				segment.append(_screen_for(v, center, radius))
			elif segment.size() > 1:
				draw_polyline(segment, GRATICULE_COLOR, 1.0, true)
				segment = []
			else:
				segment = []
		if segment.size() > 1:
			draw_polyline(segment, GRATICULE_COLOR, 1.0, true)

	# Parallels every 30 degrees.
	for lat in range(-60, 90, 30):
		var segment: PackedVector2Array = []
		for lon_step in range(-180, 181, 5):
			var v := _project(float(lon_step), float(lat))
			if v.z > 0.0:
				segment.append(_screen_for(v, center, radius))
			elif segment.size() > 1:
				draw_polyline(segment, GRATICULE_COLOR, 1.0, true)
				segment = []
			else:
				segment = []
		if segment.size() > 1:
			draw_polyline(segment, GRATICULE_COLOR, 1.0, true)

func _draw_land(center: Vector2, radius: float) -> void:
	var dot_radius := maxf(radius * deg_to_rad(LAND_STEP_DEG) * 0.68, 1.5)
	for point in _land_points:
		var v := _project(point.x, point.y)
		if v.z <= 0.0:
			continue
		var pos := _screen_for(v, center, radius)
		var lit := clampf(v.z * 1.6, 0.0, 1.0)
		var color := LAND_SHADE_COLOR.lerp(LAND_COLOR, lit)
		draw_circle(pos, dot_radius * (0.75 + 0.25 * lit), color)

## The marker layer's repaint. Positions are recorded here, in the globe's own
## coordinates (the layer covers the globe exactly), which is what the hover
## test, the click test and the layout harness read back.
func _draw_marker_layer() -> void:
	var canvas: CanvasItem = _marker_layer
	_marker_positions.clear()
	var center := _sphere_center()
	var radius := _sphere_radius()
	if radius <= 4.0:
		return
	_draw_markers(canvas, center, radius)

func _draw_markers(canvas: CanvasItem, center: Vector2, radius: float) -> void:
	var placed: Array = []
	for loc in _locations:
		var v := _project(float(loc.get("lon", 0.0)), float(loc.get("lat", 0.0)))
		if v.z <= 0.02:
			continue
		var pos := _screen_for(v, center, radius)
		# Nudge markers apart so neighbours (Hawaii/Oahu, Scotland/Ireland)
		# stay individually clickable and readable.
		for other in placed:
			if pos.distance_to(other) < MARKER_HIT_RADIUS * 1.6:
				var push: Vector2 = pos - other
				if push.length() < 0.01:
					push = Vector2.RIGHT
				pos = other + push.normalized() * MARKER_HIT_RADIUS * 1.6
		placed.append(pos)

		var id := str(loc.get("id", ""))
		_marker_positions[id] = pos
		var selected: bool = id == _selected_id
		var hovered := id == _hover_id

		if _land_style == LandStyle.PIXEL:
			_draw_pixel_pin(canvas, pos, loc, selected)
		else:
			_draw_smooth_marker(canvas, pos, loc, selected)
		if selected or hovered:
			if _land_style == LandStyle.PIXEL:
				_draw_marker_label_pixel(canvas, pos, str(loc.get("name", id)), selected)
			else:
				_draw_marker_label(canvas, pos, str(loc.get("name", id)), selected)

func _draw_smooth_marker(canvas: CanvasItem, pos: Vector2, loc: Dictionary, selected: bool) -> void:
	var marker_radius := MARKER_RADIUS + (2.0 if selected else 0.0)
	canvas.draw_circle(pos + Vector2(1.5, 2.0), marker_radius + 1.0, Color(0.0, 0.0, 0.0, 0.35))
	canvas.draw_circle(pos, marker_radius, marker_color(loc))
	canvas.draw_arc(pos, marker_radius, 0.0, TAU, 24, Color(0.05, 0.08, 0.05, 0.9), 1.5, true)
	if selected:
		canvas.draw_arc(pos, marker_radius + 5.0, 0.0, TAU, 32, UIConstants.COLOR_GOLD, 2.0, true)

## A marker for the PIXEL globe: the same 16x16 pin sprite the screens use
## (PixelIcon.Kind.PIN), tip on the destination, with chunky corner brackets
## in gold when it is the selected site. The sprite is nearest-filtered and
## placed on whole pixels, so the pin's cells stay crisp against the
## quantised planet.
func _draw_pixel_pin(canvas: CanvasItem, pos: Vector2, loc: Dictionary, selected: bool) -> void:
	var tint := marker_color(loc)
	var side := PixelIcon.snapped_side(PIN_SPRITE_SIDE)
	var tip := (pos - Vector2(0.0, PIN_SPRITE_RAISE)).round()
	# The sprite's pin tip sits at 13.5/16 of its height.
	var base := tip - Vector2(side * 0.5, side * 0.84)
	# A two-block cast shadow grounds the pin on the globe.
	canvas.draw_rect(Rect2(tip + Vector2(2.0, 1.0), Vector2(side * 0.4, 2.0)),
		Color(0.0, 0.0, 0.0, 0.30))
	canvas.draw_texture(PixelIcon.texture(PixelIcon.Kind.PIN, side, tint), base)
	if selected:
		_draw_pin_brackets(canvas, tip, side)

## Gold corner brackets around the selected pin — the atlas's way of saying
## "you are here" without covering the pin itself.
func _draw_pin_brackets(canvas: CanvasItem, tip: Vector2, side: float) -> void:
	var gold := UIConstants.COLOR_GOLD
	var frame := Rect2(tip - Vector2(side * 0.62, side * 0.96), Vector2(side * 1.24, side * 1.05))
	var arm := maxf(2.0, side * 0.22)
	var bar := 2.0
	# Each corner is an L of two bars, snapped to whole pixels.
	for corner in [frame.position, Vector2(frame.end.x, frame.position.y),
			Vector2(frame.position.x, frame.end.y), frame.end]:
		var sx: float = 1.0 if corner.x == frame.position.x else -1.0
		var sy: float = 1.0 if corner.y == frame.position.y else -1.0
		var h := Rect2(Vector2.ZERO, Vector2(arm, bar))
		var v := Rect2(Vector2.ZERO, Vector2(bar, arm))
		h.position = Vector2(corner.x, corner.y) if sx > 0.0 else Vector2(corner.x - arm, corner.y)
		v.position = Vector2(corner.x, corner.y) if sy > 0.0 else Vector2(corner.x, corner.y - arm)
		if sx < 0.0:
			v.position.x = corner.x - bar
		if sy < 0.0:
			h.position.y = corner.y - bar
		canvas.draw_rect(h, gold)
		canvas.draw_rect(v, gold)

## The destination's name as a pixel tag: a notched ink frame with an accent
## trim (gold for the selected site), Pixelify type on top. The frame is the
## same recipe as the screens' cards: outline, trim, fill — no rounded
## corners, nothing anti-aliased.
func _draw_marker_label_pixel(canvas: CanvasItem, pos: Vector2, text: String, selected: bool) -> void:
	var font_size := 13
	var accent := UIConstants.COLOR_GOLD if selected else Color(0.62, 0.72, 0.62, 0.85)
	var text_size := MARKER_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(6.0, 4.0)
	var rect_size := (text_size + pad * 2.0).round()
	var top := (pos + Vector2(10.0, -rect_size.y * 0.5)).round()
	_draw_pixel_tag(canvas, Rect2(top, rect_size), accent,
		Color(0.035, 0.075, 0.06, 0.92), Color("0b1a14"))
	canvas.draw_string(MARKER_FONT, top + Vector2(pad.x, pad.y + MARKER_FONT.get_ascent(font_size)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		UIConstants.COLOR_GOLD if selected else UIConstants.COLOR_TEXT)

## A small notched pixel frame: two overlapping rects per layer make the
## 1-pixel corner cut, outside in — ink outline, accent trim, dark fill.
func _draw_pixel_tag(canvas: CanvasItem, rect: Rect2, accent: Color, fill: Color, ink: Color) -> void:
	for layer in [[rect, ink], [rect.grow(-1.0), accent], [rect.grow(-2.0), fill]]:
		var layer_rect: Rect2 = layer[0]
		var color: Color = layer[1]
		canvas.draw_rect(Rect2(layer_rect.position + Vector2(1.0, 0.0),
			layer_rect.size - Vector2(2.0, 0.0)), color)
		canvas.draw_rect(Rect2(layer_rect.position + Vector2(0.0, 1.0),
			layer_rect.size - Vector2(0.0, 2.0)), color)

func _draw_marker_label(canvas: CanvasItem, pos: Vector2, text: String, selected: bool) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 13
	var text_pos := pos + Vector2(11.0, 4.0)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(5.0, 3.0)
	var rect_pos := text_pos - pad
	var rect_size := text_size + pad * 2.0
	canvas.draw_rect(Rect2(rect_pos, rect_size), Color(0.04, 0.07, 0.05, 0.82), true)
	var border := UIConstants.COLOR_GOLD if selected else Color(0.6, 0.7, 0.6, 0.8)
	canvas.draw_rect(Rect2(rect_pos, rect_size), border, false, 1.0)
	canvas.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIConstants.COLOR_TEXT)

## Marker colour: active location gold, owned green, affordable white,
## out-of-reach grey.
static func marker_color(loc: Dictionary) -> Color:
	if bool(loc.get("active", false)):
		return UIConstants.COLOR_GOLD
	if bool(loc.get("owned", false)):
		return Color("7fd07f")
	if bool(loc.get("affordable", true)):
		return Color("f0f4ea")
	return Color("7d8a80")

## ── Interaction ──────────────────────────────────────────────────────────

## Handle raw screen touches here instead of letting the game's camera gesture
## adapter claim them. On phones, one finger drags the atlas round, two fingers
## pinch it open or closed to zoom, and a tap on a pin selects a destination.
## Other screen gestures still flow to the shared TouchInput adapter as usual.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var local_pos := _screen_to_local(event.position)
	if event.pressed:
		if not _contains(local_pos):
			return
		# A dialogue or panel drawn over the globe owns the touch, even when
		# the finger is inside the globe's circle: the globe must not eat the
		# tap meant for a button on top of it.
		if not TouchInput.owns_native_touch(self, event.position):
			return
		_touches[event.index] = local_pos
		if _touches.size() == 1:
			# A fresh gesture: one finger owns the spin and nothing is pinched.
			_multi_touch_used = false
			_begin_spin(event.index, local_pos)
		else:
			# A second finger joins. This is a pinch from here on, so it must
			# never end as a tap on whichever pin is under a lifted finger.
			_multi_touch_used = true
			_begin_pinch()
		get_viewport().set_input_as_handled()
		return

	if not _touches.has(event.index):
		return
	if event.canceled:
		# The OS interrupted the gesture (a call, an app switch): drop every
		# finger, and never let the interruption read as a tap on a pin.
		_cancel_touches()
		get_viewport().set_input_as_handled()
		return
	# A release carries the finger's final position, which can be beyond the
	# last drag event; fold it in before judging what the gesture was.
	_touches[event.index] = local_pos
	_touches.erase(event.index)
	get_viewport().set_input_as_handled()

	if _touches.is_empty():
		var was_multi := _multi_touch_used
		_touch_index = -1
		_dragging = false
		_pinch_start_span = 0.0
		_multi_touch_used = false
		if was_multi:
			# Releasing a pinch neither picks a marker nor coasts the globe.
			_spin_lon = 0.0
			_spin_lat = 0.0
			return
		if _drag_distance < TAP_SLOP:
			_spin_lon = 0.0
			_spin_lat = 0.0
			var hit := _marker_at(local_pos)
			if not hit.is_empty():
				location_clicked.emit(hit)
		else:
			# Let go mid-flick: the globe keeps the spin and coasts.
			_start_animating()
		return

	if _touches.size() >= 2:
		# A third finger joined, or a second one came down after a release:
		# carry on pinching with the fingers that are still on the globe.
		_begin_pinch()
		return

	# One finger is left after a pinch. It can carry on spinning, but the
	# gesture stays a pinch so its release is not read as a tap.
	var remaining_index: int = int(_touches.keys()[0])
	_begin_spin(remaining_index, Vector2(_touches[remaining_index]))

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var local_pos := _screen_to_local(event.position)
	_touches[event.index] = local_pos
	if _touches.size() >= 2:
		_update_pinch()
		get_viewport().set_input_as_handled()
		return
	if event.index != _touch_index:
		return
	var delta := local_pos - _drag_last
	_drag_last = local_pos
	_drag_distance += delta.length()
	var radius := maxf(_sphere_radius(), 1.0)
	_rotate_by_screen_offset(delta)
	_remember_flick(_spin_from_velocity(event.velocity, radius))
	_redraw_view()
	get_viewport().set_input_as_handled()

## Forget every finger of an interrupted gesture. The globe stays on the view
## it had reached, with no spin carrying on afterwards.
func _cancel_touches() -> void:
	_touches.clear()
	_touch_index = -1
	_dragging = false
	_pinch_start_span = 0.0
	_multi_touch_used = false
	_spin_lon = 0.0
	_spin_lat = 0.0

## Start (or resume) a one-finger spin at `local_pos`. A finger left over from
## a pinch picks the spin up where it is, so the globe never jumps.
func _begin_spin(index: int, local_pos: Vector2) -> void:
	_touch_index = index
	_take_hold()
	_dragging = true
	_drag_start = local_pos
	_drag_last = local_pos
	_drag_distance = 0.0

## Take the reference span and midpoint a pinch is measured from. The globe
## stops coasting so the fingers work on the view that is on screen.
func _begin_pinch() -> void:
	_take_hold()
	_dragging = false
	_pinch_start_span = _touch_span()
	_pinch_mid = _touch_midpoint()
	_pinch_radius = maxf(_sphere_radius(), 1.0)
	_pinch_start_scale = _radius_scale
	# Drop the eased target a wheel notch may still be settling towards: the
	# hand owns the zoom from here, and letting go must not resume that ease.
	_zoom_target = _radius_scale
	_pinch_start_lon = _center_lon
	_pinch_start_lat = _center_lat

## The fingers moved: the span between them zooms the globe, and their shared
## midpoint spins it, so a two-finger gesture can bring a coast into view as
## well as open it up.
func _update_pinch() -> void:
	var span := _touch_span()
	var mid := _touch_midpoint()
	if _pinch_start_span > 1.0 and span > 1.0:
		_pinch_to(_pinch_start_scale * span / _pinch_start_span)
	# Both fingers moving together spin the globe about the view the pinch
	# began from, so a pinch-and-drag turns it as one steady movement.
	var midpoint_delta := mid - _pinch_mid
	if _pinch_radius > 0.0 and midpoint_delta.length() > 0.0:
		_center_lon = fposmod(_pinch_start_lon - midpoint_delta.x * (190.0 / _pinch_radius), 360.0)
		_center_lat = clampf(_pinch_start_lat + midpoint_delta.y * (170.0 / _pinch_radius),
			-MAX_CENTER_LAT, MAX_CENTER_LAT)
	_redraw_view()

## Show the globe at `radius_scale`. A pinch tracks the hand directly rather
## than easing, and the target follows the hand, so the eased zoom the buttons
## and the wheel use never fights the gesture.
func _pinch_to(radius_scale: float) -> void:
	radius_scale = clampf(radius_scale, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	_zoom_target = radius_scale
	if is_equal_approx(radius_scale, _radius_scale):
		return
	_radius_scale = radius_scale

## Turn the globe as if a pointer had been dragged `delta` screen pixels.
func _rotate_by_screen_offset(delta: Vector2) -> void:
	if delta == Vector2.ZERO:
		return
	var sphere_radius := maxf(_sphere_radius(), 1.0)
	_center_lon = fposmod(_center_lon - delta.x * (190.0 / sphere_radius), 360.0)
	_center_lat = clampf(_center_lat + delta.y * (170.0 / sphere_radius), -MAX_CENTER_LAT, MAX_CENTER_LAT)

## The two fingers a pinch is measured between, nearest first.
func _touch_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for index in _touches:
		positions.append(Vector2(_touches[index]))
		if positions.size() == 2:
			break
	return positions

func _touch_span() -> float:
	var positions := _touch_positions()
	if positions.size() < 2:
		return 0.0
	return positions[0].distance_to(positions[1])

func _touch_midpoint() -> Vector2:
	var positions := _touch_positions()
	if positions.size() < 2:
		return Vector2.ZERO
	return (positions[0] + positions[1]) * 0.5

func _contains(local_pos: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(local_pos)

func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

## The player has taken hold of the globe: whatever it was doing — flying to a
## destination or coasting off a flick — is theirs to overrule from here. A
## fly-to left in flight would otherwise write its own centre over every frame
## of the drag, and the globe would refuse to follow the hand on it.
func _take_hold() -> void:
	_animating = false
	_spin_lon = 0.0
	_spin_lat = 0.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_take_hold()
			_dragging = true
			_drag_start = event.position
			_drag_last = event.position
			_drag_distance = 0.0
		else:
			_dragging = false
			if _drag_distance < 6.0:
				_spin_lon = 0.0
				_spin_lat = 0.0
				var hit := _marker_at(event.position)
				if not hit.is_empty():
					location_clicked.emit(hit)
			else:
				_start_animating()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		zoom_in()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		zoom_out()
		accept_event()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging:
		var delta := event.position - _drag_last
		_drag_last = event.position
		_drag_distance += delta.length()
		var radius := maxf(_sphere_radius(), 1.0)
		_center_lon = fposmod(_center_lon - delta.x * (190.0 / radius), 360.0)
		_center_lat = clampf(_center_lat + delta.y * (170.0 / radius), -MAX_CENTER_LAT, MAX_CENTER_LAT)
		_remember_flick(_spin_from_velocity(event.velocity, radius))
		_redraw_view()
		return
	var hit := _marker_at(event.position)
	if hit != _hover_id:
		_hover_id = hit
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hit.is_empty() else Control.CURSOR_ARROW
		_redraw_markers()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not _hover_id.is_empty():
		_hover_id = ""
		_redraw_markers()

## The spin a drag of this speed leaves behind, in degrees per second. The
## direction matches the drag: pulling right spins the globe eastwards.
func _spin_from_velocity(velocity: Vector2, radius: float) -> Vector2:
	return Vector2(-velocity.x * (190.0 / radius), velocity.y * (170.0 / radius))

## Remember the newest flick, capped so a violent throw cannot spin the globe
## into a blur.
func _remember_flick(spin: Vector2) -> void:
	_spin_lon = clampf(spin.x, -MAX_SPIN_DEG_PER_SEC, MAX_SPIN_DEG_PER_SEC)
	_spin_lat = clampf(spin.y, -MAX_SPIN_DEG_PER_SEC, MAX_SPIN_DEG_PER_SEC)

## The marker under a screen position (uses the positions from the last draw).
func _marker_at(screen_pos: Vector2) -> String:
	for id in _marker_positions:
		if screen_pos.distance_to(_marker_positions[id]) <= MARKER_HIT_RADIUS:
			return id
	return ""

## Screen position of a marker from the last draw (empty Vector2 when hidden).
func get_marker_position(location_id: String) -> Vector2:
	return _marker_positions.get(location_id, Vector2.ZERO)

func has_marker_on_screen(location_id: String) -> bool:
	return _marker_positions.has(location_id)
