extends GutTest
## The course benchmark tour's matrix and arithmetic: the suites must cover
## the game's real variables (every course type, hole count, terrain type,
## improvement, golfer field, camera move, edit style and game speed), the
## seeded scenarios must be ones the generators can actually build, and the
## per-course numbers must roll up into subsystem comparisons the report and
## the results screen read.

func _building_ids() -> Array[String]:
	var ids: Array[String] = []
	var file := FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if file == null:
		return ids
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		for key in (parsed.get("buildings", {}) as Dictionary).keys():
			ids.append(str(key))
	return ids

func test_the_suites_are_buildable_scenarios() -> void:
	var building_ids := _building_ids()
	assert_false(building_ids.is_empty(), "the building catalog loads for validation")
	assert_eq(CourseBenchmarkScenarios.validate_suite(
		CourseBenchmarkScenarios.full_suite(), building_ids), [],
		"the full suite passes its own validation against the live catalog")
	assert_eq(CourseBenchmarkScenarios.validate_suite(
		CourseBenchmarkScenarios.quick_suite(), building_ids), [],
		"and so does the quick suite")

func test_the_full_suite_covers_every_course_variable() -> void:
	var full := CourseBenchmarkScenarios.full_suite()
	assert_eq(full.size(), 11, "the full tour visits eleven courses")
	assert_eq(CourseBenchmarkScenarios.covered(full, "theme").size(),
		CourseTheme.Type.size(), "every course type (theme) is toured")
	for holes in [3, 6, 9, 18]:
		assert_true(CourseBenchmarkScenarios.covered(full, "holes").has(holes),
			"%d-hole courses are toured" % holes)
	for layout in ["generated", "quick_start",
			"prebuilt:executive", "prebuilt:championship18"]:
		assert_true(CourseBenchmarkScenarios.covered(full, "layout").has(layout),
			"the %s layout is toured" % layout)
	for speed in [GameManager.GameSpeed.NORMAL, GameManager.GameSpeed.FAST,
			GameManager.GameSpeed.ULTRA]:
		assert_true(CourseBenchmarkScenarios.covered(full, "speed").has(int(speed)),
			"game speed %d is simulated" % int(speed))
	for plan in ["still", "pan", "zoom", "tour", "tour_rotate"]:
		assert_true(CourseBenchmarkScenarios.covered(full, "camera").has(plan),
			"camera plan %s runs" % plan)
	for plan in ["none", "paint", "elevation", "both", "stress"]:
		assert_true(CourseBenchmarkScenarios.covered(full, "edit").has(plan),
			"terrain editing plan %s runs" % plan)
	var golfers := CourseBenchmarkScenarios.covered(full, "golfers")
	assert_true(golfers.has(0), "an empty course is measured")
	assert_true(int(golfers.max()) >= 32, "and a full field of 32 golfers")
	var visiting := CourseBenchmarkScenarios.covered(full, "visiting_fraction")
	assert_true(float(visiting.max()) >= 0.75, "visiting-golfer pools are exercised")
	assert_true(CourseBenchmarkScenarios.covered(full, "weather").has("rain"),
		"a rainy day is simulated")
	assert_gte(CourseBenchmarkScenarios.covered_buildings(full).size(), 12,
		"twelve or more different buildings and facilities get built")
	var terrain := CourseBenchmarkScenarios.covered_terrain_types(full)
	for required in [TerrainTypes.Type.WATER,
			TerrainTypes.Type.STREAM,
			TerrainTypes.Type.BUNKER,
			TerrainTypes.Type.DEEP_ROUGH,
			TerrainTypes.Type.TREES,
			TerrainTypes.Type.PINE]:
		assert_true(terrain.has(int(required)),
			"terrain type %d is painted or stamped" % int(required))
	for scenario in full:
		assert_ne(int(scenario["seed"]), 0, "no scenario uses the random seed 0")

func test_the_quick_suite_is_a_faster_slice_of_the_full_one() -> void:
	var quick := CourseBenchmarkScenarios.quick_suite()
	var full_ids: Array = []
	for scenario in CourseBenchmarkScenarios.full_suite():
		full_ids.append(str(scenario["id"]))
	assert_eq(quick.size(), 4, "four courses")
	for scenario in quick:
		assert_true(full_ids.has(str(scenario["id"])),
			"%s is part of the full suite" % str(scenario["id"]))
	for holes in [9, 18]:
		assert_true(CourseBenchmarkScenarios.covered(quick, "holes").has(holes),
			"the quick tour still builds %d holes" % holes)
	assert_true(CourseBenchmarkScenarios.covered(quick, "speed")
		.has(int(GameManager.GameSpeed.ULTRA)), "and still runs at Ultra speed")
	assert_eq(CourseBenchmarkScenarios.suite_name(
		CourseBenchmarkScenarios.SUITE_QUICK), "Quick course tour", "suites carry names")
	assert_eq((CourseBenchmarkScenarios.suite_by_id(
		CourseBenchmarkScenarios.SUITE_FULL).get("scenarios", []) as Array).size(),
		11, "the full suite is reachable by id")

