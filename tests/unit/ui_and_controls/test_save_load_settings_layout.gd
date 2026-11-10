extends GameTest
const PerformanceSettingsScript = preload("res://scripts/autoload/performance_settings.gd")
## The Save / Load archive and the Settings office: which arrangement each window
## size asks for, and how a typed save name is cleaned before it becomes a file
## name. (The save list the archive shows is covered with SaveManager, in
## save_and_load/test_save_manager.gd.)

# ---------------------------------------------------------------------------
# Save / Load breakpoints
# ---------------------------------------------------------------------------

func test_save_load_phone_sizes_use_the_stacked_archive() -> void:
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(390, 844)), MenuScreenKit.LayoutMode.PHONE_PORTRAIT, "phone portrait")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(320, 568)), MenuScreenKit.LayoutMode.PHONE_PORTRAIT, "smallest phone")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(599, 800)), MenuScreenKit.LayoutMode.PHONE_PORTRAIT, "narrow tall window")

func test_save_load_rotated_phone_keeps_two_panes() -> void:
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(844, 390)), MenuScreenKit.LayoutMode.PHONE_LANDSCAPE, "rotated phone")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(640, 360)), MenuScreenKit.LayoutMode.PHONE_LANDSCAPE, "small rotated phone")

func test_save_load_tablet_and_desktop_breakpoints() -> void:
	assert_true(MenuScreenKit.is_tablet(SaveLoadPanel.layout_mode_for(Vector2(768, 1024))), "tablet portrait")
	assert_true(MenuScreenKit.is_tablet(SaveLoadPanel.layout_mode_for(Vector2(1024, 768))), "tablet landscape")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(1600, 1000)), MenuScreenKit.LayoutMode.DESKTOP, "reference desktop")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(2560, 1440)), MenuScreenKit.LayoutMode.DESKTOP, "large desktop")

func test_save_load_desktop_needs_its_minimum_size() -> void:
	var w := SaveLoadPanel.DESKTOP_MIN_WIDTH
	var h := SaveLoadPanel.DESKTOP_MIN_HEIGHT
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(w, h)), MenuScreenKit.LayoutMode.DESKTOP)
	assert_ne(SaveLoadPanel.layout_mode_for(Vector2(w, h - 1.0)), MenuScreenKit.LayoutMode.DESKTOP, "one pixel short")
	assert_ne(SaveLoadPanel.layout_mode_for(Vector2(w - 1.0, h)), MenuScreenKit.LayoutMode.DESKTOP, "one pixel narrow")


# ---------------------------------------------------------------------------
# Settings breakpoints
# ---------------------------------------------------------------------------

func test_settings_breakpoints_cover_every_device() -> void:
	assert_eq(SettingsMenu.layout_mode_for(Vector2(390, 844)), MenuScreenKit.LayoutMode.PHONE_PORTRAIT, "phone portrait")
	assert_eq(SettingsMenu.layout_mode_for(Vector2(844, 390)), MenuScreenKit.LayoutMode.PHONE_LANDSCAPE, "rotated phone")
	assert_true(MenuScreenKit.is_tablet(SettingsMenu.layout_mode_for(Vector2(768, 1024))), "tablet portrait")
	assert_true(MenuScreenKit.is_tablet(SettingsMenu.layout_mode_for(Vector2(1024, 768))), "tablet landscape")
	assert_eq(SettingsMenu.layout_mode_for(Vector2(1600, 1000)), MenuScreenKit.LayoutMode.DESKTOP, "reference desktop")

## Every size gets exactly one arrangement, and the wide ones only start at
## their documented minimums.
func test_settings_breakpoints_respect_their_minimums() -> void:
	for x in range(300, 2700, 97):
		for y in range(300, 1600, 89):
			var size := Vector2(x, y)
			match SettingsMenu.layout_mode_for(size):
				MenuScreenKit.LayoutMode.DESKTOP:
					assert_true(size.x >= SettingsMenu.DESKTOP_MIN_WIDTH and size.y >= SettingsMenu.DESKTOP_MIN_HEIGHT,
						"%s qualifies for DESKTOP" % size)
				MenuScreenKit.LayoutMode.TABLET_LANDSCAPE, MenuScreenKit.LayoutMode.TABLET_PORTRAIT:
					assert_true(size.x >= SettingsMenu.TABLET_MIN_WIDTH and size.y >= SettingsMenu.TABLET_MIN_HEIGHT,
						"%s qualifies for TABLET" % size)
				MenuScreenKit.LayoutMode.PHONE_LANDSCAPE:
					assert_true(size.x > size.y, "%s is wider than tall for LANDSCAPE" % size)

func test_auto_graphics_profile_targets_web_and_mobile_devices() -> void:
	var auto := PerformanceSettings.GraphicsPreset.AUTO
	assert_true(PerformanceSettingsScript.should_use_low_detail(auto, "Web", 16))
	assert_true(PerformanceSettingsScript.should_use_low_detail(auto, "Android", 8))
	assert_true(PerformanceSettingsScript.should_use_low_detail(auto, "iOS", 8))

