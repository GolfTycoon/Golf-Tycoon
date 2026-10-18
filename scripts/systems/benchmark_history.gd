extends RefCounted
class_name BenchmarkHistory
## BenchmarkHistory - the local shelf of past device benchmark runs.
##
## One report on its own says little: "60 FPS" is only interesting next to
## "58 FPS yesterday after I turned VSync off" or "60 FPS on the tablet and
## 41 on the phone". So each finished run keeps a small record here, in
## `user://benchmark_history.json`, and the results screen draws them as a
## comparison graph and a list with the change against the newest run beside
## each one.
##
## The file is local, tiny and optional - it holds the numbers from the report
## and nothing else, and `clear()` wipes it. Records are capped so a player who
## benchmarks every build does not grow the file forever.
##
## Record shape (all keys optional when read back, so an older file still
## loads): at_unix, benchmark_version, game_version, platform, device_model,
## cpu_name, gpu, resolution, scenario, overall, stars, tier, cpu_units_per_second,
## gpu_megapixels_per_second, average_fps, one_percent_low_fps, p95_frame_ms,
## stutter_percent, static_memory_mb, and - for a course-tour run - tour_suite,
## tour_scenarios, tour_worst_scenario, tour_worst_fps, tour_generation_ms,
## tour_editing_tiles_per_second, tour_prepare_ms (the throwaway course the
## benchmark prepared from the Main Menu; absent on older records).

const FILE_VERSION := 1
const DEFAULT_HISTORY_PATH := "user://benchmark_history.json"
## Runs kept on the shelf.
const MAX_RUNS := 12
## Three-letter month names for the run list ("18 Oct 14:32").
const MONTH_NAMES := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
	"Nov", "Dec"]
## Keys a comparison can be drawn or subtracted on, and the unit each reads in.
const METRIC_KEYS := ["overall", "average_fps", "one_percent_low_fps", "cpu_units_per_second",
	"gpu_megapixels_per_second", "p95_frame_ms"]

## Tests point this at a scratch file instead of the player's.
static var history_path: String = DEFAULT_HISTORY_PATH

## The compact record a finished report leaves behind. Rounded, so the file
## stays readable and small.
static func record_from(result: Dictionary) -> Dictionary:
	var frame: Dictionary = result.get("frame", {})
	var cpu: Dictionary = result.get("cpu", {})
	var gpu: Dictionary = result.get("gpu", {})
	var memory: Dictionary = result.get("memory", {})
	var score: Dictionary = result.get("score", PerformanceBenchmark.score_result(result))
	var context: Dictionary = result.get("context", {})
	var sample_count := maxi(int(frame.get("sample_count", 0)), 1)
	var record := {
		"at_unix": int(result.get("started_at_unix", 0)),
		"benchmark_version": str(result.get("benchmark_version", "")),
		"game_version": str(result.get("game_version", "")),
		"platform": str(result.get("platform", "Unknown platform")),
		"device_model": str(result.get("device_model", "Unknown model")),
		"cpu_name": str(result.get("cpu_name", "Unknown CPU")),
		"gpu": str(result.get("gpu_name", "Unknown")),
		"resolution": str(result.get("resolution", "Unknown")),
		"scenario": str(context.get("scenario", "Unknown scene")),
		"overall": round1(float(score.get("overall", 0.0))),
		"stars": int(score.get("stars", 0)),
		"tier": str(score.get("tier", "Unrated")),
		"cpu_units_per_second": int(round(float(cpu.get("units_per_second", 0.0)))),
		"gpu_megapixels_per_second": round1(float(gpu.get("peak_megapixels_per_second", 0.0))),
		"gpu_measured": bool(gpu.get("available", false)),
		"average_fps": round1(float(frame.get("average_fps", 0.0))),
		"one_percent_low_fps": round1(float(frame.get("one_percent_low_fps", 0.0))),
		"p95_frame_ms": round1(float(frame.get("p95_frame_ms", 0.0))),
		"stutter_percent": round1(100.0 * float(int(frame.get("frames_over_33_ms", 0))) \
			/ float(sample_count)),
		"static_memory_mb": round1(float(memory.get("static_mb", 0.0))),
	}
	# A tour run also leaves the shape of its tour behind, so the shelf can
	# say which course was heaviest without keeping the whole report.
	var tour: Dictionary = result.get("tour", {})
	if not tour.is_empty():
		var rollup: Dictionary = tour.get("rollup", {})
		var simulation: Dictionary = rollup.get("simulation", {})
		var generation: Dictionary = rollup.get("generation", {})
		var editing: Dictionary = rollup.get("editing", {})
		record["tour_suite"] = str(tour.get("suite", ""))
		record["tour_scenarios"] = int(rollup.get("scenario_count",
			(tour.get("scenarios", []) as Array).size()))
		record["tour_worst_scenario"] = str(simulation.get("worst_scenario", ""))
		record["tour_worst_fps"] = round1(float(simulation.get("worst_fps", 0.0)))
		record["tour_generation_ms"] = round1(float(generation.get("total_ms", 0.0)))
		record["tour_editing_tiles_per_second"] = round1(
			float(editing.get("tiles_per_second", 0.0)))
		var prepare: Dictionary = tour.get("prepare", {})
		if not prepare.is_empty():
			record["tour_prepare_ms"] = round1(float(prepare.get("prepare_ms", 0.0)))
	return record

