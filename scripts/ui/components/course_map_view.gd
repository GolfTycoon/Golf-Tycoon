extends Control
class_name CourseMapView
## CourseMapView - The course drawn as one isometric diamond, in four modes.
##
## The whole 128x128 grid is projected through the course's own GridProjection -
## so the map is a true isometric diamond, and it turns with the course when the
## view is rotated with Q - and the terrain is sampled into a texture that is laid
## over the diamond (the same trick the corner minimap uses, at a size that fills
## a whole screen).
##
## On top of that sits one overlay per mode:
##
##  * LAND    - the six-by-six parcel grid: owned land, land for sale and its
##              price tag, and land that is out of reach (locked, or not touching
##              the property).
##  * ROUTING - the holes in play order: a badge with each hole's number, its tee
##              and green, and the walk from each green to the next tee painted
##              green, amber or red by length (see HoleRouting).
##  * AURA    - where golfers have been happy and unhappy (see CourseAura),
##              green through amber to red, over the holes they were playing.
##  * STAFF   - the ground each employee covers, in their job's colour, plus the
##              owner's own ground in gold.
##
## The control owns no rules: it reports what was pressed (`map_pressed`) with the
## tile and whatever was hit, and the screen decides what that means - the same
## split as the rest of the UI, so a pending "move this staff area" and a plain
## selection are one code path.

signal map_pressed(tile: Vector2i, hit: Dictionary)
signal hover_changed(text: String)
signal hover_cleared()
## Zoom or pan changed, so the screen can refresh a zoom readout.
signal view_changed()

enum Mode { LAND, ROUTING, AURA, STAFF }

# =============================================================================
# LOOK
# =============================================================================

## Margin between the diamond and the edge of the control.
const PAD := 10.0
## Texture side, in pixels, for the terrain image laid over the diamond. The
## screen switches to the compact side when the map is drawn small.
const TEXTURE_SIDE := 512
const COMPACT_TEXTURE_SIDE := 320

const MIN_ZOOM := 1.0
const MAX_ZOOM := 3.2
const ZOOM_STEP := 1.25
## Pointer travel (px) past which a press is a drag of the map, not a click.
const CLICK_SLOP := 6.0
## How close (px) a click has to be to a hole marker or a staff area to pick it.
const PICK_RADIUS := 20.0

## Property lines, buying and locked land.
## The ground is the point of this map: it is a colour key of the course, tile
## for tile, and every mode is drawn *over* it rather than instead of it. So the
## washes below are only ever deep enough to make a mode's own marks read, never
## deep enough to hide what a tile is. Parcels, above all: a 20 x 20 tile parcel
## covered by an even wash reads as one flat rectangle and takes the whole tile
## mosaic with it, so the state of a parcel is carried by its outline, its price
## label and the panel instead of by a colour field.
const LAND_OWNED_FILL := Color(0.36, 0.78, 0.45, 0.05)
const LAND_OWNED_LINE := Color(0.95, 0.82, 0.42, 0.95)
const LAND_BUY_FILL := Color(0.98, 0.80, 0.30, 0.12)
const LAND_BUY_LINE := Color(1.0, 0.90, 0.50, 0.95)
const LAND_LOCKED_FILL := Color(0.06, 0.10, 0.08, 0.05)
const LAND_LOCKED_LINE := Color(0.62, 0.64, 0.56, 0.55)

## How dark the course is laid under each mode's own colours. Land mode lays
## nothing over it at all: the parcel outlines and prices are enough, and the
## ground is what the player came to look at. The aura is the one exception - 
## there the map *is* the mood, so the ground underneath steps back for it.
const SCRIM_LAND := 0.0
const SCRIM_OVERLAY := 0.03
const SCRIM_AURA := 0.20

## The terrain key in the legend: up to this many types, and only those covering
## at least this much of the course. The key names the colours; the map's panel
## has the numbers.
const TERRAIN_KEY_LIMIT: int = 5
const TERRAIN_KEY_MIN_SHARE: float = 0.005

## The tile grid, drawn once a tile is this many pixels across on screen (and
## reaching its full strength by TILE_GRID_FULL_PX). It is what makes the ground
## read as a map of tiles rather than as a painting: at the whole-course view a
## tile is around ten pixels across, and a hairline every ten pixels is the
## difference between "a green diamond" and "tiles".
const TILE_GRID_MIN_PX := 5.0
const TILE_GRID_FULL_PX := 13.0
const TILE_GRID_COLOR := Color(0.04, 0.09, 0.06, 0.22)
## Parcel quality, matching the Land panel: standard, premium, elite.
const TIER_COLORS: Array[Color] = [Color("7cc47a"), Color("d8b44a"), Color("bcd6ee")]

## The holes, their route and their markers.
const ROUTE_COLOR := Color(0.95, 0.92, 0.82, 0.75)
const TEE_COLOR := Color(0.97, 0.88, 0.55)
const GREEN_COLOR := Color(0.55, 0.95, 0.55)
const CUP_COLOR := Color(0.98, 0.98, 0.94)
const CLOSED_COLOR := Color(0.62, 0.64, 0.60, 0.75)

## The aura: happy, mixed and unhappy cells.
const AURA_HAPPY := Color(0.30, 0.92, 0.42)
const AURA_MIXED := Color(0.97, 0.85, 0.32)
const AURA_UNHAPPY := Color(0.98, 0.31, 0.28)

## Staff by job, in StaffManager.Job order, plus the owner's own ground.
const JOB_COLORS: Array[Color] = [
	Color("6fd08a"),  # Groundskeepers
	Color("6cb8e6"),  # Greeters
	Color("e8a15a"),  # Marshals
	Color("e07fb8"),  # Drinks vendors
]
const OWNER_COLOR := Color("f0cf7a")

const HIGHLIGHT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const HINT_COLOR := Color(0.95, 0.92, 0.82)
## The property's own edge, drawn round the whole diamond.
const COLOR_EDGE := Color(0.82, 0.86, 0.78, 0.65)

const LABEL_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

# =============================================================================
# STATE
# =============================================================================

var mode: int = Mode.LAND
## What is picked right now: {"kind": "parcel"|"hole"|"aura"|"staff", "value": ...}.
## Empty when nothing is.
var selection: Dictionary = {}
## An action waiting for a tile: {"kind": "move_staff"|"hire_staff", "value": ...}.
## While one is set, the next press is reported as a plain tile press and the map
## draws a ghost of what is about to be placed.
var pending: Dictionary = {}

var _terrain_grid: TerrainGrid = null
var _texture_side: int = TEXTURE_SIDE
var _texture_revision: int = -1
var _texture_dirty: bool = true
var _palette: Dictionary = {}
var _palette_theme: int = -999
var _map_texture: ImageTexture = null
## The terrain cover of the course, cached against the terrain revision.
var _cover: Array = []
var _cover_revision: int = -1