func test_validation_catches_unbuildable_scenarios() -> void:
	var building_ids := _building_ids()
	var bad: Array[Dictionary] = [CourseBenchmarkScenarios.scenario_with({
		"id": "broken", "theme": 99, "holes": 5, "golfers": 400,
		"buildings": ["no_such_building"], "seed": 0,
	})]
	var problems := CourseBenchmarkScenarios.validate_suite(bad, building_ids)
	assert_false(problems.is_empty(), "a broken scenario is reported")
	var joined := " | ".join(problems)
	assert_string_contains(joined, "theme", "including its theme")
	assert_string_contains(joined, "holes", "its hole count")
	assert_string_contains(joined, "no_such_building", "its unknown building")
	assert_string_contains(joined, "seed", "and its random seed")

func test_scenarios_describe_themselves() -> void:
	var baseline: Dictionary = CourseBenchmarkScenarios.full_suite()[0]
	var text := CourseBenchmarkScenarios.describe(baseline)
	assert_string_contains(text, "Parkland", "the description names the course type")
	assert_string_contains(text, "9 holes", "the hole count")
	assert_string_contains(text, "8 golfers", "the field")

## Tour records in the shape CourseBenchmarkTour writes them: a build
## breakdown, what actually got placed and spawned, and the three sampled
## phases under `phases`.
func _record(name: String, holes: int, build_ms: float, spawned: int,
		visiting: int, speed: int, cam_fps: float, sim_fps: float,
		days: float, tiles: int, vertices: int,
		paint_ms: float, elevation_ms: float) -> Dictionary:
	return {
		"id": name.to_lower(), "name": name, "description": "%s · %d holes" % [name, holes],
		"holes": holes, "holes_built": holes, "speed": speed,
		"build": {"total_ms": build_ms},
		"counts": {"buildings": 2, "decorations": 3, "path_tiles": 100,
			"golfers_spawned": spawned, "visiting_spawned": visiting,
			"terrain_patch_tiles": 50},
		"phases": {
			"camera": {"average_fps": cam_fps, "sample_count": 100},
			"simulate": {"average_fps": sim_fps, "one_percent_low_fps": sim_fps * 0.8,
				"process_ms_per_frame": 3.0, "days_advanced": days,
				"sample_seconds": 2.0, "sample_count": 100},
			"edit": {"tiles_changed": tiles, "vertices_changed": vertices,
				"paint_ms": paint_ms, "elevation_ms": elevation_ms},
		},
	}

func _tour_records() -> Array:
	return [
		_record("Alpha", 9, 400.0, 12, 0, 1, 118.0, 100.0, 1.0, 300, 0, 10.0, 0.0),
		_record("Beta", 18, 900.0, 32, 8, 8, 90.0, 60.0, 3.0, 200, 100, 10.0, 10.0),
		_record("Gamma", 9, 200.0, 0, 0, 1, 140.0, 130.0, 0.5, 0, 0, 0.0, 0.0),
	]

func test_tour_rollups_compare_the_games_subsystems() -> void:
	var summary := PerformanceBenchmark.summarize_tour(_tour_records())
	assert_eq(summary["scenario_count"], 3, "three courses toured")
	var generation: Dictionary = summary["generation"]
	assert_almost_eq(float(generation["total_ms"]), 1500.0, 0.001,
		"generation totals every course")
	assert_eq(str(generation["slowest_scenario"]), "Beta", "the slowest build is named")
	var by_holes: Array = generation["by_hole_count"]
	assert_eq(by_holes.size(), 2, "generation is grouped by hole count")
	assert_eq(int(by_holes[0]["holes"]), 9, "9-hole average first")
	assert_almost_eq(float(by_holes[0]["average_ms"]), 300.0, 0.001,
		"the two 9-hole builds average 300 ms")
	var simulation: Dictionary = summary["simulation"]
	assert_eq(str(simulation["worst_scenario"]), "Beta", "the heaviest course is named")
	assert_eq(str(simulation["best_scenario"]), "Gamma", "and the lightest")
	var by_golfers: Array = simulation["by_golfer_count"]
	assert_eq(by_golfers.size(), 3, "fields of 0, 12 and 32 are separated")
	assert_eq(int(by_golfers[2]["golfers"]), 32, "largest field last")
	assert_almost_eq(float(by_golfers[2]["average_fps"]), 60.0, 0.001,
		"its frame rate rides along")
	var by_speed: Array = simulation["by_speed"]
	assert_eq(by_speed.size(), 2, "Normal and Ultra speeds are separated")
	assert_almost_eq(float(by_speed[1]["days_per_second"]), 1.5, 0.001,
		"Ultra advanced 3 game-days in 2 seconds")
	var editing: Dictionary = summary["editing"]
	assert_eq(int(editing["tiles_changed"]), 500, "painted tiles total")
	assert_eq(int(editing["vertices_changed"]), 100, "elevation vertices total")
	assert_almost_eq(float(editing["tiles_per_second"]), 20000.0, 0.001,
		"600 moved tiles in 30 ms of brush work is 20k a second")
	var totals: Dictionary = summary["totals"]
	assert_eq(int(totals["holes"]), 36, "36 holes built across the tour")
	assert_eq(int(totals["visiting_spawned"]), 8, "visiting golfers counted")

