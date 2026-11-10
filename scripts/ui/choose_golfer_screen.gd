extends TournamentLibraryScreen
class_name ChooseGolferScreen
## ChooseGolferScreen — the fullscreen golfer shelf the Start Tournament
## screen opens for its Golfer section.
##
## The four built-in Default Golfers and every Career-saved golfer on this
## device are laid out as big, tappable cards on the left: each golfer's own
## sprite portrait in their own Skin Colours. The right card is the dossier
## for the highlighted golfer — identity, Skin and Skin Colours, traits,
## Golfer Skills, ability bars and a gold "Choose This Golfer" action.
## Saved Career golfers can be deleted right here, with a question first.
## Pressing Back (or Escape / controller B) leaves without changing the
## selection; choosing emits `golfer_chosen`, and the caller decides what to
## do with it.

signal golfer_chosen(golfer_id: String)

const SKIN_CHIP_HEIGHT := 18.0

var _golfers: Array[Dictionary] = []
var _selected_id := ""

var _list_container: VBoxContainer = null
var _golfer_buttons: Dictionary = {}
var _dossier_host: VBoxContainer = null
var _count_label: Label = null

func _screen_title() -> String:
	return "Choose Golfer"

func _screen_icon() -> int:
	return PixelIcon.Kind.SHIRT

## Pre-select the golfer the Start Tournament screen currently has ready.
func configure(selected_id: String) -> void:
	_selected_id = selected_id.strip_edges()
	if is_inside_tree():
		_build()

func _ready() -> void:
	_reload_catalogue()
	super()

func _after_build() -> void:
	var cta := find_child("ChooseGolferButton", true, false) as Button
	if cta != null and has_node("/root/InputManager") and InputManager.is_navigation_device():
		cta.grab_focus.call_deferred()

# ── Body ───────────────────────────────────────────────────────────────────

func _reload_catalogue() -> void:
	_golfers = TournamentLibrary.list_golfers()
	var found := false
	for entry in _golfers:
		if str(entry.get("id", "")) == _selected_id:
			found = true
			break
	if not found:
		_selected_id = str(_golfers[0].get("id", "")) if not _golfers.is_empty() else ""

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
	panel.name = "GolferShelf"
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
	var title := Kit.make_label("Golfers", 16 if compact else 20, COLOR_TEXT)
	title.name = "ShelfTitle"
	heading_box.add_child(title)
	heading_row.add_child(heading_box)
	_count_label = Kit.make_label("", 10, COLOR_MUTED)
	_count_label.name = "GolferCount"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading_row.add_child(_count_label)
	stack.add_child(heading_row)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "GolferShelfScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.follow_focus = true
	list_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stack.add_child(list_scroll)
	_list_container = VBoxContainer.new()
	_list_container.name = "GolferShelfList"
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
	_golfer_buttons.clear()
	if is_instance_valid(_count_label):
		_count_label.text = "%d GOLFER%s" % [_golfers.size(), "" if _golfers.size() == 1 else "S"]
	for entry in _golfers:
		_list_container.add_child(_build_golfer_row(entry, mode))

