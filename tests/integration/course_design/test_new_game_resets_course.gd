extends MainSceneTest
## Starting a new game leaves no trace of the course played before it: no tee
## boxes, greens, fairways or bunker depths, no waiting cups or sculpted
## elevation, no hole flags, golfers or undo history. A leftover tee box would
## be worse than cosmetic — it would block the player's very first tee.

const TEE := Vector2i(60, 60)
const CUP := Vector2i(60, 50)
const SCULPTED := Vector2i(61, 61)
const BUILT := [
	TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.GREEN,
	TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.BUNKER,
]

var grid: TerrainGrid


func before_all() -> void:
	await super()
	grid = main.terrain_grid


func _built_tiles() -> int:
	var total := 0
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			if grid.get_tile(Vector2i(x, y)) in BUILT:
				total += 1
	return total


func test_a_new_game_starts_from_a_clean_lot() -> void:
	# --- The first course: a hole, sculpted ground, undo history and golfers.
	await new_game("First Course")
	assert_not_null(build_hole(TEE, CUP), "The first course opens a hole")
	await process_frames(4)
	assert_eq(grid.get_tee_box_tiles().size(), 1, "The first course has its tee box")
	grid.set_vertex_elevation(SCULPTED, grid.MAX_ELEVATION)
	assert_eq(grid.get_vertex_elevation(SCULPTED), grid.MAX_ELEVATION, "The first course has sculpted ground")
	assert_true(main.undo_manager.can_undo(), "The first course has undo history")
	assert_eq(main.hole_manager.get_all_hole_visualizers().size(), 1, "The first course has a hole flag")
	main.golfer_manager.spawn_initial_group()
	await process_frames(4)
	assert_gt(main.golfer_manager.get_active_golfers().size(), 0, "The first course has golfers on it")
	assert_gt(_built_tiles(), 0, "The first course has built tiles")

	# --- The second course.
	await new_game("Second Course")
	assert_eq(GameManager.course_name, "Second Course", "The second game is running")
	assert_eq(GameManager.current_course.holes.size(), 0, "The second course starts with no holes")
	assert_true(grid.get_tee_box_tiles().is_empty(), "No tee box survives into the second course")
	assert_true(grid.get_cup_tiles().is_empty(), "No waiting cup survives into the second course")
	assert_eq(_built_tiles(), 0, "No built tile survives into the second course")
	# Player-placed marks are not checked here: the course paints its own
	# vegetation with set_tile_natural(), so the only marks a generated course
	# leaves are the ones its buildings set. reset_for_new_course() clearing them
	# is covered by the unit tests in course_design/test_cup_tiles.gd.
	assert_true(grid.serialize_bunker_depth().is_empty(), "No bunker depth survives")
	assert_true(main.hole_manager.get_all_hole_visualizers().is_empty(), "The old hole flag is gone")
	assert_false(main.undo_manager.can_undo(), "Undo history does not cross into the second course")
	assert_true(main.golfer_manager.get_active_golfers().is_empty(), "No golfer survives into the second course")
	assert_true(HoleLayout.can_place_tee_box(grid, GameManager.current_course),
		"The player can paint a first tee box")
	# Generation stays within the theme's range of the flat base level, so the
	# maximum could only come back if the vertex was never reset.
	assert_ne(grid.get_vertex_elevation(SCULPTED), grid.MAX_ELEVATION,
		"Sculpted ground is regenerated, not inherited")

	# --- And the second course is playable.
	assert_not_null(build_hole(TEE, CUP), "The second course opens its own hole")
	assert_eq(GameManager.current_course.holes.size(), 1, "and it is the only one")
