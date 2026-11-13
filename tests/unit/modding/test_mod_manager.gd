extends GameTest
## ModManager: turning a pile of discovered mods into one deterministic
## load order (dependencies, conflicts, cycles, version gates), and the
## runtime services mods register into - providers, hooks, config, save
## slices. Resolution is tested as the pure function it is; loading uses a
## throwaway manager over temp mod folders.
## (scripts/modding/mod_manager.gd)

const ManagerScript := preload("res://scripts/modding/mod_manager.gd")
const RegistryScript := preload("res://scripts/modding/mod_content_registry.gd")
const WeatherImpl := preload("res://repository/packages/golf_tycoon.weather/weather_system.gd")
const ROOT := "user://ut_mod_manager"
const GAME_VERSION := "0.6.4"

var _saved_season_provider: SeasonProvider = null


func before_each() -> void:
	super()
	_saved_season_provider = SeasonSystem._provider
	_cleanup()


func after_each() -> void:
	SeasonSystem.set_provider(_saved_season_provider)
	restore_live_content()
	_cleanup()
	super()


func _cleanup() -> void:
	ModPackage.remove_directory_recursive(ROOT)


func _manifest(mod_id: String, extra: Dictionary = {}) -> ModManifest:
	var data := {
		"format_version": 1, "id": mod_id, "name": mod_id, "version": "1.0.0",
		"api_version": ModManifest.CURRENT_API_VERSION, "description": "test",
	}
	for key in extra:
		data[key] = extra[key]
	return ModManifest.from_dictionary(data)


func _manifests(list: Array) -> Dictionary:
	var by_id := {}
	for manifest in list:
		by_id[manifest.id] = manifest
	return by_id


# ---------------------------------------------------------------------------
# Resolution: the player's list becomes the load order
# ---------------------------------------------------------------------------

func test_the_players_order_is_the_default() -> void:
	var manifests := _manifests([_manifest("a.one"), _manifest("b.two")])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(["b.two", "a.one"], manifests, GAME_VERSION)
	assert_eq(resolved["order"], ["b.two", "a.one"], "nothing asked to move, nothing moves")


const ModManagerClass := preload("res://scripts/modding/mod_manager.gd")


func test_hard_dependencies_are_pulled_in_before_their_dependent() -> void:
	var manifests := _manifests([
		_manifest("a.base"),
		_manifest("b.rider", {"dependencies": ["a.base"]}),
	])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(["b.rider"], manifests, GAME_VERSION)
	assert_eq(resolved["order"], ["a.base", "b.rider"], "enabled by need, ordered first")
	assert_true("a.base" in resolved["auto_enabled"], "so the UI can say why it is on")


func test_a_missing_hard_dependency_excludes_the_dependent_with_the_reason() -> void:
	var manifests := _manifests([_manifest("b.rider", {"dependencies": ["ghost.mod"]})])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(["b.rider"], manifests, GAME_VERSION)
	assert_eq(resolved["order"], [])
	assert_true(("; ".join(resolved["errors"].get("b.rider", []))).contains("ghost.mod"))


func test_dependency_version_ranges_are_enforced() -> void:
	var manifests := _manifests([
		_manifest("a.base"),
		_manifest("b.rider", {"dependencies": [{"id": "a.base", "min_version": "2.0.0"}]}),
	])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(["b.rider"], manifests, GAME_VERSION)
	assert_eq(resolved["order"], ["a.base"], "1.0.0 does not satisfy >= 2.0.0")


func test_optional_dependencies_order_but_never_pull_or_block() -> void:
	var manifests := _manifests([
		_manifest("a.base"),
		_manifest("b.rider", {"dependencies": [{"id": "a.base", "optional": true}]}),
		_manifest("c.alone", {"dependencies": [{"id": "ghost.mod", "optional": true}]}),
	])
	var only_rider: Dictionary = ModManagerClass.resolve_load_order(["b.rider", "c.alone"], manifests, GAME_VERSION)
	assert_eq(only_rider["order"], ["b.rider", "c.alone"], "optional means optional, both ways")
	var both: Dictionary = ModManagerClass.resolve_load_order(["b.rider", "a.base"], manifests, GAME_VERSION)
	assert_eq(both["order"], ["a.base", "b.rider"], "present, it goes first")


func test_conflicts_keep_the_earlier_mod_and_explain_the_later_one() -> void:
	var manifests := _manifests([
		_manifest("a.one", {"conflicts": ["b.two"]}),
		_manifest("b.two"),
	])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(["a.one", "b.two"], manifests, GAME_VERSION)
	assert_eq(resolved["order"], ["a.one"])
	assert_true(("; ".join(resolved["errors"].get("b.two", []))).contains("a.one"),
		"the loser is told which mod won, so the player can reorder")


