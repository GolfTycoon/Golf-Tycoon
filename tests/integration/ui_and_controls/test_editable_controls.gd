extends GameTest
## The Controls page of Settings: listening on a keycap, binding a key and a
## controller button, the conflict swap, unbinding, resetting and the saved
## file that carries the player's bindings between sessions.

const TEMP_PATH := "user://test_editable_controls.cfg"
const DESIGN_WINDOW := Vector2i(1600, 1000)

var _old_path: String = ""


func before_each() -> void:
	super()
	_old_path = InputBindings.settings_path
	InputBindings.settings_path = TEMP_PATH
	InputBindings.reset_all(false)
	get_window().size = DESIGN_WINDOW


func after_each() -> void:
	get_window().size = DESIGN_WINDOW
	InputBindings.settings_path = _old_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	super()


func _open_controls() -> SettingsMenu:
	var menu := SettingsMenu.new()
	add_child_autofree(menu)
	await process_frames(5)
	menu._select_category(SettingsMenu.Category.CONTROLS)
	await process_frames(3)
	return menu


func _binding_button(menu: SettingsMenu, action: String) -> Button:
	return menu.find_child("Binding_%s" % action, true, false) as Button


func _reset_button(menu: SettingsMenu, action: String) -> Button:
	return menu.find_child("Reset_%s" % action, true, false) as Button


