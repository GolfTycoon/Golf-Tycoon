extends GameTest
## Physical 2.5D tree collision, sprite profile classification, deflection,
## rollout obstacles, aim-guide updates, audio, and impact VFX.

var grid: TerrainGrid

func before_each() -> void:
	super()
	GameManager.wind_system = null
	GameManager.current_theme = CourseTheme.Type.PARKLAND
	GameManager.current_day = 1
	grid = TerrainGrid.new()
	grid.grid_width = 32
	grid.grid_height = 32
	add_child_autofree(grid)
	await process_frames(1)
	for x in range(32):
		for y in range(32):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.FAIRWAY


func after_each() -> void:
	GameManager.terrain_grid = null
	GameManager.course_data = null
	super()


func _make_golfer(pos: Vector2i = Vector2i(6, 16)) -> Golfer:
	var g: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	g.ball_position = pos
	g.ball_position_precise = Vector2(pos)
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = "TreeTester"
	for _i in range(5):
		profile.allocate(0, 1)
		profile.allocate(1, 1)
	profile.golfer_skills = {"length": true, "accuracy": true, "imagination": false}
	g.player_profile = profile
	g.sync_player_profile_skills()
	return g


func test_collision_profile_classifies_oak_trunk_and_canopy() -> void:
	var oak_pos := Vector2i(10, 10)
	grid._grid[oak_pos] = TerrainTypes.Type.OAK
	var profile := TreeCollisionProfile.get_profile_for_tile(grid, oak_pos, "oak", 0)
	assert_not_null(profile, "Oak sprite produces a collision profile")
	assert_gt(profile.max_world_h, 40.0, "Oak canopy extends meaningfully above ground")
	var trunk_hw := profile.half_width_at_height(4.0, 1.0)
	assert_gt(trunk_hw, 2.0, "Oak builds a tangible trunk width")

	# Low height near trunk center should register solid wood; upper wide canopy should be foliage.
	var low_mat := profile.sample_ball(profile.trunk_center_x, 4.0, 2.2, 1.0)
	assert_eq(low_mat, TreeCollisionProfile.MAT_WOOD, "Oak trunk base classifies as wood")

	var mid_canopy_h := clampf(profile.max_world_h * 0.62, 18.0, profile.max_world_h - 6.0)
	var hw := profile.half_width_at_height(mid_canopy_h, 1.0)
	assert_gt(hw, trunk_hw + 4.0, "Oak canopy widens past its trunk")
	var canopy_mat := profile.sample_ball(profile.trunk_center_x + hw * 0.55, mid_canopy_h, 2.2, 1.0)
	assert_eq(canopy_mat, TreeCollisionProfile.MAT_FOLIAGE, "Oak canopy classifies as foliage")


func test_collision_profile_handles_woody_brush_pine_and_fall_maple() -> void:
	var dead_p := TreeCollisionProfile.get_profile_for_tile(grid, Vector2i(5, 5), "dead_tree", 0)
	assert_not_null(dead_p)
	var cactus_p := TreeCollisionProfile.get_profile_for_tile(grid, Vector2i(6, 5), "cactus", 0)
	assert_not_null(cactus_p)
	var heather_p := TreeCollisionProfile.get_profile_for_tile(grid, Vector2i(7, 5), "heather", 0)
	assert_not_null(heather_p)
	var maple_p := TreeCollisionProfile.get_profile_for_tile(grid, Vector2i(8, 5), "maple", 0)
	assert_not_null(maple_p)

	assert_eq(dead_p.sample_ball(0.0, dead_p.max_world_h * 0.5, 2.2, 1.0),
		TreeCollisionProfile.MAT_WOOD, "Dead tree skeleton is woody throughout")
	assert_eq(cactus_p.sample_ball(0.0, cactus_p.max_world_h * 0.45, 2.2, 1.0),
		TreeCollisionProfile.MAT_WOOD, "Cactus body is solid wood-equivalent obstacle")
	assert_eq(heather_p.sample_ball(0.0, heather_p.max_world_h * 0.4, 2.6, 1.0),
		TreeCollisionProfile.MAT_BRUSH, "Heather classifies as ground brush")
	assert_eq(maple_p.sample_ball(0.0, maple_p.max_world_h * 0.65, 2.2, 1.0),
		TreeCollisionProfile.MAT_FOLIAGE, "Maple upper crown is leafy foliage")


