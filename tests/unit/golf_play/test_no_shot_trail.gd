extends GameTest
## Shots in play never draw a coloured arc once hit: ShotTrail is gone from
## scripts/effects and main.gd, and taking a shot clears the aim guide while
## animating the ball through flight to rest without adding any Line2D trail.

const MainScript := preload("res://scripts/main/main.gd")

var fixture: Node2D
var golfers: GolferManager
var balls: BallManager
var rounds: PlayerRoundManager
var grid: TerrainGrid

func before_each() -> void:
	super()
	GameManager.tournament_manager = null
	GameManager.is_paused = false
	GameManager.player_profile = PlayerGolferProfile.new()
	GameManager.current_course = GameManager.CourseData.new()
	var hole := GameManager.HoleData.new()
	hole.tee_position = Vector2i(10, 10)
	hole.hole_position = Vector2i(16, 10)
	hole.par = 3
	GameManager.course_data.add_hole(hole)
	grid = autofree(TerrainGrid.new())
	for x in range(40):
		for y in range(40):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.FAIRWAY
	grid._grid[hole.tee_position] = TerrainTypes.Type.TEE_BOX
	grid._grid[hole.hole_position] = TerrainTypes.Type.GREEN
	GameManager.terrain_grid = grid
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	golfers = make_golfer_manager()
	fixture = golfers.get_parent()
	balls = BallManager.new()
	fixture.add_child(balls)
	balls.set_terrain_grid(grid)
	var camera := IsometricCamera.new()
	fixture.add_child(camera)
	var hud := Control.new()
	fixture.add_child(hud)
	rounds = PlayerRoundManager.new()
	fixture.add_child(rounds)
	rounds.setup(golfers, camera, hud)

func after_each() -> void:
	rounds.leave_round()
	golfers.clear_all_golfers()
	await process_frames(1)
	super()

func _line2d_nodes(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is Line2D:
			found.append(child)
		found.append_array(_line2d_nodes(child))
	return found

func test_shot_trail_script_and_main_handlers_are_removed() -> void:
	assert_false(FileAccess.file_exists("res://scripts/effects/shot_trail.gd"),
		"ShotTrail effect script is removed")
	var main_script: GDScript = MainScript
	var method_names: Array[String] = []
	for method_info in main_script.get_script_method_list():
		method_names.append(str(method_info.get("name", "")))
	for removed_method in ["_setup_shot_trails", "_on_shot_for_trail", "_on_putt_for_trail"]:
		assert_false(removed_method in method_names,
			"main.gd no longer wires %s" % removed_method)

func test_owner_shot_clears_aim_guide_and_draws_no_arc_during_flight() -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Trail Check"
	rounds.mode_picker.select(0)
	rounds.start_round()
	rounds._process(0.0)

	rounds.update_aim_guide(Vector2i(16, 10))
	assert_false(rounds.aim_guide.preview.is_empty(),
		"Aim guide shows before the shot is hit")

	var player_golfer := rounds.player
	assert_true(player_golfer.play_shot_to_rest(Vector2(16, 10)),
		"Player hits the shot")
	rounds._process(0.0)
	assert_true(rounds.aim_guide.preview.is_empty(),
		"Aim guide clears once the shot is hit")

	var saw_flight := false
	var saw_rest := false
	Engine.time_scale = 3.0
	for _frame in range(240):
		await process_frames(1)
		assert_true(_line2d_nodes(fixture).is_empty(),
			"No Line2D shot arc appears while the ball is in flight or rolling")
		assert_true(rounds.aim_guide.preview.is_empty(),
			"Aim guide remains hidden until the shot stops")
		var ball := balls.get_ball(player_golfer.golfer_id)
		if ball != null:
			if ball.ball_state == Ball.BallState.IN_FLIGHT:
				saw_flight = true
			elif saw_flight and ball.ball_state == Ball.BallState.AT_REST:
				saw_rest = true
				break
	Engine.time_scale = 1.0

	assert_true(saw_flight, "The golf ball still flies through the air")
	assert_true(saw_rest, "and still lands and comes to rest")
