extends Node
class_name PerformanceBenchmark
## PerformanceBenchmark - a repeatable, local diagnostic for comparing devices.
##
## The benchmark is the course tour (CourseBenchmarkTour), and the tour is
## always the full one: run from Main Menu Settings, it prepares its own
## throwaway course, then builds every fixed, seeded course of
## CourseBenchmarkScenarios on screen - every course type, hole count, golfer
## field, camera move, edit plan and game speed - and samples each phase,
## preparation included, so the same work is measured on every machine and a
## slow number names the subsystem that is slow. The tour's samples and
## timings are summarized here (summarize_tour) and graded with the same
## scorecard as ever.
##
## This node is the device check the tour finishes with. It walks four
## phases, each sliced into short per-frame steps so the screen behind it
## stays responsive:
##
##  1. WARM_UP - let the engine settle before anything is measured.
##  2. FRAME_PACING - sample the live scene: frame times, process and physics
##     times, render counts. The samples are kept (downsampled) so the results
##     screen can draw them as a graph.
##  3. GPU_LOAD - a fill-rate test. A pixel-weave canvas is layered over the
##     window and redrawn at three growing overdraw levels; the frame rate each
##     level costs gives a throughput ladder in megapixels a second, which is
##     what shows where a GPU runs out of headroom.
##  4. CPU_WORKLOAD - a fixed GDScript workload, timed by the compute it
##     actually performed rather than by the frames it waited through.
##
## The result carries a golf-style scorecard and a five-star device rating
## (see score_result) plus the device details a comparison needs. The device
## check never edits the course; the tour edits only its own throwaway
## courses and restores the player's afterwards. Neither uploads anything;
## a finished run is optionally appended to the local BenchmarkHistory so
## past devices can be compared.

signal progress_changed(message: String, fraction: float)
signal completed(result: Dictionary)

enum Phase { IDLE, WARM_UP, FRAME_PACING, GPU_LOAD, CPU_WORKLOAD }

## GTB-5 is the full course tour - the game's only benchmark - run from the
## Main Menu on a course the benchmark prepares itself, with the preparation
## (the throwaway session plus each course's build-and-settle) sampled into
## the headline frame pacing. GTB-4 ran the short four-course tour, so its
## pacing covers a quarter of the courses GTB-5's does and the two are not
## comparable. GTB-3 toured courses borrowed from an open game without those
## frames. The CPU and GPU workloads are unchanged from GTB-2 and stay
## comparable.
const BENCHMARK_VERSION := "GTB-5"
const DEFAULT_WARMUP_USEC := 350_000
const DEFAULT_FRAME_SAMPLE_USEC := 2_500_000
## Per overdraw level of the GPU test; three of them make the ladder.
const DEFAULT_GPU_STEP_USEC := 700_000
const DEFAULT_CPU_SAMPLE_USEC := 1_500_000
const DEFAULT_CPU_BUDGET_USEC_PER_FRAME := 1_200
const CPU_WORK_BATCH := 8
const SLOW_FRAME_THRESHOLD_MS := 33.3

## The GPU test's three loads, as multiples of the window's own pixel count:
## a plain redraw, a moderate fill and a heavy one. A GPU with headroom holds
## the same frame rate through all three; one that does not falls away, and the
## fall is the interesting part.
const GPU_OVERDRAW_LEVELS: Array[float] = [1.0, 4.0, 10.0]
## Side of the weave tile the GPU test draws, and of the texture behind it. A
## big tile keeps the per-quad CPU cost small next to the pixels it fills.
const GPU_TEXTURE_GRID := 32
const GPU_CANVAS_LAYER := 100
## Frame times kept for the results graph, and the points the GPU ladder and
## the history file keep per run.
const MAX_SERIES_SAMPLES := 180

## Score anchors. Each metric is normalised on a log scale between a "double
## bogey" floor and an "eagle" ceiling, so a mid-range device lands near par
## instead of everything clustering at one end.
const CPU_FLOOR_UNITS := 120_000.0
const CPU_EAGLE_UNITS := 2_500_000.0
const GPU_FLOOR_MEGAPIXELS := 40.0
const GPU_EAGLE_MEGAPIXELS := 1_200.0
const FPS_FLOOR := 20.0
const FPS_EAGLE := 144.0
## A 1% low at 45% of the average is a stuttery run; at 90% it is glass.
const EVENNESS_FLOOR_RATIO := 0.45
const EVENNESS_EAGLE_RATIO := 0.90
## 2% of frames over 33 ms spends the whole smoothness budget.
const STUTTER_BUDGET := 0.02
## How much of the five-star rating each metric carries. A metric that could
## not be measured drops out and the rest are scaled back up to 1.0.
const SCORE_WEIGHTS := {"pacing": 0.30, "cpu": 0.25, "gpu": 0.25, "consistency": 0.20}

## The newest finished run, so the results screen can open on the last report
## even when a different screen ran it.
static var last_result: Dictionary = {}

## Public durations and budget keep the state machine fast to exercise in tests.
var warmup_duration_usec: int = DEFAULT_WARMUP_USEC
var frame_sample_duration_usec: int = DEFAULT_FRAME_SAMPLE_USEC
var gpu_step_duration_usec: int = DEFAULT_GPU_STEP_USEC
var cpu_sample_duration_usec: int = DEFAULT_CPU_SAMPLE_USEC
var cpu_budget_usec_per_frame: int = DEFAULT_CPU_BUDGET_USEC_PER_FRAME
## Tests (and a player who wants a quiet run) can skip the GPU fill test.
var gpu_test_enabled: bool = true
## Whether a finished run is appended to the local history file.
var record_history: bool = true

var _phase: int = Phase.IDLE
var _context: Dictionary = {}
var _phase_started_usec: int = 0
var _started_usec: int = 0
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
var _render_draw_calls: int = 0
var _gpu_steps: Array = []
var _gpu_level: int = 0
var _gpu_level_frames_ms: Array[float] = []
var _gpu_level_process_ms: Array[float] = []
var _gpu_layer: CanvasLayer = null
var _gpu_canvas: GpuStressCanvas = null
var _gpu_quad_side: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func is_running() -> bool:
	return _phase != Phase.IDLE

## The phase the runner is in, for the results screen's live caption.
func current_phase() -> int:
	return _phase

## Which overdraw level of the GPU test is running (0 when it is not).
func current_gpu_level() -> int:
	return _gpu_level if _phase == Phase.GPU_LOAD else 0

