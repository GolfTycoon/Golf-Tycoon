extends GameTest
## ModManager: turning a pile of discovered mods into one deterministic
## load order (dependencies, conflicts, cycles, version gates), and the
## runtime services mods register into - providers, hooks, config, save
## slices. Resolution is tested as the pure function it is; loading uses a
## throwaway manager over temp mod folders.
## (scripts/modding/mod_manager.gd)

const ManagerScript := preload("res://scripts/modding/mod_manager.gd")
const RegistryScript := preload("res://scripts/modding/mod_content_registry.gd")
const WeatherImpl := preload("res://mods/golf_tycoon.weather/weather_system.gd")
const ROOT := "user://ut_mod_manager"
const GAME_VERSION := "0.5.0"

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
	"content": {"buildings": "buildings.json"}
}""")
	_write(ROOT.path_join("lib/tester.databoi/buildings.json"),
		'{"tower": {"name": "Tower"}}')

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


func test_enabling_loading_saving_and_restoring_a_script_mod() -> void:
	var manager := _make_library()
	manager.discover()
	manager.set_mod_enabled("tester.scripty", true)
	manager.set_mod_enabled("tester.databoi", true)
	manager.load_enabled_mods()
	assert_eq(manager.get_load_order(), ["tester.scripty", "tester.databoi"])
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


# ---------------------------------------------------------------------------
# Providers and hooks on a throwaway manager
# ---------------------------------------------------------------------------

func test_the_last_weather_factory_registered_wins() -> void:
	var manager := _make_library()
	manager.register_weather_factory("tester.a", func() -> WeatherSystem: return WeatherSystem.new())
	manager.register_weather_factory("tester.b", func() -> WeatherSystem: return WeatherImpl.new())
	var made: WeatherSystem = manager.create_weather_system()
	assert_true(made.get_script().resource_path.ends_with("mods/golf_tycoon.weather/weather_system.gd"),
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


func test_the_live_session_loaded_the_official_mods() -> void:
	# The real autoload in this very test run: the three official mods are
	# what makes the season/weather suites meaningful.
	assert_eq(ModManager.get_load_order(),
		["golf_tycoon.seasons", "golf_tycoon.weather", "golf_tycoon.wind"])
	var owners: Dictionary = ModManager.provider_owners()
	assert_eq(str(owners.get("seasons", "")), "golf_tycoon.seasons")
	assert_eq(str(owners.get("weather", "")), "golf_tycoon.weather")
	assert_eq(str(owners.get("wind", "")), "golf_tycoon.wind")
	assert_true(GameManager.feature_available("seasons"))


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
	assert_true(bool(ModPackage.pack_folder("res://mods/golf_tycoon.weather", zip_path)["ok"]))
	assert_true(bool(manager.install_zip(zip_path)["ok"]))
	manager.set_mod_enabled("golf_tycoon.weather", true)
	manager.load_enabled_mods()
	assert_true(manager.has_weather_provider(), "relative preloads work from an installed ZIP too")
	var weather: WeatherSystem = manager.create_weather_system()
	assert_true(weather.has_method("_maybe_change_weather"))
	weather.free()
	manager.unload_all()
