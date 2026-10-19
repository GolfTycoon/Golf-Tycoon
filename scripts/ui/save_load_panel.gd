extends Control
class_name SaveLoadPanel
## Responsive save desk and course archive.
##
## The Save and Load flows share the same archive, but each has its own clear
## primary action and selected-slot dossier. Desktop uses a two-column desk;
## tablets and phones reflow the checkpoint / dossier above a touch-friendly
## save shelf, and a rotated phone keeps the two panes side by side.

signal panel_closed
signal quit_to_menu_requested

enum ScreenMode { SAVE, LOAD }
enum LayoutMode { DESKTOP, TABLET, LANDSCAPE, PHONE }

const DESKTOP_MIN_WIDTH := 1180.0
const DESKTOP_MIN_HEIGHT := 700.0
const TABLET_MIN_WIDTH := 700.0
const TABLET_MIN_HEIGHT := 620.0
const MAX_SAVE_NAME_LENGTH := 40

const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_RAISED := MenuStyle.RAIL_BG
const COLOR_INSET := MenuStyle.INSET_BG
const COLOR_BORDER := UIConstants.COLOR_BORDER
const COLOR_TEXT := MenuStyle.TITLE_COLOR
const COLOR_MUTED := UIConstants.COLOR_TEXT_DIM
const COLOR_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

## Set before adding the panel to the tree. The title screen only opens the
## archive; a pause-session panel can switch between saving and loading.
var open_mode: int = ScreenMode.LOAD
var allow_save: bool = true
var camera: IsometricCamera = null

var _mode: int = ScreenMode.LOAD
var _layout_mode: int = LayoutMode.PHONE
var _built_size := Vector2.ZERO
var _selected_save_name := ""
var _draft_name := ""
var _saves: Array[Dictionary] = []
var _save_name_input: LineEdit
var _save_status_label: Label
var _save_list_container: VBoxContainer
var _save_count_label: Label
var _load_detail_host: VBoxContainer
var _confirmation_overlay: Control
var _header_title: Label
var _header_subtitle: Label

func _ready() -> void:
	name = "SaveLoadPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mode = ScreenMode.SAVE if allow_save and open_mode == ScreenMode.SAVE else ScreenMode.LOAD
	if _draft_name.is_empty():
		_draft_name = _initial_save_name()
	if has_node("/root/Screen") and not Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.connect(_on_screen_changed)
	_refresh_save_cache()
	_ensure_selection()
	_build()

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)

## Pure layout decision, kept public so phone, tablet and desktop breakpoints
## can be checked without constructing a window.
static func layout_mode_for(view: Vector2) -> int:
	if view.x >= DESKTOP_MIN_WIDTH and view.y >= DESKTOP_MIN_HEIGHT and view.x > view.y:
		return LayoutMode.DESKTOP
	if view.x >= TABLET_MIN_WIDTH and view.y >= TABLET_MIN_HEIGHT:
		return LayoutMode.TABLET
	if view.x > view.y and view.y < TABLET_MIN_HEIGHT:
		return LayoutMode.LANDSCAPE
	return LayoutMode.PHONE

## Remove filesystem-sensitive characters while keeping ordinary spaces,
## punctuation and non-English course names. A blank result is rejected by the
## save action; path separators and traversal-only names can never reach disk.
static func sanitize_save_name(raw_name: String) -> String:
	var cleaned := ""
	for index in raw_name.strip_edges().length():
		var character := raw_name.strip_edges().substr(index, 1)
		if character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r"]:
			continue
		cleaned += character
	cleaned = cleaned.strip_edges()
	while cleaned.begins_with("."):
		cleaned = cleaned.trim_prefix(".")
	while cleaned.ends_with("."):
		cleaned = cleaned.trim_suffix(".")
	cleaned = cleaned.substr(0, mini(cleaned.length(), MAX_SAVE_NAME_LENGTH)).strip_edges()
	if cleaned == "." or cleaned == "..":
		return ""
	return cleaned

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

func _on_screen_changed(window_size: Vector2, _world_scale: float) -> void:
	var new_layout := layout_mode_for(window_size)
	var remeasure := absf(window_size.x - _built_size.x) > maxf(120.0, _built_size.x * 0.16) \
		or absf(window_size.y - _built_size.y) > maxf(100.0, _built_size.y * 0.16)
	if new_layout != _layout_mode or remeasure:
		_capture_build_state()
		_build()

