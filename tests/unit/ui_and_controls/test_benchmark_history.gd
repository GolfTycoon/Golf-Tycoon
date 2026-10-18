extends GameTest
## BenchmarkHistory - the local shelf of past runs the results screen compares:
## what a finished report leaves behind, how the shelf is kept and trimmed, and
## the comparisons the screen draws from it.

const HISTORY_PATH := "user://test_benchmark_history_shelf.json"

var _old_history_path := ""

func before_each() -> void:
	super()
	_old_history_path = BenchmarkHistory.history_path
	BenchmarkHistory.history_path = HISTORY_PATH
	BenchmarkHistory.clear()

func after_each() -> void:
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = _old_history_path
	PerformanceBenchmark.last_result = {}
	super()

## A finished run, the way PerformanceBenchmark hands one over.
func _run(unix_time: int, overall: float, fps: float, cpu: float, gpu: float,
		device: String = "Test device") -> Dictionary:
	return {
		"started_at_unix": unix_time,
		"benchmark_version": "GTB-2",
		"game_version": "0.4.3",
		"platform": "Test OS",
		"device_model": device,
		"cpu_name": "Test CPU",
		"gpu_name": "Test GPU",
		"resolution": "1600 x 1000",
		"context": {"scenario": "Course view"},
		"frame": {"sample_count": 150, "average_fps": fps, "one_percent_low_fps": fps * 0.8,
			"p95_frame_ms": 18.0, "frames_over_33_ms": 2},
		"cpu": {"units_per_second": cpu},
		"gpu": {"available": gpu > 0.0, "peak_megapixels_per_second": gpu},
		"memory": {"static_mb": 128.0},
		"score": {"overall": overall, "stars": clampi(int(round(overall / 20.0)), 0, 5),
			"tier": PerformanceBenchmark.tier_name(clampi(int(round(overall / 20.0)), 0, 5))},
	}

# ---------------------------------------------------------------------------
# What a run leaves behind
# ---------------------------------------------------------------------------

func test_a_finished_run_is_kept_as_a_small_comparable_record() -> void:
	var record := BenchmarkHistory.record_from(_run(1_700_000_000, 72.4, 60.0, 900_000.0, 640.0))
	assert_eq(record["at_unix"], 1_700_000_000)
	assert_eq(record["device_model"], "Test device")
	assert_eq(record["gpu"], "Test GPU", "the adapter name is what identifies the machine")
	assert_eq(record["average_fps"], 60.0)
	assert_eq(record["cpu_units_per_second"], 900_000)
	assert_eq(record["overall"], 72.4)
	assert_eq(record["stars"], 4)
	assert_eq(record["tier"], "Tour")
	assert_true(record["gpu_measured"], "and whether the GPU test ran at all")
	assert_eq(record["stutter_percent"], 1.3, "the stutter share is kept as a percentage")

func test_a_run_without_a_gpu_says_so_rather_than_reporting_a_zero_rate() -> void:
	var record := BenchmarkHistory.record_from(_run(1_700_000_000, 60.0, 55.0, 500_000.0, 0.0))
	assert_false(record["gpu_measured"])
	assert_eq(record["gpu_megapixels_per_second"], 0.0)

# ---------------------------------------------------------------------------
# The shelf
# ---------------------------------------------------------------------------

func test_runs_are_kept_oldest_first_and_read_back_from_disk() -> void:
	BenchmarkHistory.append_run(_run(3_000, 80.0, 60.0, 1_000_000.0, 700.0))
	BenchmarkHistory.append_run(_run(1_000, 40.0, 30.0, 300_000.0, 100.0))
	BenchmarkHistory.append_run(_run(2_000, 60.0, 45.0, 600_000.0, 400.0))
	var runs := BenchmarkHistory.load_runs()
	assert_eq(runs.size(), 3)
	assert_eq(int(runs[0]["at_unix"]), 1_000, "the shelf is ordered by time, not by arrival")
	assert_eq(int(BenchmarkHistory.latest(runs)["at_unix"]), 3_000)
	assert_eq(int(BenchmarkHistory.previous_of(runs)["at_unix"]), 2_000,
		"the run before the newest is the one to compare against")
	assert_eq(BenchmarkHistory.previous_of(runs, 2), {}, "the oldest run has nothing before it")

func test_the_shelf_is_capped_so_it_never_grows_forever() -> void:
	for index in range(BenchmarkHistory.MAX_RUNS + 5):
		BenchmarkHistory.append_run(_run(1_000 + index, 50.0, 45.0, 500_000.0, 300.0))
	var runs := BenchmarkHistory.load_runs()
	assert_eq(runs.size(), BenchmarkHistory.MAX_RUNS, "the oldest runs fall off the shelf")
	assert_eq(int(runs[0]["at_unix"]), 1_005, "and the newest are the ones kept")

func test_an_unreadable_shelf_is_an_empty_one() -> void:
	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "runs": "not a list"}))
	file.close()
	assert_eq(BenchmarkHistory.load_runs(), [], "a shelf in the wrong shape is an empty one")
	file = FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "runs": [{"at_unix": 5}, "junk", 12]}))
	file.close()
	var runs := BenchmarkHistory.load_runs()
	assert_eq(runs.size(), 1, "and entries that are not records are dropped")
	BenchmarkHistory.clear()
	assert_eq(BenchmarkHistory.load_runs(), [], "and a missing file is too")

