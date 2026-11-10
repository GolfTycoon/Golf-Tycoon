extends TournamentLibraryScreen
class_name ChooseCourseScreen
## ChooseCourseScreen — the fullscreen course shelf the Start Tournament
## screen opens for its Course section.
##
## The four built-in Default Courses and every Career-saved course on this
## device are laid out as big, tappable cards on the left. The right card is
## the dossier for the highlighted course — a top-down preview in theme
## colours, its vital statistics and a gold "Choose This Course" action.
## Saved Career courses can be deleted right here, with a question first.
## Pressing Back (or Escape / controller B) leaves without changing the
## selection; choosing emits `course_chosen`, and the caller decides what to
## do with it.

signal course_chosen(course_id: String)

var _courses: Array[Dictionary] = []
var _selected_id := ""

var _list_container: VBoxContainer = null
var _course_buttons: Dictionary = {}
var _dossier_host: VBoxContainer = null
var _choose_button: Button = null
var _count_label: Label = null

func _screen_title() -> String:
	return "Choose Course"

func _screen_icon() -> int:
	return PixelIcon.Kind.FLAG

## Pre-select the course the Start Tournament screen currently has ready.
func configure(selected_id: String) -> void:
	_selected_id = selected_id.strip_edges()
	if is_inside_tree():
		_build()

func _ready() -> void:
	_reload_catalogue()
	super()

func _after_build() -> void:
	var cta := find_child("ChooseCourseButton", true, false) as Button
	if cta != null and has_node("/root/InputManager") and InputManager.is_navigation_device():
		cta.grab_focus.call_deferred()

func _capture_build_state() -> void:
	# Nothing half-typed lives on this screen; the selection is the state.
	pass

# ── Body ───────────────────────────────────────────────────────────────────

func _reload_catalogue() -> void:
	_courses = TournamentLibrary.list_courses()
	var found := false
	for entry in _courses:
		if str(entry.get("id", "")) == _selected_id:
			found = true
			break
	if not found:
		_selected_id = str(_courses[0].get("id", "")) if not _courses.is_empty() else ""

func _build_body(mode: int, view: Vector2) -> Control:
	_reload_catalogue()
	var body: BoxContainer
	if _uses_split(mode, view):
		body = HBoxContainer.new()
		body.name = "SplitWorkspace"
		body.add_theme_constant_override("separation", 12 if mode == Kit.LayoutMode.DESKTOP else 8)
	else:
		body = VBoxContainer.new()
		body.name = "StackedWorkspace"
		body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var shelf := _build_shelf_card(mode)
	var dossier := _build_dossier_card(mode)
	if _uses_split(mode, view):
		shelf.size_flags_stretch_ratio = 1.35
		dossier.size_flags_stretch_ratio = 1.0
		shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dossier.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dossier.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dossier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(dossier if not _uses_split(mode, view) else shelf)
	body.add_child(shelf if not _uses_split(mode, view) else dossier)
	return body

func _build_shelf_card(mode: int) -> PanelContainer:
	var compact := Kit.is_phone(mode)
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_MINT, 0.32))
	panel.name = "CourseShelf"
	var margin := MarginContainer.new()
	_set_margins(margin, 12 if compact else 16)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 8)
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_box.add_theme_constant_override("separation", 1)
	heading_box.add_child(Kit.make_label("ON THIS DEVICE", 9 if compact else 10, COLOR_MINT))
	var title := Kit.make_label("Courses", 16 if compact else 20, COLOR_TEXT)
	title.name = "ShelfTitle"
	heading_box.add_child(title)
	heading_row.add_child(heading_box)
	_count_label = Kit.make_label("", 10, COLOR_MUTED)
	_count_label.name = "CourseCount"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading_row.add_child(_count_label)
	stack.add_child(heading_row)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "CourseShelfScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.follow_focus = true
	list_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stack.add_child(list_scroll)
	_list_container = VBoxContainer.new()
	_list_container.name = "CourseShelfList"
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 8)
	list_scroll.add_child(_list_container)
	_render_rows(mode)
	return panel

