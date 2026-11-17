extends Node2D
class_name PlacementPreview
## PlacementPreview - Enhanced placement preview with ghost sprites and validity indication

signal placement_confirmed(grid_pos: Vector2i, placement_type: String)
signal open_hole_pressed

var terrain_grid: TerrainGrid
var placement_manager: PlacementManager
var camera: IsometricCamera
var current_terrain_tool: int = -1  # Current terrain painting tool
var terrain_painting_enabled: bool = false  # Whether to show terrain preview
var elevation_mode_active: bool = false  # Whether an elevation selector is active
var elevation_tool_type: int = ElevationTool.Tool.NONE  # Which selector tool
## Elevation Brush of the active Square Selector (separate from the terrain
## brush: `brush_size`/`round_brush` belong to the Course Terrain tab).
var elevation_brush_size: int = 3
var elevation_brush_square := true
var bulldozer_mode_active: bool = false  # Whether bulldozer mode is active
var round_brush := true
var brush_size: int = 1  # Current terrain brush size (1 through 9)
var _hole_move_mode: int = 0  # 0=NONE, matches main.gd HoleMoveMode enum
## The building being carried to a new tile (the clubhouse) — its ghost follows
## the cursor until it is set down or the move is cancelled.
var _move_building: Building = null

# Preview state
var current_grid_pos: Vector2i = Vector2i(-1, -1)
var current_preview_valid: bool = false
var current_preview_positions: Array = []
var current_world_pos: Vector2 = Vector2.ZERO
var smooth_world_pos: Vector2 = Vector2.ZERO

# Visual settings
const VALID_COLOR := Color(0.3, 0.9, 0.3, 0.6)
const INVALID_COLOR := Color(0.9, 0.3, 0.3, 0.6)
const VALID_OUTLINE := Color(0.5, 1.0, 0.5, 0.9)
const INVALID_OUTLINE := Color(1.0, 0.4, 0.4, 0.9)
const BLOCKED_TILE_COLOR := Color(0.8, 0.2, 0.2, 0.4)
const SMOOTH_SPEED := 20.0

# Potential hole path: while a tee box waits and the Green tool is about to cut
# the cup, the hovered tile is previewed as the hole it would make.
const HOLE_PATH_COLOR := Color(1.0, 0.95, 0.72, 0.9)
const HOLE_PATH_SHADOW := Color(0.0, 0.0, 0.0, 0.35)
const HOLE_PATH_BLOCKED := Color(1.0, 0.45, 0.4, 0.9)
const HOLE_PATH_LANDING := Color(0.5, 0.85, 1.0, 0.9)  # HoleVisualizer landing-zone blue
const HOLE_PATH_TEE := Color(0.55, 0.95, 0.6, 0.95)
const HOLE_PATH_WIDTH := 2.0
const HOLE_PATH_DASH := 8.0
const HOLE_PATH_FONT_SIZE := 13
const HOLE_PATH_NOTE_FONT_SIZE := 11
const HOLE_LABEL_PADDING := Vector2(8.0, 4.0)
const HOLE_LABEL_OFFSET_Y := 6.0
const HOLE_BUTTON_PLAQUE_GAP := 6.0

## The potential hole under the cursor (HoleLayout.potential_hole()), {} when hidden.
var potential_hole: Dictionary = {}
## Planned route for potential_hole: [tee, landing..., cup], or [] while planning.
var potential_hole_route: Array[Vector2i] = []
## Painted pair stays visible until Open Hole claims the cup.
var waiting_hole: Dictionary = {}
var waiting_hole_route: Array[Vector2i] = []
var _hole_path_planner := HolePathPlanner.new()

## Inline Open Hole button mounted in the HUD over the waiting tee-to-cup line.
var open_hole_button: WaitingHoleOpenButton = null
## Optional main-scene gates: whether the course allows the inline button right
## now, and whether an active stroke/inspect should pass straight through it.
var button_allowed_provider: Callable = Callable()
var passthrough_input_provider: Callable = Callable()
var _hud_visible: bool = true

# Animation state
var _building_ghost: CourseArchitecture
var _pulse_time: float = 0.0
var _current_alpha: float = 0.0
var _target_alpha: float = 0.0
var _last_process_usec: int = -1
var _label_style: StyleBoxFlat

func _ready() -> void:
	_building_ghost = CourseArchitecture.new()
	_building_ghost.name = "BuildingGhost"
	_building_ghost.visible = false
	add_child(_building_ghost)
	set_process(true)
	# Sync the HUD Open Hole button after IsometricCamera finishes moving for
	# this frame so panning and zooming never lag by a frame.
	process_priority = 10
	z_index = 100  # Render above terrain
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_connect_event_bus()

func _process(_delta: float) -> void:
	# The player keeps building while the game is paused (Engine.time_scale = 0)
	# or fast-forwarded, so animate on wall-clock time like IsometricCamera does —
	# the scaled delta would freeze the fade-in at 0 or overshoot it at 8x.
	var delta := _real_delta()
	_pulse_time += delta * 3.0

	# Show preview for entity placement, terrain painting, elevation, or bulldozer
	var show_entity_preview = placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE
	var show_terrain_preview = terrain_painting_enabled and current_terrain_tool >= 0
	var show_elevation_preview = elevation_mode_active
	var show_bulldozer_preview = bulldozer_mode_active
	var show_move_preview = _hole_move_mode != 0 or _move_building != null

	if show_entity_preview or show_terrain_preview or show_elevation_preview or show_bulldozer_preview or show_move_preview:
		_target_alpha = 1.0
		_update_preview(delta)
	else:
		_target_alpha = 0.0
		current_preview_positions = []
		current_preview_valid = false
		_clear_potential_hole()
		# The building ghost is a child CanvasItem, not something this node
		# paints in _draw(). Hiding it only inside _draw() would strand the
		# last ghost whenever no redraw follows the end of a placement — for
		# example when a long frame drops the fade-out alpha straight to zero.
		# Hide it here as well, as soon as nothing is being previewed.
		if _hide_building_ghost():
			queue_redraw()

	# This overlay belongs to the course, not the cursor or selected tool.
	sync_waiting_hole()

	# Smooth alpha transition. The frame on which the fade crosses zero still
	# needs a redraw to wipe the last translucent footprint off this node's
	# canvas; a slow frame can otherwise take alpha from 1 to 0 without one.
	var was_fading := _current_alpha > 0.01
	_current_alpha = lerp(_current_alpha, _target_alpha, delta * 10.0)

	if _current_alpha > 0.01 or was_fading:
		queue_redraw()

## Seconds since the previous frame, unaffected by Engine.time_scale.
func _real_delta() -> float:
	var now := Time.get_ticks_usec()
	var elapsed := 0.0 if _last_process_usec < 0 else float(now - _last_process_usec) / 1000000.0
	_last_process_usec = now
	return minf(elapsed, 0.1)  # Guard against huge jumps (minimized window, debugger).

func set_terrain_grid(grid: TerrainGrid) -> void:
	_disconnect_terrain_grid()
	terrain_grid = grid
	_connect_terrain_grid()
	sync_waiting_hole()