var _zoom: float = 1.0
var _pan := Vector2.ZERO
var _drag_active: bool = false
var _drag_moved: bool = false
var _drag_start := Vector2.ZERO
var _drag_from_pan := Vector2.ZERO
var _hover_tile := Vector2i(-1, -1)
var _hover_hit: Dictionary = {}
## Fingers on the map, keyed by touch index (position in this control's space).
var _touches: Dictionary = {}
var _touch_dragged: bool = false
## The pinch, measured against the view it started from: the span between the
## fingers, the midpoint, and the zoom and pan at that moment. A reference
## keeps the gesture steady when the two fingers' events interleave (their
## span appears to wobble between reports) and returns exactly to the view it
## started from when the fingers come back together.
var _pinch_start_span: float = 0.0
var _pinch_mid: Vector2 = Vector2.ZERO
var _pinch_start_zoom: float = 1.0
var _pinch_start_pan: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The map answers touch directly (tap to pick, drag to pan, pinch to zoom) so
	# the shared gesture adapter leaves it alone.
	add_to_group("native_touch_input")
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bind()
	if _terrain_grid:
		_terrain_grid.tile_changed.connect(_on_tile_changed)
		_terrain_grid.view_rotated.connect(_on_view_rotated)
	if EventBus.has_signal("theme_changed"):
		EventBus.theme_changed.connect(_on_theme_changed)
	EventBus.holes_reordered.connect(_on_holes_reordered)
	EventBus.hole_created.connect(_on_hole_changed_created)
	EventBus.hole_deleted.connect(_on_hole_changed)
	EventBus.hole_updated.connect(_on_hole_changed)
	resized.connect(_on_resized)

## Point the view at the live course. Called by the screen, and again whenever a
## new game or a loaded save swaps the world out from under it.
func _bind() -> void:
	_terrain_grid = GameManager.terrain_grid
	if GameManager.land_manager and not GameManager.land_manager.land_boundary_changed.is_connected(_on_land_changed):
		GameManager.land_manager.land_boundary_changed.connect(_on_land_changed)
	if GameManager.staff_manager and not GameManager.staff_manager.staff_changed.is_connected(_on_staff_changed):
		GameManager.staff_manager.staff_changed.connect(_on_staff_changed)

func _exit_tree() -> void:
	if _terrain_grid:
		if _terrain_grid.tile_changed.is_connected(_on_tile_changed):
			_terrain_grid.tile_changed.disconnect(_on_tile_changed)
		if _terrain_grid.view_rotated.is_connected(_on_view_rotated):
			_terrain_grid.view_rotated.disconnect(_on_view_rotated)
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)
	if EventBus.holes_reordered.is_connected(_on_holes_reordered):
		EventBus.holes_reordered.disconnect(_on_holes_reordered)
	if EventBus.hole_created.is_connected(_on_hole_changed_created):
		EventBus.hole_created.disconnect(_on_hole_changed_created)
	if EventBus.hole_deleted.is_connected(_on_hole_changed):
		EventBus.hole_deleted.disconnect(_on_hole_changed)
	if EventBus.hole_updated.is_connected(_on_hole_changed):
		EventBus.hole_updated.disconnect(_on_hole_changed)
	if GameManager.land_manager and GameManager.land_manager.land_boundary_changed.is_connected(_on_land_changed):
		GameManager.land_manager.land_boundary_changed.disconnect(_on_land_changed)
	if GameManager.staff_manager and GameManager.staff_manager.staff_changed.is_connected(_on_staff_changed):
		GameManager.staff_manager.staff_changed.disconnect(_on_staff_changed)

# =============================================================================
# PUBLIC API
# =============================================================================

func set_mode(new_mode: int) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	selection = {}
	queue_redraw()

func set_selection(kind: String, value: Variant) -> void:
	selection = {"kind": kind, "value": value}
	queue_redraw()

func clear_selection() -> void:
	selection = {}
	queue_redraw()

func set_pending(action: Dictionary) -> void:
	pending = action
	queue_redraw()

func clear_pending() -> void:
	pending = {}
	queue_redraw()

## Compactly drawn map (phone and small tablets): a smaller terrain texture.
func set_compact_texture(compact: bool) -> void:
	var side := COMPACT_TEXTURE_SIDE if compact else TEXTURE_SIDE
	if side == _texture_side:
		return
	_texture_side = side
	_texture_dirty = true
	queue_redraw()

func get_zoom() -> float:
	return _zoom

## Frame the whole course again.
func fit() -> void:
	_zoom = MIN_ZOOM
	_pan = Vector2.ZERO
	view_changed.emit()
	queue_redraw()

## Zoom about the middle of the control: what the + / - buttons and keys do.
func zoom_by(factor: float) -> void:
	_zoom_at(size * 0.5, factor)

## Centre the map on a point in grid space, at a zoom worth looking at. Used when
## a row in a side panel is picked, so picking a parcel, a hole, a hotspot or a
## member of staff brings the ground it is about into view.
func focus_on_grid_point(point: Vector2, zoom: float = 1.7) -> void:
	if _terrain_grid == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var bounds := _map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	_zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	var room := size - Vector2(PAD, PAD) * 2.0
	var base := maxf(minf(room.x / bounds.size.x, room.y / bounds.size.y), 0.0001)
	var drawn := base * _zoom
	var projected := _terrain_grid.projection.project(point) - bounds.position
	_pan = size * 0.5 - projected * drawn - (size - bounds.size * drawn) * 0.5
	_clamp_pan()
	view_changed.emit()
	queue_redraw()

## Centre on one tile.
func focus_on_tile(tile: Vector2i) -> void:
	focus_on_grid_point(Vector2(tile) + Vector2(0.5, 0.5))

## Redraw from the live course (a save was loaded, a new game started, terrain
## changed under us).
func refresh() -> void:
	_texture_dirty = true
	_bind()
	queue_redraw()

## The mode's colour key, drawn inside the map so the colours on the map and the
## words for them always come from one place. The ground the course is made of is
## listed after the mode's own colours: the map is a colour key of the tiles, and
## a key is only any use if it says what the colours are called.
func legend_entries() -> Array:
	var entries: Array = _mode_legend()
	if mode == Mode.AURA:
		# The aura lays the mood over the ground and dims it; the tiles are not
		# what that map is about, so its key stays about the comments.
		return entries
	entries.append_array(terrain_key())
	return entries

