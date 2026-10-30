extends GameTest
## What a camera move costs the ground overlays.
##
## The overlays cull their draw lists to the camera, so TerrainGrid queues a
## repaint for them as the view moves. That repaint rebuilds the visible ground
## art, so it is rationed: it runs at the configured camera-update cadence and
## only when the camera reaches a tile window it did not already cover. A pan
## that drifts a few pixels inside the same window must cost nothing at all —
## that is what dropping frames while the course was running looked like.
##
## The cadence is wall-clock time, like the camera itself. While the game is
## paused the scaled frame delta is 0, which used to stop the repaints with the
## simulation: the overlays stayed stale under a paused pan. A paused pan must
## repaint them exactly like a live one.

## A camera close enough that a few screen pixels stay well inside one tile.
const ZOOM := 4.0

var grid: TerrainGrid
var camera: Camera2D

func before_each() -> void:
	super()
	PerformanceSettings.camera_update_rate = PerformanceSettings.UpdateRate.HIGH
	grid = make_grid(96, 96)
	camera = Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = grid.grid_to_screen_center(Vector2i(48, 48))
	grid.add_child(camera)
	camera.make_current()

## Await frames until the queued repaint has run. The cadence is wall-clock, so
## this does not depend on the simulation clock. Returns whether it settled.
func _await_settled(timeout_seconds: float = 1.0) -> bool:
	# Two frames: the viewport adopts the new camera on the frame after it is
	# made current, and the grid reads the window on the frame after that.
	await process_frames(2)
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not grid._camera_redraw_pending:
			return true
		await process_frames(1)
	return not grid._camera_redraw_pending


func test_the_ground_under_the_camera_is_repainted() -> void:
	assert_eq(grid.camera_repaint_count, 0, "precondition: nothing repainted yet")
	assert_true(await _await_settled(), "the camera's window is painted once it is known")
	assert_gt(grid.camera_repaint_count, 0, "the ground overlays were given a repaint")


func test_a_pan_inside_one_tile_window_queues_no_repaint() -> void:
	assert_true(await _await_settled(), "the camera settles first")
	var window := grid.get_visible_tile_range()
	var repaints := grid.camera_repaint_count

	camera.position += Vector2(2.0, 0.0)  # two screen pixels, no tile crossed
	await process_frames(3)

	assert_eq(grid.get_visible_tile_range(), window,
		"precondition: the drift stays inside the same tile window")
	assert_eq(grid.camera_repaint_count, repaints,
		"a drift inside the tile window repaints nothing")


func test_reaching_a_new_tile_window_queues_a_repaint() -> void:
	assert_true(await _await_settled(), "the camera settles first")
	var window := grid.get_visible_tile_range()
	var repaints := grid.camera_repaint_count

	# Six tile-heights down at this zoom crosses into a new window.
	camera.position.y += 6.0 * float(grid.tile_height) * ZOOM
	assert_true(await _await_settled(), "the overlays are repainted for the new window")

	assert_ne(grid.get_visible_tile_range(), window,
		"precondition: the camera reached tiles it did not cover")
	assert_gt(grid.camera_repaint_count, repaints,
		"a new tile window is repainted")


func test_a_paused_pan_still_repaints_the_ground() -> void:
	assert_true(await _await_settled(), "the camera settles first")
	Engine.time_scale = 0.0
	assert_eq(Engine.time_scale, 0.0, "precondition: the simulation is frozen")
	var repaints := grid.camera_repaint_count

	camera.position.y += 6.0 * float(grid.tile_height) * ZOOM
	assert_true(await _await_settled(), "the repaint does not wait for the game clock")
	assert_gt(grid.camera_repaint_count, repaints,
		"a frozen course still repaints the ground under a pan")
	assert_eq(Engine.time_scale, 0.0, "and the panning never unfreezes it")


func test_zooming_outside_a_tile_window_repaints_the_ground() -> void:
	assert_true(await _await_settled(), "the camera settles first")
	var repaints := grid.camera_repaint_count

	# Zooming changes which tiles are in view even with the camera still.
	camera.zoom = Vector2(1.0, 1.0)
	assert_true(await _await_settled(), "the new view is repainted")
	assert_gt(grid.camera_repaint_count, repaints,
		"a zoom that reaches more tiles is repainted")