func _capture_build_state() -> void:
	if is_instance_valid(_save_name_input):
		_draft_name = _save_name_input.text

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_save_name_input = null
	_save_status_label = null
	_save_list_container = null
	_save_count_label = null
	_load_detail_host = null
	_header_title = null
	_header_subtitle = null
	_layout_mode = layout_mode_for(_window_size())
	_built_size = _window_size()

	var scrim := ColorRect.new()
	scrim.name = "ArchiveScrim"
	scrim.color = Color(0.006, 0.022, 0.016, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var frame := MarginContainer.new()
	frame.name = "ArchiveFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var padding := _outer_padding(_layout_mode, _built_size)
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, padding)
	add_child(frame)

	var page := VBoxContainer.new()
	page.name = "ArchivePage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", _page_gap(_layout_mode))
	frame.add_child(page)
	page.add_child(_build_header(_layout_mode))
	page.add_child(_build_mode_switch(_layout_mode))
	page.add_child(_build_workspace(_layout_mode, _built_size))
	page.add_child(_build_footer(_layout_mode))

func _outer_padding(mode: int, view: Vector2) -> int:
	match mode:
		LayoutMode.DESKTOP:
			return int(clampf(minf(view.x, view.y) * 0.026, 22.0, 38.0))
		LayoutMode.TABLET:
			return int(clampf(minf(view.x, view.y) * 0.023, 14.0, 26.0))
		LayoutMode.LANDSCAPE:
			return 6
		_:
			return int(clampf(view.x * 0.030, 9.0, 16.0))

func _page_gap(mode: int) -> int:
	match mode:
		LayoutMode.DESKTOP: return 13
		LayoutMode.TABLET: return 10
		LayoutMode.LANDSCAPE: return 5
		_: return 8

func _build_header(mode: int) -> Control:
	var compact := mode == LayoutMode.LANDSCAPE or mode == LayoutMode.PHONE
	var header := HBoxContainer.new()
	header.name = "ArchiveHeader"
	header.custom_minimum_size.y = (44.0 if mode == LayoutMode.LANDSCAPE else 52.0) if compact else 74.0
	header.add_theme_constant_override("separation", 10 if not compact else 6)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "‹ Back" if not compact else "‹"
	back.tooltip_text = "Return to the previous screen"
	back.custom_minimum_size = Vector2(86.0 if not compact else 46.0, 40.0 if mode == LayoutMode.LANDSCAPE else 44.0)
	back.add_theme_font_size_override("font_size", 14 if not compact else 18)
	_paint_secondary_button(back, false)
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)

	var mark := MenuFlagMark.new()
	mark.name = "GolfMark"
	mark.mark_size = 46.0 if mode == LayoutMode.DESKTOP else (38.0 if mode == LayoutMode.TABLET else (30.0 if mode == LayoutMode.PHONE else 26.0))
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mark)

	var title_box := VBoxContainer.new()
	title_box.name = "TitleBlock"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 0)
	var kicker := _label("THE CLUBHOUSE ARCHIVE", 10 if compact else 11, COLOR_GOLD)
	kicker.name = "Kicker"
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	_header_title = _label("", 20 if compact else 28, COLOR_TEXT)
	_header_title.name = "Title"
	title_row.add_child(_header_title)
	title_box.add_child(kicker)
	title_box.add_child(title_row)
	# The compact arrangements have no room for the subtitle, so it is only
	# built where it is shown: a label left out of the tree is never freed.
	if not compact:
		_header_subtitle = _label("A little care now makes it easy to pick up the perfect round later.",
			13, COLOR_MUTED)
		_header_subtitle.name = "Subtitle"
		title_box.add_child(_header_subtitle)
	header.add_child(title_box)

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "×"
	close.tooltip_text = "Close archive"
	close.custom_minimum_size = Vector2(46, 40 if mode == LayoutMode.LANDSCAPE else 46)
	close.add_theme_font_size_override("font_size", 23)
	_paint_secondary_button(close, false)
	close.pressed.connect(_on_back_pressed)
	header.add_child(close)
	_update_header_copy()
	return header

func _update_header_copy() -> void:
	if not is_instance_valid(_header_title):
		return
	if _mode == ScreenMode.SAVE:
		_header_title.text = "Save your course"
	else:
		_header_title.text = "Load a course"

