extends Node2D
class_name HoleVisualizer
## HoleVisualizer - Manages visual representation of a golf hole

var hole_data: GameManager.HoleData
var terrain_grid: TerrainGrid
var flag: Flag

# Visual components
var line: Line2D
var tee_number_sprite: Sprite2D
const TEE_OCCLUSION: Shader = preload("res://shaders/terrain_sprite_occlusion.gdshader")
const TEE_CORNER := Vector2(17, 0)
var _tee_occlusion_material: ShaderMaterial
const TEE_NUMBER_LAYOUT = preload("res://assets/sprites/tee_numbers/layout.json")
# Shared metadata: each complete sprite has its own cropped-canvas foot anchor.
static var _tee_layout: Dictionary = {}
var waypoint_markers: Array[Node2D] = []
var carry_annotations: Array[Node2D] = []
static var carry_annotations_visible: bool = false  # Toggled by J hotkey with fairway width
var _line_update_pending: bool = false
var _highlighted: bool = false

signal hole_selected(hole_number: int)

func _ready() -> void:
	# Participate in the world Y-sort; only selection annotations are overlays.
	z_index = 0
	y_sort_enabled = true

func initialize(hole: GameManager.HoleData, grid: TerrainGrid) -> void:
	hole_data = hole
	terrain_grid = grid
	_create_visuals()
	EventBus.terrain_tile_changed.connect(_on_terrain_tile_changed)
	terrain_grid.view_rotated.connect(_on_tee_view_rotated)
	terrain_grid.vertex_elevation_changed.connect(_on_tee_elevation_changed)
	terrain_grid.terrain_occlusion_changed.connect(_on_tee_occlusion_changed)

func _create_visuals() -> void:
	# Create shot path line (routed through golfer AI waypoints)
	_create_connection_line()

	# Create flag at hole position
	_create_flag()

	# Create a baked number sign inside the tee corner
	_create_tee_number_sprite()

	# Create forced carry annotations
	_update_carry_annotations()

func _create_connection_line() -> void:
	if line:
		remove_child(line)
		line.free()

	line = Line2D.new()
	line.name = "ConnectionLine"
	line.width = 3.0 if _highlighted else 1.0
	line.default_color = Color(1, 1, 0, 0.7) if _highlighted else Color(0.96, 0.91, 0.70, 0.24)
	line.antialiased = true
	line.z_index = 9  # Selection route above the world, beneath annotations
	line.visible = _highlighted
	add_child(line)

	_update_line()

func _update_line() -> void:
	if not line or not terrain_grid or not hole_data:
		return

	# Calculate shot path waypoints using golfer AI logic
	var waypoints: Array[Vector2i] = ShotPathCalculator.calculate_waypoints(hole_data, terrain_grid)

	# Draw line through all waypoints (only shown while the hole is selected)
	line.clear_points()
	for wp in waypoints:
		var screen_pos: Vector2 = terrain_grid.grid_to_screen_center(wp)
		line.add_point(to_local(screen_pos))
	line.visible = _highlighted

	# Update landing zone markers at intermediate waypoints
	_update_waypoint_markers(waypoints)

func _update_waypoint_markers(waypoints: Array[Vector2i]) -> void:
	# Reuse marker nodes when terrain edits change the route. Apart from avoiding
	# allocations this keeps the selection highlight across recalculations.
	var count := maxi(waypoints.size() - 2, 0)
	while waypoint_markers.size() > count:
		var marker: Node2D = waypoint_markers.pop_back()
		if is_instance_valid(marker):
			remove_child(marker)
			marker.free()
	for i in range(count):
		var marker: Node2D
		if i < waypoint_markers.size():
			marker = waypoint_markers[i]
			marker.position = to_local(terrain_grid.grid_to_screen_center(waypoints[i + 1]))
		else:
			marker = _create_waypoint_marker(waypoints[i + 1])
			add_child(marker)
			waypoint_markers.append(marker)
		marker.visible = _highlighted
		var inner: Polygon2D = marker.get_child(1)
		inner.color = Color(1.0, 1.0, 0.3, 0.8) if _highlighted else Color(0.5, 0.85, 1.0, 0.7)

