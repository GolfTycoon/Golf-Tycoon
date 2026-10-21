extends Node
## ModManager - Finds mods, decides the order they load in, and loads them.
##
## Autoloaded as `ModManager`. At boot it discovers mods from four places:
##
##   res://mods/            bundled with the game (the official mods and the
##                          examples players can copy and learn from)
##   Steam Workshop items   subscribed items, through SteamWorkshopProvider
##                          when GodotSteam is present (silently absent
##                          otherwise - everything else keeps working)
##   user://mods/*.zip      zip files a player dropped in (installed on load)
##   user://mods/<folder>/  folder mods, including previously installed zips
##                          under user://mods/installed/
##
## Which of those are on, and in what order, is the player's: an ordered list
## kept in user://mods/load_order.json and edited in the Mods screen.
## Dependencies, conflicts and each manifest's load_after/load_before are
## resolved against that list (later in the order wins data conflicts and
## provider take-overs), and anything that cannot be satisfied is reported
## per mod instead of failing the whole load. On first run the list is
## seeded with every bundled mod that asks to be on by default - which is
## how Weather, Wind and Seasons, the three official feature mods, come to
## be running out of the box.
##
## Loading a mod means: mount its resource packs, apply its declared data
## through ContentRegistry, then - only with the "script" permission - run
## its entry point with a ModAPI. A mod that errors is marked and skipped;
## the ones after it still load. `--no-mods` on the command line skips
## loading entirely, and a marker file turns one hard crash while loading
## script mods into a script-free "safe mode" boot the next time.

## Mod sources, lowest precedence first for one mod found in several places.
const SOURCE_BUNDLED: String = "bundled"
const SOURCE_WORKSHOP: String = "workshop"
const SOURCE_ZIP: String = "zip"
const SOURCE_USER: String = "user"
const _SOURCE_PRECEDENCE: Dictionary = {
	SOURCE_BUNDLED: 0, SOURCE_WORKSHOP: 1, SOURCE_ZIP: 2, SOURCE_USER: 3,
}

const CONFIG_FILE: String = "load_order.json"
const CRASH_MARKER: String = ".loading_mods"

var bundled_root: String = "res://mods"
var user_root: String = "user://mods"
var use_steam: bool = true

var _registry: Node = null  # ContentRegistry; the autoload by default.
var _steam: SteamWorkshopProvider = SteamWorkshopProvider.new()

var _records: Dictionary = {}  # id -> record Dictionary (see _new_record)
var _discovery_warnings: Array[String] = []
var _persisted_enabled: Array[String] = []  # The player's ordered list.
var _loaded_order: Array[String] = []  # What actually loaded, in order.
var _loaded_nodes: Dictionary = {}  # id -> GolfTycoonMod
var _resolution_errors: Dictionary = {}  # id -> [String]
var _hooks: Dictionary = {}  # hook name -> [{mod_id, callable}]
var _hud_widgets: Array = []  # [{mod_id, factory}]
var _main_scene_callbacks: Array = []  # [{mod_id, callable}]
var _weather_factory: Callable
var _weather_factory_owner: String = ""
var _wind_factory: Callable
var _wind_factory_owner: String = ""
var _season_provider_owner: String = ""
var _provider_notes: Array[String] = []
var _start_features: Array = []  # feature option dicts registered by mods: {id, title, caption, tooltip, glyph, mod_id}
var _texture_cache: Dictionary = {}
var _mod_configs: Dictionary = {}  # id -> Dictionary (lazy)
var _main_scene: Node = null

## True after the player changed the enabled set or its order and those
## changes have not been loaded yet.
var needs_reload: bool = false
## True when this boot found a half-written crash marker and skipped script
## mods so the player can reach the Mods screen and sort it out.
var safe_mode_triggered: bool = false
## True when --no-mods was passed: nothing loads this session.
var mods_disabled_by_flag: bool = false
var _initialized: bool = false
var _owns_crash_marker: bool = false


func _ready() -> void:
	# Only the autoload instance (a child of the root) boots the real mod
	# set. Tests add their own managers under the test node and initialize()
	# them against throwaway roots by hand.
	if get_parent() == get_tree().root:
		initialize()


## Discover and load, once. Safe to call again - later calls do nothing
## (use reload_mods() to re-run the set on purpose).
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if _registry == null:
		_registry = get_node_or_null("/root/ContentRegistry") if is_inside_tree() else null
	if not EventBus.main_scene_ready.is_connected(_on_main_scene_ready):
		EventBus.main_scene_ready.connect(_on_main_scene_ready)
	if not EventBus.new_game_started.is_connected(_on_new_game_started):
		EventBus.new_game_started.connect(_on_new_game_started)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	mods_disabled_by_flag = "--no-mods" in args
	# Validation/packing must not start a gameplay mod session or leave a
	# crash marker simply because the command-line tool quits immediately.
	var loop_script: Script = Engine.get_main_loop().get_script()
	if loop_script != null and loop_script.resource_path == "res://tools/mod_tool.gd":
		mods_disabled_by_flag = true
	discover()
	if not mods_disabled_by_flag:
		load_enabled_mods()


## Use a specific content registry (tests); the autoload by default.
func set_content_registry(registry: Node) -> void:
	_registry = registry


func content_registry() -> Node:
	if _registry == null and is_inside_tree():
		_registry = get_node_or_null("/root/ContentRegistry")
	return _registry