func _build_mode_switch(mode: int) -> Control:
	var bar := HBoxContainer.new()
	bar.name = "ArchiveModeSwitch"
	bar.add_theme_constant_override("separation", 6)
	bar.custom_minimum_size.y = 40.0 if mode == LayoutMode.LANDSCAPE else 46.0
	var surface_pad := 3 if mode == LayoutMode.LANDSCAPE else 5
	if not allow_save:
		var load_only := PanelContainer.new()
		load_only.name = "LoadOnlyLabel"
		load_only.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_only.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_RAISED,
			MenuStyle.with_alpha(COLOR_GOLD, 0.30), MenuStyle.CARD_RADIUS, 12, 5, 1))
		var label := _label("LOAD A SAVED COURSE", 11 if mode == LayoutMode.PHONE else 12, COLOR_GOLD)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		load_only.add_child(label)
		bar.add_child(load_only)
		return bar

	var switch_surface := PanelContainer.new()
	switch_surface.name = "ModeSegmentSurface"
	switch_surface.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	switch_surface.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_RAISED,
		MenuStyle.with_alpha(COLOR_BORDER, 0.45), MenuStyle.CARD_RADIUS + 2, surface_pad, surface_pad, 1))
	bar.add_child(switch_surface)
	var segments := HBoxContainer.new()
	segments.add_theme_constant_override("separation", 5)
	switch_surface.add_child(segments)
	for entry in [[ScreenMode.SAVE, "Save progress", "Create or replace a checkpoint"],
			[ScreenMode.LOAD, "Load course", "Choose a saved clubhouse"]]:
		var target_mode: int = entry[0]
		var button := Button.new()
		button.name = "SaveMode" if target_mode == ScreenMode.SAVE else "LoadMode"
		button.text = str(entry[1])
		button.tooltip_text = str(entry[2])
		button.toggle_mode = true
		button.button_pressed = _mode == target_mode
		button.custom_minimum_size = Vector2(150 if mode == LayoutMode.DESKTOP else 128, 36 if mode == LayoutMode.LANDSCAPE else 40)
		button.add_theme_font_size_override("font_size", 12 if mode == LayoutMode.PHONE else 13)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		MenuStyle.paint_choice(button, COLOR_MINT, 8)
		button.add_theme_color_override("font_color", COLOR_MUTED)
		button.add_theme_color_override("font_hover_color", COLOR_TEXT)
		button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
		button.pressed.connect(_set_mode.bind(target_mode))
		segments.add_child(button)
	return bar

func _build_workspace(mode: int, view: Vector2) -> Control:
	var split := _uses_split_workspace(mode, view)
	var body: BoxContainer
	if split:
		body = HBoxContainer.new()
		body.name = "SplitWorkspace"
		body.add_theme_constant_override("separation", 12 if mode == LayoutMode.DESKTOP else 8)
	else:
		body = VBoxContainer.new()
		body.name = "StackedWorkspace"
		body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var focus := _build_focus_card(mode, view)
	var archive := _build_archive_card(mode)
	focus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus.size_flags_vertical = Control.SIZE_EXPAND_FILL
	archive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	archive.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if split:
		focus.custom_minimum_size.x = _focus_width(mode, view)
		focus.size_flags_stretch_ratio = 0.88 if mode == LayoutMode.LANDSCAPE else 0.92
		archive.size_flags_stretch_ratio = 1.38
		body.add_child(focus)
		body.add_child(archive)
	else:
		focus.custom_minimum_size.y = _focus_height(mode, view)
		body.add_child(focus)
		body.add_child(archive)
	return body

func _uses_split_workspace(mode: int, view: Vector2) -> bool:
	if mode == LayoutMode.DESKTOP or mode == LayoutMode.LANDSCAPE:
		return true
	return mode == LayoutMode.TABLET and view.x > view.y

func _focus_width(mode: int, view: Vector2) -> float:
	if mode == LayoutMode.LANDSCAPE:
		return clampf(view.x * 0.39, 275.0, 350.0)
	if mode == LayoutMode.TABLET:
		return clampf(view.x * 0.40, 320.0, 420.0)
	return clampf(view.x * 0.34, 370.0, 500.0)

func _focus_height(mode: int, view: Vector2) -> float:
	if mode == LayoutMode.TABLET:
		return clampf(view.y * 0.31, 205.0, 286.0)
	return clampf(view.y * 0.31, 184.0, 250.0)

func _build_focus_card(mode: int, view: Vector2) -> PanelContainer:
	var panel := _make_card(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_GOLD, 0.30), MenuStyle.CARD_RADIUS + 2)
	panel.name = "SaveWorkspace" if _mode == ScreenMode.SAVE else "LoadDossier"
	var margin := MarginContainer.new()
	var pad := 18 if mode == LayoutMode.DESKTOP else (14 if mode == LayoutMode.TABLET else 11)
	_set_margins(margin, pad)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.name = "FocusContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6 if mode == LayoutMode.LANDSCAPE else 11)
	margin.add_child(content)

	if _mode == ScreenMode.SAVE:
		_populate_save_workspace(content, mode)
	else:
		_load_detail_host = content
		_populate_load_dossier(content, mode, view)
	return panel

