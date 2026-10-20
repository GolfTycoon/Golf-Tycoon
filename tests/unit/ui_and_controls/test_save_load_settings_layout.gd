extends GameTest
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