func test_auto_graphics_profile_uses_processor_count_on_desktop() -> void:
	var auto := PerformanceSettings.GraphicsPreset.AUTO
	assert_true(PerformanceSettingsScript.should_use_low_detail(auto, "Linux", 4))
	assert_false(PerformanceSettingsScript.should_use_low_detail(auto, "Linux", 8))

func test_graphics_profile_overrides_are_deterministic() -> void:
	assert_true(PerformanceSettingsScript.should_use_low_detail(
			PerformanceSettings.GraphicsPreset.PERFORMANCE, "Linux", 32))
	for preset in [PerformanceSettings.GraphicsPreset.BALANCED, PerformanceSettings.GraphicsPreset.HIGH]:
		assert_false(PerformanceSettingsScript.should_use_low_detail(preset, "Android", 2))

func test_quality_presets_apply_independent_component_settings() -> void:
	var original_preset := PerformanceSettings.graphics_preset
	var original_settings: Dictionary = {}
	for setting in PerformanceSettings.GRAPHICS_SETTINGS:
		original_settings[setting] = PerformanceSettings.get_graphics_setting(setting)

	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.AUTO)
	var auto_uses_fast_path := PerformanceSettingsScript.should_use_low_detail(
		PerformanceSettings.GraphicsPreset.AUTO, OS.get_name(), OS.get_processor_count())
	assert_eq(PerformanceSettings.terrain_quality,
		PerformanceSettings.TerrainQuality.FAST if auto_uses_fast_path else PerformanceSettings.TerrainQuality.FULL)
	assert_eq(PerformanceSettings.grass_quality,
		PerformanceSettings.GrassQuality.OFF if auto_uses_fast_path else PerformanceSettings.GrassQuality.FULL)

	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.PERFORMANCE)
	assert_eq(PerformanceSettings.terrain_quality, PerformanceSettings.TerrainQuality.FAST)
	assert_eq(PerformanceSettings.grass_quality, PerformanceSettings.GrassQuality.OFF)
	assert_false(PerformanceSettings.tree_occlusion_enabled)
	assert_eq(PerformanceSettings.water_quality, PerformanceSettings.WaterQuality.REDUCED)
	assert_eq(PerformanceSettings.wind_flag_quality, PerformanceSettings.WindFlagQuality.REDUCED)
	assert_almost_eq(PerformanceSettings.animation_redraw_interval(), 0.25, 0.0001)
	assert_almost_eq(PerformanceSettings.camera_redraw_interval(), 1.0 / 15.0, 0.0001)
	assert_almost_eq(PerformanceSettings.simulation_update_interval(), 1.0 / 15.0, 0.0001)

	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.BALANCED)
	assert_eq(PerformanceSettings.terrain_quality, PerformanceSettings.TerrainQuality.FULL)
	assert_eq(PerformanceSettings.grass_quality, PerformanceSettings.GrassQuality.FULL)
	assert_true(PerformanceSettings.tree_occlusion_enabled)
	assert_eq(PerformanceSettings.water_quality, PerformanceSettings.WaterQuality.FULL)
	assert_eq(PerformanceSettings.wind_flag_quality, PerformanceSettings.WindFlagQuality.FULL)
	assert_almost_eq(PerformanceSettings.animation_redraw_interval(), 1.0 / 15.0, 0.0001)
	assert_almost_eq(PerformanceSettings.camera_redraw_interval(), 1.0 / 30.0, 0.0001)
	assert_almost_eq(PerformanceSettings.simulation_update_interval(), 1.0 / 30.0, 0.0001)

	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.HIGH)
	assert_almost_eq(PerformanceSettings.animation_redraw_interval(), 1.0 / 30.0, 0.0001)
	assert_almost_eq(PerformanceSettings.camera_redraw_interval(), 1.0 / 60.0, 0.0001)
	assert_almost_eq(PerformanceSettings.simulation_update_interval(), 1.0 / 60.0, 0.0001)
	if original_preset == PerformanceSettings.GraphicsPreset.CUSTOM:
		PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.CUSTOM)
		for setting in PerformanceSettings.GRAPHICS_SETTINGS:
			PerformanceSettings.set_graphics_setting(setting, original_settings[setting])
	else:
		PerformanceSettings.set_graphics_preset(original_preset)

