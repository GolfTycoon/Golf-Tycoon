extends MainSceneTest
## The course benchmark tour, end to end on the live scene: it borrows the
## player's course view, visibly builds seeded test courses of different
## types with different hole counts, golfers, camera plans, editing plans
## and game speeds under its banner, measures each phase, and then puts
## the player's course back exactly as it was - finished or cancelled.

const HISTORY_PATH := "user://test_tour_integration_history.json"

var _old_history_path := ""


func before_all() -> void:
	await super()
	_old_history_path = BenchmarkHistory.history_path
	BenchmarkHistory.history_path = HISTORY_PATH
	BenchmarkHistory.clear()
	await quick_start()


func after_all() -> void:
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = _old_history_path
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


func _course_fingerprint() -> Dictionary:
	return {
		"terrain": main.terrain_grid.serialize().duplicate(true),
		"holes": GameManager.current_course.holes.size(),
		"theme": int(GameManager.current_theme),
		"name": GameManager.course_name,
		"day": GameManager.current_day,
		"money": GameManager.money,
		"camera_position": main.camera.position,
		"camera_zoom": main.camera.zoom,
		"speed": int(GameManager.current_speed),
	}


func _assert_fingerprint(before: Dictionary, context: String) -> void:
	var after := _course_fingerprint()
	assert_eq(after["terrain"], before["terrain"], "%s: the ground is byte-for-byte back" % context)
	assert_eq(after["holes"], before["holes"], "%s: the holes are back" % context)
	assert_eq(after["theme"], before["theme"], "%s: the course type is back" % context)
	assert_eq(after["name"], before["name"], "%s: the name is back" % context)
	assert_eq(after["day"], before["day"], "%s: the day did not move" % context)
	assert_eq(after["money"], before["money"], "%s: the money did not move" % context)
	assert_lt((after["camera_position"] as Vector2).distance_to(before["camera_position"]), 2.0,
		"%s: the camera is back" % context)
	assert_almost_eq((after["camera_zoom"] as Vector2).x, (before["camera_zoom"] as Vector2).x, 0.02,
		"%s: the zoom is back" % context)
	assert_eq(after["speed"], before["speed"], "%s: the game speed is back" % context)
	assert_false(SaveManager.benchmark_suppression, "%s: autosaves are armed again" % context)


func test_the_tour_builds_seeded_courses_on_screen_and_restores_the_players() -> void:
	var before := _course_fingerprint()
	assert_eq(before["holes"], 9, "the player starts on their Quick Start 9")

	var tour := _tour()
	var completed: Array = []
	var progress: Array = []
	tour.completed.connect(func(run_result: Dictionary) -> void: completed.append(run_result))
	tour.progress_changed.connect(func(status: Dictionary) -> void: progress.append(status))

	var scenarios: Array = [
		CourseBenchmarkScenarios.scenario_with({
			"id": "test_desert", "name": "Test - Desert 3",
			"theme": CourseBenchmarkScenarios.THEME.DESERT,
			"holes": 3, "seed": 9901, "golfers": 3,
			"speed": int(GameManager.GameSpeed.NORMAL),
			"camera": "pan", "edit": "both"}),
		CourseBenchmarkScenarios.scenario_with({
			"id": "test_woodland", "name": "Test - Woodland 6",
			"theme": CourseBenchmarkScenarios.THEME.WOODLAND,
			"holes": 6, "seed": 9902, "golfers": 5, "visiting_fraction": 0.4,
			"speed": int(GameManager.GameSpeed.ULTRA),
			"camera": "tour_rotate", "edit": "stress"}),
	]
	assert_true(tour.start_scenarios(scenarios, "test", "Test tour"),
		"the tour starts on the open course")
	assert_true(tour.is_running(), "and is underway")

	# The tour is visible: its banner is on screen while a test course with
	# a different hole count replaces the player's on the live view.
	var built := await process_frames_until(
		func() -> bool: return GameManager.current_course != null \
			and GameManager.current_course.holes.size() == 3, 600)
	assert_true(built, "the 3-hole Desert test course is built on screen")
	assert_eq(int(GameManager.current_theme), int(CourseBenchmarkScenarios.THEME.DESERT),
		"under a different course type than the player's")
	assert_not_null(tour.find_child("BenchmarkTourOverlay", true, false),
		"under the tour banner")
	assert_true(main.camera.benchmark_controlled, "the camera belongs to the tour")

	var finished := await process_frames_until(
		func() -> bool: return not completed.is_empty(), 8000)
	assert_true(finished, "the tour runs to completion")
	await process_frames(2)
	if completed.is_empty():
		return
	var result: Dictionary = completed[0]
	assert_false(progress.is_empty(), "progress was published while it ran")
	assert_eq(str(result.get("benchmark_version", "")), "GTB-4",
		"the result carries the tour benchmark version")

	var tour_data: Dictionary = result.get("tour", {})
	assert_true(bool(tour_data.get("restored", false)), "the run reports its restore")
	assert_false(bool(tour_data.get("prepare", {}).get("prepared", true)),
		"this tour borrowed the open course instead of preparing one")
	var records: Array = tour_data.get("scenarios", [])
	assert_eq(records.size(), 2, "both test courses were toured")
	for entry in records:
		var record: Dictionary = entry
		var label := str(record.get("name", "?"))
		assert_gt(float(record.get("build", {}).get("total_ms", 0.0)), 0.0,
			"%s: building the course was timed" % label)
		assert_eq(int(record.get("holes_built", 0)), int(record.get("holes", 0)),
			"%s: every hole was built" % label)
		var counts: Dictionary = record.get("counts", {})
		assert_gt(int(counts.get("golfers_spawned", 0)), 0,
			"%s: golfers took to the course" % label)
		var phases: Dictionary = record.get("phases", {})
		for phase in ["prepare", "camera", "simulate", "edit"]:
			assert_true(phases.has(phase), "%s: the %s phase ran" % [label, phase])
		assert_gt(int(phases.get("prepare", {}).get("sample_count", 0)), 0,
			"%s: preparing the course (build and settle) was sampled" % label)
		assert_gt(int(phases.get("camera", {}).get("sample_count", 0)), 0,
			"%s: camera movement was sampled" % label)
		assert_gt(int(phases.get("simulate", {}).get("sample_count", 0)), 0,
			"%s: the simulation was sampled" % label)
		assert_gt(int(phases.get("edit", {}).get("tiles_changed", 0))
			+ int(phases.get("edit", {}).get("vertices_changed", 0)), 0,
			"%s: terrain editing moved ground" % label)

	var frame: Dictionary = result.get("frame", {})
	assert_gt(int(frame.get("sample_count", 0)), 0,
		"headline frame pacing pools the toured courses")
	assert_string_contains(str(result.get("report_text", "")), "Course tour",
		"the report tells the tour's story")
	assert_eq(PerformanceBenchmark.last_result, result,
		"the results screen will open on this run")
	assert_false(BenchmarkHistory.load_runs().is_empty(),
		"the finished tour lands on the shelf")

	_assert_fingerprint(before, "after the tour")
	assert_false(main.camera.benchmark_controlled, "the camera is the player's again")
	assert_null(tour.find_child("BenchmarkTourOverlay", true, false),
		"and the banner has come down")


