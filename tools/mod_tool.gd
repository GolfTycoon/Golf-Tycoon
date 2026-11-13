extends SceneTree

# Preloaded rather than relying on the global class cache, which a --script
# run may not have rebuilt yet.
const ManifestLib := preload("res://scripts/modding/mod_manifest.gd")
const PackageLib := preload("res://scripts/modding/mod_package.gd")
const FeedLib := preload("res://scripts/modding/mod_repository_feed.gd")
## Mod tool - validate mod folders, pack them into shareable zips, and
## build the Official Repository.
##
## Players never need this (the in-game Mods screen installs zips and the
## Browse Mods screen downloads from repository feeds); it is for modders
## and CI:
##
##     godot --headless --path . --script tools/mod_tool.gd -- validate repository/packages/example.jackpot
##     godot --headless --path . --script tools/mod_tool.gd -- pack repository/packages/example.jackpot
##     godot --headless --path . --script tools/mod_tool.gd -- list dist/mods/example.jackpot-1.0.0.zip
##     godot --headless --path . --script tools/mod_tool.gd -- validate-all
##     godot --headless --path . --script tools/mod_tool.gd -- pack-repository
##
## Or through the Makefile: `make mod-pack MOD=repository/packages/<folder>`,
## `make repository` (validate every mod package, pack each into
## repository/zips/ and rewrite repository/official.json - the Official
## Repository feed the game ships pointing at). Exit code is 0 on success,
## 1 on any problem, so CI can gate on it. Validation is exactly what the
## game will say when it scans the same folder, per ModManifest plus file
## existence - a mod that validates here is ready to publish to a feed.
##
## The Official Repository lives in this repository so it is served by
## GitHub straight from `main` (see repository/README.md): the feed JSON at
## repository/official.json, one zip per mod at repository/zips/. Both are
## generated from repository/packages/ by pack-repository, and the unit
## tests check the generated files against the packages, so a mod edited
## without repacking fails the suite.

## Where the generated zips and the feed JSON are written.
const REPOSITORY_ROOT: String = "res://repository"
const PACKAGES_ROOT: String = REPOSITORY_ROOT + "/packages"
const ZIPS_ROOT: String = REPOSITORY_ROOT + "/zips"
## The feed the game adds by default (ModRepositoryStore points players'
## games at this exact address).
const OFFICIAL_FEED_URL: String = "https://raw.githubusercontent.com/GolfTycoon/Golf-Tycoon/main/repository/official.json"
## Download URLs are served from the same tree the feed lives in; one
## zip per mod id.
const OFFICIAL_ZIP_URL_BASE: String = \
	"https://raw.githubusercontent.com/GolfTycoon/Golf-Tycoon/main/repository/zips/"
const OFFICIAL_FEED_NAME: String = "Golf Tycoon Official Repository"
const OFFICIAL_FEED_DESCRIPTION: String = \
	"The official environment mods and every example, straight from the Golf Tycoon project."


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
		"pack-repository":
			quit(0 if _pack_repository() else 1)
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
	print("       mod_tool.gd -- pack-repository")


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
	# A missing icon is a warning, not an error: the mod still loads and is
	# listed, it just wears the default mark in the Mods screen.
	if not manifest.icon.is_empty() and not FileAccess.file_exists(path.path_join(manifest.icon)):
		print("  warning: icon file not found: %s" % manifest.icon)
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
	if not manifest.icon.is_empty() and not bool(read.get("icon_present", true)):
		print("  warning: icon '%s' is declared but not in the zip" % manifest.icon)
	var reader := ZIPReader.new()
	if reader.open(zip_path) == OK:
		for entry in reader.get_files():
			print("  " + str(entry))
		reader.close()
	return true


func _validate_all() -> bool:
	var all_ok: bool = true
	var bundles: Array = []
	var dir := DirAccess.open(PACKAGES_ROOT)
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with(".") and not entry.begins_with("_"):
				bundles.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	bundles.sort()
	print("validating %d mod packages" % bundles.size())
	for name in bundles:
		if not _validate(PACKAGES_ROOT + "/" + name):
			all_ok = false
	return all_ok


## Build the Official Repository from repository/packages/: one zip per mod
## into repository/zips/ (replacing whatever was there) and the feed JSON
## at repository/official.json. Deterministic: the same packages always
## produce byte-identical zips and feed, so committed outputs only change
## when a mod does.
func _pack_repository() -> bool:
	var packages := _package_folders()
	if packages.is_empty():
		push_error("no mod packages found under %s" % PACKAGES_ROOT)
		return false
	var zips_dir: String = ProjectSettings.globalize_path(ZIPS_ROOT)
	DirAccess.make_dir_recursive_absolute(zips_dir)
	# Start from a clean shelf so a mod that left the repository does not
	# leave a stale zip behind.
	for entry in DirAccess.get_files_at(ZIPS_ROOT):
		if str(entry).ends_with(".zip"):
			DirAccess.remove_absolute(ZIPS_ROOT.path_join(str(entry)))
	var entries: Array = []
	for package in packages:
		var folder: String = PACKAGES_ROOT + "/" + package
		if not _validate(folder):
			push_error("not packing an invalid mod: " + package)
			return false
		var manifest: ModManifest = ManifestLib.from_json_text(
			FileAccess.get_file_as_string(folder.path_join("mod.json")), folder)
		var zip_name := "%s.zip" % manifest.id
		var zip_path: String = ZIPS_ROOT.path_join(zip_name)
		var packed: Dictionary = PackageLib.pack_folder(folder, zip_path)
		if not bool(packed.get("ok", false)):
			for error in packed.get("errors", []):
				push_error(str(error))
			push_error("could not pack " + package)
			return false
		var size: int = FileAccess.open(zip_path, FileAccess.READ).get_length()
		print("packed %s (%d files, %d bytes) -> repository/zips/%s"
			% [manifest.display_line(), int(packed.get("file_count", 0)), size, zip_name])
		entries.append(_feed_entry(manifest, size))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["id"]) < str(b["id"]))
	var feed := {
		"format_version": FeedLib.FORMAT_VERSION,
		"name": OFFICIAL_FEED_NAME,
		"description": OFFICIAL_FEED_DESCRIPTION,
		"homepage": "https://github.com/GolfTycoon/Golf-Tycoon",
		"mods": entries,
	}
	DirAccess.make_dir_recursive_absolute(REPOSITORY_ROOT)
	var feed_file := FileAccess.open(REPOSITORY_ROOT + "/official.json", FileAccess.WRITE)
	if feed_file == null:
		push_error("could not write repository/official.json")
		return false
	feed_file.store_string(JSON.stringify(feed, "\t") + "\n")
	feed_file.close()
	print("wrote repository/official.json (%d mods)" % entries.size())
	return true


func _package_folders() -> Array[String]:
	var packages: Array[String] = []
	var dir := DirAccess.open(PACKAGES_ROOT)
	if dir == null:
		return packages
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with(".") and not entry.begins_with("_"):
			packages.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	packages.sort()
	return packages


## One catalogue entry in the Official Repository feed, from a package's
## own manifest - the zip's contents stay the single source of truth; the
## feed only points at it.
func _feed_entry(manifest: ModManifest, size_bytes: int) -> Dictionary:
	return {
		"id": manifest.id,
		"name": manifest.name,
		"version": manifest.version,
		"author": manifest.author,
		"description": manifest.description,
		"download_url": OFFICIAL_ZIP_URL_BASE + manifest.id + ".zip",
		"size_bytes": size_bytes,
		"api_version": manifest.api_version,
	}
