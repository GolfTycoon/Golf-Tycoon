extends Node2D
## Main - Primary game scene controller

const GameManagerScript := preload("res://scripts/autoload/game_manager.gd")
const WorldMapStateScript := preload("res://scripts/autoload/world_map_state.gd")

@onready var terrain_grid: TerrainGrid = $TerrainGrid
@onready var camera: IsometricCamera = $IsometricCamera
@onready var ball_manager: BallManager = $BallManager
@onready var hole_manager: HoleManager = $HoleManager
@onready var golfer_manager: GolferManager = $GolferManager
@onready var bottom_bar: HBoxContainer = $UI/HUD/BottomBar
var terrain_toolbar: TerrainToolbar = null
var _last_hud_focus: WeakRef = null
var hole_grid: GridContainer = null  # Lives in the toolbar's Holes tab (set up in _setup_terrain_toolbar)
@onready var left_controls: BottomControlDock = $UI/HUD/BottomBar/LeftControls
## The view controls ride on the top-left location banner (see
## _fill_view_controls): the two Rotate arrows on the right of its details
## card, and the facing chip in the card's top-right corner.
var rotate_view_controls: HBoxContainer = null
var rotate_ccw_btn: Button = null
var rotate_cw_btn: Button = null
var orientation_toggle: OrientationToggleButton = null
@onready var pause_btn: PixelCircleButton = $UI/HUD/BottomBar/LeftControls/SpeedControls/PauseBtn
## One button for every running speed: it reads ">" at Normal, ">>" at Fast
## and ">>>" at Ultra — one, two or three triangles on its face — and a press
## cycles to the next speed (see GameManager.cycle_running_speed).
@onready var speed_btn: PixelCircleButton = $UI/HUD/BottomBar/LeftControls/SpeedControls/SpeedBtn
@onready var speed_controls: Control = $UI/HUD/BottomBar/LeftControls/SpeedControls
# New UI components
var player_round: PlayerRoundManager

var hud_status_column: HUDStatusColumn = null
var course_location_banner: CourseLocationBanner = null

# Legacy references (kept for compatibility, now managed by HUDStatusColumn)
var money_label: Label = null
var day_label: Label = null
var reputation_label: Label = null
var game_mode_label: Label = null

var current_tool: int = -1  # Start with no tool selected
var round_brush := true
var brush_size: int = 1
var is_painting: bool = false
var _tee_block_notified: bool = false  # One "tee box is waiting" notice per stroke
var _path_block_notified: bool = false  # One "no room for a walking path" notice per stroke
var last_paint_pos: Vector2i = Vector2i(-1, -1)
var last_paint_anchor: Vector2i = Vector2i(-1, -1)

# Measurement tool (Ctrl+click drag)
var _measuring: bool = false
var _measure_start: Vector2i = Vector2i.ZERO
var _measure_end: Vector2i = Vector2i.ZERO
var _measure_overlay: Node2D = null

## Moving entities captured (in grid space) across a view projection change.
var _pending_moving_entities: Array = []

var hole_tool: HoleCreationTool = HoleCreationTool.new()
var placement_manager: PlacementManager = PlacementManager.new()
var undo_manager: UndoManager = UndoManager.new()
var wind_system: WindSystem = null
var weather_system: WeatherSystem = null
## The rain and weather tint are the Weather mod's visuals now: it adds them
## to this scene when EventBus.main_scene_ready fires (see
## mods/golf_tycoon.weather/mod_main.gd). These untyped slots stay for the
## older call sites that look the nodes up on the main scene.
var rain_overlay: Node = null
var weather_tint_system: Node = null
var elevation_tool: ElevationTool = ElevationTool.new()
var building_registry: Dictionary = {}
var decoration_registry: Dictionary = {}
var entity_layer: EntityLayer = null
var building_info_panel: BuildingInfoPanel = null
var financial_panel: FinancialPanel = null
## Marketing now lives on the Financial Overview screen; retained as a null
## compatibility reference for older panel call sites.
var marketing_panel: MarketingPanel = null
var mini_map: MiniMap = null
var inspect_mode: bool = false
## Alias for the pinned Inspect toggle on the toolbar's Course Terrain tab; the
## matching toggles on the other Build tabs stay in step via the toolbar.
var inspect_btn: PixelCircleButton = null
var feed_btn: DockActionButton = null  # Event feed toggle: the Feed card on the toolbar's Club tab
var tile_inspector: TileInspector = null
var hole_stats_panel: HoleStatsPanel = null
var tournament_manager: TournamentManager = null
var tournament_panel: TournamentPanel = null
var hotkey_panel: HotkeyPanel = null
var weather_debug_panel: WeatherDebugPanel = null
var season_debug_panel: SeasonDebugPanel = null
var analytics_panel_ui: AnalyticsPanel = null
var round_summary_popup: RoundSummaryPopup = null
var tournament_leaderboard: TournamentLeaderboard = null
## Top-left corner of the screen: round scores and the live tournament board.
var scores_dock: ScoresDock = null
var tournament_results_popup: TournamentResultsPopup = null
var pause_menu: PauseMenu = null
## The course benchmark tour runner (Settings → Display → Benchmark).
## While it runs it owns the course view: gameplay input stands down and
## Escape cancels it instead of opening the pause menu.
var course_benchmark_tour: CourseBenchmarkTour = null
var _benchmark_tour_active: bool = false
## True only while the live Settings menu (or the Benchmark Results opened
## from it, or a running tour) descends from one opened on the Main Menu.
## Benchmarks may only run under it: measuring the device is a title-screen
## job, so a game in progress is never the test scene.
var _settings_opened_from_main_menu: bool = false
var _was_paused_before_pause_menu: bool = false
var _pause_session_active: bool = false  # True while the pause menu (or its Save/Load/Settings sub-panels) is open
var _just_loaded_game: bool = false  # Set when a save just loaded successfully, consumed by the save/load panel
var milestone_manager: MilestoneManager = null
## Where a goal screen was opened from: the Club tab freezes the course and
## hands it back on the way out; the title screen's Achievements tile comes
## home to the menu instead.
enum GoalScreenOrigin { CLUB_TAB, TITLE_SCREEN }
## The three fullscreen goal screens: Course Milestones (per-location goals
## for this save), World Milestones (company goals for this save) and
## Achievements (career honours kept between saves). All three sit on the
## World Map's backdrop and hand the course back the way the Course Map
## does.
var course_milestones_screen: CourseMilestonesScreen = null
var world_milestones_screen: WorldMilestonesScreen = null
var achievements_screen: AchievementsScreen = null
## The Mods screen opened from the title screen's Mods tile.
var mods_screen: ModsScreen = null
## The pause flag from before a goal screen opened. The screens freeze the
## day while they are up, so this is what the course resumes to on the way
## out.
var _goal_screen_restore_paused: bool = false
var _goal_screen_origin: int = GoalScreenOrigin.CLUB_TAB
var seasonal_calendar_panel: SeasonalCalendarPanel = null
var tutorial_system: TutorialSystem = null
var course_rating_overlay: CourseRatingOverlay = null
var shot_heatmap_tracker: ShotHeatmapTracker = null
var _active_panel: CenteredPanel = null  # Tracks the currently open panel to prevent stacking
var bulldozer_mode: bool = false
var _bulldoze_drag_count: int = 0
var _bulldoze_drag_cost: int = 0
## The required building (the clubhouse) being carried to a new tile. While it
## is set, the next click on the course sets it down — see
## _handle_building_move_click.
var _moving_building: Building = null
var placement_preview: PlacementPreview = null
var main_menu: MainMenu = null
var world_map_screen: WorldMapScreen = null
## One overlay owns input from the start of Quick Start preparation until the
## course is built. Other new courses create it when generation begins.
var _generating_course_screen: GeneratingCourseScreen = null
## Controller/keyboard pointer and the on-screen prompt strip (see
## _setup_input_layer). Both live in the HUD and never take pointer input.
var gamepad_cursor: GamepadCursor = null
var input_hint_bar: InputHintBar = null
## The Course Map: the isometric overview of the course and its four modes
## (Land, Routing Holes, Course Aura, Staff Management).
var course_map_screen: CourseMapScreen = null
## The pause flag from before the Course Map opened. The map freezes the day
## while it is up, so this is what the course resumes to on the way out.
var _course_map_restore_paused: bool = false
var event_feed_panel: EventFeedPanel = null
## Where the world map screen was opened from — decides where its Back button
## (and a picked location) return to.
##  - TITLE_SCREEN: Start New Game / Quick Start.
##  - CLUB_TAB:     the Club tab's World Map button, which hands the course back.
##  - PAUSE_MENU:   the in-game entry the pause menu used before the button
##                  moved to the Club tab (kept for tests and harnesses).
enum WorldMapOrigin { TITLE_SCREEN, CLUB_TAB, PAUSE_MENU }
var _world_map_origin: int = WorldMapOrigin.TITLE_SCREEN
## The game's pause flag from before the Club tab opened the map. The map freezes
## the day while it is up, so this is what the course resumes to on the way out.
var _world_map_restore_paused: bool = false
## Holes the world map asked the first course to start with (0 = build them all).
var _generated_holes_pending: int = 0

# Staff on the course: a container for the wandering staff members, the weeds
# they work on, and the overlay that draws their designated areas.
var staff_container: Node2D = null
var weed_container: Node2D = null
var weed_manager: WeedManager = null
var staff_area_overlay: StaffAreaOverlay = null
## The owner's own golfer, who is on the course between rounds.
var player_golfer_manager: PlayerGolferManager = null
## Index into StaffManager.hired_staff whose area the player is repositioning,
## or -1 when not in that mode.
var _staff_area_mode_index: int = -1
## True while the player is choosing the ground the owner's own golfer works
## (see PlayerGolferManager).
var _owner_area_mode: bool = false

# Hole context menu and move modes
enum HoleMoveMode { NONE, MOVING_TEE, MOVING_GREEN }
var _hole_move_mode: int = HoleMoveMode.NONE
var _hole_move_data: GameManager.HoleData = null
var _hole_context_menu: HoleContextMenu = null
var _highlighted_hole_number: int = 0
var routing_overlay: RoutingOverlay = null

## True once the title screen is up and the player can act. Until then the
## scene's input handlers stand down: on a sliced build (see _ready) a player
## pressing a key while the loading screen is still up would otherwise hit a
## half-built HUD.
var _startup_complete: bool = false

# The startup, in order. Each step is a group of setup calls small enough to
# run between two frames; _run_startup_step does the work of each one.
const STARTUP_LOAD_CONTENT := 0
const STARTUP_COURSE_LAYER := 1
const STARTUP_MANAGERS := 2
const STARTUP_HUD := 3
const STARTUP_PANELS := 4
const STARTUP_SCREENS := 5
const STARTUP_TITLE_SCREEN := 6
## Steps in the startup, the title screen included.
const STARTUP_STEPS := 7

## Bring the scene up in slices rather than one long _ready().
##
## Building the HUD, the tool palette, the player's round and the title screen
## is a lot of work in one go: a couple of seconds of script even on a desktop,
## and long enough on a low-end device for the browser to look hung. The web
## build is the worst case, because the loader the player is looking at then
## (web/custom_shell.html) is a web page: while the engine holds the thread the
## page cannot repaint, so its animation stops dead and "Starting up 100%" sits
## there until the first frame arrives. Slicing the work — a short group of
## setup calls, a frame for the page to paint in and for the player to read the
## stage line, then the next group — keeps the loader alive throughout.
##
## Only the web pays for those frames: everywhere else the startup runs straight
## through in this one _ready(), as it always did, because a native build keeps
## the engine's own boot splash (application/boot_splash in project.godot) up
## until the first frame and nothing half-built is ever seen.
func _ready() -> void:
	var sliced := _startup_is_sliced()
	for step in STARTUP_STEPS:
		# The stage is announced before the frame that follows it, so the
		# loader describes the work that is about to run, not the work that
		# just finished. The first step needs no frame: the scene has only
		# just been created and the browser has had nothing to wait for.
		WebBoot.set_stage(_startup_stage_text(step))
		if sliced and step > 0:
			await get_tree().process_frame
		_run_startup_step(step)
	_startup_complete = true
	print("Main scene ready")
	# Mods hang their per-scene nodes (weather visuals and friends) off this.
	EventBus.main_scene_ready.emit(self)
	# The title screen is really up now, so the page's loader can go away (on
	# the web the engine's startGame() promise resolved long before this).
	WebBoot.menu_ready()


## Whether to spread the startup over frames on this device. Every web build
## does; a native build can ask for it with the `--split-startup` command-line
## argument, which is how the sliced path is exercised without a browser.
func _startup_is_sliced() -> bool:
	return WebBoot.split_startup()


## What the web loader's stage line reads while `step` runs. Short: it sits on
## one line of the shell's loading panel (see web/custom_shell.html).
func _startup_stage_text(step: int) -> String:
	match step:
		STARTUP_LOAD_CONTENT:
			return "Loading the clubhouse"
		STARTUP_COURSE_LAYER:
			return "Surveying the grounds"
		STARTUP_MANAGERS:
			return "Hiring the ground staff"
		STARTUP_HUD:
			return "Setting up the clubhouse"
		STARTUP_PANELS:
			return "Opening the pro shop"
		STARTUP_SCREENS:
			return "Marking the scorecards"
		STARTUP_TITLE_SCREEN:
			return "Opening the first tee"
	return "Starting up"


## Build one step of the scene. _ready runs them in order, once each.
func _run_startup_step(step: int) -> void:
	match step:
		STARTUP_LOAD_CONTENT:
			_startup_load_content()
		STARTUP_COURSE_LAYER:
			_startup_course_layer()
		STARTUP_MANAGERS:
			_startup_managers()
		STARTUP_HUD:
			_startup_hud()
		STARTUP_PANELS:
			_startup_panels()
		STARTUP_SCREENS:
			_startup_screens()
		STARTUP_TITLE_SCREEN:
			_startup_title_screen()

## Catalogs: the building and decoration data every later step reads (mods
## included, through ContentRegistry).
func _startup_load_content() -> void:
	# Set terrain grid reference in GameManager
	GameManager.terrain_grid = terrain_grid

	# Load buildings and decorations from JSON
	_load_buildings_data()
	_load_decorations_data()

## The course layer: the entity layer, the hole routing overlay, the wind and
## weather systems and the weather-independent tools. This is the part that
## touches the terrain grid, so it comes before the managers that paint on it.
func _startup_course_layer() -> void:
	entity_layer = EntityLayer.new()
	add_child(entity_layer)
	entity_layer.set_terrain_grid(terrain_grid)
	entity_layer.set_building_registry(building_registry)
	entity_layer.set_decoration_registry(decoration_registry)
	entity_layer.building_selected.connect(_on_building_clicked)
	GameManager.entity_layer = entity_layer

	# Create building info panel (added to UI layer later)
	building_info_panel = BuildingInfoPanel.new()
	building_info_panel.close_requested.connect(_on_building_panel_closed)

	# On-course staff look customers up through GameManager.
	GameManager.golfer_manager = golfer_manager

	# Set up ball manager
	ball_manager.set_terrain_grid(terrain_grid)

	# Set up hole manager
	hole_manager.set_terrain_grid(terrain_grid)
	GameManager.hole_manager = hole_manager

	# Set up routing overlay for inter-hole walking routes
	routing_overlay = RoutingOverlay.new()
	routing_overlay.name = "RoutingOverlay"
	$Holes.add_child(routing_overlay)
	routing_overlay.initialize(terrain_grid)

	# Add hole creation tool
	add_child(hole_tool)

	# Add undo manager
	add_child(undo_manager)
	terrain_grid.tile_changed.connect(_on_terrain_tile_changed_for_undo)

	# Set up wind and weather: whichever implementations the loaded mods
	# provided, or the neutral bases (dead calm, permanent sun) when the
	# Wind/Weather mods are off. The tint and rain are the Weather mod's to
	# add - see the main_scene_ready signal at the end of _ready.
	wind_system = ModManager.create_wind_system()
	wind_system.name = "WindSystem"
	add_child(wind_system)
	GameManager.wind_system = wind_system

	weather_system = ModManager.create_weather_system()
	weather_system.name = "WeatherSystem"
	add_child(weather_system)
	GameManager.weather_system = weather_system

	# Add elevation tool
	add_child(elevation_tool)


## The managers: the tournament and economy staff, the weeds they work on, the
## owner's own golfer and the save manager's references into the scene.
func _startup_managers() -> void:
	# Set up tournament manager
	tournament_manager = TournamentManager.new()
	tournament_manager.name = "TournamentManager"
	add_child(tournament_manager)
	GameManager.tournament_manager = tournament_manager

	# Set up tournament leaderboard
	tournament_leaderboard = TournamentLeaderboard.new()
	tournament_leaderboard.name = "TournamentLeaderboard"
	tournament_manager.setup(golfer_manager, tournament_leaderboard)

	# Final event details remain in the dedicated results dialog; live scores
	# dock to the top-left corner of the HUD (see _setup_scores_dock) and the
	# owner's shots are played from the Play Course page.
	tournament_results_popup = TournamentResultsPopup.new()
	tournament_results_popup.name = "TournamentResultsPopup"
	$UI/HUD.add_child(tournament_results_popup)
	tournament_manager.tournament_completed.connect(_on_tournament_completed)

	# Set up economy managers
	var land_mgr = LandManager.new()
	land_mgr.name = "LandManager"
	add_child(land_mgr)
	GameManager.land_manager = land_mgr
	land_mgr.land_purchased.connect(_on_parcel_purchased)

	var staff_mgr = StaffManager.new()
	staff_mgr.name = "StaffManager"
	add_child(staff_mgr)
	GameManager.staff_manager = staff_mgr

	# Staff bodies live under Entities, weeds just above the terrain surface.
	staff_container = Node2D.new()
	staff_container.name = "Staff"
	staff_container.y_sort_enabled = true
	$Entities.add_child(staff_container)
	staff_mgr.set_staff_container(staff_container)

	weed_container = Node2D.new()
	weed_container.name = "Weeds"
	weed_container.y_sort_enabled = true
	$Entities.add_child(weed_container)
	weed_manager = WeedManager.new()
	weed_manager.name = "WeedManager"
	add_child(weed_manager)
	weed_manager.setup(terrain_grid, weed_container)
	GameManager.weed_manager = weed_manager
	staff_mgr.set_weed_manager(weed_manager)

	staff_area_overlay = StaffAreaOverlay.new()
	staff_area_overlay.name = "StaffAreaOverlay"
	staff_area_overlay.set_terrain_grid(terrain_grid)
	terrain_grid.add_child(staff_area_overlay)

	# The owner's own golfer lives on the course: between rounds they work
	# the ground the player gives them (see PlayerGolferManager).
	player_golfer_manager = PlayerGolferManager.new()
	player_golfer_manager.name = "PlayerGolferManager"
	add_child(player_golfer_manager)
	GameManager.player_golfer_manager = player_golfer_manager
	player_golfer_manager.setup(golfer_manager.golfers_container)
	player_golfer_manager.area_changed.connect(func(_center: Vector2i):
		if staff_area_overlay:
			staff_area_overlay.refresh())

	var marketing_mgr = MarketingManager.new()
	marketing_mgr.name = "MarketingManager"
	add_child(marketing_mgr)
	GameManager.marketing_manager = marketing_mgr

	# Set up save manager references
	SaveManager.set_references(terrain_grid, entity_layer, golfer_manager, ball_manager)


## The HUD: the signals and buttons the scene listens on, the bottom bar, the
## status column, the location banner, the scores dock and the tool palette.
func _startup_hud() -> void:
	_connect_signals()
	_connect_ui_buttons()
	_setup_bottom_bar()
	_setup_hud_status_column()
	_setup_course_location_banner()
	_setup_scores_dock()
	_setup_mod_hud_widgets()
	_setup_placement_preview()
	_create_menu_buttons()
	_fill_left_control_stack()


## The panels: the side panels, the minimap, the event feed's dock and the
## round summary, all of which hang off the HUD above.
func _startup_panels() -> void:
	_setup_building_info_panel()
	_setup_financial_panel()
	_setup_mini_map()
	_setup_hole_stats_panel()
	_setup_tournament_panel()
	_setup_marketing_panel()
	_setup_hotkey_panel()
	_setup_weather_debug_panel()
	_setup_season_debug_panel()
	_setup_analytics_panel()
	_setup_golfer_profile_navigation()
	_setup_round_summary_popup()


## The screens that drive a course: the benchmark tour, the owner's round, and
## the milestone, calendar, feed and overlay setups that read the HUD's panels.
func _startup_screens() -> void:
	# The benchmark tour drives this scene's own course machinery, so it is
	# set up here (paused) and started from Settings / Benchmark Results.
	course_benchmark_tour = CourseBenchmarkTour.new()
	course_benchmark_tour.name = "CourseBenchmarkTour"
	add_child(course_benchmark_tour)
	course_benchmark_tour.setup(terrain_grid, camera, entity_layer, hole_tool,
		golfer_manager, hole_manager, ball_manager, self)
	course_benchmark_tour.completed.connect(_on_course_benchmark_completed)
	course_benchmark_tour.cancelled.connect(_on_course_benchmark_cancelled)

	player_round = PlayerRoundManager.new()
	add_child(player_round)
	player_round.setup(golfer_manager, $IsometricCamera, $UI/HUD)
	player_round.attach_player_tab(terrain_toolbar.player_tab)
	player_round.attach_scores_panel(scores_dock.round_scores)
	# The Edit Player page asks for a click on the course to move the ground
	# the owner's own golfer works.
	player_round.owner_area_move_requested.connect(_on_owner_area_move_requested)
	# The owner plays their own shots during a tournament: the manager spawns the
	# field, but aiming for their live golfer is handed to the PlayerRoundManager.
	tournament_manager.set_aim_controller(player_round)
	player_round.session_opened.connect(func():
		# Clear both tiers of tool selection before mouse input becomes shot input.
		_cancel_action()
		_cancel_action()
		if _active_panel:
			_active_panel.hide()
			_active_panel = null)
	_setup_milestone_system()
	_setup_seasonal_calendar()
	_setup_autosave_indicator()
	_setup_notification_toast()
	_setup_event_feed()
	_setup_course_rating_overlay()
	_setup_floating_text()
	_setup_shot_trails()
	_setup_shot_heatmap()
	_setup_course_aura()
	_setup_responsive_ui()
	_setup_input_layer()


## The title screen last of all: it covers the finished course, so the player
## only ever sees the menu once everything behind it is ready.
func _startup_title_screen() -> void:
	_initialize_game()

## Add the two input aids shared by every screen: the pointer that lets a
## keyboard or controller operate the course like a mouse, and the strip of
## prompts for the input method in use. Both are children of the HUD so they
## sit above the course and below the screens opened from it.
func _setup_input_layer() -> void:
	get_viewport().gui_focus_changed.connect(_remember_hud_focus)
	gamepad_cursor = GamepadCursor.new()
	gamepad_cursor.camera = camera
	$UI/HUD.add_child(gamepad_cursor)

	input_hint_bar = InputHintBar.new()
	$UI/HUD.add_child(input_hint_bar)

## True on the course with no screen/panel (or benchmark) owning input.
func _gameplay_input_active() -> bool:
	if not _startup_complete or is_instance_valid(_generating_course_screen):
		return false
	if _benchmark_tour_active:
		return false
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return false
	if has_node("/root/InputManager") and InputManager.has_visible_scope():
		return false
	return true

## Remember only gameplay HUD controls, not controls in overlay screens.
func _remember_hud_focus(control: Control) -> void:
	if control != null and not InputManager.has_visible_scope() \
			and $UI/HUD.is_ancestor_of(control):
		_last_hud_focus = weakref(control)


## View/Back on a controller (or the dock's own Tab cycle) can put focus on
## the bottom-left controls; this gives the player a deliberate way in.
func _focus_gameplay_hud(restore_last: bool = false) -> void:
	if restore_last and _last_hud_focus != null:
		var previous := _last_hud_focus.get_ref() as Control
		if is_instance_valid(previous) and previous.is_inside_tree() \
				and $UI/HUD.is_ancestor_of(previous) and previous.is_visible_in_tree() \
				and previous.focus_mode != Control.FOCUS_NONE \
				and not (previous is BaseButton and previous.disabled):
			InputManager.focus_control(previous)
			return
	if left_controls == null:
		return
	var target := left_controls.get_node_or_null("MenuBtn") as Control
	if target == null or not target.is_visible_in_tree():
		for child in left_controls.get_children():
			if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE \
					and (child as Control).is_visible_in_tree():
				target = child as Control
				break
	if target != null:
		InputManager.focus_control(target)

func _load_buildings_data() -> void:
	"""The building catalog the game plays with: data/buildings.json with every
	enabled mod's additions and overrides merged over it in load order."""
	building_registry = ContentRegistry.get_buildings()
	print("Loaded %d building types" % building_registry.size())

func _load_decorations_data() -> void:
	"""The merged decoration catalog, mods and all (see _load_buildings_data)."""
	decoration_registry = ContentRegistry.get_decorations()
	print("Loaded %d decoration types" % decoration_registry.size())

func _process(_delta: float) -> void:
	# While the startup slices run there is no HUD to update yet, and on the web
	# the frames between slices belong to the loading screen's repaint.
	if not _startup_complete:
		return
	# The title screen has no live course HUD to maintain. Avoid polling gameplay
	# controls, the minimap and tile inspection on every frame while it is open.
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU and not _benchmark_tour_active:
		return
	_update_ui()
	_update_mini_map_camera()
	_update_tile_inspector()

## The course hotkeys this scene dispatches. InputBindings owns their keys and
## Settings edits them; this list keeps one scene from claiming another's.
const COURSE_SHORTCUTS: Array[String] = [
	"pause_menu", "simulation_pause", "quick_save", "undo", "redo", "toggle_help",
	"financial_overview", "marketing", "tournaments", "analytics",
	"course_milestones", "world_milestones", "achievements", "calendar",
	"event_feed", "course_scorecard", "course_map", "routing_overlay",
	"shot_heatmap", "shot_heatmap_mode", "fairway_width_overlay",
	"weather_debug", "terrain_debug", "season_debug",
	"rotate_camera", "rotate_camera_cw", "gamepad_rotate_ccw", "gamepad_rotate_cw",
]

