extends MainSceneTest
## The title screen and the setup screen with a controller and with a keyboard:
## focus arrives on its own, the D-pad/arrows move it, A/Enter activates it and
## B/Escape goes back. These are the rules every other screen inherits through
## InputManager, so they are checked on the two screens that start the game.

func before_each() -> void:
	InputManager.device = InputManager.Device.MOUSE
	InputManager._last_active_scope = null
	get_viewport().gui_release_focus()


func _push_joy(index: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = index
		event.pressed = pressed
		get_viewport().push_input(event)
		await process_frames(1)
	await process_frames(1)


func _push_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event)
		await process_frames(1)
	await process_frames(1)


func _focus_on_title_screen() -> Control:
	InputManager.device = InputManager.Device.GAMEPAD
	await process_frames(2)
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		focus = InputManager.focus_first(main.main_menu)
	await process_frames(1)
	return focus


func _assert_visible_pixel_focus(control: Control, context: String) -> void:
	assert_not_null(control, "%s has a focused control" % context)
	if control == null:
		return
	assert_true(control.has_focus(true), "%s shows its focus indicator" % context)
	var focus := control.get_theme_stylebox("focus") as StyleBoxTexture
	assert_not_null(focus, "%s uses the shared pixel focus overlay" % context)
	if focus:
		assert_eq(focus.get_expand_margin(SIDE_LEFT), PixelButtonStyle.FOCUS_EXPAND,
			"%s has the prominent outline" % context)


func test_gamepad_focuses_the_first_title_screen_action() -> void:
	var focus := await _focus_on_title_screen()
	assert_not_null(focus, "a controller gets focus on the title screen without pressing anything")
	assert_true(main.main_menu.is_ancestor_of(focus), "focus starts inside the title screen")
	_assert_visible_pixel_focus(focus, "the initial title action")


func test_dpad_moves_focus_between_title_screen_actions() -> void:
	var before := await _focus_on_title_screen()
	await _push_joy(JOY_BUTTON_DPAD_DOWN)
	var after := get_viewport().gui_get_focus_owner()
	assert_not_null(after)
	assert_ne(after, before, "D-pad Down moves to another action")
	assert_true(main.main_menu.is_ancestor_of(after))
	if before != null:
		assert_false(before.has_focus(true), "the previous action no longer shows focus")
	_assert_visible_pixel_focus(after, "the newly focused action")
	if after is Button:
		assert_false((after as Button).disabled, "navigation cannot highlight a disabled action")


func test_focus_stays_visible_on_all_title_screen_layouts() -> void:
	await _focus_on_title_screen()
	for window in [Vector2i(1600, 1000), Vector2i(768, 1024),
			Vector2i(844, 390), Vector2i(390, 844)]:
		await set_window(window)
		await process_frames(3)
		var current := get_viewport().gui_get_focus_owner()
		_assert_visible_pixel_focus(current, "the title action at %s" % window)
		if current != null:
			assert_true(main.main_menu.is_ancestor_of(current), "focus remains on the title screen")
		for button in find_buttons(main.main_menu):
			var ring := button.get_theme_stylebox("focus") as StyleBoxTexture
			assert_not_null(ring, "%s has the same focus treatment at %s" % [button.text, window])
			if button.disabled:
				assert_false(InputManager.collect_focusables(main.main_menu).has(button),
					"disabled %s cannot become the focused action" % button.text)
	await set_window(DESIGN_WINDOW)


func test_a_opens_the_focused_action_and_b_returns() -> void:
	await _focus_on_title_screen()
	var start := InputManager.focus_first(main.main_menu)
	assert_not_null(start)
	if start == null:
		return
	assert_eq(start.text, "Start New Game", "the first focusable action is Start New Game")
	await _push_joy(JOY_BUTTON_A)
	var setup := main.get_node_or_null("UI/HUD/StartNewGameScreen")
	assert_not_null(setup, "A activates the focused card")
	if setup != null:
		assert_not_null(get_viewport().gui_get_focus_owner(), "the setup screen takes focus")
		await _push_joy(JOY_BUTTON_B)
		assert_null(main.get_node_or_null("UI/HUD/StartNewGameScreen"), "B backs out of the setup screen")
		assert_not_null(main.main_menu, "and the title screen is still there")
		_assert_visible_pixel_focus(get_viewport().gui_get_focus_owner(), "the restored title action")


func test_setup_focus_is_distinct_from_the_chosen_option() -> void:
	await _focus_on_title_screen()
	InputManager.focus_first(main.main_menu)
	await _push_joy(JOY_BUTTON_A)
	var setup := main.get_node_or_null("UI/HUD/StartNewGameScreen") as StartNewGameScreen
	assert_not_null(setup)
	if setup == null:
		return
	var picked: Button = null
	var unpicked: Button = null
	for card: StartNewGameScreen.ChoiceCard in setup._choices:
		if card.group != "difficulty":
			continue
		if card.button.button_pressed:
			picked = card.button
		else:
			unpicked = card.button
	assert_not_null(picked)
	assert_not_null(unpicked)
	if picked != null and unpicked != null:
		unpicked.grab_focus()
		_assert_visible_pixel_focus(unpicked, "an unchosen difficulty")
		assert_false(unpicked.button_pressed, "focus alone does not select the option")
		assert_true(picked.button_pressed, "the previous choice remains selected")
		await _push_joy(JOY_BUTTON_A)
		assert_true(unpicked.button_pressed, "A selects the focused option")
		assert_false(picked.button_pressed, "the old option is no longer selected")
		_assert_visible_pixel_focus(unpicked, "the newly chosen difficulty")
	await _push_joy(JOY_BUTTON_B)


