extends GameTest
## The local device benchmark reports reproducible frame statistics and a
## versioned script-workload score, measures the GPU with a fill-rate ladder,
## grades the whole run as a five-star device scorecard, and formats a
## device-to-device report.

const HISTORY_PATH := "user://test_performance_benchmark_history.json"

var _old_history_path := ""

func before_each() -> void:
	super()
	_old_history_path = BenchmarkHistory.history_path
	BenchmarkHistory.history_path = HISTORY_PATH
	BenchmarkHistory.clear()

func after_each() -> void:
	PerformanceBenchmark.last_result = {}
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = _old_history_path
	super()

## A result shaped like a finished run, for the pure functions.
func _report(cpu_units: float, fps: float, one_percent_low: float, megapixels: float,
		gpu_available: bool = true, frames_over_33: int = 0, samples: int = 150) -> Dictionary:
	return {
		"benchmark_version": "GTB-2",
		"game_version": "0.5.2",
		"engine_version": "4.6.stable",
		"build_type": "Release",
		"device_model": "Test device",
		"platform": "Test OS",
		"os_version": "Test OS version",
		"cpu_name": "Test CPU",
		"cpu_cores": 8,
		"gpu_name": "Test GPU",
		"renderer": "forward_plus / vulkan",
		"display_server": "Test display",
		"resolution": "1600 x 1000",
		"vsync": "On",
		"max_fps": 0,
		"frame_sample_seconds": 2.5,
		"gpu_sample_seconds": 2.1,
		"context": {"scenario": "Course view", "day": 7},
		"frame": {
			"sample_count": samples,
			"average_fps": fps,
			"average_frame_ms": 1000.0 / fps,
			"one_percent_low_fps": one_percent_low,
			"p95_frame_ms": 18.2,
			"worst_frame_ms": 41.0,
			"best_frame_ms": 8.0,
			"frames_over_33_ms": frames_over_33,
			"series_ms": [16.0, 17.0, 40.0],
		},
		"cpu": {"units_per_second": cpu_units, "work_units": 120000},
		"gpu": {
			"available": gpu_available,
			"reason": "" if gpu_available else "no renderer in a headless run",
			"peak_megapixels_per_second": megapixels,
			"peak_overdraw": 10.0,
			"gpu_ms_per_frame": 4.5,
			"levels": [],
		},
		"engine": {
			"process_ms_per_frame": 4.1,
			"physics_ms_per_frame": 0.6,
			"render_objects": 220,
			"render_primitives": 3100,
			"draw_calls": 48,
			"node_count": 1900,
		},
		"memory": {"static_mb": 120.0, "video_mb": 64.0, "texture_mb": 40.0},
	}

# ---------------------------------------------------------------------------
# The CPU workload and the frame summary
# ---------------------------------------------------------------------------

func test_cpu_work_units_are_deterministic() -> void:
	var first := PerformanceBenchmark.work_unit_checksum(42)
	var second := PerformanceBenchmark.work_unit_checksum(42)
	var next := PerformanceBenchmark.work_unit_checksum(43)
	assert_almost_eq(first, second, 0.000001, "the same input always produces the same work")
	assert_ne(first, next, "different inputs exercise different work")

func test_frame_summary_reports_average_one_percent_low_and_stutters() -> void:
	var samples: Array[float] = [10.0, 20.0, 50.0, 100.0]
	var summary := PerformanceBenchmark.summarize_frame_times(samples)
	assert_eq(summary["sample_count"], 4)
	assert_almost_eq(summary["average_fps"], 1000.0 / 45.0, 0.001)
	assert_almost_eq(summary["one_percent_low_fps"], 10.0, 0.001,
		"the slowest frame is the one-percent-low sample in a tiny test")
	assert_almost_eq(summary["p95_frame_ms"], 100.0, 0.001)
	assert_eq(summary["frames_over_33_ms"], 2)

func test_empty_frame_summary_is_safe_to_display() -> void:
	var summary := PerformanceBenchmark.summarize_frame_times([])
	assert_eq(summary["sample_count"], 0)
	assert_eq(summary["average_fps"], 0.0)
	assert_eq(summary["one_percent_low_fps"], 0.0)
	assert_eq(summary["frames_over_33_ms"], 0)

func test_a_long_series_is_bucketed_down_for_the_graph() -> void:
	var samples: Array[float] = []
	for i in range(600):
		samples.append(float(i % 30) + 1.0)
	var series := PerformanceBenchmark.downsample_series(samples, 60)
	assert_eq(series.size(), 60, "the series is bucketed to the chart's budget")
	assert_almost_eq(series[0], 5.5, 0.001, "each ten-frame bucket is the mean of its frames")
	var untouched := PerformanceBenchmark.downsample_series(samples, 900)
	assert_eq(untouched.size(), 600, "a series that already fits is left alone")

