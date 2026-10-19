extends Control
class_name CourseMilestonesScreen
## CourseMilestonesScreen - the fullscreen book of per-location goals.
##
## Course Location Milestones are unlocked again with every new save: each
## course location carries its own set of fifteen, and this screen is where
## that site's book is read. The left rail (or the chip shelf on smaller
## windows) picks the site; beside it the ledger of milestone cards, grouped
## by category and stamped with the day each one landed.
##
## The composition suits the window's shape:
##
##  * Desktop: a location rail, then the site's dossier over a two-column
##    ledger of its milestone cards.
##  * Tablet landscape: a chip shelf and the site dossier above the ledger.
##  * Tablet portrait and phone landscape: the same shelf and dossier, with
##    the cards two columns wide.
##  * Phone portrait: one scrollable column - shelf, dossier, cards.
##
## It sits on the World Map's MenuBackdrop artwork, wears the same pixel
## look as the other goal screens, and carries the three-track switch (Course
## / World / Achievements) so the player can hop tracks without going back
## to the course.

signal back_requested()
signal track_requested(track: int)

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

## Columns of milestone cards in the ledger.
const DESKTOP_LEDGER_COLUMNS := 2
const NARROW_LEDGER_COLUMNS := 2
const PHONE_LEDGER_COLUMNS := 1

var milestone_manager: MilestoneManager = null

var _layout_mode: int = -1
var _built_size := Vector2.ZERO
## The course location whose milestones the ledger shows.
var _selected_location_id := ""

func set_milestone_manager(manager: MilestoneManager) -> void:
	milestone_manager = manager

func _ready() -> void:
	name = "CourseMilestonesScreen"
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
	_pick_default_location()

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
			body = _build_shelf_body(DESKTOP_LEDGER_COLUMNS)
		_:
			body = _build_shelf_body(
				PHONE_LEDGER_COLUMNS if _layout_mode == Kit.LayoutMode.PHONE_PORTRAIT
					else NARROW_LEDGER_COLUMNS)
	page.add_child(body)

## Keep the ledger on a real location: the current pick while it is still a
## site the company owns, else the active site, the first owned one, or the
## legacy key the manager falls back to.
func _pick_default_location() -> void:
	var ids := _location_ids()
	if ids.has(_selected_location_id):
		return
	if ids.has(WorldMap.active_location_id):
		_selected_location_id = WorldMap.active_location_id
	elif not ids.is_empty():
		_selected_location_id = ids[0]
	else:
		_selected_location_id = MilestoneManager.LEGACY_LOCATION_KEY