func _mode_legend() -> Array:
	match mode:
		Mode.LAND:
			return [
				{"color": TIER_COLORS[LandManager.TIER_STANDARD], "label": "Owned"},
				{"color": LAND_BUY_LINE, "label": "For sale"},
				{"color": LAND_LOCKED_LINE, "label": "Out of reach"},
			]
		Mode.ROUTING:
			return [
				{"color": HoleRouting.grade_color(HoleRouting.Grade.SHORT), "label": "Short walk"},
				{"color": HoleRouting.grade_color(HoleRouting.Grade.MODERATE), "label": "Moderate walk"},
				{"color": HoleRouting.grade_color(HoleRouting.Grade.LONG), "label": "Long walk"},
			]
		Mode.AURA:
			return [
				{"color": AURA_HAPPY, "label": "Happy comments"},
				{"color": AURA_MIXED, "label": "Mixed"},
				{"color": AURA_UNHAPPY, "label": "Unhappy comments"},
			]
		_:
			return [
				{"color": JOB_COLORS[StaffManager.Job.GROUNDSKEEPER], "label": "Groundskeepers"},
				{"color": JOB_COLORS[StaffManager.Job.GREETER], "label": "Greeters"},
				{"color": JOB_COLORS[StaffManager.Job.MARSHAL], "label": "Marshals"},
				{"color": JOB_COLORS[StaffManager.Job.DRINKS_VENDOR], "label": "Drinks vendors"},
				{"color": OWNER_COLOR, "label": "Owner's ground"},
			]

## How much of the course each terrain type covers: the tiles actually painted
## on this course, most of the ground first. Cached by terrain revision, so the
## map only walks the grid when the ground changes.
func terrain_cover() -> Array:
	if _terrain_grid == null:
		return []
	if _cover_revision == _terrain_grid.terrain_revision and not _cover.is_empty():
		return _cover
	var tally: Dictionary = {}
	var total: int = 0
	for x in _terrain_grid.grid_width:
		for y in _terrain_grid.grid_height:
			var terrain_type: int = _terrain_grid.get_tile(Vector2i(x, y))
			tally[terrain_type] = int(tally.get(terrain_type, 0)) + 1
			total += 1
	var ranked: Array = []
	for terrain_type in tally:
		ranked.append({
			"type": int(terrain_type),
			"label": TerrainTypes.get_type_name(int(terrain_type)),
			"color": CourseSurface.map_color(int(terrain_type)),
			"tiles": int(tally[terrain_type]),
			"share": float(tally[terrain_type]) / float(maxi(1, total)),
		})
	ranked.sort_custom(func(a, b):
		if int(a["tiles"]) != int(b["tiles"]):
			return int(a["tiles"]) > int(b["tiles"])
		return int(a["type"]) < int(b["type"]))
	_cover = ranked
	_cover_revision = _terrain_grid.terrain_revision
	return _cover

## The ground, in the legend's own shape: a chip and a name per terrain type,
## biggest patch of ground first. Anything that barely shows on the map (under
## TERRAIN_KEY_MIN_SHARE of it) is left to the panel's own read of the course.
func terrain_key() -> Array:
	var entries: Array = []
	for entry in terrain_cover():
		if float(entry["share"]) < TERRAIN_KEY_MIN_SHARE:
			continue
		entries.append({"color": entry["color"], "label": str(entry["label"])})
		if entries.size() >= TERRAIN_KEY_LIMIT:
			break
	return entries

# =============================================================================
# MAPPING (grid <-> control space)
# =============================================================================

func _map_bounds() -> Rect2:
	if _terrain_grid == null:
		return Rect2()
	return _terrain_grid.projection.world_bounds()

## Scale and offset from projection space into this control, with the diamond
## centred in the control and the current zoom and pan applied.
func _transform() -> Dictionary:
	var bounds := _map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {"origin": Vector2.ZERO, "scale": 1.0}
	var room := size - Vector2(PAD, PAD) * 2.0
	var drawn := minf(room.x / bounds.size.x, room.y / bounds.size.y)
	drawn = maxf(drawn, 0.0001) * _zoom
	return {"origin": (size - bounds.size * drawn) * 0.5 + _pan, "scale": drawn}

func _local_of_grid(grid_point: Vector2) -> Vector2:
	var transform := _transform()
	if _terrain_grid == null:
		return Vector2.ZERO
	return (_terrain_grid.projection.project(grid_point) - _map_bounds().position) * float(transform["scale"]) \
		+ Vector2(transform["origin"])

func _grid_of_local(local: Vector2) -> Vector2:
	var transform := _transform()
	if _terrain_grid == null:
		return Vector2.ZERO
	var projected: Vector2 = (local - Vector2(transform["origin"])) / float(transform["scale"]) \
		+ _map_bounds().position
	return _terrain_grid.projection.unproject(projected)

func _tile_at(local: Vector2) -> Vector2i:
	var point := _grid_of_local(local)
	return Vector2i(floori(point.x), floori(point.y))

func _valid_tile(tile: Vector2i) -> bool:
	return _terrain_grid != null and _terrain_grid.is_valid_position(tile)

## The four corners of a grid-space rectangle, in control space.
func _polygon_of_rect(from: Vector2, to: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		_local_of_grid(from),
		_local_of_grid(Vector2(to.x, from.y)),
		_local_of_grid(to),
		_local_of_grid(Vector2(from.x, to.y)),
	])

## A circle in grid space, drawn as a ring: each sampled point is projected, so
## the ring stretches with the map the way the on-course staff overlay's does.
func _ring_of_circle(center: Vector2, radius: float, segments: int = 28) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := (float(i) / float(segments)) * TAU
		points.append(_local_of_grid(center + Vector2(cos(angle), sin(angle)) * radius))
	return points

# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	if _terrain_grid == null or _terrain_grid.grid_width <= 0:
		return
	_ensure_texture()
	_draw_diamond()
	_draw_tile_grid()
	match mode:
		Mode.LAND:
			_draw_land()
		Mode.ROUTING:
			_draw_routing()
		Mode.AURA:
			_draw_aura()
		_:
			_draw_staff()
	_draw_legend()
	_draw_pending_hint()

## How dark the course is laid under the current mode's own colours.
func _scrim() -> float:
	match mode:
		Mode.AURA:
			return SCRIM_AURA
		Mode.LAND:
			return SCRIM_LAND
		_:
			return SCRIM_OVERLAY

## How big one tile is drawn, in pixels. The grid, the tile-sized labels and
## the aura cells all want to know this, and it is the honest measure: what
## matters is how much room a tile has on screen, not the zoom factor that got it
## there (a phone-sized map at 3x has smaller tiles than a desktop one at 1x).
func tile_pixels() -> Vector2:
	if _terrain_grid == null:
		return Vector2.ZERO
	return _terrain_grid.projection.tile_size * float(_transform()["scale"])

