extends GameTest
## ModsScreen: the pure text the rows and details pane are built from, and
## that the real screen renders the live library (one row per discovered
## mod, enabled mods numbered in load order). Toggling is not exercised
## here - it persists to the player's real list and belongs to the manager
## tests against throwaway libraries. (scripts/ui/mods_screen.gd)


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


func test_the_screen_renders_the_live_library() -> void:
	var screen := ModsScreen.new()
	add_child_autofree(screen)
	await process_frames(1)
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
	var screen := ModsScreen.new()
	add_child_autofree(screen)
	await process_frames(1)
	for node in screen.find_children("*", "Button", true, false):
		assert_false((node as Button).text.to_lower().contains("workshop"),
			"Workshop remains backend-only for now")


func test_search_filters_without_changing_loadout() -> void:
	var screen := ModsScreen.new()
	add_child_autofree(screen)
	await process_frames(1)
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
	var screen := ModsScreen.new()
	add_child_autofree(screen)
	await process_frames(1)
	screen._compact = true
	screen._inspect_mobile = false
	screen._update_panes()
	assert_true(screen._library.visible)
	assert_false(screen._inspector.visible)
	assert_true(screen._tabs.visible)
	screen._inspect_mobile = true
	screen._update_panes()
	assert_false(screen._library.visible)
	assert_true(screen._inspector.visible)
	screen._compact = false
	screen._update_panes()
	assert_true(screen._library.visible)
	assert_true(screen._inspector.visible)
	assert_false(screen._tabs.visible)


func test_workspace_fits_desktop_tablet_and_phone_widths() -> void:
	var screen := ModsScreen.new()
	add_child_autofree(screen)
	await process_frames(2)
	for width in [1280, 820, 390, 320]:
		screen._compact = width < 700
		screen._update_panes()
		screen.size = Vector2(width, 720)
		await process_frames(3)
		assert_lte(screen.get_combined_minimum_size().x, float(width),
			"no horizontal overflow at %d px" % width)
		assert_lte(screen._workspace.size.x, float(width),
			"workspace reflows at %d px" % width)
