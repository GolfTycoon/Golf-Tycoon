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
## turn with the course instead of being seen side-on. `angle_offset` carries
## the angle between `facing` and the exact view while Gradual View Rotation has
## the course between two of them: the picture is then sheared on to the angled
## tiles (see BuildingSprites.draw_warped()).

var kind := "clubhouse"
var footprint := Vector2(256, 128)
var level := 1
var facing := 0
## How far the course's exact view angle sits from `facing`, in quarter turns,
## from -0.5 to 0.5 (TerrainGrid.get_view_angle_offset()). Zero draws the
## quarter-turn picture exactly as it always has; anything else shears the
## picture on to the course at the angle in between (see draw_warped()).
var angle_offset: float = 0.0

## Close enough to a quarter turn to use the untouched sprite.
const WARP_EPSILON := 0.0005

## The strongest shear a picture is drawn with. Approaching the halfway point
## between two quarter-turn pictures the projection squeezes one whole wall face
## to a line, and shearing the picture all the way would fold it over itself.
## Stopping short keeps the building readable; the last few degrees of base sit
## a little off the tiles, and the picture changes at the halfway point anyway.
const MAX_WARP_OFFSET := 0.4

## The shear actually applied for a view offset, stopped short of the halfway
## point (see MAX_WARP_OFFSET).
static func clamp_warp(offset: float) -> float:
	return clampf(offset, -MAX_WARP_OFFSET, MAX_WARP_OFFSET)

func _ready() -> void:
	add_to_group("course_architecture")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func _draw() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if absf(angle_offset) < WARP_EPSILON:
		BuildingSprites.draw(self, kind, footprint, level, facing)
	else:
		BuildingSprites.draw_warped(self, kind, footprint, level, facing, angle_offset)


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

## The footprint's centre in local draw space — the fixed point a building's
## art, click silhouette and gradual-turn shear all turn around.
static func footprint_pivot(size: Vector2) -> Vector2:
	return Vector2(size.x * 0.5, size.y)

# ===========================================================================
# GRADUAL TURNS
# ===========================================================================

## The linear map that carries a screen offset drawn at one quarter turn to the
## same ground offset at `residual` quarter turns away from it.
##
## A quarter turn is the projection of one 90° turn of the grid, so the
## in-between map is `P · R(residual) · P⁻¹` where P is the 2:1 projection. It
## keeps the ground where the terrain draws it, and is the identity at 0.
static func warp_matrix(residual: float) -> Transform2D:
	var angle := residual * PI * 0.5
	var c := cos(angle)
	var s := sin(angle)
	return Transform2D(Vector2(c, s * 0.5), Vector2(-2.0 * s, c), Vector2.ZERO)

## The front ground edges of a footprint at `view_facing`, as two lines
## `y = m x + b` meeting at the footprint's bottom corner. A building's base
## sits on these, so they are the ground line each vertical column of the
## drawing stands on.
static func ground_lines(size: Vector2, view_facing: int) -> Dictionary:
	var corners := footprint_corners(size, view_facing)
	if corners.size() < 4:
		return {}
	var bottom := 0
	for i in range(1, corners.size()):
		if corners[i].y > corners[bottom].y:
			bottom = i
	var left: Vector2 = corners[(bottom + corners.size() - 1) % corners.size()]
	var bottom_corner: Vector2 = corners[bottom]
	var right: Vector2 = corners[(bottom + 1) % corners.size()]
	if left.x > right.x:
		var swap := left
		left = right
		right = swap
	var left_m := _line_slope(left, bottom_corner)
	var right_m := _line_slope(bottom_corner, right)
	return {
		"hinge_x": bottom_corner.x,
		"left_m": left_m,
		"left_b": left.y - left_m * left.x,
		"right_m": right_m,
		"right_b": bottom_corner.y - right_m * bottom_corner.x,
	}

## The ground height under the footprint at local `x`, on the front ground
## edges (see ground_lines()).
static func ground_y(lines: Dictionary, x: float) -> float:
	if lines.is_empty():
		return 0.0
	if x <= float(lines["hinge_x"]):
		return float(lines["left_m"]) * x + float(lines["left_b"])
	return float(lines["right_m"]) * x + float(lines["right_b"])

## How far the vertical column at local `x` moves when the view is `residual`
## quarter turns from `facing`: the ground point under it is carried by
## warp_matrix(), and the column above it keeps its height.
static func column_warp(x: float, lines: Dictionary, pivot: Vector2,
		matrix: Transform2D) -> Vector2:
	var base_y := ground_y(lines, x)
	var ground := pivot + matrix * (Vector2(x, base_y) - pivot)
	return Vector2(ground.x - x, ground.y - base_y)

## The sheared position of one point of the drawing. Verticals stay vertical:
## a point moves with the ground under its column, not with its own height.
static func warp_point(point: Vector2, size: Vector2, view_facing: int,
		residual: float) -> Vector2:
	var lines := ground_lines(size, view_facing)
	if lines.is_empty():
		return point
	return point + column_warp(point.x, lines, footprint_pivot(size),
		warp_matrix(clamp_warp(residual)))

static func _line_slope(from: Vector2, to: Vector2) -> float:
	if absf(to.x - from.x) < 0.0001:
		return 0.0
	return (to.y - from.y) / (to.x - from.x)

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
