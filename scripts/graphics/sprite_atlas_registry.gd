extends RefCounted
class_name SpriteAtlasRegistry
## SpriteAtlasRegistry - High-level lookup for game sprite categories.
##
## Centralizes the mapping between game ids (building type + facing, tree
## species + season, decoration type) and sprite sheet entries. This gives
## mods a stable API to add sprites: register_sprite(category, id, entry).
##
## Categories map to sheet files:
##   "building"     -> buildings.png/json
##   "decoration"   -> decorations.png/json
##   "tree"         -> trees.png/json
##   "golfer"       -> golfer.png/json
##   "ui_icon"      -> ui_icons.png/json
##
## Mods can call ModAPI.register_sprite(category, id, { atlas_rect, fallback })
## to extend any category without touching core code.

const CATEGORY_TO_SHEET: Dictionary = {
	"building": "buildings",
	"decoration": "decorations",
	"tree": "trees",
	"golfer": "golfer",
	"ui_icon": "ui_icons",
}

static var _mod_overrides: Dictionary = {}  # category -> id -> { mod_id, texture_path, rect }

## Register a mod-provided sprite. `info` = { "fallback": "res://path.png", "rect": [x,y,w,h], "sheet": "buildings" }
static func register_mod_sprite(mod_id: String, category: String, sprite_id: String, info: Dictionary) -> void:
	if not _mod_overrides.has(category):
		_mod_overrides[category] = {}
	_mod_overrides[category][sprite_id] = { "mod_id": mod_id, "info": info }

static func has_mod_sprite(category: String, sprite_id: String) -> bool:
	return _mod_overrides.has(category) and _mod_overrides[category].has(sprite_id)

static func get_mod_texture(category: String, sprite_id: String) -> Texture2D:
	if not has_mod_sprite(category, sprite_id):
		return null
	var entry: Dictionary = _mod_overrides[category][sprite_id]
	var info: Dictionary = entry["info"]
	var fallback: String = str(info.get("fallback", ""))
	if ResourceLoader.exists(fallback):
		return load(fallback) as Texture2D
	return null

## Get the texture for a game id, checking mod overrides first, then sheets, then fallback.
static func get_texture(category: String, sprite_id: String, fallback_path: String = "") -> Texture2D:
	# Mod override wins (later mods already overwrote earlier in _mod_overrides)
	if has_mod_sprite(category, sprite_id):
		var mod_tex := get_mod_texture(category, sprite_id)
		if mod_tex:
			return mod_tex
	var sheet: String = str(CATEGORY_TO_SHEET.get(category, category))
	return SpriteSheet.get_texture_with_fallback(sheet, sprite_id, fallback_path)

static func clear_mod_sprites(mod_id: String) -> void:
	for category in _mod_overrides.keys():
		var ids: Array = _mod_overrides[category].keys()
		for sid in ids:
			if str(_mod_overrides[category][sid].get("mod_id", "")) == mod_id:
				_mod_overrides[category].erase(sid)
