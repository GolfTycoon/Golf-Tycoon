extends Control
class_name WorldMapScreen
## Company atlas: buy, browse and switch between the company's course sites.
##
## The map is deliberately composed for the shape of the screen instead of
## shrinking one desktop layout down:
##
##  * Desktop: an expansive globe beside a location dossier and searchable
##    vertical directory.
##  * Tablet: a globe and selected-site dossier above a swipeable destination
##    shelf, keeping the map and choices in the same glance.
##  * Phone landscape: a compact globe beside a four-row, touch-sized picker.
##  * Phone portrait: a scrollable travel journal with the globe and selected
##    site first, followed by the complete location directory.
##
## All modes are built from the same location state and actions. Directory
## cards offer Buy & Play. The selected-site dossier offers Buy (stay on the
## map) beside Buy & Play, or Play once the site is owned. The selected site,
## search, filter, scroll position and globe view survive a resize.
##
## The screen wears the same pixel-art look as the title screen and the Start
## New Game setup: PixelButtonStyle's notched nine-patch frames on every card,
## tile, button and field; Pixelify Sans throughout (bold for the heading,
## treasury and the call to action, semibold for names, kickers and buttons,
## regular for captions and quiet lines); PixelIcon sprites for the treasury
## coin, the legend pins and each location's state flag; and the globe itself
## drawn in LandStyle.PIXEL, so the planet is chunky cells with sprite pins.

signal play_location_requested(location_id: String)
signal back_requested()

enum LayoutMode { DESKTOP, TABLET_LANDSCAPE, TABLET_PORTRAIT, PHONE_LANDSCAPE, PHONE_PORTRAIT }
enum BrowseFilter { ALL, OWNED, AFFORDABLE }

const WorldMapStateScript := preload("res://scripts/autoload/world_map_state.gd")
const DESKTOP_MIN_WIDTH := 1180.0
const DESKTOP_MIN_HEIGHT := 680.0
const TABLET_MIN_WIDTH := 680.0
const TABLET_MIN_HEIGHT := 620.0

const DESKTOP_ROW_HEIGHT := 56.0
const PHONE_ROW_HEIGHT := 60.0
const LANDSCAPE_ROW_HEIGHT := 46.0
const TABLET_CARD_WIDTH := 218.0
const TABLET_CARD_HEIGHT := 112.0
## Unowned sites buy the land and start that course in one press.
const BUY_LABEL := "Buy"
const BUY_AND_PLAY_LABEL := "Buy & Play"
## The out-of-game menus share one background image backdrop, one translucent
## card system and the same cream / golf-green / flag-gold accent palette.
const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_SURFACE_RAISED := MenuStyle.RAIL_BG
const COLOR_SURFACE_INSET := MenuStyle.INSET_BG
const COLOR_BORDER_SOFT := UIConstants.COLOR_BORDER
const COLOR_TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const COLOR_TEXT_SECONDARY := UIConstants.COLOR_TEXT_DIM
const COLOR_TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

## The atlas shares the title screen's chunky, readable Pixelify Sans
## lettering: Bold for the heading, the treasury and the call to action,
## SemiBold for names, kickers and buttons, Regular for the explanatory copy.
const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

var globe: GlobeMap = null
var _list_box: BoxContainer = null
var _directory_scroll: ScrollContainer = null
var _phone_scroll: ScrollContainer = null
var _horizontal_directory: bool = false
var _rows: Dictionary = {}
var _filter_buttons: Dictionary = {}
var _money_label: Label = null
var _map_summary_label: Label = null
var _hint_label: Label = null
var _search_input: LineEdit = null
var _featured_name: Label = null
var _featured_meta: Label = null
var _featured_description: Label = null
var _featured_stats: Label = null
var _featured_status: Label = null
var _featured_buy: Button = null
var _featured_action: Button = null
var _layout_mode: int = -1
var _built_size := Vector2.ZERO
var _selected_id := ""
var _search_query := ""
var _browse_filter: int = BrowseFilter.ALL
var _phone_scroll_value := 0
var _catalog_scroll_value := 0
var _first_show := true
var _unbounded_phone_list := false
var _featured_compact := false
var _featured_micro := false
var _globe_view_state: Dictionary = {}

func _ready() -> void:
	name = "WorldMapScreen"
	if WorldMap.locations.is_empty():
		WorldMap.new_world(WorldMapStateScript.default_options())
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	if has_node("/root/EventBus") and not EventBus.money_changed.is_connected(_on_money_changed):
		EventBus.money_changed.connect(_on_money_changed)
	_build()
	refresh()

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

## The composition each viewport shape calls for. Kept pure so every
## breakpoint can be checked without creating a window.
static func layout_mode_for(view: Vector2) -> int:
	if view.x >= DESKTOP_MIN_WIDTH and view.y >= DESKTOP_MIN_HEIGHT and view.x > view.y:
		return LayoutMode.DESKTOP
	if view.x >= TABLET_MIN_WIDTH and view.y >= TABLET_MIN_HEIGHT:
		return LayoutMode.TABLET_LANDSCAPE if view.x >= view.y else LayoutMode.TABLET_PORTRAIT
	if view.x > view.y and view.y < TABLET_MIN_HEIGHT:
		return LayoutMode.PHONE_LANDSCAPE
	return LayoutMode.PHONE_PORTRAIT

func _on_screen_changed(window_size: Vector2, _scale: float) -> void:
	var mode := layout_mode_for(window_size)
	var width_delta := absf(window_size.x - _built_size.x)
	var height_delta := absf(window_size.y - _built_size.y)
	var needs_remeasure := width_delta > maxf(96.0, _built_size.x * 0.14) \
		or height_delta > maxf(72.0, _built_size.y * 0.14)
	if mode != _layout_mode or needs_remeasure:
		_build()
		refresh()

func _on_money_changed(_old_amount: int, _new_amount: int) -> void:
	if visible and is_inside_tree():
		refresh()

func _save_build_state() -> void:
	if is_instance_valid(_search_input):
		_search_query = _search_input.text
	if is_instance_valid(_phone_scroll):
		_phone_scroll_value = _phone_scroll.scroll_vertical
	if is_instance_valid(_directory_scroll):
		if _horizontal_directory:
			_catalog_scroll_value = _directory_scroll.scroll_horizontal
		else:
			_catalog_scroll_value = _directory_scroll.scroll_vertical
	if is_instance_valid(globe):
		_globe_view_state = globe.get_view_state()

