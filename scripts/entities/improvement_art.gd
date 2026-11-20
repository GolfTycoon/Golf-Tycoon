extends RefCounted
class_name ImprovementArt
## ImprovementArt - the baked sprites for the Path furniture and the ornaments.
##
## The art is baked offline by `tools/improvement_art/generate.py`, which writes
## one PNG per drawing plus `layout.json`.  The sidecar records where the tile
## centre lands in each drawing's own (cropped) canvas: a bench seen from the
## front is a different shape from the same bench seen end-on, and a fountain's
## basin reaches lower than a sundial's steps.  The game anchors every sprite
## from those ratios, so a redrawn prop needs no code edit here.
##
## The fountain, statue and sundial stand in the open and ship one drawing; the
## bench and ball washer are laid beside a walk and ship four fronts, matching
## `PathFurniture`'s cardinal vectors (south, east, north, west).

const DIR := "res://assets/sprites/improvements/"
const LAYOUT_FILE := DIR + "layout.json"

## The ornaments that ship a sprite (the Path itself is ground art).
const KEYS := ["fountain", "golfer_statue", "ball_washer", "park_bench", "sundial"]
## Clips drawn beside a walk, one per front.
const DIRECTIONAL := ["park_bench", "ball_washer"]
## Fronts in file-suffix order, matching PathFurniture's facing vectors.
const FRONTS := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]

static var _layout: Dictionary = {}
static var _layout_loaded := false
static var _textures: Dictionary = {}

static func _load_layout() -> void:
	if _layout_loaded:
		return
	_layout_loaded = true
	if not FileAccess.file_exists(LAYOUT_FILE):
		return
	var file := FileAccess.open(LAYOUT_FILE, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_layout = parsed

static func _sprite_entry(key: String, suffix: String) -> Dictionary:
	_load_layout()
	var sprites: Dictionary = _layout.get("sprites", {})
	return sprites.get("%s_%s" % [key, suffix], {})

## The file suffix for a front.  Non-directional props always use "0".
static func suffix_for(key: String, front: Vector2i) -> String:
	if key not in DIRECTIONAL:
		return "0"
	var index := FRONTS.find(front)
	return str(index) if index >= 0 else "0"

static func texture(key: String, suffix: String = "0") -> Texture2D:
	var name := "%s_%s" % [key, suffix]
	if _textures.has(name):
		return _textures[name]
	var path := DIR + name + ".png"
	if not ResourceLoader.exists(path):
		_textures[name] = null
		return null
	var tex: Texture2D = load(path)
	_textures[name] = tex
	return tex

## Where the tile centre sits inside the drawing, in pixels from its top-left.
## Drawing the texture at `-foot_offset` puts the prop's foot on the tile.
static func foot_offset(key: String, suffix: String = "0") -> Vector2:
	var entry := _sprite_entry(key, suffix)
	var width := float(entry.get("width", 1))
	var height := float(entry.get("height", 1))
	return Vector2(float(entry.get("foot_x_ratio", 0.5)) * width,
			float(entry.get("foot_y_ratio", 1.0)) * height)

## How far the drawing's lowest painted pixel reaches below its foot, in pixels.
## This is the reach the terrain clip must measure from the anchor.
static func below_foot(key: String, suffix: String = "0") -> float:
	var tex := texture(key, suffix)
	if tex == null:
		return 0.0
	return maxf(0.0, tex.get_height() - foot_offset(key, suffix).y)