## Mount the inline Open Hole button inside `hud` at child index 0 so it sits
## over the course route while remaining behind every HUD bar, panel and screen.
func attach_hud(hud: Control) -> WaitingHoleOpenButton:
	_detach_open_hole_button()
	if not is_instance_valid(hud):
		return null
	open_hole_button = WaitingHoleOpenButton.new()
	open_hole_button.name = "WaitingHoleOpenButton"
	open_hole_button.visible = false
	open_hole_button.pressed.connect(_on_open_hole_button_pressed)
	hud.add_child(open_hole_button)
	hud.move_child(open_hole_button, 0)
	sync_waiting_hole()
	return open_hole_button

## Mirror the gameplay HUD visibility flag without ever showing the button
## while no tee/cup pair is waiting.
func set_hud_visible(visible_flag: bool) -> void:
	_hud_visible = visible_flag
	_sync_open_hole_button()

## Update whether clicks pass through the inline Open Hole button right now
## (used during active paint strokes, measurement drags and tile inspection).
func refresh_input_filter() -> void:
	if not is_instance_valid(open_hole_button):
		return
	var passthrough := passthrough_input_provider.is_valid() \
			and bool(passthrough_input_provider.call())
	open_hole_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if passthrough \
			else Control.MOUSE_FILTER_STOP

func set_placement_manager(manager: PlacementManager) -> void:
	if is_instance_valid(placement_manager) and placement_manager.placement_mode_changed.is_connected(_on_placement_mode_changed):
		placement_manager.placement_mode_changed.disconnect(_on_placement_mode_changed)
	placement_manager = manager
	if is_instance_valid(placement_manager) and not placement_manager.placement_mode_changed.is_connected(_on_placement_mode_changed):
		placement_manager.placement_mode_changed.connect(_on_placement_mode_changed)

func set_camera(cam: IsometricCamera) -> void:
	camera = cam

func set_terrain_tool(tool_type: int) -> void:
	current_terrain_tool = tool_type

func set_terrain_painting_enabled(enabled: bool) -> void:
	terrain_painting_enabled = enabled

func set_brush_size(size: int) -> void:
	brush_size = size

func set_elevation_mode(active: bool) -> void:
	elevation_mode_active = active
	if not active:
		elevation_tool_type = ElevationTool.Tool.NONE

func set_elevation_tool(tool_type: int) -> void:
	elevation_tool_type = tool_type

func set_elevation_brush(size: int, square: bool) -> void:
	elevation_brush_size = size
	elevation_brush_square = square

func set_bulldozer_mode(active: bool) -> void:
	bulldozer_mode_active = active

func set_hole_move_mode(mode: int) -> void:
	var was_active := _hole_move_mode != 0
	_hole_move_mode = mode
	if was_active and mode == 0:
		_clear_preview_state()
	_sync_open_hole_button()

## Carry `building` with the cursor (null ends the move). The ghost shows where
## the footprint would land and turns red where placement is refused.
func set_building_move_target(building: Building) -> void:
	var was_carrying := _move_building != null
	_move_building = building if is_instance_valid(building) else null
	if was_carrying and _move_building == null:
		_clear_preview_state()
	_sync_open_hole_button()

## A placement just ended (or changed to a different catalogue item). Forget
## the old footprint and put the ghost away *now*, rather than waiting for the
## next _draw(): a placed building must never have a second, translucent copy
## of itself left hovering over its tiles. The signal covers every way a
## placement can finish — a click, Escape, a tool change or a mod/script — even
## when this node's process or redraws are paused.
func _on_placement_mode_changed(_mode: int) -> void:
	_clear_preview_state()

## Clear everything the last hover drew, on the canvas and in the ghost node.
func _clear_preview_state() -> void:
	current_preview_positions = []
	current_preview_valid = false
	_clear_potential_hole()
	_hide_building_ghost()
	queue_redraw()

## The ghost is a separate CanvasItem child; hide it explicitly instead of
## relying on a redraw of this node to do it. Returns whether it was visible.
func _hide_building_ghost() -> bool:
	if is_instance_valid(_building_ghost) and _building_ghost.visible:
		_building_ghost.visible = false
		return true
	return false

func _exit_tree() -> void:
	# A running route task reads a terrain copy the planner owns: let it finish.
	_hole_path_planner.shutdown()
	_disconnect_terrain_grid()
	_disconnect_event_bus()
	_detach_open_hole_button()
	if is_instance_valid(placement_manager) and placement_manager.placement_mode_changed.is_connected(_on_placement_mode_changed):
		placement_manager.placement_mode_changed.disconnect(_on_placement_mode_changed)

func _connect_terrain_grid() -> void:
	if not is_instance_valid(terrain_grid):
		return
	if not terrain_grid.tile_changed.is_connected(_on_terrain_tile_changed):
		terrain_grid.tile_changed.connect(_on_terrain_tile_changed)
	if not terrain_grid.cup_tiles_changed.is_connected(sync_waiting_hole):
		terrain_grid.cup_tiles_changed.connect(sync_waiting_hole)
	if not terrain_grid.view_rotated.is_connected(_on_terrain_view_rotated):
		terrain_grid.view_rotated.connect(_on_terrain_view_rotated)

func _disconnect_terrain_grid() -> void:
	if not is_instance_valid(terrain_grid):
		return
	if terrain_grid.tile_changed.is_connected(_on_terrain_tile_changed):
		terrain_grid.tile_changed.disconnect(_on_terrain_tile_changed)
	if terrain_grid.cup_tiles_changed.is_connected(sync_waiting_hole):
		terrain_grid.cup_tiles_changed.disconnect(sync_waiting_hole)
	if terrain_grid.view_rotated.is_connected(_on_terrain_view_rotated):
		terrain_grid.view_rotated.disconnect(_on_terrain_view_rotated)

func _connect_event_bus() -> void:
	if not has_node("/root/EventBus"):
		return
	if not EventBus.hole_created.is_connected(_on_hole_created):
		EventBus.hole_created.connect(_on_hole_created)
	if not EventBus.hole_deleted.is_connected(_on_hole_deleted):
		EventBus.hole_deleted.connect(_on_hole_deleted)
	if not EventBus.holes_reordered.is_connected(_on_holes_reordered):
		EventBus.holes_reordered.connect(_on_holes_reordered)
	if not EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.connect(_on_load_completed)
	if not EventBus.new_game_started.is_connected(sync_waiting_hole):
		EventBus.new_game_started.connect(sync_waiting_hole)
	if has_node("/root/Screen"):
		if not Screen.changed.is_connected(_on_screen_changed):
			Screen.changed.connect(_on_screen_changed)
		if not Screen.ui_scale_changed.is_connected(_on_ui_scale_changed):
			Screen.ui_scale_changed.connect(_on_ui_scale_changed)

func _disconnect_event_bus() -> void:
	if has_node("/root/Screen"):
		if Screen.changed.is_connected(_on_screen_changed):
			Screen.changed.disconnect(_on_screen_changed)
		if Screen.ui_scale_changed.is_connected(_on_ui_scale_changed):
			Screen.ui_scale_changed.disconnect(_on_ui_scale_changed)
	if not has_node("/root/EventBus"):
		return
	if EventBus.hole_created.is_connected(_on_hole_created):
		EventBus.hole_created.disconnect(_on_hole_created)
	if EventBus.hole_deleted.is_connected(_on_hole_deleted):
		EventBus.hole_deleted.disconnect(_on_hole_deleted)
	if EventBus.holes_reordered.is_connected(_on_holes_reordered):
		EventBus.holes_reordered.disconnect(_on_holes_reordered)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if EventBus.new_game_started.is_connected(sync_waiting_hole):
		EventBus.new_game_started.disconnect(sync_waiting_hole)

