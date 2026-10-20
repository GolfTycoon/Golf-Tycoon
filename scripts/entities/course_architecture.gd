extends Node2D
class_name CourseArchitecture
## The pixel-art drawing of one facility, anchored to the tiles it stands on.
##
## Every facility is a pixel image: a pre-rendered isometric sprite from
## `assets/sprites/buildings/` (see BuildingSprites and the art pipeline in
## `tools/building_art/`). One image exists per upgrade tier and per quarter-turn
## of the view, so the same picture is used by the placed building, the
## placement ghost and the Buildings tab.
##
## Geometry is still authored in grid space — x across the footprint, y down it,
## z in world pixels above the ground — and projected through the same 2:1
## axes the terrain uses. The sprite was rendered in that space, so its
## footprint corners are the terrain's own tile corners at every rotation. The
## helpers here are what the renderer (and the tests) use to keep that true.
##
## `facing` is the view rotation the footprint is projected for. Rotating the
## course swaps in the image drawn for that rotation, so the building's walls
## turn with the course instead of being seen side-on.

var kind := "clubhouse"
var footprint := Vector2(256, 128)
var level := 1
var facing := 0

func _ready() -> void:
	add_to_group("course_architecture")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func _draw() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	BuildingSprites.draw(self, kind, footprint, level, facing)


# ===========================================================================
# PROJECTION
# ===========================================================================

## One grid tile's diamond in world pixels: a footprint of `n` tiles arrives
## here as `n * TILE_W` wide and `n * TILE_H` deep.
const TILE_W := 64.0
const TILE_H := 32.0

## Quarter-turn a grid-space offset the way GridProjection rotates the course.
## The parameter is named `view_facing` rather than `facing` so that a static
## helper does not shadow the view rotation a placed node keeps in `facing`.
static func rotate_uv(offset: Vector2, view_facing: int) -> Vector2:
	match wrapi(view_facing, 0, 4):
		1:
			return Vector2(-offset.y, offset.x)
		2:
			return -offset
		3:
			return Vector2(offset.y, -offset.x)
		_:
			return offset

## A grid-space offset projected onto the screen's 2:1 isometric axes.
static func screen_delta(offset: Vector2) -> Vector2:
	return Vector2((offset.x - offset.y) * TILE_W * 0.5,
			(offset.x + offset.y) * TILE_H * 0.5)

## Where grid (0, 0) — the tile corner the footprint's north corner sits on —
## falls in the local space of the building node, for a given view rotation.
##
## Building.set_position_in_grid() places the node at
## `footprint centre - (size.x * 0.5, size.y)` and that anchor is fixed, while
## the footprint's projected centre swings around it as the view turns. This is
## the offset that reconciles the two, and it is what keeps the pixels on the
## tiles at every rotation.
static func grid_origin_offset(size: Vector2, view_facing: int) -> Vector2:
	var tiles := Vector2(size.x / TILE_W, size.y / TILE_H)
	var anchor := Vector2(size.x * 0.5, size.y)
	return anchor - screen_delta(rotate_uv(tiles * 0.5, view_facing))

## Grid point (u across, v down, z up) to local draw space.
static func project_point(origin: Vector2, p: Vector3, view_facing: int) -> Vector2:
	var r := rotate_uv(Vector2(p.x, p.y), view_facing)
	return origin + Vector2((r.x - r.y) * TILE_W * 0.5, (r.x + r.y) * TILE_H * 0.5 - p.z)

## Painter's-algorithm key: how near the viewer a plan position sits. Bigger
## draws later, on top.
static func depth_of(u: float, v: float, view_facing: int) -> float:
	var r := rotate_uv(Vector2(u, v), view_facing)
	return r.x + r.y

## How many tiles across and down a footprint in pixels is.
static func tiles_of(size: Vector2) -> Vector2:
	return Vector2(maxf(size.x / TILE_W, 1.0), maxf(size.y / TILE_H, 1.0))

## The four footprint corners of a building node, in its local draw space — the
## terrain's own tile corners for the rotation it is drawn at.
static func footprint_corners(size: Vector2, view_facing: int) -> PackedVector2Array:
	var origin := grid_origin_offset(size, view_facing)
	var tiles := tiles_of(size)
	return PackedVector2Array([
		project_point(origin, Vector3(0, 0, 0), view_facing),
		project_point(origin, Vector3(tiles.x, 0, 0), view_facing),
		project_point(origin, Vector3(tiles.x, tiles.y, 0), view_facing),
		project_point(origin, Vector3(0, tiles.y, 0), view_facing),
	])

## Draws one facility and returns the rectangle it covered in local draw space
## (world pixels). The placement ghost and the catalogue tile go through the
## same routine, so all three show the identical picture.
##
## `time` and `gloomy` are accepted for call-site compatibility with the
## drawing routine this replaced: pixel art does not animate, so they are
## unused.
static func draw_building(c: CanvasItem, kind_name: String, size: Vector2,
		tier := 1, _time := 0.0, _gloomy := false, view_facing := 0) -> Rect2:
	if kind_name == "bench":
		# The bench is a ground fixture, not a facility (see PathFurniture).
		var origin := grid_origin_offset(size, view_facing)
		var r := rotate_uv(Vector2(0.5, 0.7), view_facing)
		c.draw_set_transform(origin + Vector2((r.x - r.y) * TILE_W * 0.5,
				(r.x + r.y) * TILE_H * 0.5))
		PathFurniture.draw_item(c, "park_bench", Vector2i.DOWN)
		c.draw_set_transform(Vector2.ZERO)
		return Rect2(Vector2.ZERO, size)
	return BuildingSprites.draw(c, kind_name, size, tier, view_facing)