func test_cycles_and_wrong_generations_fall_out() -> void:
	var manifests := _manifests([
		_manifest("a.loop", {"load_after": ["b.loop"]}),
		_manifest("b.loop", {"load_after": ["a.loop"]}),
		_manifest("c.future", {"api_version": ModManifest.CURRENT_API_VERSION + 5}),
		_manifest("d.too_new", {"min_game_version": "99.0.0"}),
		_manifest("e.fine"),
	])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(
		["a.loop", "b.loop", "c.future", "d.too_new", "e.fine"], manifests, GAME_VERSION)
	assert_eq(resolved["order"], ["e.fine"], "only the loadable mod survives")
	assert_true(resolved["errors"].has("a.loop") and resolved["errors"].has("c.future")
		and resolved["errors"].has("d.too_new"), "each exclusion is explained")


func test_load_before_and_after_hints_reorder_neighbours() -> void:
	var manifests := _manifests([
		_manifest("a.one", {"load_before": ["c.three"]}),
		_manifest("b.two"),
		_manifest("c.three"),
	])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(
		["c.three", "b.two", "a.one"], manifests, GAME_VERSION)
	assert_lt(resolved["order"].find("a.one"), resolved["order"].find("c.three"))


# ---------------------------------------------------------------------------
# A throwaway manager over temp folders
# ---------------------------------------------------------------------------

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


const SCRIPT_MOD_MAIN := """extends GolfTycoonMod

var seen: int = 0

func _mod_load(_mod_api: ModAPI) -> void:
	seen += 1

func _mod_save() -> Dictionary:
	return {"seen": seen}

func _mod_restore(data: Dictionary) -> void:
	seen = int(data.get("seen", 0))
"""


func _make_library() -> Node:
	# A script mod and a data mod in a fresh library; nothing bundled.
	_write(ROOT.path_join("lib/tester.scripty/mod.json"), """{
	"format_version": 1, "id": "tester.scripty", "name": "Scripty",
	"version": "1.0.0", "api_version": 1, "description": "test",
	"entry_point": "mod_main.gd", "permissions": ["script"],
	"config": {"payout": {"type": "int", "default": 500}}
}""")
	_write(ROOT.path_join("lib/tester.scripty/mod_main.gd"), SCRIPT_MOD_MAIN)
	_write(ROOT.path_join("lib/tester.databoi/mod.json"), """{
	"format_version": 1, "id": "tester.databoi", "name": "Databoi",
	"version": "1.0.0", "api_version": 1, "description": "test",
	"icon": "icon.png",
	"content": {"buildings": "buildings.json"}
}""")
	_write(ROOT.path_join("lib/tester.databoi/buildings.json"),
		'{"tower": {"name": "Tower"}}')
	# A small red picture the Mods screen can show for the data mod.
	var icon := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	icon.fill(Color(0.8, 0.2, 0.2, 1.0))
	assert_eq(icon.save_png(ROOT.path_join("lib/tester.databoi/icon.png")), OK)

	var manager: Node = ManagerScript.new()
	manager.bundled_root = ROOT.path_join("no_bundled")
	manager.user_root = ROOT.path_join("lib")
	manager.use_steam = false
	var registry: Node = RegistryScript.new()
	add_child_autofree(registry)
	manager.set_content_registry(registry)
	add_child_autofree(manager)
	return manager


func test_a_throwaway_manager_does_not_boot_itself() -> void:
	var manager := _make_library()
	assert_false(manager._initialized, "only the root autoload self-starts")
	assert_eq(manager.get_load_order(), [])


func test_discovery_lists_both_kinds_and_starts_them_off() -> void:
	var manager := _make_library()
	manager.discover()
	var infos: Array = manager.get_all_mod_infos()
	assert_eq(infos.size(), 2)
	for info in infos:
		assert_false(bool(info.get("enabled", true)), "installing is never enabling")
	var scripty: Dictionary = manager.get_mod_info("tester.scripty")
	assert_true(bool(scripty.get("has_script", false)), "the script permission is player-visible")
	assert_false(bool(manager.get_mod_info("tester.databoi").get("has_script", true)))


# ---------------------------------------------------------------------------
# Icons: the picture the Mods screen shows for each mod
# ---------------------------------------------------------------------------

