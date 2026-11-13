extends GameTest
## The mod packages the game publishes (res://repository/packages/): every
## one validates, every referenced file exists, the zips the Official
## Repository serves match the packages file for file, and the Official
## Repository feed lists exactly those zips. The Seasons package's events,
## the example golfer skin and the GUI examples really register when their
## content is applied - the way the loader would, after a download.
## (tools/mod_tool.gd builds the zips and the feed in `make repository`.)

const ModManagerScript := preload("res://scripts/modding/mod_manager.gd")
const PACKAGES_ROOT := "res://repository/packages"
const ZIPS_ROOT := "res://repository/zips"
const FEED_PATH := "res://repository/official.json"


func after_each() -> void:
	restore_live_content()
	super()


func _package_folders() -> Array[String]:
	var folders: Array[String] = []
	var dir := DirAccess.open(PACKAGES_ROOT)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with(".") and not entry.begins_with("_"):
			folders.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	folders.sort()
	return folders


func _manifest_of(folder: String) -> ModManifest:
	return ModManifest.from_json_text(
		FileAccess.get_file_as_string(PACKAGES_ROOT.path_join(folder).path_join("mod.json")),
		folder)


func _feed_text() -> String:
	return FileAccess.get_file_as_string(FEED_PATH)


func _official_feed() -> ModRepositoryFeed:
	return ModRepositoryFeed.parse(_feed_text(), ModRepositoryStore.OFFICIAL_REPOSITORY_URL)


# ── the packages ─────────────────────────────────────────────────────────

func test_every_package_manifest_validates_and_references_real_files() -> void:
	var folders := _package_folders()
	assert_eq(folders.size(), 18, "three official mods and fifteen examples are published")
	for folder in folders:
		var root := PACKAGES_ROOT.path_join(folder)
		var manifest := _manifest_of(folder)
		assert_true(manifest.is_valid(), "%s validates: %s" % [folder, "; ".join(manifest.errors)])
		assert_eq(manifest.api_version, ModManifest.CURRENT_API_VERSION, "%s speaks the current API" % folder)
		if manifest.has_script():
			assert_true(FileAccess.file_exists(root.path_join(manifest.entry_point)),
				"%s entry point exists" % folder)
		assert_false(manifest.icon.is_empty(), "%s declares an icon" % folder)
		assert_true(FileAccess.file_exists(root.path_join(manifest.icon)),
			"%s icon exists (%s)" % [folder, manifest.icon])
		for kind in manifest.content:
			var declared: Variant = manifest.content[kind]
			var paths: Array = []
			if declared is String:
				paths.append(declared)
			elif declared is Dictionary:
				paths.append_array(declared.values())
			for relative in paths:
				var target := root.path_join(str(relative))
				assert_true(FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target),
					"%s content %s exists" % [folder, str(relative)])


func test_package_ids_are_unique() -> void:
	var ids := {}
	for folder in _package_folders():
		var manifest := _manifest_of(folder)
		assert_false(ids.has(manifest.id), "%s reuses an id" % manifest.id)
		ids[manifest.id] = true
	for id in ["golf_tycoon.seasons", "golf_tycoon.weather", "golf_tycoon.wind"]:
		assert_true(ids.has(id), "the official %s is published" % id)


func test_nothing_is_bundled_with_the_game_any_more() -> void:
	# The game package carries no mods: what used to be res://mods/ now
	# lives in the repository, downloaded from a feed. Whatever a player
	# (or a test fixture) has installed came through the library - no mod
	# anywhere claims to ship with the game.
	for info in ModManager.get_all_mod_infos():
		assert_ne(str(info.get("source", "")), ModManager.SOURCE_BUNDLED,
			"%s claims to be bundled" % str(info.get("id", "")))
	# The game's own mods folder ships no mods: whatever folders it keeps
	# (the modders' templates) are underscore-prefixed and never discovered.
	var dir := DirAccess.open("res://mods")
	assert_not_null(dir, "the mods folder exists for the templates")
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("_"):
			assert_false(FileAccess.file_exists("res://mods".path_join(entry).path_join("mod.json")),
				"%s ships a mod.json; the game no longer bundles mods" % entry)
		entry = dir.get_next()
	dir.list_dir_end()


