extends RefCounted
class_name ModManifest
## ModManifest - Declarative description of a single mod.
##
## Every mod on disk (builtin under res://mods/ and user-installed under
## user://mods/) carries a mod.json that is parsed into one of these.
## The manifest is the contract between the game and the mod: what it is,
## what it needs, what it conflicts with, where its code lives, what it
## provides, and how it should be ordered among other mods.
##
## Ordering & conflict resolution:
##   - Enabled mods live in an ordered list (ModManager.enabled_mods).
##   - When two mods touch the same game resource (e.g. terrain type,
##     building definition, hook), the later entry wins ("last wins").
##   - Dependencies are validated before enabling; conflicts are warned.
##   - load_priority hints ordering; dependencies enforce hard ordering.
##
## Example mod.json:
## {
##   "id": "weather",
##   "name": "Weather System",
##   "version": "1.0.0",
##   "description": "Storms change turnout and sky tint.",
##   "author": "Golf Tycoon Team",
##   "api_version": "1.0",
##   "category": "gameplay",
##   "is_builtin": true,
##   "enabled_by_default": false,
##   "load_priority": 10,
##   "dependencies": [],
##   "optional_dependencies": [],
##   "conflicts": [],
##   "tags": ["environment","difficulty"],
##   "entry_point": "res://mods/weather/weather_mod.gd",
##   "permissions": ["event_bus","game_manager","terrain"]
## }

const REQUIRED_FIELDS: Array[String] = ["id", "name", "version"]

## Unique mod identifier — lowercase letters, numbers, underscores.
var id: String = ""
var name: String = ""
var version: String = "1.0.0"
var description: String = ""
var author: String = ""
var api_version: String = "1.0"
var category: String = "gameplay"
var tags: Array[String] = []
var is_builtin: bool = false
var enabled_by_default: bool = false
var load_priority: int = 100
## Hard dependencies — ids that must be enabled and load before this mod.
var dependencies: Array[String] = []
## Soft dependencies — loaded before this mod if present, but not required.
var optional_dependencies: Array[String] = []
## Ids this mod is known to be incompatible with.
var conflicts: Array[String] = []
## Load ordering hints: ids this mod must load after/before.
var load_after: Array[String] = []
var load_before: Array[String] = []
## Path to the GDScript that implements ModHooks (optional).
var entry_point: String = ""
## Content packs this mod contributes.
var content: Dictionary = {}
## Permissions — what engine APIs this mod may touch.
var permissions: Array[String] = []
## Icon path (optional).
var icon: String = ""
## Minimum game version this mod was built for.
var game_version: String = ""
## Raw JSON dictionary (for round-trip and debugging).
var raw: Dictionary = {}
## Where the manifest was found on disk.
var manifest_path: String = ""

## Parse a dictionary (from JSON) into a manifest. Returns null on failure
## and fills `error` with a human-readable reason.
static func from_dict(data: Dictionary, path: String = "") -> ModManifest:
	var m := ModManifest.new()
	m.raw = data.duplicate(true)
	m.manifest_path = path
	# Required fields
	for field in REQUIRED_FIELDS:
		if not data.has(field) or str(data[field]).strip_edges().is_empty():
			push_warning("ModManifest: missing required field '%s' in %s" % [field, path])
			return null
	m.id = _sanitize_id(str(data.get("id", "")))
	if m.id.is_empty():
		push_warning("ModManifest: invalid id '%s' in %s" % [str(data.get("id", "")), path])
		return null
	m.name = str(data.get("name", m.id))
	m.version = str(data.get("version", "1.0.0"))
	if not _is_valid_version(m.version):
		push_warning("ModManifest: invalid version '%s' for %s" % [m.version, m.id])
		# keep it anyway — version is advisory
	m.description = str(data.get("description", ""))
	m.author = str(data.get("author", ""))
	m.api_version = str(data.get("api_version", "1.0"))
	m.category = str(data.get("category", "gameplay"))
	m.tags = _to_string_array(data.get("tags", []))
	m.is_builtin = bool(data.get("is_builtin", false))
	m.enabled_by_default = bool(data.get("enabled_by_default", false))
	m.load_priority = int(data.get("load_priority", 100))
	m.dependencies = _to_string_array(data.get("dependencies", []))
	m.optional_dependencies = _to_string_array(data.get("optional_dependencies", []))
	m.conflicts = _to_string_array(data.get("conflicts", []))
	m.load_after = _to_string_array(data.get("load_after", []))
	m.load_before = _to_string_array(data.get("load_before", []))
	m.entry_point = str(data.get("entry_point", ""))
	m.content = data.get("content", {}) if data.get("content", {}) is Dictionary else {}
	m.permissions = _to_string_array(data.get("permissions", []))
	m.icon = str(data.get("icon", ""))
	m.game_version = str(data.get("game_version", ""))
	return m

## Load from a JSON file on disk. Returns null on failure.
static func from_file(path: String) -> ModManifest:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("ModManifest: cannot open %s" % path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_warning("ModManifest: invalid JSON in %s" % path)
		return null
	return from_dict(parsed, path)

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"version": version,
		"description": description,
		"author": author,
		"api_version": api_version,
		"category": category,
		"tags": tags,
		"is_builtin": is_builtin,
		"enabled_by_default": enabled_by_default,
		"load_priority": load_priority,
		"dependencies": dependencies,
		"optional_dependencies": optional_dependencies,
		"conflicts": conflicts,
		"load_after": load_after,
		"load_before": load_before,
		"entry_point": entry_point,
		"content": content,
		"permissions": permissions,
		"icon": icon,
		"game_version": game_version,
	}

func is_valid() -> bool:
	return not id.is_empty() and not name.is_empty()

## Human-readable one-line summary.
func summary() -> String:
	return "%s (%s) v%s by %s" % [name, id, version, author]

# --- helpers ---

static func _sanitize_id(raw_id: String) -> String:
	var s := raw_id.strip_edges().to_lower()
	if s.is_empty():
		return ""
	# Must be [a-z0-9_], starting with letter
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*$")
	if not regex.search(s):
		return ""
	return s

static func _is_valid_version(v: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^\\d+\\.\\d+(\\.\\d+)?(-[a-z0-9]+)?$")
	return regex.search(v) != null

static func _to_string_array(val) -> Array[String]:
	var out: Array[String] = []
	if val is Array:
		for e in val:
			out.append(str(e))
	elif val is String and not str(val).is_empty():
		out.append(str(val))
	return out
