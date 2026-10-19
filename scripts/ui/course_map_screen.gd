extends Control
class_name CourseMapScreen
const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")
## CourseMapScreen - the whole course on one isometric map, in four modes.
##
## Opened from the Club tab's Land Parcels button or with Shift+M, and it freezes
## the course while it is up (see main.gd). It edits the live game in place: a
## parcel bought here is bought, a hole moved here is moved, and the course
## behind the screen is the same course it hands back.
##
## The mode decides what the map is about and which panel sits beside it:
##
##   LAND     owned land, land for sale and its price; buy from the strip under
##            the map or from the panel (LandManager, the Land panel's rules).
##   ROUTING  the round in play order: move a hole up or down the card, cycle its
##            par, turn it round, close it, or play the course backwards
##            (HoleManager, with HoleRouting judging the walks in between).
##   AURA     where golfers left happy and unhappy comments (CourseAura).
##   STAFF    the ground each employee covers; hire, fire and re-post them
##            (StaffManager).
##
## Each viewport shape gets its own composition rather than one squeezed into
## the others:
##
##   DESKTOP          heading and mode tabs in the top bar, map left, dossier
##                    panel down the right.
##   TABLET_LANDSCAPE modes on a left rail, map centre, panel right with a toggle
##                    that folds the panel away and gives the map the width.
##   TABLET_PORTRAIT  tabs across the top, map above, panel as a sheet below it.
##   PHONE_LANDSCAPE  a compact bar, modes on a rail, and the panel behind a
##                    Details sheet that slides in over the right of the map.
##   PHONE_PORTRAIT   tabs across the top, map filling the body, and the panel as
##                    a bottom sheet that peeks along the edge and lifts to half
##                    the screen when tapped.
##
## The map control owns no rules (see CourseMapView): it reports presses, and
## this screen decides what they mean. Every two-step action - hire then tap,
## move then tap, pick then confirm - is stated in the strip under the map, so
## the words live in one place whatever shape the screen is.

signal back_requested()
signal advice_action_requested(advice: Dictionary)

## The five compositions. Same shape as WorldMapScreen's, and pure so every
## breakpoint can be checked without a window (see layout_mode_for).


const RAIL_WIDTH := 96.0
const RAIL_WIDTH_PHONE := 78.0
const PANEL_WIDTH_DESKTOP := 348.0
const PANEL_WIDTH_TABLET := 286.0
## The phone sheet: how tall it stands when lifted (portrait), and how wide it is
## when it slides in from the edge (landscape).
const SHEET_LIFT_RATIO := 0.56
const SHEET_PEEK_HEIGHT := 76.0
const SHEET_WIDTH_RATIO := 0.46
const STRIP_HEIGHT_DESKTOP := 38.0
const STRIP_HEIGHT_TOUCH := 50.0
## The panel's own height when it sits under the map (tablet portrait).
const TABLET_SHEET_HEIGHT := 268.0

## The four modes, in tab order: what the map is about, and the words for it.
const MODES: Array = [
	{
		"mode": CourseMapView.Mode.LAND,
		"name": "Land",
		"blurb": "Buy land and read what you own",
	},
	{
		"mode": CourseMapView.Mode.ROUTING,
		"name": "Routing",
		"blurb": "Reorder the holes and shorten the walks between them",
	},
	{
		"mode": CourseMapView.Mode.AURA,
		"name": "Aura",
		"blurb": "Course review, guest experience and where golfers are happy and unhappy",
	},
	{
		"mode": CourseMapView.Mode.STAFF,
		"name": "Staff",
		"blurb": "Hire, fire and post the crew around the course",
	},
]

var layout: int = Kit.LayoutMode.DESKTOP
var mode: int = CourseMapView.Mode.LAND
## What is picked: {"kind": "parcel"|"hole"|"aura"|"staff", "value": ...}.
var selection: Dictionary = {}
## An action waiting for a tap on the map: {"kind": "move_staff"|"hire_staff",
## "value": ...}. The map draws the ground it is about to hand over while one is
## set, so the tap is never blind.
var pending: Dictionary = {}
## A confirmation waiting in the strip: {"kind": "buy", "value": parcel}.
var offer: Dictionary = {}
## The tablet landscape's dossier panel is folded away, so the map has the whole
## width.
var panel_hidden: bool = false
## The phone sheet is lifted (portrait) or slid in (landscape). It starts folded
## down, so the map has the screen to itself until the panel is asked for.
var sheet_open: bool = false

var map: CourseMapView = null

var _backdrop: MenuBackdrop = null
var _root: MarginContainer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _money_label: Label = null
var _rail_stack: VBoxContainer = null
var _tab_row: HBoxContainer = null
var _tab_buttons: Array = []
var _map_column: VBoxContainer = null
var _map_stack: Control = null
var _panel_column: PanelContainer = null
var _panel_toggle: Button = null
var _panel_scroll: ScrollContainer = null
var _sheet_layer: Control = null
var _sheet: PanelContainer = null
var _sheet_scrim: ColorRect = null
var _sheet_title: Label = null
var _sheet_chevron: Label = null
var _strip: PanelContainer = null
var _strip_label: Label = null
var _strip_actions: HBoxContainer = null
var _zoom_label: Label = null

var _land_panel: CourseMapLandPanel = null
var _routing_panel: CourseMapRoutingPanel = null
var _aura_panel: CourseMapAuraPanel = null
var _staff_panel: CourseMapStaffPanel = null
var _built_size := Vector2.ZERO
var _building: bool = false

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	name = "CourseMapScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_panels()
	_build_map()
	Screen.changed.connect(_on_screen_changed)
	EventBus.holes_reordered.connect(_on_course_changed)
	EventBus.hole_updated.connect(_on_hole_changed)
	EventBus.hole_deleted.connect(_on_hole_changed)
	EventBus.course_rating_changed.connect(_on_course_changed_rating)
	_build_structure()
	refresh()

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _exit_tree() -> void:
	# Every panel is inside this screen's own subtree - parked on it, or in the
	# panel frame - so whoever frees the screen frees them with it.
	if Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)
	if EventBus.holes_reordered.is_connected(_on_course_changed):
		EventBus.holes_reordered.disconnect(_on_course_changed)
	for signal_name in ["hole_updated", "hole_deleted"]:
		if EventBus.is_connected(signal_name, _on_hole_changed):
			EventBus.disconnect(signal_name, _on_hole_changed)
	if EventBus.course_rating_changed.is_connected(_on_course_changed_rating):
		EventBus.course_rating_changed.disconnect(_on_course_changed_rating)

