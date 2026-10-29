extends Node2D
class_name DecorationAtmosphere
## Animated water details attached to the fountain sprite; no simulation effects.

var terrain_grid: TerrainGrid
var _time := 0.0
var _redraw_elapsed := 0.0

func _process(delta: float) -> void:
	if GameManager.is_paused or GameManager.current_speed == GameManager.GameSpeed.PAUSED:
		return
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	_time += real_delta
	_redraw_elapsed += real_delta
	if _redraw_elapsed >= PerformanceSettings.animation_redraw_interval():
		_redraw_elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	if terrain_grid and not terrain_grid.get_visible_world_rect().grow(64).has_point(global_position):
		return
	_draw_fountain(_time + global_position.x * 0.017)

func _draw_fountain(phase: float) -> void:
	var water := Color(0.78, 0.94, 1.0, 0.65)
	# Falling beads follow the existing sprite's central jet into the lower bowl.
	for i in range(6):
		var t := fposmod(phase * 0.8 + float(i) / 6.0, 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector2(side * t * 12.0, -43.0 + t * t * 27.0)
		draw_line(p, p + Vector2(side, 2.0 + t), water, 1.0)
	# Elliptical ripple fits the original basin, rather than growing onto the turf.
	var ripple := fposmod(phase * 0.55, 1.0)
	draw_set_transform(Vector2(0, -16), 0.0, Vector2(1.0, 0.35))
	draw_arc(Vector2.ZERO, 5.0 + ripple * 15.0, 0, TAU, 20,
		Color(0.85, 0.97, 1.0, (1.0 - ripple) * 0.55), 1.0)
	draw_set_transform(Vector2.ZERO)
