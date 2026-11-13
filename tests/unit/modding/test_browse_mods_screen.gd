extends GameTest
## BrowseModsScreen: the mod catalogue. It lists the player's repository
## feeds (the Official Repository seeded by default), the mods each fetched
## feed offers, and installs a download the same way the Mods screen's
## "Install ZIP" does - switched off, waiting for a tick. The network layer
## is replaced with a local fetcher that serves the committed Official
## Repository (res://repository/) plus whatever a test adds, so the whole
## screen is exercised without touching the web.
## (scripts/ui/browse_mods_screen.gd)

const DESKTOP := Vector2i(1600, 1000)
const TABLET := Vector2i(820, 720)
const PHONE := Vector2i(390, 720)
const NARROW_PHONE := Vector2i(320, 720)

const OFFICIAL_URL := ModRepositoryStore.OFFICIAL_REPOSITORY_URL
const OFFICIAL_ZIPS := "https://raw.githubusercontent.com/GolfTycoon/Golf-Tycoon/main/repository/zips/"
const EXTRA_FEED_URL := "https://example.com/my-mods.json"

const ROOT := "user://ut_browse_screen"

var store: ModRepositoryStore = null
var downloader: ModRepositoryDownloader = null

## url -> {ok, status, bytes, errors}: the local "server".
var _served: Dictionary = {}
var _listed_before: Array[String] = []
var _loadout_before: Array[String] = []
var _loadout_was_saved := false
var _library_was_saved := false
## Mods a test downloaded through the screen, removed again afterwards.
var _downloaded: Array[String] = []


func before_each() -> void:
	super()
	_listed_before = ModManager.get_listed_order()
	_loadout_before = ModManager.get_enabled_order()
	_loadout_was_saved = FileAccess.file_exists(ModManager._config_path())
	_library_was_saved = FileAccess.file_exists(ModManager._library_order_path())
	ModPackage.remove_directory_recursive(ROOT)
	store = ModRepositoryStore.new(ROOT.path_join("store"))
	downloader = ModRepositoryDownloader.new()
	add_child_autofree(downloader)
	downloader.fetch_override = _serve
	_served.clear()
	# The committed Official Repository answers for its real address (its
	# zips included, so a download can really install), and so does a
	# self-hosted feed a test can add.
	_serve_file(OFFICIAL_URL, "res://repository/official.json")
	for zip_name in _official_zip_names():
		_serve_file(OFFICIAL_ZIPS + zip_name, "res://repository/zips/" + zip_name)
	_serve_file(EXTRA_FEED_URL, _write_extra_feed())


func after_each() -> void:
	for mod_id in _downloaded:
		ModManager.uninstall_mod(mod_id)
	_downloaded.clear()
	_remove_upgrade_fixture()
	ModPackage.remove_directory_recursive(ROOT)
	_restore_library()
	super()


## The screen edits the real ModManager (a download joins the library), so
## put every mod back in the place the test found it and leave no order
## files behind where there were none - the same courtesy
## test_mods_screen.gd extends to the library.
func _restore_library() -> void:
	for place in _listed_before.size():
		var mod_id := _listed_before[place]
		if ModManager.get_listed_order().find(mod_id) >= 0:
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


# ── fixtures ─────────────────────────────────────────────────────────────

func _serve(url: String, on_done: Callable) -> void:
	var answer: Dictionary = _served.get(url, {
		"ok": false, "status": 0, "bytes": PackedByteArray(),
		"errors": ["No local answer for %s" % url],
	})
	on_done.call(answer.duplicate(true))


func _serve_file(url: String, path: String) -> void:
	_served[url] = {"ok": true, "status": 200,
		"bytes": FileAccess.get_file_as_bytes(path), "errors": [] as Array[String]}


func _serve_failure(url: String, message: String) -> void:
	_served[url] = {"ok": false, "status": 0, "bytes": PackedByteArray(),
		"errors": [message] as Array[String]}


