extends Node
class_name PerformanceBenchmark
## PerformanceBenchmark - a repeatable, local diagnostic for comparing devices.
##
## It samples the live frame pacing first, then runs a small deterministic
## GDScript workload in short per-frame slices so the settings screen remains
## responsive. The benchmark never edits the course or uploads anything.

signal progress_changed(message: String, fraction: float)
signal completed(result: Dictionary)

enum Phase { IDLE, WARM_UP, FRAME_PACING, CPU_WORKLOAD }

const BENCHMARK_VERSION := "GTB-1"
const DEFAULT_WARMUP_USEC := 350_000
const DEFAULT_FRAME_SAMPLE_USEC := 2_500_000
const DEFAULT_CPU_SAMPLE_USEC := 1_500_000
const DEFAULT_CPU_BUDGET_USEC_PER_FRAME := 1_200
const CPU_WORK_BATCH := 8
const SLOW_FRAME_THRESHOLD_MS := 33.3

## Public durations and budget keep the state machine fast to exercise in tests.
var warmup_duration_usec: int = DEFAULT_WARMUP_USEC
var frame_sample_duration_usec: int = DEFAULT_FRAME_SAMPLE_USEC
var cpu_sample_duration_usec: int = DEFAULT_CPU_SAMPLE_USEC
var cpu_budget_usec_per_frame: int = DEFAULT_CPU_BUDGET_USEC_PER_FRAME

var _phase: int = Phase.IDLE
var _context: Dictionary = {}
var _phase_started_usec: int = 0
var _last_frame_usec: int = 0
var _last_progress_usec: int = 0
var _frame_times_ms: Array[float] = []
var _process_times_ms: Array[float] = []
var _physics_times_ms: Array[float] = []
var _work_units: int = 0
var _cpu_compute_usec: int = 0
var _work_checksum: float = 0.0
var _render_objects: int = 0
var _render_primitives: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func is_running() -> bool:
	return _phase != Phase.IDLE

## Start a benchmark, annotating the report with the screen that was measured.
## Returns false when another run is already in progress.
func start(context: Dictionary = {}) -> bool:
	if is_running():
		return false
	_context = context.duplicate(true)
	_frame_times_ms.clear()
	_process_times_ms.clear()
	_physics_times_ms.clear()
	_work_units = 0
	_cpu_compute_usec = 0
	_work_checksum = 0.0
	_render_objects = 0
	_render_primitives = 0
	var now_usec := Time.get_ticks_usec()
	_phase = Phase.WARM_UP
	_phase_started_usec = now_usec
	_last_progress_usec = now_usec
	set_process(true)
	progress_changed.emit("Warming up...", 0.0)
	return true

func cancel() -> void:
	_phase = Phase.IDLE
	set_process(false)

func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	match _phase:
		Phase.WARM_UP:
			_process_warmup(now_usec)
		Phase.FRAME_PACING:
			_process_frame_sample(now_usec)
		Phase.CPU_WORKLOAD:
			_process_cpu_sample(now_usec)

func _process_warmup(now_usec: int) -> void:
	var elapsed_usec := now_usec - _phase_started_usec
	if elapsed_usec >= warmup_duration_usec:
		_begin_frame_sample(now_usec)
		return
	var fraction := 0.05 * float(elapsed_usec) / float(maxi(warmup_duration_usec, 1))
	_publish_progress("Warming up...", fraction, now_usec)

func _begin_frame_sample(now_usec: int) -> void:
	_phase = Phase.FRAME_PACING
	_phase_started_usec = now_usec
	_last_frame_usec = now_usec
	_last_progress_usec = now_usec
	progress_changed.emit("Measuring frame pacing...", 0.05)

func _process_frame_sample(now_usec: int) -> void:
	var frame_usec := now_usec - _last_frame_usec
	if frame_usec > 0:
		_frame_times_ms.append(float(frame_usec) / 1000.0)
		_last_frame_usec = now_usec
		_process_times_ms.append(maxf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.0))
		_physics_times_ms.append(maxf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.0))
		_render_objects = maxi(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), 0)
		_render_primitives = maxi(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), 0)

	var elapsed_usec := now_usec - _phase_started_usec
	if elapsed_usec >= frame_sample_duration_usec:
		_begin_cpu_sample(now_usec)
		return
	var fraction := 0.05 + 0.60 * float(elapsed_usec) / float(maxi(frame_sample_duration_usec, 1))
	_publish_progress("Measuring frame pacing...", fraction, now_usec)

func _begin_cpu_sample(now_usec: int) -> void:
	_phase = Phase.CPU_WORKLOAD
	_phase_started_usec = now_usec
	_last_progress_usec = now_usec
	progress_changed.emit("Measuring CPU workload...", 0.65)

func _process_cpu_sample(now_usec: int) -> void:
	_run_cpu_slice()
	var elapsed_usec := now_usec - _phase_started_usec
	if elapsed_usec >= cpu_sample_duration_usec:
		_finish()
		return
	var fraction := 0.65 + 0.35 * float(elapsed_usec) / float(maxi(cpu_sample_duration_usec, 1))
	_publish_progress("Measuring CPU workload...", fraction, now_usec)

