extends MainSceneTest
## A smoke test of a running course: the Quick Start course plays several days at
## Ultra speed with every kind of staff on it while the panels open and close,
## the view turns and the map toggles, and it is saved and loaded on the way.
## Mostly it is here to surface runtime errors (test.sh fails on any), so its
## own checks are few.

const SAVE_NAME := "integration_simulation_smoke"
const DAYS := 4
const DAY_FRAMES := 1500
const PANELS: Array[StringName] = [
	&"_toggle_analytics_panel", &"_toggle_milestones_panel", &"_toggle_course_scorecard_panel",
	&"_toggle_event_feed",
	&"_toggle_marketing_panel", &"_toggle_tournament_panel", &"_toggle_seasonal_calendar",
	&"_toggle_hotkey_panel", &"_toggle_weather_debug_panel", &"_toggle_season_debug_panel",
	&"_toggle_terrain_debug_overlay",
]


func before_all() -> void:
	await super()
	await quick_start("Simulation smoke")
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)


func after_all() -> void:
	SaveManager.delete_save(SAVE_NAME)
	super()


func _run_a_day() -> bool:
	var day := GameManager.current_day
	return await process_frames_until(func() -> bool:
		var summary = main.get_node_or_null("UI/HUD/YearSummary")
		if summary:
			summary.continue_pressed.emit()
		return GameManager.current_day != day, DAY_FRAMES)


func test_every_kind_of_staff_works_the_course() -> void:
	var staff: StaffManager = GameManager.staff_manager
	for staff_type in StaffManager.StaffType.values():
		staff.hire_staff(staff_type)
	await process_frames(20)
	assert_eq(main.staff_container.get_child_count(), staff.hired_staff.size(),
		"Every hire has a body on the course")
	main._on_staff_area_move_requested(0)
	main._handle_staff_area_click(Vector2i(74, 64))
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.STAFF)
	await process_frames(5)
	assert_eq(staff.get_staff_area(0), Vector2i(74, 64), "An area moves across the course")


func test_the_panels_and_the_view_work_while_days_go_by() -> void:
	for day in range(DAYS):
		for panel in [PANELS[(day * 2) % PANELS.size()], PANELS[(day * 2 + 1) % PANELS.size()],
				PANELS[(day * 5 + 3) % PANELS.size()]]:
			main.call(panel)
			await process_frames(3)
			main.call(panel)
			await process_frames(3)
		main._on_view_rotate_cw()
		await process_frames(3)
		main._on_view_rotate_ccw()
		main._on_map_toggled(true)
		await process_frames(3)
		main._on_map_toggled(false)
		assert_true(await _run_a_day(), "Day %d goes by" % day)


func test_the_running_course_saves_and_loads() -> void:
	assert_true(SaveManager.save_game(SAVE_NAME), "The running course saves")
	assert_true(await _run_a_day(), "A day goes by after the save")
	assert_true(SaveManager.load_game(SAVE_NAME), "The save loads")
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	assert_true(await _run_a_day(), "and the loaded course plays on")
