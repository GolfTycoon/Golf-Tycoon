extends Node
class_name CourseBenchmarkTour
## CourseBenchmarkTour - builds and plays the benchmark course matrix on
## screen, one course at a time, and times every part of it.
##
## The tour runs from the Main Menu (Main only starts it from Main Menu
## Settings), where no game is open, so before the first scenario it:
##
##  0. PREPARE - makes the throwaway course session the tour builds on: a
##     fresh course record, cleared ground, the land the layouts need, and
##     the camera over the site. Preparation is part of the benchmark - it
##     is timed step by step and its frames are sampled into the headline
##     pacing, exactly like each course's own build-and-settle (recorded
##     per course as the "prepare" phase).
##
## For each scenario in CourseBenchmarkScenarios the tour then, live on the
## course view:
##
##  1. BUILD - resets to bare land, sets the course type (theme), generates
##     natural terrain from the scenario seed, lays out its holes, stamps
##     its terrain-type patches, places the clubhouse, its buildings and
##     decorations, lays the walking-path network, and spawns its field of
##     golfers (asking the visiting-golfer pool for its share first). Every
##     stage is timed and runs on its own frame, so the course visibly grows.
##     The frames of the build and the settle that follows it are sampled
##     as the course's preparation phase and pooled into the headline
##     frame pacing: preparing a course is part of what is being measured.
##  2. CAMERA - drives the scenario's camera plan (still / pan / zoom / a
##     tour of the tees and greens / a tour with a view rotation) while the
##     frame times are sampled.
##  3. SIMULATE - lets the golfers play at the scenario's game speed while
##     frame, script and physics times are sampled.
##  4. EDIT - paints terrain brush stamps, lays Path improvements and
##     sculpts elevation with the player's own tools on a sacrificial
##     patch, timing the brush work itself.
##  5. DEVICE - finishes with the quick device check (PerformanceBenchmark:
##     GPU fill ladder and fixed CPU workload) on the last course built.
##
## Nothing real is ever at risk. From the Main Menu there is no course to
## borrow: the tour prepares its own throwaway session and ends - finish or
## cancel alike - by tearing it down and handing the title screen back as
## empty as it found it. Driven directly on an open course (tests and
## harnesses), it instead captures the whole game as in-memory save data
## (SaveManager.capture_course_snapshot) and restores that snapshot. Either
## way it runs under benchmark suppression (no autosave, no milestone or
## achievement progress, unlimited funds so a tour cannot bankrupt the
## company) and returns the captured camera, speed and pause state.

signal progress_changed(status: Dictionary)
signal completed(result: Dictionary)
signal cancelled(result: Dictionary)

enum Phase { IDLE, PREPARE, BUILD, SETTLE, CAMERA, SIMULATE, EDIT, DEVICE, RESTORE }

## A fixed mid-summer day for every toured course, so seasons and the
## calendar cost the same on every machine. Day 152 is 1 June 2000.
const BENCHMARK_DAY := 152
## Build stages, one per frame so each paints before the next begins.
const BUILD_STAGES: Array[String] = ["reset", "natural", "holes", "terrain",
	"buildings", "paths", "spawn"]
const STAGE_LABELS := {
	"reset": "Clearing the land", "natural": "Generating natural terrain",
	"holes": "Laying out holes", "terrain": "Stamping terrain types",
	"buildings": "Placing buildings & improvements",
	"paths": "Laying walking paths", "spawn": "Sending out the golfers",
}
## Preparing the throwaway course from the Main Menu, one step per frame
## like the build stages, each timed into the run's prepare record.
const PREPARE_STEPS: Array[String] = ["session", "ground", "land", "camera"]
const PREPARE_LABELS := {
	"session": "Opening the benchmark course", "ground": "Clearing the ground",
	"land": "Granting the land", "camera": "Framing the course",
}
## Brush stamps an edit plan paints before its phase ends.
const EDIT_STAMP_BUDGETS := {"paint": 110, "elevation": 70, "both": 130, "stress": 280}
## Ground a tour may not repaint or build over: the playing line itself.
const PLAYING_TERRAINS: Array[int] = [
	TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY,
	TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX,
]

## Public durations keep the whole tour fast to exercise in tests, exactly
## like PerformanceBenchmark's.
var settle_duration_usec: int = 500_000
var camera_duration_usec: int = 2_200_000
var simulate_duration_usec: int = 2_800_000
var edit_stamps_per_frame: int = 5
## Cap on an edit phase's stamps (tests); -1 uses the plan's full budget.
var edit_max_stamps: int = -1
## Whether the tour ends with the GPU/CPU device check.
var run_device_check: bool = true
## Whether a finished tour is appended to the local history shelf.
var record_history: bool = true
## A sampled phase never ends empty-handed: on a very slow device one long
## frame could eat the whole phase budget, so the phase runs on until it
## holds at least this many frame samples (with a hard overrun cap so a
## slideshow cannot stall the tour forever).
const MIN_PHASE_SAMPLES := 10
const PHASE_OVERRUN_USEC := 10_000_000

var _grid: TerrainGrid = null
var _camera: IsometricCamera = null
var _entities: EntityLayer = null
var _hole_tool: HoleCreationTool = null
var _golfers: GolferManager = null
var _hole_manager: HoleManager = null
var _ball_manager: BallManager = null
var _host: Node = null

var _device_runner: PerformanceBenchmark = null
var _elevation_tool: ElevationTool = null
var _overlay: BenchmarkTourOverlay = null

var _phase: int = Phase.IDLE
var _suite_id: String = ""
var _suite_name: String = ""
var _scenarios: Array = []
var _scenario_index: int = 0
var _scenario: Dictionary = {}
var _current: Dictionary = {}
var _records: Array = []
var _build_stage: int = 0
var _phase_started_usec: int = 0
var _started_usec: int = 0
var _started_unix: int = 0
var _last_frame_usec: int = 0
var _last_publish_usec: int = 0
var _phase_start_day: int = 0
var _phase_start_day_progress: float = 0.0
var _frame_ms: Array[float] = []
var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _tour_frame_ms: Array[float] = []
var _tour_process_ms: Array[float] = []
var _tour_physics_ms: Array[float] = []
var _tour_sample_seconds: float = 0.0
var _waypoints: Array = []
var _rotated: bool = false
var _edit_points: Array[Vector2i] = []
var _edit_done: int = 0
var _edit_budget: int = 0
var _edit_paint_usec: int = 0
var _edit_elevation_usec: int = 0
var _edit_tiles: int = 0
var _edit_vertices: int = 0
var _edit_paths: int = 0
var _snapshot: Dictionary = {}
var _captured: Dictionary = {}
## True when the tour prepared its own throwaway course because none was
## open (the Main Menu run); false when it borrowed the player's course.
var _prepared_course: bool = false
var _prepare_step: int = 0
var _prepare_steps_ms: Dictionary = {}
var _prepare_record: Dictionary = {}
## When the current scenario's build-and-settle sampling began.
var _scenario_started_usec: int = 0
var _device_result: Dictionary = {}
var _buildings_data: Dictionary = {}
var _decorations_data: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_device_runner = PerformanceBenchmark.new()
	_device_runner.name = "TourDeviceCheck"
	_device_runner.record_history = false
	_device_runner.progress_changed.connect(_on_device_progress)
	_device_runner.completed.connect(_on_device_completed)
	add_child(_device_runner)
	_elevation_tool = ElevationTool.new()
	_elevation_tool.name = "TourElevationTool"
	add_child(_elevation_tool)