## Limit each slice so the benchmark does not monopolize the main thread. The
## actual compute time (rather than time spent waiting for the next frame) is
## used for the throughput score.
func _run_cpu_slice() -> void:
	var started_usec := Time.get_ticks_usec()
	var deadline_usec := started_usec + maxi(cpu_budget_usec_per_frame, 0)
	while Time.get_ticks_usec() < deadline_usec:
		for _unit in range(CPU_WORK_BATCH):
			_work_checksum += work_unit_checksum(_work_units)
			_work_units += 1
	_cpu_compute_usec += Time.get_ticks_usec() - started_usec

func _publish_progress(message: String, fraction: float, now_usec: int) -> void:
	if now_usec - _last_progress_usec < 100_000:
		return
	_last_progress_usec = now_usec
	progress_changed.emit(message, clampf(fraction, 0.0, 1.0))

func _finish() -> void:
	var frame_summary := summarize_frame_times(_frame_times_ms)
	var compute_seconds := float(_cpu_compute_usec) / 1_000_000.0
	var units_per_second := float(_work_units) / compute_seconds if compute_seconds > 0.0 else 0.0
	var result := _collect_device_details()
	result["frame"] = frame_summary
	result["cpu"] = {
		"work_units": _work_units,
		"compute_ms": float(_cpu_compute_usec) / 1000.0,
		"units_per_second": units_per_second,
		"checksum": _work_checksum,
	}
	result["engine"] = {
		"process_ms_per_frame": _average(_process_times_ms),
		"physics_ms_per_frame": _average(_physics_times_ms),
		"render_objects": _render_objects,
		"render_primitives": _render_primitives,
		"node_count": maxi(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), 0),
	}
	result["context"] = _context.duplicate(true)
	result["report_text"] = format_report(result)
	_phase = Phase.IDLE
	set_process(false)
	completed.emit(result)

func _collect_device_details() -> Dictionary:
	var engine_version: Dictionary = Engine.get_version_info()
	var viewport_size := get_viewport().get_visible_rect().size
	var gpu_name := _fallback(RenderingServer.get_video_adapter_name(), "Unknown")
	var gpu_vendor := _fallback(RenderingServer.get_video_adapter_vendor(), "Unknown")
	var gpu_label := gpu_name if gpu_vendor == "Unknown" or gpu_name == gpu_vendor \
		else "%s (%s)" % [gpu_name, gpu_vendor]
	var renderer := "%s / %s" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name()]
	return {
		"benchmark_version": BENCHMARK_VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "Unknown")),
		"engine_version": str(engine_version.get("string", "Unknown")),
		"build_type": "Debug" if OS.is_debug_build() else "Release",
		"device_model": _fallback(OS.get_model_name(), "Unknown model"),
		"platform": _fallback(OS.get_name(), "Unknown platform"),
		"os_version": _fallback(OS.get_version(), "Unknown version"),
		"cpu_name": _fallback(OS.get_processor_name(), "Unknown CPU"),
		"cpu_cores": OS.get_processor_count(),
		"gpu": gpu_label,
		"renderer": renderer,
		"display_server": DisplayServer.get_name(),
		"resolution": "%d x %d" % [int(viewport_size.x), int(viewport_size.y)],
		"vsync": vsync_mode_name(DisplayServer.window_get_vsync_mode()),
		"max_fps": Engine.max_fps,
		"frame_sample_seconds": float(frame_sample_duration_usec) / 1_000_000.0,
	}

## Deterministic workload unit shared by every run of GTB-1. It performs the
## same small vector/trigonometry calculation regardless of the current course.
static func work_unit_checksum(iteration: int) -> float:
	var value := float((iteration * 37 + 11) % 997) / 997.0 + 0.01
	for step in range(6):
		var angle := float((iteration + step * 29) % 360 - 180) * PI / 180.0
		var x := value * cos(angle) - float(step) * 0.001
		var y := value * sin(angle) + float(step) * 0.002
		value = sqrt(absf(x * x + y * y)) / (1.0 + absf(y) * 0.05)
	return value

## Frame-rate summary used by both the device report and the tests. The 1% low
## is the mean FPS of the slowest one percent of sampled frames (at least one).
static func summarize_frame_times(samples_ms: Array[float]) -> Dictionary:
	var count := samples_ms.size()
	if count == 0:
		return {
			"sample_count": 0,
			"average_fps": 0.0,
			"one_percent_low_fps": 0.0,
			"average_frame_ms": 0.0,
			"p95_frame_ms": 0.0,
			"frames_over_33_ms": 0,
		}
	var sorted_samples: Array[float] = samples_ms.duplicate()
	sorted_samples.sort()
	var total_ms := 0.0
	var slow_frames := 0
	for sample_ms in sorted_samples:
		var safe_ms := maxf(sample_ms, 0.001)
		total_ms += safe_ms
		if safe_ms > SLOW_FRAME_THRESHOLD_MS:
			slow_frames += 1
	var average_frame_ms := total_ms / float(count)
	var slow_count := maxi(1, ceili(float(count) * 0.01))
	var slow_total_ms := 0.0
	for index in range(count - slow_count, count):
		slow_total_ms += maxf(sorted_samples[index], 0.001)
	var p95_index := clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)
	return {
		"sample_count": count,
		"average_fps": 1000.0 / average_frame_ms,
		"one_percent_low_fps": 1000.0 / (slow_total_ms / float(slow_count)),
		"average_frame_ms": average_frame_ms,
		"p95_frame_ms": sorted_samples[p95_index],
		"frames_over_33_ms": slow_frames,
	}

