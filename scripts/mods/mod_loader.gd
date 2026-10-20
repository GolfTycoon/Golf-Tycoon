extends RefCounted
class_name ModLoader
## ModLoader - Discovers mods on disk and parses their manifests.
##
## Looks in:
##   - res://mods/            (builtin, shipped with the game)
##   - user://mods/            (user-installed, folders or .zip files)
##   - user://workshop/        (local “workshop” staging — see ModWorkshop)
##
## Each mod is a folder containing a mod.json, or a .zip containing one.
## The loader returns a dictionary of id -> ModManifest, de-duplicating by
## id (builtin wins over user, so a user mod cannot shadow a builtin one).
## Zip manifests are read via ZIPReader without extracting.

const BUILTIN_MODS_PATH := "res://mods"
const USER_MODS_PATH := "user://mods"
const WORKSHOP_STAGING_PATH := "user://workshop/staging"
## Optional extra workshop path via env var (set by Steam or tests).
const ENV_WORKSHOP_PATH := "GOLF_TYCOON_WORKSHOP_PATH"

## Discover all manifests. Returns { id: ModManifest }.
static func discover() -> Dictionary:
	var found: Dictionary = {}
	# Builtins first (so they win on id collision)
	_scan_path(BUILTIN_MODS_PATH, found, true)
	_scan_path(USER_MODS_PATH, found, false)
	_scan_zips(USER_MODS_PATH, found, false)
	# Local workshop staging — lower priority than user://mods but scanned
	_scan_path(WORKSHOP_STAGING_PATH, found, false)
	_scan_zips(WORKSHOP_STAGING_PATH, found, false)
	# Steam workshop via env var (points at steamapps/workshop/content/<app_id>)
	var env_root := OS.get_environment(ENV_WORKSHOP_PATH)
	if not env_root.is_empty():
		_scan_path(env_root, found, false)
		_scan_zips(env_root, found, false)
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
			entry = dir.get_next()
			continue
		if dir.current_is_dir():
			var mod_path := root.path_join(entry).path_join("mod.json")
			if FileAccess.file_exists(mod_path):
				var manifest := ModManifest.from_file(mod_path)
				if manifest != null:
					if is_builtin:
						manifest.is_builtin = true
					_register_manifest(out, manifest, mod_path, is_builtin)
				else:
					push_warning("ModLoader: failed to parse %s" % mod_path)
			else:
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

## Scan a root folder for .zip files that contain a mod.json.
## If a zip's mod is not yet unpacked, it is auto-extracted to user://mods/<id>/
## so scripts can be loaded via ResourceLoader (Godot cannot load GDScript
## from inside a zip directly).
static func _scan_zips(root: String, out: Dictionary, is_builtin: bool) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".zip"):
			var zip_path := root.path_join(entry)
			var manifest := _manifest_from_zip(zip_path)
			if manifest != null:
				if is_builtin:
					manifest.is_builtin = true
				# Auto-extract zips dropped into user://mods/ so they become
				# real folders that ModLoader can load with _scan_path.
				var dest_dir := "user://mods/%s" % manifest.id
				if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest_dir)):
					if _extract_zip(zip_path, dest_dir):
						print("ModLoader: auto-extracted zipped mod %s to %s" % [manifest.id, dest_dir])
						# Re-read manifest from extracted folder for canonical path
						var extracted_manifest := ModManifest.from_file(dest_dir.path_join("mod.json"))
						if extracted_manifest != null:
							manifest = extracted_manifest
							manifest.manifest_path = dest_dir.path_join("mod.json")
							if is_builtin:
								manifest.is_builtin = true
				if out.has(manifest.id):
					push_warning("ModLoader: duplicate zipped mod id '%s' in %s — skipping" % [manifest.id, zip_path])
				else:
					out[manifest.id] = manifest
					print("ModLoader: discovered zipped mod %s in %s" % [manifest.id, zip_path])
		entry = dir.get_next()
	dir.list_dir_end()

## Extract a mod zip to dest_dir (overwrites). Returns success.
static func _extract_zip(zip_path: String, dest_dir: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	var files := reader.get_files()
	if files.is_empty():
		reader.close()
		return false
	# Find mod.json depth to strip top-level folder if present
	var mod_json_path := ""
	for p in files:
		if p.ends_with("mod.json"):
			mod_json_path = p
			break
	var candidates: Array[String] = []
	for p in files:
		if p.ends_with("mod.json"):
			candidates.append(p)
	candidates.sort_custom(func(a, b): return a.count("/") < b.count("/"))
	if not candidates.is_empty():
		mod_json_path = candidates[0]
	var strip_prefix := mod_json_path.get_base_dir() # "" or "my_mod" or "mods/my_mod"
	for file_path in files:
		if file_path.ends_with("/"):
			continue
		var rel := file_path
		if not strip_prefix.is_empty() and rel.begins_with(strip_prefix):
			rel = rel.substr(strip_prefix.length()).lstrip("/")
			if rel.is_empty():
				continue
		var dest_path := dest_dir.path_join(rel)
		var dir_part := dest_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_part))
		var data: PackedByteArray = reader.read_file(file_path)
		var out := FileAccess.open(dest_path, FileAccess.WRITE)
		if out:
			out.store_buffer(data)
	reader.close()
	return true

## Read mod.json from inside a zip without extracting.
static func _manifest_from_zip(zip_path: String) -> ModManifest:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return null
	var files := reader.get_files()
	var candidate := ""
	for p in files:
		if p.ends_with("mod.json"):
			candidate = p
			break
	# Prefer shallowest mod.json
	if candidate.is_empty():
		reader.close()
		return null
	var candidates: Array[String] = []
	for p in files:
		if p.ends_with("mod.json"):
			candidates.append(p)
	candidates.sort_custom(func(a, b): return a.count("/") < b.count("/"))
	candidate = candidates[0]
	var bytes := reader.read_file(candidate)
	reader.close()
	if bytes.is_empty():
		return null
	var text := bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return null
	var mf := ModManifest.from_dict(parsed, candidate)
	if mf == null:
		return null
	# Fix entry_point if it was relative to res:// but zip is in user://
	# Keep as declared; Mod.gd will resolve both res:// and user:// via ResourceLoader
	return mf

static func _register_manifest(out: Dictionary, manifest: ModManifest, mod_path: String, is_builtin: bool) -> void:
	if out.has(manifest.id):
		if not is_builtin:
			push_warning("ModLoader: duplicate mod id '%s' in %s — skipping (builtin wins)" % [manifest.id, mod_path])
		else:
			push_warning("ModLoader: duplicate builtin id '%s' — overwriting" % manifest.id)
			out[manifest.id] = manifest
	else:
		out[manifest.id] = manifest

## Ensure the user mods folder exists.
static func ensure_user_mods_dir() -> void:
	var da := DirAccess.open("user://")
	if da and not da.dir_exists("mods"):
		da.make_dir("mods")
	# Also ensure workshop staging/exports exist
	var exports := ProjectSettings.globalize_path("user://mods/exports")
	DirAccess.make_dir_recursive_absolute(exports)
	var staging := ProjectSettings.globalize_path("user://workshop/staging")
	DirAccess.make_dir_recursive_absolute(staging)

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
