extends MainSceneTest
## The Save / Load archive and the Settings office, at phone, rotated-phone,
## tablet and desktop window sizes: each picks the right arrangement, keeps every
## visible action inside the window, touch-sized and apart, and does not scroll
## where it promises to fit (desktop and rotated phone). Then the controls do what
## they say, and the game opens the archive in the right mode.

const MIN_TARGET := 36.0
const SIZES := [
	[Vector2i(390, 844), "phone portrait"],
	[Vector2i(360, 640), "small phone"],
	[Vector2i(844, 390), "rotated phone"],
	[Vector2i(640, 360), "small rotated phone"],
	[Vector2i(768, 1024), "tablet portrait"],
	[Vector2i(1024, 768), "tablet landscape"],
	[Vector2i(1366, 657), "laptop browser window"],
	[Vector2i(1600, 1000), "desktop"],
	[Vector2i(2560, 1440), "large desktop"],
]
## Checkpoints on the shelf, so the archive has rows to lay out.
const SEEDED_SAVES := ["integration_layout_one", "integration_layout_two"]
const CHECKPOINT := "integration_layout_checkpoint"
## The benchmark's run shelf, kept off the player's own file.
const HISTORY_PATH := "user://test_settings_benchmark_history.json"
## The Data page's tests point PlayerDataStore at this scratch folder, so the
## deletion buttons are exercised without touching the real player's files.
const DATA_ROOT := "user://test_settings_data_page"
const DATA_SAVES := DATA_ROOT + "/saves/"
const DATA_SETTINGS := DATA_ROOT + "/settings.cfg"
const DATA_HISTORY := DATA_ROOT + "/benchmark_history.json"
const DATA_SNAPSHOT := DATA_ROOT + "/economic_snapshots.json"
const DATA_SKINS := DATA_ROOT + "/golfer_skins"

var _old_history_path := ""


func before_all() -> void:
	await super()
	for save_id in SEEDED_SAVES:
		var file := FileAccess.open(SaveManager.SAVE_DIR + save_id + ".save", FileAccess.WRITE)
		file.store_string(JSON.stringify({
			"timestamp": "2026-10-02T10:00:00",
			"holes": [{"hole_number": 1}, {"hole_number": 2}],
			"game_state": {"course_name": "Integration Links", "current_day": 9, "money": 120000},
		}))
		file.close()


func after_all() -> void:
	for save_id in SEEDED_SAVES + [CHECKPOINT]:
		SaveManager.delete_save(save_id)
	super()


func before_each() -> void:
	super()
	PlayerDataStore.restore_default_paths()
	_remove_data_root()


func after_each() -> void:
	PlayerDataStore.restore_default_paths()
	_remove_data_root()
	await super()


# ---------------------------------------------------------------------------
# The Data page's scratch device
# ---------------------------------------------------------------------------

func _use_scratch_data() -> void:
	PlayerDataStore.saves_dir = DATA_SAVES
	PlayerDataStore.settings_path = DATA_SETTINGS
	PlayerDataStore.benchmark_history_path = DATA_HISTORY
	PlayerDataStore.economic_snapshot_path = DATA_SNAPSHOT
	PlayerDataStore.golfer_skins_dir = DATA_SKINS
	DirAccess.make_dir_recursive_absolute(DATA_SAVES)


