extends MainSceneTest
## The Start New Game screen, opened from the title screen, at phone through
## desktop window sizes: the arrangement StartNewGameScreen.layout_mode_for picks
## shows every option and both actions as big enough targets inside the window
## and apart, never cuts text short or scrolls sideways, keeps Choose Location in
## view, and does not scroll at all where it promises not to (WIDE, LANDSCAPE).
## Then real clicks and keys play it: the picks reach the summary and the course
## plan, survive the window being resized, and Esc and Choose Location leave it.

## 3 difficulties + 4 budgets + 5 hole counts + 3 features + the tutorial
## switch + random name + Back + Choose Location.
const BUTTON_COUNT := 19
const MIN_TARGET := 44.0
const SIZES := [
	[Vector2i(390, 844), StartNewGameScreen.Layout.PHONE, "phone portrait"],
	[Vector2i(360, 640), StartNewGameScreen.Layout.PHONE, "small phone"],
	[Vector2i(844, 390), StartNewGameScreen.Layout.LANDSCAPE, "rotated phone"],
	[Vector2i(640, 360), StartNewGameScreen.Layout.LANDSCAPE, "small rotated phone"],
	[Vector2i(1000, 620), StartNewGameScreen.Layout.LANDSCAPE, "squat window"],
	[Vector2i(768, 1024), StartNewGameScreen.Layout.TABLET, "tablet portrait"],
	[Vector2i(1024, 1366), StartNewGameScreen.Layout.TABLET, "large tablet portrait"],
	[Vector2i(1024, 768), StartNewGameScreen.Layout.WIDE, "tablet landscape"],
	[Vector2i(1000, 640), StartNewGameScreen.Layout.WIDE, "smallest wide window"],
	[Vector2i(1280, 720), StartNewGameScreen.Layout.WIDE, "720p desktop"],
	[Vector2i(1366, 657), StartNewGameScreen.Layout.WIDE, "laptop browser window"],
	[Vector2i(1600, 1000), StartNewGameScreen.Layout.WIDE, "desktop"],
	[Vector2i(2560, 1440), StartNewGameScreen.Layout.WIDE, "large desktop"],
]


func _screen() -> StartNewGameScreen:
	return main.get_node_or_null("UI/HUD/StartNewGameScreen") as StartNewGameScreen


## Resize, then wait out the screen's settle delay (a small resize within one
## arrangement rebuilds once the window stops changing) and the plan's draw-in.
func _resize(size: Vector2i) -> void:
	await set_window(size)
	await get_tree().create_timer(StartNewGameScreen.SETTLE_DELAY + 0.15).timeout
	await process_frames(3)


func _button_for(buttons: Array, value: int) -> Button:
	for button in buttons:
		if int(button.get_meta("value")) == value:
			return button
	return null


func _pressed_values(buttons: Array) -> Array:
	var values := []
	for button in buttons:
		if button.button_pressed:
			values.append(int(button.get_meta("value")))
	return values


func _describe(control: Control) -> String:
	if control is Button and control.has_meta("value"):
		return "%s(%s)" % [control.get_parent().name, control.get_meta("value")]
	return str(control.name)


## Every visible label whose text is cut to fewer lines than it needs, or a
## one-line label whose text is wider than the label.
func _cut_text(root: Node) -> Array:
	var cut: Array = []
	for node in nodes_of_class(root, "Label"):
		var label: Label = node
		if not label.is_visible_in_tree() or label.text.is_empty():
			continue
		if label.get_visible_line_count() < label.get_line_count():
			cut.append("'%s' %d/%d lines" % [label.text.left(30), label.get_visible_line_count(), label.get_line_count()])
		elif label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var text := label.text.to_upper() if label.uppercase else label.text
			var width := label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.get_theme_font_size("font_size")).x
			if width > label.size.x + 1.0:
				cut.append("'%s' %.0f > %.0f px" % [text.left(30), width, label.size.x])
	return cut