## The device-check runner, exposed so tests can shorten its phases.
func device_runner() -> PerformanceBenchmark:
	return _device_runner

func setup(grid: TerrainGrid, camera: IsometricCamera, entities: EntityLayer,
		hole_tool: HoleCreationTool, golfers: GolferManager,
		holes: HoleManager, balls: BallManager, host: Node = null) -> void:
	_grid = grid
	_camera = camera
	_entities = entities
	_hole_tool = hole_tool
	_golfers = golfers
	_hole_manager = holes
	_ball_manager = balls
	_host = host

func is_running() -> bool:
	return _phase != Phase.IDLE

## Roughly how long a suite takes at the current durations, for the menus.
func estimated_seconds(suite_id: String) -> int:
	var scenarios: Array = CourseBenchmarkScenarios.suite_by_id(suite_id).get("scenarios", [])
	var per_course := (float(settle_duration_usec + camera_duration_usec
		+ simulate_duration_usec) / 1_000_000.0) + 2.5
	var prepare_allowance := 2 if GameManager.current_course == null else 0
	return int(round(per_course * float(scenarios.size()))) + prepare_allowance \
		+ (7 if run_device_check else 0)

func start(suite_id: String) -> bool:
	var suite := CourseBenchmarkScenarios.suite_by_id(suite_id)
	return start_scenarios(suite.get("scenarios", []), str(suite.get("id", suite_id)),
		str(suite.get("name", "Course tour")))

## Run an explicit scenario list (the suites, or a test's miniature tour).
## Returns false without touching anything when the tour cannot start.
func start_scenarios(scenarios: Array, suite_id: String, suite_name: String) -> bool:
	if is_running() or scenarios.is_empty():
		return false
	if _grid == null or _camera == null or _entities == null or _hole_tool == null \
			or _golfers == null:
		return false
	# With no course open - the Main Menu - the tour prepares its own
	# throwaway course as its first, timed phase. With one open it borrows
	# it under a snapshot, and timing that snapshot is its preparation.
	_prepared_course = GameManager.current_course == null
	_prepare_record = {}
	_prepare_steps_ms = {}
	_prepare_step = 0
	_snapshot = {}
	if not _prepared_course:
		var snapshot_started := Time.get_ticks_usec()
		_snapshot = SaveManager.capture_course_snapshot()
		if _snapshot.is_empty():
			return false
		_prepare_record = {
			"prepared": false,
			"prepare_ms": float(Time.get_ticks_usec() - snapshot_started) / 1000.0,
			"steps_ms": {},
		}
	_scenarios = scenarios.duplicate(true)
	_suite_id = suite_id
	_suite_name = suite_name
	_records.clear()
	_tour_frame_ms.clear()
	_tour_process_ms.clear()
	_tour_physics_ms.clear()
	_tour_sample_seconds = 0.0
	_device_result = {}
	_scenario_index = 0
	_started_usec = Time.get_ticks_usec()
	_started_unix = int(Time.get_unix_time_from_system())
	_capture_session()
	# From here to the restore, nothing the tour does may persist: no
	# autosave of a benchmark course, no goals earned by benchmark play,
	# and no bankruptcy when Ultra speed chews through the days.
	SaveManager.benchmark_suppression = true
	GameManager.unlimited_money = true
	GameManager.is_paused = false
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	if _golfers != null:
		_golfers.min_spawn_cooldown_seconds = 1_000_000_000.0
		_golfers.time_since_last_spawn = 0.0
	_camera.benchmark_controlled = true
	_set_host_undo_suppressed(true)
	_show_overlay()
	set_process(true)
	if _prepared_course:
		_begin_prepare()
	else:
		_begin_scenario()
	return true

func cancel() -> void:
	if not is_running() or _phase == Phase.RESTORE:
		return
	_finish_tour(true)

func _capture_session() -> void:
	_captured = {
		"camera_position": _camera.global_position,
		"camera_zoom": _camera.get_zoom_level(),
		"speed": int(GameManager.current_speed),
		"paused": GameManager.is_paused,
		"unlimited_money": GameManager.unlimited_money,
		"spawn_cooldown": _golfers.min_spawn_cooldown_seconds if _golfers else 90.0,
		"achievements": AchievementStore.load_state(),
		# The title-screen scalars a prepared tour hands back when it tears
		# its throwaway course down (a borrowed course returns by snapshot).
		"mode": int(GameManager.current_mode),
		"course_name": GameManager.course_name,
		"theme": int(GameManager.current_theme),
		"day": GameManager.current_day,
		"money": GameManager.money,
		"reputation": GameManager.reputation,
		"green_fee": GameManager.green_fee,
		"land": GameManager.land_manager.serialize() \
			if GameManager.land_manager != null else {},
	}

func _set_host_undo_suppressed(suppressed: bool) -> void:
	# The tour's thousand tile edits are not the player's stroke history.
	if _host != null and _host.get("_suppress_tile_undo") != null:
		_host.set("_suppress_tile_undo", suppressed)

func _show_overlay() -> void:
	_overlay = BenchmarkTourOverlay.new()
	_overlay.cancel_requested.connect(cancel)
	add_child(_overlay)

