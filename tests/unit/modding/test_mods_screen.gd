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

## The library these tests run against is a player's after a Browse Mods
## session: every published package downloaded into the library and waiting
## (the game no longer bundles mods, so a fresh boot finds an empty library
## and the screen tests need rows to tick, drag and filter). Installed the
## same way the Browse screen installs - zips through ModPackage - and
## removed again after the suite.
const PACKAGES_ROOT := "res://repository/packages"

const ALL := ModsScreen.Filter.ALL
const ENABLED := ModsScreen.Filter.ENABLED
const DISABLED := ModsScreen.Filter.DISABLED

## From the top of one row to the top of the next.
const ROW_PITCH := ModsScreen.ROW_HEIGHT + ModsScreen.ROW_GAP

var _window_before := Vector2i.ZERO
var _listed_before: Array[String] = []
var _loadout_before: Array[String] = []
var _loadout_was_saved := false
var _library_was_saved := false
## What this suite installed into the real library, removed again after.
var _fixture_ids: Array[String] = []

func before_all() -> void:
	_populate_library()

func after_all() -> void:
	_take_library_back()

func before_each() -> void:
	super()
	_window_before = get_window().size
	_listed_before = ModManager.get_listed_order()
	_loadout_before = ModManager.get_enabled_order()
	_loadout_was_saved = FileAccess.file_exists(ModManager._config_path())
	_library_was_saved = FileAccess.file_exists(ModManager._library_order_path())

func after_each() -> void:
	_restore_library()
	get_window().size = _window_before
	super()

## Install every repository package the player has not already got, as the
## Browse Mods screen would: pack the package, unpack it into the library,
## rescan. Idempotent, so a half-cleaned earlier run does not pile up.
func _populate_library() -> void:
	var dir := DirAccess.open(PACKAGES_ROOT)
	dir.list_dir_begin()
	var entry := dir.get_next()
	var scratch := "user://ut_mods_screen_fixture.zip"
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with(".") and not entry.begins_with("_"):
			var packed: Dictionary = ModPackage.pack_folder(
				PACKAGES_ROOT.path_join(entry), scratch)
			if not bool(packed.get("ok", false)):
				push_error("fixture pack failed for " + entry)
			else:
				var installed: Dictionary = ModPackage.install_zip(
					scratch, ModManager.user_root.path_join("installed"))
				if bool(installed.get("ok", false)):
					_fixture_ids.append(str(installed.get("mod_id", "")))
			DirAccess.remove_absolute(scratch)
		entry = dir.get_next()
	dir.list_dir_end()
	ModManager.discover()

func _take_library_back() -> void:
	# Unload the fixture set before its files go: deleting a loaded mod's
	# folder would leave the manager holding a record it can never reload.
	for mod_id in _fixture_ids:
		ModManager.set_mod_enabled(mod_id, false)
	ModManager.reload_mods()
	for mod_id in _fixture_ids:
		var installed_root := ModManager.user_root.path_join("installed").path_join(mod_id)
		if DirAccess.dir_exists_absolute(installed_root):
			ModPackage.remove_directory_recursive(installed_root)
	_fixture_ids.clear()
	ModManager.discover()

## The screen edits the real ModManager, so a test that ticks or moves a mod
## would leave it that way for every suite after this one. Put every mod
## back in the place the test found it, tick the ones that were ticked, and
## leave no load_order.json or library_order.json behind where there was none.
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
	if not _library_was_saved and FileAccess.file_exists(ModManager._library_order_path()):
		DirAccess.remove_absolute(ModManager._library_order_path())

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

func _grip(screen: ModsScreen, mod_id: String) -> Control:
	return _row(screen, mod_id).get_node("DragHandle") as Control

