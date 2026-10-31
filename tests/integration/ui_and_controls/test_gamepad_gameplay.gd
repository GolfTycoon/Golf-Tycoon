extends MainSceneTest
## The course itself with a controller: the pointer appears, moves with the
## right stick, clicks with A, and Start/B open and close the pause menu with
## focus inside it.

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


func _use_gamepad() -> void:
	await _push_joy(JOY_BUTTON_DPAD_UP)
	assert_eq(InputManager.device, InputManager.Device.GAMEPAD)


func test_controller_shows_a_course_pointer_when_no_ui_owns_focus() -> void:
	await new_game()
	assert_not_null(main.gamepad_cursor, "Main creates the controller pointer")
	assert_false(main.gamepad_cursor.visible, "a fresh course starts without a pointer")
	await _use_gamepad()
	# Wait for the pointer to activate on the next frame.
	await process_frames(3)
	assert_true(main.gamepad_cursor.visible, "the pointer shows while the course owns input")
	assert_true(main.input_hint_bar.visible, "the controller prompts are visible too")


func test_right_stick_moves_the_pointer() -> void:
	await new_game()
	await _use_gamepad()
	await process_frames(3)
	var start: Vector2 = main.gamepad_cursor.position
	Input.action_press("gamepad_cursor_right", 1.0)
	await process_frames(8)
	Input.action_release("gamepad_cursor_right")
	await process_frames(1)
	assert_gt(main.gamepad_cursor.position.x, start.x, "the pointer follows the right stick")
	Input.action_press("gamepad_cursor_up", 1.0)
	await process_frames(8)
	Input.action_release("gamepad_cursor_up")
	assert_lt(main.gamepad_cursor.position.y, start.y, "and it moves up as well")


func test_a_clicks_the_course_where_the_pointer_is() -> void:
	await new_game()
	await _use_gamepad()
	await process_frames(3)
	var hud: Control = main.get_node("UI/HUD")
	var target := Button.new()
	target.name = "CursorTarget"
	target.focus_mode = Control.FOCUS_NONE
	target.text = "target"
	target.size = Vector2(240, 80)
	target.position = main.gamepad_cursor.position - target.size * 0.5
	var clicks: Array = []
	target.pressed.connect(func(): clicks.append(true))
	hud.add_child(target)
	await process_frames(2)

	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "gamepad_click"
		event.pressed = pressed
		get_viewport().push_input(event)
		await process_frames(1)
	await process_frames(1)
	assert_eq(clicks.size(), 1, "A sends one click at the pointer")
	target.queue_free()


func test_start_opens_the_pause_menu_and_b_closes_it() -> void:
	await new_game()
	await _use_gamepad()
	await process_frames(2)
	await _push_joy(JOY_BUTTON_START)
	assert_not_null(main.pause_menu, "Start opens the pause menu on the course")
	if main.pause_menu == null:
		return
	await process_frames(2)
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "the pause menu takes focus for the controller")
	assert_true(main.pause_menu.is_ancestor_of(focus))
	if focus != null:
		assert_true(focus.has_focus(true), "the focused pause action shows its indicator")
		var ring := focus.get_theme_stylebox("focus") as StyleBoxFlat
		assert_not_null(ring, "the pause menu inherits the shared button highlight")
		if ring:
			assert_gte(ring.border_width_left, 3, "the outline is prominent")
	await _push_joy(JOY_BUTTON_B)
	assert_null(main.pause_menu, "B resumes and closes the menu")


func test_view_focuses_the_hud_and_b_returns_to_the_course() -> void:
	await new_game()
	await _use_gamepad()
	await process_frames(2)
	var cursor_position: Vector2 = main.gamepad_cursor.position
	await _push_joy(JOY_BUTTON_BACK)  # View / Back
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "View puts focus on the bottom-left controls")
	assert_true(main.left_controls.is_ancestor_of(focus))
	assert_false(main.gamepad_cursor.visible, "the pointer steps aside while the HUD is focused")
	await _push_joy(JOY_BUTTON_B)
	assert_null(get_viewport().gui_get_focus_owner(), "B hands input back to the course")
	await process_frames(2)
	assert_true(main.gamepad_cursor.visible)
	assert_eq(InputManager.virtual_pointer, cursor_position,
		"The returning reticle immediately reclaims the camera pointer")
	var expected: Vector2 = main.camera.get_canvas_transform().affine_inverse() * cursor_position
	assert_eq(main.camera.get_mouse_world_position(), expected)


func test_shift_tab_focuses_the_hud_for_a_keyboard_player() -> void:
	await new_game()
	var shift_tab := InputEventKey.new()
	shift_tab.keycode = KEY_TAB
	shift_tab.physical_keycode = KEY_TAB
	shift_tab.shift_pressed = true
	shift_tab.pressed = true
	get_viewport().push_input(shift_tab)
	await process_frames(3)
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "Shift+Tab reaches the gameplay HUD")
	if focus != null:
		assert_true(main.left_controls.is_ancestor_of(focus))


func _push_key(keycode: Key, shift: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.shift_pressed = shift
		event.pressed = pressed
		get_viewport().push_input(event)
		await process_frames(1)


func test_shift_tab_focuses_the_dock_for_a_keyboard_player() -> void:
	await new_game()
	await _push_key(KEY_TAB, true)
	await process_frames(2)
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "Shift+Tab reaches the gameplay HUD from the course")
	if focus != null:
		assert_true(main.left_controls.is_ancestor_of(focus),
			"and lands on the bottom-left controls")
	var escape := InputEventAction.new()
	escape.action = "cancel"
	escape.pressed = true
	get_viewport().push_input(escape)
	await process_frames(2)


