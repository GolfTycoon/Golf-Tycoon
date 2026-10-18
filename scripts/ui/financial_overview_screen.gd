extends CenteredPanel
class_name FinancialOverviewScreen
## FinancialOverviewScreen - the full-screen company dashboard.
##
## The World Map's MenuBackdrop, pixel-framed cards and Pixelify Sans carry
## the game into the clubhouse ledger. Desktop shows the whole operation as a
## three-column board; tablets and phones use three thumb-friendly pages so
## every control and every report remains usable at narrow sizes.

signal close_requested

enum LayoutMode { DESKTOP, TABLET_LANDSCAPE, TABLET_PORTRAIT, PHONE_LANDSCAPE, PHONE_PORTRAIT }
enum Section { FINANCE, COURSE, MARKETING }

const DESKTOP_MIN_WIDTH := 1180.0
const DESKTOP_MIN_HEIGHT := 680.0
const TABLET_MIN_WIDTH := 680.0
const TABLET_MIN_HEIGHT := 620.0

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

const SURFACE := MenuStyle.SHEET_BG
const SURFACE_RAISED := MenuStyle.RAIL_BG
const INSET := MenuStyle.INSET_BG
const TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const TEXT_SECONDARY := UIConstants.COLOR_TEXT_DIM
const TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const GOLD := MenuStyle.ACCENT_PRIMARY
const MINT := MenuStyle.ACCENT_SECONDARY
const UTILITY := MenuStyle.ACCENT_UTILITY
const PROFIT_GREEN := UIConstants.COLOR_SUCCESS
const WARNING_AMBER := UIConstants.COLOR_WARNING
const LOSS_RED := UIConstants.COLOR_DANGER

const CHANNEL_ACCENTS: Array[Color] = [
	Color("82b77e"), Color("7fb8a8"), Color("e5c57c"), Color("8fb1df"), Color("e49a67"),
]

var active_section: int = Section.FINANCE

var _layout_mode: int = -1
var _built_size := Vector2.ZERO
var _screen_root: Control = null
var _page: VBoxContainer = null
var _scroll_nodes: Array[ScrollContainer] = []
var _scroll_positions: Dictionary = {}
var _refresh_pending := false

func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2.ZERO
	_connect_live_signals()

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)
	if has_node("/root/EventBus"):
		for signal_name in ["money_changed", "day_changed", "reputation_changed", "green_fee_changed", "course_rating_changed"]:
			if EventBus.is_connected(signal_name, _on_event_changed):
				EventBus.disconnect(signal_name, _on_event_changed)
	if GameManager.marketing_manager and GameManager.marketing_manager.campaigns_changed.is_connected(_on_campaigns_changed):
		GameManager.marketing_manager.campaigns_changed.disconnect(_on_campaigns_changed)

## Kept pure so the five responsive compositions can be tested without a
## window, matching the World Map and Course Map breakpoints.
static func layout_mode_for(view: Vector2) -> int:
	if view.x >= DESKTOP_MIN_WIDTH and view.y >= DESKTOP_MIN_HEIGHT and view.x > view.y:
		return LayoutMode.DESKTOP
	if view.x >= TABLET_MIN_WIDTH and view.y >= TABLET_MIN_HEIGHT:
		return LayoutMode.TABLET_LANDSCAPE if view.x >= view.y else LayoutMode.TABLET_PORTRAIT
	if view.x > view.y and view.y < TABLET_MIN_HEIGHT:
		return LayoutMode.PHONE_LANDSCAPE
	return LayoutMode.PHONE_PORTRAIT

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

func _build_ui() -> void:
	# CenteredPanel's base is retained for compatibility with the other in-game
	# panels, but this screen deliberately ignores popup sizing and fills the
	# entire viewport, including the old HUD and bottom dock.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_mode = layout_mode_for(_window_size())
	_build_structure()

func _connect_live_signals() -> void:
	if has_node("/root/EventBus"):
		for signal_name in ["money_changed", "day_changed", "reputation_changed", "green_fee_changed", "course_rating_changed"]:
			if not EventBus.is_connected(signal_name, _on_event_changed):
				EventBus.connect(signal_name, _on_event_changed)
	if GameManager.marketing_manager and not GameManager.marketing_manager.campaigns_changed.is_connected(_on_campaigns_changed):
		GameManager.marketing_manager.campaigns_changed.connect(_on_campaigns_changed)

func _on_event_changed(_first: Variant = null, _second: Variant = null) -> void:
	_request_refresh()

func _on_campaigns_changed() -> void:
	_request_refresh()

func _request_refresh() -> void:
	if not visible or _refresh_pending or is_queued_for_deletion():
		return
	_refresh_pending = true
	call_deferred("_refresh_if_visible")

func _refresh_if_visible() -> void:
	_refresh_pending = false
	if visible and is_inside_tree():
		_build_structure()

func _on_screen_changed(window_size: Vector2, _world_scale: float) -> void:
	if not visible:
		return
	var next_mode := layout_mode_for(window_size)
	var width_delta := absf(window_size.x - _built_size.x)
	var height_delta := absf(window_size.y - _built_size.y)
	var needs_remeasure := width_delta > maxf(96.0, _built_size.x * 0.14) \
		or height_delta > maxf(72.0, _built_size.y * 0.14)
	if next_mode != _layout_mode or needs_remeasure:
		_build_structure()
	else:
		_layout_to_viewport()