func test_fallback_silhouette_profile_covers_wood_and_foliage() -> void:
	var sil := TreeCollisionProfile._build_silhouette_profile("oak", 0)
	assert_not_null(sil)
	assert_gt(sil.max_world_h, 30.0)
	assert_eq(sil.sample_ball(0.0, 4.0, 2.2, 1.0), TreeCollisionProfile.MAT_WOOD)
	assert_eq(sil.sample_ball(4.0, sil.max_world_h * 0.65, 2.2, 1.0), TreeCollisionProfile.MAT_FOLIAGE)


func test_high_arc_clears_oak_while_low_punch_or_close_shot_hits() -> void:
	var tee := Vector2(6.0, 16.0)
	var oak_tile := Vector2i(10, 16)
	grid._grid[oak_tile] = TerrainTypes.Type.OAK
	var target := Vector2(20.0, 16.0)

	# Full high-arc iron flies well over an oak 4 tiles out (sin(4/14 * PI)*140 ~= 110px > tree max_h).
	var high_sim := TreeCollision.simulate_flight(
		grid, tee, target, 140.0, Vector2.ZERO, Vector2.ZERO, Golfer.Club.IRON, true
	)
	assert_false(bool(high_sim.get("hit", true)),
		"High iron arc clears over an oak tree 4 tiles ahead")

	# Punch shot (low arc = 32px max) clips straight into the oak!
	var punch_sim := TreeCollision.simulate_flight(
		grid, tee, target, 32.0, Vector2.ZERO, Vector2.ZERO, Golfer.Club.IRON, true
	)
	assert_true(bool(punch_sim.get("hit", false)),
		"Low punch shot hits the oak tree blocking the flight corridor")
	assert_eq(punch_sim.get("first_hit_tile"), oak_tile)
	assert_eq(punch_sim.get("first_hit_species"), "oak")
	assert_lt(punch_sim.carry.x, target.x - 1.5,
		"Deflected punch lands well short of the original target")


func test_trunk_bounces_away_while_high_foliage_drops_near_tree() -> void:
	var tee := Vector2(8.0, 16.0)
	var dead_tile := Vector2i(12, 16)
	grid._grid[dead_tile] = TerrainTypes.Type.DEAD_TREE
	var target := Vector2(22.0, 16.0)

	# Dead tree hit at mid/low height -> solid MAT_WOOD bounce back/short.
	var wood_sim := TreeCollision.simulate_flight(
		grid, tee, target, 28.0, Vector2.ZERO, Vector2.ZERO, Golfer.Club.IRON, true
	)
	assert_true(bool(wood_sim.get("hit", false)))
	assert_eq(wood_sim.get("first_hit_material"), TreeCollisionProfile.MAT_WOOD)
	assert_gt((wood_sim.segments as Array).size(), 1, "Wood collision creates multiple flight segments")

	# Foliage hit -> lands close to tree with sharply damped residual speed.
	grid._grid[dead_tile] = TerrainTypes.Type.OAK
	var foliage_sim := TreeCollision.simulate_flight(
		grid, tee, target, 58.0, Vector2.ZERO, Vector2.ZERO, Golfer.Club.WEDGE, true
	)
	assert_true(bool(foliage_sim.get("hit", false)))
	assert_eq(foliage_sim.get("first_hit_material"), TreeCollisionProfile.MAT_FOLIAGE)
	assert_lt(foliage_sim.carry.distance_to(Vector2(dead_tile)), 3.0,
		"Leaf hit drops steeply near the canopy instead of carrying full distance")
	assert_lt(float(foliage_sim.get("speed_factor", 1.0)), 0.7,
		"Foliage hit damps rollout speed")


func test_self_tile_escape_clears_golfer_under_own_tree() -> void:
	var own_tree := Vector2i(10, 16)
	grid._grid[own_tree] = TerrainTypes.Type.OAK
	var sim := TreeCollision.simulate_flight(
		grid, Vector2(own_tree), Vector2(18, 16), 95.0,
		Vector2.ZERO, Vector2.ZERO, Golfer.Club.WEDGE, true
	)
	assert_false(bool(sim.get("hit", true)),
		"High escape wedge from under a tree leaves its own tile cleanly without trapping")