func _key(keycode: int, shift: bool = false, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.pressed = true
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	return event


func _press(event: InputEvent) -> void:
	get_viewport().push_input(event)
	await process_frames(2)


func _saved_bindings() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(TEMP_PATH) != OK:
		return {}
	var saved: Variant = config.get_value("controls", "bindings", {})
	if saved is Dictionary:
		return saved as Dictionary
	return {}


# ---------------------------------------------------------------------------
# The page
# ---------------------------------------------------------------------------

func test_the_controls_page_lists_every_bindable_action() -> void:
	var menu := await _open_controls()
	var status := menu.find_child("ControlsStatus", true, false) as Label
	assert_not_null(status, "the page explains how listening works")
	var reset_all := menu.find_child("ResetAllControlsButton", true, false) as Button
	assert_not_null(reset_all, "and carries Reset All")
	var expected := 0
	for group in InputBindings.groups():
		for action in InputBindings.actions_in_group(str(group["id"])):
			expected += 1
			assert_not_null(_binding_button(menu, action), "%s has a keycap" % action)
			assert_not_null(_reset_button(menu, action), "%s has a reset" % action)
	assert_gt(expected, 50)
	assert_eq(_binding_button(menu, "quick_save").text, "Ctrl + S")
	assert_eq(_binding_button(menu, "pause_menu").text, "P / Start")


# ---------------------------------------------------------------------------
# Listening and assigning
# ---------------------------------------------------------------------------

func test_clicking_a_keycap_and_pressing_a_key_rebinds_it() -> void:
	var menu := await _open_controls()
	var button := _binding_button(menu, "quick_save")
	assert_false(button.disabled, "the keycap is a button")
	button.pressed.emit()
	await process_frames(1)
	assert_eq(menu._capturing_action, "quick_save", "the row starts listening")
	assert_string_contains(button.text, "Press")

	await _press(_key(KEY_F5))
	assert_eq(menu._capturing_action, "", "the capture ends")
	assert_eq(InputBindings.binding_text("quick_save"), "F5")
	assert_eq(button.text, "F5", "the keycap shows the new binding")
	assert_string_contains(str((menu.find_child("ControlsStatus", true, false) as Label).text), "Bound Quick save")
	var saved := _saved_bindings()
	assert_true(saved.has("quick_save"), "and the change is on disk")
	# The old shortcut is gone and the new one works.
	assert_eq(InputBindings.action_for_event(_key(KEY_S, false, true), ["quick_save"]), "")
	assert_eq(InputBindings.action_for_event(_key(KEY_F5), ["quick_save"]), "quick_save")


func test_a_modifier_combination_can_be_bound() -> void:
	var menu := await _open_controls()
	menu._begin_rebinding("quick_save")
	await _press(_key(KEY_K, false, true))
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + K")
	assert_eq(_binding_button(menu, "quick_save").text, "Ctrl + K")


func test_a_conflict_swaps_the_two_bindings() -> void:
	var menu := await _open_controls()
	menu._begin_rebinding("marketing")
	await _press(_key(KEY_F))
	assert_eq(InputBindings.binding_text("marketing"), "F")
	assert_eq(InputBindings.binding_text("financial_overview"), "M",
		"the action that had F takes the key Marketing had")
	assert_eq(_binding_button(menu, "financial_overview").text, "M",
		"the other row refreshes in place")
	assert_string_contains(str((menu.find_child("ControlsStatus", true, false) as Label).text), "Financial Overview",
		"the message names the action that moved")


func test_escape_cancels_listening_without_closing_settings() -> void:
	var menu := await _open_controls()
	menu._begin_rebinding("quick_save")
	await _press(_key(KEY_ESCAPE))
	assert_eq(menu._capturing_action, "")
	assert_true(is_instance_valid(menu), "Esc did not close the menu")
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S", "the binding was left alone")
	assert_string_contains(str((menu.find_child("ControlsStatus", true, false) as Label).text), "unchanged")


func test_backspace_unbinds_and_reset_puts_it_back() -> void:
	var menu := await _open_controls()
	menu._begin_rebinding("camera_pan_up")
	await _press(_key(KEY_BACKSPACE))
	assert_eq(InputBindings.binding_text("camera_pan_up"), "Unbound")
	assert_eq(_binding_button(menu, "camera_pan_up").text, "Unbound")
	var reset := _reset_button(menu, "camera_pan_up")
	assert_false(reset.disabled, "the row now offers its reset")
	reset.pressed.emit()
	await process_frames(2)
	assert_eq(InputBindings.binding_text("camera_pan_up"), "W")
	assert_true(reset.disabled, "with nothing left to reset")


func test_a_controller_button_can_be_bound() -> void:
	var menu := await _open_controls()
	menu._begin_rebinding("gamepad_rotate_ccw")
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_LEFT_STICK
	event.pressed = true
	await _press(event)
	assert_eq(InputBindings.binding_text("gamepad_rotate_ccw"), "L3")
	assert_eq(_binding_button(menu, "gamepad_rotate_ccw").text, "L3")


func test_reset_all_returns_every_row_to_its_default() -> void:
	var menu := await _open_controls()
	menu._begin_rebinding("quick_save")
	await _press(_key(KEY_F5))
	menu._begin_rebinding("camera_pan_up")
	await _press(_key(KEY_I))
	assert_eq(InputBindings.binding_text("quick_save"), "F5")
	assert_eq(InputBindings.binding_text("camera_pan_up"), "I")

	var reset_all := menu.find_child("ResetAllControlsButton", true, false) as Button
	assert_not_null(reset_all)
	reset_all.pressed.emit()
	await process_frames(2)
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S")
	assert_eq(InputBindings.binding_text("camera_pan_up"), "W")
	assert_eq(_binding_button(menu, "quick_save").text, "Ctrl + S")
	assert_eq(_binding_button(menu, "camera_pan_up").text, "W")
	assert_true(reset_all.disabled, "there is nothing left to reset")
	assert_string_contains(str((menu.find_child("ControlsStatus", true, false) as Label).text), "defaults")


func test_bindings_saved_here_survive_a_reload() -> void:
	var menu := await _open_controls()
	menu._begin_rebinding("quick_save")
	await _press(_key(KEY_F5))
	InputBindings.reset_all(false)
	assert_eq(InputBindings.binding_text("quick_save"), "Ctrl + S")
	InputBindings.load_bindings()
	assert_eq(InputBindings.binding_text("quick_save"), "F5",
		"the settings file restores the player's key")