func _build_panels() -> void:
	_land_panel = CourseMapLandPanel.new()
	_routing_panel = CourseMapRoutingPanel.new()
	_aura_panel = CourseMapAuraPanel.new()
	_staff_panel = CourseMapStaffPanel.new()
	for panel in _mode_panels():
		panel.visible = false
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_land_panel.parcel_selected.connect(func(parcel): _select("parcel", parcel))
	_land_panel.buy_requested.connect(_on_buy_requested)

	_routing_panel.hole_selected.connect(func(number): _select("hole", number))
	_routing_panel.move_requested.connect(_on_hole_move)
	_routing_panel.flip_requested.connect(_on_hole_flip)
	_routing_panel.par_requested.connect(_on_hole_par)
	_routing_panel.toggle_requested.connect(_on_hole_toggle)
	_routing_panel.reverse_requested.connect(_on_holes_reverse)

	_aura_panel.cell_selected.connect(func(cell): _select("aura", cell))
	_aura_panel.hole_selected.connect(_on_aura_hole_selected)
	_aura_panel.advice_selected.connect(_on_aura_advice_selected)

	_staff_panel.staff_selected.connect(func(index): _select("staff", index))
	_staff_panel.move_requested.connect(_on_staff_move_requested)
	_staff_panel.fire_requested.connect(_on_staff_fire_requested)
	_staff_panel.hire_armed.connect(_on_staff_hire_armed)

func _build_map() -> void:
	map = CourseMapView.new()
	map.name = "CourseMap"
	map.map_pressed.connect(_on_map_pressed)
	map.hover_changed.connect(_on_hover_changed)
	map.hover_cleared.connect(_on_hover_cleared)
	map.view_changed.connect(_refresh_zoom_label)

# =============================================================================
# PUBLIC API
# =============================================================================

## Bring the screen up to date with the live course: the map re-reads it, the
## mode's panel rebuilds itself, and the tabs, title and strip follow the mode.
func refresh() -> void:
	if map == null:
		return
	map.set_mode(mode)
	map.set_compact_texture(_map_is_small())
	map.refresh()
	if selection.is_empty():
		map.clear_selection()
	else:
		map.set_selection(str(selection.get("kind", "")), selection.get("value", null))
	if pending.is_empty():
		map.clear_pending()
	else:
		map.set_pending(pending)
	_refresh_panel()
	_refresh_tabs()
	_refresh_zoom_label()
	_refresh_title()
	_refresh_strip()

## Switch mode: what the map is about, and which panel it is shown with.
func set_mode(new_mode: int) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	selection = {}
	offer = {}
	pending = {}
	if map:
		map.clear_pending()
		map.clear_selection()
		map.set_mode(mode)
	_staff_panel.set_armed(-1)
	_refresh_panel()
	_refresh_tabs()
	_refresh_title()
	_refresh_strip()

# =============================================================================
# STRUCTURE
# =============================================================================

## The composition this viewport calls for. Pure, so the breakpoints can be
## checked without a window.
static func layout_mode_for(view: Vector2) -> int:
	return Kit.layout_mode_for(view)

## True where the map is drawn small: the phone shapes and the portrait tablet,
## where the panel takes half the height.
func _map_is_small() -> bool:
	return layout != Kit.LayoutMode.DESKTOP and layout != Kit.LayoutMode.TABLET_LANDSCAPE

func _uses_rail() -> bool:
	return layout == Kit.LayoutMode.TABLET_LANDSCAPE or layout == Kit.LayoutMode.PHONE_LANDSCAPE

func _uses_sheet() -> bool:
	return layout == Kit.LayoutMode.PHONE_LANDSCAPE or layout == Kit.LayoutMode.PHONE_PORTRAIT

func _view_size() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return Screen.window_size

func _on_screen_changed(window_size: Vector2, _scale: float) -> void:
	_relayout_for(window_size)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and _root != null and not _building:
		_relayout_for(size)

func _relayout_for(view: Vector2) -> void:
	var next := layout_mode_for(view)
	var grown := absf(view.x - _built_size.x) > maxf(96.0, _built_size.x * 0.16) \
		or absf(view.y - _built_size.y) > maxf(72.0, _built_size.y * 0.16)
	if next == layout and not grown:
		if _sheet != null:
			_layout_sheet()
		return
	_build_structure()
	refresh()

## Tear the composition down and put it back together for the current shape. The
## map control itself survives - it is re-parented rather than rebuilt - so the
## view the player had (the zoom, the pan, the picked spot) is the view they keep.
func _build_structure() -> void:
	_building = true
	var view := _view_size()
	layout = layout_mode_for(view)
	_built_size = view

	# The map and the four panels outlive the composition: they are pulled out of
	# the frames being thrown away so the view the player had (the zoom, the pan,
	# the picked spot, the words in the panels) survives the rebuild. They are
	# parked on this screen between builds, which is also why the sweep below has
	# to leave them where they are: freeing one of them here would leave the mode
	# chooser pointing at a dead control.
	_ensure_body_parts()
	var keep: Array = _mode_panels()
	keep.append(map)
	for child in get_children():
		if child in keep:
			continue
		remove_child(child)
		child.queue_free()
	_detach(map)
	for panel in _mode_panels():
		_detach(panel)

	_backdrop = MenuBackdrop.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)

	_root = MarginContainer.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := 14 if layout == Kit.LayoutMode.DESKTOP else (10 if not _uses_sheet() else 6)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_root.add_theme_constant_override(side, pad)
	add_child(_root)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8 if layout == Kit.LayoutMode.DESKTOP else 6)
	_root.add_child(column)
	column.add_child(_build_header())
	column.add_child(_build_body())
	if layout == Kit.LayoutMode.PHONE_LANDSCAPE:
		_root.add_child(_build_sheet_layer())
	elif layout == Kit.LayoutMode.PHONE_PORTRAIT:
		# Portrait has the height to spare, so the sheet is a row of the
		# composition rather than a thing floating over the map: the strip
		# under the map stays visible while the panel is folded away.
		column.add_child(_build_sheet())

	map.set_compact_texture(_map_is_small())
	_refresh_zoom_label()
	_layout_sheet()
	_building = false