# =============================================================================
# DISCOVERY
# =============================================================================

## Find every mod this installation knows about. The player's enabled list is
## read (or seeded) here, so the Mods screen can render straight away.
func discover() -> void:
	var previous_records := _records.duplicate()
	_records.clear()
	_discovery_warnings.clear()
	_discover_folder_mods(bundled_root, SOURCE_BUNDLED, 0)
	if use_steam and _steam != null:
		for item in _steam.get_subscribed_mod_roots():
			var folder: String = str(item.get("folder", ""))
			if not folder.is_empty():
				# A Workshop item is one mod folder (or a zip beside it).
				_discover_one_folder(folder, SOURCE_WORKSHOP, int(item.get("published_file_id", 0)))
	_discover_zip_mods(user_root)
	_discover_folder_mods(user_root.path_join("installed"), SOURCE_USER, 0, true)
	_discover_folder_mods(user_root, SOURCE_USER, 0)
	_read_persisted_order()
	for mod_id in _records:
		_records[mod_id]["enabled"] = mod_id in _persisted_enabled
		if mod_id in _loaded_order:
			_records[mod_id]["loaded"] = true
			_records[mod_id]["state"] = "loaded"
	# Keep live records even if files vanished: uninstall must never delete a
	# running mod just because the library was rescanned.
	for live_id in _loaded_order:
		if not _records.has(live_id) and previous_records.has(live_id):
			_records[live_id] = previous_records[live_id]


func _discover_folder_mods(root: String, source: String, workshop_id: int, installed: bool = false) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		# Underscore-prefixed folders (the template) and the bookkeeping
		# folders are not mods.
		if dir.current_is_dir() and not entry.begins_with(".") and not entry.begins_with("_") \
				and entry not in ["installed", "config"]:
			_discover_one_folder(root.path_join(entry), source, workshop_id, installed)
		entry = dir.get_next()
	dir.list_dir_end()


func _discover_one_folder(folder: String, source: String, workshop_id: int, installed: bool = false) -> void:
	var manifest_path: String = folder.path_join("mod.json")
	if not FileAccess.file_exists(manifest_path):
		return
	var manifest := ModManifest.from_json_text(
		FileAccess.get_file_as_string(manifest_path), manifest_path)
	if manifest.id.is_empty():
		_discovery_warnings.append("%s: mod.json has no usable id." % folder)
		return
	_register_discovered(manifest, source, folder, "", workshop_id, installed)


func _discover_zip_mods(root: String) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".zip"):
			var zip_path: String = root.path_join(entry)
			var read: Dictionary = ModPackage.read_manifest_from_zip(zip_path)
			var manifest: ModManifest = read.get("manifest", null)
			if manifest == null or manifest.id.is_empty():
				_discovery_warnings.append("%s: %s" % [zip_path, "; ".join(read.get("errors", ["not a mod zip"]))])
			else:
				_register_discovered(manifest, SOURCE_ZIP, "", zip_path, 0, false)
		entry = dir.get_next()
	dir.list_dir_end()


func _register_discovered(manifest: ModManifest, source: String, root: String,
		zip_path: String, workshop_id: int, installed: bool) -> void:
	var existing: Dictionary = _records.get(manifest.id, {})
	if not existing.is_empty():
		var mine: int = int(_SOURCE_PRECEDENCE.get(source, 0))
		var theirs: int = int(_SOURCE_PRECEDENCE.get(str(existing["source"]), 0))
		if mine < theirs:
			return  # Shadowed by the copy the player controls more directly.
		if mine == theirs and ModManifest.compare_versions(
				manifest.version, (existing["manifest"] as ModManifest).version) < 0:
			return
	_records[manifest.id] = {
		"id": manifest.id, "manifest": manifest, "source": source,
		"root": root, "zip_path": zip_path, "workshop_id": workshop_id,
		"installed": installed, "enabled": false, "loaded": false,
		"auto_enabled": false, "state": "discovered",
		"errors": manifest.errors.duplicate(), "warnings": manifest.warnings.duplicate(),
	}


# =============================================================================
# THE PLAYER'S ORDERED LIST (user://mods/load_order.json)
# =============================================================================

func _config_path() -> String:
	return user_root.path_join(CONFIG_FILE)


func _read_persisted_order() -> void:
	_persisted_enabled.clear()
	var parsed: Variant = null
	if FileAccess.file_exists(_config_path()):
		parsed = ModManifest.parse_json_quietly(FileAccess.get_file_as_string(_config_path()))
	if parsed is Dictionary and parsed.get("enabled") is Array:
		for entry in parsed["enabled"]:
			var mod_id: String = str(entry)
			if not mod_id in _persisted_enabled:
				_persisted_enabled.append(mod_id)
		return
	# First run (or a damaged file): seed with the bundled mods that ask to
	# be on by default, earliest priority first.
	var seeded: Array = []
	for mod_id in _records:
		var record: Dictionary = _records[mod_id]
		var manifest: ModManifest = record["manifest"]
		if str(record["source"]) == SOURCE_BUNDLED and manifest.enabled_by_default and manifest.is_valid():
			seeded.append({"id": mod_id, "priority": manifest.load_priority})
	seeded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		return str(a["id"]) < str(b["id"]))
	for entry in seeded:
		_persisted_enabled.append(str(entry["id"]))