## Start a benchmark, annotating the report with the screen that was measured.
## Returns false when another run is already in progress.
func start(context: Dictionary = {}) -> bool:
	if is_running():
		return false
	_context = context.duplicate(true)
	_frame_times_ms.clear()
	_process_times_ms.clear()
	_physics_times_ms.clear()
	_gpu_steps.clear()
	_gpu_level_frames_ms.clear()
	_gpu_level_process_ms.clear()
	_gpu_level = 0
	_work_units = 0
	_cpu_compute_usec = 0
	_work_checksum = 0.0
	_render_objects = 0
	_render_primitives = 0
	_render_draw_calls = 0
	var now_usec := Time.get_ticks_usec()
	_started_usec = now_usec
	_phase = Phase.WARM_UP
	_phase_started_usec = now_usec
	_last_progress_usec = now_usec
	set_process(true)
	progress_changed.emit("Warming up...", 0.0)
	return true

func cancel() -> void:
	_release_gpu_canvas()
	_phase = Phase.IDLE
	set_process(false)

func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	match _phase:
		Phase.WARM_UP:
			_process_warmup(now_usec)
		Phase.FRAME_PACING:
			_process_frame_sample(now_usec)
		Phase.GPU_LOAD:
			_process_gpu_step(now_usec)
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
	var samples_before := _frame_times_ms.size()
	_sample_frame(now_usec, _frame_times_ms, _process_times_ms)
	if _frame_times_ms.size() > samples_before:
		_physics_times_ms.append(maxf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.0))
		_render_objects = maxi(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), 0)
		_render_primitives = maxi(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), 0)
		_render_draw_calls = maxi(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), 0)

	var elapsed_usec := now_usec - _phase_started_usec
	if elapsed_usec >= frame_sample_duration_usec:
		_begin_gpu_step(now_usec)
		return
	var fraction := 0.05 + 0.35 * float(elapsed_usec) / float(maxi(frame_sample_duration_usec, 1))
	_publish_progress("Measuring frame pacing...", fraction, now_usec)

# =============================================================================
# GPU FILL TEST
# =============================================================================

func _begin_gpu_step(now_usec: int) -> void:
	if not _should_run_gpu_test():
		_begin_cpu_sample(now_usec)
		return
	if _gpu_level == 0:
		_create_gpu_canvas()
	if _gpu_canvas == null:
		_begin_cpu_sample(now_usec)
		return
	var overdraw := GPU_OVERDRAW_LEVELS[mini(_gpu_level, GPU_OVERDRAW_LEVELS.size() - 1)]
	_gpu_canvas.set_load(overdraw)
	_gpu_level_frames_ms.clear()
	_gpu_level_process_ms.clear()
	_phase = Phase.GPU_LOAD
	_phase_started_usec = now_usec
	_last_frame_usec = now_usec
	_last_progress_usec = now_usec
	progress_changed.emit(gpu_step_message(_gpu_level, overdraw), 0.40)

func _process_gpu_step(now_usec: int) -> void:
	_sample_frame(now_usec, _gpu_level_frames_ms, _gpu_level_process_ms)
	var elapsed_usec := now_usec - _phase_started_usec
	var step_seconds := float(maxi(gpu_step_duration_usec, 1))
	if elapsed_usec >= gpu_step_duration_usec:
		_finish_gpu_step()
		_gpu_level += 1
		if _gpu_level >= GPU_OVERDRAW_LEVELS.size():
			_release_gpu_canvas()
			_begin_cpu_sample(now_usec)
		else:
			_begin_gpu_step(now_usec)
		return
	var fraction := 0.40 + 0.30 * (float(_gpu_level) + float(elapsed_usec) / step_seconds) \
		/ float(GPU_OVERDRAW_LEVELS.size())
	var overdraw := GPU_OVERDRAW_LEVELS[mini(_gpu_level, GPU_OVERDRAW_LEVELS.size() - 1)]
	_publish_progress(gpu_step_message(_gpu_level, overdraw), fraction, now_usec)

func _finish_gpu_step() -> void:
	var overdraw := GPU_OVERDRAW_LEVELS[mini(_gpu_level, GPU_OVERDRAW_LEVELS.size() - 1)]
	var fill_pixels := _gpu_canvas.total_fill_pixels() if _gpu_canvas != null else 0
	_gpu_steps.append(gpu_step_result(overdraw, fill_pixels, _gpu_quad_side,
		_gpu_level_frames_ms, _gpu_level_process_ms, _frame_cap_fps()))

## One frame's timing, appended to the caller's series. The frame is measured
## from the previous call, so the first sample of a phase is skipped rather
## than reporting the phase switch as a hitch.
func _sample_frame(now_usec: int, frame_series: Array[float], process_series: Array[float]) -> void:
	var frame_usec := now_usec - _last_frame_usec
	if frame_usec <= 0:
		return
	frame_series.append(float(frame_usec) / 1000.0)
	process_series.append(maxf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.0))
	_last_frame_usec = now_usec

func _should_run_gpu_test() -> bool:
	return gpu_test_enabled and gpu_test_available()

func _create_gpu_canvas() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_gpu_quad_side = GpuStressCanvas.tile_side_for(viewport_size)
	var canvas := GpuStressCanvas.new(_gpu_quad_side)
	canvas.fill_size = viewport_size
	canvas.name = "GpuStressCanvas"
	var layer := CanvasLayer.new()
	layer.name = "GpuStressLayer"
	layer.layer = GPU_CANVAS_LAYER
	layer.add_child(canvas)
	add_child(layer)
	_gpu_layer = layer
	_gpu_canvas = canvas

func _release_gpu_canvas() -> void:
	if is_instance_valid(_gpu_canvas):
		_gpu_canvas.queue_free()
	if is_instance_valid(_gpu_layer):
		_gpu_layer.queue_free()
	_gpu_canvas = null
	_gpu_layer = null

## Whether the GPU fill test can say anything here: the headless server has no
## renderer, and a run with no adapter name has nothing to fill.
static func gpu_test_available() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not RenderingServer.get_current_rendering_driver_name().strip_edges().is_empty()

static func gpu_skip_reason() -> String:
	if DisplayServer.get_name() == "headless":
		return "no renderer in a headless run"
	if RenderingServer.get_current_rendering_driver_name().strip_edges().is_empty():
		return "no rendering driver reported"
	return ""

static func gpu_step_message(level: int, overdraw: float) -> String:
	return "GPU fill test %d/%d (%dx overdraw)..." % [level + 1, GPU_OVERDRAW_LEVELS.size(),
		int(round(overdraw))]