func _assert_layout(tag: String, size: Vector2i, layout: int) -> void:
	var screen := _screen()
	var view := Rect2(Vector2.ZERO, Vector2(size))
	assert_eq(screen._layout_mode, layout, "%s: %s gets its arrangement" % [tag, size])
	var buttons := nodes_of_class(screen, "Button").filter(func(button: Button) -> bool: return button.is_visible_in_tree())
	assert_eq(buttons.size(), BUTTON_COUNT, "%s: every option and action is a button" % tag)
	assert_true(screen._company_input != null and screen._company_input.is_visible_in_tree(),
		"%s: the company name field is shown" % tag)
	assert_true(screen._difficulty_buttons.size() == 3 and screen._money_buttons.size() == 4 \
		and screen._hole_buttons.size() == 5 and screen._feature_boxes.size() == 3,
		"%s: three difficulties, four budgets, five hole counts and three features" % tag)
	assert_true(screen._tutorial_card != null and screen._tutorial_card.button.is_visible_in_tree(),
		"%s: the tutorial switch is shown" % tag)
	# Wide and landscape keep it in the title bar; the scrolling ones give it a section.
	var in_title_bar := layout == StartNewGameScreen.Layout.WIDE or layout == StartNewGameScreen.Layout.LANDSCAPE
	assert_eq(screen._tutorial_card.cell.get_parent().name, "Header" if in_title_bar else "TutorialBlock",
		"%s: the tutorial switch sits in the title bar or its own section" % tag)

	# Scrolling arrangements only promise the width; the rest sit wholly inside.
	var scrolling := layout == StartNewGameScreen.Layout.PHONE or layout == StartNewGameScreen.Layout.TABLET
	var targets: Array = buttons.duplicate()
	targets.append(screen._company_input)
	var too_small: Array = []
	var outside: Array = []
	var overlaps: Array = []
	for i in targets.size():
		var rect: Rect2 = targets[i].get_global_rect()
		if rect.size.y < MIN_TARGET - 0.5 or rect.size.x < MIN_TARGET - 0.5:
			too_small.append("%s %s" % [_describe(targets[i]), rect.size])
		var inside := rect.position.x >= -1.0 and rect.end.x <= size.x + 1.0 if scrolling else rect_within(rect, view)
		if not inside:
			outside.append("%s %s" % [_describe(targets[i]), rect])
		for j in range(i + 1, targets.size()):
			var a := visible_rect(targets[i])
			var b := visible_rect(targets[j])
			if a.size.x > 0.0 and b.size.x > 0.0 and a.intersects(b, false):
				overlaps.append("%s / %s" % [_describe(targets[i]), _describe(targets[j])])
	assert_eq(too_small, [], "%s: every target is at least %d px square" % [tag, MIN_TARGET])
	assert_eq(outside, [], "%s: every target is inside the window" % tag)
	assert_eq(overlaps, [], "%s: no two targets overlap" % tag)

	var next: Button = screen._next_button
	assert_true(next != null and rect_within(next.get_global_rect(), view) \
		and visible_rect(next).size.is_equal_approx(next.get_global_rect().size),
		"%s: Choose Location is on screen without scrolling" % tag)
	assert_true(screen._back_button != null and rect_within(screen._back_button.get_global_rect(), view),
		"%s: Back is on screen" % tag)
	if layout == StartNewGameScreen.Layout.WIDE or layout == StartNewGameScreen.Layout.LANDSCAPE:
		assert_false(scrolls(screen), "%s: everything fits without scrolling" % tag)
	assert_lte(screen._page.size.x, size.x + 0.5, "%s: nothing runs off the side" % tag)
	assert_eq(_cut_text(screen), [], "%s: no text is cut short or trimmed" % tag)
	var backdrop := screen.get_node_or_null("Backdrop") as Control
	assert_true(backdrop != null and backdrop.get_global_rect().size == Vector2(size),
		"%s: the drawn backdrop covers the window" % tag)

	var holes := int(screen.get_options()["generated_holes"])
	if screen._course_plan != null:
		assert_true(screen._course_plan.hole_count == holes and screen._course_plan.is_visible_in_tree(),
			"%s: the course plan shows the %d holes picked" % [tag, holes])
		assert_true(screen._course_plan.size.x >= 100.0 and screen._course_plan.size.y >= 100.0,
			"%s: the course plan is big enough to read" % tag)
	else:
		assert_true(layout == StartNewGameScreen.Layout.LANDSCAPE and size.y < 540, "%s: only a short landscape window leaves the plan out" % tag)
	var unstyled := 0
	for button in screen._difficulty_buttons + screen._money_buttons + screen._hole_buttons:
		if str(button.accessibility_name).is_empty() or not button.has_theme_stylebox_override("hover_pressed"):
			unstyled += 1
	assert_eq(unstyled, 0, "%s: option buttons are named for screen readers and styled when hovered picked" % tag)


func test_the_screen_opens_with_the_default_options() -> void:
	main._on_menu_start_new_game()
	await process_frames(4)
	assert_not_null(_screen(), "Start New Game opens the company setup screen")
	if _screen() == null:
		return
	assert_eq(_screen().get_options()["generated_holes"], 0, "No generated holes by default")
	assert_eq(_screen().get_options()["starting_money"], 100000, "and $100,000")


