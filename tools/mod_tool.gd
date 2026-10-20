extends SceneTree

# Preloaded rather than relying on the global class cache, which a --script
# run may not have rebuilt yet.
const ManifestLib := preload("res://scripts/modding/mod_manifest.gd")
const PackageLib := preload("res://scripts/modding/mod_package.gd")
## Mod tool - validate mod folders and pack them into shareable zips.
##
## Players never need this (the in-game Mods screen installs zips and
## uploads Workshop items); it is for modders and CI:
##
##     godot --headless --path . --script tools/mod_tool.gd -- validate mods/example.jackpot
##     godot --headless --path . --script tools/mod_tool.gd -- pack mods/example.jackpot
##     godot --headless --path . --script tools/mod_tool.gd -- list dist/mods/example.jackpot-1.0.0.zip
##     godot --headless --path . --script tools/mod_tool.gd -- validate-all
##
## Or through the Makefile: `make mod-pack MOD=mods/example.jackpot`,
## `make mods` (validate every bundled mod and pack them all into
## dist/mods/). Exit code is 0 on success, 1 on any problem, so CI can
## gate on it. Validation is exactly what the game will say when it scans
## the same folder, per ModManifest plus file existence - a mod that
## validates here will be offered (disabled) in the Mods screen.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_print_usage()
		quit(1)
		return
	match args[0]:
		"validate":
			if args.size() < 2:
				_print_usage()
				quit(1)
				return
			quit(0 if _validate(_absolute(args[1])) else 1)
		"pack":
			if args.size() < 2:
				_print_usage()
				quit(1)
				return
			quit(0 if _pack(_absolute(args[1]),
				_absolute(args[2]) if args.size() > 2 else "") else 1)
		"list":
			if args.size() < 2:
				_print_usage()
				quit(1)
				return
			quit(0 if _list(_absolute(args[1])) else 1)
		"validate-all":
			quit(0 if _validate_all() else 1)
		_:
			_print_usage()
			quit(1)


## A path as the engine tools understand it: res:// stays, anything else is
## made absolute against the working directory.
func _absolute(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path) \
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path) \
		else OS.get_executable_path().get_base_dir().path_join(path)


func _print_usage() -> void:
	print("usage: mod_tool.gd -- validate <mod folder or .zip>")
	print("       mod_tool.gd -- pack <mod folder> [output.zip]")
	print("       mod_tool.gd -- list <mod .zip>")
	print("       mod_tool.gd -- validate-all")


func _validate(path: String) -> bool:
	if path.to_lower().ends_with(".zip"):
		return _list(path)
	var manifest_path: String = path.path_join("mod.json")
	var text: String = FileAccess.get_file_as_string(manifest_path)
	if text.is_empty():
		push_error("no mod.json readable at " + manifest_path)
		return false
	var manifest: ModManifest = ManifestLib.from_json_text(text, manifest_path)
	print("mod: %s %s (%s)" % [manifest.name, manifest.version, manifest.id])
	for warning in manifest.warnings:
		print("  warning: " + warning)
	for error in manifest.errors:
		push_error("  error: " + error)
	var ok: bool = manifest.is_valid()
	if manifest.has_script():
		var entry_path: String = path.path_join(manifest.entry_point)
		if not FileAccess.file_exists(entry_path):
			push_error("  error: entry point not found: " + entry_path)
			ok = false
		else:
			var script := load(entry_path) as GDScript
			if script == null:
				push_error("  error: entry point does not parse: " + entry_path)
				ok = false
	for kind in manifest.content:
		for relative in _content_paths(manifest.content[kind]):
			if not FileAccess.file_exists(path.path_join(relative)) 					and not DirAccess.dir_exists_absolute(path.path_join(relative)):
				push_error("  error: content path not found: %s (%s)" % [relative, str(kind)])
				ok = false
	if ok:
		print("  valid")
	return ok


## A content value is one path, several, or (visiting_golfers) a map of them.
func _content_paths(value: Variant) -> Array[String]:
	var paths: Array[String] = []
	if value is String:
		paths.append(value)
	elif value is Array:
		for entry in value:
			paths.append(str(entry))
	elif value is Dictionary:
		for key in value:
			paths.append(str(value[key]))
	return paths


func _pack(folder: String, output_path: String) -> bool:
	if not _validate(folder):
		push_error("not packing an invalid mod")
		return false
	var manifest: ModManifest = ManifestLib.from_json_text(
		FileAccess.get_file_as_string(folder.path_join("mod.json")), folder)
	if output_path.is_empty():
		var dist: String = ProjectSettings.globalize_path("res://").path_join("dist/mods")
		DirAccess.make_dir_recursive_absolute(dist)
		output_path = dist.path_join("%s-%s.zip" % [manifest.id, manifest.version])
	var packed: Dictionary = PackageLib.pack_folder(folder, output_path)
	if not bool(packed.get("ok", false)):
		for error in packed.get("errors", []):
			push_error(str(error))
		return false
	print("packed %d files -> %s" % [int(packed.get("file_count", 0)), output_path])
	return true


func _list(zip_path: String) -> bool:
	var read: Dictionary = PackageLib.read_manifest_from_zip(zip_path)
	for error in read.get("errors", []):
		push_error(str(error))
	if not bool(read.get("ok", false)):
		return false
	var manifest: ModManifest = read["manifest"]
	print("mod: %s" % manifest.display_line())
	for warning in manifest.warnings:
		print("  warning: " + warning)
	var reader := ZIPReader.new()
	if reader.open(zip_path) == OK:
		for entry in reader.get_files():
			print("  " + str(entry))
		reader.close()
	return true


func _validate_all() -> bool:
	var all_ok: bool = true
	var bundles: Array = []
	var dir := DirAccess.open("res://mods")
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with(".") and not entry.begins_with("_"):
				bundles.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	bundles.sort()
	print("validating %d bundled mods" % bundles.size())
	for name in bundles:
		if not _validate("res://mods/" + name):
			all_ok = false
	return all_ok
