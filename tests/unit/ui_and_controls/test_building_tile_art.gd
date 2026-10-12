extends GameTest
## BuildingTileArt: the building example on a Buildings tab tile stands on the
## tile's own diamond.
##
## The catalogue reuses the course's architecture drawings, so a preview lines
## up with its tile button the way a placed building lines up with its course
## cells: the footprint diamond fills the middle of the tile diamond and the
## building rises over its own square. These tests hold the preview transform
## to that — every footprint lands concentric with the tile, the whole drawing
## stays as wide as its button, and the roof climbs no further than the notch
## gap the honeycomb leaves above the tile (see TileHoneycomb and the
## TerrainToolbar separations).

const TILE := TerrainTileButton.TILE_SIZE
## Nothing but a contact shadow may hang below the tile's bottom vertex; the
## honeycomb's inter-row gap absorbs that much overlap.
const BELOW_TILE_ALLOWANCE := 8.0

var registry: Dictionary = {}


func before_all() -> void:
	registry = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]


## Draws facilities the way the catalogue does — from inside a real `_draw()`,
## under the preview transform — and reports the grid-space box each one
## covered (see test_isometric_architecture.gd for the same pattern on the
## course).
class Painter extends Node2D:
	var kind := ""
	var footprint := Vector2.ZERO
	var extent := AABB()

	func _draw() -> void:
		var placement := BuildingTileArt.preview_transform(footprint)
		draw_set_transform(placement.origin, 0.0, placement.get_scale())
		extent = CourseArchitecture.draw_building(self, kind, footprint)
		draw_set_transform(Vector2.ZERO)


## The footprint of one catalogue entry, in the pixels draw_building is given.
func _footprint_of(building_type: String) -> Vector2:
	var dimensions: Array = registry[building_type].get("size", [1, 1])
	return Vector2(
		maxf(1.0, float(dimensions[0])) * BuildingTileArt.TILE_PIXEL_SIZE.x,
		maxf(1.0, float(dimensions[1])) * BuildingTileArt.TILE_PIXEL_SIZE.y)


func _draw_extent(building_type: String) -> AABB:
	var painter := Painter.new()
	painter.kind = building_type
	painter.footprint = _footprint_of(building_type)
	add_child_autofree(painter)
	await process_frames(2)
	return painter.extent


## The four sides of a grid-space box, projected into tile space the way
## CourseArchitecture draws it — through the grid's draw-space origin and the
## preview transform — giving the screen-space bounds of a preview drawing.
func _projected_bounds(extent: AABB, footprint: Vector2, placement: Transform2D) -> Rect2:
	var draw_origin := CourseArchitecture.grid_origin_offset(footprint, 0)
	var bounds := Rect2()
	var first := true
	for u in [extent.position.x, extent.end.x]:
		for v in [extent.position.y, extent.end.y]:
			for z in [extent.position.z, extent.end.z]:
				var corner: Vector2 = placement * (draw_origin \
					+ Vector2((u - v) * 32.0, (u + v) * 16.0 - z))
				if first:
					bounds = Rect2(corner, Vector2.ZERO)
					first = false
				else:
					bounds = bounds.expand(corner)
	return bounds


func test_every_footprint_lands_on_the_tile_diamond() -> void:
	assert_gte(registry.size(), 16, "The catalogue has its buildings")
	for building_type in registry:
		var footprint := _footprint_of(building_type)
		var placement := BuildingTileArt.preview_transform(footprint)
		# CourseArchitecture projects a footprint's centre to
		# (footprint.x * 0.5, footprint.y) in its own draw space. That point
		# belongs on the tile diamond's centre, so the example stands on its
		# button instead of hanging off its bottom vertex.
		var footprint_centre := placement * Vector2(footprint.x * 0.5, footprint.y)
		assert_almost_eq(footprint_centre.x, TILE.x * 0.5, 0.01,
			"%s: the footprint is centred across the tile" % building_type)
		assert_almost_eq(footprint_centre.y, TILE.y * 0.5, 0.01,
			"%s: the footprint is centred down the tile" % building_type)
		# The footprint's own corners then sit on a diamond concentric with the
		# tile's, scaled to the footprint — not on some other anchor.
		var top_corner := placement * Vector2(footprint.x * 0.5, footprint.y * 0.5)
		assert_almost_eq(top_corner.y, TILE.y * 0.5 - footprint.y * 0.5 * placement.get_scale().y,
			0.01, "%s: the footprint's top corner keeps the diamond's shape" % building_type)
		var left_corner := placement * Vector2(0.0, footprint.y)
		assert_almost_eq(left_corner.x, TILE.x * 0.5 - footprint.x * 0.5 * placement.get_scale().x,
			0.01, "%s: the footprint's left corner keeps the diamond's shape" % building_type)


func test_every_preview_stays_on_its_button() -> void:
	for building_type in registry:
		var footprint := _footprint_of(building_type)
		var placement := BuildingTileArt.preview_transform(footprint)
		var bounds := _projected_bounds(await _draw_extent(building_type), footprint, placement)
		assert_true(bounds.position.x >= -0.5 and bounds.end.x <= TILE.x + 0.5,
			"%s: the drawing is no wider than its tile (%s..%s of %s)" % [
				building_type, bounds.position.x, bounds.end.x, TILE.x])
		# The roof may climb into the V-shaped notch gap above the tile — the
		# honeycomb keeps that much daylight between interlocking rows — but no
		# further, or the example would sit on the row above.
		assert_true(bounds.position.y >= -float(TerrainToolbar.TILE_V_SEPARATION),
			"%s: the drawing rises at most into the notch gap above the tile (top %s)" % [
				building_type, bounds.position.y])
		assert_true(bounds.end.y <= TILE.y + BELOW_TILE_ALLOWANCE,
			"%s: nothing but a shadow reaches below the tile (bottom %s)" % [
				building_type, bounds.end.y])


func test_the_button_draws_its_preview_over_the_button_space() -> void:
	var button := BuildingTileButton.new()
	# The toolbar configures a building tile before it joins the tree, so the
	# preview is built with its data (the test exercises the same order).
	button.configure_building("snack_bar", registry["snack_bar"])
	add_child_autofree(button)
	await process_frames(2)
	var preview: BuildingTileArt = button.get_node_or_null("BuildingPreview")
	assert_not_null(preview, "The building tile carries a preview")
	if preview:
		assert_eq(preview.position, Vector2.ZERO,
			"The preview's draw space starts at the button's corner")
		assert_eq(BuildingTileArt.PREVIEW_SIZE, button.button_size(),
			"The preview spans the whole diamond the button is")