## Rebuild the responsive composition. Container sizing does the continuous
## resize work; this only runs when a breakpoint is crossed or proportions
## have changed enough to warrant recalculating the typography.
func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_save_build_state()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_rows.clear()
	_filter_buttons.clear()
	_list_box = null
	_directory_scroll = null
	_phone_scroll = null
	_horizontal_directory = false
	_search_input = null
	_featured_name = null
	_featured_meta = null
	_featured_description = null
	_featured_stats = null
	_featured_status = null
	_featured_buy = null
	_featured_action = null
	_money_label = null
	_map_summary_label = null
	_hint_label = null

	_layout_mode = layout_mode_for(_window_size())
	_built_size = _window_size()
	_featured_compact = _layout_mode == LayoutMode.PHONE_PORTRAIT
	_featured_micro = _layout_mode == LayoutMode.PHONE_LANDSCAPE
	_unbounded_phone_list = _layout_mode == LayoutMode.PHONE_PORTRAIT

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := _outer_padding(_layout_mode, _built_size)
	frame.add_theme_constant_override("margin_left", pad)
	frame.add_theme_constant_override("margin_right", pad)
	frame.add_theme_constant_override("margin_top", pad)
	frame.add_theme_constant_override("margin_bottom", pad)
	add_child(frame)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", _page_separation(_layout_mode))
	frame.add_child(page)
	page.add_child(_build_header(_layout_mode))

	match _layout_mode:
		LayoutMode.DESKTOP:
			page.add_child(_build_desktop_body(_built_size))
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			page.add_child(_build_tablet_body(_built_size))
		LayoutMode.PHONE_LANDSCAPE:
			page.add_child(_build_phone_landscape_body(_built_size))
		_:
			page.add_child(_build_phone_portrait_body(_built_size))

func _outer_padding(mode: int, view: Vector2) -> int:
	match mode:
		LayoutMode.DESKTOP:
			return int(clampf(minf(view.x, view.y) * 0.025, 20.0, 36.0))
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return int(clampf(minf(view.x, view.y) * 0.022, 14.0, 26.0))
		LayoutMode.PHONE_LANDSCAPE:
			return 8
		_:
			return int(clampf(view.x * 0.028, 9.0, 14.0))

func _page_separation(mode: int) -> int:
	match mode:
		LayoutMode.DESKTOP:
			return 14
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return 11
		LayoutMode.PHONE_LANDSCAPE:
			return 7
		_:
			return 8

# =============================================================================
# HEADER AND PAGE COMPOSITIONS
# =============================================================================

func _build_header(mode: int) -> Control:
	var compact := mode == LayoutMode.PHONE_LANDSCAPE or mode == LayoutMode.PHONE_PORTRAIT
	var header := HBoxContainer.new()
	header.name = "AtlasHeader"
	header.add_theme_constant_override("separation", 10 if not compact else 7)
	header.custom_minimum_size.y = 62.0 if mode == LayoutMode.DESKTOP else (56.0 if not compact else 48.0)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "‹  Back" if not compact else "‹ Back"
	back.tooltip_text = "Return to the previous screen"
	back.custom_minimum_size = Vector2(94.0 if not compact else 72.0, 42.0 if compact else 46.0)
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.add_theme_font_override("font", SUBTITLE_FONT)
	_paint_utility_button(back, false)
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)

	var title_box := HBoxContainer.new()
	title_box.name = "TitleBlock"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 7 if compact else 9)
	var mark := MenuFlagMark.new()
	mark.name = "Mark"
	mark.mark_size = 20.0 if compact else (29.0 if mode == LayoutMode.DESKTOP else 27.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_child(mark)
	var title := _make_title_label("World Map", 20 if compact else 26)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(title)
	header.add_child(title_box)

	var balance := PanelContainer.new()
	balance.name = "TreasuryCard"
	balance.custom_minimum_size = Vector2(132.0 if compact else 168.0, 42.0 if compact else 54.0)
	balance.size_flags_horizontal = Control.SIZE_SHRINK_END
	balance.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(COLOR_GOLD, 0.72), COLOR_SURFACE_RAISED, 6, 5))
	var balance_margin := MarginContainer.new()
	balance_margin.add_theme_constant_override("margin_left", 12 if not compact else 9)
	balance_margin.add_theme_constant_override("margin_right", 12 if not compact else 9)
	balance_margin.add_theme_constant_override("margin_top", 5)
	balance_margin.add_theme_constant_override("margin_bottom", 5)
	balance.add_child(balance_margin)
	var balance_box := VBoxContainer.new()
	balance_box.add_theme_constant_override("separation", 0)
	balance_margin.add_child(balance_box)
	if not compact:
		var cash_caption := _make_kicker("Company cash", 10)
		cash_caption.name = "CashCaption"
		cash_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cash_caption.add_theme_color_override("font_color", COLOR_TEXT_QUIET)
		balance_box.add_child(cash_caption)
	var money_row := HBoxContainer.new()
	money_row.name = "MoneyRow"
	money_row.alignment = BoxContainer.ALIGNMENT_END
	money_row.add_theme_constant_override("separation", 6)
	var coin := _make_sprite(PixelIcon.Kind.COIN, 16, COLOR_GOLD)
	coin.name = "Coin"
	money_row.add_child(coin)
	_money_label = _make_title_label("", 16 if not compact else 13, COLOR_GOLD)
	_money_label.name = "Money"
	# A clipped Label reports only a one-pixel minimum width; expand it into the
	# space beside the coin so the balance itself remains visible.
	_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.clip_text = true
	money_row.add_child(_money_label)
	balance_box.add_child(money_row)
	balance.tooltip_text = "Available company funds"
	header.add_child(balance)
	_update_header()
	return header

func _build_desktop_body(view: Vector2) -> Control:
	var body := HBoxContainer.new()
	body.name = "DesktopAtlas"
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var map_panel := _build_map_panel(LayoutMode.DESKTOP)
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 1.42
	body.add_child(map_panel)

	var rail := VBoxContainer.new()
	rail.name = "LocationRail"
	rail.custom_minimum_size.x = clampf(view.x * 0.30, 360.0, 470.0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_theme_constant_override("separation", 11)
	body.add_child(rail)

	var feature := _build_featured_panel(false, false)
	feature.custom_minimum_size.y = 226.0 if view.y >= 760.0 else 196.0
	rail.add_child(feature)
	var catalog := _build_vertical_catalog(LayoutMode.DESKTOP, false)
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(catalog)
	return body

func _build_tablet_body(view: Vector2) -> Control:
	var body := VBoxContainer.new()
	body.name = "TabletAtlas"
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var stage := HBoxContainer.new()
	stage.name = "MapAndDestination"
	stage.add_theme_constant_override("separation", 12)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = 1.0
	var map_panel := _build_map_panel(_layout_mode)
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 1.12
	stage.add_child(map_panel)
	var feature := _build_featured_panel(false, false)
	feature.custom_minimum_size.x = clampf(view.x * 0.39, 292.0, 390.0)
	feature.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(feature)
	body.add_child(stage)

	var shelf := _build_horizontal_catalog()
	shelf.custom_minimum_size.y = 204.0 if _layout_mode == LayoutMode.TABLET_PORTRAIT else 194.0
	shelf.size_flags_vertical = Control.SIZE_SHRINK_END
	body.add_child(shelf)
	return body

func _build_phone_landscape_body(view: Vector2) -> Control:
	var body := HBoxContainer.new()
	body.name = "PhoneLandscapeAtlas"
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var map_panel := _build_map_panel(LayoutMode.PHONE_LANDSCAPE)
	map_panel.custom_minimum_size.x = clampf(view.x * 0.37, 228.0, 330.0)
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map_panel)

	var rail := VBoxContainer.new()
	rail.name = "PhoneDestinationRail"
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_theme_constant_override("separation", 7)
	var feature := _build_featured_panel(true, true)
	feature.custom_minimum_size.y = 102.0
	rail.add_child(feature)
	var catalog := _build_vertical_catalog(LayoutMode.PHONE_LANDSCAPE, false)
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(catalog)
	body.add_child(rail)
	return body

