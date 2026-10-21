extends RefCounted
class_name ModPackage
## ModPackage - Reading, installing and writing the `.zip` files mods travel in.
##
## A shipped mod is a zip holding the mod folder's contents at its root (the
## classic shape a Steam Workshop item also has: files, not a Godot resource
## pack). The game reads the manifest straight out of a zip so a player can
## see what a mod is before anything of it runs, and installing a zip simply
## unpacks it into `user://mods/installed/`, after which it is an ordinary
## folder mod.
##
## Everything here is static and autoload-free, so the command-line mod tool
## (tools/mod_tool.gd) can validate and pack mods exactly the way the game
## will read them.

const MAX_ZIP_BYTES: int = 512 * 1024 * 1024
const MAX_FILES: int = 5000
const MAX_FILE_BYTES: int = 128 * 1024 * 1024
## Files that never belong inside a shipped mod.
const SKIP_SUFFIXES: Array[String] = [".zip", ".import", ".uid"]
const SKIP_NAMES: Array[String] = [".DS_Store", "Thumbs.db"]


## The manifest inside `zip_path`, plus the prefix its files live under (""
## when the zip holds the mod at its root, "folder/" when one wrapper folder
## encloses it). Result: {ok, manifest: ModManifest, root_prefix, errors}.
static func read_manifest_from_zip(zip_path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "manifest": null, "root_prefix": "", "errors": []}
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		result["errors"] = ["Could not open '%s' as a zip file." % zip_path]
		return result
	var files := reader.get_files()
	var manifest_entry: String = ""
	for entry in files:
		if entry == "mod.json":
			manifest_entry = entry
			break
		if entry.ends_with("/mod.json") and entry.count("/") == 1:
			manifest_entry = entry
	if manifest_entry.is_empty():
		result["errors"] = ["No mod.json at the root of the zip (or inside one wrapper folder)."]
		reader.close()
		return result
	var bytes := reader.read_file(manifest_entry)
	reader.close()
	var manifest := ModManifest.from_json_text(bytes.get_string_from_utf8(), zip_path)
	result["ok"] = manifest.is_valid()
	result["manifest"] = manifest
	result["root_prefix"] = manifest_entry.trim_suffix("mod.json")
	result["errors"] = manifest.errors
	return result


## Unpack a mod zip into `installed_root/<mod id>/`, replacing any older copy
## of the same mod installed the same way. Paths that would escape the
## destination ("zip slip") are rejected, as are absurd archives.
## Result: {ok, mod_id, directory, errors}.
static func install_zip(zip_path: String, installed_root: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "mod_id": "", "directory": "", "errors": []}
	if not FileAccess.file_exists(zip_path):
		result["errors"] = ["No such file: %s" % zip_path]
		return result
	var size_probe := FileAccess.open(zip_path, FileAccess.READ)
	if size_probe != null and size_probe.get_length() > MAX_ZIP_BYTES:
		result["errors"] = ["The zip is larger than %d MB." % int(MAX_ZIP_BYTES / 1048576.0)]
		return result
	var read := read_manifest_from_zip(zip_path)
	if not bool(read["ok"]):
		result["errors"] = read["errors"]
		return result
	var manifest: ModManifest = read["manifest"]
	var target: String = installed_root.path_join(_folder_name_for(manifest.id))
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		result["errors"] = ["Could not open '%s' as a zip file." % zip_path]
		return result
	var files := reader.get_files()
	if files.size() > MAX_FILES:
		result["errors"] = ["The zip holds more than %d files." % MAX_FILES]
		reader.close()
		return result
	for entry in files:
		if not _entry_is_safe(entry):
			result["errors"] = ["The zip contains an unsafe path: %s" % entry]
			reader.close()
			return result
	# Replace any previous install of this mod wholesale, so files deleted
	# between versions cannot linger.
	if DirAccess.dir_exists_absolute(target):
		remove_directory_recursive(target)
	DirAccess.make_dir_recursive_absolute(target)
	var prefix: String = str(read["root_prefix"])
	for entry in files:
		if entry.ends_with("/"):
			continue
		if not entry.begins_with(prefix):
			continue  # Outside the wrapper folder: not part of the mod.
		var relative: String = entry.trim_prefix(prefix)
		if relative.is_empty():
			continue
		var bytes := reader.read_file(entry)
		if bytes.size() > MAX_FILE_BYTES:
			result["errors"] = ["'%s' is larger than %d MB." % [entry, int(MAX_FILE_BYTES / 1048576.0)]]
			reader.close()
			return result
		var out_path: String = target.path_join(relative)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var out := FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			result["errors"] = ["Could not write '%s'." % out_path]
			reader.close()
			return result
		out.store_buffer(bytes)
	reader.close()
	result["ok"] = true
	result["mod_id"] = manifest.id
	result["directory"] = target
	return result


## Pack `folder` (a mod root holding mod.json) into `out_zip`, files at the
## zip root. Result: {ok, file_count, errors}.
static func pack_folder(folder: String, out_zip: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "file_count": 0, "errors": []}
	if not FileAccess.file_exists(folder.path_join("mod.json")):
		result["errors"] = ["%s holds no mod.json." % folder]
		return result
	var files: Array[String] = []
	_collect_files(folder, "", files)
	DirAccess.make_dir_recursive_absolute(out_zip.get_base_dir())
	var packer := ZIPPacker.new()
	if packer.open(out_zip) != OK:
		result["errors"] = ["Could not create %s." % out_zip]
		return result
	for relative in files:
			packer.start_file(relative)
			packer.write_file(FileAccess.get_file_as_bytes(folder.path_join(relative)))
			packer.close_file()
	packer.close()
	result["ok"] = true
	result["file_count"] = files.size()
	return result


## Every file under `folder` as a path relative to it, sorted.
static func list_files(folder: String) -> Array[String]:
	var files: Array[String] = []
	_collect_files(folder, "", files)
	files.sort()
	return files


## Delete a directory and everything in it. Used for replaced installs and
## uninstalling mods the player installed themselves.
static func remove_directory_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full: String = path.path_join(entry)
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				remove_directory_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## The folder an installed copy of a mod lives in (the id is already a safe
## token, so it is used as-is: `installed/yourname.cool_mod/`).
static func _folder_name_for(mod_id: String) -> String:
	return mod_id


static func _entry_is_safe(entry: String) -> bool:
	if entry.begins_with("/") or entry.begins_with("\\") or entry.contains("\\"):
		return false
	if entry.length() >= 2 and entry[1] == ":":  # Windows drive letters.
		return false
	for part in entry.split("/"):
		if part == "..":
			return false
	return true


static func _collect_files(root: String, relative_dir: String, into: Array[String]) -> void:
	var here: String = root if relative_dir.is_empty() else root.path_join(relative_dir)
	var dir := DirAccess.open(here)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var relative: String = entry if relative_dir.is_empty() else relative_dir.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_files(root, relative, into)
		elif not _should_skip(entry):
			into.append(relative)
		entry = dir.get_next()
	dir.list_dir_end()


static func _should_skip(file_name: String) -> bool:
	if file_name in SKIP_NAMES or file_name.begins_with("."):
		return true
	for suffix in SKIP_SUFFIXES:
		if file_name.ends_with(suffix):
			return true
	return false