## The four mode panels, in tab order. Built once with the screen, parked on it
## when they are not the current mode's, and never rebuilt: a resize re-arranges
## the frames around them, it does not throw them away.
func _mode_panels() -> Array:
	return [_land_panel, _routing_panel, _aura_panel, _staff_panel]

## The map and the panels the composition is built around. A panel that has gone
## missing is built again rather than left dangling - the mode chooser and the
## strip both point at them by name.
func _ensure_body_parts() -> void:
	if map == null or not is_instance_valid(map):
		_build_map()
	for panel in _mode_panels():
		if panel != null and is_instance_valid(panel):
			continue
		_build_panels()
		return

func _detach(control: Node) -> void:
	if control != null and control.get_parent() != null:
		control.get_parent().remove_child(control)

func _build_header() -> Control:
	var group := HBoxContainer.new()
	group.name = "HeaderActions"
	group.add_theme_constant_override("separation", 8 if not _uses_sheet() else 5)
	group.size_flags_horizontal = Control.SIZE_SHRINK_END
	if not _uses_rail():
		_tab_row = _build_tabs()
		group.add_child(_tab_row)

	if layout == Kit.LayoutMode.DESKTOP:
		group.add_child(_build_money_block())

	if layout == Kit.LayoutMode.PHONE_LANDSCAPE:
		var details := CourseMapStyle.icon_button("Details", CourseMapStyle.MINT, 11)
		details.name = "DetailsButton"
		details.custom_minimum_size = Vector2(64, 34)
		details.tooltip_text = "Show or hide the mode's panel"
		details.pressed.connect(_toggle_sheet)
		group.add_child(details)

	var header := Kit.make_screen_header(layout, "Course map", "Course planner",
		_subtitle_text(), func(): back_requested.emit(), group)
	_title_label = header.find_child("Title", true, false) as Label
	_title_label.name = "TitleLabel"
	_subtitle_label = header.find_child("Subtitle", true, false) as Label
	return header

func _build_money_block() -> Control:
	var money_box := VBoxContainer.new()
	money_box.name = "Money"
	money_box.add_theme_constant_override("separation", 0)
	money_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var caption := CourseMapStyle.kicker("Company cash", 9)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_box.add_child(caption)
	_money_label = CourseMapStyle.title("", 15, CourseMapStyle.GOLD)
	_money_label.name = "MoneyLabel"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_box.add_child(_money_label)
	return money_box

func _build_tabs() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ModeTabs"
	row.add_theme_constant_override("separation", 5)
	_tab_buttons.clear()
	for entry in MODES:
		var control := CourseMapStyle.choice(str(entry["name"]), 12 if not _uses_sheet() else 11)
		control.name = "Mode_%s" % str(entry["name"])
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.custom_minimum_size.y = 38.0 if not _uses_sheet() else 34.0
		if not _uses_sheet():
			control.custom_minimum_size.x = 104.0
		control.tooltip_text = str(entry["blurb"])
		var target := int(entry["mode"])
		control.pressed.connect(func(): set_mode(target))
		row.add_child(control)
		_tab_buttons.append(control)
	return row

func _build_body() -> Control:
	var landscape := layout != Kit.LayoutMode.TABLET_PORTRAIT and layout != Kit.LayoutMode.PHONE_PORTRAIT
	var body: BoxContainer
	if landscape:
		body = HBoxContainer.new()
	else:
		body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 8 if layout == Kit.LayoutMode.DESKTOP else 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if _uses_rail():
		body.add_child(_build_rail())

	_map_column = VBoxContainer.new()
	_map_column.name = "MapColumn"
	_map_column.add_theme_constant_override("separation", 5)
	_map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_map_column)

	_map_stack = Control.new()
	_map_stack.name = "MapStack"
	_map_stack.clip_contents = true
	_map_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_stack.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_stack.add_child(_build_zoom_cluster())
	_map_column.add_child(_map_stack)
	_map_column.add_child(_build_strip())

	if not _uses_sheet():
		_panel_column = _build_panel_column()
		body.add_child(_panel_column)
	return body

## The mode rail: the same four choices as the tabs, stacked down the side for
## the shapes that are short of height.
func _build_rail() -> Control:
	var frame := PanelContainer.new()
	frame.name = "ModeRail"
	frame.add_theme_stylebox_override("panel",
		CourseMapStyle.panel(CourseMapStyle.SURFACE_RAISED, CourseMapStyle.MINT, 6, 6))
	frame.custom_minimum_size.x = RAIL_WIDTH if layout == Kit.LayoutMode.TABLET_LANDSCAPE else RAIL_WIDTH_PHONE
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_rail_stack = VBoxContainer.new()
	_rail_stack.name = "RailButtons"
	_rail_stack.add_theme_constant_override("separation", 5)
	frame.add_child(_rail_stack)
	_tab_buttons.clear()
	for entry in MODES:
		var control := CourseMapStyle.choice(str(entry["name"]), 12 if layout == Kit.LayoutMode.TABLET_LANDSCAPE else 11)
		control.name = "Mode_%s" % str(entry["name"])
		control.custom_minimum_size.y = 54.0 if layout == Kit.LayoutMode.TABLET_LANDSCAPE else 46.0
		control.tooltip_text = str(entry["blurb"])
		var target := int(entry["mode"])
		control.pressed.connect(func(): set_mode(target))
		_rail_stack.add_child(control)
		_tab_buttons.append(control)
	return frame

## The dossier column, for the shapes that keep the panel on screen beside the
## map (desktop, tablet). The tablet landscape composition folds it away.
func _build_panel_column() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "PanelColumn"
	frame.add_theme_stylebox_override("panel",
		CourseMapStyle.panel(CourseMapStyle.SURFACE, CourseMapStyle.BORDER, 8, 8))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if layout == Kit.LayoutMode.TABLET_PORTRAIT:
		frame.custom_minimum_size.y = TABLET_SHEET_HEIGHT
		frame.size_flags_vertical = Control.SIZE_SHRINK_END
	else:
		frame.custom_minimum_size.x = PANEL_WIDTH_DESKTOP if layout == Kit.LayoutMode.DESKTOP \
			else PANEL_WIDTH_TABLET

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	frame.add_child(stack)
	if layout == Kit.LayoutMode.TABLET_LANDSCAPE:
		stack.add_child(_build_panel_bar())
	stack.add_child(_build_panel_scroll())
	return frame