func _detach_open_hole_button() -> void:
	if not is_instance_valid(open_hole_button):
		open_hole_button = null
		return
	var btn := open_hole_button
	open_hole_button = null
	if btn.pressed.is_connected(_on_open_hole_button_pressed):
		btn.pressed.disconnect(_on_open_hole_button_pressed)
	btn.visible = false
	if not btn.is_queued_for_deletion():
		if btn.get_parent() == null:
			btn.free()
		else:
			btn.queue_free()

func _on_terrain_tile_changed(_pos: Vector2i, old_type: int, new_type: int) -> void:
	if old_type == TerrainTypes.Type.TEE_BOX or new_type == TerrainTypes.Type.TEE_BOX \
			or old_type == TerrainTypes.Type.GREEN or new_type == TerrainTypes.Type.GREEN:
		sync_waiting_hole()

func _on_terrain_view_rotated(_orientation: int, _isometric: bool) -> void:
	_sync_open_hole_button()
	if not waiting_hole.is_empty():
		queue_redraw()

func _on_screen_changed(_window_size: Vector2, _world_scale: float) -> void:
	_sync_open_hole_button()

func _on_ui_scale_changed(_scale: float, _mode: int) -> void:
	_sync_open_hole_button()

func _on_hole_created(_hole_number: int, _par: int, _distance_yards: int) -> void:
	sync_waiting_hole()

func _on_hole_deleted(_hole_number: int) -> void:
	sync_waiting_hole()

func _on_holes_reordered(_order: Array) -> void:
	sync_waiting_hole()

func _on_load_completed(_success: bool) -> void:
	sync_waiting_hole()

func _on_open_hole_button_pressed() -> void:
	if has_node("/root/SoundManager"):
		SoundManager.play_ui_click()
	open_hole_pressed.emit()

## Recompute the waiting tee-to-cup pair, update its planned route, and keep
## the inline Open Hole button anchored on the connecting line.
func sync_waiting_hole() -> void:
	var had_waiting_hole := not waiting_hole.is_empty() or not waiting_hole_route.is_empty()
	waiting_hole = HoleLayout.waiting_hole(terrain_grid, GameManager.current_course)
	waiting_hole_route = []
	if not waiting_hole.is_empty():
		waiting_hole_route = _hole_path_planner.route_for(terrain_grid, waiting_hole.tee,
				waiting_hole.cup, waiting_hole.par)
		queue_redraw()
	elif had_waiting_hole:
		queue_redraw()
	_sync_open_hole_button()

func _update_preview(delta: float) -> void:
	if not terrain_grid or not camera:
		return
	# Clicking the inline Open Hole pill commits the hole instead of painting or
	# placing on the tile beneath it, so hide the tool ghost while hovering it.
	if _is_open_hole_button_hovered():
		_clear_preview_state()
		return

	var mouse_world = camera.get_mouse_world_position()
	var grid_pos = terrain_grid.screen_to_grid(mouse_world)

	# Smooth world position for fluid movement
	current_world_pos = terrain_grid.grid_to_screen_center(grid_pos)
	smooth_world_pos = smooth_world_pos.lerp(current_world_pos, SMOOTH_SPEED * delta)

	current_grid_pos = grid_pos

	# Carrying a building: the footprint follows the cursor and placement rules
	# decide its colour (its own tiles are not in the way of itself).
	if _move_building != null:
		var move_size := Vector2i(_move_building.width, _move_building.height)
		current_preview_positions = _get_footprint_at(grid_pos, move_size)
		current_preview_valid = CourseClubhouse.move_error(terrain_grid, GameManager.entity_layer,
				_move_building, grid_pos).is_empty()
		_update_potential_hole(grid_pos)
		queue_redraw()
		return

	# Get positions to preview based on placement mode
	if placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE:
		match placement_manager.placement_mode:
			PlacementManager.PlacementMode.BUILDING, PlacementManager.PlacementMode.DECORATION:
				current_preview_positions = _get_building_footprint(grid_pos)
			_:
				current_preview_positions = [grid_pos]
		# Check overall validity for entity placement
		current_preview_valid = placement_manager.can_place_at(grid_pos, terrain_grid)
	elif elevation_mode_active:
		# Elevation selectors draw their own vertex/tile footprint below. Do not
		# leave the generic terrain hover tile under the cursor as a second,
		# misleading highlight (especially for the single-vertex selector).
		current_preview_positions = []
		current_preview_valid = terrain_grid.is_valid_position(grid_pos)
		_clear_potential_hole()
	else:
		# Terrain painting mode - show the area the tool will actually paint
		var course: GameManager.CourseData = GameManager.current_course
		var max_brush: int = HoleLayout.max_brush_size(current_terrain_tool, terrain_grid, course)
		var effective_brush: int = brush_size if max_brush == HoleLayout.UNLIMITED_BRUSH \
				else mini(brush_size, max_brush)
		if effective_brush <= 1:
			current_preview_positions = [grid_pos]
		else:
			current_preview_positions = terrain_grid.get_brush_tiles(grid_pos, effective_brush, round_brush)
		current_preview_valid = terrain_grid.is_valid_position(grid_pos)
		if current_terrain_tool == TerrainTypes.Type.TEE_BOX:
			current_preview_valid = current_preview_valid \
					and HoleLayout.can_place_tee_box(terrain_grid, course)
		elif current_terrain_tool == TerrainTypes.WALKING_PATH_TOOL:
			# The trail only sits on hostable ground (see TerrainTypes.
			# WALKING_PATH_TERRAINS), so validity is per ground type.
			current_preview_valid = terrain_grid.can_place_walking_path(grid_pos)

		_update_potential_hole(grid_pos)
	queue_redraw()

## Refresh the potential hole for the hovered tile: shown only while terrain
## painting with the Green tool, a Green With Hole comes next and a tee box waits.
func _update_potential_hole(grid_pos: Vector2i) -> void:
	var show_path: bool = terrain_painting_enabled and _hole_move_mode == 0 \
			and _move_building == null \
			and not elevation_mode_active and not bulldozer_mode_active \
			and not (placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE)
	var hole: Dictionary = {}
	if show_path:
		hole = HoleLayout.potential_hole(current_terrain_tool, terrain_grid,
				GameManager.current_course, grid_pos)
	if hole.is_empty():
		_clear_potential_hole()
		return
	potential_hole = hole
	potential_hole_route = _hole_path_planner.route_for(terrain_grid, hole.tee, hole.cup, hole.par)

func _clear_potential_hole() -> void:
	if not potential_hole.is_empty() or not potential_hole_route.is_empty():
		potential_hole = {}
		potential_hole_route = []
		queue_redraw()
	if HoleLayout.waiting_hole(terrain_grid, GameManager.current_course).is_empty():
		_hole_path_planner.cancel_pending()
	# Let a finished task hand its route to the cache even while hidden.
	_hole_path_planner.poll()