func _populate_save_workspace(content: VBoxContainer, mode: int) -> void:
	var compact := mode == LayoutMode.LANDSCAPE or mode == LayoutMode.PHONE
	content.add_child(_label("SAVE A CHECKPOINT", 10 if compact else 11, COLOR_GOLD))
	var heading := _label("Keep this course in the books.", 19 if mode == LayoutMode.DESKTOP else 16, COLOR_TEXT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.visible = mode != LayoutMode.LANDSCAPE
	content.add_child(heading)

	var course_card := _make_card(COLOR_RAISED, MenuStyle.with_alpha(COLOR_MINT, 0.20), 9)
	course_card.name = "LiveCourseSummary"
	var summary_margin := MarginContainer.new()
	_set_margins(summary_margin, 9 if compact else 12)
	course_card.add_child(summary_margin)
	var course_row := HBoxContainer.new()
	course_row.add_theme_constant_override("separation", 9)
	summary_margin.add_child(course_row)
	var mark := MenuFlagMark.new()
	mark.mark_size = (26 if mode == LayoutMode.LANDSCAPE else 30) if compact else 38
	course_row.add_child(mark)
	var course_info := VBoxContainer.new()
	course_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_info.alignment = BoxContainer.ALIGNMENT_CENTER
	course_info.add_theme_constant_override("separation", 1)
	var course_name := _label(GameManager.course_name, 13 if compact else 15, COLOR_TEXT)
	course_name.clip_text = true
	course_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	course_info.add_child(course_name)
	var day_info := _label("DAY %02d  ·  %s" % [GameManager.current_day, _format_money(GameManager.money)], 10 if compact else 11, COLOR_MUTED)
	day_info.clip_text = true
	course_info.add_child(day_info)
	course_row.add_child(course_info)
	content.add_child(course_card)

	var name_row := VBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	var name_label := _label("SAVE SLOT NAME", 9 if compact else 10, COLOR_QUIET)
	name_row.add_child(name_label)
	_save_name_input = LineEdit.new()
	_save_name_input.name = "SaveNameInput"
	_save_name_input.placeholder_text = "Name this checkpoint"
	_save_name_input.text = _draft_name
	_save_name_input.max_length = MAX_SAVE_NAME_LENGTH + 12
	_save_name_input.clear_button_enabled = true
	_save_name_input.custom_minimum_size.y = (38 if mode == LayoutMode.LANDSCAPE else 42) if compact else 46
	_save_name_input.add_theme_font_size_override("font_size", 13 if compact else 14)
	_save_name_input.add_theme_color_override("font_color", COLOR_TEXT)
	_save_name_input.add_theme_color_override("font_placeholder_color", COLOR_QUIET)
	_save_name_input.add_theme_stylebox_override("normal", _field_style(COLOR_INSET, COLOR_BORDER))
	_save_name_input.add_theme_stylebox_override("focus", _field_style(COLOR_INSET, COLOR_GOLD))
	_save_name_input.text_submitted.connect(func(_submitted: String): _on_save_pressed())
	_save_name_input.text_changed.connect(func(value: String): _draft_name = value)
	name_row.add_child(_save_name_input)
	content.add_child(name_row)

	_save_status_label = _label("Stored on this device · changes are never uploaded.", 10, COLOR_QUIET)
	_save_status_label.name = "SaveStatus"
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_status_label.visible = mode != LayoutMode.LANDSCAPE
	content.add_child(_save_status_label)

	var save_button := Button.new()
	save_button.name = "SaveCheckpointButton"
	save_button.text = "Save checkpoint  ›"
	save_button.custom_minimum_size.y = (40 if mode == LayoutMode.LANDSCAPE else 46) if compact else 52
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.add_theme_font_size_override("font_size", 14 if compact else 16)
	MenuStyle.paint_primary(save_button, 10)
	save_button.add_theme_color_override("font_color", MenuStyle.INK)
	save_button.add_theme_color_override("font_hover_color", MenuStyle.INK)
	save_button.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	save_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	save_button.pressed.connect(_on_save_pressed)
	content.add_child(save_button)


func _populate_load_dossier(content: VBoxContainer, mode: int, view: Vector2) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var compact := mode == LayoutMode.LANDSCAPE or mode == LayoutMode.PHONE
	var selected := _find_save(_selected_save_name)
	content.add_child(_label("SELECTED CLUBHOUSE", 10 if compact else 11, COLOR_GOLD))
	if selected.is_empty():
		content.add_child(_build_empty_dossier(compact))
		return

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	var mark := MenuFlagMark.new()
	mark.mark_size = (36 if mode == LayoutMode.LANDSCAPE else 44) if compact else 58
	title_row.add_child(mark)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 2)
	var slot_name := _label(str(selected.get("name", "Unknown save")), 15 if compact else 19, COLOR_TEXT)
	slot_name.name = "SelectedSaveName"
	slot_name.clip_text = true
	slot_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(slot_name)
	var course := _label(str(selected.get("course_name", "Unknown course")), 11 if compact else 13, COLOR_MUTED)
	course.name = "SelectedCourseName"
	course.clip_text = true
	course.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(course)
	title_row.add_child(title_box)
	content.add_child(title_row)

	var stats := HBoxContainer.new()
	stats.name = "SelectedSaveStats"
	stats.add_theme_constant_override("separation", 6)
	for stat in _save_stats(selected):
		stats.add_child(_build_stat_tile(str(stat[0]), str(stat[1]), compact, mode))
	content.add_child(stats)

	var timestamp := _label("LAST PLAYED  ·  %s" % _format_timestamp(str(selected.get("timestamp", ""))), 9 if compact else 10, COLOR_QUIET)
	timestamp.name = "SelectedSaveTimestamp"
	timestamp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timestamp.visible = mode != LayoutMode.LANDSCAPE
	content.add_child(timestamp)

	if mode != LayoutMode.LANDSCAPE:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.custom_minimum_size.y = 2
		content.add_child(spacer)

	var load_button := Button.new()
	load_button.name = "LoadSelectedButton"
	load_button.text = "Load this course  ›"
	load_button.custom_minimum_size.y = 40 if mode == LayoutMode.LANDSCAPE else (46 if compact else 52)
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.add_theme_font_size_override("font_size", 14 if compact else 16)
	MenuStyle.paint_primary(load_button, 10)
	load_button.add_theme_color_override("font_color", MenuStyle.INK)
	load_button.add_theme_color_override("font_hover_color", MenuStyle.INK)
	load_button.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	load_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	load_button.pressed.connect(_on_load_selected_pressed)
	content.add_child(load_button)

	var delete_button := Button.new()
	delete_button.name = "DeleteSelectedButton"
	delete_button.text = "Delete this save"
	delete_button.custom_minimum_size.y = 40
	delete_button.visible = mode != LayoutMode.LANDSCAPE
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.add_theme_font_size_override("font_size", 12)
	_paint_secondary_button(delete_button, true)
	delete_button.pressed.connect(_on_delete_selected_pressed)
	content.add_child(delete_button)
	if view.x < 390:
		delete_button.text = "Delete save"

