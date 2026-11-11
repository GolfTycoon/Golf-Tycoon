extends GameTest
## ModsScreen: the fullscreen mod library. It sits on the World Map's
## MenuBackdrop and lists every discovered mod in the player's order, which
## is the load order of the enabled ones read from the top down: a row never
## moves when its mod is ticked or unticked, and moves one place when its
## arrows are pressed, whether its mod is enabled or not. The screen narrows
## that list with a search box and the All / Enabled / Disabled filter
## chips, inspects one mod at a time in the field-notes pane, and stages
## toggles and reorders until the player applies them.
## (scripts/ui/mods_screen.gd)
##
## The screen always shows the real ModManager's library, so nothing here
## expects a particular mod on a particular row: what decides the order is
## tested on throwaway libraries in test_mod_manager.gd.
##
## The pure text the rows and details pane are built from is unit-tested
## first; the screen tests walk the built tree and check what it actually
## draws at each window shape.

const DESKTOP := Vector2i(1600, 1000)
const TABLET := Vector2i(820, 720)
const PHONE := Vector2i(390, 720)
const NARROW_PHONE := Vector2i(320, 720)
const PHONE_SIDEWAYS := Vector2i(667, 375)

const ALL := ModsScreen.Filter.ALL
const ENABLED := ModsScreen.Filter.ENABLED
const DISABLED := ModsScreen.Filter.DISABLED

## From the top of one row to the top of the next.
const ROW_PITCH := ModsScreen.ROW_HEIGHT + ModsScreen.ROW_GAP

var _window_before := Vector2i.ZERO
var _listed_before: Array[String] = []
var _loadout_before: Array[String] = []
var _loadout_was_saved := false

func before_each() -> void:
	super()
	_window_before = get_window().size
	_listed_before = ModManager.get_listed_order()
	_loadout_before = ModManager.get_enabled_order()
	_loadout_was_saved = FileAccess.file_exists(ModManager._config_path())

func after_each() -> void:
	_restore_library()
	get_window().size = _window_before
	super()

## The screen edits the real ModManager, so a test that ticks or moves a mod
## would leave it that way for every suite after this one. Put every mod
## back in the place the test found it, tick the ones that were ticked, and
## leave no load_order.json behind where there was none.
func _restore_library() -> void:
	for place in _listed_before.size():
		var mod_id := _listed_before[place]
		ModManager.move_mod(mod_id, place - ModManager.get_listed_order().find(mod_id))
	if ModManager.get_enabled_order() != _loadout_before:
		for mod_id in ModManager.get_enabled_order():
			ModManager.set_mod_enabled(mod_id, false)
		for mod_id in _loadout_before:
			ModManager.set_mod_enabled(mod_id, true)
	if not _loadout_was_saved and FileAccess.file_exists(ModManager._config_path()):
		DirAccess.remove_absolute(ModManager._config_path())

func _screen(size: Vector2i = DESKTOP) -> ModsScreen:
	get_window().size = size
	await process_frames(2)
	var screen := ModsScreen.new()
	add_child_autofree(screen)
	await process_frames(1)
	return screen

func _back_button(screen: ModsScreen) -> Button:
	var header := screen.find_child("ScreenHeader", true, false)
	assert_not_null(header, "the screen wears the shared screen header")
	return header.get_node("BackButton") as Button

## What a click does to a button: a toggle (a tick box, a filter chip) flips
## first, then the press is announced.
func _press(button: BaseButton) -> void:
	if button.toggle_mode:
		button.button_pressed = not button.button_pressed
	button.pressed.emit()

## What a keyboard or a controller sends: one of the engine's UI actions,
## pressed and let go, for whichever control has the focus. "ui_accept" is
## Enter or the A button; "ui_up" and "ui_down" are the arrow keys or the
## D-pad.
func _press_action(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)
		await process_frames(1)

func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()

## Type into the search box the way a player does: the text, then the signal
## the box sends for it.
func _type(screen: ModsScreen, text: String) -> void:
	screen._search.text = text
	screen._search.text_changed.emit(text)

func _chip(screen: ModsScreen, label: String) -> Button:
	return screen.find_child("Filter_" + label, true, false) as Button

func _row(screen: ModsScreen, mod_id: String) -> Control:
	return screen._row_for(mod_id)

func _row_text(screen: ModsScreen, mod_id: String) -> String:
	return (_row(screen, mod_id).get_node("ModName") as Button).text

## Mod ids down the list, top to bottom - every row, or only the ones on show.
func _listed_ids(screen: ModsScreen, only_shown: bool = false) -> Array:
	var ids := []
	for row in screen._rows_box.get_children():
		if row.visible or not only_shown:
			ids.append(str(row.get_meta("mod_id", "")))
	return ids

func _shown_ids(screen: ModsScreen) -> Array:
	return _listed_ids(screen, true)

func _ids_of(infos: Array) -> Array:
	var ids := []
	for info in infos:
		ids.append(str(info.get("id", "")))
	return ids

## The ids the manager lists as ticked (or not), in the list's own order.
func _ids_where(enabled: bool) -> Array:
	var ids := []
	for info in ModManager.get_all_mod_infos():
		if bool(info.get("enabled", false)) == enabled:
			ids.append(str(info.get("id", "")))
	return ids

## The load order as plain ids, to hold against the rows.
func _loadout() -> Array:
	var ids := []
	for mod_id in ModManager.get_enabled_order():
		ids.append(mod_id)
	return ids

func _arrow(screen: ModsScreen, mod_id: String, arrow: String) -> Button:
	return _row(screen, mod_id).get_node(arrow) as Button

## Tick the mods at these places in the list and no others, so a test of the
## order does not hang on which mods the library happens to have switched on
## or where it lists them. Returns their ids. (after_each puts it all back.)
func _tick_only(places: Array) -> Array:
	var listed := ModManager.get_listed_order()
	for mod_id in ModManager.get_enabled_order():
		ModManager.set_mod_enabled(mod_id, false)
	var ids := []
	for place in places:
		ModManager.set_mod_enabled(listed[place], true)
		ids.append(listed[place])
	return ids

