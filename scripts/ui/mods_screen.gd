extends Control
class_name ModsScreen
## ModsScreen - Fullscreen mod management UI.
##
## Shows every discovered mod (builtin + user), its enabled state, ordering,
## dependencies, conflicts, and description. Players can:
##   - Enable / disable mods (with dependency checks)
##   - Reorder enabled mods via Up/Down (later = higher priority, wins conflicts)
##   - View conflict report
##   - See which save's mods would be loaded
##
## The enabled order is the "ordered list to help resolve mod conflicts" the
## task requires: later entries override earlier ones.
##
## Styling matches the other fullscreen goal/world-map screens (MenuScreenKit,
## MenuStyle, PixelButtonStyle, MenuBackdrop).

signal back_requested
signal mods_applied()  # emitted after enabled order changes (for caller to react)

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

var _layout_mode: int = Kit.LayoutMode.DESKTOP
var _built_size := Vector2.ZERO
var _conflict_label: Label = null
var _enabled_column: VBoxContainer = null
var _available_column: VBoxContainer = null
var _selected_id: String = ""
var _detail_title: Label = null
var _detail_version: Label = null
var _detail_desc: Label = null
var _detail_deps: Label = null
var _detail_conflicts: Label = null
var _detail_perms: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_build()
	if has_node("/root/InputManager"):
		InputManager.register_scope(self)
	if has_node("/root/ModManager"):
		ModManager.enabled_order_changed.connect(_on_order_changed)
		ModManager.mod_error.connect(_on_mod_error)
		ModManager.conflict_detected.connect(_on_conflicts)

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)

func _on_screen_changed(sz: Vector2, _scale: float) -> void:
	var new_mode := Kit.layout_mode_for(sz)
	if new_mode != _layout_mode:
		_build()
	elif _built_size != Vector2.ZERO and (absf(sz.x - _built_size.x) > 100 or absf(sz.y - _built_size.y) > 100):
		_build()

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_layout_mode = Kit.layout_mode_for(_window_size())
	_built_size = _window_size()

	var backdrop := MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var pad := Kit.outer_padding(_layout_mode, _window_size())
	var page := _make_page(pad)
	var header := Kit.make_screen_header(_layout_mode, "Mods", "Game modifications", "Enable mods and drag them into the order they should load — later mods override earlier ones", func(): back_requested.emit())
	page.add_child(header)

	# Conflict banner
	_conflict_label = Label.new()
	_conflict_label.name = "ConflictReport"
	_conflict_label.add_theme_font_override("font", Kit.BODY_FONT)
	_conflict_label.add_theme_font_size_override("font_size", 12)
	_conflict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.add_child(_conflict_label)
	_refresh_conflicts()

	# Two columns: enabled (ordered) and available (disabled)
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	page.add_child(columns)

	_enabled_column = _make_section_column("Enabled — drag to reorder", true)
	_available_column = _make_section_column("Available — click to enable", false)
	columns.add_child(_enabled_column)
	columns.add_child(_available_column)

	_refresh_lists()

	# Detail panel (selected mod info)
	var detail_panel := _make_detail_panel()
	page.add_child(detail_panel)
	if not _selected_id.is_empty():
		_show_detail(_selected_id)
	elif ModManager and not ModManager.manifests.is_empty():
		_show_detail(str(ModManager.manifests.keys()[0]))

	# Footer actions
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	page.add_child(footer)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.tooltip_text = "Restore the default set of enabled mods"
	Kit.paint_utility_button(reset_btn, false)
	reset_btn.pressed.connect(_on_reset_defaults)
	footer.add_child(reset_btn)
	var apply_btn := Button.new()
	apply_btn.text = "Apply & Reload"
	apply_btn.tooltip_text = "Apply changes and reload enabled mods"
	Kit.paint_action(apply_btn, true)
	apply_btn.pressed.connect(_on_apply)
	footer.add_child(apply_btn)

func _make_page(pad: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.name = "Page"
	margin.custom_minimum_size = _window_size() - Vector2(pad * 2, pad * 2)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "PageColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", Kit.page_separation(_layout_mode))
	margin.add_child(column)
	return column

func _make_section_column(title: String, is_enabled_section: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Mods_" + ("Enabled" if is_enabled_section else "Available")
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var kicker := Kit.make_kicker(title, 11)
	box.add_child(kicker)
	# Header panel for the list
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.55), MenuStyle.RAIL_BG, 8, 8))
	var margin := MarginContainer.new()
	for s in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + s, 6)
	panel.add_child(margin)
	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 6)
	margin.add_child(list)
	box.add_child(panel)
	return box