func _save_scroll_positions() -> void:
	for scroll in _scroll_nodes:
		if is_instance_valid(scroll):
			_scroll_positions[scroll.name] = scroll.scroll_vertical
	_scroll_nodes.clear()

func _restore_scroll_positions() -> void:
	for scroll in _scroll_nodes:
		if is_instance_valid(scroll) and _scroll_positions.has(scroll.name):
			scroll.scroll_vertical = int(_scroll_positions[scroll.name])

func _build_structure() -> void:
	_save_scroll_positions()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_layout_mode = layout_mode_for(_window_size())
	_built_size = _window_size()
	_scroll_nodes.clear()

	_screen_root = Control.new()
	_screen_root.name = "FinancialOverviewRoot"
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen_root)

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.add_child(backdrop)

	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var outer_pad := _outer_padding(_layout_mode)
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_%s" % side, outer_pad)
	_screen_root.add_child(frame)

	_page = VBoxContainer.new()
	_page.name = "Page"
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", _page_separation())
	frame.add_child(_page)

	_page.add_child(_build_header())
	_page.add_child(_build_metric_strip())
	if _layout_mode != LayoutMode.DESKTOP:
		_page.add_child(_build_section_tabs())
	var content := _build_responsive_content()
	content.name = "DashboardContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(content)

	_layout_to_viewport()
	if visible:
		move_to_front()
	call_deferred("_restore_scroll_positions")

func _layout_to_viewport() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if is_instance_valid(_screen_root):
		_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Full-screen counterpart to CenteredPanel.show_centered().
func show_centered() -> void:
	_build_structure()
	_layout_to_viewport()
	show()
	move_to_front()

func toggle() -> void:
	if visible:
		hide()
	else:
		show_centered()

func refresh() -> void:
	_build_structure()

## Retained as a convenient adapter for older panel call sites.
func update_display() -> void:
	refresh()

func select_section(section: int) -> void:
	if section < Section.FINANCE or section > Section.MARKETING:
		return
	active_section = section
	if visible and _layout_mode != LayoutMode.DESKTOP:
		_build_structure()

func _close_pressed() -> void:
	close_requested.emit()
	hide()

func _outer_padding(mode: int) -> int:
	match mode:
		LayoutMode.DESKTOP:
			return int(clampf(minf(_built_size.x, _built_size.y) * 0.024, 20.0, 34.0))
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return int(clampf(minf(_built_size.x, _built_size.y) * 0.021, 14.0, 24.0))
		LayoutMode.PHONE_LANDSCAPE:
			return 8
		_:
			return int(clampf(_built_size.x * 0.028, 9.0, 14.0))

func _page_separation() -> int:
	match _layout_mode:
		LayoutMode.DESKTOP:
			return 12
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return 9
		LayoutMode.PHONE_LANDSCAPE:
			return 6
		_:
			return 8

func _is_phone() -> bool:
	return _layout_mode == LayoutMode.PHONE_LANDSCAPE or _layout_mode == LayoutMode.PHONE_PORTRAIT

func _is_touch_layout() -> bool:
	return _is_phone() or DisplayServer.is_touchscreen_available()

func _font_size(base: int) -> int:
	if _layout_mode == LayoutMode.PHONE_LANDSCAPE:
		return maxi(10, base - 2)
	if _layout_mode == LayoutMode.PHONE_PORTRAIT:
		return maxi(11, base - 1)
	if _layout_mode == LayoutMode.TABLET_PORTRAIT:
		return maxi(11, base - 1)
	return base

func _build_header() -> Control:
	var compact := _is_phone()
	var header := HBoxContainer.new()
	header.name = "OverviewHeader"
	header.add_theme_constant_override("separation", 8 if not compact else 5)
	header.custom_minimum_size.y = 60.0 if _layout_mode == LayoutMode.DESKTOP else (54.0 if not compact else 44.0)

	var back := CourseMapStyle.button("‹  Back", false, _font_size(12))
	back.name = "BackToCourse"
	back.tooltip_text = "Return to the course"
	back.accessibility_name = "Close financial overview and return to the course"
	back.custom_minimum_size = Vector2(88 if not compact else 42, 44 if _is_touch_layout() else 40)
	if compact:
		back.text = "‹"
	back.pressed.connect(_close_pressed)
	header.add_child(back)

	var title_block := HBoxContainer.new()
	title_block.name = "TitleBlock"
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_theme_constant_override("separation", 7 if compact else 10)
	var mark := MenuFlagMark.new()
	mark.name = "FlagMark"
	mark.mark_size = 20.0 if compact else (26.0 if _layout_mode == LayoutMode.DESKTOP else 24.0)
	title_block.add_child(mark)

	var title_stack := VBoxContainer.new()
	title_stack.add_theme_constant_override("separation", 0)
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := CourseMapStyle.title("Financial Overview", _font_size(25 if not compact else 20))
	title.name = "Title"
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_stack.add_child(title)
	if not compact:
		var subtitle := CourseMapStyle.label(
			"COMPANY LEDGER  /  %s" % GameCalendar.format_date(GameManager.current_day),
			_font_size(11), TEXT_QUIET, BODY_FONT)
		subtitle.name = "DateLine"
		title_stack.add_child(subtitle)
	title_block.add_child(title_stack)
	header.add_child(title_block)

	if not compact:
		var treasury := _make_treasury_chip()
		header.add_child(treasury)

	var close := CourseMapStyle.button("Close", false, _font_size(12))
	close.name = "CloseButton"
	close.tooltip_text = "Close the financial overview"
	close.accessibility_name = "Close financial overview"
	close.custom_minimum_size = Vector2(72 if not compact else 56, 44 if _is_touch_layout() else 40)
	if compact:
		close.text = "DONE"
	close.pressed.connect(_close_pressed)
	header.add_child(close)
	return header