## The load order reads down the list: the ticked rows are numbered 1, 2, 3
## from the top, the rest carry no number, and that is the order the manager
## will load them in.
func _assert_the_numbers_run_down_the_list(screen: ModsScreen, context: String) -> void:
	var ticked := []
	for mod_id in _listed_ids(screen):
		var title := _row_text(screen, mod_id)
		if ModManager.is_mod_enabled(mod_id):
			ticked.append(mod_id)
			assert_true(title.begins_with("%d. " % ticked.size()),
				"%s: %s is ticked row number %d from the top" % [context, mod_id, ticked.size()])
		else:
			assert_eq(title, ModsScreen.row_title(ModManager.get_mod_info(mod_id)) + "\n" \
				+ ModsScreen.row_badge(ModManager.get_mod_info(mod_id)).to_upper(),
				"%s: %s is off, and has no number" % [context, mod_id])
			assert_eq(int(ModManager.get_mod_info(mod_id)["order_index"]), -1)
	assert_eq(_loadout(), ticked, "%s: the load order is the ticked rows, top to bottom" % context)

## The arrows that are lit are the ones with somewhere to go: every row on
## show can move up except the first of them, and down except the last.
func _assert_the_arrows_fit_the_rows_on_show(screen: ModsScreen, context: String) -> void:
	var shown := _shown_ids(screen)
	for place in shown.size():
		var mod_id := str(shown[place])
		assert_eq(_arrow(screen, mod_id, "MoveUp").disabled, place == 0,
			"%s: only the first row on show cannot move up (%s)" % [context, mod_id])
		assert_eq(_arrow(screen, mod_id, "MoveDown").disabled, place == shown.size() - 1,
			"%s: only the last row on show cannot move down (%s)" % [context, mod_id])

# ── static text ──────────────────────────────────────────────────────────

func test_row_titles_number_the_load_order() -> void:
	assert_eq(ModsScreen.row_title({"name": "Weather", "version": "1.0.0", "order_index": 0}),
		"1. Weather  1.0.0")
	assert_eq(ModsScreen.row_title({"name": "Off Mod", "version": "2.1", "order_index": -1}),
		"Off Mod  2.1", "a disabled mod has no place in the order")


func test_row_badges_say_the_mod_state() -> void:
	assert_eq(ModsScreen.row_badge({"errors": ["boom"]}), "won't load")
	assert_eq(ModsScreen.row_badge({"errors": [], "loaded": true}), "loaded")
	assert_eq(ModsScreen.row_badge({"errors": [], "loaded": false, "enabled": true}), "pending apply",
		"ticked but not applied is called out, because nothing hot-swaps")
	assert_eq(ModsScreen.row_badge({"errors": [], "loaded": false, "enabled": false, "source": "zip"}),
		"zip", "otherwise the badge says where the mod came from")


func test_details_text_covers_trust_and_provenance_without_session_section() -> void:
	var info := {
		"id": "tester.big", "name": "Big Mod", "version": "1.0.0", "author": "Ada",
		"description": "Does big things.", "source_label": "your mods folder",
		"types": ["gameplay"], "has_script": true,
		"dependencies": ["golf_tycoon.seasons >= 1.0.0"],
		"errors": [], "warnings": ["mind the gaps"],
		"conflicts_declared": [], "workshop_id": 0, "auto_enabled": false,
	}
	var text := ModsScreen.details_text(info,
		["buildings 'snack_bar': written by tester.small, overwritten by tester.big (later in the load order wins)."],
		["[tester.big] Tuning value 'x' is not a number; skipped."])
	assert_true(text.contains("Big Mod") and text.contains("by Ada"))
	assert_true(text.contains("runs code"), "players are told when a mod runs code")
	assert_true(text.contains("Needs: golf_tycoon.seasons >= 1.0.0"))
	assert_true(text.contains("mind the gaps"), "manifest warnings surface")
	assert_true(text.contains("tester.small"), "data conflicts name both sides")
	for removed_text in ["This session", "Weather:", "Wind:", "Seasons:"]:
		assert_false(text.contains(removed_text), "session provider details are not shown")

	assert_true(ModsScreen.details_text({}, [], []).contains("No mod selected"))


func test_filters_split_the_library_by_what_is_ticked() -> void:
	assert_true(ModsScreen.filter_accepts(ALL, true))
	assert_true(ModsScreen.filter_accepts(ALL, false), "All hides nothing")
	assert_true(ModsScreen.filter_accepts(ENABLED, true))
	assert_false(ModsScreen.filter_accepts(ENABLED, false))
	assert_false(ModsScreen.filter_accepts(DISABLED, true))
	assert_true(ModsScreen.filter_accepts(DISABLED, false))


func test_filter_chips_are_named_for_what_they_show() -> void:
	assert_eq(ModsScreen.filter_label(ALL), "All")
	assert_eq(ModsScreen.filter_label(ENABLED), "Enabled")
	assert_eq(ModsScreen.filter_label(DISABLED), "Disabled")
	assert_eq(ModsScreen.filter_label(ALL, true), "All")
	assert_eq(ModsScreen.filter_label(ENABLED, true), "On", "the narrowest row gets the short words")
	assert_eq(ModsScreen.filter_label(DISABLED, true), "Off")
	for filter in [ALL, ENABLED, DISABLED]:
		assert_false(ModsScreen.filter_hint(filter).is_empty(), "every chip explains itself on hover")


func test_the_summary_says_how_much_of_the_library_is_on_show() -> void:
	assert_eq(ModsScreen.summary_text(14, 14, 3, 3), "14 found · 3 enabled · 3 loaded")
	assert_eq(ModsScreen.summary_text(3, 14, 3, 3), "showing 3 of 14 · 3 enabled · 3 loaded",
		"a narrowed list says so, and still counts the whole loadout")
	assert_eq(ModsScreen.summary_text(0, 14, 3, 3), "showing 0 of 14 · 3 enabled · 3 loaded")


