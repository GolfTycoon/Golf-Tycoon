extends GameTest
## The Benchmark Results screen: the arrangement it picks for each window
## shape, the instruments it draws (the frame-time chart, the GPU ladder, the
## segmented meters, the golf scorecard and the shelf of past runs), and the
## pixel look it shares with the World Map - its MenuBackdrop background,
## Pixelify Sans, the notched nine-patch frames and whole-pixel charts.
##
## The screen is built from code, so these walk the built tree and check what
## it actually draws.

const TITLE_FONT_PATH := "res://assets/fonts/PixelifySans-Bold.ttf"
const SUBTITLE_FONT_PATH := "res://assets/fonts/PixelifySans-SemiBold.ttf"
const BODY_FONT_PATH := "res://assets/fonts/PixelifySans-Regular.ttf"
const HISTORY_PATH := "user://test_benchmark_results_screen_shelf.json"
const MIN_TARGET := 36.0

const SIZES := [
	[Vector2i(1600, 1000), "desktop"],
	[Vector2i(1180, 700), "small desktop"],
	[Vector2i(1024, 768), "tablet landscape"],
	[Vector2i(768, 1024), "tablet portrait"],
	[Vector2i(844, 390), "phone landscape"],
	[Vector2i(390, 844), "phone portrait"],
]

var _window_before := Vector2i.ZERO
var _old_history_path := ""

func before_each() -> void:
	super()
	_window_before = get_window().size
	_old_history_path = BenchmarkHistory.history_path
	BenchmarkHistory.history_path = HISTORY_PATH
	BenchmarkHistory.clear()
	PerformanceBenchmark.last_result = _report()

func after_each() -> void:
	# Let the rebuilds' queued frees land before GUT counts orphans.
	await process_frames(1)
	get_window().size = _window_before
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = _old_history_path
	PerformanceBenchmark.last_result = {}
	super()

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A finished report with a known shape, so the screen's numbers can be read
## back off it.
func _report() -> Dictionary:
	var series: Array[float] = []
	for index in range(120):
		series.append(16.0 if index % 12 != 0 else 44.0)
	return {
		"benchmark_version": "GTB-2",
		"game_version": "0.4.4",
		"engine_version": "4.6.stable",
		"build_type": "Release",
		"device_model": "Test device",
		"platform": "Test OS",
		"os_version": "Test OS 15",
		"cpu_name": "Test CPU",
		"cpu_cores": 8,
		"gpu_name": "Test GPU (Test vendor)",
		"renderer": "forward_plus / vulkan",
		"display_server": "Test display",
		"resolution": "1600 x 1000",
		"vsync": "On",
		"max_fps": 0,
		"started_at_unix": 1_760_000_000,
		"frame_sample_seconds": 2.5,
		"gpu_sample_seconds": 2.1,
		"context": {"scenario": "Course view", "day": 7},
		"frame": {
			"sample_count": 120,
			"average_fps": 62.0,
			"average_frame_ms": 16.1,
			"one_percent_low_fps": 51.0,
			"p95_frame_ms": 19.4,
			"worst_frame_ms": 44.0,
			"best_frame_ms": 14.0,
			"frames_over_33_ms": 10,
			"series_ms": series,
		},
		"cpu": {"work_units": 900_000, "compute_ms": 900.0, "units_per_second": 1_000_000.0},
		"gpu": {
			"available": true,
			"reason": "",
			"sample_seconds": 2.1,
			"levels": [
				{"overdraw": 1.0, "megapixels_per_second": 190.0, "fps": 60.0, "gpu_ms": 2.0,
					"capped": true, "frames": 20, "quad_side": 250, "fill_pixels": 2_000_000},
				{"overdraw": 4.0, "megapixels_per_second": 520.0, "fps": 55.0, "gpu_ms": 6.0,
					"capped": false, "frames": 20, "quad_side": 250, "fill_pixels": 8_000_000},
				{"overdraw": 10.0, "megapixels_per_second": 640.0, "fps": 26.0, "gpu_ms": 12.0,
					"capped": false, "frames": 20, "quad_side": 250, "fill_pixels": 20_000_000},
			],
			"peak_megapixels_per_second": 640.0,
			"peak_overdraw": 10.0,
			"gpu_ms_per_frame": 12.0,
			"frames_sampled": 20,
		},
		"engine": {
			"process_ms_per_frame": 4.2,
			"physics_ms_per_frame": 0.7,
			"render_objects": 240,
			"render_primitives": 3200,
			"draw_calls": 52,
			"node_count": 1880,
			"orphan_nodes": 0,
			"resource_count": 640,
		},
		"memory": {"static_mb": 128.0, "static_max_mb": 140.0, "video_mb": 72.0,
			"texture_mb": 44.0, "buffer_mb": 8.0},
		"score": {
			"overall": 72.0,
			"stars": 4,
			"tier": "Tour",
			"verdict": "Tour pace. Smooth play, with headroom for a bigger window.",
			"parts": {"pacing": 56.0, "cpu": 70.0, "gpu": 81.0, "consistency": 74.0},
			"gpu_measured": true,
			"measured": true,
			"stutter_rate": 0.083,
		},
		"report_text": "Golf Tycoon benchmark GTB-2\nTest report",
	}

