extends Control
class_name ModsScreen
## ModsScreen - The player's mod library: what is installed, what is on,
## and the order it loads in.
##
## The list *is* the load order, with a place in it for every mod: the
## enabled ones load from the top of the list down (later wins data
## conflicts, provider take-overs and hook order) and carry their place as
## the number in front of their name. Dragging a row (or its grip handle) or
## pressing its arrow buttons moves any mod up or down the list, enabled or
## not, and its row moves with it; ticking a mod on or off never moves its
## row. ModManager keeps the order: it starts as
## the order the game first found each mod, a mod new to the player joins
## the bottom, and one that is taken away and put back returns to its
## place. The search box and the All / Enabled / Disabled filter chips
## narrow the list without touching the loadout or the order. The details
## pane says where each mod came from (bundled, the mods folder, a zip, the
## Steam Workshop), what it needs, what the loader complained about.
##
## Toggling or reordering writes the player's lists
## (user://mods/load_order.json, user://mods/library_order.json) straight
## away, and the new loadout is put into play the moment the player leaves
## the screen: Back (or Esc, or the header's Back) re-runs the loader and
## reloads the scene, so the changes land whole and a course in play is
## never half re-modded. There is no Apply button to press and nothing to
## forget; leaving with the list unchanged reloads nothing. Installing a
## zip copies it into the library still disabled - installing is never
## enabling. **Create New Mod** scaffolds a fresh folder in the same
## library (mod.json, an optional starter script and a README) and likewise
## leaves it off until the player ticks it.
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
## The header's Browse Mods button was pressed: the game's mod repositories
## (the Official one included, by default) open on the Browse Mods screen.
signal browse_requested()

## Which mods the list shows, on top of whatever the search box asks for. A
## filter only narrows the view: it never enables, disables or reorders.
enum Filter { ALL, ENABLED, DISABLED }

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_SURFACE_RAISED := MenuStyle.RAIL_BG
const COLOR_SURFACE_INSET := MenuStyle.INSET_BG
const COLOR_TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const COLOR_TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

const ROW_HEIGHT := 68.0
const ROW_GAP := 8
## The picture inside a list row's mod button: the mod's own icon, or the
## default mark when the mod ships none.
const ROW_ICON_SIZE := 44.0
## The same picture at the head of the field-notes pane.
const DETAIL_ICON_SIZE := 64.0
## Preferred panel widths; clamped down on narrow windows so nothing is
## clipped off the sides.
const MIN_LIBRARY_WIDTH := 340.0
const MIN_INSPECTOR_WIDTH := 420.0
## The search box never gets squeezed thinner than this by the filter chips
## that share its row.
const MIN_SEARCH_WIDTH := 96.0
## Desktop filter chips are all this wide, so the three read as one switch
## whatever the length of their words.
const FILTER_CHIP_WIDTH := 90.0
## Pointer travel (px) before a press on a row lifts it to reorder, so a
## click or tap still selects the mod without twitching the list.
const DRAG_THRESHOLD := 6.0
## Hysteresis (px) either side of the midpoint between two slots, so holding
## the pointer on the boundary never flickers a row back and forth.
const DRAG_SWAP_HYSTERESIS := 2.0
## Strip at the top and bottom of the scrolling list where holding a dragged
## row scrolls more of the library into reach.
const DRAG_SCROLL_MARGIN := 52.0
const DRAG_SCROLL_MAX_SPEED := 520.0
const DRAG_HANDLE_WIDTH := 22.0
const DRAG_HANDLE_WIDTH_PHONE := 26.0

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

## Pixel six-dot grip on the leading edge of each mod row. Gives pointer
## players an unmistakable place to grab, and owns raw touch gestures on
## mobile (through "native_touch_input") so dragging the grip reorders the row
## while swiping anywhere else on the list keeps scrolling it.
class DragHandle extends Control:
	var disabled: bool = false:
		set(value):
			if disabled == value:
				return
			disabled = value
			mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_DRAG
			tooltip_text = "" if disabled else "Drag up or down to reorder"
			queue_redraw()
	var dragging: bool = false:
		set(value):
			if dragging == value:
				return
			dragging = value
			queue_redraw()
	var _hovered: bool = false

	func _init(handle_width: float = DRAG_HANDLE_WIDTH, interactive: bool = true) -> void:
		name = "DragHandle" if interactive else "PreviewGrip"
		custom_minimum_size = Vector2(handle_width, 44.0)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_NONE
		if interactive:
			mouse_filter = Control.MOUSE_FILTER_STOP
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			tooltip_text = "Drag up or down to reorder"
			add_to_group("native_touch_input")
			mouse_entered.connect(func() -> void:
				_hovered = true
				queue_redraw())
			mouse_exited.connect(func() -> void:
				_hovered = false
				queue_redraw())
		else:
			mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var dot_color: Color
		if disabled:
			dot_color = MenuStyle.with_alpha(GuiTheme.remap_color(COLOR_TEXT_QUIET), 0.30)
		elif dragging or _hovered:
			dot_color = GuiTheme.remap_color(COLOR_GOLD)
		else:
			dot_color = GuiTheme.remap_color(MenuStyle.ACCENT_UTILITY)
		var shadow_color := Color(PixelButtonStyle.INK.r, PixelButtonStyle.INK.g,
			PixelButtonStyle.INK.b, dot_color.a * 0.85)
		var dot_side := 3.0
		var col_gap := 6.0
		var row_gap := 6.0
		var block_w := dot_side * 2.0 + col_gap
		var block_h := dot_side * 3.0 + row_gap * 2.0
		var origin := Vector2(
			floorf((size.x - block_w) * 0.5),
			floorf((size.y - block_h) * 0.5))
		for r in 3:
			for c in 2:
				var pos := origin + Vector2(
					float(c) * (dot_side + col_gap),
					float(r) * (dot_side + row_gap))
				draw_rect(Rect2(pos + Vector2(0.0, 1.0), Vector2(dot_side, dot_side)), shadow_color)
				draw_rect(Rect2(pos, Vector2(dot_side, dot_side)), dot_color)

