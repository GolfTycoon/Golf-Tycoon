extends Control
class_name MiniMap
## MiniMap - Shows course overview with click-to-navigate

signal camera_move_requested(world_position: Vector2)

const MAP_SIZE: int = 180  # Size of mini-map in pixels (standard windows)
const COMPACT_MAP_SIZE: int = 120  # Narrow windows (phones, small browser windows)
const BORDER_WIDTH: int = 2

## Live map size; apply_screen() switches between MAP_SIZE and
## COMPACT_MAP_SIZE as the window resizes.
var _map_size: int = MAP_SIZE

## Whether the surrounding gameplay HUD is currently shown. Main clears this on
## the title screen and fullscreen overlays so enabling the minimap from Main
## Menu Settings keeps it hidden until the course is on screen.
var hud_visible: bool = true:
	set(value):
		hud_visible = value
		_sync_visibility()

var _terrain_grid: TerrainGrid = null
var _entity_layer = null  # EntityLayer reference
var _golfer_manager = null  # GolferManager reference
var _camera_rect: Rect2 = Rect2()  # Camera viewport in world coordinates
var _map_texture: ImageTexture = null
var _needs_redraw: bool = true
var _update_timer: float = 0.0
var _is_dragging: bool = false  # Track drag state for click-and-drag navigation
var _touch_index: int = -1  # Active finger for direct minimap navigation
const UPDATE_INTERVAL: float = 0.5  # Redraw terrain every 0.5 seconds

## The colour of a walking path, for a theme that names no trail colour of its
## own (see CourseTheme.get_terrain_colors).
const TRAIL_COLOR := Color("c9bc98")

## The theme's own trail colour, re-read when the theme changes.
var _trail_color: Color = TRAIL_COLOR

func _refresh_trail_color() -> void:
	_trail_color = CourseTheme.get_terrain_colors(GameManager.current_theme).get("path", TRAIL_COLOR)

## The map colour of one tile: the same lookup the course surface paints the
## ground with, so the minimap, the Course Map and the course itself always agree
## about what a tile looks like. Woodland is one colour whatever the species — at
## this scale a pine and an oak are the same dark patch of trees.
func _terrain_color(terrain_type: int) -> Color:
	return CourseSurface.map_color(terrain_type)

# Land boundary colors
const BOUNDARY_COLOR = Color(0.9, 0.6, 0.2, 1.0)  # Orange/gold property line
const UNOWNED_TINT = Color(0.3, 0.2, 0.2, 0.4)    # Subtle dark tint on unowned

func _ready() -> void:
	custom_minimum_size = get_map_total_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("native_touch_input")
	apply_screen()
	_refresh_trail_color()
	# Listen for theme and preference changes
	if EventBus.has_signal("theme_changed") and not EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.connect(_on_theme_changed)
	if EventBus.has_signal("minimap_enabled_changed") and not EventBus.minimap_enabled_changed.is_connected(_on_minimap_enabled_changed):
		EventBus.minimap_enabled_changed.connect(_on_minimap_enabled_changed)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_sync_visibility()

func _exit_tree() -> void:
	if EventBus.has_signal("theme_changed") and EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)
	if EventBus.has_signal("minimap_enabled_changed") and EventBus.minimap_enabled_changed.is_connected(_on_minimap_enabled_changed):
		EventBus.minimap_enabled_changed.disconnect(_on_minimap_enabled_changed)

func _on_minimap_enabled_changed(_enabled: bool) -> void:
	_sync_visibility()

func _sync_visibility() -> void:
	if has_node("/root/Screen") and Screen.uses_portrait_hud() and not Screen.portrait_map_open:
		visible = false
		return
	visible = hud_visible and (GameManager.minimap_enabled or (has_node("/root/Screen") and Screen.uses_portrait_hud() and Screen.portrait_map_open))

func _on_visibility_changed() -> void:
	if not visible:
		_is_dragging = false
		_touch_index = -1
		return
	if _needs_redraw:
		_regenerate_map_texture()
		_needs_redraw = false
	queue_redraw()

## Total drawn size of the map (isometric diamond bounding box + border).
func get_map_total_size() -> Vector2:
	return Vector2(_map_size + BORDER_WIDTH * 2, _map_size / 2.0 + BORDER_WIDTH * 2)

## Pick the map size for the current window and reflow. Called from Main on
## every responsive window change.
func apply_screen() -> void:
	var new_size: int = COMPACT_MAP_SIZE if (has_node("/root/Screen") and Screen.is_compact()) else MAP_SIZE
	set_map_size(new_size)

