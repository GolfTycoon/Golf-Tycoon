extends RefCounted
class_name MenuBackdropCatalog
## MenuBackdropCatalog - the background styles and overlays the menus can wear.
##
## A *background style* is a picture, its tint and its edge-scrim weight.
## An *overlay* is a pattern painted over whichever picture is showing. They
## are separate choices on purpose: a player picks one of each, so a mod that
## ships only an overlay still works with every picture, and the other way
## round.
##
## The shipped catalogue is `data/menu_backdrops.json` and
## `data/menu_overlays.json`. A mod adds to it declaratively, through the
## `menu_backdrops` / `menu_overlays` keys in its mod.json - no script needed:
##
##   "content": {
##     "menu_backdrops": "data/backdrops.json",
##     "menu_overlays":  "data/overlays.json"
##   }
##
## Both files hold one wrapper key (`backdrops` / `overlays`) mapping an id to
## an entry. Entries apply in load order and later wins, like every other
## content kind: an id that already exists patches that entry (so a mod can
## repaint the clubhouse without renaming it), a new id is namespaced to the
## mod that added it (`yourname.cool_mod:aurora`).
##
## This is one of the static data classes (like TerrainTypes and CourseTheme):
## the ContentRegistry owns the merged mod table and pushes it here with
## `set_mod_catalogues()`, and every reader - the menus, the Settings picker,
## the Mods screen - comes through `backdrops()` and `overlays()`.

const BACKDROPS_PATH := "res://data/menu_backdrops.json"
const OVERLAYS_PATH := "res://data/menu_overlays.json"
const CORE_SOURCE := "core"

## The picture Auto falls back to when nothing seasonal or theme-tagged applies.
const DEFAULT_BACKDROP_ID := "clubhouse"
## The overlay Auto falls back to: the plain picture. The edge scrim that keeps
## the headings readable is part of MenuBackdrop itself, not an overlay.
const DEFAULT_OVERLAY_ID := "none"

## The image formats a backdrop may use: the ones this game decodes from raw
## bytes, so mod art needs no import pipeline.
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "bmp"]

## The shipped catalogue, read once from data/. id -> entry.
static var _shipped_backdrops: Dictionary = {}
static var _shipped_overlays: Dictionary = {}
static var _shipped_settings: Dictionary = {}
static var _shipped_loaded: bool = false

## The mod table the ContentRegistry pushes (already merged in load order).
static var _mod_backdrops: Dictionary = {}
static var _mod_overlays: Dictionary = {}
static var _mod_settings: Dictionary = {}
static var _backdrop_sources: Dictionary = {}
static var _overlay_sources: Dictionary = {}


# ---------------------------------------------------------------------------
# THE READ DOOR
# ---------------------------------------------------------------------------

## Every background style, in picker order: the shipped pictures first (in
## file order), then mod-added ones alphabetically by display name.
static func backdrops() -> Array[Dictionary]:
	_ensure_shipped()
	return _ordered(_shipped_backdrops, _mod_backdrops, _backdrop_sources)


## Every overlay, in picker order.
static func overlays() -> Array[Dictionary]:
	_ensure_shipped()
	return _ordered(_shipped_overlays, _mod_overlays, _overlay_sources)


static func has_backdrop(id: String) -> bool:
	_ensure_shipped()
	return _shipped_backdrops.has(id) or _mod_backdrops.has(id)


static func has_overlay(id: String) -> bool:
	_ensure_shipped()
	return _shipped_overlays.has(id) or _mod_overlays.has(id)


## True when `id` names a style that ships with the game - the test a mod's
## entry uses to decide between patching that style and adding a new one.
static func has_shipped_entry(id: String, is_overlay: bool) -> bool:
	_ensure_shipped()
	return (_shipped_overlays if is_overlay else _shipped_backdrops).has(id)


## The shipped entry for `id` as read from data/, or {} - what a mod's patch is
## merged over, so a sparse patch ("just change the tint") needs no image of
## its own.
static func shipped_backdrop(id: String) -> Dictionary:
	_ensure_shipped()
	var found: Variant = _shipped_backdrops.get(id, {})
	return (found as Dictionary).duplicate(true) if found is Dictionary else {}


static func shipped_overlay(id: String) -> Dictionary:
	_ensure_shipped()
	var found: Variant = _shipped_overlays.get(id, {})
	return (found as Dictionary).duplicate(true) if found is Dictionary else {}