func test_every_published_mod_ships_a_distinct_icon_the_manager_resolves() -> void:
	for folder in _package_folders():
		var manifest := _manifest_of(folder)
		var texture: Texture2D = null
		var image := ModManager.load_mod_image(
			PACKAGES_ROOT.path_join(folder).path_join(manifest.icon))
		if image != null:
			texture = ModManagerScript.square_icon_texture(image)
		assert_not_null(texture, "%s resolves its icon" % folder)
		assert_eq((texture as ImageTexture).get_image().get_width(),
			(texture as ImageTexture).get_image().get_height(), "%s icon is square" % folder)
		assert_lte((texture as ImageTexture).get_image().get_width(), ModManager.ICON_MAX_SIDE,
			"%s icon is capped to a display size" % folder)


func test_more_seasons_is_a_true_add_on() -> void:
	var manifest := _manifest_of("example.more_seasons")
	var deps: Array = manifest.dependencies.map(func(d): return str(d.get("id", "")))
	assert_true("golf_tycoon.seasons" in deps, "it hard-depends on the Seasons mod")
	var hard: Array = manifest.dependencies.filter(func(d): return str(d.get("id", "")) == "golf_tycoon.seasons")
	assert_false(bool(hard[0].get("optional", true)), "and the dependency is not optional")


# ── the zips the Official Repository serves ──────────────────────────────

func test_every_package_has_a_zip_that_matches_it_file_for_file() -> void:
	for folder in _package_folders():
		var manifest := _manifest_of(folder)
		var zip_path := ZIPS_ROOT.path_join(manifest.id + ".zip")
		assert_true(FileAccess.file_exists(zip_path), "%s has a committed zip" % manifest.id)
		var read: Dictionary = ModPackage.read_manifest_from_zip(zip_path)
		assert_true(bool(read.get("ok", false)), "%s zip validates: %s"
			% [manifest.id, "; ".join(read.get("errors", []))])
		var prefix := str(read.get("root_prefix", ""))
		# The zip's files are the folder's files, byte for byte: the
		# published zip is exactly the package, or a player downloads
		# something other than what the repository source says it ships.
		var folder_root := PACKAGES_ROOT.path_join(folder)
		var expected := ModPackage.list_files(folder_root)
		var reader := ZIPReader.new()
		assert_eq(reader.open(zip_path), OK, "%s zip opens" % manifest.id)
		var zip_files: PackedStringArray = reader.get_files()
		var zip_relative: Array[String] = []
		for entry in zip_files:
			if entry.ends_with("/"):
				continue
			assert_true(entry.begins_with(prefix), "%s zip entry %s is inside the mod" % [manifest.id, entry])
			zip_relative.append(entry.trim_prefix(prefix))
		zip_relative.sort()
		assert_eq(zip_relative, expected, "%s zip holds the package's files and nothing else" % manifest.id)
		for relative in expected:
			var in_zip := reader.read_file(prefix + relative)
			assert_eq(in_zip, FileAccess.get_file_as_bytes(folder_root.path_join(relative)),
				"%s/%s is identical in zip and package" % [manifest.id, relative])
		reader.close()


func test_a_published_zip_installs_like_any_player_zip() -> void:
	# The Browse screen's install is ModPackage.install_zip: run it on the
	# committed Seasons zip and the result is an ordinary disabled library
	# mod, icons and all.
	var zip_path := ZIPS_ROOT.path_join("golf_tycoon.seasons.zip")
	var target := "user://ut_repository_install"
	DirAccess.make_dir_recursive_absolute(target)
	var installed: Dictionary = ModPackage.install_zip(zip_path, target)
	assert_true(bool(installed.get("ok", false)), "the zip installs: %s"
		% "; ".join(installed.get("errors", [])))
	assert_eq(str(installed.get("mod_id", "")), "golf_tycoon.seasons")
	var root := str(installed.get("directory", ""))
	var manifest := ModManifest.from_json_text(
		FileAccess.get_file_as_string(root.path_join("mod.json")), root)
	assert_true(manifest.is_valid(), "the installed copy validates")
	assert_not_null(ModManager.load_mod_image(root.path_join(manifest.icon)),
		"and its icon rides along")
	ModPackage.remove_directory_recursive(target)


# ── the Official Repository feed ─────────────────────────────────────────