func _input(event: InputEvent) -> void:
	# A sliced startup leaves a window (on the web, a second or two of loader)
	# in which hotkeys would reach a half-built scene. The title screen handles
	# its own input as GUI events, so nothing is lost by standing down here.
	if not _startup_complete:
		return
	# The loading overlay blocks mouse clicks, but keyboard and controller
	# shortcuts are handled here before GUI input. Do not let them start another
	# game, open a menu or change the course while it is being prepared.
	if is_instance_valid(_generating_course_screen):
		get_viewport().set_input_as_handled()
		return
	# The benchmark tour owns the keyboard while it runs: Escape cancels it
	# (and restores the player's course); every other hotkey stands down so
	# nothing can pause, save or retool the course being measured. Mouse
	# events still pass so the tour banner's Cancel button stays clickable;
	# _unhandled_input below keeps them off the course itself.
	if _benchmark_tour_active and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			course_benchmark_tour.cancel()
		get_viewport().set_input_as_handled()
		return
	# Controller Start (or its keyboard binding, P by default) opens the pause
	# menu on the course. While the pause menu is up it resumes, matching
	# Escape; other screens keep their own back handling and ignore it.
	if InputBindings.matches(event, "pause_menu"):
		# Its key is also a letter, so a focused text field keeps it.
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return
		if not _benchmark_tour_active and GameManager.current_mode != GameManager.GameMode.MAIN_MENU:
			if pause_menu:
				_close_pause_menu()
			elif not InputManager.has_visible_scope():
				_show_pause_menu()
			get_viewport().set_input_as_handled()
		return
	# Unmodified arrows enter HUD navigation. Shift+arrows remain available to
	# move the course pointer without a mouse; consume this first arrow so it
	# restores focus rather than immediately advancing to another control.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] \
			and not (event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed) \
			and _gameplay_input_active() and get_viewport().gui_get_focus_owner() == null:
		_focus_gameplay_hud(true)
		get_viewport().set_input_as_handled()
		return
	# Shift+Tab (or LB) focuses the bottom-left dock when the course has no
	# focused control. Handled in _input because the GUI consumes the
	# ui_focus_prev action even when there is nothing focused to move from.
	if (event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_focus_next")) \
			and _gameplay_input_active() and get_viewport().gui_get_focus_owner() == null:
		_focus_gameplay_hud()
		get_viewport().set_input_as_handled()
		return
	# Controller X/Y (or whatever they are rebound to) rotate the course view
	# whenever the course owns input.
	if _gameplay_input_active():
		if InputBindings.matches(event, "gamepad_rotate_ccw"):
			_on_view_rotate_ccw()
			get_viewport().set_input_as_handled()
			return
		if InputBindings.matches(event, "gamepad_rotate_cw"):
			_on_view_rotate_cw()
			get_viewport().set_input_as_handled()
			return
	# Finish strokes even when the mouse is released over a panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and is_painting:
		_stop_painting()
	# ...and a right-click raise stroke ends the same way.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and is_painting:
		if elevation_tool.is_active():
			_stop_elevation_painting()
	# Keyboard shortcuts - handled in _input so UI controls don't swallow them
	if event is InputEventKey and event.pressed and not event.echo:
		# The World Map and the goal screens are screens of their own: while
		# one is up, no gameplay hotkey (Escape included) reaches the course
		# behind it. Their own Back button and Escape close them.
		if _world_map_is_open() or _course_map_is_open() or _goal_screen_is_open():
			return
		# Escape key: deselect active tool/panel first, then open pause menu
		if event.keycode == KEY_ESCAPE:
			if GameManager.current_mode != GameManager.GameMode.MAIN_MENU:
				# The event feed is a side panel, not a CenteredPanel: close it
				# before Escape reaches the pause menu.
				if event_feed_panel and event_feed_panel.visible:
					_toggle_event_feed()
					get_viewport().set_input_as_handled()
					return
				# Close open panel first
				if _active_panel and _active_panel.visible:
					_active_panel.hide()
					_active_panel = null
					get_viewport().set_input_as_handled()
					return
				# Deselect active tool/selection — let _unhandled_input handle it
				if _has_active_tool():
					return
				# Nothing active — open pause menu
				_toggle_pause_menu()
				get_viewport().set_input_as_handled()
				return

		# The binding registry answers "which action did this key or button
		# fire?" with its modifiers compared exactly, so a rebound key behaves
		# like the default one and Ctrl+S never counts as a plain S.
		var action := InputBindings.action_for_event(event, COURSE_SHORTCUTS)

		# The full-screen dashboard owns gameplay hotkeys while open. Keep its
		# finance and marketing shortcuts useful as close / page-switch actions.
		if financial_panel and financial_panel.visible:
			if action == "marketing":
				financial_panel.select_section(FinancialOverviewScreen.Section.MARKETING)
				get_viewport().set_input_as_handled()
			elif action == "financial_overview":
				_toggle_panel(financial_panel)
				get_viewport().set_input_as_handled()
			return

		# Don't process any gameplay hotkeys while in main menu
		if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
			return

		# Don't process hotkeys while pause menu is open
		if pause_menu:
			return

		# Skip non-modifier hotkeys if a text input has focus
		var focused = get_viewport().gui_get_focus_owner()
		var text_input_focused = focused is LineEdit or focused is TextEdit

		# The help sheet and the debug panels work from any mode and even
		# while a screen owns the keyboard.
		if action == "toggle_help":
			_toggle_hotkey_panel()
			get_viewport().set_input_as_handled()
			return
		if action == "weather_debug":
			_toggle_weather_debug_panel()
			get_viewport().set_input_as_handled()
			return
		if action == "season_debug":
			_toggle_season_debug_panel()
			get_viewport().set_input_as_handled()
			return

		# A screen or panel owns the keyboard while it is open: its own handler
		# reads Enter/Escape/arrows and the gameplay hotkeys stand down.
		if has_node("/root/InputManager") and InputManager.has_visible_scope():
			return

		if action.is_empty():
			return
		# Letters stay letters in a text field; modified shortcuts (quick save,
		# undo, redo) still work while typing.
		if text_input_focused and not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed):
			return

		match action:
			"quick_save":
				SaveManager.save_game("quicksave")
			"undo":
				_perform_undo()
			"redo":
				_perform_redo()
			"financial_overview":
				_toggle_financial_overview()
			"tournaments":
				_toggle_tournament_panel()
			"course_map":
				_toggle_course_map()
			"marketing":
				_toggle_marketing_panel()
			"analytics":
				_toggle_analytics_panel()
			"world_milestones":
				_toggle_world_milestones_screen()
			"course_milestones":
				_toggle_course_milestones_screen()
			"achievements":
				_toggle_achievements_screen()
			"calendar":
				_toggle_seasonal_calendar()
			"terrain_debug":
				_toggle_terrain_debug_overlay()
			"event_feed":
				_toggle_event_feed()
			"course_scorecard":
				_toggle_course_scorecard()
			"routing_overlay":
				if routing_overlay:
					routing_overlay.toggle()
			"shot_heatmap_mode":
				if terrain_grid.is_shot_heatmap_enabled():
					terrain_grid.cycle_shot_heatmap_mode()
			"shot_heatmap":
				terrain_grid.toggle_shot_heatmap()
			"fairway_width_overlay":
				_toggle_fairway_width_overlay()
			"rotate_camera":
				_on_view_rotate_ccw()
			"rotate_camera_cw":
				_on_view_rotate_cw()
			"simulation_pause":
				# With a HUD control focused, Space activates it (ui_accept)
				# instead of pausing.
				if get_viewport().gui_get_focus_owner() != null:
					return
				if GameManager.current_mode != GameManager.GameMode.SIMULATING:
					return
				_toggle_simulation_pause()
			_:
				return
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _startup_complete:
		return
	if is_instance_valid(_generating_course_screen):
		get_viewport().set_input_as_handled()
		return
	# Nothing paints, places or measures on a course the benchmark tour is
	# driving; the tour banner's own controls are GUI input and already ran.
	if _benchmark_tour_active:
		get_viewport().set_input_as_handled()
		return
	# View/Back on a controller puts focus on the bottom-left dock, so the
	# whole HUD is reachable without a mouse. Shift+Tab does the same for a
	# keyboard player (Tab itself keeps toggling the minimap).
	if (event.is_action_pressed("gamepad_focus_hud") \
			or event.is_action_pressed("ui_focus_prev")) \
			and _gameplay_input_active() and get_viewport().gui_get_focus_owner() == null:
		_focus_gameplay_hud()
		get_viewport().set_input_as_handled()
		return
	# B (or right-click) while a HUD control has focus leaves the HUD and hands
	# the pointer back to the course before it cancels any tool.
	if event.is_action_pressed("cancel") and _gameplay_input_active() \
			and get_viewport().gui_get_focus_owner() != null:
		InputManager.clear_focus()
		get_viewport().set_input_as_handled()
		return
	# While an elevation selector is active, right click raises terrain
	# instead of cancelling the tool (ESC still cancels).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and elevation_tool.is_active() \
			and GameManager.current_mode != GameManager.GameMode.MAIN_MENU \
			and not GameManager.is_paused:
		if event.pressed:
			_start_elevation_painting(true)
		else:
			_stop_elevation_painting()
		get_viewport().set_input_as_handled()
		return

	# Cancel action (ESC/right-click/B) closes the open popup panel first, then
	# deselects tools. B can therefore back out of any panel without a mouse.
	if event.is_action_pressed("cancel"):
		if _active_panel != null and _active_panel.visible:
			_active_panel.hide()
			_active_panel = null
			get_viewport().set_input_as_handled()
			return
		_cancel_action()
		return

	# Tycoon-style: build while golfers play (day always runs in SIMULATING)
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return

	# Block terrain painting/placement when popups are showing
	if GameManager.is_paused:
		return

	# Inspection is read-only, including modified clicks and entity picking.
	if inspect_mode and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		return

	# Ctrl+click drag measurement tool — intercept before painting
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_command_or_control_pressed():
			if event.pressed:
				var mouse_world = camera.get_mouse_world_position()
				_measure_start = terrain_grid.screen_to_grid(mouse_world)
				_measure_end = _measure_start
				_measuring = true
				_update_measure_overlay()
			else:
				_measuring = false
				_update_measure_overlay()
			get_viewport().set_input_as_handled()
			return

	if _measuring and event is InputEventMouseMotion:
		var mouse_world = camera.get_mouse_world_position()
		_measure_end = terrain_grid.screen_to_grid(mouse_world)
		_update_measure_overlay()
		return

	if event.is_action_pressed("select"):
		if elevation_tool.is_active():
			# Left click lowers the selected terrain.
			_start_elevation_painting(false)
			get_viewport().set_input_as_handled()
		else:
			var was_placing := placement_manager.placement_mode != PlacementManager.PlacementMode.NONE or bulldozer_mode
			_start_painting()
			# Consume the event when in placement/bulldozer mode to prevent propagation
			if was_placing:
				get_viewport().set_input_as_handled()
	elif event.is_action_released("select"):
		_stop_painting()
	if is_painting and event is InputEventMouseMotion:
		if elevation_tool.is_active():
			_paint_elevation_at_mouse()
		elif bulldozer_mode:
			_bulldoze_at_mouse()
		else:
			_paint_at_mouse()

func _connect_signals() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.hole_created.connect(_on_hole_created)
	EventBus.hole_deleted.connect(_on_hole_deleted)
	EventBus.hole_toggled.connect(_on_hole_toggled)
	# The Holes tab can re-par a hole, so its card re-reads the hole.
	EventBus.hole_updated.connect(_refresh_hole_button)
	# The round's order changed (Course Map, Routing Holes): the hole buttons
	# and the tee/cup states read the course again.
	EventBus.holes_reordered.connect(_on_holes_reordered)
	EventBus.end_of_day.connect(_on_end_of_day)
	EventBus.year_ended.connect(_on_year_ended)
	EventBus.load_completed.connect(_on_load_completed)
	EventBus.new_game_started.connect(_on_new_game_started)
	hole_manager.hole_selected.connect(_on_hole_flag_selected)
	terrain_grid.view_rotated.connect(_on_terrain_view_rotated)
	# Tee boxes, cups and holes decide what may be placed next and whether a hole
	# is ready to open, so the toolbar re-reads the rules whenever they change.
	terrain_grid.cup_tiles_changed.connect(_refresh_hole_layout_ui)
	EventBus.new_game_started.connect(_refresh_hole_layout_ui)
	EventBus.hole_created.connect(_on_hole_layout_hole_created)
	EventBus.hole_deleted.connect(_on_hole_layout_hole_deleted)
	EventBus.load_completed.connect(_on_hole_layout_load_completed)

func _connect_ui_buttons() -> void:
	# Replace old tool panel with new terrain toolbar
	_setup_terrain_toolbar()

	$UI/HUD/BottomBar/LeftControls/SpeedControls/PauseBtn.pressed.connect(_on_speed_selected.bind(GameManager.GameSpeed.PAUSED))
	# Normal, Fast and Ultra share this one button, so it cannot bind a fixed
	# speed — each press asks GameManager for the next tier instead.
	$UI/HUD/BottomBar/LeftControls/SpeedControls/SpeedBtn.pressed.connect(_on_speed_toggle_pressed)

func _setup_terrain_toolbar() -> void:
	"""Dock the tabbed toolbar into the bottom bar (right section, flush after left controls)"""
	terrain_toolbar = TerrainToolbar.new()
	terrain_toolbar.name = "TerrainToolbar"
	terrain_toolbar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# EXPAND_FILL so the toolbar consumes whatever horizontal room is left,
	# removing the empty gap that previously existed between LeftControls and toolbar.
	terrain_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(terrain_toolbar)
	# Keep the toolbar as the last child so it sits immediately after the separator
	bottom_bar.move_child(terrain_toolbar, bottom_bar.get_child_count() - 1)

	# The course holes buttons now live in the toolbar's Holes tab
	hole_grid = terrain_toolbar.hole_grid
	terrain_toolbar.terrain_grid = terrain_grid
	terrain_toolbar.hole_move_tee_requested.connect(_on_context_move_tee)
	terrain_toolbar.hole_move_green_requested.connect(_on_context_move_green)
	terrain_toolbar.hole_toggle_requested.connect(_on_context_toggle_hole)
	terrain_toolbar.hole_par_override_requested.connect(_on_context_par_override)
	terrain_toolbar.hole_delete_requested.connect(_on_context_delete_hole)
	terrain_toolbar.hole_locate_requested.connect(_on_hole_stats_selected)
	terrain_toolbar.hole_detail_changed.connect(_on_hole_detail_changed)

	# Build tool signals
	terrain_toolbar.tool_selected.connect(_on_tool_selected)
	terrain_toolbar.open_hole_pressed.connect(_on_open_hole_pressed)
	terrain_toolbar.building_placement_pressed.connect(_on_building_placement_pressed)
	terrain_toolbar.building_selected.connect(_on_building_type_selected_from_toolbar)
	terrain_toolbar.set_building_registry(building_registry)
	terrain_toolbar.decoration_placement_pressed.connect(_on_decoration_placement_pressed)
	terrain_toolbar.decoration_selected.connect(_on_decoration_type_selected_from_toolbar)
	terrain_toolbar.set_decoration_registry(decoration_registry)
	terrain_toolbar.elevation_tool_pressed.connect(_on_elevation_tool_pressed)
	terrain_toolbar.elevation_brush_size_changed.connect(_on_elevation_brush_size_changed)
	terrain_toolbar.elevation_brush_shape_changed.connect(_on_elevation_brush_shape_changed)
	terrain_toolbar.bulldozer_pressed.connect(_on_bulldozer_pressed)
	# Inspect lives on the Build tabs' pinned corner toggles now, not the dock.
	terrain_toolbar.inspect_toggled.connect(_on_inspect_toggled)
	inspect_btn = terrain_toolbar.inspect_button()
	terrain_toolbar.financial_overview_pressed.connect(_toggle_financial_overview)
	terrain_toolbar.course_review_pressed.connect(_open_course_map_aura)
	if terrain_toolbar.has_signal("aura_map_pressed"):
		terrain_toolbar.aura_map_pressed.connect(_open_course_map_aura)
	terrain_toolbar.brush_size_changed.connect(_on_brush_size_changed)
	terrain_toolbar.brush_shape_changed.connect(func(value: bool):
		round_brush = value
		placement_preview.round_brush = value
	)

	# Club / Player tab signals
	terrain_toolbar.play_course_pressed.connect(_on_play_course_pressed)
	terrain_toolbar.tournaments_pressed.connect(_toggle_tournament_panel)
	terrain_toolbar.world_map_pressed.connect(_open_world_map_from_club_tab)
	terrain_toolbar.course_map_pressed.connect(_open_course_map)
	terrain_toolbar.holes_map_pressed.connect(_open_course_map_routing)
	terrain_toolbar.staff_map_pressed.connect(_open_course_map_staff)
	terrain_toolbar.marketing_pressed.connect(_toggle_marketing_panel)
	terrain_toolbar.event_feed_pressed.connect(_toggle_event_feed)
	feed_btn = terrain_toolbar.feed_button
	terrain_toolbar.course_milestones_pressed.connect(_toggle_course_milestones_screen)
	terrain_toolbar.world_milestones_pressed.connect(_toggle_world_milestones_screen)
	terrain_toolbar.achievements_pressed.connect(_toggle_achievements_screen)
	terrain_toolbar.golfer_row_clicked.connect(_on_toolbar_golfer_clicked)
	terrain_toolbar.staff_area_move_requested.connect(_on_staff_area_move_requested)
	terrain_toolbar.golfer_data_provider = _collect_golfer_rows

	_sync_view_controls()

func _collect_golfer_rows() -> Array:
	"""Snapshot of golfers currently on the course, for the toolbar's Golfers tab."""
	var rows: Array = []
	for golfer in golfer_manager.get_active_golfers():
		rows.append({
			"id": golfer.golfer_id,
			"name": golfer.golfer_name,
			"tier": golfer.golfer_tier,
			"hole": golfer.current_hole + 1,
			"strokes": golfer.total_strokes + golfer.current_strokes,
			"attitude": golfer.attitude,
			"profile": _visitor_profile(golfer),
			"portrait": VisitorPortrait.for_golfer(golfer),
		})
	return rows

func _on_toolbar_golfer_clicked(golfer_id: int) -> void:
	"""Follow a golfer from the toolbar's Golfers tab."""
	var golfer = golfer_manager.get_golfer(golfer_id)
	if golfer:
		camera.focus_on(golfer.global_position, false)

func _visitor_profile(golfer: Golfer) -> Array[Dictionary]:
	# Value-only snapshot: departed visitors retain every detail without keeping
	# a freed golfer node alive. Active visitors refresh through the provider.
	var attributes := golfer.attributes
	var sections: Array[Dictionary] = []
	sections.append({"title": "Identity", "lines": [
		"Profession: " + attributes.profession,
		"Age / Gender: %d / %s" % [attributes.age, attributes.gender_name()],
		"Marital Status: " + attributes.marital_status_name(),
		"Returning guest: " + ("Yes" if golfer.is_returning_guest else "No")]})
	var traits: Array[String] = []
	for key in GolferAttributes.TRAIT_KEYS:
		traits.append("%s: %s" % [GolferAttributes.TRAIT_NAMES[key], "On" if attributes.trait_on(key) else "Off"])
	sections.append({"title": "Golfer Traits", "lines": traits})
	var skills: Array[String] = []
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		skills.append("%s: %s" % [GolferAttributes.GOLFER_SKILL_NAMES[key], "On" if attributes.skill_on(key) else "Off"])
	sections.append({"title": "Golfer Skills", "lines": skills})
	var golf_skills: Array[String] = []
	for i in GolferAttributes.GOLF_SKILLS.size():
		golf_skills.append("%s: %d%%" % [GolferAttributes.GOLF_SKILLS[i], attributes.golf_skill_percent(i)])
	sections.append({"title": "Golf Skills", "lines": golf_skills})
	sections.append({"title": "Golfer Statuses", "meters": {
		"Fun": attributes.fun, "Attitude": attributes.attitude,
		"Energy": attributes.energy, "Hunger": attributes.hunger, "Thirst": attributes.thirst}})
	var comments: Array[String] = ["Positive %d / Neutral %d / Negative %d" % [
		int(attributes.comment_counts.get("positive", 0)), int(attributes.comment_counts.get("neutral", 0)), int(attributes.comment_counts.get("negative", 0))]]
	for comment in attributes.recent_comments(5):
		comments.append("%s: %s" % [str(comment.get("sentiment", "neutral")).capitalize(), comment.get("text", "")])
	sections.append({"title": "Golfer Comments", "lines": comments})
	sections.append({"title": "Course Experience", "lines": [golfer.activity_text,
		"Traffic wait: %.1f game minutes" % (golfer.traffic_wait_seconds * 60.0 / GameManager.SECONDS_PER_GAME_HOUR),
		"Amenities used: %d" % golfer.amenities_used,
		FeedbackManager.guest_incident_text(golfer.golfer_id)]})
	var diff := golfer.total_strokes - golfer.total_par
	var score := "%d (%+d)" % [golfer.total_strokes, diff]
	if golfer.total_par <= 0:
		score = "Not started"
	elif diff == 0:
		score = "%d (E)" % golfer.total_strokes
	sections.append({"title": "Current Round", "lines": ["Score: " + score, "Hole: %d" % (golfer.current_hole + 1)]})
	var scores: Array[String] = []
	for hole in golfer.hole_scores:
		scores.append("H%d: %d strokes / par %d / %s" % [hole.hole, hole.strokes, hole.par, GolfRules.get_score_name(hole.strokes, hole.par)])
	sections.append({"title": "Scorecard", "lines": scores if not scores.is_empty() else ["No completed holes yet."]})
	return sections

func _on_play_course_pressed() -> void:
	terrain_toolbar.select_player_section(PlayerTab.PAGE_PLAY)

func _initialize_game() -> void:
	# Show the title screen instead of auto-starting
	_show_main_menu()

## ── Main menu ────────────────────────────────────────────────────────────
## Start New Game goes to the world map. Quick Start buys an affordable
## location itself, opening the map only if it cannot make the purchase.

func _show_main_menu() -> void:
	_close_world_map()
	_close_course_map()
	_close_goal_screens()
	main_menu = MainMenu.new()
	main_menu.name = "MainMenu"
	main_menu.start_new_game_requested.connect(_on_menu_start_new_game)
	main_menu.quick_start_requested.connect(_on_menu_quick_start)
	main_menu.continue_requested.connect(_on_menu_continue)
	main_menu.load_game_requested.connect(_on_main_menu_load)
	main_menu.achievements_requested.connect(_on_menu_achievements)
	main_menu.mods_requested.connect(_on_menu_mods)
	main_menu.edit_golfer_skins_requested.connect(_on_menu_edit_golfer_skins)
	main_menu.settings_requested.connect(_on_main_menu_settings)
	main_menu.quit_requested.connect(_on_quit_pressed)
	$UI/HUD.add_child(main_menu)
	# The title is an opaque UI screen; drawing the idle course underneath it
	# wastes fill-rate and texture bandwidth, especially on integrated GPUs.
	_set_course_world_visible(false)
	# Hide gameplay UI while in menu
	_set_gameplay_ui_visible(false)

## The title screen's Achievements tile: the career trophy room opens over
## the menu on the shared backdrop, and its Back comes home to the menu.

## The title screen's Mods tile: the mod library. Applying a new set from
## there reloads this scene wholesale, so the screen closes back to the
## menu whether the player applies or just browses.
func _on_menu_mods() -> void:
	_hide_main_menu()
	mods_screen = ModsScreen.new()
	mods_screen.name = "ModsScreen"
	mods_screen.back_requested.connect(func():
		if mods_screen:
			mods_screen.queue_free()
			mods_screen = null
			_show_main_menu())
	$UI/HUD.add_child(mods_screen)
	mods_screen.show()
	mods_screen.refresh()
	_set_gameplay_ui_visible(false)

func _on_menu_achievements() -> void:
	_open_goal_screen(MenuScreenKit.GoalTrack.ACHIEVEMENTS, GoalScreenOrigin.TITLE_SCREEN)

func _hide_main_menu() -> void:
	if main_menu:
		main_menu.queue_free()
		main_menu = null
	_disconnect_main_menu_load_signal()
	_set_course_world_visible(true)

## The title screen fully covers the idle course, so skip its rendering until
## the player leaves the menu (or starts a benchmark tour).
func _set_course_world_visible(world_visible: bool) -> void:
	if is_instance_valid(terrain_grid):
		terrain_grid.visible = world_visible
	if is_instance_valid(entity_layer):
		entity_layer.visible = world_visible
	var holes := get_node_or_null("Holes") as CanvasItem
	if holes != null:
		holes.visible = world_visible

## Hand the player the course a save just restored. The title screen and the
## gameplay HUD are the two halves of one trade — the menu was hiding the
## course while it was up — so leaving the menu is the same set of moves
## whichever way in the save arrived, the archive or the Continue card.
func _leave_title_screen_for_course() -> void:
	_hide_main_menu()
	_close_world_map()
	_set_gameplay_ui_visible(true)

## Start New Game: company setup first, then the world map.
func _on_menu_start_new_game() -> void:
	_hide_main_menu()
	var screen := StartNewGameScreen.new()
	screen.name = "StartNewGameScreen"
	screen.back_requested.connect(func():
		screen.queue_free()
		_show_main_menu())
	screen.next_requested.connect(func(options: Dictionary):
		screen.queue_free()
		WorldMap.new_world(options)
		_show_world_map_screen(true))
	$UI/HUD.add_child(screen)
	_set_gameplay_ui_visible(false)