## The runs on the shelf, oldest first. A missing or unreadable file is an
## empty shelf rather than an error.
static func load_runs() -> Array:
	if not FileAccess.file_exists(history_path):
		return []
	var file := FileAccess.open(history_path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return []
	var raw: Variant = (parsed as Dictionary).get("runs", [])
	if not (raw is Array):
		return []
	var runs: Array = []
	for entry in raw:
		if entry is Dictionary:
			runs.append(entry)
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("at_unix", 0)) < int(b.get("at_unix", 0)))
	return runs

static func save_runs(runs: Array) -> void:
	var trimmed := runs.duplicate()
	while trimmed.size() > MAX_RUNS:
		trimmed.pop_front()
	var file := FileAccess.open(history_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"version": FILE_VERSION, "runs": trimmed}, "\t"))
	file.close()

## Append a finished report to the shelf and return the shelf, oldest first.
static func append_run(result: Dictionary) -> Array:
	var runs := load_runs()
	runs.append(record_from(result))
	save_runs(runs)
	return load_runs()

## Forget every run on the shelf.
static func clear() -> void:
	if FileAccess.file_exists(history_path):
		DirAccess.remove_absolute(history_path)

## The newest run, or an empty dictionary on an empty shelf.
static func latest(runs: Array) -> Dictionary:
	return {} if runs.is_empty() else runs[runs.size() - 1]

## The run before `index` (0 is the newest), used to show what changed.
static func previous_of(runs: Array, index: int = 0) -> Dictionary:
	var from_newest := runs.size() - 1 - index
	if from_newest < 1 or from_newest >= runs.size():
		return {}
	return runs[from_newest - 1]

## One metric of a record, tolerant of records written before it existed.
static func metric_of(record: Dictionary, key: String) -> float:
	if record.is_empty():
		return 0.0
	return float(record.get(key, 0.0))

## Percentage change of `key` between two records. Zero when there is nothing
## to compare against, so callers can hide the delta rather than print 0%.
static func change_percent(previous: Dictionary, current: Dictionary, key: String) -> float:
	if previous.is_empty():
		return 0.0
	var before := metric_of(previous, key)
	var after := metric_of(current, key)
	if is_zero_approx(before):
		return 0.0
	return 100.0 * (after - before) / absf(before)

## One metric across the whole shelf, oldest first, for a comparison graph.
static func series_of(runs: Array, key: String) -> Array[float]:
	var series: Array[float] = []
	for record in runs:
		series.append(metric_of(record, key))
	return series

## The best run on the shelf for `key`; `lower_is_better` for frame times.
static func best_of(runs: Array, key: String, lower_is_better: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_value := 0.0
	for record in runs:
		var value := metric_of(record, key)
		if best.is_empty() or (value < best_value if lower_is_better else value > best_value):
			best = record
			best_value = value
	return best

## Whether two records came from the same machine. Comparing across machines
## is the point of the shelf, but a change is only attributable to a setting
## when the hardware underneath it did not move.
static func same_device(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	for key in ["cpu_name", "gpu", "platform", "device_model"]:
		if str(a.get(key, "")) != str(b.get(key, "")):
			return false
	return true

## "Today 14:32", "Yesterday 09:05" or "18 Oct 14:32".
static func time_label(unix_time: int, now_unix: int = 0) -> String:
	if unix_time <= 0:
		return "Unknown time"
	var now := now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
	var stamp: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	var today: Dictionary = Time.get_datetime_dict_from_unix_time(now)
	var clock := "%02d:%02d" % [int(stamp.get("hour", 0)), int(stamp.get("minute", 0))]
	var day := "%d %s" % [int(stamp.get("day", 0)),
		MONTH_NAMES[clampi(int(stamp.get("month", 1)), 1, 12) - 1]]
	if int(stamp.get("year", 0)) == int(today.get("year", 0)) \
			and int(stamp.get("month", 1)) == int(today.get("month", 1)) \
			and int(stamp.get("day", 0)) == int(today.get("day", 0)):
		return "Today %s" % clock
	var yesterday: Dictionary = Time.get_datetime_dict_from_unix_time(now - 86_400)
	if int(stamp.get("year", 0)) == int(yesterday.get("year", 0)) \
			and int(stamp.get("month", 1)) == int(yesterday.get("month", 1)) \
			and int(stamp.get("day", 0)) == int(yesterday.get("day", 0)):
		return "Yesterday %s" % clock
	return "%s %s" % [day, clock]

## The short name a run wears in the list: the machine, or the scene when the
## machine is unknown.
static func device_label(record: Dictionary) -> String:
	var model := str(record.get("device_model", "")).strip_edges()
	if model.is_empty() or model.begins_with("Unknown"):
		return str(record.get("platform", "Unknown device"))
	return model

## "+12%" / "-4%" / "0%" for a change against the previous run.
static func format_change(percent: float) -> String:
	if is_zero_approx(percent):
		return "0%"
	return "%+.0f%%" % percent

static func round1(value: float) -> float:
	return float(roundf(value * 10.0)) / 10.0