func _build_golfer_row(entry: Dictionary, mode: int) -> Control:
	var compact := Kit.is_phone(mode)
	var gid := str(entry.get("id", ""))
	var is_default := bool(entry.get("is_default", true))
	# Tall enough for the sprite to draw at twice its pixel size.
	var min_h := 56.0 if compact else 72.0

	var row := HBoxContainer.new()
	row.name = "GolferRow_%s" % gid.replace(":", "_").validate_node_name()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.name = "Golfer_%s" % gid.replace(":", "_")
	btn.toggle_mode = true
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(100.0, min_h)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "%s · Age %d · %s" % [
		str(entry.get("profession", "Golfer")),
		int(entry.get("age", 30)),
		str(entry.get("skin_name", "Casual"))]
	btn.add_theme_font_override("font", SUBTITLE_FONT)
	MenuStyle.paint_choice(btn, Color("7fb8d8") if is_default else MenuStyle.ACCENT_PRIMARY, 10)
	btn.toggled.connect(_on_golfer_toggled.bind(gid))

	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_margins(inner, 6)
	btn.add_child(inner)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	inner.add_child(content)

	var portrait := GolferPortrait.new(entry)
	portrait.name = "GolferPortrait_%s" % gid.replace(":", "_")
	portrait.accent_color = Color("7fb8d8") if is_default else COLOR_GOLD
	portrait.custom_minimum_size = Vector2(32.0, min_h - 10.0)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(portrait)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 2)
	content.add_child(text_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	text_box.add_child(top)
	var name_lbl := Kit.make_label(str(entry.get("name", "Golfer")),
		13 if compact else 15, COLOR_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_lbl)
	var badge := Kit.make_label(str(entry.get("source_label", "DEFAULT")), 8 if compact else 9,
		COLOR_QUIET if is_default else COLOR_GOLD)
	top.add_child(badge)
	var stats_line := "%s  ·  Age %d  ·  %.0f%% Skill" % [
		str(entry.get("profession", "Golfer")),
		int(entry.get("age", 30)),
		float(entry.get("avg_golf_skill_pct", 50.0))]
	var meta_lbl := Kit.make_label(stats_line, 9 if compact else 10, COLOR_MUTED)
	meta_lbl.clip_text = true
	meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(meta_lbl)

	row.add_child(btn)
	_golfer_buttons[gid] = btn

	if not is_default:
		var del_btn := Button.new()
		del_btn.name = "DeleteSavedGolfer_%s" % gid.trim_prefix("saved:").validate_node_name()
		del_btn.text = "Del"
		del_btn.tooltip_text = "Delete saved golfer '%s'" % str(entry.get("name", ""))
		del_btn.custom_minimum_size = Vector2(46.0, min_h)
		del_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		del_btn.add_theme_font_override("font", SUBTITLE_FONT)
		del_btn.add_theme_font_size_override("font_size", 11)
		PixelButtonStyle.paint_card(del_btn, COLOR_QUIT, 0.0, 6,
			Color(0.96, 0.72, 0.68), Color.WHITE)
		del_btn.pressed.connect(_on_delete_pressed.bind(gid))
		row.add_child(del_btn)
	return row

func _build_dossier_card(mode: int) -> PanelContainer:
	var compact := Kit.is_phone(mode)
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_GOLD, 0.30))
	panel.name = "GolferDossier"
	var margin := MarginContainer.new()
	_set_margins(margin, 12 if compact else 18)
	panel.add_child(margin)
	_dossier_host = VBoxContainer.new()
	_dossier_host.name = "DossierContent"
	_dossier_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dossier_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dossier_host.add_theme_constant_override("separation", 6 if compact else 8)
	margin.add_child(_dossier_host)
	_render_dossier(mode)
	return panel

