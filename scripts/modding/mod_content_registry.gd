extends Node
## ContentRegistry (ModContentRegistry) - The one place game data is read from.
##
## The base game ships its buildings, decorations and friends as JSON under
## `res://data/`. Mods ship the same shapes in their own folders. This
## registry loads the base data first, then applies every enabled mod's data
## in load order - additions, deep-merged overrides, removals - and every
## game system reads the merged result from here. That is what makes a data
## mod possible at all, and what makes load order meaningful: when two mods
## change the same building, the later one wins, and the registry remembers
## who wrote what (provenance) so the Mods screen can say so.
##
## Content ids are namespaced. A new building a mod calls "marquee_tent"
## enters the game as "<mod id>:marquee_tent" - the form saves store - so two
## mods can never collide by accident, and a save can always tell whose thing
## is missing when a mod is gone. Patching something that already exists (a
## shipped building, or an earlier mod's) keeps its existing id.
##
## Some kinds of data live in static classes with readers all over the game
## (TerrainTypes, CourseTheme, WorldLocations, ...). For those the registry
## keeps the merged table and pushes it into the class (`set_mod_overrides`
## and friends), and the class folds it over its built-in values at its one
## read door. Autoloaded as `ContentRegistry`.

signal content_changed

## The provenance name of the shipped game data.
const CORE_SOURCE: String = "core"

const BUILDINGS_PATH: String = "res://data/buildings.json"
const DECORATIONS_PATH: String = "res://data/decorations.json"
const TERRAIN_TYPES_PATH: String = "res://data/terrain_types.json"

var _buildings: Dictionary = {}
var _decorations: Dictionary = {}
## content kind -> id -> mod id that last wrote it.
var _provenance: Dictionary = {"buildings": {}, "decorations": {}}
## Conflicts worth showing a player: two mods writing the same entry.
var _conflicts: Array[String] = []
var _warnings: Array[String] = []

var _terrain_overrides: Dictionary = {}  # terrain id (int) -> property patch
var _theme_overrides: Dictionary = {}  # theme save name -> patch
var _tier_overrides: Dictionary = {}  # tournament tier save name -> patch
var _locations: Array = []  # normalised WorldLocations entries from mods
var _visitors: Dictionary = {}  # location id -> [golfer cards]
var _name_extras: Dictionary = {}
var _skin_roots: Array[String] = []
var _tuning: Dictionary = {}  # dotted key -> float
var _tuning_provenance: Dictionary = {}
var _terrain_name_to_id: Dictionary = {}


func _init() -> void:
	load_base_content()


# =============================================================================
# BASE DATA
# =============================================================================

## (Re)load the shipped game's data and drop everything mods added. The mod
## manager calls this before re-applying the enabled mods in load order.
func load_base_content() -> void:
	_buildings = _read_catalog(BUILDINGS_PATH, "buildings")
	_decorations = _read_catalog(DECORATIONS_PATH, "decorations")
	_provenance = {"buildings": {}, "decorations": {}}
	for entry_id in _buildings:
		_provenance["buildings"][entry_id] = CORE_SOURCE
	for entry_id in _decorations:
		_provenance["decorations"][entry_id] = CORE_SOURCE
	_terrain_name_to_id = _read_terrain_name_map()
	reset_mod_content()


## Drop every mod contribution, leaving the shipped data exactly as loaded.
func reset_mod_content() -> void:
	_buildings = _read_catalog(BUILDINGS_PATH, "buildings")
	_decorations = _read_catalog(DECORATIONS_PATH, "decorations")
	_provenance = {"buildings": {}, "decorations": {}}
	for entry_id in _buildings:
		_provenance["buildings"][entry_id] = CORE_SOURCE
	for entry_id in _decorations:
		_provenance["decorations"][entry_id] = CORE_SOURCE
	_conflicts.clear()
	_warnings.clear()
	_terrain_overrides.clear()
	_theme_overrides.clear()
	_tier_overrides.clear()
	_locations.clear()
	_visitors.clear()
	_name_extras.clear()
	_skin_roots.clear()
	_tuning.clear()
	_tuning_provenance.clear()
	SeasonalEvents.clear_registered_events()
	BuildingSprites.clear_mod_sprites()
	_push_statics()
	content_changed.emit()


func _read_catalog(path: String, key: String) -> Dictionary:
	var parsed: Variant = _read_json_file(path)
	if parsed is Dictionary and parsed.get(key) is Dictionary:
		return parsed[key].duplicate(true)
	push_error("ContentRegistry: %s does not hold a '%s' catalog." % [path, key])
	return {}