func _build_empty_dossier(compact: bool) -> Control:
	var empty := VBoxContainer.new()
	empty.name = "EmptyLoadDossier"
	empty.alignment = BoxContainer.ALIGNMENT_CENTER
	empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty.add_theme_constant_override("separation", 7)
	var mark := MenuFlagMark.new()
	mark.mark_size = 42 if compact else 58
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	empty.add_child(mark)
	var title := _label("No saved courses yet", 15, COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_child(title)
	var copy := _label("Create a checkpoint from the Save screen and it will appear here.", 11, COLOR_MUTED)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.add_child(copy)
	return empty

func _build_stat_tile(caption: String, value: String, compact: bool, mode: int) -> PanelContainer:
	var tile := _make_card(COLOR_RAISED, MenuStyle.with_alpha(COLOR_BORDER, 0.30), 8)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	_set_margins(margin, (5 if mode == LayoutMode.LANDSCAPE else 8) if compact else 10)
	tile.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)
	var value_label := _label(value, 13 if compact else 16, COLOR_GOLD)
	value_label.name = "Value"
	value_label.clip_text = true
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(value_label)
	var caption_label := _label(caption, 8 if compact else 9, COLOR_QUIET)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption_label)
	return tile

func _save_stats(save_info: Dictionary) -> Array:
	var day := int(save_info.get("day", 0))
	var holes := int(save_info.get("hole_count", 0))
	var money := int(save_info.get("money", 0))
	return [
		["DAY", "%02d" % day if day > 0 else "—"],
		["HOLES", str(holes)],
		["BALANCE", _format_money_compact(money)],
	]

func _build_archive_card(mode: int) -> PanelContainer:
	var panel := _make_card(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_BORDER, 0.42), MenuStyle.CARD_RADIUS + 2)
	panel.name = "SaveArchive"
	var margin := MarginContainer.new()
	_set_margins(margin, 16 if mode == LayoutMode.DESKTOP else (12 if mode == LayoutMode.TABLET else 9))
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8 if mode == LayoutMode.LANDSCAPE else 11)
	margin.add_child(stack)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 8)
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_box.add_theme_constant_override("separation", 1)
	heading_box.add_child(_label("YOUR CLUBHOUSE LIBRARY", 10 if mode == LayoutMode.PHONE else 11, COLOR_GOLD))
	var title := _label("Saved courses", 17 if mode == LayoutMode.PHONE else 20, COLOR_TEXT)
	title.name = "ArchiveTitle"
	heading_box.add_child(title)
	heading_row.add_child(heading_box)
	_save_count_label = _label("", 10, COLOR_MUTED)
	_save_count_label.name = "SaveCount"
	_save_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_save_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading_row.add_child(_save_count_label)
	stack.add_child(heading_row)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "SaveListScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.follow_focus = true
	list_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stack.add_child(list_scroll)
	_save_list_container = VBoxContainer.new()
	_save_list_container.name = "SaveList"
	_save_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_list_container.add_theme_constant_override("separation", 7 if mode == LayoutMode.LANDSCAPE else 9)
	list_scroll.add_child(_save_list_container)
	_render_save_rows(mode)
	return panel

