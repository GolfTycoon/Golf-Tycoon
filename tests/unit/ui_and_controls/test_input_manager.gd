extends GameTest
## InputManager: device detection and the focus plumbing every screen uses for
## keyboard and gamepad navigation.

const InputManagerScript := preload("res://scripts/autoload/input_manager.gd")

var manager: Node


func before_each() -> void:
	super()
	manager = get_node("/root/InputManager")
	manager.device = InputManagerScript.Device.MOUSE
	manager._scopes.clear()
	manager._wired_scopes.clear()
	manager._last_active_scope = null
	get_viewport().gui_release_focus()


func after_each() -> void:
	get_viewport().gui_release_focus()
	manager.device = InputManagerScript.Device.MOUSE
	manager._scopes.clear()
	manager._wired_scopes.clear()
	manager._last_active_scope = null
	super()


func _key(pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.pressed = pressed
	event.echo = echo
	return event


func _joy_button(index: JoyButton = JOY_BUTTON_A) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


func _joy_motion(axis: JoyAxis = JOY_AXIS_LEFT_X, value: float = -1.0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _mouse_motion(travel: Vector2 = Vector2(4, 0)) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = travel
	return event


# ---------------------------------------------------------------------------
# Device detection
# ---------------------------------------------------------------------------

func test_device_for_event_classifies_all_five_methods() -> void:
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	assert_eq(InputManagerScript.device_for_event(mouse), InputManagerScript.Device.MOUSE)
	assert_eq(InputManagerScript.device_for_event(_mouse_motion()), InputManagerScript.Device.MOUSE)
	assert_eq(InputManagerScript.device_for_event(_key()), InputManagerScript.Device.KEYBOARD)
	assert_eq(InputManagerScript.device_for_event(_joy_button()), InputManagerScript.Device.GAMEPAD)
	assert_eq(InputManagerScript.device_for_event(_joy_motion()), InputManagerScript.Device.GAMEPAD)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	assert_eq(InputManagerScript.device_for_event(touch), InputManagerScript.Device.TOUCH)


func test_events_without_device_intent_are_ignored() -> void:
	# Key repeats, released keys, resting sticks and zero-travel synthetic
	# motion (touch taps, the gamepad cursor) must not steal the UI's device.
	assert_eq(InputManagerScript.device_for_event(_key(false)), -1)
	assert_eq(InputManagerScript.device_for_event(_key(true, true)), -1)
	assert_eq(InputManagerScript.device_for_event(_joy_motion(JOY_AXIS_LEFT_X, 0.05)), -1)
	assert_eq(InputManagerScript.device_for_event(_mouse_motion(Vector2.ZERO)), -1)


func test_only_keyboard_and_gamepad_are_navigation_devices() -> void:
	for value in [InputManagerScript.Device.KEYBOARD, InputManagerScript.Device.GAMEPAD]:
		manager.device = value
		assert_true(manager.is_navigation_device(), InputManagerScript.device_label(value))
	for value in [InputManagerScript.Device.MOUSE, InputManagerScript.Device.TOUCH]:
		manager.device = value
		assert_false(manager.is_navigation_device(), InputManagerScript.device_label(value))


func test_device_change_emits_the_same_device_once() -> void:
	manager.device = InputManagerScript.Device.GAMEPAD
	var seen: Array = []
	manager.device_changed.connect(func(value: int): seen.append(value))
	# A second controller event does not re-announce the device...
	manager._input(_joy_button())
	assert_eq(seen.size(), 0)
	# ...but switching to the keyboard does.
	manager._input(_key())
	assert_eq(seen, [InputManagerScript.Device.KEYBOARD])


# ---------------------------------------------------------------------------
# Focus scopes
# ---------------------------------------------------------------------------

func _make_root() -> Control:
	var root := Control.new()
	root.size = Vector2(600, 400)
	add_child_autofree(root)
	return root


func _make_button(parent: Control, text: String, at: Vector2, size: Vector2 = Vector2(100, 40)) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = size
	parent.add_child(button)
	return button


func test_focus_first_skips_hidden_disabled_and_unfocusable_controls() -> void:
	var root := _make_root()
	var hidden := _make_button(root, "Hidden", Vector2(0, 0))
	hidden.visible = false
	var disabled := _make_button(root, "Disabled", Vector2(0, 50))
	disabled.disabled = true
	var unfocusable := _make_button(root, "Unfocusable", Vector2(0, 100))
	unfocusable.focus_mode = Control.FOCUS_NONE
	var reachable := _make_button(root, "Reachable", Vector2(0, 150))

	var focused: Control = manager.focus_first(root)
	assert_eq(focused, reachable)
	assert_eq(get_viewport().gui_get_focus_owner(), reachable)


func test_focus_first_prefers_the_screens_marked_default() -> void:
	var root := _make_root()
	_make_button(root, "First", Vector2(0, 0))
	var preferred := _make_button(root, "Preferred", Vector2(0, 50))
	preferred.set_meta(InputManagerScript.DEFAULT_FOCUS_META, true)
	_make_button(root, "Last", Vector2(0, 100))

	assert_eq(manager.focus_first(root), preferred)


func test_directional_neighbours_follow_screen_positions() -> void:
	var root := _make_root()
	var top_left := _make_button(root, "TL", Vector2(20, 20))
	var top_right := _make_button(root, "TR", Vector2(220, 20))
	var bottom_left := _make_button(root, "BL", Vector2(20, 170))
	var bottom_right := _make_button(root, "BR", Vector2(220, 170))
	manager.focus_scope(root)

	assert_eq(top_left.get_node(top_left.focus_neighbor_right), top_right,
		"Right on the top-left button reaches the top-right one")
	assert_eq(top_left.get_node(top_left.focus_neighbor_bottom), bottom_left,
		"Down on the top-left button reaches the one below, not the diagonal")
	assert_eq(bottom_right.get_node(bottom_right.focus_neighbor_left), bottom_left)
	assert_eq(bottom_right.get_node(bottom_right.focus_neighbor_top), top_right)


func test_tab_cycle_uses_reading_order() -> void:
	var root := _make_root()
	var top_left := _make_button(root, "TL", Vector2(20, 20))
	var top_right := _make_button(root, "TR", Vector2(220, 20))
	var bottom_left := _make_button(root, "BL", Vector2(20, 170))
	var bottom_right := _make_button(root, "BR", Vector2(220, 170))
	manager.focus_scope(root)

	assert_eq(top_left.get_node(top_left.focus_next), top_right)
	assert_eq(top_right.get_node(top_right.focus_next), bottom_left)
	assert_eq(bottom_left.get_node(bottom_left.focus_next), bottom_right)
	assert_eq(top_left.get_node(top_left.focus_previous), bottom_right,
		"Tab wraps from the first control to the last")


func test_active_scope_is_the_newest_visible_one() -> void:
	var first := _make_root()
	_make_button(first, "One", Vector2(0, 0))
	var second := _make_root()
	_make_button(second, "Two", Vector2(0, 0))
	manager.register_scope(first)
	manager.register_scope(second)
	assert_eq(manager.active_scope(), second)
	second.hide()
	assert_eq(manager.active_scope(), first, "closing the top panel returns to the one below")
	first.hide()
	assert_null(manager.active_scope())
	assert_false(manager.has_visible_scope())


func test_navigation_device_focuses_an_open_scope_on_the_next_frame() -> void:
	var scope := _make_root()
	var button := _make_button(scope, "Button", Vector2(0, 0))
	manager.device = InputManagerScript.Device.GAMEPAD
	manager.register_scope(scope)
	assert_true(await process_frames_until(
		func() -> bool: return get_viewport().gui_get_focus_owner() == button, 5),
		"the gamepad player gets focus in the panel without pressing anything")


# ---------------------------------------------------------------------------
# Controller mappings
# ---------------------------------------------------------------------------

func test_controller_can_confirm_and_cancel_everywhere() -> void:
	assert_true(_has_joypad_button("ui_accept", JOY_BUTTON_A),
		"A confirms the focused control")
	assert_true(_has_joypad_button("ui_cancel", JOY_BUTTON_B),
		"B cancels in Godot's built-in UI actions")
	assert_true(_has_joypad_button("cancel", JOY_BUTTON_B),
		"B also reaches the game's own cancel action")
	assert_true(_has_joypad_button("ui_focus_next", JOY_BUTTON_RIGHT_SHOULDER))
	assert_true(_has_joypad_button("ui_focus_prev", JOY_BUTTON_LEFT_SHOULDER))
	assert_true(_has_joypad_button("pause_menu", JOY_BUTTON_START),
		"Start opens the pause menu")


func test_controller_has_a_course_pointer_and_camera_controls() -> void:
	assert_true(InputMap.has_action("gamepad_click"))
	assert_true(InputMap.has_action("gamepad_focus_hud"))
	assert_true(InputMap.has_action("gamepad_cursor_left"))
	assert_true(InputMap.has_action("gamepad_zoom_in"))
	assert_true(_has_joypad_button("gamepad_rotate_ccw", JOY_BUTTON_X))
	assert_true(_has_joypad_button("gamepad_rotate_cw", JOY_BUTTON_Y))


func _has_joypad_button(action: String, button_index: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button_index:
			return true
	return false


func test_directional_neighbours_are_rebuilt_when_the_layout_changes() -> void:
	var root := _make_root()
	var first := _make_button(root, "First", Vector2(20, 20))
	var second := _make_button(root, "Second", Vector2(220, 20))
	manager.focus_scope(root)
	assert_eq(first.get_node(first.focus_neighbor_right), second)

	# A responsive screen puts the second button under the first instead.
	second.position = Vector2(20, 170)
	manager._last_wire_ms = 0
	manager._refresh_focus_graph_if_stale(root)
	assert_eq(first.get_node(first.focus_neighbor_bottom), second,
		"the D-pad follows the new layout")
	assert_true(first.focus_neighbor_right.is_empty()
		or first.get_node(first.focus_neighbor_right) != second,
		"and the stale right neighbour is gone")


func test_the_synthetic_pointer_only_lives_for_navigation_devices() -> void:
	manager.virtual_pointer = Vector2(120, 340)
	assert_eq(manager.pointer_screen_position(), Vector2(120, 340))
	# A real mouse move (or touch) takes the pointer back.
	manager._input(_mouse_motion(Vector2(6, 0)))
	assert_false(manager.virtual_pointer.is_finite(),
		"the mouse clears the keyboard/controller pointer")