func _render_rows(mode: int) -> void:
	if not is_instance_valid(_list_container):
		return
	for child in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()
	_course_buttons.clear()
	if is_instance_valid(_count_label):
		_count_label.text = "%d COURSE%s" % [_courses.size(), "" if _courses.size() == 1 else "S"]
	for entry in _courses:
		_list_container.add_child(_build_course_row(entry, mode))

func _build_course_row(entry: Dictionary, mode: int) -> Control:
	var compact := Kit.is_phone(mode)
	var cid := str(entry.get("id", ""))
	var is_default := bool(entry.get("is_default", true))
	var min_h := 46.0 if compact else 58.0

	var row := HBoxContainer.new()
	row.name = "CourseRow_%s" % cid.replace(":", "_").validate_node_name()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.name = "Course_%s" % cid.replace(":", "_")
	btn.toggle_mode = true
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(100.0, min_h)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = str(entry.get("tagline", ""))
	btn.add_theme_font_override("font", SUBTITLE_FONT)
	MenuStyle.paint_choice(btn, COLOR_MINT if is_default else MenuStyle.ACCENT_PRIMARY, 10)
	btn.toggled.connect(_on_course_toggled.bind(cid))

	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_margins(inner, 6)
	btn.add_child(inner)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	inner.add_child(content)

	var preview := TournamentCoursePreview.new()
	preview.custom_minimum_size = Vector2(84.0 if compact else 108.0, min_h - 12.0)
	preview.set_course_entry(entry)
	content.add_child(preview)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 2)
	content.add_child(text_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	text_box.add_child(top)
	var name_lbl := Kit.make_label(str(entry.get("name", "Course")),
		13 if compact else 15, COLOR_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_lbl)
	var badge := Kit.make_label(str(entry.get("source_label", "DEFAULT")), 8 if compact else 9,
		COLOR_QUIET if is_default else COLOR_GOLD)
	top.add_child(badge)
	var meta := "%s  ·  %d holes  ·  Par %d" % [
		str(entry.get("theme_name", "Parkland")),
		int(entry.get("hole_count", 0)),
		int(entry.get("par", 0))]
	var meta_lbl := Kit.make_label(meta, 9 if compact else 10, COLOR_MUTED)
	meta_lbl.clip_text = true
	meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(meta_lbl)

	row.add_child(btn)
	_course_buttons[cid] = btn

	if not is_default:
		var del_btn := Button.new()
		del_btn.name = "DeleteSavedCourse_%s" % cid.trim_prefix("saved:").validate_node_name()
		del_btn.text = "Del"
		del_btn.tooltip_text = "Delete saved course '%s'" % str(entry.get("name", ""))
		del_btn.custom_minimum_size = Vector2(46.0, min_h)
		del_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		del_btn.add_theme_font_override("font", SUBTITLE_FONT)
		del_btn.add_theme_font_size_override("font_size", 11)
		PixelButtonStyle.paint_card(del_btn, COLOR_QUIT, 0.0, 6,
			Color(0.96, 0.72, 0.68), Color.WHITE)
		del_btn.pressed.connect(_on_delete_pressed.bind(cid))
		row.add_child(del_btn)
	return row

func _build_dossier_card(mode: int) -> PanelContainer:
	var compact := Kit.is_phone(mode)
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_GOLD, 0.30))
	panel.name = "CourseDossier"
	var margin := MarginContainer.new()
	_set_margins(margin, 12 if compact else 18)
	panel.add_child(margin)
	_dossier_host = VBoxContainer.new()
	_dossier_host.name = "DossierContent"
	_dossier_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dossier_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dossier_host.add_theme_constant_override("separation", 8 if compact else 10)
	margin.add_child(_dossier_host)
	_render_dossier(mode)
	return panel

