extends GameTest
## The Course Map's composition: the breakpoints, and which shape gets which
## arrangement of map, mode chooser and panel.
##
## The screen needs no course to build - with no terrain grid the map draws
## nothing and every panel says so in its own words, which is exactly the state
## these check. What is checked here is the furniture: the tabs, the rail, the
## porthole-sized sheet and the strip under the map.

const MODE_LAND := CourseMapView.Mode.LAND
const MODE_ROUTING := CourseMapView.Mode.ROUTING
const MODE_AURA := CourseMapView.Mode.AURA
const MODE_STAFF := CourseMapView.Mode.STAFF


## A Course Map filling a `view`-sized holder, so a shape can be built without a
## window. The holder is freed with the test.
func _screen_at(view: Vector2) -> CourseMapScreen:
	var holder := Control.new()
	add_child_autofree(holder)
	holder.size = view
	var screen := CourseMapScreen.new()
	holder.add_child(screen)
	await process_frames(2)
	return screen


## Resize the window the screen is sitting in and let it re-arrange itself.
func _resize(holder: Control, view: Vector2) -> void:
	holder.size = view
	await process_frames(3)


# ---------------------------------------------------------------------------
# Breakpoints
# ---------------------------------------------------------------------------

func test_desktop_windows_get_the_tab_bar_and_a_side_panel() -> void:
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(1600, 1000)), MenuScreenKit.LayoutMode.DESKTOP)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(1280, 800)), MenuScreenKit.LayoutMode.DESKTOP)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(1920, 1080)), MenuScreenKit.LayoutMode.DESKTOP)


func test_tablet_orientation_chooses_between_the_rail_and_the_sheet() -> void:
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(1024, 768)), MenuScreenKit.LayoutMode.TABLET_LANDSCAPE)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(768, 1024)), MenuScreenKit.LayoutMode.TABLET_PORTRAIT)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(700, 900)), MenuScreenKit.LayoutMode.TABLET_PORTRAIT)


func test_phone_landscape_gets_the_compact_rail_and_sheet() -> void:
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(844, 390)), MenuScreenKit.LayoutMode.PHONE_LANDSCAPE)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(640, 360)), MenuScreenKit.LayoutMode.PHONE_LANDSCAPE)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(1920, 500)), MenuScreenKit.LayoutMode.PHONE_LANDSCAPE)


func test_phone_portrait_gets_the_bottom_sheet() -> void:
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(390, 844)), MenuScreenKit.LayoutMode.PHONE_PORTRAIT)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(320, 568)), MenuScreenKit.LayoutMode.PHONE_PORTRAIT)
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(600, 900)), MenuScreenKit.LayoutMode.PHONE_PORTRAIT)


func test_a_short_window_never_gets_the_desktop_composition() -> void:
	assert_eq(CourseMapScreen.layout_mode_for(Vector2(1200, 650)), MenuScreenKit.LayoutMode.TABLET_LANDSCAPE)
	assert_ne(CourseMapScreen.layout_mode_for(Vector2(1600, 600)), MenuScreenKit.LayoutMode.DESKTOP)


# ---------------------------------------------------------------------------
# The desktop composition
# ---------------------------------------------------------------------------

func test_the_desktop_screen_shows_the_tabs_the_map_and_the_panel_beside_it() -> void:
	var screen := await _screen_at(Vector2(1600, 1000))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.DESKTOP)
	assert_null(screen._rail_stack, "the modes are tabs across the top, not a rail")
	assert_not_null(screen._tab_row)
	assert_eq(screen._tab_buttons.size(), CourseMapScreen.MODES.size(), "one tab per mode")
	assert_not_null(screen._panel_column, "the dossier panel sits beside the map")
	assert_null(screen._sheet, "the desktop has no use for a sheet")


func test_the_desktop_map_and_panel_share_the_body() -> void:
	var screen := await _screen_at(Vector2(1600, 1000))
	var body: BoxContainer = screen._map_column.get_parent()
	assert_true(body is HBoxContainer, "a wide screen puts the map and the panel side by side")
	assert_eq(screen._panel_column.get_parent(), body)
	assert_true(screen._map_column.size.x > float(CourseMapScreen.PANEL_WIDTH_DESKTOP),
		"the map keeps the rest of the width")


