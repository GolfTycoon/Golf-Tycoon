extends MainSceneTest
## Live gameplay tree impacts: multi-segment ball bounce, impact particles,
## canopy wobble signal, thought triggers, view rotation mid-bounce, and
## clean landing without shot trail Line2Ds.

const TEE := Vector2i(60, 62)
const OAK_BLOCKER := Vector2i(60, 58)
const CUP := Vector2i(60, 50)

var entities: Node2D


func before_all() -> void:
	await super()
	await new_game("Tree Impact Integration")
	main._suppress_tile_undo = true
	for x in range(TEE.x - 2, TEE.x + 3):
		for y in range(CUP.y - 1, TEE.y + 2):
			main.terrain_grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	assert_not_null(build_hole(TEE, CUP), "Hole opens cleanly on test lot")
	main.terrain_grid.set_tile(OAK_BLOCKER, TerrainTypes.Type.OAK)
	main._suppress_tile_undo = false
	entities = main.get_node("Entities")
	_focus_camera_on(main.terrain_grid.grid_to_screen_center(OAK_BLOCKER))
	await process_frames(3)


func after_each() -> void:
	GameManager.set_gradual_view_rotation(true)
	main.terrain_grid.set_view_orientation(0)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	GameManager.stop_simulation()
	await super()


func _focus_camera_on(world_pos: Vector2) -> void:
	main.camera.global_position = world_pos
	main.camera._target_position = world_pos
	main.camera._smoothed_position = world_pos


func _spawn_punch_golfer() -> Golfer:
	var golfer: Golfer = main.golfer_manager.spawn_golfer("Tree Hitter", 1.0, 0)
	golfer.set_process(false)
	golfer.golfer_tier = GolferTier.Tier.PRO
	golfer.miss_tendency = 0.0
	golfer.current_hole = 0
	golfer.ball_position = TEE
	golfer.ball_position_precise = Vector2(TEE)
	golfer.global_position = main.terrain_grid.grid_to_screen_center(TEE)
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = "Tree Hitter"
	for _i in range(5):
		profile.allocate(2, 1)  # Accurate Driver
		profile.allocate(3, 1)  # Accurate Irons
	profile.golfer_skills = {"length": true, "accuracy": true, "imagination": false}
	golfer.player_profile = profile
	golfer.sync_player_profile_skills()
	golfer.player_shape = 4  # Low punch aimed straight through OAK_BLOCKER
	return golfer


func _tree_fx_children() -> Array:
	var res: Array = []
	for child in main.ball_manager.balls_container.get_children():
		if child is TreeImpactEffect:
			res.append(child)
	return res