func test_an_empty_list_says_why_it_is_empty() -> void:
	assert_eq(ModsScreen.empty_text(ALL, true, 14), "No matching mods. Try another search.")
	assert_true(ModsScreen.empty_text(ENABLED, false, 14).begins_with("No mods are enabled"),
		"nothing ticked is not a failed search")
	assert_true(ModsScreen.empty_text(DISABLED, false, 14).begins_with("No mods are disabled"))
	for filter in [ENABLED, DISABLED]:
		var text := ModsScreen.empty_text(filter, true, 14)
		assert_true(text.contains("search") and text.contains("All filter"),
			"a search under a filter names both ways out")
	for filter in [ALL, ENABLED, DISABLED]:
		assert_true(ModsScreen.empty_text(filter, false, 0).contains("install a zip"),
			"an empty library says how to fill it, whatever the filter")


# ── screen ───────────────────────────────────────────────────────────────

func test_the_screen_sits_on_the_world_map_background() -> void:
	var screen := await _screen()
	assert_eq(screen.anchor_left, 0.0)
	assert_eq(screen.anchor_top, 0.0)
	assert_eq(screen.anchor_right, 1.0)
	assert_eq(screen.anchor_bottom, 1.0)
	var backdrop := screen.find_child("Backdrop", true, false)
	assert_not_null(backdrop, "the screen sits on the shared menu backdrop")
	assert_true(backdrop is MenuBackdrop)
	assert_eq(backdrop.anchor_left, 0.0)
	assert_eq(backdrop.anchor_top, 0.0)
	assert_eq(backdrop.anchor_right, 1.0)
	assert_eq(backdrop.anchor_bottom, 1.0)


func test_the_header_carries_the_mods_title() -> void:
	var screen := await _screen()
	var header := screen.find_child("ScreenHeader", true, false)
	assert_not_null(header)
	var back := _back_button(screen)
	assert_true(back.text.contains("Back"), "Back leads home to the menu")
	var title := header.get_node("TitleBlock/Title") as Label
	assert_eq(title.text, "Mods")
	assert_eq(header.get_node("TitleBlock").get_child_count(), 1,
		"the header contains only the screen title")


func test_the_screen_renders_the_live_library() -> void:
	var screen := await _screen()
	var rows := screen.find_child("ModRows", true, false)
	assert_not_null(rows)
	assert_eq(rows.get_child_count(), ModManager.get_all_mod_infos().size(),
		"one row per discovered mod")
	var seasons_row := rows.get_node_or_null("ModRow_golf_tycoon_seasons")
	assert_not_null(seasons_row, "the bundled Seasons mod is listed")
	var check := seasons_row.get_node_or_null("EnabledCheck") as CheckBox
	assert_true(check.button_pressed, "and shows as enabled, as it ships")
	var details := screen.find_child("ModDetails", true, false) as RichTextLabel
	var first: Dictionary = ModManager.get_all_mod_infos()[0]
	assert_eq(screen._selected_id, str(first.get("id", "")))
	assert_true(details.text.contains(str(first.get("name", ""))),
		"the details pane opens on the first mod in the list")
	var subtitle := screen.find_child("SubtitleLabel", true, false) as Label
	assert_true(subtitle.text.contains("loaded"),
		"the header reports the live counts, not a blank")


func test_workshop_controls_are_not_exposed() -> void:
	var screen := await _screen()
	for node in screen.find_children("*", "Button", true, false):
		assert_false((node as Button).text.to_lower().contains("workshop"),
			"Workshop remains backend-only for now")


func test_selecting_a_mod_updates_the_field_notes() -> void:
	var screen := await _screen()
	var details := screen.find_child("ModDetails", true, false) as RichTextLabel
	assert_not_null(details)
	var first := details.text

	var rows := screen.find_child("ModRows", true, false)
	assert_not_null(rows)
	assert_true(rows.get_child_count() > 1, "need at least two mods to switch selection")

	var target: Button = null
	for row in rows.get_children():
		if str(row.get_meta("mod_id", "")) == screen._selected_id:
			continue
		var btn := row.get_node_or_null("ModName") as Button
		if btn != null:
			target = btn
			break
	assert_not_null(target, "found another mod's name button")
	target.emit_signal("pressed")
	await process_frames(1)
	assert_false(details.text == first, "field notes switched to the selected mod")


func test_search_filters_without_changing_loadout() -> void:
	var screen := await _screen()
	var before := ModManager.get_enabled_order().duplicate()
	screen._search.text = "no_such_mod_2938"
	screen._filter_rows()
	assert_true(screen._empty.visible)
	for row in screen._rows_box.get_children():
		assert_false(row.visible)
	screen._search.text = ""
	screen._filter_rows()
	assert_false(screen._empty.visible)
	assert_eq(ModManager.get_enabled_order(), before)


# ── the list: one order, the player's ────────────────────────────────────

func test_the_rows_are_the_managers_list_from_the_top_down() -> void:
	var screen := await _screen()
	var ids := _ids_of(ModManager.get_all_mod_infos())
	assert_eq(_listed_ids(screen), ids, "the rows are the manager's list, top to bottom")
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	assert_eq(sorted_ids, ModManager.get_installed_mod_ids(),
		"and that list has every discovered mod on it, once")
	_assert_the_numbers_run_down_the_list(screen, "as the screen opens")
	_assert_the_arrows_fit_the_rows_on_show(screen, "as the screen opens")
	await process_frames(1)
	var last_bottom := -INF
	for row in screen._rows_box.get_children():
		assert_gte(row.position.y, last_bottom, "each row stands under the one listed before it")
		last_bottom = row.position.y + row.size.y