func test_tree_collision_is_rotation_invariant_across_all_orientations() -> void:
	var tee := Vector2(6.0, 16.0)
	var target := Vector2(20.0, 16.0)
	var oak_tile := Vector2i(10, 16)
	grid._grid[oak_tile] = TerrainTypes.Type.OAK

	var baseline_carry := Vector2.ZERO
	var baseline_mat := -1
	for ori in range(4):
		grid.set_view_orientation(ori)
		var sim := TreeCollision.simulate_flight(
			grid, tee, target, 32.0, Vector2.ZERO, Vector2.ZERO, Golfer.Club.IRON, true
		)
		assert_true(bool(sim.get("hit", false)), "Orientation %d should register tree hit" % ori)
		assert_eq(sim.get("first_hit_tile"), oak_tile)
		if ori == 0:
			baseline_carry = sim.carry
			baseline_mat = int(sim.first_hit_material)
		else:
			assert_eq(int(sim.first_hit_material), baseline_mat,
				"Material at orientation %d matches north baseline" % ori)
			assert_almost_eq(sim.carry.distance_to(baseline_carry), 0.0, 0.001,
				"Carry at orientation %d matches north baseline" % ori)


func test_rollout_deflects_off_trunk_and_slows_in_heather() -> void:
	GameManager.terrain_grid = grid
	var golfer := _make_golfer(Vector2i(4, 16))
	var oak_tile := Vector2i(10, 16)
	grid._grid[oak_tile] = TerrainTypes.Type.OAK

	# Roll directly from (8.8,16) across trunk at (10,16) toward (14,16).
	var blocked_roll := golfer._calculate_rollout(
		Golfer.Club.IRON, Vector2i(9, 16), Vector2(8.8, 16), Vector2(2, 16),
		16.0, 1.0, true, 1.5, Vector2(1, 0), 1.0
	)
	var hits: Array = blocked_roll.get("roll_tree_hits", [])
	assert_gt(hits.size(), 0, "Ground rollout detects oak trunk collision")
	assert_eq(hits[0].tree_tile, oak_tile)
	var stopped_pos: Vector2 = blocked_roll.final_position
	assert_lt(stopped_pos.x, 11.5,
		"Trunk rebound stops/deflects roll before punching straight through to far side")
	assert_gt(stopped_pos.distance_to(Vector2(oak_tile)), 0.12,
		"Ball does not come to rest embedded at exact center of solid trunk")

	# Heather brush slows roll compared to clean fairway.
	grid._grid[oak_tile] = TerrainTypes.Type.FAIRWAY
	var clear_roll := golfer._calculate_rollout(
		Golfer.Club.IRON, Vector2i(7, 16), Vector2(7, 16), Vector2(2, 16),
		15.0, 1.0, true, 1.5, Vector2(1, 0), 1.0
	)
	for x in range(8, 13):
		grid._grid[Vector2i(x, 16)] = TerrainTypes.Type.HEATHER
	var brush_roll := golfer._calculate_rollout(
		Golfer.Club.IRON, Vector2i(7, 16), Vector2(7, 16), Vector2(2, 16),
		15.0, 1.0, true, 1.5, Vector2(1, 0), 1.0
	)
	assert_lt(float(brush_roll.rollout_distance), float(clear_roll.rollout_distance),
		"Heather brush resists ground rollout compared to fairway")


func test_preview_shot_to_rest_stops_at_tree_without_false_out_of_range() -> void:
	GameManager.terrain_grid = grid
	var cd := GameManager.CourseData.new()
	var hole := GameManager.HoleData.new()
	hole.hole_number = 1
	hole.tee_position = Vector2i(4, 16)
	hole.green_position = Vector2i(12, 16)
	hole.hole_position = Vector2i(12, 16)
	hole.par = 3
	hole.distance_yards = 176
	cd.holes.append(hole)
	GameManager.course_data = cd

	var oak_tile := Vector2i(7, 16)
	grid._grid[oak_tile] = TerrainTypes.Type.OAK
	var golfer := _make_golfer(Vector2i(4, 16))
	golfer.current_state = Golfer.State.PREPARING_SHOT
	golfer.player_shape = 4  # Low punch into oak

	var preview := golfer.preview_shot_to_rest(Vector2(12, 16))
	assert_false(preview.is_empty(), "Preparing golfer produces a valid shot preview")
	assert_true(bool(preview.get("tree_hit", false)), "Preview surfaces blocking oak impact")
	assert_eq(preview.get("tree_species"), "oak")
	assert_false(bool(preview.get("range_limited", true)),
		"Blocked shot well within club reach must not falsely report out of range")


