extends Control
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
##
## The screen sits on the same MenuBackdrop as the World Map and the other
## fullscreen menus, and composes for the window's shape the way they do:
##
##  * Desktop and tablet: the loadout library beside the field-notes
##    inspector, each scrolling on its own.
##  * Phone landscape: the same two panels side by side in a compact cut.
##  * Phone portrait: a scrollable journal whose tabs flip between the
##    library and the inspector.
##
## It wears the shared pixel look: MenuStyle's translucent cards on the
## backdrop, PixelButtonStyle's notched frames, and Pixelify Sans set by
## MenuScreenKit.

signal back_requested()

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_SURFACE_RAISED := MenuStyle.RAIL_BG
const COLOR_SURFACE_INSET := MenuStyle.INSET_BG
const COLOR_TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const COLOR_TEXT_SECONDARY := UIConstants.COLOR_TEXT_DIM
const COLOR_TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

const ROW_HEIGHT := 68.0
const ROW_GAP := 8
## Preferred panel widths; clamped down on narrow windows so nothing is
## clipped off the sides.
const MIN_LIBRARY_WIDTH := 340.0
const MIN_INSPECTOR_WIDTH := 420.0

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

## Live state: what is shown, what is selected, what is staged for reload.
var _rows_box: VBoxContainer = null
var _subtitle: Label = null
var _details: RichTextLabel = null
var _status: Label = null
var _apply_button: Button = null
var _uninstall_button: Button = null
var _file_dialog: FileDialog = null
var _selected_id: String = ""
var _infos: Array = []
var _search_query: String = ""

var _tabs: HBoxContainer = null
var _library: PanelContainer = null
var _inspector: PanelContainer = null
var _search: LineEdit = null
var _empty: Label = null
## Phone portrait journals flip between the two panes with tabs; every other
## shape shows them side by side, so tabs are not built at all.
var _compact := false
var _inspect_mobile := false

var _layout_mode: int = -1
var _built_size := Vector2.ZERO

func _ready() -> void:
	name = "ModsScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_build()

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _window_size() -> Vector2:
	return Kit.window_size_of(self)

func _on_screen_changed(window_size: Vector2, _scale: float) -> void:
	var mode := Kit.layout_mode_for(window_size)
	var width_delta := absf(window_size.x - _built_size.x)
	var height_delta := absf(window_size.y - _built_size.y)
	var needs_remeasure := width_delta > maxf(96.0, _built_size.x * 0.14) \
		or height_delta > maxf(72.0, _built_size.y * 0.14)
	if mode != _layout_mode or needs_remeasure:
		_build()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

## Show only the rows whose searchable text contains the search query.
func _filter_rows() -> void:
	if _rows_box == null or _search == null:
		return
	var count := 0
	for row in _rows_box.get_children():
		row.visible = _search.text.is_empty() or str(row.get_meta("search", "")).contains(_search.text.to_lower())
		if row.visible:
			count += 1
	if _empty != null:
		_empty.visible = count == 0

# =============================================================================
# BUILDING
# =============================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_saved_build_state()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_rows_box = null
	_subtitle = null
	_details = null
	_status = null
	_apply_button = null
	_uninstall_button = null
	_tabs = null
	_library = null
	_inspector = null
	_search = null
	_empty = null

	_layout_mode = Kit.layout_mode_for(_window_size())
	_built_size = _window_size()
	_compact = _layout_mode == Kit.LayoutMode.PHONE_PORTRAIT

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := Kit.outer_padding(_layout_mode, _built_size)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		frame.add_theme_constant_override(side, pad)
	add_child(frame)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", Kit.page_separation(_layout_mode))
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(page)

	page.add_child(_build_header(_layout_mode))

	var page_scrolled := _compact
	var body: Control
	match _layout_mode:
		Kit.LayoutMode.PHONE_PORTRAIT:
			body = _build_phone_portrait_body(_built_size)
		_:
			body = _build_desktop_body(_built_size, page_scrolled)
	page.add_child(body)

	page.add_child(_build_tools_strip())

	refresh()
	_restore_build_state()

## Remembers the live search text before the tree is thrown away for a
## rebuild, so a resize does not lose what the player typed.
func _saved_build_state() -> void:
	if is_instance_valid(_search):
		_search_query = _search.text

func _restore_build_state() -> void:
	if is_instance_valid(_search):
		_search.text = _search_query
		_filter_rows()

func _build_header(mode: int) -> Control:
	var header := Kit.make_screen_header(mode, "Mods", "The Mod Shed", "",
		func(): back_requested.emit())
	return header

func _build_desktop_body(view: Vector2, _page_scrolled: bool) -> Control:
	var body := HBoxContainer.new()
	body.name = "LibraryAndInspector"
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var library := _build_library_panel(_page_scrolled)
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(library)

	var inspector := _build_inspector_panel(_page_scrolled)
	inspector.custom_minimum_size.x = clampf(MIN_INSPECTOR_WIDTH, 200.0,
		view.x - MIN_LIBRARY_WIDTH - 24.0)
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(inspector)
	return body