func test_rows_are_kept_as_the_library_changes_around_them() -> void:
	var screen := await _screen()
	var rows_before := screen._rows_box.get_children()
	screen.refresh()
	assert_eq(screen._rows_box.get_children(), rows_before,
		"an ordinary refresh repaints the rows it already has")

	# The library as it would be with its first mod taken away...
	var infos: Array = ModManager.get_all_mod_infos()
	var first: Dictionary = infos.pop_front()
	screen._infos = infos
	screen._sync_rows()
	assert_eq(_listed_ids(screen), _ids_of(infos), "a mod that left the library loses its row")
	assert_eq(screen._rows_box.get_children(), rows_before.slice(1),
		"and every other mod keeps the row it had")

	# ...with a mod the player never had before, which is listed last...
	infos.append(first)
	screen._infos = infos
	screen._sync_rows()
	assert_eq(_listed_ids(screen), _ids_of(infos), "a newcomer gets its row at the bottom")
	assert_eq(str(_listed_ids(screen).back()), str(first.get("id", "")))
	assert_eq(screen._rows_box.get_children().slice(0, infos.size() - 1), rows_before.slice(1),
		"under the rows that were there already, which are still the same rows")
	assert_eq(_row_text(screen, str(first.get("id", ""))),
		ModsScreen.row_title(first) + "\n" + ModsScreen.row_badge(first).to_upper(),
		"painted like any other")

	# ...and with the whole list turned upside down.
	var rows_right_way_up := screen._rows_box.get_children()
	infos.reverse()
	screen._infos = infos
	screen._sync_rows()
	rows_right_way_up.reverse()
	assert_eq(_listed_ids(screen), _ids_of(infos), "the rows follow a new order")
	assert_eq(screen._rows_box.get_children(), rows_right_way_up,
		"by moving: each mod still has the row it had")
	# Let the row that was replaced go before the test ends.
	await process_frames(1)


func test_ticking_a_mod_leaves_every_row_where_it_was() -> void:
	var screen := await _screen()
	await process_frames(1)
	var order_before := _listed_ids(screen)
	var rows_before := screen._rows_box.get_children()
	# The last unticked mod in the list is the one that had furthest to jump
	# when ticked mods were gathered at the top.
	var mod_id := str(_ids_where(false).back())
	var row := _row(screen, mod_id)
	var check := row.get_node("EnabledCheck") as CheckBox
	assert_false(check.button_pressed)
	# Focusing the tick box scrolls it into view; measure once that settled.
	check.grab_focus()
	await process_frames(2)
	var place_before := row.get_global_rect()
	var list := screen.find_child("ModList", true, false) as Control
	assert_true(rect_within(place_before, list.get_global_rect()), "the row is on show in the list")

	_press(check)
	await process_frames(1)
	assert_true(ModManager.is_mod_enabled(mod_id), "the tick reached the manager")
	assert_eq(_listed_ids(screen), order_before, "the mod did not jump to the top of the list")
	assert_eq(row.get_global_rect(), place_before, "its row is exactly where it was on screen")
	assert_eq(screen._rows_box.get_children(), rows_before,
		"the rows were repainted where they stand, not rebuilt")
	assert_eq(get_viewport().gui_get_focus_owner(), check,
		"so a keyboard or gamepad player keeps their place on the tick box")
	assert_true(check.button_pressed)
	assert_true(_row_text(screen, mod_id).begins_with("%d. " % (_ids_where(true).find(mod_id) + 1)),
		"the number in front of its name is its place among the ticked rows")
	_assert_the_numbers_run_down_the_list(screen, "after a tick")
	assert_true(_row_text(screen, mod_id).contains("PENDING APPLY"))
	assert_eq(screen._selected_id, mod_id, "its field notes open")
	assert_true(screen._subtitle.text.contains("%d enabled" % ModManager.get_enabled_order().size()),
		"and the counts follow")

	_press(check)
	await process_frames(1)
	assert_false(ModManager.is_mod_enabled(mod_id))
	assert_eq(_listed_ids(screen), order_before, "unticking leaves the row in place as well")
	assert_eq(row.get_global_rect(), place_before)
	assert_false(check.button_pressed)
	assert_false(_row_text(screen, mod_id).contains("PENDING APPLY"), "and takes its number away")
	_assert_the_numbers_run_down_the_list(screen, "after an untick")


func test_a_second_tap_on_the_same_spot_unticks_the_same_mod() -> void:
	# What the list used to get wrong: a ticked mod moved away, a different
	# one slid under the finger, and the next tap hit that one instead.
	var screen := await _screen()
	await process_frames(2)
	var loadout := ModManager.get_enabled_order()
	var unticked := _ids_where(false)
	assert_gt(unticked.size(), 1, "need an unticked mod with another unticked mod above it")
	var mod_id := str(unticked[1])
	var check := _row(screen, mod_id).get_node("EnabledCheck") as CheckBox
	# Wherever the library lists it, focus brings its row into view.
	check.grab_focus()
	await process_frames(2)
	var spot := check.get_global_rect().get_center()
	var list := screen.find_child("ModList", true, false) as Control
	assert_true(list.get_global_rect().has_point(spot), "the tick box is on screen")

	await touch_tap(spot)
	assert_true(ModManager.is_mod_enabled(mod_id), "the first tap ticks the mod under the finger")
	assert_eq(ModManager.get_enabled_order().size(), loadout.size() + 1, "and no other")
	assert_eq(_loadout(), _ids_where(true), "it loads where the list has it, not last for being newest")
	await touch_tap(spot)
	assert_eq(ModManager.get_enabled_order(), loadout,
		"the second tap, on the same spot, unticks that same mod and touches no other")


# ── moving mods up and down the list ─────────────────────────────────────