func test_custom_graphics_components_load_separately_from_config() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "graphics_preset", PerformanceSettings.GraphicsPreset.CUSTOM)
	config.set_value("graphics", "terrain_quality", PerformanceSettings.TerrainQuality.FAST)
	config.set_value("graphics", "grass_quality", PerformanceSettings.GrassQuality.FULL)
	config.set_value("graphics", "tree_occlusion", 0)
	config.set_value("graphics", "water_quality", PerformanceSettings.WaterQuality.REDUCED)
	config.set_value("graphics", "wind_flag_quality", PerformanceSettings.WindFlagQuality.FULL)
	config.set_value("graphics", "animation_rate", PerformanceSettings.UpdateRate.LOW)
	config.set_value("graphics", "camera_update_rate", PerformanceSettings.UpdateRate.HIGH)
	config.set_value("graphics", "golfer_update_rate", PerformanceSettings.UpdateRate.STANDARD)
	var settings_script = load("res://scripts/autoload/performance_settings.gd")
	var loaded_settings = settings_script.new()
	loaded_settings.load_from_config(config)
	assert_eq(loaded_settings.graphics_preset, PerformanceSettings.GraphicsPreset.CUSTOM)
	assert_eq(loaded_settings.terrain_quality, PerformanceSettings.TerrainQuality.FAST)
	assert_eq(loaded_settings.grass_quality, PerformanceSettings.GrassQuality.FULL)
	assert_false(loaded_settings.tree_occlusion_enabled)
	assert_eq(loaded_settings.water_quality, PerformanceSettings.WaterQuality.REDUCED)
	assert_eq(loaded_settings.wind_flag_quality, PerformanceSettings.WindFlagQuality.FULL)
	assert_eq(loaded_settings.animation_rate, PerformanceSettings.UpdateRate.LOW)
	assert_eq(loaded_settings.camera_update_rate, PerformanceSettings.UpdateRate.HIGH)
	assert_eq(loaded_settings.golfer_update_rate, PerformanceSettings.UpdateRate.STANDARD)
	loaded_settings.free()

func test_changing_one_graphics_component_keeps_the_others_and_marks_custom() -> void:
	var original_preset := PerformanceSettings.graphics_preset
	var original_settings: Dictionary = {}
	for setting in PerformanceSettings.GRAPHICS_SETTINGS:
		original_settings[setting] = PerformanceSettings.get_graphics_setting(setting)

	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.PERFORMANCE)
	var water_before := PerformanceSettings.water_quality
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.GRASS_QUALITY,
		PerformanceSettings.GrassQuality.FULL)
	assert_eq(PerformanceSettings.graphics_preset, PerformanceSettings.GraphicsPreset.CUSTOM)
	assert_eq(PerformanceSettings.grass_quality, PerformanceSettings.GrassQuality.FULL)
	assert_eq(PerformanceSettings.water_quality, water_before,
		"changing grass leaves water quality alone")
	assert_eq(PerformanceSettings.terrain_quality, PerformanceSettings.TerrainQuality.FAST,
		"changing grass leaves the terrain path alone")

	if original_preset == PerformanceSettings.GraphicsPreset.CUSTOM:
		PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.CUSTOM)
		for setting in PerformanceSettings.GRAPHICS_SETTINGS:
			PerformanceSettings.set_graphics_setting(setting, original_settings[setting])
	else:
		PerformanceSettings.set_graphics_preset(original_preset)


# ---------------------------------------------------------------------------
# Save names
# ---------------------------------------------------------------------------

func test_save_name_is_trimmed() -> void:
	assert_eq(SaveLoadPanel.sanitize_save_name("  Spring Opening  "), "Spring Opening")

func test_save_name_drops_path_characters() -> void:
	assert_eq(SaveLoadPanel.sanitize_save_name("a/b\\c:d*e?f"), "abcdef", "separators and reserved characters are removed")
	assert_eq(SaveLoadPanel.sanitize_save_name("../../etc"), "etc", "traversal cannot reach another folder")

func test_save_name_keeps_ordinary_punctuation_and_unicode() -> void:
	assert_eq(SaveLoadPanel.sanitize_save_name("Pebble Beach - Day 12"), "Pebble Beach - Day 12")
	assert_eq(SaveLoadPanel.sanitize_save_name("Golf Club Ñ"), "Golf Club Ñ")

func test_save_name_is_rejected_when_nothing_is_left() -> void:
	assert_eq(SaveLoadPanel.sanitize_save_name(""), "")
	assert_eq(SaveLoadPanel.sanitize_save_name("   "), "")
	assert_eq(SaveLoadPanel.sanitize_save_name("."), "")
	assert_eq(SaveLoadPanel.sanitize_save_name(".."), "")
	assert_eq(SaveLoadPanel.sanitize_save_name("///"), "")

func test_save_name_is_capped_in_length() -> void:
	var long_name := "x".repeat(200)
	assert_eq(SaveLoadPanel.sanitize_save_name(long_name).length(), SaveLoadPanel.MAX_SAVE_NAME_LENGTH)


# ---------------------------------------------------------------------------
# Shared menu backdrop
# ---------------------------------------------------------------------------