func _write_persisted_order() -> void:
	DirAccess.make_dir_recursive_absolute(user_root)
	var file := FileAccess.open(_config_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(
			{"version": 1, "enabled": _persisted_enabled}, "\t") + "\n")


## The player's ordered enabled list - the order mods attempt to load in.
func get_enabled_order() -> Array[String]:
	return _persisted_enabled.duplicate()


## The order mods actually loaded in this session.
func get_load_order() -> Array[String]:
	return _loaded_order.duplicate()


func is_mod_enabled(mod_id: String) -> bool:
	return mod_id in _persisted_enabled


func is_mod_loaded(mod_id: String) -> bool:
	return _records.has(mod_id) and bool(_records[mod_id].get("loaded", false))


func get_mod_version(mod_id: String) -> String:
	if _records.has(mod_id):
		return (_records[mod_id]["manifest"] as ModManifest).version
	return ""


func set_mod_enabled(mod_id: String, enabled: bool) -> void:
	if enabled:
		if not mod_id in _persisted_enabled:
			_persisted_enabled.append(mod_id)
	else:
		_persisted_enabled.erase(mod_id)
	if _records.has(mod_id):
		_records[mod_id]["enabled"] = enabled
	_write_persisted_order()
	_refresh_needs_reload()


## Move a mod one step in the ordered list (+1 loads it later, -1 earlier).
func move_mod(mod_id: String, steps: int) -> void:
	var index: int = _persisted_enabled.find(mod_id)
	if index < 0:
		return
	var target: int = clampi(index + steps, 0, _persisted_enabled.size() - 1)
	if target == index:
		return
	_persisted_enabled.remove_at(index)
	_persisted_enabled.insert(target, mod_id)
	_write_persisted_order()
	_refresh_needs_reload()


func _refresh_needs_reload() -> void:
	needs_reload = _persisted_enabled != _loaded_order


# =============================================================================
# RESOLUTION (pure: the same inputs always decide the same order)
# =============================================================================

## Decide the final load order for `enabled` (the player's ordered list)
## against `manifests` (id -> ModManifest). Returns
## {order: [ids], errors: {id: [messages]}, auto_enabled: [ids]}.
## Hard dependencies pull their target in just before the mod that needs
## them; mods that cannot load - bad API, missing dependency, a conflict, a
## dependency cycle - fall out with an explanation each.
static func resolve_load_order(enabled: Array, manifests: Dictionary, game_version: String) -> Dictionary:
	var errors: Dictionary = {}
	var excluded: Dictionary = {}
	var scores: Dictionary = {}  # id -> float: lower loads earlier.
	var candidates: Array[String] = []
	var auto_enabled: Array[String] = []

	var note_error := func(mod_id: String, message: String) -> void:
		var list: Array = errors.get(mod_id, [])
		list.append(message)
		errors[mod_id] = list
		excluded[mod_id] = true

	for i in range(enabled.size()):
		scores[str(enabled[i])] = float(i * 10)
	var queue: Array[String] = []
	for entry in enabled:
		queue.append(str(entry))
	# Walk the queue, pulling hard dependencies in as they are met.
	while not queue.is_empty():
		var mod_id: String = queue.pop_front()
		if mod_id in candidates or excluded.has(mod_id):
			continue
		var manifest: ModManifest = manifests.get(mod_id, null)
		if manifest == null:
			note_error.call(mod_id, "Enabled, but no such mod is installed.")
			continue
		if not manifest.is_valid():
			note_error.call(mod_id, "mod.json has errors: %s" % "; ".join(manifest.errors))
			continue
		if manifest.api_version != ModManifest.CURRENT_API_VERSION:
			note_error.call(mod_id, "Built for Mod API %d; this game speaks Mod API %d." % [manifest.api_version, ModManifest.CURRENT_API_VERSION])
			continue
		if not ModManifest.version_in_range(game_version, manifest.min_game_version, manifest.max_game_version):
			note_error.call(mod_id, "Needs game version %s%s; this is %s." % [
				manifest.min_game_version,
				(" to " + manifest.max_game_version) if not manifest.max_game_version.is_empty() else "+",
				game_version])
			continue
		candidates.append(mod_id)
		for dependency in manifest.dependencies:
			var dependency_id: String = str(dependency.get("id", ""))
			if bool(dependency.get("optional", false)):
				continue
			if not manifests.has(dependency_id):
				continue  # Reported by the dependency pass below.
			if dependency_id in candidates or dependency_id in queue:
				continue
			scores[dependency_id] = minf(float(scores.get(dependency_id, 1e9)),
				float(scores.get(mod_id, 0.0)) - 1.0)
			auto_enabled.append(dependency_id)
			queue.push_front(dependency_id)

	# Dependency pass: a hard dependency that is missing, excluded or the
	# wrong version takes its dependent out (repeatedly, as exclusions
	# cascade). Optional dependencies only order, never exclude.
	var changed := true
	while changed:
		changed = false
		for mod_id in candidates:
			if excluded.has(mod_id):
				continue
			var manifest: ModManifest = manifests[mod_id]
			for dependency in manifest.dependencies:
				if bool(dependency.get("optional", false)):
					continue
				var dependency_id: String = str(dependency.get("id", ""))
				if not manifests.has(dependency_id):
					note_error.call(mod_id, "Needs the mod '%s', which is not installed." % dependency_id)
					changed = true
					break
				if excluded.has(dependency_id) or not dependency_id in candidates:
					note_error.call(mod_id, "Needs the mod '%s', which could not load." % dependency_id)
					changed = true
					break
				var dependency_manifest: ModManifest = manifests[dependency_id]
				if not ModManifest.version_in_range(dependency_manifest.version,
						str(dependency.get("min_version", "")), str(dependency.get("max_version", ""))):
					note_error.call(mod_id, "Needs '%s' version %s+, found %s." % [dependency_id, str(dependency.get("min_version", "")), dependency_manifest.version])
					changed = true
					break

	# Conflicts: walking the player's order, the first of a conflicting pair
	# stays; the later one is the one they can move or switch off.
	var kept: Array[String] = []
	var ordered := candidates.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool:
		return float(scores.get(a, 0.0)) < float(scores.get(b, 0.0)))
	for mod_id in ordered:
		if excluded.has(mod_id):
			continue
		var manifest: ModManifest = manifests[mod_id]
		var clashes_with: String = ""
		for other in kept:
			if other in manifest.conflicts or mod_id in (manifests[other] as ModManifest).conflicts:
				clashes_with = other
				break
		if clashes_with.is_empty():
			kept.append(mod_id)
		else:
			note_error.call(mod_id, "Conflicts with '%s', which loads earlier. Disable one of them." % clashes_with)

	# Topological order over dependency/order edges, stable by the player's
	# list: among the mods that could go next, the earliest-listed does.
	var edges: Dictionary = {}  # id -> [ids that must load before it]
	for mod_id in kept:
		var manifest: ModManifest = manifests[mod_id]
		var before: Array = []
		for dependency in manifest.dependencies:
			var dependency_id: String = str(dependency.get("id", ""))
			if dependency_id in kept:
				before.append(dependency_id)
		for other in manifest.load_after:
			if other in kept and not other in before:
				before.append(other)
		edges[mod_id] = before
	for mod_id in kept:
		for other in (manifests[mod_id] as ModManifest).load_before:
			if other in kept and not mod_id in edges[other]:
				edges[other].append(mod_id)
	var order: Array[String] = []
	var remaining := kept.duplicate()
	while not remaining.is_empty():
		var unblocked: Array[String] = []
		for mod_id in remaining:
			var blocked := false
			for needed in edges.get(mod_id, []):
				if needed in remaining:
					blocked = true
					break
			if not blocked:
				unblocked.append(mod_id)
		if unblocked.is_empty():
			for mod_id in remaining:
				note_error.call(mod_id, "Its load-order requirements form a cycle.")
			break
		unblocked.sort_custom(func(a: String, b: String) -> bool:
			return float(scores.get(a, 0.0)) < float(scores.get(b, 0.0)))
		var next: String = unblocked[0]
		order.append(next)
		remaining.erase(next)
	# A conflict or cycle can exclude a dependency after the first dependency
	# pass. Cascade those exclusions too, rather than loading orphan add-ons.
	var pruned := true
	while pruned:
		pruned = false
		for candidate_id in order.duplicate():
			for requirement in (manifests[candidate_id] as ModManifest).dependencies:
				if not bool(requirement.get("optional", false)) and not str(requirement["id"]) in order:
					note_error.call(candidate_id, "Required mod '%s' was excluded by conflict or load-order rules." % requirement["id"])
					order.erase(candidate_id)
					pruned = true
					break
	return {"order": order, "errors": errors, "auto_enabled": auto_enabled}