func test_the_arrows_move_a_mod_up_and_down_the_list_enabled_or_not() -> void:
	# A mod that is switched off, with a row above it and a row below.
	var mod_id := ModManager.get_listed_order()[1]
	ModManager.set_mod_enabled(mod_id, false)
	var screen := await _screen()
	await process_frames(1)
	var everything := _listed_ids(screen)
	var loadout := ModManager.get_enabled_order()
	var place := everything.find(mod_id)
	assert_true(place > 0 and place < everything.size() - 2, "need a row above it and two rows below")
	var below := str(everything[place + 1])
	var row := _row(screen, mod_id)
	var neighbour := _row(screen, below)
	var up := row.get_node("MoveUp") as Button
	var down := row.get_node("MoveDown") as Button
	assert_false(up.disabled or down.disabled, "a mod that is off can be moved like any other")
	# Focus brings the arrow into view wherever the library lists its mod.
	down.grab_focus()
	await process_frames(2)
	var height_before := row.position.y
	var spot := down.get_global_rect().get_center()
	var list := screen.find_child("ModList", true, false) as Control
	assert_true(list.get_global_rect().has_point(spot), "the arrow is on screen")

	await touch_tap(spot)
	var moved := everything.duplicate()
	moved[place] = below
	moved[place + 1] = mod_id
	assert_eq(_listed_ids(screen), moved, "the row went down one place, past the row below it")
	assert_eq(_ids_of(ModManager.get_all_mod_infos()), moved, "in the manager's list as on the screen")
	assert_eq(_row(screen, mod_id), row, "it is the same row, moved - not a new one in its place")
	assert_eq(row.position.y, height_before + ROW_PITCH, "and it stands one row lower in the list")
	assert_eq(neighbour.position.y, height_before, "where it stood, the row from below has come up")
	assert_eq(get_viewport().gui_get_focus_owner(), down,
		"the arrow that was pressed keeps the focus, ready to be pressed again")
	assert_eq(screen._selected_id, mod_id, "its field notes open")
	assert_false(ModManager.is_mod_enabled(mod_id), "moving a mod does not switch it on")
	assert_eq(ModManager.get_enabled_order(), loadout, "and moving one that is off changes nothing that loads")
	_assert_the_arrows_fit_the_rows_on_show(screen, "after a move")

	# With the focus still on that arrow, a keyboard or a pad repeats the move.
	await _press_action("ui_accept")
	await process_frames(1)
	assert_eq(_listed_ids(screen).find(mod_id), place + 2, "Enter on the focused arrow moves the same mod down again")
	assert_eq(row.position.y, height_before + ROW_PITCH * 2)
	assert_eq(get_viewport().gui_get_focus_owner(), down)

	_press(up)
	_press(up)
	await process_frames(2)
	assert_eq(_listed_ids(screen), everything, "the up arrow takes it back")
	assert_eq(row.position.y, height_before)
	assert_eq(neighbour.position.y, height_before + ROW_PITCH)
	assert_eq(_ids_of(ModManager.get_all_mod_infos()), everything)


func test_moving_an_enabled_mod_past_another_changes_the_load_order() -> void:
	# Two enabled mods, with a mod that is off listed between them.
	var ticked := _tick_only([0, 2])
	var first := str(ticked[0])
	var second := str(ticked[1])
	var screen := await _screen()
	await process_frames(1)
	assert_eq(_loadout(), [first, second], "they load in the order they are listed")
	assert_true(_row_text(screen, first).begins_with("1. "))
	assert_true(_row_text(screen, second).begins_with("2. "))
	assert_lt(_row(screen, first).position.y, _row(screen, second).position.y,
		"the first to load stands above the second")
	var down := _arrow(screen, first, "MoveDown")
	var up := _arrow(screen, first, "MoveUp")

	_press(down)
	await process_frames(1)
	assert_eq(_listed_ids(screen).find(first), 1, "one place down, past the mod that is off")
	assert_eq(_loadout(), [first, second], "which changes nothing that loads")
	assert_true(_row_text(screen, first).begins_with("1. "))

	_press(down)
	await process_frames(2)
	assert_eq(_listed_ids(screen).find(first), 2, "another place down, past the other enabled mod")
	assert_eq(_loadout(), [second, first], "and now that one loads first")
	assert_true(_row_text(screen, first).begins_with("2. "), "the numbers follow the rows")
	assert_true(_row_text(screen, second).begins_with("1. "))
	assert_gt(_row(screen, first).position.y, _row(screen, second).position.y,
		"the row itself stands below the row of the mod that loads before it")
	_assert_the_numbers_run_down_the_list(screen, "after moving an enabled mod down")
	var apply := screen.find_child("ApplyButton", true, false) as Button
	assert_eq(apply.disabled, not ModManager.needs_reload, "Apply & Reload follows the manager")

	_press(up)
	_press(up)
	await process_frames(2)
	assert_eq(_listed_ids(screen).find(first), 0)
	assert_eq(_loadout(), [first, second], "moved back up, it loads first again")
	assert_true(_row_text(screen, first).begins_with("1. "))
	_assert_the_numbers_run_down_the_list(screen, "after moving it back")


func test_a_row_moves_past_the_rows_on_show_not_the_hidden_ones() -> void:
	# Three enabled mods; a mod that is off is listed between the first two,
	# and the Enabled filter will hide it.
	var ticked := _tick_only([0, 2, ModManager.get_listed_order().size() - 1])
	var top := str(ticked[0])
	var next := str(ticked[1])
	var screen := await _screen()
	var everything := _listed_ids(screen)
	_press(_chip(screen, "Enabled"))
	var shown := _shown_ids(screen)
	assert_eq(shown, ticked, "the filter shows the three enabled mods")
	var hidden := everything.filter(func(mod_id: String) -> bool: return not mod_id in shown)
	_assert_the_arrows_fit_the_rows_on_show(screen, "under the Enabled filter")
	assert_true(_row_text(screen, top).begins_with("1. "))

	_press(_arrow(screen, top, "MoveDown"))
	await process_frames(1)
	var swapped := shown.duplicate()
	swapped[0] = next
	swapped[1] = top
	assert_eq(_shown_ids(screen), swapped, "one press, one place down the rows on show")
	assert_eq(_loadout(), swapped, "which under this filter is one place later in the load order")
	assert_true(_row_text(screen, top).begins_with("2. "), "the numbers follow")
	assert_true(_row_text(screen, next).begins_with("1. "))
	var listed := _listed_ids(screen)
	assert_eq(listed.find(top), listed.find(next) + 1,
		"in the whole list it stepped over the hidden row too, to stand right under the mod it passed")
	assert_eq(listed.filter(func(mod_id: String) -> bool: return not mod_id in shown), hidden,
		"and the hidden rows keep the order they had")
	_assert_the_arrows_fit_the_rows_on_show(screen, "after a move under the filter")

	# The search narrows the rows on show the same way.
	_press(_chip(screen, "All"))
	_type(screen, top)
	assert_false(_shown_ids(screen).is_empty())
	_assert_the_arrows_fit_the_rows_on_show(screen, "with a search on")
	_type(screen, "")
	assert_eq(_shown_ids(screen), listed)
	_assert_the_arrows_fit_the_rows_on_show(screen, "with the whole library back")
	_assert_the_numbers_run_down_the_list(screen, "with the whole library back")