## Quick Start: the agreed defaults (random company name, Normal, $100,000,
## 3 generated holes, every feature off), then a random location the company can
## afford is bought and its course is started straight away.
func _on_menu_quick_start() -> void:
	if is_instance_valid(_generating_course_screen):
		return  # Ignore repeated clicks / shortcuts while a course is starting.

	# World creation, location signals and GameManager.new_game can all do
	# substantial synchronous work. Show the loading screen *before* any of it,
	# while the idle course is still hidden behind the title screen.
	var holes := WorldMapStateScript.QUICK_START_HOLES
	var holes_stage := GeneratingCourseScreen.holes_stage_text(false, holes, false)
	var loading_overlay := GeneratingCourseScreen.new()
	loading_overlay.name = "GeneratingCourseScreen"
	loading_overlay.setup("Your new course", "%d holes" % holes,
		GeneratingCourseScreen.stages_for_job(holes_stage, true, true))
	_generating_course_screen = loading_overlay
	add_child(loading_overlay)
	loading_overlay.set_stage_by_title(GeneratingCourseScreen.STAGE_LOCATION)
	if is_instance_valid(main_menu):
		main_menu.hide()

	# process_frame fires before _process and drawing. Waiting twice gives the
	# screen a complete frame to actually paint, even in a slow browser build.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return

	_hide_main_menu()
	WorldMap.new_world(WorldMapStateScript.quick_start_options())
	var location_id := WorldMap.pick_random_affordable_location()
	if location_id.is_empty() or not WorldMap.buy_location(location_id):
		# Nothing affordable (or the purchase failed): let the player choose.
		_dismiss_generating_course_screen()
		EventBus.notify("No location is affordable right now. Choose one on the World Map.", "info")
		_show_world_map_screen(true)
		return
	WorldMap.set_active_location(location_id)
	# Give the screen another repaint between the world roll and course setup.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_start_new_course_at_location(location_id, WorldMapOrigin.TITLE_SCREEN)


## Remove the shared loader on either successful generation or a fallback to
## the world map. Clear the reference immediately so input can resume.
func _dismiss_generating_course_screen() -> void:
	if is_instance_valid(_generating_course_screen):
		_generating_course_screen.queue_free()
	_generating_course_screen = null

## Continue: play the newest checkpoint straight away, the shortcut past the
## archive. The load itself is the archive's; what Continue adds is taking the
## player into the course once it lands (see _leave_title_screen_for_course).
##
## A checkpoint that will not come back — deleted while the menu was up, or
## written by a version this build cannot read — leaves the title screen
## standing. load_game() has already said why, and the menu is the one place
## left to pick another save or start over; swapping it for an empty course
## would strand the player with nothing to go back to.
func _on_menu_continue(save_name: String) -> void:
	if save_name.is_empty():
		return
	if not SaveManager.load_game(save_name):
		return
	_leave_title_screen_for_course()

func _on_quit_pressed() -> void:
	get_tree().quit()

## ── Course map ───────────────────────────────────────────────────────────
## The Course Map takes the whole window and freezes the day while it is up, the
## same way the world map does. It edits the live course in place, so a parcel
## bought or a hole moved is there the moment the course is handed back.

## The Club tab's Land Parcels button, and the Shift+M hotkey. `mode` is the
## mode the map opens on: Land unless the caller asks for another — the
## Holes tab's Holes Map button asks for Routing Holes.
func _open_course_map(mode: int = CourseMapView.Mode.LAND) -> void:
	if _course_map_is_open():
		course_map_screen.set_mode(mode)
		return
	_course_map_restore_paused = GameManager.is_paused
	GameManager.is_paused = true
	_set_gameplay_ui_visible(false)
	var hud := $UI/HUD
	# A screen that is on its way out (Shift+M tapped twice in one frame) is not
	# the screen to hand the course to: it is replaced rather than reused.
	var existing := hud.get_node_or_null("CourseMapScreen") as CourseMapScreen
	course_map_screen = null if existing != null and existing.is_queued_for_deletion() else existing
	if course_map_screen == null:
		course_map_screen = CourseMapScreen.new()
		course_map_screen.name = "CourseMapScreen"
		course_map_screen.back_requested.connect(_on_course_map_back)
		if course_map_screen.has_signal("advice_action_requested"):
			course_map_screen.advice_action_requested.connect(_on_course_map_advice_action)
		hud.add_child(course_map_screen)
		if course_map_screen._aura_panel:
			course_map_screen._aura_panel.rating_updated.connect(_on_aura_rating_updated)
	else:
		# Reused screen: ensure advice forwarding is still connected
		if course_map_screen.has_signal("advice_action_requested") and not course_map_screen.advice_action_requested.is_connected(_on_course_map_advice_action):
			course_map_screen.advice_action_requested.connect(_on_course_map_advice_action)
		if course_map_screen._aura_panel and not course_map_screen._aura_panel.rating_updated.is_connected(_on_aura_rating_updated):
			course_map_screen._aura_panel.rating_updated.connect(_on_aura_rating_updated)
	course_map_screen.show()
	course_map_screen.set_mode(mode)
	course_map_screen.refresh()

## The Holes tab's Holes Map button: the Course Map on Routing Holes,
## the mode that is the round the holes make.
func _open_course_map_routing() -> void:
	_open_course_map(CourseMapView.Mode.ROUTING)

## The Staff tab's Staff Map button: the Course Map on Staff, the mode
## that is the crew's ground.
func _open_course_map_staff() -> void:
	_open_course_map(CourseMapView.Mode.STAFF)

## The Club tab's Review entry and the star rating now open the Course Map
## on Aura, where the full Course Review lives.
func _open_course_map_aura() -> void:
	_open_course_map(CourseMapView.Mode.AURA)

func _close_course_map() -> void:
	if course_map_screen:
		course_map_screen.queue_free()
		course_map_screen = null

## The Shift+M hotkey: open the map, or put it away again.
func _toggle_course_map() -> void:
	if _course_map_is_open():
		_on_course_map_back()
		return
	_open_course_map()

## True while the Course Map is up. It takes the whole window, so the course
## behind it must not answer gameplay hotkeys while it is open.
func _course_map_is_open() -> bool:
	return course_map_screen != null and not course_map_screen.is_queued_for_deletion() \
		and course_map_screen.visible

func _on_course_map_back() -> void:
	_close_course_map()
	_leave_course_map()

func _on_course_map_advice_action(advice: Dictionary) -> void:
	# Advice that wasn't a locate (finance, garden, build, observe) comes from
	# the Aura panel's unified review. Close the map first, then perform the
	# action on the course.
	_close_course_map()
	_leave_course_map()
	var action := str(advice.get("action", ""))
	match action:
		"finance":
			_toggle_panel(financial_panel)
		"garden":
			_on_decoration_placement_pressed()
		"build":
			_on_open_hole_pressed()
		"observe":
			EventBus.notify(str(advice.get("detail", advice.get("title", ""))), "info")
		_:
			if advice.has("position"):
				_cancel_action()
				camera.focus_on_smooth(terrain_grid.grid_to_screen_center(advice["position"]))
				EventBus.notify(str(advice.get("title", "")), "info")
			else:
				EventBus.notify(str(advice.get("title", "")), "info")

## Hand the course back after the map closes: the gameplay UI returns and the day
## resumes only if it was running before the map opened.
func _leave_course_map() -> void:
	_set_gameplay_ui_visible(true)
	GameManager.is_paused = _course_map_restore_paused

## ── World map ────────────────────────────────────────────────────────────

## Show the globe. `from_menu` is the legacy switch the title screen uses: true
## from the title screen (Start New Game / Quick Start), false for the in-game
## entry tests and harnesses use, which returns to the pause menu. The Club tab
## opens the map through _open_world_map_from_club_tab().
func _show_world_map_screen(from_menu: bool) -> void:
	_show_world_map_screen_at(WorldMapOrigin.TITLE_SCREEN if from_menu else WorldMapOrigin.PAUSE_MENU)

## The Club tab's World Map button: browse the company's sites without leaving
## the course. The map freezes the day and takes the screen while it is up —
## the same hands-off state the pause menu handed it — so a site can be bought,
## browsed or switched without the course running on behind it.
func _open_world_map_from_club_tab() -> void:
	_world_map_restore_paused = GameManager.is_paused
	GameManager.is_paused = true
	_set_gameplay_ui_visible(false)
	_show_world_map_screen_at(WorldMapOrigin.CLUB_TAB)

func _show_world_map_screen_at(origin: int) -> void:
	_world_map_origin = origin
	if origin == WorldMapOrigin.TITLE_SCREEN:
		_hide_main_menu()
		_set_gameplay_ui_visible(false)
		GameManager.set_mode(GameManager.GameMode.MAIN_MENU)

	var hud := $UI/HUD
	world_map_screen = hud.get_node_or_null("WorldMapScreen") as WorldMapScreen
	if world_map_screen == null:
		world_map_screen = WorldMapScreen.new()
		world_map_screen.name = "WorldMapScreen"
		world_map_screen.play_location_requested.connect(_on_world_map_play_location)
		world_map_screen.back_requested.connect(_on_world_map_back)
		hud.add_child(world_map_screen)
	world_map_screen.show()
	world_map_screen.refresh()

func _close_world_map() -> void:
	if world_map_screen:
		world_map_screen.queue_free()
		world_map_screen = null

## True while the world map screen is up. It takes the whole window, so the
## course behind it must not answer gameplay hotkeys while it is open.
func _world_map_is_open() -> bool:
	return world_map_screen != null and world_map_screen.visible

func _on_world_map_back() -> void:
	var origin := _world_map_origin
	_close_world_map()
	match origin:
		WorldMapOrigin.TITLE_SCREEN:
			_show_main_menu()
		WorldMapOrigin.CLUB_TAB:
			_leave_club_world_map()
		_:
			# Back to the paused game it was opened from.
			_show_pause_menu()

## Hand the course back after the world map closes: the gameplay UI returns and
## the day resumes only if it was running before the map opened.
func _leave_club_world_map() -> void:
	_set_gameplay_ui_visible(true)
	GameManager.is_paused = _world_map_restore_paused

## The player pressed Play on an owned location, or Buy & Play on an unowned
## one: start the company's game there, restoring the course they left when
## there is one.
func _on_world_map_play_location(location_id: String) -> void:
	if not WorldMap.is_owned(location_id):
		return
	# Remember the course being left exactly as it is now.
	var leaving := WorldMap.active_location_id
	if not leaving.is_empty() and leaving != location_id and GameManager.current_course != null:
		WorldMap.take_snapshot(leaving, SaveManager.build_location_snapshot())

	var origin := _world_map_origin
	WorldMap.set_active_location(location_id)
	_close_world_map()

	var snapshot := WorldMap.get_snapshot(location_id)
	var can_restore := not snapshot.is_empty() and GameManager.current_course != null
	if can_restore:
		WorldMap.apply_location_land(location_id)
		SaveManager.switch_to_location(snapshot)
		_after_location_activated(origin)
		EventBus.notify("Moved to %s." % WorldMap.get_active_location().get("name", location_id), "info")
		return

	# Nothing to restore: build this location's course from the company's
	# Start New Game options (location theme, generated holes, money).
	_start_new_course_at_location(location_id, origin)

func _start_new_course_at_location(location_id: String, origin: int) -> void:
	var def := WorldLocations.get_definition(location_id)
	WorldMap.apply_location_land(location_id)
	# Only the first location the player bought gets the pre-generated holes
	# from the Start New Game screen; every later purchase starts empty.
	var holes_for_this_location: int = WorldMap.holes_to_generate_for(location_id)
	_generated_holes_pending = holes_for_this_location
	_set_gameplay_ui_visible(true)
	if origin == WorldMapOrigin.TITLE_SCREEN:
		GameManager.set_mode(GameManager.GameMode.SIMULATING)

	# The balance carries over: buying the location before starting the course
	# comes out of the same company budget.
	GameManager.new_game(_course_name_for_location(def), int(def.get("theme", CourseTheme.Type.PARKLAND)),
		WorldMap.difficulty, {
			"company_name": WorldMap.company_name,
			"starting_money": GameManager.money,
			"unlimited": GameManager.unlimited_money,
			"generated_holes": holes_for_this_location,
			"features": WorldMap.features,
		})

	# Center camera on the middle of the grid
	_center_camera_on_course()
	# Start with no tool selected — player chooses their first action
	current_tool = -1
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	if placement_preview:
		placement_preview.set_terrain_painting_enabled(false)
	# The new course replaces the one the map was opened over, so hand the
	# course back the same way Back does: gameplay UI on, pre-map speed back.
	if origin == WorldMapOrigin.CLUB_TAB:
		_leave_club_world_map()

## The default course name for a location: "Monterey Golf Club".
static func _course_name_for_location(definition: Dictionary) -> String:
	var course_name := str(definition.get("name", "New Course"))
	return course_name if course_name.to_lower().ends_with("golf club") else "%s Golf Club" % course_name

## Shared finishing touches after a location's course becomes the live one.
func _after_location_activated(origin: int) -> void:
	_set_gameplay_ui_visible(true)
	match origin:
		WorldMapOrigin.TITLE_SCREEN:
			GameManager.set_mode(GameManager.GameMode.SIMULATING)
			GameManager.is_paused = false
		WorldMapOrigin.CLUB_TAB:
			# Picked from the Club tab: hand the course back, now at the new site.
			_leave_club_world_map()
		_:
			# Came from the pause menu: leave the game paused and show it again.
			_show_pause_menu()

## Legacy entry point (tests and harnesses): start a game directly on a course
## name and theme, bypassing the world map.
func _on_main_menu_new_game(course_name: String, theme_type: int, difficulty: int = -1, options: Dictionary = {}) -> void:
	var chosen_difficulty: int = difficulty if difficulty >= 0 else WorldMap.difficulty
	_pending_terrain_seed = int(options.get("terrain_seed", 0))
	_hide_main_menu()
	WorldMap.ensure_legacy_world(theme_type)
	WorldMap.apply_location_land(WorldMap.active_location_id)
	_set_gameplay_ui_visible(true)

	GameManager.new_game(course_name, theme_type, chosen_difficulty, options)
	if milestone_manager:
		# A brand-new company: per-save milestones lock again.
		milestone_manager.reset_for_new_save()

	# Center camera on the middle of the grid
	_center_camera_on_course()
	# Start with no tool selected — player chooses their first action
	current_tool = -1
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	if placement_preview:
		placement_preview.set_terrain_painting_enabled(false)

var _quick_start_pending: bool = false
var _prebuilt_pending: String = ""  # Package ID, empty = not pending
var _prebuilt_money: int = 0  # Money to restore after new_game() resets it
## Terrain seed for the next course's natural generation, stashed by the start
## entry points (0 lets the generator pick one from the clock). Tests pin it so
## every run builds the same course.
var _pending_terrain_seed: int = 0

func _on_main_menu_prebuilt_course(course_name: String, theme_type: int, package_id: String) -> void:
	"""Legacy entry point: start a new game with a prebuilt course package."""
	var difficulty: int = WorldMap.difficulty
	_hide_main_menu()
	WorldMap.ensure_legacy_world(theme_type)
	WorldMap.apply_location_land(WorldMap.active_location_id)
	_set_gameplay_ui_visible(true)

	# Save money before new_game() resets it (already has cost deducted)
	_prebuilt_money = GameManager.money
	_prebuilt_pending = package_id
	GameManager.new_game(course_name, theme_type, difficulty)
	if milestone_manager:
		# A brand-new company: per-save milestones lock again.
		milestone_manager.reset_for_new_save()

	_center_camera_on_course()
	current_tool = -1
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	if placement_preview:
		placement_preview.set_terrain_painting_enabled(false)

func _on_main_menu_quick_start(course_name: String = "", theme_type: int = -1,
		options: Dictionary = {}) -> void:
	"""Legacy entry point (tests and harnesses): start a game right away on the
	landscaped nine-hole Quick Start course. The title screen's Quick Start
	button and hotkey use the world-map flow instead."""
	var theme := theme_type if theme_type >= 0 else CourseTheme.Type.PARKLAND
	var difficulty: int = WorldMap.difficulty
	_pending_terrain_seed = int(options.get("terrain_seed", 0))
	_hide_main_menu()
	WorldMap.ensure_legacy_world(theme)
	WorldMap.apply_location_land(WorldMap.active_location_id)
	_set_gameplay_ui_visible(true)

	# Flag so _on_new_game_started knows to build the quick-start course
	_quick_start_pending = true
	GameManager.new_game(course_name if not course_name.is_empty() else "Quick Start Course", theme, difficulty)
	if milestone_manager:
		# A brand-new company: per-save milestones lock again.
		milestone_manager.reset_for_new_save()

	_center_camera_on_course()
	current_tool = -1
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	_cancel_elevation_mode()
	if placement_preview:
		placement_preview.set_terrain_painting_enabled(false)

func _on_main_menu_load() -> void:
	# Show save/load panel overlaid on the main menu (don't dismiss menu yet)
	var hud = $UI/HUD
	var existing = hud.get_node_or_null("SaveLoadPanel")
	if existing:
		existing.queue_free()
		return

	var panel = SaveLoadPanel.new()
	panel.name = "SaveLoadPanel"
	panel.allow_save = false
	panel.open_mode = SaveLoadPanel.ScreenMode.LOAD

	# When a save is loaded, dismiss the main menu
	panel.panel_closed.connect(_on_main_menu_load_panel_closed)
	panel.quit_to_menu_requested.connect(_on_quit_to_menu)
	hud.add_child(panel)

	# Connect load_completed to dismiss the menu on successful load
	if not EventBus.load_completed.is_connected(_on_main_menu_load_completed):
		EventBus.load_completed.connect(_on_main_menu_load_completed)

## Edit Golfer Skins: the skin studio, opened from the title screen. It writes
## its skins to user://golfer_skins (see GolferSkins) and hands every golfer on
## the course their new colours as soon as one is saved.
func _on_menu_edit_golfer_skins() -> void:
	_hide_main_menu()
	var screen := EditGolferSkinsScreen.new()
	screen.name = "EditGolferSkinsScreen"
	screen.back_requested.connect(func():
		screen.queue_free()
		_show_main_menu())
	$UI/HUD.add_child(screen)
	_set_gameplay_ui_visible(false)

func _on_main_menu_settings() -> void:
	"""Show settings from main menu."""
	var settings = SettingsMenu.new()
	settings.name = "SettingsMenu"
	settings.origin = SettingsMenu.Origin.MAIN_MENU
	_settings_opened_from_main_menu = true
	# No need to re-show anything when closing from main menu
	settings.close_requested.connect(func(): pass)
	settings.results_requested.connect(_show_benchmark_results)
	settings.tour_requested.connect(start_course_benchmark)
	settings.data_deleted.connect(_on_settings_data_deleted)
	$UI/HUD.add_child(settings)

func _on_main_menu_load_panel_closed() -> void:
	"""Save/load panel closed without loading — return to main menu."""
	_disconnect_main_menu_load_signal()

func _on_main_menu_load_completed(success: bool) -> void:
	"""A save was loaded from the main menu — dismiss menu and show game."""
	_disconnect_main_menu_load_signal()
	if success:
		_leave_title_screen_for_course()

func _disconnect_main_menu_load_signal() -> void:
	if EventBus.load_completed.is_connected(_on_main_menu_load_completed):
		EventBus.load_completed.disconnect(_on_main_menu_load_completed)

func _set_gameplay_ui_visible(visible_flag: bool) -> void:
	# Toggle visibility of gameplay HUD elements
	# Exclude popup panels that should remain hidden until explicitly toggled
	var popup_panels = ["MainMenu", "StartNewGameScreen", "EditGolferSkinsScreen", "WorldMapScreen", "CourseMapScreen", "PauseMenu", "GameOverPanel", "SettingsMenu", "BenchmarkResultsScreen", "ModsScreen", "CourseMilestonesScreen", "WorldMilestonesScreen", "AchievementsScreen", "SeasonalCalendarPanel", "TournamentPanel", "FinancialOverviewScreen", "FinancialPanel", "HoleStatsPanel", "SaveLoadPanel", "BuildingInfoPanel", "MarketingPanel", "HotkeyPanel", "WeatherDebugPanel", "SeasonDebugPanel", "AnalyticsPanel", "GolferInfoPopup", "TournamentResultsPopup", "CourseRatingOverlay", "EventFeedPanel", "TileInspector"]
	var hud = $UI/HUD
	for child in hud.get_children():
		if child == mini_map:
			mini_map.hud_visible = visible_flag
		elif child.name not in popup_panels:
			child.visible = visible_flag

## Scores for the owner's rounds read out in the top-left corner of the screen,
## away from the shot controls in the bottom bar: the round card (practice round,
## vs pro) and the live tournament board share one dock, one under the other.
func _setup_scores_dock() -> void:
	scores_dock = ScoresDock.new()
	$UI/HUD.add_child(scores_dock)
	scores_dock.attach_leaderboard(tournament_leaderboard)
	# Stack the round scores under the location postcard in the top-left corner.
	_dock_scores_below_banner()
	tournament_leaderboard.return_to_course.connect(func():
		terrain_toolbar.select_player_section(PlayerTab.PAGE_PLAY)
		terrain_toolbar.player_tab.set_playing(false))

func _setup_hud_status_column() -> void:
	"""Replace the legacy full-width TopBar with the top-right status column."""
	var old_top_bar = $UI/HUD/StatusColumnPlaceholder
	var hud = $UI/HUD

	# Remove the placeholder node the scene ships with
	if old_top_bar:
		for child in old_top_bar.get_children():
			child.queue_free()
		old_top_bar.queue_free()

	# Create the status column (anchors itself to the top-right corner)
	hud_status_column = HUDStatusColumn.new()
	hud_status_column.name = "HUDStatusColumn"

	# Connect status clicks to panels
	hud_status_column.money_clicked.connect(_on_money_clicked)
	hud_status_column.rating_clicked.connect(_open_course_map_aura)

	# Add to HUD as first child
	hud.add_child(hud_status_column)
	hud.move_child(hud_status_column, 0)

## The top-left postcard: a per-location pixel-art picture beside the course
## name and the date. The scores dock stacks underneath it (see _setup_scores_dock).
func _setup_course_location_banner() -> void:
	course_location_banner = CourseLocationBanner.new()
	course_location_banner.name = "CourseLocationBanner"
	$UI/HUD.add_child(course_location_banner)
	# Folding the view controls in or out changes the corner's height, so the
	# score cards below it follow.
	course_location_banner.layout_changed.connect(_dock_scores_below_banner)
	# The postcard carries the course's view controls in the same corner.
	_fill_view_controls()
	_dock_scores_below_banner()

## Take the banner's view controls: the two Rotate arrows on the right of its
## details card, and the facing chip in the card's top-right corner that shows
## the direction the course faces and folds the arrows away.
func _fill_view_controls() -> void:
	rotate_view_controls = course_location_banner.rotate_controls
	rotate_ccw_btn = course_location_banner.rotate_ccw_btn
	rotate_cw_btn = course_location_banner.rotate_cw_btn
	orientation_toggle = course_location_banner.orientation_toggle
	rotate_ccw_btn.pressed.connect(_on_view_rotate_ccw)
	rotate_cw_btn.pressed.connect(_on_view_rotate_cw)
	_sync_view_controls()

## Keep the scores dock just under the location banner, in both layouts.
func _dock_scores_below_banner() -> void:
	if scores_dock == null or course_location_banner == null:
		return
	scores_dock.set_top_clearance(
		course_location_banner.get_occupied_height() + UIConstants.COURSE_BANNER_GAP)

## Hand the loaded mods their HUD space: each registered widget factory
## returns a Control, added to the HUD in load order. The Weather mod's
## rain and tint arrive through EventBus.main_scene_ready instead - they
## belong to the world layers, not the HUD.
func _setup_mod_hud_widgets() -> void:
	for widget in ModManager.get_hud_widgets():
		var factory: Callable = widget.get("factory", Callable())
		if not factory.is_valid():
			continue
		var made: Variant = factory.call()
		if made is Control:
			(made as Control).name = "ModWidget_" + str(widget.get("mod_id", "mod")).replace(".", "_").replace("-", "_")
			$UI/HUD.add_child(made)

func _setup_placement_preview() -> void:
	"""Create placement preview overlay for building and decoration placement"""
	placement_preview = PlacementPreview.new()
	placement_preview.name = "PlacementPreview"
	placement_preview.set_terrain_grid(terrain_grid)
	placement_preview.set_placement_manager(placement_manager)
	placement_preview.set_camera(camera)
	# Add as child of main scene so it renders above terrain
	add_child(placement_preview)

	# Measurement overlay for ctrl-click drag yardage display
	_measure_overlay = MeasurementOverlay.new()
	_measure_overlay.name = "MeasureOverlay"
	_measure_overlay.terrain_grid = terrain_grid
	add_child(_measure_overlay)

func _setup_bottom_bar() -> void:
	# Each side paints its own curved backdrop. The container itself must not
	# cover the course visible between or above those silhouettes.
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.add_theme_constant_override("separation", 0)
	bottom_bar.offset_top = -Screen.bottom_bar_height()

func _toggle_panel(panel: CenteredPanel) -> void:
	"""Toggle a panel with mutual exclusion — opening one closes the previous."""
	if panel == _active_panel and panel.visible:
		panel.hide()
		_active_panel = null
		return
	# Close the currently open panel (if different)
	if _active_panel and _active_panel != panel and _active_panel.visible:
		_active_panel.hide()
	_active_panel = panel
	panel.toggle()

func _update_ui() -> void:
	# HUDStatusColumn now handles money/day/reputation/weather/wind updates via signals
	# Only update button states here
	_update_button_states()

func _update_button_states() -> void:
	"""Update button appearance based on game mode and speed"""
	# Speed controls are always visible — tycoon-style, build while playing
	pause_btn.visible = true
	speed_btn.visible = true
	pause_btn.disabled = false
	speed_btn.disabled = false
	pause_btn.text = "||"
	# The speed button owns every running speed: its icon and face show the
	# tier that is running, its tooltip names the tier a press cycles to, and
	# while paused it advertises the Normal a press resumes at.
	var speed: int = GameManager.current_speed
	speed_btn.text = speed_toggle_label(speed)
	speed_btn.glyph = speed_toggle_glyph(speed)
	speed_btn.tooltip_text = speed_toggle_tooltip(speed)
	speed_btn.accessibility_name = "Game speed: %s" % _speed_tier_name(speed)

	# Gold-lit rings communicate speed without dimming the icons into the bar.
	pause_btn.active = speed == GameManager.GameSpeed.PAUSED
	speed_btn.active = GameManagerScript.is_running_speed(speed)