func _write_data(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_data_root() -> void:
	if not DirAccess.dir_exists_absolute(DATA_ROOT):
		return
	var dir := DirAccess.open(DATA_ROOT)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var full := DATA_ROOT.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(DATA_ROOT)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var full := path.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _seed_data_device() -> void:
	_write_data(DATA_SAVES + "checkpoint.save", "{\"game_state\": {}}")
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", 0.4)
	config.set_value("display", "fps_counter_enabled", true)
	config.set_value("achievements", "unlocked", {"ach_first_steps": 4})
	config.set_value("tutorial", "completed", true)
	config.save(DATA_SETTINGS)
	_write_data(DATA_HISTORY, JSON.stringify({"version": 2, "runs": [{"at_unix": 1}]}))
	_write_data(DATA_SKINS.path_join("painted").path_join("skin.txt"), "id=painted")


func _open_data_page(origin: int = SettingsMenu.Origin.MAIN_MENU) -> SettingsMenu:
	await set_window(DESIGN_WINDOW)
	var menu := SettingsMenu.new()
	menu.origin = origin
	add_child_autofree(menu)
	await process_frames(6)
	menu._select_category(SettingsMenu.Category.DATA)
	await process_frames(3)
	return menu


func _confirmation_says(menu: SettingsMenu, fragment: String) -> bool:
	var overlay := menu.find_child("SettingsConfirmation", true, false)
	if overlay == null:
		return false
	for label in nodes_of_class(overlay, "Label"):
		if str((label as Label).text).contains(fragment):
			return true
	return false


func _open_archive(mode: SaveLoadPanel.ScreenMode) -> SaveLoadPanel:
	var panel := SaveLoadPanel.new()
	panel.allow_save = true
	panel.open_mode = mode
	add_child_autofree(panel)
	await process_frames(6)
	return panel


func _visible_buttons(root: Node) -> Array:
	return nodes_of_class(root, "Button").filter(func(button: Button) -> bool:
		return button.is_visible_in_tree() and button.get_global_rect().size.x > 0.0)


func _describe(button: Button) -> String:
	return button.text.replace("\n", " ") if not button.text.is_empty() else str(button.name)


## Every visible button is big enough to tap and inside the window (rows inside
## a scroll container may sit below the fold, so only their width is checked),
## and no two of them overlap where they are seen.
func _assert_targets(tag: String, root: Node, size: Vector2i) -> void:
	var view := Rect2(Vector2.ZERO, Vector2(size))
	var buttons := _visible_buttons(root)
	assert_false(buttons.is_empty(), "%s: there are actions on screen" % tag)
	var too_small: Array = []
	var outside: Array = []
	var overlaps: Array = []
	for i in buttons.size():
		var button: Button = buttons[i]
		var rect := button.get_global_rect()
		if rect.size.y < MIN_TARGET - 0.5 or rect.size.x < MIN_TARGET - 0.5:
			too_small.append("%s %s" % [_describe(button), rect.size])
		var inside := rect.position.x >= -1.0 and rect.end.x <= view.end.x + 1.0 if inside_scroll(button) \
			else rect_within(rect, view)
		if not inside:
			outside.append("%s %s" % [_describe(button), rect])
		var seen := visible_rect(button)
		for j in range(i + 1, buttons.size()):
			var other := visible_rect(buttons[j])
			if seen.has_area() and other.has_area() and seen.intersects(other, false):
				overlaps.append("%s / %s" % [_describe(button), _describe(buttons[j])])
	assert_eq(too_small, [], "%s: every action is at least %d px" % [tag, MIN_TARGET])
	assert_eq(outside, [], "%s: every action is inside the window" % tag)
	assert_eq(overlaps, [], "%s: no two actions overlap" % tag)


## No arrangement is wider than the window, and the desktop and rotated-phone
## ones fit without scrolling.
func _assert_fits(tag: String, frame: Control, size: Vector2i, must_fit: bool) -> void:
	assert_not_null(frame, "%s: the page frame exists" % tag)
	if frame == null:
		return
	var needed := frame.get_combined_minimum_size()
	assert_lte(needed.x, size.x + 1.0, "%s: the page is no wider than the window" % tag)
	if must_fit:
		assert_lte(needed.y, size.y + 1.0, "%s: the page fits without scrolling" % tag)


func _assert_archive_fits_every_window(mode: SaveLoadPanel.ScreenMode) -> void:
	var saving := mode == SaveLoadPanel.ScreenMode.SAVE
	for entry in SIZES:
		var size: Vector2i = entry[0]
		var tag := "%s %s" % ["save" if saving else "load", entry[1]]
		await set_window(size)
		var panel: SaveLoadPanel = await _open_archive(mode)
		var layout := SaveLoadPanel.layout_mode_for(Vector2(size))
		assert_eq(panel._layout_mode, layout, "%s: the arrangement for %s" % [tag, size])
		_assert_targets(tag, panel, size)
		_assert_fits(tag, panel.get_node_or_null("ArchiveFrame"), size,
			layout == MenuScreenKit.LayoutMode.DESKTOP or layout == MenuScreenKit.LayoutMode.PHONE_LANDSCAPE)
		if saving:
			assert_not_null(panel.get_node_or_null("ArchiveFrame/ArchivePage"), "%s: the save page is built" % tag)
			assert_not_null(panel.find_child("SaveNameInput", true, false), "%s: with its name field" % tag)
			assert_not_null(panel.find_child("SaveCheckpointButton", true, false), "%s: and its save action" % tag)
		else:
			assert_not_null(panel.find_child("LoadSelectedButton", true, false), "%s: the load action is shown" % tag)
			assert_null(panel.find_child("SaveNameInput", true, false), "%s: with no name field" % tag)
		panel.free()


func test_the_save_screen_fits_every_window() -> void:
	await _assert_archive_fits_every_window(SaveLoadPanel.ScreenMode.SAVE)


func test_the_load_screen_fits_every_window() -> void:
	await _assert_archive_fits_every_window(SaveLoadPanel.ScreenMode.LOAD)


func test_the_settings_office_fits_every_window() -> void:
	for entry in SIZES:
		var size: Vector2i = entry[0]
		var tag := "settings %s" % entry[1]
		await set_window(size)
		var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
		await process_frames(6)
		var layout := SettingsMenu.layout_mode_for(Vector2(size))
		assert_eq(menu._layout_mode, layout, "%s: the arrangement for %s" % [tag, size])
		assert_null(menu.find_child("CourseContextCard", true, false), "%s: the at-a-glance section is removed" % tag)
		var categories := 0
		for category in SettingsMenu.Category.values():
			if menu.find_child("Category_%s" % menu._category_key(category), true, false):
				categories += 1
		assert_eq(categories, 4, "%s: all four categories are in reach" % tag)
		_assert_targets(tag, menu, size)
		_assert_fits(tag, menu.get_node_or_null("SettingsFrame"), size,
			layout == MenuScreenKit.LayoutMode.DESKTOP or layout == MenuScreenKit.LayoutMode.PHONE_LANDSCAPE)
		# Every category builds, and stays on screen, at this size.
		for category in SettingsMenu.Category.values():
			menu._select_category(category)
			await process_frames(3)
			var page := "%s %s" % [tag, menu._category_name(category)]
			_assert_targets(page, menu, size)
			assert_not_null(menu.find_child("CategoryContent", true, false), "%s: the page is built" % page)
		menu.free()


func test_a_checkpoint_needs_a_name_and_asks_before_it_overwrites() -> void:
	await set_window(DESIGN_WINDOW)
	var path: String = SaveManager.SAVE_DIR + CHECKPOINT + ".save"
	var panel: SaveLoadPanel = await _open_archive(SaveLoadPanel.ScreenMode.SAVE)
	panel._save_name_input.text = "   "
	panel._on_save_pressed()
	assert_false(FileAccess.file_exists(path), "A blank checkpoint name is refused")
	assert_string_contains(panel._save_status_label.text, "name", "with a hint")
	panel._save_name_input.text = CHECKPOINT + "/"
	panel._on_save_pressed()
	assert_true(FileAccess.file_exists(path), "A checkpoint is written under the cleaned-up name")
	assert_null(panel.find_child("ArchiveConfirmation", true, false), "A new name saves without asking")
	panel._save_name_input.text = CHECKPOINT
	panel._on_save_pressed()
	assert_not_null(panel.find_child("ArchiveConfirmation", true, false), "Saving over a name asks first")
	panel._close_confirmation()
	await process_frames(2)


func test_a_settings_toggle_changes_the_live_setting() -> void:
	var inverted := GameManager.invert_zoom_scroll
	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	await process_frames(6)
	menu._select_category(SettingsMenu.Category.CONTROLS)
	await process_frames(3)
	var toggle := menu.find_child("Toggle_invert_scroll_zoom", true, false) as CheckButton
	assert_not_null(toggle, "The invert-zoom toggle is on the Controls page")
	if toggle == null:
		return
	toggle.button_pressed = not inverted
	await process_frames(2)
	assert_eq(GameManager.invert_zoom_scroll, not inverted, "Flipping the toggle changes the setting")
	# The toggle saved the flipped value at once: put the real setting back on disk.
	GameManager.invert_zoom_scroll = inverted
	menu._save_controls_settings()


func test_the_edge_pan_setting_switches_the_live_camera() -> void:
	var original_enabled := GameManager.edge_pan_enabled
	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	await process_frames(6)
	menu._select_category(SettingsMenu.Category.CONTROLS)
	await process_frames(3)
	var toggle := menu.find_child("Toggle_edge_panning", true, false) as CheckButton
	assert_not_null(toggle, "The edge-panning toggle is on the Controls page")
	if toggle == null:
		return
	assert_eq(toggle.button_pressed, original_enabled, "The toggle reflects the live preference")

	toggle.button_pressed = not original_enabled
	await process_frames(2)
	assert_eq(GameManager.edge_pan_enabled, not original_enabled, "Flipping the toggle changes the setting")
	assert_eq(main.camera.edge_pan_enabled, not original_enabled, "and the live camera follows it at once")
	var saved := ConfigFile.new()
	assert_eq(saved.load(SaveManager.SETTINGS_PATH), OK, "The setting saves to settings.cfg")
	assert_eq(bool(saved.get_value("camera", "edge_pan_enabled", original_enabled)), not original_enabled,
		"with edge_pan_enabled stored under [camera]")

	toggle.button_pressed = original_enabled
	await process_frames(2)
	assert_eq(GameManager.edge_pan_enabled, original_enabled, "Turning the toggle back restores the preference")
	assert_eq(main.camera.edge_pan_enabled, original_enabled, "and the live camera follows it back")

	# Put the real setting back on disk.
	menu._save_camera_settings()


## The UI scale control: automatic by default, following the detected display
## scale; moving the slider pins a manual size and saves both facts, and
## "Match this display" goes back to automatic.
func test_the_ui_scale_control_matches_the_display_or_pins_a_manual_size() -> void:
	await set_window(DESIGN_WINDOW)
	var saved_mode: int = Screen.ui_scale_mode
	var saved_scale: float = Screen.ui_scale
	var saved_root: float = get_tree().root.content_scale_factor
	var had_file := FileAccess.file_exists(SaveManager.SETTINGS_PATH)
	var saved_bytes := FileAccess.get_file_as_bytes(SaveManager.SETTINGS_PATH) if had_file else PackedByteArray()

	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	await process_frames(6)
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(3)
	var slider := menu.find_child("UIScale", true, false) as HSlider
	var auto_toggle := menu.find_child("Toggle_match_this_display", true, false) as CheckButton
	assert_not_null(slider, "The UI scale slider is on the Display page")
	assert_not_null(auto_toggle, "The automatic UI scale switch is on the Display page")
	if slider == null or auto_toggle == null:
		return
	assert_eq(auto_toggle.button_pressed, Screen.uses_automatic_ui_scale(),
		"the switch reflects the live sizing choice")
	assert_almost_eq(slider.value, Screen.ui_scale, 0.001,
		"the slider shows the size in use")

	# Dragging the slider is choosing a size of your own: manual and saved now.
	slider.value = 1.4
	await process_frames(3)
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.MANUAL, "moving the slider takes manual control")
	assert_almost_eq(Screen.ui_scale, 1.4, 0.001)
	assert_almost_eq(get_tree().root.content_scale_factor, 1.4, 0.001,
		"the chosen size applies to the running game")
	# The page re-flows around the new logical window a moment after the
	# slider settles, so read the control from the live tree.
	auto_toggle = menu.find_child("Toggle_match_this_display", true, false) as CheckButton
	assert_not_null(auto_toggle, "the automatic switch is still on the page")
	if auto_toggle == null:
		return
	assert_false(auto_toggle.button_pressed, "and the automatic switch follows the manual size off")
	var saved := ConfigFile.new()
	assert_eq(saved.load(SaveManager.SETTINGS_PATH), OK, "the choice saves to settings.cfg")
	assert_eq(int(saved.get_value("display", "ui_scale_mode", -1)), Screen.UIScaleMode.MANUAL,
		"with ui_scale_mode marking it as a manual choice")
	assert_almost_eq(float(saved.get_value("display", "ui_scale", 0.0)), 1.4, 0.001)

	# "Match this display" drops the manual size and re-detects.
	auto_toggle.button_pressed = true
	await process_frames(2)
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.AUTO, "the switch returns to automatic sizing")
	assert_almost_eq(Screen.ui_scale, Screen.detected_ui_scale, 0.001)

	# Put the live preference and the real settings file back for later tests.
	Screen.set_ui_scale_mode(saved_mode, false)
	if saved_mode == Screen.UIScaleMode.MANUAL:
		Screen.set_ui_scale(saved_scale, false)
	get_tree().root.content_scale_factor = saved_root
	if had_file:
		var file := FileAccess.open(SaveManager.SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(saved_bytes)
		file.close()
	elif FileAccess.file_exists(SaveManager.SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SETTINGS_PATH))