func _render_dossier(mode: int) -> void:
	if not is_instance_valid(_dossier_host):
		return
	for child in _dossier_host.get_children():
		_dossier_host.remove_child(child)
		child.queue_free()
	_choose_button = null
	var compact := Kit.is_phone(mode)
	_dossier_host.add_child(Kit.make_kicker("Course dossier", 10 if compact else 11))
	_sync_row_pressed()
	var entry := _selected_entry()
	if entry.is_empty():
		_dossier_host.add_child(Kit.make_label("No courses are available on this device.",
			13, COLOR_MUTED))
		return

	var is_default := bool(entry.get("is_default", true))
	var preview := TournamentCoursePreview.new()
	preview.name = "DossierPreview"
	preview.set_course_entry(entry)
	preview.custom_minimum_size = Vector2(180.0, 84.0 if compact else 132.0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dossier_host.add_child(preview)

	var name_lbl := Kit.make_label(str(entry.get("name", "Course")),
		17 if compact else 22, COLOR_TEXT)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dossier_host.add_child(name_lbl)

	var saved_stamp := format_saved_at(str(entry.get("saved_at", "")))
	var source := "Default course" if is_default else \
		("Career course · saved %s" % saved_stamp if not saved_stamp.is_empty() else "Career course")
	var source_lbl := Kit.make_label(
		source,
		10 if compact else 11, COLOR_GOLD if not is_default else COLOR_QUIET)
	_dossier_host.add_child(source_lbl)

	var tagline := str(entry.get("tagline", ""))
	if not tagline.is_empty():
		var tagline_lbl := Kit.make_label(tagline, 10 if compact else 11, COLOR_MUTED)
		tagline_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tagline_lbl.clip_text = true
		tagline_lbl.custom_minimum_size.y = float(MenuStyle.text_block(BODY_FONT,
			10 if compact else 11, 2))
		_dossier_host.add_child(tagline_lbl)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	stats.add_child(_make_stat_tile("Holes", str(int(entry.get("hole_count", 0))), mode))
	stats.add_child(_make_stat_tile("Par", str(int(entry.get("par", 0))), mode))
	stats.add_child(_make_stat_tile("Theme", str(entry.get("theme_name", "Parkland")), mode))
	_dossier_host.add_child(stats)

	_dossier_host.add_child(_make_hairline())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size.y = 2
	_dossier_host.add_child(spacer)

	_choose_button = Button.new()
	_choose_button.name = "ChooseCourseButton"
	_choose_button.text = "Choose This Course  ›"
	_choose_button.tooltip_text = "Play the next tournament on %s" % str(entry.get("name", "this course"))
	_choose_button.custom_minimum_size.y = 44.0 if compact else 52.0
	_choose_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choose_button.add_theme_font_override("font", TITLE_FONT)
	_choose_button.add_theme_font_size_override("font_size", 14 if compact else 16)
	MenuStyle.paint_primary(_choose_button)
	_choose_button.add_theme_color_override("font_color", MenuStyle.INK)
	_choose_button.add_theme_color_override("font_hover_color", MenuStyle.INK)
	_choose_button.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	_choose_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_choose_button.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	_choose_button.pressed.connect(_on_choose_pressed)
	_dossier_host.add_child(_choose_button)

# ── Selection ─────────────────────────────────────────────────────────────

func _selected_entry() -> Dictionary:
	for entry in _courses:
		if str(entry.get("id", "")) == _selected_id:
			return entry
	return {}

func _sync_row_pressed() -> void:
	for cid in _course_buttons:
		var btn: Button = _course_buttons[cid]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(str(cid) == _selected_id)

func _on_course_toggled(pressed: bool, course_id: String) -> void:
	if not pressed:
		if course_id == _selected_id and _course_buttons.has(course_id):
			(_course_buttons[course_id] as Button).set_pressed_no_signal(true)
		return
	_selected_id = course_id
	_render_dossier(_layout_mode)

func _on_choose_pressed() -> void:
	if _selected_id.is_empty():
		return
	course_chosen.emit(_selected_id)

func _on_delete_pressed(course_id: String) -> void:
	var target_name := course_id
	for entry in _courses:
		if str(entry.get("id", "")) == course_id:
			target_name = str(entry.get("name", course_id))
			break
	_show_confirmation(
		"Delete saved course '%s'? It will be removed from this device." % target_name,
		"Delete course",
		func() -> void:
			if TournamentLibrary.delete_saved_course(course_id):
				EventBus.notify("Removed saved tournament course.", "info")
			else:
				EventBus.notify("That course could not be deleted.", "warning")
			if _selected_id == course_id:
				_selected_id = ""
			_reload_catalogue()
			_render_rows(_layout_mode)
			_render_dossier(_layout_mode))