# =============================================================================
# THE STATE MACHINE
# =============================================================================

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	match _phase:
		Phase.PREPARE:
			_sample_frame(now)
			_process_prepare_step(now)
		Phase.BUILD:
			# Preparing this course is part of the benchmark: the frames of
			# the build (and the settle after it) are sampled like any
			# other phase and pooled into the headline pacing.
			_sample_frame(now)
			_process_build_stage()
		Phase.SETTLE:
			_sample_frame(now)
			if now - _phase_started_usec >= settle_duration_usec:
				_finish_timed_phase("prepare", now, true, _scenario_started_usec)
				_begin_timed_phase(Phase.CAMERA, now)
				_build_waypoints()
			else:
				_publish("Letting the course settle", now)
		Phase.CAMERA:
			_sample_frame(now)
			_drive_camera(now)
			if _timed_phase_done(now, camera_duration_usec):
				_finish_timed_phase("camera", now, true)
				_restore_orientation()
				_begin_timed_phase(Phase.SIMULATE, now)
			else:
				_publish("Camera: %s" % str(_scenario.get("camera", "tour")), now)
		Phase.SIMULATE:
			_sample_frame(now)
			_enforce_speed()
			if _timed_phase_done(now, simulate_duration_usec):
				_finish_timed_phase("simulate", now, true)
				if _begin_edit(now):
					pass
				else:
					_next_scenario()
			else:
				_publish("Simulating at %s" % CourseBenchmarkScenarios.speed_name(
					int(_scenario.get("speed", 1))), now)
		Phase.EDIT:
			_sample_frame(now)
			_edit_stamps()
			if _edit_done >= _edit_budget:
				_finish_timed_phase("edit", now, false)
				_next_scenario()
			else:
				_publish("Editing terrain: %s (%d/%d stamps)" % [
					str(_scenario.get("edit", "")), _edit_done, _edit_budget], now)
		Phase.DEVICE, Phase.RESTORE:
			pass

func _begin_scenario() -> void:
	_scenario = _scenarios[_scenario_index]
	seed(int(_scenario.get("seed", 1)))
	_current = {
		"id": str(_scenario.get("id", "")),
		"name": str(_scenario.get("name", "Course")),
		"description": CourseBenchmarkScenarios.describe(_scenario),
		"theme": int(_scenario.get("theme", 0)),
		"theme_name": CourseBenchmarkScenarios.theme_name(_scenario),
		"layout": str(_scenario.get("layout", "generated")),
		"holes": int(_scenario.get("holes", 0)),
		"holes_built": 0,
		"seed": int(_scenario.get("seed", 0)),
		"terrain_patch_names": CourseBenchmarkScenarios.terrain_patch_names(_scenario),
		"speed": int(_scenario.get("speed", GameManager.GameSpeed.NORMAL)),
		"speed_name": CourseBenchmarkScenarios.speed_name(
			int(_scenario.get("speed", 1))),
		"camera": str(_scenario.get("camera", "tour")),
		"edit": str(_scenario.get("edit", "none")),
		"weather_applied": "clear",
		"build": {},
		"counts": {"buildings": 0, "decorations": 0, "path_tiles": 0,
			"golfers_spawned": 0, "visiting_spawned": 0, "terrain_patch_tiles": 0},
		"phases": {},
	}
	_build_stage = 0
	_rotated = false
	_phase = Phase.BUILD
	# A fresh frame collection for the preparation sample (build + settle).
	# _phase_started_usec still marks the settle's start when the build
	# completes, so the collection's own start is kept separately.
	_scenario_started_usec = Time.get_ticks_usec()
	_last_frame_usec = 0
	_frame_ms.clear()
	_process_ms.clear()
	_physics_ms.clear()
	_phase_start_day = GameManager.current_day
	_phase_start_day_progress = GameManager._day_progress
	_publish("Building the course", _scenario_started_usec, true)

func _next_scenario() -> void:
	_records.append(_current)
	_current = {}
	_scenario_index += 1
	if _scenario_index >= _scenarios.size():
		_begin_device_phase()
	else:
		_begin_scenario()

## A timed phase is done when its budget has elapsed AND it holds enough
## frame samples to summarize - or when the overrun cap says the device is
## too slow to wait for them.
func _timed_phase_done(now: int, duration_usec: int) -> bool:
	var elapsed := now - _phase_started_usec
	if elapsed < duration_usec:
		return false
	return _frame_ms.size() >= MIN_PHASE_SAMPLES \
		or elapsed >= duration_usec + PHASE_OVERRUN_USEC

func _begin_timed_phase(phase: int, now: int) -> void:
	_phase = phase
	_phase_started_usec = now
	_last_frame_usec = 0
	_frame_ms.clear()
	_process_ms.clear()
	_physics_ms.clear()
	_phase_start_day = GameManager.current_day
	_phase_start_day_progress = GameManager._day_progress
	_last_publish_usec = 0

## One frame's wall-clock timing, exactly as PerformanceBenchmark samples:
## the engine's scaled delta would lie at Fast and Ultra speeds.
func _sample_frame(now: int) -> void:
	if _last_frame_usec <= 0:
		_last_frame_usec = now
		return
	var frame_ms := float(now - _last_frame_usec) / 1000.0
	_last_frame_usec = now
	if frame_ms <= 0.0 or frame_ms > 2000.0:
		return
	_frame_ms.append(frame_ms)
	_process_ms.append(maxf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.0))
	_physics_ms.append(maxf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.0))

func _finish_timed_phase(key: String, now: int, pool: bool,
		started_usec: int = 0) -> void:
	var summary := PerformanceBenchmark.summarize_frame_times(_frame_ms)
	summary["series_ms"] = PerformanceBenchmark.downsample_series(_frame_ms, 60)
	summary["worst_frame_ms"] = _frame_ms.max() if not _frame_ms.is_empty() else 0.0
	summary["process_ms_per_frame"] = _average_of(_process_ms)
	summary["physics_ms_per_frame"] = _average_of(_physics_ms)
	summary["sample_seconds"] = float(now - (started_usec if started_usec > 0 \
		else _phase_started_usec)) / 1_000_000.0
	summary["days_advanced"] = float(GameManager.current_day - _phase_start_day) \
		+ (GameManager._day_progress - _phase_start_day_progress) \
		/ GameManager.SECONDS_PER_GAME_DAY
	summary["render_objects"] = maxi(int(Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), 0)
	summary["draw_calls"] = maxi(int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), 0)
	summary["node_count"] = maxi(int(Performance.get_monitor(
		Performance.OBJECT_NODE_COUNT)), 0)
	if key == "edit":
		summary["tiles_changed"] = _edit_tiles
		summary["vertices_changed"] = _edit_vertices
		summary["path_tiles"] = _edit_paths
		summary["stamps"] = _edit_done
		summary["paint_ms"] = float(_edit_paint_usec) / 1000.0
		summary["elevation_ms"] = float(_edit_elevation_usec) / 1000.0
	var phases: Dictionary = _current.get("phases", {})
	phases[key] = summary
	_current["phases"] = phases
	if pool:
		_tour_frame_ms.append_array(_frame_ms)
		_tour_process_ms.append_array(_process_ms)
		_tour_physics_ms.append_array(_physics_ms)
		_tour_sample_seconds += float(summary["sample_seconds"])

