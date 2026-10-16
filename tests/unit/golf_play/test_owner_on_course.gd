extends GameTest
## The owner's own golfer is always on the course. Between rounds they work a
## ground of their own - pulling the weeds a groundskeeper would pull and
## chatting with the golfers a greeter would cheer up - and the round they play
## is played with that same golfer.

var grid: TerrainGrid
var weeds: WeedManager
var golfers: GolferManager
var container: Node2D
var owner_manager: PlayerGolferManager

func before_each() -> void:
	super()
	GameManager.is_paused = false
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	GameManager.player_profile = PlayerGolferProfile.new()
	grid = make_grid(32, 32)
	GameManager.terrain_grid = grid
	weeds = WeedManager.new()
	add_child_autofree(weeds)
	weeds.setup(grid, null)
	GameManager.weed_manager = weeds
	golfers = make_golfer_manager()
	GameManager.golfer_manager = golfers
	container = Node2D.new()
	container.name = "Golfers"
	add_child_autofree(container)
	owner_manager = PlayerGolferManager.new()
	add_child_autofree(owner_manager)
	owner_manager.setup(container)
	GameManager.player_golfer_manager = owner_manager

## Step the duty machine until `condition` holds, or the steps run out.
func _run_duty(duty: OwnerDuty, condition: Callable, steps: int = 200, delta: float = 0.1) -> bool:
	for i in range(steps):
		if condition.call():
			return true
		duty._process(delta)
	return condition.call()

func test_the_owner_golfer_is_on_the_course_working() -> void:
	var course_owner := owner_manager.ensure_golfer()
	assert_not_null(course_owner, "The owner has a golfer of their own on the course")
	assert_true(container.has_node("OwnerGolfer"), "Their golfer stands in the course's golfer container")
	assert_true(course_owner.is_on_course_duty(), "Between rounds they work the course")
	assert_eq(course_owner.golfer_id, PlayerGolferManager.OWNER_GOLFER_ID,
		"Their id never clashes with the guests the course numbers")
	assert_eq(course_owner.golfer_name, GameManager.player_profile.golfer_name,
		"They wear the owner's name")
	assert_false(golfers.get_active_golfers().has(course_owner),
		"They are not one of the guests playing the course")
	assert_not_null(owner_manager.duty, "They have the work to do")

func test_the_profile_follows_the_owner() -> void:
	var course_owner := owner_manager.ensure_golfer()
	GameManager.player_profile.golfer_name = "Renamed Owner"
	owner_manager.refresh_profile()
	assert_eq(course_owner.golfer_name, "Renamed Owner",
		"The golfer on the course wears the name the player gave them")
	assert_eq(course_owner.attributes.name, "Renamed Owner")

func test_the_work_area_moves_and_is_announced() -> void:
	owner_manager.ensure_golfer()
	var seen: Array = []
	owner_manager.area_changed.connect(func(center: Vector2i): seen.append(center))
	assert_true(owner_manager.set_area_center(Vector2i(12, 14)))
	assert_eq(owner_manager.area_center, Vector2i(12, 14))
	assert_eq(seen.size(), 1, "The move is announced, so the overlay can follow it")
	assert_eq(seen[0], Vector2i(12, 14))
	assert_eq(owner_manager.duty.area_center, Vector2i(12, 14),
		"Their work follows the ground they were given")
	assert_false(owner_manager.set_area_center(Vector2i(-1, 4)), "A tile off the course is refused")
	assert_eq(owner_manager.area_center, Vector2i(12, 14), "The ground they work does not move")

func test_the_work_area_survives_a_save() -> void:
	owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(9, 9))
	var data := owner_manager.serialize()
	owner_manager.set_area_center(Vector2i(20, 20))
	owner_manager.deserialize(data)
	assert_eq(owner_manager.area_center, Vector2i(9, 9), "The ground comes back with the course")
	assert_eq(owner_manager.duty.area_center, Vector2i(9, 9),
		"Their work is on the ground that was saved")
	# A course saved before the owner worked anywhere has no ground to restore.
	owner_manager.deserialize({})
	assert_eq(owner_manager.area_center, Vector2i(-1, -1),
		"A course with no ground saved has no ground to work")

