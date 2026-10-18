extends GameTest
## The Achievements screen: the trophy room's arrangement per window shape,
## the honours that stay unlocked between saves, and the pixel look it
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
var _old_store_path := ""

func before_each() -> void:
	super()
	_window_before = get_window().size
	GameManager.current_day = 5
	_old_store_path = AchievementStore.settings_path
	AchievementStore.settings_path = "user://test_achievements_screen_store.cfg"
	AchievementStore.clear()
	manager = autofree(MilestoneManager.new())
	manager._init_state()

func after_each() -> void:
	# Let the rebuilds' queued frees land before GUT counts orphans.
	await process_frames(1)
	get_window().size = _window_before
	AchievementStore.clear()
	AchievementStore.settings_path = _old_store_path
	manager = null
	super()

func _screen(size: Vector2i, track_navigation_enabled: bool = true) -> AchievementsScreen:
	get_window().size = size
	await process_frames(2)
	var screen := AchievementsScreen.new()
	screen.set_milestone_manager(manager)
	screen.track_navigation_enabled = track_navigation_enabled
	add_child_autofree(screen)
	return screen

func _achievement_def(id: String) -> MilestoneSystem.Milestone:
	for m in manager.achievements:
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
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
	var backdrop := screen.find_child("Backdrop", true, false)
	assert_not_null(backdrop, "the backdrop is built")
	assert_true(backdrop is MenuBackdrop,
		"it is the World Map's shared background artwork")

func test_every_visible_word_uses_the_title_screens_pixelify_faces() -> void:
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
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
		assert_eq(title.text, "Achievements")
		assert_eq(title.get_theme_font("font").resource_path, TITLE_FONT_PATH, "the heading is bold")

# ---------------------------------------------------------------------------
# Arrangements
# ---------------------------------------------------------------------------

func test_desktop_shows_the_trophy_case_beside_the_honour_grid() -> void:
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
	assert_not_null(screen.find_child("TrophyCase", true, false), "the trophy-case rail is up")
	assert_not_null(screen.find_child("FeaturedHonor", true, false), "the newest honour is featured")
	assert_not_null(screen.find_child("CareerStats", true, false), "the career record is up")
	assert_not_null(screen.find_child("HonorGrid", true, false), "the honour grid is up")

func test_tablet_keeps_the_case_as_a_strip_above_the_grid() -> void:
	var screen: AchievementsScreen = await _screen(Vector2i(1024, 768))
	assert_not_null(screen.find_child("CaseStrip", true, false), "the case shares a wide strip")
	assert_not_null(screen.find_child("FeaturedHonor", true, false))
	assert_not_null(screen.find_child("CareerStats", true, false))
	assert_not_null(screen.find_child("HonorGrid", true, false))

func test_phone_portrait_folds_the_career_record_into_one_summary_line() -> void:
	var screen: AchievementsScreen = await _screen(Vector2i(390, 844))
	assert_not_null(screen.find_child("CareerSummary", true, false),
		"the record becomes one quiet line")
	assert_null(screen.find_child("CareerStats", true, false),
		"so it never stands taller than the honours")
	assert_not_null(screen.find_child("HonorGrid", true, false))

func test_smaller_windows_still_carry_the_filter_switch() -> void:
	for size in [Vector2i(768, 1024), Vector2i(844, 390), Vector2i(390, 844)]:
		var screen: AchievementsScreen = await _screen(size)
		assert_not_null(screen.find_child("FilterSwitch", true, false),
			"%s can still filter All / Unlocked / Locked" % size)

func test_title_menu_entry_hides_track_navigation_at_every_size() -> void:
	for size in [DESIGN_WINDOW, Vector2i(1024, 768), Vector2i(768, 1024),
			Vector2i(844, 390), Vector2i(390, 844)]:
		var screen: AchievementsScreen = await _screen(size, false)
		assert_null(screen.find_child("TrackSwitch", true, false),
			"%s hides the whole track switch" % size)
		for track_button in ["Track_course", "Track_world", "Track_achievements"]:
			assert_null(screen.find_child(track_button, true, false),
				"%s does not show %s" % [size, track_button])
		assert_not_null(screen.find_child("UnlockedStat", true, false),
			"%s keeps the unlocked tally" % size)

# ---------------------------------------------------------------------------
# The career honours
# ---------------------------------------------------------------------------

func test_locked_honours_keep_their_title_but_hide_what_they_take() -> void:
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
	var card := screen.find_child("Honor_ach_club_classic", true, false)
	assert_not_null(card, "every honour has a card, locked or not")
	var text := _labels_text(card)
	assert_string_contains(text, "Club Classic", "the title stands")
	assert_string_contains(text, "LOCKED", "the card is stamped LOCKED")
	assert_false(text.contains("Complete 100 rounds of golf"),
		"what it takes stays hidden")
	assert_string_contains(text, "100", "but the career progress shows through")

func test_an_unlocked_honour_opens_up_with_its_day() -> void:
	manager._bump_counter("rounds", 1)
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
	var card := screen.find_child("Honor_ach_opening_day", true, false)
	assert_not_null(card)
	var text := _labels_text(card)
	assert_string_contains(text, "Opening Day")
	assert_string_contains(text, "Complete your first round of golf",
		"the honour reveals what it took")
	assert_string_contains(text, "Day 5", "and when it landed")

func test_the_filter_switch_shows_only_the_shelf_or_only_the_locks() -> void:
	manager._bump_counter("rounds", 1)
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
	var unlocked_filter := screen.find_child("Filter_Unlocked", true, false) as Button
	assert_not_null(unlocked_filter)
	if unlocked_filter:
		unlocked_filter.pressed.emit()
	assert_not_null(screen.find_child("Honor_ach_opening_day", true, false),
		"the unlocked honour stays")
	assert_null(screen.find_child("Honor_ach_club_classic", true, false),
		"locked honours stand down")

	var locked_filter := screen.find_child("Filter_Locked", true, false) as Button
	if locked_filter:
		locked_filter.pressed.emit()
	assert_null(screen.find_child("Honor_ach_opening_day", true, false),
		"now the shelf stands down")
	assert_not_null(screen.find_child("Honor_ach_club_classic", true, false),
		"and only the locks show")

func test_the_featured_panel_prefers_the_newest_honour() -> void:
	manager._bump_counter("holes_built", 1)
	manager._bump_counter("rounds", 1)
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
	var featured := screen.find_child("FeaturedHonor", true, false)
	var text := _labels_text(featured)
	assert_string_contains(text, "Opening Day",
		"the honour from the higher day is the newest")
	assert_string_contains(text, "Unlocked on day 5")

func test_the_career_record_counts_what_the_honours_are_earned_from() -> void:
	manager._bump_counter("rounds", 40)
	manager._bump_counter("revenue", 250000)
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
	var stats := screen.find_child("CareerStats", true, false)
	var text := _labels_text(stats)
	assert_string_contains(text, "40", "rounds are counted")
	assert_string_contains(text, "$250K", "revenue is counted")

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func test_back_and_the_track_switch_ask_the_host_to_move() -> void:
	var screen: AchievementsScreen = await _screen(DESIGN_WINDOW)
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
	var world := screen.find_child("Track_world", true, false) as Button
	assert_not_null(world, "and so is the World track")
	if world:
		world.pressed.emit()
		assert_signal_emitted_with_parameters(screen, "track_requested",
			[MenuScreenKit.GoalTrack.WORLD])