func _get_building_footprint(grid_pos: Vector2i) -> Array:
	var footprint = placement_manager.get_building_footprint()
	var result: Array = []
	for offset in footprint:
		result.append(grid_pos + offset)
	return result

## Footprint tiles of a `size` building whose top-left corner is at `grid_pos`.
func _get_footprint_at(grid_pos: Vector2i, size: Vector2i) -> Array:
	var result: Array = []
	for x in maxi(1, size.x):
		for y in maxi(1, size.y):
			result.append(grid_pos + Vector2i(x, y))
	return result

func _draw() -> void:
	_hide_building_ghost()
	if not terrain_grid:
		return

	# Check for hole move mode preview
	if _hole_move_mode != 0:
		_draw_hole_move_preview()
		return

	# Carrying the clubhouse: its footprint and its architecture follow the
	# cursor, both coloured by whether the tile it is over can take it.
	if _move_building != null:
		_draw_building_move_preview()
		return

	if not waiting_hole.is_empty():
		_draw_potential_hole(1.0, waiting_hole, waiting_hole_route, true)

	if _current_alpha < 0.01:
		return

	var is_entity_mode = placement_manager and placement_manager.placement_mode != PlacementManager.PlacementMode.NONE
	var is_terrain_mode = terrain_painting_enabled and current_terrain_tool >= 0
	var is_special_mode = is_terrain_mode or elevation_mode_active or bulldozer_mode_active

	if not is_entity_mode and not is_special_mode:
		return

	# Pulsing effect
	var pulse = 0.85 + sin(_pulse_time) * 0.15
	var alpha_mod = _current_alpha * pulse

	# The Path tool paints a thin trail over hostable ground, so its preview
	# shows per-tile validity colors plus a ghost dot instead of a paint fill.
	var path_tool := is_terrain_mode and current_terrain_tool == TerrainTypes.WALKING_PATH_TOOL

	# Draw generic entity/terrain footprint tiles. Elevation selectors render
	# their own footprint: Vertex is vertex-only, while the square tools draw
	# tiles touched by the selected vertices and those tiles' corner vertices.
	if not elevation_mode_active:
		for i in range(current_preview_positions.size()):
			var grid_pos = current_preview_positions[i]
			if terrain_grid.is_valid_position(grid_pos):
				var tile_valid: bool
				if is_entity_mode:
					tile_valid = _is_tile_valid_for_placement(grid_pos)
				elif path_tool:
					tile_valid = terrain_grid.can_place_walking_path(grid_pos)
				else:
					tile_valid = true  # Terrain/bulldozer painting is always valid on valid tiles
				_draw_isometric_tile(grid_pos, tile_valid, alpha_mod, i == 0, is_special_mode and not path_tool)

	if path_tool:
		_draw_path_ghost(alpha_mod)

	if not potential_hole.is_empty():
		_draw_potential_hole(_current_alpha, potential_hole, potential_hole_route)

	if elevation_mode_active:
		_draw_elevation_brush(alpha_mod)

	# Draw entity ghost preview (only for entity placement)
	if is_entity_mode:
		_draw_entity_ghost(alpha_mod)

func _draw_elevation_brush(alpha_mod: float) -> void:
	if not terrain_grid or not camera:
		return

	var mouse_world: Vector2 = camera.get_mouse_world_position()
	# The Vertex Selector snaps to the nearest vertex; the Square Selectors
	# anchor their tile block on the tile under the cursor, so the preview
	# always sits on what the click will reshape.
	var grid_point: Vector2 = terrain_grid.screen_to_grid_point(mouse_world)
	var anchor: Vector2i = ElevationTool.anchor_for_tool(grid_point, terrain_grid,
			elevation_tool_type)
	if not terrain_grid.is_valid_vertex(anchor):
		return

	var label: String
	var label_point: Vector2
	match elevation_tool_type:
		ElevationTool.Tool.VERTEX:
			# A vertex is the entire selection: never tint its neighbouring tiles.
			_draw_vertex_marker(anchor, Color(1, 1, 1, 0.95 * alpha_mod), 0.18)
			label = "%d" % terrain_grid.get_vertex_elevation(anchor)
			label_point = to_local(terrain_grid.grid_point_to_screen(Vector2(anchor)))
		ElevationTool.Tool.FLAT, ElevationTool.Tool.GRADUAL:
			# The brush is measured in tiles: it tints the tiles it covers and
			# marks the corner vertices it will move.
			var selected_tiles := _elevation_preview_tiles(anchor)
			var selected_vertices := _elevation_preview_vertices(anchor)
			if selected_vertices.is_empty():
				return  # The brush is off the grid: nothing to preview.
			for tile in selected_tiles:
				_draw_isometric_tile(tile, true, alpha_mod, tile == anchor, true)

			var middle: Array[Vector2i] = [anchor]
			if elevation_tool_type == ElevationTool.Tool.GRADUAL:
				middle = ElevationTool.middle_vertices(elevation_brush_size, anchor)
			for vertex in selected_vertices:
				var is_middle: bool = middle.has(vertex)
				var marker_color := Color(1, 1, 1, 0.95 * alpha_mod) if is_middle \
							else Color(0.55, 0.78, 1.0, 0.85 * alpha_mod)
				_draw_vertex_marker(vertex, marker_color, 0.16 if is_middle else 0.10)

			var lowest: int = terrain_grid.MAX_ELEVATION
			var highest: int = terrain_grid.MIN_ELEVATION
			# The Gradual tool only lifts its middle, so that is the height the
			# label follows; the Flat label reports the whole brush's range.
			var reported: Array[Vector2i] = middle if elevation_tool_type == ElevationTool.Tool.GRADUAL \
					else selected_vertices
			for vertex in reported:
				var height: int = terrain_grid.get_vertex_elevation(vertex)
				lowest = mini(lowest, height)
				highest = maxi(highest, height)
			label = "%d" % lowest if lowest == highest else "%d..%d" % [lowest, highest]
			label_point = to_local(terrain_grid.grid_to_screen_center(anchor))
		_:
			return

	draw_string(
		ThemeDB.fallback_font,
		label_point + Vector2(10, -8),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1, 1, 1, 0.9 * alpha_mod)
	)

## The tiles a square elevation tool reshapes - an S x S block of tiles (or its
## round clipping) anchored on the hovered tile. The Vertex Selector
## intentionally uses its own one-point drawing path instead.
func _elevation_preview_tiles(anchor: Vector2i) -> Array[Vector2i]:
	if not terrain_grid or not _is_square_elevation_tool():
		return []
	return ElevationTool.brush_tiles(terrain_grid, anchor, elevation_brush_size,
			elevation_brush_square)

## The vertices that same brush moves: the corners of its tiles. A 1x1 brush
## moves 4 vertices, a 2x2 brush 9, a 3x3 brush 16, and so on.
func _elevation_preview_vertices(anchor: Vector2i) -> Array[Vector2i]:
	if not terrain_grid or not _is_square_elevation_tool():
		return []
	return ElevationTool.brush_vertices(terrain_grid, anchor, elevation_brush_size,
			elevation_brush_square)

func _is_square_elevation_tool() -> bool:
	return elevation_tool_type == ElevationTool.Tool.FLAT \
			or elevation_tool_type == ElevationTool.Tool.GRADUAL

