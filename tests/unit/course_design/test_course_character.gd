extends GameTest
## Course character: the sculpting brush that shapes landforms (and what it must
## leave alone), clubhouse upgrades, golfer expressions and the building
## placement ghost.

## Elevation levels run 0..10 with flat ground mid-range at BASE_ELEVATION.
const BASE := TerrainGrid.BASE_ELEVATION

var grid: TerrainGrid

func before_each() -> void:
	super()
	GameManager.land_manager = null
	GameManager.is_paused = false
	GameManager.current_speed = GameManager.GameSpeed.NORMAL
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	for x in range(16):
		for y in range(16):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)

func test_sculpted_brush_tapers_preserves_surfaces_and_can_be_undone() -> void:
	grid.set_tile(Vector2i(8, 7), TerrainTypes.Type.WATER)
	grid.set_tile(Vector2i(7, 8), TerrainTypes.Type.OUT_OF_BOUNDS)
	var saved := grid.serialize()
	# A 9-wide brush centred on tile (8, 8) stamps around vertex (9, 9) with a
	# 4-vertex radius and a 3-step centre (the Rolling Hill/Hollow math, now
	# only used by course generation).
	var center := grid.nearest_vertex(Vector2(8, 8) + Vector2(0.5, 0.5))
	var changes := SculptedTerrain.stamp(grid, center, SculptedTerrain.sculpt_radius(9), 3, null)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 9)), BASE + 3)
	assert_eq(grid.get_vertex_elevation(Vector2i(12, 9)), BASE + 1)
	assert_eq(grid.get_vertex_elevation(Vector2i(13, 9)), BASE)
	assert_eq(grid.get_elevation(Vector2i(9, 9)), BASE + 3)
	assert_eq(grid.get_elevation(Vector2i(11, 9)), BASE + 1)
	assert_eq(grid.get_elevation(Vector2i(12, 9)), BASE)
	assert_eq(grid.get_elevation(Vector2i(8, 8)), BASE + 1)
	assert_eq(grid.get_elevation(Vector2i(8, 7)), BASE)
	assert_eq(grid.get_elevation(Vector2i(7, 8)), BASE)
	assert_eq(grid.get_vertex_elevation(Vector2i(9, 8)), BASE)
	assert_eq(grid.serialize(), saved)
	assert_eq(roundi(grid._course_surface._data.get_pixel(9, 9).b * 10.0), BASE + 3)
	var heights := grid.serialize_elevation()
	grid.deserialize_elevation(heights)
	assert_eq(grid.get_elevation(Vector2i(9, 9)), BASE + 3)
	assert_eq(roundi(grid._course_surface._data.get_pixel(9, 9).b * 10.0), BASE + 3)
	for i in range(changes.size() - 1, -1, -1):
		var change = changes[i]
		grid.set_vertex_elevation(change.position, change.old_elevation)
	assert_eq(grid.get_elevation(Vector2i(9, 9)), BASE)
	assert_eq(grid.get_elevation(Vector2i(8, 8)), BASE)
	grid.deserialize_elevation({})
	assert_eq(roundi(grid._course_surface._data.get_pixel(9, 9).b * 10.0), BASE)

func test_sculpting_respects_buildings_and_height_limits() -> void:
	var entities := EntityLayer.new()
	entities.map_seed = 1234
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	entities.place_building("clubhouse", Vector2i(6, 6), registry)
	SculptedTerrain.stamp(grid, Vector2i(8, 8), 5, 3, entities)
	assert_eq(grid.get_vertex_elevation(Vector2i(8, 8)), BASE)
	assert_eq(grid.get_elevation(Vector2i(8, 8)), BASE)
	# Just outside the footprint the same stamp still lifts the ground.
	assert_eq(grid.get_vertex_elevation(Vector2i(5, 8)), BASE + 1)
	grid.set_elevation(Vector2i(3, 3), BASE + 4)
	assert_eq(grid.get_vertex_elevation(Vector2i(3, 3)), BASE + 4)
	SculptedTerrain.stamp(grid, Vector2i(3, 3), 3, 3)
	assert_eq(grid.get_vertex_elevation(Vector2i(3, 3)), grid.MAX_ELEVATION)
	assert_eq(grid.get_elevation(Vector2i(3, 3)), grid.MAX_ELEVATION)
	SculptedTerrain.stamp(grid, Vector2i(3, 3), 3, -20)
	assert_eq(grid.get_vertex_elevation(Vector2i(3, 3)), grid.MIN_ELEVATION)
	assert_eq(grid.get_elevation(Vector2i(3, 3)), grid.MIN_ELEVATION)

