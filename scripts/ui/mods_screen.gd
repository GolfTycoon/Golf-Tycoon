extends CenteredPanel
class_name ModsScreen
## ModsScreen - The player's mod library: what is installed, what is on,
## and the order it loads in.
##
## The list *is* the load order: enabled mods sit at the top in the order
## they will load (arrow buttons move them - later wins data conflicts,
## provider take-overs and hook order), disabled mods follow
## alphabetically. The details pane says where each mod came from (bundled,
## the mods folder, a zip, the Steam Workshop), what it needs, what the
## loader complained about, and which of the environment systems each mod
## currently provides.
##
## Toggling or reordering writes the player's list
## (user://mods/load_order.json) straight away but changes nothing live:
## **Apply & Reload** re-runs the loader and reloads the scene, so a course
## in play is never half re-modded. Installing a zip copies it into the
## library still disabled - installing is never enabling.

signal close_requested

var _rows_box: VBoxContainer = null
var _subtitle: Label = null
var _details: RichTextLabel = null
var _status: Label = null
var _apply_button: Button = null
var _uninstall_button: Button = null
var _file_dialog: FileDialog = null
var _selected_id: String = ""
var _infos: Array = []


const INK := Color("142c30")
const MINT := Color("a9e4b0")
const CREAM := Color("f3e9c5")
var _workspace: VBoxContainer
var _body: HBoxContainer
var _library: VBoxContainer
var _inspector: PanelContainer
var _tabs: HBoxContainer
var _search: LineEdit
var _empty: Label
var _compact := false
var _inspect_mobile := false