## The frame rate the run could not have beaten: the engine's cap, or the
## display's refresh when there is no cap. A GPU level that lands on it is
## limited by the cap rather than by the hardware.
func _frame_cap_fps() -> float:
	if Engine.max_fps > 0:
		return float(Engine.max_fps)
	if DisplayServer.get_name() == "headless":
		return 60.0
	var refresh := DisplayServer.screen_get_refresh_rate()
	return float(refresh) if refresh > 0 else 60.0

## One rung of the GPU ladder: how many pixels the level pushed and how fast.
## `gpu_ms` is the frame time left over once the script time is taken out, so
## it reads as the render side's share of the frame.
static func gpu_step_result(overdraw: float, fill_pixels: int, quad_side: int,
		frames_ms: Array[float], process_ms: Array[float], cap_fps: float) -> Dictionary:
	var frames := frames_ms.size()
	if frames == 0:
		return {
			"overdraw": overdraw,
			"quad_side": quad_side,
			"fill_pixels": fill_pixels,
			"frames": 0,
			"fps": 0.0,
			"gpu_ms": 0.0,
			"megapixels_per_second": 0.0,
			"capped": false,
		}
	var frame_summary := summarize_frame_times(frames_ms)
	var average_frame_ms := maxf(float(frame_summary["average_frame_ms"]), 0.001)
	var fps := 1000.0 / average_frame_ms
	var total_process := 0.0
	for sample in process_ms:
		total_process += maxf(sample, 0.0)
	var average_process_ms := total_process / float(maxi(process_ms.size(), 1))
	var capped := cap_fps > 0.0 and fps >= cap_fps * 0.95
	return {
		"overdraw": overdraw,
		"quad_side": quad_side,
		"fill_pixels": fill_pixels,
		"frames": frames,
		"fps": fps,
		"gpu_ms": maxf(average_frame_ms - average_process_ms, 0.0),
		"megapixels_per_second": float(fill_pixels) * fps / 1_000_000.0,
		"capped": capped,
	}

## The GPU section of a report: the ladder, and the peak throughput the
## scorecard grades. A run with no ladder (headless, or the test switched off)
## says so instead of reporting zeros as a result.
static func summarize_gpu(ladder: Array, available: bool, reason: String,
		sample_seconds: float) -> Dictionary:
	var peak := 0.0
	var peak_overdraw := 0.0
	var total_gpu_ms := 0.0
	var heaviest_frames := 0
	for step in ladder:
		var entry: Dictionary = step
		var throughput := float(entry.get("megapixels_per_second", 0.0))
		if throughput >= peak:
			peak = throughput
			peak_overdraw = float(entry.get("overdraw", 0.0))
		if int(entry.get("frames", 0)) >= heaviest_frames:
			heaviest_frames = int(entry.get("frames", 0))
			total_gpu_ms = float(entry.get("gpu_ms", 0.0))
	return {
		"available": available,
		"reason": reason,
		"sample_seconds": sample_seconds,
		"levels": ladder.duplicate(true),
		"peak_megapixels_per_second": peak,
		"peak_overdraw": peak_overdraw,
		"gpu_ms_per_frame": total_gpu_ms,
		"frames_sampled": heaviest_frames,
	}

func _begin_cpu_sample(now_usec: int) -> void:
	_phase = Phase.CPU_WORKLOAD
	_phase_started_usec = now_usec
	_last_progress_usec = now_usec
	progress_changed.emit("Measuring CPU workload...", 0.70)

func _process_cpu_sample(now_usec: int) -> void:
	_run_cpu_slice()
	var elapsed_usec := now_usec - _phase_started_usec
	if elapsed_usec >= cpu_sample_duration_usec:
		_finish()
		return
	var fraction := 0.70 + 0.30 * float(elapsed_usec) / float(maxi(cpu_sample_duration_usec, 1))
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
	frame_summary["series_ms"] = downsample_series(_frame_times_ms, MAX_SERIES_SAMPLES)
	frame_summary["best_frame_ms"] = _minimum(_frame_times_ms)
	frame_summary["worst_frame_ms"] = _maximum(_frame_times_ms)
	var compute_seconds := float(_cpu_compute_usec) / 1_000_000.0
	var units_per_second := float(_work_units) / compute_seconds if compute_seconds > 0.0 else 0.0
	var result := _collect_device_details()
	result["frame"] = frame_summary
	result["gpu"] = summarize_gpu(_gpu_steps, _should_run_gpu_test(), gpu_skip_reason(),
		float(GPU_OVERDRAW_LEVELS.size() * maxi(gpu_step_duration_usec, 0)) / 1_000_000.0)
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
		"draw_calls": _render_draw_calls,
		"node_count": maxi(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), 0),
		"orphan_nodes": maxi(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), 0),
		"resource_count": maxi(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), 0),
	}
	result["memory"] = collect_memory()
	result["context"] = _context.duplicate(true)
	result["started_at_unix"] = int(float(_started_usec) / 1_000_000.0)
	result["duration_ms"] = float(Time.get_ticks_usec() - _started_usec) / 1000.0
	result["score"] = score_result(result)
	result["report_text"] = format_report(result)
	_phase = Phase.IDLE
	set_process(false)
	last_result = result
	if record_history:
		BenchmarkHistory.append_run(result)
	completed.emit(result)

## The device half of a report (versions, machine, renderer, window), for
## the tour runner as well as this node's own finish.
func collect_device_details() -> Dictionary:
	return _collect_device_details()

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
		## The adapter name; the GPU fill test's own numbers live under "gpu".
		"gpu_name": gpu_label,
		"renderer": renderer,
		"display_server": DisplayServer.get_name(),
		"resolution": "%d x %d" % [int(viewport_size.x), int(viewport_size.y)],
		"vsync": vsync_mode_name(DisplayServer.window_get_vsync_mode()),
		"max_fps": Engine.max_fps,
		"frame_sample_seconds": float(frame_sample_duration_usec) / 1_000_000.0,
		"gpu_sample_seconds": float(GPU_OVERDRAW_LEVELS.size() * maxi(gpu_step_duration_usec, 0)) / 1_000_000.0,
	}

## Video and static memory, in megabytes, for the report and the results
## screen's memory read-out.
static func collect_memory() -> Dictionary:
	return {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"static_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
	}

## Deterministic workload unit shared by every run since GTB-2. It performs
## the same small vector/trigonometry calculation regardless of the course.
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