func _screen(size: Vector2i) -> BenchmarkResultsScreen:
	get_window().size = size
	await process_frames(2)
	var screen := BenchmarkResultsScreen.new()
	add_child_autofree(screen)
	# Containers need a second frame to apply the minimum sizes they measured
	# on the first, so the rects read here are the ones the player sees.
	await process_frames(2)
	return screen

func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

func _labels_text(root: Node) -> String:
	var text := ""
	if root is Label:
		text += (root as Label).text + "\n"
	for child in root.get_children():
		text += _labels_text(child)
	return text

## Whether `node` sits inside a ScrollContainer: rows below the fold are
## reached by scrolling, so only their width is checked against the window.
func _inside_scroll(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false

func _visible_buttons(root: Node) -> Array:
	var found: Array = []
	for button in _nodes_of_class(root, "Button"):
		var control := button as Button
		if control.is_visible_in_tree() and control.get_global_rect().size.x > 0.0:
			found.append(control)
	return found

# ---------------------------------------------------------------------------
# The World Map's look
# ---------------------------------------------------------------------------

func test_the_screen_sits_on_the_world_map_background() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var backdrop := screen.find_child("Backdrop", true, false)
	assert_not_null(backdrop, "the backdrop is built")
	assert_true(backdrop is MenuBackdrop, "it is the World Map's shared background artwork")

func test_every_visible_word_uses_the_title_screens_pixelify_faces() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var allowed := [TITLE_FONT_PATH, SUBTITLE_FONT_PATH, BODY_FONT_PATH]
	var unstyled: Array[String] = []
	for label in _nodes_of_class(screen, "Label"):
		var path := (label as Label).get_theme_font("font").resource_path
		if not path in allowed:
			unstyled.append("%s -> %s" % [(label as Label).name, path])
	for button in _nodes_of_class(screen, "Button"):
		var control := button as Button
		if control.text.is_empty():
			continue
		var path := control.get_theme_font("font").resource_path
		if not path in allowed:
			unstyled.append("%s -> %s" % [control.name, path])
	assert_eq(unstyled, [], "every label and button uses Pixelify Sans")
	var title := screen.find_child("Title", true, false) as Label
	assert_not_null(title)
	if title:
		assert_eq(title.text, "Benchmark Results")
		assert_eq(title.get_theme_font("font").resource_path, TITLE_FONT_PATH,
			"the heading is the bold face")

func test_the_panels_wear_the_menus_notched_pixel_frames() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var unframed: Array[String] = []
	for panel_name in ["RatingPanel", "InstrumentsPanel", "FrameChartPanel", "GpuPanel",
			"EnginePanel", "ScorecardPanel", "HistoryPanel", "DevicePanel"]:
		var panel := screen.find_child(panel_name, true, false) as PanelContainer
		if panel == null:
			unframed.append("%s missing" % panel_name)
			continue
		var style := panel.get_theme_stylebox("panel")
		if not (style is StyleBoxTexture):
			unframed.append("%s -> %s" % [panel_name, style.get_class()])
	assert_eq(unframed, [], "every panel is a PixelButtonStyle nine-patch frame")

# ---------------------------------------------------------------------------
# Arrangements
# ---------------------------------------------------------------------------

func test_each_window_shape_gets_its_own_arrangement() -> void:
	for entry in SIZES:
		var size: Vector2i = entry[0]
		var tag := "%s %s" % [size, entry[1]]
		var screen: BenchmarkResultsScreen = await _screen(size)
		assert_eq(screen._layout_mode, MenuScreenKit.layout_mode_for(Vector2(size)),
			"%s: the arrangement for that shape" % tag)
		var body_name := "DesktopLayout" if screen._layout_mode == MenuScreenKit.LayoutMode.DESKTOP \
			else ("TabletLayout" if not MenuScreenKit.is_phone(screen._layout_mode) else "PhoneLayout")
		assert_not_null(screen.find_child(body_name, true, false), "%s: %s is built" % [tag, body_name])
		assert_not_null(screen.find_child("FrameChart", true, false),
			"%s: the frame chart is always on screen" % tag)
		assert_not_null(screen.find_child("ScorecardPanel", true, false),
			"%s: so is the scorecard" % tag)

func test_desktop_lays_the_report_out_in_three_columns() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var body := screen.find_child("DesktopLayout", true, false) as HBoxContainer
	assert_not_null(body)
	if body == null:
		return
	assert_eq(body.get_child_count(), 3, "the left rail, the charts and the instruments")
	var left := body.find_child("DesktopLeft", true, false) as Control
	var middle := body.find_child("DesktopMiddle", true, false) as Control
	var right := body.find_child("DesktopRight", true, false) as Control
	assert_not_null(left)
	assert_not_null(middle)
	assert_not_null(right)
	if left == null or middle == null or right == null:
		return
	assert_lt(left.get_global_rect().position.x, middle.get_global_rect().position.x,
		"the rail is left of the charts")
	assert_lt(middle.get_global_rect().position.x, right.get_global_rect().position.x,
		"and the instruments are right of them")
	assert_not_null(left.find_child("RatingPanel", true, false), "the rating heads the rail")
	assert_not_null(middle.find_child("FrameChartPanel", true, false),
		"the oscilloscope takes the wide middle column")
	assert_not_null(right.find_child("ScorecardPanel", true, false),
		"the scorecard sits with the instruments")

func test_the_desktop_report_fits_a_full_height_window_without_scrolling() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var footer := screen.find_child("Footer", true, false) as Control
	assert_not_null(footer)
	if footer == null:
		return
	var limit := footer.get_global_rect().position.y
	var below: Array = []
	var too_wide: Array = []
	for panel_name in ["RatingPanel", "InstrumentsPanel", "FrameChartPanel", "GpuPanel",
			"EnginePanel", "ScorecardPanel", "HistoryPanel", "DevicePanel"]:
		var panel := screen.find_child(panel_name, true, false) as Control
		if panel == null:
			below.append("%s missing" % panel_name)
			continue
		var rect := panel.get_global_rect()
		if rect.end.y > limit + 1.0:
			below.append("%s ends at %.0f" % [panel_name, rect.end.y])
		if rect.end.x > 1601.0:
			too_wide.append("%s ends at %.0f" % [panel_name, rect.end.x])
	assert_eq(below, [], "every panel stands clear of the action bar")
	assert_eq(too_wide, [], "and inside the window")

func test_phones_fold_the_report_into_one_scrolling_column() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(390, 844))
	var scroll := screen.find_child("PhoneLayout", true, false) as ScrollContainer
	assert_not_null(scroll, "the phone column scrolls")
	var column := screen.find_child("PhoneColumn", true, false) as VBoxContainer
	assert_not_null(column)
	if column == null:
		return
	assert_gt(column.get_child_count(), 5, "every panel is in the one column")
	var widest := 0.0
	for child in column.get_children():
		widest = maxf(widest, (child as Control).get_combined_minimum_size().x)
	assert_lte(widest, 391.0, "and no panel is wider than the phone")

