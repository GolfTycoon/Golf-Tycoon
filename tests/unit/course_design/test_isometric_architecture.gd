extends GameTest
## Buildings stand on the grid's own isometric diamonds — now as pixel art.
##
## Every facility is one pre-rendered isometric sprite per upgrade tier and per
## quarter-turn of the view, projected in grid space (tiles across, tiles down,
## world pixels up) through the same 2:1 axes the terrain uses. These tests hold
## the renderer to that promise: the artwork covers the tiles the building
## occupies at every view rotation, every facility has its own image, and the
## clubhouse's upgrades grow upward rather than outward. See CourseArchitecture
## and BuildingSprites.

const POS := Vector2i(6, 6)

var grid: TerrainGrid
var entities: EntityLayer
var registry: Dictionary

func before_all() -> void:
	registry = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 32
	add_child_autofree(grid)
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	entities = EntityLayer.new()
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities

func _size_of(building_type: String) -> Vector2:
	var dimensions: Array = registry[building_type].get("size", [1, 1])
	return Vector2(float(dimensions[0]) * 64.0, float(dimensions[1]) * 32.0)

func _tiles_of(size: Vector2) -> Vector2:
	return size / Vector2(64.0, 32.0)

func _corners(tiles: Vector2) -> Array:
	return [Vector2(0, 0), Vector2(tiles.x, 0), Vector2(tiles.x, tiles.y), Vector2(0, tiles.y)]

## The node position Building.set_position_in_grid() gives a footprint here.
func _node_position(size: Vector2, tiles: Vector2) -> Vector2:
	return grid.grid_point_to_screen(Vector2(POS) + tiles * 0.5) - Vector2(size.x * 0.5, size.y)

## The rectangle a sprite actually paints, in the building node's local space:
## the manifest rect trimmed to the image's opaque pixels and scaled from art
## pixels to world pixels.
func _painted_rect(building_type: String, tier := 1, facing := 0) -> Rect2:
	var tex := BuildingSprites.texture(building_type, tier, facing)
	if tex == null:
		return Rect2()
	var used := tex.get_image().get_used_rect()
	var scale := float(BuildingSprites.manifest().get("pixel_scale", 2.0))
	var art := BuildingSprites.rect(building_type, tier, facing)
	return Rect2(art.position + Vector2(used.position) * scale,
			Vector2(used.size) * scale)

# ---------------------------------------------------------------------------
# The footprint sits on the tiles
# ---------------------------------------------------------------------------

func test_the_art_covers_exactly_the_tiles_a_building_stands_on() -> void:
	# The whole point of the renderer: a placed building's projected corners are
	# the terrain's own tile corners, so its square is the square it was placed
	# on — not a flat elevation laid across them. The sprite is authored in that
	# same space, so the corner maths is what anchors the pixels.
	for building_type in registry:
		var size := _size_of(building_type)
		var tiles := _tiles_of(size)
		for facing in range(4):
			grid.set_view_orientation(facing)
			var node_pos := _node_position(size, tiles)
			var origin := CourseArchitecture.grid_origin_offset(size, facing)
			for corner in _corners(tiles):
				var drawn := origin + CourseArchitecture.project_point(
						Vector2.ZERO, Vector3(corner.x, corner.y, 0), facing)
				var expected := grid.grid_point_to_screen(Vector2(POS) + corner) - node_pos
				assert_almost_eq(drawn.x, expected.x, 0.001,
					"%s at rotation %d: corner %s across" % [building_type, facing, corner])
				assert_almost_eq(drawn.y, expected.y, 0.001,
					"%s at rotation %d: corner %s down" % [building_type, facing, corner])