## Bucket a series down to at most `max_samples` points, averaging each bucket,
## so a long run still draws as a readable graph and stores as a small record.
## A series that already fits is passed through unchanged.
static func downsample_series(samples_ms: Array[float], max_samples: int) -> Array[float]:
	var out: Array[float] = []
	var count := samples_ms.size()
	var limit := maxi(max_samples, 1)
	if count <= limit:
		for sample in samples_ms:
			out.append(sample)
		return out
	var bucket_size := float(count) / float(limit)
	for bucket in range(limit):
		var first := int(floorf(float(bucket) * bucket_size))
		var last := maxi(first + 1, int(ceilf(float(bucket + 1) * bucket_size)))
		last = mini(last, count)
		var total := 0.0
		for index in range(first, last):
			total += samples_ms[index]
		out.append(total / float(maxi(last - first, 1)))
	return out

# =============================================================================
# SCORING - the golf scorecard for a device
# =============================================================================

## Log-scale normalisation between a floor (0) and a ceiling (1). Log keeps a
## mid-range device near the middle of the scale, where a linear map would put
## everything at one end.
static func normalize_log(value: float, floor_value: float, ceiling: float) -> float:
	if ceiling <= floor_value or value <= floor_value:
		return 0.0
	if value >= ceiling:
		return 1.0
	return log(value / floor_value) / log(ceiling / floor_value)

## How evenly the run held its frame rate: the 1% low against the average, and
## the share of frames that missed 33 ms.
static func consistency_score(average_fps: float, one_percent_low_fps: float,
		stutter_rate: float) -> float:
	if average_fps <= 0.0:
		return 0.0
	var ratio := clampf(one_percent_low_fps / average_fps, 0.0, 1.0)
	var evenness := clampf((ratio - EVENNESS_FLOOR_RATIO) \
		/ (EVENNESS_EAGLE_RATIO - EVENNESS_FLOOR_RATIO), 0.0, 1.0)
	var smoothness := clampf(1.0 - stutter_rate / STUTTER_BUDGET, 0.0, 1.0)
	return 100.0 * (0.6 * evenness + 0.4 * smoothness)

## The device scorecard: four graded metrics, the five-star rating they carry
## and the tier name it reads as. Metrics that were not measured drop out and
## the remaining weights are scaled back up, so a headless or GPU-less run is
## still rated on what it did measure.
static func score_result(result: Dictionary) -> Dictionary:
	var frame: Dictionary = result.get("frame", {})
	var cpu: Dictionary = result.get("cpu", {})
	var gpu: Dictionary = result.get("gpu", {})
	var sample_count := int(frame.get("sample_count", 0))
	var average_fps := float(frame.get("average_fps", 0.0))
	var one_percent_low := float(frame.get("one_percent_low_fps", 0.0))
	var stutter_rate := 0.0
	if sample_count > 0:
		stutter_rate = float(int(frame.get("frames_over_33_ms", 0))) / float(sample_count)
	var units_per_second := float(cpu.get("units_per_second", 0.0))
	var peak_megapixels := float(gpu.get("peak_megapixels_per_second", 0.0))
	var gpu_measured := bool(gpu.get("available", false)) and peak_megapixels > 0.0

	var parts := {
		"pacing": 100.0 * normalize_log(average_fps, FPS_FLOOR, FPS_EAGLE),
		"cpu": 100.0 * normalize_log(units_per_second, CPU_FLOOR_UNITS, CPU_EAGLE_UNITS),
		"consistency": consistency_score(average_fps, one_percent_low, stutter_rate),
		"gpu": 100.0 * normalize_log(peak_megapixels, GPU_FLOOR_MEGAPIXELS, GPU_EAGLE_MEGAPIXELS),
	}
	var weighted_total := 0.0
	var weight_total := 0.0
	for key in SCORE_WEIGHTS:
		if key == "gpu" and not gpu_measured:
			continue
		var weight: float = SCORE_WEIGHTS[key]
		weighted_total += float(parts[key]) * weight
		weight_total += weight
	var overall := weighted_total / weight_total if weight_total > 0.0 else 0.0
	if sample_count <= 0 and units_per_second <= 0.0:
		overall = 0.0
	var stars := clampi(int(round(overall / 20.0)), 0, 5)
	return {
		"overall": overall,
		"stars": stars,
		"tier": tier_name(stars),
		"verdict": verdict_text(stars),
		"parts": parts,
		"gpu_measured": gpu_measured,
		"measured": sample_count > 0 or units_per_second > 0.0,
		"stutter_rate": stutter_rate,
	}

static func tier_name(stars: int) -> String:
	match stars:
		5: return "Championship"
		4: return "Tour"
		3: return "Club"
		2: return "Municipal"
		1: return "Practice Range"
		_: return "Unrated"

static func verdict_text(stars: int) -> String:
	match stars:
		5: return "Championship pace. This device carries the course with room to spare."
		4: return "Tour pace. Smooth play, with headroom for a bigger window."
		3: return "Club pace. A solid round; trim the window size if the lows dip."
		2: return "Municipal pace. Playable, but expect the odd slow frame."
		1: return "Practice range pace. Try a smaller window and fewer golfers on screen."
		_: return "Not enough of a sample to rate this device yet."

## The scorecard's golf grade for one 0-100 metric score.
static func grade_for(score: float) -> String:
	if score >= 85.0:
		return "Eagle"
	if score >= 70.0:
		return "Birdie"
	if score >= 55.0:
		return "Par"
	if score >= 35.0:
		return "Bogey"
	return "Double"