func _render_dossier(mode: int) -> void:
	if not is_instance_valid(_dossier_host):
		return
	for child in _dossier_host.get_children():
		_dossier_host.remove_child(child)
		child.queue_free()
	var compact := Kit.is_phone(mode)
	var short := mode == Kit.LayoutMode.PHONE_LANDSCAPE
	_dossier_host.add_child(Kit.make_kicker("Golfer dossier", 10 if compact else 11))
	_sync_row_pressed()
	var entry := _selected_entry()
	if entry.is_empty():
		_dossier_host.add_child(Kit.make_label("No golfers are available on this device.",
			13, COLOR_MUTED))
		return

	var is_default := bool(entry.get("is_default", true))

	# Portrait with the name and the one-line identity beside it.
	var head := HBoxContainer.new()
	head.name = "DossierHead"
	head.add_theme_constant_override("separation", 12)
	var portrait := GolferPortrait.new(entry)
	portrait.name = "DossierPortrait"
	portrait.accent_color = Color("7fb8d8") if is_default else COLOR_GOLD
	portrait.custom_minimum_size = Vector2(56.0 if compact else 72.0, 84.0 if short else (104.0 if compact else 122.0))
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(portrait)
	var head_text := VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.alignment = BoxContainer.ALIGNMENT_CENTER
	head_text.add_theme_constant_override("separation", 2)
	head.add_child(head_text)
	var name_lbl := Kit.make_label(str(entry.get("name", "Golfer")),
		18 if compact else 22, COLOR_TEXT)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_text.add_child(name_lbl)
	var archetype := Kit.make_label(str(entry.get("archetype", "Golfer")), 11 if compact else 12, COLOR_GOLD)
	archetype.clip_text = true
	archetype.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_text.add_child(archetype)
	var identity := Kit.make_label("Age %d  ·  %s  ·  %s" % [
		int(entry.get("age", 30)),
		str(entry.get("gender_name", "Male")),
		str(entry.get("marital_status_name", "Single"))], 9 if compact else 10, COLOR_MUTED)
	identity.clip_text = true
	identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_text.add_child(identity)
	_dossier_host.add_child(head)

	var saved_stamp := format_saved_at(str(entry.get("saved_at", "")))
	var source := "Default golfer" if is_default else \
		("Career golfer · saved %s" % saved_stamp if not saved_stamp.is_empty() else "Career golfer")
	var source_lbl := Kit.make_label(source, 10 if compact else 11,
		COLOR_QUIET if is_default else COLOR_GOLD)
	_dossier_host.add_child(source_lbl)

	# Skin and Skin Colours, as chips with the group each colour belongs to.
	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 6)
	var skin_caption := Kit.make_label("SKIN", 9 if compact else 10, COLOR_QUIET)
	skin_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skin_row.add_child(skin_caption)
	var skin_name := Kit.make_label(str(entry.get("skin_name", "Casual")), 10 if compact else 11, COLOR_TEXT)
	skin_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skin_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_name.clip_text = true
	skin_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	skin_row.add_child(skin_name)
	_dossier_host.add_child(skin_row)
	var chips := HBoxContainer.new()
	chips.name = "SkinColorChips"
	chips.add_theme_constant_override("separation", 6)
	var skin_colors: Variant = entry.get("skin_colors", {})
	if skin_colors is Dictionary:
		for group_name in ["Shirt", "Pants", "Cap", "Hair", "Skin"]:
			var chip_box := VBoxContainer.new()
			chip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chip_box.add_theme_constant_override("separation", 2)
			var swatch := ColorRect.new()
			swatch.name = "SkinColor_%s" % str(group_name)
			swatch.color = Color.from_string(str((skin_colors as Dictionary).get(group_name, "404040")), Color("404040"))
			swatch.custom_minimum_size = Vector2(0.0, SKIN_CHIP_HEIGHT)
			swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip_box.add_child(swatch)
			var chip_label := Kit.make_label(str(group_name).to_upper(), 7, COLOR_QUIET)
			chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip_box.add_child(chip_label)
			chips.add_child(chip_box)
	_dossier_host.add_child(chips)

	if not short:
		# Traits and Golfer Skills the golfer actually carries.
		var traits: Variant = entry.get("active_traits", [])
		var trait_text := ", ".join(PackedStringArray(traits)) if (traits is Array and not (traits as Array).is_empty()) else "No traits marked"
		var trait_lbl := Kit.make_label("Traits:  %s" % trait_text, 9 if compact else 10, COLOR_MUTED)
		trait_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trait_lbl.custom_minimum_size.y = MenuStyle.text_block(BODY_FONT, 10 if compact else 10, 1)
		_dossier_host.add_child(trait_lbl)
		var gskills: Variant = entry.get("active_golfer_skills", [])
		var gskill_text := ", ".join(PackedStringArray(gskills)) if (gskills is Array and not (gskills as Array).is_empty()) else "No golfer skills marked"
		var gskill_lbl := Kit.make_label("Golfer Skills:  %s" % gskill_text, 9 if compact else 10, COLOR_MUTED)
		gskill_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gskill_lbl.custom_minimum_size.y = MenuStyle.text_block(BODY_FONT, 10 if compact else 10, 1)
		_dossier_host.add_child(gskill_lbl)

		# The four abilities that come out of the Golf Skill points.
		for ability in [
			["Driving", float(entry.get("driving_pct", 50.0)) / 100.0],
			["Accuracy", float(entry.get("accuracy_pct", 50.0)) / 100.0],
			["Putting", float(entry.get("putting_pct", 50.0)) / 100.0],
			["Recovery", float(entry.get("recovery_pct", 50.0)) / 100.0],
		]:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			var ability_caption := Kit.make_label(str(ability[0]).to_upper(), 9 if compact else 10, COLOR_QUIET)
			ability_caption.custom_minimum_size.x = 62.0 if compact else 74.0
			ability_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(ability_caption)
			var bar: Control = Kit.make_progress_bar(float(ability[1]),
				COLOR_GOLD if ability[0] == "Accuracy" else COLOR_MINT, 8.0)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(bar)
			var pct := Kit.make_label("%4d%%" % roundi(float(ability[1]) * 100.0), 9 if compact else 10, COLOR_MUTED)
			pct.custom_minimum_size.x = 38.0
			pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(pct)
			_dossier_host.add_child(line)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	stats.add_child(_make_stat_tile("Age", str(int(entry.get("age", 30))), mode))
	stats.add_child(_make_stat_tile("Skill pts", str(int(entry.get("total_golf_points", 0))), mode))
	stats.add_child(_make_stat_tile("Avg skill", "%d%%" % roundi(float(entry.get("avg_golf_skill_pct", 0.0))), mode))
	_dossier_host.add_child(stats)

	_dossier_host.add_child(_make_hairline())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size.y = 2
	_dossier_host.add_child(spacer)

	var choose_button := Button.new()
	choose_button.name = "ChooseGolferButton"
	choose_button.text = "Choose This Golfer  ›"
	choose_button.tooltip_text = "Play the next tournament as %s" % str(entry.get("name", "this golfer"))
	choose_button.custom_minimum_size.y = 44.0 if compact else 52.0
	choose_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choose_button.add_theme_font_override("font", TITLE_FONT)
	choose_button.add_theme_font_size_override("font_size", 14 if compact else 16)
	MenuStyle.paint_primary(choose_button)
	choose_button.add_theme_color_override("font_color", MenuStyle.INK)
	choose_button.add_theme_color_override("font_hover_color", MenuStyle.INK)
	choose_button.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	choose_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	choose_button.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	choose_button.pressed.connect(_on_choose_pressed)
	_dossier_host.add_child(choose_button)