## The entry for `id`, or {} when no style by that name is on this machine - a
## settings file written with a mod still installed can be opened after it was
## removed, and the reader falls back rather than failing.
static func backdrop(id: String) -> Dictionary:
	_ensure_shipped()
	var entry := _resolve(_shipped_backdrops, _mod_backdrops, id, false)
	if not entry.is_empty():
		entry["source"] = str(_backdrop_sources.get(id, CORE_SOURCE))
	return entry


static func overlay(id: String) -> Dictionary:
	_ensure_shipped()
	var entry := _resolve(_shipped_overlays, _mod_overlays, id, true)
	if not entry.is_empty():
		entry["source"] = str(_overlay_sources.get(id, CORE_SOURCE))
	return entry


## A shipped entry with the mod table's patch folded over it, or a mod's own
## entry when no shipped style has that id. The result is normalised again so a
## patch that changes only one field still yields a complete entry - and so a
## patch can never leave a stale value behind.
static func _resolve(shipped: Dictionary, modded: Dictionary, id: String, is_overlay: bool) -> Dictionary:
	var has_shipped := shipped.has(id)
	if has_shipped:
		var base: Dictionary = shipped[id].duplicate(true)
		if modded.has(id):
			base = deep_merge(base, modded[id])
		base["id"] = id
		if is_overlay:
			normalise_overlay(base)
		else:
			normalise_backdrop(base)
		return base
	if modded.has(id):
		var entry: Dictionary = (modded[id] as Dictionary).duplicate(true)
		entry["id"] = id
		return entry
	return {}


## Which mod last wrote an entry ("core" for the shipped game), for the picker's
## "added by" caption and the Mods screen.
static func backdrop_source(id: String) -> String:
	return str(_backdrop_sources.get(id, CORE_SOURCE))


static func overlay_source(id: String) -> String:
	return str(_overlay_sources.get(id, CORE_SOURCE))


## True when the entry came from a mod rather than the shipped game.
static func is_from_mod(id: String, is_overlay: bool) -> bool:
	return str((_overlay_sources if is_overlay else _backdrop_sources).get(id, CORE_SOURCE)) != CORE_SOURCE


## The choices one overlay exposes (e.g. `angle` for the stripe patterns),
## ready for an OptionButton: [{key, name, description, choices, values, default}].
static func settings_for(overlay_id: String) -> Array[Dictionary]:
	_ensure_shipped()
	var entry := overlay(overlay_id)
	var ids: Variant = entry.get("setting_ids", [])
	var result: Array[Dictionary] = []
	if not (ids is Array):
		return result
	for raw_id in ids:
		var key: String = str(raw_id)
		var schema: Variant = _mod_settings.get(key, _shipped_settings.get(key, {}))
		if not (schema is Dictionary):
			continue
		result.append({
			"key": key,
			"name": str(schema.get("name", key.capitalize())),
			"description": str(schema.get("description", "")),
			"default": _whole_number(schema.get("default", 0)),
			"choices": (schema.get("choices", []) as Array).duplicate(),
			"values": _whole_values(schema.get("values", [])),
		})
	return result


## A saved value for `overlay_id`'s `key`, kept inside the values the catalogue
## declares. A hand-edited or stale value falls back to the default.
static func setting_value(overlay_id: String, key: String, saved: Variant) -> Variant:
	for schema in settings_for(overlay_id):
		if str(schema["key"]) != key:
			continue
		var values: Array = schema["values"]
		if saved is int or saved is float:
			var wanted := int(saved)
			return wanted if values.has(wanted) else schema["default"]
		if saved is String:
			var index: int = (schema["choices"] as Array).find(str(saved))
			if index >= 0 and index < values.size():
				return _whole_number(values[index])
		return schema["default"]
	return saved