## The scorecard rows the results screen prints, in reading order. `graded`
## is false for the informational rows, which describe the scene the run
## measured rather than the device that ran it.
static func scorecard_rows(result: Dictionary) -> Array:
	var score: Dictionary = result.get("score", score_result(result))
	var parts: Dictionary = score.get("parts", {})
	var frame: Dictionary = result.get("frame", {})
	var cpu: Dictionary = result.get("cpu", {})
	var gpu: Dictionary = result.get("gpu", {})
	var engine: Dictionary = result.get("engine", {})
	var gpu_measured := bool(score.get("gpu_measured", false))
	var rows: Array = []
	rows.append({
		"key": "pacing",
		"label": "Frame pacing",
		"value": "%.1f FPS avg" % float(frame.get("average_fps", 0.0)),
		"detail": "p95 %.1f ms" % float(frame.get("p95_frame_ms", 0.0)),
		"score": float(parts.get("pacing", 0.0)),
		"graded": true,
	})
	rows.append({
		"key": "consistency",
		"label": "Consistency",
		"value": "%.1f FPS 1%% low" % float(frame.get("one_percent_low_fps", 0.0)),
		"detail": "%s frames over 33 ms" % str(frame.get("frames_over_33_ms", 0)),
		"score": float(parts.get("consistency", 0.0)),
		"graded": true,
	})
	rows.append({
		"key": "cpu",
		"label": "Script CPU",
		"value": "%s units/s" % format_integer(int(round(float(cpu.get("units_per_second", 0.0))))),
		"detail": "%s work units" % format_integer(int(cpu.get("work_units", 0))),
		"score": float(parts.get("cpu", 0.0)),
		"graded": true,
	})
	rows.append({
		"key": "gpu",
		"label": "GPU fill",
		"value": ("%.0f MPix/s" % float(gpu.get("peak_megapixels_per_second", 0.0))) \
			if gpu_measured else "Not measured",
		"detail": ("peak at %dx overdraw" % int(round(float(gpu.get("peak_overdraw", 0.0))))) \
			if gpu_measured else str(gpu.get("reason", "not run")),
		"score": float(parts.get("gpu", 0.0)),
		"graded": gpu_measured,
	})
	rows.append({
		"key": "scene",
		"label": "Scene load",
		"value": "%s nodes" % format_integer(int(engine.get("node_count", 0))),
		"detail": "%s objects | %s draw calls" % [format_integer(int(engine.get("render_objects", 0))),
			format_integer(int(engine.get("draw_calls", 0)))],
		"score": 0.0,
		"graded": false,
	})
	return rows

# =============================================================================
# THE COURSE TOUR - reducing built, played and edited courses to comparisons
# =============================================================================

## Reduce a tour's per-scenario records (CourseBenchmarkTour's shape: build
## timings, course counts, and a frame summary per prepare/camera/simulate/
## edit phase) to the rollups that say which part of the game costs what:
## generation by hole count, preparation pacing, simulation by golfer field
## and by game speed, camera against simulation, and editing throughput.
## Pure arithmetic over the records, so the maths is testable without
## building a single course.
static func summarize_tour(scenarios: Array) -> Dictionary:
	var generation := {
		"total_ms": 0.0, "average_ms": 0.0,
		"slowest_scenario": "", "slowest_ms": 0.0, "by_hole_count": [],
	}
	var sim_fps: Array[float] = []
	var camera_fps: Array[float] = []
	var prepare_fps: Array[float] = []
	var worst_fps := 0.0
	var worst_scenario := ""
	var best_fps := 0.0
	var best_scenario := ""
	var build_by_holes: Dictionary = {}
	var sim_by_golfers: Dictionary = {}
	var sim_by_speed: Dictionary = {}
	var edit_tiles := 0
	var edit_vertices := 0
	var edit_paint_ms := 0.0
	var edit_elevation_ms := 0.0
	var edit_scenarios := 0
	var totals := {"holes": 0, "buildings": 0, "decorations": 0, "path_tiles": 0,
		"golfers_spawned": 0, "visiting_spawned": 0, "terrain_patch_tiles": 0}
	for entry in scenarios:
		var scenario: Dictionary = entry
		var scenario_name := str(scenario.get("name", scenario.get("id", "Course")))
		var build: Dictionary = scenario.get("build", {})
		var build_ms := float(build.get("total_ms", 0.0))
		generation["total_ms"] = float(generation["total_ms"]) + build_ms
		if build_ms >= float(generation["slowest_ms"]):
			generation["slowest_ms"] = build_ms
			generation["slowest_scenario"] = scenario_name
		var holes := int(scenario.get("holes_built", scenario.get("holes", 0)))
		if holes > 0:
			var bucket: Dictionary = build_by_holes.get(holes, {"total": 0.0, "runs": 0})
			bucket["total"] = float(bucket["total"]) + build_ms
			bucket["runs"] = int(bucket["runs"]) + 1
			build_by_holes[holes] = bucket
		var counts: Dictionary = scenario.get("counts", {})
		totals["holes"] = int(totals["holes"]) + holes
		for key in ["buildings", "decorations", "path_tiles", "golfers_spawned",
				"visiting_spawned", "terrain_patch_tiles"]:
			totals[key] = int(totals[key]) + int(counts.get(key, 0))
		var phases: Dictionary = scenario.get("phases", {})
		var sim: Dictionary = phases.get("simulate", {})
		var fps := float(sim.get("average_fps", 0.0))
		if int(sim.get("sample_count", 0)) > 0 and fps > 0.0:
			sim_fps.append(fps)
			if worst_scenario.is_empty() or fps < worst_fps:
				worst_fps = fps
				worst_scenario = scenario_name
			if best_scenario.is_empty() or fps > best_fps:
				best_fps = fps
				best_scenario = scenario_name
			var golfers := int(counts.get("golfers_spawned", 0))
			_group_phase(sim_by_golfers, golfers, sim)
			_group_phase(sim_by_speed, int(scenario.get("speed", 1)), sim)
		var camera: Dictionary = phases.get("camera", {})
		if int(camera.get("sample_count", 0)) > 0 \
				and float(camera.get("average_fps", 0.0)) > 0.0:
			camera_fps.append(float(camera["average_fps"]))
		var prepare: Dictionary = phases.get("prepare", {})
		if int(prepare.get("sample_count", 0)) > 0 \
				and float(prepare.get("average_fps", 0.0)) > 0.0:
			prepare_fps.append(float(prepare["average_fps"]))
		var edit: Dictionary = phases.get("edit", {})
		var tiles := int(edit.get("tiles_changed", 0))
		var vertices := int(edit.get("vertices_changed", 0))
		if tiles > 0 or vertices > 0:
			edit_scenarios += 1
			edit_tiles += tiles
			edit_vertices += vertices
			edit_paint_ms += float(edit.get("paint_ms", 0.0))
			edit_elevation_ms += float(edit.get("elevation_ms", 0.0))
	if not scenarios.is_empty():
		generation["average_ms"] = float(generation["total_ms"]) / float(scenarios.size())
	var hole_rows: Array = []
	var hole_counts := build_by_holes.keys()
	hole_counts.sort()
	for holes in hole_counts:
		var bucket: Dictionary = build_by_holes[holes]
		hole_rows.append({"holes": int(holes), "runs": int(bucket["runs"]),
			"average_ms": float(bucket["total"]) / float(maxi(int(bucket["runs"]), 1))})
	generation["by_hole_count"] = hole_rows
	var sim_average := _mean(sim_fps)
	var camera_average := _mean(camera_fps)
	var edit_seconds := (edit_paint_ms + edit_elevation_ms) / 1000.0
	return {
		"scenario_count": scenarios.size(),
		"generation": generation,
		"preparation": {
			"scenarios_sampled": prepare_fps.size(),
			"average_fps": _mean(prepare_fps),
		},
		"simulation": {
			"scenarios_sampled": sim_fps.size(),
			"average_fps": sim_average,
			"worst_fps": worst_fps, "worst_scenario": worst_scenario,
			"best_fps": best_fps, "best_scenario": best_scenario,
			"by_golfer_count": _group_rows(sim_by_golfers, "golfers"),
			"by_speed": _group_rows(sim_by_speed, "speed"),
		},
		"camera": {
			"scenarios_sampled": camera_fps.size(),
			"average_fps": camera_average,
			"delta_vs_simulation_fps": camera_average - sim_average,
		},
		"editing": {
			"scenarios": edit_scenarios,
			"tiles_changed": edit_tiles,
			"vertices_changed": edit_vertices,
			"paint_ms": edit_paint_ms,
			"elevation_ms": edit_elevation_ms,
			"tiles_per_second": float(edit_tiles + edit_vertices) / edit_seconds \
				if edit_seconds > 0.0 else 0.0,
		},
		"totals": totals,
	}