func test_every_arrangement_shows_every_option_in_reach() -> void:
	# A generated course makes the plan worth checking at every size.
	_screen()._select_holes(9)
	for entry in SIZES:
		await _resize(entry[0])
		_assert_layout(entry[2], entry[0], entry[1])


func test_the_picks_reach_the_summary_and_the_plan() -> void:
	await _resize(Vector2i(1600, 1000))
	var screen := _screen()
	await click(_button_for(screen._difficulty_buttons, DifficultyPresets.Preset.HARD))
	assert_eq(screen.get_options()["difficulty"], DifficultyPresets.Preset.HARD, "Clicking Hard picks Hard")
	assert_eq(_pressed_values(screen._difficulty_buttons), [DifficultyPresets.Preset.HARD], "Only Hard shows as picked")
	assert_eq(screen._summary_values["difficulty"].text, "Hard", "The summary says Hard")

	await click(_button_for(screen._money_buttons, -1))
	assert_eq(screen.get_options()["starting_money"], -1, "Clicking Unlimited picks an unlimited budget")
	assert_eq(screen._summary_values["money"].text, "Unlimited", "The summary says Unlimited")

	# The tutorial only applies to an empty course, so pick it while there are no holes.
	await click(_button_for(screen._hole_buttons, 0))
	var tutorial_before: bool = screen.get_options()["tutorial"]
	await click(screen._tutorial_card.button)
	assert_eq(screen.get_options()["tutorial"], not tutorial_before, "Clicking the tutorial switch turns the tutorial over")
	assert_eq(screen._summary_values["tutorial"].text, "Off" if tutorial_before else "On", "The summary follows the switch")
	assert_eq(screen._tutorial_card.button.button_pressed, not tutorial_before, "and the switch shows its state")
	await click(screen._tutorial_card.button)
	assert_eq(screen.get_options()["tutorial"], tutorial_before, "Clicking it again puts the choice back")

	await click(_button_for(screen._hole_buttons, 18))
	assert_eq(screen.get_options()["generated_holes"], 18, "Clicking 18 asks for an 18-hole course")
	assert_true(screen._tutorial_card.button.disabled, "With holes generated the tutorial switch cannot be changed")
	assert_eq(screen._summary_values["tutorial"].text, "Not used", "and the summary says the tutorial is not used")
	assert_true(screen._course_plan.hole_count == 18 and screen._course_plan.is_revealing(),
		"The course plan starts drawing the 18 holes in")
	var waited := 0.0
	while screen._course_plan.is_revealing() and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	assert_false(screen._course_plan.is_revealing(), "The course plan finishes drawing in")
	assert_eq(screen._plan_caption.text, "18 holes · par 72", "Its caption reads 18 holes, par 72")

	await click(screen._feature_boxes["wind"])
	assert_eq(screen.get_options()["features"], {"weather": false, "wind": true, "seasons": false},
		"Clicking Wind turns the wind on and leaves the rest off")
	assert_eq(screen._summary_values["features"].text, "Wind", "The summary lists the feature left on")
	await click(screen._feature_boxes["wind"])
	await click(screen._feature_boxes["wind"])
	assert_true(screen.get_options()["features"]["wind"], "Wind toggles off and back on")


	screen._company_input.text = "Integration Links"
	screen._company_input.text_changed.emit("Integration Links")
	await process_frames(1)
	assert_eq(screen._summary_company.text, "Integration Links", "The summary shows the name as it is typed")
	screen._company_input.text = ""
	screen._company_input.text_changed.emit("")
	await process_frames(1)
	assert_eq(screen._summary_company.text, StartNewGameScreen.NAME_PLACEHOLDER, "A blank name shows the placeholder")
	assert_false(str(screen.get_options()["company_name"]).is_empty(), "and still gets a random name")
	await click(screen.find_child("RandomNameButton", true, false))
	assert_false(screen._company_input.text.is_empty(), "The die fills in a random name")
	assert_eq(screen._summary_company.text, screen._company_input.text, "and the summary follows")
	screen._company_input.text = "Integration Links"
	screen._company_input.text_changed.emit("Integration Links")


