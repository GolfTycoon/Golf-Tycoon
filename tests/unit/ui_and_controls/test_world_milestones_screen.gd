extends GameTest
## The World Milestones screen: the company goal book's arrangement per
## window shape, the company record that fronts it, and the pixel look it
## shares with the World Map - its MenuBackdrop background, Pixelify Sans
## and the notched nine-patch frames.
##
## The screen is built from code, so these walk the built tree and check
## what it actually draws.

const TITLE_FONT_PATH := "res://assets/fonts/PixelifySans-Bold.ttf"
const SUBTITLE_FONT_PATH := "res://assets/fonts/PixelifySans-SemiBold.ttf"
const BODY_FONT_PATH := "res://assets/fonts/PixelifySans-Regular.ttf"
const DESIGN_WINDOW := Vector2i(1600, 1000)

var manager: MilestoneManager
var _window_before := Vector2i.ZERO

func before_each() -> void:
	super()
	_window_before = get_window().size
	GameManager.current_day = 42
	GameManager.reputation = 30.0
	AchievementStore.settings_path = "user://test_world_milestones_store.cfg"
	AchievementStore.clear()
	manager = autofree(MilestoneManager.new())
	manager._init_state()
	WorldMap.locations = {
		"monterey": {"owned": true, "unlocked": [], "price": 0, "seed": 1},
		"florida": {"owned": true, "unlocked": [], "price": 0, "seed": 2},
		"rocky_mountains": {"owned": false, "unlocked": [], "price": 52000, "seed": 3},
	}
	WorldMap.active_location_id = "monterey"

func after_each() -> void:
	# Let the rebuilds' queued frees land before GUT counts orphans.
	await process_frames(1)
	get_window().size = _window_before
	AchievementStore.clear()
	manager = null
	super()

func _screen(size: Vector2i) -> WorldMilestonesScreen:
	get_window().size = size
	await process_frames(2)
	var screen := WorldMilestonesScreen.new()
	screen.set_milestone_manager(manager)
	add_child_autofree(screen)
	return screen

func _world_def(id: String) -> MilestoneSystem.Milestone:
	for m in manager.world_milestones:
		if m.id == id:
			return m
	return null

func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

func _labels_text(root: Node) -> String:
	var text := ""
	for child in root.get_children():
		if child is Label:
			text += child.text + "\n"
		text += _labels_text(child)
	return text

# ---------------------------------------------------------------------------
# The World Map's look
# ---------------------------------------------------------------------------

func test_the_screen_sits_on_the_world_map_background() -> void:
	var screen: WorldMilestonesScreen = await _screen(DESIGN_WINDOW)
	var backdrop := screen.find_child("Backdrop", true, false)
	assert_not_null(backdrop, "the backdrop is built")
	assert_true(backdrop is MenuBackdrop,
		"it is the World Map's shared background artwork")

func test_every_visible_word_uses_the_title_screens_pixelify_faces() -> void:
	var screen: WorldMilestonesScreen = await _screen(DESIGN_WINDOW)
	var allowed := [TITLE_FONT_PATH, SUBTITLE_FONT_PATH, BODY_FONT_PATH]
	var unstyled: Array[String] = []
	for label in _nodes_of_class(screen, "Label"):
		var path := (label as Label).get_theme_font("font").resource_path
		if not path in allowed:
			unstyled.append("%s -> %s" % [label.name, path])
	for button in _nodes_of_class(screen, "Button"):
		var control := button as Button
		if control.text.is_empty():
			continue
		var path := control.get_theme_font("font").resource_path
		if not path in allowed:
			unstyled.append("%s -> %s" % [control.name, path])
	assert_eq(unstyled, [], "every label and button uses Pixelify Sans")
	var title := screen.find_child("Title", true, false) as Label
	assert_not_null(title, "the screen keeps its title")
	if title:
		assert_eq(title.text, "World Milestones")
		assert_eq(title.get_theme_font("font").resource_path, TITLE_FONT_PATH, "the heading is bold")