func test_a_round_is_played_with_the_golfer_who_works_the_course() -> void:
	var course_owner := owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(10, 10))
	course_owner.global_position = grid.grid_to_screen_center(Vector2i(25, 25))
	var claimed := owner_manager.claim_for_round(4)
	assert_eq(claimed, course_owner, "The round is played with the same golfer")
	assert_true(golfers.get_active_golfers().has(course_owner), "They play with the group")
	assert_false(course_owner.is_on_course_duty(), "They are playing, not working")
	assert_eq(course_owner.group_id, 4)
	assert_false(owner_manager.duty.running, "The work stops while they play")
	owner_manager.release_from_round()
	assert_false(golfers.get_active_golfers().has(course_owner),
		"When the round is over they are not one of the guests playing")
	assert_eq(course_owner.group_id, -1)
	# The round ended away from the ground they work, so they walk back to it.
	assert_eq(owner_manager.duty.commute, OwnerDuty.Commute.HOME, "They walk back to their ground")
	assert_false(course_owner.is_on_course_duty(), "They are walking, not working yet")

func test_the_owner_walks_to_the_tee_and_back_to_their_ground() -> void:
	var course_owner := owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(10, 10))
	course_owner.global_position = grid.grid_to_screen_center(Vector2i(10, 10))
	var tee := Vector2i(20, 20)
	var claimed := owner_manager.claim_for_round(4, tee)
	assert_eq(claimed, course_owner)
	assert_eq(owner_manager.duty.commute, OwnerDuty.Commute.TO_TEE, "They walk to the tee")
	assert_eq(course_owner.ball_position, tee, "Their ball is on the tee while they walk to it")
	assert_false(owner_manager.duty.running, "The work stops while they walk to the tee")
	# The walk is the golfer's own: they arrive and the round can begin.
	course_owner.global_position = grid.grid_to_screen_center(tee)
	course_owner.path.clear()
	course_owner._on_reached_destination()
	owner_manager.duty._process(0.1)
	assert_eq(owner_manager.duty.commute, OwnerDuty.Commute.NONE, "The walk to the tee is over")
	owner_manager.release_from_round()
	# The round ended on the tee, away from the ground they work: they walk
	# back to it and pick the work up again.
	assert_eq(owner_manager.duty.commute, OwnerDuty.Commute.HOME, "They walk back to their ground")
	course_owner.global_position = grid.grid_to_screen_center(Vector2i(10, 10))
	course_owner.path.clear()
	course_owner._on_reached_destination()
	owner_manager.duty._process(0.1)
	assert_eq(owner_manager.duty.commute, OwnerDuty.Commute.NONE, "The walk home is over")
	assert_true(owner_manager.duty.running, "The work starts again on their ground")
	assert_true(course_owner.is_on_course_duty(), "They are working the course again")

func test_the_owner_pulls_the_weeds_in_their_area() -> void:
	var course_owner := owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(10, 10))
	var inside := Vector2i(10, 10)
	var outside := Vector2i(25, 25)
	assert_true(weeds.spawn_weed(inside, 0.4))
	assert_true(weeds.spawn_weed(outside, 0.4))
	course_owner.global_position = grid.grid_to_screen_center(inside)
	var duty := owner_manager.duty
	assert_true(_run_duty(duty, func(): return not weeds.has_weed(inside)),
		"The weed on their ground is pulled")
	assert_true(weeds.has_weed(outside), "A weed outside their ground is left alone")
	assert_eq(duty.job, OwnerDuty.Job.GREETER, "The two jobs alternate")

func test_the_owner_cheers_up_the_golfers_in_their_area() -> void:
	owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(10, 10))
	var guest: Golfer = add_child_autofree(load("res://scenes/entities/golfer.tscn").instantiate())
	guest.global_position = grid.grid_to_screen_center(Vector2i(10, 10))
	guest.attitude = 0.2
	golfers.join_course(guest, 1)
	var duty := owner_manager.duty
	assert_true(_run_duty(duty, func(): return guest.attitude > 0.2),
		"The owner chats with the golfers on their ground")
	assert_gt(guest.attitude, 0.2, "The chat cheers them up")

func test_the_owner_keeps_to_their_ground() -> void:
	var course_owner := owner_manager.ensure_golfer()
	owner_manager.set_area_center(Vector2i(10, 10))
	var duty := owner_manager.duty
	# With nothing to do, they walk about inside the ground they were given.
	for i in range(400):
		duty._process(0.1)
		var here := grid.screen_to_grid_point(course_owner.global_position)
		assert_lte(here.distance_to(Vector2(10, 10)), owner_manager.area_radius + 1.0,
			"The owner stays on the ground they work")
