extends MainSceneTest
## A rebound key drives the real course: the main scene's hotkey dispatcher,
## the terrain toolbar's tool shortcuts and the F1 sheet all follow the
## player's bindings rather than the defaults.

const TEMP_PATH := "user://test_gameplay_rebinding.cfg"

var _old_path: String = ""


func before_all() -> void:
	await super()
	_old_path = InputBindings.settings_path
	InputBindings.settings_path = TEMP_PATH
	InputBindings.reset_all(false)
	await new_game("Rebinding test")


func after_all() -> void:
	InputBindings.settings_path = _old_path
	InputBindings.reset_all(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	super()


func before_each() -> void:
	super()
	InputBindings.reset_all(false)


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.pressed = true
	return event


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event)
	await process_frames(3)


func test_a_rebound_management_key_opens_the_panel_and_the_old_key_does_nothing() -> void:
	main._toggle_financial_overview()
	await process_frames(2)
	if main.financial_panel.visible:
		main._toggle_financial_overview()
		await process_frames(2)
	assert_false(main.financial_panel.visible)

	InputBindings.assign_binding("financial_overview", _key(KEY_F6))
	await _push(_key(KEY_F6))
	assert_true(main.financial_panel.visible, "F6 opens the dashboard now")
	await _push(_key(KEY_F6))
	assert_false(main.financial_panel.visible, "and closes it again")

	await _push(_key(KEY_F))
	assert_false(main.financial_panel.visible, "the default F no longer does")


func test_a_rebound_terrain_key_selects_its_tool() -> void:
	InputBindings.assign_binding("terrain_water", _key(KEY_I))
	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.Type.ROUGH)
	await process_frames(1)

	await _push(_key(KEY_6))
	assert_eq(main.terrain_toolbar.get_current_tool(), TerrainTypes.Type.ROUGH,
		"the old 6 key is free")

	await _push(_key(KEY_I))
	assert_eq(main.terrain_toolbar.get_current_tool(), TerrainTypes.Type.WATER,
		"the rebound I paints water")


func test_the_help_sheet_shows_the_bindings_in_force() -> void:
	InputBindings.assign_binding("quick_save", _key(KEY_F5))
	main._toggle_hotkey_panel()
	await process_frames(3)
	var label := main.hotkey_panel._binding_labels.get("quick_save") as Label
	assert_not_null(label, "the sheet lists Quick save")
	if label != null:
		assert_eq(label.text, "F5", "with the player's key, not the default")
	main.hotkey_panel.hide()
	await process_frames(1)