func _build_phone_portrait_body(view: Vector2) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "PhoneAtlasScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_phone_scroll = scroll
	var content := VBoxContainer.new()
	content.name = "TravelJournal"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	var map_panel := _build_map_panel(LayoutMode.PHONE_PORTRAIT)
	map_panel.custom_minimum_size.y = clampf(view.y * 0.28, 220.0, 252.0)
	content.add_child(map_panel)
	var feature := _build_featured_panel(true, false)
	feature.custom_minimum_size.y = 148.0
	content.add_child(feature)
	var catalog := _build_vertical_catalog(LayoutMode.PHONE_PORTRAIT, true)
	content.add_child(catalog)
	return scroll

# =============================================================================
# GLOBE AND SELECTED-LOCATION DOSSIER
# =============================================================================

func _build_map_panel(mode: int) -> PanelContainer:
	var compact := mode == LayoutMode.PHONE_LANDSCAPE or mode == LayoutMode.PHONE_PORTRAIT
	var panel := _make_panel(COLOR_SURFACE, MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.42), MenuStyle.CARD_RADIUS)
	panel.name = "GlobePanel"
	if mode == LayoutMode.PHONE_PORTRAIT:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	var pad := 15 if mode == LayoutMode.DESKTOP else (12 if not compact else 8)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7 if not compact else 4)
	margin.add_child(stack)

	var map_header := HBoxContainer.new()
	map_header.add_theme_constant_override("separation", 8)
	var map_title_box := VBoxContainer.new()
	map_title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_title_box.add_theme_constant_override("separation", 1)
	var map_kicker := _make_kicker("The world is your fairway", 10 if compact else 11)
	map_kicker.name = "MapKicker"
	map_title_box.add_child(map_kicker)
	_map_summary_label = _make_label("", 12 if compact else 14, COLOR_TEXT_BRIGHT)
	_map_summary_label.name = "MapSummary"
	_map_summary_label.add_theme_font_override("font", SUBTITLE_FONT)
	_map_summary_label.clip_text = true
	map_title_box.add_child(_map_summary_label)
	map_header.add_child(map_title_box)

	var zoom_controls := HBoxContainer.new()
	zoom_controls.add_theme_constant_override("separation", 4)
	var center_button := Button.new()
	center_button.name = "CenterGlobe"
	center_button.text = "Center"
	center_button.tooltip_text = "Center the globe on the selected destination"
	center_button.custom_minimum_size = Vector2(56 if compact else 66, 32)
	center_button.add_theme_font_size_override("font_size", 11)
	_paint_utility_button(center_button, false)
	center_button.pressed.connect(func():
		if is_instance_valid(globe):
			globe.look_at_location(_selected_id))
	zoom_controls.add_child(center_button)
	var zoom_out := Button.new()
	zoom_out.name = "ZoomOut"
	zoom_out.text = "-"
	zoom_out.tooltip_text = "Zoom out"
	zoom_out.custom_minimum_size = Vector2(32, 32)
	zoom_out.add_theme_font_size_override("font_size", 17)
	_paint_utility_button(zoom_out, false)
	zoom_out.pressed.connect(func():
		if is_instance_valid(globe):
			globe.zoom_out())
	zoom_controls.add_child(zoom_out)
	var zoom_in := Button.new()
	zoom_in.name = "ZoomIn"
	zoom_in.text = "+"
	zoom_in.tooltip_text = "Zoom in"
	zoom_in.custom_minimum_size = Vector2(32, 32)
	zoom_in.add_theme_font_size_override("font_size", 17)
	_paint_utility_button(zoom_in, true)
	zoom_in.pressed.connect(func():
		if is_instance_valid(globe):
			globe.zoom_in())
	zoom_controls.add_child(zoom_in)
	map_header.add_child(zoom_controls)
	stack.add_child(map_header)

	globe = GlobeMap.new()
	globe.name = "GlobeMap"
	globe.set_land_style(GlobeMap.LandStyle.PIXEL)
	globe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe.custom_minimum_size = _globe_minimum(mode)
	globe.location_clicked.connect(_on_globe_location_clicked)
	if not _globe_view_state.is_empty():
		globe.set_view_state(_globe_view_state)
	stack.add_child(globe)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	_hint_label = _make_label(_map_hint(mode), 10 if compact else 11, COLOR_TEXT_QUIET)
	_hint_label.name = "MapHint"
	_hint_label.clip_text = true
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_hint_label)
	if not compact:
		footer.add_child(_build_map_legend())
	stack.add_child(footer)
	return panel

func _globe_minimum(mode: int) -> Vector2:
	match mode:
		LayoutMode.DESKTOP:
			return Vector2(310, 260)
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return Vector2(260, 220)
		LayoutMode.PHONE_LANDSCAPE:
			return Vector2(210, 176)
		_:
			return Vector2(220, 170)

func _map_hint(mode: int) -> String:
	if mode == LayoutMode.PHONE_LANDSCAPE or mode == LayoutMode.PHONE_PORTRAIT:
		return "Drag to explore  ·  tap a pin  ·  use + / - to zoom"
	return "Drag to rotate  ·  tap a pin or a destination card  ·  use + / - to zoom"

## The pin colours the globe itself uses (see GlobeMap.marker_color), so the
## legend always agrees with the map.
func _build_map_legend() -> Control:
	var legend := HBoxContainer.new()
	legend.name = "MarkerLegend"
	legend.add_theme_constant_override("separation", 10)
	legend.add_child(_legend_item(GlobeMap.marker_color({"active": true}), "Current"))
	legend.add_child(_legend_item(GlobeMap.marker_color({"owned": true}), "Owned"))
	legend.add_child(_legend_item(GlobeMap.marker_color({}), "For sale"))
	return legend