## Live state: what is shown and what is selected.
var _rows_box: VBoxContainer = null
var _details: RichTextLabel = null
var _detail_icon: TextureRect = null
var _status: Label = null
var _uninstall_button: Button = null
var _file_dialog: FileDialog = null
var _create_dialog: CreateModDialog = null
var _selected_id: String = ""
var _infos: Array = []
var _search_query: String = ""
var _filter: int = Filter.ALL
## Filter -> its chip, so the one in force can be shown held down.
var _filter_buttons: Dictionary = {}
## Mods ticked on or off since a filter was last picked. Their rows stay
## listed even if they no longer fit that filter, so a tick never makes its
## own row vanish from under the pointer; picking a filter (the one in force
## included) sorts every row afresh.
var _held_ids: Dictionary = {}

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

## Drag-to-reorder state: a press on a row's grip or card starts as a
## candidate and becomes an active drag once the pointer travels past
## DRAG_THRESHOLD, so clicks and taps still select without moving anything.
var _drag_candidate_id: String = ""
var _drag_id: String = ""
var _drag_active := false
var _drag_touch_index: int = -1
var _drag_start_pos := Vector2.ZERO
var _drag_pointer_pos := Vector2.ZERO
var _drag_grab_offset_y: float = ROW_HEIGHT * 0.5
var _drag_origin_listed_index: int = -1
var _drag_scroll_accum: float = 0.0
var _drag_last_usec: int = 0
var _drag_preview: PanelContainer = null
var _drag_preview_label: Label = null
var _drag_preview_icon: TextureRect = null
var _suppress_select_for_id: String = ""

func _ready() -> void:
	name = "ModsScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	visibility_changed.connect(_on_visibility_changed)
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_build()

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _exit_tree() -> void:
	_cleanup_drag_state()

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
		leave()
		get_viewport().set_input_as_handled()

## Show only the rows the filter lets through whose searchable text contains
## the search query. Rows are hidden, never removed or reordered, so the list
## keeps its order whatever is on show - and the arrows are lit for the rows
## that are.
func _filter_rows() -> void:
	if _rows_box == null or _search == null:
		return
	var query := _search.text.strip_edges().to_lower()
	var shown := 0
	for row in _rows_box.get_children():
		var listed: bool = filter_accepts(_filter, bool(row.get_meta("enabled", false))) \
			or _held_ids.has(str(row.get_meta("mod_id", "")))
		row.visible = listed and (query.is_empty() or str(row.get_meta("search", "")).contains(query))
		if row.visible:
			shown += 1
	if _empty != null:
		_empty.text = empty_text(_filter, not query.is_empty(), _rows_box.get_child_count())
		_empty.visible = shown == 0
	_update_move_buttons()
	if _drag_active:
		var dragged_row := _row_for(_drag_id)
		if dragged_row == null or not dragged_row.visible or shown <= 1:
			_cleanup_drag_state()

## Light the arrows and grip handles that have somewhere to go. A mod moves
## past the rows on show (see _on_row_moved), so the first of those cannot go
## up and the last cannot go down, and a grip dims when only one row is shown.
## An arrow that goes out under the press that took its row to the end keeps
## the focus: pressing it again does nothing, rather than the focus jumping to
## a button that does something else.
func _update_move_buttons() -> void:
	var shown := _shown_rows()
	var single_or_empty := shown.size() <= 1
	for row in _rows_box.get_children():
		var handle := row.get_node_or_null("DragHandle") as DragHandle
		if handle != null:
			handle.disabled = single_or_empty or not row.visible
	for index in shown.size():
		(shown[index].get_node("MoveUp") as Button).disabled = index == 0
		(shown[index].get_node("MoveDown") as Button).disabled = index == shown.size() - 1

func _on_filter_pressed(filter: int) -> void:
	_cleanup_drag_state()
	_filter = filter
	# Picking a filter - even the one already in force - sorts every row
	# afresh, so the rows that were only being held on show step out.
	_held_ids.clear()
	_update_filter_buttons()
	_filter_rows()

## Hold down the chip of the filter in force and release the others. The
## chips are plain toggles, so this is also what keeps a second press on the
## chosen one from popping it back up.
func _update_filter_buttons() -> void:
	for filter in _filter_buttons:
		var button := _filter_buttons[filter] as Button
		if is_instance_valid(button):
			button.set_pressed_no_signal(int(filter) == _filter)

## The row listing `mod_id`, or null when the library has no such mod.
func _row_for(mod_id: String) -> Control:
	if _rows_box == null:
		return null
	for row in _rows_box.get_children():
		if str(row.get_meta("mod_id", "")) == mod_id:
			return row as Control
	return null

## Make sure a mod that has just arrived can be seen: if the search or the
## filter would hide its row, clear them both and show the whole library.
func _reveal(mod_id: String) -> void:
	var row := _row_for(mod_id)
	if row != null and row.visible:
		return
	_search_query = ""
	if is_instance_valid(_search):
		_search.text = ""
	_filter = Filter.ALL
	_held_ids.clear()
	_update_filter_buttons()
	_filter_rows()

# =============================================================================
# BUILDING
# =============================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cleanup_drag_state()
	_saved_build_state()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_rows_box = null
	_details = null
	_detail_icon = null
	_status = null
	_uninstall_button = null
	# Rebuilding the tree closes any open form; it was a child like the rest.
	_create_dialog = null
	_tabs = null
	_library = null
	_inspector = null
	_search = null
	_empty = null
	_filter_buttons.clear()

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
## rebuild, so a resize does not lose what the player typed. (The filter in
## force is not kept in a control, so it carries over by itself.)
func _saved_build_state() -> void:
	if is_instance_valid(_search):
		_search_query = _search.text

