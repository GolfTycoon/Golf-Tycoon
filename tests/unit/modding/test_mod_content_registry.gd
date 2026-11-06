extends GameTest
## ContentRegistry: how mod data becomes game data - namespacing new
## entries, deep-merging patches over shipped ones, replace/remove,
## conflict bookkeeping, tuning and the pushes into the static libraries.
## Uses a throwaway registry against temp mod folders; the real mod set is
## reloaded afterwards so later tests see the shipped state again.
## (scripts/modding/mod_content_registry.gd)

const RegistryScript := preload("res://scripts/modding/mod_content_registry.gd")
const ROOT := "user://ut_content_registry"

var registry: Node = null


func before_each() -> void:
	super()
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("mod_a"))
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("mod_b"))
	registry = RegistryScript.new()
	add_child_autofree(registry)


func after_each() -> void:
	restore_live_content()
	_cleanup()
	super()


func _cleanup() -> void:
	ModPackage.remove_directory_recursive(ROOT)


func _write(mod_folder: String, relative: String, json_text: String) -> void:
	var path := ROOT.path_join(mod_folder).path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(json_text)
	file.close()


## A tiny real PNG, for the content kinds that ship art rather than JSON.
func _write_png(mod_folder: String, relative: String) -> String:
	var path := ROOT.path_join(mod_folder).path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	image.save_png(path)
	return path


# ---------------------------------------------------------------------------
# Menu backgrounds and overlays (content.menu_backdrops / menu_overlays)
# ---------------------------------------------------------------------------

func test_a_mod_adds_menu_pictures_and_overlays_from_its_own_folder() -> void:
	_write_png("mod_a", "art/aurora.png")
	_write("mod_a", "backdrops.json",
		'{"backdrops": {"aurora": {"name": "Aurora", "image": "art/aurora.png", "seasons": ["winter"]}}}')
	_write("mod_a", "overlays.json",
		'{"overlays": {"stars": {"name": "Stars", "pattern": "sparkle", "strength": 0.5}},'
		+ ' "settings": {"twinkle": {"name": "Twinkle", "default": 0, "choices": ["Off", "On"], "values": [0, 1]}}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"),
		{"menu_backdrops": "backdrops.json", "menu_overlays": "overlays.json"})

	assert_true(MenuBackdropCatalog.has_backdrop("tester.a:aurora"),
		"a new picture is namespaced under its mod")
	assert_eq(MenuBackdropCatalog.backdrop("tester.a:aurora")["image"],
		ROOT.path_join("mod_a").path_join("art/aurora.png"),
		"and its picture resolves against the mod's own folder")
	assert_true(MenuBackdropCatalog.has_overlay("tester.a:stars"))
	assert_eq(MenuBackdropCatalog.overlay("tester.a:stars")["pattern"], "sparkle")
	assert_eq(MenuBackdropCatalog.settings_for("tester.a:stars").size(), 0,
		"an overlay only exposes the settings it lists")
	assert_eq(str(MenuBackdropCatalog.backdrop_source("tester.a:aurora")), "tester.a",
		"the registry credits the mod that added it")


func test_a_mod_patches_a_shipped_picture_by_naming_its_id() -> void:
	_write("mod_a", "backdrops.json",
		'{"backdrops": {"clubhouse": {"tint": "ffcc88", "scrim": 0.6}}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"),
		{"menu_backdrops": "backdrops.json"})

	var clubhouse := MenuBackdropCatalog.backdrop("clubhouse")
	assert_eq(str(clubhouse["name"]), "Clubhouse", "the shipped name survives a patch")
	assert_eq(clubhouse["tint"], Color.html("ffcc88"), "the patch's tint lands")
	assert_almost_eq(float(clubhouse["scrim"]), 0.6, 0.001)
	assert_eq(str(MenuBackdropCatalog.backdrop_source("clubhouse")), "tester.a")