## The bar above the tablet landscape's panel: what it is, and the fold-away
## toggle that hands the map the whole width.
func _build_panel_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "PanelBar"
	bar.add_theme_constant_override("separation", 6)
	var caption := CourseMapStyle.kicker("Dossier", 10)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(caption)
	_panel_toggle = CourseMapStyle.icon_button("Hide", CourseMapStyle.MINT, 10)
	_panel_toggle.name = "PanelToggle"
	_panel_toggle.custom_minimum_size = Vector2(50, 26)
	_panel_toggle.tooltip_text = "Hide the panel and give the map the whole width"
	_panel_toggle.pressed.connect(_toggle_fold)
	bar.add_child(_panel_toggle)
	return bar

func _build_panel_scroll() -> ScrollContainer:
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.name = "PanelScroll"
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_scroll.follow_focus = true
	return _panel_scroll

## The zoom cluster in the map's top corner, with the gesture hint along the
## bottom edge on the touch shapes.
func _build_zoom_cluster() -> Control:
	var host := Control.new()
	host.name = "Overlay"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cluster := PanelContainer.new()
	cluster.name = "ZoomCluster"
	cluster.add_theme_stylebox_override("panel",
		CourseMapStyle.panel(Color(0.03, 0.07, 0.06, 0.72), CourseMapStyle.BORDER, 5, 4))
	cluster.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	cluster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cluster.grow_vertical = Control.GROW_DIRECTION_END
	cluster.offset_left = -6.0
	cluster.offset_right = -6.0
	cluster.offset_top = 6.0
	cluster.offset_bottom = 6.0
	cluster.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	cluster.add_child(row)

	var zoom_out := CourseMapStyle.icon_button("-", CourseMapStyle.MINT, 12)
	zoom_out.name = "ZoomOut"
	zoom_out.custom_minimum_size = Vector2(30, 28)
	zoom_out.tooltip_text = "Zoom out"
	zoom_out.pressed.connect(func(): map.zoom_by(1.0 / CourseMapView.ZOOM_STEP))
	row.add_child(zoom_out)

	_zoom_label = CourseMapStyle.label("1.0x", 11, CourseMapStyle.TEXT_SECONDARY)
	_zoom_label.name = "ZoomLabel"
	_zoom_label.custom_minimum_size.x = 38.0
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_zoom_label)

	var zoom_in := CourseMapStyle.icon_button("+", CourseMapStyle.MINT, 12)
	zoom_in.name = "ZoomIn"
	zoom_in.custom_minimum_size = Vector2(30, 28)
	zoom_in.tooltip_text = "Zoom in"
	zoom_in.pressed.connect(func(): map.zoom_by(CourseMapView.ZOOM_STEP))
	row.add_child(zoom_in)

	var fit := CourseMapStyle.icon_button("Fit", CourseMapStyle.UTILITY, 10)
	fit.name = "ZoomFit"
	fit.custom_minimum_size = Vector2(36, 28)
	fit.tooltip_text = "Frame the whole course again (F)"
	fit.pressed.connect(func(): map.fit())
	row.add_child(fit)
	host.add_child(cluster)

	if Screen.uses_touch_layout():
		var hint := CourseMapStyle.label("Drag to pan   ·   pinch to zoom   ·   tap to pick", 10,
			CourseMapStyle.TEXT_QUIET)
		hint.name = "GestureHint"
		hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		hint.offset_left = 10.0
		hint.offset_right = 10.0
		hint.offset_top = -24.0
		hint.offset_bottom = -8.0
		host.add_child(hint)
	return host

## The strip under the map: what the pointer is over, what is picked, and the
## buttons whatever is pending asks for. Every shape puts it in the same place
## relative to the map, so the map's instructions never move.
func _build_strip() -> Control:
	_strip = PanelContainer.new()
	_strip.name = "Strip"
	_strip.add_theme_stylebox_override("panel",
		CourseMapStyle.panel(Color(0.02, 0.05, 0.04, 0.84), CourseMapStyle.BORDER, 9, 5))
	_strip.custom_minimum_size.y = STRIP_HEIGHT_DESKTOP if not _uses_sheet() else STRIP_HEIGHT_TOUCH
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_strip.add_child(row)

	_strip_label = CourseMapStyle.label("", 11 if not _uses_sheet() else 12, CourseMapStyle.TEXT_SECONDARY)
	_strip_label.name = "StripText"
	_strip_label.clip_text = true
	_strip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_strip_label)

	_strip_actions = HBoxContainer.new()
	_strip_actions.name = "StripActions"
	_strip_actions.add_theme_constant_override("separation", 5)
	_strip_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_strip_actions)
	return _strip

## The landscape phone's sheet: a layer over the body carrying the panel and a
## scrim, so the panel slides in over the map instead of shrinking it. Tapping
## the scrim puts it away again.
func _build_sheet_layer() -> Control:
	_sheet_layer = Control.new()
	_sheet_layer.name = "SheetLayer"
	_sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_sheet_scrim = ColorRect.new()
	_sheet_scrim.name = "SheetScrim"
	_sheet_scrim.color = Color(0, 0, 0, 0.5)
	_sheet_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_scrim.visible = false
	_sheet_scrim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_set_sheet_open(false))
	_sheet_layer.add_child(_sheet_scrim)
	_sheet_layer.add_child(_build_sheet())
	return _sheet_layer

## The panel itself: a title bar with the mode's summary, and the mode's panel
## underneath it. The same sheet serves both phone shapes - it is the frame
## around it that changes (see _layout_sheet).
func _build_sheet() -> PanelContainer:
	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	_sheet.add_theme_stylebox_override("panel",
		CourseMapStyle.panel(Color(0.02, 0.05, 0.04, 0.95), CourseMapStyle.BORDER, 8, 6))
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	_sheet.add_child(stack)

	var handle := HBoxContainer.new()
	handle.name = "SheetHandle"
	handle.add_theme_constant_override("separation", 8)
	handle.mouse_filter = Control.MOUSE_FILTER_PASS
	_sheet_title = CourseMapStyle.title("", 14)
	_sheet_title.name = "SheetTitle"
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_title.clip_text = true
	handle.add_child(_sheet_title)
	_sheet_chevron = CourseMapStyle.label("^", 15, CourseMapStyle.GOLD, CourseMapStyle.SUBTITLE_FONT)
	_sheet_chevron.custom_minimum_size.x = 22.0
	_sheet_chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	handle.add_child(_sheet_chevron)
	stack.add_child(handle)

	stack.add_child(_build_panel_scroll())

	var grab := Button.new()
	grab.name = "SheetGrab"
	grab.flat = true
	grab.text = ""
	grab.tooltip_text = "Show or hide the panel"
	grab.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	grab.offset_bottom = 34.0
	grab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	grab.pressed.connect(_toggle_sheet)
	handle.add_child(grab)
	return _sheet

