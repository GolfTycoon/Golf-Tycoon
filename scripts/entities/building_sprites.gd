extends Node
class_name BuildingSprites
## The pixel-art sprites every facility on the course is drawn with.
##
## The images live in `assets/sprites/buildings/` next to a manifest
## (`sprites.json`) that the art pipeline (`tools/building_art/generate.py`)
## writes. For every building, upgrade tier and view rotation the manifest
## records the PNG and the rectangle it covers in the local draw space of the
## building node, in world pixels — the same space `Building.set_position_in_grid()`
## anchors. Drawing a sprite into that rectangle therefore places the pixel art
## exactly on the tiles the building occupies, at every rotation.
##
## One art pixel is `PIXEL_SCALE` world pixels (a tile is 64 x 32 world pixels,
## so an art pixel is 1/32 of a tile across). Sprites are drawn with nearest
## filtering so that pixel grid stays crisp at any camera zoom.

const MANIFEST_PATH := "res://assets/sprites/buildings/sprites.json"
const SPRITE_DIR := "res://assets/sprites/buildings/"

## View rotations, in the order the manifest lists them. Matches
## TerrainGrid.get_view_orientation().
const FACINGS := ["e", "s", "w", "n"]

static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}

## The parsed manifest, loaded once. Keys: `pixel_scale`, `tile` and
## `buildings` -> kind -> `tiers` -> tier -> `facings` -> [{file, rect}].
static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			_manifest = parsed if parsed is Dictionary else {}
		else:
			push_warning("BuildingSprites: no sprite manifest at %s" % MANIFEST_PATH)
			_manifest = {"pixel_scale": 2.0, "buildings": {}}
	return _manifest

static func has_sprite(kind: String) -> bool:
	return manifest().get("buildings", {}).has(kind)

static func tier_count(kind: String) -> int:
	var building: Dictionary = manifest().get("buildings", {}).get(kind, {})
	return building.get("tiers", {}).size()

## Tier clamped to the tiers the art provides (most facilities have one).
static func tier_for(kind: String, level: int) -> int:
	var count := tier_count(kind)
	if count <= 0:
		return 1
	return clampi(level, 1, count)

## `{file, rect}` for one building, tier and view rotation, or {} when there
## is no art for it.
static func entry(kind: String, tier: int, facing: int) -> Dictionary:
	var tiers: Dictionary = manifest().get("buildings", {}).get(kind, {}).get("tiers", {})
	var faces: Array = tiers.get(str(tier_for(kind, tier)), {}).get("facings", [])
	var index := wrapi(facing, 0, FACINGS.size())
	if index < 0 or index >= faces.size():
		return {}
	return faces[index]

## The texture for one building, tier and view rotation.
static func texture(kind: String, tier: int, facing: int) -> Texture2D:
	var art := entry(kind, tier, facing)
	if art.is_empty():
		return null
	var path: String = SPRITE_DIR + str(art.get("file", ""))
	if _textures.has(path):
		return _textures[path]
	var loaded: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_textures[path] = loaded
	return loaded

## The rectangle the sprite covers in the building node's local draw space
## (world pixels), or a zero rect when there is no art.
static func rect(kind: String, tier: int, facing: int) -> Rect2:
	var art := entry(kind, tier, facing)
	if art.is_empty():
		return Rect2()
	var values: Array = art.get("rect", [0, 0, 0, 0])
	if values.size() < 4:
		return Rect2()
	return Rect2(values[0], values[1], values[2], values[3])

## How tall the facility draws above its own footprint, in world pixels. Used
## by tests and menu copy; the art itself needs nothing from the manifest.
static func height(kind: String) -> float:
	return float(manifest().get("buildings", {}).get(kind, {}).get("sprite_height", 0.0))

## Draw `kind` at `tier` and `facing` in the local space of a building node.
## The footprint is part of the call so every drawing path names the square it
## stands on, but the manifest rect already carries the artwork's placement — it
## was rendered in exactly that space. Returns the rectangle drawn.
static func draw(canvas: CanvasItem, kind: String, _footprint: Vector2, tier := 1,
		facing := 0) -> Rect2:
	var art_rect := rect(kind, tier, facing)
	var tex := texture(kind, tier, facing)
	if tex == null or art_rect.size.x <= 0.0:
		return Rect2()
	canvas.draw_texture_rect(tex, art_rect, false)
	return art_rect

## Draw the same sprite scaled so the footprint fills `placement`, the transform
## the catalogue tiles use to stand a building on a diamond button. The rect is
## authored in the full-size local space, so scaling the whole space keeps the
## preview concentric with the placed building.
static func draw_with_transform(canvas: CanvasItem, kind: String, tier: int,
		placement: Transform2D) -> Rect2:
	var art_rect := rect(kind, tier, 0)
	var tex := texture(kind, tier, 0)
	if tex == null or art_rect.size.x <= 0.0:
		return Rect2()
	var drawn := Rect2(placement * art_rect.position,
			placement.get_scale() * art_rect.size)
	canvas.draw_texture_rect(tex, drawn, false)
	return drawn