func _start_painting() -> void:
	if inspect_mode:
		return
	# Repositioning a staff member's designated area takes the next click.
	if _staff_area_mode_index >= 0:
		_handle_staff_area_click(terrain_grid.screen_to_grid(camera.get_mouse_world_position()))
		return

	# Choosing the ground the owner's own golfer works takes the next click.
	if _owner_area_mode:
		_handle_owner_area_click(terrain_grid.screen_to_grid(camera.get_mouse_world_position()))
		return

	# The building being carried (the clubhouse) takes the next click.
	if _moving_building != null:
		_handle_building_move_click(terrain_grid.screen_to_grid(camera.get_mouse_world_position()))
		return

	# Handle hole move mode clicks first
	if _hole_move_mode != HoleMoveMode.NONE:
		var mouse_world = camera.get_mouse_world_position()
		var grid_pos = terrain_grid.screen_to_grid(mouse_world)
		_handle_hole_move_click(grid_pos)
		return

	# In the null selector state, a hole's tee or cup opens its details on the
	# Holes tab. During the owner's practice round, leave the click for aiming.
	if not _has_active_tool():
		if is_instance_valid(player_round) and player_round.active:
			return
		var mouse_world = camera.get_mouse_world_position()
		var grid_pos = terrain_grid.screen_to_grid(mouse_world)
		var tile_type = terrain_grid.get_tile(grid_pos)
		if tile_type == TerrainTypes.Type.TEE_BOX or tile_type == TerrainTypes.Type.GREEN:
			var hole = hole_manager.get_hole_at_position(grid_pos)
			if hole:
				_on_hole_button_pressed(hole.hole_number)
				return
		return

	# Check if we're in bulldozer mode — supports click-and-drag
	if bulldozer_mode:
		is_painting = true
		_bulldoze_drag_count = 0
		_bulldoze_drag_cost = 0
		_bulldoze_at_mouse()
		return

	# Check if we're in placement mode (a building or a decoration; both are a
	# single click, unlike the terrain brush)
	if placement_manager.placement_mode != PlacementManager.PlacementMode.NONE:
		var mouse_world = camera.get_mouse_world_position()
		var grid_pos = terrain_grid.screen_to_grid(mouse_world)
		_handle_placement_click(grid_pos)
		return

	is_painting = true
	_tee_block_notified = false
	_path_block_notified = false
	undo_manager.begin_stroke()
	_paint_at_mouse()

func _stop_painting() -> void:
	# Show bulldozer drag summary if items were cleared
	if bulldozer_mode and _bulldoze_drag_count > 0:
		EventBus.notify("Cleared %d item%s (-$%d)" % [_bulldoze_drag_count, "s" if _bulldoze_drag_count != 1 else "", _bulldoze_drag_cost], "info")
	# Elevation strokes (left lowers / right raises) end through their own path.
	if elevation_tool.is_active() and elevation_tool.elevation_mode != ElevationTool.ElevationMode.NONE:
		_stop_elevation_painting()
		return
	is_painting = false
	_tee_block_notified = false
	_path_block_notified = false
	last_paint_pos = Vector2i(-1, -1)
	last_paint_anchor = Vector2i(-1, -1)
	if not elevation_tool.is_active():
		undo_manager.end_stroke()

func _paint_at_mouse() -> void:
	if current_tool <= TerrainTypes.Type.EMPTY: return
	var grid_pos := terrain_grid.screen_to_grid(camera.get_mouse_world_position())
	if grid_pos == last_paint_pos: return
	# Sample every crossed tile so quick mouse drags cannot leave holes.
	var start := last_paint_pos if last_paint_pos != Vector2i(-1, -1) else grid_pos
	# Stream channels only join edge-adjacent tiles, so stream strokes never
	# step diagonally.
	var stroke := TerrainBrush.centers_4_connected(start, grid_pos) \
			if current_tool == TerrainTypes.Type.STREAM else TerrainBrush.centers(start, grid_pos)
	for center in stroke:
		if terrain_grid.is_valid_position(center): _paint_terrain_stamp(center)
	last_paint_pos = grid_pos

func _paint_terrain_stamp(grid_pos: Vector2i) -> void:
	# The Path improvement is laid on top of the terrain instead of replacing
	# it, so it has its own stamp.
	if current_tool == TerrainTypes.WALKING_PATH_TOOL:
		_paint_walking_path_stamp(grid_pos)
		return

	# No tool selected: painting the first tee deselects the tee tool (it is
	# unselectable while that tee waits), so a follow-up stamp must do nothing
	# instead of repainting the ground to Empty. _paint_at_mouse() refuses a
	# stamp without a tool too; the stamp itself has to hold the same line.
	if current_tool <= TerrainTypes.Type.EMPTY:
		return

	# Capture the name now: the tee rules may deselect the tool mid-stroke and
	# the transaction log should still name what was painted.
	var stamp_tool_name := TerrainTypes.get_type_name(current_tool)
	var cost = TerrainTypes.get_placement_cost(current_tool)
	if cost > 0 and not GameManager.can_afford(cost):
		if GameManager.is_bankrupt():
			EventBus.notify(GameManager.spending_blocked_message(), "error")
		else:
			EventBus.notify("Not enough money!", "error")
		return

	# Tee boxes are single tiles and only one may wait on the course at a time.
	if current_tool == TerrainTypes.Type.TEE_BOX:
		var blocker := HoleLayout.tee_placement_blocker(terrain_grid, GameManager.current_course)
		if not blocker.is_empty():
			if not _tee_block_notified:
				_tee_block_notified = true
				EventBus.notify(blocker, "error")
			return

	# A green painted while no cup is waiting becomes a "Green With Hole" — one tile
	# with a cup in it. Later greens are ordinary green and use the normal brush.
	var places_cup := current_tool == TerrainTypes.Type.GREEN \
			and HoleLayout.green_places_cup(terrain_grid, GameManager.current_course)
	var max_brush: int = HoleLayout.max_brush_size(current_tool, terrain_grid, GameManager.current_course)
	var effective_brush: int = brush_size if max_brush == HoleLayout.UNLIMITED_BRUSH \
			else mini(brush_size, max_brush)

	var tiles_to_paint: Array
	if effective_brush <= 1:
		tiles_to_paint = [grid_pos]
	else:
		tiles_to_paint = terrain_grid.get_brush_tiles(grid_pos, effective_brush, round_brush)
	var total_cost = 0
	var blocked_by_land = false
	var blocked_by_money = false
	# Every Course Terrain paint replaces the tile it lands on — woodland
	# included, since a tree is a tile and not a thing standing on one.
	# Buildings and decorations are improvements — the Bulldozer removes those.
	_suppress_tile_undo = true
	# Batch tile changes to avoid per-tile overlay redraw cascade
	if tiles_to_paint.size() > 1:
		terrain_grid.begin_batch()
	for tile_pos in tiles_to_paint:
		# Check land ownership first
		if GameManager.land_manager and not GameManager.land_manager.is_tile_owned(tile_pos):
			blocked_by_land = true
			continue
		# Improvements are not Course Terrain tiles.
		if entity_layer and (entity_layer.is_tile_occupied_by_building(tile_pos) or entity_layer.is_tile_occupied_by_decoration(tile_pos)):
			continue
		var terrain_changes := terrain_grid.get_tile(tile_pos) != current_tool
		if not terrain_changes:
			continue
		if cost > 0 and not GameManager.can_afford(total_cost + cost):
			blocked_by_money = true
			continue
		var original_type: int = terrain_grid.get_tile(tile_pos)
		var metadata := {"old_player_placed":terrain_grid._player_placed_tiles.has(tile_pos), "old_cup":terrain_grid.has_cup_tile(tile_pos)}
		if terrain_changes:
			# A green painted while no cup is waiting becomes a Green With Hole.
			var will_place_cup := places_cup and current_tool == TerrainTypes.Type.GREEN
			metadata["new_cup"] = will_place_cup
			undo_manager.record_tile_change(tile_pos, original_type, current_tool, metadata)
			terrain_grid.set_tile(tile_pos, current_tool)
			if will_place_cup and terrain_grid.add_cup_tile(tile_pos):
				places_cup = false  # One cup per course, so this stroke is done.
			total_cost += cost

	if tiles_to_paint.size() > 1:
		terrain_grid.end_batch()

	_suppress_tile_undo = false
	undo_manager.record_stroke_cost(total_cost)
	if blocked_by_land and total_cost == 0:
		EventBus.notify("You don't own this land! Press L to buy parcels.", "error")
	elif blocked_by_money and total_cost == 0:
		_notify_cant_afford()

	if total_cost > 0:
		GameManager.modify_money(-total_cost)
		EventBus.log_transaction("Terrain: " + stamp_tool_name, -total_cost)

	# Painting a tee box or a green changes what may be placed next, and whether a
	# hole is ready to open.
	_refresh_hole_layout_ui()

## The Path improvement: lay a thin walking path ON TOP of the tile instead of
## repainting its terrain. Hostable ground is TerrainTypes.WALKING_PATH_TERRAINS
## (rough, deep rough, waste bunker, brush, rocks/boulders, stream, wild flowers,
## trees). One tile per stamp; the brush is capped at 1x1 by HoleLayout.
func _paint_walking_path_stamp(grid_pos: Vector2i) -> void:
	if not terrain_grid.is_valid_position(grid_pos):
		return
	# Land must be owned before anything is laid on it.
	if GameManager.land_manager and not GameManager.land_manager.is_tile_owned(grid_pos):
		if not _path_block_notified:
			_path_block_notified = true
			EventBus.notify("You don't own this land! Press L to buy parcels.", "error")
		return
	# Buildings and decorations occupy their tiles; a trail cannot run under them.
	if entity_layer and (entity_layer.is_tile_occupied_by_building(grid_pos) \
			or entity_layer.is_tile_occupied_by_decoration(grid_pos)):
		return
	if not terrain_grid.can_place_walking_path(grid_pos):
		if not _path_block_notified:
			_path_block_notified = true
			EventBus.notify(terrain_grid.walking_path_placement_error(grid_pos), "error")
		return
	if terrain_grid.has_walking_path(grid_pos):
		return  # Already has a trail — no double charge.
	var cost := TerrainTypes.WALKING_PATH_COST
	if cost > 0 and not GameManager.can_afford(cost):
		if GameManager.is_bankrupt():
			EventBus.notify(GameManager.spending_blocked_message(), "error")
		else:
			EventBus.notify("Not enough money!", "error")
		return
	if not terrain_grid.set_walking_path(grid_pos, true):
		return
	undo_manager.record_walking_path(grid_pos, true)
	undo_manager.record_stroke_cost(cost)
	GameManager.modify_money(-cost)
	EventBus.log_transaction("Walking path", -cost)

func _update_measure_overlay() -> void:
	if _measure_overlay:
		_measure_overlay.update_measurement(_measure_start, _measure_end, _measuring)

## Ask main to reposition a staff member's designated area (index >= 0) or to
## leave that mode (index < 0).
func _on_staff_area_move_requested(index: int) -> void:
	_cancel_inspect_mode()
	if index < 0:
		_cancel_staff_area_mode()
		return
	var sm = GameManager.staff_manager
	if sm == null or index >= sm.hired_staff.size():
		_cancel_staff_area_mode()
		return
	# Any other tool would fight the click, so clear it first.
	_cancel_hole_move_mode()
	_cancel_building_move()
	_close_hole_context_menu()
	placement_manager.cancel_placement()
	_cancel_elevation_mode()
	_cancel_bulldozer_mode()
	is_painting = false
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	if placement_preview:
		placement_preview.set_terrain_painting_enabled(false)

	_staff_area_mode_index = index
	var record: Dictionary = sm.hired_staff[index]
	if staff_area_overlay:
		staff_area_overlay.highlight_index = index
		staff_area_overlay.refresh()
	if terrain_toolbar:
		terrain_toolbar.set_staff_area_mode_index(index)
	EventBus.notify("Click a tile to set %s's designated area." % record.get("name", "staff"), "info")

func _cancel_staff_area_mode() -> void:
	if _staff_area_mode_index < 0 and (staff_area_overlay == null or staff_area_overlay.highlight_index < 0):
		return
	_staff_area_mode_index = -1
	if staff_area_overlay:
		staff_area_overlay.highlight_index = -1
		staff_area_overlay.refresh()
	if terrain_toolbar:
		terrain_toolbar.set_staff_area_mode_index(-1)

func _handle_staff_area_click(grid_pos: Vector2i) -> void:
	var sm = GameManager.staff_manager
	if sm == null or _staff_area_mode_index < 0 \
			or _staff_area_mode_index >= sm.hired_staff.size():
		_cancel_staff_area_mode()
		return
	if not terrain_grid.is_valid_position(grid_pos):
		EventBus.notify("That tile is off the course.", "error")
		return
	var record: Dictionary = sm.hired_staff[_staff_area_mode_index]
	var staff_name: String = record.get("name", "staff")
	if sm.move_staff_area(_staff_area_mode_index, grid_pos):
		EventBus.notify("%s's area moved." % staff_name, "success")
	else:
		EventBus.notify("Could not move that area.", "error")
	_cancel_staff_area_mode()

## Ask main to choose the ground the owner's own golfer works. The next
## click on the course moves their area there.
func _on_owner_area_move_requested() -> void:
	_cancel_inspect_mode()
	_cancel_staff_area_mode()
	# Any other tool would fight the click, so clear it first.
	_cancel_hole_move_mode()
	_cancel_building_move()
	_close_hole_context_menu()
	placement_manager.cancel_placement()
	_cancel_elevation_mode()
	_cancel_bulldozer_mode()
	is_painting = false
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	if placement_preview:
		placement_preview.set_terrain_painting_enabled(false)

	_owner_area_mode = true
	if player_round:
		player_round.set_owner_area_mode(true)
	EventBus.notify("Click a tile to set your golfer's work area.", "info")

func _cancel_owner_area_mode() -> void:
	if not _owner_area_mode:
		return
	_owner_area_mode = false
	if player_round:
		player_round.set_owner_area_mode(false)

## The click that puts the owner's own golfer to work somewhere new.
func _handle_owner_area_click(grid_pos: Vector2i) -> void:
	var manager := GameManager.player_golfer_manager
	if manager == null:
		_cancel_owner_area_mode()
		return
	if not terrain_grid.is_valid_position(grid_pos):
		EventBus.notify("That tile is off the course.", "error")
		return
	if manager.set_area_center(grid_pos):
		EventBus.notify("Your golfer's work area moved.", "success")
	else:
		EventBus.notify("Could not move that area.", "error")
	_cancel_owner_area_mode()

func _cancel_action() -> void:
	if is_painting:
		_stop_painting()
	is_painting = false
	last_paint_pos = Vector2i(-1, -1)
	_measuring = false
	_update_measure_overlay()

	# Two-tier cancel: first ESC cancels the active operation, second deselects tool
	var had_active_operation = false

	if inspect_mode:
		_cancel_inspect_mode()
		had_active_operation = true

	if _staff_area_mode_index >= 0:
		_cancel_staff_area_mode()
		had_active_operation = true
	if _owner_area_mode:
		_cancel_owner_area_mode()
		had_active_operation = true
	if _hole_context_menu:
		_close_hole_context_menu()
		had_active_operation = true
	if _hole_move_mode != HoleMoveMode.NONE:
		_cancel_hole_move_mode()
		had_active_operation = true
	if _moving_building != null:
		_cancel_building_move()
		had_active_operation = true
	if bulldozer_mode:
		_cancel_bulldozer_mode()
		had_active_operation = true
	if elevation_tool.is_active():
		_cancel_elevation_mode()
		had_active_operation = true
	if placement_manager.placement_mode != PlacementManager.PlacementMode.NONE:
		placement_manager.cancel_placement()
		had_active_operation = true

	if had_active_operation:
		# First ESC: cancelled the active operation, keep terrain tool selected
		return

	# Second ESC (or no active operation): deselect terrain tool entirely
	if terrain_toolbar and terrain_toolbar.has_selection():
		terrain_toolbar.clear_selection()
		_disable_terrain_painting_preview()
		return

func _has_active_tool() -> bool:
	"""Check if any tool is currently active (not in null selector state)"""
	if inspect_mode:
		return true
	if _staff_area_mode_index >= 0:
		return true
	if _owner_area_mode:
		return true
	if _hole_move_mode != HoleMoveMode.NONE:
		return true
	if _moving_building != null:
		return true
	if bulldozer_mode:
		return true
	if elevation_tool.is_active():
		return true
	if placement_manager.placement_mode != PlacementManager.PlacementMode.NONE:
		return true
	if terrain_toolbar and terrain_toolbar.has_selection():
		return true
	return false

func _on_tool_selected(tool_type: int) -> void:
	_cancel_inspect_mode()
	# Tee Box is unselectable while an unused tee waits.
	if tool_type == TerrainTypes.Type.TEE_BOX:
		if not HoleLayout.can_place_tee_box(terrain_grid, GameManager.current_course):
			if terrain_toolbar:
				terrain_toolbar.clear_selection()
			current_tool = -1
			is_painting = false
			return

	# Cancel any building or decoration placement, elevation mode and bulldozer
	_cancel_staff_area_mode()
	_cancel_owner_area_mode()
	_cancel_hole_move_mode()
	_cancel_building_move()
	_close_hole_context_menu()
	placement_manager.cancel_placement()
	_cancel_elevation_mode()
	_cancel_bulldozer_mode()
	is_painting = false

	current_tool = tool_type
	# Update toolbar highlight
	if terrain_toolbar:
		terrain_toolbar.set_current_tool(tool_type)
	# Update placement preview for terrain painting
	if placement_preview:
		placement_preview.set_terrain_tool(tool_type)
		placement_preview.set_brush_size(brush_size)
		placement_preview.set_terrain_painting_enabled(true)
	# The selected tool decides whether the brush is capped at a single tile.
	_refresh_hole_layout_ui()
	print("Tool selected: " + TerrainTypes.get_type_name(tool_type))

func _on_brush_size_changed(new_size: int) -> void:
	# The terrain brush: the Elevation tab's Square Selectors keep their own
	# Elevation Brush, so their size is not part of this state.
	brush_size = new_size
	if placement_preview:
		placement_preview.set_brush_size(new_size)

func _on_view_rotate_cw() -> void:
	_change_view_projection(true)

func _on_view_rotate_ccw() -> void:
	_change_view_projection(false)

func _change_view_projection(clockwise: bool) -> void:
	var focus_grid := _begin_view_change()
	if clockwise:
		terrain_grid.rotate_view_cw()
	else:
		terrain_grid.rotate_view_ccw()
	_finish_view_change(focus_grid)

func _begin_view_change() -> Vector2:
	_pending_moving_entities = _snapshot_moving_entities()
	if camera and terrain_grid:
		return terrain_grid.screen_to_grid_precise(camera.global_position)
	return Vector2.ZERO

func _finish_view_change(focus_grid: Vector2) -> void:
	_restore_moving_entities(_pending_moving_entities)
	_pending_moving_entities = []
	if camera and terrain_grid:
		camera.focus_on(terrain_grid.grid_to_screen_precise(focus_grid), true)

func _on_terrain_view_rotated(_orientation: int, _isometric: bool) -> void:
	_after_view_change()

func _snapshot_moving_entities() -> Array:
	var snapshot: Array = []
	if not terrain_grid:
		return snapshot
	if golfer_manager:
		for golfer in golfer_manager.get_active_golfers():
			if is_instance_valid(golfer):
				snapshot.append([golfer, terrain_grid.screen_to_grid_precise(golfer.global_position)])
	if ball_manager:
		for ball in ball_manager.get_all_balls():
			if is_instance_valid(ball):
				snapshot.append([ball, terrain_grid.screen_to_grid_precise(ball.global_position)])
	# Staff and weeds are live course objects too; a view rotation must carry
	# them to their new projected positions.
	for container in [staff_container, weed_container]:
		if container == null:
			continue
		for child in container.get_children():
			if child is Node2D and is_instance_valid(child):
				snapshot.append([child, terrain_grid.screen_to_grid_precise(child.global_position)])
	return snapshot

func _restore_moving_entities(snapshot: Array) -> void:
	for entry in snapshot:
		var entity: Node2D = entry[0]
		if is_instance_valid(entity):
			entity.global_position = terrain_grid.grid_to_screen_precise(entry[1])

func _after_view_change() -> void:
	_reposition_placed_entities()
	_sync_camera_bounds_to_view()
	_sync_view_controls()
	if placement_preview:
		placement_preview.queue_redraw()
	if mini_map:
		mini_map.queue_redraw()
	if _measure_overlay:
		_measure_overlay.queue_redraw()
	if routing_overlay:
		routing_overlay.queue_redraw()
	# Designated-area rings are projected per-point, so they redraw with the view.
	if staff_area_overlay:
		staff_area_overlay.refresh()

func _reposition_placed_entities() -> void:
	if not entity_layer:
		return
	for building in entity_layer.get_all_buildings():
		if is_instance_valid(building):
			building.set_position_in_grid(building.grid_position)
	for decoration in entity_layer.get_all_decorations():
		if is_instance_valid(decoration):
			decoration.set_position_in_grid(decoration.grid_position)
	for visualizer in hole_manager.get_all_hole_visualizers():
		if is_instance_valid(visualizer) and visualizer.has_method("refresh_positions"):
			visualizer.refresh_positions()

func _center_camera_on_course() -> void:
	if not camera or not terrain_grid:
		return
	_sync_camera_bounds_to_view()
	camera.focus_on(terrain_grid.world_bounds().get_center(), true)


func _sync_camera_bounds_to_view() -> void:
	if not camera or not terrain_grid:
		return
	var bounds := terrain_grid.world_bounds().grow(512.0)
	camera.bounds_min = bounds.position
	camera.bounds_max = bounds.end

func _sync_view_controls() -> void:
	# The facing chip in the banner's details card takes the same quarter turn
	# the course just took, so the corner reads as a compass.
	if terrain_grid and course_location_banner:
		course_location_banner.set_orientation(terrain_grid.get_view_orientation())
	# Keep toolbar in sync if it still has the deprecated method
	if terrain_toolbar and terrain_grid and terrain_toolbar.has_method("set_view_state"):
		terrain_toolbar.set_view_state(terrain_grid.get_view_orientation(), terrain_grid.is_view_isometric())

## Open a hole from the tee box and green-with-hole tiles waiting on the course
## (H key or the Open Hole button). See HoleLayout for the pairing rules.
## The player's current tool stays selected: opening a hole is a single action,
## not a mode, so building continues where it left off.
func _on_open_hole_pressed() -> void:
	var request: Dictionary = hole_tool.open_hole_request()
	if not bool(request.get("ready", false)):
		EventBus.notify(str(request.get("reason", "A hole cannot be opened yet.")), "error")
		return

	var hole: GameManager.HoleData = hole_tool.open_hole(request.get("tee", Vector2i(-1, -1)),
			request.get("cup", Vector2i(-1, -1)))
	if not hole:
		EventBus.notify("That tee box and green cannot be opened as a hole.", "error")
		return
	EventBus.notify("Hole %d opened — Par %d, %d yards" % [hole.hole_number, hole.par,
			hole.distance_yards], "success")

func _on_hole_layout_hole_created(_hole_number: int, _par: int, _distance_yards: int) -> void:
	_refresh_hole_layout_ui()

func _on_hole_layout_hole_deleted(_hole_number: int) -> void:
	_refresh_hole_layout_ui()

## The Course Map moved holes or turned the round around: the hole buttons are
## read back from course data (numbers follow the new order) and the tee/cup
## states are re-checked.
func _on_holes_reordered(_order: Array) -> void:
	_rebuild_hole_list()
	_refresh_hole_layout_ui()

func _on_hole_layout_load_completed(_success: bool) -> void:
	_refresh_hole_layout_ui()

## Keep the Green flag, brush cap and Open Hole action in sync with the current
## tee/cup state.
func _refresh_hole_layout_ui() -> void:
	if not terrain_toolbar or not terrain_grid:
		return
	var course: GameManager.CourseData = GameManager.current_course
	var request: Dictionary = HoleLayout.open_hole_request(terrain_grid, course)
	terrain_toolbar.set_open_hole_state(bool(request.get("ready", false)),
			str(request.get("reason", "")))
	terrain_toolbar.set_brush_limit(HoleLayout.max_brush_size(current_tool, terrain_grid, course))
	terrain_toolbar.set_green_placement_state(HoleLayout.green_places_cup(terrain_grid, course))

	# Tee tile: unselected, unselectable and greyed out while an unused tee waits.
	var can_place_tee := HoleLayout.can_place_tee_box(terrain_grid, course)
	var tee_blocker := HoleLayout.tee_placement_blocker(terrain_grid, course)
	terrain_toolbar.set_tee_box_state(can_place_tee, tee_blocker)
	if not can_place_tee and current_tool == TerrainTypes.Type.TEE_BOX:
		current_tool = -1
		is_painting = false
		terrain_toolbar.clear_selection()

func _on_speed_selected(speed: int) -> void:
	GameManager.set_speed(speed)

## Space (or its rebinding) pauses and resumes the clock while the course is
## simulating. The key is only dispatched in SIMULATING mode (see _input), so
## this helper has one job.
func _toggle_simulation_pause() -> void:
	if GameManager.current_speed == GameManager.GameSpeed.PAUSED:
		GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	else:
		GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	_update_button_states()

func _on_speed_toggle_pressed() -> void:
	"""The single speed button cycles Normal (1x), Fast (3x) and Ultra (8x)."""
	GameManager.cycle_running_speed()

## Size `button` for the widest of `faces` and never let a face change shrink
## it. Toggling a button whose face changes with state (like the speed
## button's ">" / ">>" / ">>>" faces) then cannot resize the button or nudge
## the row holding it.
static func lock_button_width_to_faces(button: Button, faces: Array) -> void:
	var face: String = button.text
	var widest: float = button.custom_minimum_size.x
	for candidate in faces:
		button.text = str(candidate)
		widest = maxf(widest, button.get_combined_minimum_size().x)
	button.text = face
	button.custom_minimum_size.x = widest

## Face of the speed button: one chevron per tier. While paused it shows the
## single chevron of the Normal speed a press resumes at.
static func speed_toggle_label(speed: int) -> String:
	if speed == GameManager.GameSpeed.FAST:
		return ">>"
	if speed == GameManager.GameSpeed.ULTRA:
		return ">>>"
	return ">"

## Icon of the speed button (a PixelCircleButton glyph): one, two or three
## triangles for Normal, Fast and Ultra; the plain play triangle while paused.
static func speed_toggle_glyph(speed: int) -> String:
	if speed == GameManager.GameSpeed.FAST:
		return "fast"
	if speed == GameManager.GameSpeed.ULTRA:
		return "ultra"
	return "play"