## Put the sheet where this shape wants it. On a landscape phone it is a column
## pinned to the right edge of the layer, out or full height. On a portrait one
## the VBox above places it, so all that changes is how much of the screen it
## asks for: the peeking handle, or SHEET_LIFT_RATIO of the height lifted.
func _layout_sheet() -> void:
	if _sheet == null:
		return
	var view := _view_size()
	if layout == Kit.LayoutMode.PHONE_LANDSCAPE:
		var width := clampf(view.x * SHEET_WIDTH_RATIO, 250.0, 430.0)
		_sheet.anchor_left = 1.0
		_sheet.anchor_right = 1.0
		_sheet.anchor_top = 0.0
		_sheet.anchor_bottom = 1.0
		_sheet.offset_left = -width - 6.0
		_sheet.offset_right = -6.0
		_sheet.offset_top = 6.0
		_sheet.offset_bottom = -6.0
		_sheet.visible = _sheet_open()
		if _sheet_scrim:
			_sheet_scrim.visible = _sheet_open()
	else:
		_sheet.custom_minimum_size.y = view.y * SHEET_LIFT_RATIO if _sheet_open() \
			else SHEET_PEEK_HEIGHT
		_sheet.visible = true
		if _sheet_scrim:
			_sheet_scrim.visible = false
	_sheet_chevron.text = "v" if _sheet_open() else "^"
	_sheet.tooltip_text = "Tap to fold the panel away" if _sheet_open() \
		else "Tap to open the %s panel" % _mode_name()

func _toggle_fold() -> void:
	panel_hidden = not panel_hidden
	if _panel_column:
		_panel_column.visible = not panel_hidden
	if _panel_toggle:
		_panel_toggle.text = "Show" if panel_hidden else "Hide"

func _toggle_sheet() -> void:
	_set_sheet_open(not _sheet_open())

func _set_sheet_open(open: bool) -> void:
	sheet_open = open
	_layout_sheet()

func _sheet_open() -> bool:
	return sheet_open

func _mode_entry() -> Dictionary:
	for entry in MODES:
		if int(entry["mode"]) == mode:
			return entry
	return {}

func _mode_name() -> String:
	return str(_mode_entry().get("name", "Land"))

# =============================================================================
# PANELS
# =============================================================================

## Show the mode's panel inside whichever frame this shape gave the panel, and
## rebuild it: every panel reads the live game as it refreshes.
func _refresh_panel() -> void:
	if _panel_scroll == null:
		return
	var active := _panel_for_mode()
	for panel in _mode_panels():
		panel.visible = false
		if panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		# A panel that is out of the frame rides along with the screen rather
		# than sitting parentless: only the mode's own panel is in the frame, and
		# the screen owns the other three.
		if panel != active:
			add_child(panel)
	active.visible = true
	active.set_compact(_map_is_small())
	_sync_panel_selection()
	_panel_scroll.add_child(active)
	active.refresh()
	_refresh_sheet_title()

func _panel_for_mode() -> VBoxContainer:
	match mode:
		CourseMapView.Mode.LAND:
			return _land_panel
		CourseMapView.Mode.ROUTING:
			return _routing_panel
		CourseMapView.Mode.AURA:
			return _aura_panel
		_:
			return _staff_panel

func _refresh_sheet_title() -> void:
	if _sheet_title == null:
		return
	_sheet_title.text = "%s — %s" % [_mode_name(), _panel_summary()]

## One line for the sheet's handle: what the panel is about to say.
func _panel_summary() -> String:
	match mode:
		CourseMapView.Mode.LAND:
			var land: LandManager = GameManager.land_manager
			if land == null:
				return "no land"
			return "%d parcels, %d for sale" % [land.owned_parcels.size(),
				land.get_purchasable_parcels().size()]
		CourseMapView.Mode.ROUTING:
			var course = GameManager.current_course
			var holes: int = 0 if course == null else course.holes.size()
			return "%d holes" % holes if holes > 0 else "no holes yet"
		CourseMapView.Mode.AURA:
			var aura: CourseAura = GameManager.course_aura
			if aura == null:
				return "no comments yet"
			var totals := aura.totals()
			var speakers: int = int(totals["positive"]) + int(totals["negative"])
			if speakers == 0:
				return "%d comments kept" % int(totals["total"])
			return "%d comments, %s happy" % [int(totals["total"]),
				CourseMapStyle.percent(float(totals["positive"]) / float(speakers))]
		_:
			var manager: StaffManager = GameManager.staff_manager
			if manager == null:
				return "no staff"
			return "%d on the crew, %s/day" % [manager.hired_staff.size(),
				CourseMapStyle.short_money(manager.get_daily_payroll())]

## A panel that lists things keeps its own picked row; hand the screen's
## selection down so the row and the map never disagree.
func _sync_panel_selection() -> void:
	var kind := str(selection.get("kind", ""))
	var value: Variant = selection.get("value", null)
	_land_panel.set_selected(value if kind == "parcel" and value is Vector2i else Vector2i(-1, -1))
	_routing_panel.set_selected(int(value) if kind == "hole" and value != null else -1)
	_aura_panel.set_selected(value if kind == "aura" and value is Vector2i else Vector2i(-2, -2))
	_staff_panel.set_selected(int(value) if kind == "staff" and value != null else -1)

# =============================================================================
# SELECTION AND THE STRIP
# =============================================================================

## Pick something and bring it into view: a parcel, a hole, a hotspot or a
## member of staff. Everything picked runs through here, whether it came from the
## map or from a row in the panel, so the two always agree.
func _select(kind: String, value: Variant) -> void:
	selection = {"kind": kind, "value": value}
	offer = {}
	if map:
		map.set_selection(kind, value)
	_focus_on(kind, value)
	_sync_panel_selection()
	_refresh_sheet_title()
	_refresh_strip()