func test_save_load_screen_uses_shared_menu_backdrop_in_save_and_load_modes() -> void:
	var panel := SaveLoadPanel.new()
	panel.allow_save = true
	panel.open_mode = SaveLoadPanel.ScreenMode.SAVE
	add_child_autofree(panel)
	await process_frames(2)

	var save_backdrop := panel.get_node_or_null("Backdrop")
	var save_map := panel.find_child("CourseMapPreview", true, false) as CourseMapThumbnail
	assert_not_null(save_map, "Save mode includes a course map in its left workspace")
	assert_eq(save_map._grid, GameManager.terrain_grid, "Save map previews the live course")
	assert_not_null(save_backdrop, "Save mode builds the shared backdrop")
	assert_true(save_backdrop is MenuBackdrop, "Save mode uses MenuBackdrop like MainMenu")
	assert_eq(panel.get_child(0), save_backdrop, "Backdrop sits behind the archive frame")
	assert_null(panel.find_child("ArchiveScrim", true, false), "Legacy scrim is gone")
	if save_backdrop is Control:
		var ctrl := save_backdrop as Control
		assert_eq(ctrl.anchor_left, 0.0)
		assert_eq(ctrl.anchor_top, 0.0)
		assert_eq(ctrl.anchor_right, 1.0)
		assert_eq(ctrl.anchor_bottom, 1.0)

	panel._set_mode(SaveLoadPanel.ScreenMode.LOAD)
	await process_frames(2)

	var load_backdrop := panel.get_node_or_null("Backdrop")
	var load_map := panel.find_child("CourseMapPreview", true, false) as CourseMapThumbnail
	assert_not_null(load_map, "Load mode includes a map of the selected course")
	assert_not_null(load_backdrop, "Load mode rebuilds the shared backdrop")
	assert_true(load_backdrop is MenuBackdrop, "Load mode uses MenuBackdrop like MainMenu")
	assert_eq(panel.get_child(0), load_backdrop, "Backdrop stays behind the archive frame")
	assert_null(panel.find_child("ArchiveScrim", true, false), "Legacy scrim remains absent")

func test_settings_screen_uses_shared_menu_backdrop_across_categories() -> void:
	var menu := SettingsMenu.new()
	add_child_autofree(menu)
	await process_frames(2)

	for category in SettingsMenu.Category.values():
		menu._select_category(category)
		await process_frames(2)
		var backdrop := menu.get_node_or_null("Backdrop")
		assert_not_null(backdrop, "%s builds the shared backdrop" % menu._category_name(category))
		assert_true(backdrop is MenuBackdrop, "%s uses MenuBackdrop like MainMenu" % menu._category_name(category))
		assert_eq(menu.get_child(0), backdrop, "Backdrop sits behind SettingsFrame")
		assert_null(menu.find_child("SettingsScrim", true, false), "Legacy scrim is gone")
		if backdrop is Control:
			var ctrl := backdrop as Control
			assert_eq(ctrl.anchor_left, 0.0)
			assert_eq(ctrl.anchor_top, 0.0)
			assert_eq(ctrl.anchor_right, 1.0)
			assert_eq(ctrl.anchor_bottom, 1.0)


# ---------------------------------------------------------------------------
# Settings page: the header over the workspace, with no bottom row
# ---------------------------------------------------------------------------

## One window for each arrangement the Settings office has.
const SETTINGS_WINDOWS: Array[Vector2i] = [
	Vector2i(1600, 1000),
	Vector2i(1024, 768),
	Vector2i(768, 1024),
	Vector2i(844, 390),
	Vector2i(390, 844),
]
## What the page's bottom row was made of: a footer holding a save notice and a
## Done button. Settings save as they change and the header's Back button
## already leaves the screen, so the row is gone and none of it may come back.
const SETTINGS_BOTTOM_ROW: Array[String] = ["SettingsFooter", "SaveNotice", "DoneButton"]

func _open_settings(window_size: Vector2i) -> SettingsMenu:
	await resize_window(window_size)
	var menu := SettingsMenu.new()
	add_child_autofree(menu)
	await process_frames(3)
	return menu

func test_settings_page_is_the_header_over_the_workspace_with_no_bottom_row() -> void:
	var original_window := get_window().size
	var arrangements: Dictionary = {}
	for window_size in SETTINGS_WINDOWS:
		var menu: SettingsMenu = await _open_settings(window_size)
		arrangements[menu._layout_mode] = true
		for category in SettingsMenu.Category.values():
			menu._select_category(category)
			await process_frames(2)
			var tag := "%s %s" % [window_size, menu._category_name(category)]
			var page := menu.get_node_or_null("SettingsFrame/SettingsPage") as VBoxContainer
			assert_not_null(page, "%s: the page is built" % tag)
			if page == null:
				continue
			var rows: Array[String] = []
			for row in page.get_children():
				rows.append(str(row.name))
			assert_eq(rows, ["ScreenHeader", "SettingsWorkspace"],
				"%s: the page is the header over the workspace and nothing else" % tag)
			for legacy in SETTINGS_BOTTOM_ROW:
				assert_null(menu.find_child(legacy, true, false),
					"%s: the bottom row's %s is gone" % [tag, legacy])
			# The room the row took went to the settings cards: the workspace
			# ends where the page does, as far above the bottom of the screen
			# as the header starts below the top of it.
			var header := page.get_node_or_null("ScreenHeader") as Control
			var workspace := page.get_node_or_null("SettingsWorkspace") as Control
			if header == null or workspace == null:
				continue
			var screen := menu.get_global_rect()
			var workspace_end := workspace.get_global_rect().end.y
			assert_almost_eq(workspace_end, page.get_global_rect().end.y, 0.5,
				"%s: the workspace runs down to the end of the page" % tag)
			assert_almost_eq(screen.end.y - workspace_end,
				header.get_global_rect().position.y - screen.position.y, 0.5,
				"%s: only the screen margin is left under the workspace" % tag)
		menu.free()
	assert_eq(arrangements.size(), MenuScreenKit.LayoutMode.size(),
		"every arrangement of the page was checked")
	await resize_window(original_window)