func test_phone_landscape_puts_the_rating_beside_the_charts() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(844, 390))
	assert_not_null(screen.find_child("PhoneLandscapeRow", true, false),
		"the short window reads across rather than down")
	assert_not_null(screen.find_child("RatingPanel", true, false))
	assert_not_null(screen.find_child("FrameChartPanel", true, false))

func test_no_window_shape_leaves_a_panel_out_of_reach() -> void:
	var panels := ["RatingPanel", "InstrumentsPanel", "FrameChartPanel", "GpuPanel",
		"EnginePanel", "ScorecardPanel", "HistoryPanel", "DevicePanel"]
	for entry in SIZES:
		var size: Vector2i = entry[0]
		var screen: BenchmarkResultsScreen = await _screen(size)
		var missing: Array = []
		for panel_name in panels:
			if screen.find_child(panel_name, true, false) == null:
				missing.append(panel_name)
		assert_eq(missing, [], "%s %s reaches every panel" % [size, entry[1]])

func test_tablets_share_the_width_between_the_rating_and_the_instruments() -> void:
	for size in [Vector2i(1024, 768), Vector2i(768, 1024)]:
		var screen: BenchmarkResultsScreen = await _screen(size)
		var top := screen.find_child("TabletTopRow", true, false) as HBoxContainer
		assert_not_null(top, "%s pairs the rating with the meters" % size)
		if top:
			assert_eq(top.get_child_count(), 2)

# ---------------------------------------------------------------------------
# The instruments
# ---------------------------------------------------------------------------

func test_the_frame_chart_draws_every_sampled_frame() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var chart := screen.find_child("FrameChart", true, false) as BenchmarkVisuals.FrameChart
	assert_not_null(chart)
	if chart == null:
		return
	assert_eq(chart.values.size(), 120, "one column per sampled frame")
	assert_almost_eq(chart.average_ms, 16.1, 0.001)
	assert_almost_eq(chart.one_percent_low_fps, 51.0, 0.001)
	assert_gte(chart.ceiling_ms(), 44.0, "the scale clears the worst frame")
	assert_eq(fmod(chart.ceiling_ms(), 10.0), 0.0, "and lands on a round axis label")
	assert_not_null(screen.find_child("ChartLegend", true, false), "the budget lines are explained")
	var stats := _labels_text(screen.find_child("FrameStats", true, false))
	assert_string_contains(stats, "62.0 FPS", "the average is read out")
	assert_string_contains(stats, "51.0 FPS", "so is the one percent low")

