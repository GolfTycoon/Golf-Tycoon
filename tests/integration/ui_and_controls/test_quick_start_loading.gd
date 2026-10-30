extends MainSceneTest
## The real Quick Start button must show the loading screen before rolling the
## world or initializing a course. The same screen then follows the job through
## generation, and a failed location search gives control back to the map.

var _saved_mod_locations: Array[Dictionary] = []


func before_each() -> void:
	super()
	_saved_mod_locations = WorldLocations.get_mod_locations()
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	if is_instance_valid(main.world_map_screen):
		main._close_world_map()
	if not is_instance_valid(main.main_menu):
		main._show_main_menu()
	await process_frames(2)


func after_each() -> void:
	WorldLocations.set_mod_locations(_saved_mod_locations)
	await super()


## Press the actual menu card through the viewport, without advancing a frame.
## That lets the test inspect what happens in the click's own frame.
func _click_quick_start() -> void:
	var button := main.main_menu.find_child("QuickStartButton", true, false) as Button
	assert_not_null(button, "the title screen offers Quick Start")
	if button == null:
		return
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)


func test_quick_start_paints_before_setup_and_reuses_the_loader() -> void:
	var observations := {"world_resets": 0, "painted_before_reset": false,
		"game_starts": 0, "loader_at_start": null}
	var on_world_reset := func() -> void:
		observations.world_resets += 1
		var observed_screen: GeneratingCourseScreen = main._generating_course_screen
		observations.painted_before_reset = is_instance_valid(observed_screen) \
				and observed_screen.is_inside_tree() and observed_screen._time > 0.0
	var on_game_started := func() -> void:
		observations.game_starts += 1
		observations.loader_at_start = main._generating_course_screen
	WorldMap.world_reset.connect(on_world_reset)
	EventBus.new_game_started.connect(on_game_started)

	var old_seed := WorldMap.world_seed
	var old_course: GameManager.CourseData = GameManager.current_course
	_click_quick_start()
	var screen: GeneratingCourseScreen = main._generating_course_screen
	assert_not_null(screen, "the click immediately installs the loading screen")
	if screen == null:
		WorldMap.world_reset.disconnect(on_world_reset)
		EventBus.new_game_started.disconnect(on_game_started)
		return
	assert_true(screen.is_inside_tree(), "the loader is in the scene")
	assert_false(main.main_menu.visible, "the title cannot accept another selection")
	assert_false(main.terrain_grid.visible, "the idle course stays hidden for the first paint")
	assert_eq(screen._status_base(), GeneratingCourseScreen.STAGE_LOCATION, "location preparation is visible")
	assert_eq(screen._stages.size(), 6, "the location and course share one checklist")
	assert_eq(WorldMap.world_seed, old_seed, "world creation has not happened in the click handler")
	assert_same(GameManager.current_course, old_course, "the old game state is not reset before the loader")
	assert_eq(observations.world_resets, 0, "no world roll has started yet")
	assert_false(main._gameplay_input_active(), "gameplay input is blocked during preparation")

	# A second activation during the preparation frames must not schedule a
	# second world roll or create a second overlay.
	main._on_menu_quick_start()
	assert_same(main._generating_course_screen, screen, "repeated activation reuses the pending job")
	assert_eq(observations.world_resets, 0, "the repeated activation does not start another job")

	var started := await process_frames_until(func() -> bool: return observations.game_starts > 0, 30)
	assert_true(started, "the course initialization starts")
	if not started:
		WorldMap.world_reset.disconnect(on_world_reset)
		EventBus.new_game_started.disconnect(on_game_started)
		return
	assert_eq(observations.world_resets, 1, "exactly one world was rolled")
	assert_true(observations.painted_before_reset,
		"the loader processed a complete frame before the synchronous world roll")
	assert_eq(observations.game_starts, 1, "exactly one game was initialized")
	assert_same(observations.loader_at_start, screen, "course generation keeps the original loader")
	assert_eq(screen._status_base(), GeneratingCourseScreen.STAGE_TERRAIN, "generation advances the checklist")
	assert_eq(screen._stages[0], GeneratingCourseScreen.STAGE_LOCATION, "the preparation stage is retained")
	assert_eq(screen._course_name,
		main._course_name_for_location(WorldMap.get_active_location()), "the loader names the chosen course")
	main._on_menu_quick_start()
	assert_same(main._generating_course_screen, screen, "another activation during generation is ignored")
	assert_eq(observations.world_resets, 1, "generation cannot start a second company")
	assert_false(main._gameplay_input_active(), "gameplay input stays blocked during generation")
	press_key(KEY_ESCAPE)
	assert_null(main.pause_menu, "Escape cannot open the pause menu during generation")
	assert_false(GameManager.is_paused, "Escape did not pause the new course")

	assert_true(await process_frames_until(func() -> bool: return main._generating_course_screen == null, 30),
		"the loading screen closes when generation is complete")
	await process_frames(2)
	WorldMap.world_reset.disconnect(on_world_reset)
	EventBus.new_game_started.disconnect(on_game_started)
	assert_false(is_instance_valid(screen), "the loading screen was freed")
	assert_ne(WorldMap.active_location_id, "", "Quick Start chose a location")
	assert_true(WorldMap.is_owned(WorldMap.active_location_id), "and bought it")
	assert_eq(GameManager.current_course.holes.size(), 3, "the course has its three generated holes")
	assert_not_null(CourseClubhouse.find(main.entity_layer), "the course has a clubhouse")
	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING, "the course is playable")
	assert_true(main.terrain_grid.visible, "the finished course is visible")
	press_key(KEY_ESCAPE)
	assert_not_null(main.pause_menu, "gameplay shortcuts work again after loading")
	press_key(KEY_ESCAPE)
	assert_null(main.pause_menu, "the pause menu can be closed again")