func _legend_item(color: Color, text: String) -> Control:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 5)
	item.add_child(_make_sprite(PixelIcon.Kind.PIN, 16, color))
	item.add_child(_make_label(text, 10, COLOR_TEXT_SECONDARY))
	return item

func _build_featured_panel(compact: bool, micro: bool) -> PanelContainer:
	_featured_compact = compact
	_featured_micro = micro
	var panel := _make_panel(COLOR_SURFACE_RAISED, MenuStyle.with_alpha(MenuStyle.ACCENT_SECONDARY, 0.42), MenuStyle.CARD_RADIUS)
	panel.name = "FeaturedLocation"
	var margin := MarginContainer.new()
	var pad := 13 if not compact else (9 if micro else 10)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6 if not compact else 4)
	margin.add_child(stack)

	if micro:
		_featured_name = _make_title_label("", 15)
		_featured_name.clip_text = true
		stack.add_child(_featured_name)
		_featured_meta = _make_label("", 11, COLOR_TEXT_SECONDARY)
		_featured_meta.clip_text = true
		stack.add_child(_featured_meta)
		stack.add_child(_build_featured_actions(true, true))
		_featured_status = _make_label("", 10, COLOR_TEXT_QUIET)
		_featured_status.clip_text = true
		stack.add_child(_featured_status)
		_featured_description = null
		_featured_stats = null
		return panel

	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 6)
	var cap := _make_kicker("Selected destination" if compact else "Location dossier", 10)
	cap.name = "FeaturedKicker"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_row.add_child(cap)
	_featured_status = _make_label("", 10, COLOR_MINT)
	_featured_status.add_theme_font_override("font", SUBTITLE_FONT)
	_featured_status.uppercase = true
	_featured_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap_row.add_child(_featured_status)
	stack.add_child(cap_row)

	_featured_name = _make_title_label("", 22 if not compact else 18)
	_featured_name.clip_text = true
	stack.add_child(_featured_name)
	_featured_meta = _make_label("", 12 if not compact else 11, COLOR_TEXT_SECONDARY)
	_featured_meta.clip_text = true
	stack.add_child(_featured_meta)

	_featured_description = _make_label("", 12, COLOR_TEXT_SECONDARY)
	_featured_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_featured_description.max_lines_visible = 2 if not compact else 1
	_featured_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(_featured_description)

	_featured_stats = _make_label("", 11, COLOR_MINT)
	_featured_stats.add_theme_font_override("font", SUBTITLE_FONT)
	_featured_stats.clip_text = true
	stack.add_child(_featured_stats)

	stack.add_child(_build_featured_actions(compact, false))
	return panel

## Buy beside Buy & Play for an unowned site; Play alone once it is owned.
func _build_featured_actions(compact: bool, micro: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "FeaturedActions"
	row.add_theme_constant_override("separation", 6 if not compact else 4)
	var height := 34 if micro else (42 if compact else 48)
	var font_size := 11 if micro else (12 if compact else 14)

	_featured_buy = Button.new()
	_featured_buy.name = "FeaturedBuy"
	_featured_buy.custom_minimum_size = Vector2(64 if micro else (72 if compact else 96), height)
	_featured_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_featured_buy.add_theme_font_size_override("font_size", font_size)
	_featured_buy.pressed.connect(_on_featured_buy_pressed)
	_paint_action_button(_featured_buy, false)
	row.add_child(_featured_buy)

	_featured_action = _make_action_shell(true)
	_featured_action.custom_minimum_size = Vector2(88 if micro else (108 if compact else 140), height)
	_featured_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_featured_action.add_theme_font_size_override("font_size", font_size)
	row.add_child(_featured_action)
	return row

# =============================================================================
# LOCATION CATALOGS
# =============================================================================

## Tall locations panel used by desktop and the rotated phone. On portrait
## phones the same panel is placed inside the page scroller, and its inner list
## grows naturally so the page—not a nested scroll view—owns the swipe.
func _build_vertical_catalog(mode: int, page_scrolled: bool) -> PanelContainer:
	var phone_landscape := mode == LayoutMode.PHONE_LANDSCAPE
	var compact := phone_landscape or mode == LayoutMode.PHONE_PORTRAIT
	var panel := _make_panel(COLOR_SURFACE, MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.42), MenuStyle.CARD_RADIUS)
	panel.name = "LocationDirectory"
	var margin := MarginContainer.new()
	var pad := 12 if not compact else (7 if phone_landscape else 10)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7 if not compact else 5)
	margin.add_child(stack)

	if phone_landscape:
		var controls := HBoxContainer.new()
		controls.add_theme_constant_override("separation", 4)
		_search_input = _make_search_input(32)
		_search_input.custom_minimum_size.x = 82
		_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(_search_input)
		controls.add_child(_build_filter_bar(true))
		controls.add_child(_make_reset_button(true))
		stack.add_child(controls)
	else:
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 6)
		var title_box := VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.add_theme_constant_override("separation", 0)
		var heading := _make_label("Course locations" if not compact else "Explore destinations",
			15 if not compact else 14, COLOR_TEXT_BRIGHT)
		heading.name = "CatalogHeading"
		heading.add_theme_font_override("font", SUBTITLE_FONT)
		title_box.add_child(heading)
		var caption := _make_label("Choose a site to buy & play, or switch courses" if not compact else "27 places to build your next course",
			10, COLOR_TEXT_QUIET)
		title_box.add_child(caption)
		title_row.add_child(title_box)
		title_row.add_child(_make_reset_button(compact))
		stack.add_child(title_row)
		_search_input = _make_search_input(38 if not compact else 34)
		stack.add_child(_search_input)
		stack.add_child(_build_filter_bar(compact))

	var scroll := ScrollContainer.new()
	scroll.name = "LocationScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_directory_scroll = scroll
	if page_scrolled:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var visible_rows := 4.0
		if phone_landscape and _built_size.y < 380.0:
			visible_rows = 3.0
		scroll.custom_minimum_size.y = visible_rows * _row_height_for(mode) + 10.0
	stack.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.name = "LocationRows"
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if page_scrolled else Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3 if compact else 4)
	scroll.add_child(_list_box)
	return panel

