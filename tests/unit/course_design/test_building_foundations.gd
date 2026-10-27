extends GameTest
## Building foundations level shared vertices and hide the original terrain.
## Moving, demolition and save/load must put that ground back exactly, without
## disturbing neighbouring foundations or adding phantom terrain undo steps.

const BASE := TerrainGrid.BASE_ELEVATION

var grid: TerrainGrid
var entities: EntityLayer
var registry: Dictionary


func before_each() -> void:
	super()
	GameManager.land_manager = null
	grid = make_grid(20, 20)
	entities = make_entity_layer(grid)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities
	registry = ContentRegistry.get_buildings()
	entities.building_registry = registry


func _levelled(building: Building, expected: int) -> void:
	for tile in building.get_footprint():
		assert_eq(grid.get_tile(tile), TerrainTypes.Type.ROUGH, "%s is rough" % tile)
		for vertex in grid.vertices_of_tile(tile):
			assert_eq(grid.get_vertex_elevation(vertex), expected, "%s is level" % vertex)


func _sorted(values: Array) -> Array:
	var result := values.duplicate()
	result.sort()
	return result


func _save_grid_and_entities() -> Dictionary:
	return JSON.parse_string(JSON.stringify({
		"terrain": grid.serialize(),
		"vertices": grid.serialize_elevation(),
		"player_placed": grid.serialize_player_placed(),
		"cups": grid.serialize_cup_tiles(),
		"paths": grid.serialize_walking_paths(),
		"entities": entities.serialize(),
	}))


func _load_grid_and_entities(data: Dictionary) -> void:
	grid.deserialize(data["terrain"])
	grid.deserialize_elevation(data["vertices"])
	grid.deserialize_player_placed(data["player_placed"])
	grid.deserialize_cup_tiles(data["cups"])
	grid.deserialize_walking_paths(data["paths"])
	entities.deserialize(data["entities"])


func test_placement_and_demolition_restore_exact_vertices_and_ground_metadata() -> void:
	var origin := Vector2i(4, 4)
	grid.set_tile_natural(origin, TerrainTypes.Type.GREEN)
	grid.add_cup_tile(origin)
	grid.set_tile_natural(origin + Vector2i(0, 1), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(origin + Vector2i(0, 1), true)
	grid.set_tile(origin + Vector2i(1, 0), TerrainTypes.Type.FAIRWAY)
	for x in range(4, 7):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), BASE - 2 + (x + y) % 4)
	var terrain_before := grid.serialize()
	var elevation_before := grid.serialize_elevation()
	var placed_before := _sorted(grid.serialize_player_placed())
	var cups_before := _sorted(grid.serialize_cup_tiles())
	var paths_before := _sorted(grid.serialize_walking_paths())
	var target := grid.get_elevation(origin)

	var shop := entities.place_building("pro_shop", origin, registry)
	assert_not_null(shop)
	_levelled(shop, target)
	assert_eq(_sorted(grid.serialize_player_placed()), placed_before,
		"Foundation work does not invent maintenance tiles")
	var expected_position := grid.grid_point_to_screen(Vector2(origin) + Vector2(1, 1)) \
			- Vector2(float(grid.tile_width), float(grid.tile_height * 2))
	assert_eq(shop.global_position, expected_position, "The drawing is re-anchored after leveling")

	entities.remove_building(origin + Vector2i(1, 1))
	assert_eq(grid.serialize(), terrain_before, "Every original terrain type returns")
	assert_eq(grid.serialize_elevation(), elevation_before, "Every shared corner returns exactly")
	assert_eq(_sorted(grid.serialize_player_placed()), placed_before, "Maintenance markers return")
	assert_eq(_sorted(grid.serialize_cup_tiles()), cups_before, "The original cup returns")
	assert_eq(_sorted(grid.serialize_walking_paths()), paths_before, "The original path returns")


func test_equal_tile_averages_do_not_hide_an_uneven_foundation() -> void:
	var origin := Vector2i(4, 4)
	for x in range(4, 7):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), BASE - 1 if (x + y) % 2 == 0 else BASE + 1)
	for x in range(2):
		for y in range(2):
			var tile := origin + Vector2i(x, y)
			grid.set_tile_natural(tile, TerrainTypes.Type.ROUGH)
			assert_eq(grid.get_elevation(tile), BASE, "Each rounded tile average is already equal")
	var before := grid.serialize_elevation()
	var shop := entities.place_building("pro_shop", origin, registry)
	_levelled(shop, BASE)
	entities.remove_building(origin)
	assert_eq(grid.serialize_elevation(), before, "The checkerboard corners are restored")