func _build_phone_portrait_body(_view: Vector2) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "PhoneModsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var content := VBoxContainer.new()
	content.name = "ModJournal"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	_tabs = HBoxContainer.new()
	_tabs.name = "ModTabs"
	_tabs.add_theme_constant_override("separation", 6)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tab in ["Library", "Inspector"]:
		var is_inspector: bool = tab == "Inspector"
		var button := _button(tab, func() -> void:
			_inspect_mobile = is_inspector
			_update_panes())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(button)
	content.add_child(_tabs)

	var library := _build_library_panel(true, Kit.outer_padding(_layout_mode, _built_size))
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(library)

	var inspector := _build_inspector_panel(true)
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(inspector)

	_update_panes()
	return scroll

func _build_library_panel(page_scrolled: bool, pad: int = 12) -> PanelContainer:
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.42))
	panel.name = "LibraryPanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	_search = LineEdit.new()
	_search.name = "ModSearch"
	_search.placeholder_text = "Search your collection..."
	_search.custom_minimum_size.y = 44.0
	_search.add_theme_font_override("font", BODY_FONT)
	_search.add_theme_font_size_override("font_size", 13)
	_search.add_theme_color_override("font_color", COLOR_TEXT_BRIGHT)
	_search.add_theme_color_override("font_placeholder_color", COLOR_TEXT_QUIET)
	_search.add_theme_color_override("caret_color", COLOR_GOLD)
	_search.add_theme_color_override("selection_color", MenuStyle.with_alpha(COLOR_GOLD, 0.35))
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelButtonStyle.paint_field(_search, MenuStyle.with_alpha(COLOR_GOLD, 0.85),
		COLOR_SURFACE_INSET, 8)
	_search.text = _search_query
	_search.text_changed.connect(func(_text: String) -> void: _filter_rows())
	controls.add_child(_search)
	stack.add_child(controls)

	var caption := _label("LOADOUT / tick to enable · arrows set priority", 13, COLOR_GOLD,
		SUBTITLE_FONT)
	caption.uppercase = true
	stack.add_child(caption)

	_subtitle = _label("", 13, COLOR_TEXT_SECONDARY)
	_subtitle.name = "SubtitleLabel"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_subtitle)

	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if page_scrolled:
		list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		list_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list_scroll.custom_minimum_size.y = ROW_HEIGHT * 4.0 + 10.0
	stack.add_child(list_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "ModRows"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", ROW_GAP)
	list_scroll.add_child(_rows_box)

	_empty = _label("No matching mods. Try another search.", 13, COLOR_TEXT_QUIET)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_empty)

	_library = panel
	panel.custom_minimum_size.x = clampf(MIN_LIBRARY_WIDTH, 100.0,
		_built_size.x - pad * 2.0 - 8.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if not page_scrolled \
		else Control.SIZE_SHRINK_BEGIN
	return panel

func _build_inspector_panel(page_scrolled: bool) -> PanelContainer:
	var panel := Kit.make_panel(COLOR_SURFACE_RAISED,
		MenuStyle.with_alpha(MenuStyle.ACCENT_SECONDARY, 0.42))
	panel.name = "InspectorPanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.name = "InspectorStack"
	stack.add_theme_constant_override("separation", 8)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	var head := _label("FIELD NOTES / selected mod", 16, COLOR_GOLD, SUBTITLE_FONT)
	head.uppercase = true
	stack.add_child(head)

	var details_scroll := ScrollContainer.new()
	details_scroll.name = "DetailsScroll"
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	details_scroll.custom_minimum_size.y = 200.0
	if page_scrolled:
		details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		details_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(details_scroll)

	_details = RichTextLabel.new()
	_details.name = "ModDetails"
	_details.bbcode_enabled = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_override("font", BODY_FONT)
	_details.add_theme_font_size_override("normal_font_size", 15)
	_details.add_theme_color_override("default_color", UIConstants.COLOR_TEXT)
	details_scroll.add_child(_details)

	_uninstall_button = _button("Uninstall selected mod", _on_uninstall_pressed)
	stack.add_child(_uninstall_button)

	_status = _label("", 13, COLOR_MINT)
	_status.name = "StatusLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(_status)

	_inspector = panel
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if not page_scrolled \
		else Control.SIZE_SHRINK_BEGIN
	return panel

func _build_tools_strip() -> Control:
	var strip := HBoxContainer.new()
	strip.name = "Tools"
	strip.add_theme_constant_override("separation", 10)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_apply_button = _button("Apply & Reload", _on_apply_pressed, true)
	_apply_button.name = "ApplyButton"

	# Spread the bottom row across the full width instead of bunching the
	# secondary tools into the bottom-left corner on large screens.
	var buttons := Array([
		_button("+ Install ZIP", func() -> void:
			_file_dialog.popup_centered(get_viewport().get_visible_rect().size.min(Vector2(720, 480)) * 0.9), true),
		_button("Rescan", func() -> void:
			ModManager.discover()
			refresh("Library rescanned.")),
		_button("Mods folder", func() -> void: OS.shell_open(ModManager.mods_folder_path())),
		_button("Disable all", _on_disable_all_pressed),
		_apply_button,
	])
	for i in buttons.size():
		strip.add_child(buttons[i])
		if i < buttons.size() - 1:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			strip.add_child(spacer)

	var file_dialog := FileDialog.new()
	file_dialog.name = "ModFileDialog"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.zip", "Mod ZIP files")
	file_dialog.title = "Install a mod from ZIP"
	file_dialog.file_selected.connect(_on_zip_selected)
	add_child(file_dialog)
	_file_dialog = file_dialog

	return strip

func _update_panes() -> void:
	if _tabs == null:
		# Desktop, tablet and landscape phone: both panes share the screen.
		if _library != null:
			_library.visible = true
		if _inspector != null:
			_inspector.visible = true
		return
	_tabs.visible = true
	_library.visible = not _inspect_mobile
	_inspector.visible = _inspect_mobile

# =============================================================================
# REFRESH AND CONTENT
# =============================================================================

## Rebuild the list and details from the manager. `message` replaces the
## status line (results of installs and the like).
func refresh(message: String = "") -> void:
	if _rows_box == null:
		return
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
	if _apply_button != null:
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
	if _status != null:
		_status.tooltip_text = _status.text

func _make_row(info: Dictionary) -> Control:
	var mod_id: String = str(info.get("id", ""))
	var row := HBoxContainer.new()
	row.set_meta("search", (str(info.get("name", "")) + " " + mod_id + " " + str(info.get("description", ""))).to_lower())
	row.custom_minimum_size.y = ROW_HEIGHT
	row.name = "ModRow_" + mod_id.replace(".", "_").replace("-", "_")
	row.add_theme_constant_override("separation", 6)

	var check := CheckBox.new()
	check.name = "EnabledCheck"
	check.custom_minimum_size = Vector2(44.0, 44.0)
	check.button_pressed = bool(info.get("enabled", false))
	check.tooltip_text = "Load this mod"
	check.toggled.connect(func(on: bool) -> void:
		ModManager.set_mod_enabled(mod_id, on)
		_selected_id = mod_id
		refresh())
	row.add_child(check)

	var name_button := Button.new()
	name_button.name = "ModName"
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.text = row_title(info) + "\n" + row_badge(info).to_upper()
	name_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_button.clip_text = true
	name_button.custom_minimum_size.x = 40.0
	name_button.tooltip_text = str(info.get("description", ""))
	name_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	name_button.pressed.connect(func() -> void:
		_selected_id = mod_id
		_inspect_mobile = true
		_update_panes()
		_show_details()
		_refresh_row_highlights())
	row.add_child(name_button)

	var order_index: int = int(info.get("order_index", -1))
	var up := _row_button("▲", func() -> void:
		ModManager.move_mod(mod_id, -1)
		_selected_id = mod_id
		refresh())
	up.name = "MoveUp"
	up.tooltip_text = "Load earlier"
	up.disabled = order_index <= 0
	row.add_child(up)

	var down := _row_button("▼", func() -> void:
		ModManager.move_mod(mod_id, 1)
		_selected_id = mod_id
		refresh())
	down.name = "MoveDown"
	down.tooltip_text = "Load later (wins conflicts)"
	down.disabled = order_index < 0 or order_index >= ModManager.get_enabled_order().size() - 1
	row.add_child(down)
	return row

func _row_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(36.0, 36.0)
	button.add_theme_font_size_override("font_size", 15)
	Kit.paint_utility_button(button, false)
	button.pressed.connect(action)
	return button

func _refresh_row_highlights() -> void:
	for row in _rows_box.get_children():
		var name_button := row.get_node_or_null("ModName") as Button
		if name_button == null:
			continue
		var chosen: bool = row.name == "ModRow_" + _selected_id.replace(".", "_").replace("-", "_")
		Kit.paint_utility_button(name_button, chosen)
		name_button.add_theme_color_override("font_color",
			COLOR_GOLD if chosen else UIConstants.COLOR_TEXT)

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
	back_requested.emit()
	ModManager.apply_and_reload_scene()

# =============================================================================
# LOOK AND FEEL
# =============================================================================

func _label(text: String, font_size: int = 14, color: Color = COLOR_TEXT_BRIGHT,
		font: Font = BODY_FONT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44.0
	if accent:
		Kit.paint_action(button, true)
	else:
		Kit.paint_utility_button(button, false)
	button.pressed.connect(action)
	return button

# =============================================================================
# INPUT
# =============================================================================

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
		" · runs code (\\\"script\\\" permission)" if bool(info.get("has_script", false)) else " · data only (no code runs)"])
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