static func format_summary(result: Dictionary) -> String:
	var frame: Dictionary = result.get("frame", {})
	var cpu: Dictionary = result.get("cpu", {})
	var score := int(round(float(cpu.get("units_per_second", 0.0))))
	if int(frame.get("sample_count", 0)) <= 0:
		return "CPU score %s units/s · no frame samples" % format_integer(score)
	return "CPU score %s units/s · avg %.1f FPS · 1%% low %.1f FPS" % [
		format_integer(score), float(frame.get("average_fps", 0.0)),
		float(frame.get("one_percent_low_fps", 0.0)),
	]

static func format_report(result: Dictionary) -> String:
	var frame: Dictionary = result.get("frame", {})
	var cpu: Dictionary = result.get("cpu", {})
	var engine: Dictionary = result.get("engine", {})
	var context: Dictionary = result.get("context", {})
	var lines := PackedStringArray()
	lines.append("Golf Tycoon benchmark %s" % str(result.get("benchmark_version", BENCHMARK_VERSION)))
	lines.append("Game %s | Godot %s | %s build" % [str(result.get("game_version", "Unknown")),
		str(result.get("engine_version", "Unknown")), str(result.get("build_type", "Unknown"))])
	lines.append("Device %s | %s" % [str(result.get("device_model", "Unknown model")),
		str(result.get("platform", "Unknown platform"))])
	lines.append("OS %s | CPU %s (%s logical cores)" % [str(result.get("os_version", "Unknown version")),
		str(result.get("cpu_name", "Unknown CPU")), str(result.get("cpu_cores", "?"))])
	lines.append("GPU %s | Renderer %s | Display %s" % [str(result.get("gpu", "Unknown")),
		str(result.get("renderer", "Unknown")), str(result.get("display_server", "Unknown"))])
	lines.append("Resolution %s | VSync %s | FPS cap %s" % [str(result.get("resolution", "Unknown")),
		str(result.get("vsync", "Unknown")), _fps_cap_label(int(result.get("max_fps", 0)))])
	var scenario := str(context.get("scenario", "Unknown scene"))
	if context.has("day") and context["day"] != null:
		scenario += " | day %s" % str(context["day"])
	lines.append("Scene %s | %s nodes | %s render objects | %s primitives" % [scenario,
		str(engine.get("node_count", 0)), str(engine.get("render_objects", 0)),
		str(engine.get("render_primitives", 0))])
	if int(frame.get("sample_count", 0)) > 0:
		lines.append("Frame pacing (%s s): %.1f FPS avg | 1%% low %.1f FPS | p95 %.1f ms | %s frames >33 ms" % [
			"%.1f" % float(result.get("frame_sample_seconds", DEFAULT_FRAME_SAMPLE_USEC / 1_000_000.0)),
			float(frame.get("average_fps", 0.0)),
			float(frame.get("one_percent_low_fps", 0.0)),
			float(frame.get("p95_frame_ms", 0.0)),
			str(frame.get("frames_over_33_ms", 0)),
		])
	else:
		lines.append("Frame pacing: no frames were sampled")
	lines.append("Game CPU: %.2f ms process | %.2f ms physics per frame" % [
		float(engine.get("process_ms_per_frame", 0.0)),
		float(engine.get("physics_ms_per_frame", 0.0)),
	])
	lines.append("CPU script score: %s work units/s (higher is faster; compare GTB-1 reports)" %
		format_integer(int(round(float(cpu.get("units_per_second", 0.0))))))
	lines.append("")
	lines.append("For fair comparisons, use the same course/save, camera view, resolution, VSync and power mode.")
	lines.append("Frame pacing measures the current scene; the CPU score is a fixed script workload.")
	lines.append("This report stays local. Copying it includes device and hardware details; it is not uploaded.")
	return "\n".join(lines)

static func vsync_mode_name(mode: int) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED: return "Off"
		DisplayServer.VSYNC_ENABLED: return "On"
		DisplayServer.VSYNC_ADAPTIVE: return "Adaptive"
		DisplayServer.VSYNC_MAILBOX: return "Mailbox"
		_: return "Unknown (%d)" % mode

static func format_integer(value: int) -> String:
	var digits := str(absi(value))
	var formatted := "" if value >= 0 else "-"
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += ","
		formatted += digits[index]
	return formatted

func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

static func _fallback(value: String, fallback: String) -> String:
	return fallback if value.strip_edges().is_empty() else value

static func _fps_cap_label(max_fps: int) -> String:
	return "Unlimited" if max_fps <= 0 else "%d FPS" % max_fps