func test_a_row_that_is_moved_stays_on_show() -> void:
	for size in [DESKTOP, PHONE]:
		var screen := await _screen(size)
		await process_frames(2)
		var at := "at %dx%d" % [size.x, size.y]
		# What scrolls the rows: the list, or the whole page on a phone held upright.
		var scroller := screen.find_child(
			"PhoneModsScroll" if size == PHONE else "ModList", true, false) as ScrollContainer
		assert_not_null(scroller)
		var everything := _listed_ids(screen)
		assert_gt(everything.size() * ROW_PITCH, scroller.size.y,
			"the rows do not all fit, so the list has to scroll %s" % at)
		var mod_id := str(everything[0])
		var row := _row(screen, mod_id)
		assert_true(rect_within(row.get_global_rect(), scroller.get_global_rect()),
			"the first row starts on show %s" % at)
		for press in everything.size() - 1:
			_press(_arrow(screen, mod_id, "MoveDown"))
			await process_frames(2)
			assert_true(rect_within(row.get_global_rect(), scroller.get_global_rect()),
				"the row is still on show after %d presses %s" % [press + 1, at])
		assert_eq(str(_listed_ids(screen).back()), mod_id, "it went the length of the list %s" % at)
		assert_gt(scroller.scroll_vertical, 0, "which the list scrolled to follow %s" % at)
		assert_true(_arrow(screen, mod_id, "MoveDown").disabled, "and at the bottom it can go no further")
		screen.queue_free()
		await process_frames(1)
		_restore_library()


# ── moving mods from a keyboard or a controller ──────────────────────────

func test_the_d_pad_steps_through_the_rows_as_they_stand_after_a_move() -> void:
	InputManager.device = InputManager.Device.GAMEPAD
	var screen := await _screen()
	await process_frames(2)
	var everything := _listed_ids(screen)
	assert_gt(everything.size(), 5, "need a row above the three this is about, and one below")
	var mod_id := str(everything[2])
	var passed := str(everything[3])
	var beyond := str(everything[4])
	var down := _arrow(screen, mod_id, "MoveDown")
	down.grab_focus()
	await process_frames(2)

	await _press_action("ui_accept")
	await process_frames(1)
	assert_eq(_listed_ids(screen).slice(2, 5), [passed, mod_id, beyond],
		"A on the arrow takes its row down one place")
	assert_eq(_focused(), down, "and the focus goes down with it")

	await _press_action("ui_down")
	assert_eq(_focused(), _arrow(screen, beyond, "MoveDown"),
		"Down steps to the row below it now - not back to the row it has just passed")
	await _press_action("ui_up")
	assert_eq(_focused(), down, "Up comes back")
	await _press_action("ui_up")
	assert_eq(_focused(), _arrow(screen, passed, "MoveDown"),
		"and Up again reaches the row it passed, which stands above it now")


func test_an_arrow_that_goes_out_keeps_the_focus_and_the_way_on_from_it() -> void:
	InputManager.device = InputManager.Device.KEYBOARD
	var screen := await _screen()
	await process_frames(2)
	var everything := _listed_ids(screen)
	assert_gt(everything.size(), 3, "need rows between the ends of the list")

	# To the bottom of the list, with the down arrow.
	var mod_id := str(everything[everything.size() - 2])
	var passed := str(everything.back())
	var down := _arrow(screen, mod_id, "MoveDown")
	down.grab_focus()
	await process_frames(2)
	await _press_action("ui_accept")
	await process_frames(1)
	var at_the_bottom := _listed_ids(screen)
	assert_eq(str(at_the_bottom.back()), mod_id, "Enter takes the row to the bottom of the list")
	assert_true(down.disabled, "where its down arrow has nowhere left to go")
	assert_eq(_focused(), down, "the arrow keeps the focus all the same")

	await _press_action("ui_accept")
	await process_frames(1)
	assert_eq(_listed_ids(screen), at_the_bottom, "Enter again moves nothing")
	assert_eq(_focused(), down, "and the focus has not jumped to a button that does something else")

	await _press_action("ui_up")
	assert_eq(_focused(), _arrow(screen, passed, "MoveDown"),
		"Up from the greyed-out arrow steps to the row it passed, the next one up")
	down.grab_focus()
	await process_frames(1)
	await _press_action("ui_left")
	assert_eq(_focused(), _arrow(screen, mod_id, "MoveUp"), "and Left reaches the row's other arrow")

	# To the top of the list, with the up arrow.
	var second := str(at_the_bottom[1])
	var first := str(at_the_bottom[0])
	var up := _arrow(screen, second, "MoveUp")
	up.grab_focus()
	await process_frames(2)
	await _press_action("ui_accept")
	await process_frames(1)
	var at_the_top := _listed_ids(screen)
	assert_eq(str(at_the_top[0]), second, "Enter takes a row to the top of the list")
	assert_true(up.disabled)
	assert_eq(_focused(), up, "and its up arrow keeps the focus there too")
	await _press_action("ui_accept")
	await process_frames(1)
	assert_eq(_listed_ids(screen), at_the_top)
	await _press_action("ui_down")
	assert_eq(_focused(), _arrow(screen, first, "MoveUp"),
		"Down from it steps to the row it passed, the next one down")


# ── filters ──────────────────────────────────────────────────────────────