func _focus_on(kind: String, value: Variant) -> void:
	if map == null:
		return
	match kind:
		"parcel":
			var land: LandManager = GameManager.land_manager
			if land == null or not (value is Vector2i):
				return
			var rect: Rect2i = land.parcel_to_tile_rect(value)
			map.focus_on_grid_point(Vector2(rect.position) + Vector2(rect.size) * 0.5, 1.7)
		"hole":
			var course = GameManager.current_course
			if course == null:
				return
			for hole in course.holes:
				if int(hole.hole_number) == int(value):
					var middle := (Vector2(hole.tee_position) + Vector2(hole.green_position)) * 0.5
					map.focus_on_grid_point(middle + Vector2(0.5, 0.5), 1.7)
					return
		"aura":
			if not (value is Vector2i):
				return
			map.focus_on_grid_point(Vector2(CourseAura.cell_center(value)) + Vector2(0.5, 0.5), 1.9)
		"staff":
			if GameManager.staff_manager == null or int(value) < 0 \
					or int(value) >= GameManager.staff_manager.hired_staff.size():
				return
			var record: Dictionary = GameManager.staff_manager.hired_staff[int(value)]
			var centre: Vector2i = record.get("area_center", Vector2i.ZERO)
			var radius := maxf(float(record.get("area_radius", 6.0)), 4.0)
			map.focus_on_grid_point(Vector2(centre) + Vector2(0.5, 0.5), clampf(300.0 / (radius * 6.0), 1.0, 2.4))

## The words under the map, with the buttons whatever is pending or picked asks
## for.
func _refresh_strip() -> void:
	if _strip_label == null:
		return
	for child in _strip_actions.get_children():
		_strip_actions.remove_child(child)
		child.queue_free()
	_strip_label.text = _strip_text()
	_strip_label.add_theme_color_override("font_color", _strip_color())
	_build_strip_actions()

func _strip_text() -> String:
	if not pending.is_empty():
		if str(pending.get("kind", "")) == "hire_staff":
			var data: Dictionary = GameManager.staff_manager.get_staff_data(int(pending["value"])) \
				if GameManager.staff_manager else {}
			return "Tap the map where the new %s should work." % str(data.get("name", "hire")).to_lower()
		return "Tap the map where this employee's area should go."
	if str(offer.get("kind", "")) == "buy":
		var parcel: Vector2i = offer["value"]
		var cost: int = GameManager.land_manager.get_parcel_cost(parcel) if GameManager.land_manager else 0
		return "Parcel %d, %d — buy it for %s?" % [parcel.x, parcel.y, CourseMapStyle.money(cost)]
	if not selection.is_empty():
		return _selection_text()
	return str(_mode_entry().get("blurb", "")) + _strip_tail()

func _strip_tail() -> String:
	if _uses_sheet():
		return "   ·   drag to pan, pinch to zoom"
	return "   ·   tap the map to pick things up"

## The chosen thing said in one line, in the map's own words.
func _selection_text() -> String:
	var value: Variant = selection.get("value", null)
	match str(selection.get("kind", "")):
		"parcel":
			var land: LandManager = GameManager.land_manager
			if land == null or not (value is Vector2i):
				return ""
			var tier := LandManager.get_tier_name(land.get_parcel_tier(value))
			if land.owned_parcels.has(value):
				return "Parcel %d, %d — %s land you own" % [value.x, value.y, tier]
			return "Parcel %d, %d — %s land for sale at %s" % [value.x, value.y, tier,
				CourseMapStyle.money(land.get_parcel_cost(value))]
		"hole":
			var course = GameManager.current_course
			if course == null:
				return ""
			for i in course.holes.size():
				var hole = course.holes[i]
				if int(hole.hole_number) != int(value):
					continue
				var leg := ""
				if i + 1 < course.holes.size():
					var grade := HoleRouting.grade_for(HoleRouting.leg_tiles(course.holes, i))
					leg = "   ·   %s walk to hole %d" % [HoleRouting.grade_name(grade).to_lower(), i + 2]
				return "Hole %d, played %d of %d — par %d, %d yds, %s%s" % [int(hole.hole_number), i + 1,
					course.holes.size(), hole.par, hole.distance_yards,
					"open" if hole.is_open else "closed", leg]
			return ""
		"aura":
			var aura: CourseAura = GameManager.course_aura
			if aura == null or not (value is Vector2i):
				return ""
			var counts: Dictionary = aura.cell_counts().get(value, {})
			if counts.is_empty():
				return ""
			var triggers := aura.top_triggers(value, "", 1)
			var note := "" if triggers.is_empty() \
				else "   ·   mostly %s" % str(triggers[0]["label"]).to_lower()
			return "%s — %d happy, %d unhappy%s" % [aura.describe(value), int(counts["positive"]),
				int(counts["negative"]), note]
		"staff":
			var manager: StaffManager = GameManager.staff_manager
			if manager == null or int(value) < 0 or int(value) >= manager.hired_staff.size():
				return ""
			var record: Dictionary = manager.hired_staff[int(value)]
			var data: Dictionary = manager.get_staff_data(int(record.type))
			var centre: Vector2i = record.get("area_center", Vector2i.ZERO)
			return "%s (%s) — $%d/day, based at tile %d, %d, covering %.0f tiles" % [
				str(record.get("name", "Staff")), str(data.get("name", "Staff")),
				int(record.get("salary", 0)), centre.x, centre.y, float(record.get("area_radius", 6.0))]
	return ""

func _strip_color() -> Color:
	if not pending.is_empty() or not offer.is_empty():
		return CourseMapStyle.GOLD
	if not selection.is_empty():
		return CourseMapStyle.TEXT_BRIGHT
	return CourseMapStyle.TEXT_SECONDARY