func _draw_vertex_marker(vertex: Vector2i, color: Color, marker_scale: float) -> void:
	var axis_x: Vector2 = terrain_grid.projection.axis_x() * marker_scale
	var axis_y: Vector2 = terrain_grid.projection.axis_y() * marker_scale
	var center: Vector2 = to_local(terrain_grid.grid_point_to_screen(Vector2(vertex)))
	draw_colored_polygon(PackedVector2Array([
		center - axis_x, center - axis_y, center + axis_x, center + axis_y,
	]), color)

## Ghost of the trodden dirt dot the Path tool would lay on the hovered tile:
## the same trodden patch the overlay draws for a trail head, so the cursor
## shows what gets laid.
func _draw_path_ghost(alpha_mod: float) -> void:
	if current_preview_positions.is_empty():
		return
	var pos: Vector2i = current_preview_positions[0]
	if not terrain_grid.is_valid_position(pos) or not terrain_grid.can_place_walking_path(pos):
		return
	var across := (OverlayGeometry.point_in_tile(terrain_grid, self, pos, Vector2(1.5, 0.5))
			- OverlayGeometry.point_in_tile(terrain_grid, self, pos, Vector2(0.5, 0.5))).length()
	var centre := OverlayGeometry.point_in_tile(terrain_grid, self, pos, Vector2(0.5, 0.5))
	var verge := Color(WalkingPathOverlay.DIRT_VERGE)
	verge.a *= alpha_mod
	var fill := Color(WalkingPathOverlay.DIRT_COLOR)
	fill.a *= alpha_mod
	draw_circle(centre, WalkingPathOverlay.DIRT_VERGE_DOT * across, verge)
	draw_circle(centre, WalkingPathOverlay.DIRT_LONE_DOT * across, fill)
	draw_arc(centre, WalkingPathOverlay.DIRT_LONE_DOT * across, 0.0, TAU, 20,
			Color(1.0, 1.0, 1.0, 0.8 * alpha_mod), 1.5)

func _is_tile_valid_for_placement(_grid_pos: Vector2i) -> bool:
	# The preview and click use one footprint-level validation result.
	return current_preview_valid

func _draw_isometric_tile(grid_pos: Vector2i, is_valid: bool, alpha_mod: float, is_primary: bool, is_terrain_mode: bool = false) -> void:

	# Fill color based on validity and mode
	var fill_color: Color
	var outline_color: Color

	if is_terrain_mode:
		# Use terrain-specific color for painting preview
		fill_color = _get_terrain_preview_color()
		outline_color = Color(1.0, 1.0, 1.0, 0.8)
	elif is_valid:
		fill_color = VALID_COLOR
		outline_color = VALID_OUTLINE
	else:
		fill_color = INVALID_COLOR if is_primary else BLOCKED_TILE_COLOR
		outline_color = INVALID_OUTLINE

	fill_color.a *= alpha_mod
	outline_color.a *= alpha_mod

	draw_colored_polygon(OverlayGeometry.tile_polygon(terrain_grid, self, grid_pos), fill_color)

	# Draw outline
	var outline_width = 2.0 if is_primary else 1.0
	draw_polyline(OverlayGeometry.tile_polyline(terrain_grid, self, grid_pos),
			outline_color, outline_width)

func _get_terrain_preview_color() -> Color:
	"""Get a preview color based on the current terrain tool or active mode"""
	if elevation_mode_active:
		return Color(0.5, 0.7, 1.0, 0.5)  # Light blue for the elevation selectors
	if bulldozer_mode_active:
		return Color(1.0, 0.5, 0.3, 0.5)  # Orange for bulldozer
	match current_terrain_tool:
		TerrainTypes.Type.FAIRWAY:
			return Color(0.4, 0.8, 0.4, 0.5)  # Light green
		TerrainTypes.Type.ROUGH:
			return Color(0.5, 0.7, 0.3, 0.5)  # Yellow-green
		TerrainTypes.Type.GREEN:
			return Color(0.3, 0.9, 0.5, 0.5)  # Bright green
		TerrainTypes.Type.TEE_BOX:
			return Color(0.4, 0.85, 0.45, 0.5)  # Medium green
		TerrainTypes.Type.BUNKER:
			return Color(0.9, 0.85, 0.6, 0.5)  # Sand color
		TerrainTypes.Type.WATER:
			return Color(0.3, 0.5, 0.9, 0.5)  # Blue
		TerrainTypes.Type.OUT_OF_BOUNDS:
			return Color(0.9, 0.3, 0.3, 0.5)  # Red
		TerrainTypes.Type.FLOWER_BED:
			return Color(0.9, 0.5, 0.7, 0.5)  # Pink
		TerrainTypes.Type.FIRM_FAIRWAY:
			return Color(0.7, 0.78, 0.4, 0.5)  # Straw green
		TerrainTypes.Type.DEEP_ROUGH:
			return Color(0.3, 0.5, 0.25, 0.5)  # Dark green
		TerrainTypes.Type.POT_BUNKER:
			return Color(0.8, 0.68, 0.45, 0.5)  # Dark sand
		TerrainTypes.Type.WASTE_BUNKER:
			return Color(0.78, 0.7, 0.55, 0.5)  # Grey-tan sand
		TerrainTypes.Type.STREAM:
			return Color(0.35, 0.7, 0.9, 0.5)  # Light blue
		TerrainTypes.Type.ROCKS:
			return Color(0.6, 0.58, 0.55, 0.5)  # Stone grey
		TerrainTypes.Type.BRUSH:
			return Color(0.4, 0.5, 0.2, 0.5)  # Olive
		_:
			return Color(0.5, 0.5, 0.5, 0.5)  # Gray default

func _draw_entity_ghost(alpha_mod: float) -> void:
	if current_preview_positions.is_empty():
		return

	var ghost_color = VALID_COLOR if current_preview_valid else INVALID_COLOR
	ghost_color.a = alpha_mod * 0.8

	match placement_manager.placement_mode:
		PlacementManager.PlacementMode.BUILDING:
			_draw_building_ghost(current_grid_pos, ghost_color)
		PlacementManager.PlacementMode.DECORATION:
			var top_left_dec = terrain_grid.grid_to_screen(current_grid_pos)
			_draw_decoration_ghost(top_left_dec, ghost_color)

func _draw_building_ghost(grid_pos: Vector2i, color: Color) -> void:
	var footprint = placement_manager.get_building_footprint()
	var fw = 1
	var fh = 1
	for offset in footprint:
		fw = max(fw, offset.x + 1)
		fh = max(fh, offset.y + 1)
	_draw_building_ghost_shape(grid_pos, placement_manager.selected_building_type,
			Vector2i(fw, fh), color)

