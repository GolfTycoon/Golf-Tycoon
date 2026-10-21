extends GameTest
## ModScaffold: the rules and file layout behind the Mods screen's Create
## New Mod button. It writes a real folder into a throwaway library, then a
## throwaway ModManager discovers - and loads - exactly what it wrote.
## (scripts/modding/mod_scaffold.gd)

const ManagerScript := preload("res://scripts/modding/mod_manager.gd")
const RegistryScript := preload("res://scripts/modding/mod_content_registry.gd")
const ROOT := "user://ut_mod_scaffold"


func before_each() -> void:
	super()
	ModPackage.remove_directory_recursive(ROOT)


func after_each() -> void:
	ModPackage.remove_directory_recursive(ROOT)
	super()


func _fields(extra: Dictionary = {}) -> Dictionary:
	var fields: Dictionary = {
		"id": "tester.scaffold", "name": "Scaffold Test", "author": "Ada",
		"description": "Built by the scaffolder.", "script": true,
	}
	for key in extra:
		fields[key] = extra[key]
	return fields


func _manager() -> Node:
	var manager: Node = ManagerScript.new()
	manager.bundled_root = ROOT.path_join("no_bundled")
	manager.user_root = ROOT
	manager.use_steam = false
	var registry: Node = RegistryScript.new()
	add_child_autofree(registry)
	manager.set_content_registry(registry)
	add_child_autofree(manager)
	return manager


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# ── the manifest ─────────────────────────────────────────────────────────

func test_a_scripted_scaffold_builds_a_valid_manifest() -> void:
	var manifest := ModManifest.from_dictionary(ModScaffold.manifest_for(_fields()))
	assert_true(manifest.is_valid(), "the button only writes manifests the loader accepts")
	assert_eq(manifest.id, "tester.scaffold")
	assert_eq(manifest.name, "Scaffold Test")
	assert_eq(manifest.version, ModScaffold.DEFAULT_VERSION)
	assert_eq(manifest.api_version, ModManifest.CURRENT_API_VERSION)
	assert_true(manifest.wants_script(), "the starter script carries the script permission")
	assert_eq(manifest.entry_point, ModScaffold.SCRIPT_FILE)
	assert_true("script" in manifest.types)


func test_a_data_only_scaffold_declares_no_code() -> void:
	var manifest := ModManifest.from_dictionary(
		ModScaffold.manifest_for(_fields({"script": false})))
	assert_true(manifest.is_valid())
	assert_false(manifest.has_script())
	assert_false(manifest.wants_script())
	assert_eq(manifest.permissions, [])
	assert_true("data" in manifest.types)


func test_an_empty_description_still_leaves_a_useful_manifest() -> void:
	var manifest := ModManifest.from_dictionary(
		ModScaffold.manifest_for(_fields({"description": ""})))
	assert_true(manifest.is_valid())
	assert_eq(manifest.description, ModScaffold.DEFAULT_DESCRIPTION,
		"a scaffold never starts life with a manifest warning")
	assert_eq(manifest.warnings, [])


# ── validation ───────────────────────────────────────────────────────────

func test_ids_are_checked_the_way_the_loader_checks_them() -> void:
	assert_true(_errors({"id": "Bad Id"}).size() > 0)
	assert_true("; ".join(_errors({"id": "Bad Id"})).contains("not usable"))
	assert_true("; ".join(_errors({"id": "1starts_with_a_digit"})).contains("not usable"))
	assert_true("; ".join(_errors({"id": "installed"})).contains("reserved"),
		"the library's own folders are not mod ids")
	assert_true("; ".join(_errors({"id": "config"})).contains("reserved"))


func test_ids_already_in_the_library_are_refused() -> void:
	var errors: Array[String] = _errors({"id": "tester.taken"}, ["tester.taken"])
	assert_true("; ".join(errors).contains("already installed"))


func _errors(extra: Dictionary = {}, taken: Array = []) -> Array[String]:
	return ModScaffold.validate(_fields(extra), taken)


