extends MainSceneTest
## The clubhouse in the real game, on a one-hole course built from nothing: the
## course gets a clubhouse that the Bulldozer refuses but that can be moved, and
## golfers arrive from its door, play, walk home to it, go inside and leave —
## a group once its last member is inside.

const TEE := Vector2i(60, 60)
const CUP := Vector2i(60, 50)
## Frames a walk or a round may take at Ultra speed before the test gives up.
const WALK_FRAMES := 6000

var clubhouse: Building
## Golfer ids announced by EventBus.golfer_left_course.
var departures: Array[int] = []


func before_all() -> void:
	await super()
	EventBus.golfer_left_course.connect(_on_golfer_left_course)
	await new_game("Clubhouse lifecycle")
	build_hole(TEE, CUP)
	await process_frames(6)
	clubhouse = CourseClubhouse.find(main.entity_layer)


func after_all() -> void:
	EventBus.golfer_left_course.disconnect(_on_golfer_left_course)
	super()


func _on_golfer_left_course(golfer_id: int) -> void:
	departures.append(golfer_id)


## The state of the golfer with this id, or -1 once it is off the course.
func _state_of(golfer_id: int) -> int:
	var golfer: Golfer = main.golfer_manager.get_golfer(golfer_id)
	return golfer.current_state if golfer else -1


func _all_in_state(golfer_ids: Array, state: int) -> bool:
	for golfer_id in golfer_ids:
		if _state_of(golfer_id) != state:
			return false
	return true


## Hole out on every shot until the game ends each golfer's round and they set
## off home. Drives the turn system a real round uses, so the walk home starts
## the way it does in play.
func _play_round(golfer_ids: Array) -> bool:
	for i in range(WALK_FRAMES):
		var all_leaving := true
		for golfer_id in golfer_ids:
			var golfer: Golfer = main.golfer_manager.get_golfer(golfer_id)
			if golfer == null or golfer.current_state == Golfer.State.LEAVING:
				continue
			all_leaving = false
			if golfer.current_state != Golfer.State.PREPARING_SHOT:
				continue
			var hole: GameManager.HoleData = GameManager.current_course.holes[golfer.current_hole]
			golfer.current_strokes = 3
			golfer.ball_position = hole.hole_position
			golfer.ball_position_precise = Vector2(hole.hole_position)
			golfer._change_state(Golfer.State.IDLE)
		if all_leaving:
			return true
		await process_frames(1)
	return false


## The nearest tile the clubhouse can legally move to, asked of the game rather
## than guessed (the arrival garden and the hole are in the way).
func _move_target(from: Vector2i) -> Vector2i:
	for radius in range(3, 40):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate: Vector2i = from + Vector2i(dx, dy)
				if CourseClubhouse.can_move_to(main.terrain_grid, main.entity_layer, clubhouse, candidate):
					return candidate
	return Vector2i(-1, -1)


func _start_play() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	GameManager.is_paused = false
	# No other guests: a group spawning ahead would block the one being watched.
	main.golfer_manager.min_spawn_cooldown_seconds = 1000000.0


func test_the_clubhouse_cannot_be_bulldozed_but_can_be_moved() -> void:
	assert_eq(GameManager.current_course.holes.size(), 1, "The test course opens one hole")
	assert_not_null(clubhouse, "A course built from nothing gets a clubhouse")
	if clubhouse == null:
		return
	# As close to the arrival corner of the owned land as the ground allows.
	assert_lte(Vector2(clubhouse.grid_position).distance_to(Vector2(CourseClubhouse.arrival_corner())), 4.0,
		"The clubhouse stands at the arrival corner")
	var door := CourseClubhouse.front_tile(clubhouse, main.terrain_grid, main.entity_layer)
	assert_gte(door.x, 0, "The clubhouse has a front door")
	assert_false(main.entity_layer.is_tile_occupied_by_building(door), "Golfers can stand at the door")
	assert_eq(GameManager.current_course.holes[0].tee_position, TEE, "The clubhouse did not land on the hole")

	# The Bulldozer refuses it, through the real click path.
	main._on_bulldozer_pressed()
	main._handle_bulldozer_click(clubhouse.grid_position + Vector2i(1, 1))
	assert_eq(CourseClubhouse.find(main.entity_layer), clubhouse, "The Bulldozer cannot demolish the clubhouse")
	main._cancel_bulldozer_mode()

	# It can be moved, and the door follows it.
	var home := clubhouse.grid_position
	var target := _move_target(home)
	assert_gte(target.x, 0, "There is a legal tile to move the clubhouse to")
	main._on_building_move_requested(clubhouse)
	assert_eq(main._moving_building, clubhouse, "Move Clubhouse picks the building up")
	main._handle_building_move_click(target)
	assert_eq(clubhouse.grid_position, target, "The clubhouse moves where it was put down")
	assert_null(main._moving_building, "and the move ends with the click")
	assert_ne(CourseClubhouse.front_tile(clubhouse, main.terrain_grid, main.entity_layer), door,
		"The door moves with the building")
	# Put it back before the guests arrive.
	CourseClubhouse.move_to(main.entity_layer, clubhouse, home)
	assert_eq(clubhouse.grid_position, home, "and it can be moved back")
	await process_frames(2)


func test_a_guest_walks_in_from_the_clubhouse_plays_and_walks_home() -> void:
	_start_play()
	var door := CourseClubhouse.front_tile(clubhouse, main.terrain_grid, main.entity_layer)
	var golfer: Golfer = main.golfer_manager.spawn_golfer("Lifecycle guest", 0.5, main.golfer_manager.next_group_id)
	var golfer_id := golfer.golfer_id
	assert_eq(golfer.current_state, Golfer.State.WALKING, "A new guest starts out walking")
	assert_lt(golfer.global_position.distance_to(main.terrain_grid.grid_to_screen_center(door)), 4.0,
		"from the clubhouse door")

	var tee_screen: Vector2 = main.terrain_grid.grid_to_screen_center(TEE)
	assert_true(await process_frames_until(func() -> bool: return golfer.global_position.distance_to(tee_screen) < 8.0,
		WALK_FRAMES), "The guest walks in from the clubhouse to the first tee")
	assert_true(await _play_round([golfer_id]), "The guest plays the hole and the round ends")
	assert_eq(_state_of(golfer_id), Golfer.State.LEAVING, "A finished round walks home")
	assert_true(await process_frames_until(_all_in_state.bind([golfer_id], Golfer.State.FINISHED), WALK_FRAMES),
		"The golfer reaches the clubhouse and goes inside")
	assert_true(departures.has(golfer_id), "Leaving the course is announced")
	assert_true(await process_frames_until(func() -> bool: return _state_of(golfer_id) == -1, 900),
		"A golfer who has gone inside is taken off the course")


func test_a_group_leaves_once_its_last_member_is_inside() -> void:
	_start_play()
	var group: int = main.golfer_manager.next_group_id
	var pair := [
		main.golfer_manager.spawn_golfer("Group first", 0.5, group).golfer_id,
		main.golfer_manager.spawn_golfer("Group second", 0.5, group).golfer_id,
	]
	assert_true(await _play_round(pair), "Both partners play their round to the end")
	assert_true(await process_frames_until(_all_in_state.bind(pair, Golfer.State.FINISHED), WALK_FRAMES),
		"Both partners walk home and go inside")
	assert_true(await process_frames_until(_all_in_state.bind(pair, -1), 900),
		"The group is taken off the course once the last one is inside")
