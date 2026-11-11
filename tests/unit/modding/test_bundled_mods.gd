extends GameTest
## The mods that ship in res://mods/: every one validates, every referenced
## file exists, the three official feature mods are the default set, the
## examples cover every kind of mod without switching themselves on, and
## the Season mod's events plus the example golfer skin really register.
## (tools/mod_tool.gd runs the same validation in `make mods`.)

const BUNDLED_ROOT := "res://mods"


func after_each() -> void:
	restore_live_content()
	super()


func _bundled_folders() -> Array[String]:
	var folders: Array[String] = []
	var dir := DirAccess.open(BUNDLED_ROOT)
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
		FileAccess.get_file_as_string(BUNDLED_ROOT.path_join(folder).path_join("mod.json")),
		folder)


func test_every_bundled_manifest_validates_and_references_real_files() -> void:
	var folders := _bundled_folders()
	assert_eq(folders.size(), 14, "three official mods and eleven examples ship with the game")
	for folder in folders:
		var root := BUNDLED_ROOT.path_join(folder)
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


func test_the_official_mods_are_the_defaults_and_the_examples_stay_off() -> void:
	var enabled_by_default: Array = []
	for folder in _bundled_folders():
		var manifest := _manifest_of(folder)
		if folder.begins_with("golf_tycoon."):
			assert_true(manifest.enabled_by_default, "%s is on out of the box" % folder)
			enabled_by_default.append(manifest.id)
		else:
			assert_false(manifest.enabled_by_default, "%s waits to be invited" % folder)
	assert_eq(enabled_by_default.size(), 3, "Seasons, Weather and Wind")


func test_bundled_ids_are_unique_and_the_template_stays_inert() -> void:
	var ids := {}
	for folder in _bundled_folders():
		var manifest := _manifest_of(folder)
		assert_false(ids.has(manifest.id), "%s reuses an id" % manifest.id)
		ids[manifest.id] = true
	var infos := {}
	for info in ModManager.get_all_mod_infos():
		infos[str(info.get("id", ""))] = info
	assert_false(infos.has("yourname.my_mod"), "the _template folder is never discovered")


func test_every_bundled_mod_ships_a_distinct_icon_the_manager_resolves() -> void:
	var seen: Dictionary = {}
	for folder in _bundled_folders():
		var manifest := _manifest_of(folder)
		var texture: Texture2D = ModManager.get_mod_icon_texture(manifest.id)
		assert_not_null(texture, "%s resolves its icon in the live manager" % folder)
		var image := (texture as ImageTexture).get_image()
		assert_eq(image.get_width(), image.get_height(), "%s icon is square" % folder)
		assert_lte(image.get_width(), ModManager.ICON_MAX_SIDE,
			"%s icon is capped to a display size" % folder)
		# The picture's own pixels: two mods must not wear the same one, or
		# the shelf of icons stops saying which is which. (Packed arrays
		# hash by content, so the bytes are their own fingerprint.)
		var fingerprint := image.get_data()
		assert_false(seen.has(fingerprint), "%s reuses another mod's icon" % folder)
		seen[fingerprint] = manifest.id


func test_the_seasons_mod_events_are_registered_in_this_session() -> void:
	var names: Array = SeasonalEvents.get_all_events().map(func(e): return e.name)
	assert_eq(SeasonalEvents.registered_count(), 8, "eight shipped events")
	for expected in ["Spring Opening Week", "Charity Scramble", "Peak Season"]:
		assert_true(expected in names, "%s is on the calendar" % expected)


func test_the_seasons_mod_tree_art_is_registered_in_this_session() -> void:
	# The seasonal drawings travel inside the mod (its `tree_art_root`), not in
	# the game's own assets: with the mod off, a wood has no wardrobe to wear.
	var spring_oak := TreeOverlay.art_file("spring/oak", TreeOverlay.DEFAULT_FACING)
	assert_true(spring_oak.begins_with("res://mods/golf_tycoon.seasons/tree_art/"),
			"a spring oak is drawn from inside the mod (%s)" % spring_oak)
	assert_not_null(TreeOverlay.texture_at(spring_oak), "and its art loads from there")


func test_the_example_golfer_skin_loads_through_the_library() -> void:
	ContentRegistry.apply_mod_content("example.golfers",
		BUNDLED_ROOT.path_join("example.golfers"),
		{"golfer_names": "data/names.json", "golfer_skins_root": "golfer_skins"})
	var library := GolferSkinLibrary.new()
	var ids: Array = library.skins().map(func(s): return s.id)
	assert_true("high_viz" in ids,
		"a recolor-only skin (no painted layers) parses and registers")
	# The library is RefCounted; it frees itself.


func test_more_seasons_is_a_true_add_on() -> void:
	var manifest := _manifest_of("example.more_seasons")
	var deps: Array = manifest.dependencies.map(func(d): return str(d.get("id", "")))
	assert_true("golf_tycoon.seasons" in deps, "it hard-depends on the Seasons mod")
	var hard: Array = manifest.dependencies.filter(func(d): return str(d.get("id", "")) == "golf_tycoon.seasons")
	assert_false(bool(hard[0].get("optional", true)), "and the dependency is not optional")


func test_the_example_backgrounds_mod_ships_pictures_and_overlays() -> void:
	ContentRegistry.apply_mod_content("example.backgrounds",
		BUNDLED_ROOT.path_join("example.backgrounds"),
		{"menu_backdrops": "data/backdrops.json", "menu_overlays": "data/overlays.json"})
	assert_eq(ContentRegistry.get_warnings().size(), 0,
		"the example loads without a single warning")
	for id in ["example.backgrounds:harbour_dusk", "example.backgrounds:moonlit_frost"]:
		assert_true(MenuBackdropCatalog.has_backdrop(id), "%s is on offer" % id)
		var entry := MenuBackdropCatalog.backdrop(id)
		var art: String = str(entry.get("image", ""))
		assert_true(art.begins_with("res://mods/example.backgrounds/"),
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