func _build_horizontal_catalog() -> PanelContainer:
	var panel := _make_panel(COLOR_SURFACE, MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.42), MenuStyle.CARD_RADIUS)
	panel.name = "DestinationShelf"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 8)
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_box.add_theme_constant_override("separation", 0)
	var heading := _make_label("Destination shelf", 15, COLOR_TEXT_BRIGHT)
	heading.name = "ShelfHeading"
	heading.add_theme_font_override("font", SUBTITLE_FONT)
	heading_box.add_child(heading)
	heading_box.add_child(_make_label("Swipe through your company's worldwide portfolio", 10, COLOR_TEXT_QUIET))
	heading_row.add_child(heading_box)
	heading_row.add_child(_make_reset_button(true))
	stack.add_child(heading_row)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	_search_input = _make_search_input(34)
	_search_input.custom_minimum_size.x = 130
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_search_input)
	controls.add_child(_build_filter_bar(true))
	stack.add_child(controls)

	var scroll := ScrollContainer.new()
	scroll.name = "DestinationScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 112
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_directory_scroll = scroll
	_horizontal_directory = true
	stack.add_child(scroll)

	_list_box = HBoxContainer.new()
	_list_box.name = "DestinationCards"
	_list_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)
	return panel

func _make_search_input(height: int) -> LineEdit:
	var search := LineEdit.new()
	search.name = "LocationSearch"
	search.placeholder_text = "Search name, region or course style"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = height
	search.add_theme_font_override("font", BODY_FONT)
	search.add_theme_font_size_override("font_size", 12)
	search.add_theme_color_override("font_color", COLOR_TEXT_BRIGHT)
	search.add_theme_color_override("font_placeholder_color", COLOR_TEXT_QUIET)
	search.add_theme_color_override("caret_color", MenuStyle.ACCENT_PRIMARY)
	search.add_theme_color_override("selection_color", MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.35))
	PixelButtonStyle.paint_field(search, MenuStyle.with_alpha(COLOR_GOLD, 0.85), COLOR_SURFACE_INSET, 8)
	search.text = _search_query
	search.text_changed.connect(_on_search_changed)
	return search

func _build_filter_bar(compact: bool) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "LocationFilters"
	bar.add_theme_constant_override("separation", 4)
	for filter in [BrowseFilter.ALL, BrowseFilter.OWNED, BrowseFilter.AFFORDABLE]:
		var button := Button.new()
		button.name = "Filter%d" % int(filter)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(51 if compact else 72, 31 if compact else 33)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 10 if compact else 11)
		button.tooltip_text = _filter_description(int(filter))
		_paint_filter_button(button)
		button.pressed.connect(_on_filter_pressed.bind(int(filter)))
		_filter_buttons[int(filter)] = button
		bar.add_child(button)
	_update_filter_buttons()
	return bar

func _make_reset_button(compact: bool) -> Button:
	var reset := Button.new()
	reset.name = "ResetWorldButton"
	reset.text = "Reset" if compact else "Reset World"
	reset.tooltip_text = "Re-roll the ready land and asking price for every unowned location. Your owned sites are untouched."
	reset.custom_minimum_size = Vector2(67 if compact else 103, 32 if compact else 34)
	reset.add_theme_font_size_override("font_size", 10 if compact else 11)
	_paint_utility_button(reset, false)
	reset.pressed.connect(_on_reset_world_pressed)
	return reset

# =============================================================================
# REFRESH, SEARCH AND LOCATION ROWS
# =============================================================================

## Rebuild markers and the visible directory from current company state.
func refresh() -> void:
	if not is_instance_valid(_list_box) or not is_instance_valid(globe):
		return
	if _selected_id.is_empty() or not WorldLocations.has_location(_selected_id):
		_selected_id = WorldMap.active_location_id if WorldMap.is_owned(WorldMap.active_location_id) \
			else str(WorldLocations.get_all()[0].get("id", "monterey"))

	var markers: Array = []
	for def in WorldLocations.get_all():
		markers.append(_row_state(def))
	globe.set_locations(markers)
	globe.set_selected(_selected_id)
	if _first_show:
		globe.look_at_location(_selected_id)
		_first_show = false

	_update_header()
	_update_map_header()
	_update_featured()
	_rebuild_catalog()
	_update_row_styles()
	_restore_scroll_positions.call_deferred()

func _update_header() -> void:
	if is_instance_valid(_money_label):
		var cash := "Unlimited" if GameManager.unlimited_money else _format_money(GameManager.money)
		if _layout_mode == LayoutMode.PHONE_LANDSCAPE or _layout_mode == LayoutMode.PHONE_PORTRAIT:
			cash = "Unlimited" if GameManager.unlimited_money else _format_money_compact(GameManager.money)
		_money_label.text = cash
		_money_label.tooltip_text = "Company balance: %s" % (
			"Unlimited" if GameManager.unlimited_money else _format_money(GameManager.money))
	_update_filter_buttons()

func _update_map_header() -> void:
	if not is_instance_valid(_map_summary_label):
		return
	var owned := 0
	for def in WorldLocations.get_all():
		if WorldMap.is_owned(str(def.get("id", ""))):
			owned += 1
	_map_summary_label.text = "%d destinations  ·  %d owned" % [WorldLocations.get_all().size(), owned]

func _row_state(def: Dictionary) -> Dictionary:
	var id := str(def.get("id", ""))
	var owned := WorldMap.is_owned(id)
	var location_size := int(def.get("size", WorldLocations.Size.SMALL))
	var price := WorldMap.get_price(id)
	var parcels := WorldMap.get_total_parcels(id)
	var ready_parcels := WorldMap.get_unlocked_parcels(id).size()
	return {
		"id": id,
		"name": str(def.get("name", id)),
		"region": str(def.get("region", "")),
		"description": str(def.get("description", "")),
		"theme_name": CourseTheme.get_theme_name(int(def.get("theme", 0))),
		"size_name": WorldLocations.get_size_name(location_size),
		"capacity": WorldLocations.get_hole_capacity(location_size),
		"parcels": parcels,
		"ready": ready_parcels,
		"price": price,
		"owned": owned,
		"active": id == WorldMap.active_location_id,
		"affordable": owned or GameManager.can_afford(price),
		"lat": float(def.get("lat", 0.0)),
		"lon": float(def.get("lon", 0.0)),
	}