# ---------------------------------------------------------------------------
# The GPU fill test
# ---------------------------------------------------------------------------

func test_gpu_step_turns_frame_times_into_throughput() -> void:
	var frames: Array[float] = [30.0, 30.0, 30.0, 30.0]
	var process: Array[float] = [4.0, 4.0, 4.0, 4.0]
	var step := PerformanceBenchmark.gpu_step_result(10.0, 12_000_000, 256, frames, process, 60.0)
	assert_eq(step["frames"], 4)
	assert_almost_eq(step["fps"], 1000.0 / 30.0, 0.001)
	assert_almost_eq(step["megapixels_per_second"], 12_000_000.0 * step["fps"] / 1_000_000.0, 0.01,
		"throughput is the fill per frame times the frame rate")
	assert_almost_eq(step["gpu_ms"], 26.0, 0.001, "the render share is the frame minus the script")
	assert_false(step["capped"], "a frame rate well under the cap is not capped")

func test_a_gpu_step_at_the_frame_cap_is_flagged_as_a_floor() -> void:
	var frames: Array[float] = [16.7, 16.7, 16.7]
	var process: Array[float] = [1.0, 1.0, 1.0]
	var step := PerformanceBenchmark.gpu_step_result(1.0, 2_000_000, 256, frames, process, 60.0)
	assert_true(step["capped"], "a level that hits the display refresh is limited by the cap")
	var empty := PerformanceBenchmark.gpu_step_result(1.0, 2_000_000, 256, [], [], 60.0)
	assert_eq(empty["frames"], 0, "a level with no frames reports none rather than a fake rate")
	assert_eq(empty["megapixels_per_second"], 0.0)

func test_the_gpu_summary_peaks_at_the_fastest_rung_of_the_ladder() -> void:
	var ladder: Array = [
		{"overdraw": 1.0, "megapixels_per_second": 180.0, "frames": 20, "gpu_ms": 2.0},
		{"overdraw": 4.0, "megapixels_per_second": 640.0, "frames": 20, "gpu_ms": 6.0},
		{"overdraw": 10.0, "megapixels_per_second": 910.0, "frames": 20, "gpu_ms": 9.5},
	]
	var summary := PerformanceBenchmark.summarize_gpu(ladder, true, "", 2.1)
	assert_almost_eq(summary["peak_megapixels_per_second"], 910.0, 0.001)
	assert_eq(summary["peak_overdraw"], 10.0, "the peak names the load it was reached at")
	assert_eq(summary["levels"].size(), 3, "the ladder itself is kept for the chart")
	assert_eq(summary["gpu_ms_per_frame"], 9.5)

func test_a_skipped_gpu_test_says_why_instead_of_reporting_zeros() -> void:
	var summary := PerformanceBenchmark.summarize_gpu([], false,
		"no renderer in a headless run", 2.1)
	assert_false(summary["available"])
	assert_eq(summary["reason"], "no renderer in a headless run")
	assert_eq(summary["peak_megapixels_per_second"], 0.0)

func test_the_gpu_test_is_not_claimed_in_a_headless_run() -> void:
	assert_false(PerformanceBenchmark.gpu_test_available(),
		"the headless server has no renderer to fill")
	assert_ne(PerformanceBenchmark.gpu_skip_reason(), "", "and says so")

func test_the_stress_canvas_sizes_its_fill_from_the_window() -> void:
	var side := PerformanceBenchmark.GpuStressCanvas.tile_side_for(Vector2(1600, 1000))
	assert_eq(side, 250, "a quarter of the shorter edge")
	assert_eq(PerformanceBenchmark.GpuStressCanvas.tile_side_for(Vector2(390, 844)), 97,
		"a phone's tiles stay chunky rather than tiny")
	var canvas: PerformanceBenchmark.GpuStressCanvas = \
		autofree(PerformanceBenchmark.GpuStressCanvas.new(256))
	canvas.fill_size = Vector2(1600, 1000)
	canvas.set_load(4.0)
	assert_eq(canvas.quad_count(), 98, "four windows' worth of pixels over 256px tiles")
	assert_eq(canvas.total_fill_pixels(), 98 * 256 * 256)
	var weave := PerformanceBenchmark.GpuStressCanvas.weave_image()
	assert_eq(weave.get_width(), PerformanceBenchmark.GPU_TEXTURE_GRID)
	assert_eq(weave.get_pixel(0, 0).a, 1.0, "the weave is opaque, so the fill cost is fixed")

# ---------------------------------------------------------------------------
# The scorecard
# ---------------------------------------------------------------------------