func test_the_gpu_ladder_is_charted_and_explained() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var chart := screen.find_child("GpuLadderChart", true, false) as BenchmarkVisuals.BarChart
	assert_not_null(chart)
	if chart == null:
		return
	assert_eq(chart.values.size(), 3, "one bar per overdraw level")
	assert_eq(chart.values[2], 640.0, "the heaviest load is the last bar")
	assert_eq(chart.labels, ["1x", "4x", "10x"])
	var panel := screen.find_child("GpuPanel", true, false)
	var text := _labels_text(panel)
	assert_string_contains(text, "640 MPix/s", "the peak throughput is stamped on the panel")
	assert_string_contains(text, "peak 640 MPix/s at 10x", "and named in the note")
	assert_string_contains(text, "A level hit the frame cap",
		"a capped rung is called out as a floor")

func test_a_skipped_gpu_test_says_why_instead_of_drawing_empty_bars() -> void:
	var report := _report()
	report["gpu"] = {"available": false, "reason": "no renderer in a headless run",
		"levels": [], "peak_megapixels_per_second": 0.0}
	report["score"] = PerformanceBenchmark.score_result(report)
	PerformanceBenchmark.last_result = report
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var chart := screen.find_child("GpuLadderChart", true, false) as BenchmarkVisuals.BarChart
	assert_not_null(chart)
	if chart:
		assert_true(chart.values.is_empty(), "no bars are invented for a test that did not run")
	var text := _labels_text(screen.find_child("GpuPanel", true, false))
	assert_string_contains(text, "Skipped: no renderer in a headless run")

func test_the_instruments_light_a_segmented_meter_per_metric() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	for entry in [["pacing", 56.0], ["consistency", 74.0], ["cpu", 70.0], ["gpu", 81.0]]:
		var key := str(entry[0])
		var row := screen.find_child("Meter_%s" % key, true, false)
		assert_not_null(row, "the %s meter is on the panel" % key)
		if row == null:
			continue
		var meter := row.find_child("Meter", true, false) as BenchmarkVisuals.SegmentMeter
		assert_not_null(meter)
		if meter:
			assert_eq(meter.lit_segments(), int(round(float(entry[1]) / 100.0 * 14.0)),
				"the %s meter is lit to its score" % key)
		assert_string_contains(_labels_text(row), "%d/100" % int(entry[1]))

func test_the_scorecard_grades_every_metric_and_only_reads_out_the_scene() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	for key in ["pacing", "consistency", "cpu", "gpu"]:
		var row := screen.find_child("Row_%s" % key, true, false)
		assert_not_null(row, "the %s row is on the card" % key)
		if row:
			assert_ne(str((row.find_child("Grade", true, false) as Label).text), "—",
				"the %s row is graded" % key)
	var scene := screen.find_child("Row_scene", true, false)
	assert_not_null(scene, "the scene the run measured is listed too")
	if scene:
		assert_eq(str((scene.find_child("Grade", true, false) as Label).text), "—",
			"but it is not the device's fault, so it carries no grade")
		assert_string_contains(_labels_text(scene), "1,880 nodes")
	var total := _labels_text(screen.find_child("ScorecardTotal", true, false))
	assert_string_contains(total, "72 / 100")
	assert_string_contains(total, "Tour")

## A tour record in the shape CourseBenchmarkTour writes.
func _tour_record(record_name: String, holes: int, build_ms: float, sim_fps: float) -> Dictionary:
	return {
		"id": record_name.to_lower(), "name": record_name,
		"description": "Parkland · Generated · %d holes · 8 golfers · Normal 1×" % holes,
		"holes": holes, "holes_built": holes, "speed": 1,
		"build": {"total_ms": build_ms},
		"counts": {"buildings": 2, "decorations": 3, "path_tiles": 100,
			"golfers_spawned": 8, "visiting_spawned": 2, "terrain_patch_tiles": 50},
		"phases": {
			"camera": {"average_fps": sim_fps + 10.0, "sample_count": 50},
			"simulate": {"average_fps": sim_fps, "one_percent_low_fps": sim_fps * 0.8,
				"process_ms_per_frame": 3.0, "days_advanced": 1.0,
				"sample_seconds": 2.0, "sample_count": 50},
			"edit": {"tiles_changed": 120, "vertices_changed": 30,
				"paint_ms": 5.0, "elevation_ms": 5.0},
		},
	}

func _tour_report() -> Dictionary:
	var report := _report()
	var records: Array = [
		_tour_record("Alpha 9", 9, 400.0, 100.0),
		_tour_record("Beta 18", 18, 900.0, 60.0),
	]
	report["tour"] = {"suite": "test", "suite_name": "Test tour",
		"prepare": {"prepared": true, "prepare_ms": 88.0, "steps_ms": {}},
		"scenarios": records,
		"rollup": PerformanceBenchmark.summarize_tour(records),
		"restored": true, "cancelled": false}
	return report