func _make_treasury_chip() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "TreasuryChip"
	panel.custom_minimum_size = Vector2(154, 46)
	panel.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(GOLD, 0.74), SURFACE_RAISED, 10, 5))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	panel.add_child(stack)
	var caption := CourseMapStyle.kicker("Available funds", _font_size(9))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_theme_color_override("font_color", TEXT_QUIET)
	stack.add_child(caption)
	var amount := CourseMapStyle.title(CourseMapStyle.money(GameManager.money), _font_size(16), GOLD)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.clip_text = true
	stack.add_child(amount)
	return panel

func _build_metric_strip() -> Control:
	var stats := _period_stats()
	var grid := GridContainer.new()
	grid.name = "KeyFigures"
	grid.columns = 4 if _layout_mode == LayoutMode.DESKTOP or _layout_mode == LayoutMode.TABLET_LANDSCAPE or _layout_mode == LayoutMode.PHONE_LANDSCAPE else 2
	grid.add_theme_constant_override("h_separation", 8 if not _is_phone() else 5)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var expense_total := stats.operating_costs + stats.tournament_entry_fee
	var entries: Array[Dictionary] = [
		{"title": "CURRENT BALANCE", "value": CourseMapStyle.money(GameManager.money), "note": "Cash on hand", "color": GOLD},
		{"title": "REVENUE", "value": CourseMapStyle.money(stats.get_total_revenue()), "note": "Since Jan 1", "color": MINT},
		{"title": "COSTS", "value": CourseMapStyle.money(expense_total), "note": "Operating + events", "color": Color("df9b83")},
		{"title": "NET PROFIT", "value": _signed_money(stats.get_profit()), "note": "Year to date", "color": PROFIT_GREEN if stats.get_profit() >= 0 else LOSS_RED},
	]
	for entry in entries:
		grid.add_child(_build_metric_card(entry))
	return grid

func _build_metric_card(entry: Dictionary) -> PanelContainer:
	var accent: Color = entry["color"]
	var panel := PanelContainer.new()
	panel.name = "Metric%s" % str(entry["title"]).capitalize().replace(" ", "")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 56 if _is_phone() else 62
	panel.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(accent, 0.50), SURFACE, 10 if not _is_phone() else 7, 6))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	panel.add_child(stack)
	var title := CourseMapStyle.kicker(str(entry["title"]), _font_size(9))
	title.add_theme_color_override("font_color", TEXT_QUIET)
	stack.add_child(title)
	var value := CourseMapStyle.title(str(entry["value"]), _font_size(19 if not _is_phone() else 16), accent)
	value.name = "Value"
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(value)
	var note := CourseMapStyle.label(str(entry["note"]), _font_size(10), TEXT_SECONDARY, BODY_FONT)
	note.name = "Note"
	stack.add_child(note)
	return panel

func _build_section_tabs() -> Control:
	var tabs := HBoxContainer.new()
	tabs.name = "SectionTabs"
	tabs.add_theme_constant_override("separation", 6 if not _is_phone() else 4)
	var labels: Array[String] = ["FINANCES", "COURSE", "MARKETING"]
	var names: Array[String] = ["FinanceTab", "CourseTab", "MarketingTab"]
	for section in [Section.FINANCE, Section.COURSE, Section.MARKETING]:
		var index := int(section)
		var button := CourseMapStyle.choice(labels[index], _font_size(12))
		button.name = names[index]
		button.accessibility_name = labels[index].to_lower().capitalize() + " overview"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44 if _is_touch_layout() else 38
		button.set_pressed_no_signal(active_section == section)
		button.pressed.connect(_on_section_tab_pressed.bind(index))
		tabs.add_child(button)
	return tabs

func _on_section_tab_pressed(section: int) -> void:
	select_section(section)

func _build_responsive_content() -> Control:
	if _layout_mode == LayoutMode.DESKTOP:
		return _build_desktop_board()
	if _layout_mode == LayoutMode.TABLET_LANDSCAPE:
		return _build_landscape_section()
	return _build_vertical_section()