func test_company_cash_is_shown_with_the_map() -> void:
	GameManager.money = 234500
	var screen := await _screen_at(Vector2(1600, 1000))
	assert_not_null(screen._money_label)
	assert_eq(screen._money_label.text, "$234,500")


# ---------------------------------------------------------------------------
# Modes and their panels
# ---------------------------------------------------------------------------

func test_the_four_modes_are_distinct_and_in_the_order_the_map_draws_them() -> void:
	var modes: Array = []
	for entry in CourseMapScreen.MODES:
		modes.append(int(entry["mode"]))
	assert_eq(modes, [MODE_LAND, MODE_ROUTING, MODE_AURA, MODE_STAFF])
	var names: Array = []
	for entry in CourseMapScreen.MODES:
		names.append(str(entry["name"]))
	assert_eq(names, ["Land", "Routing", "Aura", "Staff"])


func test_each_mode_shows_its_own_panel_and_lights_its_own_tab() -> void:
	var screen := await _screen_at(Vector2(1600, 1000))
	var panels: Array = [
		{"mode": MODE_LAND, "panel": screen._land_panel},
		{"mode": MODE_ROUTING, "panel": screen._routing_panel},
		{"mode": MODE_AURA, "panel": screen._aura_panel},
		{"mode": MODE_STAFF, "panel": screen._staff_panel},
	]
	for i in panels.size():
		screen.set_mode(int(panels[i]["mode"]))
		await process_frames(1)
		assert_eq(screen.mode, int(panels[i]["mode"]))
		assert_eq(screen.map.mode, int(panels[i]["mode"]), "the map follows the mode")
		for j in panels.size():
			assert_eq(screen._tab_buttons[j].button_pressed, i == j,
				"only the current mode's tab is picked")
		var active: Control = panels[i]["panel"]
		assert_true(active.visible, "the mode's panel is shown")
		assert_eq(active.get_parent(), screen._panel_scroll)


func test_switching_mode_puts_away_what_the_last_one_had_picked() -> void:
	var screen := await _screen_at(Vector2(1600, 1000))
	screen._select("parcel", Vector2i(1, 1))
	assert_false(screen.selection.is_empty())
	screen.set_mode(MODE_STAFF)
	assert_true(screen.selection.is_empty(), "a pick from another mode means nothing here")
	assert_true(screen.map.selection.is_empty(), "the map's highlight goes with it")


func test_the_strip_says_what_the_mode_is_about_before_anything_is_picked() -> void:
	var screen := await _screen_at(Vector2(1600, 1000))
	for entry in CourseMapScreen.MODES:
		screen.set_mode(int(entry["mode"]))
		await process_frames(1)
		assert_true(screen._strip_label.text.begins_with(str(entry["blurb"]).substr(0, 12)),
			"the strip names the mode: %s" % screen._strip_label.text)
		assert_eq(screen._strip_actions.get_child_count(), 0, "and offers nothing yet")


func test_the_legend_is_about_the_mode_the_map_is_in() -> void:
	var screen := await _screen_at(Vector2(1600, 1000))
	for entry in CourseMapScreen.MODES:
		screen.set_mode(int(entry["mode"]))
		var entries: Array = screen.map.legend_entries()
		assert_gte(entries.size(), 3, "every mode has a colour key")
		for legend_entry in entries:
			assert_false(str(legend_entry["label"]).is_empty())


# ---------------------------------------------------------------------------
# Tablet and phone compositions
# ---------------------------------------------------------------------------