## Footprint and architecture ghost for a building of `size` at `grid_pos`.
## Shared by the Buildings tab preview and a clubhouse being carried to a new
## tile, so both show the same outline the click will drop.
func _draw_building_ghost_shape(grid_pos: Vector2i, building_type: String, size: Vector2i, color: Color, upgrade_level: int = 1) -> void:
	var w = size.x * 64.0
	var h = size.y * 32.0
	var pos: Vector2
	if terrain_grid != null:
		if terrain_grid.is_view_isometric():
			var center_grid := Vector2(grid_pos) + Vector2(size.x * 0.5, size.y * 0.5)
			var level := terrain_grid.get_elevation(grid_pos)
			var entities: EntityLayer = GameManager.entity_layer
			if is_instance_valid(entities) and entities.terrain_grid == terrain_grid:
				level = entities.foundation_elevation(grid_pos, size, _move_building)
			var center := terrain_grid.projection.project(center_grid) \
					+ Vector2(0.0, -float(level - TerrainGrid.BASE_ELEVATION) * TerrainGrid.ELEVATION_STEP_Y)
			pos = center - Vector2(w * 0.5, h)
		else:
			pos = terrain_grid.grid_to_screen(Vector2i(grid_pos))
	else:
		pos = Vector2(grid_pos)

	if not is_instance_valid(_building_ghost):
		return
	_building_ghost.kind = building_type
	_building_ghost.facing = terrain_grid.get_view_facing_angle() if terrain_grid != null else 0.0
	if "level" in _building_ghost:
		_building_ghost.level = upgrade_level
	_building_ghost.footprint = Vector2(w, h)
	_building_ghost.position = pos
	_building_ghost.modulate = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, color.a)
	_building_ghost.visible = true
	_building_ghost.queue_redraw()

## The building being carried to a new tile: footprint tiles coloured per tile
## (its own tiles are not in the way of itself) plus its architecture ghost.
func _draw_building_move_preview() -> void:
	if not is_instance_valid(_move_building):
		return
	var pulse = 0.85 + sin(_pulse_time) * 0.15
	var alpha_mod = _current_alpha * pulse
	var ghost_color = VALID_COLOR if current_preview_valid else INVALID_COLOR
	ghost_color.a = alpha_mod * 0.8
	for i in range(current_preview_positions.size()):
		var tile: Vector2i = current_preview_positions[i]
		if terrain_grid.is_valid_position(tile):
			_draw_isometric_tile(tile, _tile_allows_move(tile), alpha_mod, i == 0, false)
	_draw_building_ghost_shape(current_grid_pos, _move_building.building_type,
			Vector2i(_move_building.width, _move_building.height), ghost_color,
			_move_building.upgrade_level)

## Would this footprint tile take the building being moved? Its own footprint
## is skipped: the building is leaving those tiles behind as it goes. The rules
## come from CourseClubhouse, so the tiles cannot say yes where the click says
## no.
func _tile_allows_move(tile: Vector2i) -> bool:
	var entities: EntityLayer = GameManager.entity_layer
	if is_instance_valid(_move_building) and is_instance_valid(entities):
		var size := Vector2i(_move_building.width, _move_building.height)
		if entities.foundation_placement_error(current_grid_pos, size, _move_building) \
				== EntityLayer.FOUNDATION_CONFLICT_ERROR:
			return false
	return CourseClubhouse.tile_error(tile, terrain_grid, entities, _move_building).is_empty()

func _draw_decoration_ghost(pos: Vector2, color: Color) -> void:
	"""Draw ghost preview for decoration placement using Decoration sprites/fallback"""
	var footprint = placement_manager.get_placement_footprint()
	var fw = 1
	var fh = 1
	for offset in footprint:
		fw = max(fw, offset.x + 1)
		fh = max(fh, offset.y + 1)

	var w = fw * 64.0
	var h = fh * 32.0
	var a = color.a
	var dec_type = placement_manager.selected_decoration_type

	var layout := PathFurniture.layout(terrain_grid, current_grid_pos, dec_type)
	var anchor := terrain_grid.grid_to_screen_center(current_grid_pos) + Vector2(layout.offset)
	if PathFurniture.has_art(dec_type):
		draw_set_transform(anchor)
		PathFurniture.draw_item(self, dec_type, layout.facing, a)
		draw_set_transform(Vector2.ZERO)
		return

	# Use the same foot anchor and deterministic transform as the placed sprite.
	if dec_type in Decoration.SPRITE_PATHS:
		var sprite_path = Decoration.SPRITE_PATHS[dec_type]
		if ResourceLoader.exists(sprite_path):
			var tex = load(sprite_path) as Texture2D
			if tex:
				var variation := Decoration.visual_variation(dec_type, current_grid_pos)
				var offset_y: float = Decoration.SPRITE_BASE_OFFSETS.get(dec_type, 16.0)
				var tint := variation.apply_color_shift(Color.WHITE)
				tint.a = a
				draw_set_transform(anchor, variation.rotation, Vector2.ONE * variation.scale)
				draw_texture(tex, -tex.get_size() * 0.5 - Vector2(0, offset_y), tint)
				draw_set_transform(Vector2.ZERO)
				return

	# Procedural fallback: simple colored shape
	var dec_color = Decoration.DECORATION_COLORS.get(dec_type, Color(0.5, 0.5, 0.5))
	dec_color.a = a
	var cx = pos.x + w / 2.0
	var cy = pos.y + h / 2.0
	# Draw a diamond/rhombus shape
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, pos.y + 2),
		Vector2(pos.x + w - 4, cy),
		Vector2(cx, pos.y + h - 2),
		Vector2(pos.x + 4, cy)
	]), dec_color)

# =============================================================================
# POTENTIAL HOLE PATH
# =============================================================================

## Draw the hole the hovered tile would make: the waiting tee, the expected shot
## route (dashed; a straight provisional line while a par 4/5 route is planned),
## the landing zones, the cup-to-be and a "Hole N · Par P · Y yds" plaque.
func _draw_potential_hole(alpha: float, hole: Dictionary, route: Array[Vector2i],
		is_waiting: bool = false) -> void:
	var tee: Vector2i = hole.tee
	var cup: Vector2i = hole.cup
	var hole_ready: bool = hole.ready
	var planned: bool = not route.is_empty()

	var points := PackedVector2Array()
	if planned:
		for waypoint in route:
			points.append(OverlayGeometry.tile_center(terrain_grid, self, waypoint))
	else:
		# Par 4/5 route still being planned: a provisional straight line.
		points.append(OverlayGeometry.tile_center(terrain_grid, self, tee))
		points.append(OverlayGeometry.tile_center(terrain_grid, self, cup))

	# The waiting tee this cup would pair with.
	var pulse := 0.75 + sin(_pulse_time) * 0.25
	draw_polyline(OverlayGeometry.tile_polyline(terrain_grid, self, tee),
			Color(HOLE_PATH_TEE, HOLE_PATH_TEE.a * alpha * pulse), 2.0)

	# Route: a soft dark underlay keeps the dashes readable on any turf.
	var line_color := HOLE_PATH_COLOR if hole_ready else HOLE_PATH_BLOCKED
	line_color.a *= alpha * (1.0 if planned else 0.6)
	if points[0].distance_to(points[points.size() - 1]) >= 1.0:
		draw_polyline(points, Color(HOLE_PATH_SHADOW, HOLE_PATH_SHADOW.a * alpha),
				HOLE_PATH_WIDTH + 2.0, true)
	for i in range(points.size() - 1):
		if points[i].distance_to(points[i + 1]) >= 1.0:
			draw_dashed_line(points[i], points[i + 1], line_color, HOLE_PATH_WIDTH,
					HOLE_PATH_DASH, true, true)

	# When extreme zoom-out or a very short pair steps the inline Open Hole
	# button away from the line to keep clear of the cup's plaque, tether it
	# back to the route midpoint so its bond with the line stays obvious.
	if is_waiting and is_instance_valid(open_hole_button) and open_hole_button.visible:
		var screen_points := waiting_hole_screen_points()
		var btn_center := open_hole_button.position + open_hole_button.size * 0.5
		if screen_points.size() >= 2 and distance_to_polyline(btn_center, screen_points) > 2.0:
			var inv := _world_to_screen_transform().affine_inverse()
			var from_pt := polyline_point_at(points, 0.5)
			var to_pt := to_local(inv * btn_center)
			draw_line(from_pt, to_pt, Color(HOLE_PATH_SHADOW, HOLE_PATH_SHADOW.a * alpha),
					HOLE_PATH_WIDTH + 2.0, true)
			draw_dashed_line(from_pt, to_pt, line_color, HOLE_PATH_WIDTH,
					HOLE_PATH_DASH * 0.6, true, true)

	# Landing zones, styled like the markers HoleVisualizer draws once the hole opens.
	for i in range(1, points.size() - 1):
		draw_circle(points[i], 5.0, Color(0.0, 0.0, 0.0, 0.5 * alpha))
		draw_circle(points[i], 3.5, Color(HOLE_PATH_LANDING, HOLE_PATH_LANDING.a * alpha))

	var pin_top := _draw_potential_cup(cup, alpha, hole_ready)
	_draw_potential_hole_label(hole, pin_top, alpha)