func _build_desktop_board() -> Control:
	var board := HBoxContainer.new()
	board.name = "DesktopFinancialBoard"
	board.add_theme_constant_override("separation", 12)
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stats := _period_stats()

	var finance := _make_scroll_column("FinanceColumn")
	finance.size_flags_stretch_ratio = 1.08
	var finance_stack := _scroll_content(finance)
	finance_stack.add_child(_build_statement_card(stats, true))
	board.add_child(finance)

	var course := _make_scroll_column("CourseColumn")
	course.size_flags_stretch_ratio = 1.00
	var course_stack := _scroll_content(course)
	course_stack.add_child(_build_pricing_card())
	course_stack.add_child(_build_course_status_card(stats))
	course_stack.add_child(_build_loan_card())
	course_stack.add_child(_build_seasonal_card())
	course_stack.add_child(_build_rating_card())
	board.add_child(course)

	var marketing := _make_scroll_column("MarketingColumn")
	marketing.size_flags_stretch_ratio = 1.16
	var marketing_stack := _scroll_content(marketing)
	marketing_stack.add_child(_build_marketing_performance_card())
	marketing_stack.add_child(_build_active_campaigns_card())
	marketing_stack.add_child(_build_channel_catalog_card())
	board.add_child(marketing)
	return board

func _build_landscape_section() -> Control:
	var board := HBoxContainer.new()
	board.name = "TabletLandscapeBoard"
	board.add_theme_constant_override("separation", 10)
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stats := _period_stats()
	var left := _make_scroll_column("TabletSectionLeft_%d" % active_section)
	var right := _make_scroll_column("TabletSectionRight_%d" % active_section)
	left.size_flags_stretch_ratio = 1.05
	right.size_flags_stretch_ratio = 0.95
	board.add_child(left)
	board.add_child(right)
	var left_stack := _scroll_content(left)
	var right_stack := _scroll_content(right)

	match active_section:
		Section.FINANCE:
			left_stack.add_child(_build_statement_card(stats, true))
			right_stack.add_child(_build_pricing_card())
			var note := CourseMapStyle.hint("Course health, debt and seasonal outlook are grouped on the Course page.", _font_size(11))
			right_stack.add_child(note)
		Section.COURSE:
			left_stack.add_child(_build_course_status_card(stats))
			left_stack.add_child(_build_loan_card())
			right_stack.add_child(_build_seasonal_card())
			right_stack.add_child(_build_rating_card())
		Section.MARKETING:
			left_stack.add_child(_build_marketing_performance_card())
			left_stack.add_child(_build_active_campaigns_card())
			right_stack.add_child(_build_channel_catalog_card())
	return board

func _build_vertical_section() -> Control:
	var scroll := _make_scroll_column("SectionScroll_%d" % active_section)
	scroll.name = "SectionScroll_%d" % active_section
	var stack := _scroll_content(scroll)
	stack.add_theme_constant_override("separation", 9 if not _is_phone() else 7)
	var stats := _period_stats()
	match active_section:
		Section.FINANCE:
			stack.add_child(_build_statement_card(stats, false))
			stack.add_child(_build_pricing_card())
		Section.COURSE:
			stack.add_child(_build_course_status_card(stats))
			stack.add_child(_build_loan_card())
			stack.add_child(_build_seasonal_card())
			stack.add_child(_build_rating_card())
		Section.MARKETING:
			stack.add_child(_build_marketing_performance_card())
			stack.add_child(_build_active_campaigns_card())
			stack.add_child(_build_channel_catalog_card())
	return scroll

func _make_scroll_column(scroll_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_nodes.append(scroll)
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 9 if not _is_phone() else 7)
	scroll.add_child(stack)
	return scroll

func _scroll_content(scroll: ScrollContainer) -> VBoxContainer:
	return scroll.get_node("Stack") as VBoxContainer

func _make_card(kicker_text: String, title_text: String, accent: Color = UTILITY) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(accent, 0.60), SURFACE, 13 if not _is_phone() else 9, 10 if not _is_phone() else 8))
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 7 if not _is_phone() else 5)
	panel.add_child(content)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 0)
	var kicker := CourseMapStyle.kicker(kicker_text, _font_size(9))
	kicker.add_theme_color_override("font_color", accent)
	heading.add_child(kicker)
	var title := CourseMapStyle.title(title_text, _font_size(16))
	title.add_theme_color_override("font_color", TEXT_BRIGHT)
	heading.add_child(title)
	content.add_child(heading)
	return panel

func _card_content(card: PanelContainer) -> VBoxContainer:
	return card.get_node("Content") as VBoxContainer