func test_every_placed_building_lands_on_its_tile_corners() -> void:
	# Exercise the real placement path: EntityLayer positions a building before
	# it enters the tree, while Building loads its data-driven footprint in
	# _ready(). Every building type must be re-anchored to that final footprint,
	# not just the 4x4 clubhouse whose size matches Building's default.
	for building_type in registry:
		var kind := str(building_type)
		var building := entities.place_building(kind, POS, registry)
		assert_not_null(building, "%s is placed" % kind)
		if building == null:
			continue

		var size := _size_of(kind)
		var tiles := _tiles_of(size)
		assert_eq(Vector2i(building.width, building.height), Vector2i(tiles),
			"%s loads its registered footprint" % kind)
		for facing in range(4):
			grid.set_view_orientation(facing)
			building.set_position_in_grid(POS)
			var origin := CourseArchitecture.grid_origin_offset(size, facing)
			for corner in _corners(tiles):
				var drawn := building.global_position + origin + CourseArchitecture.project_point(
						Vector2.ZERO, Vector3(corner.x, corner.y, 0), facing)
				var expected := grid.to_global(grid.grid_point_to_screen(Vector2(POS) + corner))
				assert_almost_eq(drawn.x, expected.x, 0.001,
					"%s rotation %d: corner %s across" % [kind, facing, corner])
				assert_almost_eq(drawn.y, expected.y, 0.001,
					"%s rotation %d: corner %s down" % [kind, facing, corner])

		entities.clear_all()
		await process_frames(1)

func test_the_projection_matches_the_grids_own_away_from_the_corners() -> void:
	# Interior tiles and lifted points — the wall tops and roof ridges the
	# renderer was authored from — project through the same transform.
	var tiles := Vector2(3, 2)
	var size := Vector2(tiles.x * 64.0, tiles.y * 32.0)
	for facing in range(4):
		grid.set_view_orientation(facing)
		var node_pos := _node_position(size, tiles)
		var origin := CourseArchitecture.grid_origin_offset(size, facing)
		for point in [Vector3(0, 0, 0), Vector3(1.5, 0.5, 0), Vector3(3, 2, 0),
				Vector3(0.5, 1.5, 40), Vector3(2.5, 2.0, 17)]:
			var drawn := node_pos + origin + CourseArchitecture.project_point(
					Vector2.ZERO, point, facing)
			var expected := grid.grid_point_to_screen(
					Vector2(POS) + Vector2(point.x, point.y)) - Vector2(0, point.z)
			assert_almost_eq(drawn.x, expected.x, 0.001,
				"rotation %d: %s across" % [facing, point])
			assert_almost_eq(drawn.y, expected.y, 0.001,
				"rotation %d: %s down" % [facing, point])

func test_rotating_the_view_turns_the_building_with_the_course() -> void:
	var building := entities.place_building("pub", POS, registry)
	var architecture: CourseArchitecture = building.get_node("Visual/Architecture")
	for facing in range(4):
		grid.set_view_orientation(facing)
		building.set_position_in_grid(POS)
		assert_eq(architecture.facing, facing,
			"the drawing follows the course round to rotation %d" % facing)

# ---------------------------------------------------------------------------
# Every facility is a pixel image on its own square
# ---------------------------------------------------------------------------

func test_every_facility_has_pixel_art_for_every_tier_and_rotation() -> void:
	for building_type in registry:
		var kind := str(building_type)
		assert_true(BuildingSprites.has_sprite(kind),
			"%s has pixel art" % kind)
		if not BuildingSprites.has_sprite(kind):
			continue
		assert_gte(BuildingSprites.tier_count(kind), 1, "%s has art tiers" % kind)
		for tier in range(1, BuildingSprites.tier_count(kind) + 1):
			for facing in range(4):
				var tex := BuildingSprites.texture(kind, tier, facing)
				assert_not_null(tex, "%s tier %d rotation %d has an image"
					% [kind, tier, facing])
				var art := BuildingSprites.rect(kind, tier, facing)
				assert_gt(art.size.x, 0.0, "%s tier %d rotation %d has a rect"
					% [kind, tier, facing])

func test_every_facility_is_drawn_with_its_own_architecture() -> void:
	# Distinct files: a kind with no design of its own would silently share
	# another facility's picture.
	var seen := {}
	for building_type in registry:
		var art := BuildingSprites.entry(building_type, 1, 0)
		assert_false(art.is_empty(), "%s has a catalogue image" % building_type)
		if art.is_empty():
			continue
		var file := str(art.get("file", ""))
		assert_false(seen.has(file), "%s has an image of its own" % building_type)
		seen[file] = building_type
		for tier in range(1, BuildingSprites.tier_count(building_type) + 1):
			for facing in range(4):
				assert_ne(BuildingSprites.texture(building_type, tier, facing),
					null, "%s has every rotation" % building_type)