# ── Selection ─────────────────────────────────────────────────────────────

func _selected_entry() -> Dictionary:
	for entry in _golfers:
		if str(entry.get("id", "")) == _selected_id:
			return entry
	return {}

func _sync_row_pressed() -> void:
	for gid in _golfer_buttons:
		var btn: Button = _golfer_buttons[gid]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(str(gid) == _selected_id)

func _on_golfer_toggled(pressed: bool, golfer_id: String) -> void:
	if not pressed:
		if golfer_id == _selected_id and _golfer_buttons.has(golfer_id):
			(_golfer_buttons[golfer_id] as Button).set_pressed_no_signal(true)
		return
	_selected_id = golfer_id
	_render_dossier(_layout_mode)

func _on_choose_pressed() -> void:
	if _selected_id.is_empty():
		return
	golfer_chosen.emit(_selected_id)

func _on_delete_pressed(golfer_id: String) -> void:
	var target_name := golfer_id
	for entry in _golfers:
		if str(entry.get("id", "")) == golfer_id:
			target_name = str(entry.get("name", golfer_id))
			break
	_show_confirmation(
		"Delete saved golfer '%s'? They will be removed from this device." % target_name,
		"Delete golfer",
		func() -> void:
			if TournamentLibrary.delete_saved_golfer(golfer_id):
				EventBus.notify("Removed saved tournament golfer.", "info")
			else:
				EventBus.notify("That golfer could not be deleted.", "warning")
			if _selected_id == golfer_id:
				_selected_id = ""
			_reload_catalogue()
			_render_rows(_layout_mode)
			_render_dossier(_layout_mode))
