extends Node
## Run: godot --headless --path . res://tests/harness/save_settings_layout_harness.tscn
##
## Builds the Save / Load archive and the Settings office at phone, rotated
## phone, tablet and desktop window sizes and checks the arrangement each one
## gets: the right breakpoint, every visible action inside the window and at
## least a touch-sized target, no two actions overlapping, and no scrolling in
## the arrangements that promise to fit (desktop and rotated phone).
##
## Prints one PASS/FAIL line per check and exits non-zero on any failure.

const TAG_SAVE := "SAVE_LOAD"
const TAG_SETTINGS := "SETTINGS"
const MIN_TARGET := 36.0

var failures := 0

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", description])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _set_window(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)
	await _frames(4)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Two sizes are not enough to be sure the archive keeps its rows in view,
	# so the save shelf is seeded with a couple of checkpoints first.
	_seed_saves()

	var sizes := [
		[390, 844, "phone portrait"],
		[360, 640, "small phone"],
		[844, 390, "rotated phone"],
		[640, 360, "small rotated phone"],
		[768, 1024, "tablet portrait"],
		[1024, 768, "tablet landscape"],
		[1366, 657, "laptop browser window"],
		[1600, 1000, "desktop"],
		[2560, 1440, "large desktop"],
	]
	for entry in sizes:
		await _set_window(entry[0], entry[1])
		await _check_save_load(entry[0], entry[1], str(entry[2]), false)
		await _set_window(entry[0], entry[1])
		await _check_save_load(entry[0], entry[1], str(entry[2]), true)
		await _set_window(entry[0], entry[1])
		await _check_settings(entry[0], entry[1], str(entry[2]))

	await _check_behaviour()
	await _check_game_wiring()
	_remove_saves()
	print("SAVE_SETTINGS_LAYOUT: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

# =============================================================================
# BEHAVIOUR
# =============================================================================

## The controls do what they say: a checkpoint is written under the typed name,
## an existing name asks before it is replaced, a blank name is refused, and a
## setting toggle changes the live setting.
func _check_behaviour() -> void:
	await _set_window(1600, 1000)
	var path := "user://saves/layout_harness_checkpoint.save"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var panel := SaveLoadPanel.new()
	panel.allow_save = true
	panel.open_mode = SaveLoadPanel.ScreenMode.SAVE
	add_child(panel)
	await _frames(6)

	panel._save_name_input.text = "   "
	panel._on_save_pressed()
	_check(not FileAccess.file_exists(path) and panel._save_status_label.text.contains("name"),
		"a blank checkpoint name is refused with a hint")

	panel._save_name_input.text = "layout_harness_checkpoint/"
	panel._on_save_pressed()
	_check(FileAccess.file_exists(path), "a checkpoint is written under the cleaned name")
	_check(_find(panel, "ArchiveConfirmation") == null, "a new name saves without a confirmation")

	panel._save_name_input.text = "layout_harness_checkpoint"
	panel._on_save_pressed()
	var confirmation := _find(panel, "ArchiveConfirmation")
	_check(confirmation != null, "saving over an existing name asks for confirmation first")
	if confirmation != null:
		panel._close_confirmation()
	await _frames(2)

	panel.queue_free()
	await _frames(2)

	# Settings: a toggle changes the live setting and writes it back.
	var was_inverted := GameManager.invert_zoom_scroll
	var menu := SettingsMenu.new()
	add_child(menu)
	await _frames(6)
	menu._select_category(SettingsMenu.Category.CONTROLS)
	await _frames(3)
	var toggle := _find(menu, "Toggle_invert_scroll_zoom") as CheckButton
	_check(toggle != null, "the invert-zoom toggle is on the Controls page")
	if toggle != null:
		toggle.button_pressed = not was_inverted
		await _frames(2)
		_check(GameManager.invert_zoom_scroll == (not was_inverted), "flipping the toggle changes the setting")
		# The toggle saved the flipped value straight away: put the player's
		# real setting back on disk too, not just in memory.
		GameManager.invert_zoom_scroll = was_inverted
		menu._save_controls_settings()
	menu.queue_free()
	await _frames(2)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## The real game opens these screens from the right places: the title screen's
## Load is load-only, and the pause menu's Save and Load open the matching mode
## with the course camera wired in.
func _check_game_wiring() -> void:
	await _set_window(1600, 1000)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _frames(6)

	main._on_main_menu_load()
	await _frames(3)
	var title_panel := main.get_node_or_null("UI/HUD/SaveLoadPanel") as SaveLoadPanel
	_check(title_panel != null and not title_panel.allow_save and title_panel._mode == SaveLoadPanel.ScreenMode.LOAD,
		"the title screen's Load opens the archive in load-only mode")
	if title_panel != null:
		title_panel.queue_free()
	await _frames(2)

	main._show_save_load_panel(true, SaveLoadPanel.ScreenMode.SAVE)
	await _frames(3)
	var pause_panel := main.get_node_or_null("UI/HUD/SaveLoadPanel") as SaveLoadPanel
	_check(pause_panel != null and pause_panel.allow_save and pause_panel._mode == SaveLoadPanel.ScreenMode.SAVE,
		"the pause menu's Save opens the archive in save mode")
	_check(pause_panel != null and pause_panel.camera == main.camera,
		"the pause archive keeps the course camera for looking around")
	if pause_panel != null:
		pause_panel.queue_free()
	await _frames(2)
	main.queue_free()
	await _frames(2)

# =============================================================================
# SAVE / LOAD
# =============================================================================

func _check_save_load(width: int, height: int, label: String, save_mode: bool) -> void:
	var tag := "%s %s %dx%d" % [TAG_SAVE, "save" if save_mode else "load", width, height]
	var panel := SaveLoadPanel.new()
	panel.allow_save = true
	panel.open_mode = SaveLoadPanel.ScreenMode.SAVE if save_mode else SaveLoadPanel.ScreenMode.LOAD
	add_child(panel)
	await _frames(6)

	var view := Rect2(Vector2.ZERO, Vector2(width, height))
	var mode := SaveLoadPanel.layout_mode_for(Vector2(width, height))
	_check(panel._layout_mode == mode, "%s: %s uses breakpoint %d (got %d)" % [tag, label, mode, panel._layout_mode])

	var buttons := _visible_buttons(panel)
	_check(not buttons.is_empty(), "%s: has actions on screen" % tag)
	_check_targets(tag, buttons, view)
	_check_no_overlap(tag, buttons)
	_check_fits_without_scroll(tag, panel, width, height, mode)

	if save_mode:
		_check(panel.get_node_or_null("ArchiveFrame/ArchivePage") != null, "%s: the save page is built" % tag)
		_check(_find(panel, "SaveNameInput") != null, "%s: the name field is shown on the save screen" % tag)
		_check(_find(panel, "SaveCheckpointButton") != null, "%s: the save action is shown" % tag)
	else:
		_check(_find(panel, "LoadSelectedButton") != null, "%s: the load action is shown for a selected save" % tag)
		_check(_find(panel, "SaveNameInput") == null, "%s: the name field is not shown on the load screen" % tag)

	panel.queue_free()
	await _frames(2)

func _seed_saves() -> void:
	# Two checkpoints in the archive so the list has rows to lay out.
	for save_id in ["layout_harness_one", "layout_harness_two"]:
		var file := FileAccess.open("user://saves/%s.save" % save_id, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({
				"timestamp": "2026-10-02T10:00:00",
				"holes": [{"hole_number": 1}, {"hole_number": 2}],
				"game_state": {"course_name": "Harness Links", "current_day": 9, "money": 120000},
			}))
			file.close()

func _remove_saves() -> void:
	for save_id in ["layout_harness_one", "layout_harness_two"]:
		var path := "user://saves/%s.save" % save_id
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

# =============================================================================
# SETTINGS
# =============================================================================

func _check_settings(width: int, height: int, label: String) -> void:
	var tag := "%s %s %dx%d" % [TAG_SETTINGS, label, width, height]
	var menu := SettingsMenu.new()
	add_child(menu)
	await _frames(6)
	var view := Rect2(Vector2.ZERO, Vector2(width, height))
	var mode := SettingsMenu.layout_mode_for(Vector2(width, height))
	_check(menu._layout_mode == mode, "%s: uses breakpoint %d (got %d)" % [tag, mode, menu._layout_mode])

	var categories := 0
	for category in SettingsMenu.Category.values():
		var found := _find(menu, "Category_%s" % menu._category_key(category))
		if found != null:
			categories += 1
	_check(categories == 4, "%s: all four categories are reachable (%d)" % [tag, categories])

	var buttons := _visible_buttons(menu)
	_check_targets(tag, buttons, view)
	_check_no_overlap(tag, buttons)
	_check_fits_without_scroll(tag, menu, width, height, mode)

	# Walk every category at this size: each must build and stay on screen.
	for category in SettingsMenu.Category.values():
		menu._select_category(category)
		await _frames(3)
		var page_buttons := _visible_buttons(menu)
		_check_targets("%s %s" % [tag, menu._category_name(category)], page_buttons, view)
		_check(_find(menu, "CategoryContent") != null, "%s: %s content is built" % [tag, menu._category_name(category)])

	menu.queue_free()
	await _frames(2)

# =============================================================================
# SHARED CHECKS
# =============================================================================

## Every visible button is big enough to tap and sits inside the window. Rows
## inside a scroll container may legitimately sit below the fold, so only the
## horizontal extent is checked for them.
func _check_targets(tag: String, buttons: Array, view: Rect2) -> void:
	var too_small: Array = []
	var outside: Array = []
	for button in buttons:
		var rect: Rect2 = button.get_global_rect()
		if rect.size.y < MIN_TARGET - 0.5 or rect.size.x < MIN_TARGET - 0.5:
			too_small.append("%s %s" % [_describe(button), rect.size])
		var in_scroll := _inside_scroll(button)
		if in_scroll:
			if rect.position.x < view.position.x - 1.0 or rect.end.x > view.end.x + 1.0:
				outside.append("%s %s" % [_describe(button), rect])
		elif not _within(rect, view):
			outside.append("%s %s" % [_describe(button), rect])
	_check(too_small.is_empty(), "%s: every action is at least %d px (%s)" % [tag, MIN_TARGET, too_small])
	_check(outside.is_empty(), "%s: every action is inside the window (%s)" % [tag, outside])

## Two actions overlap when their visible parts do. A row scrolled out of view
## is clipped by its ScrollContainer, so the clipped rect is what counts.
func _check_no_overlap(tag: String, buttons: Array) -> void:
	var overlaps: Array = []
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a := _visible_rect(buttons[i])
			var b := _visible_rect(buttons[j])
			if a.size.x > 0.0 and a.size.y > 0.0 and b.size.x > 0.0 and b.size.y > 0.0 and a.intersects(b, false):
				overlaps.append("%s %s / %s %s" % [_describe(buttons[i]), a, _describe(buttons[j]), b])
	_check(overlaps.is_empty(), "%s: no two actions overlap (%s)" % [tag, overlaps])

func _visible_rect(node: Control) -> Rect2:
	var rect := node.get_global_rect()
	var current := node.get_parent()
	while current != null:
		if current is ScrollContainer:
			rect = rect.intersection((current as Control).get_global_rect())
		current = current.get_parent()
	return rect

## Desktop and rotated-phone arrangements promise to fit the window without
## scrolling; the tall ones may scroll their lists.
func _check_fits_without_scroll(tag: String, root: Control, width: int, height: int, mode: int) -> void:
	var must_fit := mode == SaveLoadPanel.LayoutMode.DESKTOP or mode == SaveLoadPanel.LayoutMode.LANDSCAPE
	if root is SettingsMenu:
		must_fit = mode == SettingsMenu.LayoutMode.DESKTOP or mode == SettingsMenu.LayoutMode.LANDSCAPE
	var frame := root.get_node_or_null("ArchiveFrame")
	if frame == null:
		frame = root.get_node_or_null("SettingsFrame")
	if frame == null:
		_check(false, "%s: the page frame exists" % tag)
		return
	var needed: Vector2 = frame.get_combined_minimum_size()
	_check(needed.x <= width + 1.0, "%s: the page is no wider than the window (needs %.0f)" % [tag, needed.x])
	if must_fit:
		_check(needed.y <= height + 1.0, "%s: the page fits without scrolling (needs %.0f of %d)" % [tag, needed.y, height])

func _visible_buttons(root: Node) -> Array:
	var found: Array = []
	for node in _all_nodes(root):
		if node is Button and (node as Button).is_visible_in_tree() and (node as Button).get_global_rect().size.x > 0.0:
			found.append(node)
	return found

func _inside_scroll(node: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current is ScrollContainer:
			return true
		current = current.get_parent()
	return false

func _find(root: Node, node_name: String) -> Node:
	for node in _all_nodes(root):
		if node.name == node_name:
			return node
	return null

func _all_nodes(root: Node) -> Array:
	var found: Array = [root]
	for child in root.get_children():
		found.append_array(_all_nodes(child))
	return found

func _describe(node: Node) -> String:
	if node is Button:
		return str((node as Button).text).replace("\n", " ")
	return str(node.name)

func _within(inner: Rect2, outer: Rect2, slack: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - slack \
		and inner.position.y >= outer.position.y - slack \
		and inner.end.x <= outer.end.x + slack \
		and inner.end.y <= outer.end.y + slack