func _build_statement_card(stats: GameManager.DailyStatistics, split_ledgers: bool) -> PanelContainer:
	var card := _make_card("COMPANY LEDGER", "Revenue & costs", GOLD)
	var content := _card_content(card)
	var year_hint := CourseMapStyle.label("Year-to-date totals since Jan 1", _font_size(10), TEXT_QUIET, BODY_FONT)
	content.add_child(year_hint)

	var revenue_entries: Array[Dictionary] = [
		{"name": "Green fees", "amount": stats.revenue},
		{"name": "Amenities", "amount": stats.building_revenue},
	]
	if stats.tournament_revenue > 0:
		revenue_entries.append({"name": "Tournaments", "amount": stats.tournament_revenue})
	var cost_entries: Array[Dictionary] = []
	_add_positive_cost(cost_entries, "Terrain", stats.terrain_maintenance)
	_add_positive_cost(cost_entries, "Base operations", stats.base_operating_cost)
	_add_positive_cost(cost_entries, "Staff", stats.staff_wages)
	_add_positive_cost(cost_entries, "Hired staff payroll", stats.hired_staff_payroll)
	_add_positive_cost(cost_entries, "Buildings", stats.building_operating_costs)
	_add_positive_cost(cost_entries, "Decorations", stats.decoration_operating_costs)
	_add_positive_cost(cost_entries, "Marketing", stats.marketing_cost)
	_add_positive_cost(cost_entries, "Tournament entry", stats.tournament_entry_fee)
	var total_costs := stats.operating_costs + stats.tournament_entry_fee

	if split_ledgers:
		var ledger_row := HBoxContainer.new()
		ledger_row.add_theme_constant_override("separation", 12)
		var revenue_column := VBoxContainer.new()
		revenue_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		revenue_column.add_theme_constant_override("separation", 4)
		_add_ledger_heading(revenue_column, "INCOME", MINT)
		_add_ledger_rows(revenue_column, revenue_entries, MINT)
		_add_stat_row(revenue_column, "Total revenue", CourseMapStyle.money(stats.get_total_revenue()), PROFIT_GREEN, true)
		ledger_row.add_child(revenue_column)
		var costs_column := VBoxContainer.new()
		costs_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		costs_column.add_theme_constant_override("separation", 4)
		_add_ledger_heading(costs_column, "OUTGOINGS", Color("df9b83"))
		_add_ledger_rows(costs_column, cost_entries, TEXT_SECONDARY, true)
		_add_stat_row(costs_column, "Total costs", CourseMapStyle.money(-total_costs), LOSS_RED, true)
		ledger_row.add_child(costs_column)
		content.add_child(ledger_row)
	else:
		_add_ledger_heading(content, "INCOME", MINT)
		_add_ledger_rows(content, revenue_entries, MINT)
		_add_stat_row(content, "Total revenue", CourseMapStyle.money(stats.get_total_revenue()), PROFIT_GREEN, true)
		_add_rule(content)
		_add_ledger_heading(content, "COSTS SINCE JAN 1", Color("df9b83"))
		_add_ledger_rows(content, cost_entries, TEXT_SECONDARY, true)
		_add_stat_row(content, "Total costs", CourseMapStyle.money(-total_costs), LOSS_RED, true)

	_add_rule(content)
	var profit := stats.get_profit()
	var profit_panel := _highlight_row("Year-to-date profit", _signed_money(profit), PROFIT_GREEN if profit >= 0 else LOSS_RED)
	content.add_child(profit_panel)

	if GameManager.previous_year_stats != null:
		_add_rule(content)
		_add_ledger_heading(content, "LAST YEAR'S RESULTS", GOLD)
		var previous: GameManager.DailyStatistics = GameManager.previous_year_stats
		_add_stat_row(content, "Revenue", CourseMapStyle.money(previous.get_total_revenue()), TEXT_SECONDARY)
		_add_stat_row(content, "Profit", _signed_money(previous.get_profit()), PROFIT_GREEN if previous.get_profit() >= 0 else LOSS_RED)
		var trend := profit - previous.get_profit()
		var trend_text := "Same as last year"
		var trend_color := TEXT_SECONDARY
		if trend > 0:
			trend_text = "+%s vs last year" % CourseMapStyle.money(trend)
			trend_color = PROFIT_GREEN
		elif trend < 0:
			trend_text = "-%s vs last year" % CourseMapStyle.money(absi(trend))
			trend_color = LOSS_RED
		_add_stat_row(content, "Trend", trend_text, trend_color)
	return card

func _add_positive_cost(entries: Array[Dictionary], label_text: String, amount: int) -> void:
	if amount > 0:
		entries.append({"name": label_text, "amount": amount})

func _add_ledger_heading(parent: VBoxContainer, text: String, color: Color) -> void:
	var label := CourseMapStyle.kicker(text, _font_size(9))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _add_ledger_rows(parent: VBoxContainer, entries: Array[Dictionary], color: Color,
		negative_values: bool = false) -> void:
	for entry in entries:
		var amount := int(entry["amount"])
		var value := -amount if negative_values else amount
		_add_stat_row(parent, str(entry["name"]), CourseMapStyle.money(value), color)