func test_the_filter_chips_show_all_enabled_or_disabled_mods() -> void:
	var screen := await _screen()
	var loadout := ModManager.get_enabled_order()
	var everything := _listed_ids(screen)
	var ticked := _ids_where(true)
	var unticked := _ids_where(false)
	assert_false(ticked.is_empty() or unticked.is_empty(), "the shipped set has both kinds")
	var all_chip := _chip(screen, "All")
	var enabled_chip := _chip(screen, "Enabled")
	var disabled_chip := _chip(screen, "Disabled")
	assert_not_null(all_chip)
	assert_not_null(enabled_chip)
	assert_not_null(disabled_chip)
	assert_true(all_chip.button_pressed, "the screen opens on the whole library")
	assert_false(enabled_chip.button_pressed or disabled_chip.button_pressed)
	assert_eq(_shown_ids(screen), everything)
	assert_true(screen._subtitle.text.contains("%d found" % everything.size()))

	_press(enabled_chip)
	assert_eq(_shown_ids(screen), ticked, "only the ticked mods, still in the list's order")
	assert_true(enabled_chip.button_pressed, "the chosen chip is held down")
	assert_false(all_chip.button_pressed or disabled_chip.button_pressed, "and only that one")
	assert_true(screen._subtitle.text.contains("showing %d of %d" % [ticked.size(), everything.size()]),
		"the summary says the list is narrowed")
	assert_false(screen._empty.visible)

	_press(enabled_chip)
	assert_true(enabled_chip.button_pressed, "pressing the chosen chip again does not release it")
	assert_eq(_shown_ids(screen), ticked)

	_press(disabled_chip)
	assert_eq(_shown_ids(screen), unticked, "the rest of the library")
	assert_true(disabled_chip.button_pressed)
	assert_false(all_chip.button_pressed or enabled_chip.button_pressed)

	_press(all_chip)
	assert_eq(_shown_ids(screen), everything)
	assert_true(all_chip.button_pressed)
	assert_eq(_listed_ids(screen), everything, "filtering hides rows; it never reorders them")
	assert_eq(ModManager.get_enabled_order(), loadout, "and never changes the loadout")


func test_the_filter_and_the_search_narrow_the_list_together() -> void:
	var screen := await _screen()
	var ticked_id := str(_ids_where(true)[0])
	var unticked_id := str(_ids_where(false)[0])

	_press(_chip(screen, "Enabled"))
	_type(screen, ticked_id)
	assert_eq(_shown_ids(screen), [ticked_id], "an enabled mod, found by its id")
	assert_false(screen._empty.visible)

	_type(screen, unticked_id)
	assert_eq(_shown_ids(screen), [], "the search finds a mod the filter rules out")
	assert_true(screen._empty.visible, "so the list explains itself")
	assert_eq(screen._empty.text,
		ModsScreen.empty_text(ENABLED, true, screen._rows_box.get_child_count()))
	assert_true(screen._subtitle.text.contains("showing 0 of"))

	_press(_chip(screen, "Disabled"))
	assert_eq(_shown_ids(screen), [unticked_id], "the search is kept when the filter changes")
	assert_false(screen._empty.visible)

	_type(screen, "  ")
	assert_eq(_shown_ids(screen), _ids_where(false),
		"clearing the search (stray spaces are not a search) leaves the filter in force")


func test_a_row_ticked_under_a_filter_stays_until_a_filter_is_picked() -> void:
	var screen := await _screen()
	var disabled_chip := _chip(screen, "Disabled")
	_press(disabled_chip)
	var shown := _shown_ids(screen)
	var mod_id := str(shown[0])
	var row := _row(screen, mod_id)

	_press(row.get_node("EnabledCheck") as CheckBox)
	await process_frames(1)
	assert_true(ModManager.is_mod_enabled(mod_id))
	assert_true(row.visible, "the row just ticked does not vanish from under the pointer")
	assert_eq(_shown_ids(screen), shown, "so no other row slides up into its place")

	_press(disabled_chip)
	assert_false(row.visible, "picking the filter again sorts the list afresh")
	assert_eq(_shown_ids(screen), _ids_where(false))

	_press(_chip(screen, "Enabled"))
	_press(row.get_node("EnabledCheck") as CheckBox)
	await process_frames(1)
	assert_false(ModManager.is_mod_enabled(mod_id))
	assert_true(row.visible, "the same holds for a mod unticked under Enabled")
	_press(_chip(screen, "All"))
	_press(_chip(screen, "Enabled"))
	assert_false(row.visible, "until the filter is picked again")


func test_the_filter_survives_a_rebuild_for_a_new_window_shape() -> void:
	var screen := await _screen()
	assert_eq(_chip(screen, "All").get_parent().get_parent(), screen._search.get_parent(),
		"on desktop the chips share the search box's row")
	_press(_chip(screen, "Enabled"))
	_type(screen, "o")
	var shown := _shown_ids(screen)
	var old_chip := _chip(screen, "Enabled")

	await resize_window(TABLET)
	assert_false(is_instance_valid(old_chip) and old_chip.is_inside_tree(),
		"the new window shape rebuilt the screen")
	assert_eq(screen._filter, ENABLED, "the filter in force carried over")
	assert_true(_chip(screen, "Enabled").button_pressed, "and its new chip is held down")
	assert_false(_chip(screen, "All").button_pressed)
	assert_eq(screen._search.text, "o", "alongside the search")
	assert_eq(_shown_ids(screen), shown, "so the same rows are on show")
	assert_ne(_chip(screen, "All").get_parent().get_parent(), screen._search.get_parent(),
		"on a tablet the chips take a row of their own under the search box")


func test_a_new_mod_is_never_hidden_by_the_filter() -> void:
	var screen := await _screen()
	_press(_chip(screen, "Enabled"))
	screen._on_mod_created("tester.fresh")
	assert_eq(screen._filter, ALL,
		"a new mod arrives switched off, which the Enabled filter would hide")
	assert_true(_chip(screen, "All").button_pressed)
	assert_false(_chip(screen, "Enabled").button_pressed)
	assert_eq(_shown_ids(screen), _listed_ids(screen))

	# A filter and search that already show the newcomer are left alone.
	var unticked_id := str(_ids_where(false)[0])
	_press(_chip(screen, "Disabled"))
	_type(screen, unticked_id)
	screen._reveal(unticked_id)
	assert_eq(screen._filter, DISABLED)
	assert_eq(screen._search.text, unticked_id)


