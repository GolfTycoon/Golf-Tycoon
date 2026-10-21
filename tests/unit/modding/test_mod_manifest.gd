extends GameTest
## ModManifest: what a mod.json must say before the game will load it, the
## version arithmetic dependencies lean on, and the soft warnings that still
## load. (scripts/modding/mod_manifest.gd)


func _manifest(data: Dictionary) -> ModManifest:
	var base := {
		"format_version": 1, "id": "tester.mod", "name": "Test Mod",
		"version": "1.2.0", "api_version": ModManifest.CURRENT_API_VERSION,
		"description": "A test mod.",
	}
	for key in data:
		base[key] = data[key]
	return ModManifest.from_dictionary(base, "test")


# ---------------------------------------------------------------------------
# The basics: identity, version, format
# ---------------------------------------------------------------------------

func test_a_complete_manifest_is_valid() -> void:
	var manifest := _manifest({})
	assert_true(manifest.is_valid(), "a complete manifest validates")
	assert_eq(manifest.id, "tester.mod")
	assert_eq(manifest.display_line(), "Test Mod 1.2.0", "lists read 'Name Version'")
	# _manifest's dict has no author.
	var authored := _manifest({"author": "Ada"})
	assert_eq(authored.display_line(), "Test Mod 1.2.0 by Ada")


func test_invalid_json_and_non_objects_are_errors_not_crashes() -> void:
	assert_false(ModManifest.from_json_text("{not json").is_valid())
	assert_false(ModManifest.from_json_text("[1, 2]").is_valid())


func test_mod_ids_must_be_safe_namespaces() -> void:
	for good in ["a.b", "golf_tycoon.seasons", "me-my_mod.v2"]:
		assert_true(ModManifest.is_valid_mod_id(good), "%s is a serviceable id" % good)
	for bad in ["", "ab", "1mod.x", "Upper.case", "has space", "mod:id", "mod.", ".mod", "mod..x"]:
		assert_false(ModManifest.is_valid_mod_id(bad), "%s is not" % bad)


func test_missing_required_fields_are_errors() -> void:
	assert_false(_manifest({"format_version": 99}).is_valid(), "future format")
	assert_false(_manifest({"name": ""}).is_valid(), "nameless")
	assert_false(_manifest({"version": "banana"}).is_valid(), "unversioned")
	assert_false(_manifest({"api_version": 0}).is_valid(), "api undeclared")
	assert_false(_manifest({"id": "Bad Id"}).is_valid(), "id unsafe")


func test_missing_description_is_only_a_warning() -> void:
	var manifest := _manifest({"description": ""})
	assert_true(manifest.is_valid(), "it still loads")
	assert_gt(manifest.warnings.size(), 0, "but the player is told")


func test_unknown_content_keys_warn_instead_of_failing() -> void:
	var manifest := _manifest({"content": {"moon_phases": "data/moon.json"}})
	assert_true(manifest.is_valid())
	assert_true(manifest.warnings.any(func(w): return w.contains("moon_phases")),
		"the warning names the key that will be ignored")


# ---------------------------------------------------------------------------
# Script permission contract
# ---------------------------------------------------------------------------

func test_an_entry_point_without_the_script_permission_is_an_error() -> void:
	assert_false(_manifest({"entry_point": "mod_main.gd"}).is_valid(),
		"a script that could never run is a broken mod, not a quiet one")


func test_script_permission_without_an_entry_point_is_a_warning() -> void:
	var manifest := _manifest({"permissions": ["script"]})
	assert_true(manifest.is_valid())
	assert_true(manifest.warnings.any(func(w): return w.contains("entry_point")))


func test_wants_script_needs_both_halves() -> void:
	assert_true(_manifest({"entry_point": "main.gd", "permissions": ["script"]}).wants_script())
	assert_false(_manifest({}).wants_script(), "data-only mods never run code")


# ---------------------------------------------------------------------------
# Dependencies, versions, config
# ---------------------------------------------------------------------------

func test_dependencies_read_both_spellings() -> void:
	var manifest := _manifest({"dependencies": [
		"golf_tycoon.seasons",
		{"id": "other.mod", "min_version": "1.1.0", "optional": true},
	]})
	assert_eq(manifest.dependencies.size(), 2)
	assert_eq(str(manifest.dependencies[0].get("id")), "golf_tycoon.seasons")
	assert_false(bool(manifest.dependencies[0].get("optional")), "a bare id is a hard dependency")
	assert_true(bool(manifest.dependencies[1].get("optional")))


func test_a_mod_cannot_depend_on_or_fight_itself() -> void:
	assert_false(_manifest({"dependencies": ["tester.mod"]}).is_valid())
	assert_false(_manifest({"conflicts": ["tester.mod"]}).is_valid())


func test_version_parsing_and_ordering() -> void:
	assert_eq(ModManifest.parse_version("1.2"), [1, 2, 0], "short versions pad to three")
	assert_eq(ModManifest.parse_version("v2.0.3-beta"), [2, 0, 3], "v prefix and suffix tolerated")
	assert_eq(ModManifest.parse_version(""), [], "empty is unreadable")
	assert_eq(ModManifest.parse_version("banana"), [])
	assert_lt(ModManifest.compare_versions("1.9.9", "1.10.0"), 0, "numeric, not lexicographic")
	assert_gt(ModManifest.compare_versions("2.0.0", "1.9.9"), 0)
	assert_eq(ModManifest.compare_versions("1.2.0", "1.2"), 0)
	assert_true(ModManifest.version_in_range("1.5.0", "1.0.0", "2.0.0"))
	assert_false(ModManifest.version_in_range("2.0.1", "1.0.0", "2.0.0"))
	assert_true(ModManifest.version_in_range("9.9.9", "1.0.0", ""), "an empty bound is open")


func test_config_defaults_come_from_the_schema() -> void:
	var manifest := _manifest({"config": {
		"payout": {"type": "int", "default": 500},
		"no_default": {"type": "string"},
	}})
	assert_eq(manifest.default_config(), {"payout": 500},
		"only keys with a declared default land in the defaults")


func test_declared_file_paths_cannot_escape_the_mod_folder() -> void:
	for unsafe_path in ["../other.json", "user://settings.cfg", "/etc/passwd", "C:\\outside.json"]:
		assert_false(_manifest({"content": {"buildings": unsafe_path}}).is_valid())
	assert_true(_manifest({"content": {"buildings": "data/buildings.json"}}).is_valid())
