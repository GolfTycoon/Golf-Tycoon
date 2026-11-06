extends MainSceneTest
## The Background card in Settings > Display, driven the way a player drives
## it: both pickers and their Auto switches, the live preview, the per-overlay
## settings and the saved file - from the title screen and from a pause
## session, at every window shape.
##
## The card is the only place the two choices are made, so this file is where
## "Auto is the default", "a choice is remembered" and "the menus repaint" are
## pinned end to end.

const BackdropsScript := preload("res://scripts/autoload/backdrops.gd")

var _saved_background: String = ""
var _saved_overlay: String = ""
var _saved_overlay_settings: Dictionary = {}
var _had_settings_file := false
var _settings_bytes := PackedByteArray()


func before_each() -> void:
	super()
	_saved_background = Backdrops.background_choice
	_saved_overlay = Backdrops.overlay_choice
	_saved_overlay_settings = Backdrops.overlay_settings.duplicate(true)
	_had_settings_file = FileAccess.file_exists(SaveManager.SETTINGS_PATH)
	if _had_settings_file:
		_settings_bytes = FileAccess.get_file_as_bytes(SaveManager.SETTINGS_PATH)
	Backdrops.reset_choices()


func after_each() -> void:
	var menu := main.get_node_or_null("UI/HUD/SettingsMenu")
	if menu != null:
		menu.free()
	Backdrops.background_choice = _saved_background
	Backdrops.overlay_choice = _saved_overlay
	Backdrops.overlay_settings = _saved_overlay_settings.duplicate(true)
	if _had_settings_file:
		var file := FileAccess.open(SaveManager.SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(_settings_bytes)
		file.close()
	elif FileAccess.file_exists(SaveManager.SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SETTINGS_PATH))
	await super()


## Open Settings from the title screen on its Display page.
func _open_display() -> SettingsMenu:
	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	menu.origin = SettingsMenu.Origin.MAIN_MENU
	await process_frames(2)
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(3)
	return menu


func _picker(menu: SettingsMenu, node_name: String) -> OptionButton:
	return menu.find_child(node_name, true, false) as OptionButton