func _render_save_rows(mode: int) -> void:
	if not is_instance_valid(_save_list_container):
		return
	for child in _save_list_container.get_children():
		_save_list_container.remove_child(child)
		child.queue_free()
	if is_instance_valid(_save_count_label):
		_save_count_label.text = "%d SAVE%s" % [_saves.size(), "" if _saves.size() == 1 else "S"]
	if _saves.is_empty():
		var empty := _build_empty_archive(mode)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_save_list_container.add_child(empty)
		return
	for save_info in _saves:
		_save_list_container.add_child(_build_save_row(save_info, mode))

func _build_empty_archive(mode: int) -> Control:
	var box := PanelContainer.new()
	box.name = "EmptyArchive"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 144 if mode == LayoutMode.DESKTOP else 112
	box.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_RAISED,
		MenuStyle.with_alpha(COLOR_BORDER, 0.24), 12, 14, 12, 1))
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 5)
	box.add_child(content)
	var title := _label("The first page is still blank.", 14, COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var detail := _label("Save a course to keep your clubhouse ready for another day.", 11, COLOR_MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail)
	return box

func _build_save_row(save_info: Dictionary, mode: int) -> Button:
	var save_name := str(save_info.get("name", "Unknown save"))
	var compact := mode == LayoutMode.PHONE or mode == LayoutMode.LANDSCAPE
	var selected := save_name == _selected_save_name
	var row := Button.new()
	row.name = "SaveRow_%s" % save_name.validate_node_name()
	row.set_meta("save_name", save_name)
	row.toggle_mode = true
	row.button_pressed = selected
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 64 if mode == LayoutMode.LANDSCAPE else (70 if compact else 82)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "Select %s" % save_name
	MenuStyle.paint_choice(row, COLOR_MINT, 10)
	row.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_theme_color_override("font_hover_color", COLOR_TEXT)
	row.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	row.add_theme_color_override("font_disabled_color", COLOR_QUIET)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_margins(margin, 8 if compact else 12)
	row.add_child(margin)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)
	var mark := MenuFlagMark.new()
	mark.mark_size = 27 if compact else 34
	content.add_child(mark)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 2)
	var name_label := _label(save_name, 13 if compact else 15, COLOR_TEXT)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(name_label)
	var detail_text := "%s  ·  DAY %02d  ·  %s" % [
		str(save_info.get("course_name", "Unknown course")),
		int(save_info.get("day", 0)),
		_format_timestamp(str(save_info.get("timestamp", ""))),
	]
	var info_label := _label(detail_text, 9 if compact else 10, COLOR_MUTED)
	info_label.clip_text = true
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(info_label)
	content.add_child(text_box)

	var badge_text := "AUTO" if save_name.to_lower() == "autosave" else ("CURRENT" if save_name == SaveManager.current_save_name else "SELECT")
	var badge := _label(badge_text, 8 if compact else 9, COLOR_GOLD if selected or badge_text == "AUTO" else COLOR_QUIET)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size.x = 43 if compact else 52
	content.add_child(badge)
	row.pressed.connect(_on_save_selected.bind(save_name))
	return row

func _build_footer(mode: int) -> Control:
	var footer := HBoxContainer.new()
	footer.name = "ArchiveFooter"
	footer.custom_minimum_size.y = 40 if mode == LayoutMode.LANDSCAPE else 46
	footer.add_theme_constant_override("separation", 8)
	var note := _label("LOCAL SAVE  ·  %d COURSE%s" % [_saves.size(), "" if _saves.size() == 1 else "S"], 10, COLOR_QUIET)
	note.name = "ArchiveFooterNote"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.visible = mode == LayoutMode.DESKTOP or mode == LayoutMode.TABLET
	footer.add_child(note)
	if allow_save:
		var quit := Button.new()
		quit.name = "QuitToMenuButton"
		quit.text = "Quit to menu"
		quit.custom_minimum_size = Vector2(130 if mode != LayoutMode.PHONE else 0, 40)
		quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quit.add_theme_font_size_override("font_size", 11)
		_paint_secondary_button(quit, true)
		quit.pressed.connect(_on_quit_to_menu_pressed)
		footer.add_child(quit)
	var back := Button.new()
	back.name = "FooterBackButton"
	back.text = "Back to course" if allow_save else "Back"
	back.custom_minimum_size = Vector2(142 if mode != LayoutMode.PHONE else 0, 42)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL if mode == LayoutMode.PHONE else Control.SIZE_SHRINK_END
	back.add_theme_font_size_override("font_size", 12)
	MenuStyle.paint_primary(back, 9)
	back.add_theme_color_override("font_color", MenuStyle.INK)
	back.add_theme_color_override("font_hover_color", MenuStyle.INK)
	back.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	back.pressed.connect(_on_back_pressed)
	footer.add_child(back)
	return footer