func test_overlapping_move_then_removal_restores_both_footprints() -> void:
	var origin := Vector2i(4, 4)
	var destination := origin + Vector2i(1, 0)
	for x in range(4, 8):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), BASE - 1 + (x + y) % 4)
	for x in range(4, 7):
		for y in range(4, 6):
			grid.set_tile_natural(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	var terrain_before := grid.serialize()
	var elevation_before := grid.serialize_elevation()
	var shop := entities.place_building("pro_shop", origin, registry)
	assert_true(entities.move_building(shop, destination))
	assert_eq(grid.get_tile(origin), TerrainTypes.Type.FAIRWAY, "The part left behind is restored")
	_levelled(shop, grid.get_elevation(destination))
	var expected_position := grid.grid_point_to_screen(Vector2(destination) + Vector2(1, 1)) \
			- Vector2(float(grid.tile_width), float(grid.tile_height * 2))
	assert_eq(shop.global_position, expected_position, "The moved drawing sits on its new level")
	entities.remove_building(destination)
	assert_eq(grid.serialize(), terrain_before)
	assert_eq(grid.serialize_elevation(), elevation_before, "No corner is lost in the overlap")


func _neighbour_fixture() -> Array[Building]:
	for x in range(4, 9):
		for y in range(4, 7):
			var height := 4 if x <= 5 else (6 if x == 6 else 8)
			grid.set_vertex_elevation(Vector2i(x, y), height)
	var first := entities.place_building("pro_shop", Vector2i(4, 4), registry)
	var second := entities.place_building("snack_bar", Vector2i(6, 4), registry)
	return [first, second]


func test_touching_buildings_share_a_level_and_restore_it_in_either_order() -> void:
	# Record the heightfield before laying either foundation.
	for x in range(4, 9):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), 4 if x <= 5 else (6 if x == 6 else 8))
	var before := grid.serialize_elevation()
	var buildings := _neighbour_fixture()
	_levelled(buildings[0], 4)
	_levelled(buildings[1], 4)
	entities.remove_building(buildings[0].grid_position)
	_levelled(buildings[1], 4)
	entities.remove_building(buildings[1].grid_position)
	assert_eq(grid.serialize_elevation(), before, "The shared edge is restored after its last owner leaves")

	buildings = _neighbour_fixture()
	entities.remove_building(buildings[1].grid_position)
	_levelled(buildings[0], 4)
	entities.remove_building(buildings[0].grid_position)
	assert_eq(grid.serialize_elevation(), before, "The reverse demolition order also restores every corner")


func test_saved_shared_foundation_keeps_the_original_edge_after_its_neighbour_leaves() -> void:
	for x in range(4, 9):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), 4 if x <= 5 else (6 if x == 6 else 8))
	var before := grid.serialize_elevation()
	var buildings := _neighbour_fixture()
	entities.remove_building(buildings[0].grid_position)
	var saved := _save_grid_and_entities()
	_load_grid_and_entities(saved)
	var remaining := entities.get_building_at(Vector2i(6, 4))
	assert_not_null(remaining)
	_levelled(remaining, 4)
	entities.remove_building(remaining.grid_position)
	assert_eq(grid.serialize_elevation(), before, "The last saved owner remembers the original shared edge")


func test_conflicting_neighbour_heights_are_rejected_without_changes() -> void:
	for x in range(3, 10):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), 3 if x <= 5 else (8 if x >= 7 else 5))
	var first := entities.place_building("pro_shop", Vector2i(3, 4), registry)
	var second := entities.place_building("snack_bar", Vector2i(7, 4), registry)
	_levelled(first, 3)
	_levelled(second, 8)
	var target := Vector2i(5, 4)
	var heights := grid.serialize_elevation()
	var terrain := grid.serialize()
	var manager: PlacementManager = autofree(PlacementManager.new())
	manager.start_building_placement("snack_bar", registry["snack_bar"])
	assert_string_contains(manager.get_placement_error(target, grid), "different elevations")
	assert_null(entities.place_building("snack_bar", target, registry))
	assert_eq(grid.serialize_elevation(), heights, "Rejected placement does not move either foundation")
	assert_eq(grid.serialize(), terrain)
	assert_false(entities.move_building(first, second.grid_position), "A direct move cannot overlap another building")
	assert_eq(first.grid_position, Vector2i(3, 4))