func _build_pricing_card() -> PanelContainer:
	var card := _make_card("REVENUE LEVERS", "Pricing & tee flow", MINT)
	var content := _card_content(card)
	var booking_label := CourseMapStyle.kicker("Tee bookings", _font_size(9))
	booking_label.add_theme_color_override("font_color", TEXT_QUIET)
	content.add_child(booking_label)
	var bookings := OptionButton.new()
	bookings.name = "TeeBookingInterval"
	bookings.add_item("Busy - more groups", 60)
	bookings.add_item("Balanced", 90)
	bookings.add_item("Relaxed - fewer queues", 180)
	bookings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bookings.custom_minimum_size.y = 44 if _is_touch_layout() else 36
	bookings.add_theme_font_override("font", BODY_FONT)
	bookings.add_theme_font_size_override("font_size", _font_size(12))
	var selected_index := 1
	for i in bookings.item_count:
		if bookings.get_item_id(i) == GameManager.tee_booking_interval:
			selected_index = i
			break
	bookings.select(selected_index)
	bookings.item_selected.connect(func(index: int) -> void:
		GameManager.tee_booking_interval = bookings.get_item_id(index))
	content.add_child(bookings)
	var hint := CourseMapStyle.hint("Relaxed bookings limit crowding on the course, but can reduce revenue.", _font_size(10))
	content.add_child(hint)
	_add_rule(content)

	var fee_row := HBoxContainer.new()
	fee_row.add_theme_constant_override("separation", 5)
	var fee_title := CourseMapStyle.label("Fee per hole", _font_size(12), TEXT_SECONDARY, BODY_FONT)
	fee_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fee_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fee_row.add_child(fee_title)
	var decrement := _make_small_button("-", "Lower green fee")
	decrement.name = "FeeDecrease"
	decrement.pressed.connect(_adjust_green_fee.bind(-1))
	fee_row.add_child(decrement)
	var fee_value := CourseMapStyle.title("$%d / hole" % GameManager.green_fee, _font_size(14), GOLD)
	fee_value.name = "GreenFeeValue"
	fee_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fee_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fee_value.custom_minimum_size.x = 94 if not _is_phone() else 86
	fee_row.add_child(fee_value)
	var increment := _make_small_button("+", "Raise green fee")
	increment.name = "FeeIncrease"
	increment.pressed.connect(_adjust_green_fee.bind(1))
	fee_row.add_child(increment)
	content.add_child(fee_row)

	var open_holes := maxi(GameManager.get_open_hole_count(), 1)
	var round_cost := GameManager.green_fee * open_holes
	var fee_info := CourseMapStyle.label(
		"Full round: %s across %d holes  /  Cap: $%d per hole" % [CourseMapStyle.money(round_cost), open_holes, GameManager.get_effective_max_green_fee()],
		_font_size(10), TEXT_QUIET, BODY_FONT)
	fee_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(fee_info)
	var warning := _get_green_fee_warning()
	if not warning.is_empty():
		var warning_label := CourseMapStyle.hint("! " + warning, _font_size(10))
		warning_label.add_theme_color_override("font_color", WARNING_AMBER)
		content.add_child(warning_label)
	return card

func _make_small_button(text: String, tip: String) -> Button:
	var button := CourseMapStyle.icon_button(text, UTILITY, _font_size(14))
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(44, 44) if _is_touch_layout() else Vector2(34, 34)
	return button

func _adjust_green_fee(amount: int) -> void:
	GameManager.set_green_fee(GameManager.green_fee + amount)
	_request_refresh()

func _get_green_fee_warning() -> String:
	var hole_count := GameManager.get_open_hole_count()
	if hole_count <= 0:
		return ""
	var total_round_cost := GameManager.green_fee * maxi(hole_count, 1)
	var fair_price := CourseEconomy.fair_round_price(
		GameManager.reputation, hole_count, GameManager.current_day, GameManager.current_theme)
	var price_ratio := float(total_round_cost) / maxf(fair_price, 1.0)
	if price_ratio > 2.0:
		return "Green fee is very overpriced for course quality. Golfers will avoid your course."
	if price_ratio > 1.5:
		return "Green fee appears overpriced. Consider lowering to attract more golfers."
	return ""

func _build_course_status_card(stats: GameManager.DailyStatistics) -> PanelContainer:
	var card := _make_card("COURSE PULSE", "Reputation & visitors", MINT)
	var content := _card_content(card)
	var reputation := GameManager.reputation
	var reputation_color := PROFIT_GREEN if reputation >= 70.0 else (WARNING_AMBER if reputation >= 40.0 else LOSS_RED)
	_add_stat_row(content, "Reputation", "%.0f%%" % reputation, reputation_color, true)
	_add_stat_row(content, "Golfers this year", "%d" % stats.golfers_served, TEXT_BRIGHT, true)
	var holes := GameManager.get_open_hole_count()
	_add_stat_row(content, "Open holes", "%d" % holes, TEXT_SECONDARY)
	return card

func _build_loan_card() -> PanelContainer:
	var card := _make_card("CAPITAL", "Loans & repayments", Color("df9b83"))
	var content := _card_content(card)
	var loan_color := LOSS_RED if GameManager.loan_balance > 0 else TEXT_SECONDARY
	_add_stat_row(content, "Outstanding", CourseMapStyle.money(GameManager.loan_balance), loan_color, true)
	if GameManager.loan_balance > 0:
		_add_stat_row(content, "Interest", "10% / year-end", TEXT_SECONDARY)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var borrow := CourseMapStyle.button("Borrow $10k", false, _font_size(11))
	borrow.name = "BorrowLoanButton"
	borrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	borrow.custom_minimum_size.y = 44 if _is_touch_layout() else 36
	borrow.disabled = GameManager.loan_balance >= GameManager.MAX_LOAN
	borrow.pressed.connect(func() -> void:
		GameManager.take_loan(10000)
		_request_refresh())
	actions.add_child(borrow)
	var repay := CourseMapStyle.button("Repay $10k", false, _font_size(11))
	repay.name = "RepayLoanButton"
	repay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repay.custom_minimum_size.y = 44 if _is_touch_layout() else 36
	repay.disabled = GameManager.loan_balance <= 0
	repay.pressed.connect(func() -> void:
		GameManager.repay_loan(10000)
		_request_refresh())
	actions.add_child(repay)
	content.add_child(actions)
	return card