## The tile grid, drawn while the tiles are big enough to be worth counting.
## Every mode draws over it, and it is what makes the ground read as a map of
## tiles rather than as a painting.
func _draw_tile_grid() -> void:
	if _terrain_grid == null:
		return
	var tile := tile_pixels()
	if tile.x < TILE_GRID_MIN_PX or tile.y <= 0.0:
		return
	var strength := clampf((tile.x - TILE_GRID_MIN_PX) / (TILE_GRID_FULL_PX - TILE_GRID_MIN_PX), 0.25, 1.0)
	var color := Color(TILE_GRID_COLOR.r, TILE_GRID_COLOR.g, TILE_GRID_COLOR.b, TILE_GRID_COLOR.a * strength)
	var width: int = _terrain_grid.grid_width
	var height: int = _terrain_grid.grid_height
	for x in range(1, width):
		draw_line(_local_of_grid(Vector2(x, 0)), _local_of_grid(Vector2(x, height)), color, 1.0)
	for y in range(1, height):
		draw_line(_local_of_grid(Vector2(0, y)), _local_of_grid(Vector2(width, y)), color, 1.0)

## The texture's UVs cover the tile grid, not the world-space pixel bounds.
## Use the same grid corners as the tile grid and the mode overlays so each
## terrain colour lands on the tile it represents.
func _terrain_polygon() -> PackedVector2Array:
	return _polygon_of_rect(Vector2.ZERO, Vector2(_terrain_grid.grid_width, _terrain_grid.grid_height))

func _draw_diamond() -> void:
	var outline := _terrain_polygon()
	if _map_texture:
		draw_polygon(outline, PackedColorArray([Color.WHITE]),
			PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]), _map_texture)
	else:
		draw_colored_polygon(outline, Color(0.16, 0.24, 0.18))
	# Every mode works over a slightly dimmed course so its own colours read
	# without the ground losing its own (see SCRIM_*). Land mode takes none.
	var scrim := _scrim()
	if scrim > 0.0:
		draw_colored_polygon(outline, Color(0.02, 0.07, 0.05, scrim))
	var edge := outline.duplicate()
	edge.append(outline[0])
	draw_polyline(edge, COLOR_EDGE, 1.5, true)

# --- Terrain texture ---------------------------------------------------------

func _ensure_texture() -> void:
	if not _texture_dirty and _texture_revision == _terrain_grid.terrain_revision \
			and _palette_theme == GameManager.current_theme:
		return
	_build_palette()
	var side := _texture_side
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var grid_width: int = maxi(1, _terrain_grid.grid_width)
	var grid_height: int = maxi(1, _terrain_grid.grid_height)
	for px in side:
		var gx := mini(grid_width - 1, int(float(px) / float(side) * float(grid_width)))
		for py in side:
			var gy := mini(grid_height - 1, int(float(py) / float(side) * float(grid_height)))
			var tile := Vector2i(gx, gy)
			var color: Color = _palette.get(_terrain_grid.get_tile(tile), Color(0.3, 0.3, 0.3))
			if _terrain_grid.has_walking_path(tile):
				color = _palette.get("path", color)
			image.set_pixel(px, py, color)
	_map_texture = ImageTexture.create_from_image(image)
	_texture_revision = _terrain_grid.terrain_revision
	_palette_theme = GameManager.current_theme
	_texture_dirty = false

## The trail laid on a tile with a walking path, where a theme names none.
const PATH_COLOR := Color("c9bc98")

## The map's colours: exactly the ones the course surface is painted with and
## the minimap draws with, tile for tile, so the three can never disagree about
## what a tile looks like (see CourseSurface.map_color). Keeping the lookup in
## one place also means a theme change - or a colourblind mode - repaints this
## map the same way it repaints the course.
func _build_palette() -> void:
	_palette = {}
	for terrain_type in TerrainTypes.Type.values():
		_palette[terrain_type] = CourseSurface.map_color(terrain_type)
	_palette["path"] = CourseTheme.get_terrain_colors(GameManager.current_theme).get("path", PATH_COLOR)

# --- Land mode ---------------------------------------------------------------

func _draw_land() -> void:
	var land: LandManager = GameManager.land_manager
	if land == null:
		return
	for px in land.PARCEL_GRID_COLS:
		for py in land.PARCEL_GRID_ROWS:
			var parcel := Vector2i(px, py)
			var rect := land.parcel_to_tile_rect(parcel)
			var polygon := _polygon_of_rect(Vector2(rect.position), Vector2(rect.position + rect.size))
			var in_location := land.is_parcel_in_location(parcel)
			var selected: bool = selection.get("kind", "") == "parcel" \
				and selection.get("value", Vector2i(-1, -1)) == parcel
			if land.owned_parcels.has(parcel):
				draw_colored_polygon(polygon, LAND_OWNED_FILL)
				_draw_outline(polygon, LAND_OWNED_LINE if not selected else HIGHLIGHT_COLOR,
					2.4 if selected else 1.2)
				continue
			if land.is_parcel_purchasable(parcel):
				draw_colored_polygon(polygon, LAND_BUY_FILL)
				_draw_outline(polygon, HIGHLIGHT_COLOR if selected else LAND_BUY_LINE,
					2.6 if selected else 1.6)
				_draw_parcel_price(land, parcel, polygon)
				continue
			# Out of reach: land that is not for sale yet, and land outside the
			# block this location came with.
			draw_colored_polygon(polygon, LAND_LOCKED_FILL)
			if in_location:
				_draw_outline(polygon, LAND_LOCKED_LINE, 1.0)

func _draw_parcel_price(land: LandManager, parcel: Vector2i, polygon: PackedVector2Array) -> void:
	var centre := _polygon_centroid(polygon)
	var tier := land.get_parcel_tier(parcel)
	var cost := land.get_parcel_cost(parcel)
	var label := "$%s" % _short_money(cost)
	var font_size := _label_size(11, 8)
	var color: Color = TIER_COLORS[tier] if tier < TIER_COLORS.size() else Color.WHITE
	draw_string(BODY_FONT, centre + Vector2(-30.0, float(font_size) * 0.35), label,
		HORIZONTAL_ALIGNMENT_CENTER, 60.0, font_size, color)
	if tier != LandManager.TIER_STANDARD:
		var tier_label := LandManager.get_tier_name(tier).to_upper()
		draw_string(LABEL_FONT, centre + Vector2(-30.0, -float(font_size) * 0.9), tier_label,
			HORIZONTAL_ALIGNMENT_CENTER, 60.0, _label_size(9, 7), color)

# --- Routing mode ------------------------------------------------------------

func _draw_routing() -> void:
	var course = GameManager.current_course
	if course == null or course.holes.is_empty():
		_draw_empty_note("No holes yet — paint a tee box and a green, then press H to open the first hole.")
		return
	var holes: Array = course.holes
	# The walks between holes first, so the holes sit on top of them.
	for i in range(holes.size() - 1):
		var from_green: Vector2i = holes[i].green_position
		var to_tee: Vector2i = holes[i + 1].tee_position
		var grade := HoleRouting.grade_for(HoleRouting.leg_tiles(holes, i))
		var leg_color := HoleRouting.grade_color(grade)
		leg_color.a = 0.85
		_draw_dashed_leg(_local_of_grid(Vector2(from_green) + Vector2(0.5, 0.5)),
			_local_of_grid(Vector2(to_tee) + Vector2(0.5, 0.5)), leg_color)
	for i in holes.size():
		_draw_hole_marker(holes[i])