## Tooltip that names the running tier and the tier the next press cycles to.
static func speed_toggle_tooltip(speed: int) -> String:
	if speed == GameManager.GameSpeed.PAUSED:
		return "Paused — click for Normal (1x), click again for Fast (3x) and Ultra (8x)"
	var next_speed: int = GameManagerScript.next_running_speed(speed)
	return "%s (%dx) — click for %s (%dx)" % [
		_speed_tier_name(speed), int(speed),
		_speed_tier_name(next_speed), int(next_speed),
	]

static func _speed_tier_name(speed: int) -> String:
	if speed == GameManager.GameSpeed.PAUSED:
		return "Paused"
	if speed == GameManager.GameSpeed.ULTRA:
		return "Ultra"
	if speed == GameManager.GameSpeed.FAST:
		return "Fast"
	return "Normal"

var _game_over_shown: bool = false

func _on_money_changed(_old: int, _new: int) -> void:
	# Check for bankruptcy game over
	if GameManager.is_bankrupt() and not _game_over_shown:
		_show_game_over()

func _on_day_changed(_new_day: int) -> void:
	# Operating costs are now calculated at end of day before summary
	pass

func _on_hole_created(hole_number: int, _par: int, _distance_yards: int) -> void:
	StrokeIndexCalculator.recalculate_for_course()
	if not hole_grid:
		return
	# Each hole joins the register as a pixel-art hole card: its number on the
	# tee-marked plate, its own little course window and its par and yardage.
	# The card fills in its map from the course data in _refresh_hole_button.
	var hole_btn := HoleCardButton.new()
	hole_btn.name = "HoleBtn%d" % hole_number
	hole_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hole_btn.set_meta("hole_number", hole_number)
	# The hole button opens details; Locate keeps the register visible.
	# Everything else about that hole — its pin, tees and
	# green, its par, whether it is open, its statistics — opens on the Holes
	# tab in place of the hole grid, the way a visitor card opens on Visiting
	# Golfers.
	hole_btn.pressed.connect(_on_hole_button_pressed.bind(hole_number))
	var row := HBoxContainer.new()
	row.name = "HoleRow%d" % hole_number
	row.set_meta("hole_number", hole_number)
	row.add_theme_constant_override("separation", 4)
	row.add_child(hole_btn)
	var locate := terrain_toolbar._visitor_button("Locate", Color("87b9cf"))
	locate.name = "LocateHoleButton%d" % hole_number
	locate.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	locate.tooltip_text = "Center the camera on hole %d" % hole_number
	# The card is taller than the old text row, so the Locate chip rides at the
	# card's middle rather than hanging off its top corner.
	locate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	locate.pressed.connect(func(): terrain_toolbar.hole_locate_requested.emit(hole_number))
	row.add_child(locate)
	hole_grid.add_child(row)
	# Three holes to a column, so the buttons are re-seated after every change.
	terrain_toolbar.layout_hole_buttons()
	# The signal payload seeds the label; the course data owns the open state.
	_refresh_hole_button(hole_number)
	_update_status_rating()

## A hole button opens that hole's detail view on the Holes tab — its tee and
## green actions, par, open/closed toggle, delete action and statistics —
## in place of the hole grid, the way a visitor card opens on Visiting Golfers.
func _on_hole_button_pressed(hole_number: int) -> void:
	var hole = _find_hole_data(hole_number)
	if not hole:
		return
	_close_hole_context_menu()
	if hole_stats_panel and hole_stats_panel.visible:
		_on_hole_stats_panel_closed()
	if terrain_toolbar:
		terrain_toolbar.show_hole_detail(hole_number)

func _on_hole_detail_changed(hole_number: int) -> void:
	if _highlighted_hole_number > 0 and _highlighted_hole_number != hole_number:
		hole_manager.highlight_hole(_highlighted_hole_number, false)
	_highlighted_hole_number = hole_number
	if _highlighted_hole_number > 0:
		hole_manager.highlight_hole(_highlighted_hole_number, true)

## Re-read one hole button from the course data: its par, its yardage, its
## real tee and cup cells (which the card's course window faces along) and
## whether it is open. A closed hole plays nowhere, so its card dims the way
## the row's Open/Closed toggle used to, and the window's own map fades grey.
func _refresh_hole_button(hole_number: int) -> void:
	var hole_btn := _find_hole_button(hole_number)
	if not hole_btn:
		return
	var hole := _find_hole_data(hole_number)
	if not hole:
		return
	if hole_btn is HoleCardButton:
		(hole_btn as HoleCardButton).set_hole(hole_number, hole.par, hole.distance_yards,
			hole.is_open, hole.tee_position, hole.hole_position)
	hole_btn.tooltip_text = "Hole %d (Par %d, %d yds)%s - Click for hole details" % [
			hole_number, hole.par, hole.distance_yards, "" if hole.is_open else " - Closed"]
	hole_btn.modulate = Color(1, 1, 1) if hole.is_open else Color(0.5, 0.5, 0.5)

func _find_hole_button(hole_number: int) -> Button:
	if not hole_grid:
		return null
	return hole_grid.find_child("HoleBtn%d" % hole_number, true, false) as Button

func _on_hole_deleted(_hole_number: int) -> void:
	# Rebuild the buttons so they follow the renumbered holes
	_rebuild_hole_list()
	_update_status_rating()
	StrokeIndexCalculator.recalculate_for_course()

func _on_hole_toggled(hole_number: int, _is_open: bool) -> void:
	StrokeIndexCalculator.recalculate_for_course()
	_refresh_hole_button(hole_number)

func _rebuild_hole_list() -> void:
	if not hole_grid:
		return
	# Drop the old buttons outright: leaving them queued for deletion would keep
	# them counted in the column layout for the rest of this frame.
	for child in hole_grid.get_children():
		hole_grid.remove_child(child)
		child.queue_free()
	# Re-add from course data, which also restores each hole's open state
	if GameManager.current_course:
		for hole in GameManager.current_course.holes:
			_on_hole_created(hole.hole_number, hole.par, hole.distance_yards)

func _on_building_type_selected_from_toolbar(building_type: String) -> void:
	"""Start placement immediately for a building card in the Buildings tab."""
	_cancel_inspect_mode()
	_cancel_hole_move_mode()
	_cancel_building_move()
	_close_hole_context_menu()
	_cancel_elevation_mode()
	_cancel_bulldozer_mode()
	_disable_terrain_painting_preview()
	is_painting = false
	if building_type not in building_registry:
		EventBus.notify("Building type not found: %s" % building_type, "error")
		return
	if building_registry[building_type].get("required", false) and entity_layer.has_building_of_type(building_type):
		EventBus.notify("That required facility is already placed.", "info")
		return
	if not BuildingAvailability.is_available(building_registry[building_type], GameManager.current_theme):
		var facility_name = building_registry[building_type].get("name", building_type)
		EventBus.notify("%s can't be built on a %s course." % [
			facility_name, CourseTheme.get_theme_name(GameManager.current_theme)], "error")
		return
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	placement_manager.start_building_placement(building_type, building_registry[building_type])

func _on_building_placement_pressed() -> void:
	"""Open the Buildings tab; facility cards there start placement directly."""
	if terrain_toolbar:
		terrain_toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)

func _on_decoration_placement_pressed() -> void:
	"""Open the Improvements tab; decoration tiles there start placement directly."""
	if terrain_toolbar:
		terrain_toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)

func _on_decoration_type_selected_from_toolbar(decoration_type: String) -> void:
	"""Start placement immediately for a decoration tile in the Improvements tab."""
	_cancel_inspect_mode()
	_cancel_hole_move_mode()
	_cancel_building_move()
	_close_hole_context_menu()
	_cancel_elevation_mode()
	_cancel_bulldozer_mode()
	_disable_terrain_painting_preview()
	is_painting = false
	if decoration_type not in decoration_registry:
		EventBus.notify("Decoration type not found: %s" % decoration_type, "error")
		return
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	placement_manager.start_decoration_placement(decoration_type, decoration_registry[decoration_type])
	print("Decoration placement mode from toolbar: %s" % decoration_type)

## Select one of the three elevation selector tools. While it is active,
## right clicking raises the selected terrain and left clicking lowers it.
func _on_elevation_tool_pressed(tool_name: String) -> void:
	_cancel_inspect_mode()
	var new_tool: ElevationTool.Tool
	match tool_name:
		ElevationTool.TOOL_VERTEX:
			new_tool = ElevationTool.Tool.VERTEX
		ElevationTool.TOOL_FLAT:
			new_tool = ElevationTool.Tool.FLAT
		ElevationTool.TOOL_GRADUAL:
			new_tool = ElevationTool.Tool.GRADUAL
		_:
			return
	_cancel_hole_move_mode()
	_cancel_building_move()
	_close_hole_context_menu()
	placement_manager.cancel_placement()
	_cancel_bulldozer_mode()
	_disable_terrain_painting_preview()
	is_painting = false
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	# The Square Selectors share one Elevation Brush, separate from the
	# terrain brush: hand the tool the size and shape the controls are showing.
	terrain_toolbar.set_elevation_tool(tool_name)
	elevation_tool.select_tool(new_tool)
	elevation_tool.set_brush(terrain_toolbar.get_elevation_brush_size(),
			terrain_toolbar.get_elevation_brush_square())
	terrain_grid.set_elevation_overlay_active(true)
	_sync_elevation_preview()
	var display_names := {
		ElevationTool.TOOL_VERTEX: "Vertex",
		ElevationTool.TOOL_FLAT: "Flat Square",
		ElevationTool.TOOL_GRADUAL: "Gradual Square",
	}
	EventBus.notify("%s selector - right click raises, left click lowers" % display_names[tool_name], "info")
	print("Elevation tool selected: %s" % tool_name)

func _on_elevation_brush_size_changed(new_size: int) -> void:
	elevation_tool.set_brush_size(new_size)
	_sync_elevation_preview()

func _on_elevation_brush_shape_changed(square_shape: bool) -> void:
	elevation_tool.set_brush_square(square_shape)
	_sync_elevation_preview()

## Point the placement preview at the selected elevation tool and its brush.
func _sync_elevation_preview() -> void:
	if placement_preview:
		placement_preview.set_elevation_mode(true)
		placement_preview.set_elevation_tool(elevation_tool.tool)
		placement_preview.set_elevation_brush(elevation_tool.brush_size,
				elevation_tool.brush_square)

func _on_bulldozer_pressed() -> void:
	"""Activate bulldozer mode to demolish improvements and buildings"""
	_cancel_inspect_mode()
	_cancel_hole_move_mode()
	_cancel_building_move()
	_close_hole_context_menu()
	placement_manager.cancel_placement()
	_cancel_elevation_mode()
	_disable_terrain_painting_preview()
	is_painting = false
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	bulldozer_mode = true
	if placement_preview:
		placement_preview.set_bulldozer_mode(true)
		placement_preview.set_brush_size(brush_size)
	if terrain_toolbar:
		terrain_toolbar.set_bulldozer_active(true)
	EventBus.notify("Bulldozer mode - click decorations, paths or buildings to remove them", "info")
	print("Bulldozer mode: ACTIVE")

func _cancel_bulldozer_mode() -> void:
	bulldozer_mode = false
	if placement_preview:
		placement_preview.set_bulldozer_mode(false)
	if terrain_toolbar:
		terrain_toolbar.set_bulldozer_active(false)

func _disable_terrain_painting_preview() -> void:
	"""Disable terrain painting preview when switching to other modes"""
	if placement_preview:
		placement_preview.set_terrain_painting_enabled(false)

func _on_new_game_started() -> void:
	"""Generate natural terrain when a new game starts"""
	_cancel_inspect_mode()
	_game_over_shown = false
	_close_hole_context_menu()
	_cancel_hole_move_mode()
	_cancel_building_move()

	# What this course is being built from, captured before the pending flags
	# are spent below. The loading screen's checklist is worded from them.
	var is_quick_start := _quick_start_pending
	var is_prebuilt := not _prebuilt_pending.is_empty()
	var holes_requested := _generated_holes_pending
	var holes_stage := GeneratingCourseScreen.holes_stage_text(
		is_quick_start, holes_requested, is_prebuilt)
	var with_paths := is_quick_start or is_prebuilt or holes_requested > 0
	var theme_name := CourseTheme.get_theme_name(GameManager.current_theme)

	# Quick Start already showed this screen before the world roll. Reuse it and
	# replace the placeholder with the chosen course and theme; other entry
	# points create their screen here as before.
	var with_location := is_instance_valid(_generating_course_screen)
	var loading_overlay := _generating_course_screen
	if not with_location:
		loading_overlay = GeneratingCourseScreen.new()
		loading_overlay.name = "GeneratingCourseScreen"
	loading_overlay.setup(GameManager.course_name,
		GeneratingCourseScreen.subtitle_for_job(
			theme_name, is_quick_start, holes_requested, is_prebuilt),
		GeneratingCourseScreen.stages_for_job(holes_stage, with_paths, with_location),
		CourseTheme.get_description(GameManager.current_theme))
	if not with_location:
		_generating_course_screen = loading_overlay
		add_child(loading_overlay)
	loading_overlay.set_stage_by_title(GeneratingCourseScreen.STAGE_TERRAIN)
	await get_tree().process_frame
	await get_tree().process_frame  # Two frames to ensure the overlay paints

	# Wipe the previous course before building the new one: golfers, entities, hole
	# flags, tiles, cups, elevation and undo history. Removing an entity restores the
	# terrain underneath it, so entities go first and the grid reset goes last —
	# otherwise whatever they restore would survive into the new course. Natural
	# terrain generation paints over whatever is on the grid without clearing it,
	# so without this a stale tee box would even block the player's first tee.
	if golfer_manager:
		golfer_manager.clear_all_golfers()
	if weed_manager:
		weed_manager.clear_all()
	if GameManager.staff_manager:
		GameManager.staff_manager.clear_all_staff()
	if player_golfer_manager:
		# A new course starts with the ground unchosen: the owner works the
		# middle of it until the player moves their area somewhere else.
		player_golfer_manager.reset_area()
	if entity_layer:
		entity_layer.clear_all()
	if hole_manager:
		hole_manager.clear_visualizations()
	if terrain_grid:
		terrain_grid.reset_for_new_course()
	undo_manager.clear()

	# Clear shot heatmap data for new game
	if shot_heatmap_tracker:
		shot_heatmap_tracker.clear()

	# Generate natural terrain features using batch mode to avoid per-tile signal spam.
	# Without batch mode, each set_tile() triggers 12+ signal handlers (overlays, undo,
	# minimap, etc.) — with thousands of tiles this blocks the main thread for too long.
	_suppress_tile_undo = true
	terrain_grid.begin_batch()
	NaturalTerrainGenerator.generate(terrain_grid, entity_layer, _pending_terrain_seed)
	_pending_terrain_seed = 0
	terrain_grid.end_batch_quiet()
	terrain_grid.refresh_all_overlays()
	_suppress_tile_undo = false

	# Build pre-made course if Quick Start was selected
	if _quick_start_pending:
		_quick_start_pending = false
		loading_overlay.set_stage_by_title(holes_stage)
		await get_tree().process_frame
		_suppress_tile_undo = true
		terrain_grid.begin_batch()
		QuickStartCourse.build(terrain_grid, entity_layer, hole_tool)
		terrain_grid.end_batch_quiet()
		terrain_grid.refresh_all_overlays()
		_suppress_tile_undo = false

	# Lay out the holes the world map asked this course to start with. Only the
	# first location the player bought gets pre-generated holes (Start New Game:
	# 0, 3, 6, 9 or 18); subsequent locations are built by the player.
	var generated_holes := 0
	_generated_holes_pending = 0
	if holes_requested > 0 and not is_quick_start and not is_prebuilt:
		loading_overlay.set_stage_by_title(holes_stage)
		await get_tree().process_frame
		_suppress_tile_undo = true
		terrain_grid.begin_batch()
		generated_holes = GeneratedCourse.generate(holes_requested, terrain_grid, entity_layer, hole_tool)
		terrain_grid.end_batch_quiet()
		terrain_grid.refresh_all_overlays()
		_suppress_tile_undo = false
		# The generated-hole option only applies to the first course. From here
		# on every new location starts empty, and Reset World no longer
		# reserves extra parcels for a layout that has already been used.
		WorldMap.mark_generated_holes_used()

	# Build prebuilt course package if selected from main menu
	if is_prebuilt:
		var pkg_id := _prebuilt_pending
		_prebuilt_pending = ""
		# Restore earned money (cost already deducted before new_game)
		GameManager.money = _prebuilt_money
		EventBus.money_changed.emit(0, _prebuilt_money)
		_prebuilt_money = 0
		loading_overlay.set_stage_by_title(holes_stage)
		await get_tree().process_frame
		_suppress_tile_undo = true
		terrain_grid.begin_batch()
		PrebuiltCourseGenerator.build(pkg_id, terrain_grid, hole_tool)
		terrain_grid.end_batch_quiet()
		terrain_grid.refresh_all_overlays()
		_suppress_tile_undo = false

	# Every course starts with a clubhouse. Quick Start and the generated
	# courses place one with their layout; if the layout could not fit it, or
	# the course was built empty or from a prebuilt package, it is placed here.
	# Golfers arrive and leave through its door either way.
	var clubhouse_preferred := Vector2i(-1, -1)
	if is_quick_start:
		clubhouse_preferred = QuickStartCourse.CLUBHOUSE_TILE
	elif generated_holes > 0:
		clubhouse_preferred = GeneratedCourse.get_anchor(holes_requested) + GeneratedCourse.CLUBHOUSE_OFFSET
	else:
		# An empty lot or a prebuilt package: the corner of the property every
		# shipped layout keeps clear (the Quick Start garden's spot).
		clubhouse_preferred = CourseClubhouse.arrival_corner()
	# Laying the grounds is the course's landscaping, not a player edit: keep
	# it out of the undo history (and off the maintenance books).
	loading_overlay.set_stage_by_title(GeneratingCourseScreen.STAGE_CLUBHOUSE)
	await get_tree().process_frame
	_suppress_tile_undo = true
	var clubhouse := _ensure_course_clubhouse(clubhouse_preferred)
	_suppress_tile_undo = false

	# A course that arrives with its holes arrives with its paths: the walk out of
	# the clubhouse door to the first tee, a path beside every fairway, the link
	# from each green to the next tee, and the walk home from the last green. What
	# is laid is the Improvements tab's Path, so golfers walk it at 1.25x, and at
	# 1.5x where the network reaches the clubhouse and the trail is paved (see
	# WalkingPathOverlay). Laid here rather than inside each generator so every
	# layout — Quick Start, a Start New Game course and the prebuilt packages
	# alike — gets the paths that belong to the clubhouse it was actually given.
	if clubhouse != null and GameManager.get_open_hole_count() > 0:
		loading_overlay.set_stage_by_title(GeneratingCourseScreen.STAGE_PATHS)
		await get_tree().process_frame
		_suppress_tile_undo = true
		terrain_grid.begin_batch()
		CoursePathGenerator.generate(terrain_grid, GameManager.current_course.holes,
				entity_layer, clubhouse.grid_position)
		terrain_grid.end_batch_quiet()
		terrain_grid.refresh_all_overlays()
		_suppress_tile_undo = false

	loading_overlay.set_stage_by_title(GeneratingCourseScreen.STAGE_OPENING)
	await get_tree().process_frame
	if is_quick_start:
		camera.focus_on(terrain_grid.grid_to_screen_center(Vector2i(57,64)), true)
		camera.set_zoom_level(1.0, true)
		GameManager.update_course_rating()
	elif generated_holes > 0:
		var anchor := GeneratedCourse.get_anchor(holes_requested)
		camera.focus_on(terrain_grid.grid_to_screen_center(anchor), true)
		camera.set_zoom_level(1.0, true)
		GameManager.update_course_rating()
	elif is_instance_valid(clubhouse):
		# An empty course opens on its new clubhouse: that is the whole start.
		camera.focus_on(terrain_grid.grid_to_screen_center(clubhouse.grid_position), true)
		camera.set_zoom_level(1.0, true)

	# The course is ready: complete the checklist, let the full bar paint for
	# a beat, then remove the loading screen.
	loading_overlay.finish()
	await get_tree().process_frame
	_dismiss_generating_course_screen()

	# The owner's own golfer is on the course from the start, working the
	# ground the player gave them.
	if player_golfer_manager:
		player_golfer_manager.on_course_ready()

	# Day always starts automatically — ensure simulation is active even if a
	# subclass previously cleared mode during generation.
	if GameManager.current_mode != GameManager.GameMode.SIMULATING:
		GameManager.set_mode(GameManager.GameMode.SIMULATING)
		GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	# Spawn initial golfers if the course already has playable holes (e.g. Quick
	# Start / Prebuilt). Empty courses spawn naturally once the player builds.
	if GameManager.get_open_hole_count() > 0 and not tournament_manager.is_tournament_in_progress():
		# One frame so hole visualizations finish spawning before golfers query them.
		await get_tree().process_frame
		if is_inside_tree() and GameManager.current_mode == GameManager.GameMode.SIMULATING:
			golfer_manager.spawn_initial_group()

	# The tutorial runs when the company chose it on Start New Game. It skips
	# courses that already have holes (Quick Start, Prebuilt, or a generated
	# first course). The choice is spent here, so later empty sites of the same
	# company do not repeat it.
	var tutorial_due := not is_quick_start and not is_prebuilt and generated_holes == 0 and WorldMap.tutorial_enabled
	if tutorial_due:
		WorldMap.tutorial_enabled = false
		_start_tutorial()

func _cancel_elevation_mode() -> void:
	if elevation_tool.is_active():
		elevation_tool.cancel()
		terrain_grid.set_elevation_overlay_active(false)
	if terrain_toolbar:
		terrain_toolbar.set_elevation_tool("")
	if placement_preview:
		placement_preview.set_elevation_mode(false)

## Begin an elevation stroke. While a selector tool is active the two mouse
## buttons paint in opposite directions: right click raises, left click lowers.
func _start_elevation_painting(raising: bool) -> void:
	if is_painting or GameManager.is_paused:
		return
	elevation_tool.set_mode(raising)
	is_painting = true
	_paint_elevation_at_mouse()

## End the current elevation stroke; the selector tool stays selected.
func _stop_elevation_painting() -> void:
	if not is_painting:
		return
	is_painting = false
	last_paint_anchor = Vector2i(-1, -1)
	if elevation_tool.is_active():
		elevation_tool.stop_stroke()

func _paint_elevation_at_mouse() -> void:
	if not elevation_tool.is_raising() and not elevation_tool.is_lowering():
		return
	var mouse_world = camera.get_mouse_world_position()
	# Tile-space point: integers are grid vertices, `+0.5` are tile centres.
	var grid_point = terrain_grid.screen_to_grid_point(mouse_world)
	# The Square Selectors anchor their tile block on the tile under the
	# cursor; the Vertex Selector snaps to the nearest vertex.
	var anchor = ElevationTool.anchor_for_tool(grid_point, terrain_grid, elevation_tool.tool)
	if anchor == last_paint_anchor:
		return
	last_paint_anchor = anchor

	var changes = elevation_tool.paint_at_point(grid_point, terrain_grid, entity_layer)
	if not changes.is_empty():
		undo_manager.record_elevation_stroke(changes)

func _handle_placement_click(grid_pos: Vector2i) -> void:
	"""Handle clicking during building or decoration placement"""
	# Check land ownership first
	if GameManager.land_manager and not GameManager.land_manager.is_tile_owned(grid_pos):
		EventBus.notify("You don't own this land! Press L to buy parcels.", "error")
		return

	if not placement_manager.can_place_at(grid_pos, terrain_grid):
		EventBus.notify(placement_manager.get_placement_error(grid_pos, terrain_grid), "error")
		return

	var cost = placement_manager.get_placement_cost()
	if cost > 0 and not GameManager.can_afford(cost):
		if GameManager.is_bankrupt():
			EventBus.notify(GameManager.spending_blocked_message(), "error")
		else:
			EventBus.notify("Not enough money!", "error")
		return

	if placement_manager.placement_mode == PlacementManager.PlacementMode.BUILDING:
		_place_building(grid_pos, cost)
	elif placement_manager.placement_mode == PlacementManager.PlacementMode.DECORATION:
		_place_decoration(grid_pos, cost)

func _place_building(grid_pos: Vector2i, cost: int) -> void:
	"""Place a building at the grid position"""
	var building_type = placement_manager.selected_building_type
	var building_data = building_registry.get(building_type, {})
	var building_name = building_data.get("name", building_type)

	# Check if this is a unique building that already exists
	if building_data.get("required", false) and entity_layer.has_building_of_type(building_type):
		EventBus.notify("Only one %s allowed!" % building_name, "error")
		placement_manager.cancel_placement()
		return

	# The Buildings tab only offers facilities this location allows, but keep
	# the check here too so scripted flows can't bypass the location rules.
	if not BuildingAvailability.is_available(building_data, GameManager.current_theme):
		EventBus.notify("%s can't be built on a %s course." % [
			building_name, CourseTheme.get_theme_name(GameManager.current_theme)], "error")
		placement_manager.cancel_placement()
		return

	var building = entity_layer.place_building(building_type, grid_pos, building_registry)

	if building:
		GameManager.modify_money(-cost)
		EventBus.log_transaction("Building: %s" % building_name, -cost)
		EventBus.building_placed.emit(building_type, grid_pos)
		undo_manager.record_entity_placement("building", grid_pos, building_type, cost)
		print("Placed %s at %s" % [building_type, grid_pos])
		# Placement feedback
		_play_placement_feedback(grid_pos, "building")
	else:
		EventBus.notify("Cannot place here - overlaps with existing building!", "error")
	# Always clear the building selector after placement attempt
	placement_manager.cancel_placement()

func _notify_cant_afford() -> void:
	if GameManager.is_bankrupt():
		EventBus.notify(GameManager.spending_blocked_message(), "error")
	else:
		EventBus.notify("Not enough money!", "error")

func _place_decoration(grid_pos: Vector2i, cost: int) -> void:
	"""Place a decoration at the grid position"""
	var dec_type = placement_manager.selected_decoration_type
	var dec_data = placement_manager.selected_decoration_data
	var dec_name = dec_data.get("name", dec_type.capitalize())

	var decoration = entity_layer.place_decoration(dec_type, grid_pos, decoration_registry)

	if decoration:
		GameManager.modify_money(-cost)
		EventBus.log_transaction("Decoration: %s" % dec_name, -cost)
		undo_manager.record_entity_placement("decoration", grid_pos, dec_type, cost)
		print("Placed %s at %s" % [dec_type, grid_pos])
		_play_placement_feedback(grid_pos, "decoration")
	else:
		EventBus.notify("Cannot place here!", "error")
	# Multi-tile decorations clear placement after placing (like buildings)
	var sz = dec_data.get("size", [1, 1])
	if int(sz[0]) > 1 or int(sz[1]) > 1:
		placement_manager.cancel_placement()

