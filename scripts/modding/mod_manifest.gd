extends RefCounted
class_name ModManifest
## ModManifest - The parsed and validated `mod.json` at the root of every mod.
##
## The manifest is the contract between a mod and the game: who the mod is
## (`id`, `name`, `version`), what it needs (`api_version`, `dependencies`,
## `permissions`), what it clashes with (`conflicts`, `load_after`,
## `load_before`) and what it ships (`content`, `entry_point`,
## `resource_packs`). Everything a player sees in the Mods screen, and
## everything the loader is allowed to do with the mod, comes from here.
##
## See docs/modding/manifest-and-packaging.md for the field-by-field reference.

## The manifest format itself, independent of the game / Mod API versions.
const FORMAT_VERSION: int = 1

## The Golf Tycoon Mod API version this build of the game speaks. A mod's
## `api_version` must match this major number to load: the API only ever
## grows within a major version, so a match means every call the mod was
## written against still exists with the same meaning.
const CURRENT_API_VERSION: int = 1

## Permission a manifest must declare before its GDScript entry point is run.
## Data-only mods (JSON content, no entry point) need no permissions and any
## `.gd` files in them are ignored by the loader.
const PERMISSION_SCRIPT: String = "script"

var format_version: int = FORMAT_VERSION
var id: String = ""
var name: String = ""
var version: String = "0.0.0"
var api_version: int = 0
var author: String = ""
var description: String = ""
var homepage: String = ""
var min_game_version: String = ""
var max_game_version: String = ""
var entry_point: String = ""
var permissions: Array[String] = []
## [{id: String, min_version: String, max_version: String, optional: bool}]
var dependencies: Array[Dictionary] = []
var conflicts: Array[String] = []
var load_after: Array[String] = []
var load_before: Array[String] = []
var types: Array[String] = []
var enabled_by_default: bool = false
## Tie-breaker for the first-run default order only (lower loads earlier).
## The player's own order in the Mods screen always wins after that.
var load_priority: int = 0
var content: Dictionary = {}
var resource_packs: Array[String] = []
var workshop: Dictionary = {}
var config_schema: Dictionary = {}

## Validation problems. A mod with any error is listed in the Mods screen but
## never loads; warnings load anyway and are shown to the player.
var errors: Array[String] = []
var warnings: Array[String] = []
## Where the manifest was read from (for error messages), e.g. a folder path.
var origin: String = ""

const _ID_PATTERN: String = "^[a-z][a-z0-9_]*([.\\-][a-z0-9_]+)*$"


func is_valid() -> bool:
	return errors.is_empty()


func has_permission(permission: String) -> bool:
	return permission in permissions


func has_script() -> bool:
	return not entry_point.is_empty()


## True when this mod asks the loader to run code, which requires both an
## entry point and the "script" permission.
func wants_script() -> bool:
	return has_script() and has_permission(PERMISSION_SCRIPT)


## The Steam Workshop published file id recorded by a previous upload, or 0.
func workshop_file_id() -> int:
	return int(workshop.get("published_file_id", 0))


## One line for lists: "Name 1.2.0 by Author".
func display_line() -> String:
	if author.is_empty():
		return "%s %s" % [name, version]
	return "%s %s by %s" % [name, version, author]


# =============================================================================
# PARSING AND VALIDATION
# =============================================================================