static func _average_of(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

func _enforce_speed() -> void:
	var wanted := int(_scenario.get("speed", GameManager.GameSpeed.NORMAL))
	if int(GameManager.current_speed) != wanted or GameManager.is_paused:
		GameManager.is_paused = false
		GameManager.set_speed(wanted as GameManager.GameSpeed)

# =============================================================================
# PREPARE - the throwaway course a Main Menu tour builds on, timed & sampled
# =============================================================================

func _begin_prepare() -> void:
	_scenario = _scenarios[0]
	_prepare_step = 0
	_prepare_steps_ms = {}
	_begin_timed_phase(Phase.PREPARE, Time.get_ticks_usec())
	_publish("Preparing the benchmark course", Time.get_ticks_usec(), true)

func _process_prepare_step(now: int) -> void:
	if _prepare_step >= PREPARE_STEPS.size():
		_finish_prepare(now)
		return
	var step := PREPARE_STEPS[_prepare_step]
	_publish("Preparing the benchmark course: %s" % str(PREPARE_LABELS.get(step, step)),
		now, true)
	var started := Time.get_ticks_usec()
	match step:
		"session": _prepare_session()
		"ground": _prepare_ground()
		"land": _prepare_land()
		"camera": _prepare_camera()
	_prepare_steps_ms["%s_ms" % step] = float(Time.get_ticks_usec() - started) / 1000.0
	_prepare_step += 1

## The session a new game would open, minus everything that persists: a
## fresh course record under the first scenario's course type, on the
## fixed benchmark day, simulating. Benchmark suppression (already up)
## keeps it off the autosave slot and the goal books.
func _prepare_session() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.course_name = "Benchmark — preparing"
	var theme := int(_scenario.get("theme", CourseTheme.Type.PARKLAND))
	GameManager.current_theme = theme
	var colors := ColorblindMode.remap_colors(
		CourseTheme.get_terrain_colors(theme), GameManager.colorblind_mode)
	TerrainPalette.set_theme_colors(colors)
	EventBus.theme_changed.emit(theme)
	GameManager.current_day = BENCHMARK_DAY
	GameManager._day_progress = 0.0
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	_hole_tool.current_hole_number = 1

## Bare ground: whatever the title screen left on the view goes, and the
## grid returns to its new-course state.
func _prepare_ground() -> void:
	_golfers.clear_all_golfers()
	if _ball_manager != null:
		_ball_manager.clear_all_balls()
	if GameManager.weed_manager != null:
		GameManager.weed_manager.clear_all()
	if GameManager.staff_manager != null:
		GameManager.staff_manager.clear_all_staff()
	_entities.clear_all()
	if _hole_manager != null:
		_hole_manager.clear_visualizations()
	_grid.reset_for_new_course()

## The parcels the first layout needs (each scenario's reset stage
## re-grants for its own hole count, as it does on a borrowed course).
func _prepare_land() -> void:
	if GameManager.land_manager != null:
		GameManager.land_manager.grant_parcels(
			WorldLocations.get_required_parcels(int(_scenario.get("holes", 9))))

func _prepare_camera() -> void:
	_grid.refresh_all_overlays()
	_frame_on_anchor(_camera.min_zoom + 0.1, true)

## Preparation joins the headline sample like every other measured phase,
## and its wall time and step times ride in the report's prepare record.
func _finish_prepare(now: int) -> void:
	var summary := PerformanceBenchmark.summarize_frame_times(_frame_ms)
	summary["series_ms"] = PerformanceBenchmark.downsample_series(_frame_ms, 60)
	summary["worst_frame_ms"] = _frame_ms.max() if not _frame_ms.is_empty() else 0.0
	summary["process_ms_per_frame"] = _average_of(_process_ms)
	summary["physics_ms_per_frame"] = _average_of(_physics_ms)
	summary["sample_seconds"] = float(now - _phase_started_usec) / 1_000_000.0
	_tour_frame_ms.append_array(_frame_ms)
	_tour_process_ms.append_array(_process_ms)
	_tour_physics_ms.append_array(_physics_ms)
	_tour_sample_seconds += float(summary["sample_seconds"])
	_prepare_record = {
		"prepared": true,
		"prepare_ms": float(now - _phase_started_usec) / 1000.0,
		"steps_ms": _prepare_steps_ms.duplicate(),
		"frame": summary,
	}
	_begin_scenario()

# =============================================================================
# BUILD STAGES - one per frame, each timed
# =============================================================================

func _process_build_stage() -> void:
	if _build_stage >= BUILD_STAGES.size():
		var finished_build: Dictionary = _current.get("build", {})
		var total := 0.0
		for key in finished_build:
			if key != "total_ms":
				total += float(finished_build[key])
		finished_build["total_ms"] = total
		_current["build"] = finished_build
		_phase = Phase.SETTLE
		_phase_started_usec = Time.get_ticks_usec()
		return
	var stage := BUILD_STAGES[_build_stage]
	_publish(str(STAGE_LABELS.get(stage, stage)), Time.get_ticks_usec(), true)
	var started := Time.get_ticks_usec()
	match stage:
		"reset": _stage_reset()
		"natural": _stage_natural()
		"holes": _stage_holes()
		"terrain": _stage_terrain()
		"buildings": _stage_buildings()
		"paths": _stage_paths()
		"spawn": _stage_spawn()
	var build: Dictionary = _current.get("build", {})
	build["%s_ms" % stage] = float(Time.get_ticks_usec() - started) / 1000.0
	_current["build"] = build
	_build_stage += 1

## The wipe main.gd does for a new game, minus the loading screen: the
## banner and the growing course are the show here.
func _stage_reset() -> void:
	_golfers.clear_all_golfers()
	if _ball_manager != null:
		_ball_manager.clear_all_balls()
	if GameManager.weed_manager != null:
		GameManager.weed_manager.clear_all()
	if GameManager.staff_manager != null:
		GameManager.staff_manager.clear_all_staff()
	_entities.clear_all()
	if _hole_manager != null:
		_hole_manager.clear_visualizations()
	_grid.reset_for_new_course()
	GameManager.current_course = GameManager.CourseData.new()
	_hole_tool.current_hole_number = 1
	var theme := int(_scenario.get("theme", CourseTheme.Type.PARKLAND))
	GameManager.current_theme = theme
	var colors := ColorblindMode.remap_colors(
		CourseTheme.get_terrain_colors(theme), GameManager.colorblind_mode)
	TerrainPalette.set_theme_colors(colors)
	EventBus.theme_changed.emit(theme)
	if GameManager.land_manager != null:
		GameManager.land_manager.grant_parcels(
			WorldLocations.get_required_parcels(int(_scenario.get("holes", 9))))
	GameManager.course_name = "Benchmark — %s" % str(_scenario.get("name", "Course"))
	GameManager.current_day = BENCHMARK_DAY
	GameManager._day_progress = 0.0
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	_apply_weather()
	_frame_on_anchor(_camera.min_zoom + 0.1, true)

func _stage_natural() -> void:
	_grid.begin_batch()
	NaturalTerrainGenerator.generate(_grid, _entities, int(_scenario.get("seed", 1)))
	_grid.end_batch_quiet()
	_grid.refresh_all_overlays()

func _stage_holes() -> void:
	var layout := str(_scenario.get("layout", "generated"))
	var preferred := CourseClubhouse.arrival_corner()
	if layout == "quick_start":
		_grid.begin_batch()
		QuickStartCourse.build(_grid, _entities, _hole_tool)
		_grid.end_batch_quiet()
		_grid.refresh_all_overlays()
		preferred = QuickStartCourse.CLUBHOUSE_TILE
	elif layout.begins_with("prebuilt:"):
		PrebuiltCourseGenerator.build(layout.trim_prefix("prebuilt:"), _grid, _hole_tool)
	else:
		var holes := int(_scenario.get("holes", 9))
		_grid.begin_batch()
		GeneratedCourse.generate(holes, _grid, _entities, _hole_tool)
		_grid.end_batch_quiet()
		_grid.refresh_all_overlays()
		preferred = GeneratedCourse.get_anchor(holes) + GeneratedCourse.CLUBHOUSE_OFFSET
	CourseClubhouse.ensure(_grid, _entities, preferred)
	_current["holes_built"] = GameManager.current_course.holes.size() \
		if GameManager.current_course else 0
	GameManager.set_green_fee(10)
	GameManager.update_course_rating()
	_frame_on_anchor(_camera.min_zoom + 0.1, true)

## Seeded blobs of the scenario's terrain types on ground that is not the
## playing line, so water, sand, rock and woodland tiles all cost their
## overlays something on every toured course.
func _stage_terrain() -> void:
	var patches: Array = _scenario.get("terrain_patches", [])
	if patches.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_scenario.get("seed", 1)) + 7
	var anchor := _anchor()
	var spread := 24 if int(_scenario.get("holes", 9)) >= 18 else 19
	var changed := 0
	_grid.begin_batch()
	for blob in range(int(_scenario.get("patch_blobs", 0))):
		var terrain := int(patches[blob % patches.size()])
		var centre := anchor + Vector2i(rng.randi_range(-spread, spread),
			rng.randi_range(-spread, spread))
		var radius := int(_scenario.get("patch_radius", 2)) + rng.randi_range(0, 1)
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius + 1:
					continue
				var pos := centre + Vector2i(dx, dy)
				if _is_free_ground(pos) and _grid.get_tile(pos) != terrain:
					_grid.set_tile(pos, terrain)
					changed += 1
	_grid.end_batch_quiet()
	_grid.refresh_all_overlays()
	var counts: Dictionary = _current.get("counts", {})
	counts["terrain_patch_tiles"] = changed
	_current["counts"] = counts