func test_a_mods_icon_is_read_and_prepared_for_the_screen() -> void:
	var manager := _make_library()
	manager.discover()
	var info: Dictionary = manager.get_mod_info("tester.databoi")
	assert_eq(str(info.get("icon", "")), "icon.png", "the manifest's icon rides along")
	var texture: Texture2D = manager.get_mod_icon_texture("tester.databoi")
	assert_not_null(texture, "the declared icon is found and decoded")
	var image := (texture as ImageTexture).get_image()
	assert_eq(image.get_width(), image.get_height(), "it is prepared square for a row")
	assert_lte(image.get_width(), ModManagerClass.ICON_MAX_SIDE, "and capped to a display size")
	# A mod that declares no icon gets no texture: the screen wears its own
	# default mark in the gap.
	assert_null(manager.get_mod_icon_texture("tester.scripty"))
	# Unknown ids get nothing at all.
	assert_null(manager.get_mod_icon_texture("tester.ghost"))


func test_a_declared_icon_that_is_missing_falls_back_and_says_so() -> void:
	var missing: String = ROOT.path_join("lib/tester.nope")
	_write(missing.path_join("mod.json"), """{
	"format_version": 1, "id": "tester.nope", "name": "Nope",
	"version": "1.0.0", "api_version": 1, "description": "test",
	"icon": "icon.png"
}""")
	var manager := _make_library()
	manager.discover()
	assert_null(manager.get_mod_icon_texture("tester.nope"),
		"the picture is not there, so the screen falls back")
	var warnings: Array = manager.get_mod_info("tester.nope").get("warnings", [])
	assert_true(warnings.any(func(w): return w.contains("default mark")),
		"and the field notes tell the player why")


func test_icons_are_centred_on_a_square_and_capped() -> void:
	var small := Image.create_empty(10, 4, false, Image.FORMAT_RGBA8)
	small.fill(Color(1, 0, 0, 1))
	var squared := ModManagerClass.square_icon_texture(small)
	assert_eq(squared.get_width(), 10, "the smaller side sets the square's side")
	assert_eq(squared.get_height(), 10)
	assert_eq(squared.get_image().get_pixel(0, 0).a, 0.0, "the padding stays transparent")
	assert_eq(squared.get_image().get_pixel(5, 5).r, 1.0, "the picture lands in the middle")
	var wide := Image.create_empty(300, 100, false, Image.FORMAT_RGBA8)
	wide.fill(Color(0, 1, 0, 1))
	var capped := ModManagerClass.square_icon_texture(wide)
	assert_eq(capped.get_width(), ModManagerClass.ICON_MAX_SIDE, "oversized pictures shrink")
	assert_eq(capped.get_height(), ModManagerClass.ICON_MAX_SIDE)


func test_enabling_loading_saving_and_restoring_a_script_mod() -> void:
	var manager := _make_library()
	manager.discover()
	manager.set_mod_enabled("tester.scripty", true)
	manager.set_mod_enabled("tester.databoi", true)
	manager.load_enabled_mods()
	assert_eq(manager.get_load_order(), ["tester.databoi", "tester.scripty"],
		"Databoi is listed above Scripty, so it loads first whichever was ticked first")
	assert_true(manager.is_mod_loaded("tester.scripty"))
	assert_false(manager.safe_mode_triggered)

	# The data mod's content landed in the throwaway registry meanwhile.
	assert_true(manager.content_registry().has_building("tester.databoi:tower"))

	# Config: declared default, then a stored override.
	assert_eq(int(manager.get_mod_config_value("tester.scripty", "payout", 0)), 500)
	manager.set_mod_config_value("tester.scripty", "payout", 750)
	assert_eq(int(manager.get_mod_config_value("tester.scripty", "payout", 0)), 750)

	# Save slice, then restore onto a freshly loaded set.
	assert_eq(manager.collect_save_data(), {"tester.scripty": {"seen": 1}})
	var missing: Array = manager.apply_save_data({
		"api_version": 1,
		"load_order": [{"id": "tester.scripty", "version": "1.0.0"},
			{"id": "ghost.mod", "version": "9.9.9"}],
		"data": {"tester.scripty": {"seen": 41}},
	})
	assert_eq(missing, ["ghost.mod"], "mods in the save but not loaded are named")
	assert_eq(manager.collect_save_data(), {"tester.scripty": {"seen": 41}},
		"_mod_restore was handed the slice back")

	manager.unload_all()
	assert_false(manager.is_mod_loaded("tester.scripty"))
	assert_false(manager.content_registry().has_building("tester.databoi:tower"),
		"unloading undoes the data too")