func _restore_build_state() -> void:
	if is_instance_valid(_search):
		_search.text = _search_query
		_filter_rows()

func _build_header(mode: int) -> Control:
	# The top-right corner is the way into the mod repositories: the
	# Official and Example mods are downloaded from there, not shipped with
	# the game. A caller-named trailing control keeps its own name (see
	# make_screen_header), so the button stays findable as "BrowseModsButton"
	# in every layout.
	var browse_button := Button.new()
	browse_button.name = "BrowseModsButton"
	browse_button.text = "Browse Mods"
	browse_button.tooltip_text = "Download the official mods and examples, or add a self-hosted repository feed"
	browse_button.custom_minimum_size.y = 44.0
	Kit.paint_action(browse_button, true)
	browse_button.pressed.connect(func() -> void: browse_requested.emit())
	return Kit.make_screen_header(mode, "Mods", leave, browse_button, PixelIcon.Kind.PUZZLE)

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

	# The filter chips sit beside the search box where the panel is wide
	# (desktop) or the window is short (a phone on its side, where a row of
	# their own would cost the list a row); everywhere else they take the
	# full width under it.
	var filters_beside_search := _layout_mode == Kit.LayoutMode.DESKTOP \
		or _layout_mode == Kit.LayoutMode.PHONE_LANDSCAPE
	var controls := HBoxContainer.new()
	controls.name = "LibraryControls"
	controls.add_theme_constant_override("separation", 8)
	_search = LineEdit.new()
	_search.name = "ModSearch"
	# A phone on its side has room for a short prompt only.
	_search.placeholder_text = "Search mods..." \
		if _layout_mode == Kit.LayoutMode.PHONE_LANDSCAPE else "Search your collection..."
	_search.custom_minimum_size = Vector2(MIN_SEARCH_WIDTH, 44.0)
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
	var filters := _build_filter_bar(filters_beside_search)
	if filters_beside_search:
		controls.add_child(filters)
	else:
		stack.add_child(filters)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "ModList"
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if page_scrolled:
		list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		list_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list_scroll.custom_minimum_size.y = ROW_HEIGHT * 4.0 + 10.0
	stack.add_child(list_scroll)

	# The note shares the list's own space: an empty list says why where its
	# first row would have been, and the panel is no taller for saying it.
	var list_content := VBoxContainer.new()
	list_content.name = "ModListContent"
	list_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_content.add_theme_constant_override("separation", 0)
	list_scroll.add_child(list_content)

	_empty = _label("", 13, COLOR_TEXT_QUIET)
	_empty.name = "EmptyNote"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.visible = false
	list_content.add_child(_empty)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "ModRows"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", ROW_GAP)
	list_content.add_child(_rows_box)

	_library = panel
	panel.custom_minimum_size.x = clampf(MIN_LIBRARY_WIDTH, 100.0,
		_built_size.x - pad * 2.0 - 8.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if not page_scrolled \
		else Control.SIZE_SHRINK_BEGIN
	return panel

## The All / Enabled / Disabled chips. One is always held down; picking
## another narrows the rows on top of the search, and leaves the loadout
## alone. `beside_search` chips are only as wide as they need to be, so the
## search box keeps the rest of the row; on a row of their own the three
## share the panel's width.
func _build_filter_bar(beside_search: bool) -> HBoxContainer:
	var phone := Kit.is_phone(_layout_mode)
	# A phone on its side has the least room of all: "On" and "Off" leave
	# the search box wide enough to read what is typed into it.
	var short_labels := beside_search and phone
	var bar := HBoxContainer.new()
	bar.name = "ModFilters"
	bar.add_theme_constant_override("separation", 4 if phone else 6)
	for filter in [Filter.ALL, Filter.ENABLED, Filter.DISABLED]:
		var button := Button.new()
		button.name = "Filter_" + filter_label(int(filter))
		button.text = filter_label(int(filter), short_labels)
		button.tooltip_text = filter_hint(int(filter))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",
			10 if short_labels else (11 if phone else 12))
		if not beside_search:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif not phone:
			button.custom_minimum_size.x = FILTER_CHIP_WIDTH
		Kit.paint_toggle(button)
		button.pressed.connect(_on_filter_pressed.bind(int(filter)))
		_filter_buttons[int(filter)] = button
		bar.add_child(button)
	_update_filter_buttons()
	return bar

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

	# The selected mod's own icon, at the head of its field notes - the
	# default mark when it has none.
	_detail_icon = _mod_icon_texture_rect()
	_detail_icon.name = "DetailIcon"
	stack.add_child(_detail_icon)

	var details_scroll := ScrollContainer.new()
	details_scroll.name = "DetailsScroll"
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	details_scroll.custom_minimum_size.y = 200.0
	if page_scrolled:
		details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		details_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# The tool row scrolls sideways when the window is narrower than the
	# buttons together (phones): every action stays reachable, nothing is
	# clipped off the edge.
	var strip_scroll := ScrollContainer.new()
	strip_scroll.name = "ToolsScroll"
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Room for the 44px cards and the horizontal scrollbar under them.
	strip_scroll.custom_minimum_size.y = 56.0

	var strip := HBoxContainer.new()
	strip.name = "Tools"
	strip.add_theme_constant_override("separation", 10)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_scroll.add_child(strip)

	var create_button := _button("Create New Mod", _on_create_mod_pressed)
	create_button.name = "CreateModButton"
	create_button.tooltip_text = "Scaffold a new mod folder in your library"

	# Spread the bottom row across the full width instead of bunching the
	# secondary tools into the bottom-left corner on large screens.
	var buttons := Array([
		create_button,
		_button("+ Install ZIP", func() -> void:
			_file_dialog.popup_centered(get_viewport().get_visible_rect().size.min(Vector2(720, 480)) * 0.9), true),
		_button("Rescan", func() -> void:
			_cleanup_drag_state()
			ModManager.discover()
			_held_ids.clear()
			refresh("Library rescanned.")),
		_button("Mods folder", func() -> void: OS.shell_open(ModManager.mods_folder_path())),
		_button("Disable all", _on_disable_all_pressed),
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

	return strip_scroll

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
	_sync_rows()
	_filter_rows()
	_show_details()
	if not message.is_empty():
		_status.text = message
	elif ModManager.safe_mode_triggered:
		_status.text = "A previous session stopped while loading script mods, so this session loaded data only (safe mode). Switch the mod that caused it off and leave the screen to load the rest normally."
	elif ModManager.mods_disabled_by_flag:
		_status.text = "Started with --no-mods: nothing loads this session. The list above is still saved for next time."
	elif not ModManager.get_discovery_warnings().is_empty():
		_status.text = "While scanning: " + " · ".join(ModManager.get_discovery_warnings())
	elif ModManager.needs_reload:
		_status.text = "Back puts this loadout into play."
	else:
		_status.text = "Everything above is loaded and in play."
	if _status != null:
		_status.tooltip_text = _status.text
	if _drag_active:
		_sync_drag_visuals()

## Bring the rows in line with `_infos`: one row per mod, in the list's
## order. Rows are kept and moved, not rebuilt - one is only made for a mod
## that is new to the library, and only dropped when its mod has left it -
## so after a tick, a move or a rescan the control under the pointer, or
## holding the keyboard focus, still belongs to the same mod.
func _sync_rows() -> void:
	var rows: Dictionary = {}
	for row in _rows_box.get_children():
		rows[str(row.get_meta("mod_id", ""))] = row
	var listed: Dictionary = {}
	for info in _infos:
		listed[str(info.get("id", ""))] = true
	for mod_id in rows:
		if not listed.has(mod_id):
			_rows_box.remove_child(rows[mod_id])
			rows[mod_id].queue_free()
	var traded_places := false
	for index in _infos.size():
		var mod_id := str(_infos[index].get("id", ""))
		var row: Node = rows.get(mod_id)
		if row == null:
			row = _make_row(mod_id)
			_rows_box.add_child(row)
		if row.get_index() != index:
			_rows_box.move_child(row, index)
			traded_places = true
		_paint_row(row, _infos[index])
	# The D-pad steps from row to row by where each row was when the screen
	# was last measured, and rows that swap leave it measuring the same.
	if traded_places and has_node("/root/InputManager"):
		InputManager.invalidate_focus_graph(self)

## One row of the list, wired to its mod. What it shows is _paint_row()'s
## business, so the same row can be repainted as the loadout changes and
## moved as the order does.
func _make_row(mod_id: String) -> Control:
	var row := HBoxContainer.new()
	row.set_meta("mod_id", mod_id)
	row.custom_minimum_size.y = ROW_HEIGHT
	row.name = "ModRow_" + mod_id.replace(".", "_").replace("-", "_")
	row.add_theme_constant_override("separation", 6)
	row.gui_input.connect(_on_row_card_gui_input.bind(mod_id, row))

	var handle_width := DRAG_HANDLE_WIDTH_PHONE if Kit.is_phone(_layout_mode) else DRAG_HANDLE_WIDTH
	var handle := DragHandle.new(handle_width)
	handle.gui_input.connect(_on_drag_handle_gui_input.bind(mod_id, handle))
	row.add_child(handle)

	var check := CheckBox.new()
	check.name = "EnabledCheck"
	check.custom_minimum_size = Vector2(44.0, 44.0)
	check.tooltip_text = "Load this mod"
	check.toggled.connect(_on_row_toggled.bind(mod_id))
	row.add_child(check)

	var name_button := Button.new()
	name_button.name = "ModName"
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_button.clip_text = true
	name_button.custom_minimum_size.x = 40.0
	name_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The mod's own picture rides inside the button, at the left of its
	# label. A button draws its icon at the texture's size unless the theme
	# caps it, so cap it at the row's icon side - the prepared icons are
	# square, and the height follows the width.
	name_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	name_button.add_theme_constant_override("icon_max_width", int(ROW_ICON_SIZE))
	name_button.add_theme_constant_override("h_separation", 10)
	name_button.gui_input.connect(_on_row_card_gui_input.bind(mod_id, name_button))
	name_button.pressed.connect(_on_row_selected.bind(mod_id))
	row.add_child(name_button)

	var up := _row_button("▲", _on_row_moved.bind(mod_id, -1))
	up.name = "MoveUp"
	up.tooltip_text = "Move up the list (loads earlier)"
	row.add_child(up)

	var down := _row_button("▼", _on_row_moved.bind(mod_id, 1))
	down.name = "MoveDown"
	down.tooltip_text = "Move down the list (loads later, wins conflicts)"
	row.add_child(down)
	return row

## Show `info` on its row: the tick, the mod's picture inside its button,
## and the numbered title over the state badge. (Which arrows are lit
## depends on the rows on show, not on the mod: see _update_move_buttons.)
func _paint_row(row: Node, info: Dictionary) -> void:
	var enabled := bool(info.get("enabled", false))
	row.set_meta("enabled", enabled)
	row.set_meta("search", (str(info.get("name", "")) + " " + str(info.get("id", "")) \
		+ " " + str(info.get("description", ""))).to_lower())
	# Without the signal: this is the manager's answer, not a click to act on.
	(row.get_node("EnabledCheck") as CheckBox).set_pressed_no_signal(enabled)
	var name_button := row.get_node("ModName") as Button
	name_button.text = row_title(info) + "\n" + row_badge(info).to_upper()
	name_button.tooltip_text = str(info.get("description", ""))
	# The picture inside the button: the mod's own icon, or the default
	# mark in its place.
	name_button.icon = icon_texture_for(info)


## A TextureRect sized for the details pane's head, ready to take a mod's
## icon: it keeps any picture centred and undistorted.
func _mod_icon_texture_rect() -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(DETAIL_ICON_SIZE, DETAIL_ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## The icon texture for `info`: the mod's own picture through the manager,
## or the shared default mark when it has none (or its icon would not read).
static func icon_texture_for(info: Dictionary) -> Texture2D:
	var texture: Texture2D = ModManager.get_mod_icon_texture(str(info.get("id", "")))
	return texture if texture != null else fallback_icon_texture()


## The mark a mod without a readable icon of its own wears: the same puzzle
## piece as the screen's header, muted so it reads as "placeholder".
static var _fallback_icon: Texture2D = null
static func fallback_icon_texture() -> Texture2D:
	if _fallback_icon == null:
		_fallback_icon = PixelIcon.texture(PixelIcon.Kind.PUZZLE, 64,
			MenuStyle.ACCENT_UTILITY, true)
	return _fallback_icon

func _on_row_toggled(on: bool, mod_id: String) -> void:
	ModManager.set_mod_enabled(mod_id, on)
	_selected_id = mod_id
	# The row suited the filter when it was ticked; keep it on show.
	_held_ids[mod_id] = true
	refresh()

func _on_row_selected(mod_id: String) -> void:
	if _suppress_select_for_id == mod_id:
		_suppress_select_for_id = ""
		return
	_selected_id = mod_id
	_inspect_mobile = true
	_update_panes()
	_show_details()
	_refresh_row_highlights()

## An arrow was pressed (`direction` is -1 for up, 1 for down): move the mod
## past the next row on show that way, enabled or not. Rows the search or a
## filter is hiding are stepped over with it, so a press always moves the
## row one place in the list as it reads right now - under the Enabled
## filter, one place in the load order.
func _on_row_moved(mod_id: String, direction: int) -> void:
	var row := _row_for(mod_id)
	if row == null:
		return
	var rows := _rows_box.get_children()
	var stop := row.get_index() + direction
	while stop >= 0 and stop < rows.size() and not rows[stop].visible:
		stop += direction
	if stop < 0 or stop >= rows.size():
		return
	ModManager.move_mod(mod_id, stop - row.get_index())
	_selected_id = mod_id
	refresh()
	# The rows only take their new places when the list next lays itself
	# out, which is before this deferred call comes round.
	_scroll_to_row.call_deferred(row.get_instance_id())

## Scroll whatever scrolls the list - the list itself or, on a phone held
## upright, the whole page - far enough to keep a row that has just moved
## on show. By instance id: the row can be gone (a rebuild for a new window
## shape) by the time a deferred call arrives.
func _scroll_to_row(row_id: int) -> void:
	var row := instance_from_id(row_id) as Control
	if row == null or not row.is_visible_in_tree():
		return
	var node := row.get_parent()
	while node != null and node != self:
		if node is ScrollContainer:
			(node as ScrollContainer).ensure_control_visible(row)
		node = node.get_parent()

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
		var chosen: bool = str(row.get_meta("mod_id", "")) == _selected_id
		Kit.paint_utility_button(name_button, chosen)
		name_button.add_theme_color_override("font_color",
			COLOR_GOLD if chosen else UIConstants.COLOR_TEXT)

func _show_details() -> void:
	var info: Dictionary = ModManager.get_mod_info(_selected_id)
	_details.text = details_text(info,
		ContentRegistry.get_conflicts(), ContentRegistry.get_warnings())
	_uninstall_button.disabled = info.is_empty() or not bool(info.get("can_uninstall", false))
	if _detail_icon != null:
		# No selection, no picture; the pane still opens on its heading.
		_detail_icon.visible = not info.is_empty()
		if not info.is_empty():
			_detail_icon.texture = icon_texture_for(info)
	_refresh_row_highlights()

func _on_create_mod_pressed() -> void:
	if is_instance_valid(_create_dialog):
		return
	_create_dialog = CreateModDialog.new()
	_create_dialog.created.connect(_on_mod_created)
	_create_dialog.tree_exited.connect(func() -> void: _create_dialog = null)
	add_child(_create_dialog)

## A new mod arrived switched off, like an installed zip. Select it (clearing
## any search or filter that would hide its row) and say what to do next.
func _on_mod_created(mod_id: String) -> void:
	_inspect_mobile = true
	_update_panes()
	refresh("Created %s in your mods folder - still off. Its README has the next steps: tick it, and it loads when you leave this screen." % mod_id)
	# The refresh may have fallen back to the first row while going through
	# the manager; the new mod is in the list now, so open its field notes.
	_selected_id = mod_id
	_reveal(mod_id)
	_show_details()
	_refresh_row_highlights()

func _on_zip_selected(path: String) -> void:
	var result: Dictionary = ModManager.install_zip(path)
	if bool(result.get("ok", false)):
		_selected_id = str(result.get("mod_id", ""))
		refresh("Installed %s - still disabled. Tick it, and it loads when you leave this screen." % _selected_id)
		# It arrives unticked, which the Enabled filter would hide.
		_reveal(_selected_id)
	else:
		refresh("That zip is not a Golf Tycoon mod: %s" % "; ".join(result.get("errors", ["unknown error"])))

func _on_disable_all_pressed() -> void:
	_cleanup_drag_state()
	for info in _infos:
		ModManager.set_mod_enabled(str(info.get("id", "")), false)
	# A sweep of the whole library, not a tick on one row: nothing is held.
	_held_ids.clear()
	refresh("Every mod is off, and leaving the screen puts that into play - the plain game's built-in weather, wind and seasons stand-ins keep everything working.")

func _on_uninstall_pressed() -> void:
	_cleanup_drag_state()
	var result: Dictionary = ModManager.uninstall_mod(_selected_id)
	if bool(result.get("ok", false)):
		_selected_id = ""
		refresh("Uninstalled.")
	else:
		refresh("Could not uninstall: %s" % "; ".join(result.get("errors", [])))

## Leave the screen, putting the loadout into play on the way out: a tick, a
## drag or an arrow press writes the list straight away, and this is where
## those changes take effect, so the player never has to press Apply. A set
## that has not changed since it loaded reloads nothing - Back is just Back.
func leave() -> void:
	if _drag_active:
		_finish_drag()
	else:
		_cleanup_drag_state()
	if ModManager.apply_staged_changes():
		# The scene is reloading under us; the screen goes with it.
		return
	back_requested.emit()

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

## Whether a row is currently lifted and being dragged to a new place.
func is_dragging() -> bool:
	return _drag_active

## The id of the mod currently lifted in a drag, or "" when idle.
func dragged_mod_id() -> String:
	return _drag_id

func _on_visibility_changed() -> void:
	if not visible:
		if _drag_active:
			_cancel_drag()
		else:
			_cleanup_drag_state()

func _on_drag_handle_gui_input(event: InputEvent, mod_id: String, handle: DragHandle) -> void:
	if handle.disabled or _shown_rows().size() <= 1:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var global_pos := handle.get_global_transform_with_canvas() * mb.position
			_start_drag_candidate(mod_id, global_pos)
			handle.accept_event()

func _on_row_card_gui_input(event: InputEvent, mod_id: String, source: Control) -> void:
	if _shown_rows().size() <= 1:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var global_pos := source.get_global_transform_with_canvas() * mb.position
			_start_drag_candidate(mod_id, global_pos)
			# Leave ModName's press unconsumed so a plain click still selects
			# the mod; consume presses in the inter-button gap on the row box.
			if not (source is BaseButton):
				source.accept_event()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Escape, right-click or controller B while dragging puts the mod back
	# where it started rather than leaving the screen.
	if _drag_active and event.is_action_pressed("cancel"):
		_cancel_drag()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _drag_touch_index < 0 and _drag_candidate_id.is_empty():
				var hit_id := _touch_drag_handle_at(touch.position)
				if not hit_id.is_empty():
					_drag_touch_index = touch.index
					_start_drag_candidate(hit_id, touch.position)
					get_viewport().set_input_as_handled()
		elif touch.index == _drag_touch_index:
			if touch.canceled:
				_cancel_drag()
			elif _drag_active:
				_update_drag(touch.position)
				_finish_drag()
			else:
				var tapped_id := _drag_candidate_id
				_cleanup_drag_state()
				if not tapped_id.is_empty():
					_selected_id = tapped_id
					_show_details()
					_refresh_row_highlights()
			_drag_touch_index = -1
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _drag_touch_index and not _drag_candidate_id.is_empty():
			if not _drag_active and drag.position.distance_to(_drag_start_pos) > DRAG_THRESHOLD:
				_begin_drag(drag.position)
			if _drag_active:
				_update_drag(drag.position)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_suppress_select_for_id = ""
				if _drag_touch_index < 0 and not _drag_candidate_id.is_empty():
					if _drag_active:
						_finish_drag()
					else:
						_cleanup_drag_state()
			elif _drag_touch_index < 0 and not _drag_candidate_id.is_empty():
				if _drag_active:
					_suppress_select_for_id = _drag_id
					_update_drag(mb.position)
					_finish_drag()
				else:
					var clicked_id := _drag_candidate_id
					_cleanup_drag_state()
					if _selected_id != clicked_id:
						var row := _row_for(clicked_id)
						var handle := row.get_node_or_null("DragHandle") as Control if row != null else null
						if handle != null and handle.get_global_rect().has_point(mb.position):
							_selected_id = clicked_id
							_show_details()
							_refresh_row_highlights()
		return

	if event is InputEventMouseMotion:
		if _drag_touch_index < 0 and not _drag_candidate_id.is_empty():
			var mm := event as InputEventMouseMotion
			if not _drag_active and mm.position.distance_to(_drag_start_pos) > DRAG_THRESHOLD:
				_begin_drag(mm.position)
			if _drag_active:
				_update_drag(mm.position)

func _process(delta: float) -> void:
	if not _drag_active or not visible:
		set_process(false)
		return
	var now_usec := Time.get_ticks_usec()
	var dt := delta
	if dt <= 0.0 and _drag_last_usec > 0:
		dt = clampf(float(now_usec - _drag_last_usec) / 1000000.0, 0.0, 0.1)
	_drag_last_usec = now_usec
	# Re-evaluate against the latest sorted layout first, so a list that
	# scrolled on the previous frame advances the dragged row across newly
	# revealed slots even while the pointer stands still.
	_update_drag(_drag_pointer_pos)
	var scroller := _active_scroller()
	if scroller == null:
		return
	var v_bar := scroller.get_v_scroll_bar()
	if v_bar == null or v_bar.max_value <= v_bar.page + 1.0:
		_drag_scroll_accum = 0.0
		return
	var rect := scroller.get_global_rect()
	var margin := minf(DRAG_SCROLL_MARGIN, rect.size.y * 0.25)
	if margin <= 1.0:
		return
	var velocity := 0.0
	if _drag_pointer_pos.y < rect.position.y + margin:
		var t := clampf((rect.position.y + margin - _drag_pointer_pos.y) / margin, 0.0, 1.0)
		velocity = -DRAG_SCROLL_MAX_SPEED * t
	elif _drag_pointer_pos.y > rect.end.y - margin:
		var t := clampf((_drag_pointer_pos.y - (rect.end.y - margin)) / margin, 0.0, 1.0)
		velocity = DRAG_SCROLL_MAX_SPEED * t
	else:
		_drag_scroll_accum = 0.0
		return
	_drag_scroll_accum += velocity * dt
	var step := int(_drag_scroll_accum)
	if step == 0:
		return
	_drag_scroll_accum -= float(step)
	var max_scroll := maxi(0, roundi(v_bar.max_value - v_bar.page))
	var next_scroll := clampi(scroller.scroll_vertical + step, 0, max_scroll)
	if next_scroll != scroller.scroll_vertical:
		scroller.scroll_vertical = next_scroll

func _start_drag_candidate(mod_id: String, global_pos: Vector2) -> void:
	var row := _row_for(mod_id)
	if row == null or not row.visible:
		return
	_drag_candidate_id = mod_id
	_drag_start_pos = global_pos
	_drag_pointer_pos = global_pos
	var row_rect := row.get_global_rect()
	var row_h := maxf(row_rect.size.y, ROW_HEIGHT)
	_drag_grab_offset_y = clampf(global_pos.y - row_rect.position.y, 0.0, row_h)

func _begin_drag(current_pos: Vector2) -> void:
	if _drag_candidate_id.is_empty() or _shown_rows().size() <= 1:
		return
	var row := _row_for(_drag_candidate_id)
	if row == null or not row.visible:
		_cleanup_drag_state()
		return
	_drag_id = _drag_candidate_id
	_drag_active = true
	_drag_pointer_pos = current_pos
	_drag_origin_listed_index = ModManager.get_listed_order().find(_drag_id)
	_drag_scroll_accum = 0.0
	_drag_last_usec = Time.get_ticks_usec()
	_selected_id = _drag_id
	_show_details()
	_refresh_row_highlights()
	_create_drag_preview()
	_sync_drag_visuals()
	set_process(true)

func _update_drag(pointer_pos: Vector2) -> void:
	_drag_pointer_pos = pointer_pos
	if not _drag_active or _drag_id.is_empty():
		return
	var shown := _shown_rows()
	var dragged_row := _row_for(_drag_id)
	if dragged_row == null or shown.size() <= 1:
		_cleanup_drag_state()
		return
	var cur := shown.find(dragged_row)
	if cur < 0:
		_cleanup_drag_state()
		return
	var card_center_y := pointer_pos.y - _drag_grab_offset_y + ROW_HEIGHT * 0.5
	var centers := _shown_slot_centers_y(shown)
	var target := target_slot_for_drag(cur, card_center_y, centers)
	if target != cur:
		var target_row := shown[target]
		ModManager.move_mod(_drag_id, target_row.get_index() - dragged_row.get_index())
		refresh()
	else:
		_position_drag_preview()

func _finish_drag() -> void:
	var moved_id := _drag_id
	_cleanup_drag_state()
	if not moved_id.is_empty():
		_selected_id = moved_id
		refresh()
		var moved_row := _row_for(moved_id)
		if moved_row != null:
			_scroll_to_row.call_deferred(moved_row.get_instance_id())

func _cancel_drag() -> void:
	var cancelled_id := _drag_id
	var origin_index := _drag_origin_listed_index
	_suppress_select_for_id = cancelled_id
	_cleanup_drag_state()
	if not cancelled_id.is_empty() and origin_index >= 0:
		var current_index := ModManager.get_listed_order().find(cancelled_id)
		if current_index >= 0 and current_index != origin_index:
			ModManager.move_mod(cancelled_id, origin_index - current_index)
		refresh()

func _cleanup_drag_state() -> void:
	_free_drag_preview()
	if _rows_box != null:
		for child in _rows_box.get_children():
			var row := child as Control
			if row != null:
				row.modulate = Color.WHITE
				var handle := row.get_node_or_null("DragHandle") as DragHandle
				if handle != null:
					handle.dragging = false
	_drag_candidate_id = ""
	_drag_id = ""
	_drag_active = false
	_drag_touch_index = -1
	_drag_origin_listed_index = -1
	_drag_scroll_accum = 0.0
	_drag_last_usec = 0
	set_process(false)

func _create_drag_preview() -> void:
	_free_drag_preview()
	var card := PanelContainer.new()
	card.name = "ModDragPreview"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 20
	card.add_theme_stylebox_override("panel", PixelButtonStyle.card_style(
		COLOR_GOLD, PixelButtonStyle.State.HOVER, COLOR_SURFACE_RAISED, 10, 6, 6))

	var row_box := HBoxContainer.new()
	row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_box.add_theme_constant_override("separation", 10)
	card.add_child(row_box)

	var grip := DragHandle.new(DRAG_HANDLE_WIDTH, false)
	grip.dragging = true
	row_box.add_child(grip)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ROW_ICON_SIZE, ROW_ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row_box.add_child(icon)

	var title := _label("", 14, COLOR_GOLD, SUBTITLE_FONT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row_box.add_child(title)

	add_child(card)
	_drag_preview = card
	_drag_preview_icon = icon
	_drag_preview_label = title
	_paint_drag_preview()
	_position_drag_preview()

func _paint_drag_preview() -> void:
	if _drag_preview == null or _drag_id.is_empty():
		return
	var info: Dictionary = ModManager.get_mod_info(_drag_id)
	if info.is_empty():
		return
	if _drag_preview_label != null:
		_drag_preview_label.text = row_title(info) + "\n" + row_badge(info).to_upper()
	if _drag_preview_icon != null:
		_drag_preview_icon.texture = icon_texture_for(info)

func _position_drag_preview() -> void:
	if _drag_preview == null or _rows_box == null:
		return
	var rows_rect := _rows_box.get_global_rect()
	var bounds_rect := _library.get_global_rect() if _library != null else get_global_rect()
	var width := maxf(rows_rect.size.x, 120.0)
	var min_y := bounds_rect.position.y
	var max_y := maxf(min_y, bounds_rect.end.y - ROW_HEIGHT)
	var target_y := clampf(_drag_pointer_pos.y - _drag_grab_offset_y, min_y, max_y)
	_drag_preview.size = Vector2(width, ROW_HEIGHT)
	_drag_preview.global_position = Vector2(rows_rect.position.x, target_y)

func _free_drag_preview() -> void:
	if is_instance_valid(_drag_preview):
		if _drag_preview.get_parent() == self:
			remove_child(_drag_preview)
		_drag_preview.free()
	_drag_preview = null
	_drag_preview_label = null
	_drag_preview_icon = null

func _sync_drag_visuals() -> void:
	if not _drag_active or _rows_box == null:
		return
	for child in _rows_box.get_children():
		var row := child as Control
		if row == null:
			continue
		var is_dragged := str(row.get_meta("mod_id", "")) == _drag_id
		row.modulate = Color(1.0, 1.0, 1.0, 0.35) if is_dragged else Color.WHITE
		var handle := row.get_node_or_null("DragHandle") as DragHandle
		if handle != null:
			handle.dragging = is_dragged
	_paint_drag_preview()
	_position_drag_preview()

func _shown_rows() -> Array[Control]:
	var shown: Array[Control] = []
	if _rows_box == null:
		return shown
	for child in _rows_box.get_children():
		var row := child as Control
		if row != null and row.visible:
			shown.append(row)
	return shown

## Global Y centres of the visible row slots in their current child order.
## Computed from `_rows_box`'s canvas transform and each row's height rather
## than each child's `position.y`, so multiple swaps within one frame see the
## new slot positions immediately without waiting for Container to re-sort.
func _shown_slot_centers_y(shown: Array[Control]) -> PackedFloat32Array:
	var centers := PackedFloat32Array()
	if _rows_box == null:
		return centers
	var xform := _rows_box.get_global_transform_with_canvas()
	var y := 0.0
	for row in shown:
		var h := maxf(row.size.y, ROW_HEIGHT)
		centers.append((xform * Vector2(0.0, y + h * 0.5)).y)
		y += h + float(ROW_GAP)
	return centers

func _active_scroller() -> ScrollContainer:
	if _rows_box == null:
		return null
	var node: Node = _rows_box.get_parent()
	while node != null and node != self:
		if node is ScrollContainer:
			var scroller := node as ScrollContainer
			if scroller.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				return scroller
		node = node.get_parent()
	return null

func _touch_drag_handle_at(screen_pos: Vector2) -> String:
	if _rows_box == null or _shown_rows().size() <= 1:
		return ""
	var scroller := _active_scroller()
	if scroller != null and not scroller.get_global_rect().has_point(screen_pos):
		return ""
	for child in _rows_box.get_children():
		var row := child as Control
		if row == null or not row.is_visible_in_tree():
			continue
		var handle := row.get_node_or_null("DragHandle") as DragHandle
		if handle == null or handle.disabled:
			continue
		if not handle.get_global_rect().has_point(screen_pos):
			continue
		if has_node("/root/TouchInput") and not TouchInput.owns_native_touch(handle, screen_pos):
			return ""
		return str(row.get_meta("mod_id", ""))
	return ""

# =============================================================================
# ROW AND DETAIL TEXT (pure, unit-tested)
# =============================================================================

## Which visible slot (`0 .. slot_centers.size() - 1`) a dragged row belongs
## in when its vertical centre is at `card_center_y`. `hysteresis` keeps a
## pointer parked right on the midpoint between two slots from flickering the
## row back and forth.
static func target_slot_for_drag(current_slot: int, card_center_y: float,
		slot_centers: PackedFloat32Array, hysteresis: float = DRAG_SWAP_HYSTERESIS) -> int:
	if slot_centers.size() <= 1:
		return 0
	var slot := clampi(current_slot, 0, slot_centers.size() - 1)
	while slot + 1 < slot_centers.size():
		var midpoint := (slot_centers[slot] + slot_centers[slot + 1]) * 0.5
		if card_center_y > midpoint + hysteresis:
			slot += 1
		else:
			break
	while slot > 0:
		var midpoint := (slot_centers[slot - 1] + slot_centers[slot]) * 0.5
		if card_center_y < midpoint - hysteresis:
			slot -= 1
		else:
			break
	return slot

## Whether `filter` lists a mod that is ticked to load (`enabled`) or not.
static func filter_accepts(filter: int, enabled: bool) -> bool:
	match filter:
		Filter.ENABLED:
			return enabled
		Filter.DISABLED:
			return not enabled
	return true

## The word on a filter's chip. `short` is for the narrowest rows, where
## "On" and "Off" stand in for "Enabled" and "Disabled".
static func filter_label(filter: int, short: bool = false) -> String:
	match filter:
		Filter.ENABLED:
			return "On" if short else "Enabled"
		Filter.DISABLED:
			return "Off" if short else "Disabled"
	return "All"

## The tooltip on a filter's chip.
static func filter_hint(filter: int) -> String:
	match filter:
		Filter.ENABLED:
			return "Show only the mods ticked to load"
		Filter.DISABLED:
			return "Show only the mods that are switched off"
	return "Show every mod"

## What the list says when it has no row to show, so an empty list always
## names the reason: nothing installed, nothing in that filter, or nothing
## matching the search.
static func empty_text(filter: int, searching: bool, library_size: int) -> String:
	if library_size == 0:
		return "No mods here yet. Browse Mods for the official set, create one, install a zip, or drop a mod folder into the mods folder and Rescan."
	if searching:
		match filter:
			Filter.ENABLED:
				return "No enabled mods match. Try another search, or the All filter."
			Filter.DISABLED:
				return "No disabled mods match. Try another search, or the All filter."
		return "No matching mods. Try another search."
	match filter:
		Filter.ENABLED:
			return "No mods are enabled. Pick All, then tick the ones you want."
		Filter.DISABLED:
			return "No mods are disabled: every one of them is ticked."
	return "No matching mods. Try another search."

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
		return "loads on leave"
	return str(info.get("source", ""))

static func details_text(info: Dictionary,
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
	return "\n".join(lines)