func test_clubhouse_upgrades_grow_without_changing_footprint_or_duplicate_clicks() -> void:
	var building := Building.new()
	add_child_autofree(building)
	var previous_height := 0.0
	for level in range(1, 4):
		building.upgrade_level = level
		building._update_visuals()
		assert_eq(building.get_node("Visual/Architecture").level, level)
		var architecture = building.get_node("Visual/Architecture")
		# Each upgrade swaps in the next tier's pixel art: taller, same square.
		var texture := BuildingSprites.texture("clubhouse", level, architecture.facing)
		assert_not_null(texture, "tier %d has its own pixel art" % level)
		var tier_height := float(BuildingSprites.manifest()["buildings"]["clubhouse"]
			["tiers"][str(level)].get("height", 0.0))
		assert_gt(tier_height, previous_height)
		previous_height = tier_height
		assert_eq(architecture.footprint, Vector2(256, 128))
		var clicks := 0
		var visuals := 0
		for child in building.get_children():
			if child is Area2D: clicks += 1
			if child.name == "Visual": visuals += 1
		assert_eq(clicks, 1)
		assert_eq(visuals, 1)
		await process_frames(1)

func test_golfer_expression_does_not_move_actor_or_delay_next_shot() -> void:
	var golfer = load("res://scenes/entities/golfer.tscn").instantiate()
	add_child_autofree(golfer)
	golfer.set_process(false)
	var expression: GolferExpression = golfer._expression
	expression.set_process(false)
	var position_before: Vector2 = golfer.position
	var score_before: int = golfer.current_strokes
	expression.react_to_score(-1)
	expression._process(0.1)
	assert_lt(expression.position.y, 0.0)
	assert_eq(golfer.position, position_before)
	assert_eq(golfer.current_strokes, score_before)
	GameManager.is_paused = true
	var remaining := expression._reaction_remaining
	expression._process(1.0)
	assert_eq(expression._reaction_remaining, remaining)
	GameManager.is_paused = false
	golfer.current_state = Golfer.State.PREPARING_SHOT
	expression._process(0.1)
	assert_eq(expression._reaction_remaining, 0.0)
	assert_eq(golfer.preparation_time, 0.0)
	assert_eq(GolferExpression.reaction_for_score(2), -1)
	assert_eq(GolferExpression.reaction_for_score(0), 0)

func test_building_ghost_matches_facility_and_clears_when_preview_ends() -> void:
	var manager = autofree(PlacementManager.new())
	manager.selected_building_type = "resort_hotel"
	manager.placement_mode = PlacementManager.PlacementMode.BUILDING
	manager.current_placement_data = {"size": [4, 4]}
	var preview := PlacementPreview.new()
	add_child_autofree(preview)
	preview.set_process(false)
	preview.placement_manager = manager
	preview.terrain_grid = null
	preview._draw_building_ghost(Vector2i(120, 80), Color(0.3, 0.9, 0.3, 0.4))
	assert_eq(preview._building_ghost.kind, "resort_hotel")
	assert_eq(preview._building_ghost.position, Vector2(120, 80))
	assert_almost_eq(preview._building_ghost.modulate.a, 0.4, 0.001)
	assert_true(preview._building_ghost.visible)
	# With no terrain/active preview, drawing must hide the previous building.
	preview._draw()
	assert_false(preview._building_ghost.visible)
