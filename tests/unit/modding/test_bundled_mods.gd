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
	assert_eq(folders.size(), 12, "three official mods and nine examples ship with the game")
	for folder in folders:
		var root := BUNDLED_ROOT.path_join(folder)
		var manifest := _manifest_of(folder)
		assert_true(manifest.is_valid(), "%s validates: %s" % [folder, "; ".join(manifest.errors)])
		assert_eq(manifest.api_version, ModManifest.CURRENT_API_VERSION, "%s speaks the current API" % folder)
		if manifest.has_script():
			assert_true(FileAccess.file_exists(root.path_join(manifest.entry_point)),
				"%s entry point exists" % folder)
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
