extends GameTest
## ShotPathCalculator: the expected shot route HoleVisualizer draws for a hole,
## and calculate_route() — the same route for a tee/cup pair that is not a hole
## yet.

const TEE := Vector2i(4, 20)
const CUP := Vector2i(22, 22)  # ~18 tiles = 398 yds, par 4

var grid: TerrainGrid

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 40
	grid.grid_height = 40
	add_child_autofree(grid)
	GameManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.wind_system = null

func after_each() -> void:
	# An earlier suite may have left a freed grid in the global; don't restore it.
	super()

func _hole(tee: Vector2i, cup: Vector2i, hole_number: int = 1) -> GameManager.HoleData:
	var hole := GameManager.HoleData.new()
	hole.hole_number = hole_number
	hole.tee_position = tee
	hole.green_position = cup
	hole.hole_position = cup
	hole.distance_yards = grid.calculate_distance_yards(tee, cup)
	hole.par = GolfRules.calculate_par(hole.distance_yards)
	return hole

func test_par_3_is_one_shot_to_the_cup() -> void:
	assert_eq(ShotPathCalculator.calculate_route(TEE, Vector2i(12, 20), 3), [TEE, Vector2i(12, 20)])

func test_par_4_and_5_add_landing_zones() -> void:
	var par4 := ShotPathCalculator.calculate_route(TEE, CUP, 4)
	assert_eq(par4.size(), 3)
	assert_eq(par4[0], TEE)
	assert_eq(par4[2], CUP)
	var par5_cup := Vector2i(30, 22)
	var par5 := ShotPathCalculator.calculate_route(TEE, par5_cup, 5)
	assert_eq(par5.size(), 4)
	assert_eq(par5[3], par5_cup)
	for i in range(1, par5.size()):
		assert_lt(Vector2(par5[i]).distance_to(Vector2(par5_cup)),
				Vector2(par5[i - 1]).distance_to(Vector2(par5_cup)), "Every shot advances")

func test_calculate_waypoints_is_calculate_route_for_the_hole() -> void:
	var hole := _hole(TEE, CUP)
	assert_eq(ShotPathCalculator.calculate_waypoints(hole, grid),
			ShotPathCalculator.calculate_route(TEE, CUP, hole.par, 0, grid))

func test_an_explicit_grid_is_used_instead_of_the_global_one() -> void:
	var expected := ShotPathCalculator.calculate_route(TEE, CUP, 4)
	var copy := grid.create_analysis_copy()
	GameManager.terrain_grid = null
	assert_eq(ShotPathCalculator.calculate_route(TEE, CUP, 4, -1, copy), expected,
			"Planning against a detached copy needs no global grid")
	GameManager.terrain_grid = grid
	copy.free()

func test_a_potential_hole_does_not_borrow_another_holes_green() -> void:
	# ShotAI's green-centre bias pulls approach shots toward holes[hole_index]'s
	# green. A cup that is not a hole yet has no entry there: with hole_index 0 it
	# would borrow hole 1's green; -1 must route as if no hole existed.
	var par5_cup := Vector2i(27, 20)
	var clean := ShotPathCalculator.calculate_route(TEE, par5_cup, 5, 0)

	var hole_one := _hole(Vector2i(2, 2), Vector2i(4, 36))
	GameManager.current_course.add_hole(hole_one)
	var borrowed := ShotPathCalculator.calculate_route(TEE, par5_cup, 5, 0)
	assert_ne(borrowed, clean, "Precondition: hole 1's green bends a borrowed route")
	assert_eq(ShotPathCalculator.calculate_route(TEE, par5_cup, 5, -1), clean,
			"hole_index -1 ignores the course's existing holes")

func test_visualizer_reuses_markers_and_preserves_highlight() -> void:
	var visualizer := HoleVisualizer.new()
	add_child_autofree(visualizer)
	visualizer.initialize(_hole(TEE, CUP), grid)
	assert_eq(visualizer.waypoint_markers.size(), 1)
	var marker := visualizer.waypoint_markers[0]
	visualizer.highlight(true)
	visualizer.update_visualization()
	assert_eq(visualizer.waypoint_markers[0], marker)
	assert_eq((marker.get_child(1) as Polygon2D).color, Color(1.0, 1.0, 0.3, 0.8))
	visualizer.hole_data.par = 3
	visualizer.update_visualization()
	assert_eq(visualizer.waypoint_markers.size(), 0)
	visualizer.hole_data.par = 4
	visualizer.update_visualization()
	assert_eq((visualizer.waypoint_markers[0].get_child(1) as Polygon2D).color, Color(1.0, 1.0, 0.3, 0.8))

func test_combined_flight_scan_matches_original_helpers() -> void:
	var start := Vector2i(4, 20)
	var end := Vector2i(24, 20)
	for x in range(4, 25):
		var copy := grid.create_analysis_copy()
		copy.set_analysis_tile(Vector2i(x, 20), TerrainTypes.Type.TREES)
		var combined := ShotAI._flight_tree_count(start, end, copy)
		if ShotAI._path_crosses_trees(start, end, copy):
			assert_eq(combined, -1)
		else:
			assert_eq(combined, ShotAI._count_trees_along_path(start, end, copy))
		copy.free()