func _set_mode(target_mode: int) -> void:
	if target_mode == ScreenMode.SAVE and not allow_save:
		return
	if _mode == target_mode:
		return
	_capture_build_state()
	_mode = target_mode
	_update_header_copy()
	_build()

func _on_save_selected(save_name: String) -> void:
	_selected_save_name = save_name
	if _mode == ScreenMode.SAVE and is_instance_valid(_save_name_input):
		_save_name_input.text = save_name
		_draft_name = save_name
	if _mode == ScreenMode.LOAD and is_instance_valid(_load_detail_host):
		_populate_load_dossier(_load_detail_host, _layout_mode, _window_size())
	_refresh_row_selection()

func _refresh_row_selection() -> void:
	if not is_instance_valid(_save_list_container):
		return
	for child in _save_list_container.get_children():
		if child is Button:
			var row: Button = child
			var row_name := str(row.get_meta("save_name", ""))
			row.button_pressed = row_name == _selected_save_name

func _on_save_pressed() -> void:
	if not is_instance_valid(_save_name_input):
		return
	var save_name := sanitize_save_name(_save_name_input.text)
	if save_name.is_empty():
		_set_save_status("Give this checkpoint a name before saving.", UIConstants.COLOR_WARNING)
		_save_name_input.grab_focus()
		return
	_save_name_input.text = save_name
	_draft_name = save_name
	var existing := _find_save(save_name)
	if not existing.is_empty():
		_show_confirmation("Replace this checkpoint?", "A save named ‘%s’ already exists. Replacing it cannot be undone." % save_name,
			"Replace save", false, _commit_save.bind(save_name))
		return
	_commit_save(save_name)

func _commit_save(save_name: String) -> void:
	if SaveManager.save_game(save_name):
		_selected_save_name = save_name
		_draft_name = save_name
		_refresh_save_cache()
		_render_save_rows(_layout_mode)
		_set_save_status("Saved safely on this device.", UIConstants.COLOR_SUCCESS_DIM)
		if is_instance_valid(_save_name_input):
			_save_name_input.text = save_name
	else:
		_set_save_status("The save could not be written. Check available storage.", UIConstants.COLOR_DANGER_DIM)

func _set_save_status(message: String, color: Color) -> void:
	if is_instance_valid(_save_status_label):
		_save_status_label.text = message
		_save_status_label.add_theme_color_override("font_color", color)

func _on_load_selected_pressed() -> void:
	if _selected_save_name.is_empty():
		return
	var save_name := _selected_save_name
	if GameManager.current_mode != GameManager.GameMode.MAIN_MENU:
		_show_confirmation("Load this clubhouse?", "Your current course will be replaced. Any unsaved progress will be lost.",
			"Load course", true, _load_save.bind(save_name))
	else:
		_load_save(save_name)

func _load_save(save_name: String) -> void:
	if SaveManager.load_game(save_name):
		_on_back_pressed()

func _on_delete_selected_pressed() -> void:
	if _selected_save_name.is_empty():
		return
	var save_name := _selected_save_name
	_show_confirmation("Delete this checkpoint?", "‘%s’ will be permanently removed from this device." % save_name,
		"Delete save", true, _delete_save.bind(save_name))

func _delete_save(save_name: String) -> void:
	if not SaveManager.delete_save(save_name):
		return
	if save_name == _selected_save_name:
		_selected_save_name = ""
	_refresh_save_cache()
	_ensure_selection()
	_render_save_rows(_layout_mode)
	if _mode == ScreenMode.LOAD and is_instance_valid(_load_detail_host):
		_populate_load_dossier(_load_detail_host, _layout_mode, _window_size())
	if is_instance_valid(_save_name_input) and _save_name_input.text == save_name:
		_save_name_input.text = _initial_save_name()
		_draft_name = _save_name_input.text
	if is_instance_valid(_save_status_label):
		_set_save_status("Checkpoint deleted.", COLOR_MUTED)

func _on_quit_to_menu_pressed() -> void:
	_show_confirmation("Return to the title screen?", "Unsaved progress will be lost.",
		"Quit to menu", true, func(): quit_to_menu_requested.emit())