func test_the_tour_panel_lists_every_course_the_tour_built() -> void:
	PerformanceBenchmark.last_result = _tour_report()
	for entry in SIZES:
		var size: Vector2i = entry[0]
		var label: String = entry[1]
		var screen: BenchmarkResultsScreen = await _screen(size)
		var panel := screen.find_child("TourPanel", true, false)
		assert_not_null(panel, "%s: a tour report gets its tour panel" % label)
		if panel == null:
			continue
		assert_not_null(screen.find_child("TourScenarioChart", true, false),
			"%s: the per-course frame rates are charted" % label)
		assert_not_null(screen.find_child("TourRow_0", true, false),
			"%s: the first toured course has a row" % label)
		assert_not_null(screen.find_child("TourRow_1", true, false),
			"%s: and the second" % label)
		var text := _labels_text(panel)
		assert_string_contains(text, "Alpha 9", "%s: rows name the courses" % label)
		assert_string_contains(text, "Beta 18", "%s: every one of them" % label)
		assert_string_contains(text, "build 900 ms", "%s: build times are readable" % label)
		assert_string_contains(text, "Benchmark course prepared in 88 ms",
			"%s: preparing the course is reported as part of the run" % label)
		assert_string_contains(text, "Generation by size", "%s: the rollups follow" % label)
		assert_string_contains(text, "Main menu restored: yes",
			"%s: the return to the title screen is confirmed" % label)

func test_a_report_with_no_tour_behind_it_shows_no_tour_panel() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	assert_null(screen.find_child("TourPanel", true, false),
		"the plain GTB-2 fixture has no tour to show")
	var run := screen.find_child("RunBenchmarkButton", true, false) as Button
	assert_not_null(run, "the run button is on the bar")
	if run:
		assert_eq(run.text, "Run Benchmark", "and it runs the one benchmark there is")
		assert_true(run.disabled,
			"but it stands down here: the screen was not opened from the Main Menu")

func test_run_benchmark_asks_for_the_full_tour() -> void:
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	var screen := BenchmarkResultsScreen.new()
	screen.tour_available = true
	add_child_autofree(screen)
	await process_frames(2)
	var run := screen.find_child("RunBenchmarkButton", true, false) as Button
	assert_not_null(run, "the run button is on the bar")
	if run == null:
		return
	assert_eq(run.text, "Run Benchmark", "the headline run is the course tour")
	assert_false(run.disabled, "and it can be pressed from the Main Menu")
	assert_not_null(screen.find_child("TourPanel", true, false),
		"the panel invites a tour even before one is in the report")
	var requested: Array = []
	screen.tour_requested.connect(func(suite_id: String) -> void: requested.append(suite_id))
	run.pressed.emit()
	assert_eq(requested, [CourseBenchmarkScenarios.SUITE_FULL],
		"and it asks for the full tour - the only one there is")
	assert_string_contains(screen._status_text, "Starting the course tour",
		"the screen says what it is doing")

func test_away_from_the_main_menu_the_screen_runs_nothing() -> void:
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	var screen := BenchmarkResultsScreen.new()
	screen.benchmarks_allowed = false
	screen.tour_available = true
	add_child_autofree(screen)
	await process_frames(2)
	var run := screen.find_child("RunBenchmarkButton", true, false) as Button
	var copy := screen.find_child("CopyReportButton", true, false) as Button
	assert_not_null(run, "the run button is still shown")
	assert_true(run.disabled, "but it cannot be pressed away from the Main Menu")
	var requested: Array = []
	screen.tour_requested.connect(func(suite_id: String) -> void: requested.append(suite_id))
	run.pressed.emit()
	await process_frames(2)
	assert_eq(requested, [], "no tour is requested")
	assert_not_null(copy, "reading the report is not running a benchmark")
	if copy:
		assert_false(copy.disabled, "so copying still works here")
	assert_string_contains(screen._status_text, "Main Menu",
		"the screen says where benchmarks do run")

func test_the_rating_shows_the_stars_the_tier_and_the_change() -> void:
	BenchmarkHistory.append_run(_report())
	var older := _report()
	older["started_at_unix"] = 1_759_900_000
	older["score"]["overall"] = 60.0
	BenchmarkHistory.append_run(older)
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var stars := screen.find_child("RatingStarRow", true, false) as BenchmarkVisuals.StarRow
	assert_not_null(stars)
	if stars:
		assert_eq(stars.stars, 4, "the run's stars are drawn")
	var panel := screen.find_child("RatingPanel", true, false)
	var text := _labels_text(panel)
	assert_string_contains(text, "Tour", "the tier names the rating")
	assert_string_contains(text, "72 / 100 overall score")
	assert_string_contains(text, "Course view", "the scene the run measured")
	assert_not_null(screen.find_child("DeltaChip", true, false),
		"and what changed against the run before it")

