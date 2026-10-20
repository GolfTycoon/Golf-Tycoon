extends Control
class_name AchievementsScreen
## AchievementsScreen - the fullscreen trophy room.
##
## Career honours that stay unlocked between saves. While Course Location
## and World Milestones lock again with every new company, what is earned
## here is written to the player's settings file and kept for good (see
## AchievementStore), so the shelf fills across every company ever run.
##
## The composition suits each window shape:
##
##  * Desktop: a trophy-case rail (the newest honour, then the career
##    counters behind the rest) beside a three-column case of honours.
##  * Tablet landscape: the case header as a wide strip over a three-column
##    grid; tablet portrait drops to two columns.
##  * Phone landscape: a compact featured row over a two-column grid.
##  * Phone portrait: one scrollable column, featured honour first.
##
## A filter flips between every honour, the ones on the shelf and the ones
## still locked. Locked honours keep their title and progress but hide what
## they are waiting for behind a "LOCKED" stamp.
##
## It sits on the World Map's MenuBackdrop artwork and wears the same pixel
## look as the Milestones screen and the World Map.

signal back_requested()
signal track_requested(track: int)

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

enum Filter { ALL, UNLOCKED, LOCKED }

var milestone_manager: MilestoneManager = null
## The title-menu entry is a standalone trophy room; the in-game entry keeps
## the switch for jumping between all three goal tracks.
var track_navigation_enabled: bool = true

var _layout_mode: int = -1
var _built_size := Vector2.ZERO
var _filter: int = Filter.ALL
var back_button: Button = null

func set_milestone_manager(manager: MilestoneManager) -> void:
	milestone_manager = manager

func _ready() -> void:
	name = "AchievementsScreen"
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
	if milestone_manager:
		milestone_manager.refresh_achievements()
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
		Kit.LayoutMode.TABLET_LANDSCAPE:
			body = _build_tablet_body(3)
		Kit.LayoutMode.TABLET_PORTRAIT:
			body = _build_tablet_body(2)
		Kit.LayoutMode.PHONE_LANDSCAPE:
			body = _build_phone_body(2)
		_:
			body = _build_phone_body(1)
	page.add_child(body)

# =============================================================================
# HEADER
# =============================================================================

func _build_header() -> Control:
	var trailing: Control = null
	if not Kit.is_phone(_layout_mode):
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", 10)
		group.add_child(_build_unlocked_chip())
		if track_navigation_enabled:
			var switch := Kit.make_track_switch(Kit.GoalTrack.ACHIEVEMENTS,
				func(track: int): track_requested.emit(track))
			switch.size_flags_horizontal = Control.SIZE_SHRINK_END
			group.add_child(switch)
		trailing = group
	var header := Kit.make_screen_header(_layout_mode, "Achievements", "Milestones",
		"", func(): back_requested.emit(), trailing)
	back_button = header.get_node("BackButton") as Button
	return header

func _build_unlocked_chip() -> PanelContainer:
	var done := milestone_manager.get_achievement_count() if milestone_manager else 0
	var total := milestone_manager.get_achievement_total_count() if milestone_manager else 0
	var chip := Kit.make_panel(Kit.COLOR_SURFACE_RAISED, MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.55))
	chip.name = "UnlockedStat"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 9)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	chip.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	if not Kit.is_phone(_layout_mode):
		var caption := Kit.make_kicker("Unlocked", 9)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(caption)
	var count := Kit.make_count_label(done, total, 15)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(count)
	return chip

# =============================================================================
# BODY: DESKTOP - trophy case beside the honour grid
# =============================================================================