## The zip file names the committed Official Repository offers.
func _official_zip_names() -> Array:
	var names := []
	var dir := DirAccess.open("res://repository/zips")
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".zip"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return names


## A small second feed a test can add: one entry that is not installed, and
## one (the upgrade fixture) that is installed at an older version when the
## test installs it.
func _write_extra_feed() -> String:
	var path := ROOT.path_join("extra_feed.json")
	DirAccess.make_dir_recursive_absolute(ROOT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""{
	"format_version": 1,
	"name": "Backyard Mods",
	"mods": [
		{"id": "example.decorations", "name": "Example: Garden Accessories",
		 "version": "1.0.0", "author": "Golf Tycoon examples",
		 "description": "A decoration mod served from a self-hosted feed.",
		 "download_url": "%sexample.decorations.zip", "size_bytes": 1814},
		{"id": "tester.upgrade", "name": "Upgrade Me",
		 "version": "2.0.0", "download_url": "%stester.upgrade.zip"}
	]
}""" % [OFFICIAL_ZIPS, OFFICIAL_ZIPS])
	file.close()
	return path


func _install_upgrade_fixture() -> void:
	# An older copy of the feed's mod, already in the library: the feed's
	# 2.0.0 should read as an Update, not a fresh Download.
	var folder := ModManager.user_root.path_join("installed").path_join("tester.upgrade")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("mod.json"), FileAccess.WRITE)
	file.store_string("""{
	"format_version": 1, "id": "tester.upgrade", "name": "Upgrade Me",
	"version": "0.1.0", "api_version": 1, "description": "fixture"
}""")
	file.close()
	var icon := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	icon.fill(Color.GREEN)
	icon.save_png(folder.path_join("icon.png"))
	ModManager.discover()
	_served[OFFICIAL_ZIPS + "tester.upgrade.zip"] = {"ok": true, "status": 200,
		"bytes": PackedByteArray([1, 2, 3]), "errors": [] as Array[String]}


func _remove_upgrade_fixture() -> void:
	var folder := ModManager.user_root.path_join("installed").path_join("tester.upgrade")
	if DirAccess.dir_exists_absolute(folder):
		ModPackage.remove_directory_recursive(folder)
		ModManager.discover()


# ── helpers ──────────────────────────────────────────────────────────────

## Make sure a test's target is not already in the library (a leaked
## fixture, a persistent user folder): a download test starts from "not
## installed" whatever happened before it.
func _ensure_not_installed(mod_id: String) -> void:
	if not ModManager.get_mod_info(mod_id).is_empty():
		ModManager.uninstall_mod(mod_id)

func _screen(size: Vector2i = DESKTOP) -> BrowseModsScreen:
	get_window().size = size
	await process_frames(2)
	var screen := BrowseModsScreen.new()
	screen.store = store
	screen.downloader = downloader
	add_child_autofree(screen)
	await process_frames(1)
	return screen


func _repo_card(screen: BrowseModsScreen, url: String) -> Control:
	if screen._repositories_box == null:
		return null
	for row in screen._repositories_box.get_children():
		if str(row.get_meta("url", "")) == url:
			return row as Control
	return null


func _mod_row(screen: BrowseModsScreen, section: int, mod_id: String) -> Control:
	var sections := screen._available_box.get_children() if screen._available_box != null else []
	if section >= sections.size():
		return null
	return sections[section].get_node_or_null(
		"ModRow_" + mod_id.replace(".", "_").replace("-", "_")) as Control


func _download_button(screen: BrowseModsScreen, section: int, mod_id: String) -> Button:
	var row := _mod_row(screen, section, mod_id)
	return row.get_node("DownloadButton") as Button if row != null else null


func _mod_card(screen: BrowseModsScreen, section: int, mod_id: String) -> Button:
	var row := _mod_row(screen, section, mod_id)
	return row.get_node("ModCard") as Button if row != null else null


func _back_button(screen: BrowseModsScreen) -> Button:
	var header := screen.find_child("ScreenHeader", true, false)
	return header.get_node("BackButton") as Button


# ── the screen itself ────────────────────────────────────────────────────

func test_the_screen_sits_on_the_world_map_background() -> void:
	var screen := await _screen()
	assert_eq(screen.anchor_left, 0.0)
	assert_eq(screen.anchor_top, 0.0)
	assert_eq(screen.anchor_right, 1.0)
	assert_eq(screen.anchor_bottom, 1.0)
	var backdrop := screen.find_child("Backdrop", true, false)
	assert_not_null(backdrop, "the screen sits on the shared menu backdrop")
	assert_true(backdrop is MenuBackdrop)


func test_the_header_carries_the_browse_title_and_a_back_button() -> void:
	var screen := await _screen()
	var header := screen.find_child("ScreenHeader", true, false)
	assert_not_null(header)
	var title := header.get_node("TitleBlock/Title") as Label
	assert_eq(title.text, "Browse Mods")
	var back := _back_button(screen)
	assert_true(back.text.contains("Back"))
	var calls := []
	screen.back_requested.connect(func() -> void: calls.append(true))
	back.emit_signal("pressed")
	assert_eq(calls, [true])


func test_escape_requests_back() -> void:
	var screen := await _screen()
	var calls := []
	screen.back_requested.connect(func() -> void: calls.append(true))
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	screen._unhandled_input(esc)
	assert_eq(calls, [true])


# ── the official repository, seeded and fetched ──────────────────────────

func test_the_official_repository_is_on_the_list_before_anything_is_added() -> void:
	var screen := await _screen()
	var card := _repo_card(screen, OFFICIAL_URL)
	assert_not_null(card, "the seeded feed has a card")
	assert_not_null(card.find_child("OfficialBadge", true, false),
		"it wears the Official mark")
	assert_eq(store.repository_count(), 1)


func test_the_official_feed_is_fetched_and_its_entries_listed() -> void:
	var screen := await _screen()
	var card := _repo_card(screen, OFFICIAL_URL)
	var status := card.find_child("RepoStatus", true, false) as Label
	assert_true(status.text.contains("18 mods on offer"),
		"the whole official catalogue is on offer (%s)" % status.text)
	assert_not_null(screen.feed_for(OFFICIAL_URL), "the feed itself is kept")
	var section := screen._available_box.get_child(0)
	assert_eq(str(section.get_meta("url", "")), OFFICIAL_URL)
	assert_eq(section.get_child_count(), 19, "a header line and one row per mod")
	var seasons_row := section.get_node_or_null("ModRow_golf_tycoon_seasons") as Control
	assert_not_null(seasons_row, "the Seasons mod is on offer")
	assert_eq(str(seasons_row.get_meta("mod_id", "")), "golf_tycoon.seasons")


func test_every_official_row_carries_an_icon_and_a_download_button() -> void:
	var screen := await _screen()
	var section := screen._available_box.get_child(0)
	var first_row: Control = null
	for child in section.get_children():
		if child.name.begins_with("ModRow_"):
			first_row = child
			break
	assert_not_null(first_row)
	var card := first_row.get_node("ModCard") as Button
	assert_not_null(card.icon, "the row wears the default mark")
	var button := first_row.get_node("DownloadButton") as Button
	assert_false(button.disabled, "a mod that is not installed offers Download")
	assert_eq(button.text, "Download")


func test_every_row_says_which_mod_it_is() -> void:
	_ensure_not_installed("golf_tycoon.seasons")
	var screen := await _screen()
	var section := screen._available_box.get_child(0)
	var rows := 0
	for child in section.get_children():
		if not child.name.begins_with("ModRow_"):
			continue
		rows += 1
		var mod_id := str(child.get_meta("mod_id", ""))
		var entry := screen.entry_for(mod_id)
		var card := child.get_node("ModCard") as Button
		assert_true(card.text.begins_with(str(entry.get("name", ""))),
			"the card for %s leads with the mod's name (%s)" % [mod_id, card.text])
		assert_true(card.tooltip_text.contains(str(entry.get("name", ""))),
			"and its tooltip carries the name in full")
	assert_eq(rows, 18, "every official mod was checked")

	var seasons := _mod_card(screen, 0, "golf_tycoon.seasons")
	var offered := screen.entry_for("golf_tycoon.seasons")
	assert_eq(seasons.text, "%s  %s\nNOT INSTALLED" % [offered["name"], offered["version"]],
		"name and version on offer, over where the mod stands in the library")
	assert_ne(seasons.get_theme_color("font_color").to_html(false),
		MenuStyle.CARD_BG.to_html(false), "the words are not the colour of the card")


func test_a_card_fits_its_words_at_every_window_shape() -> void:
	for size in [DESKTOP, TABLET, PHONE, NARROW_PHONE]:
		var screen := await _screen(size)
		# On a phone held upright the catalogue is behind the Mods tab.
		screen._repositories_shown = false
		screen._sync_panes()
		await process_frames(3)
		var where := "at %dx%d" % [size.x, size.y]
		assert_lte((screen.get_node("Frame") as Control).get_combined_minimum_size().x,
			float(size.x), "the catalogue is no wider than the window " + where)
		var section := screen._available_box.get_child(0)
		for child in section.get_children():
			if not child.name.begins_with("ModRow_"):
				continue
			var row := child as Control
			var card := row.get_node("ModCard") as Button
			var button := row.get_node("DownloadButton") as Button
			assert_lte(row.size.x, float(size.x), "%s fits the window %s" % [row.name, where])
			# The words wrap inside the card instead of being cut off, so
			# the card must be given the height its wrapped text asks for
			# and the width to keep whole words on a line.
			assert_gte(card.size.y, card.get_combined_minimum_size().y,
				"%s is as tall as its text %s" % [row.name, where])
			var words_width := card.size.x - card.get_theme_stylebox("normal").get_minimum_size().x \
				- BrowseModsScreen.ROW_ICON_SIZE - 10.0
			assert_gte(words_width, 140.0,
				"%s leaves the name room to read %s" % [row.name, where])
			var line_height := card.get_theme_font("font").get_height(
				card.get_theme_font_size("font_size"))
			assert_lte(card.size.y,
				card.get_theme_stylebox("normal").get_minimum_size().y + line_height * 4.0,
				"%s wraps its name onto three lines at most %s" % [row.name, where])
			assert_eq(row.get_meta("stacked", false), BrowseModsScreen.rows_stack_at(float(size.x)))
			if BrowseModsScreen.rows_stack_at(float(size.x)):
				assert_gte(button.position.y, card.position.y + card.size.y,
					"the Download button sits under its card " + where)
			else:
				assert_gte(button.position.x, card.position.x + card.size.x,
					"the Download button sits beside its card " + where)
		screen.queue_free()
		await process_frames(1)


func test_card_text_names_the_mod_and_where_it_stands() -> void:
	var entry := {"id": "tester.mod", "name": "Test Mod", "version": "1.2.0"}
	assert_eq(BrowseModsScreen.card_title(entry), "Test Mod  1.2.0")
	assert_eq(BrowseModsScreen.card_text(entry, ""), "Test Mod  1.2.0\nNOT INSTALLED")
	assert_eq(BrowseModsScreen.card_text(entry, "1.2.0"), "Test Mod  1.2.0\nINSTALLED 1.2.0")
	assert_eq(BrowseModsScreen.card_text(entry, "1.0.0"),
		"Test Mod  1.2.0\nINSTALLED 1.0.0 · 1.2.0 AVAILABLE")
	assert_eq(BrowseModsScreen.card_title({"id": "tester.bare"}), "tester.bare",
		"a feed entry without a name or version still reads as something")
	assert_eq(BrowseModsScreen.card_title({"id": "tester.bare", "name": "  "}), "tester.bare")
	assert_eq(BrowseModsScreen.card_title({}), "?")
	assert_true(BrowseModsScreen.rows_stack_at(390.0), "a phone held upright stacks its rows")
	assert_false(BrowseModsScreen.rows_stack_at(820.0))


# ── downloading ──────────────────────────────────────────────────────────

func test_downloading_installs_the_mod_switched_off() -> void:
	_ensure_not_installed("example.theme")
	var screen := await _screen()
	assert_true(ModManager.get_mod_info("example.theme").is_empty(), "nothing installed yet")
	var button := _download_button(screen, 0, "example.theme")
	assert_not_null(button)
	button.emit_signal("pressed")
	await process_frames(2)

	var info: Dictionary = ModManager.get_mod_info("example.theme")
	assert_false(info.is_empty(), "the download lands in the library the manager discovers")
	assert_false(bool(info.get("enabled", false)),
		"installing is never enabling: it waits for the Mods screen's tick")
	assert_eq(bool(info.get("loaded", false)), false)
	_downloaded.append("example.theme")

	var refreshed := _download_button(screen, 0, "example.theme")
	assert_not_null(refreshed)
	assert_true(refreshed.disabled, "an installed mod offers nothing more to download")
	assert_eq(refreshed.text, "Installed")
	assert_true(_mod_card(screen, 0, "example.theme").text.ends_with(
		"INSTALLED " + str(info.get("version", ""))), "and its card says so too")
	assert_true(screen._status.text.contains("switched off"),
		"the status line says what to do next (%s)" % screen._status.text)
	assert_false(ModManager.needs_reload, "and nothing is staged: downloads never change the loadout")


func test_a_second_download_waits_for_the_first() -> void:
	_ensure_not_installed("example.decorations")
	var screen := await _screen()
	# A download still in flight - what on a real network would take a few
	# seconds - and a second press while it runs.
	screen._downloading_id = "example.balance"
	var second := _download_button(screen, 0, "example.decorations")
	second.emit_signal("pressed")
	await process_frames(1)
	assert_true(ModManager.get_mod_info("example.decorations").is_empty(),
		"the second press downloaded nothing")
	assert_true(screen._status.text.contains("One download at a time"))
	screen._downloading_id = ""


func test_a_download_failure_says_what_happened() -> void:
	_ensure_not_installed("example.balance")
	var screen := await _screen()
	# Serve the official feed, but not its zips: the fetch of the download
	# itself fails, as an offline mirror would.
	_served.erase(OFFICIAL_ZIPS + "example.balance.zip")
	var button := _download_button(screen, 0, "example.balance")
	button.emit_signal("pressed")
	await process_frames(2)
	assert_true(ModManager.get_mod_info("example.balance").is_empty(), "nothing was installed")
	assert_true(screen._status.text.contains("Could not install"),
		"the failure is announced (%s)" % screen._status.text)
	assert_true(screen._status.text.contains("No local answer"))
	assert_false(_download_button(screen, 0, "example.balance").disabled,
		"and the row is ready to try again")


# ── entries against the library ──────────────────────────────────────────

func test_a_feed_entry_older_than_the_offering_reads_as_an_update() -> void:
	_install_upgrade_fixture()
	var screen := await _screen()
	store.add_repository(EXTRA_FEED_URL)
	screen.refresh_feed(EXTRA_FEED_URL)
	await process_frames(1)

	var section := 1  # The extra feed, after the official one.
	var update := _download_button(screen, section, "tester.upgrade")
	assert_not_null(update, "the fixture's row exists")
	assert_eq(update.text, "Update")
	assert_false(update.disabled)
	assert_eq(_mod_card(screen, section, "tester.upgrade").text,
		"Upgrade Me  2.0.0\nINSTALLED 0.1.0 · 2.0.0 AVAILABLE",
		"the card names the installed version and the one on offer")
	var fresh := _download_button(screen, section, "example.decorations")
	assert_eq(fresh.text, "Download", "an uninstalled entry still reads as a download")
	var installed := _download_button(screen, section, "golf_tycoon.seasons") if _mod_row(screen, section, "golf_tycoon.seasons") != null else null
	assert_null(installed, "the extra feed does not list the official mods")

	# The same mod on two feeds resolves to the first feed that offers it.
	assert_eq(str(screen.entry_for("tester.upgrade").get("download_url", "")),
		OFFICIAL_ZIPS + "tester.upgrade.zip")


func test_entry_states_against_the_library() -> void:
	assert_eq(BrowseModsScreen.entry_state("", "1.0.0"), BrowseModsScreen.EntryState.DOWNLOAD,
		"not installed: Download")
	assert_eq(BrowseModsScreen.entry_state("1.0.0", "1.0.0"), BrowseModsScreen.EntryState.INSTALLED,
		"same version: Installed")
	assert_eq(BrowseModsScreen.entry_state("1.1.0", "1.0.0"), BrowseModsScreen.EntryState.INSTALLED,
		"installed ahead of the feed: Installed, never a downgrade offer")
	assert_eq(BrowseModsScreen.entry_state("0.9.0", "1.0.0"), BrowseModsScreen.EntryState.UPDATE,
		"installed behind the feed: Update")
	assert_eq(BrowseModsScreen.entry_state("1.0.0", ""), BrowseModsScreen.EntryState.INSTALLED,
		"a feed that names no version cannot promise an update")
	assert_eq(BrowseModsScreen.entry_state_label(BrowseModsScreen.EntryState.DOWNLOAD), "Download")
	assert_eq(BrowseModsScreen.entry_state_label(BrowseModsScreen.EntryState.INSTALLED), "Installed")
	assert_eq(BrowseModsScreen.entry_state_label(BrowseModsScreen.EntryState.UPDATE), "Update")
	assert_true(BrowseModsScreen.entry_state_detail("0.9.0", "1.0.0", BrowseModsScreen.EntryState.UPDATE)
		.contains("0.9.0"), "the detail line names both versions")


# ── feeds: add, fail, remove, restore ────────────────────────────────────

func test_adding_a_feed_lists_and_fetches_it() -> void:
	var screen := await _screen()
	assert_eq(store.repository_count(), 1)
	var add := screen.find_child("AddFeedButton", true, false) as Button
	add.emit_signal("pressed")
	await process_frames(1)
	var dialog := screen.find_child("AddRepositoryDialog", true, false) as AddRepositoryDialog
	assert_not_null(dialog, "the add form opens")
	var url_field := dialog.find_child("UrlField", true, false) as LineEdit
	url_field.text = EXTRA_FEED_URL
	url_field.text_changed.emit(EXTRA_FEED_URL)
	var confirm := dialog.find_child("AddButton", true, false) as Button
	assert_false(confirm.disabled, "a well-formed address is accepted")
	confirm.emit_signal("pressed")
	await process_frames(1)
	assert_null(screen.find_child("AddRepositoryDialog", true, false), "the form closes on success")
	assert_eq(store.repository_count(), 2, "the feed joined the list")
	var card := _repo_card(screen, EXTRA_FEED_URL)
	assert_not_null(card)
	assert_true((card.find_child("RepoStatus", true, false) as Label).text.contains("2 mods on offer"),
		"and was fetched straight away")

	var section := screen._available_box.get_children()[1] as Control
	assert_eq(str(section.get_meta("url", "")), EXTRA_FEED_URL)
	assert_not_null(section.get_node_or_null("ModRow_tester_upgrade"),
		"the self-hosted feed's entries sit under it")
	assert_eq((section.find_child("SectionTitle", true, false) as Label).text, "Backyard Mods",
		"the feed is titled by the name its JSON gives itself")


func test_the_add_form_rejects_a_bad_address_and_cancels_cleanly() -> void:
	var screen := await _screen()
	var add := screen.find_child("AddFeedButton", true, false) as Button
	add.emit_signal("pressed")
	await process_frames(1)
	var dialog := screen.find_child("AddRepositoryDialog", true, false) as AddRepositoryDialog
	var url_field := dialog.find_child("UrlField", true, false) as LineEdit
	var confirm := dialog.find_child("AddButton", true, false) as Button
	var feedback := dialog.find_child("Feedback", true, false) as Label

	assert_true(confirm.disabled, "an empty form offers nothing to press")
	url_field.text = "ftp://example.com/mods.json"
	url_field.text_changed.emit(url_field.text)
	assert_true(confirm.disabled)
	assert_true(feedback.text.contains("http"), "the field says why")

	url_field.text = "https://example.com/my-mods.json"
	url_field.text_changed.emit(url_field.text)
	assert_false(confirm.disabled)
	# The store refuses what the form cannot see: an address already listed.
	# Add it once for real, then offer it a second time.
	confirm.emit_signal("pressed")
	await process_frames(1)
	assert_null(screen.find_child("AddRepositoryDialog", true, false), "a good address closes the form")
	assert_eq(store.repository_count(), 2)

	add.emit_signal("pressed")
	await process_frames(1)
	dialog = screen.find_child("AddRepositoryDialog", true, false) as AddRepositoryDialog
	assert_not_null(dialog, "the form opens again")
	url_field = dialog.find_child("UrlField", true, false) as LineEdit
	confirm = dialog.find_child("AddButton", true, false) as Button
	feedback = dialog.find_child("Feedback", true, false) as Label
	url_field.text = EXTRA_FEED_URL
	url_field.text_changed.emit(url_field.text)
	confirm.emit_signal("pressed")
	await process_frames(1)
	assert_not_null(screen.find_child("AddRepositoryDialog", true, false),
		"a refused address keeps the form open")
	assert_true(feedback.text.contains("already"), "and repeats the store's reason")

	dialog.find_child("CancelButton", true, false).emit_signal("pressed")
	await process_frames(1)
	assert_null(screen.find_child("AddRepositoryDialog", true, false), "cancel closes it")
	assert_eq(store.repository_count(), 2, "and nothing was added by the refusal")


func test_a_feed_that_cannot_be_fetched_says_so_and_the_screen_stays_whole() -> void:
	var screen := await _screen()
	var unreachable := "https://down.example.com/feed.json"
	_serve_failure(unreachable, "That address could not be resolved - check the spelling and your connection.")
	assert_true(bool(store.add_repository(unreachable).get("ok", false)))
	screen.refresh_feed(unreachable)
	await process_frames(1)
	var card := _repo_card(screen, unreachable)
	assert_not_null(card)
	var status := card.find_child("RepoStatus", true, false) as Label
	assert_true(status.text.contains("Could not read this feed"))
	assert_true(status.text.contains("resolved"), "the fetcher's advice is shown")
	assert_null(screen.feed_for(unreachable), "no feed is kept for a failed fetch")
	assert_not_null(screen.feed_for(OFFICIAL_URL), "the other feeds are untouched")
	assert_not_null(_repo_card(screen, OFFICIAL_URL))


func test_a_feed_can_be_removed_and_the_official_restored() -> void:
	var screen := await _screen()
	var card := _repo_card(screen, OFFICIAL_URL)
	(card.find_child("RemoveButton", true, false) as Button).emit_signal("pressed")
	await process_frames(1)
	assert_null(_repo_card(screen, OFFICIAL_URL), "the card goes")
	assert_eq(store.repository_count(), 0, "and the list is empty")
	assert_true(screen.find_child("RestoreOfficialButton", true, false).visible,
		"with the official feed gone, Restore appears")
	assert_true((screen._repositories_empty as Label).visible,
		"the empty repositories panel says why")
	assert_true(screen._status.text.contains("Removed"),
		"the removal is announced")

	(screen.find_child("RestoreOfficialButton", true, false) as Button).emit_signal("pressed")
	await process_frames(1)
	assert_not_null(_repo_card(screen, OFFICIAL_URL), "the official feed is back")
	assert_eq(store.repository_count(), 1)
	assert_false(screen.find_child("RestoreOfficialButton", true, false).visible)


func test_restoring_the_official_repository_fetches_it_again() -> void:
	var screen := await _screen()
	store.remove_repository(OFFICIAL_URL)
	screen.refresh()
	await process_frames(1)
	(screen.find_child("RestoreOfficialButton", true, false) as Button).emit_signal("pressed")
	await process_frames(1)
	assert_not_null(screen.feed_for(OFFICIAL_URL), "the restored feed was fetched at once")


# ── empty and summary text (pure) ────────────────────────────────────────

func test_the_empty_states_explain_themselves() -> void:
	assert_true(BrowseModsScreen.repository_empty_text(0).contains("restore the Official"))
	assert_eq(BrowseModsScreen.repository_empty_text(3), "", "a stocked list says nothing")
	assert_true(BrowseModsScreen.available_empty_text(0, 0).contains("add a repository feed"))
	assert_true(BrowseModsScreen.available_empty_text(2, 0).contains("Refresh"),
		"feeds fetched but empty: the problem is the feeds, not the list")
	assert_eq(BrowseModsScreen.available_empty_text(2, 5), "", "entries on offer, nothing to say")
	assert_true(BrowseModsScreen._summary_text(2, 1, 4, true).contains("1 of 2 feeds fetched"))
	assert_true(BrowseModsScreen._summary_text(2, 2, 36, false)
		.contains("the Official Repository is not on the list"),
		"an absent official feed is called out, not hidden")
	assert_true(BrowseModsScreen._summary_text(0, 0, 0, false).contains("No repository feeds"))


# ── layouts ──────────────────────────────────────────────────────────────

func test_the_screen_fits_narrow_windows_without_overflow() -> void:
	for size in [DESKTOP, TABLET, PHONE, NARROW_PHONE]:
		var screen := await _screen(size)
		await process_frames(2)
		assert_lte(screen.get_combined_minimum_size().x, float(size.x),
			"no horizontal overflow at %dx%d" % [size.x, size.y])
		var frame := screen.get_node("Frame") as Control
		assert_lte(frame.get_combined_minimum_size().x, float(size.x),
			"the page is no wider than the window at %dx%d" % [size.x, size.y])
		var header := screen.find_child("ScreenHeader", true, false)
		assert_lte(header.size.x, float(size.x), "the header fits %dx%d" % [size.x, size.y])
		screen.queue_free()
		await process_frames(1)


func test_phone_portrait_flips_between_the_two_panes() -> void:
	var screen := await _screen(PHONE)
	assert_not_null(screen._tabs, "phone portrait shows the pane tabs")
	assert_true(screen._repositories_panel.visible)
	assert_false(screen._available_panel.visible)
	for button in screen._tabs.get_children():
		if (button as Button).text == "Mods":
			(button as Button).emit_signal("pressed")
	await process_frames(1)
	assert_false(screen._repositories_panel.visible)
	assert_true(screen._available_panel.visible, "the catalogue is behind the Mods tab")


func test_a_window_shape_rebuild_keeps_the_downloader_alive() -> void:
	var screen := await _screen(DESKTOP)
	await resize_window(TABLET)
	await process_frames(2)
	assert_true(is_instance_valid(screen.downloader), "the network layer survives a rebuild")
	assert_eq(screen.downloader, downloader, "and is still the one the test holds")
	var status := (screen.find_child("RepoStatus", true, false) as Label)
	assert_not_null(status, "the rebuilt screen re-fetches nothing and still shows the feed")
	assert_true(status.text.contains("18 mods on offer"))