func test_right_stick_points_and_the_dpad_returns_to_focus() -> void:
	await _focus_on_title_screen()
	var focused := get_viewport().gui_get_focus_owner()
	assert_not_null(focused)
	Input.action_press("gamepad_cursor_right", 1.0)
	await process_frames(4)
	Input.action_release("gamepad_cursor_right")
	await process_frames(2)
	assert_true(main.gamepad_cursor.visible, "the right stick brings up a pointer on a screen")
	assert_null(get_viewport().gui_get_focus_owner(), "and stands focus navigation down")
	await _push_joy(JOY_BUTTON_DPAD_DOWN)
	await process_frames(2)
	assert_false(main.gamepad_cursor.visible, "the D-pad returns to focus navigation")
	assert_not_null(get_viewport().gui_get_focus_owner(), "with a focused control again")
	assert_true(main.main_menu.is_ancestor_of(get_viewport().gui_get_focus_owner()))
	_assert_visible_pixel_focus(get_viewport().gui_get_focus_owner(), "the restored controller focus")


func test_left_stick_restores_focus_after_the_controller_pointer() -> void:
	await _focus_on_title_screen()
	Input.action_press("gamepad_cursor_right", 1.0)
	await process_frames(4)
	Input.action_release("gamepad_cursor_right")
	await process_frames(2)
	assert_true(InputManager.pointer_mode)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 1.0
	get_viewport().push_input(stick)
	await process_frames(3)
	assert_false(InputManager.pointer_mode, "the left stick returns to focus navigation")
	assert_false(main.gamepad_cursor.visible)
	_assert_visible_pixel_focus(get_viewport().gui_get_focus_owner(), "the left stick's restored focus")


func test_keyboard_restores_focus_after_the_controller_pointer() -> void:
	await _focus_on_title_screen()
	Input.action_press("gamepad_cursor_right", 1.0)
	await process_frames(4)
	Input.action_release("gamepad_cursor_right")
	await process_frames(2)
	assert_true(InputManager.pointer_mode, "the controller pointer owns the screen")
	assert_null(get_viewport().gui_get_focus_owner())
	await _push_key(KEY_DOWN)
	assert_false(InputManager.pointer_mode, "keyboard input leaves controller pointer mode")
	assert_false(main.gamepad_cursor.visible)
	_assert_visible_pixel_focus(get_viewport().gui_get_focus_owner(), "the keyboard's restored focus")


func test_mouse_leaves_controller_pointer_mode_without_stealing_focus() -> void:
	await _focus_on_title_screen()
	Input.action_press("gamepad_cursor_right", 1.0)
	await process_frames(4)
	Input.action_release("gamepad_cursor_right")
	await process_frames(2)
	assert_true(InputManager.pointer_mode)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	motion.position = Vector2(10, 10)
	motion.global_position = motion.position
	get_viewport().push_input(motion)
	await process_frames(3)
	assert_eq(InputManager.device, InputManager.Device.MOUSE)
	assert_false(InputManager.pointer_mode, "the real mouse leaves virtual pointer mode")
	assert_null(get_viewport().gui_get_focus_owner(), "pointer use does not force focus onto a button")
	await _push_joy(JOY_BUTTON_DPAD_DOWN)
	_assert_visible_pixel_focus(get_viewport().gui_get_focus_owner(), "focus after returning to the controller")


func test_keyboard_tab_and_arrows_navigate_the_title_screen() -> void:
	InputManager.device = InputManager.Device.KEYBOARD
	await process_frames(2)
	var first := get_viewport().gui_get_focus_owner()
	assert_not_null(first, "the keyboard gets focus on the title screen")
	if first == null:
		return
	await _push_key(KEY_TAB)
	var after_tab := get_viewport().gui_get_focus_owner()
	assert_ne(after_tab, first, "Tab moves to the next action")
	await _push_key(KEY_DOWN)
	var after_down := get_viewport().gui_get_focus_owner()
	assert_ne(after_down, after_tab, "arrow keys move focus as well")
	assert_true(main.main_menu.is_ancestor_of(after_down))
	_assert_visible_pixel_focus(after_down, "the keyboard-focused action")


func test_the_screen_pointer_clicks_a_control() -> void:
	await _focus_on_title_screen()
	var start := InputManager.focus_first(main.main_menu)
	assert_not_null(start)
	if start == null:
		return
	Input.action_press("gamepad_cursor_right", 1.0)
	await process_frames(4)
	Input.action_release("gamepad_cursor_right")
	await process_frames(2)
	assert_true(main.gamepad_cursor.visible)
	main.gamepad_cursor.position = start.get_global_rect().get_center()
	await process_frames(1)
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "gamepad_click"
		event.pressed = pressed
		get_viewport().push_input(event)
		await process_frames(1)
	await process_frames(2)
	assert_not_null(main.get_node_or_null("UI/HUD/StartNewGameScreen"),
		"the controller pointer clicks the card under it")
	await _push_joy(JOY_BUTTON_B)
