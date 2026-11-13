extends MainSceneTest
## In the live main scene, hitting a shot or putt must not spawn a coloured
## ShotTrail arc over the course while the ball is flying and rolling.

const TEE := Vector2i(60, 60)
const CUP := Vector2i(60, 50)

var entities: Node2D


func before_all() -> void:
	await super()
	await new_game("No shot trail")
	main._suppress_tile_undo = true
	for x in range(TEE.x - 1, TEE.x + 2):
		for y in range(CUP.y, TEE.y + 1):
			main.terrain_grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	main._suppress_tile_undo = false
	assert_not_null(build_hole(TEE, CUP), "A hole opens on the lot")
	entities = main.get_node("Entities")
	# Place the camera right over the hole so every shot lies inside the
	# viewport (where the removed visibility guard used to spawn trails).
	_focus_camera_on(main.terrain_grid.grid_to_screen_center(Vector2i(60, 55)))
	await process_frames(2)


func after_each() -> void:
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	GameManager.stop_simulation()
	await super()


func _focus_camera_on(world_pos: Vector2) -> void:
	main.camera.global_position = world_pos
	main.camera._target_position = world_pos
	main.camera._smoothed_position = world_pos


func test_visible_shot_signal_animates_ball_without_creating_line2d_arc() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	GameManager.is_paused = false
	var golfer: Golfer = main.golfer_manager.spawn_golfer("Shot Viewer", 0.8, 0)
	golfer.set_process(false)
	var from_screen: Vector2 = main.terrain_grid.grid_to_screen_center(TEE)
	var carry_screen: Vector2 = main.terrain_grid.grid_to_screen_center(Vector2i(60, 52))
	var to_screen: Vector2 = main.terrain_grid.grid_to_screen_center(Vector2i(60, 51))
	_focus_camera_on(from_screen)

	var arcs_before: int = main.shot_heatmap_tracker.shot_arcs.size()
	assert_true(nodes_of_class(entities, "Line2D").is_empty(),
		"No Line2D trail exists on Entities before a shot")

	EventBus.ball_shot_landed_precise.emit(golfer.golfer_id, from_screen, to_screen, 176, carry_screen)
	await process_frames(1)

	var ball: Ball = main.ball_manager.get_ball(golfer.golfer_id)
	assert_not_null(ball, "BallManager still creates and animates the ball")
	assert_eq(ball.ball_state, Ball.BallState.IN_FLIGHT,
		"Ball enters flight immediately when the shot is hit")
	assert_true(nodes_of_class(entities, "Line2D").is_empty(),
		"No coloured Line2D arc is spawned when the shot is hit")

	var finished := await process_frames_until(
		func() -> bool:
			assert_true(nodes_of_class(entities, "Line2D").is_empty(),
				"No Line2D arc appears during flight or rollout")
			return ball.ball_state == Ball.BallState.AT_REST,
		600)
	assert_true(finished, "The ball completes flight and rollout to rest")
	assert_eq(main.shot_heatmap_tracker.shot_arcs.size(), arcs_before + 1,
		"Heatmap tracker still records the shot for its toggleable overlay")
	assert_false(main.terrain_grid.is_shot_heatmap_enabled(),
		"Heatmap overlay stays off unless toggled")

	main.golfer_manager.remove_golfer(golfer.golfer_id)


func test_visible_putt_signal_creates_no_line2d_trail() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	GameManager.is_paused = false
	var golfer: Golfer = main.golfer_manager.spawn_golfer("Putt Viewer", 0.8, 0)
	golfer.set_process(false)
	var from_screen: Vector2 = main.terrain_grid.grid_to_screen_center(Vector2i(60, 51))
	var to_screen: Vector2 = main.terrain_grid.grid_to_screen_center(CUP)
	_focus_camera_on(to_screen)

	EventBus.ball_putt_landed_precise.emit(golfer.golfer_id, from_screen, to_screen, 22)
	await process_frames(1)

	var ball: Ball = main.ball_manager.get_ball(golfer.golfer_id)
	assert_not_null(ball, "BallManager still animates the putt")
	assert_true(nodes_of_class(entities, "Line2D").is_empty(),
		"No Line2D trail is spawned for a putt")

	var finished := await process_frames_until(
		func() -> bool:
			assert_true(nodes_of_class(entities, "Line2D").is_empty(),
				"No Line2D trail appears while the putt rolls")
			return ball.ball_state == Ball.BallState.AT_REST,
		600)
	assert_true(finished, "The putt reaches rest cleanly")

	main.golfer_manager.remove_golfer(golfer.golfer_id)


func test_live_golfer_shot_draws_no_arc_from_hit_until_stop() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.FAST)
	GameManager.is_paused = false
	var golfer: Golfer = main.golfer_manager.spawn_golfer("Live Golfer", 0.85, 0)
	var gid: int = golfer.golfer_id
	golfer.start_hole(0, TEE)
	golfer.global_position = main.terrain_grid.grid_to_screen_center(TEE)
	_focus_camera_on(golfer.global_position)

	golfer.take_shot_precise(Vector2(60, 52))
	var progress := {"saw_flight": false}
	var landed := await process_frames_until(
		func() -> bool:
			assert_true(nodes_of_class(entities, "Line2D").is_empty(),
				"No Line2D arc appears on Entities during swing, flight or rollout")
			var b: Ball = main.ball_manager.get_ball(gid)
			if b != null:
				if b.ball_state == Ball.BallState.IN_FLIGHT:
					progress["saw_flight"] = true
				elif progress["saw_flight"] and b.ball_state == Ball.BallState.AT_REST:
					return true
			return false,
		600)
	assert_true(progress["saw_flight"], "Live golfer shot animated ball flight")
	assert_true(landed, "Live golfer shot stopped cleanly without spawning a shot trail arc")

	if is_instance_valid(golfer):
		main.golfer_manager.remove_golfer(gid)