## With no Done button, the header's Back button is the on-screen way out.
func test_settings_header_back_button_closes_the_screen_in_every_arrangement() -> void:
	var original_window := get_window().size
	for window_size in SETTINGS_WINDOWS:
		var menu: SettingsMenu = await _open_settings(window_size)
		var closed := [0]
		menu.close_requested.connect(func() -> void: closed[0] += 1)
		var back := menu.get_node_or_null("SettingsFrame/SettingsPage/ScreenHeader/BackButton") as Button
		assert_not_null(back, "%s: the header carries the Back button" % window_size)
		if back == null:
			menu.free()
			continue
		assert_true(back.is_visible_in_tree(), "%s: Back is shown" % window_size)
		assert_false(back.disabled, "%s: Back can be pressed" % window_size)
		assert_true(rect_within(back.get_global_rect(), menu.get_global_rect()),
			"%s: Back is on the screen" % window_size)
		assert_eq(back.focus_mode, Control.FOCUS_ALL,
			"%s: Back can take keyboard and controller focus" % window_size)
		back.pressed.emit()
		await process_frames(2)
		assert_eq(closed[0], 1, "%s: Back asks the game to close the screen, once" % window_size)
		# (the screen freed itself, so GUT cannot re-interrogate it for signals)
		assert_false(is_instance_valid(menu), "%s: and the screen frees itself" % window_size)
	await resize_window(original_window)

func test_settings_escape_closes_the_screen() -> void:
	var original_window := get_window().size
	var menu: SettingsMenu = await _open_settings(Vector2i(1600, 1000))
	var closed := [0]
	menu.close_requested.connect(func() -> void: closed[0] += 1)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._input(esc)
	await process_frames(2)
	assert_eq(closed[0], 1, "Esc asks the game to close the screen, once")
	assert_false(is_instance_valid(menu), "and the screen frees itself")
	await resize_window(original_window)


# ---------------------------------------------------------------------------
# Save / Load top-right header mode buttons
# ---------------------------------------------------------------------------

func test_save_load_mode_buttons_sit_in_top_right_header_like_course_map() -> void:
	var original_window := get_window().size
	await resize_window(Vector2i(1600, 1000))

	var panel := SaveLoadPanel.new()
	panel.allow_save = true
	panel.open_mode = SaveLoadPanel.ScreenMode.SAVE
	add_child_autofree(panel)
	await process_frames(3)

	var page := panel.get_node_or_null("ArchiveFrame/ArchivePage") as VBoxContainer
	var header := panel.get_node_or_null("ArchiveFrame/ArchivePage/ScreenHeader") as HBoxContainer
	assert_not_null(page, "Archive page is built")
	assert_not_null(header, "Shared ScreenHeader leads the page")
	assert_eq(page.get_child_count(), 2, "Only header and workspace sit in ArchivePage on desktop")
	assert_null(panel.find_child("ArchiveModeSwitch", true, false), "Separate mode-switch row is gone")
	assert_null(panel.find_child("ModeSegmentSurface", true, false), "Outer segment surface is gone")

	var actions := header.get_node_or_null("HeaderActions") as HBoxContainer
	var tabs := header.get_node_or_null("HeaderActions/ModeTabs") as HBoxContainer
	var save_btn := header.find_child("SaveMode", true, false) as Button
	var load_btn := header.find_child("LoadMode", true, false) as Button
	var title := header.get_node_or_null("TitleBlock/Title") as Label
	assert_not_null(actions, "Header carries HeaderActions like CourseMapScreen")
	assert_not_null(tabs, "HeaderActions carries ModeTabs like CourseMapScreen")
	assert_not_null(save_btn, "Save progress button is inside ScreenHeader")
	assert_not_null(load_btn, "Load course button is inside ScreenHeader")
	assert_not_null(title)

	if save_btn != null and load_btn != null and title != null and actions != null:
		assert_eq(title.text, "Save your course")
		assert_gt(title.size.x, 0.0, "Title retains visible width")
		assert_eq(save_btn.text, "Save progress")
		assert_eq(load_btn.text, "Load course")
		assert_eq(save_btn.get_theme_font("font"), CourseMapStyle.SUBTITLE_FONT,
			"Mode buttons use the Course Map choice font")
		assert_eq(load_btn.get_theme_font("font"), CourseMapStyle.SUBTITLE_FONT)
		assert_true(save_btn.button_pressed, "Save progress starts selected in SAVE mode")
		assert_false(load_btn.button_pressed, "Load course starts unselected in SAVE mode")

		var save_rect := save_btn.get_global_rect()
		var load_rect := load_btn.get_global_rect()
		assert_gt(save_rect.position.x, 800.0, "Save progress sits on the right side of the header")
		assert_gt(load_rect.position.x, save_rect.end.x, "Load course sits to the right of Save progress")
		assert_lte(load_rect.end.x, 1600.0 + 1.0, "Load course stays inside the right edge")
		assert_lt(save_rect.position.y, 120.0, "Save progress sits in the top corner")
		assert_lte(title.get_global_rect().end.x, actions.get_global_rect().position.x + 1.0,
			"HeaderActions do not overlap the title")

		load_btn.pressed.emit()
		await process_frames(3)

	header = panel.get_node_or_null("ArchiveFrame/ArchivePage/ScreenHeader") as HBoxContainer
	save_btn = header.find_child("SaveMode", true, false) as Button if header else null
	load_btn = header.find_child("LoadMode", true, false) as Button if header else null
	title = header.get_node_or_null("TitleBlock/Title") as Label if header else null
	assert_not_null(save_btn, "Save progress stays in top-right header on Load screen")
	assert_not_null(load_btn, "Load course stays in top-right header on Load screen")
	if save_btn != null and load_btn != null and title != null:
		assert_eq(title.text, "Load a course")
		assert_false(save_btn.button_pressed, "Save progress is unselected in LOAD mode")
		assert_true(load_btn.button_pressed, "Load course is selected in LOAD mode")
		assert_gt(save_btn.get_global_rect().position.x, 800.0,
			"Mode buttons remain in the top-right corner on the Load screen")

	await resize_window(original_window)

