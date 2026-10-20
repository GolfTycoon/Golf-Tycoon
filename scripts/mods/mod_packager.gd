extends RefCounted
class_name ModPackager
## ModPackager - Create and install mod ZIPs for sharing.
##
## Players can build a mod as a folder under user://mods/<id>/ (with mod.json
## at its root). This helper packs that folder into a single .zip that can be
## dropped into Discord, itch.io, or Steam Workshop, and does the reverse:
## installing a .zip by unpacking it into user://mods/.
##
## The zip layout is the same as the folder on disk: mod.json at the archive
## root (or one subfolder deep, to tolerate zips made from a parent folder),
## plus all scripts, sprites, audio, etc. that the mod needs. Builtins are
## never exported — they ship with the game.
##
## Uses ZIPReader/ZIPPacker when available (Godot 4.x). Falls back to a
## clear error if the engine was built without them.

const EXPORTS_DIR: String = "user://mods/exports"
const WORKSHOP_STAGING_DIR: String = "user://workshop/staging"

## Export a mod to a zip. Returns the absolute or user:// path on success,
## or an empty string on failure. Emits a notification via EventBus.
static func export_mod(mod_id: String) -> String:
	@warning_ignore("inferred_declaration")
	var mf = ModManager.manifests.get(mod_id, null) if ModManager else null
	if mf == null:
		# Try direct folder check even if not discovered
		if not FileAccess.file_exists("user://mods/%s/mod.json" % mod_id):
			push_warning("ModPackager: cannot export unknown mod %s" % mod_id)
			if has_node_warning():
				EventBus.notify("Cannot export '%s' — mod not found." % mod_id, "error")
			return ""
		# Fallback manifest
		mf = ModManifest.from_file("user://mods/%s/mod.json" % mod_id)
		if mf == null:
			return ""
	if mf.is_builtin:
		push_warning("ModPackager: builtin mod %s is not exported — it ships with the game." % mod_id)
		_notify("Builtin mods ship with the game — no need to export '%s'." % mf.name, "info")
		return ""

	var source_dir: String = mf.manifest_path.get_base_dir()
	if source_dir.is_empty() or source_dir == "res://mods":
		# Try user dir for this id
		source_dir = "user://mods/%s" % mod_id
	if not DirAccess.dir_exists_absolute(source_dir) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(source_dir)):
		# Another fallback: manifest_path may be empty for zipped mods; use user dir
		source_dir = "user://mods/%s" % mod_id
	if not _dir_exists(source_dir):
		_notify("Mod folder not found for '%s'." % mod_id, "error")
		return ""

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORTS_DIR))
	var version_safe: String = mf.version.replace(".", "_")
	var zip_name: String = "%s-%s.zip" % [mod_id, version_safe]
	var zip_path: String = EXPORTS_DIR.path_join(zip_name) # user://

	var err := _pack_zip(source_dir, zip_path)
	if err != OK:
		push_error("ModPackager: ZIP pack failed for %s: %s" % [mod_id, error_string(err)])
		_notify("Export failed for '%s'." % mod_id, "error")
		return ""
	var abs_path := ProjectSettings.globalize_path(zip_path)
	_notify("Exported '%s' to %s" % [mod_id, zip_path], "success")
	print("ModPackager: exported %s -> %s (%s)" % [mod_id, zip_path, abs_path])
	return zip_path

