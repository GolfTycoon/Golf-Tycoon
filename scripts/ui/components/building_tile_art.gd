extends Node2D
class_name BuildingTileArt
## Small footprint-aware building preview used by BuildingTileButton.
##
## Building catalogue buttons use the same diamond footprint as the terrain
## swatches, but keep the existing course-architecture drawings as their icon.
## The preview is deliberately compact so it stays inside the diamond while
## leaving the button caption readable on top.

const PREVIEW_SIZE := TerrainTileButton.TILE_SIZE
const TILE_PIXEL_SIZE := Vector2(64, 32)
## The preview was tuned for an 84px-wide diamond; scale it with the tile.
const PREVIEW_SCALE := PREVIEW_SIZE.x / 84.0

var building_type := ""
var building_data: Dictionary = {}

func configure(kind: String, data: Dictionary) -> void:
	building_type = kind
	building_data = data.duplicate(true)
	queue_redraw()

## The transform that stands a footprint's drawing on the tile. The button is
## its diamond, and the building must line up with it the way a placed
## building lines up with its course cells: CourseArchitecture projects a
## footprint's centre to (footprint.x * 0.5, footprint.y) in its own draw
## space — not the middle of its bounding rect — so that is the point that goes
## on the tile diamond's centre. The footprint then fills the middle of the
## diamond and the building rises over its own square, the roof reaching into
## the notch gap the honeycomb leaves above the tile.
static func preview_transform(footprint: Vector2) -> Transform2D:
	var scale_factor := minf(0.34, 66.0 / maxf(footprint.x, 1.0)) * PREVIEW_SCALE
	return Transform2D(Vector2(scale_factor, 0.0), Vector2(0.0, scale_factor),
		PREVIEW_SIZE * 0.5 - Vector2(footprint.x * 0.5, footprint.y) * scale_factor)

func _draw() -> void:
	if building_type.is_empty():
		return

	var dimensions: Array = building_data.get("size", [1, 1])
	if dimensions.size() < 2:
		return

	var footprint := Vector2(
		maxf(1.0, float(dimensions[0])) * TILE_PIXEL_SIZE.x,
		maxf(1.0, float(dimensions[1])) * TILE_PIXEL_SIZE.y)
	# CourseArchitecture draws its own depth and roof overhang, so the complete
	# footprint — not just its facade — fills the middle of the diamond.
	var placement := preview_transform(footprint)
	draw_set_transform(placement.origin, 0.0, placement.get_scale())
	CourseArchitecture.draw_building(self, building_type, footprint)
	draw_set_transform(Vector2.ZERO)