## The buttons the strip carries: Cancel while something is waiting for a tap,
## Buy and Not now for a parcel that is for sale, and Clear for a plain pick.
func _build_strip_actions() -> void:
	if not pending.is_empty():
		var cancel := CourseMapStyle.icon_button("Cancel", CourseMapStyle.QUIT, 11)
		cancel.name = "StripCancel"
		cancel.custom_minimum_size.y = 34.0
		cancel.tooltip_text = "Put this action away (Esc)"
		cancel.pressed.connect(func(): _cancel_pending())
		_strip_actions.add_child(cancel)
		return
	if str(offer.get("kind", "")) == "buy":
		var parcel: Vector2i = offer["value"]
		var cost: int = GameManager.land_manager.get_parcel_cost(parcel) if GameManager.land_manager else 0
		var buy := CourseMapStyle.button("Buy for %s" % CourseMapStyle.short_money(cost), true, 11)
		buy.name = "StripBuy"
		buy.custom_minimum_size.y = 34.0
		buy.tooltip_text = "Buy parcel %d, %d" % [parcel.x, parcel.y]
		buy.pressed.connect(func(): _on_buy_requested(parcel))
		_strip_actions.add_child(buy)
		var later := CourseMapStyle.icon_button("Not now", CourseMapStyle.UTILITY, 11)
		later.name = "StripLater"
		later.custom_minimum_size.y = 34.0
		later.pressed.connect(func():
			offer = {}
			_refresh_strip())
		_strip_actions.add_child(later)
		return
	if not selection.is_empty():
		var clear := CourseMapStyle.icon_button("Clear", CourseMapStyle.UTILITY, 11)
		clear.name = "StripClear"
		clear.custom_minimum_size.y = 34.0
		clear.tooltip_text = "Put what is picked away"
		clear.pressed.connect(_clear_selection)
		_strip_actions.add_child(clear)

func _clear_selection() -> void:
	selection = {}
	offer = {}
	if map:
		map.clear_selection()
	_sync_panel_selection()
	_refresh_strip()

func _refresh_tabs() -> void:
	for i in _tab_buttons.size():
		var control: Button = _tab_buttons[i]
		control.set_pressed_no_signal(int(MODES[i]["mode"]) == mode)

func _refresh_title() -> void:
	if _title_label == null:
		return
	_title_label.text = "Course map" if layout == Kit.LayoutMode.DESKTOP \
		else "Course map — %s" % _mode_name()
	if _subtitle_label:
		_subtitle_label.text = _subtitle_text()
	if _money_label:
		_money_label.text = CourseMapStyle.money(GameManager.money)

func _subtitle_text() -> String:
	var course = GameManager.current_course
	var name_text: String = GameManager.course_name if GameManager.course_name != "" else "This course"
	if course == null or course.holes.is_empty():
		return "%s — no holes laid out yet" % name_text
	return "%s — %d holes, par %d" % [name_text, course.holes.size(), int(course.total_par)]

func _refresh_zoom_label() -> void:
	if _zoom_label == null or map == null:
		return
	_zoom_label.text = "%.1fx" % map.get_zoom()

# =============================================================================
# THE MAP
# =============================================================================

func _on_map_pressed(tile: Vector2i, hit: Dictionary) -> void:
	if not pending.is_empty():
		_apply_pending(tile)
		return
	if tile.x < 0:
		return
	match str(hit.get("kind", "")):
		"parcel":
			var parcel: Vector2i = hit["value"]
			_select("parcel", parcel)
			# A parcel that is for sale offers itself in the strip: a tap never
			# spends money without the player seeing what it costs.
			if GameManager.land_manager and GameManager.land_manager.is_parcel_purchasable(parcel):
				offer = {"kind": "buy", "value": parcel}
			_refresh_strip()
		"hole":
			_select("hole", int(hit["value"]))
		"aura":
			_select("aura", hit["value"])
		"staff":
			_select("staff", int(hit["value"]))
		_:
			_clear_selection()

func _on_hover_changed(text: String) -> void:
	if _strip_label == null or not pending.is_empty() or not offer.is_empty():
		return
	if text.is_empty():
		return
	_strip_label.text = text
	_strip_label.add_theme_color_override("font_color", CourseMapStyle.MINT)

func _on_hover_cleared() -> void:
	_refresh_strip()

# =============================================================================
# LAND
# =============================================================================

## Buy a parcel. LandManager owns the rules and the money; main.gd answers its
## land_purchased signal by generating the parcel's terrain, and the map simply
## re-reads the course.
func _on_buy_requested(parcel: Vector2i) -> void:
	var land: LandManager = GameManager.land_manager
	if land == null:
		return
	offer = {}
	if land.purchase_parcel(parcel):
		selection = {"kind": "parcel", "value": parcel}
		if map:
			map.set_selection("parcel", parcel)
	_refresh_after_course()

# =============================================================================
# ROUTING
# =============================================================================

func _on_hole_move(from_index: int, to_index: int) -> void:
	if GameManager.hole_manager == null:
		return
	if GameManager.hole_manager.move_hole(from_index, to_index):
		_refresh_after_course()

func _on_hole_flip(hole_number: int) -> void:
	if GameManager.hole_manager == null:
		return
	if GameManager.hole_manager.flip_hole(hole_number):
		_refresh_after_course()

func _on_hole_par(hole_number: int, new_par: int) -> void:
	if GameManager.hole_manager == null:
		return
	if GameManager.hole_manager.set_hole_par(hole_number, new_par):
		_refresh_after_course()

func _on_hole_toggle(hole_number: int) -> void:
	var course = GameManager.current_course
	if course == null:
		return
	course.toggle_hole_open(hole_number)
	_refresh_after_course()

func _on_holes_reverse() -> void:
	if GameManager.hole_manager == null:
		return
	if GameManager.hole_manager.reverse_hole_order():
		_refresh_after_course()

## The aura panel's hole rows jump to the hole they are about.
func _on_aura_hole_selected(hole_number: int) -> void:
	set_mode(CourseMapView.Mode.ROUTING)
	_select("hole", hole_number)

## Advice from the unified review/aura panel. Locate actions stay on the map,
## other actions are forwarded to main.gd (which closes the map and opens finance etc).
func _on_aura_advice_selected(advice: Dictionary) -> void:
	if advice.has("position"):
		var pos: Vector2i = advice["position"]
		# Focus the map on the problematic ground
		if map:
			map.focus_on_grid_point(Vector2(pos) + Vector2(0.5, 0.5), 1.9)
		# Also select the aura cell containing it if we are in aura mode
		if mode == CourseMapView.Mode.AURA:
			_select("aura", CourseAura.cell_of(pos))
		EventBus.notify(str(advice.get("title", "Advice")), "info")
		return
	# For non-locate advice, let main.gd handle (close map + open panel)
	advice_action_requested.emit(advice)

