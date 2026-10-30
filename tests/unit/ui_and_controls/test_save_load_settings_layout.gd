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