func test_graphics_presets_apply_and_save_their_separate_settings() -> void:
	await set_window(DESIGN_WINDOW)
	var original_preset := PerformanceSettings.graphics_preset
	var original_graphics: Dictionary = {}
	for setting in PerformanceSettings.GRAPHICS_SETTINGS:
		original_graphics[setting] = PerformanceSettings.get_graphics_setting(setting)
	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	await process_frames(5)
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(2)
	var options := menu.find_child("GraphicsPreset", true, false) as OptionButton
	assert_not_null(options, "Graphics quality is on the Display page")
	if options == null:
		return
	assert_eq(options.item_count, PerformanceSettings.PRESET_LABELS.size(),
		"the named presets and the current Custom combination are shown")
	assert_eq(options.selected, original_preset, "the menu reflects the saved choice")
	for control_name in ["TerrainQuality", "GrassQuality", "TreeOcclusion", "WaterQuality",
			"WindFlagQuality", "ShadowDetail", "WildlifeDetail", "EffectDetail",
			"AnimationRate", "CameraUpdateRate", "GolferUpdateRate"]:
		assert_not_null(menu.find_child(control_name, true, false),
			"%s is an independently adjustable graphics setting" % control_name)

	var performance_index := options.get_item_index(PerformanceSettings.GraphicsPreset.PERFORMANCE)
	options.select(performance_index)
	options.item_selected.emit(performance_index)
	await process_frames(1)
	assert_eq(PerformanceSettings.graphics_preset, PerformanceSettings.GraphicsPreset.PERFORMANCE,
		"choosing a preset applies it immediately")
	assert_eq(PerformanceSettings.terrain_quality, PerformanceSettings.TerrainQuality.FAST)
	assert_eq(PerformanceSettings.grass_quality, PerformanceSettings.GrassQuality.OFF)
	assert_false(PerformanceSettings.tree_occlusion_enabled)
	assert_eq(PerformanceSettings.water_quality, PerformanceSettings.WaterQuality.REDUCED)
	assert_eq(PerformanceSettings.shadow_detail, PerformanceSettings.ShadowDetail.OFF)
	assert_eq(PerformanceSettings.wildlife_detail, PerformanceSettings.WildlifeDetail.OFF)
	assert_eq(PerformanceSettings.effect_detail, PerformanceSettings.EffectDetail.REDUCED)
	assert_eq(PerformanceSettings.animation_rate, PerformanceSettings.UpdateRate.LOW)

	var grass_options := menu.find_child("GrassQuality", true, false) as OptionButton
	var water_before := PerformanceSettings.water_quality
	var grass_full_index := grass_options.get_item_index(PerformanceSettings.GrassQuality.FULL)
	grass_options.select(grass_full_index)
	grass_options.item_selected.emit(grass_full_index)
	await process_frames(1)
	assert_eq(PerformanceSettings.graphics_preset, PerformanceSettings.GraphicsPreset.CUSTOM,
		"editing one component changes the preset label to Custom")
	assert_eq(PerformanceSettings.grass_quality, PerformanceSettings.GrassQuality.FULL)
	assert_eq(PerformanceSettings.water_quality, water_before,
		"the other quality settings keep the preset's values")
	assert_eq(options.selected, PerformanceSettings.GraphicsPreset.CUSTOM)

	var saved := ConfigFile.new()
	assert_eq(saved.load(SaveManager.SETTINGS_PATH), OK, "the display settings file still loads")
	assert_eq(int(saved.get_value("display", "graphics_preset", -1)),
		PerformanceSettings.GraphicsPreset.CUSTOM, "the active preset label is persisted")
	assert_eq(int(saved.get_value("graphics", "grass_quality", -1)),
		PerformanceSettings.GrassQuality.FULL, "the changed component is persisted separately")
	assert_eq(int(saved.get_value("graphics", "water_quality", -1)),
		PerformanceSettings.WaterQuality.REDUCED, "untouched component settings are persisted too")

	if original_preset == PerformanceSettings.GraphicsPreset.CUSTOM:
		PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.CUSTOM)
		for setting in PerformanceSettings.GRAPHICS_SETTINGS:
			PerformanceSettings.set_graphics_setting(setting, original_graphics[setting])
	else:
		PerformanceSettings.set_graphics_preset(original_preset)
	menu._save_display_settings()