func test_tour_rows_feed_the_results_table() -> void:
	var result := {"tour": {"scenarios": _tour_records()}}
	var rows := PerformanceBenchmark.tour_scenario_rows(result)
	assert_eq(rows.size(), 3, "one row per toured course")
	assert_eq(str(rows[1]["name"]), "Beta", "rows keep tour order")
	assert_string_contains(str(rows[1]["detail"]), "18 holes", "rows describe the course")
	assert_almost_eq(float(rows[1]["sim_fps"]), 60.0, 0.001, "rows carry the sim rate")
	assert_string_contains(str(rows[1]["edit_text"]), "tiles/vertices",
		"edited rows quote the brush work")
	assert_string_contains(str(rows[2]["edit_text"]), "no editing",
		"an unedited course says so")
	assert_eq(PerformanceBenchmark.tour_scenario_rows({}), [],
		"a quick check has no tour rows")

func _report_result(with_tour: bool) -> Dictionary:
	var result := {
		"benchmark_version": PerformanceBenchmark.BENCHMARK_VERSION,
		"started_at_unix": 1_700_000_000,
		"duration_seconds": 40.0,
		"device": {}, "display": {}, "engine": {},
		"context": {"scenario": "course tour" if with_tour else "test scene"},
		"frame_sample_seconds": 10.0,
		"frame": {"sample_count": 100, "average_fps": 60.0,
			"one_percent_low_fps": 40.0, "p95_frame_ms": 20.0,
			"frames_over_33ms": 3},
		"gpu": {"available": false, "reason": "headless"},
		"cpu": {"work_units": 1000, "score": 500.0},
		"memory": {},
		"score": {"overall": 0.0, "grade": "Unrated", "stars": 0, "metrics": {}},
	}
	if with_tour:
		result["tour"] = {"suite": "test", "suite_name": "Test tour",
			"scenarios": _tour_records(),
			"rollup": PerformanceBenchmark.summarize_tour(_tour_records()),
			"restored": true}
	return result

func test_a_tour_report_names_every_course_it_built() -> void:
	var text := PerformanceBenchmark.format_report(_report_result(true))
	assert_string_contains(text, "GTB-3", "the tour report carries the new version")
	assert_string_contains(text, "Course tour Test tour", "the tour is headed by suite")
	assert_string_contains(text, "3 courses built on screen", "it says what happened")
	assert_string_contains(text, "Beta", "each toured course is listed")
	assert_string_contains(text, "Simulation by field", "golfer-field comparisons included")
	assert_string_contains(text, "Simulation by speed", "game-speed comparisons included")
	assert_string_contains(text, "Terrain editing", "editing throughput included")
	assert_string_contains(text, "player's course restored: yes",
		"the report confirms the player's course came back")
	assert_string_contains(text, "same tour suite", "and how to compare fairly")

func test_a_quick_check_report_still_reads_as_before() -> void:
	var text := PerformanceBenchmark.format_report(_report_result(false))
	assert_false(text.contains("Course tour"), "no tour section without a tour")
	assert_string_contains(text, "same course/save", "the old fairness note stays")

func test_history_records_the_tour_alongside_the_headline_numbers() -> void:
	var old_path := BenchmarkHistory.history_path
	BenchmarkHistory.history_path = "user://test_tour_benchmark_history.json"
	BenchmarkHistory.clear()
	var record := BenchmarkHistory.record_from(_report_result(true))
	assert_eq(str(record["tour_suite"]), "test", "the suite is shelved")
	assert_eq(int(record["tour_scenarios"]), 3, "with its course count")
	assert_eq(str(record["tour_worst_scenario"]), "Beta", "its heaviest course")
	assert_almost_eq(float(record["tour_worst_fps"]), 60.0, 0.05,
		"and that course's frame rate")
	assert_almost_eq(float(record["tour_generation_ms"]), 1500.0, 0.05,
		"and total build time")
	var quick := BenchmarkHistory.record_from(_report_result(false))
	assert_false(quick.has("tour_suite"), "a quick check shelves no tour fields")
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = old_path
