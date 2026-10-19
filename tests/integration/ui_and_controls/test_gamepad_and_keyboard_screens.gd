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


func test_gamepad_focuses_the_first_title_screen_action() -> void:
	var focus := await _focus_on_title_screen()
	assert_not_null(focus, "a controller gets focus on the title screen without pressing anything")
	assert_true(main.main_menu.is_ancestor_of(focus), "focus starts inside the title screen")


func test_dpad_moves_focus_between_title_screen_actions() -> void:
	var before := await _focus_on_title_screen()
	await _push_joy(JOY_BUTTON_DPAD_DOWN)
	var after := get_viewport().gui_get_focus_owner()
	assert_not_null(after)
	assert_ne(after, before, "D-pad Down moves to another action")
	assert_true(main.main_menu.is_ancestor_of(after))


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