func _show_confirmation(title_text: String, message_text: String, confirm_text: String,
		dangerous: bool, callback: Callable) -> void:
	if is_instance_valid(_confirmation_overlay):
		_confirmation_overlay.queue_free()
	_confirmation_overlay = Control.new()
	_confirmation_overlay.name = "ArchiveConfirmation"
	_confirmation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirmation_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirmation_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirmation_overlay.add_child(center)
	var view := _window_size()
	var accent: Color = UIConstants.COLOR_DANGER if dangerous else COLOR_GOLD
	var panel := PanelContainer.new()
	panel.name = "ConfirmationCard"
	panel.custom_minimum_size.x = minf(470.0, maxf(280.0, view.x - 28.0))
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_SURFACE,
		MenuStyle.with_alpha(accent, 0.75), 14, 20, 18, 2))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	var title := _label(title_text, 19, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var message := _label(message_text, 13, COLOR_MUTED)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = panel.custom_minimum_size.x - 44.0
	content.add_child(message)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 9)
	content.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Keep it"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint_secondary_button(cancel, false)
	cancel.pressed.connect(func(): _close_confirmation())
	buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.text = confirm_text
	confirm.custom_minimum_size = Vector2(0, 44)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if dangerous:
		_paint_secondary_button(confirm, true)
	else:
		MenuStyle.paint_primary(confirm, 9)
		confirm.add_theme_color_override("font_color", MenuStyle.INK)
		confirm.add_theme_color_override("font_hover_color", MenuStyle.INK)
		confirm.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	confirm.pressed.connect(func():
		_close_confirmation()
		callback.call()
	)
	buttons.add_child(confirm)

func _close_confirmation() -> void:
	if is_instance_valid(_confirmation_overlay):
		_confirmation_overlay.queue_free()
	_confirmation_overlay = null

func _refresh_save_cache() -> void:
	_saves = SaveManager.get_save_list()

func _ensure_selection() -> void:
	if not _find_save(_selected_save_name).is_empty():
		return
	_selected_save_name = ""
	if _mode == ScreenMode.LOAD and not _saves.is_empty():
		_selected_save_name = str(_saves[0].get("name", ""))
	elif _mode == ScreenMode.SAVE and not SaveManager.current_save_name.is_empty():
		if not _find_save(SaveManager.current_save_name).is_empty():
			_selected_save_name = SaveManager.current_save_name

func _find_save(save_name: String) -> Dictionary:
	for save_info in _saves:
		if str(save_info.get("name", "")) == save_name:
			return save_info
	return {}

func _initial_save_name() -> String:
	if not SaveManager.current_save_name.is_empty():
		return SaveManager.current_save_name
	var course_name := GameManager.course_name.strip_edges()
	if course_name.is_empty():
		course_name = "My Golf Course"
	return sanitize_save_name("%s - Day %d" % [course_name, GameManager.current_day])

func _format_money(amount: int) -> String:
	return "$" + _thousands(amount)

func _format_money_compact(amount: int) -> String:
	if amount >= 1000000:
		return "$%.1fM" % (float(amount) / 1000000.0)
	if amount >= 1000:
		return "$%dK" % floori(float(amount) / 1000.0)
	return _format_money(amount)

static func _thousands(amount: int) -> String:
	var digits := str(absi(amount))
	var result := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return ("-" if amount < 0 else "") + result

func _format_timestamp(timestamp: String) -> String:
	if timestamp.is_empty():
		return "Date unknown"
	var display := timestamp.replace("T", "  ·  ")
	if display.length() > 23:
		display = display.substr(0, 23)
	return display

func _on_back_pressed() -> void:
	panel_closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(_confirmation_overlay):
				_close_confirmation()
			else:
				_on_back_pressed()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		if is_instance_valid(_confirmation_overlay):
			_close_confirmation()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()
		return
	if camera != null and _is_camera_event(event):
		camera.handle_input_event(event, true)

func _is_camera_event(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		return _hover_is_backdrop()
	if event is InputEventMouseMotion:
		return camera.is_dragging() or _hover_is_backdrop()
	if event is InputEventMouseButton:
		if camera.is_dragging():
			return true
		if not _hover_is_backdrop():
			return false
		return event.button_index == MOUSE_BUTTON_MIDDLE \
			or event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	return false

func _hover_is_backdrop() -> bool:
	var hovered := _get_hovered_control()
	return hovered == null or not _is_interactive_control(hovered)

func _get_hovered_control() -> Control:
	return get_viewport().gui_get_hovered_control()

func _is_interactive_control(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		if node is Button or node is LineEdit or node is Range or node is ScrollContainer:
			return true
		node = node.get_parent()
	return false

func _set_margins(container: MarginContainer, margin: int) -> void:
	for side in ["left", "right", "top", "bottom"]:
		container.add_theme_constant_override("margin_" + side, margin)

func _make_card(bg: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(bg, border, radius, 0, 0, 1))
	return panel

func _field_style(bg: Color, border: Color) -> StyleBoxFlat:
	return MenuStyle.panel(bg, border, 1, 8, 5, 1)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _paint_secondary_button(button: Button, danger: bool) -> void:
	var accent := UIConstants.COLOR_DANGER if danger else COLOR_MINT
	MenuStyle.paint_card(button, accent, 0.0, 8, COLOR_TEXT, COLOR_TEXT)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
