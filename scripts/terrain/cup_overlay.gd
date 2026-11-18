extends Node2D
class_name CupOverlay
## CupOverlay - Cuts a black hole in the ground under every flag on the course.
##
## Two kinds of flag stand on a cup: the gold pin of a "Green With Hole" tile
## that no tee box has been paired with yet, and the red pin of an open hole.
## Both get the same hole drawn under them, so the pin always has something to
## stand in.
##
## The hole is cut to the golf ball's own size — Ball.BALL_RADIUS across — so
## the black disc is exactly as wide as the ball that drops into it. Laid flat
## on the green it reads as an ellipse squashed the same way the tile under it
## is, never as a circle pasted on the screen.
##
## The hole is paint on the green: every vertex carries the grid point of the
## turf under it, so a nearer hill hides it as it hides the walking trail
## (terrain_decal_occlusion.gdshader); the pins standing in the cups are clipped
## as trees are (WindFlag.stand_on()).

const HOLE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
## A hair of light around the rim: the black disc is the ball's exact size, and
## the lip of the cut is what keeps it from vanishing into a dark green.
const HOLE_RIM_COLOR := Color(0.96, 0.96, 0.90, 0.8)
const HOLE_RIM_WIDTH := 1.0
const WAITING_PIN_COLOR := Color(0.98, 0.83, 0.25)
const WAITING_POLE_HEIGHT := 30.0
const WAITING_FLAG_LENGTH := 14.0
const SEGMENTS := 16
const GROUND_Z_INDEX := 1
## Clips the holes where nearer terrain covers them (see
## TerrainGrid.terrain_occlusion_enabled()).
const TERRAIN_DECAL_OCCLUSION: Shader = preload("res://shaders/terrain_decal_occlusion.gdshader")

var _terrain_grid: TerrainGrid = null
var _pins: Array[WindFlag] = []
## The overlay's material while terrain occlusion is on; null on a flat course.
var _occlusion_material: ShaderMaterial = null
## Vector2i tile -> the hole cut there as a GroundDecal, laid out for the ground
## and the view recorded in `_decal_stamp`, so a camera pan reuses it.
var _decal_cache: Dictionary = {}
var _decal_stamp: Array = []

## The radius the hole is drawn at: the golf ball's, so hole and ball match.
static func hole_radius() -> float:
	return Ball.BALL_RADIUS

func initialize(grid: TerrainGrid) -> void:
	_terrain_grid = grid
	# The cup cut itself belongs in the ground band beneath sprites and balls,
	# while child waiting pins rise into the entity band and Y-sort with sprites.
	z_index = GROUND_Z_INDEX
	y_sort_enabled = true
	if _terrain_grid and not _terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
		_terrain_grid.cup_tiles_changed.connect(_on_cup_tiles_changed)
	if _terrain_grid:
		_terrain_grid.terrain_occlusion_changed.connect(_on_terrain_occlusion_changed)
		_terrain_grid.view_rotated.connect(_on_view_rotated)
	EventBus.load_completed.connect(_on_load_completed)
	# An open hole's cup moves with its green, so the holes redrawn here follow
	# the same signals WindFlagOverlay rebuilds its pins on.
	EventBus.hole_created.connect(_on_hole_created)
	EventBus.hole_deleted.connect(_on_hole_changed)
	EventBus.hole_updated.connect(_on_hole_changed)
	_refresh_occlusion()
	_rebuild()

func _exit_tree() -> void:
	if _terrain_grid and _terrain_grid.cup_tiles_changed.is_connected(_on_cup_tiles_changed):
		_terrain_grid.cup_tiles_changed.disconnect(_on_cup_tiles_changed)
	if _terrain_grid and _terrain_grid.terrain_occlusion_changed.is_connected(_on_terrain_occlusion_changed):
		_terrain_grid.terrain_occlusion_changed.disconnect(_on_terrain_occlusion_changed)
	if _terrain_grid and _terrain_grid.view_rotated.is_connected(_on_view_rotated):
		_terrain_grid.view_rotated.disconnect(_on_view_rotated)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if EventBus.hole_created.is_connected(_on_hole_created):
		EventBus.hole_created.disconnect(_on_hole_created)
	if EventBus.hole_deleted.is_connected(_on_hole_changed):
		EventBus.hole_deleted.disconnect(_on_hole_changed)
	if EventBus.hole_updated.is_connected(_on_hole_changed):
		EventBus.hole_updated.disconnect(_on_hole_changed)

func _on_cup_tiles_changed() -> void:
	_rebuild()

func _on_hole_created(_hole_number: int, _par: int, _distance_yards: int) -> void:
	queue_redraw()

func _on_hole_changed(_hole_number: int) -> void:
	queue_redraw()

func _on_load_completed(_success: bool) -> void:
	call_deferred("_rebuild")

func _on_terrain_occlusion_changed(_enabled: bool) -> void:
	_refresh_occlusion()

## A turn gives the occlusion shader the new projection (the redraw itself
## comes with every other terrain overlay's).
func _on_view_rotated(_orientation: int, _isometric: bool) -> void:
	_refresh_occlusion()