## The hole CupOverlay will cut — black and exactly the golf ball's width — plus
## a small gold pin, previewing the waiting pin it will plant. Returns the top
## of the pin so the plaque can sit above it.
func _draw_potential_cup(cup: Vector2i, alpha: float, hole_ready: bool) -> Vector2:
	CupOverlay.draw_hole(self, terrain_grid, cup, alpha)
	var cup_point := OverlayGeometry.tile_center(terrain_grid, self, cup)

	var pin_color := CupOverlay.WAITING_PIN_COLOR if hole_ready else HOLE_PATH_BLOCKED
	var pole_top := cup_point - Vector2(0.0, CupOverlay.WAITING_POLE_HEIGHT * 0.75)
	draw_line(cup_point, pole_top, Color(0.95, 0.95, 0.92, 0.9 * alpha), 1.5, true)
	draw_colored_polygon(PackedVector2Array([
		pole_top,
		pole_top + Vector2(CupOverlay.WAITING_FLAG_LENGTH * 0.8, 3.5),
		pole_top + Vector2(0.0, 7.0),
	]), Color(pin_color, alpha))
	return pole_top

## Local screen-sized bounding box of a hole plaque relative to its pin top.
static func _hole_label_box(hole: Dictionary) -> Dictionary:
	var font: Font = ThemeDB.fallback_font
	var title := "Hole %d · Par %d · %d yds" % [hole.hole_number, hole.par, hole.distance_yards]
	var note: String = str(hole.get("reason", ""))
	var title_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_FONT_SIZE)
	var note_size := Vector2.ZERO
	if not note.is_empty():
		note_size = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_NOTE_FONT_SIZE)
	var box_size := Vector2(maxf(title_size.x, note_size.x), title_size.y + note_size.y) \
			+ HOLE_LABEL_PADDING * 2.0
	var rect := Rect2(Vector2(-box_size.x * 0.5, -box_size.y - HOLE_LABEL_OFFSET_Y), box_size)
	return {
		"font": font,
		"title": title,
		"note": note,
		"title_size": title_size,
		"rect": rect,
	}

