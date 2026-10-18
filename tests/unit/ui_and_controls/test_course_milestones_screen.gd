extends GameTest
## The Course Milestones screen: the per-location goal book's arrangement
## per window shape, the site picker and ledger it shows, and the pixel look
## it borrows from the World Map - its MenuBackdrop background, Pixelify
## Sans and the notched nine-patch frames.
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
	GameManager.current_day = 1
	AchievementStore.settings_path = "user://test_course_milestones_store.cfg"
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

func _screen(size: Vector2i) -> CourseMilestonesScreen:
	get_window().size = size
	await process_frames(2)
	var screen := CourseMilestonesScreen.new()
	screen.set_milestone_manager(manager)
	add_child_autofree(screen)
	return screen

func _location_def(id: String) -> MilestoneSystem.Milestone:
	for m in manager.location_milestones:
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
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	var backdrop := screen.find_child("Backdrop", true, false)
	assert_not_null(backdrop, "the backdrop is built")
	assert_true(backdrop is MenuBackdrop,
		"it is the World Map's shared background artwork")

func test_every_visible_word_uses_the_title_screens_pixelify_faces() -> void:
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
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
		assert_eq(title.text, "Course Milestones")
		assert_eq(title.get_theme_font("font").resource_path, TITLE_FONT_PATH, "the heading is bold")

# ---------------------------------------------------------------------------
# Arrangements
# ---------------------------------------------------------------------------

func test_desktop_shows_the_site_rail_the_dossier_and_the_ledger_at_once() -> void:
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	assert_not_null(screen.find_child("LocationRail", true, false), "the site picker is up")
	assert_not_null(screen.find_child("SiteDossier", true, false), "the site's dossier is up")
	assert_not_null(screen.find_child("LocationLedger", true, false), "the goal ledger is up")
	assert_not_null(screen.find_child("TrackSwitch", true, false),
		"the track switch keeps the other goal screens one tap away")

func test_tablet_and_phone_shelves_the_site_picker() -> void:
	for size in [Vector2i(1024, 768), Vector2i(768, 1024), Vector2i(844, 390), Vector2i(390, 844)]:
		var screen: CourseMilestonesScreen = await _screen(size)
		assert_not_null(screen.find_child("LocationShelf", true, false),
			"%s keeps the sites on a shelf" % size)
		assert_not_null(screen.find_child("SiteDossier", true, false),
			"and the site's dossier under it")
		assert_not_null(screen.find_child("LocationLedger", true, false))

func test_the_ledger_fills_wider_windows_with_more_columns() -> void:
	var wide: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	var wide_columns := wide.find_child("LedgerColumns", true, false)
	assert_not_null(wide_columns)
	if wide_columns:
		assert_eq(wide_columns.get_child_count(), 2, "desktop is a two-column ledger")
	var phone: CourseMilestonesScreen = await _screen(Vector2i(390, 844))
	var phone_columns := phone.find_child("LedgerColumns", true, false)
	assert_not_null(phone_columns)
	if phone_columns:
		assert_eq(phone_columns.get_child_count(), 1, "phone portrait is one column")

# ---------------------------------------------------------------------------
# The per-location track
# ---------------------------------------------------------------------------

func test_the_ledger_follows_the_selected_course_location() -> void:
	manager._complete_milestone(_location_def("loc_first_hole"))
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	var ledger := screen.find_child("LocationLedger", true, false)
	var text := _labels_text(ledger)
	assert_string_contains(text, "First Tee", "the earned milestone is listed")

	# Pick the other owned site from the chips: its ledger is a blank slate.
	var florida_chip := screen.find_child("Location_florida", true, false) as Button
	assert_not_null(florida_chip, "each owned site has a chip")
	if florida_chip:
		florida_chip.pressed.emit()
		ledger = screen.find_child("LocationLedger", true, false)
		text = _labels_text(ledger)
		assert_string_contains(text, "Front Three", "the other site lists its own goals")
		assert_false(text.contains("Day 1"), "and has earned nothing yet")

func test_completed_milestones_stay_visible_with_their_day() -> void:
	manager._complete_milestone(_location_def("loc_first_hole"))
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	var text := _labels_text(screen)
	assert_string_contains(text, "First Tee", "the milestone is listed")
	assert_string_contains(text, "Day 1", "its completion day is stamped on it")
	assert_string_contains(text, "In progress", "unfinished milestones say so")

func test_the_dossier_summarises_the_site_and_its_records() -> void:
	manager._complete_milestone(_location_def("loc_first_hole"))
	manager._location_entry("monterey").rounds = 4
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	var dossier := screen.find_child("SiteDossier", true, false)
	var text := _labels_text(dossier)
	assert_string_contains(text, "Monterey", "the dossier names the site")
	assert_string_contains(text, "1 / %d" % manager.get_location_total_count(),
		"and its tally")
	assert_string_contains(text, "4 rounds", "and the records behind the goals")

func test_only_owned_sites_offer_a_chip() -> void:
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	assert_not_null(screen.find_child("Location_monterey", true, false))
	assert_not_null(screen.find_child("Location_florida", true, false))
	assert_null(screen.find_child("Location_rocky_mountains", true, false),
		"unowned sites have no milestones to show")

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func test_back_and_the_track_switch_ask_the_host_to_move() -> void:
	var screen: CourseMilestonesScreen = await _screen(DESIGN_WINDOW)
	watch_signals(screen)
	var back := screen.find_child("BackButton", true, false) as Button
	assert_not_null(back)
	if back:
		back.pressed.emit()
		assert_signal_emitted(screen, "back_requested")
	var world := screen.find_child("Track_world", true, false) as Button
	assert_not_null(world, "the World track is one tap away")
	if world:
		world.pressed.emit()
		assert_signal_emitted_with_parameters(screen, "track_requested",
			[MenuScreenKit.GoalTrack.WORLD])
	var honours := screen.find_child("Track_achievements", true, false) as Button
	assert_not_null(honours, "and so is the trophy room")
	if honours:
		honours.pressed.emit()
		assert_signal_emitted_with_parameters(screen, "track_requested",
			[MenuScreenKit.GoalTrack.ACHIEVEMENTS])