func _build_seasonal_card() -> PanelContainer:
	var card := _make_card("SEASONAL FORECAST", "Demand & upkeep", Color("8fb1df"))
	var content := _card_content(card)
	var season := SeasonSystem.get_season(GameManager.current_day)
	var season_name := SeasonSystem.get_season_name(season)
	var season_color := SeasonSystem.get_season_color(season)
	_add_stat_row(content, "Season", season_name, season_color, true)
	var spawn_mod := SeasonSystem.get_spawn_modifier(season)
	var spawn_pct := int(roundf(spawn_mod * 100.0))
	var spawn_color := PROFIT_GREEN if spawn_mod >= 1.0 else (WARNING_AMBER if spawn_mod >= 0.7 else LOSS_RED)
	_add_stat_row(content, "Golfer demand", "%d%%" % spawn_pct, spawn_color)
	var maintenance_mod := SeasonSystem.get_maintenance_modifier(season)
	var maintenance_pct := int(roundf(maintenance_mod * 100.0))
	var maintenance_color := PROFIT_GREEN if maintenance_mod <= 1.0 else (WARNING_AMBER if maintenance_mod <= 1.2 else LOSS_RED)
	_add_stat_row(content, "Maintenance", "%d%%" % maintenance_pct, maintenance_color)
	return card

func _build_rating_card() -> PanelContainer:
	var card := _make_card("OFFICIAL RATINGS", "Course difficulty", Color("9bb9da"))
	var content := _card_content(card)
	var rating: Dictionary = GameManager.course_rating
	if rating.is_empty() or not rating.has("slope"):
		var waiting := CourseMapStyle.hint("Official ratings appear once your course has been rated.", _font_size(11))
		content.add_child(waiting)
		return card

	var hole_count := 0
	if GameManager.current_course:
		for hole in GameManager.current_course.holes:
			if hole.is_open:
				hole_count += 1
	_add_stat_row(content, "Holes", "%d" % hole_count, TEXT_BRIGHT)
	var slope := int(rating.get("slope", 113))
	var slope_color := UIConstants.COLOR_INFO_DIM
	if slope >= 130:
		slope_color = UIConstants.COLOR_ORANGE
	elif slope <= 90:
		slope_color = PROFIT_GREEN
	_add_stat_row(content, "Slope", "%d (%s)" % [slope, CourseRatingSystem.get_slope_text(slope)], slope_color)
	_add_stat_row(content, "Course rating", "%.1f" % float(rating.get("course_rating", 72.0)), TEXT_BRIGHT)
	var difficulty := float(rating.get("difficulty", 5.0))
	var difficulty_color := PROFIT_GREEN
	if difficulty >= 7.0:
		difficulty_color = LOSS_RED
	elif difficulty >= 5.0:
		difficulty_color = WARNING_AMBER
	_add_stat_row(content, "Difficulty", "%.1f (%s)" % [difficulty, CourseRatingSystem.get_difficulty_text(difficulty)], difficulty_color)
	return card

func _build_marketing_performance_card() -> PanelContainer:
	var card := _make_card("CAMPAIGN EFFECT", "Marketing performance", GOLD)
	var content := _card_content(card)
	var manager: MarketingManager = GameManager.marketing_manager
	if manager == null:
		content.add_child(CourseMapStyle.hint("Marketing services are unavailable.", _font_size(11)))
		return card
	var bonus_pct := int(roundf((manager.get_spawn_rate_modifier() - 1.0) * 100.0))
	var bonus_color := PROFIT_GREEN if bonus_pct > 0 else TEXT_SECONDARY
	_add_stat_row(content, "Spawn bonus", "+%d%%" % bonus_pct, bonus_color, true)
	_add_stat_row(content, "Daily campaign spend", CourseMapStyle.money(manager.get_daily_marketing_cost()), WARNING_AMBER)
	_add_stat_row(content, "Campaigns active", "%d" % manager.get_active_campaign_count(), TEXT_BRIGHT)
	_add_rule(content)
	_add_stat_row(content, "Total spent", CourseMapStyle.money(manager.total_marketing_spent), TEXT_SECONDARY)
	_add_stat_row(content, "Campaigns completed", "%d" % manager.campaigns_completed, TEXT_SECONDARY)
	return card

func _build_active_campaigns_card() -> PanelContainer:
	var card := _make_card("ON AIR", "Active campaigns", MINT)
	var content := _card_content(card)
	var manager: MarketingManager = GameManager.marketing_manager
	if manager == null or manager.active_campaigns.is_empty():
		content.add_child(CourseMapStyle.hint("No active campaigns. Choose a channel below to start reaching more golfers.", _font_size(11)))
		return card
	for campaign in manager.active_campaigns:
		var channel := int(campaign.get("channel", -1))
		var channel_data: Dictionary = MarketingManager.CHANNEL_DATA.get(channel, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 1)
		var name_label := CourseMapStyle.label(str(channel_data.get("name", "Campaign")), _font_size(12), TEXT_BRIGHT, SUBTITLE_FONT)
		details.add_child(name_label)
		var days := int(campaign.get("days_remaining", 0))
		var days_text := "%d day%s left" % [days, "" if days == 1 else "s"]
		var info := CourseMapStyle.label(days_text, _font_size(10), TEXT_QUIET, BODY_FONT)
		details.add_child(info)
		row.add_child(details)
		var cost := CourseMapStyle.label("%s/day" % CourseMapStyle.money(int(campaign.get("daily_cost", 0))), _font_size(10), WARNING_AMBER, BODY_FONT)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(cost)
		content.add_child(row)
	return card