func test_the_minimap_setting_enables_and_disables_the_minimap() -> void:
	await set_window(DESIGN_WINDOW)
	var original_enabled := GameManager.minimap_enabled
	var was_hud_visible: bool = main.mini_map.hud_visible

	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	await process_frames(5)
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(2)
	var toggle := menu.find_child("Toggle_minimap", true, false) as CheckButton
	assert_not_null(toggle, "The Minimap toggle is on the Display page")
	if toggle == null:
		return
	assert_eq(toggle.button_pressed, original_enabled, "The toggle reflects the live minimap setting")

	# On the title screen (gameplay HUD hidden), toggling the setting updates and
	# persists the preference without popping the minimap onto the title screen.
	main._set_gameplay_ui_visible(false)
	toggle.button_pressed = false
	await process_frames(2)
	assert_false(GameManager.minimap_enabled, "Turning the toggle off disables the minimap")
	assert_false(main.mini_map.visible, "and keeps it hidden")
	var saved := ConfigFile.new()
	assert_eq(saved.load(SaveManager.SETTINGS_PATH), OK, "The setting saves to settings.cfg")
	assert_eq(bool(saved.get_value("display", "minimap_enabled", true)), false,
		"with minimap_enabled stored under [display]")

	toggle.button_pressed = true
	await process_frames(2)
	assert_true(GameManager.minimap_enabled, "Turning the toggle on enables the minimap preference")
	assert_false(main.mini_map.visible, "while keeping the minimap off the title screen")

	# On the course HUD, the setting immediately hides and shows the minimap.
	main._set_gameplay_ui_visible(true)
	assert_true(main.mini_map.visible, "The enabled minimap appears when the course HUD is shown")
	toggle.button_pressed = false
	await process_frames(2)
	assert_false(main.mini_map.visible, "Disabling the setting hides the live minimap at once")
	toggle.button_pressed = true
	await process_frames(2)
	assert_true(main.mini_map.visible, "Enabling the setting brings the live minimap back at once")

	# Restore global and HUD state.
	main._set_gameplay_ui_visible(was_hud_visible)
	GameManager.set_minimap_enabled(original_enabled)
	menu._save_display_settings()