func _make_detail_panel() -> Control:
	var panel := Kit.make_panel(Kit.COLOR_SURFACE_RAISED, MenuStyle.with_alpha(Kit.COLOR_BORDER_SOFT, 0.55))
	panel.name = "DetailPanel"
	var margin := MarginContainer.new()
	for s in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + s, 12)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.name = "DetailColumn"
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)
	_detail_title = Kit.make_title_label("", 18, Kit.COLOR_GOLD)
	_detail_title.name = "DetailTitle"
	col.add_child(_detail_title)
	_detail_version = Kit.make_label("", 11, Kit.COLOR_TEXT_SECONDARY)
	col.add_child(_detail_version)
	_detail_desc = Kit.make_label("", 12, Kit.COLOR_TEXT_SECONDARY)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_detail_desc)
	_detail_deps = Kit.make_label("", 11, Kit.COLOR_TEXT_QUIET)
	_detail_deps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_detail_deps)
	_detail_conflicts = Kit.make_label("", 11, UIConstants.COLOR_WARNING)
	_detail_conflicts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_detail_conflicts)
	_detail_perms = Kit.make_label("", 10, Kit.COLOR_TEXT_QUIET)
	col.add_child(_detail_perms)
	return panel

# ---------------------------------------------------------------------------
# List population
# ---------------------------------------------------------------------------

func _refresh_lists() -> void:
	if _enabled_column == null or _available_column == null:
		return
	_clear_list(_enabled_column)
	_clear_list(_available_column)
	if not has_node("/root/ModManager"):
		_add_placeholder(_available_column, "ModManager not available")
		return
	var mm = get_node("/root/ModManager")
	# Enabled — in order
	for idx in mm.enabled_mods.size():
		var eid: String = str(mm.enabled_mods[idx])
		var mani: ModManifest = mm.manifests.get(eid, null)
		if mani == null:
			continue
		_add_mod_row(_enabled_column, mani, true, idx, mm.enabled_mods.size())
	# Available (not enabled)
	for mid in mm.manifests:
		if mm.enabled_mods.has(mid):
			continue
		var mani2: ModManifest = mm.manifests[mid]
		_add_mod_row(_available_column, mani2, false, -1, -1)

func _clear_list(section: VBoxContainer) -> void:
	var list := section.find_child("List", true, false) as VBoxContainer
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