func test_disable_all_leaves_the_enabled_filter_empty_and_says_so() -> void:
	var screen := await _screen()
	_press(_chip(screen, "Enabled"))
	assert_false(_shown_ids(screen).is_empty())

	screen._on_disable_all_pressed()
	assert_eq(ModManager.get_enabled_order(), [] as Array[String])
	assert_eq(_shown_ids(screen), [], "no ticked mod is left to show")
	assert_true(screen._empty.visible)
	assert_eq(screen._empty.text,
		ModsScreen.empty_text(ENABLED, false, screen._rows_box.get_child_count()))
	await process_frames(2)
	var list := screen.find_child("ModList", true, false) as Control
	assert_true(rect_within(screen._empty.get_global_rect(), list.get_global_rect()),
		"the note sits in the list, where the first row would have been")

	_press(_chip(screen, "Disabled"))
	assert_eq(_shown_ids(screen), _listed_ids(screen), "every mod is unticked now")
	assert_false(screen._empty.visible)


func test_the_filter_chips_fit_the_library_at_every_window_shape() -> void:
	for size in [DESKTOP, TABLET, PHONE_SIDEWAYS, PHONE, NARROW_PHONE]:
		var screen := await _screen(size)
		await process_frames(2)
		var at := "at %dx%d" % [size.x, size.y]
		var library := screen._library.get_global_rect()
		var right_edge := 0.0
		for label in ["All", "Enabled", "Disabled"]:
			var chip := _chip(screen, label)
			assert_not_null(chip, "the %s chip is built %s" % [label, at])
			var rect := chip.get_global_rect()
			assert_true(rect_within(rect, library), "the %s chip is inside the library panel %s" % [label, at])
			assert_true(rect.position.x >= 0.0 and rect.end.x <= float(size.x),
				"and inside the window %s" % at)
			assert_gte(rect.position.x, right_edge, "the chips do not overlap %s" % at)
			assert_false(chip.text.is_empty())
			right_edge = rect.end.x
		assert_gte(screen._search.size.x, ModsScreen.MIN_SEARCH_WIDTH,
			"the search box keeps room to type %s" % at)
		assert_true(rect_within(screen._search.get_global_rect(), library),
			"and stays inside the library panel %s" % at)
		screen.queue_free()
		await process_frames(1)


func test_mobile_panes_are_switchable_and_desktop_shows_both() -> void:
	var screen := await _screen(PHONE)
	assert_not_null(screen._tabs, "phone portrait shows the pane tabs")
	assert_true(screen._tabs.visible)
	assert_true(screen._library.visible)
	assert_false(screen._inspector.visible)
	screen._inspect_mobile = true
	screen._update_panes()
	assert_false(screen._library.visible)
	assert_true(screen._inspector.visible)
	screen._inspect_mobile = false
	screen._update_panes()
	assert_true(screen._library.visible)
	assert_false(screen._inspector.visible)

	var desktop := await _screen(DESKTOP)
	assert_null(desktop._tabs, "desktop shows both panes, no tabs")
	assert_true(desktop._library.visible)
	assert_true(desktop._inspector.visible)


func test_the_screen_fits_narrow_windows_without_overflow() -> void:
	for size in [DESKTOP, TABLET, PHONE, NARROW_PHONE]:
		var screen := await _screen(size)
		await process_frames(2)
		assert_lte(screen.get_combined_minimum_size().x, float(size.x),
			"no horizontal overflow at %dx%d" % [size.x, size.y])
		# The screen itself is a plain Control and asks for nothing; the page
		# inside it is what would spill past the window's edge.
		var frame := screen.get_node("Frame") as Control
		assert_lte(frame.get_combined_minimum_size().x, float(size.x),
			"the page is no wider than the window at %dx%d" % [size.x, size.y])


func test_the_back_button_requests_back() -> void:
	var screen := await _screen()
	var calls := []
	screen.back_requested.connect(func(): calls.push_back(true))
	_back_button(screen).emit_signal("pressed")
	assert_true(calls.has(true))


func test_escape_requests_back() -> void:
	var screen := await _screen()
	var calls := []
	screen.back_requested.connect(func(): calls.push_back(true))
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	screen._unhandled_input(esc)
	assert_true(calls.has(true))


func test_the_apply_button_stages_a_reload() -> void:
	var screen := await _screen()
	var apply := screen.find_child("ApplyButton", true, false)
	assert_not_null(apply, "Apply & Reload is the headline action")
	assert_eq(apply.disabled, not ModManager.needs_reload)


func test_create_new_mod_opens_the_scaffold_form() -> void:
	var screen := await _screen()
	var tools := screen.find_child("ToolsScroll", true, false)
	assert_not_null(tools, "the tool row scrolls so every action stays reachable")
	var button := screen.find_child("CreateModButton", true, false) as Button
	assert_not_null(button, "the library has a Create New Mod action")
	assert_true(button.text.contains("Create New Mod"))
	button.emit_signal("pressed")
	await process_frames(1)
	var dialog := screen.find_child("CreateModDialog", true, false)
	assert_not_null(dialog, "the button opens the creation form")
	assert_true(dialog is CreateModDialog)
	var cancel := dialog.find_child("CancelButton", true, false) as Button
	assert_not_null(cancel)
	cancel.emit_signal("pressed")
	await process_frames(2)
	assert_null(screen.find_child("CreateModDialog", true, false),
		"cancelling returns to the library")


func test_a_created_mod_is_selected_and_announced_as_still_off() -> void:
	var screen := await _screen()
	screen._search.text = "something else"
	screen._on_mod_created("tester.fresh")
	assert_eq(screen._selected_id, "tester.fresh")
	assert_true(screen._status.text.contains("Created tester.fresh"))
	assert_true(screen._status.text.contains("still off"))
	assert_eq(screen._search.text, "",
		"a search from before does not hide the new row")


func test_the_form_reports_a_created_mod_to_the_screen() -> void:
	var screen := await _screen()
	var button := screen.find_child("CreateModButton", true, false) as Button
	button.emit_signal("pressed")
	await process_frames(1)
	var dialog := screen.find_child("CreateModDialog", true, false)
	assert_not_null(dialog)
	dialog.created.emit("tester.wired")
	await process_frames(1)
	assert_eq(screen._selected_id, "tester.wired",
		"the screen opens the new mod's field notes")
	assert_true(screen._status.text.contains("Created tester.wired"))