## Import a zip file from an OS path or user:// path into user://mods/.
## Validates that the zip contains a mod.json with a valid id before
## extracting. Returns the mod id on success, empty string on failure.
static func import_zip(zip_path: String, overwrite: bool = false) -> String:
	if not FileAccess.file_exists(zip_path) and not FileAccess.file_exists(ProjectSettings.globalize_path(zip_path)):
		# Try absolute OS path
		if not FileAccess.file_exists(zip_path):
			_notify("ZIP not found: %s" % zip_path, "error")
			return ""
	# Read manifest from zip without extracting all files
	var reader := ZIPReader.new()
	var open_err := reader.open(zip_path)
	if open_err != OK:
		_notify("Cannot open ZIP: %s" % zip_path, "error")
		return ""
	var mod_json_path := _find_mod_json_in_zip(reader)
	if mod_json_path.is_empty():
		_notify("ZIP does not contain a mod.json", "error")
		reader.close()
		return ""
	var manifest_text := reader.read_file(mod_json_path).get_string_from_utf8()
	reader.close()
	var parsed = JSON.parse_string(manifest_text)
	if not parsed is Dictionary:
		_notify("Invalid mod.json in ZIP", "error")
		return ""
	var mf := ModManifest.from_dict(parsed, zip_path + "::" + mod_json_path)
	if mf == null or not mf.is_valid():
		_notify("Invalid mod manifest in ZIP", "error")
		return ""
	if mf.is_builtin:
		_notify("Builtin mod '%s' cannot be imported — it already ships with the game." % mf.id, "warning")
		return ""

	# Check for existing id
	var dest_dir := "user://mods/%s" % mf.id
	if _dir_exists(dest_dir):
		if not overwrite:
			_notify("Mod '%s' already exists. Enable overwrite to replace it." % mf.id, "warning")
			return ""
		# Remove old files
		_remove_dir_recursive(dest_dir)

	# Extract
	reader = ZIPReader.new()
	reader.open(zip_path)
	var files := reader.get_files()
	var prefix := mod_json_path.get_base_dir() # "" or "my_mod" etc
	# If zip contains a single top-level folder, strip it so contents go directly into dest_dir
	# Heuristic: if every file starts with "<prefix>/" and prefix is not empty, strip it.
	# We already have mod_json_path, so we know the prefix to strip.
	for file_path in files:
		if file_path.ends_with("/"):
			continue # directory entry, will be created as needed
		var rel := file_path
		# Strip leading prefix if present
		if not prefix.is_empty() and rel.begins_with(prefix):
			rel = rel.substr(prefix.length()).lstrip("/")
			if rel.is_empty():
				continue
		# Skip the manifest at root? No, we want it
		var dest_path := dest_dir.path_join(rel)
		if rel.is_empty():
			continue
		var dir_part := dest_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_part))
		var data: PackedByteArray = reader.read_file(file_path)
		var out := FileAccess.open(dest_path, FileAccess.WRITE)
		if out == null:
			push_warning("ModPackager: cannot write %s" % dest_path)
			continue
		out.store_buffer(data)
	reader.close()

	_notify("Imported mod '%s' v%s" % [mf.name, mf.version], "success")
	print("ModPackager: imported %s from %s" % [mf.id, zip_path])
	# Refresh discovery so new mod appears without restart
	if ModManager:
		ModManager.refresh_after_user_change()
	return mf.id

## Create a new mod from a template in user://mods/<id>/. Returns id or "".
static func create_template(new_id: String, display_name: String, author: String) -> String:
	var sanitized := ModManifest._sanitize_id(new_id)
	if sanitized.is_empty():
		_notify("Invalid mod id '%s' — use letters, numbers, underscores starting with a letter." % new_id, "error")
		return ""
	var dest_dir := "user://mods/%s" % sanitized
	if _dir_exists(dest_dir):
		_notify("Mod '%s' already exists." % sanitized, "error")
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_dir))
	var manifest := {
		"id": sanitized,
		"name": display_name if not display_name.is_empty() else sanitized.capitalize(),
		"version": "0.1.0",
		"description": "A new Golf Tycoon mod.",
		"author": author if not author.is_empty() else "You",
		"api_version": ModAPI.API_VERSION,
		"category": "content",
		"is_builtin": false,
		"enabled_by_default": false,
		"load_priority": 200,
		"dependencies": [],
		"optional_dependencies": [],
		"conflicts": [],
		"load_after": [],
		"load_before": [],
		"entry_point": "user://mods/%s/mod.gd" % sanitized,
		"content": {},
		"permissions": ["event_bus"],
		"tags": ["community"],
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.4.6")),
	}
	var json_path := dest_dir.path_join("mod.json")
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	var script_path := dest_dir.path_join("mod.gd")
	var sf := FileAccess.open(script_path, FileAccess.WRITE)
	sf.store_string(_template_script(sanitized, display_name))
	_notify("Created mod '%s' at %s" % [sanitized, dest_dir], "success")
	print("ModPackager: created template %s" % dest_dir)
	if ModManager:
		ModManager.refresh_after_user_change()
	return sanitized