func test_safe_mode_loads_data_but_no_scripts_after_a_bad_session() -> void:
	var manager := _make_library()
	# The marker a crashed script-loading session would have left behind.
	_write(ROOT.path_join("lib/" + ModManagerClass.CRASH_MARKER), "loading")
	manager.discover()
	manager.set_mod_enabled("tester.scripty", true)
	manager.load_enabled_mods()
	assert_true(manager.safe_mode_triggered, "the marker is honoured")
	assert_false(FileAccess.file_exists(ROOT.path_join("lib/" + ModManagerClass.CRASH_MARKER)),
		"and consumed, so the next apply can try again")
	assert_eq(manager.collect_save_data(), {}, "the script never ran, so it has nothing to save")
	manager.unload_all()


func test_the_enabled_list_persists_as_the_players_order() -> void:
	var manager := _make_library()
	manager.discover()
	manager.set_mod_enabled("tester.databoi", true)
	manager.set_mod_enabled("tester.scripty", true)
	manager.move_mod("tester.scripty", -1)
	assert_eq(manager.get_enabled_order(), ["tester.scripty", "tester.databoi"])
	assert_true(manager.needs_reload, "a changed list asks for an apply")

	var again := _make_library()
	again.discover()
	assert_eq(again.get_enabled_order(), ["tester.scripty", "tester.databoi"],
		"the order is read back from load_order.json")


func test_leaving_the_mods_screen_applies_a_staged_change_once() -> void:
	var manager := _make_library()
	manager.discover()
	manager.load_enabled_mods()
	assert_false(manager.apply_staged_changes(), "an unchanged list applies nothing")

	manager.set_mod_enabled("tester.databoi", true)
	assert_true(manager.needs_reload, "the tick is staged")
	assert_true(manager.apply_staged_changes(), "leaving the screen puts it into play")
	assert_false(manager.needs_reload, "and nothing is left staged")
	assert_true(manager.is_mod_loaded("tester.databoi"), "the ticked mod is loaded")
	# The mods screen is gone by now (the scene reloaded); a second leave with
	# the same list is not a second apply.
	assert_false(manager.apply_staged_changes(), "leaving again reloads nothing")
	manager.unload_all()


# ---------------------------------------------------------------------------
# The player's list: a place for every mod, which is also the load order
# ---------------------------------------------------------------------------

func _listed_ids(manager: Node) -> Array:
	var ids := []
	for info in manager.get_all_mod_infos():
		ids.append(str(info.get("id", "")))
	return ids


## A data-only mod folder, in the throwaway library unless `root` says where.
func _write_mod(mod_id: String, display_name: String, root: String = ROOT.path_join("lib")) -> void:
	_write(root.path_join(mod_id).path_join("mod.json"), JSON.stringify({
		"format_version": 1, "id": mod_id, "name": display_name,
		"version": "1.0.0", "api_version": 1, "description": "test",
	}))


## Take a mod folder out of the throwaway library, as a player would.
func _remove_mod(mod_id: String) -> void:
	ModPackage.remove_directory_recursive(ROOT.path_join("lib").path_join(mod_id))


func _library_order_path() -> String:
	return ROOT.path_join("lib").path_join(ModManagerClass.LIBRARY_ORDER_FILE)


func _load_order_path() -> String:
	return ROOT.path_join("lib").path_join(ModManagerClass.CONFIG_FILE)


