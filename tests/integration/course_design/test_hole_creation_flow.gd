extends MainSceneTest
## The hole workflow on an empty lot: a tee box is one tile and only one may
## wait, the first green is a one-tile Green With Hole, undo and redo carry the
## cup with its tile, the same brush widens the green while a cup waits, Open
## Hole pairs the two — and waiting cups and open holes survive a save round trip.

var grid: TerrainGrid


func before_all() -> void:
	await super()
	await new_game("Hole creation")
	grid = main.terrain_grid


func test_a_hole_is_built_from_one_tee_tile_and_one_green_with_hole() -> void:
	assert_eq(GameManager.current_course.holes.size(), 0, "A new game starts with no holes")

	# --- Tee box: a 1x1 brush, and only one may wait on the course.
	main._on_tool_selected(TerrainTypes.Type.TEE_BOX)
	main.terrain_toolbar.set_brush_size(5)
	assert_eq(main.brush_size, 5, "The toolbar's brush size reaches main")
	assert_eq(main.terrain_toolbar.effective_brush_size(), 1, "The tee box brush is capped at 1x1")
	var tee := Vector2i(60, 60)
	stroke(tee)
	assert_eq(grid.get_tile(tee), TerrainTypes.Type.TEE_BOX, "The tee box is painted")
	assert_eq(grid.get_tee_box_tiles().size(), 1, "The tee box paints exactly one tile")
	assert_ne(grid.get_tile(tee + Vector2i(1, 0)), TerrainTypes.Type.TEE_BOX, "The tee brush is not 5x5")
	assert_false(HoleLayout.can_place_tee_box(grid, GameManager.current_course), "The waiting tee blocks another")

	var cash_before_second_tee := GameManager.money
	var second_tee := Vector2i(70, 70)
	stroke(second_tee)
	assert_ne(grid.get_tile(second_tee), TerrainTypes.Type.TEE_BOX, "A second tee box must wait")
	assert_eq(GameManager.money, cash_before_second_tee, "A blocked tee box costs nothing")

	# --- Green: the first green is a 1x1 Green With Hole.
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	main.terrain_toolbar.set_brush_size(5)
	assert_eq(main.terrain_toolbar.effective_brush_size(), 1, "Green With Hole is capped at 1x1")
	assert_true(main.terrain_toolbar.green_will_place_cup(), "The Green button shows a flag for the cup")
	var cup := Vector2i(68, 60)
	stroke(cup)
	assert_eq(grid.get_tile(cup), TerrainTypes.Type.GREEN, "The green is painted")
	assert_eq(grid.get_cup_tiles(), [cup], "The first green carries the hole")
	assert_ne(grid.get_tile(cup + Vector2i(1, 0)), TerrainTypes.Type.GREEN, "The cup's green is one tile")
	assert_false(HoleLayout.green_places_cup(grid, GameManager.current_course), "A cup is waiting now")
	assert_false(main.terrain_toolbar.green_will_place_cup(), "The Green button's flag turns off while a cup waits")
	assert_false(main.terrain_toolbar._open_hole_buttons[0].disabled, "Open Hole is ready")
	await process_frames(2)  # The cup overlay draws its waiting pin.

	# --- Undo and redo keep the cup with its tile.
	main._perform_undo()
	assert_ne(grid.get_tile(cup), TerrainTypes.Type.GREEN, "Undo removes the painted green")
	assert_eq(grid.get_cup_tiles(), [] as Array[Vector2i], "Undo removes the cup with it")
	assert_true(main.terrain_toolbar.green_will_place_cup(), "Undo restores the Green With Hole flag")
	main._perform_redo()
	assert_eq(grid.get_tile(cup), TerrainTypes.Type.GREEN, "Redo repaints the green")
	assert_eq(grid.get_cup_tiles(), [cup], "Redo restores the cup")
	assert_false(main.terrain_toolbar.green_will_place_cup(), "Redo clears the Green With Hole flag")

	# --- While a cup waits, the same brush widens the putting surface.
	var patch := Vector2i(cup.x, cup.y + 2)
	stroke(patch)
	var painted := 0
	for pos in grid.get_brush_tiles(patch, 5, main.round_brush):
		if grid.get_tile(pos) == TerrainTypes.Type.GREEN:
			painted += 1
	assert_gt(painted, 1, "Green Without Hole paints with the standard brush")
	assert_eq(grid.get_cup_tiles(), [cup], "Widening the green adds no second cup")
	assert_eq(main.terrain_toolbar.effective_brush_size(), 5, "The brush is uncapped once a cup waits")
	assert_false(main.terrain_toolbar.green_will_place_cup(), "The Green button stays unflagged while a cup waits")

	# --- Open Hole pairs the waiting tee with the waiting cup.
	main._on_open_hole_pressed()
	assert_eq(GameManager.current_course.holes.size(), 1, "Open Hole created the hole")
	assert_eq(grid.get_cup_tiles(), [] as Array[Vector2i], "Opening a hole consumes the cup")
	var hole: GameManager.HoleData = GameManager.current_course.holes[0]
	assert_eq(hole.tee_position, tee, "The hole's tee is the painted tee box")
	assert_eq(hole.green_position, cup, "The hole's green is the painted cup")
	assert_eq(hole.hole_position, cup, "The cup is where it was painted")
	assert_true(HoleLayout.can_place_tee_box(grid, GameManager.current_course),
		"The tee is claimed, so a new one may be painted")
	assert_true(HoleLayout.green_places_cup(grid, GameManager.current_course), "The next green carries the next cup")
	assert_true(main.terrain_toolbar.green_will_place_cup(), "Opening the hole restores the Green With Hole flag")
	assert_true(main.terrain_toolbar._open_hole_buttons[0].disabled, "Nothing is left waiting to open")

	# --- The loop restarts: the next green is a capped Green With Hole again.
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	main.terrain_toolbar.set_brush_size(5)
	assert_eq(main.terrain_toolbar.effective_brush_size(), 1, "A fresh green is capped at 1x1 again")
	assert_true(main.terrain_toolbar.green_will_place_cup(), "The next Green button is flagged before painting")


func test_waiting_cups_and_open_holes_survive_a_save_round_trip() -> void:
	var opened := build_hole(Vector2i(80, 70), Vector2i(80, 58))
	assert_not_null(opened, "A hole opens on the lot")
	var holes := GameManager.current_course.holes.size()
	var waiting_cup := Vector2i(50, 50)
	paint(TerrainTypes.Type.GREEN, waiting_cup)
	assert_eq(grid.get_cup_tiles(), [waiting_cup], "The next green carries a cup")
	assert_false(main.terrain_toolbar.green_will_place_cup(), "The flag turns off after placing the next cup")
	await process_frames(2)  # The cup overlay draws the new cup.

	SaveManager._apply_save_data(SaveManager._build_save_data())
	assert_eq(GameManager.current_course.holes.size(), holes, "The open holes survive save and load")
	assert_eq(GameManager.current_course.holes[-1].hole_position, opened.hole_position,
		"The opened cup survives save and load")
	assert_eq(grid.get_cup_tiles(), [waiting_cup], "The waiting cup survives save and load")
	assert_false(main.terrain_toolbar.green_will_place_cup(), "The Green flag reflects the waiting cup after load")
