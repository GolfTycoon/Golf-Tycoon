extends MainSceneTest
## Hiring staff puts them on the course: one hire of each job gets a body, a
## groundskeeper's designated area moves where the player clicks, the
## groundskeeper walks to a weed inside it and pulls it, and firing takes the
## body off the course.

const AREA_TILE := Vector2i(8, 8)

var staff: StaffManager


func before_all() -> void:
	await super()
	seed(90210)
	await new_game("Staff")
	staff = GameManager.staff_manager
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)


func test_every_hire_gets_a_body_on_the_course() -> void:
	assert_not_null(GameManager.weed_manager, "The course has a weed manager")
	for staff_type in [StaffManager.StaffType.GROUNDSKEEPER, StaffManager.StaffType.CELEBRITY,
			StaffManager.StaffType.RANGER, StaffManager.StaffType.SODA_VENDOR]:
		assert_true(staff.hire_staff(staff_type), "Hiring staff type %d succeeds" % staff_type)
	await process_frames(10)
	assert_eq(main.staff_container.get_child_count(), 4, "Every hire gets a body on the course")


func test_a_groundskeeper_pulls_the_weeds_in_their_area() -> void:
	var groundskeeper := 0
	assert_eq(int(staff.hired_staff[groundskeeper].get("type", -1)), StaffManager.StaffType.GROUNDSKEEPER,
		"The first hire is the groundskeeper")
	main._on_staff_area_move_requested(groundskeeper)
	assert_eq(main._staff_area_mode_index, groundskeeper, "Moving the area engages area mode")
	main._handle_staff_area_click(AREA_TILE)
	assert_eq(staff.get_staff_area(groundskeeper), AREA_TILE, "The designated area moves to the clicked tile")
	assert_eq(main._staff_area_mode_index, -1, "Area mode ends with the click")

	assert_true(GameManager.weed_manager.spawn_weed(AREA_TILE, 0.5), "A weed grows in the area")
	var body = staff.get_entity(int(staff.hired_staff[groundskeeper].staff_id))
	assert_not_null(body, "The groundskeeper has a body")
	if body == null:
		return
	body.global_position = GameManager.terrain_grid.grid_to_screen_center(AREA_TILE)
	assert_true(await process_frames_until(func() -> bool: return not GameManager.weed_manager.has_weed(AREA_TILE),
		3000), "The groundskeeper walks over and pulls the weed")


func test_firing_takes_the_body_off_the_course() -> void:
	var bodies: int = main.staff_container.get_child_count()
	assert_true(staff.fire_staff(0), "Firing succeeds")
	await process_frames(3)
	assert_lt(main.staff_container.get_child_count(), bodies, "Fired staff leave the course")
