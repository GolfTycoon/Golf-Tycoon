extends TournamentLibraryScreen
class_name SaveGolferScreen
## SaveGolferScreen — the Pause Menu's "Save Golfer" card, opened as its own
## fullscreen screen.
##
## This keeps the owner's golfer — skills, traits, appearance and the colours of
## the skin they wear — as a snapshot Tournament Mode can play as (Main Menu →
## Tournament Mode → Choose Golfer). It is not a Career save slot and not a
## profile editor: nothing here writes back to the live profile, whose edits
## already persist as they are made. The left card shows whom is being kept;
## the right card is the shelf of golfers already exported, where one can be
## picked back up for an overwrite, or deleted. Saving over an existing name
## asks first; the outcome is reported in the card's own status line.

signal saved(result: Dictionary)

const MAX_NAME_LENGTH := 40

var _draft_name := ""
var _saved_golfers: Array[Dictionary] = []
var _selected_slug := ""

var _name_input: LineEdit = null
var _status_label: Label = null
var _save_count_label: Label = null
var _list_container: VBoxContainer = null
var _golfer_buttons: Array[Button] = []

func _screen_title() -> String:
	return "Save Golfer"

func _screen_icon() -> int:
	return PixelIcon.Kind.SHIRT

func _ready() -> void:
	if _draft_name.is_empty():
		_draft_name = _live_golfer_name()
	super()

func _capture_build_state() -> void:
	if is_instance_valid(_name_input):
		_draft_name = _name_input.text

func _after_build() -> void:
	var cta := find_child("SaveGolferButton", true, false) as Button
	if cta != null:
		if has_node("/root/InputManager") and InputManager.is_navigation_device():
			cta.grab_focus.call_deferred()

# ── Body ───────────────────────────────────────────────────────────────────

func _build_body(mode: int, view: Vector2) -> Control:
	_refresh_entries()
	var focus := _build_focus_card(mode)
	var archive := _build_archive_card(mode)
	return _build_workspace(mode, view, focus, archive)

func _build_workspace(mode: int, view: Vector2, focus: Control, archive: Control) -> Control:
	var body: BoxContainer
	if _uses_split(mode, view):
		body = HBoxContainer.new()
		body.name = "SplitWorkspace"
		body.add_theme_constant_override("separation", 12 if mode == Kit.LayoutMode.DESKTOP else 8)
		focus.size_flags_stretch_ratio = 0.92
		archive.size_flags_stretch_ratio = 1.38
	else:
		body = VBoxContainer.new()
		body.name = "StackedWorkspace"
		body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	archive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus.size_flags_vertical = Control.SIZE_EXPAND_FILL if _uses_split(mode, view) else Control.SIZE_SHRINK_BEGIN
	archive.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(focus)
	body.add_child(archive)
	return body