func test_the_settings_benchmark_offers_a_run_and_the_past_results() -> void:
	await set_window(DESIGN_WINDOW)
	_old_history_path = BenchmarkHistory.history_path
	BenchmarkHistory.history_path = HISTORY_PATH
	BenchmarkHistory.clear()
	# The card adopts the newest finished run, and in a full-suite process
	# another file's tour may have left one behind: start from none.
	PerformanceBenchmark.last_result = {}
	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	await process_frames(5)
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(2)
	var run_button := menu.find_child("RunBenchmarkButton", true, false) as Button
	var past_button := menu.find_child("PastResultsButton", true, false) as Button
	assert_not_null(run_button, "Display settings offer the benchmark")
	assert_not_null(past_button, "and the past results beside it")
	if run_button == null or past_button == null:
		return
	assert_eq(run_button.text, "Run Benchmark", "the run button runs the tour")
	var card_buttons: Array[String] = []
	for child in run_button.get_parent().get_children():
		if child is Button:
			card_buttons.append(str((child as Button).name))
	assert_eq(card_buttons, ["RunBenchmarkButton", "PastResultsButton"],
		"and those two are the only buttons on the benchmark card")
	# A Settings menu standing in for the Main Menu's may run the benchmark:
	# the tour prepares its own course, so it asks Main to start without
	# any course being open.
	assert_true(menu.benchmarks_allowed(), "this menu counts as Main Menu Settings")
	assert_false(run_button.disabled, "so the run can be pressed")
	watch_signals(menu)
	run_button.pressed.emit()
	assert_signal_emitted(menu, "tour_requested",
		"the tour request reaches Main - no open course needed")
	assert_signal_emitted_with_parameters(menu, "tour_requested",
		[CourseBenchmarkScenarios.SUITE_FULL])
	assert_string_contains(menu._benchmark_status_text, "Starting the course tour",
		"the card says what it started")
	assert_not_null(menu.find_child("BenchmarkStars", true, false),
		"the card carries the last run's star rating")
	assert_not_null(menu.find_child("BenchmarkScoreMeter", true, false), "and its score meter")
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = _old_history_path
	PerformanceBenchmark.last_result = {}


