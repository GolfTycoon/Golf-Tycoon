extends GameTest
## InputBindings: the editable controls registry, its exact key matching, the
## conflict swap and the settings file round trip.

const TEMP_PATH := "user://test_input_bindings.cfg"

var _old_path: String = ""


func before_each() -> void:
	super()
	_old_path = InputBindings.settings_path
	InputBindings.settings_path = TEMP_PATH
	InputBindings.reset_all(false)


func after_each() -> void:
	InputBindings.settings_path = _old_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	super()


func _key(keycode: int, shift: bool = false, ctrl: bool = false,
		alt: bool = false, meta: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.pressed = true
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.meta_pressed = meta
	return event


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _motion(axis: JoyAxis, value: float = 1.0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _all_actions() -> Array[String]:
	var actions: Array[String] = []
	for group in InputBindings.groups():
		actions.append_array(InputBindings.actions_in_group(str(group["id"])))
	return actions


func _input_map_has(action: String, wanted: Callable) -> bool:
	for event in InputMap.action_get_events(action):
		if wanted.call(event):
			return true
	return false


# ---------------------------------------------------------------------------
# Registry and display
# ---------------------------------------------------------------------------

func test_every_group_lists_bindable_actions_with_a_keycap_text() -> void:
	assert_gt(InputBindings.groups().size(), 3, "the controls page has groups to show")
	var actions := _all_actions()
	assert_gt(actions.size(), 50, "and a full set of course controls")
	for action in actions:
		assert_true(InputBindings.has_action(action), action)
		assert_true(InputMap.has_action(action), "%s is registered with the InputMap" % action)
		assert_false(InputBindings.binding_text(action).is_empty(),
			"%s shows a binding, not a blank keycap" % action)
		assert_false(InputBindings.action_label(action).is_empty(), action)


func test_binding_text_uses_the_games_short_names() -> void:
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S")
	assert_eq(InputBindings.binding_text("rotate_camera_cw"), "Shift + Q")
	assert_eq(InputBindings.binding_text("redo"), "Ctrl + Shift + Z / Ctrl + Y")
	assert_eq(InputBindings.binding_text("pause_menu"), "P / Start")
	assert_eq(InputBindings.binding_text("terrain_water"), "6")
	assert_eq(InputBindings.binding_text("tab_terrain"), "=")
	assert_eq(InputBindings.binding_text("elevation_flat"), "Shift + =")
	assert_eq(InputBindings.binding_text("gamepad_rotate_ccw"), "X")
	assert_eq(InputBindings.binding_text("gamepad_zoom_in"), "RT")


# ---------------------------------------------------------------------------
# Editing
# ---------------------------------------------------------------------------

func test_rebinding_updates_the_action_and_keeps_its_mouse_controls() -> void:
	var result := InputBindings.assign_binding("camera_zoom_in", _key(KEY_F5))
	assert_true(result["ok"])
	assert_eq(InputBindings.binding_text("camera_zoom_in"), "F5")
	assert_true(InputBindings.is_customized("camera_zoom_in"))
	assert_eq(InputBindings.action_for_event(_key(KEY_F5), ["camera_zoom_in"]), "camera_zoom_in")
	assert_eq(InputBindings.action_for_event(_key(KEY_BRACKETRIGHT), ["camera_zoom_in"]), "",
		"the old key no longer zooms")
	assert_true(_input_map_has("camera_zoom_in", func(event: InputEvent) -> bool:
		return event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP),
		"the mouse wheel still zooms")


func test_key_matching_is_exact_about_modifiers() -> void:
	assert_eq(InputBindings.action_for_event(_key(KEY_S), ["quick_save"]), "",
		"a plain S is not a quick save")
	assert_eq(InputBindings.action_for_event(_key(KEY_S, false, true), ["quick_save"]), "quick_save")
	assert_eq(InputBindings.action_for_event(_key(KEY_Q, true), ["rotate_camera"]), "",
		"Shift+Q is not the counter-clockwise rotate")
	assert_eq(InputBindings.action_for_event(_key(KEY_Q, true), ["rotate_camera_cw"]), "rotate_camera_cw")
	assert_eq(InputBindings.action_for_event(_key(KEY_2, true), ["terrain_rough"]), "",
		"Shift+2 paints rough's harsher variant, not rough")


func test_overrides_are_saved_and_reloaded() -> void:
	var result := InputBindings.assign_binding("quick_save", _key(KEY_F5))
	assert_true(result["ok"])
	assert_true(FileAccess.file_exists(TEMP_PATH), "the change is written at once")

	var config := ConfigFile.new()
	assert_eq(config.load(TEMP_PATH), OK)
	var saved: Variant = config.get_value("controls", "bindings", {})
	assert_true(saved is Dictionary)
	if saved is Dictionary:
		assert_true((saved as Dictionary).has("quick_save"), "only the changed action is stored")

	InputBindings.reset_all(false)
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S", "resetting forgets the change in memory")
	InputBindings.load_bindings()
	assert_eq(InputBindings.binding_text("quick_save"), "F5", "reloading brings it back")


func test_reset_one_puts_back_only_that_actions_defaults() -> void:
	InputBindings.assign_binding("quick_save", _key(KEY_F5))
	InputBindings.assign_binding("camera_pan_up", _key(KEY_I))
	InputBindings.reset_binding("quick_save")
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S")
	assert_false(InputBindings.is_customized("quick_save"))
	assert_eq(InputBindings.binding_text("camera_pan_up"), "I", "the other change is kept")

	InputBindings.reset_all()
	assert_eq(InputBindings.binding_text("camera_pan_up"), "W")
	assert_false(InputBindings.is_customized("camera_pan_up"))


func test_a_free_binding_can_be_cleared_and_reset() -> void:
	InputBindings.reset_binding("quick_save")
	InputBindings.clear_binding("quick_save")
	assert_eq(InputBindings.binding_text("quick_save"), "Unbound")
	assert_eq(InputBindings.action_for_event(_key(KEY_S, false, true), ["quick_save"]), "")
	InputBindings.reset_binding("quick_save")
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S")


func test_a_conflicting_key_is_taken_from_the_other_action() -> void:
	var result := InputBindings.assign_binding("quick_save", _key(KEY_P))
	assert_true(result["ok"])
	assert_true(result["conflicts"].has("pause_menu"), "P belongs to the pause menu")
	assert_eq(InputBindings.binding_text("quick_save"), "P")
	assert_eq(InputBindings.binding_text("pause_menu"), "Start",
		"the pause menu keeps its controller binding")


func test_a_conflict_swaps_the_old_binding_so_nothing_is_left_unbound() -> void:
	var result := InputBindings.assign_binding("marketing", _key(KEY_F))
	assert_true(result["ok"])
	assert_true(result["conflicts"].has("financial_overview"))
	assert_true(result["swapped"], "the financial overview had no other binding")
	assert_eq(InputBindings.binding_text("marketing"), "F")
	assert_eq(InputBindings.binding_text("financial_overview"), "M",
		"so it takes over the key Marketing had")


func test_reserved_keys_are_refused_with_a_reason() -> void:
	for keycode in [KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_UP, KEY_BACKSPACE, KEY_CTRL]:
		var result := InputBindings.assign_binding("quick_save", _key(keycode))
		assert_false(result["ok"], "key %d is reserved" % keycode)
		assert_eq(result["reason"], "reserved")
		assert_false(str(result["message"]).is_empty())
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S", "the refusal changed nothing")


func test_controller_buttons_and_triggers_are_editable() -> void:
	assert_eq(InputBindings.binding_text("gamepad_rotate_ccw"), "X")
	var button_result := InputBindings.assign_binding("gamepad_rotate_ccw", _joy(JOY_BUTTON_LEFT_STICK))
	assert_true(button_result["ok"])
	assert_eq(InputBindings.binding_text("gamepad_rotate_ccw"), "L3")
	assert_true(InputBindings.matches(_joy(JOY_BUTTON_LEFT_STICK), "gamepad_rotate_ccw"))
	assert_false(InputBindings.matches(_joy(JOY_BUTTON_X), "gamepad_rotate_ccw"))

	var trigger_result := InputBindings.assign_binding("gamepad_zoom_out", _motion(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	assert_true(trigger_result["ok"])
	assert_eq(InputBindings.binding_text("gamepad_zoom_out"), "RT")
	assert_true(_input_map_has("gamepad_zoom_out", func(event: InputEvent) -> bool:
		return event is InputEventJoypadMotion \
			and (event as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_RIGHT))

	var reserved := InputBindings.assign_binding("gamepad_rotate_ccw", _joy(JOY_BUTTON_A))
	assert_false(reserved["ok"], "A is reserved for menus")
	var stick := InputBindings.assign_binding("gamepad_rotate_ccw", _motion(JOY_AXIS_LEFT_X, -1.0))
	assert_false(stick["ok"], "the left stick belongs to navigation")


func test_malformed_saved_entries_are_ignored_on_load() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "bindings", {
		"quick_save": [{"type": "key", "keycode": KEY_F5}],
		"not_an_action": [{"type": "key", "keycode": KEY_F6}],
		"camera_pan_up": [{"type": "key", "keycode": 0}, "junk", {"type": "nonsense"}],
	})
	config.save(TEMP_PATH)
	InputBindings.load_bindings()
	assert_eq(InputBindings.binding_text("quick_save"), "F5")
	assert_eq(InputBindings.binding_text("camera_pan_up"), "W",
		"a malformed entry leaves the default in place")