func _build_desktop_body() -> Control:
	var body := HBoxContainer.new()
	body.name = "DesktopTrophyRoom"
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var case := _build_trophy_case()
	case.custom_minimum_size.x = clampf(_built_size.x * 0.235, 300.0, 380.0)
	case.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(case)

	var grid := _build_honor_grid(3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	return body

## The trophy-case rail: the newest honour on the shelf over the career
## counters that fill the rest.
func _build_trophy_case() -> Control:
	var rail := VBoxContainer.new()
	rail.name = "TrophyCase"
	rail.add_theme_constant_override("separation", 11)

	var featured := _build_featured_panel()
	featured.size_flags_vertical = Control.SIZE_SHRINK_END
	rail.add_child(featured)

	var stats := _build_career_stats_panel()
	stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(stats)
	return rail

## The newest honour, big: trophy sprite, name, and when it landed.
func _build_featured_panel() -> Control:
	var panel := Kit.make_panel(Kit.COLOR_SURFACE, MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.55))
	panel.name = "FeaturedHonor"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	stack.add_child(Kit.make_kicker("Newest honour", 11))
	var latest := _latest_unlock()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var sprite := Kit.make_sprite(PixelIcon.Kind.TROPHY, 40 if not Kit.is_phone(_layout_mode) else 32,
		Kit.COLOR_GOLD, latest.is_empty())
	sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sprite)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	if latest.is_empty():
		text.add_child(Kit.make_semibold_label("The shelf is waiting", 15, Kit.COLOR_TEXT_SECONDARY))
		var tease := Kit.make_label("Play any company to earn your first honour. It will stay with you.",
			11, Kit.COLOR_TEXT_QUIET)
		tease.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(tease)
	else:
		var m: MilestoneSystem.Milestone = latest["milestone"]
		text.add_child(Kit.make_title_label(m.title, 18 if not Kit.is_phone(_layout_mode) else 15))
		var desc := Kit.make_label(m.description, 11, Kit.COLOR_TEXT_SECONDARY)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(desc)
		text.add_child(Kit.make_chip("Unlocked on day %d" % int(latest["day"]),
			Kit.COLOR_GOLD, UIConstants.COLOR_TEXT, 10))
	row.add_child(text)
	stack.add_child(row)
	return panel

## The career counters the honours are earned from - the numbers that carry
## across every company.
func _build_career_stats_panel() -> Control:
	var panel := Kit.make_panel(Kit.COLOR_SURFACE_INSET, MenuStyle.with_alpha(Kit.COLOR_BORDER_SOFT, 0.5))
	panel.name = "CareerStats"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	margin.add_child(stack)
	stack.add_child(Kit.make_kicker("Career record", 11))
	var counters := [
		["rounds", "Rounds played", PixelIcon.Kind.SHIRT],
		["holes_built", "Holes built", PixelIcon.Kind.FLAG],
		["hole_in_ones", "Holes-in-one", PixelIcon.Kind.STAR],
		["revenue", "Total revenue", PixelIcon.Kind.COIN],
		["locations_bought", "Locations bought", PixelIcon.Kind.PIN],
		["days", "Longest company", PixelIcon.Kind.TROPHY],
	]
	for entry in counters:
		stack.add_child(_make_stat_row(str(entry[0]), str(entry[1]), int(entry[2])))
	return panel

