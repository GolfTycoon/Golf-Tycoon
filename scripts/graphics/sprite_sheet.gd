extends RefCounted
class_name SpriteSheet
## SpriteSheet - Efficient atlas-based sprite access.
##
## Individual sprites (buildings, decorations, trees, golfer frames) used to be
## loaded as dozens of small PNG files, each with its own import and texture.
## That costs draw calls and memory. SpriteSheet groups them into one or a few
## atlas textures and describes each sprite as a rectangle inside that atlas.
##
## The atlas is built by tools/pack_sprites.py (or the Python packer) which
## writes:
##   - assets/sprite_sheets/<sheet>.png   — the packed image
##   - assets/sprite_sheets/<sheet>.json  — map of sprite id -> rect + metadata
##
## At runtime SpriteSheet loads the atlas once and hands out AtlasTexture
## regions. Callers never touch the individual PNGs directly; they ask for
## "building:clubhouse:1:e" and get a texture that draws from the sheet.
##
## This saves:
##   - Texture binds (one atlas per category vs one per sprite)
##   - Import overhead (one .import per atlas vs dozens)
##   - Memory (shared image vs many small images + padding)
##
## Fallback: if a sheet is missing or a sprite not in it, the old individual
## PNG path is tried so older mods and unsheeted content still work.

const SHEETS_DIR := "res://assets/sprite_sheets/"

## One atlas: its texture, and a map of sprite id -> entry.
## entry = { "rect": [x,y,w,h], "source_size": [w,h], "rotated": bool, "atlas": int }
static var _atlases: Dictionary = {}  # sheet_name -> { texture: Texture2D, entries: Dictionary, json: Dictionary }
static var _texture_cache: Dictionary = {}  # path -> Texture2D
static var _region_cache: Dictionary = {}  # sheet_name:sprite_id -> AtlasTexture

## All known sheets (must have a .json manifest). Add new sheets here.
const KNOWN_SHEETS: Array[String] = [
	"buildings",
	"decorations",
	"trees",
	"golfer",
	"ui_icons",
]

## Load (or return cached) the atlas for a sheet. Returns null if missing.
static func get_atlas(sheet_name: String) -> Dictionary:
	if _atlases.has(sheet_name):
		return _atlases[sheet_name]
	var json_path := SHEETS_DIR + sheet_name + ".json"
	if not FileAccess.file_exists(json_path):
		return {}
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_warning("SpriteSheet: invalid JSON in %s" % json_path)
		return {}
	var tex_path: String = parsed.get("meta", {}).get("image", SHEETS_DIR + sheet_name + ".png")
	var tex: Texture2D = null
	if ResourceLoader.exists(tex_path):
		tex = load(tex_path)
		if tex == null:
			push_warning("SpriteSheet: cannot load atlas texture %s" % tex_path)
	_atlases[sheet_name] = {
		"texture": tex,
		"entries": parsed.get("frames", {}),
		"meta": parsed.get("meta", {}),
		"json": parsed,
	}
	return _atlases[sheet_name]

## Does this sheet contain sprite_id?
static func has_sprite(sheet_name: String, sprite_id: String) -> bool:
	var atlas := get_atlas(sheet_name)
	if atlas.is_empty():
		return false
	return atlas["entries"].has(sprite_id)

## Get an AtlasTexture for sprite_id inside sheet_name. Returns null if missing.
static func get_texture(sheet_name: String, sprite_id: String) -> Texture2D:
	var cache_key := sheet_name + ":" + sprite_id
	if _region_cache.has(cache_key):
		return _region_cache[cache_key]
	var atlas := get_atlas(sheet_name)
	if atlas.is_empty() or atlas["texture"] == null:
		return null
	var entries: Dictionary = atlas["entries"]
	if not entries.has(sprite_id):
		return null
	var entry: Dictionary = entries[sprite_id]
	var rect_data: Array = entry.get("frame", entry.get("rect", []))
	if rect_data.size() < 4:
		return null
	var rect := Rect2(float(rect_data[0]), float(rect_data[1]), float(rect_data[2]), float(rect_data[3]))
	var _source_size_data: Array = entry.get("sourceSize", entry.get("source_size", rect_data))
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = atlas["texture"]
	atlas_tex.region = rect
	atlas_tex.filter_clip = true
	_region_cache[cache_key] = atlas_tex
	return atlas_tex

## Get the frame rectangle for a sprite (in atlas pixels).
static func get_rect(sheet_name: String, sprite_id: String) -> Rect2:
	var atlas := get_atlas(sheet_name)
	if atlas.is_empty():
		return Rect2()
	var entry: Dictionary = atlas["entries"].get(sprite_id, {})
	var rect_data: Array = entry.get("frame", entry.get("rect", []))
	if rect_data.size() < 4:
		return Rect2()
	return Rect2(float(rect_data[0]), float(rect_data[1]), float(rect_data[2]), float(rect_data[3]))

## Try sheet first, fall back to individual PNG. Returns a Texture2D or null.
static func get_texture_with_fallback(sheet_name: String, sprite_id: String, fallback_path: String) -> Texture2D:
	var tex := get_texture(sheet_name, sprite_id)
	if tex != null:
		return tex
	# Fallback: individual file
	if ResourceLoader.exists(fallback_path):
		if _texture_cache.has(fallback_path):
			return _texture_cache[fallback_path]
		var loaded := load(fallback_path) as Texture2D
		if loaded:
			_texture_cache[fallback_path] = loaded
			return loaded
	return null

## Clear caches (e.g. after hot-reload of atlases in editor).
static func clear_cache() -> void:
	_atlases.clear()
	_texture_cache.clear()
	_region_cache.clear()

## Create an AtlasTexture manually (for code-generated sheets).
static func make_atlas_texture(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = atlas
	t.region = region
	t.filter_clip = true
	return t

## List all sprite ids in a sheet.
static func list_sprites(sheet_name: String) -> Array[String]:
	var atlas := get_atlas(sheet_name)
	if atlas.is_empty():
		return []
	var out: Array[String] = []
	for k in atlas["entries"].keys():
		out.append(str(k))
	return out