## Set an explicit map size (independent of the window). Used by tests and
## anywhere a deterministic size is wanted; apply_screen() drives it from
## the window otherwise.
func set_map_size(new_size: int) -> void:
	if new_size <= 0 or new_size == _map_size:
		return
	_map_size = new_size
	custom_minimum_size = get_map_total_size()
	_needs_redraw = true
	queue_redraw()

func _on_theme_changed(_theme_type) -> void:
	_refresh_trail_color()
	_needs_redraw = true

func setup(terrain_grid: TerrainGrid, entity_layer, golfer_manager) -> void:
	_terrain_grid = terrain_grid
	_entity_layer = entity_layer
	_golfer_manager = golfer_manager
	_needs_redraw = true

	# Connect to terrain changes
	if terrain_grid:
		terrain_grid.tile_changed.connect(_on_terrain_changed)

	# Connect to land manager for property line updates
	call_deferred("_connect_land_signals")

func _on_terrain_changed(_pos: Vector2i, _old_type: int, _new_type: int) -> void:
	_needs_redraw = true

func _connect_land_signals() -> void:
	# Connect to land manager signals (deferred to ensure manager exists)
	if GameManager.land_manager:
		if not GameManager.land_manager.land_purchased.is_connected(_on_land_purchased):
			GameManager.land_manager.land_purchased.connect(_on_land_purchased)
		if not GameManager.land_manager.land_boundary_changed.is_connected(_on_land_boundary_changed):
			GameManager.land_manager.land_boundary_changed.connect(_on_land_boundary_changed)

func _on_land_purchased(_parcel: Vector2i) -> void:
	_needs_redraw = true
	queue_redraw()

func _on_land_boundary_changed() -> void:
	_needs_redraw = true
	queue_redraw()

func set_camera_rect(viewport_rect: Rect2, _grid_width: int, _grid_height: int) -> void:
	_camera_rect = viewport_rect
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		if _needs_redraw:
			_regenerate_map_texture()
			_needs_redraw = false
		queue_redraw()  # Redraw for golfer positions

func _regenerate_map_texture() -> void:
	if not _terrain_grid:
		return

	var grid_width = _terrain_grid.grid_width
	var grid_height = _terrain_grid.grid_height

	# Create image at appropriate resolution
	var img = Image.create(_map_size, _map_size, false, Image.FORMAT_RGBA8)

	# Sample terrain at reduced resolution
	for px in range(_map_size):
		for py in range(_map_size):
			# Map pixel to grid position
			var gx = int(float(px) / _map_size * grid_width)
			var gy = int(float(py) / _map_size * grid_height)
			var terrain_type = _terrain_grid.get_tile(Vector2i(gx, gy))

			var color = _terrain_color(terrain_type)
			if _terrain_grid.has_walking_path(Vector2i(gx, gy)):
				color = _trail_color
			img.set_pixel(px, py, color)

	_map_texture = ImageTexture.create_from_image(img)

func _draw() -> void:
	if not _terrain_grid:
		return
	var outline := _map_polygon()
	# Project the grid-space texture onto the same diamond as the course.
	if _map_texture:
		draw_polygon(outline, PackedColorArray([Color.WHITE]),
			PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]), _map_texture)
	var border := outline.duplicate()
	border.append(border[0])
	draw_polyline(border, Color(0.3, 0.3, 0.3), BORDER_WIDTH, true)

	# Draw land boundary (property lines)
	_draw_land_boundary()

	# Draw holes (tees and greens)
	_draw_holes()

	# Draw buildings
	_draw_buildings()

	# Draw active golfers
	_draw_golfers()

	# Draw camera viewport rectangle
	_draw_camera_rect()

func _draw_holes() -> void:
	if not GameManager.current_course:
		return

	for hole in GameManager.current_course.holes:
		# Tee position - small circle
		var tee_px = _grid_to_map_pos(hole.tee_position)
		draw_circle(tee_px, 3, Color(1.0, 1.0, 0.5))  # Yellow

		# Green position - small square
		var green_px = _grid_to_map_pos(hole.green_position)
		draw_rect(Rect2(green_px - Vector2(2, 2), Vector2(4, 4)), Color(0.2, 1.0, 0.2))  # Bright green

func _draw_buildings() -> void:
	if not _entity_layer:
		return

	var buildings = _entity_layer.get_all_buildings()
	for building in buildings:
		var start := Vector2(building.grid_position)
		var end := start + Vector2(building.width, building.height)
		draw_colored_polygon(_grid_rect_polygon(start, end), Color(0.6, 0.4, 0.2))