## Parse JSON without the engine ERROR that JSON.parse_string prints on
## failure: mod files are strangers' files, so malformed JSON is an expected,
## reportable outcome - not log spam. Returns null when it will not parse.
static func parse_json_quietly(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data

static func from_json_text(text: String, origin_path: String = "") -> ModManifest:
	var manifest := ModManifest.new()
	manifest.origin = origin_path
	var parsed: Variant = parse_json_quietly(text)
	if parsed == null:
		manifest.errors.append("mod.json is not valid JSON.")
		return manifest
	if not (parsed is Dictionary):
		manifest.errors.append("mod.json must be a JSON object.")
		return manifest
	return from_dictionary(parsed, origin_path)


static func from_dictionary(data: Dictionary, origin_path: String = "") -> ModManifest:
	var manifest := ModManifest.new()
	manifest.origin = origin_path
	manifest._read_fields(data)
	manifest._validate(data)
	return manifest


func _read_fields(data: Dictionary) -> void:
	format_version = int(data.get("format_version", 0))
	id = str(data.get("id", "")).strip_edges()
	name = str(data.get("name", "")).strip_edges()
	version = str(data.get("version", "")).strip_edges()
	api_version = int(data.get("api_version", 0))
	author = str(data.get("author", "")).strip_edges()
	description = str(data.get("description", "")).strip_edges()
	homepage = str(data.get("homepage", "")).strip_edges()
	min_game_version = str(data.get("min_game_version", "")).strip_edges()
	max_game_version = str(data.get("max_game_version", "")).strip_edges()
	entry_point = str(data.get("entry_point", "")).strip_edges()
	permissions = _string_list(data.get("permissions", []))
	conflicts = _string_list(data.get("conflicts", []))
	load_after = _string_list(data.get("load_after", []))
	load_before = _string_list(data.get("load_before", []))
	types = _string_list(data.get("types", []))
	enabled_by_default = bool(data.get("enabled_by_default", false))
	load_priority = int(data.get("load_priority", 0))
	dependencies = _read_dependencies(data.get("dependencies", []))
	var raw_content: Variant = data.get("content", {})
	content = raw_content.duplicate(true) if raw_content is Dictionary else {}
	resource_packs = _string_list(data.get("resource_packs", []))
	var raw_workshop: Variant = data.get("workshop", {})
	workshop = raw_workshop.duplicate(true) if raw_workshop is Dictionary else {}
	var raw_config: Variant = data.get("config", {})
	config_schema = raw_config.duplicate(true) if raw_config is Dictionary else {}


func _validate(data: Dictionary) -> void:
	if format_version != FORMAT_VERSION:
		errors.append("format_version must be %d (found %d)." % [FORMAT_VERSION, format_version])
	if not is_valid_mod_id(id):
		errors.append("id '%s' is not a valid mod id: use lower-case letters, digits, '.', '_' or '-', starting with a letter (for example 'yourname.cool_mod')." % id)
	if name.is_empty():
		errors.append("name is missing: players need a title to recognise the mod by.")
	if parse_version(version).is_empty():
		errors.append("version '%s' is not a version number like '1.2.0'." % version)
	if api_version <= 0:
		errors.append("api_version is missing: declare which Golf Tycoon Mod API the mod was built for (currently %d)." % CURRENT_API_VERSION)
	if has_script():
		if not entry_point.ends_with(".gd"):
			errors.append("entry_point '%s' must name a GDScript file inside the mod." % entry_point)
		if not has_permission(PERMISSION_SCRIPT):
			errors.append("entry_point is set but the \"script\" permission is not declared, so the script would never run. Add \"script\" to permissions, or remove entry_point for a data-only mod.")
	if has_permission(PERMISSION_SCRIPT) and not has_script():
		warnings.append("The \"script\" permission is declared but no entry_point is set.")
	for dependency in dependencies:
		var dependency_id: String = str(dependency.get("id", ""))
		if dependency_id == id:
			errors.append("A mod cannot depend on itself.")
		elif not is_valid_mod_id(dependency_id):
			errors.append("Dependency id '%s' is not a valid mod id." % dependency_id)
	if id in conflicts or id in load_after or id in load_before:
		errors.append("A mod cannot conflict with, or order itself against, itself.")
	if not min_game_version.is_empty() and parse_version(min_game_version).is_empty():
		errors.append("min_game_version '%s' is not a version number." % min_game_version)
	if not max_game_version.is_empty() and parse_version(max_game_version).is_empty():
		errors.append("max_game_version '%s' is not a version number." % max_game_version)
	# Declarative file references never escape the mod root. Script mods are
	# trusted code, but data-only packages must not read arbitrary user files.
	var declared_paths: Array = resource_packs.duplicate()
	if not entry_point.is_empty():
		declared_paths.append(entry_point)
	for declaration in content.values():
		if declaration is String:
			declared_paths.append(declaration)
		elif declaration is Dictionary:
			declared_paths.append_array(declaration.values())
	for declared_path in declared_paths:
		if not is_safe_relative_path(str(declared_path)):
			errors.append("Mod file path must stay inside its folder: %s" % str(declared_path))
	for key in content:
		if not str(key) in KNOWN_CONTENT_KEYS:
			warnings.append("Unknown content key '%s' - it will be ignored. Known keys: %s." % [key, ", ".join(KNOWN_CONTENT_KEYS)])
	if description.is_empty():
		warnings.append("No description: the Mods screen will show the mod without one.")
	if data.has("steam_workshop_id"):
		warnings.append("'steam_workshop_id' at the top level is not read; use workshop.published_file_id instead.")


## Content declarations the loader knows how to apply (see ModContentRegistry).
const KNOWN_CONTENT_KEYS: Array[String] = [
	"buildings", "decorations", "terrain_overrides", "themes",
	"world_locations", "visiting_golfers", "golfer_names",
	"seasonal_events", "golfer_skins_root", "tree_art_root", "tournament_tiers",
	"tuning",
]


func _read_dependencies(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (raw is Array):
		errors.append("dependencies must be an array of objects.")
		return result
	for entry in raw:
		if entry is String:
			result.append({"id": entry, "min_version": "", "max_version": "", "optional": false})
		elif entry is Dictionary:
			result.append({
				"id": str(entry.get("id", "")),
				"min_version": str(entry.get("min_version", "")),
				"max_version": str(entry.get("max_version", "")),
				"optional": bool(entry.get("optional", false)),
			})
		else:
			errors.append("A dependency must be a mod id or an object with an 'id'.")
	return result


static func _string_list(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for entry in raw:
			result.append(str(entry))
	return result


## A mod id namespaces everything the mod adds (buildings become
## "yourname.cool_mod:thing"), so it has to be a safe file/folder/save token.
static func is_valid_mod_id(candidate: String) -> bool:
	if candidate.length() < 3 or candidate.length() > 64:
		return false
	var regex := RegEx.create_from_string(_ID_PATTERN)
	return regex != null and regex.search(candidate) != null


# =============================================================================
# VERSIONS ("1.2.3" - suffixes after the patch number are ignored for order)
# =============================================================================

## [major, minor, patch] or [] when the text is not a dotted version number.
static func parse_version(text: String) -> Array[int]:
	var parts: Array[int] = []
	var cleaned := text.strip_edges().trim_prefix("v")
	if cleaned.is_empty():
		return parts
	for chunk in cleaned.split("."):
		var digits := ""
		for character in chunk:
			if character.is_valid_int():
				digits += character
			else:
				break
		if digits.is_empty():
			return []
		parts.append(digits.to_int())
		if parts.size() == 3:
			break
	while parts.size() < 3:
		parts.append(0)
	return parts


## -1 when `a` is older than `b`, 0 when equal, 1 when newer. An unreadable
## version sorts below every readable one.
static func compare_versions(a: String, b: String) -> int:
	var parsed_a := parse_version(a)
	var parsed_b := parse_version(b)
	if parsed_a.is_empty() and parsed_b.is_empty():
		return 0
	if parsed_a.is_empty():
		return -1
	if parsed_b.is_empty():
		return 1
	for i in range(3):
		if parsed_a[i] != parsed_b[i]:
			return -1 if parsed_a[i] < parsed_b[i] else 1
	return 0


## Does `candidate` fall inside [min_version, max_version]? An empty bound is
## open-ended.
static func version_in_range(candidate: String, min_version: String, max_version: String) -> bool:
	if not min_version.is_empty() and compare_versions(candidate, min_version) < 0:
		return false
	if not max_version.is_empty() and compare_versions(candidate, max_version) > 0:
		return false
	return true


## Config defaults declared in the manifest's `config` schema, as a plain
## key -> value dictionary (used until the player overrides a value).
func default_config() -> Dictionary:
	var values: Dictionary = {}
	for key in config_schema:
		var schema: Variant = config_schema[key]
		if schema is Dictionary and schema.has("default"):
			values[key] = schema["default"]
	return values


static func is_safe_relative_path(path_value: String) -> bool:
	if path_value.is_empty() or path_value.begins_with("/") or path_value.contains(":") or path_value.contains("\\"):
		return false
	return not ".." in path_value.split("/")
