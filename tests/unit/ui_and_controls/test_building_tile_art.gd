extends GameTest
## BuildingTileArt: the building example on a Buildings tab tile stands on the
## tile's own diamond.
##
## The catalogue shows the facility's pixel-art sprite — the same image the
## course draws — so a preview lines up with its tile button the way a placed
## building lines up with its course cells: the footprint diamond fills the
## middle of the tile diamond and the building rises over its own square. These
## tests hold the preview transform to that — every footprint lands concentric
## with the tile, the whole drawing stays as wide as its button, and the roof
## climbs no further than the notch gap the honeycomb leaves above the tile (see
## TileHoneycomb and the TerrainToolbar separations).

const TILE := TerrainTileButton.TILE_SIZE
## Nothing but a contact shadow may hang below the tile's bottom vertex; the
## honeycomb's inter-row gap absorbs that much overlap.
const BELOW_TILE_ALLOWANCE := 8.0

var registry: Dictionary = {}

func before_all() -> void:
	registry = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]

## The footprint of one catalogue entry, in the pixels the sprites are
## authored in.
func _footprint_of(building_type: String) -> Vector2:
	var dimensions: Array = registry[building_type].get("size", [1, 1])
	return Vector2(
		maxf(1.0, float(dimensions[0])) * BuildingTileArt.TILE_PIXEL_SIZE.x,
		maxf(1.0, float(dimensions[1])) * BuildingTileArt.TILE_PIXEL_SIZE.y)

## Where the sprite's painted pixels land on the tile, in button space. The
## preview draws through the same transform as the course, so start from the
## sprite's painted rect in draw space — BuildingSprites maps the source PNG's
## pixels into it, whatever resolution that PNG was authored at.
func _preview_bounds(building_type: String) -> Rect2:
	var placement := BuildingTileArt.preview_transform(_footprint_of(building_type))
	var painted := BuildingSprites.painted_rect(building_type, 1, 0)
	if painted.size.x <= 0.0:
		return Rect2()
	return Rect2(placement * painted.position, placement.get_scale() * painted.size)

func test_every_footprint_lands_on_the_tile_diamond() -> void:
	assert_gte(registry.size(), 16, "The catalogue has its buildings")
	for building_type in registry:
		var footprint := _footprint_of(building_type)
		var placement := BuildingTileArt.preview_transform(footprint)
		# The sprite's footprint centre projects to
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
		var bounds := _preview_bounds(building_type)
		assert_gt(bounds.size.x, 0.0, "%s draws its pixel art" % building_type)
		if bounds.size.x <= 0.0:
			continue
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

func test_the_preview_shows_the_courses_own_sprite() -> void:
	# The button is not a redrawing: it is the same image, scaled down.
	for building_type in registry:
		var tex := BuildingSprites.texture(building_type, 1, 0)
		assert_not_null(tex, "%s has a sprite to show" % building_type)
		var art := BuildingSprites.rect(building_type, 1, 0)
		var footprint := _footprint_of(building_type)
		# The sprite covers its footprint plus a little padding for eaves and
		# shadows; it is never a different building's size.
		assert_between(art.size.x, footprint.x * 0.5, footprint.x + 72.0,
			"%s: the sprite is as wide as its footprint" % building_type)
		assert_between(art.size.y, footprint.y * 0.5, footprint.y + 260.0,
			"%s: the sprite is as deep as its footprint" % building_type)

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
		assert_eq(preview.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"The preview keeps the pixel grid crisp")
		assert_eq(preview.building_footprint(), _footprint_of("snack_bar"),
			"The preview knows the footprint it stands on")