func test_real_punch_shot_hits_oak_emits_signal_spawns_vfx_and_lands() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.FAST)
	GameManager.is_paused = false
	GameManager.wind_system = null
	seed(777)

	var golfer := _spawn_punch_golfer()
	var hits: Array[Dictionary] = []
	var listener := func(gid: int, tile: Vector2i, sp: String, mat: int, pos: Vector2) -> void:
		if gid == golfer.golfer_id:
			hits.append({"tile": tile, "species": sp, "material": mat, "pos": pos})
	EventBus.ball_hit_tree.connect(listener)

	golfer.take_shot_precise(Vector2(CUP))
	var launched := await process_frames_until(
		func() -> bool:
			return main.ball_manager.get_ball(golfer.golfer_id) != null,
		240
	)
	assert_true(launched, "Swinging golfer launches ball into flight")

	var ball: Ball = main.ball_manager.get_ball(golfer.golfer_id)
	assert_not_null(ball, "BallManager creates ball for golfer")
	assert_eq(ball.ball_state, Ball.BallState.IN_FLIGHT, "Ball starts flight toward the oak")

	var observed := {"vfx": false, "wobble": false}
	var finished := await process_frames_until(
		func() -> bool:
			assert_true(nodes_of_class(entities, "Line2D").is_empty(),
				"Tree bounce playback must not create Line2D trail nodes")
			if not _tree_fx_children().is_empty():
				observed.vfx = true
			if main.terrain_grid._tree_overlay._visuals.has(OAK_BLOCKER):
				var v: Node2D = main.terrain_grid._tree_overlay._visuals[OAK_BLOCKER]
				if absf(v.rotation) > 0.001:
					observed.wobble = true
			return ball.ball_state == Ball.BallState.AT_REST,
		600
	)

	EventBus.ball_hit_tree.disconnect(listener)
	assert_true(finished, "Multi-segment ball completes deflection and settles to rest")
	assert_gt(hits.size(), 0, "EventBus.ball_hit_tree emitted during live impact")
	assert_eq(hits[0].tile, OAK_BLOCKER)
	assert_eq(hits[0].species, "oak")
	assert_true(bool(observed.vfx), "TreeImpactEffect spawned at impact under Balls container")
	assert_true(bool(observed.wobble), "Impacted oak canopy wobbled in TreeOverlay")
	assert_gt(ball.rest_ground.y, float(OAK_BLOCKER.y) - 3.0,
		"Oak stopped/deflected the punch well short of the distant cup")
	assert_gt(ball.rest_ground.y, float(CUP.y) + 2.0, "Oak prevented ball from reaching the distant cup")

	var vfx_freed := await process_frames_until(
		func() -> bool:
			return _tree_fx_children().is_empty(),
		120
	)
	assert_true(vfx_freed, "TreeImpactEffect self-frees cleanly after particle lifetime")

	main.golfer_manager.remove_golfer(golfer.golfer_id)
	await process_frames(2)


func test_view_rotation_mid_tree_bounce_reprojects_segments_to_landing() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	GameManager.is_paused = false
	GameManager.wind_system = null
	seed(777)

	var golfer := _spawn_punch_golfer()
	var sim_preview := golfer._calculate_shot_precise(TEE, Vector2(CUP), true)
	assert_true(bool(sim_preview.get("tree_flight_hit", false)),
		"Precondition: shot strikes tree in flight")

	var hits: Array[Dictionary] = []
	var listener := func(gid: int, tile: Vector2i, sp: String, _mat: int, _pos: Vector2) -> void:
		if gid == golfer.golfer_id:
			hits.append({"tile": tile, "species": sp})
	EventBus.ball_hit_tree.connect(listener)

	golfer.take_shot_precise(Vector2(CUP))
	var launched := await process_frames_until(
		func() -> bool:
			return main.ball_manager.get_ball(golfer.golfer_id) != null,
		240
	)
	assert_true(launched, "Swinging golfer launches ball into flight")

	var ball: Ball = main.ball_manager.get_ball(golfer.golfer_id)
	assert_not_null(ball)
	assert_eq(ball.ball_state, Ball.BallState.IN_FLIGHT)

	# Snap view orientation 90 degrees while Leg 1 / Leg 2 bounce is mid-air!
	main.terrain_grid.set_view_orientation(1)
	await process_frames(2)

	var finished := await process_frames_until(
		func() -> bool:
			return ball.ball_state == Ball.BallState.AT_REST,
		600
	)
	EventBus.ball_hit_tree.disconnect(listener)
	assert_true(finished, "Deflected ball finishes flight after mid-bounce view rotation")
	assert_gt(hits.size(), 0, "Tree hit still fires normally across view turn")

	var expected_world: Vector2 = main.terrain_grid.grid_point_to_screen(ball.rest_ground)
	assert_almost_eq(ball.global_position.distance_to(expected_world), 0.0, 2.0,
		"After view turn mid-bounce, ball finishes directly on reprojected rest_ground")

	await process_frames_until(
		func() -> bool:
			return _tree_fx_children().is_empty(),
		120
	)
	main.golfer_manager.remove_golfer(golfer.golfer_id)
	await process_frames(2)