func _draw_golfers() -> void:
	if not _golfer_manager:
		return

	var golfers = _golfer_manager.get_active_golfers()
	for golfer in golfers:
		if golfer and is_instance_valid(golfer):
			var grid_pos = _terrain_grid.screen_to_grid(golfer.global_position)
			var map_pos = _grid_to_map_pos(grid_pos)
			draw_circle(map_pos, 2, Color(1.0, 0.3, 0.3))  # Red dots

func _draw_camera_rect() -> void:
	if _camera_rect.size.x <= 0 or _camera_rect.size.y <= 0:
		return

	var rect := _camera_rect
	var viewport_polygon := PackedVector2Array([
		_world_to_map_pos(rect.position),
		_world_to_map_pos(Vector2(rect.end.x, rect.position.y)),
		_world_to_map_pos(rect.end),
		_world_to_map_pos(Vector2(rect.position.x, rect.end.y)),
	])
	for clipped in Geometry2D.intersect_polygons(viewport_polygon, _map_polygon()):
		if clipped.size() < 3:
			continue
		clipped.append(clipped[0])
		draw_polyline(clipped, Color(1, 1, 1, 0.8), 2.0, true)

func _draw_land_boundary() -> void:
	if not GameManager.land_manager or not _terrain_grid:
		return

	var lm = GameManager.land_manager
	var parcel_size = lm.PARCEL_SIZE  # 20 tiles per parcel
	var cols = lm.PARCEL_GRID_COLS    # 6 columns
	var rows = lm.PARCEL_GRID_ROWS    # 6 rows
	var offset = lm.GRID_OFFSET       # 4 tiles margin

	# Draw tint on unowned parcels
	for px in range(cols):
		for py in range(rows):
			var parcel_pos = Vector2i(px, py)
			if not lm.owned_parcels.has(parcel_pos):
				# Calculate parcel bounds in map pixels (account for grid offset)
				var grid_start = Vector2i(offset + px * parcel_size, offset + py * parcel_size)
				var grid_end = Vector2i(offset + (px + 1) * parcel_size, offset + (py + 1) * parcel_size)
				draw_colored_polygon(_grid_rect_polygon(Vector2(grid_start), Vector2(grid_end)), UNOWNED_TINT)

	# Draw property lines at parcel boundaries
	for px in range(cols):
		for py in range(rows):
			var parcel_pos = Vector2i(px, py)
			var is_owned = lm.owned_parcels.has(parcel_pos)
			if not is_owned:
				continue  # Only draw borders from owned side

			var grid_x = offset + px * parcel_size
			var grid_y = offset + py * parcel_size

			# Check right neighbor
			if px < cols - 1:
				var right = Vector2i(px + 1, py)
				if not lm.owned_parcels.has(right):
					var start = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y))
					var end = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y + parcel_size))
					draw_line(start, end, BOUNDARY_COLOR, 1.5)

			# Check bottom neighbor
			if py < rows - 1:
				var bottom = Vector2i(px, py + 1)
				if not lm.owned_parcels.has(bottom):
					var start = _grid_to_map_pos(Vector2i(grid_x, grid_y + parcel_size))
					var end = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y + parcel_size))
					draw_line(start, end, BOUNDARY_COLOR, 1.5)

			# Check left neighbor
			if px > 0:
				var left = Vector2i(px - 1, py)
				if not lm.owned_parcels.has(left):
					var start = _grid_to_map_pos(Vector2i(grid_x, grid_y))
					var end = _grid_to_map_pos(Vector2i(grid_x, grid_y + parcel_size))
					draw_line(start, end, BOUNDARY_COLOR, 1.5)

			# Check top neighbor
			if py > 0:
				var top = Vector2i(px, py - 1)
				if not lm.owned_parcels.has(top):
					var start = _grid_to_map_pos(Vector2i(grid_x, grid_y))
					var end = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y))
					draw_line(start, end, BOUNDARY_COLOR, 1.5)

			# Draw border at map edges for owned edge parcels
			if px == 0:
				var start = _grid_to_map_pos(Vector2i(grid_x, grid_y))
				var end = _grid_to_map_pos(Vector2i(grid_x, grid_y + parcel_size))
				draw_line(start, end, BOUNDARY_COLOR, 1.5)
			if py == 0:
				var start = _grid_to_map_pos(Vector2i(grid_x, grid_y))
				var end = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y))
				draw_line(start, end, BOUNDARY_COLOR, 1.5)
			if px == cols - 1:
				var start = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y))
				var end = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y + parcel_size))
				draw_line(start, end, BOUNDARY_COLOR, 1.5)
			if py == rows - 1:
				var start = _grid_to_map_pos(Vector2i(grid_x, grid_y + parcel_size))
				var end = _grid_to_map_pos(Vector2i(grid_x + parcel_size, grid_y + parcel_size))
				draw_line(start, end, BOUNDARY_COLOR, 1.5)