func test_the_tablet_landscape_puts_the_modes_on_a_rail_and_can_fold_the_panel() -> void:
	var screen := await _screen_at(Vector2(1024, 768))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.TABLET_LANDSCAPE)
	assert_null(screen._tab_row, "the modes are on a rail, not in the top bar")
	assert_not_null(screen._rail_stack)
	assert_eq(screen._rail_stack.get_child_count(), CourseMapScreen.MODES.size())
	assert_not_null(screen._panel_column)
	assert_not_null(screen._panel_toggle, "the tablet can hand the map the whole width")
	screen._toggle_fold()
	await process_frames(1)
	assert_false(screen._panel_column.visible)
	assert_eq(screen._panel_toggle.text, "Show")
	screen._toggle_fold()
	await process_frames(1)
	assert_true(screen._panel_column.visible)


func test_the_tablet_portrait_stacks_the_panel_under_the_map() -> void:
	var screen := await _screen_at(Vector2(768, 1024))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.TABLET_PORTRAIT)
	assert_not_null(screen._tab_row, "a portrait tablet keeps the tabs")
	assert_null(screen._rail_stack)
	assert_null(screen._sheet, "the sheet is for phones; the tablet stacks its panel")
	var body: BoxContainer = screen._map_column.get_parent()
	assert_true(body is VBoxContainer, "the panel sits under the map")
	assert_eq(screen._panel_column.get_parent(), body)


func test_the_phone_landscape_slides_the_panel_in_over_the_map() -> void:
	var screen := await _screen_at(Vector2(844, 390))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.PHONE_LANDSCAPE)
	assert_not_null(screen._rail_stack, "height is what a landscape phone has least of")
	assert_not_null(screen._sheet)
	assert_false(screen._sheet.visible, "the panel starts out of the way")
	assert_eq(screen._strip.get_parent(), screen._map_column, "the strip stays under the map")
	screen._toggle_sheet()
	await process_frames(1)
	assert_true(screen._sheet.visible, "Details slides the panel in")
	assert_true(screen._sheet_scrim.visible, "with a scrim to tap away")
	screen._set_sheet_open(false)
	await process_frames(1)
	assert_false(screen._sheet.visible)
	assert_false(screen._sheet_scrim.visible)


func test_the_phone_portrait_keeps_the_strip_in_view_while_the_sheet_peeks() -> void:
	var screen := await _screen_at(Vector2(390, 844))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.PHONE_PORTRAIT)
	assert_not_null(screen._tab_row)
	assert_not_null(screen._sheet)
	assert_true(screen._sheet.visible, "the handle peeks along the bottom edge")
	assert_eq(screen._sheet.custom_minimum_size.y, CourseMapScreen.SHEET_PEEK_HEIGHT)
	assert_eq(screen._strip.get_parent(), screen._map_column,
		"the strip is not hidden behind the peeking sheet")
	screen._toggle_sheet()
	await process_frames(1)
	assert_almost_eq(screen._sheet.custom_minimum_size.y, 844.0 * CourseMapScreen.SHEET_LIFT_RATIO, 1.0,
		"lifting the sheet gives the panel half the screen")


## Resizing the game window while the map is up re-arranges the furniture around
## the map and the panels, which have to survive it: the map keeps the view the
## player had, and the panels keep their words (and their connections).
func test_resizing_the_window_keeps_the_map_and_the_panels() -> void:
	var holder := Control.new()
	add_child_autofree(holder)
	holder.size = Vector2(1600, 1000)
	var screen := CourseMapScreen.new()
	holder.add_child(screen)
	await process_frames(2)
	var map := screen.map
	var land := screen._land_panel
	screen._select("parcel", Vector2i(1, 1))
	var picked := screen.selection.duplicate()

	# A tablet portrait, then a phone on its side, then back: every shape the
	# screen knows, and the panels are carried through all of them.
	await _resize(holder, Vector2(768, 1024))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.TABLET_PORTRAIT, "the window reshaped the map")
	await _resize(holder, Vector2(900, 420))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.PHONE_LANDSCAPE)
	await _resize(holder, Vector2(1600, 1000))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.DESKTOP)

	assert_true(is_instance_valid(map), "the map survived every reshape")
	assert_eq(screen.map, map, "and it is the same control, so the view is unchanged")
	assert_true(is_instance_valid(screen._land_panel), "the land panel is still there")
	assert_eq(screen._land_panel, land, "the one built with the screen, not a new one")
	for panel in screen._mode_panels():
		assert_true(is_instance_valid(panel), "every mode panel survived the reshape")
	assert_eq(screen.selection, picked, "and the map kept what was picked")
	assert_eq(screen._panel_for_mode().get_parent(), screen._panel_scroll,
		"the current mode's panel is back in the frame")

	# The panels that are not the current mode's are parked on the screen rather
	# than left floating, so nothing outlives the screen.
	for panel in screen._mode_panels():
		if panel != screen._panel_for_mode():
			assert_eq(panel.get_parent(), screen, "a panel out of the frame rides along with the screen")