func _create_waypoint_marker(grid_pos: Vector2i) -> Node2D:
	var marker := Node2D.new()
	var screen_pos: Vector2 = terrain_grid.grid_to_screen_center(grid_pos)
	marker.position = to_local(screen_pos)
	marker.z_index = 9
	marker.visible = _highlighted

	# Outer ring (dark outline for contrast)
	var outer_ring := Polygon2D.new()
	var outer_points := PackedVector2Array()
	for i in range(12):
		var angle: float = (i / 12.0) * TAU
		outer_points.append(Vector2(cos(angle) * 5.0, sin(angle) * 5.0))
	outer_ring.polygon = outer_points
	outer_ring.color = Color(0.0, 0.0, 0.0, 0.5)
	marker.add_child(outer_ring)

	# Inner filled circle (landing zone indicator)
	var inner_circle := Polygon2D.new()
	var inner_points := PackedVector2Array()
	for i in range(12):
		var angle: float = (i / 12.0) * TAU
		inner_points.append(Vector2(cos(angle) * 3.5, sin(angle) * 3.5))
	inner_circle.polygon = inner_points
	inner_circle.color = Color(0.5, 0.85, 1.0, 0.7)  # Light blue
	marker.add_child(inner_circle)

	return marker

func _create_flag() -> void:
	if flag:
		# Disconnect signals before freeing to prevent leaks
		if flag.flag_selected.is_connected(_on_flag_selected):
			flag.flag_selected.disconnect(_on_flag_selected)
		remove_child(flag)
		flag.free()

	flag = Flag.new()
	flag.name = "Flag"
	flag.set_terrain_grid(terrain_grid)
	flag.set_hole_number(hole_data.hole_number)
	flag.set_position_in_grid(hole_data.hole_position)
	add_child(flag)

	# Connect flag signals
	flag.flag_selected.connect(_on_flag_selected)

func _create_tee_number_sprite() -> void:
	if tee_number_sprite:
		remove_child(tee_number_sprite)
		tee_number_sprite.free()
	tee_number_sprite = Sprite2D.new()
	tee_number_sprite.name = "TeeNumberSprite"
	tee_number_sprite.centered = false
	# Same depth band as trees, pins and golfers, sorted at its ground contact.
	tee_number_sprite.z_as_relative = false
	tee_number_sprite.z_index = 2
	tee_number_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(tee_number_sprite)
	_update_tee_number_sprite()

func _update_tee_number_sprite() -> void:
	if not tee_number_sprite or not terrain_grid or not hole_data:
		return
	if _tee_layout.is_empty():
		_tee_layout = TEE_NUMBER_LAYOUT.data
	var file_name := "%d.png" % hole_data.hole_number
	var sprites: Dictionary = _tee_layout.get("sprites", {})
	# Unsupported custom-course numbers must not silently show the wrong hole.
	tee_number_sprite.visible = sprites.has(file_name)
	if not tee_number_sprite.visible:
		return
	tee_number_sprite.texture = load("res://assets/sprites/tee_numbers/" + file_name)
	var draw_scale: float = _tee_layout.get("scale", 0.5)
	tee_number_sprite.scale = Vector2.ONE * draw_scale
	var anchor: Array = sprites[file_name]
	tee_number_sprite.offset = -tee_number_sprite.texture.get_size() * Vector2(anchor[0], anchor[1])
	# Use the actual fractional corner height, not the tile centre's elevation.
	var ground := terrain_grid.tile_local_grid_point(hole_data.tee_position, TEE_CORNER)
	tee_number_sprite.global_position = terrain_grid.grid_point_to_screen(ground)
	if terrain_grid.terrain_occlusion_enabled() and terrain_grid._course_surface != null:
		if _tee_occlusion_material == null:
			_tee_occlusion_material = ShaderMaterial.new()
			_tee_occlusion_material.shader = TEE_OCCLUSION
			_tee_occlusion_material.set_shader_parameter("occlusion_epsilon", TerrainOcclusion.PROP_EPSILON)
		terrain_grid._course_surface.configure_sprite_occlusion(_tee_occlusion_material, ground, Vector2.ZERO)
		tee_number_sprite.material = _tee_occlusion_material
	else:
		tee_number_sprite.material = null