func test_the_official_feed_parses_and_lists_every_package() -> void:
	var feed := _official_feed()
	assert_true(feed.is_valid(), "the feed parses: %s" % "; ".join(feed.errors))
	assert_eq(feed.name, "Golf Tycoon Official Repository")
	assert_eq(feed.entry_count(), _package_folders().size(), "one entry per package")
	var ids := {}
	for entry in feed.entries:
		ids[str(entry.get("id", ""))] = entry
	for folder in _package_folders():
		var manifest := _manifest_of(folder)
		assert_true(ids.has(manifest.id), "%s is on the feed" % manifest.id)
		if not ids.has(manifest.id):
			continue
		var entry: Dictionary = ids[manifest.id]
		assert_eq(str(entry.get("name", "")), manifest.name)
		assert_eq(str(entry.get("version", "")), manifest.version,
			"%s's feed version matches its manifest" % manifest.id)
		assert_eq(str(entry.get("download_url", "")),
			"https://raw.githubusercontent.com/GolfTycoon/Golf-Tycoon/main/repository/zips/%s.zip" % manifest.id)
		var zip_path := ZIPS_ROOT.path_join(manifest.id + ".zip")
		assert_eq(int(entry.get("size_bytes", 0)),
			FileAccess.open(zip_path, FileAccess.READ).get_length(),
			"%s's feed size matches the committed zip" % manifest.id)


func test_the_official_feed_url_is_the_one_the_game_ships_pointing_at() -> void:
	var feed := _official_feed()
	assert_true(feed.is_valid())
	# The store adds this exact address by default; the feed in the
	# repository is what answers there.
	assert_true(feed.source_url == "" or feed.source_url == ModRepositoryStore.OFFICIAL_REPOSITORY_URL)


# ── the packages' content registers when applied ─────────────────────────

func test_the_seasons_package_events_register_when_applied() -> void:
	# Nothing is bundled, so a fresh boot registers no events at all.
	assert_eq(SeasonalEvents.registered_count(), 0, "a fresh install has no seasonal events")
	# Applying the package (as the loader does once it is downloaded and
	# ticked) puts the shipped calendar in place.
	apply_package_content(PACKAGES_ROOT.path_join("golf_tycoon.seasons"))
	var names: Array = SeasonalEvents.get_all_events().map(func(e): return e.name)
	assert_eq(SeasonalEvents.registered_count(), 8, "eight shipped events")
	for expected in ["Spring Opening Week", "Charity Scramble", "Peak Season"]:
		assert_true(expected in names, "%s is on the calendar" % expected)


func test_the_seasons_package_tree_art_registers_when_applied() -> void:
	# The seasonal drawings travel inside the package (its `tree_art_root`),
	# not in the game's own assets: before the download, a wood has no
	# wardrobe to wear.
	assert_eq(TreeOverlay.art_file("spring/oak", TreeOverlay.DEFAULT_FACING), "",
		"with no seasons mod, a spring oak has no seasonal art")
	apply_package_content(PACKAGES_ROOT.path_join("golf_tycoon.seasons"))
	var spring_oak := TreeOverlay.art_file("spring/oak", TreeOverlay.DEFAULT_FACING)
	assert_true(spring_oak.begins_with("res://repository/packages/golf_tycoon.seasons/tree_art/"),
			"a spring oak is drawn from inside the package (%s)" % spring_oak)
	assert_not_null(TreeOverlay.texture_at(spring_oak), "and its art loads from there")


func test_the_example_golfer_skin_loads_through_the_library() -> void:
	ContentRegistry.apply_mod_content("example.golfers",
		PACKAGES_ROOT.path_join("example.golfers"),
		{"golfer_names": "data/names.json", "golfer_skins_root": "golfer_skins"})
	var library := GolferSkinLibrary.new()
	var ids: Array = library.skins().map(func(s): return s.id)
	assert_true("high_viz" in ids,
		"a recolor-only skin (no painted layers) parses and registers")
	# The library is RefCounted; it frees itself.


