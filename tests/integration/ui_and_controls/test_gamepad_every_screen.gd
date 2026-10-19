extends GutTest
## Every screen and popup is operable without a mouse: it exposes at least one
## focusable control, the controller/keyboard gets focus inside it on open, and
## B/Esc closes it. This is the shared contract behind the per-screen tests;
## each screen is opened on its own here so a failure names the screen.

const BUTTON_B := JOY_BUTTON_B
const BUTTON_DPAD_DOWN := JOY_BUTTON_DPAD_DOWN


func before_each() -> void:
	InputManager.device = InputManager.Device.GAMEPAD
	InputManager.clear_focus()
	# A screen opened in an earlier test must not keep a stale scope.
	for scope in InputManager._scopes.duplicate():
		InputManager.unregister_scope(scope)


func after_each() -> void:
	InputManager.clear_focus()
	InputManager.device = InputManager.Device.MOUSE
	for scope in InputManager._scopes.duplicate():
		InputManager.unregister_scope(scope)


func _add(screen: Control) -> Control:
	add_child_autofree(screen)
	await wait_frames(5)
	return screen


func _push_joy(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event)
		await wait_frames(1)


func _assert_operable(label: String, screen: Control) -> void:
	var focusables: Array[Control] = InputManager.collect_focusables(screen)
	assert_gt(focusables.size(), 0, "%s: has at least one keyboard/controller control" % label)
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "%s: opens with focus inside it" % label)
	if focus != null:
		assert_true(screen.is_ancestor_of(focus), "%s: focus starts inside the screen" % label)


func test_pause_menu_is_operable_and_b_resumes() -> void:
	var screen := await _add(PauseMenu.new()) as PauseMenu
	_assert_operable("pause menu", screen)
	watch_signals(screen)
	await _push_joy(BUTTON_B)
	assert_signal_emitted(screen, "resume_requested", "B resumes the game")


func test_settings_are_operable_and_b_closes() -> void:
	var screen := await _add(SettingsMenu.new()) as SettingsMenu
	_assert_operable("settings", screen)
	var closed := [false]
	screen.close_requested.connect(func() -> void: closed[0] = true)
	await _push_joy(BUTTON_B)
	assert_true(closed[0], "B closes settings")
	assert_false(is_instance_valid(screen), "and the menu is freed")


func test_save_load_is_operable_and_b_closes() -> void:
	var screen := SaveLoadPanel.new()
	screen.open_mode = SaveLoadPanel.ScreenMode.SAVE
	screen.allow_save = true
	await _add(screen)
	_assert_operable("save/load", screen)
	var closed := [false]
	screen.panel_closed.connect(func() -> void: closed[0] = true)
	await _push_joy(BUTTON_B)
	assert_true(closed[0], "B closes the archive")


func test_credits_are_operable_and_b_closes() -> void:
	var screen := await _add(CreditsScreen.new()) as CreditsScreen
	_assert_operable("credits", screen)
	var closed := [false]
	screen.close_requested.connect(func() -> void: closed[0] = true)
	await _push_joy(BUTTON_B)
	assert_true(closed[0], "B closes the credits")


func test_help_panel_is_operable_and_b_closes() -> void:
	var screen := HotkeyPanel.new()
	add_child_autofree(screen)
	# CenteredPanel starts hidden; open it the way F1 does.
	screen.show_centered()
	await wait_frames(5)
	_assert_operable("help", screen)
	await _push_joy(BUTTON_B)
	assert_false(screen.visible, "B closes the help sheet")


func test_confirm_dialog_is_operable_and_b_cancels() -> void:
	var screen := ConfirmDialog.new("Delete the course?", "Delete", "Keep")
	var cancelled := [false]
	screen.cancelled.connect(func() -> void: cancelled[0] = true)
	await _add(screen)
	_assert_operable("confirm", screen)
	await _push_joy(BUTTON_B)
	assert_true(cancelled[0], "B cancels a destructive confirmation")


func test_keyboard_tab_cycles_the_controls_of_a_screen() -> void:
	var screen := await _add(PauseMenu.new()) as PauseMenu
	var first := get_viewport().gui_get_focus_owner()
	assert_not_null(first)
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.physical_keycode = KEY_TAB
	key.pressed = true
	get_viewport().push_input(key)
	await wait_frames(3)
	var second := get_viewport().gui_get_focus_owner()
	assert_not_null(second, "Tab lands on the next control")
	assert_ne(second, first, "and not the same one")
	assert_true(screen.is_ancestor_of(second))