func test_aim_guide_draws_single_polylines_for_tree_bounce_preview() -> void:
	var oak_tile := Vector2i(10, 16)
	grid._grid[oak_tile] = TerrainTypes.Type.OAK
	var sim := TreeCollision.simulate_flight(
		grid, Vector2(6, 16), Vector2(20, 16), 32.0, Vector2.ZERO, Vector2.ZERO, Golfer.Club.IRON, true
	)
	assert_true(bool(sim.get("hit", false)))
	var preview := {
		"origin": Vector2(6, 16),
		"aim": Vector2(20, 16),
		"carry": sim.carry,
		"rest": sim.carry + Vector2(0.8, 0.5),
		"roll_path": PackedVector2Array([sim.carry, sim.carry + Vector2(0.8, 0.5)]),
		"rollout_tiles": 0.9,
		"tree_hit": true,
		"tree_flight_hit": true,
		"tree_roll_hit": false,
		"tree_species": "oak",
		"tree_material": sim.first_hit_material,
		"flight_segments": sim.segments,
		"shape": 4,
		"punch": true,
		"club_name": "Iron",
	}
	var geo := AimGuide.build_geometry(grid, preview)
	assert_false(geo.is_empty(), "Deflected aim guide produces geometry")
	var guide := AimGuide.new()
	add_child_autofree(guide)
	guide.show_preview(preview)
	# Confirm the trajectory polyline ends cleanly at rest.
	var traj: PackedVector2Array = geo.trajectory
	assert_almost_eq(traj[0].distance_to(geo.origin), 0.0, 0.01)
	assert_almost_eq(traj[traj.size() - 1].distance_to(geo.rest), 0.0, 0.5)


func test_tree_impact_effect_and_procedural_audio_work_for_all_materials() -> void:
	var parent_node := Node2D.new()
	add_child_autofree(parent_node)
	for mat in [TreeCollisionProfile.MAT_WOOD, TreeCollisionProfile.MAT_FOLIAGE, TreeCollisionProfile.MAT_BRUSH]:
		var fx := TreeImpactEffect.create_at(parent_node, Vector2(100, 100), mat, "oak")
		assert_not_null(fx)
		assert_gt(fx.get_child_count(), 0, "TreeImpactEffect spawns particle polygons")

	var wood_samples := ProceduralAudio.generate_tree_wood_clonk(44100, 0.3)
	var foliage_samples := ProceduralAudio.generate_tree_foliage_rustle(44100, 0.3)
	var brush_samples := ProceduralAudio.generate_tree_brush_swish(44100, 0.3)
	for buf in [wood_samples, foliage_samples, brush_samples]:
		assert_gt(buf.size(), 100, "Tree SFX buffer contains stereo sample frames")


func test_feedback_trigger_course_aura_label_and_sound_manager_event() -> void:
	assert_true(CourseAura.TRIGGER_LABELS.has("TREE_HIT"),
		"CourseAura lists human-readable label for TREE_HIT")
	var msg := FeedbackTriggers.get_random_message(FeedbackTriggers.TriggerType.TREE_HIT)
	assert_false(msg.is_empty(), "FeedbackTriggers provides thought text for TREE_HIT")
	assert_eq(FeedbackTriggers.get_sentiment(FeedbackTriggers.TriggerType.TREE_HIT), "neutral",
		"Tree hits log under neutral feedback sentiment cleanly")

	for mat in [TreeCollisionProfile.MAT_WOOD, TreeCollisionProfile.MAT_FOLIAGE, TreeCollisionProfile.MAT_BRUSH]:
		EventBus.ball_hit_tree.emit(999, Vector2i(10, 16), "oak", mat, Vector2.ZERO)


func test_tree_overlay_wobble_resets_cleanly_on_visual_release() -> void:
	var oak := Vector2i(10, 10)
	grid._grid[oak] = TerrainTypes.Type.OAK
	var overlay := TreeOverlay.new()
	add_child_autofree(overlay)
	overlay.initialize(grid)
	var visual: Node2D = overlay._obtain_visual()
	visual.set_meta("tree_pos", oak)
	visual.visible = true
	overlay._visuals[oak] = visual

	EventBus.ball_hit_tree.emit(1, oak, "oak", TreeCollisionProfile.MAT_WOOD, Vector2.ZERO)
	assert_true(visual.has_meta("wobble_tween"), "Wobble tween attached to hit tree visual")
	await process_frames(3)
	assert_gt(absf(visual.rotation), 0.001, "Visual rotates slightly during wobble")

	overlay._release_visual(oak)
	assert_false(visual.has_meta("wobble_tween"), "Release clears wobble_tween metadata cleanly")
	assert_almost_eq(visual.rotation, 0.0, 0.0001, "Released pooled visual resets rotation to 0")