## Owned sites, active first, then by name. The legacy key is only listed
## when the company has no owned site yet (tests and harnesses).
func _location_ids() -> Array:
	var ids: Array = []
	for id in WorldMap.locations:
		if WorldMap.is_owned(str(id)):
			ids.append(str(id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		if a == WorldMap.active_location_id:
			return true
		if b == WorldMap.active_location_id:
			return false
		return _location_name(a) < _location_name(b))
	return ids

func _display_location_ids() -> Array:
	var ids := _location_ids()
	if ids.is_empty() and milestone_manager \
			and milestone_manager.get_location_completion_count(MilestoneManager.LEGACY_LOCATION_KEY) > 0:
		ids = [MilestoneManager.LEGACY_LOCATION_KEY]
	return ids

func _location_name(location_id: String) -> String:
	if location_id == MilestoneManager.LEGACY_LOCATION_KEY:
		return "Your Course"
	var def := WorldLocations.get_definition(location_id)
	return str(def.get("name", location_id))

func _location_region(location_id: String) -> String:
	if location_id == MilestoneManager.LEGACY_LOCATION_KEY:
		return ""
	var def := WorldLocations.get_definition(location_id)
	return str(def.get("region", ""))

## How many holes this site owns: the live course when it is the active one,
## else the course left behind in its world-map snapshot.
func _site_hole_count(location_id: String) -> int:
	if location_id == WorldMap.active_location_id and GameManager.current_course:
		return GameManager.current_course.holes.size()
	var snapshot = WorldMap.location_snapshots.get(location_id, {})
	if snapshot is Dictionary:
		return (snapshot.get("holes", []) as Array).size()
	return 0

# =============================================================================
# HEADER
# =============================================================================

func _build_header() -> Control:
	var compact := Kit.is_phone(_layout_mode)
	var header := HBoxContainer.new()
	header.name = "GoalHeader"
	header.add_theme_constant_override("separation", 10 if not compact else 7)
	header.custom_minimum_size.y = 62.0 if Kit.is_desktop(_layout_mode) else (56.0 if not compact else 48.0)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "‹  Back" if not compact else "‹ Back"
	back.tooltip_text = "Return to the course (Esc)"
	back.custom_minimum_size = Vector2(94.0 if not compact else 72.0, 42.0 if compact else 46.0)
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Kit.paint_utility_button(back, false)
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)

	var title_box := HBoxContainer.new()
	title_box.name = "TitleBlock"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 7 if compact else 9)
	var mark := Kit.make_sprite(PixelIcon.Kind.FLAG, 20 if compact else 28, Kit.COLOR_GOLD)
	mark.name = "TitleMark"
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_child(mark)
	var title := Kit.make_title_label("Course Milestones", 20 if compact else 26)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(title)
	header.add_child(title_box)

	if not compact:
		header.add_child(_build_site_stat_chip())
		var switch := Kit.make_track_switch(Kit.GoalTrack.COURSE,
			func(track: int): track_requested.emit(track))
		switch.size_flags_horizontal = Control.SIZE_SHRINK_END
		header.add_child(switch)
	return header

## The selected site's tally beside the title.
func _build_site_stat_chip() -> PanelContainer:
	var done := 0
	var total := 0
	if milestone_manager:
		done = milestone_manager.get_location_completion_count(_selected_location_id)
		total = milestone_manager.get_location_total_count()
	var chip := Kit.make_panel(Kit.COLOR_SURFACE_RAISED, MenuStyle.with_alpha(Kit.COLOR_MINT, 0.55))
	chip.name = "SiteStat"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 9)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	chip.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var caption := Kit.make_kicker(_location_label(_selected_location_id), 9)
	caption.clip_text = true
	caption.custom_minimum_size.x = 60.0
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(caption)
	var count := Kit.make_count_label(done, total, 15, Kit.COLOR_MINT)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(count)
	return chip

func _location_label(location_id: String) -> String:
	if location_id == MilestoneManager.LEGACY_LOCATION_KEY:
		return "Your Course"
	return _location_name(location_id)

# =============================================================================
# BODY: DESKTOP
# =============================================================================

func _build_desktop_body() -> Control:
	var body := HBoxContainer.new()
	body.name = "DesktopCourseGoals"
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var rail := _build_location_rail()
	rail.custom_minimum_size.x = clampf(_built_size.x * 0.185, 252.0, 320.0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(rail)

	var ledger := _build_ledger_column(DESKTOP_LEDGER_COLUMNS)
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(ledger)
	return body

## The desktop left rail: the site picker over a quiet note about how the
## goal tracks work.
func _build_location_rail() -> Control:
	var rail := VBoxContainer.new()
	rail.name = "LocationRail"
	rail.add_theme_constant_override("separation", 11)

	var panel := Kit.make_panel(Kit.COLOR_SURFACE, MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.42))
	panel.name = "LocationPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 13)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	margin.add_child(stack)

	stack.add_child(Kit.make_kicker("Course milestones", 11))
	var note := Kit.make_label("Each course location unlocks its own milestones again with every new save.",
		11, Kit.COLOR_TEXT_QUIET)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.name = "LocationList"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var chips := VBoxContainer.new()
	chips.name = "LocationChips"
	chips.add_theme_constant_override("separation", 7)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(chips)
	for id in _display_location_ids():
		chips.add_child(_make_location_chip(id, false))

	stack.add_child(_build_tracks_note())
	return rail