func _add_mod_row(section: VBoxContainer, mani: ModManifest, is_enabled: bool, index: int, total: int) -> void:
	var list := section.find_child("List", true, false) as VBoxContainer
	if list == null:
		return
	var row := PanelContainer.new()
	row.name = "ModRow_%s" % mani.id
	# Highlight selected
	var is_selected := _selected_id == mani.id
	row.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.85) if is_selected else MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.35),
		MenuStyle.RAIL_BG if not is_selected else MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.12), 6, 4))
	# Click to select
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_selected_id = mani.id
			_show_detail(mani.id)
			_refresh_lists()
			get_viewport().set_input_as_handled())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	# Info column
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hbox.add_child(info)
	var title := Kit.make_semibold_label(mani.name, 13, Kit.COLOR_TEXT_BRIGHT if is_enabled else Kit.COLOR_TEXT_SECONDARY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	var meta := Kit.make_label("v%s by %s · %s" % [mani.version, mani.author, mani.id], 10, Kit.COLOR_TEXT_QUIET)
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(meta)

	# Actions column
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(actions)
	if is_enabled:
		# Up / Down for reordering
		var up_btn := Button.new()
		up_btn.text = "▲"
		up_btn.tooltip_text = "Move up (higher priority earlier)"
		up_btn.disabled = index == 0
		Kit.paint_utility_button(up_btn, false)
		up_btn.custom_minimum_size = Vector2(28, 24)
		up_btn.pressed.connect(_on_move.bind(mani.id, -1))
		actions.add_child(up_btn)
		var down_btn := Button.new()
		down_btn.text = "▼"
		down_btn.tooltip_text = "Move down (later wins conflicts)"
		down_btn.disabled = index >= total - 1
		Kit.paint_utility_button(down_btn, false)
		down_btn.custom_minimum_size = Vector2(28, 24)
		down_btn.pressed.connect(_on_move.bind(mani.id, 1))
		actions.add_child(down_btn)
		var disable_btn := Button.new()
		disable_btn.text = "Disable"
		disable_btn.tooltip_text = "Disable this mod"
		if mani.is_builtin:
			# Builtins can still be disabled (player choice), but warn
			disable_btn.tooltip_text += " (builtin, can be re-enabled anytime)"
		Kit.paint_utility_button(disable_btn, false)
		disable_btn.custom_minimum_size = Vector2(56, 26)
		disable_btn.pressed.connect(_on_toggle.bind(mani.id, false))
		actions.add_child(disable_btn)
	else:
		var enable_btn := Button.new()
		enable_btn.text = "Enable"
		enable_btn.tooltip_text = "Enable this mod (will be added at the end of the list)"
		Kit.paint_action(enable_btn, false)
		enable_btn.custom_minimum_size = Vector2(56, 26)
		enable_btn.pressed.connect(_on_toggle.bind(mani.id, true))
		actions.add_child(enable_btn)

	# Mod state badge
	var state_badge: Label = null
	if has_node("/root/ModManager"):
		var mobj: Mod = get_node("/root/ModManager").mods.get(mani.id, null)
		if mobj and mobj.state == Mod.State.FAILED:
			state_badge = Kit.make_chip("FAILED", UIConstants.COLOR_DANGER, Color.WHITE, 9)
			info.add_child(state_badge)

	list.add_child(row)

func _add_placeholder(section: VBoxContainer, text: String) -> void:
	var list := section.find_child("List", true, false) as VBoxContainer
	if list == null:
		return
	var label := Kit.make_label(text, 12, Kit.COLOR_TEXT_QUIET)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(label)

func _show_detail(mod_id: String) -> void:
	_selected_id = mod_id
	if not has_node("/root/ModManager"):
		return
	var mani: ModManifest = get_node("/root/ModManager").manifests.get(mod_id, null)
	if mani == null:
		return
	if _detail_title:
		_detail_title.text = mani.name
	if _detail_version:
		_detail_version.text = "%s · v%s · API %s · by %s  ·  %s" % [mani.id, mani.version, mani.api_version, mani.author, mani.category]
	if _detail_desc:
		_detail_desc.text = mani.description
	if _detail_deps:
		var lines: Array[String] = []
		if not mani.dependencies.is_empty():
			lines.append("Requires: " + ", ".join(mani.dependencies))
		if not mani.optional_dependencies.is_empty():
			lines.append("Optionally after: " + ", ".join(mani.optional_dependencies))
		if not mani.conflicts.is_empty():
			lines.append("Conflicts: " + ", ".join(mani.conflicts))
		if not mani.load_after.is_empty():
			lines.append("Load after: " + ", ".join(mani.load_after))
		_detail_deps.text = "\n".join(lines)
	if _detail_conflicts:
		# Show conflict for this mod
		var mm = get_node("/root/ModManager")
		var relevant: Array[String] = []
		for c in mm.last_conflicts:
			if c.get("mod_a", "") == mod_id or c.get("mod_b", "") == mod_id:
				relevant.append("%s ↔ %s: %s" % [c.get("mod_a","?"), c.get("mod_b","?"), c.get("reason","")])
		_detail_conflicts.text = "\n".join(relevant) if not relevant.is_empty() else ""
		_detail_conflicts.visible = not _detail_conflicts.text.is_empty()
	if _detail_perms:
		_detail_perms.text = "Permissions: " + (", ".join(mani.permissions) if not mani.permissions.is_empty() else "none") + "   Tags: " + (", ".join(mani.tags) if not mani.tags.is_empty() else "none")

func _refresh_conflicts() -> void:
	if _conflict_label == null:
		return
	if not has_node("/root/ModManager"):
		_conflict_label.text = ""
		return
	var mm = get_node("/root/ModManager")
	var report: String = mm.get_conflict_report()
	if report == "No conflicts.":
		_conflict_label.text = "No conflicts — ordering is clean. Later enabled mods override earlier ones."
		_conflict_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	else:
		_conflict_label.text = "Conflicts: " + report
		_conflict_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_toggle(mod_id: String, should_enable: bool) -> void:
	if not has_node("/root/ModManager"):
		return
	var ok: bool = get_node("/root/ModManager").set_mod_enabled(mod_id, should_enable)
	if not ok:
		EventBus.notify("Could not %s %s — check dependencies. See detail panel." % [("enable" if should_enable else "disable"), mod_id], "error")
	_refresh_lists()
	_refresh_conflicts()
	_show_detail(mod_id)

func _on_move(mod_id: String, delta: int) -> void:
	if not has_node("/root/ModManager"):
		return
	var mm = get_node("/root/ModManager")
	var idx: int = mm.enabled_mods.find(mod_id)
	if idx < 0:
		return
	var new_idx := clampi(idx + delta, 0, mm.enabled_mods.size() - 1)
	mm.move_mod(mod_id, new_idx)
	_refresh_lists()
	_refresh_conflicts()

func _on_reset_defaults() -> void:
	if has_node("/root/ModManager"):
		get_node("/root/ModManager").reset_to_defaults()
	_refresh_lists()
	_refresh_conflicts()
	EventBus.notify("Mods reset to defaults", "info")

func _on_apply() -> void:
	# Persist already happens on each enable/move; this is a hook for future reload
	EventBus.notify("Mods applied — new games will use this order. Restart or start a new game to fully reload.", "success")
	mods_applied.emit()

func _on_order_changed(_order: Array) -> void:
	_refresh_lists()
	_refresh_conflicts()

func _on_mod_error(mod_id: String, msg: String) -> void:
	EventBus.notify("Mod %s error: %s" % [mod_id, msg], "error")

func _on_conflicts(_list: Array) -> void:
	_refresh_conflicts()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