func _on_tee_view_rotated(_orientation: int, _isometric: bool) -> void:
	_update_tee_number_sprite()

func _on_tee_elevation_changed(_vertex: Vector2i, _old: int, _new: int) -> void:
	# Sculpting can change the corner height without changing terrain type/par.
	_update_tee_number_sprite()

func _on_tee_occlusion_changed(_enabled: bool) -> void:
	_update_tee_number_sprite()

func set_visible_state(visible_state: bool) -> void:
	visible = visible_state

func highlight(enabled: bool) -> void:
	_highlighted = enabled
	if not line:
		return

	line.visible = enabled
	if enabled:
		line.default_color = Color(1, 1, 0, 0.7)  # Yellow when highlighted
		line.width = 3.0
		for marker in waypoint_markers:
			if is_instance_valid(marker):
				marker.visible = true
				var inner: Polygon2D = marker.get_child(1) if marker.get_child_count() > 1 else null
				if inner:
					inner.color = Color(1.0, 1.0, 0.3, 0.8)  # Yellow to match line
	else:
		line.default_color = Color(0.96, 0.91, 0.70, 0.24)  # Normal white
		line.width = 1.0
		for marker in waypoint_markers:
			if is_instance_valid(marker):
				marker.visible = false
				var inner: Polygon2D = marker.get_child(1) if marker.get_child_count() > 1 else null
				if inner:
					inner.color = Color(0.5, 0.85, 1.0, 0.7)  # Normal light blue

func _on_flag_selected(_selected_flag: Flag) -> void:
	hole_selected.emit(hole_data.hole_number)

func _on_terrain_tile_changed(_position: Vector2i, _old_type: int, _new_type: int) -> void:
	# Debounce: only recalculate once per frame even if many tiles change
	if not _line_update_pending:
		_line_update_pending = true
		call_deferred("_deferred_terrain_update")

func _deferred_terrain_update() -> void:
	_line_update_pending = false
	if hole_data and terrain_grid:
		var new_difficulty = DifficultyCalculator.calculate_hole_difficulty(hole_data, terrain_grid)
		if absf(new_difficulty - hole_data.difficulty_rating) > 0.05:
			hole_data.difficulty_rating = new_difficulty
			_update_tee_number_sprite()
			EventBus.hole_difficulty_changed.emit(hole_data.hole_number, new_difficulty)

		_update_tee_number_sprite()

		# Recalculate shot path (terrain changes affect golfer routing)
		_update_line()
		_update_carry_annotations()

func update_tee_position(new_tee_pos: Vector2i) -> void:
	hole_data.tee_position = new_tee_pos
	hole_data.distance_yards = terrain_grid.calculate_distance_yards(new_tee_pos, hole_data.hole_position)
	_recalculate_par_with_override()
	hole_data.difficulty_rating = DifficultyCalculator.calculate_hole_difficulty(hole_data, terrain_grid)
	_update_line()
	_update_tee_number_sprite()
	_update_carry_annotations()
	EventBus.hole_updated.emit(hole_data.hole_number)

func update_green_position(new_green_pos: Vector2i) -> void:
	hole_data.green_position = new_green_pos
	# The cup is the hole's Green With Hole tile, so it moves with the green.
	hole_data.hole_position = new_green_pos
	if flag:
		flag.set_position_in_grid(new_green_pos)
	hole_data.distance_yards = terrain_grid.calculate_distance_yards(hole_data.tee_position, hole_data.hole_position)
	_recalculate_par_with_override()
	hole_data.difficulty_rating = DifficultyCalculator.calculate_hole_difficulty(hole_data, terrain_grid)
	_update_line()
	_update_tee_number_sprite()
	_update_carry_annotations()
	EventBus.hole_updated.emit(hole_data.hole_number)