func _build_channel_catalog_card() -> PanelContainer:
	var card := _make_card("GROW THE GALLERY", "Launch a campaign", GOLD)
	var content := _card_content(card)
	var note := CourseMapStyle.hint("One-time setup is five days of the channel's daily rate. Campaigns can be stacked; returns diminish.", _font_size(10))
	content.add_child(note)
	var channels := MarketingManager.CHANNEL_DATA.keys()
	for index in channels.size():
		var channel := int(channels[index])
		content.add_child(_build_channel_offer(channel, CHANNEL_ACCENTS[index % CHANNEL_ACCENTS.size()]))
	return card

func _build_channel_offer(channel: int, accent: Color) -> PanelContainer:
	var data: Dictionary = MarketingManager.CHANNEL_DATA.get(channel, {})
	var daily_cost := int(data.get("daily_cost", 50))
	var setup_cost := daily_cost * 5
	var duration := int(data.get("duration_days", 5))
	var bonus := int(roundf(float(data.get("spawn_rate_bonus", 0.15)) * 100.0))
	var offer := PanelContainer.new()
	offer.name = "CampaignOffer_%d" % channel
	offer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offer.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(accent, 0.62), INSET, 8, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	offer.add_child(row)
	var detail_stack := VBoxContainer.new()
	detail_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_stack.add_theme_constant_override("separation", 1)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 5)
	var name_label := CourseMapStyle.label(str(data.get("name", "Campaign")), _font_size(12), TEXT_BRIGHT, SUBTITLE_FONT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(name_label)
	var bonus_badge := CourseMapStyle.chip("+%d%%" % bonus, accent, _font_size(9))
	title_row.add_child(bonus_badge)
	detail_stack.add_child(title_row)
	var cost_line := CourseMapStyle.label(
		"Setup %s  /  %s per day  /  %d days" % [CourseMapStyle.money(setup_cost), CourseMapStyle.money(daily_cost), duration],
		_font_size(9), WARNING_AMBER, BODY_FONT)
	detail_stack.add_child(cost_line)
	var description := CourseMapStyle.hint(str(data.get("description", "")), _font_size(10))
	description.name = "Description"
	detail_stack.add_child(description)
	row.add_child(detail_stack)

	var launch := CourseMapStyle.button("LAUNCH", true, _font_size(10))
	launch.name = "LaunchCampaign_%d" % channel
	launch.accessibility_name = "Launch %s campaign" % str(data.get("name", "Campaign"))
	launch.tooltip_text = "%s\nSetup: %s | Daily: %s | Duration: %d days | Spawn bonus: +%d%%" % [
		str(data.get("description", "")), CourseMapStyle.money(setup_cost),
		CourseMapStyle.money(daily_cost), duration, bonus,
	]
	launch.custom_minimum_size = Vector2(72, 44 if _is_touch_layout() else 36)
	launch.pressed.connect(_launch_campaign.bind(channel))
	row.add_child(launch)
	return offer

func _launch_campaign(channel: int) -> void:
	if GameManager.marketing_manager:
		GameManager.marketing_manager.start_campaign(channel)
	_request_refresh()

func _highlight_row(label_text: String, value_text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(accent, 0.58), SURFACE_RAISED, 8, 5))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var label := CourseMapStyle.label(label_text, _font_size(11), TEXT_SECONDARY, SUBTITLE_FONT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := CourseMapStyle.title(value_text, _font_size(15), accent)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.clip_text = true
	row.add_child(value)
	return panel

func _add_stat_row(parent: VBoxContainer, label_text: String, value_text: String,
		value_color: Color = TEXT_BRIGHT, emphasize: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := CourseMapStyle.label(label_text, _font_size(11), TEXT_SECONDARY, BODY_FONT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var value_font: Font = SUBTITLE_FONT if emphasize else BODY_FONT
	var value := CourseMapStyle.label(value_text, _font_size(11 if not emphasize else 12), value_color, value_font)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value)
	parent.add_child(row)
	return row

func _add_rule(parent: VBoxContainer) -> void:
	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.28), Color(0, 0, 0, 0), 0, 0))
	parent.add_child(rule)

func _period_stats() -> GameManager.DailyStatistics:
	var stats := GameManager.DailyStatistics.new()
	if GameManager.yearly_stats != null:
		stats.accumulate_from(GameManager.yearly_stats)
	if GameManager.daily_stats != null:
		stats.accumulate_from(GameManager.daily_stats)
	return stats

func _signed_money(amount: int) -> String:
	return ("+" if amount >= 0 else "") + CourseMapStyle.money(amount)