func _mouse_down(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var hover := InputEventMouseMotion.new()
	hover.position = pos
	hover.global_position = pos
	get_viewport().push_input(hover, true)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = pos
	press.global_position = pos
	get_viewport().push_input(press, true)

func _mouse_move(from: Vector2, to: Vector2, steps: int = 6) -> void:
	for step in range(1, steps + 1):
		var at := from.lerp(to, float(step) / float(steps))
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.relative = (to - from) / float(steps)
		get_viewport().push_input(motion, true)
		await process_frames(1)

func _mouse_up(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = pos
	release.global_position = pos
	get_viewport().push_input(release, true)
	await process_frames(1)

func _mouse_drag(from: Vector2, to: Vector2, steps: int = 6) -> void:
	_mouse_down(from)
	await _mouse_move(from, to, steps)
	await _mouse_up(to)

func _touch_drag(from: Vector2, to: Vector2, steps: int = 6) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = from
	get_viewport().push_input(down, true)
	for step in range(1, steps + 1):
		var at := from.lerp(to, float(step) / float(steps))
		var drag_ev := InputEventScreenDrag.new()
		drag_ev.index = 0
		drag_ev.position = at
		drag_ev.relative = (to - from) / float(steps)
		get_viewport().push_input(drag_ev, true)
		await process_frames(1)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = to
	get_viewport().push_input(up, true)
	await process_frames(1)

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
	assert_eq(ModsScreen.row_badge({"errors": [], "loaded": false, "enabled": true}), "loads on leave",
		"ticked but not loaded yet is called out, because nothing hot-swaps")
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


func test_target_slot_for_drag_steps_across_midpoints_with_hysteresis() -> void:
	assert_eq(ModsScreen.target_slot_for_drag(0, 200.0, PackedFloat32Array()), 0)
	assert_eq(ModsScreen.target_slot_for_drag(0, 200.0, PackedFloat32Array([100.0])), 0)

	var slots := PackedFloat32Array([100.0, 176.0, 252.0, 328.0])
	# Midpoint between 100 and 176 is 138; with 2px hysteresis it swaps past 140.
	assert_eq(ModsScreen.target_slot_for_drag(0, 100.0, slots), 0)
	assert_eq(ModsScreen.target_slot_for_drag(0, 139.5, slots), 0,
		"holding right on the boundary does not jump early")
	assert_eq(ModsScreen.target_slot_for_drag(0, 141.0, slots), 1,
		"past the midpoint and hysteresis, the row claims the next slot")
	assert_eq(ModsScreen.target_slot_for_drag(1, 137.0, slots), 1,
		"and a slight wobble back stays in the new slot instead of flickering")
	assert_eq(ModsScreen.target_slot_for_drag(1, 135.0, slots), 0,
		"crossing back above the band returns to the upper slot")
	assert_eq(ModsScreen.target_slot_for_drag(0, 340.0, slots), 3,
		"a fast sweep across several rows lands on the end slot")
	assert_eq(ModsScreen.target_slot_for_drag(3, -50.0, slots), 0,
		"and a sweep past the top clamps at the first slot")


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


func test_the_top_right_corner_opens_the_mod_repositories() -> void:
	var screen := await _screen()
	var header := screen.find_child("ScreenHeader", true, false)
	var button := screen.find_child("BrowseModsButton", true, false) as Button
	assert_not_null(button, "the header carries a Browse Mods button")
	assert_true(button.text.contains("Browse Mods"))
	assert_eq(button.get_index(), header.get_child_count() - 1,
		"it is the header's last control: the top-right corner")
	assert_false(button.tooltip_text.is_empty(), "and explains what it opens")
	var calls := []
	screen.browse_requested.connect(func() -> void: calls.append(true))
	button.emit_signal("pressed")
	assert_eq(calls, [true], "pressing it asks for the repositories screen")


func test_the_screen_renders_the_live_library() -> void:
	var screen := await _screen()
	var rows := screen.find_child("ModRows", true, false)
	assert_not_null(rows)
	assert_eq(rows.get_child_count(), ModManager.get_all_mod_infos().size(),
		"one row per discovered mod")
	var seasons_row := rows.get_node_or_null("ModRow_golf_tycoon_seasons")
	assert_not_null(seasons_row, "the Seasons mod is listed (the fixture library has it installed)")
	var check := seasons_row.get_node_or_null("EnabledCheck") as CheckBox
	assert_false(check.button_pressed,
		"and shows as switched off: downloaded mods wait for their tick")
	var details := screen.find_child("ModDetails", true, false) as RichTextLabel
	var first: Dictionary = ModManager.get_all_mod_infos()[0]
	assert_eq(screen._selected_id, str(first.get("id", "")))
	assert_true(details.text.contains(str(first.get("name", ""))),
		"the details pane opens on the first mod in the list")


func test_every_row_opens_with_its_mods_own_icon() -> void:
	var screen := await _screen()
	var rows := screen.find_child("ModRows", true, false)
	var fingerprints: Dictionary = {}
	for row in rows.get_children():
		assert_null(row.get_node_or_null("ModIcon"),
			"the icon rides inside the mod button, not beside it")
		var name_button := row.get_node("ModName") as Button
		var icon := name_button.icon
		assert_not_null(icon, "every row's mod button carries an icon")
		assert_true(icon is ImageTexture, "the icon is a real picture")
		assert_eq(name_button.get_theme_constant("icon_max_width"), int(ModsScreen.ROW_ICON_SIZE),
			"and the button caps it at the row's icon side")
		# The bundled mods each ship their own picture, so the rows show
		# distinct ones; count them (the pixels hash by content).
		if icon is ImageTexture:
			var fingerprint := (icon as ImageTexture).get_image().get_data()
			fingerprints[fingerprint] = true
	assert_gte(fingerprints.size(), 10, "a shelf of bundled mods shows many pictures, not one repeated")
	screen.queue_free()
	await process_frames(1)


func test_the_field_notes_head_with_the_selected_mods_icon() -> void:
	var screen := await _screen()
	var detail_icon := screen.find_child("DetailIcon", true, false) as TextureRect
	assert_not_null(detail_icon, "the field notes carry an icon")
	var first: Dictionary = ModManager.get_all_mod_infos()[0]
	var first_id := str(first.get("id", ""))
	assert_eq(detail_icon.texture, ModManager.get_mod_icon_texture(first_id),
		"it is the first mod's own icon")
	# Select another mod: the picture follows the selection.
	var rows := screen.find_child("ModRows", true, false)
	var target: Button = null
	for row in rows.get_children():
		if str(row.get_meta("mod_id", "")) == screen._selected_id:
			continue
		var btn := row.get_node_or_null("ModName") as Button
		if btn != null:
			target = btn
			break
	assert_not_null(target, "found another mod to select")
	target.emit_signal("pressed")
	await process_frames(1)
	var other_id: String = screen._selected_id
	assert_ne(other_id, first_id)
	assert_eq(detail_icon.texture, ModManager.get_mod_icon_texture(other_id),
		"the new mod's icon is on show")
	screen.queue_free()
	await process_frames(1)


func test_a_mod_without_an_icon_wears_the_default_mark() -> void:
	var mod_id := "tester.iconless"
	var directory: String = ModManager.user_root.path_join(mod_id)
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("mod.json"), FileAccess.WRITE)
	file.store_string("""{
	"format_version": 1, "id": "tester.iconless", "name": "Iconless",
	"version": "1.0.0", "api_version": 1, "description": "test"
}""")
	file.close()
	ModManager.discover()
	var screen := await _screen()
	var row := _row(screen, mod_id)
	assert_not_null(row, "the icon-less mod is listed")
	var name_button := row.get_node("ModName") as Button
	assert_eq(name_button.icon, ModsScreen.fallback_icon_texture(),
		"its row's mod button wears the shared default mark")
	name_button.emit_signal("pressed")
	await process_frames(1)
	var detail_icon := screen.find_child("DetailIcon", true, false) as TextureRect
	assert_eq(detail_icon.texture, ModsScreen.fallback_icon_texture(),
		"and its field notes do")
	screen.queue_free()
	await process_frames(1)
	# Take the test mod away again and rescan, so no later suite sees it.
	ModPackage.remove_directory_recursive(directory)
	ModManager.discover()


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
	assert_true(_row_text(screen, mod_id).contains("LOADS ON LEAVE"))
	assert_eq(screen._selected_id, mod_id, "its field notes open")

	_press(check)
	await process_frames(1)
	assert_false(ModManager.is_mod_enabled(mod_id))
	assert_eq(_listed_ids(screen), order_before, "unticking leaves the row in place as well")
	assert_eq(row.get_global_rect(), place_before)
	assert_false(check.button_pressed)
	assert_false(_row_text(screen, mod_id).contains("LOADS ON LEAVE"), "and takes its number away")
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
	assert_true(ModManager.needs_reload, "the changed order is waiting to be put into play")
	assert_null(screen.find_child("ApplyButton", true, false),
		"there is no Apply button: leaving the screen does it")

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


# ── dragging mods up and down the list ───────────────────────────────────

func test_every_row_has_a_drag_handle_that_stays_out_of_keyboard_focus() -> void:
	var screen := await _screen()
	await process_frames(1)
	var focusables := InputManager.collect_focusables(screen)
	for mod_id in _listed_ids(screen):
		var handle := _grip(screen, str(mod_id))
		assert_not_null(handle, "each row leads with a grip handle (%s)" % mod_id)
		assert_eq(handle.get_index(), 0, "at the leading edge of the row")
		assert_eq(handle.focus_mode, Control.FOCUS_NONE,
			"arrows serve keyboard and controller players, so the grip skips focus")
		assert_false(focusables.has(handle))
		assert_eq(handle.mouse_default_cursor_shape, Control.CURSOR_DRAG)
		assert_false(handle.tooltip_text.is_empty())

	# With a single row on show there is nowhere to drag it: the grip dims.
	var only_id := str(_listed_ids(screen)[0])
	_type(screen, only_id)
	assert_eq(_shown_ids(screen), [only_id])
	var lone_handle := _grip(screen, only_id) as ModsScreen.DragHandle
	assert_true(lone_handle.disabled, "a lone row cannot be reordered")
	assert_eq(lone_handle.mouse_default_cursor_shape, Control.CURSOR_ARROW)
	_type(screen, "")
	assert_false(lone_handle.disabled, "and lights up again when the rest of the library returns")


func test_dragging_a_row_card_reorders_mods_and_updates_load_order() -> void:
	var ticked := _tick_only([0, 1, 3])
	var first := str(ticked[0])
	var second := str(ticked[1])
	var third := str(ticked[2])
	var screen := await _screen()
	await process_frames(2)
	var before := _listed_ids(screen)
	var unticked_id := str(before[2])
	var first_row := _row(screen, first)

	# Dragging an unticked mod up one place leaves the load order untouched.
	var from_unticked := (_row(screen, unticked_id).get_node("ModName") as Control).get_global_rect().get_center()
	await _mouse_drag(from_unticked, from_unticked - Vector2(0.0, ROW_PITCH))
	assert_eq(_listed_ids(screen).slice(0, 4), [first, unticked_id, second, third],
		"dragging an unticked mod moves its row without switching it on")
	assert_false(ModManager.is_mod_enabled(unticked_id))
	assert_eq(_loadout(), [first, second, third])

	# Now drag the top enabled mod across three slots in one sweep, inspecting
	# the live preview mid-flight before letting go.
	var start := (first_row.get_node("ModName") as Control).get_global_rect().get_center()
	var destination := start + Vector2(0.0, ROW_PITCH * 3.0)
	_mouse_down(start)
	await _mouse_move(start, destination, 8)
	assert_true(screen.is_dragging(), "the row is lifted while the button is held")
	assert_eq(screen.dragged_mod_id(), first)
	var preview := screen.find_child("ModDragPreview", true, false) as Control
	assert_not_null(preview, "a floating preview rides with the pointer")
	assert_lt(first_row.modulate.a, 0.9, "while its slot in the list dims underneath")
	assert_eq(_loadout(), [second, third, first],
		"live swaps update the load order before the button is even released")
	var preview_text := (preview.find_child("*", true, false) as Node)
	assert_not_null(preview_text)

	await _mouse_up(destination)
	assert_false(screen.is_dragging(), "releasing drops the row into place")
	assert_null(screen.find_child("ModDragPreview", true, false), "and clears the floating card")
	assert_eq(first_row.modulate, Color.WHITE, "restoring full opacity to the row")
	assert_eq(_row(screen, first), first_row, "the same row node moved rather than being rebuilt")
	assert_eq(_listed_ids(screen).slice(0, 4), [unticked_id, second, third, first])
	assert_eq(_loadout(), [second, third, first])
	_assert_the_numbers_run_down_the_list(screen, "after dragging an enabled mod down")
	_assert_the_arrows_fit_the_rows_on_show(screen, "after dragging an enabled mod down")
	assert_true(ModManager.needs_reload)
	assert_eq(screen._selected_id, first, "the dragged mod's field notes open")


func test_dragging_the_grip_handle_reorders_mods_up_and_down() -> void:
	var screen := await _screen()
	await process_frames(2)
	var before := _listed_ids(screen)
	var top := str(before[0])
	var fourth := str(before[3])

	var handle_start := _grip(screen, fourth).get_global_rect().get_center()
	var top_spot := _grip(screen, top).get_global_rect().get_center()
	await _mouse_drag(handle_start, top_spot, 8)
	assert_eq(str(_listed_ids(screen)[0]), fourth,
		"dragging a row's grip handle to the top places it first")
	assert_eq(str(_listed_ids(screen)[1]), top)

	# Drag it back down to where it came from.
	var back_start := _grip(screen, fourth).get_global_rect().get_center()
	await _mouse_drag(back_start, back_start + Vector2(0.0, ROW_PITCH * 3.0), 8)
	assert_eq(_listed_ids(screen), before, "dragging it back restores the list")


func test_a_short_pointer_wobble_clicks_rather_than_dragging() -> void:
	var screen := await _screen(PHONE)
	await process_frames(2)
	var before := _listed_ids(screen)
	var second := str(before[1])

	# Dragging on a portrait phone keeps the Library tab open afterwards,
	# instead of treating the mouse release as a row click into the Inspector.
	var drag_start := (_row(screen, second).get_node("ModName") as Control).get_global_rect().get_center()
	await _mouse_drag(drag_start, drag_start - Vector2(0.0, ROW_PITCH))
	assert_eq(str(_listed_ids(screen)[0]), second)
	assert_true(screen._library.visible and not screen._inspector.visible,
		"finishing a drag on a portrait phone leaves the library on show")

	# A tiny wobble inside DRAG_THRESHOLD is a plain click: nothing reorders,
	# and the Inspector opens for the tapped mod.
	var order_after_drag := _listed_ids(screen)
	var target_id := str(order_after_drag[2])
	var tap_spot := (_row(screen, target_id).get_node("ModName") as Control).get_global_rect().get_center()
	await _mouse_drag(tap_spot, tap_spot + Vector2(0.0, 2.0), 2)
	assert_eq(_listed_ids(screen), order_after_drag, "sub-threshold pointer wobble moves nothing")
	assert_eq(screen._selected_id, target_id)
	assert_true(screen._inspector.visible, "a click still opens the mod's field notes on phone")


func test_touch_drags_the_grip_to_reorder_while_swiping_the_list_still_scrolls() -> void:
	var screen := await _screen(PHONE)
	await process_frames(2)
	var scroller := screen.find_child("PhoneModsScroll", true, false) as ScrollContainer
	assert_not_null(scroller)
	var before := _listed_ids(screen)
	var first := str(before[0])
	var second := str(before[1])

	# Touch-dragging the grip handle reorders the mod without scrolling or
	# flipping away from the Library tab.
	var grip_from := _grip(screen, first).get_global_rect().get_center()
	await _touch_drag(grip_from, grip_from + Vector2(0.0, ROW_PITCH * 2.0), 8)
	assert_eq(_listed_ids(screen).slice(0, 3), [second, str(before[2]), first],
		"a finger on the grip handle drags the mod down two places")
	assert_true(screen._library.visible, "the Library tab stays open after a touch drag")
	assert_eq(scroller.scroll_vertical, 0, "the grip gesture reordered rather than scrolling")

	# Swiping vertically on the mod button itself still scrolls the list
	# without reordering anything.
	var order_now := _listed_ids(screen)
	var body_spot := (_row(screen, str(order_now[2])).get_node("ModName") as Control).get_global_rect().get_center()
	await _touch_drag(body_spot, body_spot - Vector2(0.0, 140.0), 6)
	assert_eq(_listed_ids(screen), order_now, "swiping the row body does not reorder mods")
	assert_gt(scroller.scroll_vertical, 0, "swiping the row body scrolls the library")

	# Opening a modal over the screen shields the grip handles behind it.
	scroller.scroll_vertical = 0
	await process_frames(2)
	var covered_order := _listed_ids(screen)
	var covered_grip := _grip(screen, str(covered_order[0])).get_global_rect().get_center()
	(screen.find_child("CreateModButton", true, false) as Button).emit_signal("pressed")
	await process_frames(2)
	await _touch_drag(covered_grip, covered_grip + Vector2(0.0, ROW_PITCH * 2.0), 6)
	assert_eq(_listed_ids(screen), covered_order,
		"a dialogue over the screen prevents touches reaching the grips underneath")


func test_dragging_under_a_filter_or_search_steps_over_hidden_rows() -> void:
	var ticked := _tick_only([0, 2, 4])
	var first := str(ticked[0])
	var second := str(ticked[1])
	var third := str(ticked[2])
	var screen := await _screen()
	await process_frames(2)
	var hidden := _listed_ids(screen).filter(func(mod_id: String) -> bool: return not mod_id in ticked)

	_press(_chip(screen, "Enabled"))
	await process_frames(2)
	assert_eq(_shown_ids(screen), [first, second, third])

	var start := _grip(screen, first).get_global_rect().get_center()
	var bottom := _grip(screen, third).get_global_rect().get_center()
	await _mouse_drag(start, bottom, 8)
	assert_eq(_shown_ids(screen), [second, third, first],
		"dragging to the bottom of the filtered view puts the mod last among enabled mods")
	assert_eq(_loadout(), [second, third, first])
	assert_eq(_listed_ids(screen).filter(func(mod_id: String) -> bool: return not mod_id in ticked),
		hidden, "hidden rows keep their order untouched")
	_assert_the_arrows_fit_the_rows_on_show(screen, "after dragging under Enabled filter")
	_press(_chip(screen, "All"))
	await process_frames(1)
	_assert_the_numbers_run_down_the_list(screen, "back on All after filtered drag")


func test_cancelling_a_drag_with_escape_or_right_click_restores_the_order() -> void:
	var screen := await _screen()
	await process_frames(2)
	assert_false(ModManager.needs_reload)
	var before := _listed_ids(screen)
	var loadout_before := _loadout()
	var top := str(before[0])
	var back_calls := []
	screen.back_requested.connect(func() -> void: back_calls.append(true))

	# Drag down two places, then cancel with Escape before releasing.
	var start := _grip(screen, top).get_global_rect().get_center()
	var moved_to := start + Vector2(0.0, ROW_PITCH * 2.0)
	_mouse_down(start)
	await _mouse_move(start, moved_to, 6)
	assert_true(screen.is_dragging())
	assert_ne(_listed_ids(screen), before, "the row has moved mid-drag")

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	get_viewport().push_input(esc, true)
	await process_frames(1)
	assert_false(screen.is_dragging(), "Escape cancels the active drag")
	assert_null(screen.find_child("ModDragPreview", true, false))
	assert_eq(_listed_ids(screen), before, "putting every mod back where it started")
	assert_eq(_loadout(), loadout_before)
	assert_false(ModManager.needs_reload, "so nothing is staged to reload")
	assert_eq(back_calls, [], "and the screen stays open rather than backing out")
	await _mouse_up(moved_to)

	# Right-click mid-drag cancels the same way.
	_mouse_down(start)
	await _mouse_move(start, moved_to, 6)
	assert_true(screen.is_dragging())
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = moved_to
	right_click.global_position = moved_to
	get_viewport().push_input(right_click, true)
	await process_frames(1)
	assert_false(screen.is_dragging(), "right-click cancels the active drag too")
	assert_eq(_listed_ids(screen), before)
	assert_eq(back_calls, [])
	await _mouse_up(moved_to)


func test_dragging_to_the_list_edge_scrolls_more_rows_into_reach() -> void:
	var screen := await _screen()
	await process_frames(2)
	var scroller := screen.find_child("ModList", true, false) as ScrollContainer
	assert_not_null(scroller)
	var everything := _listed_ids(screen)
	assert_gt(everything.size() * ROW_PITCH, scroller.size.y,
		"the library overflows the list so edge scrolling has somewhere to go")
	var top := str(everything[0])
	var start := _grip(screen, top).get_global_rect().get_center()
	var bottom_edge := Vector2(start.x, scroller.get_global_rect().end.y - 4.0)

	_mouse_down(start)
	await _mouse_move(start, bottom_edge, 6)
	var scrolled := await process_frames_until(func() -> bool:
		return scroller.scroll_vertical > 120, 90)
	assert_true(scrolled, "holding a dragged row at the bottom edge scrolls the list down")
	await _mouse_up(bottom_edge)
	var new_place := _listed_ids(screen).find(top)
	assert_gt(new_place, 4, "and carries the dragged mod down into the newly revealed rows")
	assert_true(rect_within(_row(screen, top).get_global_rect(), scroller.get_global_rect()),
		"leaving the dropped row in view")


func test_the_d_pad_steps_through_the_new_order_after_a_drag() -> void:
	var screen := await _screen()
	await process_frames(2)
	var before := _listed_ids(screen)
	var first := str(before[0])
	var second := str(before[1])
	var third := str(before[2])

	var start := _grip(screen, first).get_global_rect().get_center()
	await _mouse_drag(start, start + Vector2(0.0, ROW_PITCH * 2.0), 6)
	assert_eq(_listed_ids(screen).slice(0, 3), [second, third, first])

	InputManager.device = InputManager.Device.GAMEPAD
	var middle_btn := _row(screen, third).get_node("ModName") as Button
	middle_btn.grab_focus()
	await process_frames(2)
	await _press_action("ui_down")
	assert_eq(_focused(), _row(screen, first).get_node("ModName"),
		"Down steps to the mod dragged under it")
	await _press_action("ui_up")
	await _press_action("ui_up")
	assert_eq(_focused(), _row(screen, second).get_node("ModName"),
		"and Up reaches the mod now standing at the top")


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
	# Both kinds, made here rather than assumed: nothing loads until the
	# player ticks it, so this test ticks two of its own.
	_tick_only([0, 1])
	var screen := await _screen()
	var loadout := ModManager.get_enabled_order()
	var everything := _listed_ids(screen)
	var ticked := _ids_where(true)
	var unticked := _ids_where(false)
	assert_false(ticked.is_empty() or unticked.is_empty(), "the ticked pair leaves both kinds")
	var all_chip := _chip(screen, "All")
	var enabled_chip := _chip(screen, "Enabled")
	var disabled_chip := _chip(screen, "Disabled")
	assert_not_null(all_chip)
	assert_not_null(enabled_chip)
	assert_not_null(disabled_chip)
	assert_true(all_chip.button_pressed, "the screen opens on the whole library")
	assert_false(enabled_chip.button_pressed or disabled_chip.button_pressed)
	assert_eq(_shown_ids(screen), everything)

	_press(enabled_chip)
	assert_eq(_shown_ids(screen), ticked, "only the ticked mods, still in the list's order")
	assert_true(enabled_chip.button_pressed, "the chosen chip is held down")
	assert_false(all_chip.button_pressed or disabled_chip.button_pressed, "and only that one")
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
	_tick_only([0])
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
	# One ticked mod of its own: nothing loads until a player ticks it.
	_tick_only([0])
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


func test_the_mod_list_follows_the_filters_without_a_caption_or_summary() -> void:
	for size in [DESKTOP, TABLET, Vector2i(720, 820), PHONE_SIDEWAYS, PHONE, NARROW_PHONE]:
		var screen := await _screen(size)
		await process_frames(2)
		var at := "at %dx%d" % [size.x, size.y]
		assert_null(screen.find_child("LoadoutCaption", true, false), "no instructions above the list %s" % at)
		assert_null(screen.find_child("SubtitleLabel", true, false), "no count summary above the list %s" % at)
		var list := screen.find_child("ModList", true, false) as Control
		var stack := list.get_parent() as VBoxContainer
		var filters := _chip(screen, "All").get_parent() as Control
		var controls := screen._search.get_parent() as Control
		var last_control: Control = filters if filters.get_parent() == stack else controls
		assert_eq(stack.get_child(last_control.get_index() + 1), list,
			"the list immediately follows the filters %s" % at)
		assert_eq(list.position.y - last_control.position.y - last_control.size.y,
			float(stack.get_theme_constant("separation")),
			"only the usual spacing separates the controls and the list %s" % at)
		assert_not_null(screen.find_child("EmptyNote", true, false),
			"the empty-list message is still available %s" % at)
		screen.queue_free()
		await process_frames(1)


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


func test_leaving_with_an_unchanged_list_just_goes_back() -> void:
	# The list already matches what loaded, so there is nothing to re-mod:
	# Back is Back, and the scene is left alone.
	var screen := await _screen()
	assert_false(ModManager.needs_reload, "nothing has changed yet")
	var calls := []
	screen.back_requested.connect(func(): calls.push_back(true))
	screen.leave()
	assert_eq(calls, [true], "leaving asks for the screen to go away")
	assert_false(ModManager.needs_reload)


func test_leaving_after_a_change_reloads_the_mods_and_the_scene() -> void:
	# Ticking a mod stages the change; leaving the screen is what puts it
	# into play, so the player never has to press anything else.
	var screen := await _screen()
	var mod_id := str(_ids_where(false).back())
	_press(_row(screen, mod_id).get_node("EnabledCheck") as CheckBox)
	await process_frames(1)
	assert_true(ModManager.needs_reload, "the tick is waiting to be put into play")
	# The screen does not survive the reload, so it asks for no back: the
	# scene coming back is the new one.
	var calls := []
	screen.back_requested.connect(func(): calls.push_back(true))
	assert_true(ModManager.apply_staged_changes(), "leaving applies the new loadout")
	await process_frames(1)
	assert_eq(calls, [], "and the old screen asks for nothing")
	assert_false(ModManager.needs_reload, "nothing is left staged")
	assert_true(ModManager.is_mod_loaded(mod_id), "the ticked mod is in play")


func test_there_is_no_apply_button() -> void:
	var screen := await _screen()
	assert_null(screen.find_child("ApplyButton", true, false),
		"mods apply themselves, so the screen carries no Apply button")
	var tools := screen.find_child("Tools", true, false)
	var labels: Array[String] = []
	for button in tools.get_children():
		if button is Button:
			labels.append((button as Button).text)
	assert_eq(labels, ["Create New Mod", "+ Install ZIP", "Rescan", "Mods folder", "Disable all"],
		"the tool row's actions, and nothing that applies a loadout")


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