func test_touch_quick_start_shows_the_loader_before_world_setup() -> void:
	var button := main.main_menu.find_child("QuickStartButton", true, false) as Button
	assert_not_null(button, "the title screen offers Quick Start")
	if button == null:
		return
	var old_seed := WorldMap.world_seed
	var at := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = at
		touch.pressed = pressed
		get_viewport().push_input(touch)
	var screen: GeneratingCourseScreen = main._generating_course_screen
	assert_not_null(screen, "a touch immediately shows the loading screen")
	assert_eq(WorldMap.world_seed, old_seed, "touch does not roll the world before the loader paints")
	if screen == null:
		return
	assert_true(await process_frames_until(func() -> bool: return main._generating_course_screen == null, 30),
		"the touch-started course finishes")
	assert_eq(GameManager.current_course.holes.size(), 3, "touch starts the same three-hole course")


func test_no_affordable_location_closes_loader_and_opens_world_map() -> void:
	# Mod overrides can make every location unaffordable; exercise the real
	# failure path without replacing the world map or the picker with a stub.
	var expensive: Array[Dictionary] = []
	for definition in WorldLocations.get_all():
		var entry: Dictionary = definition.duplicate(true)
		entry["prestige"] = 10000.0
		expensive.append(entry)
	WorldLocations.set_mod_locations(expensive)

	# The title screen's Quick Start shortcut must enter the same early loader
	# as the mouse button, including the failure path.
	var shortcut := InputMap.action_get_events("quick_start")[0].duplicate() as InputEventKey
	shortcut.pressed = true
	get_viewport().push_input(shortcut)
	var screen: GeneratingCourseScreen = main._generating_course_screen
	assert_not_null(screen, "the shortcut shows the loader while searching")
	var map_opened := await process_frames_until(func() -> bool:
		return is_instance_valid(main.world_map_screen), 30)
	assert_true(map_opened, "the world map opens on failure")
	if not map_opened:
		return
	await process_frames(1)
	assert_null(main._generating_course_screen, "the loader no longer blocks input")
	assert_false(is_instance_valid(screen), "the failed job's loader was freed")
	assert_true(main.world_map_screen.visible, "the player can choose a location on the map")
	assert_eq(WorldMap.active_location_id, "", "no location was bought")
	assert_eq(GameManager.current_mode, GameManager.GameMode.MAIN_MENU, "the map stays in menu mode")
	press_key(KEY_ESCAPE)
	await process_frames(3)
	assert_null(main.world_map_screen, "the map responds to Back after the loader is dismissed")
	assert_not_null(main.main_menu, "Back returns to the title screen")


func test_leaving_the_scene_before_preparation_cancels_the_pending_start() -> void:
	var resets := {"count": 0}
	var on_world_reset := func() -> void: resets.count += 1
	WorldMap.world_reset.connect(on_world_reset)
	var old_seed := WorldMap.world_seed
	main._on_menu_quick_start()
	assert_not_null(main._generating_course_screen, "preparation was scheduled")
	remove_child(main)
	await process_frames(3)
	assert_eq(resets.count, 0, "a detached scene does not start a world")
	assert_eq(WorldMap.world_seed, old_seed, "the pending start leaves company state alone")
	WorldMap.world_reset.disconnect(on_world_reset)
	main.free()
	main = null