func test_json_save_load_preserves_foundations_and_round_trips_the_live_ground() -> void:
	var origin := Vector2i(4, 4)
	grid.set_tile_natural(origin, TerrainTypes.Type.FAIRWAY)
	grid.set_vertex_elevation(origin + Vector2i(1, 0), BASE + 3)
	grid.set_vertex_elevation(origin + Vector2i(2, 2), BASE - 2)
	var terrain_before := grid.serialize()
	var elevation_before := grid.serialize_elevation()
	entities.place_building("pro_shop", origin, registry)
	# An older generator could paint over an occupied tile. Loading a snapshot
	# must reproduce the saved course, not silently repaint it a second time.
	grid.set_tile_natural(origin + Vector2i(1, 1), TerrainTypes.Type.FLOWER_BED)
	var live_terrain := grid.serialize()
	var live_elevation := grid.serialize_elevation()
	var saved := _save_grid_and_entities()
	_load_grid_and_entities(saved)
	assert_eq(grid.serialize(), live_terrain, "Loading does not repaint the saved course")
	assert_eq(grid.serialize_elevation(), live_elevation, "Loading does not re-level the saved course")
	entities.remove_building(origin)
	assert_eq(grid.serialize(), terrain_before, "Demolition restores the pre-construction ground")
	assert_eq(grid.serialize_elevation(), elevation_before, "and the pre-construction corners")


func test_old_saves_without_foundation_data_are_still_loadable() -> void:
	var origin := Vector2i(4, 4)
	grid.set_tile_natural(origin, TerrainTypes.Type.FAIRWAY)
	grid.set_vertex_elevation(origin + Vector2i(1, 0), BASE + 2)
	var terrain_before := grid.serialize()
	var elevation_before := grid.serialize_elevation()
	entities.deserialize({"buildings": {"4,4": {"type": "pro_shop"}}})
	var shop := entities.get_building_at(origin)
	assert_not_null(shop)
	_levelled(shop, grid.get_elevation(origin))
	entities.remove_building(origin)
	assert_eq(grid.serialize(), terrain_before)
	assert_eq(grid.serialize_elevation(), elevation_before)


func test_foundation_tile_changes_still_notify_renderers_but_not_terrain_undo() -> void:
	var seen: Array = []
	grid.tile_changed.connect(func(_pos: Vector2i, _old: int, _new: int) -> void:
		seen.append(grid.tile_change_records_undo))
	grid.begin_batch()
	entities.place_building("pro_shop", Vector2i(4, 4), registry)
	grid.set_tile(Vector2i(10, 10), TerrainTypes.Type.FAIRWAY)
	grid.end_batch()
	assert_eq(seen.size(), 5, "All four foundation tiles and the independent edit are announced")
	assert_eq(seen.count(false), 4, "Foundation notifications remain non-undoable after batching")
	assert_eq(seen.count(true), 1, "The independent terrain edit stays undoable")
	assert_true(grid.tile_change_records_undo, "The notification context is restored")


func test_forced_demolition_removes_the_required_building_node() -> void:
	var clubhouse := entities.place_building("clubhouse", Vector2i(4, 4), registry)
	entities.remove_building(clubhouse.grid_position, true)
	assert_true(clubhouse.is_queued_for_deletion(), "Forced teardown also destroys the required node")
	assert_true(entities.get_all_buildings().is_empty())


func test_legacy_save_with_a_building_between_different_levels_keeps_every_building() -> void:
	for x in range(3, 10):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), 3 if x <= 5 else (8 if x >= 7 else 5))
	var before := grid.serialize_elevation()
	# Before foundations existed, buildings could be saved on sloping and
	# differently elevated ground. The bridge is deliberately read last.
	entities.deserialize({"buildings": {
		"3,4": {"type": "pro_shop"},
		"7,4": {"type": "snack_bar"},
		"5,4": {"type": "snack_bar"},
	}})
	var first := entities.get_building_at(Vector2i(3, 4))
	var second := entities.get_building_at(Vector2i(7, 4))
	var bridge := entities.get_building_at(Vector2i(5, 4))
	assert_not_null(first)
	assert_not_null(second)
	assert_not_null(bridge, "Loading must not discard the saved bridge building")
	if first == null or second == null or bridge == null:
		return
	var level := grid.get_elevation(first.grid_position)
	_levelled(first, level)
	_levelled(second, level)
	_levelled(bridge, level)
	entities.remove_building(first.grid_position)
	entities.remove_building(second.grid_position)
	entities.remove_building(bridge.grid_position)
	assert_eq(grid.serialize_elevation(), before, "Original shared vertices survive legacy migration")