## The settings dictionary MenuBackdropOverlay needs for `overlay_id`: every
## setting the overlay exposes, resolved from `saved` (key -> value) with the
## schema's default filling any gap.
static func resolved_settings(overlay_id: String, saved: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for schema in settings_for(overlay_id):
		var key: String = str(schema["key"])
		result[key] = setting_value(overlay_id, key, saved.get(key, schema["default"]))
	return result


# ---------------------------------------------------------------------------
# THE MOD TABLE (pushed by ContentRegistry)
# ---------------------------------------------------------------------------

## Install the mod contributions the registry merged. `backdrops` and
## `overlays` are already merged over their earlier mods; `sources` records
## which mod wrote each id.
static func set_mod_catalogues(mod_backdrops: Dictionary, mod_overlays: Dictionary,
		settings: Dictionary, backdrop_sources: Dictionary, overlay_sources: Dictionary) -> void:
	_mod_backdrops = mod_backdrops.duplicate(true)
	_mod_overlays = mod_overlays.duplicate(true)
	_mod_settings = settings.duplicate(true)
	_backdrop_sources = backdrop_sources.duplicate(true)
	_overlay_sources = overlay_sources.duplicate(true)


## Drop every mod contribution (back to the shipped catalogue).
static func clear_mod_catalogues() -> void:
	_mod_backdrops.clear()
	_mod_overlays.clear()
	_mod_settings.clear()
	_backdrop_sources.clear()
	_overlay_sources.clear()


## How many styles each mod contributed, `{mod_id: {"backdrops": n, "overlays": n}}`,
## for ContentRegistry's content summary.
static func content_summary() -> Dictionary:
	var summary: Dictionary = {}
	for id in _backdrop_sources:
		_add_to_summary(summary, str(_backdrop_sources[id]), "backdrops")
	for id in _overlay_sources:
		_add_to_summary(summary, str(_overlay_sources[id]), "overlays")
	return summary


# ---------------------------------------------------------------------------
# NORMALISING A MOD ENTRY (called by ContentRegistry while applying a mod)
# ---------------------------------------------------------------------------

## Fill the gaps a sparse backdrop entry would leave for MenuBackdrop. A
## picture that is missing is the one thing that cannot be filled in, so the
## entry is flagged invalid and the options list leaves it out. Returns the
## warning to report, or "" when the entry is fine.
static func normalise_backdrop(entry: Dictionary, folder: String = "") -> String:
	var image: String = str(entry.get("image", "")).strip_edges()
	if image.is_empty():
		entry["_invalid"] = true
		return "Backdrop '%s' names no image; skipped." % str(entry.get("id", "?"))
	if not folder.is_empty() and not image.begins_with("res://") \
			and not image.begins_with("user://") and not image.is_absolute_path():
		image = folder.path_join(image)
	entry["image"] = image
	entry.erase("_invalid")
	if not entry.has("name") or str(entry.get("name", "")).is_empty():
		var id: String = str(entry.get("id", ""))
		entry["name"] = _display_name_for(id) if not id.is_empty() else "Backdrop"
	entry["description"] = str(entry.get("description", ""))
	entry["tint"] = colour_value(entry.get("tint", "ffffff"))
	var scrim: Variant = entry.get("scrim", 0.45)
	entry["scrim"] = clampf(float(scrim) if scrim is int or scrim is float else 0.45, 0.0, 0.9)
	entry["tags"] = string_list(entry.get("tags", []))
	entry["seasons"] = lower_list(entry.get("seasons", []))
	entry["themes"] = lower_list(entry.get("themes", []))
	if not IMAGE_EXTENSIONS.has(image.get_extension().to_lower()):
		return "Backdrop '%s' uses .%s - use PNG, JPG, WEBP or BMP so it decodes on every platform." % [
			str(entry.get("id", "?")), image.get_extension()]
	return ""


## Fill the gaps a sparse overlay entry would leave. An unknown pattern is
## reported and the entry still loads (drawing nothing) rather than vanishing
## from a player's picker without a trace.
static func normalise_overlay(entry: Dictionary) -> String:
	var pattern: String = str(entry.get("pattern", "none")).to_lower()
	var warning := ""
	if not MenuBackdropOverlay.is_pattern(pattern):
		warning = "Overlay '%s' names unknown pattern '%s' - it will draw nothing. Known: %s." % [
			str(entry.get("id", "?")), pattern, ", ".join(MenuBackdropOverlay.PATTERNS)]
		pattern = "none"
	entry["pattern"] = pattern
	if not entry.has("name") or str(entry.get("name", "")).is_empty():
		var id: String = str(entry.get("id", ""))
		entry["name"] = _display_name_for(id) if not id.is_empty() else "Overlay"
	entry["description"] = str(entry.get("description", ""))
	entry["color"] = colour_value(entry.get("color", "06110c"))
	var strength: Variant = entry.get("strength", 0.2)
	entry["strength"] = clampf(float(strength) if strength is int or strength is float else 0.2, 0.0, 1.0)
	var scale: Variant = entry.get("scale", MenuBackdropOverlay.default_scale(pattern))
	entry["scale"] = maxf(float(scale) if scale is int or scale is float
		else MenuBackdropOverlay.default_scale(pattern), 0.5)
	entry["setting_ids"] = string_list(entry.get("setting_ids", []))
	entry["seasons"] = lower_list(entry.get("seasons", []))
	entry["themes"] = lower_list(entry.get("themes", []))
	return warning


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

## Read the shipped files once per run. Kept lazy so a headless tool that never
## opens a menu never pays for it.
static func _ensure_shipped() -> void:
	if _shipped_loaded:
		return
	_shipped_loaded = true
	_read_file(BACKDROPS_PATH, "backdrops", _shipped_backdrops, true)
	_read_file(OVERLAYS_PATH, "overlays", _shipped_overlays, false)
	var parsed: Variant = _read_json(OVERLAYS_PATH)
	if parsed is Dictionary and parsed.get("settings") is Dictionary:
		_shipped_settings = (parsed["settings"] as Dictionary).duplicate(true)


static func _read_file(path: String, wrapper: String, into: Dictionary, is_backdrop: bool) -> void:
	var parsed: Variant = _read_json(path)
	if not (parsed is Dictionary):
		push_error("MenuBackdropCatalog: %s is missing or is not a JSON object." % path)
		return
	var entries: Variant = parsed.get(wrapper, parsed)
	if not (entries is Dictionary):
		push_error("MenuBackdropCatalog: %s holds no '%s' catalog." % [path, wrapper])
		return
	var folder := path.get_base_dir()
	for raw_id in entries:
		var patch: Variant = entries[raw_id]
		if not (patch is Dictionary):
			continue
		var entry: Dictionary = (patch as Dictionary).duplicate(true)
		entry["id"] = str(raw_id)
		if is_backdrop:
			var warning := normalise_backdrop(entry, folder)
			if not warning.is_empty():
				push_warning("MenuBackdropCatalog: " + warning)
			if bool(entry.get("_invalid", false)):
				continue
		else:
			normalise_overlay(entry)
		into[str(raw_id)] = entry


## The catalogue as display dictionaries, shipped ones first.
static func _ordered(shipped: Dictionary, modded: Dictionary, sources: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in shipped:
		var entry: Dictionary = backdrop(str(id)) if shipped == _shipped_backdrops else overlay(str(id))
		if entry.is_empty() or bool(entry.get("_invalid", false)):
			continue
		entry["id"] = str(id)
		result.append(entry)
	var added: Array[Dictionary] = []
	for id in modded:
		# An id the shipped catalogue already has was patched, and is listed
		# above with the patch folded in - not a second row.
		if shipped.has(id):
			continue
		var entry: Dictionary = backdrop(str(id)) if shipped == _shipped_backdrops else overlay(str(id))
		if entry.is_empty() or bool(entry.get("_invalid", false)):
			continue
		entry["id"] = str(id)
		entry["source"] = str(sources.get(id, CORE_SOURCE))
		added.append(entry)
	added.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	result.append_array(added)
	return result


## JSON has one number type, so a choice value written as `45` comes back as
## 45.0. The catalogue's choices are whole numbers, and a picker compares them
## by value, so they are normalised back to ints here.
static func _whole_number(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)):
		return int(roundf(value))
	return value


static func _whole_values(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for entry in value:
			result.append(_whole_number(entry))
	return result


static func _display_name_for(id: String) -> String:
	return id.get_slice(":", 1).capitalize() if id.contains(":") else id.capitalize()


static func _add_to_summary(summary: Dictionary, source: String, kind: String) -> void:
	if source == CORE_SOURCE:
		return
	if not summary.has(source):
		summary[source] = {}
	summary[source][kind] = int(summary[source].get(kind, 0)) + 1


## Recursively merge `patch` over `base`: nested dictionaries merge, everything
## else (arrays included) is replaced by the patch value.
static func deep_merge(base: Dictionary, patch: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true)
	for key in patch:
		if merged.get(key) is Dictionary and patch[key] is Dictionary:
			merged[key] = deep_merge(merged[key], patch[key])
		else:
			merged[key] = patch[key].duplicate(true) if patch[key] is Dictionary or patch[key] is Array else patch[key]
	return merged


## Colours are written as hex ("f5cb45", "#f5cb45") or as [r, g, b] floats.
static func colour_value(value: Variant) -> Color:
	if value is Color:
		return value
	if value is Array and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]),
			float(value[3]) if value.size() >= 4 else 1.0)
	if value is String and not str(value).is_empty():
		return Color.html(str(value))
	return Color.WHITE


static func string_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(str(entry))
	return result


static func lower_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(str(entry).to_lower())
	return result


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return ModManifest.parse_json_quietly(FileAccess.get_file_as_string(path))