func test_a_form_without_an_id_or_a_name_says_which_one_is_missing() -> void:
	assert_true("; ".join(_errors({"id": ""})).contains("Give the mod an id"))
	assert_true("; ".join(_errors({"name": "  "})).contains("Give the mod a name"))


# ── writing and reading back ─────────────────────────────────────────────

func test_creating_writes_a_folder_the_loader_discovers_switched_off() -> void:
	var result: Dictionary = ModScaffold.create(ROOT, _fields())
	assert_true(bool(result.get("ok", false)), "; ".join(result.get("errors", [])))
	assert_eq(str(result.get("mod_id", "")), "tester.scaffold")
	var directory: String = ROOT.path_join("tester.scaffold")
	assert_eq(str(result.get("directory", "")), directory)
	for file in ["mod.json", "mod_main.gd", "README.md"]:
		assert_true(FileAccess.file_exists(directory.path_join(file)), file + " is written")
	var manifest := ModManifest.from_json_text(_read(directory.path_join("mod.json")),
		directory.path_join("mod.json"))
	assert_true(manifest.is_valid(), "the written file parses as a valid manifest")
	assert_true(manifest.wants_script())
	assert_false(_read(directory.path_join("mod_main.gd")).contains("\nclass_name "),
		"mod scripts never declare a class_name (the rule is in its comments)")

	var manager := _manager()
	manager.discover()
	var info: Dictionary = manager.get_mod_info("tester.scaffold")
	assert_eq(info.get("id", ""), "tester.scaffold",
		"a Rescan finds the new folder")
	assert_false(bool(info.get("enabled", true)), "creating is not enabling")
	assert_false(bool(info.get("loaded", true)))
	assert_eq(info.get("errors", ["unexpected"]), [])
	assert_true(bool(info.get("has_script", false)))


func test_the_scaffolded_script_actually_loads_as_a_mod() -> void:
	var result: Dictionary = ModScaffold.create(ROOT, _fields())
	assert_true(bool(result.get("ok", false)))
	var manager := _manager()
	manager.discover()
	manager.set_mod_enabled("tester.scaffold", true)
	manager.load_enabled_mods()
	assert_eq(manager.get_load_order(), ["tester.scaffold"],
		"the starter entry point compiles and runs")
	assert_true(manager.is_mod_loaded("tester.scaffold"))


func test_a_data_only_create_writes_no_script_file() -> void:
	var result: Dictionary = ModScaffold.create(ROOT, _fields({"script": false}))
	assert_true(bool(result.get("ok", false)))
	var directory: String = ROOT.path_join("tester.scaffold")
	assert_false(FileAccess.file_exists(directory.path_join("mod_main.gd")))
	var manifest := ModManifest.from_json_text(_read(directory.path_join("mod.json")))
	assert_true(manifest.is_valid())
	assert_false(manifest.has_script())


func test_an_invalid_form_writes_nothing_at_all() -> void:
	var result: Dictionary = ModScaffold.create(ROOT, _fields({"id": "No Good"}))
	assert_false(bool(result.get("ok", true)))
	assert_true((result.get("errors", []) as Array).size() > 0)
	assert_false(DirAccess.dir_exists_absolute(ROOT.path_join("No Good")))


func test_an_existing_folder_is_never_overwritten() -> void:
	var directory: String = ROOT.path_join("tester.occupied")
	DirAccess.make_dir_recursive_absolute(directory)
	var marker: String = directory.path_join("notes.txt")
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file != null:
		file.store_string("hands off")
		file.close()
	var result: Dictionary = ModScaffold.create(ROOT, _fields({"id": "tester.occupied"}))
	assert_false(bool(result.get("ok", true)))
	assert_true("; ".join(result.get("errors", [])).contains("already in your mods folder"))
	assert_eq(_read(marker), "hands off", "the player's files are untouched")
	assert_false(FileAccess.file_exists(directory.path_join("mod.json")))