func test_settings_from_the_pause_menu_cannot_run_a_benchmark() -> void:
	await set_window(DESIGN_WINDOW)
	main._show_settings_menu()
	await process_frames(5)
	var menu := main.get_node_or_null("UI/HUD/SettingsMenu") as SettingsMenu
	assert_not_null(menu, "the pause session opens the settings office")
	if menu == null:
		return
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(2)
	var run_button := menu.find_child("RunBenchmarkButton", true, false) as Button
	var past_button := menu.find_child("PastResultsButton", true, false) as Button
	assert_not_null(run_button, "the run button is on the card")
	assert_not_null(past_button, "and the past results beside it")
	if run_button == null or past_button == null:
		menu.free()
		return
	assert_true(run_button.disabled, "the run cannot be pressed from here")
	assert_false(past_button.disabled,
		"but reading the past results is not running a benchmark")
	watch_signals(menu)
	run_button.pressed.emit()
	await process_frames(2)
	assert_signal_not_emitted(menu, "tour_requested",
		"even a forced press asks Main for nothing")
	assert_string_contains(menu._benchmark_status_text, "Main Menu",
		"the card says where benchmarks do run")
	menu.free()
	await process_frames(2)

	# The same office opened from the Main Menu runs them freely.
	main._on_main_menu_settings()
	await process_frames(5)
	var from_menu := main.get_node_or_null("UI/HUD/SettingsMenu") as SettingsMenu
	assert_not_null(from_menu, "the Main Menu opens the settings office")
	if from_menu == null:
		return
	assert_eq(from_menu.origin, SettingsMenu.Origin.MAIN_MENU,
		"and this one knows it came from the Main Menu")
	from_menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(2)
	var menu_run := from_menu.find_child("RunBenchmarkButton", true, false) as Button
	assert_false(menu_run.disabled, "the benchmark can run from Main Menu Settings")
	from_menu.free()
	await process_frames(2)


func test_the_settings_open_the_benchmark_results_screen_over_themselves() -> void:
	await set_window(DESIGN_WINDOW)
	_old_history_path = BenchmarkHistory.history_path
	BenchmarkHistory.history_path = HISTORY_PATH
	main._show_settings_menu()
	await process_frames(5)
	var menu := main.get_node_or_null("UI/HUD/SettingsMenu") as SettingsMenu
	assert_not_null(menu, "the pause menu opens the settings office")
	if menu == null:
		return
	assert_eq(menu.origin, SettingsMenu.Origin.PAUSE_MENU,
		"the pause session's Settings know where they were opened from")
	assert_false(menu.benchmarks_allowed(),
		"so no benchmark may run from them")
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(2)
	var results_button := menu.find_child("PastResultsButton", true, false) as Button
	assert_not_null(results_button, "the Display card offers the results screen")
	if results_button == null:
		return
	results_button.pressed.emit()
	await process_frames(3)
	var screen := main.get_node_or_null("UI/HUD/BenchmarkResultsScreen") as BenchmarkResultsScreen
	assert_not_null(screen, "the game opens the results screen over the settings menu")
	if screen:
		assert_false(screen.benchmarks_allowed,
			"and the Main Menu rule follows into the results screen")
		var screen_run := screen.find_child("RunBenchmarkButton", true, false) as Button
		assert_true(screen_run.disabled, "its Run stands down too - viewing only")
		assert_not_null(screen.find_child("FrameChart", true, false), "with its frame chart")
		assert_not_null(screen.find_child("ScorecardPanel", true, false), "and its scorecard")
		var back := screen.find_child("BackButton", true, false) as Button
		assert_not_null(back)
		if back:
			back.pressed.emit()
			await process_frames(3)
		assert_null(main.get_node_or_null("UI/HUD/BenchmarkResultsScreen"),
			"and backing out closes it again")
	assert_not_null(main.get_node_or_null("UI/HUD/SettingsMenu"),
		"the settings office is still open behind it")
	menu.free()
	BenchmarkHistory.clear()
	BenchmarkHistory.history_path = _old_history_path