func _read_terrain_name_map() -> Dictionary:
	var names: Dictionary = {}
	var parsed: Variant = _read_json_file(TERRAIN_TYPES_PATH)
	if parsed is Dictionary and parsed.get("terrain_types") is Dictionary:
		for key in parsed["terrain_types"]:
			names[str(key).to_lower()] = int(parsed["terrain_types"][key].get("id", -1))
	for type_name in TerrainTypes.Type.keys():
		names[str(type_name).to_lower()] = int(TerrainTypes.Type[type_name])
	return names


static func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return ModManifest.parse_json_quietly(FileAccess.get_file_as_string(path))


# =============================================================================
# READING THE MERGED RESULT (what game systems call)
# =============================================================================

func get_buildings() -> Dictionary:
	return _buildings.duplicate(true)


func get_building(building_id: String) -> Dictionary:
	var found: Variant = _buildings.get(building_id, {})
	return found.duplicate(true) if found is Dictionary else {}


func has_building(building_id: String) -> bool:
	return _buildings.has(building_id)


func get_decorations() -> Dictionary:
	return _decorations.duplicate(true)


func get_decoration(decoration_id: String) -> Dictionary:
	var found: Variant = _decorations.get(decoration_id, {})
	return found.duplicate(true) if found is Dictionary else {}


func has_decoration(decoration_id: String) -> bool:
	return _decorations.has(decoration_id)


## A tuning value a balance mod has set, or `default_value`. See
## docs/modding/mod-api.md for the keys the game reads.
func get_tuning(key: String, default_value: float) -> float:
	return float(_tuning.get(key, default_value))


func has_tuning(key: String) -> bool:
	return _tuning.has(key)


## Which mod last wrote a piece of content ("core" for the shipped game).
func source_of(kind: String, entry_id: String) -> String:
	return str(_provenance.get(kind, {}).get(entry_id, ""))


func get_conflicts() -> Array[String]:
	return _conflicts.duplicate()


func get_warnings() -> Array[String]:
	return _warnings.duplicate()


## How much content each mod contributed, for the Mods screen:
## {mod_id: {"buildings": n, "decorations": n, "tuning": n, ...}}.
func get_content_summary() -> Dictionary:
	var summary: Dictionary = {}
	for kind in ["buildings", "decorations"]:
		for entry_id in _provenance[kind]:
			var source_mod: String = _provenance[kind][entry_id]
			if source_mod == CORE_SOURCE:
				continue
			if not summary.has(source_mod):
				summary[source_mod] = {}
			summary[source_mod][kind] = int(summary[source_mod].get(kind, 0)) + 1
	for key in _tuning_provenance:
		var source_mod: String = _tuning_provenance[key]
		if not summary.has(source_mod):
			summary[source_mod] = {}
		summary[source_mod]["tuning"] = int(summary[source_mod].get("tuning", 0)) + 1
	return summary


## The full, in-game id a mod's new entry gets: its own id with the mod's
## namespace in front. Entries that already exist keep the id they have -
## that is a patch, not a new thing.
func resolve_new_id(mod_id: String, raw_id: String) -> String:
	if raw_id.contains(":"):
		return raw_id
	return "%s:%s" % [mod_id, raw_id]


# =============================================================================
# APPLYING ONE MOD'S DATA (called by the manager, in load order)
# =============================================================================

## Apply everything the manifest's `content` block declares. `mod_root` is
## the folder (res:// or user://) the mod was loaded from; every path in the
## block is relative to it.
func apply_mod_content(mod_id: String, mod_root: String, content: Dictionary) -> void:
	if content.has("buildings"):
		_apply_catalog(mod_id, mod_root, "buildings", str(content["buildings"]), _buildings)
	if content.has("decorations"):
		_apply_catalog(mod_id, mod_root, "decorations", str(content["decorations"]), _decorations)
	if content.has("terrain_overrides"):
		_apply_terrain(mod_id, mod_root.path_join(str(content["terrain_overrides"])))
	if content.has("themes"):
		_apply_simple_patches(mod_id, mod_root.path_join(str(content["themes"])), "themes", _theme_overrides)
	if content.has("tournament_tiers"):
		_apply_simple_patches(mod_id, mod_root.path_join(str(content["tournament_tiers"])), "tiers", _tier_overrides)
	if content.has("world_locations"):
		_apply_locations(mod_id, mod_root.path_join(str(content["world_locations"])))
	if content.has("visiting_golfers") and content["visiting_golfers"] is Dictionary:
		for location_id in content["visiting_golfers"]:
			_apply_visitors(mod_id, str(location_id),
				mod_root.path_join(str(content["visiting_golfers"][location_id])))
	if content.has("golfer_names"):
		_apply_names(mod_id, mod_root.path_join(str(content["golfer_names"])))
	if content.has("seasonal_events"):
		_apply_seasonal_events(mod_id, mod_root.path_join(str(content["seasonal_events"])))
	if content.has("golfer_skins_root"):
		var skins_root: String = mod_root.path_join(str(content["golfer_skins_root"]))
		if DirAccess.dir_exists_absolute(skins_root):
			_skin_roots.append(skins_root)
		else:
			_warn(mod_id, "golfer_skins_root '%s' does not exist." % skins_root)
	if content.has("tuning"):
		_apply_tuning(mod_id, mod_root.path_join(str(content["tuning"])))
	_push_statics()
	content_changed.emit()