func _stage_buildings() -> void:
	_load_catalogues()
	var theme := int(_scenario.get("theme", CourseTheme.Type.PARKLAND))
	for building_id in _scenario.get("buildings", []):
		var id := str(building_id)
		var data: Dictionary = _buildings_data.get(id, {})
		if data.is_empty() or not BuildingAvailability.is_available(data, theme):
			continue
		var size: Array = data.get("size", [1, 1])
		var spot := _find_footprint(Vector2i(int(size[0]), int(size[1])))
		if spot.x >= 0:
			_entities.place_building(id, spot, _buildings_data)
	var placed := 0
	var wanted := int(_scenario.get("decorations", 0))
	var kinds := _decorations_data.keys()
	kinds.sort()
	if wanted > 0 and not kinds.is_empty():
		var attempts := 0
		var candidates := _ground_candidates()
		while placed < wanted and attempts < candidates.size():
			var pos: Vector2i = candidates[attempts]
			attempts += 1
			if not _is_free_ground(pos):
				continue
			if _entities.place_decoration(str(kinds[placed % kinds.size()]), pos,
					_decorations_data) != null:
				placed += 1
	var counts: Dictionary = _current.get("counts", {})
	counts["buildings"] = _entities.get_all_buildings().size()
	counts["decorations"] = _entities.get_all_decorations().size()
	_current["counts"] = counts

func _stage_paths() -> void:
	var laid := 0
	var clubhouse := CourseClubhouse.find(_entities)
	if bool(_scenario.get("paths", false)) and clubhouse != null \
			and GameManager.current_course and not GameManager.current_course.holes.is_empty():
		_grid.begin_batch()
		laid = CoursePathGenerator.generate(_grid, GameManager.current_course.holes,
			_entities, clubhouse.grid_position)
		_grid.end_batch_quiet()
		_grid.refresh_all_overlays()
	var counts: Dictionary = _current.get("counts", {})
	counts["path_tiles"] = laid
	_current["counts"] = counts
	GameManager.update_course_rating()

## The field: groups of four, the visiting share asked from the location's
## pool first (exactly the game's own preference), the rest random guests.
## What the pool could not supply falls back to random golfers, and the
## record says how many true visitors took the tee.
func _stage_spawn() -> void:
	_enforce_speed()
	var target := int(_scenario.get("golfers", 0))
	var visiting_wanted := int(round(float(target)
		* float(_scenario.get("visiting_fraction", 0.0))))
	var spawned := 0
	var visiting := 0
	var group_id := -1
	for i in range(target):
		if i % 4 == 0:
			group_id = _golfers.next_group_id
			_golfers.next_group_id += 1
		var golfer: Golfer = null
		if i < visiting_wanted:
			golfer = _golfers.spawn_visiting_golfer(group_id)
			if golfer != null:
				visiting += 1
		if golfer == null:
			golfer = _golfers.spawn_random_golfer(group_id)
		if golfer != null:
			spawned += 1
	_golfers.time_since_last_spawn = 0.0
	var counts: Dictionary = _current.get("counts", {})
	counts["golfers_spawned"] = spawned
	counts["visiting_spawned"] = visiting
	_current["counts"] = counts

func _apply_weather() -> void:
	_current["weather_applied"] = "clear"
	var system = GameManager.weather_system
	if system == null or not GameManager.weather_enabled:
		return
	if str(_scenario.get("weather", "clear")) == "rain":
		system.weather_type = WeatherSystem.WeatherType.RAIN
		system.intensity = 0.7
		EventBus.weather_changed.emit(system.weather_type, system.intensity)
		_current["weather_applied"] = "rain"
	else:
		system.force_clear_weather()