## "Hole N · Par P · Y yds", plus why the pair can't open yet. Drawn at a constant
## on-screen size so it stays legible however far the camera is zoomed out.
func _draw_potential_hole_label(hole: Dictionary, anchor: Vector2, alpha: float) -> void:
	var layout := _hole_label_box(hole)
	var font: Font = layout["font"]
	var title: String = layout["title"]
	var note: String = layout["note"]
	var title_size: Vector2 = layout["title_size"]
	var box: Rect2 = layout["rect"]

	if _label_style == null:
		_label_style = StyleBoxFlat.new()
		_label_style.set_corner_radius_all(4)
		_label_style.set_border_width_all(1)
	_label_style.bg_color = Color(0.125, 0.247, 0.196, 0.87 * alpha)  # HoleVisualizer plaque green
	_label_style.border_color = Color(UIConstants.COLOR_GOLD if hole.ready else HOLE_PATH_BLOCKED, alpha)

	var screen_scale := 1.0 / camera.zoom.x if camera and camera.zoom.x > 0.0 else 1.0
	draw_set_transform(anchor, 0.0, Vector2(screen_scale, screen_scale))
	draw_style_box(_label_style, box)
	var baseline := box.position.y + HOLE_LABEL_PADDING.y + font.get_ascent(HOLE_PATH_FONT_SIZE)
	draw_string(font, Vector2(box.position.x + HOLE_LABEL_PADDING.x, baseline), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_FONT_SIZE, Color(UIConstants.COLOR_TEXT, alpha))
	if not note.is_empty():
		baseline += title_size.y
		draw_string(font, Vector2(box.position.x + HOLE_LABEL_PADDING.x, baseline), note,
				HORIZONTAL_ALIGNMENT_LEFT, -1, HOLE_PATH_NOTE_FONT_SIZE,
				Color(1.0, 0.72, 0.68, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Position and show/hide the inline Open Hole button on the waiting route.
func _sync_open_hole_button() -> void:
	if not is_instance_valid(open_hole_button):
		return
	if not _should_show_open_hole_button():
		if open_hole_button.visible:
			open_hole_button.visible = false
		return

	var screen_points := waiting_hole_screen_points()
	if screen_points.size() < 2 or screen_points[0].distance_to(screen_points[screen_points.size() - 1]) < 1.0:
		if open_hole_button.visible:
			open_hole_button.visible = false
		return

	open_hole_button.set_waiting_hole(waiting_hole)
	open_hole_button.update_layout_metrics()
	var btn_size := open_hole_button.size
	var plaque_rect := waiting_hole_plaque_rect()
	var center := line_button_center(screen_points, btn_size, plaque_rect)
	var btn_pos := (center - btn_size * 0.5).round()
	var btn_rect := Rect2(btn_pos, btn_size)

	# Hide when the camera has panned completely away from the button's seat.
	if is_instance_valid(camera) and is_inside_tree():
		var view_rect := get_viewport_rect()
		if view_rect.has_area() and not view_rect.intersects(btn_rect):
			if open_hole_button.visible:
				open_hole_button.visible = false
			return

	open_hole_button.position = btn_pos
	refresh_input_filter()
	if not open_hole_button.visible:
		open_hole_button.visible = true

func _is_open_hole_button_hovered() -> bool:
	if not is_instance_valid(open_hole_button) or not open_hole_button.visible:
		return false
	if open_hole_button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	if not is_inside_tree() or get_viewport() == null:
		return false
	return get_viewport().gui_get_hovered_control() == open_hole_button

func _should_show_open_hole_button() -> bool:
	if not _hud_visible or not is_instance_valid(terrain_grid):
		return false
	if waiting_hole.is_empty():
		return false
	# Matches _draw(): moving a hole end or carrying the clubhouse replaces the
	# waiting-hole route with the move preview until the move ends.
	if _hole_move_mode != 0 or _move_building != null:
		return false
	if button_allowed_provider.is_valid() and not bool(button_allowed_provider.call()):
		return false
	return true

func _world_to_screen_transform() -> Transform2D:
	if is_instance_valid(camera) and camera.is_inside_tree():
		return camera.get_canvas_transform()
	if is_inside_tree() and get_viewport() != null:
		return get_viewport().get_canvas_transform()
	return Transform2D.IDENTITY

## World-space polyline of the waiting tee-to-cup route ([] when none waits).
func waiting_hole_world_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(terrain_grid) or waiting_hole.is_empty():
		return points
	if not waiting_hole_route.is_empty():
		for waypoint in waiting_hole_route:
			points.append(terrain_grid.grid_to_screen_center(waypoint))
	else:
		points.append(terrain_grid.grid_to_screen_center(waiting_hole.tee))
		points.append(terrain_grid.grid_to_screen_center(waiting_hole.cup))
	return points

## Screen-space polyline of the waiting tee-to-cup route, in HUD coordinates.
func waiting_hole_screen_points() -> PackedVector2Array:
	var world_points := waiting_hole_world_points()
	if world_points.is_empty():
		return world_points
	var xform := _world_to_screen_transform()
	var out := PackedVector2Array()
	out.resize(world_points.size())
	for i in range(world_points.size()):
		out[i] = xform * world_points[i]
	return out

## Screen-space bounding box of the waiting cup's "Hole N · Par P · Y yds" plaque.
func waiting_hole_plaque_rect() -> Rect2:
	if not is_instance_valid(terrain_grid) or waiting_hole.is_empty():
		return Rect2()
	var cup_world := terrain_grid.grid_to_screen_center(waiting_hole.cup)
	var pin_top_world := cup_world - Vector2(0.0, CupOverlay.WAITING_POLE_HEIGHT * 0.75)
	var pin_top_screen := _world_to_screen_transform() * pin_top_world
	var box: Rect2 = _hole_label_box(waiting_hole)["rect"]
	return Rect2(pin_top_screen + box.position, box.size)

## Point `fraction` (0 = start, 1 = end) of the total arc length along `points`.
static func polyline_point_at(points: PackedVector2Array, fraction: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	if total <= 0.001:
		return points[0]
	var target := total * clampf(fraction, 0.0, 1.0)
	var walked := 0.0
	for i in range(1, points.size()):
		var seg_start := points[i - 1]
		var seg_end := points[i]
		var seg_len := seg_start.distance_to(seg_end)
		if walked + seg_len >= target:
			var t := 0.0 if seg_len <= 0.001 else (target - walked) / seg_len
			return seg_start.lerp(seg_end, t)
		walked += seg_len
	return points[points.size() - 1]

## Shortest distance from `point` to any segment of `points`.
static func distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.is_empty():
		return INF
	if points.size() == 1:
		return point.distance_to(points[0])
	var best := INF
	for i in range(1, points.size()):
		var closest := Geometry2D.get_closest_point_to_segment(point, points[i - 1], points[i])
		best = minf(best, point.distance_to(closest))
	return best

## Screen-space centre for the inline Open Hole button: directly on the route's
## midpoint whenever clear of the cup plaque, sliding toward the tee along the
## route when the plaque encroaches, and stepping below/above the plaque only
## when the whole route is shorter than the plaque itself (deep zoom-out or a
## very short pair).
static func line_button_center(points: PackedVector2Array, button_size: Vector2,
		plaque_rect: Rect2 = Rect2()) -> Vector2:
	var midpoint := polyline_point_at(points, 0.5)
	if points.size() < 2 or button_size == Vector2.ZERO or not plaque_rect.has_area():
		return midpoint
	var padded_plaque := plaque_rect.grow(HOLE_BUTTON_PLAQUE_GAP)
	if not Rect2(midpoint - button_size * 0.5, button_size).intersects(padded_plaque):
		return midpoint
	for step in range(1, 7):
		var fraction := 0.5 - float(step) * 0.05
		var candidate := polyline_point_at(points, fraction)
		if not Rect2(candidate - button_size * 0.5, button_size).intersects(padded_plaque):
			return candidate
	var half_h := button_size.y * 0.5
	var below := Vector2(midpoint.x, padded_plaque.end.y + half_h)
	var above := Vector2(midpoint.x, padded_plaque.position.y - half_h)
	return below if absf(below.y - midpoint.y) <= absf(above.y - midpoint.y) else above

func _draw_hole_move_preview() -> void:
	if not camera or not terrain_grid:
		return

	var mouse_world = camera.get_mouse_world_position()
	var hover_pos = terrain_grid.screen_to_grid(mouse_world)
	if not terrain_grid.is_valid_position(hover_pos):
		return

	# Determine validity and color based on mode
	var is_valid = false
	var preview_color: Color
	var label_text: String

	# HoleMoveMode: 1=TEE, 2=GREEN, 3=FORWARD_TEE, 4=MIDDLE_TEE (matches main.gd enum)
	match _hole_move_mode:
		1:  # MOVING_TEE
			var tile = terrain_grid.get_tile(hover_pos)
			is_valid = not TerrainTypes.is_water(tile) and tile != TerrainTypes.Type.OUT_OF_BOUNDS
			preview_color = Color(0.4, 0.85, 0.45, 0.5) if is_valid else Color(0.9, 0.3, 0.3, 0.3)
			label_text = "Tee"
		2:  # MOVING_GREEN
			var tile = terrain_grid.get_tile(hover_pos)
			is_valid = not TerrainTypes.is_water(tile) and tile != TerrainTypes.Type.OUT_OF_BOUNDS
			preview_color = Color(0.3, 0.9, 0.5, 0.5) if is_valid else Color(0.9, 0.3, 0.3, 0.3)
			label_text = "Green"
	if not is_valid:
		return

	var pulse = 0.7 + sin(_pulse_time) * 0.3
	preview_color.a *= pulse
	draw_colored_polygon(OverlayGeometry.tile_polygon(terrain_grid, self, hover_pos), preview_color)
	draw_polyline(OverlayGeometry.tile_polyline(terrain_grid, self, hover_pos),
			Color(1.0, 1.0, 1.0, 0.7 * pulse), 2.0)

	var font = ThemeDB.fallback_font
	var center = terrain_grid.grid_to_screen_center(hover_pos)
	draw_string(font, center + Vector2(-20, -20), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1, 1, 1, 0.9))

# =============================================================================
# PUBLIC API
# =============================================================================

func get_preview_valid() -> bool:
	return current_preview_valid

func get_preview_positions() -> Array:
	return current_preview_positions

func get_current_grid_pos() -> Vector2i:
	return current_grid_pos

func confirm_placement() -> void:
	if current_preview_valid and current_grid_pos != Vector2i(-1, -1):
		var placement_type = ""
		match placement_manager.placement_mode:
			PlacementManager.PlacementMode.BUILDING:
				placement_type = "building"
			PlacementManager.PlacementMode.DECORATION:
				placement_type = "decoration"
		placement_confirmed.emit(current_grid_pos, placement_type)
