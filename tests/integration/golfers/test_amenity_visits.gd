extends MainSceneTest
## A guest's visit to an amenity in the real game: a hungry golfer walks to a
## snack bar within reach, pays when they get there, eats and goes back to play.
## The service income and the guest identities survive a save, and a loaded save
## resumes the day it was in without billing that day's costs twice.

## Clear ground away from the clubhouse, so the snack bar is the only amenity
## the guest can reach.
const SNACK_BAR := Vector2i(48, 50)
const GUEST_TILE := Vector2i(50, 53)


func before_all() -> void:
	await super()
	await new_game("Amenity visits")
	main._suppress_tile_undo = true
	for x in range(SNACK_BAR.x - 3, SNACK_BAR.x + 6):
		for y in range(SNACK_BAR.y - 3, SNACK_BAR.y + 7):
			main.terrain_grid.set_tile(Vector2i(x, y), TerrainTypes.Type.ROUGH)
	main._suppress_tile_undo = false
	assert_not_null(main.entity_layer.place_building("snack_bar", SNACK_BAR, main.building_registry),
		"A snack bar opens on the lot")
	# A hole to play, so the day can run.
	assert_not_null(build_hole(Vector2i(62, 58), Vector2i(62, 46)), "A hole opens on the lot")


func test_a_hungry_guest_walks_to_the_snack_bar_and_pays_on_arrival() -> void:
	var golfer: Golfer = main.golfer_manager.spawn_golfer("Hungry visitor", 0.5, 0)
	golfer.set_process(false)
	golfer.global_position = main.terrain_grid.grid_to_screen_center(GUEST_TILE)
	golfer.needs.hunger = 0.1
	var cash := GameManager.money
	var visits := FeedbackManager.service_visits
	var revenue := FeedbackManager.service_revenue

	golfer._check_building_proximity()
	assert_eq(golfer._amenity_phase, 1, "A hungry guest heads for the snack bar within reach")
	assert_eq(GameManager.money, cash, "Nothing is charged before the guest arrives")
	for i in range(800):
		golfer._process_amenity_visit(0.05)
		if golfer._amenity_phase == 0:
			break
	assert_eq(golfer._amenity_phase, 0, "The guest goes back to play")
	assert_gt(golfer.needs.hunger, 0.1, "Food restores hunger")
	assert_eq(golfer.amenities_used, 1, "The visit is counted for the guest")
	assert_eq(FeedbackManager.service_visits, visits + 1, "and for the course")
	assert_eq(GameManager.money, cash + 5, "The snack bar is paid on arrival")
	assert_eq(FeedbackManager.service_revenue, revenue + 5, "and books it as service revenue")


func test_service_income_and_guest_identities_survive_a_save() -> void:
	var revenue := FeedbackManager.service_revenue
	var key := FeedbackManager.next_guest_key()
	SaveManager._apply_save_data(JSON.parse_string(JSON.stringify(SaveManager._build_save_data())))
	assert_eq(FeedbackManager.service_revenue, revenue, "Service revenue survives a save")
	assert_ne(FeedbackManager.next_guest_key(), key, "A reload never reuses a guest identity")


func test_a_loaded_day_resumes_without_paying_its_costs_twice() -> void:
	GameManager._day_progress = 0.0
	GameManager.daily_stats.operating_costs = 100
	var day := GameManager.current_day
	var cash := GameManager.money
	assert_true(GameManager.start_simulation(), "The simulation starts")
	assert_eq(GameManager.current_day, day, "on the same day")
	assert_eq(GameManager.money, cash, "A settled day does not pay its costs again")

	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	var progress := GameManager._day_progress
	await process_frames(5)
	assert_eq(GameManager._day_progress, progress, "A paused day does not move on")
	assert_eq(GameManager.current_day, day, "nor roll over")
	GameManager.stop_simulation()
	assert_eq(Engine.time_scale, 1.0, "Building runs at real-time speed, so the UI stays responsive")