func _load_catalogues() -> void:
	if not _buildings_data.is_empty():
		return
	var buildings = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	if buildings is Dictionary:
		_buildings_data = buildings.get("buildings", {})
	var decorations = JSON.parse_string(FileAccess.get_file_as_string("res://data/decorations.json"))
	if decorations is Dictionary:
		_decorations_data = decorations.get("decorations", {})

## Ground a building, patch or edit stamp may take: owned, on the grid, not
## the playing line, not water, and nothing built on it.
func _is_free_ground(pos: Vector2i) -> bool:
	if not _grid.is_valid_position(pos):
		return false
	if GameManager.land_manager != null and not GameManager.land_manager.is_tile_owned(pos):
		return false
	var terrain := _grid.get_tile(pos)
	if terrain in PLAYING_TERRAINS or terrain in [
			TerrainTypes.Type.WATER, TerrainTypes.Type.STREAM,
			TerrainTypes.Type.OUT_OF_BOUNDS, TerrainTypes.Type.EMPTY]:
		return false
	return not _entities.is_tile_occupied_by_building(pos) \
		and not _entities.is_tile_occupied_by_decoration(pos)

## First footprint of `size` that fits clear ground, in widening rings from
## the clubhouse so facilities cluster where a player would put them.
func _find_footprint(size: Vector2i) -> Vector2i:
	var clubhouse := CourseClubhouse.find(_entities)
	var centre := clubhouse.grid_position if clubhouse != null else _anchor()
	for ring in range(0, 28):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var origin := centre + Vector2i(dx * 2, dy * 2)
				if _footprint_free(origin, size):
					return origin
	return Vector2i(-1, -1)

func _footprint_free(origin: Vector2i, size: Vector2i) -> bool:
	for dx in range(size.x):
		for dy in range(size.y):
			if not _is_free_ground(origin + Vector2i(dx, dy)):
				return false
	return true

## Deterministic candidate tiles for decorations and edit stamps: every
## second tile of a block around the course anchor, centre out.
func _ground_candidates() -> Array[Vector2i]:
	var anchor := _anchor()
	var clubhouse := CourseClubhouse.find(_entities)
	if clubhouse != null:
		anchor = clubhouse.grid_position
	var tiles: Array[Vector2i] = []
	for ring in range(0, 22):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				tiles.append(anchor + Vector2i(dx * 2, dy * 2))
	return tiles

## The tile a layout is built around.
func _anchor() -> Vector2i:
	if GameManager.current_course and not GameManager.current_course.holes.is_empty():
		var mid := Vector2.ZERO
		for hole in GameManager.current_course.holes:
			mid += Vector2(hole.tee_position) + Vector2(hole.hole_position)
		mid /= float(GameManager.current_course.holes.size() * 2)
		return Vector2i(mid.round())
	var layout := str(_scenario.get("layout", "generated"))
	if layout == "generated":
		return GeneratedCourse.get_anchor(int(_scenario.get("holes", 9)))
	return Vector2i(63, 63)

func _frame_on_anchor(zoom: float, instant: bool) -> void:
	_camera.focus_on(_grid.grid_to_screen_center(_anchor()), instant)
	_camera.set_zoom_level(zoom, instant)

# =============================================================================
# CAMERA PHASE
# =============================================================================

## Waypoints in grid coordinates (converted through the projection every
## frame, so a mid-phase view rotation keeps the tour on its holes).
func _build_waypoints() -> void:
	_waypoints.clear()
	_rotated = false
	var plan := str(_scenario.get("camera", "tour"))
	var anchor := Vector2(_anchor())
	var overview := {"grid": anchor, "zoom": _camera.min_zoom + 0.05}
	var holes: Array = GameManager.current_course.holes \
		if GameManager.current_course else []
	match plan:
		"still":
			_waypoints = [overview]
		"zoom":
			_waypoints = [overview]
			if not holes.is_empty():
				_waypoints.append({"grid": Vector2(holes[0].hole_position),
					"zoom": _camera.max_zoom})
				_waypoints.append(overview)
				_waypoints.append({"grid": Vector2(holes[holes.size() - 1].tee_position),
					"zoom": 1.4})
			_waypoints.append(overview)
		"pan":
			_waypoints = [overview]
			for hole in holes:
				_waypoints.append({"grid": Vector2(hole.tee_position), "zoom": 1.05})
				_waypoints.append({"grid": Vector2(hole.hole_position), "zoom": 1.05})
			_waypoints.append(overview)
		_:  # tour / tour_rotate
			_waypoints = [overview]
			var stride := 1 if holes.size() <= 9 else 2
			var index := 0
			for hole in holes:
				if index % stride == 0:
					_waypoints.append({"grid": Vector2(hole.tee_position), "zoom": 1.0})
					_waypoints.append({"grid": Vector2(hole.hole_position), "zoom": 1.35})
				index += 1
			var clubhouse := CourseClubhouse.find(_entities)
			if clubhouse != null:
				_waypoints.append({"grid": Vector2(clubhouse.grid_position), "zoom": 1.2})
			_waypoints.append(overview)

func _drive_camera(now: int) -> void:
	if _waypoints.is_empty():
		return
	if str(_scenario.get("camera", "")) == "tour_rotate" and not _rotated \
			and (now - _phase_started_usec) * 2 >= camera_duration_usec:
		_rotated = true
		if _host != null and _host.has_method("_on_view_rotate_cw"):
			_host.call("_on_view_rotate_cw")
	if _waypoints.size() == 1:
		_apply_waypoint(_waypoints[0], _waypoints[0], 0.0)
		return
	var fraction := clampf(float(now - _phase_started_usec)
		/ float(maxi(camera_duration_usec, 1)), 0.0, 1.0)
	var scaled := fraction * float(_waypoints.size() - 1)
	var segment := mini(int(floor(scaled)), _waypoints.size() - 2)
	_apply_waypoint(_waypoints[segment], _waypoints[segment + 1], scaled - float(segment))

func _apply_waypoint(from: Dictionary, to: Dictionary, weight: float) -> void:
	var grid_pos := (from["grid"] as Vector2).lerp(to["grid"], clampf(weight, 0.0, 1.0))
	_camera.focus_on(_grid.grid_to_screen_precise(grid_pos))
	_camera.set_zoom_level(lerpf(float(from["zoom"]), float(to["zoom"]),
		clampf(weight, 0.0, 1.0)))

## The one rotating tour hands the view back the way it found it (the
## snapshot would fix it at the end of the tour regardless).
func _restore_orientation() -> void:
	if _rotated and _host != null and _host.has_method("_on_view_rotate_ccw"):
		_host.call("_on_view_rotate_ccw")
	_rotated = false

# =============================================================================
# EDIT PHASE - the player's own brush and elevation tools, timed
# =============================================================================