func test_the_picks_survive_the_window_being_resized() -> void:
	# Set the feature picks this test checks (Wind off, Seasons on), whatever
	# the earlier tests left behind.
	if _screen()._feature_boxes["wind"].button_pressed:
		await click(_screen()._feature_boxes["wind"])
	if not _screen()._feature_boxes["seasons"].button_pressed:
		await click(_screen()._feature_boxes["seasons"])
	var picked: Dictionary = _screen().get_options()
	for size in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(768, 1024), Vector2i(1280, 720)]:
		await _resize(size)
		var screen := _screen()
		assert_eq(screen.get_options(), picked, "%s keeps every choice across the rebuild" % size)
		assert_eq(_pressed_values(screen._difficulty_buttons), [DifficultyPresets.Preset.HARD], "%s: Hard" % size)
		assert_eq(_pressed_values(screen._money_buttons), [-1], "%s: Unlimited" % size)
		assert_eq(_pressed_values(screen._hole_buttons), [18], "%s: 18 holes" % size)
		assert_false(screen._feature_boxes["wind"].button_pressed, "%s: no wind" % size)
		assert_true(screen._feature_boxes["seasons"].button_pressed, "%s: seasons" % size)
		assert_eq(screen._tutorial_card.button.button_pressed, picked["tutorial"], "%s: the tutorial switch keeps its choice" % size)
	# A small drag within one arrangement rebuilds once the window settles.
	await _resize(Vector2i(1240, 700))
	assert_eq(_screen()._built_size, Vector2(1240, 700), "A small resize is measured again once the window settles")
	assert_false(scrolls(_screen()), "and still fits without scrolling")


func test_esc_goes_back_and_choose_location_goes_on() -> void:
	press_key(KEY_ESCAPE)
	await process_frames(3)
	assert_true(_screen() == null or _screen().is_queued_for_deletion(), "Esc leaves the setup screen")
	assert_true(main.main_menu != null and main.main_menu.visible, "for the title screen")

	main._on_menu_start_new_game()
	await process_frames(4)
	var screen := _screen()
	screen._company_input.text = "Integration Links"
	await click(_button_for(screen._hole_buttons, 6))
	var sent: Array = []
	screen.next_requested.connect(func(options: Dictionary) -> void: sent.append(options))
	await click(screen._next_button)
	await process_frames(3)
	assert_eq(sent.size(), 1, "Choose Location sends the options on")
	if sent.size() == 1:
		assert_eq(sent[0]["company_name"], "Integration Links", "with the company name")
		assert_eq(sent[0]["generated_holes"], 6, "and the hole count")
	var world_map := main.get_node_or_null("UI/HUD/WorldMapScreen")
	assert_true(world_map != null and world_map.visible, "Choose Location opens the world map")


## The switch decides whether the empty first course is walked through: set
## off it never starts, set on it starts once and then the choice is spent.
func test_the_tutorial_switch_decides_whether_the_empty_course_gets_one() -> void:
	var saved_world := WorldMap.serialize()

	await _choose_location_with_tutorial(false)
	await _play_first_site()
	assert_true(GameManager.current_course != null, "Play starts the company's first course")
	assert_false(_tutorial_running(), "Switched off, no tutorial starts on the empty course")
	assert_null(main.get_node_or_null("UI/TutorialOverlay"), "and no tutorial panel is drawn")

	await _choose_location_with_tutorial(true)
	await _play_first_site()
	assert_true(_tutorial_running(), "Switched on, the empty course starts the tutorial")
	assert_not_null(main.get_node_or_null("UI/TutorialOverlay"), "whose panel is drawn over the course")
	assert_false(WorldMap.tutorial_enabled, "The choice is spent once the tutorial has started")

	_stop_tutorial()
	WorldMap.deserialize(saved_world)


## Start New Game with the tutorial switch set to `on`, then Choose Location on
## an empty lot.
func _choose_location_with_tutorial(on: bool) -> void:
	main._on_menu_start_new_game()
	await process_frames(4)
	var screen := _screen()
	assert_not_null(screen, "Start New Game opens the setup screen")
	if screen == null:
		return
	await click(_button_for(screen._hole_buttons, 0))
	if screen._tutorial_card.button.button_pressed != on:
		await click(screen._tutorial_card.button)
	assert_eq(screen.get_options()["tutorial"], on, "The switch is set to %s" % ("on" if on else "off"))
	await click(screen._next_button)
	await process_frames(3)


## Buy a site the company can afford and play it, the way the world map's Buy & Play does.
func _play_first_site() -> void:
	var site := WorldMap.pick_random_affordable_location(7)
	assert_ne(site, "", "A site is affordable")
	if site.is_empty():
		return
	assert_true(WorldMap.buy_location(site), "The site is bought")
	main._on_world_map_play_location(site)
	await process_frames(12)


func _tutorial_running() -> bool:
	return main.tutorial_system != null and main.tutorial_system.is_active


## Take the tutorial down without marking it finished: finishing it writes to
## the settings file that every later run reads.
func _stop_tutorial() -> void:
	var tutorial: TutorialSystem = main.tutorial_system
	if tutorial == null:
		return
	tutorial._disconnect_step_signals()
	tutorial.is_active = false
	var overlay := tutorial.get_overlay()
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	tutorial.queue_free()
	main.tutorial_system = null
