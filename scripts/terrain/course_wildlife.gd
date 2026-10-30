extends Node2D
class_name CourseWildlife
## Small, purely visual residents. No collision, maintenance, RNG, or save data.
## Cached habitats rebuild after edits; the draw loop visits only bounded residents.

const MAX_DUCK_FAMILIES := 12
const MAX_GARDENS := 24
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BUTTERFLY_COLORS := [Color("ffcb67"), Color("eaa9cf"), Color("aad8ee")]
var terrain_grid: TerrainGrid
var _water_tiles: Dictionary = {}
var _flower_tiles: Dictionary = {}
var _duck_homes: Array[Vector2i] = []
var _garden_homes: Array[Vector2i] = []
var _time := 0.0
var _refresh_elapsed := 0.0
var _draw_elapsed := 0.0
var _draw_interval := 1.0 / 15.0
var _habitats_dirty := false

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = 1 # Water residents sit below the trees, golfers, and UI.
	grid.tile_changed.connect(_on_tile_changed)
	EventBus.load_completed.connect(_on_load_completed)
	PerformanceSettings.profile_changed.connect(_on_performance_profile_changed)
	_apply_wildlife_quality()
	rebuild()

func _exit_tree() -> void:
	if is_instance_valid(terrain_grid) and terrain_grid.tile_changed.is_connected(_on_tile_changed):
		terrain_grid.tile_changed.disconnect(_on_tile_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if PerformanceSettings.profile_changed.is_connected(_on_performance_profile_changed):
		PerformanceSettings.profile_changed.disconnect(_on_performance_profile_changed)

func _on_performance_profile_changed(_low_detail: bool) -> void:
	_update_draw_interval()
	_apply_wildlife_quality()
	_refresh_residents()

## Wildlife is decoration: a device that needs the frames more than the ducks
## can switch the residents off, or keep half of them. The overlay still holds
## its habitat cache so putting them back costs one refresh, not a new course.
func _apply_wildlife_quality() -> void:
	visible = PerformanceSettings.wildlife_detail != PerformanceSettings.WildlifeDetail.OFF

func _update_draw_interval() -> void:
	_draw_interval = PerformanceSettings.animation_redraw_interval()

## How many residents of a kind the current quality keeps.
func _resident_limit(base_limit: int) -> int:
	return int(floor(float(base_limit) * PerformanceSettings.wildlife_density()))

func _on_load_completed(success: bool) -> void:
	if success:
		rebuild()

func _on_tile_changed(pos: Vector2i, _old: int, type: int) -> void:
	_track_tile(pos, type)
	_habitats_dirty = true

func _track_tile(pos: Vector2i, type: int) -> void:
	_water_tiles.erase(pos)
	_flower_tiles.erase(pos)
	if type == TerrainTypes.Type.WATER:
		_water_tiles[pos] = true
	elif type == TerrainTypes.Type.FLOWER_BED:
		_flower_tiles[pos] = true

func rebuild() -> void:
	_water_tiles.clear()
	_flower_tiles.clear()
	for x in range(terrain_grid.grid_width):
		for y in range(terrain_grid.grid_height):
			var pos := Vector2i(x, y)
			_track_tile(pos, terrain_grid.get_tile(pos))
	_refresh_residents()

func _refresh_residents() -> void:
	var ponds: Array[Vector2i] = []
	for pos in _water_tiles:
		var wet_neighbors := 0
		for offset in NEIGHBORS:
			if _water_tiles.has(pos + offset):
				wet_neighbors += 1
		# Skip isolated painted puddles and fragile one-tile-wide corners.
		if wet_neighbors >= 3:
			ponds.append(pos)
	_duck_homes = _spaced_homes(ponds, _resident_limit(MAX_DUCK_FAMILIES), 5.0)
	var gardens: Array[Vector2i] = []
	for pos in _flower_tiles:
		gardens.append(pos)
	_garden_homes = _spaced_homes(gardens, _resident_limit(MAX_GARDENS), 2.0)
	_habitats_dirty = false
	_refresh_elapsed = 0.0
	queue_redraw()

func _spaced_homes(candidates: Array[Vector2i], limit: int, spacing: float) -> Array[Vector2i]:
	if limit <= 0:
		return []
	# Prefer the playable center; stable tie-breaking makes load/new-game repeatable.
	var center := Vector2(terrain_grid.grid_width, terrain_grid.grid_height) * 0.5
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Vector2(a).distance_squared_to(center)
		var db := Vector2(b).distance_squared_to(center)
		return da < db if da != db else a.y * terrain_grid.grid_width + a.x < b.y * terrain_grid.grid_width + b.x)
	var homes: Array[Vector2i] = []
	for pos in candidates:
		var crowded := false
		for other in homes:
			if Vector2(pos).distance_to(Vector2(other)) < spacing:
				crowded = true
				break
		if not crowded:
			homes.append(pos)
			if homes.size() >= limit:
				break
	return homes