func _build_focus_card(mode: int) -> PanelContainer:
	var compact := Kit.is_phone(mode)
	var short := mode == Kit.LayoutMode.PHONE_LANDSCAPE
	var profile := GameManager.player_profile
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_GOLD, 0.30))
	panel.name = "SaveWorkspace"
	var margin := MarginContainer.new()
	_set_margins(margin, 12 if compact else 18)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.name = "FocusContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5 if short else (8 if compact else 10))
	margin.add_child(content)

	content.add_child(Kit.make_kicker("Save for Tournament Mode", 10 if compact else 11))
	var heading := Kit.make_label("Keep this golfer for the championships.",
		16 if compact else 19, COLOR_TEXT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.visible = not short
	content.add_child(heading)

	# The golfer themselves, in the colours they are wearing right now.
	var identity := HBoxContainer.new()
	identity.name = "LiveGolferIdentity"
	identity.add_theme_constant_override("separation", 12)
	var portrait := GolferPortrait.new(_live_portrait_entry())
	portrait.name = "LiveGolferPortrait"
	portrait.accent_color = COLOR_GOLD
	portrait.custom_minimum_size = Vector2(48.0 if short else 64.0, 64.0 if short else (86.0 if compact else 96.0))
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(portrait)
	var identity_text := VBoxContainer.new()
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_text.add_theme_constant_override("separation", 2)
	identity.add_child(identity_text)
	var live_name := Kit.make_label(_live_golfer_name(), 17 if compact else 20, COLOR_TEXT)
	live_name.clip_text = true
	live_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_text.add_child(live_name)
	var profession := Kit.make_label(str(profile.profession), 11 if compact else 12, COLOR_MINT)
	profession.clip_text = true
	profession.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_text.add_child(profession)
	var detail := Kit.make_label(_live_identity_text(), 9 if compact else 10, COLOR_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_text.add_child(detail)
	content.add_child(identity)

	# The headline numbers, then the four abilities that come out of the Golf
	# Skill points — a golfer is being kept, not just a name.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	var total_points := 0
	for value in profile.points:
		total_points += int(value)
	stats.add_child(_make_stat_tile("Age", str(int(profile.age)), mode))
	stats.add_child(_make_stat_tile("Skill pts", str(total_points), mode))
	stats.add_child(_make_stat_tile("Avg skill",
		"%d%%" % roundi(float(total_points) * GolferAttributes.PERCENT_PER_POINT / float(maxi(profile.points.size(), 1))), mode))
	content.add_child(stats)

	if not short:
		var abilities := VBoxContainer.new()
		abilities.name = "LiveGolferAbilities"
		abilities.add_theme_constant_override("separation", 4)
		var ability_rows := [
			["Driving", profile.driving_ability(), COLOR_MINT],
			["Accuracy", profile.accuracy_ability(), COLOR_GOLD],
			["Putting", profile.putting_ability(), Color("8fc79b")],
			["Recovery", profile.recovery_ability(), Color("d9b468")],
		]
		for row in ability_rows:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			var ability_caption := Kit.make_label(str(row[0]).to_upper(), 9 if compact else 10, COLOR_QUIET)
			ability_caption.custom_minimum_size.x = 62.0 if compact else 74.0
			ability_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(ability_caption)
			var bar: Control = Kit.make_progress_bar(float(row[1]), row[2] as Color, 8.0)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(bar)
			var pct := Kit.make_label("%4d%%" % roundi(float(row[1]) * 100.0), 9 if compact else 10, COLOR_MUTED)
			pct.custom_minimum_size.x = 38.0
			pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(pct)
			abilities.add_child(line)
		content.add_child(abilities)

	var skin_line := Kit.make_label("Skin: %s" % _live_skin_name(), 9 if compact else 10, COLOR_QUIET)
	skin_line.name = "LiveGolferSkin"
	skin_line.clip_text = true
	content.add_child(skin_line)

	var name_row := VBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	name_row.add_child(Kit.make_label("GOLFER NAME", 9 if compact else 10, COLOR_QUIET))
	_name_input = LineEdit.new()
	_name_input.name = "GolferNameInput"
	_name_input.placeholder_text = "Name this golfer"
	_name_input.text = _draft_name
	_name_input.max_length = MAX_NAME_LENGTH + 12
	_name_input.clear_button_enabled = true
	_name_input.custom_minimum_size.y = 36.0 if short else (40.0 if compact else 46.0)
	_name_input.add_theme_font_override("font", BODY_FONT)
	_name_input.add_theme_font_size_override("font_size", 13 if compact else 14)
	_name_input.add_theme_color_override("font_color", COLOR_TEXT)
	_name_input.add_theme_color_override("font_placeholder_color", COLOR_QUIET)
	PixelButtonStyle.paint_field(_name_input, MenuStyle.with_alpha(COLOR_GOLD, 0.6), COLOR_INSET, 8)
	_name_input.text_changed.connect(func(value: String) -> void: _draft_name = value)
	_name_input.text_submitted.connect(func(_submitted: String) -> void: _on_save_pressed())
	name_row.add_child(_name_input)
	content.add_child(name_row)

	_status_label = Kit.make_label(
		"Stored for Tournament Mode on this device · never uploaded.",
		9 if compact else 10, COLOR_QUIET)
	_status_label.name = "SaveStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status_label)

	var save_button := Button.new()
	save_button.name = "SaveGolferButton"
	save_button.text = "Save Golfer  ›"
	save_button.tooltip_text = "Store this golfer for Main Menu → Tournament Mode → Choose Golfer"
	save_button.custom_minimum_size.y = 40.0 if short else (44.0 if compact else 52.0)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.add_theme_font_override("font", TITLE_FONT)
	save_button.add_theme_font_size_override("font_size", 14 if compact else 16)
	MenuStyle.paint_primary(save_button)
	save_button.add_theme_color_override("font_color", MenuStyle.INK)
	save_button.add_theme_color_override("font_hover_color", MenuStyle.INK)
	save_button.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	save_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	save_button.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	save_button.pressed.connect(_on_save_pressed)
	content.add_child(save_button)

	var caption := Kit.make_label(
		"Saved golfers appear on the Start Tournament screen's Choose Golfer shelf.",
		9 if compact else 10, COLOR_QUIET)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.visible = not short
	content.add_child(caption)
	return panel

func _build_archive_card(mode: int) -> PanelContainer:
	var compact := Kit.is_phone(mode)
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_BORDER, 0.42))
	panel.name = "SavedGolfers"
	var margin := MarginContainer.new()
	_set_margins(margin, 12 if compact else (16 if mode == Kit.LayoutMode.DESKTOP else 12))
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8 if mode == Kit.LayoutMode.PHONE_LANDSCAPE else 10)
	margin.add_child(stack)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 8)
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_box.add_theme_constant_override("separation", 1)
	heading_box.add_child(Kit.make_label("ON THIS DEVICE", 9 if compact else 10, COLOR_GOLD))
	var title := Kit.make_label("Saved golfers", 16 if compact else 20, COLOR_TEXT)
	title.name = "ArchiveTitle"
	heading_box.add_child(title)
	heading_row.add_child(heading_box)
	_save_count_label = Kit.make_label("", 10, COLOR_MUTED)
	_save_count_label.name = "SaveCount"
	_save_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_save_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading_row.add_child(_save_count_label)
	stack.add_child(heading_row)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "SavedGolferScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.follow_focus = true
	list_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stack.add_child(list_scroll)
	_list_container = VBoxContainer.new()
	_list_container.name = "SavedGolferList"
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 7 if mode == Kit.LayoutMode.PHONE_LANDSCAPE else 8)
	list_scroll.add_child(_list_container)

	var delete_button := Button.new()
	delete_button.name = "DeleteSelectedButton"
	delete_button.text = "Delete selected golfer"
	delete_button.tooltip_text = "Remove the highlighted saved golfer from Tournament Mode"
	delete_button.custom_minimum_size.y = 38.0 if compact else 42.0
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.add_theme_font_override("font", SUBTITLE_FONT)
	delete_button.add_theme_font_size_override("font_size", 12)
	Kit.paint_danger_button(delete_button)
	delete_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	delete_button.pressed.connect(_on_delete_selected_pressed)
	stack.add_child(delete_button)

	_render_rows()
	return panel