## Fold one phase summary into a grouping bucket (golfer fields, speeds).
static func _group_phase(groups: Dictionary, key: int, phase: Dictionary) -> void:
	var bucket: Dictionary = groups.get(key, {"fps": 0.0, "process": 0.0,
		"days": 0.0, "seconds": 0.0, "runs": 0})
	bucket["fps"] = float(bucket["fps"]) + float(phase.get("average_fps", 0.0))
	bucket["process"] = float(bucket["process"]) \
		+ float(phase.get("process_ms_per_frame", 0.0))
	bucket["days"] = float(bucket["days"]) + float(phase.get("days_advanced", 0.0))
	bucket["seconds"] = float(bucket["seconds"]) + float(phase.get("sample_seconds", 0.0))
	bucket["runs"] = int(bucket["runs"]) + 1
	groups[key] = bucket

## Grouping buckets as sorted report rows: average FPS, script time and, for
## the speed groups, how many game days a real second bought.
static func _group_rows(groups: Dictionary, key_name: String) -> Array:
	var rows: Array = []
	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var bucket: Dictionary = groups[key]
		var runs := maxi(int(bucket["runs"]), 1)
		var seconds := float(bucket["seconds"])
		rows.append({
			key_name: int(key), "runs": int(bucket["runs"]),
			"average_fps": float(bucket["fps"]) / float(runs),
			"process_ms_per_frame": float(bucket["process"]) / float(runs),
			"days_per_second": float(bucket["days"]) / seconds if seconds > 0.0 else 0.0,
		})
	return rows

static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

## One results-table row per toured course: what it was, what building it
## cost, and how its camera, simulation and editing phases ran. Both the
## results screen and the plain-text report print from these rows so the two
## can never disagree about a course.
static func tour_scenario_rows(result: Dictionary) -> Array:
	var tour: Dictionary = result.get("tour", {})
	var rows: Array = []
	for entry in tour.get("scenarios", []):
		var scenario: Dictionary = entry
		var phases: Dictionary = scenario.get("phases", {})
		var prepare: Dictionary = phases.get("prepare", {})
		var sim: Dictionary = phases.get("simulate", {})
		var camera: Dictionary = phases.get("camera", {})
		var edit: Dictionary = phases.get("edit", {})
		var counts: Dictionary = scenario.get("counts", {})
		var edit_text := "no editing"
		var tiles := int(edit.get("tiles_changed", 0)) + int(edit.get("vertices_changed", 0))
		if tiles > 0:
			edit_text = "%s tiles/vertices" % format_integer(tiles)
		rows.append({
			"id": str(scenario.get("id", "")),
			"name": str(scenario.get("name", "Course")),
			"detail": str(scenario.get("description", "")),
			"build_ms": float(scenario.get("build", {}).get("total_ms", 0.0)),
			"holes": int(scenario.get("holes_built", scenario.get("holes", 0))),
			"golfers": int(counts.get("golfers_spawned", 0)),
			"visiting": int(counts.get("visiting_spawned", 0)),
			"prepare_fps": float(prepare.get("average_fps", 0.0)),
			"sim_fps": float(sim.get("average_fps", 0.0)),
			"sim_low_fps": float(sim.get("one_percent_low_fps", 0.0)),
			"sim_process_ms": float(sim.get("process_ms_per_frame", 0.0)),
			"camera_fps": float(camera.get("average_fps", 0.0)),
			"edit_text": edit_text,
			"edit_tiles": tiles,
		})
	return rows

