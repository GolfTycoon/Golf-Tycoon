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
		assert_eq(categories, 3, "%s: all three categories are in reach" % tag)
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
			"WindFlagQuality", "AnimationRate", "CameraUpdateRate", "GolferUpdateRate"]:
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