func _begin_edit(now: int) -> bool:
	var plan := str(_scenario.get("edit", "none"))
	_edit_budget = int(EDIT_STAMP_BUDGETS.get(plan, 0))
	if _edit_budget <= 0:
		return false
	if edit_max_stamps > 0:
		_edit_budget = mini(_edit_budget, edit_max_stamps)
	_edit_points.clear()
	for pos in _ground_candidates():
		if _is_free_ground(pos):
			_edit_points.append(pos)
		if _edit_points.size() >= 48:
			break
	if _edit_points.is_empty():
		return false
	_edit_done = 0
	_edit_paint_usec = 0
	_edit_elevation_usec = 0
	_edit_tiles = 0
	_edit_vertices = 0
	_edit_paths = 0
	_elevation_tool.select_tool(ElevationTool.Tool.GRADUAL)
	_elevation_tool.set_brush(3, true)
	_camera.focus_on(_grid.grid_to_screen_center(_edit_points[0]))
	_camera.set_zoom_level(1.5)
	_begin_timed_phase(Phase.EDIT, now)
	_publish("Editing terrain: %s" % plan, now, true)
	return true

func _edit_stamps() -> void:
	var plan := str(_scenario.get("edit", "none"))
	for step in range(maxi(edit_stamps_per_frame, 1)):
		if _edit_done >= _edit_budget:
			break
		var centre: Vector2i = _edit_points[_edit_done % _edit_points.size()]
		match plan:
			"paint":
				_paint_stamp(centre, _edit_done, false)
			"elevation":
				_elevation_stamp(centre, _edit_done)
			"stress":
				if _edit_done % 5 == 4:
					_elevation_stamp(centre, _edit_done)
				elif _edit_done % 7 == 6:
					_path_stamp(centre)
				else:
					_paint_stamp(centre, _edit_done, true)
			_:  # both
				if _edit_done % 3 == 2:
					_elevation_stamp(centre, _edit_done)
				else:
					_paint_stamp(centre, _edit_done, false)
		_edit_done += 1

## One 3-tile brush stamp, unbatched like the player's: every tile goes
## through set_tile and its overlay redraws, which is the cost being timed.
func _paint_stamp(centre: Vector2i, index: int, cycle_all: bool) -> void:
	var types: Array = CourseBenchmarkScenarios.edit_cycle_types() if cycle_all \
		else _scenario.get("terrain_patches", [])
	if types.is_empty():
		types = CourseBenchmarkScenarios.edit_cycle_types()
	var terrain := int(types[index % types.size()])
	var started := Time.get_ticks_usec()
	for offset in TerrainBrush.offsets(3, true):
		var pos := centre + offset
		if _is_free_ground(pos) and _grid.get_tile(pos) != terrain:
			_grid.set_tile(pos, terrain)
			_edit_tiles += 1
	_edit_paint_usec += Time.get_ticks_usec() - started

func _elevation_stamp(centre: Vector2i, index: int) -> void:
	_elevation_tool.set_mode((index >> 3) % 2 == 0)
	var started := Time.get_ticks_usec()
	var changes := _elevation_tool.paint_at_tile(centre, _grid, _entities)
	_edit_elevation_usec += Time.get_ticks_usec() - started
	_edit_vertices += changes.size()

func _path_stamp(centre: Vector2i) -> void:
	var started := Time.get_ticks_usec()
	if _grid.can_place_walking_path(centre) and _grid.set_walking_path(centre, true):
		_edit_paths += 1
	_edit_paint_usec += Time.get_ticks_usec() - started

# =============================================================================
# DEVICE CHECK, FINISH AND RESTORE
# =============================================================================

func _begin_device_phase() -> void:
	_phase = Phase.DEVICE
	_publish("Device check: GPU fill ladder and CPU workload on the last course",
		Time.get_ticks_usec(), true)
	if not run_device_check or _device_runner == null:
		_finish_tour(false)
		return
	if not _device_runner.start({"scenario": "Course tour (%s) — final course" % _suite_name}):
		_finish_tour(false)

func _on_device_progress(message: String, _fraction: float) -> void:
	_publish("Device check: %s" % message, Time.get_ticks_usec())

func _on_device_completed(result: Dictionary) -> void:
	_device_result = result
	# The runner just published its own last_result; the tour's merged
	# result replaces it in _finish_tour before anything can read it.
	_finish_tour(false)

func _finish_tour(was_cancelled: bool) -> void:
	if _phase == Phase.RESTORE or _phase == Phase.IDLE:
		return
	_phase = Phase.RESTORE
	_publish("Taking the benchmark course down..." if _prepared_course \
		else "Putting your course back...", Time.get_ticks_usec(), true)
	if _device_runner != null and _device_runner.is_running():
		_device_runner.cancel()
	if not _current.is_empty() and not _records.has(_current):
		_records.append(_current)
		_current = {}
	_elevation_tool.cancel()
	var restored := _restore_session()
	var result := _build_result(was_cancelled, restored)
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_phase = Phase.IDLE
	set_process(false)
	if was_cancelled:
		cancelled.emit(result)
	else:
		PerformanceBenchmark.last_result = result
		if record_history:
			BenchmarkHistory.append_run(result)
		completed.emit(result)

func _build_result(was_cancelled: bool, restored: bool) -> Dictionary:
	var result: Dictionary
	if not _device_result.is_empty():
		result = _device_result.duplicate(true)
	else:
		result = _device_runner.collect_device_details()
		result["gpu"] = PerformanceBenchmark.summarize_gpu([], false,
			"device check skipped", 0.0)
		result["cpu"] = {"work_units": 0, "compute_ms": 0.0, "units_per_second": 0.0}
		result["memory"] = PerformanceBenchmark.collect_memory()
	# The headline frame pacing is the tour itself: every preparation,
	# camera and simulation sample pooled, on courses fixed by the suite.
	if not _tour_frame_ms.is_empty():
		var frame := PerformanceBenchmark.summarize_frame_times(_tour_frame_ms)
		frame["series_ms"] = PerformanceBenchmark.downsample_series(
			_tour_frame_ms, PerformanceBenchmark.MAX_SERIES_SAMPLES)
		frame["best_frame_ms"] = _tour_frame_ms.min()
		frame["worst_frame_ms"] = _tour_frame_ms.max()
		result["frame"] = frame
		var engine: Dictionary = result.get("engine", {})
		engine["process_ms_per_frame"] = _average_of(_tour_process_ms)
		engine["physics_ms_per_frame"] = _average_of(_tour_physics_ms)
		engine["node_count"] = maxi(int(engine.get("node_count", 0)),
			maxi(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), 0))
		result["engine"] = engine
		result["frame_sample_seconds"] = _tour_sample_seconds
	var prepare: Dictionary = _prepare_record.duplicate(true)
	if prepare.is_empty():
		prepare = {"prepared": _prepared_course, "prepare_ms": 0.0,
			"steps_ms": _prepare_steps_ms.duplicate()}
	result["tour"] = {
		"suite": _suite_id,
		"suite_name": _suite_name,
		"prepare": prepare,
		"scenarios": _records.duplicate(true),
		"rollup": PerformanceBenchmark.summarize_tour(_records),
		"restored": restored,
		"cancelled": was_cancelled,
	}
	result["context"] = {"scenario": "Course tour — %s (%d courses)" % [
		_suite_name, _records.size()]}
	result["started_at_unix"] = _started_unix
	result["duration_ms"] = float(Time.get_ticks_usec() - _started_usec) / 1000.0
	result["score"] = PerformanceBenchmark.score_result(result)
	result["report_text"] = PerformanceBenchmark.format_report(result)
	return result