func test_main_menu_is_operable() -> void:
	var screen := await _add(MainMenu.new()) as MainMenu
	_assert_operable("main menu", screen)


func test_start_new_game_is_operable_and_b_backs_out() -> void:
	var screen := await _add(StartNewGameScreen.new()) as StartNewGameScreen
	_assert_operable("start new game", screen)
	var closed := [false]
	screen.back_requested.connect(func() -> void: closed[0] = true)
	await _push_joy(BUTTON_B)
	assert_true(closed[0], "B returns to the title screen")


func test_financial_overview_is_operable_and_b_closes() -> void:
	var screen := FinancialOverviewScreen.new()
	add_child_autofree(screen)
	screen.show_centered()
	await wait_frames(5)
	_assert_operable("financial overview", screen)
	var closed := [false]
	screen.close_requested.connect(func() -> void: closed[0] = true)
	await _push_joy(BUTTON_B)
	assert_true(closed[0], "B closes the dashboard")


func _assert_back_on_b(label: String, screen: Control, signal_name: String) -> void:
	_assert_operable(label, screen)
	var closed := [false]
	screen.connect(signal_name, func() -> void: closed[0] = true)
	await _push_joy(BUTTON_B)
	assert_true(closed[0], "%s: B goes back" % label)


func test_achievements_are_operable_and_b_backs_out() -> void:
	await _assert_back_on_b("achievements", await _add(AchievementsScreen.new()), "back_requested")


func test_course_milestones_are_operable_and_b_backs_out() -> void:
	await _assert_back_on_b("course milestones", await _add(CourseMilestonesScreen.new()), "back_requested")


func test_world_milestones_are_operable_and_b_backs_out() -> void:
	await _assert_back_on_b("world milestones", await _add(WorldMilestonesScreen.new()), "back_requested")


func test_golfer_skins_are_operable_and_b_backs_out() -> void:
	await _assert_back_on_b("golfer skins", await _add(EditGolferSkinsScreen.new()), "back_requested")


func test_benchmark_results_are_operable_and_b_backs_out() -> void:
	await _assert_back_on_b("benchmark results", await _add(BenchmarkResultsScreen.new()), "back_requested")


func test_world_map_is_operable_and_b_backs_out() -> void:
	await _assert_back_on_b("world map", await _add(WorldMapScreen.new()), "back_requested")


func test_course_map_is_operable_and_b_backs_out() -> void:
	await _assert_back_on_b("course map", await _add(CourseMapScreen.new()), "back_requested")


func test_game_over_is_operable() -> void:
	var screen := await _add(GameOverPanel.new()) as GameOverPanel
	_assert_operable("game over", screen)


func test_event_feed_is_operable_and_b_closes() -> void:
	var screen := EventFeedPanel.new()
	add_child_autofree(screen)
	screen.show()
	await wait_frames(5)
	_assert_operable("event feed", screen)
	await _push_joy(BUTTON_B)
	assert_false(screen.visible, "B closes the event feed")


func _find_button(root: Node, text: String) -> Button:
	for button in root.find_children("*", "Button", true, false):
		if (button as Button).text == text and (button as Button).is_visible_in_tree():
			return button as Button
	return null


func test_keyboard_enter_activates_the_focused_control() -> void:
	var screen := await _add(PauseMenu.new()) as PauseMenu
	var resumed := [false]
	screen.resume_requested.connect(func() -> void: resumed[0] = true)
	for pressed in [true, false]:
		var enter := InputEventAction.new()
		enter.action = "ui_accept"
		enter.pressed = pressed
		get_viewport().push_input(enter)
		await wait_frames(1)
	await wait_frames(2)
	assert_true(resumed[0], "Enter presses the focused Resume button")


func test_touch_tap_activates_a_screen_control() -> void:
	# GUT runs in a tiny 64x64 viewport; use a window a touch could really hit.
	var original_size: Vector2i = get_viewport().size
	get_viewport().size = Vector2i(1280, 800)
	var screen := await _add(PauseMenu.new()) as PauseMenu
	var resumed := [false]
	screen.resume_requested.connect(func() -> void: resumed[0] = true)
	var button := _find_button(screen, "Resume")
	assert_not_null(button, "the pause menu has its Resume button")
	if button == null:
		return
	var point := button.get_global_rect().get_center()
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = true
	get_viewport().push_input(touch)
	await wait_frames(1)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = point
	release.pressed = false
	get_viewport().push_input(release)
	await wait_frames(3)
	assert_true(resumed[0], "a tap on Resume resumes the game on a touchscreen")
	get_viewport().size = original_size