func _draw_hole_marker(hole: GameManager.HoleData) -> void:
	var open: bool = hole.is_open
	var tee := _local_of_grid(Vector2(hole.tee_position) + Vector2(0.5, 0.5))
	var green := _local_of_grid(Vector2(hole.green_position) + Vector2(0.5, 0.5))
	var selected: bool = selection.get("kind", "") == "hole" \
		and int(selection.get("value", -1)) == int(hole.hole_number)
	var line_color := ROUTE_COLOR if open else CLOSED_COLOR
	if selected:
		line_color = HIGHLIGHT_COLOR
	draw_line(tee, green, line_color, 2.6 if selected else 1.8, true)
	# Tee: a small square. Green: a ring with the cup at its heart.
	var radius := _marker_radius()
	var tee_color := TEE_COLOR if open else CLOSED_COLOR
	draw_rect(Rect2(tee - Vector2(radius, radius), Vector2(radius, radius) * 2.0), tee_color)
	draw_circle(green, radius * 1.15, GREEN_COLOR if open else CLOSED_COLOR)
	draw_circle(green, radius * 0.42, CUP_COLOR if open else CLOSED_COLOR)
	# The number badge sits between the two ends, as a chip with the hole's
	# number and, when the map is big enough, its par.
	var mid := (tee + green) * 0.5
	var badge_radius := radius * 1.55
	draw_circle(mid, badge_radius, Color(0.06, 0.13, 0.10, 0.92))
	draw_arc(mid, badge_radius, 0.0, TAU, 20, line_color, 1.4, true)
	var number := str(hole.hole_number)
	var font_size := _label_size(13, 10)
	draw_string(LABEL_FONT, mid + Vector2(-badge_radius, float(font_size) * 0.36), number,
		HORIZONTAL_ALIGNMENT_CENTER, badge_radius * 2.0, font_size,
		HIGHLIGHT_COLOR if selected else Color(0.95, 0.93, 0.85))
	if not _is_compact():
		draw_string(BODY_FONT, mid + Vector2(-badge_radius, badge_radius + float(font_size)),
			"P%d · %dyds" % [hole.par, hole.distance_yards], HORIZONTAL_ALIGNMENT_CENTER,
			badge_radius * 2.0, _label_size(10, 8), Color(0.90, 0.90, 0.80))

func _draw_dashed_leg(from: Vector2, to: Vector2, color: Color) -> void:
	var direction := to - from
	var length := direction.length()
	if length < 1.0:
		return
	var step := direction / length
	var dash := 9.0
	var gap := 6.0
	var travelled := 0.0
	while travelled < length:
		var dash_end := minf(travelled + dash, length)
		draw_line(from + step * travelled, from + step * dash_end, color, 2.4, true)
		travelled = dash_end + gap

# --- Aura mode ---------------------------------------------------------------

func _draw_aura() -> void:
	var aura: CourseAura = GameManager.course_aura
	if aura == null or aura.samples.is_empty():
		_draw_empty_note("No comments yet — golfers speak up as they play.")
		return
	_draw_holes_reference()
	var cells := aura.cell_counts()
	for cell in cells:
		var counts: Dictionary = cells[cell]
		if int(counts["total"]) <= 0:
			continue
		var color := aura_color(float(counts["score"]))
		var strength := clampf(float(counts["total"]) / 8.0, 0.25, 0.85)
		color.a = strength
		var from := Vector2(cell) * float(CourseAura.CELL_SIZE)
		var to := from + Vector2(CourseAura.CELL_SIZE, CourseAura.CELL_SIZE)
		var polygon := _polygon_of_rect(from, to)
		draw_colored_polygon(polygon, color)
		_draw_outline(polygon, Color(color.r, color.g, color.b, 0.85), 1.2)
		if selection.get("kind", "") == "aura" and selection.get("value", Vector2i(-2, -2)) == cell:
			_draw_outline(polygon, HIGHLIGHT_COLOR, 2.6)
	# The three loudest happy and unhappy cells get a ring, so the panel's
	# hotspots are findable on the map.
	_draw_hotspot_rings(aura, "positive")
	_draw_hotspot_rings(aura, "negative")

func _draw_hotspot_rings(aura: CourseAura, sentiment: String) -> void:
	for hotspot in aura.hotspots(sentiment, 3):
		var cell: Vector2i = hotspot["cell"]
		var centre := CourseAura.cell_center(cell)
		var ring := _ring_of_circle(centre, float(CourseAura.CELL_SIZE) * 0.92)
		var color := AURA_HAPPY if sentiment == "positive" else AURA_UNHAPPY
		color.a = 0.9
		var closed := ring.duplicate()
		closed.append(ring[0])
		draw_polyline(closed, color, 2.0, true)
		draw_string(LABEL_FONT, _local_of_grid(centre) + Vector2(-40.0, -float(_label_size(11, 9))),
			("%d happy" if sentiment == "positive" else "%d unhappy") % int(hotspot["weight"]),
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, _label_size(11, 9), color)

## Faint tee and green marks, so the aura can be read against the holes.
func _draw_holes_reference() -> void:
	var course = GameManager.current_course
	if course == null:
		return
	for hole in course.holes:
		var tee := _local_of_grid(Vector2(hole.tee_position) + Vector2(0.5, 0.5))
		var green := _local_of_grid(Vector2(hole.green_position) + Vector2(0.5, 0.5))
		var faint := Color(0.95, 0.95, 0.9, 0.35)
		draw_circle(tee, _marker_radius() * 0.6, faint)
		draw_arc(green, _marker_radius() * 0.9, 0.0, TAU, 16, faint, 1.2, true)

static func aura_color(score: float) -> Color:
	if score < 0.0:
		return AURA_UNHAPPY.lerp(AURA_MIXED, score + 1.0)
	return AURA_MIXED.lerp(AURA_HAPPY, score)

# --- Staff mode --------------------------------------------------------------

func _draw_staff() -> void:
	var manager: StaffManager = GameManager.staff_manager
	_draw_owner_ground()
	if manager == null or manager.hired_staff.is_empty():
		_draw_empty_note("No staff hired — hire from the panel below.")
		return
	for index in manager.hired_staff.size():
		_draw_staff_area(manager, index)