func _recalculate_par_with_override() -> void:
	var auto_par = HoleCreationTool.calculate_par(hole_data.distance_yards)
	if hole_data.par_override > 0 and abs(hole_data.par_override - auto_par) <= 1:
		hole_data.par = hole_data.par_override
	else:
		hole_data.par_override = -1
		hole_data.par = auto_par

func _update_carry_annotations() -> void:
	for ann in carry_annotations:
		if is_instance_valid(ann):
			remove_child(ann)
			ann.free()
	carry_annotations.clear()

	if not hole_data or not terrain_grid:
		return
	if not carry_annotations_visible:
		return

	var segments = ForcedCarryCalculator.calculate_carries(hole_data, terrain_grid)
	for seg in segments:
		var ann = _create_carry_annotation(seg)
		add_child(ann)
		carry_annotations.append(ann)

func _create_carry_annotation(seg: ForcedCarryCalculator.CarrySegment) -> Node2D:
	var ann = Node2D.new()
	ann.z_index = 10

	var start_screen = terrain_grid.grid_to_screen_center(seg.start_grid)
	var end_screen = terrain_grid.grid_to_screen_center(seg.end_grid)
	var color = Color(0.9, 0.2, 0.2, 0.9) if seg.exceeds_beginner_range else Color(0.9, 0.5, 0.1, 0.8)

	# Draw carry line as series of short dashes
	var from_local = to_local(start_screen)
	var to_local_pos = to_local(end_screen)
	var dir = to_local_pos - from_local
	var total_len = dir.length()
	if total_len < 1.0:
		return ann
	var norm_dir = dir / total_len
	var dash_len = 6.0
	var gap_len = 4.0
	var pos = 0.0
	while pos < total_len:
		var dash_end = minf(pos + dash_len, total_len)
		var dash_line = Line2D.new()
		dash_line.width = 1.0
		dash_line.default_color = color
		dash_line.add_point(from_local + norm_dir * pos)
		dash_line.add_point(from_local + norm_dir * dash_end)
		ann.add_child(dash_line)
		pos = dash_end + gap_len

	# Yardage label at midpoint
	var mid = (from_local + to_local_pos) / 2.0
	var label = Label.new()
	label.text = "%dy carry" % seg.carry_yards
	label.position = mid + Vector2(-25, -15)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	ann.add_child(label)

	return ann

func update_visualization() -> void:
	_update_line()
	_update_tee_number_sprite()
	_update_carry_annotations()

func refresh_positions() -> void:
	if flag and is_instance_valid(flag) and hole_data:
		flag.set_position_in_grid(hole_data.hole_position)
	update_visualization()

func get_hole_number() -> int:
	return hole_data.hole_number if hole_data else 0

func _exit_tree() -> void:
	if is_instance_valid(terrain_grid):
		if terrain_grid.view_rotated.is_connected(_on_tee_view_rotated):
			terrain_grid.view_rotated.disconnect(_on_tee_view_rotated)
		if terrain_grid.vertex_elevation_changed.is_connected(_on_tee_elevation_changed):
			terrain_grid.vertex_elevation_changed.disconnect(_on_tee_elevation_changed)
		if terrain_grid.terrain_occlusion_changed.is_connected(_on_tee_occlusion_changed):
			terrain_grid.terrain_occlusion_changed.disconnect(_on_tee_occlusion_changed)
	if EventBus.terrain_tile_changed.is_connected(_on_terrain_tile_changed):
		EventBus.terrain_tile_changed.disconnect(_on_terrain_tile_changed)

func destroy() -> void:
	if flag:
		flag.destroy()
	queue_free()