func test_the_gui_theme_examples_each_register_a_complete_design() -> void:
	# Every GUI example is data-only and dresses the whole interface:
	# applying its content (as the loader does, in order) puts its design
	# in force, and the next GUI mod replaces it - lower in the list wins.
	const GUI_EXAMPLES: Array = [
		["example.gui_glass", "Modern Glass"],
		["example.gui_neon", "Neon Fairway"],
		["example.gui_parchment", "Clubhouse Parchment"],
		["example.gui_porcelain", "Porcelain Fairway"],
	]
	var warnings_before := ContentRegistry.get_warnings().size()
	for entry in GUI_EXAMPLES:
		var mod_id: String = entry[0]
		var folder := PACKAGES_ROOT.path_join(mod_id)
		var manifest := _manifest_of(mod_id)
		assert_false(manifest.has_script(), "%s needs no code to re-dress the game" % mod_id)
		assert_true(manifest.content.has("gui_theme"), "%s declares a GUI theme" % mod_id)
		ContentRegistry.apply_mod_content(mod_id, folder, manifest.content)
		assert_eq(ContentRegistry.get_gui_theme_source(), mod_id,
			"%s's design is in force once it has loaded" % mod_id)
		var theme := ContentRegistry.get_gui_theme()
		assert_not_null(theme, "%s produced a theme" % mod_id)
		assert_eq(theme.theme_name, entry[1])
		# A complete design: the handful of roles every screen is painted
		# from must all differ from stock, or part of the game would keep
		# its green while the rest changed clothes.
		for role in ["panel", "button", "text", "accent", "border", "bottom_bar"]:
			assert_false(GuiTheme._same_color(theme.color(role), GuiTheme.default_colors()[role]),
				"%s restyles %s" % [entry[1], role])
		assert_eq(theme.warnings, [], "%s parses without a warning" % mod_id)
		# And the files each palette names really load through the registry.
		match mod_id:
			"example.gui_glass":
				assert_not_null(theme.font_bold, "glass ships its display font")
			"example.gui_parchment":
				assert_not_null(theme.font, "parchment ships its body font")
			"example.gui_neon":
				assert_eq(theme.rules.size(), 1, "neon ships its Mods-screen rule")
				assert_not_null(theme.rules[0].get("icon"), "and its bolt icon loads")
	assert_eq(ContentRegistry.get_warnings().size(), warnings_before,
		"no GUI example costs a registry warning: %s" % str(ContentRegistry.get_warnings()))
	var summary: Dictionary = ContentRegistry.get_content_summary()
	assert_eq(int((summary["example.gui_porcelain"] as Dictionary).get("gui_theme", 0)), 1,
		"the winning design is counted for its mod")


func test_the_example_backgrounds_mod_ships_pictures_and_overlays() -> void:
	ContentRegistry.apply_mod_content("example.backgrounds",
		PACKAGES_ROOT.path_join("example.backgrounds"),
		{"menu_backdrops": "data/backdrops.json", "menu_overlays": "data/overlays.json"})
	assert_eq(ContentRegistry.get_warnings().size(), 0,
		"the example loads without a single warning")
	for id in ["example.backgrounds:harbour_dusk", "example.backgrounds:moonlit_frost"]:
		assert_true(MenuBackdropCatalog.has_backdrop(id), "%s is on offer" % id)
		var entry := MenuBackdropCatalog.backdrop(id)
		var art: String = str(entry.get("image", ""))
		assert_true(art.begins_with("res://repository/packages/example.backgrounds/"),
			"its picture is shipped inside the mod (%s)" % art)
		assert_not_null(load(art), "and the picture loads")
		assert_eq(str(entry.get("source", "")), "example.backgrounds",
			"and is credited to the mod")
	for id in ["example.backgrounds:starfield", "example.backgrounds:club_crest",
			"example.backgrounds:green_keeper_bands"]:
		assert_true(MenuBackdropCatalog.has_overlay(id), "%s is on offer" % id)
	# Each overlay gets a row for every setting it names, drawn from the shipped
	# catalogue or from the mod's own `settings` block.
	var density := MenuBackdropCatalog.settings_for("example.backgrounds:starfield")
	assert_eq(density.size(), 1, "Starfield offers its one setting")
	assert_eq(str(density[0].get("key", "")), "density", "the shipped Density")
	var angle := MenuBackdropCatalog.settings_for("example.backgrounds:club_crest")
	assert_eq(angle.size(), 1)
	assert_eq(str(angle[0].get("key", "")), "angle", "and the shipped Angle")
	var summary: Dictionary = ContentRegistry.get_content_summary().get("example.backgrounds", {})
	assert_eq(int(summary.get("backdrops", 0)), 2, "two pictures are counted for the mod")
	assert_eq(int(summary.get("overlays", 0)), 3, "and three overlays")