## The location picker's cards: name, region and the site's own progress.
func _make_location_chip(location_id: String, compact: bool) -> Button:
	var selected := location_id == _selected_location_id
	var chip := Button.new()
	chip.name = "Location_%s" % location_id
	chip.custom_minimum_size = Vector2(
		168.0 if compact else 0.0,
		52.0 if compact else 58.0)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not compact else 0
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.toggle_mode = true
	chip.button_pressed = selected
	Kit.paint_toggle(chip, Kit.COLOR_MINT)
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 9)
	box.add_child(pad)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	pad.add_child(inner)
	var pin := Kit.make_sprite(PixelIcon.Kind.PIN, 18,
		Kit.COLOR_GOLD if selected else MenuStyle.ACCENT_UTILITY)
	pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(pin)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	var name_label := Kit.make_semibold_label(_location_label(location_id), 12 if compact else 13)
	name_label.clip_text = true
	names.add_child(name_label)
	if not compact:
		var region := Kit.make_label(_location_region(location_id), 10, Kit.COLOR_TEXT_QUIET)
		region.clip_text = true
		names.add_child(region)
	inner.add_child(names)
	var done := 0
	var total := 0
	if milestone_manager:
		done = milestone_manager.get_location_completion_count(location_id)
		total = milestone_manager.get_location_total_count()
	var count := Kit.make_label("%d/%d" % [done, total], 11, Kit.COLOR_TEXT_SECONDARY)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(count)
	chip.add_child(box)
	chip.pressed.connect(func():
		_selected_location_id = location_id
		_build())
	return chip

## The little explainer at the bottom of the location rail.
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

## The selected site's dossier over its milestone ledger: who the site is,
## how far it has come, and every goal it has left to unlock.
func _build_ledger_column(columns: int) -> Control:
	var stack := VBoxContainer.new()
	stack.name = "SiteLedger"
	stack.add_theme_constant_override("separation", 10)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL

	stack.add_child(_build_site_dossier())

	var panel := Kit.make_panel(Kit.COLOR_SURFACE, MenuStyle.with_alpha(Kit.COLOR_MINT, 0.42))
	panel.name = "LocationLedger"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 13)
	panel.add_child(margin)
	var ledger_stack := VBoxContainer.new()
	ledger_stack.add_theme_constant_override("separation", 9)
	margin.add_child(ledger_stack)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var kicker := Kit.make_kicker("The goal book", 11)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(kicker)
	var filter_note := Kit.make_label("%d milestones" % _milestone_count(), 11, Kit.COLOR_TEXT_QUIET)
	filter_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(filter_note)
	ledger_stack.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.name = "LedgerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ledger_stack.add_child(scroll)

	var groups := []
	if milestone_manager:
		groups = Kit.group_entries_by_category(milestone_manager.location_milestones,
			milestone_manager.get_location_completed(_selected_location_id))
	scroll.add_child(Kit.build_category_columns(groups, columns,
		Kit.make_milestone_card,
		"Nothing here yet - build a course to start unlocking milestones."))
	return stack

func _milestone_count() -> int:
	return milestone_manager.get_location_total_count() if milestone_manager else 0