## Let live libraries that cache files (golfer skins) re-read after mods have
## loaded. The manager calls this once, after the last mod.
func refresh_live_libraries() -> void:
	if is_inside_tree():
		var skins: Node = get_node_or_null("/root/GolferSkins")
		if skins != null and skins.has_method("reload"):
			skins.reload()


func _push_statics() -> void:
	TerrainTypes.set_mod_overrides(_terrain_overrides)
	CourseTheme.set_mod_overrides(_theme_overrides)
	TournamentSystem.set_mod_tier_overrides(_tier_overrides)
	WorldLocations.set_mod_locations(_locations)
	WorldLocations.set_mod_visitors(_visitors)
	GolferAttributes.set_mod_name_extras(_name_extras)
	GolferSkinLibrary.set_extra_roots(_skin_roots)
	var colors: Dictionary = {}
	for entry_id in _buildings:
		var color_value: Variant = _buildings[entry_id].get("color", null) if _buildings[entry_id] is Dictionary else null
		if color_value is String and not str(color_value).is_empty():
			colors[entry_id] = Color.html(str(color_value))
	BuildingSprites.set_fallback_colors(colors)


## Buildings and decorations: one catalog file of id -> entry, deep-merged
## over whatever earlier in the load order provided.
func _apply_catalog(mod_id: String, mod_root: String, kind: String, relative_path: String, catalog: Dictionary) -> void:
	var parsed: Variant = _read_json_file(mod_root.path_join(relative_path))
	if not (parsed is Dictionary):
		_warn(mod_id, "%s file '%s' could not be read as JSON." % [kind, relative_path])
		return
	var entries: Variant = parsed.get(kind, parsed)
	if not (entries is Dictionary):
		_warn(mod_id, "%s file '%s' must hold an object of entries." % [kind, relative_path])
		return
	for raw_id in entries:
		var patch: Variant = entries[raw_id]
		if not (patch is Dictionary):
			_warn(mod_id, "%s entry '%s' is not an object; skipped." % [kind, raw_id])
			continue
		_apply_catalog_entry(mod_id, kind, str(raw_id), patch, catalog)


func _apply_catalog_entry(mod_id: String, kind: String, raw_id: String, patch: Dictionary, catalog: Dictionary) -> void:
	var entry_id: String = _entry_id_for(mod_id, raw_id, catalog)
	if entry_id.is_empty():
		return
	if bool(patch.get("__remove__", false)):
		if catalog.has(entry_id):
			if bool(catalog[entry_id].get("required", false)):
				_warn(mod_id, "%s '%s' is required by the game and cannot be removed." % [kind, entry_id])
				return
			catalog.erase(entry_id)
			_provenance[kind].erase(entry_id)
		return
	var clean: Dictionary = patch.duplicate(true)
	clean.erase("__remove__")
	var replace: bool = bool(clean.get("__replace__", false))
	clean.erase("__replace__")
	var previous_owner: String = str(_provenance[kind].get(entry_id, ""))
	if catalog.has(entry_id) and not replace:
		catalog[entry_id] = deep_merge(catalog[entry_id], clean)
	else:
		catalog[entry_id] = clean
	catalog[entry_id]["id"] = entry_id
	_normalise_catalog_entry(kind, entry_id, catalog[entry_id])
	if not previous_owner.is_empty() and previous_owner != CORE_SOURCE and previous_owner != mod_id:
		_conflicts.append("%s '%s': written by %s, overwritten by %s (later in the load order wins)." % [kind, entry_id, previous_owner, mod_id])
	_provenance[kind][entry_id] = mod_id