func test_a_small_screen_asks_the_map_for_the_smaller_texture() -> void:
	var small := await _screen_at(Vector2(390, 844))
	var desktop := await _screen_at(Vector2(1600, 1000))
	assert_eq(small.map._texture_side, CourseMapView.COMPACT_TEXTURE_SIDE)
	assert_eq(desktop.map._texture_side, CourseMapView.TEXTURE_SIDE)


# ---------------------------------------------------------------------------
# The words
# ---------------------------------------------------------------------------

func test_money_reads_with_thousands_separators() -> void:
	assert_eq(CourseMapStyle.money(0), "$0")
	assert_eq(CourseMapStyle.money(999), "$999")
	assert_eq(CourseMapStyle.money(1000), "$1,000")
	assert_eq(CourseMapStyle.money(1234567), "$1,234,567")
	assert_eq(CourseMapStyle.money(-2500), "-$2,500")


func test_short_money_keeps_a_crowded_row_readable() -> void:
	assert_eq(CourseMapStyle.short_money(950), "$950")
	assert_eq(CourseMapStyle.short_money(12500), "$13K", "rounded to the nearest thousand")
	assert_eq(CourseMapStyle.short_money(2400000), "$2.4M")


func test_an_aura_colour_runs_from_happy_through_mixed_to_unhappy() -> void:
	assert_eq(CourseMapView.aura_color(1.0), CourseMapView.AURA_HAPPY)
	assert_eq(CourseMapView.aura_color(-1.0), CourseMapView.AURA_UNHAPPY)
	assert_eq(CourseMapView.aura_color(0.0), CourseMapView.AURA_MIXED)
	var warm := CourseMapView.aura_color(0.5)
	assert_gt(warm.g, warm.r, "half-way happy is still greener than it is red")