func test_metrics_are_normalised_on_a_log_scale() -> void:
	assert_eq(PerformanceBenchmark.normalize_log(100.0, 100.0, 10000.0), 0.0)
	assert_eq(PerformanceBenchmark.normalize_log(10000.0, 100.0, 10000.0), 1.0)
	assert_almost_eq(PerformanceBenchmark.normalize_log(1000.0, 100.0, 10000.0), 0.5, 0.0001,
		"the geometric midpoint is half way up the scale")
	assert_eq(PerformanceBenchmark.normalize_log(50.0, 100.0, 10000.0), 0.0, "below the floor is zero")

func test_a_balanced_run_grades_as_par_and_a_strong_one_as_eagle() -> void:
	var even := PerformanceBenchmark.consistency_score(60.0, 60.0, 0.0)
	assert_almost_eq(even, 100.0, 0.001, "a run that never misses a frame is perfectly even")
	var ragged := PerformanceBenchmark.consistency_score(60.0, 20.0, 0.05)
	assert_lt(ragged, 20.0, "a run with deep lows and stutters is not")
	assert_eq(PerformanceBenchmark.consistency_score(0.0, 0.0, 0.0), 0.0, "no frames, no grade")

func test_the_overall_rating_grades_a_device_in_stars_and_tiers() -> void:
	var strong := PerformanceBenchmark.score_result(_report(2_400_000.0, 140.0, 130.0, 1_100.0))
	assert_eq(strong["stars"], 5)
	assert_eq(strong["tier"], "Championship")
	assert_true(strong["gpu_measured"], "a measured GPU is part of the rating")
	assert_gt(float(strong["overall"]), 85.0)

	var modest := PerformanceBenchmark.score_result(_report(400_000.0, 45.0, 26.0, 150.0))
	assert_lt(int(modest["stars"]), int(strong["stars"]), "a slower device earns fewer stars")
	assert_lt(float(modest["overall"]), float(strong["overall"]))
	assert_eq(PerformanceBenchmark.tier_name(0), "Unrated")
	assert_eq(PerformanceBenchmark.tier_name(2), "Municipal")

func test_a_run_without_a_gpu_is_rated_on_what_it_measured() -> void:
	var without_gpu := PerformanceBenchmark.score_result(
		_report(2_400_000.0, 140.0, 130.0, 0.0, false))
	var with_gpu := PerformanceBenchmark.score_result(_report(2_400_000.0, 140.0, 130.0, 1_100.0))
	assert_false(without_gpu["gpu_measured"])
	assert_gt(float(without_gpu["overall"]), 0.0, "the rating is still made")
	assert_almost_eq(float(without_gpu["overall"]), float(with_gpu["overall"]), 12.0,
		"and stays in the same neighbourhood as the same machine with a GPU result")

func test_an_empty_report_is_unrated_rather_than_a_false_zero_score() -> void:
	var nothing := PerformanceBenchmark.score_result({})
	assert_eq(nothing["stars"], 0)
	assert_eq(nothing["tier"], "Unrated")
	assert_false(nothing["measured"])

func test_scores_read_as_golf_grades() -> void:
	assert_eq(PerformanceBenchmark.grade_for(90.0), "Eagle")
	assert_eq(PerformanceBenchmark.grade_for(75.0), "Birdie")
	assert_eq(PerformanceBenchmark.grade_for(60.0), "Par")
	assert_eq(PerformanceBenchmark.grade_for(40.0), "Bogey")
	assert_eq(PerformanceBenchmark.grade_for(10.0), "Double")

func test_the_scorecard_grades_the_machine_and_only_reads_out_the_scene() -> void:
	var rows := PerformanceBenchmark.scorecard_rows(_report(1_000_000.0, 60.0, 48.0, 500.0))
	assert_eq(rows.size(), 5, "four graded metrics and the scene the run measured")
	var keys: Array = []
	for row in rows:
		keys.append(str((row as Dictionary)["key"]))
	assert_eq(keys, ["pacing", "consistency", "cpu", "gpu", "scene"])
	var scene: Dictionary = rows[4]
	assert_false(scene["graded"], "the scene load is not the device's fault")
	assert_string_contains(str(scene["value"]), "1,900 nodes")

func test_the_scorecard_marks_an_unmeasured_gpu_rather_than_grading_it_zero() -> void:
	var rows := PerformanceBenchmark.scorecard_rows(_report(1_000_000.0, 60.0, 48.0, 0.0, false))
	var gpu: Dictionary = rows[3]
	assert_false(gpu["graded"])
	assert_eq(str(gpu["value"]), "Not measured")
	assert_string_contains(str(gpu["detail"]), "headless")

# ---------------------------------------------------------------------------
# The report
# ---------------------------------------------------------------------------