func _rebuild_catalog() -> void:
	if not is_instance_valid(_list_box):
		return
	var prior_scroll := 0
	if is_instance_valid(_directory_scroll):
		prior_scroll = _directory_scroll.scroll_horizontal if _horizontal_directory \
			else _directory_scroll.scroll_vertical
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_rows.clear()

	var matches := 0
	for def in WorldLocations.get_all():
		var state := _row_state(def)
		if not _matches_browse(state):
			continue
		matches += 1
		var row := _build_location_card(state, _layout_mode == LayoutMode.TABLET_LANDSCAPE \
			or _layout_mode == LayoutMode.TABLET_PORTRAIT)
		_list_box.add_child(row)
		_rows[str(state["id"])] = row
		row.gui_input.connect(_on_row_input.bind(str(state["id"])))

	if matches == 0:
		var empty := _make_label("No locations match. Try a different search or filter.", 12, COLOR_TEXT_QUIET)
		empty.custom_minimum_size = Vector2(0, 48)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list_box.add_child(empty)
	if _unbounded_phone_list and is_instance_valid(_directory_scroll):
		var row_h := _row_height_for(_layout_mode)
		var gap := float(_list_box.get_theme_constant("separation"))
		_directory_scroll.custom_minimum_size.y = maxf(48.0, matches * row_h + maxi(matches - 1, 0) * gap)
	if not _unbounded_phone_list and is_instance_valid(_directory_scroll) and not _horizontal_directory:
		_directory_scroll.scroll_vertical = 0 if not _search_query.is_empty() else prior_scroll
	elif is_instance_valid(_directory_scroll) and _horizontal_directory:
		_directory_scroll.scroll_horizontal = prior_scroll
	_update_filter_buttons()
	_update_row_styles()

func _matches_browse(state: Dictionary) -> bool:
	match _browse_filter:
		BrowseFilter.OWNED:
			if not bool(state["owned"]):
				return false
		BrowseFilter.AFFORDABLE:
			if bool(state["owned"]) or not bool(state["affordable"]):
				return false
	var query := _search_query.strip_edges().to_lower()
	if query.is_empty():
		return true
	var haystack := "%s %s %s %s" % [state["name"], state["region"], state["theme_name"], state["size_name"]]
	return haystack.to_lower().contains(query)

func _build_location_card(state: Dictionary, horizontal_card: bool) -> PanelContainer:
	if horizontal_card:
		return _build_shelf_card(state)
	var row := PanelContainer.new()
	row.name = "Location_%s" % str(state["id"])
	row.custom_minimum_size = Vector2(0, _row_height_for(_layout_mode))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.set_meta("location_id", state["id"])
	row.tooltip_text = _location_tooltip(state)
	var margin := MarginContainer.new()
	var compact := _layout_mode == LayoutMode.PHONE_LANDSCAPE or _layout_mode == LayoutMode.PHONE_PORTRAIT
	margin.add_theme_constant_override("margin_left", 8 if compact else 10)
	margin.add_theme_constant_override("margin_right", 8 if compact else 10)
	margin.add_theme_constant_override("margin_top", 5 if compact else 6)
	margin.add_theme_constant_override("margin_bottom", 5 if compact else 6)
	row.add_child(margin)

	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	margin.add_child(contents)
	# A little pennant marks each site, dressed in its state's colour: gold
	# for the course being played, green for owned, quiet grey-green for sale.
	var marker := _make_sprite(PixelIcon.Kind.FLAG, 16 if compact else 32, _state_accent(state))
	marker.name = "StateFlag"
	contents.add_child(marker)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = 0
	info.add_theme_constant_override("separation", 0)
	contents.add_child(info)
	var name_label := _make_label("%s  ·  %s" % [state["name"], state["region"]] if not str(state["region"]).is_empty() \
		else str(state["name"]), 13 if compact else 14, COLOR_TEXT_BRIGHT)
	name_label.name = "LocationName"
	name_label.add_theme_font_override("font", SUBTITLE_FONT)
	name_label.clip_text = true
	info.add_child(name_label)
	var detail := _make_label("%s  ·  %s  ·  %d/%d plots ready" % [
		state["theme_name"], state["size_name"], int(state["ready"]), int(state["parcels"])],
		10, COLOR_TEXT_SECONDARY)
	detail.name = "LocationDetails"
	detail.clip_text = true
	info.add_child(detail)

	var price := _make_label("Owned" if state["owned"] else _format_money(int(state["price"])),
		12 if compact else 13, COLOR_MINT if state["owned"] else (COLOR_GOLD if state["affordable"] else UIConstants.COLOR_DANGER))
	price.name = "LocationPrice"
	price.add_theme_font_override("font", SUBTITLE_FONT)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.custom_minimum_size.x = 68 if compact else 82
	contents.add_child(price)
	contents.add_child(_make_row_action(state, compact))
	_apply_row_style(row, state)
	return row

func _build_shelf_card(state: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Location_%s" % str(state["id"])
	card.custom_minimum_size = Vector2(TABLET_CARD_WIDTH, TABLET_CARD_HEIGHT)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.set_meta("location_id", state["id"])
	card.tooltip_text = _location_tooltip(state)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)
	var name_label := _make_label(str(state["name"]), 15, COLOR_TEXT_BRIGHT)
	name_label.add_theme_font_override("font", SUBTITLE_FONT)
	name_label.clip_text = true
	stack.add_child(name_label)
	var region := _make_label(str(state["region"]), 10, COLOR_TEXT_QUIET)
	region.clip_text = true
	stack.add_child(region)
	var details := _make_label("%s  ·  %s" % [state["theme_name"], state["size_name"]], 10, COLOR_TEXT_SECONDARY)
	details.clip_text = true
	stack.add_child(details)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	footer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	footer.alignment = BoxContainer.ALIGNMENT_END
	var price := _make_label("Owned" if state["owned"] else _format_money(int(state["price"])),
		11, COLOR_MINT if state["owned"] else (COLOR_GOLD if state["affordable"] else UIConstants.COLOR_DANGER))
	price.add_theme_font_override("font", SUBTITLE_FONT)
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.clip_text = true
	footer.add_child(price)
	footer.add_child(_make_row_action(state, true))
	stack.add_child(footer)
	_apply_row_style(card, state)
	return card

func _make_row_action(state: Dictionary, compact: bool) -> Button:
	var action := Button.new()
	action.name = "LocationAction"
	var landscape := _layout_mode == LayoutMode.PHONE_LANDSCAPE
	action.custom_minimum_size = Vector2(88 if landscape else (96 if compact else 108),
		34 if landscape else (40 if compact else 38))
	action.add_theme_font_size_override("font_size", 10 if landscape else (11 if compact else 12))
	if bool(state["owned"]):
		if bool(state["active"]):
			action.text = "Playing"
			action.disabled = true
			action.tooltip_text = "This is the course you are playing right now"
		else:
			action.text = "Play"
			action.tooltip_text = "Switch to this course; the location you leave keeps its progress"
			action.pressed.connect(func(): play_location_requested.emit(str(state["id"])))
	else:
		action.text = BUY_AND_PLAY_LABEL
		action.disabled = not bool(state["affordable"])
		action.tooltip_text = _buy_and_play_tooltip(state)
		action.pressed.connect(_on_buy_and_play_pressed.bind(str(state["id"])))
	_paint_action_button(action, false)
	return action

