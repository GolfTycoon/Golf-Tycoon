extends Control
class_name WorldMilestonesScreen
## WorldMilestonesScreen - the fullscreen book of company goals.
##
## World Milestones are earned by the company across every course location
## it owns, and unlocked again with every new save. The screen pairs the
## company record (the numbers the goals are earned from) with the ledger of
## milestone cards, grouped by category and stamped with the day each one
## landed.
##
## The composition suits the window's shape:
##
##  * Desktop: a company-record rail beside the two-column goal ledger.
##  * Tablet landscape: the record as a wide strip above the ledger.
##  * Tablet portrait and phone landscape: the same strip, cards two
##    columns wide.
##  * Phone portrait: one scrollable column - summary, cards.
##
## It sits on the World Map's MenuBackdrop artwork, wears the same pixel
## look as the other goal screens, and carries the three-track switch
## (Course / World / Achievements).

signal back_requested()
signal track_requested(track: int)

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

const DESKTOP_LEDGER_COLUMNS := 2
const NARROW_LEDGER_COLUMNS := 2
const PHONE_LEDGER_COLUMNS := 1

var milestone_manager: MilestoneManager = null

var _layout_mode: int = -1
var _built_size := Vector2.ZERO

func set_milestone_manager(manager: MilestoneManager) -> void:
	milestone_manager = manager

func _ready() -> void:
	name = "WorldMilestonesScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	refresh()

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

func refresh() -> void:
	_build()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

# =============================================================================
# COMPOSITION
# =============================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_layout_mode = Kit.layout_mode_for(_window_size())
	_built_size = _window_size()

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
	frame.add_child(page)
	page.add_child(_build_header())

	var body: Control
	match _layout_mode:
		Kit.LayoutMode.DESKTOP:
			body = _build_desktop_body()
		_:
			body = _build_stacked_body(
				PHONE_LEDGER_COLUMNS if _layout_mode == Kit.LayoutMode.PHONE_PORTRAIT
					else NARROW_LEDGER_COLUMNS)
	page.add_child(body)

func _world_done() -> int:
	return milestone_manager.get_world_completion_count() if milestone_manager else 0

func _world_total() -> int:
	return milestone_manager.get_world_total_count() if milestone_manager else 0

# =============================================================================
# HEADER
# =============================================================================

func _build_header() -> Control:
	var trailing: Control = null
	if not Kit.is_phone(_layout_mode):
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", 10)
		group.add_child(_build_world_stat_chip())
		var switch := Kit.make_track_switch(Kit.GoalTrack.WORLD,
			func(track: int): track_requested.emit(track))
		switch.size_flags_horizontal = Control.SIZE_SHRINK_END
		group.add_child(switch)
		trailing = group
	return Kit.make_screen_header(_layout_mode, "World Milestones", "Milestones",
		"", func(): back_requested.emit(), trailing)

func _build_world_stat_chip() -> PanelContainer:
	var chip := Kit.make_panel(Kit.COLOR_SURFACE_RAISED, MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.55))
	chip.name = "WorldStat"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 9)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	chip.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var caption := Kit.make_kicker("World", 9)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(caption)
	var count := Kit.make_count_label(_world_done(), _world_total(), 15)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(count)
	return chip

# =============================================================================
# BODY: DESKTOP - company record beside the ledger
# =============================================================================

func _build_desktop_body() -> Control:
	var body := HBoxContainer.new()
	body.name = "DesktopWorldGoals"
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var rail := _build_company_record()
	rail.custom_minimum_size.x = clampf(_built_size.x * 0.21, 280.0, 350.0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(rail)

	var ledger := _build_world_ledger(DESKTOP_LEDGER_COLUMNS)
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(ledger)
	return body

## The company-record rail: the world tally over the numbers the goals are
## earned from, and the note about how the two per-save tracks work.
func _build_company_record() -> Control:
	var rail := VBoxContainer.new()
	rail.name = "CompanyRecord"
	rail.add_theme_constant_override("separation", 11)

	var panel := Kit.make_panel(Kit.COLOR_SURFACE, MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.42))
	panel.name = "CompanyStats"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	margin.add_child(stack)

	stack.add_child(Kit.make_kicker("World milestones", 11))
	stack.add_child(Kit.make_semibold_label("All course locations", 13, Kit.COLOR_TEXT_SECONDARY))

	var progress := VBoxContainer.new()
	progress.add_theme_constant_override("separation", 3)
	var count := Kit.make_count_label(_world_done(), _world_total(), 22)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.add_child(count)
	var bar := Kit.make_progress_bar(
		float(_world_done()) / maxf(float(_world_total()), 1.0), Kit.COLOR_GOLD, 9.0)
	bar.name = "WorldProgressBar"
	progress.add_child(bar)
	stack.add_child(progress)

	stack.add_child(Kit.make_kicker("The company record", 10))
	for row in _company_stat_rows():
		stack.add_child(row)

	rail.add_child(_build_tracks_note())
	return rail

