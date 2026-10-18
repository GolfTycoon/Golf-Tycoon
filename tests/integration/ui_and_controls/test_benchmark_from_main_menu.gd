extends MainSceneTest
## The benchmark from the title screen, end to end: Settings accessed from
## the Main Menu may run it, the tour prepares its own throwaway course
## (timed and sampled as part of the benchmark - no game is open to
## borrow), tours it, and hands the Main Menu back exactly as empty as it
## found it. Settings reached any other way run nothing.

const HISTORY_PATH := "user://test_main_menu_benchmark_history.json"

var _old_history_path := ""


func before_all() -> void:
	await super()
	_old_history_path = BenchmarkHistory.history_path
	BenchmarkHistory.history_path = HISTORY_PATH
	BenchmarkHistory.clear()
	# Deliberately no course: the scene sits on the Main Menu, which is
	# where benchmarks now live.


func after_all() -> void:
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = _old_history_path
	# A finished tour publishes itself as the newest report; do not leave
	# it behind for the next file's cold Settings card to adopt.
	PerformanceBenchmark.last_result = {}
	super()


## The tour, tuned down so the test measures in frames rather than seconds.
func _tour() -> CourseBenchmarkTour:
	var tour: CourseBenchmarkTour = main.course_benchmark_tour
	tour.settle_duration_usec = 60_000
	tour.camera_duration_usec = 250_000
	tour.simulate_duration_usec = 350_000
	tour.edit_max_stamps = 8
	var runner := tour.device_runner()
	runner.warmup_duration_usec = 15_000
	runner.frame_sample_duration_usec = 60_000
	runner.gpu_step_duration_usec = 20_000
	runner.cpu_sample_duration_usec = 60_000
	runner.cpu_budget_usec_per_frame = 200
	runner.gpu_test_enabled = false
	return tour


func _assert_back_on_the_title_screen(context: String) -> void:
	assert_eq(int(GameManager.current_mode), int(GameManager.GameMode.MAIN_MENU),
		"%s: the game is back in menu mode" % context)
	assert_null(GameManager.current_course,
		"%s: the throwaway course is gone - no course is open" % context)
	assert_false(SaveManager.benchmark_suppression,
		"%s: autosaves are armed again" % context)
	assert_false(main.camera.benchmark_controlled,
		"%s: the camera is free again" % context)


func test_main_refuses_the_tour_until_settings_come_from_the_main_menu() -> void:
	assert_eq(int(GameManager.current_mode), int(GameManager.GameMode.MAIN_MENU),
		"the scene opens on the Main Menu")
	assert_null(GameManager.current_course, "with no course open behind it")
	var tour := _tour()
	assert_false(main.start_course_benchmark(CourseBenchmarkScenarios.SUITE_QUICK),
		"the tour refuses before Settings were ever opened from the Main Menu")
	assert_false(tour.is_running(), "and nothing started")

	# The pause session's Settings do not unlock it either.
	main._show_settings_menu()
	await process_frames(2)
	var from_pause := main.get_node_or_null("UI/HUD/SettingsMenu") as SettingsMenu
	assert_not_null(from_pause, "the pause session's Settings open")
	if from_pause:
		assert_false(from_pause.benchmarks_allowed(), "but they may run nothing")
		from_pause.free()
		await process_frames(2)
	assert_false(main.start_course_benchmark(CourseBenchmarkScenarios.SUITE_QUICK),
		"pause Settings leave the tour refused")


func test_the_tour_prepares_its_own_course_and_hands_the_menu_back() -> void:
	var tour := _tour()
	var completed: Array = []
	tour.completed.connect(func(run_result: Dictionary) -> void: completed.append(run_result))

	var scenarios: Array = [
		CourseBenchmarkScenarios.scenario_with({
			"id": "test_menu_links", "name": "Test - Links 3",
			"theme": CourseBenchmarkScenarios.THEME.LINKS,
			"holes": 3, "seed": 9911, "golfers": 3,
			"speed": int(GameManager.GameSpeed.NORMAL),
			"camera": "tour", "edit": "both"}),
	]
	assert_true(tour.start_scenarios(scenarios, "test", "Test tour"),
		"the tour starts with no course open - it prepares its own")

	# Preparation is visible: a course session comes up under the banner
	# before the first test course replaces it.
	var prepared := await process_frames_until(
		func() -> bool: return GameManager.current_course != null, 600)
	assert_true(prepared, "the benchmark course is prepared on screen")
	var built := await process_frames_until(
		func() -> bool: return GameManager.current_course != null \
			and GameManager.current_course.holes.size() == 3, 600)
	assert_true(built, "and the 3-hole test course is built on it")
	assert_not_null(tour.find_child("BenchmarkTourOverlay", true, false),
		"under the tour banner")

	var finished := await process_frames_until(
		func() -> bool: return not completed.is_empty(), 8000)
	assert_true(finished, "the tour runs to completion")
	await process_frames(2)
	if completed.is_empty():
		return
	var result: Dictionary = completed[0]
	var tour_data: Dictionary = result.get("tour", {})
	var prepare: Dictionary = tour_data.get("prepare", {})
	assert_true(bool(prepare.get("prepared", false)),
		"the run reports the course it prepared")
	assert_gt(float(prepare.get("prepare_ms", 0.0)), 0.0,
		"preparing it was timed")
	var steps: Dictionary = prepare.get("steps_ms", {})
	for step in ["session_ms", "ground_ms", "land_ms", "camera_ms"]:
		assert_true(steps.has(step), "the %s preparation step was timed" % step)
	assert_gt(int(prepare.get("frame", {}).get("sample_count", 0)), 0,
		"preparation frames were sampled into the benchmark")
	var records: Array = tour_data.get("scenarios", [])
	assert_eq(records.size(), 1, "the test course was toured")
	if not records.is_empty():
		var phases: Dictionary = records[0].get("phases", {})
		assert_gt(int(phases.get("prepare", {}).get("sample_count", 0)), 0,
			"preparing that course (build and settle) was sampled too")
	assert_string_contains(str(result.get("report_text", "")),
		"benchmark course prepared", "the report tells the preparation's story")
	assert_string_contains(str(result.get("report_text", "")),
		"main menu restored: yes", "and confirms the title screen came back")
	assert_true(bool(tour_data.get("restored", false)), "the run reports its restore")
	_assert_back_on_the_title_screen("after the prepared tour")


func test_main_runs_the_tour_from_main_menu_settings_and_returns_there() -> void:
	var tour := _tour()
	main._on_main_menu_settings()
	await process_frames(2)
	var menu := main.get_node_or_null("UI/HUD/SettingsMenu") as SettingsMenu
	assert_not_null(menu, "Main Menu Settings open")
	if menu:
		assert_true(menu.benchmarks_allowed(), "and may run benchmarks")
	assert_not_null(main.main_menu, "the Main Menu is up before the run")

	assert_true(main.start_course_benchmark(CourseBenchmarkScenarios.SUITE_QUICK),
		"Main starts the tour from Main Menu Settings")
	assert_true(tour.is_running(), "the tour is underway")
	assert_null(main.main_menu, "the Main Menu steps aside while it runs")

	tour.cancel()
	var stopped := await process_frames_until(
		func() -> bool: return not tour.is_running(), 600)
	assert_true(stopped, "cancel stops the tour")
	await process_frames(2)
	assert_not_null(main.main_menu, "and the Main Menu is back afterwards")
	_assert_back_on_the_title_screen("after cancelling from the Main Menu")
