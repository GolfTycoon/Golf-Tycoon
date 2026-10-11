extends MainSceneTest
## The Bulldozer's remit, on a new course: it demolishes Improvements and
## Buildings — decorations, and a facility from any tile of its footprint — and
## never touches Course Terrain tiles, which replace each other when painted
## instead.

var grid: TerrainGrid


func before_all() -> void:
	await super()
	await new_game("Bulldozer")
	grid = main.terrain_grid
	# Hold the clock so green fees and day rollovers cannot move the balance
	# between a demolition and the check of what it cost.
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)


func after_each() -> void:
	main._cancel_bulldozer_mode()
	await super()


## A new course arrives with its own ground everywhere; repaint a tile so a
## scenario runs on known ground (test choreography, not a player's stroke, so
## undo stays out of it).
func _prep(tile: Vector2i, terrain: int) -> void:
	main._suppress_tile_undo = true
	grid.set_tile(tile, terrain)
	main._suppress_tile_undo = false


## Paint `tile` with `terrain` the way the toolbar's tile button does.
func _paint_with_toolbar(terrain: int, tile: Vector2i) -> void:
	main.terrain_toolbar._on_tool_button_pressed(terrain)
	main._paint_terrain_stamp(tile)


func test_course_terrain_tiles_replace_each_other() -> void:
	# Tiles on owned land near the clubhouse.
	_prep(Vector2i(50, 62), TerrainTypes.Type.BRUSH)
	_prep(Vector2i(51, 62), TerrainTypes.Type.ROCKS)
	_prep(Vector2i(49, 62), TerrainTypes.Type.FLOWER_BED)
	_prep(Vector2i(60, 50), TerrainTypes.Type.WATER)
	await process_frames(2)
	_paint_with_toolbar(TerrainTypes.Type.ROUGH, Vector2i(50, 62))
	assert_eq(grid.get_tile(Vector2i(50, 62)), TerrainTypes.Type.ROUGH, "Rough replaces Brush")
	_paint_with_toolbar(TerrainTypes.Type.FAIRWAY, Vector2i(51, 62))
	assert_eq(grid.get_tile(Vector2i(51, 62)), TerrainTypes.Type.FAIRWAY, "Fairway replaces Rocks")
	_paint_with_toolbar(TerrainTypes.Type.BUNKER, Vector2i(49, 62))
	assert_eq(grid.get_tile(Vector2i(49, 62)), TerrainTypes.Type.BUNKER, "Bunker replaces Wild Flowers")
	_paint_with_toolbar(TerrainTypes.Type.STREAM, Vector2i(60, 50))
	assert_eq(grid.get_tile(Vector2i(60, 50)), TerrainTypes.Type.STREAM, "Stream replaces Water")


func test_woods_and_boulders_are_painted_like_any_other_ground() -> void:
	# A wood is ground, so it is painted over like anything else, and the
	# boulder terrains overwrite any tile they land on.
	var tree_over_rough := Vector2i(52, 62)
	var small_boulders := Vector2i(53, 62)
	var tree_on_water := Vector2i(61, 50)
	var large_boulders := Vector2i(62, 50)
	var rocks_over_tree := Vector2i(63, 50)
	_prep(tree_over_rough, TerrainTypes.Type.OAK)
	_prep(small_boulders, TerrainTypes.Type.WATER)
	_prep(tree_on_water, TerrainTypes.Type.WATER)
	_prep(large_boulders, TerrainTypes.Type.BUNKER)
	_prep(rocks_over_tree, TerrainTypes.Type.MAPLE)
	await process_frames(1)

	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.Type.ROUGH)
	stroke(tree_over_rough)
	assert_eq(grid.get_tile(tree_over_rough), TerrainTypes.Type.ROUGH, "Rough replaces an oak tile")
	main._perform_undo()
	assert_eq(grid.get_tile(tree_over_rough), TerrainTypes.Type.OAK,
		"Undo restores the whole oak tile, its ground and its canopy with it")
	main._perform_redo()
	assert_eq(grid.get_tile(tree_over_rough), TerrainTypes.Type.ROUGH, "Redo paints Rough back")

	_paint_with_toolbar(TerrainTypes.Type.SMALL_BOULDERS, small_boulders)
	assert_eq(grid.get_tile(small_boulders), TerrainTypes.Type.SMALL_BOULDERS, "Small Boulders replace Water")
	_paint_with_toolbar(TerrainTypes.Type.LARGE_BOULDERS, large_boulders)
	assert_eq(grid.get_tile(large_boulders), TerrainTypes.Type.LARGE_BOULDERS, "Large Boulders replace a Bunker")
	_paint_with_toolbar(TerrainTypes.Type.ROCKS, rocks_over_tree)
	assert_eq(grid.get_tile(rocks_over_tree), TerrainTypes.Type.ROCKS, "Rocks replace a maple tile")
	assert_eq(grid._course_surface._data.get_pixel(rocks_over_tree.x, rocks_over_tree.y).a, 1.0,
		"Painted Rocks render as stony ground")

	# A wood is painted wherever the player wants it, water and boulder ground
	# included, because every tile on the tab replaces every other one.
	_paint_with_toolbar(TerrainTypes.Type.PINE, tree_on_water)
	assert_eq(grid.get_tile(tree_on_water), TerrainTypes.Type.PINE, "A pine tile can be painted on water")
	_paint_with_toolbar(TerrainTypes.Type.OAK, large_boulders)
	assert_eq(grid.get_tile(large_boulders), TerrainTypes.Type.OAK, "An oak tile replaces boulder ground")