func test_the_device_dossier_carries_the_hardware_behind_the_numbers() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var text := _labels_text(screen.find_child("DevicePanel", true, false))
	assert_string_contains(text, "Test CPU (8 cores)")
	assert_string_contains(text, "Test GPU (Test vendor)")
	assert_string_contains(text, "1600 x 1000")
	assert_string_contains(text, "GTB-2")
	assert_string_contains(text, "nothing is uploaded", "and the privacy line stays with it")

# ---------------------------------------------------------------------------
# The shelf of past runs
# ---------------------------------------------------------------------------

func test_the_shelf_charts_past_runs_and_compares_them() -> void:
	for index in range(4):
		var run := _report()
		run["started_at_unix"] = 1_759_000_000 + index * 100_000
		run["score"]["overall"] = 50.0 + float(index) * 10.0
		BenchmarkHistory.append_run(run)
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var chart := screen.find_child("HistoryChart", true, false) as BenchmarkVisuals.BarChart
	assert_not_null(chart)
	if chart:
		assert_eq(chart.values.size(), 4, "one bar per run on the shelf")
		assert_eq(chart.values[3], 80.0, "the newest run is the last bar")
	for index in range(4):
		assert_not_null(screen.find_child("Run_%d" % index, true, false),
			"run %d is listed" % index)
	assert_null(screen.find_child("Run_5", true, false),
		"and the list stops at the screen's five rows")
	assert_not_null(screen.find_child("MetricSwitch", true, false),
		"the desktop layout offers the metric switch")

func test_the_metric_switch_redraws_the_shelf_chart() -> void:
	for index in range(3):
		var run := _report()
		run["started_at_unix"] = 1_759_000_000 + index * 100_000
		run["frame"]["average_fps"] = 40.0 + float(index) * 10.0
		BenchmarkHistory.append_run(run)
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var fps_button := screen.find_child("Metric_average_fps", true, false) as Button
	assert_not_null(fps_button)
	if fps_button:
		fps_button.pressed.emit()
	await process_frames(2)
	var chart := screen.find_child("HistoryChart", true, false) as BenchmarkVisuals.BarChart
	assert_not_null(chart, "the chart is rebuilt")
	if chart:
		assert_eq(chart.values, [40.0, 50.0, 60.0], "and now plots the frame rate")

func test_an_empty_shelf_says_so_and_can_be_refilled() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var text := _labels_text(screen.find_child("HistoryPanel", true, false))
	assert_string_contains(text, "Finished runs are kept here")
	assert_null(screen.find_child("Run_0", true, false))

func test_clearing_the_shelf_empties_it() -> void:
	BenchmarkHistory.append_run(_report())
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var clear := screen.find_child("ClearHistoryButton", true, false) as Button
	assert_not_null(clear)
	if clear:
		clear.pressed.emit()
	await process_frames(2)
	assert_eq(BenchmarkHistory.load_runs(), [], "the shelf is empty on disk")
	assert_null(screen.find_child("Run_0", true, false), "and on screen")

# ---------------------------------------------------------------------------
# Opening a past run
# ---------------------------------------------------------------------------

## Two runs with the same shape but different numbers, the older one first.
func _shelf_of_two() -> void:
	var older := _report()
	older["started_at_unix"] = 1_759_000_000
	older["score"]["overall"] = 41.0
	older["score"]["stars"] = 2
	older["score"]["tier"] = "Municipal"
	older["score"]["verdict"] = "Municipal pace. Playable, with the odd stumble."
	older["frame"]["average_fps"] = 31.0
	older["frame"]["average_frame_ms"] = 32.3
	older["frame"]["series_ms"] = [30.0, 32.0, 34.0]
	older["device_model"] = "Old tablet"
	older["report_text"] = "Golf Tycoon benchmark GTB-2\\nThe older run"
	BenchmarkHistory.append_run(older)
	BenchmarkHistory.append_run(_report())

func test_clicking_a_past_run_shows_that_runs_report() -> void:
	_shelf_of_two()
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var older_row := screen.find_child("Run_0", true, false) as Button
	assert_not_null(older_row, "the older run has its row")
	if older_row == null:
		return
	older_row.pressed.emit()
	await process_frames(3)
	var rating := _labels_text(screen.find_child("RatingPanel", true, false))
	assert_string_contains(rating, "Municipal", "the rating is the past run's tier")
	assert_string_contains(rating, "41 / 100 overall score", "and its score")
	assert_not_null(screen.find_child("PastRunChip", true, false),
		"and the screen says this is a past run, not the current one")
	var chart := screen.find_child("FrameChart", true, false) as BenchmarkVisuals.FrameChart
	assert_not_null(chart)
	if chart:
		assert_eq(chart.values.size(), 3, "the oscilloscope draws that run's frames")
		assert_almost_eq(chart.average_ms, 32.3, 0.001, "at that run's pace")
	var dossier := _labels_text(screen.find_child("DevicePanel", true, false))
	assert_string_contains(dossier, "Old tablet", "and the machine it ran on")
	var shown := screen.find_child("Run_0", true, false) as Button
	assert_true(shown.button_pressed, "the picked row stays lit")