# ---------------------------------------------------------------------------
# Arrangements
# ---------------------------------------------------------------------------

func test_desktop_shows_the_company_record_beside_the_ledger() -> void:
	var screen: WorldMilestonesScreen = await _screen(DESIGN_WINDOW)
	assert_not_null(screen.find_child("CompanyRecord", true, false), "the company record is up")
	assert_not_null(screen.find_child("CompanyStats", true, false), "with the stats behind the goals")
	assert_not_null(screen.find_child("WorldProgressBar", true, false), "and the world tally")
	assert_not_null(screen.find_child("WorldLedger", true, false), "the goal ledger is up")
	assert_not_null(screen.find_child("TrackSwitch", true, false),
		"the track switch keeps the other goal screens one tap away")

func test_smaller_windows_fold_the_record_into_a_summary_strip() -> void:
	for size in [Vector2i(1024, 768), Vector2i(768, 1024), Vector2i(844, 390), Vector2i(390, 844)]:
		var screen: WorldMilestonesScreen = await _screen(size)
		assert_null(screen.find_child("CompanyRecord", true, false),
			"%s drops the tall rail" % size)
		assert_not_null(screen.find_child("CompanySummary", true, false),
			"and keeps the record as one strip")
		assert_not_null(screen.find_child("WorldLedger", true, false))

# ---------------------------------------------------------------------------
# The world track
# ---------------------------------------------------------------------------

func test_the_ledger_lists_the_companys_goals_with_their_days() -> void:
	manager._complete_milestone(_world_def("world_own_2"))
	var screen: WorldMilestonesScreen = await _screen(DESIGN_WINDOW)
	var ledger := screen.find_child("WorldLedger", true, false)
	var text := _labels_text(ledger)
	assert_string_contains(text, "Second Site", "the world milestone is listed")
	assert_string_contains(text, "Day 42", "its completion day is stamped on it")
	assert_string_contains(text, "In progress", "unfinished milestones say so")
	assert_string_contains(text, "Chain Reaction", "every company goal is on the page")

func test_the_company_record_counts_what_the_goals_are_earned_from() -> void:
	manager._complete_milestone(_world_def("world_own_2"))
	var screen: WorldMilestonesScreen = await _screen(DESIGN_WINDOW)
	var stats := screen.find_child("CompanyStats", true, false)
	var text := _labels_text(stats)
	assert_string_contains(text, "Course locations\n2", "the portfolio is counted")
	assert_string_contains(text, "Reputation\n30", "and the company's standing")
	assert_string_contains(text, "Days in business\n42", "and the days it has run")

func test_the_summary_strip_keeps_the_tally_and_the_key_numbers() -> void:
	var screen: WorldMilestonesScreen = await _screen(Vector2i(390, 844))
	var strip := screen.find_child("CompanySummary", true, false)
	assert_not_null(strip)
	var text := _labels_text(strip)
	assert_string_contains(text, "2 locations", "the portfolio shows")
	assert_string_contains(text, "0 holes", "the company's holes show")

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func test_back_and_the_track_switch_ask_the_host_to_move() -> void:
	var screen: WorldMilestonesScreen = await _screen(DESIGN_WINDOW)
	watch_signals(screen)
	var back := screen.find_child("BackButton", true, false) as Button
	assert_not_null(back)
	if back:
		back.pressed.emit()
		assert_signal_emitted(screen, "back_requested")
	var course := screen.find_child("Track_course", true, false) as Button
	assert_not_null(course, "the Course track is one tap away")
	if course:
		course.pressed.emit()
		assert_signal_emitted_with_parameters(screen, "track_requested",
			[MenuScreenKit.GoalTrack.COURSE])
	var honours := screen.find_child("Track_achievements", true, false) as Button
	assert_not_null(honours, "and so is the trophy room")
	if honours:
		honours.pressed.emit()
		assert_signal_emitted_with_parameters(screen, "track_requested",
			[MenuScreenKit.GoalTrack.ACHIEVEMENTS])