func test_the_game_opens_the_archive_in_the_right_mode() -> void:
	await set_window(DESIGN_WINDOW)
	main._on_main_menu_load()
	await process_frames(3)
	var from_title := main.get_node_or_null("UI/HUD/SaveLoadPanel") as SaveLoadPanel
	assert_not_null(from_title, "The title screen's Load opens the archive")
	if from_title:
		assert_false(from_title.allow_save, "for loading only")
		assert_eq(from_title._mode, SaveLoadPanel.ScreenMode.LOAD, "on the load page")
		from_title.free()

	main._show_save_load_panel(true, SaveLoadPanel.ScreenMode.SAVE)
	await process_frames(3)
	var from_pause := main.get_node_or_null("UI/HUD/SaveLoadPanel") as SaveLoadPanel
	assert_not_null(from_pause, "The pause menu's Save opens the archive")
	if from_pause:
		assert_true(from_pause.allow_save, "with saving allowed")
		assert_eq(from_pause._mode, SaveLoadPanel.ScreenMode.SAVE, "on the save page")
		assert_eq(from_pause.camera, main.camera, "and the course camera to look around with")
		from_pause.free()


# ---------------------------------------------------------------------------
# The Data page
# ---------------------------------------------------------------------------

func test_the_data_page_reports_what_is_stored_and_asks_before_deleting() -> void:
	await set_window(DESIGN_WINDOW)
	_use_scratch_data()
	_write_data(DATA_SAVES + "checkpoint.save", "{\"game_state\": {}}")
	var menu: SettingsMenu = await _open_data_page()
	watch_signals(menu)

	var summary := menu.find_child("PlayerDataSummary", true, false) as Label
	assert_not_null(summary, "the page says how much of the device is in use")
	if summary:
		assert_string_contains(summary.text, "1 of 5 data groups")
	var usage := menu.find_child("DataUsage_saved_courses", true, false) as Label
	assert_not_null(usage, "the saved-courses card says what it holds")
	if usage:
		assert_string_contains(usage.text, "1 saved course")
	var delete_saves := menu.find_child("DeleteData_saved_courses", true, false) as Button
	assert_not_null(delete_saves, "and offers to delete it")
	assert_false(delete_saves.disabled, "the button is live while a save is stored")
	var delete_preferences := menu.find_child("DeleteData_preferences", true, false) as Button
	assert_not_null(delete_preferences)
	assert_true(delete_preferences.disabled, "an empty group offers no dead action")
	var delete_all := menu.find_child("DeleteAllDataButton", true, false) as Button
	assert_not_null(delete_all, "one button clears all of it")
	assert_false(delete_all.disabled)
	if delete_saves == null:
		return

	delete_saves.pressed.emit()
	await process_frames(2)
	assert_not_null(menu.find_child("SettingsConfirmation", true, false),
		"deleting asks first")
	assert_true(FileAccess.file_exists(DATA_SAVES + "checkpoint.save"),
		"nothing is gone before the answer")
	var keep := menu.find_child("KeepDataButton", true, false) as Button
	assert_not_null(keep, "the safe answer is offered")
	if keep:
		keep.pressed.emit()
		await process_frames(2)
	assert_null(menu.find_child("SettingsConfirmation", true, false), "the card closes")
	assert_true(FileAccess.file_exists(DATA_SAVES + "checkpoint.save"),
		"keeping the data deletes nothing")
	assert_signal_not_emitted(menu, "data_deleted")

	delete_saves.pressed.emit()
	await process_frames(2)
	var confirm := menu.find_child("ConfirmDataDeleteButton", true, false) as Button
	assert_not_null(confirm, "confirming is a second, separate press")
	if confirm:
		confirm.pressed.emit()
		await process_frames(3)
	assert_false(FileAccess.file_exists(DATA_SAVES + "checkpoint.save"),
		"confirming deletes the group")
	assert_signal_emitted(menu, "data_deleted")
	assert_signal_not_emitted(menu, "quit_to_menu_requested",
		"a title-screen session has no course to close")
	var status := menu.find_child("DataStatus", true, false) as Label
	assert_not_null(status)
	if status:
		assert_string_contains(status.text, "deleted")
	var refreshed_all := menu.find_child("DeleteAllDataButton", true, false) as Button
	assert_not_null(refreshed_all)
	if refreshed_all:
		assert_true(refreshed_all.disabled, "with nothing left, the all-data action stands down")
	assert_eq(PlayerDataStore.anything_stored(), false, "the scratch device is empty")