# =============================================================================
# LOADING
# =============================================================================

func load_enabled_mods() -> void:
	var manifests: Dictionary = {}
	for mod_id in _records:
		manifests[mod_id] = _records[mod_id]["manifest"]
	var game_version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var resolution: Dictionary = resolve_load_order(_persisted_enabled, manifests, game_version)
	_resolution_errors = resolution.get("errors", {})
	var order: Array = resolution.get("order", [])
	for mod_id in resolution.get("auto_enabled", []):
		if _records.has(mod_id):
			_records[mod_id]["auto_enabled"] = true
	for mod_id in _resolution_errors:
		if _records.has(mod_id):
			_records[mod_id]["state"] = "error"
			for message in _resolution_errors[mod_id]:
				_records[mod_id]["errors"].append(str(message))
			EventBus.mod_failed.emit(mod_id, "; ".join(_resolution_errors[mod_id]))

	var any_script: bool = false
	for mod_id in order:
		if (_records[mod_id]["manifest"] as ModManifest).wants_script():
			any_script = true
			break
	var marker: String = user_root.path_join(CRASH_MARKER)
	safe_mode_triggered = any_script and not _owns_crash_marker and FileAccess.file_exists(marker)
	if safe_mode_triggered:
		DirAccess.remove_absolute(marker)
		push_warning("ModManager: a previous session stopped while loading script mods; loading data only this time (safe mode).")
	elif any_script:
		DirAccess.make_dir_recursive_absolute(user_root)
		var marker_file := FileAccess.open(marker, FileAccess.WRITE)
		if marker_file != null:
			marker_file.store_string("loading")
			_owns_crash_marker = true

	for mod_id in order:
		var missing_runtime_dependency := false
		for requirement in (_records[mod_id]["manifest"] as ModManifest).dependencies:
			if not bool(requirement.get("optional", false)) and not is_mod_loaded(str(requirement["id"])):
				_fail(_records[mod_id], "Required mod '%s' failed to load." % requirement["id"])
				missing_runtime_dependency = true
				break
		if not missing_runtime_dependency:
			_load_one(mod_id, safe_mode_triggered)
	_loaded_order.clear()
	for mod_id in order:
		if bool(_records[mod_id].get("loaded", false)):
			_loaded_order.append(str(mod_id))
	if content_registry() != null:
		content_registry().refresh_live_libraries()
	needs_reload = false
	EventBus.mods_loaded.emit(_loaded_order.duplicate())
	print("ModManager: loaded %d mod(s)%s: %s" % [_loaded_order.size(),
		" (safe mode: no scripts)" if safe_mode_triggered else "",
		", ".join(_loaded_order) if not _loaded_order.is_empty() else "none"])
	if any_script and not safe_mode_triggered and is_inside_tree():
		_clear_marker_when_alive(marker)