## The ids one of the two saved lists holds, in the order it holds them.
func _saved_ids(path: String, key: String) -> Array:
	var parsed: Variant = ModManifest.parse_json_quietly(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get(key) is Array:
		return parsed[key]
	return []


## The ids library_order.json holds, top of the list first.
func _remembered_ids() -> Array:
	return _saved_ids(_library_order_path(), "mods")


## The ids load_order.json holds, first to load first.
func _saved_loadout() -> Array:
	return _saved_ids(_load_order_path(), "enabled")


func test_mods_found_in_the_same_scan_are_ordered_by_name_then_id() -> void:
	assert_true(ModManagerClass.listed_before(
		{"id": "z.last", "name": "apple"}, {"id": "a.first", "name": "Banana"}),
		"by the name a player reads, whatever its case - not by id")
	assert_false(ModManagerClass.listed_before(
		{"id": "a.first", "name": "Banana"}, {"id": "z.last", "name": "apple"}))
	assert_true(ModManagerClass.listed_before(
		{"id": "a.one", "name": "Pack 2"}, {"id": "a.two", "name": "Pack 10"}),
		"numbers in a name count as numbers")
	assert_true(ModManagerClass.listed_before(
		{"id": "a.one", "name": "Twin"}, {"id": "b.two", "name": "Twin"}),
		"two mods with one name are split by id, so their order is still fixed")
	assert_false(ModManagerClass.listed_before(
		{"id": "b.two", "name": "Twin"}, {"id": "a.one", "name": "Twin"}))
	assert_true(ModManagerClass.listed_before(
		{"id": "b.nameless", "name": ""}, {"id": "a.named", "name": "Cedar"}),
		"a mod with no name is placed by its id")
	var same := {"id": "a.one", "name": "Twin"}
	assert_false(ModManagerClass.listed_before(same, same), "nothing is listed before itself")
	assert_true(ModManagerClass.listed_before(
		{"id": "a.one", "name": "Apple", "enabled": false, "order_index": -1},
		{"id": "b.two", "name": "Banana", "enabled": true, "order_index": 0}),
		"being enabled, or first to load, moves nothing")


func test_one_list_is_arranged_like_another_without_moving_anything_else() -> void:
	assert_eq(ModManagerClass.arranged_like(["a", "b", "c"], ["c", "a"]), ["c", "b", "a"],
		"the ids both lists hold trade places; b keeps the slot it had")
	assert_eq(ModManagerClass.arranged_like(["x", "a", "y", "b", "z"], ["b", "a"]),
		["x", "b", "y", "a", "z"], "whatever the guide does not mention stays exactly where it is")
	assert_eq(ModManagerClass.arranged_like(["a", "b"], ["ghost", "b", "other", "a"]), ["b", "a"],
		"ids only the guide holds are not brought in")
	assert_eq(ModManagerClass.arranged_like(["a", "b", "c"], ["a", "c"]), ["a", "b", "c"],
		"a list already in the guide's order is returned as it was")
	assert_eq(ModManagerClass.arranged_like(["a", "b"], []), ["a", "b"], "an empty guide asks for nothing")
	assert_eq(ModManagerClass.arranged_like([], ["a", "b"]), [])
	assert_eq(ModManagerClass.arranged_like(["a", "b", "c"], ["c", "c", "a", "c"]), ["c", "b", "a"],
		"an id the guide repeats is placed once, where the guide first has it")


func test_the_first_scan_lists_every_mod_by_name() -> void:
	var manager := _make_library()
	# Named to be listed first, with an id that would put it last.
	_write_mod("tester.zed", "alpha Pack")
	assert_false(FileAccess.file_exists(_library_order_path()), "nothing is remembered before the first scan")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.zed", "tester.databoi", "tester.scripty"],
		"found together, none is older than another: alpha Pack, Databoi, Scripty")
	assert_eq(manager.get_listed_order(), ["tester.zed", "tester.databoi", "tester.scripty"],
		"the ids on their own read the same way")
	assert_eq(_remembered_ids(), ["tester.zed", "tester.databoi", "tester.scripty"],
		"and that order is written down, to be the order from now on")


func test_a_mod_the_player_has_not_had_before_joins_the_bottom_of_the_list() -> void:
	var manager := _make_library()
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty"])

	# Its name and its id both sort above everything already listed.
	_write_mod("aaa.early", "Aardvark")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty", "aaa.early"],
		"a new mod goes under the ones the player already had, whatever it is called")

	# Two that turn up in the same scan go in by name between themselves.
	_write_mod("bbb.second", "Zulu")
	_write_mod("ccc.third", "Mike")
	manager.discover()
	assert_eq(_listed_ids(manager),
		["tester.databoi", "tester.scripty", "aaa.early", "ccc.third", "bbb.second"],
		"both under everything older: Mike, then Zulu")
	assert_eq(_remembered_ids(), _listed_ids(manager))


func test_a_mod_taken_away_and_put_back_returns_to_its_place() -> void:
	var manager := _make_library()
	_write_mod("tester.middle", "Middle")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.middle", "tester.scripty"])

	_remove_mod("tester.middle")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty"],
		"a mod that is gone from the folder is not listed")
	assert_true("tester.middle" in _remembered_ids(), "but its place is kept")

	_write_mod("tester.newer", "Newer")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty", "tester.newer"])

	# Back under a new name, as an updated copy might be: the id is the mod.
	_write_mod("tester.middle", "A Renamed Middle")
	manager.discover()
	assert_eq(_listed_ids(manager),
		["tester.databoi", "tester.middle", "tester.scripty", "tester.newer"],
		"put back, it is listed where it was - not at the bottom, as a new mod would be")