func test_the_bulldozer_never_touches_course_terrain() -> void:
	var tiles := {
		Vector2i(50, 64): TerrainTypes.Type.ROUGH,
		Vector2i(51, 64): TerrainTypes.Type.FAIRWAY,
		Vector2i(49, 64): TerrainTypes.Type.BUNKER,
		Vector2i(60, 52): TerrainTypes.Type.STREAM,
		Vector2i(59, 52): TerrainTypes.Type.OAK,
		Vector2i(58, 52): TerrainTypes.Type.SMALL_BOULDERS,
	}
	for tile in tiles:
		_prep(tile, tiles[tile])
	await process_frames(2)

	main._on_bulldozer_pressed()
	await process_frames(2)
	assert_true(main.bulldozer_mode, "Bulldozer mode is active")
	var money := GameManager.money
	for tile in tiles:
		main._handle_bulldozer_click(tile)
		assert_eq(grid.get_tile(tile), tiles[tile],
			"The bulldozer leaves %s in place" % TerrainTypes.get_type_name(tiles[tile]))
	assert_eq(GameManager.money, money, "Bulldozing course terrain charges nothing")


func test_the_bulldozer_demolishes_a_decoration_for_twenty_dollars() -> void:
	var bench_tile := Vector2i(48, 62)
	_prep(bench_tile, TerrainTypes.Type.GRASS)
	main.entity_layer.place_decoration("park_bench", bench_tile, main.decoration_registry)
	await process_frames(2)
	assert_not_null(main.entity_layer.get_decoration_at(bench_tile), "The bench is placed")

	main._on_bulldozer_pressed()
	var money := GameManager.money
	main._handle_bulldozer_click(bench_tile)
	await process_frames(2)
	assert_null(main.entity_layer.get_decoration_at(bench_tile), "The bulldozer removed the decoration")
	assert_eq(GameManager.money, money - 20, "and charged $20 for it")


func test_the_bulldozer_demolishes_a_building_from_any_footprint_tile() -> void:
	var garage := Vector2i(48, 56)
	for x in range(3):
		for y in range(2):
			_prep(garage + Vector2i(x, y), TerrainTypes.Type.GRASS)
	main.entity_layer.place_building("cart_garage", garage, main.building_registry)
	await process_frames(2)
	assert_true(main.entity_layer.is_tile_occupied_by_building(garage + Vector2i(2, 1)),
		"The cart garage covers its 3x2 footprint")

	main._on_bulldozer_pressed()
	var money := GameManager.money
	main._handle_bulldozer_click(garage + Vector2i(2, 1))
	await process_frames(2)
	assert_false(main.entity_layer.is_tile_occupied_by_building(garage),
		"A click on its far corner demolished the whole building")
	assert_false(main.entity_layer.is_tile_occupied_by_building(garage + Vector2i(1, 1)),
		"The building is gone from every tile")
	assert_eq(GameManager.money, money - 20, "Demolition charges a flat $20, whatever the facility")


func test_the_pinned_buttons_follow_bulldozer_mode() -> void:
	var buttons: Array = main.terrain_toolbar._bulldozer_buttons
	main._on_bulldozer_pressed()
	await process_frames(2)
	assert_true(buttons.all(func(button): return button.is_active()),
		"The pinned buttons show bulldozer mode is on")
	main._cancel_bulldozer_mode()
	await process_frames(2)
	assert_true(buttons.all(func(button): return not button.is_active()),
		"and off again once it ends")

	# The pinned buttons and the X hotkey share one signal, without switching tabs.
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	buttons[0].pressed.emit()
	assert_true(main.bulldozer_mode, "A pinned button activates bulldozer mode")
	assert_eq(main.terrain_toolbar._tab_bar.current_tab, TerrainToolbar.Tab.IMPROVEMENTS,
		"Pressing the pinned Bulldozer keeps its tab open")