func test_copying_a_past_run_copies_that_runs_report() -> void:
	_shelf_of_two()
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var older_row := screen.find_child("Run_0", true, false) as Button
	if older_row == null:
		return
	older_row.pressed.emit()
	await process_frames(3)
	var copied: Array = []
	screen.clipboard_writer = func(text: String): copied.append(text)
	var copy := screen.find_child("CopyReportButton", true, false) as Button
	assert_not_null(copy)
	if copy == null:
		return
	copy.pressed.emit()
	assert_eq(copied.size(), 1, "the report on screen is handed to the clipboard")
	assert_string_contains(str(copied[0]), "The older run",
		"and it is the past run's report, not the newest one")

func test_the_newest_run_can_be_picked_again() -> void:
	_shelf_of_two()
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var older_row := screen.find_child("Run_0", true, false) as Button
	var newest_row := screen.find_child("Run_1", true, false) as Button
	if older_row == null or newest_row == null:
		return
	older_row.pressed.emit()
	await process_frames(3)
	newest_row = screen.find_child("Run_1", true, false) as Button
	newest_row.pressed.emit()
	await process_frames(3)
	var rating := _labels_text(screen.find_child("RatingPanel", true, false))
	assert_string_contains(rating, "Tour", "the newest run is back on screen")
	assert_string_contains(rating, "72 / 100 overall score")
	assert_null(screen.find_child("PastRunChip", true, false),
		"and it is no longer flagged as a past run")

func test_a_run_without_a_kept_report_says_so_instead_of_emptying_the_screen() -> void:
	BenchmarkHistory.append_run(_report())
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var runs := BenchmarkHistory.load_runs()
	runs[0].erase("report")
	BenchmarkHistory.save_runs(runs)
	screen.refresh()
	await process_frames(3)
	var row := screen.find_child("Run_0", true, false) as Button
	assert_not_null(row)
	if row == null:
		return
	row.pressed.emit()
	await process_frames(3)
	assert_string_contains(screen._status_text, "before past reports were kept",
		"the screen says why that run cannot be opened")
	var rating := _labels_text(screen.find_child("RatingPanel", true, false))
	assert_string_contains(rating, "72 / 100 overall score",
		"and keeps showing the run it was already on")

func test_clearing_the_shelf_drops_the_run_being_read() -> void:
	_shelf_of_two()
	PerformanceBenchmark.last_result = {}
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	assert_string_contains(_labels_text(screen.find_child("RatingPanel", true, false)),
		"Tour", "opened cold, the newest run on the shelf is on screen")
	var older_row := screen.find_child("Run_0", true, false) as Button
	if older_row:
		older_row.pressed.emit()
		await process_frames(3)
		assert_string_contains(_labels_text(screen.find_child("RatingPanel", true, false)),
			"Municipal", "and picking the older one shows it")
	var clear := screen.find_child("ClearHistoryButton", true, false) as Button
	assert_not_null(clear)
	if clear == null:
		return
	clear.pressed.emit()
	await process_frames(3)
	assert_null(screen.find_child("Run_0", true, false), "the shelf is empty")
	assert_string_contains(_labels_text(screen.find_child("RatingPanel", true, false)),
		"Unrated", "and the screen is back to a report it has not measured")

func test_a_real_mouse_click_anywhere_on_a_row_opens_that_run() -> void:
	_shelf_of_two()
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var row := screen.find_child("Run_0", true, false) as Button
	assert_not_null(row)
	if row == null:
		return
	# The row carries stars, labels and numbers: a click on any of them has
	# to reach the row, not be swallowed by the child underneath it.
	var centre := (row as Button).get_global_rect().get_center()
	var pressed := InputEventMouseButton.new()
	pressed.position = centre
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventMouseButton.new()
	released.position = centre
	released.button_index = MOUSE_BUTTON_LEFT
	released.pressed = false
	Input.parse_input_event(released)
	await process_frames(3)
	assert_string_contains(_labels_text(screen.find_child("RatingPanel", true, false)),
		"Municipal", "the click opened that run")

func test_every_run_row_opens_the_run_it_stands_for() -> void:
	for index in range(3):
		var run := _report()
		run["started_at_unix"] = 1_759_000_000 + index * 100_000
		run["score"]["overall"] = 40.0 + float(index) * 20.0
		run["score"]["stars"] = index + 1
		BenchmarkHistory.append_run(run)
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	for index in range(3):
		var row := screen.find_child("Run_%d" % index, true, false) as Button
		assert_not_null(row, "run %d has a row" % index)
		if row == null:
			return
		row.pressed.emit()
		await process_frames(3)
		assert_string_contains(_labels_text(screen.find_child("RatingPanel", true, false)),
			"%d / 100 overall score" % int(40 + index * 20),
			"row %d opens the run it stands for" % index)