func test_a_reinstalled_zip_returns_to_its_place_too() -> void:
	var manager := _make_library()
	manager.discover()
	var source := ROOT.path_join("src")
	_write_mod("aaa.zipped", "Aaa Zipped", source)
	var zip_path := ROOT.path_join("aaa.zipped.zip")
	assert_true(bool(ModPackage.pack_folder(source.path_join("aaa.zipped"), zip_path)["ok"]))

	assert_true(bool(manager.install_zip(zip_path)["ok"]))
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty", "aaa.zipped"],
		"a newly installed mod is at the bottom of the list")

	_write_mod("tester.newer", "Newer")
	manager.discover()
	assert_true(bool(manager.uninstall_mod("aaa.zipped")["ok"]))
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty", "tester.newer"])

	assert_true(bool(manager.install_zip(zip_path)["ok"]))
	assert_eq(_listed_ids(manager),
		["tester.databoi", "tester.scripty", "aaa.zipped", "tester.newer"],
		"installed again after an uninstall, it is back above the mod that came later")


func test_a_mod_moves_up_and_down_the_list_whether_it_is_enabled_or_not() -> void:
	var manager := _make_library()
	_write_mod("tester.third", "Third")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty", "tester.third"])
	assert_eq(manager.get_enabled_order(), [], "nothing here is switched on")

	manager.move_mod("tester.scripty", -1)
	assert_eq(_listed_ids(manager), ["tester.scripty", "tester.databoi", "tester.third"],
		"a mod that is off moves up a place all the same")
	manager.move_mod("tester.scripty", 2)
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.third", "tester.scripty"],
		"and down as many places as it is asked to")
	assert_eq(_remembered_ids(), _listed_ids(manager), "each move is written down")

	manager.move_mod("tester.scripty", 1)
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.third", "tester.scripty"],
		"the last mod has nowhere further down to go")
	manager.move_mod("tester.third", -9)
	assert_eq(_listed_ids(manager), ["tester.third", "tester.databoi", "tester.scripty"],
		"a move past the end stops at the end")
	manager.move_mod("tester.third", 0)
	manager.move_mod("no.such_mod", 1)
	assert_eq(_listed_ids(manager), ["tester.third", "tester.databoi", "tester.scripty"],
		"no steps, or no such mod, moves nothing")

	assert_eq(manager.get_enabled_order(), [], "moving a mod never switches it on")
	assert_false(manager.needs_reload, "and with nothing enabled there is nothing to apply")
	assert_false(FileAccess.file_exists(_load_order_path()),
		"so the enabled list was never written")


func test_enabled_mods_load_in_the_order_they_are_listed() -> void:
	var manager := _make_library()
	_write_mod("tester.third", "Third")
	manager.discover()
	var listed := ["tester.databoi", "tester.scripty", "tester.third"]
	assert_eq(_listed_ids(manager), listed)

	manager.set_mod_enabled("tester.third", true)
	manager.set_mod_enabled("tester.databoi", true)
	assert_eq(manager.get_enabled_order(), ["tester.databoi", "tester.third"],
		"the first on the list loads first, whichever was ticked first")
	assert_eq(_saved_loadout(), ["tester.databoi", "tester.third"])
	assert_eq(_listed_ids(manager), listed, "and ticking moved nothing")
	assert_eq(int(manager.get_mod_info("tester.databoi")["order_index"]), 0)
	assert_eq(int(manager.get_mod_info("tester.third")["order_index"]), 1,
		"each enabled mod carries its place in the load order")
	assert_eq(int(manager.get_mod_info("tester.scripty")["order_index"]), -1)

	manager.load_enabled_mods()
	assert_eq(manager.get_load_order(), ["tester.databoi", "tester.third"])
	assert_false(manager.needs_reload)

	# Past a mod that is off: a new place in the list, the same load order.
	manager.move_mod("tester.third", -1)
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.third", "tester.scripty"])
	assert_eq(manager.get_enabled_order(), ["tester.databoi", "tester.third"])
	assert_false(manager.needs_reload, "nothing loads differently, so there is nothing to apply")

	# Past a mod that is on: the two swap in the load order as well.
	manager.move_mod("tester.third", -1)
	assert_eq(_listed_ids(manager), ["tester.third", "tester.databoi", "tester.scripty"])
	assert_eq(manager.get_enabled_order(), ["tester.third", "tester.databoi"],
		"the mod moved above another enabled mod now loads before it")
	assert_eq(_saved_loadout(), ["tester.third", "tester.databoi"])
	assert_true(manager.needs_reload, "which is a change to apply")
	assert_eq(int(manager.get_mod_info("tester.third")["order_index"]), 0)

	# A mod switched on between two others loads between them.
	manager.move_mod("tester.scripty", -1)
	manager.set_mod_enabled("tester.scripty", true)
	assert_eq(_listed_ids(manager), ["tester.third", "tester.scripty", "tester.databoi"])
	assert_eq(manager.get_enabled_order(), ["tester.third", "tester.scripty", "tester.databoi"],
		"not last, as the newest tick, but where the list has it")
	manager.unload_all()