func _draw_staff_area(manager: StaffManager, index: int) -> void:
	var record: Dictionary = manager.hired_staff[index]
	var centre: Vector2i = record.get("area_center", Vector2i.ZERO)
	var radius: float = float(record.get("area_radius", 6.0))
	var job := manager.get_job_for_type(int(record.type))
	var color: Color = JOB_COLORS[job] if job >= 0 and job < JOB_COLORS.size() else Color.WHITE
	var selected: bool = selection.get("kind", "") == "staff" and int(selection.get("value", -1)) == index
	var ring := _ring_of_circle(Vector2(centre) + Vector2(0.5, 0.5), radius)
	if ring.size() < 3:
		return
	var fill := color
	fill.a = 0.26 if selected else 0.13
	draw_colored_polygon(ring, fill)
	var closed := ring.duplicate()
	closed.append(ring[0])
	var outline := color
	outline.a = 1.0 if selected else 0.75
	draw_polyline(closed, outline, 2.6 if selected else 1.6, true)
	var centre_local := _local_of_grid(Vector2(centre) + Vector2(0.5, 0.5))
	var dot := _marker_radius() * (1.25 if selected else 1.0)
	draw_circle(centre_local, dot, Color(0.06, 0.12, 0.10, 0.92))
	draw_circle(centre_local, dot * 0.62, color)
	if _label_size(12, 9) >= 11:
		var staff_name: String = str(record.get("name", "Staff"))
		draw_string(BODY_FONT, centre_local + Vector2(-40.0, -dot - 3.0), staff_name,
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, _label_size(10, 8), color)

## The ground the owner's own golfer works, in the owner's gold (matches the
## on-course StaffAreaOverlay).
func _draw_owner_ground() -> void:
	var owner_manager = GameManager.player_golfer_manager
	if owner_manager == null or owner_manager.area_center.x < 0:
		return
	var ring := _ring_of_circle(Vector2(owner_manager.area_center) + Vector2(0.5, 0.5), owner_manager.area_radius)
	if ring.size() < 3:
		return
	draw_colored_polygon(ring, Color(OWNER_COLOR.r, OWNER_COLOR.g, OWNER_COLOR.b, 0.14))
	var closed := ring.duplicate()
	closed.append(ring[0])
	draw_polyline(closed, Color(OWNER_COLOR.r, OWNER_COLOR.g, OWNER_COLOR.b, 0.85), 1.8, true)

# --- Shared decoration -------------------------------------------------------

func _draw_outline(polygon: PackedVector2Array, color: Color, width: float) -> void:
	if polygon.size() < 3:
		return
	var closed := polygon.duplicate()
	closed.append(polygon[0])
	draw_polyline(closed, color, width, true)

static func _polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var total := Vector2.ZERO
	for point in polygon:
		total += point
	return total / float(maxi(1, polygon.size()))

