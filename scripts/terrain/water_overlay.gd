extends Node2D
class_name WaterOverlay
## WaterOverlay - Renders animated shimmer effect on water tiles

var terrain_grid: TerrainGrid
var _water_positions: Dictionary = {}  # Vector2i -> true
var _time: float = 0.0
var _water_color: Color = Color(0.25, 0.55, 0.85)  # Default, updated by theme
var _is_web: bool = false
var _redraw_interval: float = 0.066  # Updated from the active graphics profile
var _redraw_timer: float = 0.0

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = 1  # Render just above terrain tiles
	_is_web = OS.get_name() == "Web"
	_update_redraw_interval()
	_scan_water_tiles()
	_update_water_color()
	EventBus.terrain_tile_changed.connect(_on_terrain_tile_changed)
	EventBus.theme_changed.connect(_on_theme_changed)
	EventBus.load_completed.connect(_on_load_completed)
	PerformanceSettings.profile_changed.connect(_on_performance_profile_changed)

func _on_theme_changed(_theme_type: int) -> void:
	_update_water_color()
	queue_redraw()

func _on_load_completed(success: bool) -> void:
	if success:
		_scan_water_tiles()
		queue_redraw()

func _update_water_color() -> void:
	_water_color = TerrainPalette.get_color("water")

func _exit_tree() -> void:
	if EventBus.terrain_tile_changed.is_connected(_on_terrain_tile_changed):
		EventBus.terrain_tile_changed.disconnect(_on_terrain_tile_changed)
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if PerformanceSettings.profile_changed.is_connected(_on_performance_profile_changed):
		PerformanceSettings.profile_changed.disconnect(_on_performance_profile_changed)

func _on_performance_profile_changed(_terrain_fast: bool) -> void:
	_update_redraw_interval()
	queue_redraw()

func _update_redraw_interval() -> void:
	_redraw_interval = PerformanceSettings.animation_redraw_interval()
	if _is_web:
		_redraw_interval = maxf(_redraw_interval, 0.25)

func _scan_water_tiles() -> void:
	_water_positions.clear()
	if not terrain_grid:
		return
	for x in range(terrain_grid.grid_width):
		for y in range(terrain_grid.grid_height):
			var pos = Vector2i(x, y)
			if terrain_grid.get_tile(pos) == TerrainTypes.Type.WATER:
				_water_positions[pos] = true

func _on_terrain_tile_changed(tile_pos: Vector2i, old_type: int, new_type: int) -> void:
	if new_type == TerrainTypes.Type.WATER:
		_water_positions[tile_pos] = true
	elif old_type == TerrainTypes.Type.WATER:
		_water_positions.erase(tile_pos)
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	_redraw_timer += delta / maxf(Engine.time_scale, 0.01)
	if _redraw_timer >= _redraw_interval:
		_redraw_timer = 0.0
		queue_redraw()

func _draw() -> void:
	if not terrain_grid or _water_positions.is_empty():
		return

	var visible_rect := terrain_grid.get_visible_world_rect().grow_individual(
			terrain_grid.tile_width, terrain_grid.tile_height,
			terrain_grid.tile_width, terrain_grid.tile_height)
	var bounds := terrain_grid.get_visible_tile_range()
	if bounds.size() < 2:
		return
	var first: Vector2i = bounds[0]
	var last: Vector2i = bounds[1]
	var visible_area := maxi(0, last.x - first.x + 1) * maxi(0, last.y - first.y + 1)
	var reduced_detail := PerformanceSettings.water_quality == PerformanceSettings.WaterQuality.REDUCED

	# Sparse ponds are cheaper to visit directly; broad water bodies are cheaper
	# to query through the viewport's bounded tile range.
	if _water_positions.size() <= visible_area:
		for pos in _water_positions:
			_draw_water_tile(pos, visible_rect, reduced_detail)
	else:
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var pos := Vector2i(x, y)
				if _water_positions.has(pos):
					_draw_water_tile(pos, visible_rect, reduced_detail)

func _draw_water_tile(pos: Vector2i, visible_rect: Rect2, reduced_detail: bool) -> void:
	var screen_pos := terrain_grid.grid_to_screen(pos)
	if not visible_rect.has_point(screen_pos):
		return
	var local_pos := to_local(screen_pos)
	var wave_offset := float(pos.x * 3 + pos.y * 7)
	var alpha := 0.1 + 0.08 * sin(_time * 2.5 + wave_offset)
	var highlight_alpha := 0.06 + 0.05 * sin(_time * 1.8 + wave_offset + 1.5)
	var tile_rect := Rect2(local_pos, Vector2(terrain_grid.tile_width, terrain_grid.tile_height))
	var shimmer_color := Color(
		minf(_water_color.r + 0.25, 1.0),
		minf(_water_color.g + 0.20, 1.0),
		minf(_water_color.b + 0.15, 1.0), alpha)
	draw_rect(tile_rect, shimmer_color)

	var streak_y := local_pos.y + terrain_grid.tile_height * 0.25
	if not reduced_detail:
		streak_y += sin(_time * 1.5 + wave_offset) * 3.0
	var highlight_color := Color(
		minf(_water_color.r + 0.55, 1.0),
		minf(_water_color.g + 0.40, 1.0),
		minf(_water_color.b + 0.15, 1.0), highlight_alpha)
	draw_rect(Rect2(Vector2(local_pos.x + 6, streak_y),
		Vector2(terrain_grid.tile_width * 0.5, 2)), highlight_color)

	# Reduced water detail keeps a single quiet shimmer per tile; Web also skips
	# the optional second streak and sparkle dots to limit CanvasItem commands.
	if _is_web or reduced_detail:
		return
	var streak_y2 := local_pos.y + terrain_grid.tile_height * 0.6 \
			+ sin(_time * 1.2 + wave_offset + 2.0) * 4.0
	draw_rect(Rect2(Vector2(local_pos.x + terrain_grid.tile_width * 0.3, streak_y2),
		Vector2(terrain_grid.tile_width * 0.4, 2)),
		Color(highlight_color.r, highlight_color.g, highlight_color.b, highlight_alpha * 0.8))
	var sparkle_alpha := 0.3 + 0.3 * sin(_time * 4.0 + wave_offset * 2.0)
	if sparkle_alpha > 0.4:
		var sparkle_x := local_pos.x + 10 + (pos.x % 3) * 15
		var sparkle_y := local_pos.y + 8 + (pos.y % 2) * 10
		draw_circle(Vector2(sparkle_x, sparkle_y), 1.5,
			Color(1.0, 1.0, 1.0, sparkle_alpha * 0.5))