func test_building_ghost_sits_at_the_height_the_foundation_will_take() -> void:
	var origin := Vector2i(4, 4)
	for x in range(4, 7):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), 2 + (x - 4) * 4)
	var preview := PlacementPreview.new()
	add_child_autofree(preview)
	preview.set_process(false)
	preview.terrain_grid = grid
	preview._draw_building_ghost_shape(origin, "pro_shop", Vector2i(2, 2), Color.WHITE)
	var ghost_position: Vector2 = preview._building_ghost.position
	var shop := entities.place_building("pro_shop", origin, registry)
	assert_eq(ghost_position, shop.global_position, "The ghost lands on the same level as the building")


func test_moving_ghost_accounts_for_the_ground_restored_under_an_overlap() -> void:
	var origin := Vector2i(4, 4)
	var destination := origin + Vector2i(1, 0)
	for x in range(4, 10):
		for y in range(4, 9):
			grid.set_vertex_elevation(Vector2i(x, y), 3 if x <= 5 else 7)
	var clubhouse := entities.place_building("clubhouse", origin, registry)
	var preview := PlacementPreview.new()
	add_child_autofree(preview)
	preview.set_process(false)
	preview.terrain_grid = grid
	preview.set_building_move_target(clubhouse)
	preview._draw_building_ghost_shape(destination, "clubhouse", Vector2i(4, 4), Color.WHITE)
	var ghost_position: Vector2 = preview._building_ghost.position
	assert_true(entities.move_building(clubhouse, destination))
	assert_eq(ghost_position, clubhouse.global_position,
		"An overlapping move previews the ground after the old footprint is restored")


func test_clubhouse_move_preview_rejects_incompatible_neighbouring_foundations() -> void:
	for x in range(3, 12):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), 3 if x <= 5 else (8 if x >= 9 else 5))
	entities.place_building("pro_shop", Vector2i(3, 4), registry)
	entities.place_building("snack_bar", Vector2i(9, 4), registry)
	var clubhouse := entities.place_building("clubhouse", Vector2i(12, 11), registry)
	var target := Vector2i(5, 4)
	assert_string_contains(CourseClubhouse.move_error(grid, entities, clubhouse, target), "different elevations")
	var preview := PlacementPreview.new()
	add_child_autofree(preview)
	preview.set_process(false)
	preview.terrain_grid = grid
	preview.current_grid_pos = target
	preview.set_building_move_target(clubhouse)
	assert_false(preview._tile_allows_move(target), "The footprint cannot show green when the move is refused")
	assert_false(CourseClubhouse.move_to(entities, clubhouse, target))
	assert_eq(clubhouse.grid_position, Vector2i(12, 11))


func test_ghost_uses_a_neighbours_level_on_sloping_ground() -> void:
	for x in range(4, 9):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), 4 if x <= 5 else (6 if x == 6 else 8))
	entities.place_building("pro_shop", Vector2i(4, 4), registry)
	var destination := Vector2i(6, 4)
	var preview := PlacementPreview.new()
	add_child_autofree(preview)
	preview.set_process(false)
	preview.terrain_grid = grid
	preview._draw_building_ghost_shape(destination, "snack_bar", Vector2i(2, 2), Color.WHITE)
	var ghost_position: Vector2 = preview._building_ghost.position
	var snack := entities.place_building("snack_bar", destination, registry)
	assert_eq(ghost_position, snack.global_position, "The ghost adopts the pinned neighbour's level")
	_levelled(snack, 4)


func test_registry_dimensions_are_used_for_the_drawing_and_foundation() -> void:
	var custom := registry.duplicate(true)
	custom["pro_shop"]["size"] = [1, 3]
	var origin := Vector2i(4, 4)
	var building := entities.place_building("pro_shop", origin, custom)
	assert_eq(Vector2i(building.width, building.height), Vector2i(1, 3))
	_levelled(building, TerrainGrid.BASE_ELEVATION)
	assert_eq(grid.get_tile(origin + Vector2i(1, 0)), TerrainTypes.Type.GRASS,
		"Ground outside the supplied footprint is untouched")
	entities.remove_building(origin)
	assert_eq(grid.get_tile(origin + Vector2i(0, 2)), TerrainTypes.Type.GRASS,
		"Every tile in the supplied footprint is restored")