func test_arrow_keys_focus_the_hud_for_a_keyboard_player() -> void:
	await new_game()
	main._last_hud_focus = null
	await _push_key(KEY_RIGHT)
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "the first arrow enters the HUD")
	if focus != null:
		assert_true(main.left_controls.is_ancestor_of(focus))


func test_enter_selects_terrain_then_clicks_the_course_and_arrow_restores_focus() -> void:
	await new_game()
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(2)
	var tile: TerrainTileButton = main.terrain_toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY]
	tile.grab_focus()
	await _push_key(KEY_ENTER)
	assert_eq(main.current_tool, TerrainTypes.Type.FAIRWAY)
	assert_true(tile.is_selected())
	assert_null(get_viewport().gui_get_focus_owner(), "Enter returns focus to the course")
	await process_frames(2)
	assert_true(main.gamepad_cursor.visible)
	# Confirm the second Enter is routed through the course pointer, not the tile.
	var target := Button.new()
	target.focus_mode = Control.FOCUS_NONE
	target.size = Vector2(120, 80)
	target.position = main.gamepad_cursor.position - target.size * 0.5
	var clicks: Array = []
	target.pressed.connect(func(): clicks.append(true))
	main.get_node("UI/HUD").add_child(target)
	await process_frames(2)
	await _push_key(KEY_ENTER)
	assert_eq(clicks.size(), 1, "the next Enter clicks the pointer")
	target.queue_free()
	await _push_key(KEY_LEFT)
	assert_eq(get_viewport().gui_get_focus_owner(), tile, "the first arrow restores the last HUD control")


func test_second_enter_paints_the_selected_terrain_on_the_course() -> void:
	await new_game()
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	var tile: TerrainTileButton = main.terrain_toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY]
	tile.grab_focus()
	await _push_key(KEY_ENTER)
	await process_frames(2)
	var grid_pos := Vector2i(60, 52)
	main._suppress_tile_undo = true
	main.terrain_grid.set_tile(grid_pos, TerrainTypes.Type.ROUGH)
	main._suppress_tile_undo = false
	main.brush_size = 1
	var world: Vector2 = main.terrain_grid.grid_to_screen_center(grid_pos)
	main.camera.focus_on(world, true)
	await process_frames(2)
	main.gamepad_cursor.position = get_viewport().get_visible_rect().size * 0.5
	main.gamepad_cursor._place_pointer()
	await _push_key(KEY_ENTER)
	assert_eq(main.terrain_grid.get_tile(grid_pos), TerrainTypes.Type.FAIRWAY,
		"Enter paints the tile beneath the keyboard pointer")


func test_shift_arrows_move_the_course_pointer_without_focusing_the_hud() -> void:
	await new_game()
	await _push_key(KEY_SHIFT)
	await process_frames(2)
	var start: Vector2 = main.gamepad_cursor.position
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.shift_pressed = true
	right.pressed = true
	Input.parse_input_event(right)
	await process_frames(8)
	right.pressed = false
	Input.parse_input_event(right)
	shift.pressed = false
	Input.parse_input_event(shift)
	await process_frames(2)
	assert_gt(main.gamepad_cursor.position.x, start.x)
	assert_null(get_viewport().gui_get_focus_owner(), "pointer movement does not focus the HUD")


func test_gamepad_terrain_selection_keeps_focus() -> void:
	await new_game()
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await _use_gamepad()
	var tile: TerrainTileButton = main.terrain_toolbar._tool_buttons[TerrainTypes.Type.ROUGH]
	tile.grab_focus()
	await _push_joy(JOY_BUTTON_A)
	assert_eq(main.current_tool, TerrainTypes.Type.ROUGH)
	assert_eq(get_viewport().gui_get_focus_owner(), tile, "keyboard-only behavior leaves controller navigation unchanged")


func test_tab_navigates_the_hud_without_toggling_the_minimap() -> void:
	await new_game()
	await _push_key(KEY_RIGHT)
	var enabled: bool = GameManager.minimap_enabled
	await _push_key(KEY_TAB)
	assert_eq(GameManager.minimap_enabled, enabled)
	assert_not_null(get_viewport().gui_get_focus_owner())


func test_hidden_last_hud_control_falls_back_to_the_dock() -> void:
	await new_game()
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	var tile: TerrainTileButton = main.terrain_toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY]
	tile.grab_focus()
	get_viewport().gui_release_focus()
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.ELEVATION)
	await _push_key(KEY_DOWN)
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus)
	if focus != null:
		assert_true(main.left_controls.is_ancestor_of(focus))


func test_arrow_keys_move_between_dock_controls_after_shift_tab() -> void:
	await new_game()
	await _push_key(KEY_TAB, true)
	await process_frames(2)
	var first := get_viewport().gui_get_focus_owner()
	assert_not_null(first)
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	get_viewport().push_input(right)
	await process_frames(3)
	var release := InputEventAction.new()
	release.action = "ui_right"
	release.pressed = false
	get_viewport().push_input(release)
	await process_frames(2)
	var second := get_viewport().gui_get_focus_owner()
	assert_not_null(second, "Right moves to another HUD control")
	assert_ne(second, first, "and not the same one")
	assert_true(main.left_controls.is_ancestor_of(second),
		"focus stays in the dock")