func _select_by_id(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	fail_test("picker has no item for %s" % id)


# ---------------------------------------------------------------------------
# The card
# ---------------------------------------------------------------------------

func test_the_display_page_offers_a_background_and_an_overlay() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	var backgrounds := _picker(menu, "BackgroundPicker")
	var overlays := _picker(menu, "OverlayPicker")
	assert_not_null(backgrounds, "the picture picker is on the Display page")
	assert_not_null(overlays, "and the overlay picker beside it")
	assert_not_null(menu.find_child("BackgroundAuto", true, false), "each has its Auto switch")
	assert_not_null(menu.find_child("OverlayAuto", true, false))
	assert_not_null(menu.find_child("BackgroundPreview", true, false), "and the card previews itself")


func test_both_pickers_list_every_shipped_style_after_auto() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	var backgrounds := _picker(menu, "BackgroundPicker")
	assert_eq(backgrounds.item_count, MenuBackdropCatalog.backdrops().size() + 1,
		"every shipped picture plus Auto")
	assert_eq(str(backgrounds.get_item_metadata(0)), Backdrops.AUTO, "Auto is the first row")
	assert_string_contains(backgrounds.get_item_text(0), "Auto")
	var overlays := _picker(menu, "OverlayPicker")
	assert_eq(overlays.item_count, MenuBackdropCatalog.overlays().size() + 1)
	assert_eq(str(overlays.get_item_metadata(1)), "none", "None is the plain picture")


func test_a_fresh_install_opens_on_auto_and_says_what_auto_picked() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	var backgrounds := _picker(menu, "BackgroundPicker")
	var overlay_picker := _picker(menu, "OverlayPicker")
	assert_eq(str(backgrounds.get_item_metadata(backgrounds.selected)),
		Backdrops.AUTO, "Auto is the default, not a placeholder")
	assert_eq(str(overlay_picker.get_item_metadata(overlay_picker.selected)), Backdrops.AUTO)
	var auto_toggle := menu.find_child("BackgroundAuto", true, false) as CheckButton
	assert_true(auto_toggle.button_pressed, "the Auto switch reads on")
	var hint := menu.find_child("BackgroundAutoHint", true, false) as Label
	assert_not_null(hint, "the card says what Auto is doing")
	assert_string_contains(hint.text, "Auto", "in Auto's own words")


# ---------------------------------------------------------------------------
# Choosing
# ---------------------------------------------------------------------------

func test_picking_a_picture_applies_it_and_remembers_it() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	var picker := _picker(menu, "BackgroundPicker")
	_select_by_id(picker, "winter")
	assert_eq(Backdrops.background_choice, "winter", "the choice is live at once")
	var auto_toggle := menu.find_child("BackgroundAuto", true, false) as CheckButton
	assert_false(auto_toggle.button_pressed, "and Auto reads off")
	# The setting was written to the settings file with the rest of Display.
	var config := ConfigFile.new()
	assert_eq(config.load(SaveManager.SETTINGS_PATH), OK)
	assert_true(config.has_section_key("display", "menu_background"),
		"the choice is written to settings.cfg")
	assert_eq(str(config.get_value("display", "menu_background", "")), "winter")


func test_picking_an_overlay_applies_it_and_its_settings_appear() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	var picker := _picker(menu, "OverlayPicker")
	_select_by_id(picker, "fairway_stripes")
	assert_eq(Backdrops.overlay_choice, "fairway_stripes")
	var rows := menu.find_child("OverlaySettingRows", true, false) as VBoxContainer
	assert_not_null(rows, "the settings block is there")
	await process_frames(2)
	assert_not_null(menu.find_child("OverlaySetting_angle", true, false),
		"the stripes' own Angle choice appears")
	# Switching to an overlay with no settings takes the block away again.
	_select_by_id(picker, "vignette")
	await process_frames(2)
	assert_null(menu.find_child("OverlaySetting_angle", true, false),
		"a setting the picture ignores is not offered")


func test_the_overlays_angle_is_kept_per_overlay() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	var picker := _picker(menu, "OverlayPicker")
	_select_by_id(picker, "fairway_stripes")
	await process_frames(2)
	var angle := menu.find_child("OverlaySetting_angle", true, false) as OptionButton
	assert_not_null(angle)
	# Pick 45 degrees (the catalogue lists 0, 15, 30, 45, ...).
	angle.select(3)
	angle.item_selected.emit(3)
	assert_eq(Backdrops.overlay_settings["fairway_stripes"]["angle"], 45)
	# Leaving the overlay and coming back finds the angle still set.
	_select_by_id(picker, "vignette")
	await process_frames(2)
	_select_by_id(picker, "fairway_stripes")
	await process_frames(2)
	var again := menu.find_child("OverlaySetting_angle", true, false) as OptionButton
	assert_eq(again.get_item_metadata(again.selected), 45, "the angle survives a round trip")


func test_auto_switched_off_keeps_the_picture_that_was_showing() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	# Auto is on and resolves to the clubhouse on the title screen.
	var auto_id := Backdrops.auto_background_id()
	var toggle := menu.find_child("BackgroundAuto", true, false) as CheckButton
	toggle.button_pressed = false
	toggle.toggled.emit(false)
	assert_eq(Backdrops.background_choice, auto_id,
		"turning Auto off must not change the picture on the frame it is pressed")
	assert_false(Backdrops.background_choice == Backdrops.AUTO)


func test_reset_puts_both_choices_back_on_auto() -> void:
	await set_window(DESIGN_WINDOW)
	var menu: SettingsMenu = await _open_display()
	_select_by_id(_picker(menu, "BackgroundPicker"), "desert")
	_select_by_id(_picker(menu, "OverlayPicker"), "scanlines")
	assert_eq(Backdrops.background_choice, "desert")
	var reset := menu.find_child("BackgroundReset", true, false) as Button
	assert_not_null(reset)
	reset.pressed.emit()
	assert_eq(Backdrops.background_choice, Backdrops.AUTO)
	assert_eq(Backdrops.overlay_choice, Backdrops.AUTO)


# ---------------------------------------------------------------------------
# The menus themselves
# ---------------------------------------------------------------------------

func test_every_menu_backdrop_wears_the_chosen_picture() -> void:
	await set_window(DESIGN_WINDOW)
	Backdrops.background_choice = "winter"
	Backdrops.overlay_choice = "scanlines"
	Backdrops.backdrop_changed.emit()
	await process_frames(2)
	var title := main.get_node_or_null("UI/HUD/MainMenu/Backdrop") as MenuBackdrop
	assert_not_null(title, "the title screen sits on a backdrop")
	assert_eq(str(title.background.get("id", "")), "winter", "which shows the chosen picture")
	assert_eq(str(title.overlay.get("id", "")), "scanlines", "with the chosen overlay over it")
	assert_not_null(title.background.get("texture", null), "and the picture decoded")


func test_a_backdrop_repaints_when_the_choice_changes() -> void:
	await set_window(DESIGN_WINDOW)
	Backdrops.background_choice = "desert"
	Backdrops.backdrop_changed.emit()
	await process_frames(1)
	var title := main.get_node_or_null("UI/HUD/MainMenu/Backdrop") as MenuBackdrop
	assert_eq(str(title.background.get("id", "")), "desert")
	Backdrops.reset_choices()
	Backdrops.backdrop_changed.emit()
	await process_frames(1)
	assert_eq(str(title.background.get("id", "")), Backdrops.auto_background_id(),
		"back on Auto it follows the resolver again")


func test_a_backdrop_never_swallows_a_click() -> void:
	await set_window(DESIGN_WINDOW)
	var title := main.get_node_or_null("UI/HUD/MainMenu/Backdrop") as MenuBackdrop
	assert_eq(title.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the picture is scenery: a click lands on the cards above it")


func test_the_backdrop_survives_a_missing_picture() -> void:
	await set_window(DESIGN_WINDOW)
	MenuBackdropCatalog.set_mod_catalogues({"gone": {
		"name": "Gone", "image": "res://no/such/picture.png",
		"tint": Color.WHITE, "scrim": 0.4, "seasons": [], "themes": [],
	}}, {}, {}, {"gone": "a_mod"}, {})
	Backdrops.background_choice = "gone"
	Backdrops.backdrop_changed.emit()
	await process_frames(2)
	var title := main.get_node_or_null("UI/HUD/MainMenu/Backdrop") as MenuBackdrop
	assert_eq(str(title.background.get("id", "")), "gone")
	assert_true(bool(title.background.get("texture_missing", false)),
		"the screen knows the file is gone and paints the fallback green")
	MenuBackdropCatalog.clear_mod_catalogues()


# ---------------------------------------------------------------------------
# Every window, and from the pause menu
# ---------------------------------------------------------------------------

func test_the_background_card_fits_every_window() -> void:
	for size in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(768, 1024),
			Vector2i(1366, 657), Vector2i(1600, 1000)]:
		await set_window(size)
		var menu: SettingsMenu = await _open_display()
		var picker := _picker(menu, "BackgroundPicker")
		assert_not_null(picker, "%s: the picture picker is built" % size)
		if picker != null:
			assert_gte(picker.size.y, 36.0, "%s: and is touch-sized" % size)
		var reset := menu.find_child("BackgroundReset", true, false) as Button
		assert_not_null(reset, "%s: so is the reset" % size)
		if reset != null:
			assert_gte(reset.size.y, 36.0, "%s: every action stays touch-sized" % size)
		menu.free()
		await process_frames(1)


func test_the_card_works_from_a_pause_session_too() -> void:
	await set_window(DESIGN_WINDOW)
	await new_game("Backdrop pause test")
	main._show_settings_menu()
	await process_frames(3)
	var menu := main.get_node("UI/HUD/SettingsMenu") as SettingsMenu
	assert_eq(menu.origin, SettingsMenu.Origin.PAUSE_MENU)
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(3)
	assert_not_null(_picker(menu, "BackgroundPicker"),
		"the picture can be changed mid-game as well as from the title")
	_select_by_id(_picker(menu, "BackgroundPicker"), "golden_hour")
	assert_eq(Backdrops.background_choice, "golden_hour")
	# A course is open, so Auto may now resolve through its theme - but a pin
	# the player made is never overridden.
	var resolved := Backdrops.resolve_background()
	assert_eq(str(resolved["id"]), "golden_hour")
	assert_false(bool(resolved["automatic"]))