## Clip the holes behind nearer terrain while the course has relief and the
## graphics setting allows it; a flat course draws them with no material at
## all. The heightfield is shared with the surface and updated in place, so
## only a turn of the view (the projection) needs this again.
func _refresh_occlusion() -> void:
	var surface: CourseSurface = _terrain_grid._course_surface if _terrain_grid else null
	if surface == null or not _terrain_grid.terrain_occlusion_enabled():
		material = null
		return
	if _occlusion_material == null:
		_occlusion_material = ShaderMaterial.new()
		_occlusion_material.shader = TERRAIN_DECAL_OCCLUSION
	surface.configure_terrain_occlusion(_occlusion_material)
	material = _occlusion_material

## Stand the waiting pins back in their cups after the view turned or the
## ground moved (see WindFlag.stand_on(), which also re-aims each pin's clip).
func refresh_pin_positions() -> void:
	if not _terrain_grid:
		return
	var cups := _terrain_grid.get_cup_tiles()
	for i in range(_pins.size()):
		var pin := _pins[i]
		if is_instance_valid(pin) and i < cups.size():
			pin.stand_on(_terrain_grid, cups[i])

## Every tile that carries a hole in the ground: the cups still waiting for a
## tee box, then the cup of each open hole.
func hole_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not _terrain_grid:
		return tiles
	tiles = _terrain_grid.get_cup_tiles()
	if GameManager.course_data:
		for hole_data in GameManager.course_data.holes:
			var pos: Vector2i = hole_data.hole_position
			if _terrain_grid.is_valid_position(pos) and not tiles.has(pos):
				tiles.append(pos)
	return tiles

func _rebuild() -> void:
	for pin in _pins:
		if is_instance_valid(pin):
			remove_child(pin)
			pin.free()
	_pins.clear()

	if not _terrain_grid:
		queue_redraw()
		return

	for cup_pos in _terrain_grid.get_cup_tiles():
		var pin := WindFlag.new()
		pin.name = "WaitingPin_%d_%d" % [cup_pos.x, cup_pos.y]
		pin._flag_color = WAITING_PIN_COLOR
		pin._pole_height = WAITING_POLE_HEIGHT
		pin._flag_length = WAITING_FLAG_LENGTH
		pin.stand_on(_terrain_grid, cup_pos)
		add_child(pin)
		pin.z_index = WindFlag.ENTITY_Z_INDEX - z_index
		_pins.append(pin)
	queue_redraw()

func _draw() -> void:
	if not _terrain_grid:
		return
	var canvas_item := get_canvas_item()
	for hole_pos in hole_tiles():
		if not _terrain_grid.is_valid_position(hole_pos):
			continue
		decal_for(hole_pos).draw_on(canvas_item)

## The hole cut at `pos` (see hole_decal()), from the shelf while the ground
## and the view it was laid out for still hold.
func decal_for(pos: Vector2i) -> GroundDecal:
	var stamp := [_terrain_grid.terrain_revision, _terrain_grid.projection.orientation,
			_terrain_grid.projection.isometric, get_global_transform()]
	if stamp != _decal_stamp:
		_decal_cache.clear()
		_decal_stamp = stamp
	if not _decal_cache.has(pos):
		_decal_cache[pos] = hole_decal(_terrain_grid, self, pos)
	return _decal_cache[pos]

## The hole as an ellipse on the projected tile: Ball.BALL_RADIUS across — the
## golf ball's own width — squashed the way the ground under it is, so it lies
## flat on the green instead of facing the camera. `rim` gives the slightly
## larger lip the black disc sits in.
static func hole_polygon(grid: TerrainGrid, node: CanvasItem, pos: Vector2i,
		rim: bool = false) -> PackedVector2Array:
	var center := OverlayGeometry.tile_center(grid, node, pos)
	var rx := hole_radius() + (HOLE_RIM_WIDTH if rim else 0.0)
	var ry := rx * ground_squash(grid)
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points

## How much a shape lying flat on the ground is squashed in this view: the
## projected tile's own height-to-width ratio (0.5 in the 2:1 isometric view,
## 1.0 if the tiles are square). The hole is a flat circle cut in the turf, so
## this — not the tile's corners, which the view rotates — sets its shape.
static func ground_squash(grid: TerrainGrid) -> float:
	if grid == null or grid.tile_width <= 0:
		return 0.5
	return float(grid.tile_height) / float(grid.tile_width)

## Cut a hole in the ground at `pos`: a light lip with the black, ball-sized
## disc inside it. Shared with the placement preview so the cup a player is
## about to paint is drawn exactly like the one that gets cut (the preview wears
## no occlusion material, so the ground the paint names changes nothing there).
static func draw_hole(item: CanvasItem, grid: TerrainGrid, pos: Vector2i,
		alpha: float = 1.0) -> void:
	hole_decal(grid, item, pos, alpha).draw_on(item.get_canvas_item())

## The hole at `pos` as ground paint in `item`'s space: the lip, then the black
## disc over it, held to the tile's centre like the pin standing in it
## (GroundDecal.stand_on()): a hill in front of the green hides it, the green's
## own slope never does.
static func hole_decal(grid: TerrainGrid, item: CanvasItem, pos: Vector2i,
		alpha: float = 1.0) -> GroundDecal:
	var decal := GroundDecal.new()
	for rim in [true, false]:
		var color := HOLE_RIM_COLOR if rim else HOLE_COLOR
		decal.add_convex(hole_polygon(grid, item, pos, rim), Color(color, color.a * alpha))
	decal.stand_on(grid, Vector2(pos) + Vector2(0.5, 0.5), item.get_global_transform())
	return decal
