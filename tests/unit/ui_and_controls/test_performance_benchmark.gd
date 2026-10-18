extends GameTest
## The local device benchmark reports reproducible frame statistics and a
## versioned script-workload score, and formats a device-to-device report.

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

func test_report_is_versioned_and_contains_comparable_diagnostics() -> void:
	var report := {
		"benchmark_version": "GTB-1",
		"game_version": "0.4.3",
		"engine_version": "4.6.stable",
		"build_type": "Release",
		"device_model": "Test device",
		"platform": "Test OS",
		"os_version": "Test OS version",
		"cpu_name": "Test CPU",
		"cpu_cores": 8,
		"gpu": "Test GPU",
		"renderer": "forward_plus / vulkan",
		"display_server": "Test display",
		"resolution": "1600 x 1000",
		"vsync": "On",
		"max_fps": 0,
		"frame_sample_seconds": 2.5,
		"context": {"scenario": "Course view", "day": 7},
		"frame": {
			"sample_count": 150,
			"average_fps": 60.0,
			"one_percent_low_fps": 48.0,
			"p95_frame_ms": 18.2,
			"frames_over_33_ms": 3,
		},
		"cpu": {"units_per_second": 12345.0},
		"engine": {
			"process_ms_per_frame": 4.1,
			"physics_ms_per_frame": 0.6,
			"render_objects": 220,
			"render_primitives": 3100,
		},
	}
	var text := PerformanceBenchmark.format_report(report)
	assert_string_contains(text, "GTB-1", "same-version reports can be compared")
	assert_string_contains(text, "Test CPU", "the device hardware is identified")
	assert_string_contains(text, "1% low 48.0 FPS", "frame pacing includes a low-frame metric")
	assert_string_contains(text, "12,345 work units/s", "CPU throughput is human-readable")
	assert_string_contains(text, "same course/save", "the report explains how to compare fairly")
	assert_string_contains(PerformanceBenchmark.format_summary(report), "60.0 FPS")

func test_integer_scores_use_thousands_separators() -> void:
	assert_eq(PerformanceBenchmark.format_integer(9876543), "9,876,543")
	assert_eq(PerformanceBenchmark.format_integer(-12345), "-12,345")