func test_cancelling_the_tour_puts_the_players_course_back() -> void:
	var before := _course_fingerprint()
	var tour := _tour()
	tour.simulate_duration_usec = 30_000_000  # long enough to cancel mid-run
	var cancelled: Array = []
	tour.cancelled.connect(func(run_result: Dictionary) -> void: cancelled.append(run_result))
	var runs_before := BenchmarkHistory.load_runs().size()

	assert_true(tour.start_scenarios([CourseBenchmarkScenarios.scenario_with({
		"id": "test_cancel", "name": "Test - Cancel 3",
		"theme": CourseBenchmarkScenarios.THEME.LINKS,
		"holes": 3, "seed": 9903, "golfers": 2,
		"camera": "tour", "edit": "paint",
	})], "test", "Test tour"), "the tour starts")
	var built := await process_frames_until(
		func() -> bool: return GameManager.current_course != null \
			and GameManager.current_course.holes.size() == 3, 600)
	assert_true(built, "the test course is up before the cancel")

	tour.cancel()
	var stopped := await process_frames_until(
		func() -> bool: return not tour.is_running(), 600)
	assert_true(stopped, "cancel stops the tour")
	await process_frames(2)
	assert_eq(cancelled.size(), 1, "the cancel is reported")
	if not cancelled.is_empty():
		assert_true(bool(cancelled[0].get("tour", {}).get("cancelled", false)),
			"as a cancelled tour")
	assert_eq(BenchmarkHistory.load_runs().size(), runs_before,
		"a cancelled tour never reaches the shelf")
	_assert_fingerprint(before, "after cancelling")


func test_main_only_starts_the_tour_from_main_menu_settings() -> void:
	# Main guards the entry point: benchmarks run only when Settings was
	# accessed from the Main Menu. The runner itself refuses a second run
	# while one is underway.
	var tour := _tour()
	assert_false(tour.is_running(), "no tour is running between tests")
	assert_false(main.start_course_benchmark(CourseBenchmarkScenarios.SUITE_QUICK),
		"with no Main Menu Settings behind it, Main refuses the tour")
	assert_false(tour.is_running(), "and nothing started")
	main._on_main_menu_settings()
	await process_frames(2)
	assert_true(main.start_course_benchmark(CourseBenchmarkScenarios.SUITE_QUICK),
		"Main Menu Settings unlock the tour")
	assert_true(main._benchmark_tour_active, "Main marks the tour as owning the view")
	assert_false(main.start_course_benchmark(CourseBenchmarkScenarios.SUITE_QUICK),
		"a second tour cannot start over the first")
	main.course_benchmark_tour.cancel()
	var stopped := await process_frames_until(
		func() -> bool: return not main.course_benchmark_tour.is_running(), 600)
	assert_true(stopped, "and the tour stands down again")
	await process_frames(2)
	assert_false(main._benchmark_tour_active, "the view is the player's again")