func test_a_load_order_from_before_the_list_was_kept_is_the_order_listed() -> void:
	var manager := _make_library()
	_write_mod("tester.middle", "Middle")
	# What an earlier version of the game left: the enabled mods in the order
	# they were ticked, and no list of the library.
	_write(_load_order_path(), JSON.stringify(
		{"version": 1, "enabled": ["tester.scripty", "tester.databoi"]}))
	manager.discover()
	assert_eq(manager.get_enabled_order(), ["tester.scripty", "tester.databoi"],
		"the load order the player had is the load order they keep")
	assert_eq(_listed_ids(manager), ["tester.scripty", "tester.middle", "tester.databoi"],
		"so the two enabled mods trade places in the by-name list; Middle, which is off, stays put")
	assert_eq(_remembered_ids(), _listed_ids(manager))

	# The same holds whenever the file says otherwise, a hand edit included.
	_write(_load_order_path(), JSON.stringify(
		{"version": 1, "enabled": ["tester.databoi", "tester.middle", "tester.scripty"]}))
	manager.discover()
	assert_eq(manager.get_enabled_order(), ["tester.databoi", "tester.middle", "tester.scripty"])
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.middle", "tester.scripty"],
		"load_order.json has the last word on the order its mods are listed in")


func test_a_moved_mod_that_is_taken_away_returns_to_where_the_player_put_it() -> void:
	var manager := _make_library()
	_write_mod("tester.third", "Third")
	manager.discover()
	manager.move_mod("tester.third", -2)
	assert_eq(_listed_ids(manager), ["tester.third", "tester.databoi", "tester.scripty"])

	_remove_mod("tester.third")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty"])
	# The mods that are still here can be moved around the gap it left.
	manager.move_mod("tester.scripty", -1)
	assert_eq(_listed_ids(manager), ["tester.scripty", "tester.databoi"],
		"a place is a place among the mods on show: the missing one is not in the way")
	_write_mod("tester.newer", "Newer")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.scripty", "tester.databoi", "tester.newer"])

	_write_mod("tester.third", "Third")
	manager.discover()
	assert_eq(_listed_ids(manager),
		["tester.third", "tester.scripty", "tester.databoi", "tester.newer"],
		"back at the top, where the player moved it - not where it was first found")


func test_the_listed_order_is_remembered_between_sessions() -> void:
	var manager := _make_library()
	manager.discover()
	_write_mod("aaa.early", "Aardvark")
	manager.discover()
	manager.move_mod("tester.scripty", -1)
	var listed := _listed_ids(manager)
	assert_eq(listed, ["tester.scripty", "tester.databoi", "aaa.early"])

	var again := _make_library()
	again.discover()
	assert_eq(_listed_ids(again), listed,
		"the order is read back from library_order.json, not worked out afresh by name")


func test_a_damaged_list_file_starts_the_order_over() -> void:
	var manager := _make_library()
	manager.discover()
	_write_mod("aaa.early", "Aardvark")
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty", "aaa.early"])

	_write(_library_order_path(), "{ not json")
	manager.discover()
	assert_eq(_listed_ids(manager), ["aaa.early", "tester.databoi", "tester.scripty"],
		"with nothing to go on every mod is a newcomer again: by name")
	assert_eq(_remembered_ids(), _listed_ids(manager), "and a readable list is written back")


func test_the_command_line_tool_lists_mods_without_remembering_them() -> void:
	var manager := _make_library()
	# What initialize() sets when it finds itself under tools/mod_tool.gd.
	manager._remembers_finds = false
	manager.discover()
	assert_eq(_listed_ids(manager), ["tester.databoi", "tester.scripty"],
		"the scan still has an order for as long as the tool runs")
	assert_false(FileAccess.file_exists(_library_order_path()),
		"but the tool is not the game finding a mod: nothing is written down")