## Open the OS file browser to the mods folder.
static func open_mods_folder() -> void:
	ModLoader.ensure_user_mods_dir()
	var abs_dir := ProjectSettings.globalize_path("user://mods")
	# Also ensure exports exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORTS_DIR))
	var err := OS.shell_open(abs_dir)
	if err != OK:
		# Fallback: copy path to clipboard
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			DisplayServer.clipboard_set(abs_dir)
		_notify("Mods folder: %s (copied to clipboard)" % abs_dir, "info")
		print("ModPackager: mods folder %s" % abs_dir)

static func _pack_zip(source_dir: String, zip_path: String) -> int:
	var packer := ZIPPacker.new()
	if packer == null:
		push_error("ModPackager: ZIPPacker not available in this Godot build")
		return ERR_UNAVAILABLE
	var err := packer.open(zip_path)
	if err != OK:
		return err
	var files := _collect_files_recursive(source_dir)
	for rel in files:
		var abs_path := source_dir.path_join(rel)
		var fa := FileAccess.open(abs_path, FileAccess.READ)
		if fa == null:
			continue
		var data := fa.get_buffer(fa.get_length())
		packer.start_file(rel)
		packer.write_file(data)
		packer.close_file()
	packer.close()
	return OK

static func _collect_files_recursive(root: String, prefix: String = "") -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := root.path_join(entry)
		var rel := prefix.path_join(entry) if not prefix.is_empty() else entry
		if dir.current_is_dir():
			var sub := _collect_files_recursive(full, rel)
			for s in sub:
				out.append(s)
		else:
			out.append(rel)
		entry = dir.get_next()
	dir.list_dir_end()
	return out

static func _find_mod_json_in_zip(reader: ZIPReader) -> String:
	var files := reader.get_files()
	# Prefer root mod.json
	for p in files:
		if p == "mod.json" or p.ends_with("/mod.json"):
			# Return the first match with minimal depth (prefer shallower)
			# Collect candidates sorted by depth
			pass
	var candidates: Array[String] = []
	for p in files:
		if p.ends_with("mod.json"):
			candidates.append(p)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a, b): return a.count("/") < b.count("/"))
	return candidates[0]

static func _dir_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)) or DirAccess.dir_exists_absolute(path)

static func _remove_dir_recursive(path: String) -> void:
	var gpath := ProjectSettings.globalize_path(path)
	var da := DirAccess.open(gpath)
	if da == null:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = da.get_next()
			continue
		var full := gpath.path_join(entry)
		if DirAccess.dir_exists_absolute(full):
			_remove_dir_recursive(full)
			DirAccess.remove_absolute(full)
		else:
			DirAccess.remove_absolute(full)
		entry = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(gpath)

static func _template_script(id: String, display_name: String) -> String:
	var title := display_name if not display_name.is_empty() else id.capitalize()
	return """extends RefCounted
# %s - Community mod for Golf Tycoon
# See docs/modding.md for the API.

var api: ModAPI = null
var mod_manifest: ModManifest = null

func _mod_on_load() -> bool:
\tapi.log_info("'%s' loaded")
\treturn true

func _mod_on_enable() -> bool:
\tapi.log_info("'%s' enabled")
\t# Example: add a building
\t# api.register_building_type("my_building", {"name": "My Building", "cost": 5000})
\t# api.register_hook("day_changed", func(day): print("Day ", day))
\treturn true

func _mod_on_disable() -> bool:
\tapi.log_info("'%s' disabled")
\treturn true

func _mod_on_unload() -> bool:
\treturn true
""" % [title, title, title, title]

static func has_node_warning() -> bool:
	return Engine.get_main_loop() != null and Engine.get_main_loop().root.has_node("/root/EventBus")

static func _notify(msg: String, type: String) -> void:
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("/root/EventBus"):
		var eb = Engine.get_main_loop().root.get_node_or_null("/root/EventBus")
		if eb and eb.has_method("notify"):
			eb.notify(msg, type)
			return
	print("ModPackager: %s [%s]" % [msg, type])