func _play_placement_feedback(grid_pos: Vector2i, placement_type: String) -> void:
	"""Play visual feedback effects when placing an entity"""
	var world_pos = terrain_grid.grid_to_screen_center(grid_pos)

	# Spawn particle burst
	PlacementFeedback.create_at(self, world_pos, placement_type)

	# Ring burst effect with success color
	PlacementFeedback.create_ring_burst(self, world_pos, UIConstants.COLOR_SUCCESS)

	# Micro camera shake for satisfying feedback
	if camera:
		camera.micro_shake()

	# Sound hook (placeholder for future audio)
	PlacementFeedback.play_placement_sound(placement_type)

func _bulldoze_at_mouse() -> void:
	var mouse_world = camera.get_mouse_world_position()
	var grid_pos = terrain_grid.screen_to_grid(mouse_world)
	if grid_pos == last_paint_pos: return
	last_paint_pos = grid_pos
	if not terrain_grid.is_valid_position(grid_pos): return
	_handle_bulldozer_click(grid_pos, mouse_world)

# Bulldozer removal fees (Improvements & Buildings only: decorations, walking
# paths, buildings). Course Terrain tiles replace each other — the bulldozer
# never touches them, and neither does a clearing fee: a tree is a tile, not a
# thing standing on one.
const BULLDOZER_COSTS = {
	"decoration": 20,
	"building": 20,  # Flat demolition fee, whatever the facility cost
	"walking_path": 5,  # The Path improvement (thin walking trail)
}

func _handle_bulldozer_click(grid_pos: Vector2i, _mouse_world: Vector2 = Vector2.ZERO) -> void:
	"""Handle bulldozer removal at a single tile. Supports both single-click and drag.

	The Bulldozer only demolishes Improvements and Buildings — decorations,
	walking paths and facility buildings. Course Terrain tiles (every ground
	paint, woodland included) are untouched: replace one by painting any other
	Course Terrain tile over it.
	"""
	var dragging = is_painting
	# Check land ownership
	if GameManager.land_manager and not GameManager.land_manager.is_tile_owned(grid_pos):
		if not dragging:
			EventBus.notify("You don't own this land! Press L to buy parcels.", "error")
		return

	# Remove decoration at this tile (Improvements tab)
	var hit_decoration = entity_layer.get_decoration_at(grid_pos)
	if hit_decoration:
		var cost = BULLDOZER_COSTS.get("decoration", 20)
		if not GameManager.can_afford(cost):
			if not dragging:
				if GameManager.is_bankrupt():
					EventBus.notify(GameManager.spending_blocked_message(), "error")
				else:
					EventBus.notify("Not enough money to remove decoration ($%d)" % cost, "error")
			return
		GameManager.modify_money(-cost)
		EventBus.log_transaction("Remove decoration", -cost)
		entity_layer.remove_decoration(hit_decoration.grid_position)
		_bulldoze_drag_count += 1
		_bulldoze_drag_cost += cost
		if not dragging:
			EventBus.notify("Decoration removed (-$%d)" % cost, "info")
		return

	# Demolish the building covering this tile (Buildings tab). Buildings may
	# span several tiles — clicking any footprint tile demolishes the whole
	# facility for a flat fee.
	var hit_building = entity_layer.get_building_containing(grid_pos)
	if hit_building:
		# The required clubhouse is part of the course: it is moved, never
		# demolished (Move Clubhouse in its info panel).
		if hit_building.is_required():
			if not dragging:
				EventBus.notify("%s cannot be demolished — use Move in its panel to put it somewhere else." % _building_display_name(hit_building), "info")
			return
		var cost = BULLDOZER_COSTS["building"]
		if not GameManager.can_afford(cost):
			if not dragging:
				if GameManager.is_bankrupt():
					EventBus.notify(GameManager.spending_blocked_message(), "error")
				else:
					EventBus.notify("Not enough money to demolish the building ($%d)" % cost, "error")
			return
		var building_name := _building_display_name(hit_building)
		GameManager.modify_money(-cost)
		EventBus.log_transaction("Demolish %s" % building_name, -cost)
		entity_layer.remove_building(hit_building.grid_position)
		_bulldoze_drag_count += 1
		_bulldoze_drag_cost += cost
		if not dragging:
			EventBus.notify("%s demolished (-$%d)" % [building_name, cost], "info")
		return

	# The Path improvement: a thin walking trail laid over the ground.
	# (Course terrain paints replace the ground itself; a trail on plain
	# hostable ground needs its own pass.)
	if terrain_grid.has_walking_path(grid_pos):
		var cost = BULLDOZER_COSTS["walking_path"]
		if not GameManager.can_afford(cost):
			if not dragging:
				if GameManager.is_bankrupt():
					EventBus.notify(GameManager.spending_blocked_message(), "error")
				else:
					EventBus.notify("Not enough money to remove walking path ($%d)" % cost, "error")
			return
		GameManager.modify_money(-cost)
		EventBus.log_transaction("Remove walking path", -cost)
		terrain_grid.set_walking_path(grid_pos, false)
		undo_manager.record_walking_path(grid_pos, false)
		_bulldoze_drag_count += 1
		_bulldoze_drag_cost += cost
		if not dragging:
			EventBus.notify("Walking path removed (-$%d)" % cost, "info")
		return

	# Nothing to remove at this position — course terrain is never bulldozed.
	if not dragging:
		EventBus.notify("Nothing to bulldoze here", "info")

# --- Daily & Yearly Cycle ---

func _calculate_building_operating_costs() -> int:
	"""Sum operating costs from all placed buildings."""
	var total: int = 0
	if entity_layer:
		for building in entity_layer.get_all_buildings():
			var op_cost = building.building_data.get("operating_cost", 0)
			total += op_cost
	return total

func _calculate_decoration_operating_costs() -> int:
	"""Sum daily upkeep costs from all placed decorations."""
	var total: int = 0
	if entity_layer:
		for dec in entity_layer.get_all_decorations():
			total += dec.daily_upkeep
	return total

func _on_end_of_day(_day_number: int) -> void:
	"""Handle the bookkeeping for the day that just finished.
	The course never closes: days roll over silently and the game keeps
	running. The interruption-style summary now appears only at the end of
	the year (see _on_year_ended)."""
	# Calculate and deduct operating costs for the day that just ended
	var terrain_cost = int(terrain_grid.get_total_maintenance_cost() * GameManager.get_maintenance_multiplier())
	var hole_count = GameManager.current_course.holes.size() if GameManager.current_course else 0
	var building_costs = _calculate_building_operating_costs()
	var decoration_costs = _calculate_decoration_operating_costs()

	# Overnight weeds sprout before payroll, so condition reflects what was left
	# on the course today.
	if weed_manager:
		weed_manager.grow_daily(GameManager.get_open_hole_count())

	# Staff payroll
	var staff_payroll: int = 0
	if GameManager.staff_manager:
		staff_payroll = GameManager.apply_daily_charge("staff_payroll", GameManager.staff_manager.get_daily_payroll())
		GameManager.staff_manager.process_daily_maintenance()

	# Marketing costs
	var marketing_cost: int = 0
	if GameManager.marketing_manager:
		marketing_cost = GameManager.marketing_manager.process_daily()

	GameManager.daily_stats.calculate_operating_costs(terrain_cost, hole_count, building_costs, decoration_costs)

	GameManager.daily_stats.hired_staff_payroll = staff_payroll
	GameManager.daily_stats.marketing_cost = marketing_cost
	GameManager.daily_stats.operating_costs += staff_payroll + marketing_cost
	var total_cost = GameManager.daily_stats.operating_costs
	if total_cost > 0:
		GameManager.modify_money(-total_cost)
		EventBus.log_transaction("Daily operating costs", -total_cost)

	# Keep the course rating fresh as the day closes
	GameManager.update_course_rating()

func _on_year_ended(finished_year: int) -> void:
	"""Pause the game and present the year-in-review summary."""
	GameManager.is_paused = true

	# Prevent duplicate panels
	var hud = $UI/HUD
	var existing = hud.get_node_or_null("YearSummary")
	if existing:
		return

	var summary = YearSummaryPanel.new(finished_year)
	summary.name = "YearSummary"

	# Connect signals BEFORE add_child (ready signal fires during add_child)
	summary.continue_pressed.connect(_on_summary_continue)

	hud.add_child(summary)

	# Center the panel on screen (use custom_minimum_size since layout happens
	# next frame), clamped so it stays fully visible on small windows.
	var viewport_size = get_viewport().get_visible_rect().size
	var summary_size = summary.custom_minimum_size.min(Screen.available_panel_size()).max(Vector2(120, 120))
	summary.custom_minimum_size = summary_size
	summary.position = _center_position_clamped(viewport_size, summary_size)

## Screen center for a `panel_size`, clamped to keep the panel fully on screen.
func _center_position_clamped(viewport_size: Vector2, panel_size: Vector2) -> Vector2:
	var pos: Vector2 = (viewport_size - panel_size) / 2.0
	pos.x = clampf(pos.x, 8.0, maxf(8.0, viewport_size.x - panel_size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, viewport_size.y - panel_size.y - 8.0))
	return pos

func _on_summary_continue() -> void:
	"""Called when player clicks Continue on the year summary."""
	if tournament_leaderboard:
		tournament_leaderboard.hide()
	GameManager.is_paused = false

func _on_mode_toggle_pressed() -> void:
	"""Playtest compatibility. The day already runs, so this starts play only
	when the course is not simulating. It never force-ends the day."""
	if GameManager.current_mode == GameManager.GameMode.SIMULATING:
		return
	if GameManager.start_simulation():
		if tournament_manager and not tournament_manager.is_tournament_in_progress():
			golfer_manager.spawn_initial_group()

# --- Menu / Save/Load ---

func _create_menu_buttons() -> void:
	var menu_btn := PixelCircleButton.new()
	menu_btn.name = "MenuBtn"
	menu_btn.glyph = "menu"
	menu_btn.accessibility_name = "Menu"
	menu_btn.tooltip_text = "Game menu (Esc)"
	menu_btn.pressed.connect(_on_menu_pressed)
	left_controls.add_child(menu_btn)

	# The event Feed is not here any more: it is a card on the Club tab
	# (Manage → Club → Review → Feed), wired up in _setup_terrain_toolbar.
	# The Inspect toggle left the dock too: every Build section tab pins one to
	# its bottom-right corner, also wired up in _setup_terrain_toolbar.

	tile_inspector = TileInspector.new()
	tile_inspector.name = "TileInspector"
	$UI/HUD.add_child(tile_inspector)

func _fill_left_control_stack() -> void:
	left_controls.setup(terrain_toolbar)

func _on_inspect_toggled(enabled: bool) -> void:
	if not enabled:
		_cancel_inspect_mode()
		return
	# Finish any stroke and leave all editing operations before inspecting.
	_cancel_action()
	_cancel_staff_area_mode()
	_cancel_owner_area_mode()
	_cancel_hole_move_mode()
	_close_hole_context_menu()
	placement_manager.cancel_placement()
	_cancel_elevation_mode()
	_cancel_bulldozer_mode()
	current_tool = -1
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	_disable_terrain_painting_preview()
	inspect_mode = true
	if terrain_toolbar:
		terrain_toolbar.set_inspect_active(true)

func _cancel_inspect_mode() -> void:
	inspect_mode = false
	if terrain_toolbar:
		terrain_toolbar.set_inspect_active(false)
	if tile_inspector:
		tile_inspector.hide()

func _update_tile_inspector() -> void:
	if not tile_inspector:
		return
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position()
	# UI, modal menus and off-course positions must not reveal tiles behind them.
	if not inspect_mode or GameManager.current_mode == GameManager.GameMode.MAIN_MENU \
			or GameManager.is_paused or viewport.gui_get_hovered_control() != null \
			or not viewport.get_visible_rect().has_point(mouse):
		tile_inspector.hide()
		return
	var tile := terrain_grid.screen_to_grid(camera.get_mouse_world_position())
	tile_inspector.show_tile(terrain_grid, entity_layer, tile, mouse)

func _on_menu_pressed() -> void:
	# Open the game menu (pause menu) overlay
	_toggle_pause_menu()

func _show_save_load_panel(from_pause_menu: bool = false, open_mode: int = SaveLoadPanel.ScreenMode.LOAD) -> void:
	# Toggle save/load panel
	var hud = $UI/HUD
	var existing = hud.get_node_or_null("SaveLoadPanel")
	if existing:
		existing.queue_free()
		return
	_just_loaded_game = false
	var panel = SaveLoadPanel.new()
	panel.name = "SaveLoadPanel"
	# Saving and quitting only make sense while a course is live (the pause
	# menu); the title screen and the game-over panel can only load.
	panel.allow_save = from_pause_menu
	panel.open_mode = open_mode
	if from_pause_menu:
		panel.camera = camera
	panel.quit_to_menu_requested.connect(_on_quit_to_menu)
	if from_pause_menu:
		panel.panel_closed.connect(_on_save_load_panel_closed_from_pause)
	hud.add_child(panel)

func _on_save_load_panel_closed_from_pause() -> void:
	"""Called when the save/load panel (opened from the pause menu) closes."""
	if _just_loaded_game:
		# A game was just loaded — end the pause session and resume play.
		_just_loaded_game = false
		_hide_pause_menu()
		_pause_session_active = false
		GameManager.is_paused = false
		return
	# Backed out without loading — return to the pause menu (game stays paused).
	_show_pause_menu()

func _on_quit_to_menu() -> void:
	# Return to main menu by reloading the scene
	# This resets all game state cleanly
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	get_tree().reload_current_scene()

## Guarantee the course has its one required building. Existing clubhouses are
## left exactly where they are; a missing one is placed at `preferred` (or at
## the centre of the owned land when nothing is suggested) — the same helper
## golfers read for their front door.
func _ensure_course_clubhouse(preferred: Vector2i = Vector2i(-1, -1)) -> Building:
	if terrain_grid == null or entity_layer == null:
		return null
	return CourseClubhouse.ensure(terrain_grid, entity_layer, preferred)

func _on_load_completed(success: bool) -> void:
	_cancel_inspect_mode()
	_just_loaded_game = success
	_close_hole_context_menu()
	_cancel_hole_move_mode()
	_cancel_building_move()
	if success:
		_game_over_shown = false
		# A save from before the clubhouse rule (or one whose clubhouse could
		# not be placed where its layout wanted) still gets one. Its grounds
		# are landscaping, not an edit to undo.
		_suppress_tile_undo = true
		_ensure_course_clubhouse()
		_suppress_tile_undo = false
		_rebuild_hole_list()
		# Sync hole creation tool so the next hole gets the correct number
		if GameManager.current_course:
			hole_tool.current_hole_number = GameManager.current_course.holes.size() + 1
		# Recalculate derived stroke indices from loaded difficulty ratings
		StrokeIndexCalculator.recalculate_for_course()
		# Center camera on grid (same as new game) so player starts on their course
		_center_camera_on_course()
		# The owner's own golfer is on the course, working the ground the
		# player gave them.
		if player_golfer_manager:
			player_golfer_manager.on_course_ready()

# --- Hole Context Menu & Move Modes ---

func _on_hole_flag_selected(hole_number: int) -> void:
	if _has_active_tool():
		return
	# The owner's live round owns clicks on the course so a flag click can aim.
	if is_instance_valid(player_round) and player_round.active:
		return
	_on_hole_button_pressed(hole_number)

func _open_hole_context_menu(hole_data: GameManager.HoleData) -> void:
	_close_hole_context_menu()
	_hole_context_menu = HoleContextMenu.new(hole_data, terrain_grid)
	_hole_context_menu.name = "HoleContextMenu"
	$UI.add_child(_hole_context_menu)
	_hole_context_menu.position_at(get_viewport().get_mouse_position())

	# Connect signals
	_hole_context_menu.move_tee_requested.connect(_on_context_move_tee)
	_hole_context_menu.move_green_requested.connect(_on_context_move_green)
	_hole_context_menu.toggle_hole_requested.connect(_on_context_toggle_hole)
	_hole_context_menu.view_stats_requested.connect(_on_context_view_stats)
	_hole_context_menu.par_override_requested.connect(_on_context_par_override)
	_hole_context_menu.delete_hole_requested.connect(_on_context_delete_hole)
	_hole_context_menu.menu_closed.connect(_on_context_menu_closed)

	# Highlight the hole
	hole_manager.highlight_hole(hole_data.hole_number, true)

func _close_hole_context_menu() -> void:
	if not _hole_context_menu:
		return
	if is_instance_valid(_hole_context_menu):
		if _hole_context_menu.hole_data:
			hole_manager.highlight_hole(_hole_context_menu.hole_data.hole_number, false)
		_hole_context_menu.queue_free()
	_hole_context_menu = null

func _on_context_menu_closed() -> void:
	if _hole_context_menu and _hole_context_menu.hole_data:
		hole_manager.highlight_hole(_hole_context_menu.hole_data.hole_number, false)
	_hole_context_menu = null

func _on_context_move_tee(hole_number: int) -> void:
	var hole = _find_hole_data(hole_number)
	if hole:
		_enter_hole_move_mode(HoleMoveMode.MOVING_TEE, hole)

func _on_context_move_green(hole_number: int) -> void:
	var hole = _find_hole_data(hole_number)
	if hole:
		_enter_hole_move_mode(HoleMoveMode.MOVING_GREEN, hole)

func _on_context_toggle_hole(hole_number: int) -> void:
	if GameManager.current_course:
		var is_open = GameManager.current_course.toggle_hole_open(hole_number)
		EventBus.notify("Hole %d %s" % [hole_number, "opened" if is_open else "closed"], "info")

func _on_context_par_override(hole_number: int, new_par: int) -> void:
	if not hole_manager.set_hole_par(hole_number, new_par):
		return
	var hole = _find_hole_data(hole_number)
	var label = "Par %d (auto)" % new_par if hole and hole.par_override < 0 \
		else "Par %d (manual)" % new_par
	EventBus.notify("Hole %d set to %s" % [hole_number, label], "info")

func _on_context_view_stats(hole_number: int) -> void:
	_show_hole_stats(hole_number)

## Deleting a hole renumbers every hole after it, so it asks first. The hole's
## tee box and green stay painted on the course: repaint them, or paint a green
## to cut a cup for the tee box the deleted hole leaves waiting.
func _on_context_delete_hole(hole_number: int) -> void:
	if not _find_hole_data(hole_number):
		return
	var dialog := ConfirmDialog.new(
			"Hole %d will be removed and the holes after it renumbered.\nIts tee box and green stay on the course." % hole_number,
			"Delete Hole", "Cancel")
	dialog.name = "DeleteHoleConfirmDialog"
	dialog.confirmed.connect(_on_delete_hole_confirmed.bind(hole_number))
	$UI/HUD.add_child(dialog)

func _on_delete_hole_confirmed(hole_number: int) -> void:
	if not hole_tool.delete_hole(hole_number):
		EventBus.notify("Hole %d is not on the course." % hole_number, "error")
		return
	EventBus.notify("Hole %d deleted — the holes after it renumbered" % hole_number, "info")

func _find_hole_data(hole_number: int) -> GameManager.HoleData:
	if not GameManager.current_course:
		return null
	for hole in GameManager.current_course.holes:
		if hole.hole_number == hole_number:
			return hole
	return null

func _enter_hole_move_mode(mode: int, hole_data: GameManager.HoleData) -> void:
	_cancel_inspect_mode()
	_hole_move_mode = mode
	_hole_move_data = hole_data
	hole_manager.highlight_hole(hole_data.hole_number, true)
	if placement_preview:
		placement_preview.set_hole_move_mode(mode)

func _cancel_hole_move_mode() -> void:
	if _hole_move_mode == HoleMoveMode.NONE:
		return
	if _hole_move_data and _hole_move_data.hole_number != _highlighted_hole_number:
		hole_manager.highlight_hole(_hole_move_data.hole_number, false)
	_hole_move_mode = HoleMoveMode.NONE
	_hole_move_data = null
	if placement_preview:
		placement_preview.set_hole_move_mode(HoleMoveMode.NONE)

func _handle_hole_move_click(grid_pos: Vector2i) -> void:
	if not _hole_move_data:
		return
	match _hole_move_mode:
		HoleMoveMode.MOVING_TEE:
			if _is_valid_tee_position(grid_pos):
				_execute_tee_move(grid_pos)
		HoleMoveMode.MOVING_GREEN:
			if _is_valid_green_position(grid_pos):
				_execute_green_move(grid_pos)

func _is_valid_tee_position(pos: Vector2i) -> bool:
	if not terrain_grid.is_valid_position(pos):
		return false
	var tile = terrain_grid.get_tile(pos)
	if TerrainTypes.is_water(tile) or tile == TerrainTypes.Type.OUT_OF_BOUNDS:
		return false
	if entity_layer and entity_layer.is_tile_occupied_by_building(pos):
		return false
	# Minimum distance from green
	if pos.distance_to(_hole_move_data.green_position) < 5:
		return false
	# Not another hole's tee or green
	for hole in GameManager.current_course.holes:
		if hole.hole_number != _hole_move_data.hole_number:
			if pos == hole.tee_position or pos == hole.green_position or pos == hole.hole_position:
				return false
	return true

func _is_valid_green_position(pos: Vector2i) -> bool:
	if not terrain_grid.is_valid_position(pos):
		return false
	var tile = terrain_grid.get_tile(pos)
	if TerrainTypes.is_water(tile) or tile == TerrainTypes.Type.OUT_OF_BOUNDS:
		return false
	if entity_layer and entity_layer.is_tile_occupied_by_building(pos):
		return false
	# Minimum distance from tee
	if pos.distance_to(_hole_move_data.tee_position) < 5:
		return false
	# Not another hole's tee or green
	for hole in GameManager.current_course.holes:
		if hole.hole_number != _hole_move_data.hole_number:
			if pos == hole.tee_position or pos == hole.green_position or pos == hole.hole_position:
				return false
	return true

func _execute_tee_move(new_pos: Vector2i) -> void:
	var hole_number = _hole_move_data.hole_number
	var old_tee_pos = _hole_move_data.tee_position
	var old_tee_was_tee_box = terrain_grid.get_tile(old_tee_pos) == TerrainTypes.Type.TEE_BOX
	var old_terrain_at_new = terrain_grid.get_tile(new_pos)
	var tee_cost = TerrainTypes.get_placement_cost(TerrainTypes.Type.TEE_BOX)

	if not GameManager.can_afford(tee_cost):
		EventBus.notify("Not enough money!", "error")
		return

	var visualizer = hole_manager.get_hole_visualizer(hole_number)
	if not visualizer:
		_cancel_hole_move_mode()
		return

	_suppress_tile_undo = true

	# Revert old tee tile to grass if it's still a tee box
	if old_tee_was_tee_box:
		terrain_grid.set_tile(old_tee_pos, TerrainTypes.Type.GRASS)

	# The tee goes down: painting the tile replaces whatever ground was there.
	terrain_grid.set_tile(new_pos, TerrainTypes.Type.TEE_BOX)

	_suppress_tile_undo = false

	visualizer.update_tee_position(new_pos)
	GameManager.modify_money(-tee_cost)
	EventBus.log_transaction("Move Tee (Hole %d)" % hole_number, -tee_cost)
	EventBus.hole_tee_moved.emit(hole_number, old_tee_pos, new_pos)

	# Record undo
	undo_manager.record_action({
		"type": "tee_move",
		"hole_number": hole_number,
		"old_tee_pos": old_tee_pos,
		"new_tee_pos": new_pos,
		"old_terrain_at_new": old_terrain_at_new,
		"old_tee_was_tee_box": old_tee_was_tee_box,
		"cost": tee_cost
	})

	var label = "placed" if not old_tee_was_tee_box else "moved"
	EventBus.notify("Hole %d tee box %s" % [hole_number, label], "success")
	_cancel_hole_move_mode()

func _execute_green_move(new_pos: Vector2i) -> void:
	var hole_number = _hole_move_data.hole_number
	var old_green_pos = _hole_move_data.green_position
	var old_green_was_green = terrain_grid.get_tile(old_green_pos) == TerrainTypes.Type.GREEN
	var old_terrain_at_new = terrain_grid.get_tile(new_pos)
	var green_cost = TerrainTypes.get_placement_cost(TerrainTypes.Type.GREEN)

	if not GameManager.can_afford(green_cost):
		EventBus.notify("Not enough money!", "error")
		return

	var visualizer = hole_manager.get_hole_visualizer(hole_number)
	if not visualizer:
		_cancel_hole_move_mode()
		return

	_suppress_tile_undo = true

	# Revert old green tile to grass if it's still a green
	if old_green_was_green:
		terrain_grid.set_tile(old_green_pos, TerrainTypes.Type.GRASS)

	# The green goes down the same way, replacing the ground under it.
	terrain_grid.set_tile(new_pos, TerrainTypes.Type.GREEN)

	_suppress_tile_undo = false

	visualizer.update_green_position(new_pos)
	GameManager.modify_money(-green_cost)
	EventBus.log_transaction("Move Green (Hole %d)" % hole_number, -green_cost)
	EventBus.hole_green_moved.emit(hole_number, old_green_pos, new_pos)

	# Record undo
	undo_manager.record_action({
		"type": "green_move",
		"hole_number": hole_number,
		"old_green_pos": old_green_pos,
		"new_green_pos": new_pos,
		"old_terrain_at_new": old_terrain_at_new,
		"old_green_was_green": old_green_was_green,
		"cost": green_cost
	})

	var label = "placed" if not old_green_was_green else "moved"
	EventBus.notify("Hole %d green %s" % [hole_number, label], "success")
	_cancel_hole_move_mode()

# --- Undo/Redo System ---

var _is_undoing: bool = false  # Prevent re-recording changes triggered by undo/redo
var _suppress_tile_undo: bool = false  # Suppress tile change recording during entity placement/removal