func test_switching_mods_on_and_off_never_moves_a_mod_in_the_list() -> void:
	var manager := _make_library()
	manager.discover()
	var listed := _listed_ids(manager)
	assert_eq(listed, ["tester.databoi", "tester.scripty"])

	manager.set_mod_enabled("tester.scripty", true)
	assert_eq(_listed_ids(manager), listed, "an enabled mod does not jump to the top")

	manager.set_mod_enabled("tester.databoi", true)
	assert_eq(_listed_ids(manager), listed)
	assert_eq(manager.get_enabled_order(), listed, "the load order follows the list, not the other way round")

	manager.set_mod_enabled("tester.databoi", false)
	assert_eq(_listed_ids(manager), listed, "nor does switching one back off move anything")
	assert_eq(int(manager.get_mod_info("tester.databoi")["order_index"]), -1)
	assert_eq(int(manager.get_mod_info("tester.scripty")["order_index"]), 0)

	manager.discover()
	assert_eq(_listed_ids(manager), listed, "and a rescan with nothing new to find leaves it be")
	assert_eq(_remembered_ids(), listed)


# ---------------------------------------------------------------------------
# Providers and hooks on a throwaway manager
# ---------------------------------------------------------------------------

func test_the_last_weather_factory_registered_wins() -> void:
	var manager := _make_library()
	manager.register_weather_factory("tester.a", func() -> WeatherSystem: return WeatherSystem.new())
	manager.register_weather_factory("tester.b", func() -> WeatherSystem: return WeatherImpl.new())
	var made: WeatherSystem = manager.create_weather_system()
	assert_true(made.get_script().resource_path.ends_with("repository/packages/golf_tycoon.weather/weather_system.gd"),
		"load order is the tie-breaker")
	assert_eq(str(manager.provider_owners().get("weather", "")), "tester.b")
	made.free()


func test_hooks_chain_in_load_order_and_bad_returns_pass_through() -> void:
	var manager := _make_library()
	manager.add_hook("tester.a", "score", func(value: float, _ctx: Dictionary) -> float: return value + 1.0)
	manager.add_hook("tester.b", "score", func(_value: float, _ctx: Dictionary): return "not a number")
	manager.add_hook("tester.c", "score", func(value: float, _ctx: Dictionary) -> float: return value * 10.0)
	assert_almost_eq(manager.apply_hook("score", 1.0, {}), 20.0, 0.0001,
		"(1 + 1) * 10 - the broken hook is skipped, not fatal")
	assert_almost_eq(manager.apply_hook("nothing_registered", 3.5, {}), 3.5, 0.0001)


func test_the_live_session_boots_without_mods_until_the_player_downloads_some() -> void:
	# The real autoload in this very test run: nothing ships in the package
	# any more, so a fresh boot loads nothing - the environment systems run
	# on their neutral stand-ins until the player downloads the official
	# mods from the Browse Mods screen (the repository suites apply the
	# Seasons package by hand where a test needs its content).
	assert_eq(ModManager.get_load_order(), [] as Array[String])
	var owners: Dictionary = ModManager.provider_owners()
	assert_eq(str(owners.get("seasons", "")), "core (neutral)")
	assert_eq(str(owners.get("weather", "")), "core (neutral)")
	assert_eq(str(owners.get("wind", "")), "core (neutral)")
	assert_false(GameManager.feature_available("seasons"))


func test_conflict_exclusions_cascade_to_add_ons() -> void:
	var manifests := _manifests([
		_manifest("a.winner", {"conflicts": ["b.base"]}),
		_manifest("b.base"),
		_manifest("c.addon", {"dependencies": ["b.base"]}),
	])
	var resolved: Dictionary = ModManagerClass.resolve_load_order(
		["a.winner", "b.base", "c.addon"], manifests, GAME_VERSION)
	assert_eq(resolved["order"], ["a.winner"])
	assert_true(resolved["errors"].has("c.addon"))


func test_rescanning_does_not_forget_running_mods() -> void:
	var manager := _make_library()
	manager.discover()
	manager.set_mod_enabled("tester.scripty", true)
	manager.load_enabled_mods()
	manager.discover()
	assert_true(manager.is_mod_loaded("tester.scripty"))
	assert_false(bool(manager.uninstall_mod("tester.scripty").get("ok", true)),
		"rescanning never permits deleting a live mod")
	manager.unload_all()


func test_the_weather_zip_loads_relative_sibling_scripts_from_user_storage() -> void:
	var manager := _make_library()
	var zip_path := ROOT.path_join("weather.zip")
	assert_true(bool(ModPackage.pack_folder("res://repository/packages/golf_tycoon.weather", zip_path)["ok"]))
	assert_true(bool(manager.install_zip(zip_path)["ok"]))
	manager.set_mod_enabled("golf_tycoon.weather", true)
	manager.load_enabled_mods()
	assert_true(manager.has_weather_provider(), "relative preloads work from an installed ZIP too")
	var weather: WeatherSystem = manager.create_weather_system()
	assert_true(weather.has_method("_maybe_change_weather"))
	weather.free()
	manager.unload_all()