# =============================================================================
# STAFF
# =============================================================================

func _on_staff_move_requested(index: int) -> void:
	var manager: StaffManager = GameManager.staff_manager
	if manager == null or index < 0 or index >= manager.hired_staff.size():
		return
	pending = {"kind": "move_staff", "value": index}
	offer = {}
	selection = {"kind": "staff", "value": index}
	if map:
		map.set_selection("staff", index)
		map.set_pending(pending)
	_staff_panel.set_armed(-1)
	_refresh_strip()

## A hire button was tapped: arm the map. Tapping the same job again puts it away.
func _on_staff_hire_armed(staff_type: int) -> void:
	var manager: StaffManager = GameManager.staff_manager
	if manager == null:
		return
	if str(pending.get("kind", "")) == "hire_staff" and int(pending.get("value", -1)) == staff_type:
		_cancel_pending()
		return
	var data: Dictionary = manager.get_staff_data(staff_type)
	if data.is_empty():
		return
	if not GameManager.can_afford(int(data.get("base_salary", 0))):
		EventBus.notify("Not enough money for a %s" % str(data.get("name", "hire")).to_lower(), "error")
		return
	pending = {"kind": "hire_staff", "value": staff_type}
	offer = {}
	selection = {}
	if map:
		map.clear_selection()
		map.set_pending(pending)
	_staff_panel.set_armed(staff_type)
	_refresh_strip()

## A tap on the map while an action waits: this is where a hire and a move
## actually happen.
func _apply_pending(tile: Vector2i) -> void:
	var manager: StaffManager = GameManager.staff_manager
	var grid: TerrainGrid = GameManager.terrain_grid
	if manager == null or grid == null or tile.x < 0 or not grid.is_valid_position(tile):
		EventBus.notify("Pick a spot on the course itself", "error")
		return
	var kind := str(pending.get("kind", ""))
	if kind == "move_staff":
		var index := int(pending["value"])
		manager.move_staff_area(index, tile)
		if _ground_is_covered(manager, tile, index):
			EventBus.notify("That ground overlaps another employee's area", "warning")
		_cancel_pending(false)
		_select("staff", index)
		return
	if kind == "hire_staff":
		var staff_type := int(pending["value"])
		var data: Dictionary = manager.get_staff_data(staff_type)
		if not manager.hire_staff(staff_type):
			EventBus.notify("Could not hire a %s" % str(data.get("name", "hire")).to_lower(), "error")
			_cancel_pending()
			return
		var hired: int = manager.hired_staff.size() - 1
		manager.move_staff_area(hired, tile)
		EventBus.notify("%s hired and based at tile %d, %d" % [str(data.get("name", "Staff")),
			tile.x, tile.y], "success")
		_cancel_pending(false)
		_select("staff", hired)

## True when somebody else already covers this ground. Overlapping areas are
## allowed - the warning is the honest answer, and the player may want the cover.
func _ground_is_covered(manager: StaffManager, tile: Vector2i, except_index: int) -> bool:
	for index in manager.hired_staff.size():
		if index == except_index:
			continue
		var record: Dictionary = manager.hired_staff[index]
		var centre := Vector2(record.get("area_center", Vector2i.ZERO))
		if centre.distance_to(Vector2(tile)) <= float(record.get("area_radius", 6.0)):
			return true
	return false

## Put an armed action away. The pick goes with it unless the caller is about
## to make its own, which is what a hire and a move do the moment they land.
func _cancel_pending(clear_selection: bool = true) -> void:
	pending = {}
	offer = {}
	if map:
		map.clear_pending()
	_staff_panel.set_armed(-1)
	if clear_selection:
		_clear_selection()
	else:
		_refresh_strip()

func _on_staff_fire_requested(index: int) -> void:
	var manager: StaffManager = GameManager.staff_manager
	if manager == null or index < 0 or index >= manager.hired_staff.size():
		return
	var record: Dictionary = manager.hired_staff[index]
	var dialog := ConfirmDialog.new(
		"Let %s go? Their ground goes back to nobody, and the rest of the crew keeps their own." \
			% str(record.get("name", "this employee")),
		"Fire", "Keep", UIConstants.COLOR_DANGER)
	dialog.confirmed.connect(func():
		var current: StaffManager = GameManager.staff_manager
		current.fire_staff(index)
		if int(selection.get("value", -1)) == index:
			selection = {}
			if map:
				map.clear_selection()
		_refresh_after_course())
	add_child(dialog)

# =============================================================================
# LIVE COURSE
# =============================================================================

func _on_course_changed_rating(_rating: Dictionary) -> void:
	_refresh_after_course()

## Anything that changes the course's shape or its order - from the map, from
## the toolbar's own tools, or from a loaded save - re-reads the whole screen.
func _refresh_after_course() -> void:
	if not visible or not is_inside_tree():
		return
	if map:
		map.refresh()
	_refresh_panel()
	_refresh_tabs()
	_refresh_title()
	_refresh_strip()

func _on_course_changed(_order: Array) -> void:
	_refresh_after_course()

func _on_hole_changed(_hole_number: int) -> void:
	_refresh_after_course()

# =============================================================================
# INPUT
# =============================================================================

## The screen answers its own keys: gameplay hotkeys never reach the course while
## the map is up (see main.gd), so 1-4 pick a mode, F frames the course and
## Escape backs out one step at a time.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Controller B steps back exactly like Escape: armed action, then pick,
	# then the screen itself.
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		if not pending.is_empty():
			_cancel_pending(false)
		elif not selection.is_empty():
			_clear_selection()
		else:
			back_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			if not pending.is_empty():
				# One step at a time: the armed action now, the pick on the next tap.
				_cancel_pending(false)
			elif not selection.is_empty():
				_clear_selection()
			else:
				back_requested.emit()
		KEY_1, KEY_2, KEY_3, KEY_4:
			set_mode(int(MODES[(event as InputEventKey).keycode - KEY_1]["mode"]))
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			map.zoom_by(CourseMapView.ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			map.zoom_by(1.0 / CourseMapView.ZOOM_STEP)
		KEY_F, KEY_0:
			map.fit()
		_:
			return
	get_viewport().set_input_as_handled()