## The scorecard must fit the narrowest map dossier without a horizontal
## scrollbar, even for 18 holes and long course/record names. Exercise the actual
## composition rather than just the breakpoint helper, including rotation while
## the scorecard and a map selection are already open.
func test_the_scorecard_fits_and_remains_reachable_in_every_composition() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.course_name = "The Remarkably Long Sandbelt Championship Golf Course"
	GameManager.course_records = CourseRecords.create_empty_records()
	GameManager.hole_statistics.clear()
	for number in range(1, 19):
		var hole := make_hole(number, Vector2i(number, 0), Vector2i(number, 5), 4)
		hole.distance_yards = 350 + number
		hole.stroke_index = number
		GameManager.current_course.add_hole(hole)
		GameManager.course_records["best_per_hole"][number] = CourseRecords.RecordEntry.new(
			"Alexandria Longgolfername Visitor %d" % number, 3, 1, number)

	var screen := await _screen_at(Vector2(1600, 1000))
	var holder := screen.get_parent() as Control
	screen.show_scorecard()
	screen._select("hole", 1)
	await process_frames(3)
	for dimensions in [Vector2(1600, 1000), Vector2(1024, 768), Vector2(768, 1024),
			Vector2(640, 360), Vector2(320, 568)]:
		await _resize(holder, dimensions)
		screen.show_scorecard()
		await process_frames(6)
		var scroll := screen._panel_scroll
		var card := screen._routing_panel._scorecard
		var row := card.find_child("HoleRow1", true, false) as HBoxContainer
		assert_true(screen.is_scorecard_showing(), "%s: scorecard is visible" % dimensions)
		assert_eq(screen.mode, MODE_ROUTING)
		assert_eq(int(screen.selection.get("value", -1)), 1, "The selected hole survives rotation")
		assert_true((row.get_child(0) as Button).button_pressed)
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
		assert_lte(card.get_combined_minimum_size().x, scroll.size.x,
			"%s: even long names do not force a wider dossier" % dimensions)
		var right := scroll.get_global_rect().end.x
		if scroll.get_v_scroll_bar().visible:
			right = scroll.get_v_scroll_bar().get_global_rect().position.x
		assert_lte(row.get_global_rect().end.x, right + 1.0,
			"%s: all five columns fit inside the visible panel" % dimensions)
		for i in range(1, row.get_child_count()):
			var previous := row.get_child(i - 1) as Control
			var current := row.get_child(i) as Control
			assert_lte(previous.get_global_rect().end.x, current.get_global_rect().position.x + 1.0,
				"%s: scorecard columns do not overlap" % dimensions)
		assert_gt(scroll.get_v_scroll_bar().max_value, scroll.get_v_scroll_bar().page,
			"%s: the long card and records scroll together" % dimensions)
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await process_frames(3)
		var last_record: Label = null
		for label in card.find_child("RecordLines", true, false).find_children("*", "Label", true, false):
			if (label as Label).text.contains("Visitor 18"):
				last_record = label
		assert_not_null(last_record, "The last record is present")
		if last_record != null:
			assert_lte(last_record.get_global_rect().end.y, scroll.get_global_rect().end.y + 1.0,
				"%s: the last record can be scrolled into view" % dimensions)


func test_tournament_scorecard_is_read_only() -> void:
	GameManager.is_tournament_mode = true
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.current_course.add_hole(make_hole(1, Vector2i.ZERO, Vector2i(0, 5), 4))
	var screen := await _screen_at(Vector2(1600, 1000))
	screen.show_scorecard()
	assert_eq(screen.mode, MODE_ROUTING)
	assert_true(screen._routing_panel.read_only)
	assert_eq(screen._routing_panel.page, CourseMapRoutingPanel.Page.SCORECARD)
	assert_true(screen._routing_panel._routing_button.disabled, "Tournament cannot expose course edits")
	assert_false(screen._routing_panel._scorecard_back.visible)
	for button in screen._tab_buttons:
		assert_eq(button.disabled, button.name != "Mode_Routing", "Only the scorecard's map mode is available")
	screen.set_mode(MODE_LAND)
	screen._routing_panel.set_page(CourseMapRoutingPanel.Page.ROUTING)
	assert_eq(screen.mode, MODE_ROUTING)
	assert_eq(screen._routing_panel.page, CourseMapRoutingPanel.Page.SCORECARD)


func test_scorecard_shortcut_reveals_a_folded_dossier_and_survives_rotation() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.current_course.add_hole(make_hole(1, Vector2i.ZERO, Vector2i(0, 5), 4))
	var screen := await _screen_at(Vector2(1024, 768))
	var holder := screen.get_parent() as Control
	screen._toggle_fold()
	assert_true(screen.panel_hidden)
	assert_false(screen._panel_column.visible)
	screen.show_scorecard()
	assert_false(screen.panel_hidden, "The shortcut unfolds a hidden tablet dossier")
	assert_true(screen._panel_column.visible)
	assert_true(screen.is_scorecard_showing())

	screen._toggle_fold()
	await _resize(holder, Vector2(320, 568))
	assert_false(screen.panel_hidden, "The tablet fold does not hide the phone sheet")
	screen.show_scorecard()
	await process_frames(3)
	assert_true(screen.sheet_open)
	assert_true(screen.is_scorecard_showing())
	assert_string_contains(screen._sheet_title.text, "Scorecard")
	await _resize(holder, Vector2(1600, 1000))
	assert_null(screen._sheet, "The old phone sheet is no longer a live frame")
	assert_true(screen.is_scorecard_showing(), "The scorecard stays open on desktop")