func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	_refresh_elapsed += real_delta
	if _habitats_dirty and _refresh_elapsed >= 0.25:
		_refresh_residents()
	# Nothing to animate while the residents are switched off; skip the clock
	# and the redraws that would only be thrown away.
	if not visible or GameManager.is_paused or GameManager.current_speed == GameManager.GameSpeed.PAUSED:
		return
	_time += real_delta
	_draw_elapsed += real_delta
	if _draw_elapsed >= _draw_interval:
		_draw_elapsed = 0.0
		queue_redraw()

static func duck_offset(phase: float) -> Vector2:
	# Complete route fits inside the center of a 64x32 water tile, including bodies.
	return Vector2(cos(phase) * 17.0, sin(phase) * 5.5)

static func butterflies_active(season: int, raining: bool) -> bool:
	# It is always daytime on the course now, so butterflies appear in any fair
	# season unless it's raining.
	return season != SeasonSystem.Season.WINTER and not raining

func _draw() -> void:
	if not terrain_grid or not visible:
		return
	var weather := GameManager.weather_system
	var raining := is_instance_valid(weather) and weather.is_raining()
	var storm := is_instance_valid(weather) and weather.weather_type == WeatherSystem.WeatherType.HEAVY_RAIN
	var season := SeasonSystem.get_season(GameManager.current_day)
	var view := terrain_grid.get_visible_world_rect().grow(60.0)
	if not storm:
		for home in _duck_homes:
			# Recheck the tile immediately, so painting land never leaves a stranded duck.
			if terrain_grid.get_tile(home) != TerrainTypes.Type.WATER:
				continue
			var center := terrain_grid.grid_to_screen_center(home)
			if view.has_point(center):
				_draw_family(center, _time * 0.32 + float(home.x * 3 + home.y) * 0.7)
	var butterflies := butterflies_active(season, raining)
	for home in _garden_homes:
		var center := terrain_grid.grid_to_screen_center(home)
		if not view.has_point(center):
			continue
		var phase := float(home.x * 13 + home.y * 7)
		if butterflies:
			_draw_butterfly(center, phase, BUTTERFLY_COLORS[posmod(home.x + home.y, BUTTERFLY_COLORS.size())])

func _draw_family(center: Vector2, phase: float) -> void:
	# Two gold ducklings follow the adult around a lazy oval.
	for i in range(2, -1, -1):
		var t := phase - float(i) * 0.65
		var p := (center + duck_offset(t)).round()
		var facing := -1.0 if sin(t) > 0.0 else 1.0
		_draw_duck(p, facing, i > 0)

func _draw_duck(p: Vector2, facing: float, chick: bool) -> void:
	var scale_factor := 0.58 if chick else 1.0
	var wake := Color(0.77, 0.93, 0.84, 0.25)
	draw_arc(p + Vector2(-facing * 5.0, 2.0), 8.0 * scale_factor, 0.15, PI - 0.15, 10, wake, 1.0)
	draw_set_transform(p, 0.0, Vector2(facing * scale_factor, scale_factor))
	draw_colored_polygon(PackedVector2Array([Vector2(-9, -1), Vector2(-5, -6), Vector2(2, -6), Vector2(7, -2), Vector2(5, 3), Vector2(-4, 3)]), Color("edca67") if chick else Color("f4efdc"))
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -2), Vector2(-12, -5), Vector2(-9, 1)]), Color("d3a44c") if chick else Color("c3c9b5"))
	draw_circle(Vector2(5, -7), 4.0, Color("ffe58c") if chick else Color("fdf8e9"))
	draw_line(Vector2(8, -6), Vector2(12, -6), Color("e4a443"), 3.0)
	draw_circle(Vector2(6, -8), 0.9, Color("293d32"))
	draw_line(Vector2(-5, -2), Vector2(0, 0), Color("c4a04c") if chick else Color("bcc8b8"), 2.0)
	draw_set_transform(Vector2.ZERO)

func _draw_butterfly(center: Vector2, phase: float, color: Color) -> void:
	var t := _time + phase
	var p := center + Vector2(sin(t * 0.65) * 22.0, cos(t * 0.9) * 8.0 - 13.0)
	var wing := 1.0 + absf(sin(t * 7.0)) * 4.0
	draw_circle(p + Vector2(-wing * 0.65, -1), wing * 0.6, color)
	draw_circle(p + Vector2(wing * 0.65, -1), wing * 0.6, color)
	draw_line(p + Vector2(0, -3), p + Vector2(0, 3), Color("58483e"), 1.0)