func _exit_tree() -> void:
	# Orderly exits (tools, tests, quit during startup) are not crashes.
	if _owns_crash_marker:
		DirAccess.remove_absolute(user_root.path_join(CRASH_MARKER))
		_owns_crash_marker = false


func _clear_marker_when_alive(marker: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if _owns_crash_marker and FileAccess.file_exists(marker):
		DirAccess.remove_absolute(marker)
	_owns_crash_marker = false


func _load_one(mod_id: String, data_only: bool) -> bool:
	var record: Dictionary = _records[mod_id]
	var manifest: ModManifest = record["manifest"]
	var root: String = str(record["root"])
	if root.is_empty() and not str(record["zip_path"]).is_empty():
		var installed: Dictionary = ModPackage.install_zip(
			str(record["zip_path"]), user_root.path_join("installed"))
		if not bool(installed["ok"]):
			_fail(record, "Installing the zip failed: %s" % "; ".join(installed["errors"]))
			return false
		root = str(installed["directory"])
		record["root"] = root
		record["installed"] = true
	for pack in manifest.resource_packs:
		var pack_path: String = root.path_join(pack)
		var filesystem_path: String = ProjectSettings.globalize_path(pack_path) \
			if pack_path.begins_with("user://") else pack_path
		if not ProjectSettings.load_resource_pack(filesystem_path, true):
			_fail(record, "Resource pack '%s' could not be mounted." % pack)
			return false
	if content_registry() != null and not manifest.content.is_empty():
		content_registry().apply_mod_content(mod_id, root, manifest.content)
	if manifest.wants_script() and not data_only:
		if not _load_script(record, root, manifest):
			return false
	record["loaded"] = true
	record["state"] = "loaded"
	EventBus.mod_loaded.emit(mod_id)
	return true


func _load_script(record: Dictionary, root: String, manifest: ModManifest) -> bool:
	var entry_path: String = root.path_join(manifest.entry_point)
	if not FileAccess.file_exists(entry_path) and not ResourceLoader.exists(entry_path):
		_fail(record, "Entry point '%s' does not exist." % manifest.entry_point)
		return false
	var script: Resource = load(entry_path)
	if script == null or not (script is GDScript):
		_fail(record, "Entry point '%s' could not be loaded as a script." % manifest.entry_point)
		return false
	var instance: Variant = (script as GDScript).new()
	if not (instance is GolfTycoonMod):
		_fail(record, "Entry point must extend GolfTycoonMod (see docs/modding/mod-api.md).")
		if instance is Object:
			(instance as Object).free()
		return false
	var mod_node: GolfTycoonMod = instance
	mod_node.name = "Mod_" + manifest.id.replace(".", "_").replace("-", "_")
	var mod_api := ModAPI.new(manifest.id, self, root)
	mod_node.mod_id = manifest.id
	mod_node.api = mod_api
	_loaded_nodes[manifest.id] = mod_node
	add_child(mod_node)
	mod_node._mod_load(mod_api)
	return true


func _fail(record: Dictionary, message: String) -> void:
	record["state"] = "error"
	record["loaded"] = false
	record["errors"].append(message)
	push_warning("ModManager [%s]: %s" % [record["id"], message])
	EventBus.mod_failed.emit(str(record["id"]), message)


## Unload everything, rediscover, and load the player's list again. The
## main scene still holds this session's weather/wind instances and cached
## catalogs, so callers follow this with a scene reload (see
## apply_and_reload_scene).
func reload_mods() -> void:
	unload_all()
	discover()
	if not mods_disabled_by_flag:
		load_enabled_mods()


func apply_and_reload_scene() -> void:
	reload_mods()
	if is_inside_tree() and get_tree().current_scene != null:
		get_tree().reload_current_scene()


func unload_all() -> void:
	_main_scene = null
	_texture_cache.clear()
	var order := _loaded_order.duplicate()
	order.reverse()
	for mod_id in order:
		var mod_node: GolfTycoonMod = _loaded_nodes.get(mod_id, null)
		if mod_node != null:
			mod_node._mod_unload()
			remove_child(mod_node)
			mod_node.free()
	_loaded_nodes.clear()
	_hooks.clear()
	_hud_widgets.clear()
	_main_scene_callbacks.clear()
	_weather_factory = Callable()
	_weather_factory_owner = ""
	_wind_factory = Callable()
	_wind_factory_owner = ""
	_season_provider_owner = ""
	_provider_notes.clear()
	clear_feature_options()
	SeasonSystem.set_provider(null)
	_loaded_order.clear()
	for mod_id in _records:
		_records[mod_id]["loaded"] = false
		if str(_records[mod_id]["state"]) == "loaded":
			_records[mod_id]["state"] = "discovered"
	if content_registry() != null:
		content_registry().reset_mod_content()


# =============================================================================
# PROVIDERS AND HOOKS (what the Mod API registers into)
# =============================================================================

func register_weather_factory(mod_id: String, factory: Callable) -> void:
	if not _weather_factory_owner.is_empty() and _weather_factory_owner != mod_id:
		_provider_notes.append("Weather: %s replaces %s (later in the load order wins)." % [mod_id, _weather_factory_owner])
	_weather_factory = factory
	_weather_factory_owner = mod_id


func register_wind_factory(mod_id: String, factory: Callable) -> void:
	if not _wind_factory_owner.is_empty() and _wind_factory_owner != mod_id:
		_provider_notes.append("Wind: %s replaces %s (later in the load order wins)." % [mod_id, _wind_factory_owner])
	_wind_factory = factory
	_wind_factory_owner = mod_id


func register_season_provider(mod_id: String, provider: SeasonProvider) -> void:
	if not _season_provider_owner.is_empty() and _season_provider_owner != mod_id:
		_provider_notes.append("Seasons: %s replaces %s (later in the load order wins)." % [mod_id, _season_provider_owner])
	_season_provider_owner = mod_id
	SeasonSystem.set_provider(provider)


func has_weather_provider() -> bool:
	return _weather_factory.is_valid()


func has_wind_provider() -> bool:
	return _wind_factory.is_valid()


func has_season_provider() -> bool:
	return not _season_provider_owner.is_empty()


## Who currently provides each environment system ("core (neutral)" when no
## mod does). For the Mods screen and bug reports.
func provider_owners() -> Dictionary:
	return {
		"weather": _weather_factory_owner if has_weather_provider() else "core (neutral)",
		"wind": _wind_factory_owner if has_wind_provider() else "core (neutral)",
		"seasons": _season_provider_owner if has_season_provider() else "core (neutral)",
	}


func get_provider_notes() -> Array[String]:
	return _provider_notes.duplicate()


## Feature toggles for the Start New Game screen. Mods add them through
## ModAPI.register_feature_option; they are kept here (in load order, later
## wins per id) so the screen can decide whether its Features section has
## anything to show. With none registered the section is hidden entirely.
func register_feature_option(mod_id: String, option: Dictionary) -> void:
	var id: String = str(option.get("id", "")).strip_edges()
	if id.is_empty():
		push_warning("ModManager [%s]: a Start New Game feature option needs an id; skipped." % mod_id)
		return
	for i in range(_start_features.size()):
		if str(_start_features[i].get("id", "")) == id:
			_start_features.remove_at(i)
			break
	var entry := option.duplicate(true)
	entry["id"] = id
	entry["mod_id"] = mod_id
	_start_features.append(entry)


## Every registered feature option, in load order.
func get_feature_options() -> Array:
	return _start_features.duplicate(true)


func has_feature_options() -> bool:
	return not _start_features.is_empty()


## Drop every registered option - the mod set is being unloaded (also how a
## test reaches the "no mod adds anything" state).
func clear_feature_options() -> void:
	_start_features.clear()


## The weather the game should run: the registered mod's system, or the
## neutral base. The main scene owns the instance it is handed.
func create_weather_system() -> WeatherSystem:
	if _weather_factory.is_valid():
		var made: Variant = _weather_factory.call()
		if made is WeatherSystem:
			return made
		push_warning("ModManager: %s's weather factory did not return a WeatherSystem; using the neutral base." % _weather_factory_owner)
	return WeatherSystem.new()


func create_wind_system() -> WindSystem:
	if _wind_factory.is_valid():
		var made: Variant = _wind_factory.call()
		if made is WindSystem:
			return made
		push_warning("ModManager: %s's wind factory did not return a WindSystem; using the neutral base." % _wind_factory_owner)
	return WindSystem.new()


func add_hook(mod_id: String, hook_name: String, callable: Callable) -> void:
	var chain: Array = _hooks.get(hook_name, [])
	chain.append({"mod_id": mod_id, "callable": callable})
	_hooks[hook_name] = chain


## Pass a value through every hook registered for `hook_name`, in load
## order. Game systems call this at their tuning points.
func apply_hook(hook_name: String, value: float, context: Dictionary = {}) -> float:
	var current: float = value
	for entry in _hooks.get(hook_name, []):
		var callable: Callable = entry["callable"]
		if callable.is_valid():
			var result: Variant = callable.call(current, context)
			if result is float or result is int:
				current = float(result)
	return current


func hook_names() -> Array:
	return _hooks.keys()


func register_hud_widget(mod_id: String, factory: Callable) -> void:
	_hud_widgets.append({"mod_id": mod_id, "factory": factory})


## Widget factories in load order; the main scene calls each while building
## its HUD.
func get_hud_widgets() -> Array:
	return _hud_widgets.duplicate()


func call_on_main_scene_ready(mod_id: String, callable: Callable) -> void:
	if _main_scene != null and is_instance_valid(_main_scene):
		callable.call(_main_scene)
	else:
		_main_scene_callbacks.append({"mod_id": mod_id, "callable": callable})


func _on_main_scene_ready(main_node: Node) -> void:
	_main_scene = main_node
	var callbacks := _main_scene_callbacks.duplicate()
	_main_scene_callbacks.clear()
	for entry in callbacks:
		var callable: Callable = entry["callable"]
		if callable.is_valid():
			callable.call(main_node)
	# A reloaded scene gets the registrations again: mods that care check
	# for their node first (the bundled examples show how), and EventBus
	# carries the signal for mods that connect per-scene themselves.


func _on_new_game_started() -> void:
	for mod_id in _loaded_order:
		var mod_node: GolfTycoonMod = _loaded_nodes.get(mod_id, null)
		if mod_node != null:
			mod_node._mod_new_game()


# =============================================================================
# SAVE DATA, CONFIG, TEXTURES
# =============================================================================

## Every loaded script mod's save slice, by mod id.
func collect_save_data() -> Dictionary:
	var data: Dictionary = {}
	for mod_id in _loaded_order:
		var mod_node: GolfTycoonMod = _loaded_nodes.get(mod_id, null)
		if mod_node == null:
			continue
		var slice: Dictionary = mod_node._mod_save()
		if not slice.is_empty():
			data[mod_id] = slice
	return data


## Hand each mod its slice of a loaded save ({} when the save has none).
## Returns the ids the save used that are not loaded now, for the warning.
func apply_save_data(data: Dictionary) -> Array[String]:
	var slices: Variant = data.get("data", {})
	var missing: Array[String] = []
	for entry in data.get("load_order", []):
		var saved_id: String = str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if not saved_id.is_empty() and not is_mod_loaded(saved_id):
			missing.append(saved_id)
	for mod_id in _loaded_order:
		var mod_node: GolfTycoonMod = _loaded_nodes.get(mod_id, null)
		if mod_node != null:
			var slice: Variant = slices.get(mod_id, {}) if slices is Dictionary else {}
			mod_node._mod_restore(slice if slice is Dictionary else {})
	return missing


## [{id, version}] for everything loaded - stamped into save files.
func get_loaded_mod_versions() -> Array:
	var versions: Array = []
	for mod_id in _loaded_order:
		versions.append({"id": mod_id, "version": get_mod_version(mod_id)})
	return versions


func _config_dir() -> String:
	return user_root.path_join("config")


func _mod_config(mod_id: String) -> Dictionary:
	if _mod_configs.has(mod_id):
		return _mod_configs[mod_id]
	var values: Dictionary = {}
	if _records.has(mod_id):
		values = (_records[mod_id]["manifest"] as ModManifest).default_config()
	var file_path: String = _config_dir().path_join(mod_id + ".json")
	if FileAccess.file_exists(file_path):
		var parsed: Variant = ModManifest.parse_json_quietly(FileAccess.get_file_as_string(file_path))
		if parsed is Dictionary:
			for key in parsed:
				values[key] = parsed[key]
	_mod_configs[mod_id] = values
	return values


func get_mod_config_value(mod_id: String, key: String, fallback: Variant = null) -> Variant:
	return _mod_config(mod_id).get(key, fallback)


func set_mod_config_value(mod_id: String, key: String, value: Variant) -> void:
	var values: Dictionary = _mod_config(mod_id)
	values[key] = value
	_mod_configs[mod_id] = values
	DirAccess.make_dir_recursive_absolute(_config_dir())
	var file := FileAccess.open(_config_dir().path_join(mod_id + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(values, "\t") + "\n")


## A texture from inside a mod, decoded from the file bytes so no import
## step is ever needed, and cached by mod + path.
func load_mod_texture(mod_id: String, full_path: String) -> Texture2D:
	var cache_key: String = mod_id + "|" + full_path
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var texture_value: Texture2D = null
	if ResourceLoader.exists(full_path):
		var loaded: Resource = load(full_path)
		if loaded is Texture2D:
			texture_value = loaded
	if texture_value == null and FileAccess.file_exists(full_path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(full_path)
		var image := Image.new()
		var extension: String = full_path.get_extension().to_lower()
		var ok: bool = false
		match extension:
			"png":
				ok = image.load_png_from_buffer(bytes) == OK
			"jpg", "jpeg":
				ok = image.load_jpg_from_buffer(bytes) == OK
			"webp":
				ok = image.load_webp_from_buffer(bytes) == OK
			"bmp":
				ok = image.load_bmp_from_buffer(bytes) == OK
		if ok:
			texture_value = ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture_value
	return texture_value


# =============================================================================
# INSTALLING, REMOVING AND STEAM
# =============================================================================

## Every id the library currently knows about, sorted - what the Mods
## screen's Create New Mod form checks a typed id against.
func get_installed_mod_ids() -> Array[String]:
	var ids: Array[String] = []
	for mod_id in _records:
		ids.append(str(mod_id))
	ids.sort()
	return ids


## Scaffold a new mod folder in the player's library, then rediscover so it
## shows in the list. Creating is not enabling: like an installed zip, the
## new mod arrives switched off and does nothing until the player ticks it
## and applies. Result: {ok, mod_id, directory, files, errors} - see
## ModScaffold.create().
func create_mod(fields: Dictionary) -> Dictionary:
	var result: Dictionary = ModScaffold.create(user_root, fields, get_installed_mod_ids())
	if bool(result.get("ok", false)):
		discover()
	return result


## Install a mod zip the player picked, into user://mods/installed/, then
## rediscover so it shows in the list (still disabled: installing is not
## enabling).
func install_zip(zip_path: String) -> Dictionary:
	var result: Dictionary = ModPackage.install_zip(zip_path, user_root.path_join("installed"))
	if bool(result.get("ok", false)):
		discover()
	return result


## Delete a mod the player installed (folder or installed zip). Bundled and
## Workshop mods are refused: disable those instead (Workshop items are
## Steam's to remove, via unsubscribe).
func uninstall_mod(mod_id: String) -> Dictionary:
	if not _records.has(mod_id):
		return {"ok": false, "errors": ["No such mod."]}
	var record: Dictionary = _records[mod_id]
	if str(record["source"]) == SOURCE_BUNDLED:
		return {"ok": false, "errors": ["Bundled mods ship with the game; disable it instead."]}
	if str(record["source"]) == SOURCE_WORKSHOP:
		return {"ok": false, "errors": ["Workshop mods are removed by unsubscribing in Steam."]}
	if is_mod_loaded(mod_id):
		return {"ok": false, "errors": ["Disable the mod and apply the change first."]}
	set_mod_enabled(mod_id, false)
	if not str(record["zip_path"]).is_empty() and FileAccess.file_exists(str(record["zip_path"])):
		DirAccess.remove_absolute(str(record["zip_path"]))
	if not str(record["root"]).is_empty() and DirAccess.dir_exists_absolute(str(record["root"])):
		ModPackage.remove_directory_recursive(str(record["root"]))
	discover()
	return {"ok": true, "errors": []}


## The folder players drop mods into, created on demand.
func mods_folder_path() -> String:
	DirAccess.make_dir_recursive_absolute(user_root)
	return ProjectSettings.globalize_path(user_root)


func steam_available() -> bool:
	return _steam != null and _steam.is_available()


func steam_provider() -> SteamWorkshopProvider:
	return _steam


## Open the game's Steam Workshop in the overlay/browser (GodotSteam only).
func open_workshop() -> bool:
	return _steam != null and _steam.open_workshop_page()


## Upload (or update) one installed/bundled folder mod as a Workshop item.
## Returns {ok, message, published_file_id} - see SteamWorkshopProvider.
func upload_to_workshop(mod_id: String, change_note: String = "") -> Dictionary:
	if _steam == null or not _steam.is_available():
		return {"ok": false, "message": "Steam is not available in this build (GodotSteam not present, or Steam is not running)."}
	if not _records.has(mod_id):
		return {"ok": false, "message": "No such mod."}
	var record: Dictionary = _records[mod_id]
	var root: String = str(record["root"])
	if root.is_empty():
		return {"ok": false, "message": "Install the mod from its zip first, then upload the installed folder."}
	return await _steam.upload_mod(record["manifest"], ProjectSettings.globalize_path(root)
		if root.begins_with("user://") or root.begins_with("res://") else root, change_note)


# =============================================================================
# WHAT THE MODS SCREEN READS
# =============================================================================

## A display-ready snapshot of every discovered mod. Enabled mods come
## first, in the player's order; the rest follow alphabetically.
func get_all_mod_infos() -> Array:
	var infos: Array = []
	for mod_id in _persisted_enabled:
		if _records.has(mod_id):
			infos.append(get_mod_info(mod_id))
	var rest: Array[String] = []
	for mod_id in _records:
		if not mod_id in _persisted_enabled:
			rest.append(mod_id)
	rest.sort()
	for mod_id in rest:
		infos.append(get_mod_info(mod_id))
	return infos


func get_mod_info(mod_id: String) -> Dictionary:
	var record: Dictionary = _records.get(mod_id, {})
	if record.is_empty():
		return {}
	var manifest: ModManifest = record["manifest"]
	var dependencies: Array[String] = []
	for dependency in manifest.dependencies:
		var line: String = str(dependency.get("id", ""))
		if not str(dependency.get("min_version", "")).is_empty():
			line += " >= " + str(dependency.get("min_version", ""))
		if bool(dependency.get("optional", false)):
			line += " (optional)"
		dependencies.append(line)
	return {
		"id": mod_id, "name": manifest.name, "version": manifest.version,
		"author": manifest.author, "description": manifest.description,
		"homepage": manifest.homepage, "types": manifest.types.duplicate(),
		"source": str(record["source"]),
		"source_label": _source_label(str(record["source"]), int(record["workshop_id"])),
		"root": str(record["root"]), "enabled": is_mod_enabled(mod_id),
		"loaded": bool(record.get("loaded", false)),
		"auto_enabled": bool(record.get("auto_enabled", false)),
		"state": str(record.get("state", "discovered")),
		"errors": (record.get("errors", []) as Array).duplicate(),
		"warnings": (record.get("warnings", []) as Array).duplicate(),
		"dependencies": dependencies,
		"conflicts_declared": manifest.conflicts.duplicate(),
		"has_script": manifest.wants_script(),
		"workshop_id": maxi(int(record["workshop_id"]), manifest.workshop_file_id()),
		"can_uninstall": str(record["source"]) in [SOURCE_USER, SOURCE_ZIP],
		"order_index": _persisted_enabled.find(mod_id),
	}


func _source_label(source: String, workshop_id: int) -> String:
	match source:
		SOURCE_BUNDLED:
			return "Bundled with the game"
		SOURCE_WORKSHOP:
			return "Steam Workshop" + ((" item %d" % workshop_id) if workshop_id > 0 else "")
		SOURCE_ZIP:
			return "Installed from a zip"
		_:
			return "Mods folder"


func get_discovery_warnings() -> Array[String]:
	return _discovery_warnings.duplicate()
