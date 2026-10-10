extends GutTest
## Unit tests for the redesigned Save / Load archive and the Settings office.
##
## Both screens are built from code, so the parts worth pinning down without a
## window are the pure ones: which arrangement a window size asks for, how a
## typed save name is cleaned before it becomes a file name, and the metadata
## the archive lists each save with.

const SAVE_DIR_PATH := "user://saves/"
const TEST_SAVE := "layout_test_checkpoint"

func after_each() -> void:
	var path := SAVE_DIR_PATH + TEST_SAVE + ".save"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# --- Save / Load breakpoints -------------------------------------------------

func test_save_load_phone_sizes_use_the_stacked_archive() -> void:
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(390, 844)), SaveLoadPanel.LayoutMode.PHONE, "phone portrait")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(320, 568)), SaveLoadPanel.LayoutMode.PHONE, "smallest phone")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(599, 800)), SaveLoadPanel.LayoutMode.PHONE, "narrow tall window")

func test_save_load_rotated_phone_keeps_two_panes() -> void:
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(844, 390)), SaveLoadPanel.LayoutMode.LANDSCAPE, "rotated phone")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(640, 360)), SaveLoadPanel.LayoutMode.LANDSCAPE, "small rotated phone")

func test_save_load_tablet_and_desktop_breakpoints() -> void:
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(768, 1024)), SaveLoadPanel.LayoutMode.TABLET, "tablet portrait")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(1024, 768)), SaveLoadPanel.LayoutMode.TABLET, "tablet landscape")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(1600, 1000)), SaveLoadPanel.LayoutMode.DESKTOP, "reference desktop")
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(2560, 1440)), SaveLoadPanel.LayoutMode.DESKTOP, "large desktop")

func test_save_load_desktop_needs_its_minimum_size() -> void:
	var w := SaveLoadPanel.DESKTOP_MIN_WIDTH
	var h := SaveLoadPanel.DESKTOP_MIN_HEIGHT
	assert_eq(SaveLoadPanel.layout_mode_for(Vector2(w, h)), SaveLoadPanel.LayoutMode.DESKTOP)
	assert_ne(SaveLoadPanel.layout_mode_for(Vector2(w, h - 1.0)), SaveLoadPanel.LayoutMode.DESKTOP, "one pixel short")
	assert_ne(SaveLoadPanel.layout_mode_for(Vector2(w - 1.0, h)), SaveLoadPanel.LayoutMode.DESKTOP, "one pixel narrow")

# --- Settings breakpoints ----------------------------------------------------

func test_settings_breakpoints_cover_every_device() -> void:
	assert_eq(SettingsMenu.layout_mode_for(Vector2(390, 844)), SettingsMenu.LayoutMode.PHONE, "phone portrait")
	assert_eq(SettingsMenu.layout_mode_for(Vector2(844, 390)), SettingsMenu.LayoutMode.LANDSCAPE, "rotated phone")
	assert_eq(SettingsMenu.layout_mode_for(Vector2(768, 1024)), SettingsMenu.LayoutMode.TABLET, "tablet portrait")
	assert_eq(SettingsMenu.layout_mode_for(Vector2(1024, 768)), SettingsMenu.LayoutMode.TABLET, "tablet landscape")
	assert_eq(SettingsMenu.layout_mode_for(Vector2(1600, 1000)), SettingsMenu.LayoutMode.DESKTOP, "reference desktop")

## Every size gets exactly one arrangement, and the wide ones only start at
## their documented minimums.
func test_settings_breakpoints_respect_their_minimums() -> void:
	for x in range(300, 2700, 97):
		for y in range(300, 1600, 89):
			var size := Vector2(x, y)
			match SettingsMenu.layout_mode_for(size):
				SettingsMenu.LayoutMode.DESKTOP:
					assert_true(size.x >= SettingsMenu.DESKTOP_MIN_WIDTH and size.y >= SettingsMenu.DESKTOP_MIN_HEIGHT,
						"%s qualifies for DESKTOP" % size)
				SettingsMenu.LayoutMode.TABLET:
					assert_true(size.x >= SettingsMenu.TABLET_MIN_WIDTH and size.y >= SettingsMenu.TABLET_MIN_HEIGHT,
						"%s qualifies for TABLET" % size)
				SettingsMenu.LayoutMode.LANDSCAPE:
					assert_true(size.x > size.y, "%s is wider than tall for LANDSCAPE" % size)

# --- Save names --------------------------------------------------------------

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

# --- Archive metadata --------------------------------------------------------

## The archive shows money, holes and difficulty on each card, so the listing
## has to carry them even though the save itself stores them elsewhere.
func test_save_list_carries_the_archive_details() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR_PATH)
	var data := {
		"timestamp": "2026-10-01T09:30:00",
		"game_state": {
			"course_name": "Layout Test Links",
			"current_day": 42,
			"money": 250000,
			"reputation": 61.5,
			"difficulty": "hard",
			"theme": "links",
		},
		"holes": [{"hole_number": 1}, {"hole_number": 2}, {"hole_number": 3}],
	}
	var file := FileAccess.open(SAVE_DIR_PATH + TEST_SAVE + ".save", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

	var found: Dictionary = {}
	for entry in SaveManager.get_save_list():
		if entry.get("name", "") == TEST_SAVE:
			found = entry
	assert_false(found.is_empty(), "the written save is listed")
	assert_eq(found.get("course_name", ""), "Layout Test Links")
	assert_eq(int(found.get("day", 0)), 42)
	assert_eq(int(found.get("money", 0)), 250000)
	assert_eq(int(found.get("hole_count", 0)), 3)
	assert_almost_eq(float(found.get("reputation", 0.0)), 61.5, 0.001)
	assert_eq(found.get("difficulty", ""), "hard")
	assert_eq(found.get("theme", ""), "links")

func test_save_list_tolerates_missing_fields() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR_PATH)
	var file := FileAccess.open(SAVE_DIR_PATH + TEST_SAVE + ".save", FileAccess.WRITE)
	file.store_string(JSON.stringify({"holes": null, "game_state": {"money": "not a number"}}))
	file.close()

	var found: Dictionary = {}
	for entry in SaveManager.get_save_list():
		if entry.get("name", "") == TEST_SAVE:
			found = entry
	assert_false(found.is_empty(), "a sparse save is still listed")
	assert_eq(int(found.get("money", -1)), 0, "a non-numeric balance reads as zero")
	assert_eq(int(found.get("hole_count", -1)), 0, "missing holes read as none")
	assert_eq(found.get("course_name", ""), "Unknown", "a missing course name keeps the old fallback")