## Each row is measured against the run before it in time, not against
## itself, so the oldest row has nothing to compare to.
func test_each_row_is_compared_against_the_run_before_it() -> void:
	for index in range(3):
		var run := _report()
		run["started_at_unix"] = 1_759_000_000 + index * 100_000
		run["score"]["overall"] = 40.0 + float(index) * 20.0
		BenchmarkHistory.append_run(run)
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	assert_string_contains(_labels_text(screen.find_child("Run_0", true, false)), "\u2014",
		"the oldest row compares against nothing")
	assert_string_contains(_labels_text(screen.find_child("Run_1", true, false)), "+50%",
		"the middle row is measured against the oldest run")
	assert_string_contains(_labels_text(screen.find_child("Run_2", true, false)), "+33%",
		"the newest row is measured against the middle run")

# ---------------------------------------------------------------------------
# Running a test from the screen
# ---------------------------------------------------------------------------

func test_run_benchmark_hands_the_screen_over_to_the_tour() -> void:
	PerformanceBenchmark.last_result = {}
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	screen.tour_available = true
	await process_frames(2)
	var run := screen.find_child("RunBenchmarkButton", true, false) as Button
	assert_not_null(run)
	if run == null:
		return
	var requested: Array = []
	screen.tour_requested.connect(func(suite_id: String) -> void: requested.append(suite_id))
	run.pressed.emit()
	await process_frames(2)
	assert_eq(requested, [CourseBenchmarkScenarios.SUITE_FULL],
		"the screen runs nothing itself - Main owns the tour")
	assert_string_contains(_labels_text(screen.find_child("StatusLine", true, false)),
		"Starting the course tour", "and the status line says where the run went")

func test_the_report_goes_to_the_clipboard_and_nowhere_else() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var copy := screen.find_child("CopyReportButton", true, false) as Button
	assert_not_null(copy)
	if copy == null:
		return
	assert_false(copy.disabled, "a finished report can be copied")
	var copied: Array = []
	screen.clipboard_writer = func(text: String): copied.append(text)
	copy.pressed.emit()
	assert_eq(copied.size(), 1, "the report is handed to the clipboard")
	assert_string_contains(str(copied[0]), "Golf Tycoon benchmark GTB-2")
	assert_string_contains(_labels_text(screen.find_child("StatusLine", true, false)),
		"nothing was uploaded")

func test_a_window_with_no_clipboard_says_so_rather_than_failing_silently() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	var copy := screen.find_child("CopyReportButton", true, false) as Button
	if copy == null:
		return
	copy.pressed.emit()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		assert_string_contains(DisplayServer.clipboard_get(), "Golf Tycoon benchmark GTB-2",
			"a real clipboard receives the report")
	else:
		assert_string_contains(_labels_text(screen.find_child("StatusLine", true, false)),
			"no clipboard", "and a window without one is told")

func test_back_asks_the_host_to_close_the_screen() -> void:
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(1600, 1000))
	watch_signals(screen)
	var back := screen.find_child("BackButton", true, false) as Button
	assert_not_null(back)
	if back:
		back.pressed.emit()
	assert_signal_emitted(screen, "back_requested")

# ---------------------------------------------------------------------------
# Every window shape stays usable
# ---------------------------------------------------------------------------

func test_every_action_is_touch_sized_and_inside_the_window() -> void:
	for entry in SIZES:
		var size: Vector2i = entry[0]
		var tag := "%s %s" % [size, entry[1]]
		var screen: BenchmarkResultsScreen = await _screen(size)
		var view := Rect2(Vector2.ZERO, Vector2(size))
		var too_small: Array = []
		var outside: Array = []
		for button in _visible_buttons(screen):
			var control := button as Button
			var rect := control.get_global_rect()
			if rect.size.y < MIN_TARGET - 0.5 or rect.size.x < MIN_TARGET - 0.5:
				too_small.append("%s %s" % [control.text, rect.size])
			var inside := rect.position.x >= -1.0 and rect.end.x <= view.end.x + 1.0 \
				if _inside_scroll(control) else GameTest.rect_within(rect, view)
			if not inside:
				outside.append("%s %s" % [control.text, rect])
		assert_eq(too_small, [], "%s: every action is at least %d px" % [tag, MIN_TARGET])
		assert_eq(outside, [], "%s: every action is inside the window" % tag)
		assert_not_null(screen.find_child("RunBenchmarkButton", true, false),
			"%s: the run action is always on screen" % tag)

func test_the_screen_survives_a_window_that_starts_with_nothing_to_show() -> void:
	PerformanceBenchmark.last_result = {}
	var screen: BenchmarkResultsScreen = await _screen(Vector2i(390, 844))
	assert_not_null(screen.find_child("FrameChart", true, false),
		"an empty report still lays out, with the chart waiting for a run")
	var rating := _labels_text(screen.find_child("RatingPanel", true, false))
	assert_string_contains(rating, "Unrated")
	assert_string_contains(rating, "0 / 100 overall score")