func test_deleting_all_player_data_clears_every_group_at_once() -> void:
	await set_window(DESIGN_WINDOW)
	_use_scratch_data()
	_seed_data_device()
	var menu: SettingsMenu = await _open_data_page()
	watch_signals(menu)
	var delete_all := menu.find_child("DeleteAllDataButton", true, false) as Button
	assert_not_null(delete_all)
	if delete_all == null:
		return
	delete_all.pressed.emit()
	await process_frames(2)
	assert_not_null(menu.find_child("SettingsConfirmation", true, false),
		"deleting everything asks first")
	var confirm := menu.find_child("ConfirmDataDeleteButton", true, false) as Button
	assert_not_null(confirm)
	if confirm:
		confirm.pressed.emit()
		await process_frames(3)
	assert_eq(PlayerDataStore.usage(PlayerDataStore.SAVED_COURSES)["count"], 0,
		"saved courses are gone")
	assert_false(FileAccess.file_exists(DATA_SETTINGS), "preferences and records are gone")
	assert_false(FileAccess.file_exists(DATA_HISTORY), "the benchmark shelf is gone")
	assert_false(DirAccess.dir_exists_absolute(DATA_SKINS), "the custom skins are gone")
	assert_signal_emitted(menu, "data_deleted")
	var emitted: Array = get_signal_parameters(menu, "data_deleted", 0)
	assert_eq(emitted.size(), 1)
	if emitted.size() > 0:
		assert_eq((emitted[0] as Array).size(), PlayerDataStore.GROUP_IDS.size(),
			"the host is told every group went")
	var summary := menu.find_child("PlayerDataSummary", true, false) as Label
	assert_not_null(summary)
	if summary:
		assert_string_contains(summary.text, "Nothing is stored")


func test_deleting_saved_courses_from_a_pause_session_asks_to_close_the_course() -> void:
	_use_scratch_data()
	_write_data(DATA_SAVES + "checkpoint.save", "{\"game_state\": {}}")
	var menu: SettingsMenu = await _open_data_page(SettingsMenu.Origin.PAUSE_MENU)
	watch_signals(menu)
	var delete_saves := menu.find_child("DeleteData_saved_courses", true, false) as Button
	assert_not_null(delete_saves)
	if delete_saves == null:
		return
	delete_saves.pressed.emit()
	await process_frames(2)
	assert_true(_confirmation_says(menu, "current course will close"),
		"the confirmation warns that the course will close")
	var confirm := menu.find_child("ConfirmDataDeleteButton", true, false) as Button
	assert_not_null(confirm)
	if confirm:
		confirm.pressed.emit()
		await process_frames(3)
	assert_false(FileAccess.file_exists(DATA_SAVES + "checkpoint.save"))
	assert_signal_emitted(menu, "quit_to_menu_requested",
		"the host is asked to close the course before it can autosave again")


func test_deleting_benchmark_reports_clears_the_display_cards_last_run() -> void:
	await set_window(DESIGN_WINDOW)
	_use_scratch_data()
	_write_data(DATA_HISTORY, JSON.stringify({"version": 2, "runs": [{"at_unix": 1}]}))
	PerformanceBenchmark.last_result = {
		"frame": {"sample_count": 120, "average_fps": 61.0, "one_percent_low_fps": 55.0,
			"p95_frame_ms": 18.0},
		"score": {"overall": 82.0, "stars": 4, "tier": "Eagle"},
		"engine": {}, "gpu": {},
	}
	var menu: SettingsMenu = await _open_data_page()
	# The Display card adopts the newest run when the menu opens.
	assert_string_contains(menu._benchmark_summary_text, "Eagle",
		"the card starts on the run this machine holds")
	var delete_reports := menu.find_child("DeleteData_benchmark_reports", true, false) as Button
	assert_not_null(delete_reports)
	if delete_reports == null:
		return
	delete_reports.pressed.emit()
	await process_frames(2)
	var confirm := menu.find_child("ConfirmDataDeleteButton", true, false) as Button
	assert_not_null(confirm)
	if confirm:
		confirm.pressed.emit()
		await process_frames(3)
	assert_false(FileAccess.file_exists(DATA_HISTORY), "the shelf is gone")
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(3)
	var summary := menu.find_child("BenchmarkSummary", true, false) as Label
	var status := menu.find_child("BenchmarkStatus", true, false) as Label
	assert_not_null(summary)
	assert_not_null(status)
	if summary:
		assert_string_contains(summary.text, "No results yet",
			"the card no longer describes a deleted report")
	if status:
		assert_string_contains(status.text, "Ready",
			"and it offers a fresh run instead")
	PerformanceBenchmark.last_result = {}