func _make_stat_row(counter: String, label_text: String, icon_kind: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Stat_%s" % counter
	row.add_theme_constant_override("separation", 8)
	var icon := Kit.make_sprite(icon_kind, 18, MenuStyle.ACCENT_UTILITY)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Kit.make_label(label_text, 12, Kit.COLOR_TEXT_SECONDARY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := 0
	if milestone_manager:
		value = milestone_manager.get_counter(counter)
	var suffix := " days" if counter == "days" else ""
	var value_label := Kit.make_semibold_label(
		Kit.format_counter(counter, value) + suffix, 12, Kit.COLOR_GOLD)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row

## The newest honour on the shelf: the last one the career store unlocked
## (the store keeps its unlocks in the order they landed).
func _latest_unlock() -> Dictionary:
	if not milestone_manager:
		return {}
	var latest := {}
	for id in milestone_manager.achievement_state.get("unlocked", {}):
		var m := _achievement_def(id)
		if m:
			latest = {"milestone": m, "day": milestone_manager.get_achievement_day(id)}
	return latest

func _achievement_def(id: String) -> MilestoneSystem.Milestone:
	for m in milestone_manager.achievements:
		if m.id == id:
			return m
	return null

# =============================================================================
# THE HONOUR GRID
# =============================================================================

## Filter chips plus the grouped cards. `columns` is how many honours sit
## side by side.
func _build_honor_grid(columns: int) -> Control:
	var panel := Kit.make_panel(Kit.COLOR_SURFACE, MenuStyle.with_alpha(Kit.COLOR_MINT, 0.42))
	panel.name = "HonorGrid"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 13)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	margin.add_child(stack)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var kicker := Kit.make_kicker("The honour roll", 11)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(kicker)
	head.add_child(_build_filter_switch())
	stack.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.name = "HonorScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	scroll.add_child(_build_category_columns(_honor_groups(), columns))
	return panel

func _filter_label(filter: int) -> String:
	match filter:
		Filter.UNLOCKED: return "Unlocked"
		Filter.LOCKED: return "Locked"
		_: return "All"

## The All / Unlocked / Locked toggle row.
func _build_filter_switch() -> Control:
	var switch := HBoxContainer.new()
	switch.name = "FilterSwitch"
	switch.add_theme_constant_override("separation", 6)
	for filter in [Filter.ALL, Filter.UNLOCKED, Filter.LOCKED]:
		var button := Button.new()
		button.name = "Filter_%s" % _filter_label(filter)
		button.text = _filter_label(filter)
		button.toggle_mode = true
		button.button_pressed = _filter == filter
		button.custom_minimum_size = Vector2(0, 32.0 if not Kit.is_phone(_layout_mode) else 30.0)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		Kit.paint_toggle(button, Kit.COLOR_MINT)
		button.pressed.connect(func():
			_filter = filter
			_build())
		switch.add_child(button)
	return switch

## Achievements as category groups of entries, honouring the filter.
func _honor_groups() -> Array:
	var groups: Array = []
	if not milestone_manager:
		return groups
	var by_category: Dictionary = {}
	for m in milestone_manager.achievements:
		var unlocked := milestone_manager.is_achievement_unlocked(m.id)
		if _filter == Filter.UNLOCKED and not unlocked:
			continue
		if _filter == Filter.LOCKED and unlocked:
			continue
		var entry := {
			"milestone": m,
			"done": unlocked,
			"day": milestone_manager.get_achievement_day(m.id),
			"progress": milestone_manager.get_achievement_progress(m),
		}
		if not by_category.has(m.category):
			by_category[m.category] = []
		by_category[m.category].append(entry)
	var categories: Array = by_category.keys()
	categories.sort_custom(func(a: int, b: int) -> bool:
		return MilestoneSystem.get_category_order(a) < MilestoneSystem.get_category_order(b))
	for category in categories:
		groups.append({"category": category, "entries": by_category[category]})
	return groups

## Lay category groups into `columns` vertical ledgers, balanced by count.
func _build_category_columns(groups: Array, columns: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "HonorColumns"
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var columns_box: Array = []
	var heights: Array = []
	for i in columns:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 12)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		columns_box.append(column)
		heights.append(0)
	for group in groups:
		var lightest := 0
		for i in range(1, columns):
			if heights[i] < heights[lightest]:
				lightest = i
		(columns_box[lightest] as VBoxContainer).add_child(_build_category_group(group, columns > 1))
		heights[lightest] += 30 + (group["entries"] as Array).size() * 92
	if groups.is_empty():
		columns_box[0].add_child(_build_empty_note())
	return row

func _build_category_group(group: Dictionary, compact: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "Category_%s" % str(group["category"])
	box.add_theme_constant_override("separation", 7)
	var color := MilestoneSystem.get_category_color(int(group["category"]))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var heading := Kit.make_kicker(MilestoneSystem.get_category_name(int(group["category"])), 11)
	heading.add_theme_color_override("font_color", color)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var entries: Array = group["entries"]
	var done_count := 0
	for entry in entries:
		if entry["done"]:
			done_count += 1
	head.add_child(Kit.make_label("%d/%d" % [done_count, entries.size()], 11, Kit.COLOR_TEXT_QUIET))
	box.add_child(head)
	for entry in entries:
		box.add_child(_make_honor_card(entry, color, compact))
	return box

## One honour: gold and open when unlocked, muted and stamped LOCKED when
## not. Counter honours show how far the career has come.
func _make_honor_card(entry: Dictionary, accent: Color, compact: bool) -> Control:
	var m: MilestoneSystem.Milestone = entry["milestone"]
	var done := bool(entry["done"])
	var card := Kit.make_panel(
		MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.18) if done else Kit.COLOR_SURFACE_RAISED,
		MenuStyle.with_alpha(Kit.COLOR_GOLD if done else accent, 0.9 if done else 0.42))
	card.name = "Honor_%s" % m.id
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 11)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var icon := Kit.make_sprite(PixelIcon.Kind.TROPHY if done else PixelIcon.Kind.STAR,
		22 if not compact else 18, Kit.COLOR_GOLD if done else MenuStyle.ACCENT_UTILITY, not done)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(icon)
	var title := Kit.make_semibold_label(m.title, 14 if not compact else 13,
		Kit.COLOR_TEXT_BRIGHT if done else Kit.COLOR_TEXT_SECONDARY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	top.add_child(title)
	var stamp := Kit.make_chip(("Day %d" % int(entry["day"])) if done else "LOCKED",
		Kit.COLOR_GOLD if done else MenuStyle.ACCENT_UTILITY,
		UIConstants.COLOR_TEXT if done else Kit.COLOR_TEXT_QUIET, 10)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(stamp)
	stack.add_child(top)

	if done:
		var desc := Kit.make_label(m.description, 11, Kit.COLOR_TEXT_QUIET)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(desc)
	else:
		var tease := Kit.make_label("Keep playing to reveal this honour.", 11, Kit.COLOR_TEXT_QUIET)
		tease.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(tease)
		if not m.counter.is_empty():
			var progress_row := HBoxContainer.new()
			progress_row.add_theme_constant_override("separation", 8)
			var value := int(entry.get("progress", 0))
			var counter_label := Kit.make_label("%s / %s" % [
				Kit.format_counter(m.counter, value),
				Kit.format_counter(m.counter, m.goal),
			], 11, Kit.COLOR_TEXT_SECONDARY)
			counter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			progress_row.add_child(counter_label)
			var bar := Kit.make_progress_bar(float(value) / maxf(float(m.goal), 1.0),
				accent, 8.0)
			bar.custom_minimum_size.x = 84.0
			progress_row.add_child(bar)
			stack.add_child(progress_row)
	return card

func _build_empty_note() -> Control:
	var text := "No honours match this filter."
	if _filter == Filter.UNLOCKED:
		text = "None unlocked yet — the trophy room is waiting for its first honour."
	elif _filter == Filter.LOCKED:
		text = "Nothing locked: every honour is on the shelf!"
	var note := Kit.make_label(text, 12, Kit.COLOR_TEXT_QUIET)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note

# =============================================================================
# BODY: TABLET AND PHONE
# =============================================================================

## Tablet: the trophy case as a wide strip above the grid, so the newest
## honour and the career record never scroll away.
func _build_tablet_body(columns: int) -> Control:
	var body := VBoxContainer.new()
	body.name = "TabletTrophyRoom"
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var strip := HBoxContainer.new()
	strip.name = "CaseStrip"
	strip.add_theme_constant_override("separation", 12)
	strip.size_flags_vertical = Control.SIZE_SHRINK_END
	var featured := _build_featured_panel()
	featured.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(featured)
	var stats := _build_career_stats_panel()
	stats.custom_minimum_size.x = clampf(_built_size.x * 0.38, 280.0, 420.0)
	strip.add_child(stats)
	body.add_child(strip)

	var grid := _build_honor_grid(columns)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	return body

## Phone: a compact featured row, then the grid. On the smallest screens the
## career record folds into a single summary line above the honours.
func _build_phone_body(columns: int) -> Control:
	var body := VBoxContainer.new()
	body.name = "PhoneTrophyRoom"
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# The phone header keeps only Back and the title, so navigation and the
	# unlocked tally lead the body where they can breathe. From the title menu,
	# the trophy room is standalone: keep the tally but omit the track switch.
	if track_navigation_enabled:
		var nav := HBoxContainer.new()
		nav.name = "TrackNav"
		nav.add_theme_constant_override("separation", 8)
		var switch := Kit.make_track_switch(Kit.GoalTrack.ACHIEVEMENTS,
			func(track: int): track_requested.emit(track))
		switch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(switch)
		var chip := _build_unlocked_chip()
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nav.add_child(chip)
		body.add_child(nav)
	else:
		var stats_row := HBoxContainer.new()
		stats_row.name = "AchievementStatsRow"
		stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_row.alignment = BoxContainer.ALIGNMENT_END
		stats_row.add_child(_build_unlocked_chip())
		body.add_child(stats_row)

	var featured := _build_featured_panel()
	featured.size_flags_vertical = Control.SIZE_SHRINK_END
	body.add_child(featured)

	if _layout_mode == Kit.LayoutMode.PHONE_PORTRAIT:
		body.add_child(_build_career_summary_line())
	else:
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 10)
		strip.size_flags_vertical = Control.SIZE_SHRINK_END
		var stats := _build_career_stats_panel()
		stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(stats)
		body.add_child(strip)

	var grid := _build_honor_grid(columns)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	return body

## Phone portrait: the career record as one quiet line - rounds, revenue and
## honours - instead of a panel taller than the honours themselves.
func _build_career_summary_line() -> Control:
	var line := HBoxContainer.new()
	line.name = "CareerSummary"
	line.add_theme_constant_override("separation", 6)
	var rounds := 0
	var revenue := 0
	var unlocked := 0
	var total := 0
	if milestone_manager:
		rounds = milestone_manager.get_counter("rounds")
		revenue = milestone_manager.get_counter("revenue")
		unlocked = milestone_manager.get_achievement_count()
		total = milestone_manager.get_achievement_total_count()
	for part: Array in [
		["%d rounds" % rounds, Kit.COLOR_TEXT_SECONDARY],
		[Kit.format_money_compact(revenue), Kit.COLOR_GOLD],
		["%d/%d honours" % [unlocked, total], Kit.COLOR_MINT],
	]:
		var chip := Kit.make_chip(str(part[0]), (part[1] as Color),
			UIConstants.COLOR_TEXT, 11)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(chip)
	return line