func _on_terrain_tile_changed_for_undo(tile_pos: Vector2i, old_type: int, new_type: int) -> void:
	if _is_undoing or _suppress_tile_undo or not terrain_grid.tile_change_records_undo:
		# Still keep tee UI in sync even while undoing or suppressing undo recording.
		if old_type == TerrainTypes.Type.TEE_BOX or new_type == TerrainTypes.Type.TEE_BOX:
			_refresh_hole_layout_ui()
		return
	undo_manager.record_tile_change(tile_pos, old_type, new_type)
	if old_type == TerrainTypes.Type.TEE_BOX or new_type == TerrainTypes.Type.TEE_BOX:
		_refresh_hole_layout_ui()

func _perform_undo() -> void:
	if not undo_manager.can_undo():
		return

	var action = undo_manager.undo()
	if action.is_empty():
		return

	_is_undoing = true
	_execute_undo_action(action)
	_is_undoing = false
	_refresh_hole_layout_ui()
	EventBus.notify("Undo", "info")

func _perform_redo() -> void:
	if not undo_manager.can_redo():
		return

	var pending: Dictionary = undo_manager.redo_stack.back()
	var price: int = pending.get("paid_cost", pending.get("cost", 0))
	if pending.get("type") == "terrain" and not pending.has("paid_cost"):
		for change in pending.get("changes", []):
			price += TerrainTypes.get_placement_cost(change.new_type)
	if GameManager.money < price:
		EventBus.notify("Not enough cash to redo this action", "warning")
		return
	var action = undo_manager.redo()
	if action.is_empty():
		return

	_is_undoing = true
	_execute_redo_action(action)
	_is_undoing = false
	_refresh_hole_layout_ui()
	EventBus.notify("Redo", "info")

func _execute_undo_action(action: Dictionary) -> void:
	match action.get("type", ""):
		"terrain":
			# Revert all tile changes in reverse order
			var changes = action.get("changes", [])
			var refund = 0
			for i in range(changes.size() - 1, -1, -1):
				var change = changes[i]
				terrain_grid.set_tile(change["position"], change["old_type"])
				if not change.get("old_player_placed", true): terrain_grid._player_placed_tiles.erase(change.position)
				if change.has("old_cup"):
					if change.old_cup: terrain_grid.add_cup_tile(change.position)
					else: terrain_grid.remove_cup_tile(change.position)
				refund += TerrainTypes.get_placement_cost(change["new_type"])
			# Revert walking-path (Path improvement) changes made in the same stroke.
			for wp in action.get("walking_paths", []):
				terrain_grid.set_walking_path(wp["position"], not wp["added"])
			refund = action.get("paid_cost", refund)
			if refund > 0:
				GameManager.modify_money(refund)
		"walking_paths":
			# Standalone Path improvement change (e.g. a bulldozer removal).
			var changes = action.get("changes", [])
			for i in range(changes.size() - 1, -1, -1):
				terrain_grid.set_walking_path(changes[i]["position"], not changes[i]["added"])
		"elevation":
			# Revert vertex height changes in reverse order
			var changes = action.get("changes", [])
			for i in range(changes.size() - 1, -1, -1):
				var change = changes[i]
				terrain_grid.set_vertex_elevation(change["position"], change["old_elevation"])
		"entity_place":
			# Remove the entity and refund its cost.
			var grid_pos = action.get("grid_pos", Vector2i.ZERO)
			var entity_type = action.get("entity_type", "")
			var cost = action.get("cost", 0)
			match entity_type:
				"building":
					entity_layer.remove_building(grid_pos)
				"decoration":
					entity_layer.remove_decoration(grid_pos)
			if cost > 0:
				GameManager.modify_money(cost)
		"tee_move":
			var hn = action.get("hole_number", 0)
			var old_tee = action.get("old_tee_pos", Vector2i.ZERO)
			var new_tee = action.get("new_tee_pos", Vector2i.ZERO)
			_suppress_tile_undo = true
			terrain_grid.set_tile(new_tee, action.get("old_terrain_at_new", TerrainTypes.Type.GRASS))
			if action.get("old_tee_was_tee_box", false):
				terrain_grid.set_tile(old_tee, TerrainTypes.Type.TEE_BOX)
			_suppress_tile_undo = false
			var vis = hole_manager.get_hole_visualizer(hn)
			if vis:
				vis.update_tee_position(old_tee)
			GameManager.modify_money(action.get("cost", 0))
		"green_move":
			var hn = action.get("hole_number", 0)
			var old_green = action.get("old_green_pos", Vector2i.ZERO)
			var new_green = action.get("new_green_pos", Vector2i.ZERO)
			_suppress_tile_undo = true
			terrain_grid.set_tile(new_green, action.get("old_terrain_at_new", TerrainTypes.Type.GRASS))
			if action.get("old_green_was_green", false):
				terrain_grid.set_tile(old_green, TerrainTypes.Type.GREEN)
			_suppress_tile_undo = false
			var vis = hole_manager.get_hole_visualizer(hn)
			if vis:
				# The cup rides along with the green back to its old home.
				vis.update_green_position(old_green)
			GameManager.modify_money(action.get("cost", 0))
		"building_move":
			var move_building = action.get("building", null)
			var move_to: Vector2i = action.get("old_pos", Vector2i.ZERO)
			if is_instance_valid(move_building) and entity_layer:
				entity_layer.move_building(move_building, move_to)

func _execute_redo_action(action: Dictionary) -> void:
	match action.get("type", ""):
		"terrain":
			# Re-apply all tile changes in order
			var changes = action.get("changes", [])
			var cost = 0
			for change in changes:
				terrain_grid.set_tile(change["position"], change["new_type"])
				if change.has("new_cup"):
					if change.new_cup: terrain_grid.add_cup_tile(change.position)
					else: terrain_grid.remove_cup_tile(change.position)
				cost += TerrainTypes.get_placement_cost(change["new_type"])
			# Re-apply walking-path (Path improvement) changes from the same stroke.
			for wp in action.get("walking_paths", []):
				terrain_grid.set_walking_path(wp["position"], wp["added"])
			cost = action.get("paid_cost", cost)
			if cost > 0:
				GameManager.modify_money(-cost)
		"walking_paths":
			# Standalone Path improvement change (e.g. a bulldozer removal).
			var changes = action.get("changes", [])
			for change in changes:
				terrain_grid.set_walking_path(change["position"], change["added"])
		"elevation":
			# Re-apply vertex height changes in order
			var changes = action.get("changes", [])
			for change in changes:
				terrain_grid.set_vertex_elevation(change["position"], change["new_elevation"])
		"entity_place":
			# Re-place the entity and deduct cost. Undo put back whatever this
			# placement replaced; lift that again so the redo matches the click.
			var grid_pos = action.get("grid_pos", Vector2i.ZERO)
			var entity_type = action.get("entity_type", "")
			var subtype = action.get("subtype", "")
			var cost = action.get("cost", 0)
			match entity_type:
				"building":
					entity_layer.place_building(subtype, grid_pos, building_registry)
				"decoration":
					entity_layer.place_decoration(subtype, grid_pos, decoration_registry)
			if cost > 0:
				GameManager.modify_money(-cost)
		"building_move":
			var move_building = action.get("building", null)
			var move_to: Vector2i = action.get("new_pos", Vector2i.ZERO)
			if is_instance_valid(move_building) and entity_layer:
				entity_layer.move_building(move_building, move_to)
		"tee_move":
			var hn = action.get("hole_number", 0)
			var old_tee = action.get("old_tee_pos", Vector2i.ZERO)
			var new_tee = action.get("new_tee_pos", Vector2i.ZERO)
			_suppress_tile_undo = true
			if action.get("old_tee_was_tee_box", false):
				terrain_grid.set_tile(old_tee, TerrainTypes.Type.GRASS)
			terrain_grid.set_tile(new_tee, TerrainTypes.Type.TEE_BOX)
			_suppress_tile_undo = false
			var vis = hole_manager.get_hole_visualizer(hn)
			if vis:
				vis.update_tee_position(new_tee)
			GameManager.modify_money(-action.get("cost", 0))
		"green_move":
			var hn = action.get("hole_number", 0)
			var old_green = action.get("old_green_pos", Vector2i.ZERO)
			var new_green = action.get("new_green_pos", Vector2i.ZERO)
			_suppress_tile_undo = true
			if action.get("old_green_was_green", false):
				terrain_grid.set_tile(old_green, TerrainTypes.Type.GRASS)
			terrain_grid.set_tile(new_green, TerrainTypes.Type.GREEN)
			_suppress_tile_undo = false
			var vis = hole_manager.get_hole_visualizer(hn)
			if vis:
				vis.update_green_position(new_green)
			GameManager.modify_money(-action.get("cost", 0))

# --- Building Info Panel ---

func _setup_building_info_panel() -> void:
	"""Add building info panel to the HUD."""
	var hud = $UI/HUD
	building_info_panel.name = "BuildingInfoPanel"
	hud.add_child(building_info_panel)
	building_info_panel.move_requested.connect(_on_building_move_requested)
	building_info_panel.hide()

func _on_building_clicked(building: Building) -> void:
	"""Show building info panel when a building is clicked."""
	# If in any placement mode, don't open the panel
	if placement_manager.placement_mode != PlacementManager.PlacementMode.NONE:
		if placement_manager.placement_mode == PlacementManager.PlacementMode.BUILDING:
			EventBus.notify("Cannot place here - overlaps with existing building!", "error")
		return

	# Only show for upgradeable buildings or buildings with stats. The required
	# clubhouse always opens: its panel carries the only way to move it.
	if building.is_required() or building.building_data.get("upgradeable", false) or building.get_income_per_golfer() > 0:
		building_info_panel.show_for_building(building)

		# Center the panel on screen, clamped so it stays fully visible on
		# small (phone) windows.
		var viewport_size = get_viewport().get_visible_rect().size
		var panel_size = building_info_panel.custom_minimum_size
		building_info_panel.position = _center_position_clamped(viewport_size, panel_size)

func _on_building_panel_closed() -> void:
	"""Hide the building info panel."""
	building_info_panel.hide()

# --- Moving the clubhouse ---
#
# The clubhouse is the course's one required building: it cannot be demolished
# (the Bulldozer refuses it, EntityLayer.remove_building refuses it), so the way
# to put it somewhere else is to pick it up. Move Clubhouse in its info panel
# starts that: the ghost of the building follows the cursor, and the next click
# sets it down on a legal footprint — the same rules the Buildings tab uses,
# with the building itself ignored. Esc or a right-click puts it back.

func _on_building_move_requested(building: Building) -> void:
	"""Pick a required building up so the next click sets it down."""
	if not is_instance_valid(building) or not building.is_required():
		return
	_cancel_inspect_mode()
	_cancel_hole_move_mode()
	_close_hole_context_menu()
	_cancel_elevation_mode()
	_cancel_bulldozer_mode()
	_cancel_staff_area_mode()
	_cancel_owner_area_mode()
	placement_manager.cancel_placement()
	_disable_terrain_painting_preview()
	if terrain_toolbar:
		terrain_toolbar.clear_selection()
	is_painting = false
	_moving_building = building
	building_info_panel.hide()
	if placement_preview:
		placement_preview.set_building_move_target(building)
	EventBus.notify("%s picked up — click a tile to set it down, right-click or Esc to cancel." % _building_display_name(building), "info")

func _cancel_building_move() -> void:
	"""Put the carried building back down where it was."""
	if _moving_building == null:
		return
	_moving_building = null
	if placement_preview:
		placement_preview.set_building_move_target(null)

func _handle_building_move_click(grid_pos: Vector2i) -> void:
	"""Set the carried building down on the clicked tile when the rules allow."""
	if _moving_building == null:
		return
	var error := CourseClubhouse.move_error(terrain_grid, entity_layer, _moving_building, grid_pos)
	if not error.is_empty():
		EventBus.notify(error, "error")
		return
	var building := _moving_building
	var building_name := _building_display_name(building)
	var old_pos: Vector2i = building.grid_position
	if CourseClubhouse.move_to(entity_layer, building, grid_pos):
		# Moving is free; Ctrl+Z still puts it back where it stood.
		undo_manager.record_action({
			"type": "building_move",
			"building": building,
			"old_pos": old_pos,
			"new_pos": grid_pos,
		})
		EventBus.notify("%s moved." % building_name, "success")
	_cancel_building_move()

## The name a building is announced under (its data name, else its type).
func _building_display_name(building: Building) -> String:
	if building == null:
		return "Building"
	var display_name: String = str(building.building_data.get("name", "")) if not building.building_data.is_empty() else ""
	if display_name.is_empty():
		display_name = building.building_type.replace("_", " ").capitalize()
	return display_name

# --- Financial Overview ---

func _setup_financial_panel() -> void:
	"""Add the unified full-screen Financial Overview to the HUD."""
	var hud = $UI/HUD
	financial_panel = FinancialPanel.new()
	financial_panel.name = "FinancialOverviewScreen"
	financial_panel.close_requested.connect(_on_financial_panel_closed)
	hud.add_child(financial_panel)
	financial_panel.hide()

func _toggle_financial_overview() -> void:
	"""Open or close the unified company dashboard on its finance page."""
	if not financial_panel:
		return
	if not financial_panel.visible:
		financial_panel.select_section(FinancialOverviewScreen.Section.FINANCE)
	_toggle_panel(financial_panel)

func _on_money_clicked() -> void:
	_toggle_financial_overview()

func _on_financial_panel_closed() -> void:
	"""Hide the full-screen dashboard and release the active-panel slot."""
	if financial_panel:
		financial_panel.hide()
	if _active_panel == financial_panel:
		_active_panel = null

# --- Mini Map ---

func _setup_mini_map() -> void:
	"""Add mini-map to the HUD in bottom-left corner."""
	var hud = $UI/HUD

	mini_map = MiniMap.new()
	mini_map.name = "MiniMap"
	mini_map.setup(terrain_grid, entity_layer, golfer_manager)
	mini_map.camera_move_requested.connect(_on_mini_map_camera_move)

	hud.add_child(mini_map)
	# Pick the responsive map size now that the node is in the tree, then dock
	# it in the corner (its size feeds the corner offsets).
	mini_map.apply_screen()
	_position_mini_map()

## Dock the minimap in the bottom-left corner, above the bottom bar. Re-run
## on responsive resizes: the map itself changes size (compact windows get
## a smaller map), so the offsets are computed from its live size.
func _position_mini_map() -> void:
	if not mini_map:
		return
	var map_size := mini_map.get_map_total_size()
	mini_map.anchor_left = 0
	mini_map.anchor_top = 1
	mini_map.anchor_right = 0
	mini_map.anchor_bottom = 1
	mini_map.offset_left = 0
	mini_map.offset_top = -(Screen.bottom_bar_height() + map_size.y + MiniMap.BORDER_WIDTH)
	mini_map.offset_right = map_size.x + MiniMap.BORDER_WIDTH
	mini_map.offset_bottom = -Screen.bottom_bar_height()

func _on_mini_map_camera_move(world_position: Vector2) -> void:
	"""Move camera to the position clicked on mini-map."""
	camera.focus_on(world_position, false)

func _update_mini_map_camera() -> void:
	"""Update the mini-map camera viewport indicator."""
	if not mini_map or not mini_map.visible:
		return

	# Get current camera viewport in world coordinates
	var viewport_size = get_viewport().get_visible_rect().size
	var camera_pos = camera.global_position
	var zoom = camera.zoom

	# Calculate visible world rect
	var visible_size = viewport_size / zoom
	var top_left = camera_pos - visible_size / 2
	var viewport_rect = Rect2(top_left, visible_size)

	mini_map.set_camera_rect(viewport_rect, terrain_grid.grid_width, terrain_grid.grid_height)

# --- Hole Stats Panel ---

func _setup_hole_stats_panel() -> void:
	"""Add hole stats panel to the HUD."""
	var hud = $UI/HUD

	hole_stats_panel = HoleStatsPanel.new()
	hole_stats_panel.name = "HoleStatsPanel"
	hole_stats_panel.close_requested.connect(_on_hole_stats_panel_closed)
	hole_stats_panel.hole_selected.connect(_on_hole_stats_selected)
	hud.add_child(hole_stats_panel)
	hole_stats_panel.hide()

func _on_hole_stats_panel_closed() -> void:
	"""Hide the hole stats panel."""
	hole_stats_panel.hide()
	if _active_panel == hole_stats_panel:
		_active_panel = null

func _on_hole_stats_selected(hole_number: int) -> void:
	"""Highlight hole on course and move camera to it."""
	if not GameManager.current_course:
		return

	for hole in GameManager.current_course.holes:
		if hole.hole_number == hole_number:
			# Move camera to center between tee and green
			var tee_world = terrain_grid.grid_to_screen_center(hole.tee_position)
			var green_world = terrain_grid.grid_to_screen_center(hole.green_position)
			var center = (tee_world + green_world) / 2
			camera.focus_on(center, false)
			break

func _show_hole_stats(hole_number: int) -> void:
	"""Show hole stats panel for the given hole number."""
	if not GameManager.current_course:
		return

	for hole in GameManager.current_course.holes:
		if hole.hole_number == hole_number:
			# Close any active panel first
			if _active_panel and _active_panel.visible:
				_active_panel.hide()
			hole_stats_panel.show_for_hole(hole)
			_active_panel = hole_stats_panel
			break

# --- Tournament Panel ---

func _setup_tournament_panel() -> void:
	"""Put tournament hosting on the Player tab's Play Course page."""
	tournament_panel = TournamentPanel.new()
	tournament_panel.embedded = true
	tournament_panel.name = "TournamentPanel"
	tournament_panel.close_requested.connect(_on_tournament_panel_closed)
	terrain_toolbar.player_tab.add_persistent(tournament_panel)
	tournament_panel.setup(tournament_manager)

func _on_tournament_panel_closed() -> void:
	"""Hide the tournament panel."""
	tournament_panel.hide()
	if _active_panel == tournament_panel:
		_active_panel = null

func _toggle_tournament_panel() -> void:
	"""Toggle the tournament panel visibility."""
	terrain_toolbar.select_player_section(PlayerTab.PAGE_PLAY)
	tournament_panel._refresh_display()

func _on_tournament_completed(_tier: int, results: Dictionary) -> void:
	"""Show the post-event financial and highlight summary."""
	if tournament_results_popup:
		var entries = results.get("all_entries", [])
		tournament_results_popup.show_results(_tier, results, entries)

func _toggle_terrain_debug_overlay() -> void:
	"""Toggle the terrain debug overlay (F3)."""
	if terrain_grid:
		terrain_grid.toggle_debug_overlay()

## J (or its rebinding): the fairway width overlay and the carry annotations
## travel together.
func _toggle_fairway_width_overlay() -> void:
	terrain_grid.toggle_fairway_width_overlay()
	HoleVisualizer.carry_annotations_visible = not HoleVisualizer.carry_annotations_visible
	for vis in hole_manager.get_all_hole_visualizers():
		vis._update_carry_annotations()

func _on_parcel_purchased(parcel: Vector2i) -> void:
	"""Generate premium terrain features when a premium/elite parcel is purchased."""
	var lm = GameManager.land_manager
	if not lm or lm.has_features_generated(parcel):
		return
	var tier: int = lm.get_parcel_tier(parcel)
	if tier == 0:  # TIER_STANDARD
		return
	# Deterministic seed from parcel position
	var rng = RandomNumberGenerator.new()
	rng.seed = parcel.x * 1000 + parcel.y + hash(GameManager.current_theme)
	terrain_grid.begin_batch()
	PremiumFeatureGenerator.generate_for_parcel(parcel, terrain_grid, entity_layer, rng)
	terrain_grid.end_batch_quiet()
	terrain_grid.refresh_all_overlays()

# --- Marketing (inside Financial Overview) ---

func _setup_marketing_panel() -> void:
	"""Marketing is now a section of Financial Overview, not a popup."""
	marketing_panel = null

func _on_marketing_panel_closed() -> void:
	"""Compatibility handler: closing Marketing closes the shared dashboard."""
	_on_financial_panel_closed()

# --- Hotkey Panel ---

func _setup_hotkey_panel() -> void:
	"""Add hotkey reference panel to the HUD."""
	var hud = $UI/HUD

	hotkey_panel = HotkeyPanel.new()
	hotkey_panel.name = "HotkeyPanel"
	hud.add_child(hotkey_panel)
	hotkey_panel.hide()

func _toggle_hotkey_panel() -> void:
	"""Toggle the hotkey reference panel."""
	if hotkey_panel:
		_toggle_panel(hotkey_panel)

func _toggle_marketing_panel() -> void:
	"""Open Financial Overview on the Marketing page, or switch to it if open."""
	if not financial_panel:
		return
	if financial_panel.visible:
		financial_panel.select_section(FinancialOverviewScreen.Section.MARKETING)
		return
	financial_panel.select_section(FinancialOverviewScreen.Section.MARKETING)
	_toggle_panel(financial_panel)

# --- Weather Debug ---

func _setup_weather_debug_panel() -> void:
	"""Add weather debug panel to the HUD."""
	var hud = $UI/HUD
	weather_debug_panel = WeatherDebugPanel.new()
	weather_debug_panel.name = "WeatherDebugPanel"
	weather_debug_panel.close_requested.connect(_on_weather_debug_panel_closed)
	hud.add_child(weather_debug_panel)
	weather_debug_panel.hide()

func _on_weather_debug_panel_closed() -> void:
	weather_debug_panel.hide()
	_active_panel = null

func _toggle_weather_debug_panel() -> void:
	"""Toggle the weather debug panel."""
	if weather_debug_panel:
		_toggle_panel(weather_debug_panel)

# --- Season Debug ---

func _setup_season_debug_panel() -> void:
	"""Add season debug panel to the HUD."""
	var hud = $UI/HUD
	season_debug_panel = SeasonDebugPanel.new()
	season_debug_panel.name = "SeasonDebugPanel"
	season_debug_panel.close_requested.connect(_on_season_debug_panel_closed)
	hud.add_child(season_debug_panel)
	season_debug_panel.hide()

func _on_season_debug_panel_closed() -> void:
	season_debug_panel.hide()
	_active_panel = null

func _toggle_season_debug_panel() -> void:
	"""Toggle the season debug panel."""
	if season_debug_panel:
		_toggle_panel(season_debug_panel)

# --- Analytics Panel ---

func _setup_analytics_panel() -> void:
	"""Add analytics panel to the HUD."""
	var hud = $UI/HUD
	analytics_panel_ui = AnalyticsPanel.new()
	analytics_panel_ui.name = "AnalyticsPanel"
	analytics_panel_ui.close_requested.connect(_on_analytics_panel_closed)
	hud.add_child(analytics_panel_ui)
	analytics_panel_ui.hide()

func _on_analytics_panel_closed() -> void:
	analytics_panel_ui.hide()
	if _active_panel == analytics_panel_ui:
		_active_panel = null

func _toggle_analytics_panel() -> void:
	"""Toggle the analytics panel visibility."""
	if analytics_panel_ui:
		_toggle_panel(analytics_panel_ui)

# --- Golfer Info Popup ---

func _setup_golfer_profile_navigation() -> void:
	golfer_manager.golfer_clicked.connect(_on_golfer_clicked)

func _on_golfer_clicked(golfer: Golfer) -> void:
	if placement_manager.placement_mode != PlacementManager.PlacementMode.NONE:
		return
	if _active_panel and _active_panel.visible:
		_active_panel.hide()
	_active_panel = null
	terrain_toolbar.show_visitor_profile(golfer.golfer_name)

# --- Round Summary ---

func _setup_round_summary_popup() -> void:
	round_summary_popup = RoundSummaryPopup.new()
	round_summary_popup.name = "RoundSummaryPopup"
	$UI.add_child(round_summary_popup)
	EventBus.golfer_finished_round.connect(_on_golfer_round_for_summary)

func _on_golfer_round_for_summary(golfer_id: int, total_strokes: int, _total_par: int) -> void:
	var golfer = golfer_manager.get_golfer(golfer_id)
	if not golfer:
		return
	# Every completed round (owner included) feeds the toolbar's Golfers tab history
	if terrain_toolbar:
		terrain_toolbar.record_completed_round({
			"name": golfer.golfer_name,
			"strokes": total_strokes,
			"par": golfer.total_par,
			"day": GameManager.current_day,
			"tier": golfer.golfer_tier,
			"owner": golfer.is_owner_round,
			"profile": _visitor_profile(golfer),
			"portrait": VisitorPortrait.for_golfer(golfer),
		})
	if golfer.is_owner_round:
		return
	round_summary_popup.queue_notification({
		"name": golfer.golfer_name,
		"total_strokes": total_strokes,
		"total_par": golfer.total_par,
		"attitude": golfer.attitude,
		"tier": golfer.golfer_tier,
		"green_fee": GameManager.green_fee,
		"holes_played": golfer.hole_scores.size(),
		"total_holes": golfer._round_total_holes if golfer._round_total_holes > 0 else GameManager.get_open_hole_count(),
	})

# --- Milestone & Achievement Screens ---

func _setup_milestone_system() -> void:
	milestone_manager = MilestoneManager.new()
	milestone_manager.name = "MilestoneManager"
	add_child(milestone_manager)

	# Update SaveManager reference to include milestone manager
	SaveManager.milestone_manager = milestone_manager

## The G hotkey and the Club tab's Course Milestones button: the fullscreen
## per-location goal book, or back to the course if it is already up.
func _toggle_course_milestones_screen() -> void:
	_toggle_goal_screen(MenuScreenKit.GoalTrack.COURSE)

## The Shift+G hotkey and the Club tab's World Milestones button: the
## fullscreen book of company goals across every course location.
func _toggle_world_milestones_screen() -> void:
	_toggle_goal_screen(MenuScreenKit.GoalTrack.WORLD)

## The Shift+T hotkey, the Club tab's Achievements button and the title
## screen's Achievements tile: the trophy room, where career honours stay
## unlocked between saves.
func _toggle_achievements_screen() -> void:
	_toggle_goal_screen(MenuScreenKit.GoalTrack.ACHIEVEMENTS)

## Toggle one of the goal screens: already up on that track, it goes away;
## up on another track, the view flips; closed, it opens from the Club tab.
func _toggle_goal_screen(track: int) -> void:
	if _goal_screen_is_open():
		if _goal_screen_shown(track):
			_on_goal_screen_back()
		else:
			_switch_goal_screen(track)
		return
	_open_goal_screen(track, GoalScreenOrigin.CLUB_TAB)