func test_load_only_archive_omits_mode_buttons_and_extra_row() -> void:
	var original_window := get_window().size
	await resize_window(Vector2i(1600, 1000))

	var panel := SaveLoadPanel.new()
	panel.allow_save = false
	panel.open_mode = SaveLoadPanel.ScreenMode.LOAD
	add_child_autofree(panel)
	await process_frames(3)

	var page := panel.get_node_or_null("ArchiveFrame/ArchivePage") as VBoxContainer
	var header := panel.get_node_or_null("ArchiveFrame/ArchivePage/ScreenHeader") as HBoxContainer
	assert_not_null(page)
	assert_not_null(header)
	if page != null and header != null:
		assert_eq(page.get_child_count(), 2, "Load-only screen has only header and workspace")
		assert_null(header.get_node_or_null("HeaderActions"), "No mode switch when saving is disallowed")
		assert_null(panel.find_child("SaveMode", true, false))
		assert_null(panel.find_child("LoadMode", true, false))
		assert_null(panel.find_child("LoadOnlyLabel", true, false), "Legacy load-only banner row is gone")

	await resize_window(original_window)


# ---------------------------------------------------------------------------
# Save / Load course location pictures (matching the top-left HUD banner)
# ---------------------------------------------------------------------------

const TEST_PICTURE_SAVE_A := "unit_save_pic_hawaii"
const TEST_PICTURE_SAVE_B := "unit_save_pic_scotland"

