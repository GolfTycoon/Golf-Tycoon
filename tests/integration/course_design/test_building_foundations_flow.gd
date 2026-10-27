extends MainSceneTest
## Building construction, moves, undo/redo and a real save round trip must
## treat the changed ground as part of the building, not as extra paint steps.

const SHOP_TILE := Vector2i(48, 50)
const MOVE_TILE := Vector2i(69, 50)

var grid: TerrainGrid


func before_all() -> void:
	await super()
	await new_game("Foundation flow")
	grid = main.terrain_grid
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)


func _prepare_plot(origin: Vector2i, size: Vector2i) -> void:
	main._suppress_tile_undo = true
	for x in range(size.x):
		for y in range(size.y):
			var tile := origin + Vector2i(x, y)
			assert_true(GameManager.land_manager.is_tile_owned(tile))
			assert_false(main.entity_layer.is_tile_occupied_by_building(tile))
			grid.set_tile_natural(tile, TerrainTypes.Type.FAIRWAY)
	for x in range(size.x + 1):
		for y in range(size.y + 1):
			grid.set_vertex_elevation(origin + Vector2i(x, y),
					TerrainGrid.BASE_ELEVATION - 1 + (x + y) % 3)
	main._suppress_tile_undo = false
	main.undo_manager.clear()


func _assert_foundation(building: Building) -> void:
	var level: int = grid.get_elevation(building.grid_position)
	for tile in building.get_footprint():
		assert_eq(grid.get_tile(tile), TerrainTypes.Type.ROUGH)
		for vertex in grid.vertices_of_tile(tile):
			assert_eq(grid.get_vertex_elevation(vertex), level)


func test_placement_undo_redo_and_save_demolition_restore_the_original_plot() -> void:
	_prepare_plot(SHOP_TILE, Vector2i(2, 2))
	var terrain_before := grid.serialize()
	var elevation_before := grid.serialize_elevation()
	var markers_before := grid.serialize_player_placed()
	markers_before.sort()
	var cost: int = main.building_registry["pro_shop"]["cost"]
	main.placement_manager.start_building_placement("pro_shop", main.building_registry["pro_shop"])
	main._place_building(SHOP_TILE, cost)
	var shop: Building = main.entity_layer.get_building_at(SHOP_TILE)
	assert_not_null(shop)
	_assert_foundation(shop)
	assert_eq(main.undo_manager.undo_stack.size(), 1, "One placement is one undo action")
	assert_eq(main.undo_manager.undo_stack[0].type, "entity_place")
	# The first amenity can award a milestone; undo refunds the construction
	# price without reversing that separate reward.
	var money_after_placement := GameManager.money

	main._perform_undo()
	assert_null(main.entity_layer.get_building_at(SHOP_TILE))
	assert_eq(grid.serialize(), terrain_before)
	assert_eq(grid.serialize_elevation(), elevation_before)
	assert_eq(GameManager.money, money_after_placement + cost)
	assert_false(main.undo_manager.can_undo(), "There are no hidden per-tile actions")
	main._perform_redo()
	shop = main.entity_layer.get_building_at(SHOP_TILE)
	assert_not_null(shop)
	_assert_foundation(shop)
	assert_eq(main.undo_manager.undo_stack.size(), 1)
	assert_eq(GameManager.money, money_after_placement)

	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveManager._build_save_data()))
	SaveManager._apply_save_data(save)
	shop = main.entity_layer.get_building_at(SHOP_TILE)
	assert_not_null(shop, "The actual save/load path rebuilds the shop")
	_assert_foundation(shop)
	main.undo_manager.clear()
	main.entity_layer.remove_building(SHOP_TILE)
	assert_eq(grid.serialize(), terrain_before, "Demolition after loading restores the original ground")
	assert_eq(grid.serialize_elevation(), elevation_before, "and every original corner")
	var markers_after := grid.serialize_player_placed()
	markers_after.sort()
	assert_eq(markers_after, markers_before, "Construction does not add maintenance markers")
	assert_false(main.undo_manager.can_undo(), "Demolition does not create stray terrain actions")


func test_clubhouse_move_is_one_undoable_action() -> void:
	var clubhouse := CourseClubhouse.find(main.entity_layer)
	assert_not_null(clubhouse)
	var old_pos := clubhouse.grid_position
	_prepare_plot(MOVE_TILE, Vector2i(clubhouse.width, clubhouse.height))
	var terrain_before := grid.serialize()
	var elevation_before := grid.serialize_elevation()
	main._on_building_move_requested(clubhouse)
	main._handle_building_move_click(MOVE_TILE)
	assert_eq(clubhouse.grid_position, MOVE_TILE)
	_assert_foundation(clubhouse)
	assert_eq(main.undo_manager.undo_stack.size(), 1, "Moving produces only the building move")
	assert_eq(main.undo_manager.undo_stack[0].type, "building_move")

	main._perform_undo()
	assert_eq(clubhouse.grid_position, old_pos)
	assert_eq(grid.serialize(), terrain_before, "Undo returns both plots to their earlier state")
	assert_eq(grid.serialize_elevation(), elevation_before)
	assert_false(main.undo_manager.can_undo())
	main._perform_redo()
	assert_eq(clubhouse.grid_position, MOVE_TILE)
	_assert_foundation(clubhouse)