func _map_scale() -> float:
	return float(_map_size) / _terrain_grid.projection.world_bounds().size.x

func _world_to_map_pos(world_pos: Vector2) -> Vector2:
	return Vector2(BORDER_WIDTH, BORDER_WIDTH) + (world_pos - _terrain_grid.projection.world_bounds().position) * _map_scale()

func _grid_to_map_pos(grid_pos: Vector2) -> Vector2:
	if not _terrain_grid:
		return Vector2.ZERO
	return _world_to_map_pos(_terrain_grid.projection.project(grid_pos))

func _grid_rect_polygon(start: Vector2, end: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		_grid_to_map_pos(start), _grid_to_map_pos(Vector2(end.x, start.y)),
		_grid_to_map_pos(end), _grid_to_map_pos(Vector2(start.x, end.y)),
	])

func _map_polygon() -> PackedVector2Array:
	return _grid_rect_polygon(Vector2.ZERO, Vector2(_terrain_grid.grid_width, _terrain_grid.grid_height))

func _map_to_world_pos(map_pos: Vector2) -> Vector2:
	if not _terrain_grid:
		return Vector2.ZERO
	return (map_pos - Vector2(BORDER_WIDTH, BORDER_WIDTH)) / _map_scale() + _terrain_grid.projection.world_bounds().position

func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

func _navigate_to_map_pos(map_pos: Vector2) -> void:
	camera_move_requested.emit(_map_to_world_pos(map_pos))

# Transparent corners should not intercept clicks intended for the course.
func _has_point(point: Vector2) -> bool:
	return _is_within_map(point)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var local_pos = event.position
				# Check if click is within map area
				if _is_within_map(local_pos):
					_is_dragging = true
					var world_pos = _map_to_world_pos(local_pos)
					camera_move_requested.emit(world_pos)
					accept_event()
			else:
				# Mouse button released
				_is_dragging = false

	elif event is InputEventMouseMotion and _is_dragging:
		var local_pos = event.position
		# Continue moving camera while dragging within map area
		if _is_within_map(local_pos):
			var world_pos = _map_to_world_pos(local_pos)
			camera_move_requested.emit(world_pos)
			accept_event()

func _is_within_map(local_pos: Vector2) -> bool:
	return _terrain_grid != null and Geometry2D.is_point_in_polygon(local_pos, _map_polygon())

func _input(event: InputEvent) -> void:
	# Native touch events are not mouse-emulated in this game. Handle the map
	# directly so a finger can tap or scrub it to move the camera rather than
	# being treated as a world pan by the shared gesture adapter.
	if event is InputEventScreenTouch and visible:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# A dialogue or panel drawn over the minimap owns the touch, so a
			# button on top of the map stays tappable.
			if _touch_index == -1 and _is_within_map(_screen_to_local(touch.position)) \
					and TouchInput.owns_native_touch(self, touch.position):
				_touch_index = touch.index
				_is_dragging = true
				_navigate_to_map_pos(_screen_to_local(touch.position))
				get_viewport().set_input_as_handled()
		elif touch.index == _touch_index:
			_touch_index = -1
			_is_dragging = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag and visible and event.index == _touch_index:
		var drag := event as InputEventScreenDrag
		var local_pos := _screen_to_local(drag.position)
		if _is_within_map(local_pos):
			_navigate_to_map_pos(local_pos)
		get_viewport().set_input_as_handled()
		return

	# Don't process any gameplay hotkeys while in main menu
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return

	# Toggle visibility with Tab key - except while a screen or panel is open,
	# where Tab moves focus between its controls instead.
	if not hud_visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if has_node("/root/InputManager") and InputManager.has_visible_scope():
			return
		# Don't process hotkeys if a text input has focus
		var focused = get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return
		if event.keycode == KEY_TAB and not event.is_command_or_control_pressed() \
				and not event.shift_pressed and focused == null:
			GameManager.set_minimap_enabled(not GameManager.minimap_enabled)
			if has_node("/root/SaveManager"):
				SaveManager.set_user_preference("display", "minimap_enabled", GameManager.minimap_enabled)
			get_viewport().set_input_as_handled()

func force_redraw() -> void:
	_needs_redraw = true