func _buy_tooltip(state: Dictionary) -> String:
	var price := _format_money(int(state["price"]))
	if bool(state["affordable"]):
		return "Buy %s for %s. You stay on the map to keep browsing." % [state["name"], price]
	return "You need %s to buy %s" % [price, state["name"]]

func _buy_and_play_tooltip(state: Dictionary) -> String:
	var price := _format_money(int(state["price"]))
	if bool(state["affordable"]):
		return "Buy %s for %s and start playing there" % [state["name"], price]
	return "You need %s to buy %s" % [price, state["name"]]

func _location_tooltip(state: Dictionary) -> String:
	return "%s — %s\n%s · %d-hole capacity · %d of %d plots ready\n%s" % [
		state["name"], state["region"], state["size_name"], state["capacity"],
		state["ready"], state["parcels"], state["description"]]

func _row_height_for(mode: int) -> float:
	match mode:
		LayoutMode.PHONE_LANDSCAPE:
			return LANDSCAPE_ROW_HEIGHT
		LayoutMode.PHONE_PORTRAIT:
			return PHONE_ROW_HEIGHT
		LayoutMode.DESKTOP:
			return 56.0 if _built_size.y < 760.0 else DESKTOP_ROW_HEIGHT
		_:
			return 58.0

## The colour a location's pennant wears: the same state colours as the
## globe's pins (active gold, owned green, for-sale cream, out-of-reach
## grey), so the rows and the map never disagree.
func _state_accent(state: Dictionary) -> Color:
	return GlobeMap.marker_color(state)

func _apply_row_style(row: PanelContainer, state: Dictionary) -> void:
	var selected := str(state["id"]) == _selected_id
	var bg := MenuStyle.CARD_BG_HOVER if selected else MenuStyle.CARD_BG
	var border := MenuStyle.ACCENT_PRIMARY if selected else MenuStyle.with_alpha(
		MenuStyle.ACCENT_SECONDARY if state["owned"] else MenuStyle.ACCENT_UTILITY, 0.58)
	row.add_theme_stylebox_override("panel", _panel_style(bg, border, 2 if selected else 1, 9))

func _update_row_styles() -> void:
	for id in _rows:
		var row := _rows[id] as PanelContainer
		if not is_instance_valid(row):
			continue
		var state := _row_state(WorldLocations.get_definition(str(id)))
		_apply_row_style(row, state)

func _update_featured() -> void:
	if not is_instance_valid(_featured_name):
		return
	var def := WorldLocations.get_definition(_selected_id)
	if def.is_empty():
		return
	var state := _row_state(def)
	_featured_name.text = str(state["name"])
	_featured_meta.text = "%s  ·  %s  ·  %s" % [state["region"], state["theme_name"], state["size_name"]]
	if is_instance_valid(_featured_description):
		_featured_description.text = str(state["description"])
	if is_instance_valid(_featured_stats):
		_featured_stats.text = "%d-hole capacity  ·  %d/%d plots ready  ·  %s" % [
			state["capacity"], state["ready"], state["parcels"],
			"Owned" if state["owned"] else _format_money(int(state["price"]))]
	if is_instance_valid(_featured_status):
		if state["active"]:
			_featured_status.text = "CURRENT COURSE"
			_featured_status.add_theme_color_override("font_color", COLOR_MINT)
		elif state["owned"]:
			_featured_status.text = "IN YOUR PORTFOLIO"
			_featured_status.add_theme_color_override("font_color", COLOR_MINT)
		elif state["affordable"]:
			_featured_status.text = "READY TO ACQUIRE"
			_featured_status.add_theme_color_override("font_color", COLOR_GOLD)
		else:
			_featured_status.text = "OUT OF REACH"
			_featured_status.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	var owned := bool(state["owned"])
	var active := bool(state["active"])
	var affordable := bool(state["affordable"])
	if is_instance_valid(_featured_buy):
		_featured_buy.visible = not owned
		if not owned:
			_featured_buy.text = BUY_LABEL if (_featured_micro or _featured_compact) \
				else ("BUY · %s" % _format_money(int(state["price"])))
			_featured_buy.disabled = not affordable
			_featured_buy.tooltip_text = _buy_tooltip(state)
			_paint_action_button(_featured_buy, false)
			_apply_featured_icon(_featured_buy, PixelIcon.Kind.COIN, _featured_buy.disabled)
	if not is_instance_valid(_featured_action):
		return
	if active:
		_featured_action.text = "Playing now" if _featured_compact else "CURRENT COURSE"
		_featured_action.disabled = true
		_featured_action.tooltip_text = "This is the course you are playing right now"
	elif owned:
		_featured_action.text = "Play" if _featured_micro else "PLAY THIS COURSE"
		_featured_action.disabled = false
		_featured_action.tooltip_text = "Switch to this course; the location you leave keeps its progress"
	else:
		_featured_action.text = BUY_AND_PLAY_LABEL if (_featured_micro or _featured_compact) else "BUY & PLAY"
		_featured_action.disabled = not affordable
		_featured_action.tooltip_text = _buy_and_play_tooltip(state)
	_paint_action_button(_featured_action, true)
	_apply_featured_icon(_featured_action, PixelIcon.Kind.PLAY, _featured_action.disabled)

func _apply_featured_icon(button: Button, kind: int, dimmed: bool) -> void:
	button.icon = PixelIcon.texture(
		kind,
		16 if _featured_compact or _featured_micro else 32,
		MenuStyle.INK if not dimmed else UIConstants.COLOR_TEXT_MUTED, dimmed)
	button.add_theme_constant_override("h_separation", 8)

func _make_action_shell(primary: bool) -> Button:
	var button := Button.new()
	button.name = "FeaturedAction"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(_on_featured_action_pressed)
	_paint_action_button(button, primary)
	return button

# =============================================================================
# INTERACTION
# =============================================================================