func _write_test_save(slot_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var file := FileAccess.open(SaveManager.SAVE_DIR + slot_name + ".save", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _delete_test_saves() -> void:
	for slot_name in [TEST_PICTURE_SAVE_A, TEST_PICTURE_SAVE_B]:
		SaveManager.delete_save(slot_name)

func _has_flag_mark(root: Node) -> bool:
	if root is MenuFlagMark:
		return true
	for child in root.get_children():
		if _has_flag_mark(child):
			return true
	return false

func test_picture_texture_for_save_matches_hud_course_location_picture() -> void:
	CourseLocationPicture.clear_cache()
	var monterey := SaveLoadPanel.picture_texture_for_save(
		{"location_id": "monterey", "theme": "links"}, 2)
	var scotland := SaveLoadPanel.picture_texture_for_save(
		{"location_id": "scotland", "theme": "links"}, 2)
	assert_eq(monterey, CourseLocationPicture.texture_for_location("monterey", CourseTheme.Type.LINKS, 2),
		"save entry uses the exact cached texture of its active location")
	assert_eq(scotland, CourseLocationPicture.texture_for_location("scotland", CourseTheme.Type.LINKS, 2),
		"another save of the same theme uses its own location picture")
	assert_ne(monterey, scotland, "two links locations keep distinct save pictures")

	# Pre-world-map saves without location_id fall back to the legacy location for their theme.
	var legacy_mountain := SaveLoadPanel.picture_texture_for_save({"theme": "mountain"}, 2)
	assert_eq(legacy_mountain,
		CourseLocationPicture.texture_for_location("rocky_mountains", CourseTheme.Type.MOUNTAIN, 2),
		"legacy save falls back to the location activated when loaded")

func test_save_and_load_screens_use_hud_course_pictures_instead_of_flag_marks() -> void:
	var original_window := get_window().size
	var previous_location := WorldMap.active_location_id
	var previous_theme := GameManager.current_theme
	CourseLocationPicture.clear_cache()

	_write_test_save(TEST_PICTURE_SAVE_A, {
		"timestamp": "2099-01-02T12:00:00",
		"game_state": {"course_name": "Kohala Club", "current_day": 14, "money": 95000, "theme": "tropical"},
		"world_map": {"active_location": "hawaii"},
	})
	_write_test_save(TEST_PICTURE_SAVE_B, {
		"timestamp": "2099-01-01T12:00:00",
		"game_state": {"course_name": "Fife Links", "current_day": 8, "money": 64000, "theme": "links"},
		"world_map": {"active_location": "scotland"},
	})
	WorldMap.active_location_id = "las_vegas"
	GameManager.current_theme = CourseTheme.Type.DESERT

	await resize_window(Vector2i(1600, 1000))
	var panel := SaveLoadPanel.new()
	panel.allow_save = true
	panel.open_mode = SaveLoadPanel.ScreenMode.SAVE
	add_child_autofree(panel)
	await process_frames(3)

	var expected_live := CourseLocationPicture.texture_for_location("las_vegas", CourseTheme.Type.DESERT, 2)
	var expected_hawaii := CourseLocationPicture.texture_for_location("hawaii", CourseTheme.Type.TROPICAL, 2)
	var expected_scotland := CourseLocationPicture.texture_for_location("scotland", CourseTheme.Type.LINKS, 2)

	# Save screen: LiveCourseSummary and every save row use PictureFrame/Picture, never MenuFlagMark.
	var live_summary := panel.find_child("LiveCourseSummary", true, false)
	assert_not_null(live_summary)
	if live_summary != null:
		assert_false(_has_flag_mark(live_summary),
			"LiveCourseSummary replaces MenuFlagMark")
		var live_pic := live_summary.find_child("Picture", true, false) as TextureRect
		assert_not_null(live_pic, "LiveCourseSummary shows the live course picture")
		if live_pic != null:
			assert_eq(live_pic.texture, expected_live,
				"LiveCourseSummary matches the HUD picture for the active course")

	var row_a := panel.find_child("SaveRow_%s" % TEST_PICTURE_SAVE_A, true, false) as Button
	var row_b := panel.find_child("SaveRow_%s" % TEST_PICTURE_SAVE_B, true, false) as Button
	assert_not_null(row_a, "Hawaii save row is shown on Save screen")
	assert_not_null(row_b, "Scotland save row is shown on Save screen")
	if row_a != null and row_b != null:
		assert_false(_has_flag_mark(row_a), "Hawaii save row has no MenuFlagMark")
		assert_false(_has_flag_mark(row_b), "Scotland save row has no MenuFlagMark")
		var pic_a := row_a.find_child("Picture", true, false) as TextureRect
		var pic_b := row_b.find_child("Picture", true, false) as TextureRect
		assert_not_null(pic_a)
		assert_not_null(pic_b)
		if pic_a != null and pic_b != null:
			assert_eq(pic_a.texture, expected_hawaii, "Hawaii row uses Hawaii's HUD picture")
			assert_eq(pic_b.texture, expected_scotland, "Scotland row uses Scotland's HUD picture")
			assert_ne(pic_a.texture, pic_b.texture, "Distinct courses show distinct pictures")

	# Load screen: dossier and save rows show each save's HUD picture and follow selection.
	panel._set_mode(SaveLoadPanel.ScreenMode.LOAD)
	await process_frames(3)

	var dossier := panel.find_child("LoadDossier", true, false)
	row_a = panel.find_child("SaveRow_%s" % TEST_PICTURE_SAVE_A, true, false) as Button
	row_b = panel.find_child("SaveRow_%s" % TEST_PICTURE_SAVE_B, true, false) as Button
	assert_not_null(dossier)
	assert_not_null(row_a)
	assert_not_null(row_b)
	if dossier != null and row_a != null and row_b != null:
		assert_false(_has_flag_mark(dossier),
			"Selected save dossier replaces MenuFlagMark with the course picture")
		var dossier_pic := dossier.find_child("Picture", true, false) as TextureRect
		assert_not_null(dossier_pic)
		if dossier_pic != null:
			assert_eq(dossier_pic.texture, expected_hawaii,
				"Newest save starts selected with its Hawaii HUD picture")
		row_b.pressed.emit()
		await process_frames(2)
		dossier_pic = dossier.find_child("Picture", true, false) as TextureRect
		assert_not_null(dossier_pic)
		if dossier_pic != null:
			assert_eq(dossier_pic.texture, expected_scotland,
				"Selecting Scotland save swaps the dossier picture to Scotland's HUD picture")

	# Phone compact layout scales the pictures to 1x (32x32), matching CourseLocationBanner.
	await resize_window(Vector2i(390, 844))
	await process_frames(3)
	row_b = panel.find_child("SaveRow_%s" % TEST_PICTURE_SAVE_B, true, false) as Button
	dossier = panel.find_child("LoadDossier", true, false)
	if row_b != null and dossier != null:
		var compact_scotland := CourseLocationPicture.texture_for_location("scotland", CourseTheme.Type.LINKS, 1)
		var row_pic := row_b.find_child("Picture", true, false) as TextureRect
		var compact_dossier_pic := dossier.find_child("Picture", true, false) as TextureRect
		if row_pic != null and compact_dossier_pic != null:
			assert_eq(row_pic.texture, compact_scotland, "Phone save row uses 1x location picture")
			assert_eq(compact_dossier_pic.texture, compact_scotland, "Phone dossier uses 1x location picture")

	_delete_test_saves()
	WorldMap.active_location_id = previous_location
	GameManager.current_theme = previous_theme
	await resize_window(original_window)


# ---------------------------------------------------------------------------
# Settings top-right header category buttons
# ---------------------------------------------------------------------------

## The four categories live in the header's top right corner, the way the
## Course Map puts its mode buttons there, instead of a rail beside the cards or
## a strip over them. What is checked: the buttons are inside the shared
## ScreenHeader at every window size, they read Audio / Display / Controls /
## Data, the page under them shows one category at a time, and the old rail and
## strip are gone.
func test_settings_category_buttons_sit_in_the_top_right_header_like_course_map() -> void:
	var original_window := get_window().size
	for window_size in SETTINGS_WINDOWS:
		var menu: SettingsMenu = await _open_settings(window_size)
		var header := menu.get_node_or_null("SettingsFrame/SettingsPage/ScreenHeader") as HBoxContainer
		assert_not_null(header, "%s: the shared ScreenHeader leads the page" % window_size)
		if header == null:
			menu.free()
			continue
		var actions := header.get_node_or_null("HeaderActions") as HBoxContainer
		var tabs := header.get_node_or_null("HeaderActions/CategoryTabs") as HBoxContainer
		assert_not_null(actions, "%s: HeaderActions sit in the header like CourseMapScreen" % window_size)
		assert_not_null(tabs, "%s: HeaderActions carry the CategoryTabs" % window_size)
		assert_null(menu.find_child("CategoryNavigation", true, false),
			"%s: the category rail is gone" % window_size)
		assert_null(menu.find_child("CategoryStrip", true, false),
			"%s: the category strip is gone" % window_size)
		var labels: Array[String] = []
		for category in SettingsMenu.Category.values():
			var button := menu.find_child("Category_%s" % menu._category_key(category), true, false) as Button
			assert_not_null(button, "%s: %s has a header button" % [window_size, menu._category_name(category)])
			if button == null:
				continue
			labels.append(button.text)
			assert_true(header.is_ancestor_of(button), "%s: %s lives in the ScreenHeader" % [
				window_size, button.text])
			assert_true(button.toggle_mode, "%s: %s is a page button" % [window_size, button.text])
			assert_eq(button.get_theme_font("font"), CourseMapStyle.SUBTITLE_FONT,
				"%s: %s uses the Course Map choice font" % [window_size, button.text])
			assert_eq(button.button_pressed, category == menu._category,
				"%s: only the open page's button is pressed" % window_size)
			var rect := button.get_global_rect()
			assert_gte(rect.size.y, 36.0, "%s: %s is a touch-sized target" % [window_size, button.text])
			assert_gte(rect.size.x, 36.0, "%s: %s is a touch-sized target" % [window_size, button.text])
			assert_true(rect_within(rect, Rect2(Vector2.ZERO, Vector2(window_size))),
				"%s: %s is on the screen" % [window_size, button.text])
			assert_gt(rect.position.x, float(window_size.x) * 0.4,
				"%s: %s sits in the top right corner" % [window_size, button.text])
			assert_lt(rect.position.y, 120.0,
				"%s: %s sits in the top right corner" % [window_size, button.text])
		assert_eq(labels, ["Audio", "Display", "Controls", "Data"],
			"%s: one word per page, in order" % window_size)
		var title := header.get_node_or_null("TitleBlock/Title") as Label
		assert_not_null(title, "%s: the header keeps its title" % window_size)
		if title != null and actions != null:
			assert_lte(title.get_global_rect().end.x, actions.get_global_rect().position.x + 1.0,
				"%s: the buttons do not overlap the title" % window_size)

		# Pressing a button swaps the page under the header and lights itself.
		var data_button := menu.find_child("Category_data", true, false) as Button
		if data_button != null:
			data_button.pressed.emit()
			await process_frames(3)
			assert_eq(menu._category, SettingsMenu.Category.DATA, "%s: Data opens its page" % window_size)
			var lit := menu.find_child("Category_data", true, false) as Button
			assert_not_null(lit)
			if lit != null:
				assert_true(lit.button_pressed, "%s: the Data button stays lit" % window_size)
			var content_title := menu.find_child("CategoryTitle", true, false) as Label
			assert_not_null(content_title, "%s: the page carries its own heading" % window_size)
		menu.free()
	await resize_window(original_window)


## The header's buttons are the only category chooser left: the settings card
## runs from under the header down to the window's bottom margin, with nothing
## above it and nothing beside it.
func test_settings_workspace_is_the_card_under_the_header() -> void:
	var original_window := get_window().size
	for window_size in SETTINGS_WINDOWS:
		var menu: SettingsMenu = await _open_settings(window_size)
		var page := menu.get_node_or_null("SettingsFrame/SettingsPage") as VBoxContainer
		assert_not_null(page, "%s: the page is built" % window_size)
		if page == null:
			menu.free()
			continue
		var rows: Array[String] = []
		for row in page.get_children():
			rows.append(str(row.name))
		assert_eq(rows, ["ScreenHeader", "SettingsWorkspace"],
			"%s: the page is the header over the workspace" % window_size)
		var workspace := page.get_node_or_null("SettingsWorkspace") as Control
		assert_not_null(workspace, "%s: the workspace is the settings card" % window_size)
		if workspace != null:
			assert_eq(workspace.name, "SettingsWorkspace")
			assert_not_null(workspace.find_child("SettingsContentScroll", true, false),
				"%s: the cards scroll inside the workspace" % window_size)
			assert_true(rect_within(workspace.get_global_rect(), menu.get_global_rect()),
				"%s: the workspace is on the screen" % window_size)
		menu.free()
	await resize_window(original_window)