## The legend: a row of colour chips with their words, along the bottom of the
## map. Long keys wrap onto a second row on a narrow map.
func _draw_legend() -> void:
	var entries := legend_entries()
	if entries.is_empty():
		return
	var font_size := _label_size(11, 9)
	var chip := float(font_size) * 0.85
	var margin := 10.0
	var x := margin
	var y := size.y - margin - chip
	var max_x := size.x - margin
	for entry in entries:
		var label: String = str(entry["label"])
		var width := BODY_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var item_width := chip + 5.0 + width + 12.0
		if x + item_width > max_x:
			x = margin
			y -= chip + float(font_size) * 0.7
		draw_rect(Rect2(Vector2(x, y), Vector2(chip, chip)), entry["color"])
		draw_rect(Rect2(Vector2(x, y), Vector2(chip, chip)), Color(0, 0, 0, 0.55), false, 1.0)
		draw_string(BODY_FONT, Vector2(x + chip + 5.0, y + chip - 1.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, HINT_COLOR)
		x += item_width

## While an action waits for a tile (hire here, move this area here), say so on
## the map itself and show the ground that is about to be handed over.
func _draw_pending_hint() -> void:
	if pending.is_empty():
		return
	var kind: String = str(pending.get("kind", ""))
	var text := ""
	var radius := 6.0
	var color := Color(1.0, 0.92, 0.55, 0.95)
	if kind == "hire_staff":
		var staff_type := int(pending.get("value", -1))
		var data: Dictionary = GameManager.staff_manager.STAFF_DATA.get(staff_type, {}) \
			if GameManager.staff_manager else {}
		text = "Tap a spot to base %s there" % str(data.get("name", "the new hire"))
		radius = float(data.get("area_radius", 6.0))
	elif kind == "move_staff":
		text = "Tap a spot for the new staff area"
		var index := int(pending.get("value", -1))
		if GameManager.staff_manager and index >= 0 and index < GameManager.staff_manager.hired_staff.size():
			radius = float(GameManager.staff_manager.hired_staff[index].get("area_radius", 6.0))
	if _valid_tile(_hover_tile):
		var ring := _ring_of_circle(Vector2(_hover_tile) + Vector2(0.5, 0.5), radius)
		if ring.size() >= 3:
			draw_colored_polygon(ring, Color(color.r, color.g, color.b, 0.20))
			var closed := ring.duplicate()
			closed.append(ring[0])
			draw_polyline(closed, color, 2.0, true)
	if text.is_empty():
		return
	var font_size := _label_size(12, 10)
	var width := BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var rect := Rect2(Vector2(10.0, 8.0), Vector2(width + 16.0, float(font_size) + 12.0))
	draw_rect(rect, Color(0.05, 0.11, 0.09, 0.92))
	draw_rect(rect, color, false, 1.5)
	draw_string(BODY_FONT, rect.position + Vector2(8.0, float(font_size) + 3.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.96, 0.85))

func _draw_empty_note(text: String) -> void:
	var font_size := _label_size(13, 11)
	var width := BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(BODY_FONT, Vector2((size.x - width) * 0.5, size.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, HINT_COLOR)

## Text sizes scale with the diamond's own size, so a phone map is not covered in
## desktop-sized labels.
func _marker_radius() -> float:
	return clampf(minf(size.x, size.y) * 0.012, 2.2, 5.5)

func _label_size(desktop: int, compact: int) -> int:
	return compact if _is_compact() else desktop

## True when the map is drawn small (phone, narrow rail): labels and legend text
## shrink, and the second line of a hole badge is left off.
func _is_compact() -> bool:
	return minf(size.x, size.y) < 420.0

static func _short_money(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (float(amount) / 1000000.0)
	if amount >= 1000:
		return "%dK" % int(roundf(float(amount) / 1000.0)) if amount < 100000 else \
			"%.1fK" % (float(amount) / 1000.0)
	return str(amount)

# =============================================================================
# INPUT
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(button.position, ZOOM_STEP)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(button.position, 1.0 / ZOOM_STEP)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_drag_active = true
				_drag_moved = false
				_drag_start = button.position
				_drag_from_pan = _pan
			else:
				if _drag_active and not _drag_moved:
					_press_at(button.position)
				_drag_active = false
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _drag_active:
			var travel := motion.position - _drag_start
			if travel.length() > CLICK_SLOP:
				_drag_moved = true
			if _drag_moved:
				_pan = _drag_from_pan + travel
				_clamp_pan()
				view_changed.emit()
				queue_redraw()
		else:
			_hover_at(motion.position)
		accept_event()

## Touch is handled directly (the view is in the "native_touch_input" group, so
## the shared gesture adapter leaves it alone): one finger taps and pans, two
## fingers pinch open or closed to zoom (and, moved together, pan the map).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and not _is_inside(touch.position):
			return
		if not touch.pressed and not _touches.has(touch.index):
			return
		var local := _screen_to_local(touch.position)
		if touch.canceled:
			# An interrupted gesture must not pick the tile under a finger.
			_touches.clear()
			_touch_dragged = false
			_pinch_start_span = 0.0
			get_viewport().set_input_as_handled()
			return
		if touch.pressed:
			_touches[touch.index] = local
			if _touches.size() == 1:
				_begin_touch_pan(local)
			else:
				_begin_touch_pinch()
		else:
			var was_single := _touches.size() == 1
			# A release carries the finger's final position, so a pinch that
			# ended with a drag event still gets its last movement.
			_touches[touch.index] = local
			_touches.erase(touch.index)
			if _touches.is_empty():
				if was_single and not _touch_dragged and _is_inside(touch.position):
					_press_at(local)
				_pinch_start_span = 0.0
			elif _touches.size() == 1:
				# One finger left after a pinch: carry on panning from where
				# it is, rather than jumping by the whole pinch travel.
				var remaining_index: int = int(_touches.keys()[0])
				_begin_touch_pan(Vector2(_touches[remaining_index]))
			else:
				_begin_touch_pinch()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return
		var local_drag := _screen_to_local(drag.position)
		_touches[drag.index] = local_drag
		if _touches.size() >= 2:
			_update_touch_pinch()
		elif _touches.size() == 1:
			_update_touch_pan(local_drag)
		get_viewport().set_input_as_handled()

## A single finger takes the map's pan from where it lands. A finger left over
## from a pinch starts a fresh pan, and the gesture stays a drag, so lifting it
## never picks the tile under it.
func _begin_touch_pan(local: Vector2) -> void:
	_touch_dragged = false if _pinch_start_span <= 0.0 else true
	_drag_start = local
	_drag_from_pan = _pan

func _update_touch_pan(local: Vector2) -> void:
	var travel := local - _drag_start
	if travel.length() > CLICK_SLOP:
		_touch_dragged = true
	if _touch_dragged:
		_pan = _drag_from_pan + travel
		_clamp_pan()
		view_changed.emit()
		queue_redraw()

## Two fingers (or more) on the map: measure the span they start at and the
## point between them. The pinch begins as a drag, so no tile is picked when
## the fingers come up.
func _begin_touch_pinch() -> void:
	_pinch_start_span = _touch_span()
	_pinch_mid = _touch_midpoint()
	_pinch_start_zoom = _zoom
	_pinch_start_pan = _pan
	_touch_dragged = true

func _update_touch_pinch() -> void:
	var span := _touch_span()
	var mid := _touch_midpoint()
	if _pinch_start_span > 1.0 and span > 1.0:
		_pinch_to(_pinch_start_zoom * span / _pinch_start_span)
	# The fingers' shared midpoint carries the map with them, so a pinch can
	# also be a two-finger pan.
	var midpoint_delta := mid - _pinch_mid
	if midpoint_delta.length() > 0.0:
		_pan += midpoint_delta
		_clamp_pan()
		view_changed.emit()
		queue_redraw()

## Zoom the gesture to `target`, always built from the view the pinch started
## from rather than from the previous event: the ground under the fingers stays
## put, and a span that wobbles as the two fingers are reported returns to the
## zoom it came from.
func _pinch_to(target: float) -> void:
	target = clampf(target, MIN_ZOOM, MAX_ZOOM)
	var factor := target / _pinch_start_zoom
	_zoom = _pinch_start_zoom
	_pan = _pinch_start_pan
	if is_equal_approx(factor, 1.0):
		view_changed.emit()
		queue_redraw()
		return
	_zoom_at(_pinch_mid, factor)
	_zoom = target
	view_changed.emit()
	queue_redraw()

## The two fingers a pinch is measured between, nearest first.
func _touch_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for index in _touches:
		points.append(Vector2(_touches[index]))
		if points.size() == 2:
			break
	return points

func _touch_span() -> float:
	var points := _touch_points()
	if points.size() < 2:
		return 0.0
	return points[0].distance_to(points[1])

func _touch_midpoint() -> Vector2:
	var points := _touch_points()
	if points.size() < 2:
		return size * 0.5
	return (points[0] + points[1]) * 0.5

func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

func _is_inside(screen_pos: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(_screen_to_local(screen_pos))

func _zoom_at(local: Vector2, factor: float) -> void:
	var before := _grid_of_local(local)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	# Keep whatever was under the pointer under it. With no course bound (a
	# preview before the world exists) there is no ground to anchor, so the
	# view simply zooms about the middle.
	if _terrain_grid != null:
		var after := _local_of_grid(before)
		_pan += local - after
	_clamp_pan()
	view_changed.emit()
	queue_redraw()

## Keep at least a corner of the course inside the control.
func _clamp_pan() -> void:
	var limit := size * 0.5 * (_zoom - 1.0) + size * 0.35
	_pan.x = clampf(_pan.x, -limit.x, limit.x)
	_pan.y = clampf(_pan.y, -limit.y, limit.y)

func _press_at(local: Vector2) -> void:
	var tile := _tile_at(local)
	var hit := _hit_test(tile, local)
	map_pressed.emit(tile if _valid_tile(tile) else Vector2i(-1, -1), hit)

func _hover_at(local: Vector2) -> void:
	var tile := _tile_at(local)
	var hit := _hit_test(tile, local)
	if tile == _hover_tile and _same_hit(hit, _hover_hit):
		return
	_hover_tile = tile
	_hover_hit = hit
	if not _valid_tile(tile) and hit.is_empty():
		hover_cleared.emit()
	else:
		hover_changed.emit(hover_text(tile, hit))
	queue_redraw()

static func _same_hit(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or b[key] != a[key]:
			return false
	return true

func _notify_leave() -> void:
	_hover_tile = Vector2i(-1, -1)
	_hover_hit = {}
	hover_cleared.emit()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_notify_leave()

## What the pointer is over, in the current mode. Empty when it is over nothing
## the mode cares about.
func _hit_test(tile: Vector2i, local: Vector2) -> Dictionary:
	if _terrain_grid == null:
		return {}
	match mode:
		Mode.LAND:
			if not _valid_tile(tile):
				return {}
			var land: LandManager = GameManager.land_manager
			if land == null:
				return {}
			var parcel := land.tile_to_parcel(tile)
			if parcel == Vector2i(-1, -1):
				return {}
			return {"kind": "parcel", "value": parcel}
		Mode.ROUTING:
			var hole = _hole_near(local)
			return {} if hole == null else {"kind": "hole", "value": hole.hole_number}
		Mode.AURA:
			if not _valid_tile(tile):
				return {}
			var aura: CourseAura = GameManager.course_aura
			if aura == null:
				return {}
			var cell := CourseAura.cell_of(tile)
			return {} if not aura.cell_counts().has(cell) else {"kind": "aura", "value": cell}
		_:
			var index := _staff_near(tile)
			return {} if index < 0 else {"kind": "staff", "value": index}

## The hole whose marker or route is nearest the pointer, within PICK_RADIUS.
func _hole_near(local: Vector2) -> GameManager.HoleData:
	var course = GameManager.current_course
	if course == null or course.holes.is_empty():
		return null
	var best: GameManager.HoleData = null
	var best_distance := PICK_RADIUS * PICK_RADIUS
	for hole in course.holes:
		var tee := _local_of_grid(Vector2(hole.tee_position) + Vector2(0.5, 0.5))
		var green := _local_of_grid(Vector2(hole.green_position) + Vector2(0.5, 0.5))
		for point: Vector2 in [tee, green, (tee + green) * 0.5]:
			var distance := point.distance_squared_to(local)
			if distance < best_distance:
				best_distance = distance
				best = hole
	return best

## The staff member whose ground the pointer is standing on, or -1.
func _staff_near(tile: Vector2i) -> int:
	var manager: StaffManager = GameManager.staff_manager
	if manager == null or not _valid_tile(tile):
		return -1
	var point := Vector2(tile)
	var best := -1
	var best_distance := INF
	for index in manager.hired_staff.size():
		var record: Dictionary = manager.hired_staff[index]
		var centre := Vector2(record.get("area_center", Vector2i.ZERO))
		var radius: float = float(record.get("area_radius", 6.0))
		var distance := point.distance_to(centre)
		if distance <= maxf(radius, 2.0) and distance < best_distance:
			best_distance = distance
			best = index
	return best

## The one-line description of whatever the pointer is over, shown under the map.
func hover_text(tile: Vector2i, hit: Dictionary) -> String:
	match str(hit.get("kind", "")):
		"parcel":
			return _parcel_text(hit["value"])
		"hole":
			return _hole_text(int(hit["value"]))
		"aura":
			return _aura_text(hit["value"])
		"staff":
			return _staff_text(int(hit["value"]))
	if _valid_tile(tile):
		var terrain := _terrain_grid.get_tile(tile)
		return "Tile %d, %d — %s" % [tile.x, tile.y, TerrainTypes.get_type_name(terrain)]
	return ""

func _parcel_text(parcel: Vector2i) -> String:
	var land: LandManager = GameManager.land_manager
	if land == null:
		return ""
	var tier := land.get_parcel_tier(parcel)
	var tier_name := LandManager.get_tier_name(tier)
	var tiles: int = LandManager.PARCEL_SIZE * LandManager.PARCEL_SIZE
	if land.owned_parcels.has(parcel):
		return "Parcel %d, %d — %s land you own (%d tiles)" % [parcel.x, parcel.y, tier_name, tiles]
	if land.is_parcel_purchasable(parcel):
		var check := land.can_purchase_parcel(parcel)
		var cost := land.get_parcel_cost(parcel)
		if bool(check.get("can_buy", false)):
			return "Parcel %d, %d — %s land for sale, $%s (%d tiles)" \
				% [parcel.x, parcel.y, tier_name, _money(cost), tiles]
		return "Parcel %d, %d — %s land for sale, $%s: %s" \
			% [parcel.x, parcel.y, tier_name, _money(cost), str(check.get("reason", ""))]
	if not land.is_parcel_in_location(parcel):
		return "Parcel %d, %d — outside this location's block" % [parcel.x, parcel.y]
	return "Parcel %d, %d — not touching your land yet" % [parcel.x, parcel.y]

func _hole_text(hole_number: int) -> String:
	var course = GameManager.current_course
	if course == null:
		return ""
	for i in course.holes.size():
		var hole = course.holes[i]
		if int(hole.hole_number) != hole_number:
			continue
		var state := "open" if hole.is_open else "closed"
		var walk := HoleRouting.leg_tiles(course.holes, i)
		var leg := ""
		if i + 1 < course.holes.size():
			var grade := HoleRouting.grade_for(walk)
			leg = " · %d-tile walk to hole %d (%s)" % [int(roundf(walk)), i + 2, HoleRouting.grade_name(grade).to_lower()]
		return "Hole %d (%d of %d) — Par %d, %d yds, %s%s" \
			% [hole_number, i + 1, course.holes.size(), hole.par, hole.distance_yards, state, leg]
	return ""

func _aura_text(cell: Vector2i) -> String:
	var aura: CourseAura = GameManager.course_aura
	if aura == null:
		return ""
	var counts: Dictionary = aura.cell_counts().get(cell, {})
	if counts.is_empty():
		return ""
	var triggers := aura.top_triggers(cell, "", 1)
	var note := ""
	if not triggers.is_empty():
		note = " · mostly %s" % str(triggers[0]["label"]).to_lower()
	return "%s — %d happy, %d unhappy, %d neutral%s" % [
		aura.describe(cell), int(counts["positive"]), int(counts["negative"]), int(counts["neutral"]), note]

func _staff_text(index: int) -> String:
	var manager: StaffManager = GameManager.staff_manager
	if manager == null or index < 0 or index >= manager.hired_staff.size():
		return ""
	var record: Dictionary = manager.hired_staff[index]
	var data: Dictionary = manager.get_staff_data(int(record.type))
	var job := manager.get_job_for_type(int(record.type))
	var job_data: Dictionary = manager.get_job_data(job)
	return "%s (%s) — $%d/day, covers %.0f tiles around here to %s" % [
		str(record.get("name", "Staff")), str(data.get("name", "Staff")),
		int(record.get("salary", 0)), float(record.get("area_radius", 0.0)),
		str(job_data.get("action", "work"))]

static func _money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if amount < 0 else "") + out

# =============================================================================
# REACTIONS
# =============================================================================

func _on_tile_changed(_pos: Vector2i, _old_type: int, _new_type: int) -> void:
	_texture_dirty = true
	queue_redraw()

func _on_land_changed() -> void:
	queue_redraw()

func _on_staff_changed() -> void:
	queue_redraw()

func _on_theme_changed(_theme: int) -> void:
	_texture_dirty = true
	queue_redraw()

func _on_holes_reordered(_order: Array) -> void:
	queue_redraw()

func _on_hole_changed(_hole_number: int) -> void:
	queue_redraw()

func _on_hole_changed_created(_hole_number: int, _par: int, _distance: int) -> void:
	queue_redraw()

func _on_view_rotated(_orientation: int, _isometric: bool) -> void:
	# The diamond turns with the course, so the pan no longer means what it did.
	_pan = Vector2.ZERO
	queue_redraw()

func _on_resized() -> void:
	queue_redraw()
