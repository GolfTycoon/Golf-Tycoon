extends RefCounted
class_name ModLoader
## ModLoader - Discovers mods on disk and parses their manifests.
##
## Looks in:
##   - res://mods/            (builtin, shipped with the game)
##   - user://mods/            (user-installed)
##
## Each mod is a folder containing a mod.json. The loader returns a
## dictionary of id -> ModManifest, de-duplicating by id (builtin wins
## over user, so a user mod cannot shadow a builtin one).

const BUILTIN_MODS_PATH := "res://mods"
const USER_MODS_PATH := "user://mods"

## Discover all manifests. Returns { id: ModManifest }.
static func discover() -> Dictionary:
	var found: Dictionary = {}
	# Builtins first (so they win on id collision)
	_scan_path(BUILTIN_MODS_PATH, found, true)
	_scan_path(USER_MODS_PATH, found, false)
	return found

## Scan a root folder for mod.json files.
static func _scan_path(root: String, out: Dictionary, is_builtin: bool) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry == "mod.json":
			# Should not happen (root level file) — skip
			entry = dir.get_next()
			continue
		if dir.current_is_dir():
			var mod_path := root.path_join(entry).path_join("mod.json")
			if FileAccess.file_exists(mod_path):
				var manifest := ModManifest.from_file(mod_path)
				if manifest != null:
					# Enforce builtin flag from location (authoritative)
					if is_builtin:
						manifest.is_builtin = true
					if out.has(manifest.id):
						# Builtins already in map win; user mods with duplicate id are warned and skipped
						if not is_builtin:
							push_warning("ModLoader: duplicate mod id '%s' in %s — skipping (builtin wins)" % [manifest.id, mod_path])
						else:
							push_warning("ModLoader: duplicate builtin id '%s' — overwriting" % manifest.id)
							out[manifest.id] = manifest
					else:
						out[manifest.id] = manifest
				else:
					push_warning("ModLoader: failed to parse %s" % mod_path)
			else:
				# Recurse into subfolders that might contain mods (e.g. res://mods/category/mod/)
				# Only one level deep to prevent deep walks
				var sub_root := root.path_join(entry)
				_scan_nested(sub_root, out, is_builtin)
		entry = dir.get_next()
	dir.list_dir_end()

static func _scan_nested(root: String, out: Dictionary, is_builtin: bool) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			var mod_path := root.path_join(entry).path_join("mod.json")
			if FileAccess.file_exists(mod_path):
				var manifest := ModManifest.from_file(mod_path)
				if manifest != null:
					if is_builtin:
						manifest.is_builtin = true
					if not out.has(manifest.id):
						out[manifest.id] = manifest
		entry = dir.get_next()
	dir.list_dir_end()

## Ensure the user mods folder exists.
static func ensure_user_mods_dir() -> void:
	var da := DirAccess.open("user://")
	if da and not da.dir_exists("mods"):
		da.make_dir("mods")

## Read the persisted enabled-mods ordered list from user://mods.json.
## Returns null if no persisted file exists (caller uses defaults).
static func load_enabled_order() -> Variant:
	var path := "user://mods.json"
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.has("enabled"):
		var arr = parsed["enabled"]
		if arr is Array:
			return arr
	return null

## Persist the enabled-mods ordered list.
static func save_enabled_order(enabled_order: Array[String]) -> void:
	var path := "user://mods.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("ModLoader: cannot write %s" % path)
		return
	var data := {
		"enabled": enabled_order,
		"saved_at": Time.get_datetime_string_from_system(),
		"version": 1,
	}
	f.store_string(JSON.stringify(data, "\t"))