## Fill the gaps a sparse entry would otherwise leave for the systems that
## read it, so a minimal mod building still places, costs and draws.
func _normalise_catalog_entry(kind: String, entry_id: String, entry: Dictionary) -> void:
	if not entry.has("name") or str(entry.get("name", "")).is_empty():
		entry["name"] = entry_id.get_slice(":", 1) if entry_id.contains(":") else entry_id
	var size_value: Variant = entry.get("size", null)
	if not (size_value is Array) or size_value.size() != 2:
		entry["size"] = [1, 1]
	var dimensions: Array = entry["size"]
	for axis in range(2):
		var dimension: Variant = dimensions[axis]
		dimensions[axis] = clampi(int(dimension), 1, 32) if dimension is float or dimension is int else 1
	var cost_value: Variant = entry.get("cost", 0)
	entry["cost"] = maxi(0, int(cost_value)) if cost_value is int or cost_value is float else 0
	if kind == "decorations":
		if not entry.has("category"):
			entry["category"] = "structures"
		if not entry.has("placeable_terrain"):
			entry["placeable_terrain"] = ["grass", "path"]


## The id a raw entry applies to, or "" when the entry must be skipped.
func _entry_id_for(mod_id: String, raw_id: String, catalog: Dictionary) -> String:
	var cleaned: String = raw_id.strip_edges()
	if cleaned.is_empty():
		_warn(mod_id, "An entry with an empty id was skipped.")
		return ""
	if cleaned.contains(":"):
		var claimed_by: String = cleaned.get_slice(":", 0)
		if claimed_by != mod_id and not catalog.has(cleaned):
			_warn(mod_id, "Entry '%s' claims another mod's namespace; skipped. New content is namespaced automatically." % cleaned)
			return ""
		return cleaned
	if catalog.has(cleaned):
		return cleaned
	return resolve_new_id(mod_id, cleaned)


func _apply_terrain(mod_id: String, path: String) -> void:
	var parsed: Variant = _read_json_file(path)
	if not (parsed is Dictionary):
		_warn(mod_id, "terrain_overrides '%s' could not be read." % path)
		return
	var entries: Variant = parsed.get("terrain", parsed)
	if not (entries is Dictionary):
		return
	for key in entries:
		var terrain_id: int = _terrain_id_for(str(key))
		if terrain_id < 0 or not (entries[key] is Dictionary):
			_warn(mod_id, "Unknown terrain '%s'; skipped." % key)
			continue
		var patch: Dictionary = {}
		for property in entries[key]:
			patch[str(property)] = _terrain_value(str(property), entries[key][property])
		var existing: Dictionary = _terrain_overrides.get(terrain_id, {})
		_terrain_overrides[terrain_id] = deep_merge(existing, patch)


func _terrain_id_for(key: String) -> int:
	if key.is_valid_int():
		return key.to_int()
	return int(_terrain_name_to_id.get(key.to_lower(), -1))


func _terrain_value(property: String, value: Variant) -> Variant:
	if property == "color":
		if value is String:
			return Color.html(value)
		if value is Array and value.size() >= 3:
			return Color(float(value[0]), float(value[1]), float(value[2]),
				float(value[3]) if value.size() >= 4 else 1.0)
	return value


## Themes and tournament tiers share a shape: {wrapper: {name: {patch}}}.
func _apply_simple_patches(mod_id: String, path: String, wrapper: String, into: Dictionary) -> void:
	var parsed: Variant = _read_json_file(path)
	if not (parsed is Dictionary):
		_warn(mod_id, "'%s' could not be read." % path)
		return
	var entries: Variant = parsed.get(wrapper, parsed)
	if not (entries is Dictionary):
		return
	for key in entries:
		if entries[key] is Dictionary:
			var name_key: String = str(key).to_lower()
			into[name_key] = deep_merge(into.get(name_key, {}), entries[key])


func _apply_locations(mod_id: String, path: String) -> void:
	var parsed: Variant = _read_json_file(path)
	if not (parsed is Dictionary):
		_warn(mod_id, "world_locations '%s' could not be read." % path)
		return
	var entries: Variant = parsed.get("locations", [])
	if not (entries is Array):
		return
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var location: Dictionary = _normalise_location(mod_id, raw)
		if location.is_empty():
			continue
		var replaced := false
		for i in range(_locations.size()):
			if str(_locations[i].get("id", "")) == str(location["id"]):
				_locations[i] = location
				replaced = true
				break
		if not replaced:
			_locations.append(location)