func test_clearing_the_shelf_forgets_every_run() -> void:
	BenchmarkHistory.append_run(_run(1_000, 60.0, 45.0, 500_000.0, 300.0))
	BenchmarkHistory.clear()
	assert_eq(BenchmarkHistory.load_runs(), [])
	assert_false(FileAccess.file_exists(HISTORY_PATH), "the file itself goes")

# ---------------------------------------------------------------------------
# The comparisons the screen draws
# ---------------------------------------------------------------------------

func test_changes_are_read_as_percentages_of_the_earlier_run() -> void:
	var before := BenchmarkHistory.record_from(_run(1_000, 50.0, 40.0, 400_000.0, 200.0))
	var after := BenchmarkHistory.record_from(_run(2_000, 60.0, 50.0, 500_000.0, 250.0))
	assert_almost_eq(BenchmarkHistory.change_percent(before, after, "overall"), 20.0, 0.001)
	assert_almost_eq(BenchmarkHistory.change_percent(after, before, "overall"),
		-16.6667, 0.001, "a slower run reads as a fall")
	assert_eq(BenchmarkHistory.change_percent({}, after, "overall"), 0.0,
		"with nothing to compare against there is no change to report")
	assert_eq(BenchmarkHistory.format_change(12.4), "+12%")
	assert_eq(BenchmarkHistory.format_change(-7.6), "-8%")
	assert_eq(BenchmarkHistory.format_change(0.0), "0%")

func test_a_metric_can_be_drawn_across_the_whole_shelf() -> void:
	BenchmarkHistory.append_run(_run(1_000, 40.0, 30.0, 300_000.0, 100.0))
	BenchmarkHistory.append_run(_run(2_000, 60.0, 45.0, 500_000.0, 300.0))
	BenchmarkHistory.append_run(_run(3_000, 80.0, 60.0, 900_000.0, 700.0))
	var runs := BenchmarkHistory.load_runs()
	assert_eq(BenchmarkHistory.series_of(runs, "overall"), [40.0, 60.0, 80.0],
		"the series runs oldest to newest, the way a chart reads")
	assert_eq(BenchmarkHistory.series_of(runs, "average_fps"), [30.0, 45.0, 60.0])
	var best := BenchmarkHistory.best_of(runs, "overall")
	assert_eq(int(best["at_unix"]), 3_000, "the best run is the highest score")
	var quickest := BenchmarkHistory.best_of(runs, "p95_frame_ms", true)
	assert_eq(int(quickest["at_unix"]), 1_000, "and the quickest frame time is the lowest one")
	assert_eq(BenchmarkHistory.best_of([], "overall"), {}, "an empty shelf has no best")

func test_a_comparison_only_claims_the_same_machine() -> void:
	var here := BenchmarkHistory.record_from(_run(1_000, 60.0, 45.0, 500_000.0, 300.0))
	var there := BenchmarkHistory.record_from(
		_run(2_000, 90.0, 60.0, 900_000.0, 700.0, "Another device"))
	assert_true(BenchmarkHistory.same_device(here, BenchmarkHistory.record_from(
		_run(2_000, 90.0, 60.0, 900_000.0, 700.0))), "the same machine compares")
	assert_false(BenchmarkHistory.same_device(here, there), "another machine does not")
	assert_false(BenchmarkHistory.same_device({}, here), "and neither does nothing")

func test_run_times_read_as_today_yesterday_or_a_date() -> void:
	var now := 1_760_000_000
	var today := Time.get_datetime_dict_from_unix_time(now)
	var same_day := Time.get_unix_time_from_datetime_string("%04d-%02d-%02d 09:05:00" % [
		int(today["year"]), int(today["month"]), int(today["day"])])
	assert_eq(BenchmarkHistory.time_label(int(same_day), now), "Today 09:05")
	assert_eq(BenchmarkHistory.time_label(int(same_day) - 86_400, now), "Yesterday 09:05")
	assert_eq(BenchmarkHistory.time_label(int(same_day) - 3 * 86_400, now),
		"%d %s 09:05" % [int(today["day"]) - 3,
			BenchmarkHistory.MONTH_NAMES[int(today["month"]) - 1]],
		"anything older carries its date")
	assert_eq(BenchmarkHistory.time_label(0), "Unknown time")

func test_a_run_is_named_after_the_machine_that_made_it() -> void:
	var record := BenchmarkHistory.record_from(_run(1_000, 60.0, 45.0, 500_000.0, 300.0))
	assert_eq(BenchmarkHistory.device_label(record), "Test device")
	var anonymous := BenchmarkHistory.record_from(_run(2_000, 60.0, 45.0, 500_000.0, 300.0))
	anonymous["device_model"] = "Unknown model"
	assert_eq(BenchmarkHistory.device_label(anonymous), "Test OS",
		"a machine that will not name itself falls back to its platform")
