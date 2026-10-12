extends MainSceneTest
## The terrain brush on a course: it leaves unowned land and decorations alone
## and free of charge, charges exactly what undo refunds and redo charges again,
## refuses a redo the player cannot afford, keeps a stroke cancelled mid-drag,
## restores natural terrain on undo — and a save keeps the day's accounts.

var grid: TerrainGrid


func before_all() -> void:
	await super()
	await new_game("Builder")
	grid = main.terrain_grid


func before_each() -> void:
	super()
	main.undo_manager.clear()
	main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
	main.brush_size = 1


func test_unowned_land_and_decorations_are_left_alone_for_free() -> void:
	var cash := GameManager.money
	var outside := Vector2i(0, 0)
	assert_false(GameManager.land_manager.is_tile_owned(outside), "The corner of the map is not owned")
	var outside_type := grid.get_tile(outside)
	stroke(outside)
	assert_eq(grid.get_tile(outside), outside_type, "The brush does not reach land the course does not own")

	var bench := Vector2i(50, 58)
	main._suppress_tile_undo = true
	grid.set_tile(bench, TerrainTypes.Type.GRASS)
	main._suppress_tile_undo = false
	assert_not_null(main.entity_layer.place_decoration("park_bench", bench, main.decoration_registry),
		"A bench stands on the lot")
	cash = GameManager.money
	stroke(bench)
	assert_eq(grid.get_tile(bench), TerrainTypes.Type.GRASS, "The brush leaves a decorated tile alone")
	assert_not_null(main.entity_layer.get_decoration_at(bench), "and the decoration on it")
	assert_eq(GameManager.money, cash, "Nothing painted, nothing charged")


func test_undo_refunds_exactly_and_redo_must_be_affordable() -> void:
	var tile := Vector2i(60, 52)
	main._suppress_tile_undo = true
	grid.set_tile(tile, TerrainTypes.Type.OAK)
	main._suppress_tile_undo = false
	var cash := GameManager.money

	# A stroke cancelled mid-drag keeps what it painted.
	main.undo_manager.begin_stroke()
	main.is_painting = true
	main._paint_terrain_stamp(tile)
	main._cancel_action()
	assert_eq(grid.get_tile(tile), TerrainTypes.Type.FAIRWAY, "The cancelled stroke keeps its paint")
	var paid := cash - GameManager.money
	assert_gt(paid, 0, "Painting over a wood costs money")

	# A wood is a tile, so undo brings back its ground and its canopy as one.
	main._perform_undo()
	assert_eq(grid.get_tile(tile), TerrainTypes.Type.OAK, "Undo brings the wood back")
	assert_eq(GameManager.money, cash, "Undo refunds exactly what was paid")

	GameManager.money = 0
	main._perform_redo()
	assert_true(main.undo_manager.can_redo(), "A redo the player cannot afford stays on the stack")
	assert_eq(grid.get_tile(tile), TerrainTypes.Type.OAK, "and changes nothing")
	GameManager.money = cash
	main._perform_redo()
	assert_eq(grid.get_tile(tile), TerrainTypes.Type.FAIRWAY, "Once affordable, the redo paints again")
	assert_eq(GameManager.money, cash - paid, "for the same price")


func test_undo_restores_natural_bunker_terrain() -> void:
	var tile := Vector2i(62, 54)
	main._suppress_tile_undo = true
	grid.set_tile_natural(tile, TerrainTypes.Type.BUNKER)
	main._suppress_tile_undo = false
	stroke(tile)
	main._perform_undo()
	assert_eq(grid.get_tile(tile), TerrainTypes.Type.BUNKER, "Undo restores the natural bunker")
	assert_false(grid._player_placed_tiles.has(tile), "and the bunker is natural again")


func test_a_save_keeps_the_days_accounts() -> void:
	GameManager.daily_stats.revenue = 321
	GameManager.daily_stats.golfers_arrived = 7
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveManager._build_save_data()))
	SaveManager._apply_save_data(data)
	assert_eq(GameManager.daily_stats.revenue, 321, "The day's revenue survives a save")
	assert_eq(GameManager.daily_stats.golfers_arrived, 7, "and so does its golfer count")