## The tour section of the plain-text report.
static func _tour_report_lines(result: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var tour: Dictionary = result.get("tour", {})
	if tour.is_empty():
		return lines
	var rollup: Dictionary = tour.get("rollup", {})
	if rollup.is_empty():
		rollup = summarize_tour(tour.get("scenarios", []))
	var generation: Dictionary = rollup.get("generation", {})
	var preparation: Dictionary = rollup.get("preparation", {})
	var prepare: Dictionary = tour.get("prepare", {})
	var simulation: Dictionary = rollup.get("simulation", {})
	var editing: Dictionary = rollup.get("editing", {})
	var totals: Dictionary = rollup.get("totals", {})
	if bool(prepare.get("prepared", false)):
		lines.append("Course tour %s: benchmark course prepared in %.0f ms | %d courses built on screen in %.0f ms total (slowest %s, %.0f ms) | main menu restored: %s" % [
			str(tour.get("suite_name", tour.get("suite", "tour"))),
			float(prepare.get("prepare_ms", 0.0)),
			int(rollup.get("scenario_count", 0)),
			float(generation.get("total_ms", 0.0)),
			str(generation.get("slowest_scenario", "-")),
			float(generation.get("slowest_ms", 0.0)),
			"yes" if bool(tour.get("restored", false)) else "no",
		])
	else:
		lines.append("Course tour %s: %d courses built on screen in %.0f ms total (slowest %s, %.0f ms) | player's course restored: %s" % [
			str(tour.get("suite_name", tour.get("suite", "tour"))),
			int(rollup.get("scenario_count", 0)),
			float(generation.get("total_ms", 0.0)),
			str(generation.get("slowest_scenario", "-")),
			float(generation.get("slowest_ms", 0.0)),
			"yes" if bool(tour.get("restored", false)) else "no",
		])
	if int(preparation.get("scenarios_sampled", 0)) > 0:
		lines.append("Course preparation (building and settling each course): %.1f FPS average across %d courses, pooled into the frame pacing below" % [
			float(preparation.get("average_fps", 0.0)),
			int(preparation["scenarios_sampled"]),
		])
	var index := 1
	for row in tour_scenario_rows(result):
		var entry: Dictionary = row
		lines.append("  %2d. %-34s build %5.0f ms | sim %5.1f FPS (1%% low %4.1f, script %.1f ms) | camera %5.1f FPS | %s" % [
			index, str(entry["name"]), float(entry["build_ms"]),
			float(entry["sim_fps"]), float(entry["sim_low_fps"]),
			float(entry["sim_process_ms"]), float(entry["camera_fps"]),
			str(entry["edit_text"]),
		])
		index += 1
	var by_golfers := PackedStringArray()
	for group in simulation.get("by_golfer_count", []):
		var entry: Dictionary = group
		by_golfers.append("%d golfers: %.1f FPS" % [int(entry.get("golfers", 0)),
			float(entry.get("average_fps", 0.0))])
	if not by_golfers.is_empty():
		lines.append("Simulation by field | " + " | ".join(by_golfers))
	var by_speed := PackedStringArray()
	for group in simulation.get("by_speed", []):
		var entry: Dictionary = group
		by_speed.append("%s: %.1f FPS, %.2f game-days/s" % [
			CourseBenchmarkScenarios.speed_name(int(entry.get("speed", 1))),
			float(entry.get("average_fps", 0.0)),
			float(entry.get("days_per_second", 0.0))])
	if not by_speed.is_empty():
		lines.append("Simulation by speed | " + " | ".join(by_speed))
	if int(editing.get("tiles_changed", 0)) + int(editing.get("vertices_changed", 0)) > 0:
		lines.append("Terrain editing: %s tiles and %s vertices in %.0f ms of brush work (%.0f tiles/vertices per second)" % [
			format_integer(int(editing.get("tiles_changed", 0))),
			format_integer(int(editing.get("vertices_changed", 0))),
			float(editing.get("paint_ms", 0.0)) + float(editing.get("elevation_ms", 0.0)),
			float(editing.get("tiles_per_second", 0.0)),
		])
	lines.append("Toured totals: %d holes | %d buildings | %d decorations | %s path tiles | %d golfers (%d visiting)" % [
		int(totals.get("holes", 0)), int(totals.get("buildings", 0)),
		int(totals.get("decorations", 0)),
		format_integer(int(totals.get("path_tiles", 0))),
		int(totals.get("golfers_spawned", 0)), int(totals.get("visiting_spawned", 0)),
	])
	if not str(simulation.get("worst_scenario", "")).is_empty():
		lines.append("Heaviest course to simulate: %s at %.1f FPS" % [
			str(simulation["worst_scenario"]), float(simulation.get("worst_fps", 0.0))])
	return lines

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
	var gpu: Dictionary = result.get("gpu", {})
	var engine: Dictionary = result.get("engine", {})
	var memory: Dictionary = result.get("memory", {})
	var context: Dictionary = result.get("context", {})
	var score: Dictionary = result.get("score", score_result(result))
	var lines := PackedStringArray()
	lines.append("Golf Tycoon benchmark %s" % str(result.get("benchmark_version", BENCHMARK_VERSION)))
	lines.append("Game %s | Godot %s | %s build" % [str(result.get("game_version", "Unknown")),
		str(result.get("engine_version", "Unknown")), str(result.get("build_type", "Unknown"))])
	lines.append("Device %s | %s" % [str(result.get("device_model", "Unknown model")),
		str(result.get("platform", "Unknown platform"))])
	lines.append("OS %s | CPU %s (%s logical cores)" % [str(result.get("os_version", "Unknown version")),
		str(result.get("cpu_name", "Unknown CPU")), str(result.get("cpu_cores", "?"))])
	lines.append("GPU %s | Renderer %s | Display %s" % [str(result.get("gpu_name", "Unknown")),
		str(result.get("renderer", "Unknown")), str(result.get("display_server", "Unknown"))])
	lines.append("Resolution %s | VSync %s | FPS cap %s" % [str(result.get("resolution", "Unknown")),
		str(result.get("vsync", "Unknown")), _fps_cap_label(int(result.get("max_fps", 0)))])
	var scenario := str(context.get("scenario", "Unknown scene"))
	if context.has("day") and context["day"] != null:
		scenario += " | day %s" % str(context["day"])
	lines.append("Scene %s | %s nodes | %s render objects | %s primitives" % [scenario,
		str(engine.get("node_count", 0)), str(engine.get("render_objects", 0)),
		str(engine.get("render_primitives", 0))])
	# A tour report names every course it built; the frame pacing below it is
	# the pooled preparation, camera and simulation sample across all of them.
	lines.append_array(_tour_report_lines(result))
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
	if bool(gpu.get("available", false)):
		lines.append("GPU fill test: %.0f MPix/s peak at %dx overdraw | %.2f ms render per frame" % [
			float(gpu.get("peak_megapixels_per_second", 0.0)),
			int(round(float(gpu.get("peak_overdraw", 0.0)))),
			float(gpu.get("gpu_ms_per_frame", 0.0)),
		])
		var ladder_text := PackedStringArray()
		for step in gpu.get("levels", []):
			var entry: Dictionary = step
			ladder_text.append("%dx: %.0f MPix/s @ %.0f FPS%s" % [
				int(round(float(entry.get("overdraw", 0.0)))),
				float(entry.get("megapixels_per_second", 0.0)),
				float(entry.get("fps", 0.0)),
				" (capped)" if bool(entry.get("capped", false)) else "",
			])
		if not ladder_text.is_empty():
			lines.append("GPU load ladder | " + " | ".join(ladder_text))
	else:
		lines.append("GPU fill test: skipped (%s)" % str(gpu.get("reason", "not available")))
	lines.append("CPU script score: %s work units/s (higher is faster; compare %s reports)" % [
		format_integer(int(round(float(cpu.get("units_per_second", 0.0))))), BENCHMARK_VERSION])
	lines.append("Memory: %.0f MB static | %.0f MB video | %.0f MB textures" % [
		float(memory.get("static_mb", 0.0)), float(memory.get("video_mb", 0.0)),
		float(memory.get("texture_mb", 0.0)),
	])
	lines.append("Device rating: %s (%s) | %s" % [
		"%d/5 stars" % int(score.get("stars", 0)), str(score.get("tier", "Unrated")),
		str(score.get("verdict", "")),
	])
	for row in scorecard_rows(result):
		var entry: Dictionary = row
		if bool(entry.get("graded", false)):
			lines.append("  %-14s %-22s %3d/100  %s" % [str(entry["label"]), str(entry["value"]),
				int(round(float(entry["score"]))), grade_for(float(entry["score"]))])
		else:
			lines.append("  %-14s %-22s %s" % [str(entry["label"]), str(entry["value"]),
				str(entry["detail"])])
	lines.append("")
	if result.has("tour"):
		lines.append("For fair comparisons, run the tour from Main Menu Settings at the same resolution, VSync and power mode; the benchmark prepares its own throwaway course, and the preparation, courses, seeds, golfers and camera moves are fixed.")
	else:
		lines.append("For fair comparisons, use the same course/save, camera view, resolution, VSync and power mode.")
	lines.append("Frame pacing and the GPU fill test measure this machine; the CPU score is a fixed script workload.")
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

func _minimum(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var lowest := values[0]
	for value in values:
		lowest = minf(lowest, value)
	return lowest

func _maximum(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var highest := values[0]
	for value in values:
		highest = maxf(highest, value)
	return highest

static func _fallback(value: String, fallback: String) -> String:
	return fallback if value.strip_edges().is_empty() else value

static func _fps_cap_label(max_fps: int) -> String:
	return "Unlimited" if max_fps <= 0 else "%d FPS" % max_fps

# =============================================================================
# THE GPU TEST'S CANVAS
# =============================================================================

## The fill the GPU test draws: a hard-edged weave of big tiles that covers the
## window `overdraw` times over. Big tiles keep the per-quad CPU cost small
## next to the pixels they fill, so what the frame rate loses is the renderer's
## share, not the script's.
class GpuStressCanvas extends Control:
	## The weave's own palette: four opaque greens and a gold thread, so the
	## test looks like a piece of the game rather than a glitch.
	const WEAVE_COLORS: Array[Color] = [
		Color("0b2a1e"), Color("14492f"), Color("1d6b41"), Color("2f8f57"),
	]
	const THREAD_COLOR := Color("e5c57c")
	## The game's own pixel typeface and gold, for the test's caption.
	const CAPTION_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
	const CAPTION_COLOR := Color("e5c57c")

	var tile_side: int = 256
	var overdraw: float = 1.0
	## The area the fill covers. Left at zero it follows the viewport, which is
	## what the benchmark leaves it at between runs.
	var fill_size: Vector2 = Vector2.ZERO
	var _texture: Texture2D = null

	func _init(p_tile_side: int = 256) -> void:
		tile_side = maxi(p_tile_side, 32)
		name = "GpuStressCanvas"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)

	## The rectangle the weave covers: `fill_size` when it was given one, the
	## viewport otherwise.
	func covered_size() -> Vector2:
		if fill_size.x > 1.0 and fill_size.y > 1.0:
			return fill_size
		if is_inside_tree() and get_viewport() != null:
			return get_viewport().get_visible_rect().size
		return Vector2(1600.0, 1000.0)

	## A tile side that keeps the quad count in the hundreds rather than the
	## tens of thousands: a quarter of the shorter window edge, in whole pixels.
	static func tile_side_for(viewport_size: Vector2) -> int:
		var shortest := minf(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
		return int(clampf(floorf(shortest * 0.25), 96.0, 512.0))

	func set_load(p_overdraw: float) -> void:
		overdraw = maxf(p_overdraw, 0.25)
		queue_redraw()

	## Pixels the canvas paints in one frame at the current load.
	func total_fill_pixels() -> int:
		return quad_count() * tile_side * tile_side

	func quad_count() -> int:
		var covered := covered_size()
		var viewport_area := maxf(covered.x, 1.0) * maxf(covered.y, 1.0)
		var tile_area := float(tile_side * tile_side)
		return maxi(1, int(ceilf(viewport_area * overdraw / tile_area)))

	func _draw() -> void:
		var covered := covered_size()
		if covered.x <= 1.0 or covered.y <= 1.0:
			return
		if _texture == null:
			_texture = ImageTexture.create_from_image(weave_image())
		# Opaque base, so the fill cost is the same whatever sits behind it.
		draw_rect(Rect2(Vector2.ZERO, covered), WEAVE_COLORS[0])
		var total := quad_count()
		var columns := maxi(1, int(ceilf(covered.x / float(tile_side))))
		var rows := maxi(1, int(ceilf(covered.y / float(tile_side))))
		for index in range(total):
			var column := index % columns
			var row := floori(float(index) / float(columns)) % rows
			var rect := Rect2(Vector2(column * tile_side, row * tile_side),
				Vector2(tile_side, tile_side))
			var tone := WEAVE_COLORS[(index + row) % WEAVE_COLORS.size()]
			draw_texture_rect(_texture, rect, false, tone)
		_draw_caption()

	func _draw_caption() -> void:
		var font := CAPTION_FONT
		var caption := "GPU FILL TEST - %dx OVERDRAW" % int(round(overdraw))
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		var origin := Vector2(12.0, 26.0)
		draw_rect(Rect2(origin - Vector2(8, 18), text_size + Vector2(16, 12)),
			Color(0.02, 0.06, 0.04, 0.85))
		draw_string(font, origin, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CAPTION_COLOR)

	## The 32x32 weave tile: a hard-edged dither of the palette greens with a
	## gold thread through it. Nearest filtering keeps every pixel square when
	## the tile is stretched across the window.
	static func weave_image() -> Image:
		var image := Image.create(GPU_TEXTURE_GRID, GPU_TEXTURE_GRID, false, Image.FORMAT_RGBA8)
		for y in range(GPU_TEXTURE_GRID):
			for x in range(GPU_TEXTURE_GRID):
				# Which 8-pixel cell the pixel sits in, for the checker.
				var checker := ((x >> 3) + (y >> 3)) % 2
				var tone := WEAVE_COLORS[1 + checker]
				if (x + y) % 8 == 0:
					tone = WEAVE_COLORS[3]
				if x == y or x == GPU_TEXTURE_GRID - 1 - y:
					tone = THREAD_COLOR
				if (x % 16 < 2) or (y % 16 < 2):
					tone = WEAVE_COLORS[0]
				image.set_pixel(x, y, tone)
		return image