## The site's dossier: name, region, its tally and bar, and the little
## records the milestones are earned from (rounds served, aces, eagles).
func _build_site_dossier() -> Control:
	var compact := Kit.is_phone(_layout_mode)
	var panel := Kit.make_panel(Kit.COLOR_SURFACE, MenuStyle.with_alpha(Kit.COLOR_MINT, 0.55))
	panel.name = "SiteDossier"
	var margin := MarginContainer.new()
	var pad := 14 if not compact else 11
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, pad)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var pin := Kit.make_sprite(PixelIcon.Kind.PIN, 28 if not compact else 22, Kit.COLOR_GOLD)
	pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pin)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 1)
	var kicker := Kit.make_kicker("Course milestones - this site", 10)
	titles.add_child(kicker)
	var site_title := Kit.make_title_label(_location_label(_selected_location_id),
		20 if not compact else 16)
	site_title.clip_text = true
	titles.add_child(site_title)
	var region := Kit.make_label(_location_region(_selected_location_id), 11, Kit.COLOR_TEXT_QUIET)
	region.clip_text = true
	titles.add_child(region)
	row.add_child(titles)

	if not compact:
		row.add_child(_build_site_records())

	var progress := VBoxContainer.new()
	progress.add_theme_constant_override("separation", 3)
	progress.custom_minimum_size.x = 132.0
	var done := 0
	var total := _milestone_count()
	if milestone_manager:
		done = milestone_manager.get_location_completion_count(_selected_location_id)
	var count := Kit.make_count_label(done, total, 16, Kit.COLOR_MINT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.add_child(count)
	var bar := Kit.make_progress_bar(float(done) / maxf(float(total), 1.0), Kit.COLOR_MINT, 9.0)
	bar.name = "SiteProgressBar"
	progress.add_child(bar)
	row.add_child(progress)
	return panel

## The site's little record card: rounds served here, aces, eagles.
func _build_site_records() -> Control:
	var records := HBoxContainer.new()
	records.name = "SiteRecords"
	records.add_theme_constant_override("separation", 8)
	records.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rounds := 0
	var hio := 0
	var eagles := 0
	var holes := _site_hole_count(_selected_location_id)
	if milestone_manager:
		rounds = milestone_manager.get_location_stat(_selected_location_id, "rounds")
		hio = milestone_manager.get_location_stat(_selected_location_id, "hio")
		eagles = milestone_manager.get_location_stat(_selected_location_id, "eagles")
	for part: Array in [["%d holes" % holes, Kit.COLOR_TEXT_SECONDARY],
			["%d rounds" % rounds, Kit.COLOR_TEXT_SECONDARY],
			["%d aces" % hio, Kit.COLOR_GOLD],
			["%d eagles" % eagles, Kit.COLOR_GOLD]]:
		var chip := Kit.make_chip(str(part[0]), (part[1] as Color), UIConstants.COLOR_TEXT, 10)
		records.add_child(chip)
	return records

# =============================================================================
# BODY: SHELF (tablet and phone)
# =============================================================================

## Tablet and phone: the site picker as a horizontal shelf, the site
## dossier under it, then the ledger of cards.
func _build_shelf_body(columns: int) -> Control:
	var body := VBoxContainer.new()
	body.name = "ShelfCourseGoals"
	body.add_theme_constant_override("separation", 8 if Kit.is_phone(_layout_mode) else 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if Kit.is_phone(_layout_mode):
		var switch := Kit.make_track_switch(Kit.GoalTrack.COURSE,
			func(track: int): track_requested.emit(track))
		body.add_child(switch)

	body.add_child(_build_location_chip_shelf())
	var dossier := _build_site_dossier()
	dossier.size_flags_vertical = Control.SIZE_SHRINK_END
	body.add_child(dossier)

	var ledger := _build_ledger_column(columns)
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(ledger)
	return body

## The site picker as a horizontally scrolling shelf of chips.
func _build_location_chip_shelf() -> Control:
	var phone := Kit.is_phone(_layout_mode)
	var shelf := ScrollContainer.new()
	shelf.name = "LocationShelf"
	shelf.size_flags_vertical = Control.SIZE_SHRINK_END
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	shelf.custom_minimum_size.y = 58.0 if phone else 64.0
	var row := HBoxContainer.new()
	row.name = "LocationChips"
	row.add_theme_constant_override("separation", 7)
	shelf.add_child(row)
	var ids := _display_location_ids()
	if ids.is_empty():
		row.add_child(Kit.make_label("Buy a course location to unlock its milestones.",
			11, Kit.COLOR_TEXT_QUIET))
		return shelf
	for id in ids:
		row.add_child(_make_location_chip(id, phone))
	return shelf
