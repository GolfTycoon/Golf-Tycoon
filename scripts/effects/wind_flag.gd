extends Node2D
class_name WindFlag
## Animated wind pennant rendered on tee boxes and greens.
## Subscribes to wind_changed for direction/speed updates.
## Uses _draw() with sine-wave vertex offset for flutter animation.

var _wind_direction: float = 0.0  # radians, 0 = North
var _wind_speed: float = 5.0
var _time: float = 0.0
var _flag_color: Color = Color(0.9, 0.15, 0.15)  # Red pennant
var _pole_height: float = 24.0
var _flag_length: float = 10.0
var _phase_offset: float = 0.0  # Per-flag variation
var _is_web: bool = false
var _redraw_timer: float = 0.0
const WEB_FLAG_REDRAW_INTERVAL: float = 0.1  # 10 FPS for flag flutter on web
## Entity band shared with golfers, trees, buildings, decorations, and balls so
## flags Y-sort cleanly against nearby sprites.
const ENTITY_Z_INDEX: int = 2
## Clips the pin where nearer terrain covers it, as trees are clipped (see
## refresh_terrain_occlusion()).
const TERRAIN_SPRITE_OCCLUSION: Shader = preload("res://shaders/terrain_sprite_occlusion.gdshader")

## The course and the cup the pin stands in, once stand_on() has put it there.
var _grid: TerrainGrid = null
var _ground: Vector2 = Vector2.ZERO
## The pin's occlusion material: created the first time the course has relief,
## and only worn while occlusion is on.
var _occlusion_material: ShaderMaterial = null

func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	EventBus.wind_changed.connect(_on_wind_changed)
	PerformanceSettings.profile_changed.connect(_on_graphics_settings_changed)
	_phase_offset = randf() * TAU  # Random phase so flags don't all flutter in sync
	z_index = ENTITY_Z_INDEX

func _enter_tree() -> void:
	_watch_terrain_occlusion(true)
	refresh_terrain_occlusion()

func _exit_tree() -> void:
	if EventBus.wind_changed.is_connected(_on_wind_changed):
		EventBus.wind_changed.disconnect(_on_wind_changed)
	if PerformanceSettings.profile_changed.is_connected(_on_graphics_settings_changed):
		PerformanceSettings.profile_changed.disconnect(_on_graphics_settings_changed)
	_watch_terrain_occlusion(false)

## Stand the pin in the cup at `tile` of `grid`: on the ground at the tile's
## centre, and clipped wherever nearer terrain covers it. Its owner calls this
## again whenever a turn of the view or a sculpt moves that ground on screen,
## which also gives the clip the new view.
func stand_on(grid: TerrainGrid, tile: Vector2i) -> void:
	if grid != _grid:
		_watch_terrain_occlusion(false)
		_grid = grid
		_watch_terrain_occlusion(true)
	_ground = Vector2(tile) + Vector2(0.5, 0.5)
	if grid:
		position = grid.grid_to_screen_center(tile)
	refresh_terrain_occlusion()

## Clip the pin wherever a nearer hill covers it, as trees are clipped, while the
## course has relief and the graphics setting allows it (see
## TerrainGrid.terrain_occlusion_enabled()). The pin is a billboard on its cup:
## its pole stands on the ground there, so a hill in front hides the foot of the
## pole first and the pennant only once the hill rises past it. Only a pin drawn
## on the course's own canvas is clipped.
func refresh_terrain_occlusion() -> void:
	if not is_instance_valid(_grid):
		_grid = null
	var grid := _grid
	var active := is_inside_tree() and grid != null and grid.is_inside_tree() \
			and grid._course_surface != null and grid.terrain_occlusion_enabled() \
			and get_canvas() == grid.get_canvas()
	if active:
		if _occlusion_material == null:
			_occlusion_material = ShaderMaterial.new()
			_occlusion_material.shader = TERRAIN_SPRITE_OCCLUSION
			_occlusion_material.set_shader_parameter("occlusion_epsilon", TerrainOcclusion.PROP_EPSILON)
		# The pole's lowest pixel is its foot, so nothing lifts the anchor.
		grid._course_surface.configure_sprite_occlusion(_occlusion_material, _ground, Vector2.ZERO)
	material = _occlusion_material if active else null

## Whether the terrain hides the pin's pixel at a world point: the same test its
## occlusion shader runs.
func terrain_hides_point(world: Vector2) -> bool:
	var occlusion := material as ShaderMaterial
	if occlusion == null or _grid == null:
		return false
	return TerrainOcclusion.hides_with_material(_grid, occlusion, world)