## Take the throwaway course down: golfers, entities and ground cleared,
## the course record dropped (the title screen's state, as at boot), the
## captured land and scalars back, and the game in the mode it was found
## in (the Main Menu). Nothing here announces a load - there is no course
## left to load.
func _teardown_prepared_course() -> bool:
	_prepare_ground()
	GameManager.current_course = null
	_grid.refresh_all_overlays()
	GameManager.course_name = str(_captured.get("course_name", "New Course"))
	var theme := int(_captured.get("theme", CourseTheme.Type.PARKLAND))
	GameManager.current_theme = theme
	var colors := ColorblindMode.remap_colors(
		CourseTheme.get_terrain_colors(theme), GameManager.colorblind_mode)
	TerrainPalette.set_theme_colors(colors)
	EventBus.theme_changed.emit(theme)
	GameManager.current_day = int(_captured.get("day", 1))
	GameManager._day_progress = 0.0
	GameManager.money = int(_captured.get("money", GameManager.money))
	GameManager.reputation = float(_captured.get("reputation", GameManager.reputation))
	GameManager.green_fee = int(_captured.get("green_fee", GameManager.green_fee))
	var land: Dictionary = _captured.get("land", {})
	if GameManager.land_manager != null and not land.is_empty():
		GameManager.land_manager.deserialize(land)
	GameManager.set_mode(int(_captured.get("mode", GameManager.GameMode.MAIN_MENU))
		as GameManager.GameMode)
	return true

## Give the game back the way the tour found it. A borrowed course returns
## by snapshot (which rebuilds it and announces a load); a course the tour
## prepared itself is torn down to the bare title-screen state instead.
## Either way the session state a save does not carry - camera, game
## speed, pause, funds flag and the spawn cooldown - follows after.
func _restore_session() -> bool:
	var restored: bool
	if _prepared_course:
		restored = _teardown_prepared_course()
	else:
		restored = SaveManager.restore_course_snapshot(_snapshot)
	_snapshot = {}
	_restore_orientation()
	_camera.benchmark_controlled = false
	_camera.focus_on(_captured.get("camera_position", _camera.global_position), true)
	_camera.set_zoom_level(float(_captured.get("camera_zoom", 1.0)), true)
	GameManager.unlimited_money = bool(_captured.get("unlimited_money", false))
	if _golfers != null:
		_golfers.min_spawn_cooldown_seconds = float(_captured.get("spawn_cooldown", 90.0))
		_golfers.time_since_last_spawn = 0.0
	GameManager.set_speed(int(_captured.get("speed", GameManager.GameSpeed.NORMAL))
		as GameManager.GameSpeed)
	GameManager.is_paused = bool(_captured.get("paused", false))
	_set_host_undo_suppressed(false)
	# Career achievements write to the settings file as they unlock. The
	# suppression flag stops benchmark play moving them; putting the
	# captured shelf back makes that a guarantee rather than a hope.
	var shelf: Dictionary = _captured.get("achievements", {})
	if not shelf.is_empty() and AchievementStore.load_state() != shelf:
		AchievementStore.save_state(shelf)
		if SaveManager.milestone_manager != null:
			SaveManager.milestone_manager.refresh_achievements()
	SaveManager.benchmark_suppression = false
	return restored

# =============================================================================
# PROGRESS
# =============================================================================

func _publish(phase_text: String, now: int, force: bool = false) -> void:
	if not force and now - _last_publish_usec < 120_000:
		return
	_last_publish_usec = now
	var within := 0.0
	match _phase:
		Phase.PREPARE: within = 0.08 * float(_prepare_step) \
			/ float(maxi(PREPARE_STEPS.size(), 1))
		Phase.BUILD: within = 0.25 * float(_build_stage) / float(BUILD_STAGES.size())
		Phase.SETTLE: within = 0.30
		Phase.CAMERA: within = 0.30 + 0.20 * _phase_fraction(now, camera_duration_usec)
		Phase.SIMULATE: within = 0.50 + 0.30 * _phase_fraction(now, simulate_duration_usec)
		Phase.EDIT: within = 0.80 + 0.20 * (float(_edit_done) / float(maxi(_edit_budget, 1)))
		Phase.DEVICE: within = 1.0
		Phase.RESTORE: within = 1.0
	var total_weight := float(_scenarios.size()) + (0.5 if run_device_check else 0.0)
	var done_weight := float(_scenario_index) + within
	if _phase == Phase.DEVICE or _phase == Phase.RESTORE:
		done_weight = float(_scenarios.size()) + 0.25
	var live := ""
	if not _frame_ms.is_empty():
		var last_ms := _frame_ms[_frame_ms.size() - 1]
		live = "%.0f FPS · %.1f ms" % [1000.0 / maxf(last_ms, 0.001), last_ms]
	if _golfers != null and not _golfers.active_golfers.is_empty():
		live += " · %d golfers on course" % _golfers.active_golfers.size()
	live += " · the main menu will be restored" if _prepared_course \
		else " · your course will be restored"
	var status := {
		"suite_name": _suite_name,
		"scenario_index": mini(_scenario_index, maxi(_scenarios.size() - 1, 0)),
		"scenario_total": _scenarios.size(),
		"scenario_name": str(_current.get("name", _scenario.get("name", ""))),
		"description": str(_current.get("description", "")),
		"phase": phase_text,
		"fraction": clampf(done_weight / maxf(total_weight, 1.0), 0.0, 1.0),
		"live": live,
	}
	if _overlay != null:
		_overlay.update_status(status)
	progress_changed.emit(status)

func _phase_fraction(now: int, duration_usec: int) -> float:
	return clampf(float(now - _phase_started_usec) / float(maxi(duration_usec, 1)), 0.0, 1.0)
