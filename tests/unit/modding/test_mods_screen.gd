extends GameTest
## ModsScreen: the fullscreen mod library. It sits on the World Map's
## MenuBackdrop, lists every discovered mod in load order, inspects one mod
## at a time in the field-notes pane, and stages toggles and reorders until
## the player applies them. (scripts/ui/mods_screen.gd)
##
## The pure text the rows and details pane are built from is unit-tested
## first; the screen tests walk the built tree and check what it actually
## draws at each window shape.

const DESKTOP := Vector2i(1600, 1000)
const TABLET := Vector2i(820, 720)
const PHONE := Vector2i(390, 720)
const NARROW_PHONE := Vector2i(320, 720)

var _window_before := Vector2i.ZERO

func before_each() -> void:
	super()
	_window_before = get_window().size

func after_each() -> void:
	get_window().size = _window_before
	super()

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


func test_details_text_covers_trust_provenance_and_providers() -> void:
	var info := {
		"id": "tester.big", "name": "Big Mod", "version": "1.0.0", "author": "Ada",
		"description": "Does big things.", "source_label": "your mods folder",
		"types": ["gameplay"], "has_script": true,
		"dependencies": ["golf_tycoon.seasons >= 1.0.0"],
		"errors": [], "warnings": ["mind the gaps"],
		"conflicts_declared": [], "workshop_id": 0, "auto_enabled": false,
	}
	var text := ModsScreen.details_text(info,
		{"weather": "golf_tycoon.weather", "wind": "(built-in)", "seasons": "tester.big"},
		["buildings 'snack_bar': written by tester.small, overwritten by tester.big (later in the load order wins)."],
		["[tester.big] Tuning value 'x' is not a number; skipped."])
	assert_true(text.contains("Big Mod") and text.contains("by Ada"))
	assert_true(text.contains("runs code"), "players are told when a mod runs code")
	assert_true(text.contains("Needs: golf_tycoon.seasons >= 1.0.0"))
	assert_true(text.contains("mind the gaps"), "manifest warnings surface")
	assert_true(text.contains("tester.small"), "data conflicts name both sides")
	assert_true(text.contains("Seasons: tester.big"), "who provides what is on the pane")

	assert_true(ModsScreen.details_text({}, {}, [], []).contains("No mod selected"))


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
	var kicker := header.get_node("TitleBlock/Kicker") as Label
	assert_eq(kicker.text, "The Mod Shed")


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
	assert_true(details.text.contains("Seasons (Official)"),
		"the details pane opens on the first mod")
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
		if row.name == "ModRow_golf_tycoon_seasons":
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