## Follow the course's terrain occlusion switch while in the scene tree.
func _watch_terrain_occlusion(watch: bool) -> void:
	if not is_instance_valid(_grid):
		return
	var connected := _grid.terrain_occlusion_changed.is_connected(_on_terrain_occlusion_changed)
	if watch and not connected and is_inside_tree():
		_grid.terrain_occlusion_changed.connect(_on_terrain_occlusion_changed)
	elif not watch and connected:
		_grid.terrain_occlusion_changed.disconnect(_on_terrain_occlusion_changed)

func _on_terrain_occlusion_changed(_enabled: bool) -> void:
	refresh_terrain_occlusion()

func _on_graphics_settings_changed(_terrain_fast: bool) -> void:
	queue_redraw()

func _on_wind_changed(direction: float, speed: float) -> void:
	_wind_direction = direction
	_wind_speed = speed

func _process(delta: float) -> void:
	_time += delta
	_redraw_timer += delta / maxf(Engine.time_scale, 0.01)
	var redraw_interval := PerformanceSettings.animation_redraw_interval()
	if _is_web:
		redraw_interval = maxf(redraw_interval, WEB_FLAG_REDRAW_INTERVAL)
	if _redraw_timer >= redraw_interval:
		_redraw_timer = 0.0
		queue_redraw()

func _draw() -> void:
	# Pole: vertical line from base to top
	var pole_base := Vector2(0, 0)
	var pole_top := Vector2(0, -_pole_height)
	draw_line(pole_base, pole_top, Color("fbf4d8"), 2.5)

	# Flag extends from pole top in wind direction
	# Project wind direction into isometric space
	var wind_dir_2d := Vector2(-sin(_wind_direction), cos(_wind_direction) * 0.5)
	var wind_strength := clampf(_wind_speed / 30.0, 0.05, 1.0)

	# Flag length scales slightly with wind speed
	var flag_len := _flag_length + wind_strength * 4.0
	wind_dir_2d = (wind_dir_2d + Vector2(0.8, 0)).normalized()

	# Flutter parameters
	var flutter_speed := 3.0 + wind_strength * 5.0
	var flutter_amp := 1.0 + wind_strength * 3.0

	# Draw flag as a filled polygon with sine-wave distortion
	var segments := 6
	var top_points: PackedVector2Array = []
	var bottom_points: PackedVector2Array = []

	for i in range(segments + 1):
		var t := float(i) / segments  # 0..1 along flag length
		var base_pos := pole_top + wind_dir_2d * flag_len * t

		# Sine-wave flutter increases toward the trailing edge
		var flutter := sin(_time * flutter_speed + t * 4.0 + _phase_offset) * flutter_amp * t
		var flutter_offset := Vector2(-wind_dir_2d.y, wind_dir_2d.x) * flutter

		# Flag width tapers from ~6px at pole to ~2px at tip
		var half_width := lerpf(3.0, 1.0, t)
		var perp := Vector2(-wind_dir_2d.y, wind_dir_2d.x).normalized()

		top_points.append(base_pos + perp * half_width + flutter_offset)
		bottom_points.append(base_pos - perp * half_width + flutter_offset)

	# Combine into a single polygon (top edge forward, bottom edge reversed)
	var polygon: PackedVector2Array = []
	for pt in top_points:
		polygon.append(pt)
	for i in range(bottom_points.size() - 1, -1, -1):
		polygon.append(bottom_points[i])

	if polygon.size() >= 3:
		# Main flag fill
		var flag_alpha := 0.7 + wind_strength * 0.3
		var fill_color := Color(_flag_color.r, _flag_color.g, _flag_color.b, flag_alpha)
		draw_colored_polygon(polygon, fill_color)

		# Outline for definition (skip on web — N draw_line calls per flag)
		if not _is_web and PerformanceSettings.wind_flag_quality == PerformanceSettings.WindFlagQuality.FULL:
			var outline_color := Color(_flag_color.r * 0.6, _flag_color.g * 0.6, _flag_color.b * 0.6, flag_alpha)
			for i in range(polygon.size()):
				var next := (i + 1) % polygon.size()
				draw_line(polygon[i], polygon[next], outline_color, 0.5)

	# Small ball at pole top
	draw_circle(pole_top, 1.5, Color(0.8, 0.8, 0.8))