func test_each_mod_gets_its_own_namespace_and_a_later_mod_can_repaint_one() -> void:
	_write("mod_a", "backdrops.json", '{"backdrops": {"aurora": {"name": "Aurora A", "image": "a.png"}}}')
	_write("mod_b", "backdrops.json", '{"backdrops": {"aurora": {"name": "Aurora B", "image": "b.png"}}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"menu_backdrops": "backdrops.json"})
	registry.apply_mod_content("tester.b", ROOT.path_join("mod_b"), {"menu_backdrops": "backdrops.json"})
	# A bare id is new to each mod, so each gets its own namespaced entry - the
	# two mods' Auroras cannot collide, and both stay on offer.
	assert_true(MenuBackdropCatalog.has_backdrop("tester.a:aurora"))
	assert_true(MenuBackdropCatalog.has_backdrop("tester.b:aurora"))
	assert_eq(str(MenuBackdropCatalog.backdrop("tester.a:aurora")["name"]), "Aurora A")
	assert_eq(str(MenuBackdropCatalog.backdrop("tester.b:aurora")["name"]), "Aurora B")

	# Naming an id that already exists is a patch: later in the load order wins,
	# and the entry keeps the id (and the picture) it already had.
	_write("mod_b", "backdrops.json", '{"backdrops": {"tester.a:aurora": {"tint": "ffcc88"}}}')
	registry.apply_mod_content("tester.b", ROOT.path_join("mod_b"), {"menu_backdrops": "backdrops.json"})
	var patched := MenuBackdropCatalog.backdrop("tester.a:aurora")
	assert_eq(str(patched["name"]), "Aurora A", "the name a patch did not mention survives")
	assert_eq(patched["tint"], Color.html("ffcc88"), "the tint it did mention lands")
	assert_eq(str(MenuBackdropCatalog.backdrop_source("tester.a:aurora")), "tester.b",
		"and the later mod is credited")


func test_a_picture_with_no_image_is_reported_and_left_out() -> void:
	_write("mod_a", "backdrops.json", '{"backdrops": {"empty": {"name": "Empty"}}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"menu_backdrops": "backdrops.json"})
	assert_false(MenuBackdropCatalog.has_backdrop("tester.a:empty"),
		"a picture with no file would paint nothing, so it is dropped")
	var warnings: Array = registry.get_warnings()
	var found := false
	for warning in warnings:
		if str(warning).contains("empty") and str(warning).contains("image"):
			found = true
	assert_true(found, "and the player hears about it: %s" % str(warnings))


func test_resetting_the_registry_drops_every_menu_style() -> void:
	_write_png("mod_a", "art/aurora.png")
	_write("mod_a", "backdrops.json", '{"backdrops": {"aurora": {"image": "art/aurora.png"}}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"menu_backdrops": "backdrops.json"})
	assert_true(MenuBackdropCatalog.has_backdrop("tester.a:aurora"))
	registry.reset_mod_content()
	assert_false(MenuBackdropCatalog.has_backdrop("tester.a:aurora"),
		"switching the mod off takes its pictures with it")
	assert_true(MenuBackdropCatalog.has_backdrop("clubhouse"), "the shipped ones stay")


func test_the_content_summary_counts_menu_styles() -> void:
	_write_png("mod_a", "art/aurora.png")
	_write("mod_a", "backdrops.json", '{"backdrops": {"aurora": {"image": "art/aurora.png"}}}')
	_write("mod_a", "overlays.json", '{"overlays": {"stars": {"pattern": "sparkle"}}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"),
		{"menu_backdrops": "backdrops.json", "menu_overlays": "overlays.json"})
	var summary: Dictionary = registry.get_content_summary()
	assert_eq(int((summary["tester.a"] as Dictionary).get("backdrops", 0)), 1)
	assert_eq(int((summary["tester.a"] as Dictionary).get("overlays", 0)), 1)


func test_the_manifest_knows_the_menu_content_keys() -> void:
	assert_true("menu_backdrops" in ModManifest.KNOWN_CONTENT_KEYS)
	assert_true("menu_overlays" in ModManifest.KNOWN_CONTENT_KEYS)
	var manifest := ModManifest.from_json_text(JSON.stringify({
		"format_version": 1, "id": "tester.menu", "name": "Menu", "version": "1.0.0",
		"api_version": 1, "description": "d",
		"content": {"menu_backdrops": "b.json", "menu_overlays": "o.json"},
	}))
	assert_true(manifest.is_valid(), "a menu-background mod validates: %s" % str(manifest.errors))
	for warning in manifest.warnings:
		assert_false(str(warning).contains("menu_backdrops"), "the key is not reported as unknown")


# ---------------------------------------------------------------------------
# Catalogs: add, patch, replace, remove
# ---------------------------------------------------------------------------

func test_a_new_entry_is_namespaced_under_its_mod() -> void:
	_write("mod_a", "buildings.json", '{"tower": {"name": "Tower", "color": "ff8800"}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"buildings": "buildings.json"})
	assert_true(registry.has_building("tester.a:tower"), "new ids gain the mod's namespace")
	assert_false(registry.has_building("tower"), "so two mods' towers cannot collide")
	var tower: Dictionary = registry.get_building("tester.a:tower")
	assert_eq(tower.get("id"), "tester.a:tower", "the entry knows its full id")
	assert_eq(tower.get("size", []), [1, 1], "a sparse entry is padded out, not broken")
	assert_eq(registry.source_of("buildings", "tester.a:tower"), "tester.a", "provenance is recorded")
	assert_eq(registry.resolve_new_id("tester.a", "x"), "tester.a:x")
	assert_eq(registry.resolve_new_id("tester.a", "other:y"), "other:y", "already-namespaced ids pass through")


func test_patching_a_shipped_entry_deep_merges_in_place() -> void:
	_write("mod_a", "buildings.json", '{"snack_bar": {"cost": 99}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"buildings": "buildings.json"})
	var snack: Dictionary = registry.get_building("snack_bar")
	assert_eq(int(snack.get("cost", 0)), 99, "the patched field changes")
	assert_eq(str(snack.get("name", "")), "Snack Bar", "and the unpatched fields survive")
	assert_eq(registry.source_of("buildings", "snack_bar"), "tester.a")
	assert_true(registry.get_conflicts().is_empty(), "patching core data is not a mod conflict")


func test_two_mods_writing_one_entry_is_a_reported_conflict() -> void:
	_write("mod_a", "buildings.json", '{"snack_bar": {"cost": 111}}')
	_write("mod_b", "buildings.json", '{"snack_bar": {"cost": 222}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"buildings": "buildings.json"})
	registry.apply_mod_content("tester.b", ROOT.path_join("mod_b"), {"buildings": "buildings.json"})
	assert_eq(int(registry.get_building("snack_bar").get("cost", 0)), 222,
		"later in the load order wins")
	var conflicts: Array = registry.get_conflicts()
	assert_eq(conflicts.size(), 1, "and the overwrite is reported, by name")
	assert_true(str(conflicts[0]).contains("tester.a") and str(conflicts[0]).contains("tester.b"))


func test_replace_and_remove_markers_do_what_they_say() -> void:
	_write("mod_a", "buildings.json",
		'{"snack_bar": {"__replace__": true, "name": "Only This"}, "putting_green": {"__remove__": true}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"buildings": "buildings.json"})
	var snack: Dictionary = registry.get_building("snack_bar")
	assert_eq(str(snack.get("name", "")), "Only This")
	assert_eq(int(snack.get("cost", -1)), 0, "__replace__ discards the shipped entry whole (cost normalises to 0)")
	assert_false(registry.has_building("putting_green"), "__remove__ deletes the entry")


func test_a_required_entry_refuses_removal() -> void:
	_write("mod_a", "buildings.json", '{"clubhouse": {"__remove__": true}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"buildings": "buildings.json"})
	assert_true(registry.has_building("clubhouse"), "the clubhouse is required by the game")
	assert_true(registry.get_warnings().any(func(w): return w.contains("clubhouse")),
		"and the refusal is explained")


func test_foreign_namespaces_cannot_be_forged() -> void:
	_write("mod_a", "buildings.json", '{"tester.b:sneaky": {"name": "Sneaky"}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"buildings": "buildings.json"})
	assert_false(registry.has_building("tester.b:sneaky"),
		"you may patch another mod's existing entry, not mint one in its name")


func test_deep_merge_merges_objects_and_replaces_arrays() -> void:
	var merged: Dictionary = ContentRegistryClass.deep_merge(
		{"a": {"x": 1, "y": 2}, "list": [1, 2], "keep": true},
		{"a": {"x": 9}, "list": [3]})
	assert_eq(merged, {"a": {"x": 9, "y": 2}, "list": [3], "keep": true})


# The registry class has no class_name (the autoload alone is ContentRegistry),
# so deep_merge is reached through the instance/preload in these tests.
const ContentRegistryClass := preload("res://scripts/modding/mod_content_registry.gd")


# ---------------------------------------------------------------------------
# Tuning, terrain and events
# ---------------------------------------------------------------------------

func test_tuning_values_land_and_the_last_mod_wins() -> void:
	_write("mod_a", "tuning.json", '{"tuning": {"golfers.spawn_multiplier": 1.1, "oops": "soup"}}')
	_write("mod_b", "tuning.json", '{"tuning": {"golfers.spawn_multiplier": 0.5}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"tuning": "tuning.json"})
	registry.apply_mod_content("tester.b", ROOT.path_join("mod_b"), {"tuning": "tuning.json"})
	assert_almost_eq(registry.get_tuning("golfers.spawn_multiplier", 1.0), 0.5, 0.0001)
	assert_false(registry.has_tuning("oops"), "a non-number tuning value is skipped")
	assert_true(registry.get_warnings().any(func(w): return w.contains("oops")))


func test_terrain_overrides_reach_terrain_types() -> void:
	var fairway := TerrainTypes.Type.FAIRWAY
	var before: int = TerrainTypes.get_placement_cost(fairway)
	_write("mod_a", "terrain.json", '{"terrain": {"fairway": {"placement_cost": 4242}}}')
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"terrain_overrides": "terrain.json"})
	assert_eq(TerrainTypes.get_placement_cost(fairway), 4242,
		"the override is pushed into the static library readers everywhere use")
	registry.reset_mod_content()
	assert_eq(TerrainTypes.get_placement_cost(fairway), before, "and a reset puts the shipped value back")


func test_seasonal_events_register_namespaced_and_replace_by_full_id() -> void:
	_write("mod_a", "events.json", """{"events": [
		{"id": "harvest_fair", "name": "Harvest Fair", "season": "fall", "day_in_season": 10, "duration_days": 3},
		{"name": "Nameless", "season": "fall"}
	]}""")
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"seasonal_events": "events.json"})
	var ids: Array = SeasonalEvents.get_all_events().map(func(e): return e.id)
	assert_true("tester.a:harvest_fair" in ids, "a new event is namespaced like any content")

	_write("mod_b", "events.json", """{"events": [
		{"id": "tester.a:harvest_fair", "name": "Harvest Fair Deluxe", "season": "fall", "day_in_season": 12, "duration_days": 5}
	]}""")
	registry.apply_mod_content("tester.b", ROOT.path_join("mod_b"), {"seasonal_events": "events.json"})
	var names: Array = SeasonalEvents.get_all_events().map(func(e): return e.name)
	assert_true("Harvest Fair Deluxe" in names, "a full-id record replaces the earlier event whole")
	assert_false("Harvest Fair" in names)


func test_tree_art_registers_with_the_overlay_and_a_reset_takes_it_away() -> void:
	var east := _write_png("mod_a", "tree_art/spring/oak_e.png")
	_write_png("mod_a", "tree_art/spring/oak.png")
	registry.apply_mod_content("tester.a", ROOT.path_join("mod_a"), {"tree_art_root": "tree_art"})
	assert_eq(TreeOverlay.art_file("spring/oak", 1), east,
			"a mod's folder becomes that season's art, angled view and all")
	registry.reset_mod_content()
	assert_eq(TreeOverlay.art_file("spring/oak", 1), "",
			"and a reset drops it, so a switched-off mod leaves no wardrobe behind")


func test_a_tree_art_folder_that_holds_no_art_is_reported() -> void:
	registry.apply_mod_content("tester.b", ROOT.path_join("mod_b"), {"tree_art_root": "tree_art"})
	assert_true(registry.get_warnings().any(func(w): return w.contains("tree_art_root")),
			"a folder that is not there is named in the mod's warnings")

	DirAccess.make_dir_recursive_absolute(ROOT.path_join("mod_b/tree_art/spring"))
	registry.apply_mod_content("tester.c", ROOT.path_join("mod_b"), {"tree_art_root": "tree_art"})
	assert_true(registry.get_warnings().any(func(w): return w.contains("holds no")),
			"so is one that holds no <season>/<species>.png")


func test_base_data_is_the_shipped_catalog() -> void:
	assert_true(registry.has_building("snack_bar"), "data/buildings.json loads through the registry")
	assert_eq(registry.source_of("buildings", "snack_bar"), "core")
	assert_gt(registry.get_buildings().size(), 10)