## Open (or raise) the goal screens. From the Club tab the day freezes and
## the gameplay UI stands down, the same way the World Map and the Course
## Map take the window; from the title screen the menu steps aside and Back
## comes home to it. The title-screen trophy room is standalone, so it omits
## the cross-track navigation shown on the in-game goal screens.
func _open_goal_screen(track: int, origin: int) -> void:
	if origin == GoalScreenOrigin.TITLE_SCREEN:
		_hide_main_menu()
		_set_gameplay_ui_visible(false)
	elif not _goal_screen_is_open():
		_goal_screen_restore_paused = GameManager.is_paused
		GameManager.is_paused = true
		_set_gameplay_ui_visible(false)
	_goal_screen_origin = origin
	var hud := $UI/HUD
	if course_milestones_screen == null:
		course_milestones_screen = CourseMilestonesScreen.new()
		course_milestones_screen.name = "CourseMilestonesScreen"
		course_milestones_screen.set_milestone_manager(milestone_manager)
		course_milestones_screen.back_requested.connect(_on_goal_screen_back)
		course_milestones_screen.track_requested.connect(_switch_goal_screen)
		hud.add_child(course_milestones_screen)
	if world_milestones_screen == null:
		world_milestones_screen = WorldMilestonesScreen.new()
		world_milestones_screen.name = "WorldMilestonesScreen"
		world_milestones_screen.set_milestone_manager(milestone_manager)
		world_milestones_screen.back_requested.connect(_on_goal_screen_back)
		world_milestones_screen.track_requested.connect(_switch_goal_screen)
		hud.add_child(world_milestones_screen)
	var create_achievements_screen := achievements_screen == null
	if create_achievements_screen:
		achievements_screen = AchievementsScreen.new()
		achievements_screen.name = "AchievementsScreen"
		achievements_screen.set_milestone_manager(milestone_manager)
		achievements_screen.back_requested.connect(_on_goal_screen_back)
		achievements_screen.track_requested.connect(_switch_goal_screen)
	achievements_screen.track_navigation_enabled = origin == GoalScreenOrigin.CLUB_TAB
	if create_achievements_screen:
		hud.add_child(achievements_screen)
	_show_goal_screen(track)

## Flip between the three goal screens without leaving them.
func _switch_goal_screen(track: int) -> void:
	if not _goal_screen_is_open():
		_open_goal_screen(track, _goal_screen_origin)
		return
	_show_goal_screen(track)

## Raise one goal screen and stand the other two down.
func _show_goal_screen(track: int) -> void:
	course_milestones_screen.visible = track == MenuScreenKit.GoalTrack.COURSE
	world_milestones_screen.visible = track == MenuScreenKit.GoalTrack.WORLD
	achievements_screen.visible = track == MenuScreenKit.GoalTrack.ACHIEVEMENTS
	if course_milestones_screen.visible:
		course_milestones_screen.move_to_front()
		course_milestones_screen.refresh()
	elif world_milestones_screen.visible:
		world_milestones_screen.move_to_front()
		world_milestones_screen.refresh()
	else:
		achievements_screen.move_to_front()
		achievements_screen.refresh()

func _goal_screen_shown(track: int) -> bool:
	match track:
		MenuScreenKit.GoalTrack.COURSE:
			return course_milestones_screen != null and course_milestones_screen.visible
		MenuScreenKit.GoalTrack.WORLD:
			return world_milestones_screen != null and world_milestones_screen.visible
		_:
			return achievements_screen != null and achievements_screen.visible

func _close_goal_screens() -> void:
	for screen: Control in [course_milestones_screen, world_milestones_screen, achievements_screen]:
		if screen:
			screen.queue_free()
	course_milestones_screen = null
	world_milestones_screen = null
	achievements_screen = null

## True while any goal screen is up. They take the whole window, so the
## course behind them must not answer gameplay hotkeys while one is open.
func _goal_screen_is_open() -> bool:
	for screen: Control in [course_milestones_screen, world_milestones_screen, achievements_screen]:
		if screen != null and not screen.is_queued_for_deletion() and screen.visible:
			return true
	return false

func _on_goal_screen_back() -> void:
	var origin := _goal_screen_origin
	_close_goal_screens()
	match origin:
		GoalScreenOrigin.TITLE_SCREEN:
			_show_main_menu()
		_:
			_set_gameplay_ui_visible(true)
			GameManager.is_paused = _goal_screen_restore_paused

# --- Seasonal Calendar ---

func _setup_seasonal_calendar() -> void:
	seasonal_calendar_panel = SeasonalCalendarPanel.new()
	seasonal_calendar_panel.name = "SeasonalCalendarPanel"
	seasonal_calendar_panel.close_requested.connect(func():
		seasonal_calendar_panel.hide()
		_active_panel = null
	)
	$UI/HUD.add_child(seasonal_calendar_panel)

	# Listen for day changes to announce seasonal events
	EventBus.day_changed.connect(_on_day_changed_for_events)
	EventBus.season_changed.connect(_on_season_changed_notification)

func _toggle_seasonal_calendar() -> void:
	_toggle_panel(seasonal_calendar_panel)

# --- Course Scorecard ---
# The scorecard lives on the Holes tab now. K opens it there, or puts the hole
# register back up if the scorecard is already showing.

func _toggle_course_scorecard() -> void:
	if terrain_toolbar.is_course_scorecard_showing():
		terrain_toolbar.close_course_scorecard()
	else:
		terrain_toolbar.show_course_scorecard()

func _on_day_changed_for_events(_new_day: int) -> void:
	# Check if there's a seasonal event starting today
	var event = SeasonalEvents.get_active_event(_new_day)
	if event:
		var day_in_season = SeasonSystem.get_day_in_season(_new_day)
		if day_in_season == event.day_in_season:
			EventBus.notify("Event: %s" % event.name, "success")
			if event.reputation_bonus > 0:
				GameManager.modify_reputation(event.reputation_bonus)

func _on_season_changed_notification(_old_season: int, _new_season: int) -> void:
	# Season notifications now handled by EventFeedManager with priority-aware toasts
	pass

# --- Tutorial ---

func _start_tutorial() -> void:
	if tutorial_system and tutorial_system.is_active:
		return
	tutorial_system = TutorialSystem.new()
	tutorial_system.name = "TutorialSystem"
	add_child(tutorial_system)
	tutorial_system.start_tutorial()
	var overlay = tutorial_system.get_overlay()
	if overlay:
		$UI.add_child(overlay)
	tutorial_system.tutorial_completed.connect(_on_tutorial_completed)

func _on_tutorial_completed() -> void:
	EventBus.notify("Tutorial complete! Press F1 for hotkeys anytime.", "success")

# --- Notification Toast ---

func _setup_notification_toast() -> void:
	var toast = NotificationToast.new()
	toast.name = "NotificationToast"
	$UI.add_child(toast)

# --- Event Feed ---

func _setup_event_feed() -> void:
	event_feed_panel = EventFeedPanel.new()
	event_feed_panel.name = "EventFeedPanel"
	event_feed_panel.close_requested.connect(_toggle_event_feed)
	event_feed_panel.navigate_to_hole.connect(_navigate_to_hole)
	event_feed_panel.navigate_to_position.connect(_navigate_to_position)
	event_feed_panel.navigate_to_golfer.connect(_navigate_to_golfer_position)
	$UI/HUD.add_child(event_feed_panel)

	# Live-append new events when feed is open
	EventFeedManager.event_added.connect(func(entry):
		if event_feed_panel and event_feed_panel.visible:
			event_feed_panel.append_event(entry)
	)

	# Surface the unread badge on the Club tab's Feed card (and, through the
	# toolbar, on the Club tab and Manage section buttons behind it)
	EventFeedManager.unread_count_changed.connect(_update_feed_unread)
	_update_feed_unread(EventFeedManager.unread_count)

func _toggle_event_feed() -> void:
	# Event feed is a side panel, not a CenteredPanel, so handle independently
	if event_feed_panel:
		event_feed_panel.toggle()

func _update_feed_unread(count: int) -> void:
	# The toolbar owns the Feed card; it mirrors the count onto the Club tab
	# and Manage section badges so unread events show from anywhere.
	if terrain_toolbar:
		terrain_toolbar.set_feed_unread_count(count)

func _navigate_to_hole(hole_number: int) -> void:
	if not GameManager.current_course:
		return
	for hole in GameManager.current_course.holes:
		if hole.hole_number == hole_number:
			var tee_world = terrain_grid.grid_to_screen_center(hole.tee_position)
			var green_world = terrain_grid.grid_to_screen_center(hole.green_position)
			var center = (tee_world + green_world) / 2
			camera.focus_on(center, false)
			break

func _navigate_to_position(pos: Vector2i) -> void:
	var world_pos = terrain_grid.grid_to_screen_center(pos)
	camera.focus_on(world_pos, false)

func _navigate_to_golfer_position(golfer_id: int) -> void:
	var golfers_node = $Entities/Golfers
	if not golfers_node:
		return
	for child in golfers_node.get_children():
		if child is Golfer and child.golfer_id == golfer_id:
			camera.focus_on(child.global_position, false)
			return

# --- Course Rating Overlay ---

func _setup_course_rating_overlay() -> void:
	"""Course Review now lives in the Course Map's Aura mode.

	The old overlay is kept as a hidden compatibility node so saves and tests
	that reference it do not break, but all visible review UI is in
	CourseMapAuraPanel. The star rating in the HUD now opens the map on Aura.
	"""
	# Keep a hidden overlay for backward compatibility (tests may check existence)
	if course_rating_overlay == null:
		course_rating_overlay = CourseRatingOverlay.new()
		course_rating_overlay.name = "CourseRatingOverlay"
		course_rating_overlay.visible = false
		$UI/HUD.add_child(course_rating_overlay)
		course_rating_overlay.hide()
	# Update the status column whenever course rating changes (end of day, etc.)
	if not EventBus.course_rating_changed.is_connected(_on_course_rating_changed_for_hud):
		EventBus.course_rating_changed.connect(_on_course_rating_changed_for_hud)
	# Push initial rating to the status column (deferred so GameManager is ready)
	_update_status_rating.call_deferred()

func _on_course_rating_changed_for_hud(rating: Dictionary) -> void:
	if hud_status_column:
		hud_status_column.update_rating(rating.get("overall", 3.0))

func _on_aura_rating_updated(stars: float) -> void:
	if hud_status_column:
		hud_status_column.update_rating(stars)

var _rating_retry_count: int = 0

func _update_status_rating() -> void:
	if not GameManager.current_course or not GameManager.terrain_grid or not hud_status_column:
		if _rating_retry_count < 3:
			_rating_retry_count += 1
			get_tree().create_timer(0.5).timeout.connect(_update_status_rating)
		return
	_rating_retry_count = 0
	var rating := CourseRatingSystem.calculate_rating(
		GameManager.terrain_grid,
		GameManager.current_course,
		GameManager.daily_stats,
		GameManager.green_fee,
		GameManager.reputation,
		GameManager.entity_layer
	)
	var stars: float = rating.get("overall", 3.0)
	hud_status_column.update_rating(stars)

func _toggle_course_rating_panel() -> void:
	# Legacy entry point: Review now lives in Course Map Aura mode
	_open_course_map_aura()

# --- Floating Transaction Text ---

func _setup_floating_text() -> void:
	"""Connect money changes to spawn floating +$/-$ text on transactions."""
	EventBus.transaction_completed.connect(_on_transaction_for_floating_text)

func _on_transaction_for_floating_text(_description: String, amount: int) -> void:
	"""Spawn floating text at a relevant screen position for transactions."""
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return
	if abs(amount) < 1:
		return

	# Show floating text near the money display in the top HUD
	# Convert HUD position to world-space so it renders above terrain
	var vp_size := get_viewport().get_visible_rect().size
	var screen_pos := Vector2(120, 28)  # Near top-left money display
	# For world-space, convert screen coords to camera-relative position
	var world_pos := camera.global_position + (screen_pos - vp_size / 2) / camera.zoom
	FloatingText.create_at(self, world_pos, amount)

# --- Autosave Indicator ---

func _setup_autosave_indicator() -> void:
	var indicator = AutosaveIndicator.new()
	indicator.name = "AutosaveIndicator"
	$UI.add_child(indicator)

# --- Pause Menu ---

func _toggle_pause_menu() -> void:
	"""Toggle the pause menu overlay."""
	if pause_menu:
		_close_pause_menu()
	else:
		_show_pause_menu()

func _show_pause_menu() -> void:
	"""Show the pause menu and pause the game."""
	if pause_menu:
		return
	# Close any active panel
	if _active_panel and _active_panel.visible:
		_active_panel.hide()
		_active_panel = null

	# Remember if the game was already paused before this pause session
	# (e.g. end-of-day summary, pause button) so resume can restore it.
	# The flag persists while the session bounces between the menu and its
	# sub-panels (Save/Load, Settings), so it is only captured once.
	if not _pause_session_active:
		_was_paused_before_pause_menu = GameManager.is_paused
		_pause_session_active = true
	GameManager.is_paused = true

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.camera = camera
	pause_menu.resume_requested.connect(_on_pause_resume)
	pause_menu.save_requested.connect(_on_pause_save)
	pause_menu.load_requested.connect(_on_pause_load)
	pause_menu.settings_requested.connect(_on_pause_settings)
	pause_menu.quit_to_menu_requested.connect(_on_pause_quit_to_menu)
	pause_menu.quit_to_desktop_requested.connect(_on_pause_quit_to_desktop)
	$UI/HUD.add_child(pause_menu)

func _hide_pause_menu() -> void:
	"""Hide the pause menu overlay without changing the game's pause state."""
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null

func _close_pause_menu() -> void:
	"""Close the pause menu and restore prior pause state."""
	_hide_pause_menu()
	_pause_session_active = false
	# Only unpause if the game wasn't already paused before we opened the menu
	if not _was_paused_before_pause_menu:
		GameManager.is_paused = false

func _on_pause_resume() -> void:
	_close_pause_menu()

func _on_pause_save() -> void:
	# Keep the game paused while the save/load panel is open
	_hide_pause_menu()
	_show_save_load_panel(true, SaveLoadPanel.ScreenMode.SAVE)

func _on_pause_load() -> void:
	# Keep the game paused while the save/load panel is open
	_hide_pause_menu()
	_show_save_load_panel(true, SaveLoadPanel.ScreenMode.LOAD)

func _on_pause_settings() -> void:
	# Keep the game paused while the settings menu is open
	_hide_pause_menu()
	_show_settings_menu()

func _show_settings_menu() -> void:
	"""Show the settings menu overlay (the pause session's Settings)."""
	var settings = SettingsMenu.new()
	settings.name = "SettingsMenu"
	settings.origin = SettingsMenu.Origin.PAUSE_MENU
	_settings_opened_from_main_menu = false
	settings.camera = camera
	settings.close_requested.connect(func():
		# Re-show pause menu when settings closes (if not from main menu)
		if GameManager.current_mode != GameManager.GameMode.MAIN_MENU:
			_show_pause_menu()
	)
	settings.results_requested.connect(_show_benchmark_results)
	settings.tour_requested.connect(start_course_benchmark)
	settings.data_deleted.connect(_on_settings_data_deleted)
	# Deleting the saved courses during a pause session leaves the course with
	# nowhere to autosave, so the settings screen asks to close it.
	settings.quit_to_menu_requested.connect(_return_to_title_after_data_deleted)
	$UI/HUD.add_child(settings)


## The Settings screen's Data page changed the files this scene was built from.
## The title screen's Continue card is the one that reads them; rebuild it in
## place so it never offers a save that was just deleted.
func _on_settings_data_deleted(_groups: Array[String]) -> void:
	if is_instance_valid(main_menu):
		main_menu.refresh()


## The Data page deleted the saved courses during a pause session: the course
## has nowhere left to autosave, so end the pause session and go back to the
## title screen. The deletion itself already asked before it happened.
func _return_to_title_after_data_deleted() -> void:
	_pause_session_active = false
	GameManager.is_paused = false
	_hide_pause_menu()
	_on_quit_to_menu()


## Run the course benchmark tour - the game's only benchmark - from Main
## Menu Settings only. The menus come down, the tour prepares its own
## throwaway course (timed and sampled as part of the benchmark), builds
## every seeded test course of the suite on it one at a time (themes, hole
## counts, fields of golfers, camera moves, terrain editing and game speeds
## per CourseBenchmarkScenarios), takes the course down, and the Benchmark
## Results open over the Main Menu on the report. Refuses - with a notice
## and every menu left standing - when Settings was not accessed from the
## Main Menu. The menus ask for the full suite (`SUITE_FULL`); the suite id
## is passed through so a harness can drive a shorter list of courses.
func start_course_benchmark(suite_id: String) -> bool:
	if _benchmark_tour_active or course_benchmark_tour == null \
			or course_benchmark_tour.is_running():
		return false
	if not _settings_opened_from_main_menu:
		EventBus.notify("Benchmarks run from the Main Menu - open Settings there to measure this device.", "info")
		return false
	if tournament_manager and tournament_manager.is_tournament_in_progress():
		EventBus.notify("The benchmark tour cannot run during a tournament.", "error")
		return false
	if is_instance_valid(player_round) and player_round.active:
		EventBus.notify("Finish the owner's round first - the benchmark tour needs the course to itself.", "error")
		return false
	_cancel_inspect_mode()
	is_painting = false
	for panel_name in ["BenchmarkResultsScreen", "SettingsMenu"]:
		var panel := $UI/HUD.get_node_or_null(panel_name)
		if panel:
			panel.queue_free()
	_close_pause_menu()
	_hide_main_menu()
	_set_gameplay_ui_visible(true)
	if not course_benchmark_tour.start(suite_id):
		EventBus.notify("The benchmark tour could not start.", "error")
		_show_main_menu()
		return false
	_benchmark_tour_active = true
	return true

func _on_course_benchmark_completed(_result: Dictionary) -> void:
	_benchmark_tour_active = false
	_return_from_benchmark_tour()
	_show_benchmark_results()

func _on_course_benchmark_cancelled(result: Dictionary) -> void:
	_benchmark_tour_active = false
	_return_from_benchmark_tour()
	var prepared: bool = bool(result.get("tour", {}).get("prepare", {}).get("prepared", false))
	EventBus.notify("Benchmark tour cancelled - the benchmark course was taken down; nothing was saved." if prepared \
		else "Benchmark tour cancelled - your course was restored exactly as it was.", "info")

## A tour started from the Main Menu hands the title screen back: the tour
## has already torn its throwaway course down and returned the game to
## menu mode, so the Main Menu comes back up over the bare view (and under
## the results screen a finished tour is about to open).
func _return_from_benchmark_tour() -> void:
	if _settings_opened_from_main_menu \
			and GameManager.current_mode == GameManager.GameMode.MAIN_MENU \
			and main_menu == null:
		_show_main_menu()

## The Benchmark Results screen opens over the settings menu, so closing it
## drops the player back where they were, mid-settings.
func _show_benchmark_results() -> void:
	var hud = $UI/HUD
	var existing := hud.get_node_or_null("BenchmarkResultsScreen")
	if existing:
		existing.move_to_front()
		return
	var screen := BenchmarkResultsScreen.new()
	screen.name = "BenchmarkResultsScreen"
	# Benchmarks only run when Settings was accessed from the Main Menu;
	# the tour prepares its own course there, so it is the headline run.
	# Reached any other way the screen still shows every past report -
	# it simply runs nothing.
	screen.benchmarks_allowed = _settings_opened_from_main_menu
	screen.tour_available = _settings_opened_from_main_menu
	screen.tour_requested.connect(start_course_benchmark)
	screen.back_requested.connect(func():
		if is_instance_valid(screen):
			screen.queue_free()
	)
	hud.add_child(screen)
	screen.move_to_front()

func _on_pause_quit_to_menu() -> void:
	_close_pause_menu()
	_show_quit_confirm("Unsaved progress will be lost.\nReturn to main menu?", "Quit to Menu", _on_quit_to_menu)

func _on_pause_quit_to_desktop() -> void:
	_close_pause_menu()
	_show_quit_confirm("Unsaved progress will be lost.\nQuit to desktop?", "Quit", func(): get_tree().quit())

func _show_quit_confirm(message: String, confirm_text: String, on_confirm: Callable) -> void:
	"""Show a confirmation dialog for a destructive action."""
	var dialog = ConfirmDialog.new(message, confirm_text, "Cancel")
	dialog.name = "QuitConfirmDialog"
	dialog.confirmed.connect(on_confirm)
	dialog.cancelled.connect(func():
		# Re-show pause menu if the user cancels
		_show_pause_menu()
	)
	$UI/HUD.add_child(dialog)

# --- Game Over ---

func _show_game_over() -> void:
	"""Show the bankruptcy game over screen."""
	_game_over_shown = true
	GameManager.is_paused = true

	# Close any active panels
	if _active_panel and _active_panel.visible:
		_active_panel.hide()
		_active_panel = null
	if pause_menu:
		_close_pause_menu()

	var game_over = GameOverPanel.new()
	game_over.name = "GameOverPanel"
	game_over.retry_requested.connect(func():
		game_over.queue_free()
		_game_over_shown = false
		_on_quit_to_menu()
	)
	game_over.load_requested.connect(func():
		game_over.queue_free()
		_game_over_shown = false
		GameManager.is_paused = false
		_show_save_load_panel()
	)
	game_over.quit_to_menu_requested.connect(func():
		game_over.queue_free()
		_game_over_shown = false
		_on_quit_to_menu()
	)
	$UI/HUD.add_child(game_over)

# --- Shot Heatmap ---

func _setup_shot_heatmap() -> void:
	shot_heatmap_tracker = ShotHeatmapTracker.new()
	shot_heatmap_tracker.name = "ShotHeatmapTracker"
	add_child(shot_heatmap_tracker)
	shot_heatmap_tracker.initialize()
	GameManager.shot_heatmap_tracker = shot_heatmap_tracker
	terrain_grid.setup_shot_heatmap_overlay(shot_heatmap_tracker)

# --- Course Aura ---

## The aura listens to every golfer comment and remembers where it was made.
## It is a plain node: nothing on the course changes because of it, and the
## Course Map's Course Aura mode is the one screen that reads it.
func _setup_course_aura() -> void:
	var aura := CourseAura.new()
	aura.name = "CourseAura"
	add_child(aura)
	GameManager.course_aura = aura

# --- Responsive Layout (desktop / tablet / mobile) ---

## Wire the responsive camera scale and the touch gesture translator, and
## reflow the anchored HUD pieces whenever the window resizes or rotates.
func _setup_responsive_ui() -> void:
	camera.apply_world_scale(Screen.world_scale)
	TouchInput.camera = camera
	TouchInput.paint_mode_provider = _touch_is_paint_mode
	if not Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.connect(_on_screen_changed)
	_apply_responsive_layout()

func _touch_is_paint_mode() -> bool:
	return is_painting or _has_active_tool()

func _on_screen_changed(_size: Vector2, _world_scale: float) -> void:
	camera.apply_world_scale(Screen.world_scale)
	_apply_responsive_layout()

## Re-derive the size-sensitive HUD layout from the current window size.
func _apply_responsive_layout() -> void:
	var bar_h := Screen.bottom_bar_height()
	if bottom_bar:
		bottom_bar.offset_top = -bar_h
	if hud_status_column:
		hud_status_column.apply_screen()
	if course_location_banner:
		course_location_banner.apply_screen()
	# The banner changes height between desktop and compact, so re-dock the
	# scores cards underneath it.
	_dock_scores_below_banner()
	if left_controls:
		left_controls.apply_screen()
	if terrain_toolbar:
		terrain_toolbar.apply_screen()
	if mini_map:
		mini_map.apply_screen()
		_position_mini_map()

# --- Shot Trails ---

func _setup_shot_trails() -> void:
	EventBus.ball_shot_landed_precise.connect(_on_shot_for_trail)
	EventBus.ball_putt_landed_precise.connect(_on_putt_for_trail)

func _on_shot_for_trail(_golfer_id: int, from_screen: Vector2, to_screen: Vector2,
		_distance_yards: int, carry_screen: Vector2) -> void:
	if not _is_screen_visible(from_screen) and not _is_screen_visible(to_screen):
		return
	var landing_terrain = terrain_grid.get_tile(terrain_grid.screen_to_grid(to_screen))
	ShotTrail.create($Entities, from_screen, to_screen, carry_screen, false, landing_terrain)

func _on_putt_for_trail(_golfer_id: int, from_screen: Vector2, to_screen: Vector2,
		_distance_yards: int) -> void:
	if not _is_screen_visible(from_screen) and not _is_screen_visible(to_screen):
		return
	var terrain_types_ref = preload("res://scripts/terrain/terrain_types.gd")
	ShotTrail.create($Entities, from_screen, to_screen, to_screen, true, terrain_types_ref.Type.GREEN)

func _is_screen_visible(world_pos: Vector2) -> bool:
	var vp_size = get_viewport().get_visible_rect().size
	var cam_pos = camera.global_position
	var cam_zoom = camera.zoom
	var half_vp = vp_size / (2.0 * cam_zoom)
	var margin = 100.0
	return abs(world_pos.x - cam_pos.x) < half_vp.x + margin and abs(world_pos.y - cam_pos.y) < half_vp.y + margin

func _exit_tree() -> void:
	"""Disconnect all signals to prevent memory leaks on scene unload."""
	# EventBus signal cleanup
	if EventBus.money_changed.is_connected(_on_money_changed):
		EventBus.money_changed.disconnect(_on_money_changed)
	if EventBus.day_changed.is_connected(_on_day_changed):
		EventBus.day_changed.disconnect(_on_day_changed)
	if EventBus.hole_created.is_connected(_on_hole_created):
		EventBus.hole_created.disconnect(_on_hole_created)
	if EventBus.hole_deleted.is_connected(_on_hole_deleted):
		EventBus.hole_deleted.disconnect(_on_hole_deleted)
	if EventBus.hole_toggled.is_connected(_on_hole_toggled):
		EventBus.hole_toggled.disconnect(_on_hole_toggled)
	if EventBus.hole_updated.is_connected(_refresh_hole_button):
		EventBus.hole_updated.disconnect(_refresh_hole_button)
	if EventBus.end_of_day.is_connected(_on_end_of_day):
		EventBus.end_of_day.disconnect(_on_end_of_day)
	if EventBus.year_ended.is_connected(_on_year_ended):
		EventBus.year_ended.disconnect(_on_year_ended)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if EventBus.new_game_started.is_connected(_on_new_game_started):
		EventBus.new_game_started.disconnect(_on_new_game_started)