# ── Entries ────────────────────────────────────────────────────────────────

func _refresh_entries() -> void:
	_saved_golfers = TournamentLibrary.list_saved_golfers()
	_golfer_buttons.clear()
	_selected_slug = _selected_slug if _selected_slug != "" and \
		_saved_golfers.any(func(e: Dictionary) -> bool: return str(e.get("slug", "")) == _selected_slug) \
		else ""

func _render_rows() -> void:
	if not is_instance_valid(_list_container):
		return
	for child in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()
	_golfer_buttons.clear()
	if is_instance_valid(_save_count_label):
		_save_count_label.text = "%d SAVED" % _saved_golfers.size()
	if _saved_golfers.is_empty():
		var empty := PanelContainer.new()
		empty.name = "EmptyArchive"
		empty.custom_minimum_size.y = 120.0
		empty.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_RAISED,
			MenuStyle.with_alpha(COLOR_BORDER, 0.24), 12, 14, 12, 1))
		var content := VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 5)
		empty.add_child(content)
		var title := Kit.make_label("No golfers exported yet.", 13, COLOR_TEXT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(title)
		var detail := Kit.make_label(
			"Save this golfer with the button on the left and they will appear here, ready to play in Tournament Mode.",
			10, COLOR_MUTED)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(detail)
		_list_container.add_child(empty)
		return
	for entry in _saved_golfers:
		_list_container.add_child(_build_row(entry))

func _build_row(entry: Dictionary) -> Button:
	var slug := str(entry.get("slug", ""))
	var row := Button.new()
	row.name = "SavedGolfer_%s" % slug.validate_node_name()
	row.toggle_mode = true
	row.button_pressed = slug == _selected_slug
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 72.0
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "Use '%s' as the name to overwrite this golfer" % str(entry.get("name", ""))
	MenuStyle.paint_choice(row, COLOR_MINT, 10)
	row.add_theme_font_override("font", SUBTITLE_FONT)
	row.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_theme_color_override("font_hover_color", COLOR_TEXT)
	row.add_theme_color_override("font_pressed_color", COLOR_TEXT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_margins(margin, 8)
	row.add_child(margin)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var portrait := GolferPortrait.new(entry)
	portrait.name = "SavedGolferPortrait_%s" % slug.validate_node_name()
	portrait.custom_minimum_size = Vector2(36.0, 52.0)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(portrait)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 2)
	content.add_child(text_box)
	var name_label := Kit.make_label(str(entry.get("name", "Saved golfer")), 13, COLOR_TEXT)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(name_label)
	var meta := "%s  ·  Age %d  ·  %s" % [
		str(entry.get("profession", "Golfer")),
		int(entry.get("age", 30)),
		str(entry.get("skin_name", "Casual"))]
	var meta_label := Kit.make_label(meta, 9, COLOR_MUTED)
	meta_label.clip_text = true
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(meta_label)
	var stamped := format_saved_at(str(entry.get("saved_at", "")))
	if not stamped.is_empty():
		var date_label := Kit.make_label(stamped, 8, COLOR_QUIET)
		date_label.clip_text = true
		text_box.add_child(date_label)

	row.set_meta("slug", slug)
	row.pressed.connect(_on_row_pressed.bind(slug))
	_golfer_buttons.append(row)
	return row

func _refresh_row_selection() -> void:
	for row in _golfer_buttons:
		if is_instance_valid(row):
			row.button_pressed = str(row.get_meta("slug", "")) == _selected_slug

# ── Actions ───────────────────────────────────────────────────────────────

func _on_row_pressed(slug: String) -> void:
	_selected_slug = slug
	for entry in _saved_golfers:
		if str(entry.get("slug", "")) == slug:
			if is_instance_valid(_name_input):
				_draft_name = str(entry.get("name", ""))
				_name_input.text = _draft_name
			break
	_refresh_row_selection()

func _on_save_pressed() -> void:
	if not is_instance_valid(_name_input):
		return
	var display_name := SaveLoadPanel.sanitize_save_name(_name_input.text)
	if display_name.is_empty():
		_set_status("Give this golfer a name before saving.", UIConstants.COLOR_WARNING)
		_name_input.grab_focus()
		return
	_name_input.text = display_name
	_draft_name = display_name
	var slug := TournamentLibrary.sanitize_slug(display_name, "career_golfer")
	if _saved_slug_exists(slug):
		_show_confirmation(
			"A saved golfer named '%s' already exists. Saving over them cannot be undone." % display_name,
			"Replace golfer", _commit_save.bind(display_name, slug), MenuStyle.ACCENT_PRIMARY)
		return
	_commit_save(display_name, slug)

func _commit_save(display_name: String, slug: String) -> void:
	var result := TournamentCareerExport.save_golfer(display_name)
	var ok := bool(result.get("ok", false))
	_set_status(str(result.get("message", "")),
		UIConstants.COLOR_SUCCESS_DIM if ok else UIConstants.COLOR_WARNING)
	if ok:
		_selected_slug = slug
		_refresh_entries()
		_render_rows()
		_refresh_row_selection()
	saved.emit(result)

func _on_delete_selected_pressed() -> void:
	if _selected_slug.is_empty():
		_set_status("Select a saved golfer first.", UIConstants.COLOR_WARNING)
		return
	var target_slug := _selected_slug
	var target_name := target_slug
	for entry in _saved_golfers:
		if str(entry.get("slug", "")) == target_slug:
			target_name = str(entry.get("name", target_slug))
			break
	_show_confirmation(
		"Delete saved golfer '%s'? They will be removed from Tournament Mode on this device." % target_name,
		"Delete golfer", _delete_saved.bind(target_slug))

func _delete_saved(slug: String) -> void:
	if TournamentLibrary.delete_saved_golfer("saved:" + slug):
		_set_status("Saved golfer deleted.", COLOR_MUTED)
	else:
		_set_status("That golfer could not be deleted.", UIConstants.COLOR_WARNING)
	if _selected_slug == slug:
		_selected_slug = ""
	_refresh_entries()
	_render_rows()

func _saved_slug_exists(slug: String) -> bool:
	for entry in _saved_golfers:
		if str(entry.get("slug", "")) == slug:
			return true
	return false

func _set_status(message: String, color: Color) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message
		_status_label.add_theme_color_override("font_color", color)

# ── Live golfer data ─────────────────────────────────────────────────────

func _live_skin_id() -> String:
	var skin_id := GameManager.player_skin_id.strip_edges()
	if GolferSkins != null:
		var worn: GolferSkin = GolferSkins.player_skin()
		if worn != null and not str(worn.id).strip_edges().is_empty():
			skin_id = str(worn.id)
	return skin_id if not skin_id.is_empty() else "casual"

func _live_golfer_name() -> String:
	var live_name := GameManager.player_profile.golfer_name.strip_edges()
	return live_name if not live_name.is_empty() else "Club Pro"

func _live_skin_name() -> String:
	var wanted := _live_skin_id()
	if GolferSkins != null and GolferSkins.library != null:
		var skin: GolferSkin = GolferSkins.library.get_skin(wanted)
		if skin != null and not skin.display_name.is_empty():
			return skin.display_name
	return wanted.replace("_", " ").capitalize()

func _live_portrait_entry() -> Dictionary:
	var skin_id := _live_skin_id()
	return {
		"skin_id": skin_id,
		"skin_colors": TournamentLibrary.capture_skin_colors(GameManager.player_profile, skin_id),
	}

func _live_identity_text() -> String:
	var profile := GameManager.player_profile
	var gender := str(GolferAttributes.GENDER_NAMES.get(profile.gender, "Male"))
	var marital := str(GolferAttributes.MARITAL_STATUS_NAMES.get(profile.marital_status, "Single"))
	return "Age %d  ·  %s  ·  %s" % [int(profile.age), gender, marital]