func _panel_style(fill: Color, edge: Color = Color("45645b")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(4, 4)
	return style


func _button(text: String, action: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_stylebox_override("normal", _panel_style(Color("315c4c") if accent else Color("243e40")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("426c56"), MINT))
	button.add_theme_stylebox_override("focus", _panel_style(Color("315c4c"), CREAM))
	button.add_theme_color_override("font_color", CREAM)
	button.pressed.connect(action)
	return button


func _label(text: String, font_size: int = 14, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_ui() -> void:
	add_theme_stylebox_override("panel", _panel_style(INK, MINT))
	add_theme_font_override("font", preload("res://assets/fonts/PixelifySans-Regular.ttf"))
	add_theme_font_size_override("font_size", 16)
	var outer_scroll := ScrollContainer.new()
	outer_scroll.name = "WorkspaceScroll"
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(outer_scroll)
	var column := VBoxContainer.new()
	_workspace = column
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size.y = 500
	column.add_theme_constant_override("separation", 10)
	outer_scroll.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	heading.add_child(_label("THE MOD SHED", 28, MINT))
	_subtitle = _label("")
	_subtitle.name = "SubtitleLabel"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_subtitle)
	header.add_child(_button("Back", func() -> void: close_requested.emit()))
	var banner := preload("res://scripts/ui/mods_pixel_banner.gd").new()
	banner.custom_minimum_size.y = 64
	column.add_child(banner)
	var hint := _label("BUILD YOUR OWN GAME  /  Load top to bottom. Later mods win conflicts.", 14, MINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_tabs = HBoxContainer.new()
	column.add_child(_tabs)
	for tab in ["Library", "Inspector"]:
		var is_inspector: bool = tab == "Inspector"
		var button := _button(tab, func() -> void:
			_inspect_mobile = is_inspector
			_update_panes())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(button)
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	column.add_child(_body)
	_library = VBoxContainer.new()
	_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_library)
	_search = LineEdit.new()
	_search.name = "ModSearch"
	_search.placeholder_text = "Search your collection..."
	_search.custom_minimum_size.y = 44
	_search.text_changed.connect(func(_text: String) -> void: _filter_rows())
	_library.add_child(_search)
	_library.add_child(_label("LOADOUT / tick to enable · arrows set priority", 13, MINT))
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library.add_child(list_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "ModRows"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	list_scroll.add_child(_rows_box)
	_empty = _label("No matching mods. Try another search.")
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_library.add_child(_empty)
	_inspector = PanelContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_stylebox_override("panel", _panel_style(Color("203b39")))
	_body.add_child(_inspector)
	var details_box := VBoxContainer.new()
	_inspector.add_child(details_box)
	details_box.add_child(_label("FIELD NOTES / selected mod", 16, MINT))
	_details = RichTextLabel.new()
	_details.name = "ModDetails"
	_details.bbcode_enabled = true
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.add_theme_font_size_override("normal_font_size", 16)
	_details.add_theme_color_override("default_color", CREAM)
	details_box.add_child(_details)
	_uninstall_button = _button("Uninstall selected mod", _on_uninstall_pressed)
	details_box.add_child(_uninstall_button)
	_status = _label("", 13, MINT)
	_status.name = "StatusLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_status)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	column.add_child(tools)
	tools.add_child(_button("+ Install ZIP", func() -> void:
		_file_dialog.popup_centered(get_viewport().get_visible_rect().size.min(Vector2(720, 480)) * 0.9), true))
	tools.add_child(_button("Rescan", func() -> void:
		ModManager.discover()
		refresh("Library rescanned.")))
	tools.add_child(_button("Mods folder", func() -> void: OS.shell_open(ModManager.mods_folder_path())))
	tools.add_child(_button("Disable all", _on_disable_all_pressed))
	_apply_button = _button("Apply & Reload", _on_apply_pressed, true)
	column.add_child(_apply_button)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.zip", "Mod ZIP files")
	_file_dialog.title = "Install a mod from ZIP"
	_file_dialog.file_selected.connect(_on_zip_selected)
	add_child(_file_dialog)
	refresh()


# Unlike generic centered popups, this workspace owns its responsive layout:
# independent scroll regions, no desktop-width content inside a phone scroller.
func _layout_to_screen() -> void:
	var area := Screen.available_panel_rect()
	_compact = area.size.x < 700
	custom_minimum_size = Vector2.ZERO
	_update_panes()
	var target := area.size.min(Vector2(1320, 900))
	size = target
	position = area.position + (area.size - target) / 2.0


func _update_panes() -> void:
	_tabs.visible = _compact
	_library.visible = not _compact or not _inspect_mobile
	_inspector.visible = not _compact or _inspect_mobile


func _filter_rows() -> void:
	var count := 0
	for row in _rows_box.get_children():
		row.visible = _search.text.is_empty() or str(row.get_meta("search", "")).contains(_search.text.to_lower())
		if row.visible:
			count += 1
	_empty.visible = count == 0


## Rebuild the list and details from the manager. `message` replaces the
## status line (results of installs and the like).
func refresh(message: String = "") -> void:
	_infos = ModManager.get_all_mod_infos()
	if not ModManager.get_mod_info(_selected_id).is_empty():
		pass
	elif not _infos.is_empty():
		_selected_id = str(_infos[0].get("id", ""))
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	for info in _infos:
		_rows_box.add_child(_make_row(info))
	if _subtitle != null:
		_subtitle.text = "   %d found · %d enabled · %d loaded" % [
			_infos.size(), ModManager.get_enabled_order().size(), ModManager.get_load_order().size()]
	_filter_rows()
	_show_details()
	_apply_button.disabled = not ModManager.needs_reload
	if not message.is_empty():
		_status.text = message
	elif ModManager.safe_mode_triggered:
		_status.text = "A previous session stopped while loading script mods, so this session loaded data only (safe mode). Press Apply & Reload to try the set again."
	elif ModManager.mods_disabled_by_flag:
		_status.text = "Started with --no-mods: nothing loads this session. The list above is still saved for next time."
	elif not ModManager.get_discovery_warnings().is_empty():
		_status.text = "While scanning: " + " · ".join(ModManager.get_discovery_warnings())
	else:
		_status.text = "Changes are staged. Apply & Reload to put your loadout into play."
	_status.tooltip_text = _status.text


func _make_row(info: Dictionary) -> Control:
	var mod_id: String = str(info.get("id", ""))
	var row := HBoxContainer.new()
	row.set_meta("search", (str(info.get("name", "")) + " " + mod_id + " " + str(info.get("description", ""))).to_lower())
	row.custom_minimum_size.y = 68
	row.name = "ModRow_" + mod_id.replace(".", "_").replace("-", "_")
	row.add_theme_constant_override("separation", 6)
	var check := CheckBox.new()
	check.name = "EnabledCheck"
	check.custom_minimum_size = Vector2(44, 44)
	check.button_pressed = bool(info.get("enabled", false))
	check.tooltip_text = "Load this mod"
	check.toggled.connect(func(on: bool) -> void:
		ModManager.set_mod_enabled(mod_id, on)
		_selected_id = mod_id
		refresh())
	row.add_child(check)
	var name_button := Button.new()
	name_button.name = "ModName"
	name_button.flat = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.text = row_title(info) + "\n" + row_badge(info).to_upper()
	name_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_button.clip_text = true
	name_button.custom_minimum_size.x = 40
	name_button.tooltip_text = str(info.get("description", ""))
	name_button.pressed.connect(func() -> void:
		_selected_id = mod_id
		_inspect_mobile = true
		_update_panes()
		_show_details()
		_refresh_row_highlights())
	row.add_child(name_button)
	var order_index: int = int(info.get("order_index", -1))
	var up := _button("", func() -> void: pass)
	up.name = "MoveUp"
	up.text = "▲"
	up.tooltip_text = "Load earlier"
	up.disabled = order_index <= 0
	up.pressed.connect(func() -> void:
		ModManager.move_mod(mod_id, -1)
		_selected_id = mod_id
		refresh())
	row.add_child(up)
	var down := _button("", func() -> void: pass)
	down.name = "MoveDown"
	down.text = "▼"
	down.tooltip_text = "Load later (wins conflicts)"
	down.disabled = order_index < 0 or order_index >= ModManager.get_enabled_order().size() - 1
	down.pressed.connect(func() -> void:
		ModManager.move_mod(mod_id, 1)
		_selected_id = mod_id
		refresh())
	row.add_child(down)
	return row


func _refresh_row_highlights() -> void:
	for row in _rows_box.get_children():
		var name_button := row.get_node_or_null("ModName") as Button
		if name_button == null:
			continue
		var chosen: bool = row.name == "ModRow_" + _selected_id.replace(".", "_").replace("-", "_")
		name_button.add_theme_stylebox_override("normal", _panel_style(Color("315344") if chosen else Color("203b39"), MINT if chosen else Color("45645b")))
		name_button.add_theme_color_override("font_color",
			UIConstants.COLOR_GOLD if chosen else UIConstants.COLOR_TEXT)


func _show_details() -> void:
	var info: Dictionary = ModManager.get_mod_info(_selected_id)
	_details.text = details_text(info, ModManager.provider_owners(),
		ContentRegistry.get_conflicts(), ContentRegistry.get_warnings())
	_uninstall_button.disabled = info.is_empty() or not bool(info.get("can_uninstall", false))
	_refresh_row_highlights()


func _on_zip_selected(path: String) -> void:
	var result: Dictionary = ModManager.install_zip(path)
	if bool(result.get("ok", false)):
		_selected_id = str(result.get("mod_id", ""))
		refresh("Installed %s - still disabled. Tick it, then Apply & Reload." % _selected_id)
	else:
		refresh("That zip is not a Golf Tycoon mod: %s" % "; ".join(result.get("errors", ["unknown error"])))


func _on_disable_all_pressed() -> void:
	for info in _infos:
		ModManager.set_mod_enabled(str(info.get("id", "")), false)
	refresh("Every mod is off. Apply & Reload to run the plain game - its built-in weather, wind and seasons stand-ins keep everything working.")


func _on_uninstall_pressed() -> void:
	var result: Dictionary = ModManager.uninstall_mod(_selected_id)
	if bool(result.get("ok", false)):
		_selected_id = ""
		refresh("Uninstalled.")
	else:
		refresh("Could not uninstall: %s" % "; ".join(result.get("errors", [])))


func _on_apply_pressed() -> void:
	# The screen does not survive the reload it asks for.
	close_requested.emit()
	ModManager.apply_and_reload_scene()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


# =============================================================================
# ROW AND DETAIL TEXT (pure, unit-tested)
# =============================================================================

static func row_title(info: Dictionary) -> String:
	var place: String = ""
	var order_index: int = int(info.get("order_index", -1))
	if order_index >= 0:
		place = "%d. " % (order_index + 1)
	return "%s%s  %s" % [place, str(info.get("name", info.get("id", "?"))), str(info.get("version", ""))]


static func row_badge(info: Dictionary) -> String:
	if not (info.get("errors", []) as Array).is_empty():
		return "won't load"
	if bool(info.get("loaded", false)):
		return "loaded"
	if bool(info.get("enabled", false)):
		return "pending apply"
	return str(info.get("source", ""))


static func details_text(info: Dictionary, providers: Dictionary,
		conflicts: Array, registry_warnings: Array) -> String:
	if info.is_empty():
		return "No mod selected.\n\nInstall one from a zip, or drop a mod folder into the mods folder and Rescan."
	var lines: Array[String] = []
	lines.append("[font_size=20][b]%s[/b][/font_size]  %s" % [info.get("name", ""), info.get("version", "")])
	lines.append("[color=#b9c7af]%s · %s[/color]" % [info.get("id", ""), info.get("source_label", "")])
	if not str(info.get("author", "")).is_empty():
		lines.append("by %s" % info.get("author", ""))
	lines.append("")
	lines.append(str(info.get("description", "")))
	lines.append("")
	var types: Array = info.get("types", [])
	lines.append("Kind: %s%s" % [", ".join(types) if not types.is_empty() else "mod",
		" · runs code (\"script\" permission)" if bool(info.get("has_script", false)) else " · data only (no code runs)"])
	var dependencies: Array = info.get("dependencies", [])
	if not dependencies.is_empty():
		lines.append("Needs: " + ", ".join(dependencies))
	var declared_conflicts: Array = info.get("conflicts_declared", [])
	if not declared_conflicts.is_empty():
		lines.append("Conflicts with: " + ", ".join(declared_conflicts))
	if bool(info.get("auto_enabled", false)) and not bool(info.get("enabled", false)):
		lines.append("Loaded because another enabled mod depends on it.")
	for message in info.get("errors", []):
		lines.append("[color=#e06666]%s[/color]" % str(message))
	for message in info.get("warnings", []):
		lines.append("[color=#e5e57c]%s[/color]" % str(message))
	var mod_id: String = str(info.get("id", ""))
	for conflict in conflicts:
		if str(conflict).contains(mod_id):
			lines.append("[color=#e5e57c]Data: %s[/color]" % str(conflict))
	for warning in registry_warnings:
		if str(warning).begins_with("[%s]" % mod_id):
			lines.append("[color=#e5e57c]Data: %s[/color]" % str(warning))
	lines.append("")
	lines.append("[b]This session[/b]")
	lines.append("Weather: %s" % str(providers.get("weather", "?")))
	lines.append("Wind: %s" % str(providers.get("wind", "?")))
	lines.append("Seasons: %s" % str(providers.get("seasons", "?")))
	return "\n".join(lines)