## A mod location in WorldLocations' shape, or {} when unusable. Theme and
## size accept names ("links", "medium") so JSON stays readable.
func _normalise_location(mod_id: String, raw: Dictionary) -> Dictionary:
	var raw_id: String = str(raw.get("id", "")).strip_edges()
	var location_name: String = str(raw.get("name", "")).strip_edges()
	if raw_id.is_empty() or location_name.is_empty():
		_warn(mod_id, "A world location needs an id and a name; one was skipped.")
		return {}
	var theme_value: Variant = raw.get("theme", "parkland")
	var theme: int = CourseTheme.from_string(str(theme_value)) if theme_value is String else int(theme_value)
	var size_value: Variant = raw.get("size", "medium")
	var size: int = int({"small": 0, "medium": 1, "large": 2, "championship": 3}.get(
		str(size_value).to_lower(), 1)) if size_value is String else clampi(int(size_value), 0, 3)
	var shipped_ids: Array = []
	for shipped in WorldLocations.LOCATIONS:
		shipped_ids.append(str(shipped.get("id", "")))
	var location_id: String = raw_id if raw_id.contains(":") or raw_id in shipped_ids else resolve_new_id(mod_id, raw_id)
	return {
		"id": location_id,
		"name": location_name,
		"region": str(raw.get("region", "")),
		"theme": theme,
		"size": size,
		"lat": clampf(float(raw.get("lat", 0.0)), -85.0, 85.0),
		"lon": clampf(float(raw.get("lon", 0.0)), -180.0, 180.0),
		"prestige": clampf(float(raw.get("prestige", 1.0)), 0.1, 5.0),
		"description": str(raw.get("description", "")),
	}


func _apply_visitors(mod_id: String, location_key: String, path: String) -> void:
	var parsed: Variant = _read_json_file(path)
	if not (parsed is Array):
		_warn(mod_id, "visiting golfers '%s' must be a JSON array of golfer cards." % path)
		return
	# A mod's own location is usually named bare in its file; its in-game id
	# is the namespaced one.
	var location_id: String = location_key
	if not location_key.contains(":"):
		var namespaced: String = resolve_new_id(mod_id, location_key)
		for location in _locations:
			if str(location.get("id", "")) == namespaced:
				location_id = namespaced
				break
	var existing: Array = _visitors.get(location_id, [])
	existing.append_array(parsed)
	_visitors[location_id] = existing


func _apply_names(mod_id: String, path: String) -> void:
	var parsed: Variant = _read_json_file(path)
	if not (parsed is Dictionary):
		_warn(mod_id, "golfer_names '%s' could not be read." % path)
		return
	for key in ["professions", "female_first_names", "male_first_names", "last_names"]:
		var values: Variant = parsed.get(key, [])
		if values is Array:
			var merged: Array = _name_extras.get(key, [])
			for value in values:
				merged.append(str(value))
			_name_extras[key] = merged


func _apply_seasonal_events(mod_id: String, path: String) -> void:
	var parsed: Variant = _read_json_file(path)
	if not (parsed is Dictionary):
		_warn(mod_id, "seasonal_events '%s' could not be read." % path)
		return
	var entries: Variant = parsed.get("events", [])
	if not (entries is Array):
		return
	var known: Dictionary = {}
	for existing in SeasonalEvents.get_all_events():
		known[existing.id] = true
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var data: Dictionary = raw.duplicate(true)
		var raw_id: String = str(data.get("id", ""))
		if not raw_id.contains(":") and not known.has(raw_id):
			data["id"] = resolve_new_id(mod_id, raw_id)
		if SeasonalEvents.register_event_from_data(data, mod_id) == null:
			_warn(mod_id, "A seasonal event without an id or a name was skipped.")


func _apply_tuning(mod_id: String, path: String) -> void:
	var parsed: Variant = _read_json_file(path)
	if not (parsed is Dictionary):
		_warn(mod_id, "tuning '%s' could not be read." % path)
		return
	var entries: Variant = parsed.get("tuning", parsed)
	if not (entries is Dictionary):
		return
	for key in entries:
		if entries[key] is int or entries[key] is float:
			_tuning[str(key)] = float(entries[key])
			_tuning_provenance[str(key)] = mod_id
		else:
			_warn(mod_id, "Tuning value '%s' is not a number; skipped." % key)


func _warn(mod_id: String, message: String) -> void:
	_warnings.append("[%s] %s" % [mod_id, message])
	push_warning("ContentRegistry [%s]: %s" % [mod_id, message])


## Recursively merge `patch` over `base`: nested dictionaries merge,
## everything else (including arrays) is replaced by the patch value.
static func deep_merge(base: Dictionary, patch: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true)
	for key in patch:
		if merged.get(key) is Dictionary and patch[key] is Dictionary:
			merged[key] = deep_merge(merged[key], patch[key])
		else:
			merged[key] = patch[key].duplicate(true) if patch[key] is Dictionary or patch[key] is Array else patch[key]
	return merged