func test_report_is_versioned_and_contains_comparable_diagnostics() -> void:
	var report := _report(12_345.0, 60.0, 48.0, 640.0)
	report["gpu"]["levels"] = [
		{"overdraw": 1.0, "megapixels_per_second": 180.0, "fps": 60.0, "capped": true},
		{"overdraw": 4.0, "megapixels_per_second": 640.0, "fps": 58.0, "capped": false},
	]
	report["score"] = PerformanceBenchmark.score_result(report)
	var text := PerformanceBenchmark.format_report(report)
	assert_string_contains(text, "GTB-2", "same-version reports can be compared")
	assert_string_contains(text, "Test CPU", "the device hardware is identified")
	assert_string_contains(text, "1% low 48.0 FPS", "frame pacing includes a low-frame metric")
	assert_string_contains(text, "12,345 work units/s", "CPU throughput is human-readable")
	assert_string_contains(text, "same course/save", "the report explains how to compare fairly")
	assert_string_contains(PerformanceBenchmark.format_summary(report), "60.0 FPS")

func test_the_report_carries_the_gpu_ladder_the_scorecard_and_the_memory() -> void:
	var report := _report(1_000_000.0, 60.0, 48.0, 640.0)
	report["gpu"]["levels"] = [
		{"overdraw": 1.0, "megapixels_per_second": 180.0, "fps": 60.0, "capped": true},
		{"overdraw": 10.0, "megapixels_per_second": 640.0, "fps": 26.0, "capped": false},
	]
	report["score"] = PerformanceBenchmark.score_result(report)
	var text := PerformanceBenchmark.format_report(report)
	assert_string_contains(text, "GPU fill test: 640 MPix/s peak at 10x overdraw")
	assert_string_contains(text, "GPU load ladder")
	assert_string_contains(text, "1x: 180 MPix/s @ 60 FPS (capped)", "a capped rung is marked")
	assert_string_contains(text, "Memory: 120 MB static")
	assert_string_contains(text, "Device rating: 4/5 stars")
	assert_string_contains(text, "Script CPU", "the scorecard prints its rows")
	assert_string_contains(text, "Birdie", "and each row's golf grade")

func test_a_report_without_a_gpu_says_the_test_was_skipped() -> void:
	var report := _report(1_000_000.0, 60.0, 48.0, 0.0, false)
	report["score"] = PerformanceBenchmark.score_result(report)
	var text := PerformanceBenchmark.format_report(report)
	assert_string_contains(text, "GPU fill test: skipped")
	assert_string_contains(text, "GPU fill")
	assert_string_contains(text, "Not measured")

func test_integer_scores_use_thousands_separators() -> void:
	assert_eq(PerformanceBenchmark.format_integer(9876543), "9,876,543")
	assert_eq(PerformanceBenchmark.format_integer(-12345), "-12,345")

# ---------------------------------------------------------------------------
# A run, end to end
# ---------------------------------------------------------------------------

func test_a_run_walks_every_phase_and_reports_a_scored_result() -> void:
	var runner := PerformanceBenchmark.new()
	runner.name = "BenchmarkRunner"
	runner.warmup_duration_usec = 0
	runner.frame_sample_duration_usec = 12_000
	runner.gpu_step_duration_usec = 5_000
	runner.cpu_sample_duration_usec = 12_000
	runner.record_history = false
	add_child_autofree(runner)
	var finished: Array = []
	runner.completed.connect(func(report: Dictionary): finished.append(report))
	var progress: Array = []
	runner.progress_changed.connect(func(message: String, fraction: float):
		progress.append([message, fraction]))

	assert_true(runner.start({"scenario": "Course view"}), "a run starts")
	assert_false(runner.start({}), "and a second one is refused while it runs")
	assert_true(runner.is_running())
	var done := await process_frames_until(func(): return not finished.is_empty(), 400)
	assert_true(done, "the run finishes")
	assert_false(runner.is_running(), "and leaves the runner idle")
	assert_false(progress.is_empty(), "progress was reported as it went")

	var result: Dictionary = finished[0]
	assert_gt(int(result["frame"]["sample_count"]), 0, "frames were sampled")
	assert_true(result["frame"].has("series_ms"), "the samples are kept for the graph")
	assert_gt(float(result["cpu"]["units_per_second"]), 0.0, "the CPU workload was timed")
	assert_true(result.has("memory"), "the run reports its memory footprint")
	assert_true(result.has("score"), "and its own scorecard")
	assert_false(result["report_text"].is_empty(), "with the text report attached")
	assert_eq(result, PerformanceBenchmark.last_result, "the newest run is kept for other screens")
	assert_true(BenchmarkHistory.load_runs().is_empty(),
		"a run that opts out leaves the shelf alone")

func test_a_run_can_be_cancelled_mid_flight() -> void:
	var runner := PerformanceBenchmark.new()
	runner.name = "BenchmarkRunner"
	runner.frame_sample_duration_usec = 5_000_000
	runner.record_history = false
	add_child_autofree(runner)
	assert_true(runner.start({}))
	await process_frames(2)
	runner.cancel()
	assert_false(runner.is_running(), "cancelling stops the state machine")