func test_the_sprite_sits_on_the_buildings_own_tiles() -> void:
	# The pixels, not just the maths: the sprite's bottom edge lands on the
	# footprint's front corner and its top rises above the footprint, so the
	# picture is anchored to the tiles rather than floating over them.
	for building_type in registry:
		var kind := str(building_type)
		var size := _size_of(kind)
		for facing in range(4):
			var painted := _painted_rect(kind, 1, facing)
			assert_gt(painted.size.x, 0.0, "%s paints something at rotation %d"
				% [kind, facing])
			if painted.size.x <= 0.0:
				continue
			var corners := CourseArchitecture.footprint_corners(size, facing)
			var front := -INF
			var back := INF
			var left := INF
			var right := -INF
			for corner in corners:
				front = maxf(front, corner.y)
				back = minf(back, corner.y)
				left = minf(left, corner.x)
				right = maxf(right, corner.x)
			# A terrace sits a little inside the footprint and a roof eaves may
			# overhang it, but the picture is still the building on its square.
			assert_between(painted.end.y, front - 14.0, front + 2.0,
				"%s at rotation %d touches its front tiles" % [kind, facing])
			assert_between(painted.position.y, back - 120.0, back + 2.0,
				"%s at rotation %d rises over its own footprint" % [kind, facing])
			assert_between(painted.position.x, left - 10.0, left + 12.0,
				"%s at rotation %d stays on its west tiles" % [kind, facing])
			assert_between(painted.end.x, right - 12.0, right + 10.0,
				"%s at rotation %d stays on its east tiles" % [kind, facing])
			# The footprint's centre belongs to the building, not to the grass
			# behind it.
			var centre := CourseArchitecture.project_point(
				CourseArchitecture.grid_origin_offset(size, facing),
				Vector3(size.x / 128.0, size.y / 64.0, 0.0), facing)
			assert_true(painted.has_point(centre),
				"%s at rotation %d stands over its footprint centre" % [kind, facing])

func test_the_architecture_node_draws_the_sprite_with_nearest_filtering() -> void:
	var building := entities.place_building("pro_shop", POS, registry)
	var architecture: CourseArchitecture = building.get_node("Visual/Architecture")
	assert_not_null(architecture, "the building carries an Architecture node")
	if architecture == null:
		return
	assert_eq(architecture.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
		"the pixel art is drawn without smoothing")
	assert_eq(architecture.kind, "pro_shop", "the node knows what it draws")
	assert_eq(architecture.footprint, _size_of("pro_shop"), "and how big it is")

func test_the_clubhouse_grows_without_leaving_its_square() -> void:
	var tiles := _tiles_of(_size_of("clubhouse"))
	var heights: Array = []
	for tier in range(1, 4):
		var art: Dictionary = BuildingSprites.manifest()["buildings"]["clubhouse"]["tiers"][str(tier)]
		heights.append(float(art.get("height", 0.0)))
		for facing in range(4):
			var painted := _painted_rect("clubhouse", tier, facing)
			var corners := CourseArchitecture.footprint_corners(_size_of("clubhouse"), facing)
			var left := INF
			var right := -INF
			for corner in corners:
				left = minf(left, corner.x)
				right = maxf(right, corner.x)
			assert_between(painted.position.x, left - 10.0, left + 12.0,
				"tier %d at rotation %d covers its square" % [tier, facing])
			assert_between(painted.end.x, right - 12.0, right + 10.0,
				"tier %d at rotation %d covers its square" % [tier, facing])
	assert_eq(tiles, Vector2(4, 4), "the clubhouse keeps its footprint")
	# Each upgrade is visibly a bigger building, never a wider one.
	assert_gt(heights[1], heights[0], "The second tier is taller than the first")
	assert_gt(heights[2], heights[1], "The third tier is taller than the second")