## Clicking a destination in the list selects it and flies the globe round to
## centre on it, the same as clicking its pin on the map.
func _on_row_input(event: InputEvent, location_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_location(location_id)
		if WorldLocations.has_location(location_id) and is_instance_valid(globe):
			globe.look_at_location(location_id)

func _on_globe_location_clicked(location_id: String) -> void:
	select_location(location_id)
	if is_instance_valid(globe):
		globe.look_at_location(location_id)

func select_location(location_id: String) -> void:
	if not WorldLocations.has_location(location_id):
		return
	_selected_id = location_id
	if is_instance_valid(globe):
		globe.set_selected(location_id)
	_update_featured()
	_update_row_styles()

func _on_featured_buy_pressed() -> void:
	_on_buy_pressed(_selected_id)

func _on_featured_action_pressed() -> void:
	if WorldMap.is_owned(_selected_id):
		if _selected_id != WorldMap.active_location_id:
			play_location_requested.emit(_selected_id)
	else:
		_on_buy_and_play_pressed(_selected_id)

## Buy an unowned site and stay on the map so more sites can be browsed.
func _on_buy_pressed(location_id: String) -> void:
	_selected_id = location_id
	if not WorldMap.buy_location(location_id):
		return
	if is_instance_valid(globe):
		globe.look_at_location(location_id)
	refresh()

## Buy an unowned site and start playing it in one step. Owned sites are a
## no-op here: their rows already offer Play, and buying twice never charges.
func _on_buy_and_play_pressed(location_id: String) -> void:
	_selected_id = location_id
	if not WorldMap.buy_location(location_id):
		return
	if is_instance_valid(globe):
		globe.look_at_location(location_id)
	if location_id == WorldMap.active_location_id:
		return
	play_location_requested.emit(location_id)

func _on_search_changed(text: String) -> void:
	_search_query = text
	_rebuild_catalog()

func _on_filter_pressed(filter: int) -> void:
	_browse_filter = filter
	_rebuild_catalog()

func _on_reset_world_pressed() -> void:
	var dialog := ConfirmDialog.new(
		"Every location you have not bought will get a new amount of ready land and a new asking price. Locations you own never change.",
		"Reset World", "Keep World", UIConstants.COLOR_WARNING)
	add_child(dialog)
	dialog.confirmed.connect(func():
		WorldMap.reset_world()
		refresh()
		EventBus.notify("World re-rolled — unowned locations have new land and prices.", "info"))

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

func _restore_scroll_positions() -> void:
	if is_instance_valid(_phone_scroll):
		_phone_scroll.scroll_vertical = _phone_scroll_value
	if is_instance_valid(_directory_scroll):
		if _horizontal_directory:
			_directory_scroll.scroll_horizontal = _catalog_scroll_value
		else:
			_directory_scroll.scroll_vertical = _catalog_scroll_value

func _update_filter_buttons() -> void:
	for filter in _filter_buttons:
		var button := _filter_buttons[filter] as Button
		if not is_instance_valid(button):
			continue
		button.text = _filter_label(int(filter))
		button.button_pressed = int(filter) == _browse_filter

func _filter_label(filter: int) -> String:
	var compact := _layout_mode == LayoutMode.PHONE_LANDSCAPE or _layout_mode == LayoutMode.PHONE_PORTRAIT
	if compact:
		match filter:
			BrowseFilter.OWNED: return "Owned"
			BrowseFilter.AFFORDABLE: return "In reach"
			_: return "All"
	match filter:
		BrowseFilter.OWNED: return "Owned"
		BrowseFilter.AFFORDABLE: return "Within budget"
		_: return "All sites"

func _filter_description(filter: int) -> String:
	match filter:
		BrowseFilter.OWNED: return "Show locations already in your portfolio"
		BrowseFilter.AFFORDABLE: return "Show unowned locations the company can afford right now"
		_: return "Show every course location"

# =============================================================================
# VISUAL HELPERS
# =============================================================================

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## The small gold caption above a section, like the setup screen's kickers.
func _make_kicker(text: String, font_size: int) -> Label:
	var kicker := _make_label(text, font_size, COLOR_GOLD)
	kicker.add_theme_font_override("font", SUBTITLE_FONT)
	kicker.uppercase = true
	return kicker

## A heading in the bold weight: the screen title, a location's name, the
## treasury's balance.
func _make_title_label(text: String, font_size: int, color: Color = COLOR_TEXT_BRIGHT) -> Label:
	var title := _make_label(text, font_size, color)
	title.add_theme_font_override("font", TITLE_FONT)
	return title

## One of the menu sprites (PixelIcon), nearest-filtered so its pixels stay
## hard at whatever size the layout asks for.
func _make_sprite(kind: int, side: int, accent: Color) -> TextureRect:
	var grid_side := PixelIcon.snapped_side(side)
	var sprite := TextureRect.new()
	sprite.texture = PixelIcon.texture(kind, grid_side, accent)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(grid_side, grid_side)
	sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sprite

func _make_panel(bg: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(bg, border, 1, radius))
	return panel

## The atlas's panels wear the same notched nine-patch pixel frame as the
## title and setup screens (PixelButtonStyle): straight edges, ink outline,
## accent trim, no rounded corners and no soft shadow. The signature keeps
## the old call sites; the pixel recipe has one fixed border weight and no
## corner radius, so those two arguments are only kept for readability.
static func _panel_style(bg: Color, border: Color, _border_width: int, _radius: int) -> StyleBoxTexture:
	return PixelButtonStyle.panel_style(border, bg, 0, 0)

## Paint a small menu action (Back, Center, +, -, Reset): a pixel card with
## the semibold type.
func _paint_utility_button(button: Button, gold: bool) -> void:
	var accent := MenuStyle.ACCENT_PRIMARY if gold else MenuStyle.ACCENT_UTILITY
	PixelButtonStyle.paint_card(button, accent, 0.0, 8, UIConstants.COLOR_TEXT, MenuStyle.TITLE_COLOR)
	button.add_theme_font_override("font", SUBTITLE_FONT)
	button.add_theme_color_override("font_pressed_color", UIConstants.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)

## Paint one of the browse chooser's toggles: quiet until pressed, when the
## frame sinks and lights its trim, like the setup screen's option cards.
func _paint_filter_button(button: Button) -> void:
	PixelButtonStyle.paint_choice(button, MenuStyle.ACCENT_SECONDARY)
	button.add_theme_font_override("font", SUBTITLE_FONT)
	button.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	button.add_theme_color_override("font_hover_color", MenuStyle.TITLE_COLOR)
	button.add_theme_color_override("font_pressed_color", MenuStyle.ACCENT_PRIMARY)
	button.add_theme_color_override("font_focus_color", MenuStyle.TITLE_COLOR)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)

## Paint a Buy & Play / Play action: the featured destination's gold slab (bold ink
## type on the gold fill) or a row's quiet green card.
func _paint_action_button(button: Button, primary: bool) -> void:
	if primary:
		PixelButtonStyle.paint_primary(button)
		button.add_theme_font_override("font", TITLE_FONT)
		button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)
	else:
		PixelButtonStyle.paint_card(button, MenuStyle.ACCENT_SECONDARY, 0.0, 7,
			COLOR_TEXT_BRIGHT, MenuStyle.TITLE_COLOR)
		button.add_theme_font_override("font", SUBTITLE_FONT)
		button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _format_money_compact(amount: int) -> String:
	if amount >= 1000000:
		return "$%.1fM" % (float(amount) / 1000000.0)
	if amount >= 1000:
		return "$%dK" % floori(float(amount) / 1000.0)
	return _format_money(amount)

static func _format_money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := "$"
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