## The company stats the world goals measure: portfolio, holes, standing,
## time and this year's takings.
func _company_stat_rows() -> Array:
	var rows: Array = []
	var holes := 0
	var owned := 0
	if milestone_manager:
		holes = milestone_manager.get_company_hole_count()
		owned = milestone_manager.get_owned_location_count()
	var yearly_revenue: int = GameManager.yearly_stats.get_total_revenue() \
		+ GameManager.daily_stats.get_total_revenue()
	for part: Array in [
		[PixelIcon.Kind.PIN, "Course locations", str(owned)],
		[PixelIcon.Kind.FLAG, "Holes across the company", str(holes)],
		[PixelIcon.Kind.STAR, "Reputation", "%d" % roundi(GameManager.reputation)],
		[PixelIcon.Kind.TROPHY, "Days in business", "%d" % GameManager.current_day],
		[PixelIcon.Kind.COIN, "Revenue this year", Kit.format_money_compact(yearly_revenue)],
	]:
		rows.append(_make_stat_row(int(part[0]), str(part[1]), str(part[2])))
	return rows

func _make_stat_row(icon_kind: int, label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := Kit.make_sprite(icon_kind, 18, MenuStyle.ACCENT_UTILITY)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Kit.make_label(label_text, 12, Kit.COLOR_TEXT_SECONDARY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var value := Kit.make_semibold_label(value_text, 12, Kit.COLOR_GOLD)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row

func _build_tracks_note() -> PanelContainer:
	var note := Kit.make_panel(Kit.COLOR_SURFACE_INSET,
		MenuStyle.with_alpha(Kit.COLOR_BORDER_SOFT, 0.5))
	note.name = "TracksNote"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	note.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(Kit.make_kicker("Goals that last", 10))
	var text := Kit.make_label("Milestones unlock again with every new save. Achievements stay unlocked forever.",
		11, Kit.COLOR_TEXT_QUIET)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(text)
	return note

# =============================================================================
# THE LEDGER
# =============================================================================

## The world ledger: every company goal under its category header.
func _build_world_ledger(columns: int) -> Control:
	var panel := Kit.make_panel(Kit.COLOR_SURFACE, MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.42))
	panel.name = "WorldLedger"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 13)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	margin.add_child(stack)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var kicker := Kit.make_kicker("The company's goal book", 11)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(kicker)
	var count_note := Kit.make_label("%d milestones" % _world_total(), 11, Kit.COLOR_TEXT_QUIET)
	count_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count_note)
	stack.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.name = "LedgerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)

	var groups := []
	if milestone_manager:
		groups = Kit.group_entries_by_category(milestone_manager.world_milestones,
			milestone_manager.get_world_completed())
	scroll.add_child(Kit.build_category_columns(groups, columns,
		Kit.make_milestone_card,
		"Nothing here yet - run the company to start unlocking world milestones."))
	return panel

# =============================================================================
# BODY: STACKED (tablet and phone)
# =============================================================================

## Tablet and phone: the company record as a strip of stat chips over the
## ledger; the goal switch leads on phones.
func _build_stacked_body(columns: int) -> Control:
	var body := VBoxContainer.new()
	body.name = "StackedWorldGoals"
	body.add_theme_constant_override("separation", 8 if Kit.is_phone(_layout_mode) else 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if Kit.is_phone(_layout_mode):
		var switch := Kit.make_track_switch(Kit.GoalTrack.WORLD,
			func(track: int): track_requested.emit(track))
		body.add_child(switch)

	body.add_child(_build_company_summary_strip())
	var ledger := _build_world_ledger(columns)
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(ledger)
	return body

## The company record as one row: the tally first, then the stats the goals
## measure. On phone portrait the stats fold to the three that matter most.
func _build_company_summary_strip() -> Control:
	var phone := Kit.is_phone(_layout_mode)
	var strip := HBoxContainer.new()
	strip.name = "CompanySummary"
	strip.add_theme_constant_override("separation", 8)
	strip.size_flags_vertical = Control.SIZE_SHRINK_END

	var tally := Kit.make_panel(Kit.COLOR_SURFACE_RAISED, MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.55))
	tally.name = "WorldTally"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 9 if phone else 11)
	tally.add_child(margin)
	var tally_box := VBoxContainer.new()
	tally_box.add_theme_constant_override("separation", 2)
	margin.add_child(tally_box)
	tally_box.add_child(Kit.make_kicker("World", 9))
	var count := Kit.make_count_label(_world_done(), _world_total(), 16 if phone else 19)
	tally_box.add_child(count)
	var bar := Kit.make_progress_bar(
		float(_world_done()) / maxf(float(_world_total()), 1.0), Kit.COLOR_GOLD, 8.0)
	bar.custom_minimum_size.x = 92.0
	tally_box.add_child(bar)
	strip.add_child(tally)

	var holes := 0
	var owned := 0
	if milestone_manager:
		holes = milestone_manager.get_company_hole_count()
		owned = milestone_manager.get_owned_location_count()
	var yearly_revenue: int = GameManager.yearly_stats.get_total_revenue() \
		+ GameManager.daily_stats.get_total_revenue()
	var parts: Array = [
		["%d locations" % owned, Kit.COLOR_MINT],
		["%d holes" % holes, Kit.COLOR_MINT],
	]
	if phone:
		parts.append(["%d rep" % roundi(GameManager.reputation), Kit.COLOR_GOLD])
	else:
		parts.append_array([
			["%d rep" % roundi(GameManager.reputation), Kit.COLOR_GOLD],
			["%d days" % GameManager.current_day, Kit.COLOR_TEXT_SECONDARY],
			[Kit.format_money_compact(yearly_revenue) + " this year", Kit.COLOR_GOLD],
		])
	for part in parts:
		var chip := Kit.make_chip(str(part[0]), (part[1] as Color), UIConstants.COLOR_TEXT, 11)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(chip)
	return strip
