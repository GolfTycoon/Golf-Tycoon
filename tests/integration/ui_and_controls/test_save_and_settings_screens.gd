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
			layout == SaveLoadPanel.LayoutMode.DESKTOP or layout == SaveLoadPanel.LayoutMode.LANDSCAPE)
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
		var categories := 0
		for category in SettingsMenu.Category.values():
			if menu.find_child("Category_%s" % menu._category_key(category), true, false):
				categories += 1
		assert_eq(categories, 3, "%s: all three categories are in reach" % tag)
		_assert_targets(tag, menu, size)
		_assert_fits(tag, menu.get_node_or_null("SettingsFrame"), size,
			layout == SettingsMenu.LayoutMode.DESKTOP or layout == SettingsMenu.LayoutMode.LANDSCAPE)
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
