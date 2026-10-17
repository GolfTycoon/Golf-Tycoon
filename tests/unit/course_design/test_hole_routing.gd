extends GameTest
## Hole routing: the order the holes are played in, and the walk between them.
##
## The maths behind the Course Map's Routing mode. The order of play is the
## course's holes array, so these cover the renumbering every edit ends in, the
## three edits the map offers (move a hole, play the round backwards, turn a hole
## round), and the grades the walk between two holes is painted with - the same
## thresholds RoutingOverlay uses on the course itself.

func _holes(specs: Array) -> Array:
	var holes: Array = []
	for i in specs.size():
		var hole := make_hole(0, specs[i][0], specs[i][1], specs[i][2])
		hole.distance_yards = specs[i][3]
		holes.append(hole)
	HoleRouting.renumber(holes)
	return holes


## Three holes in a line: a 70-tile walk between the first and the second (a
## long one: the RoutingOverlay threshold is 60) and a 10-tile walk after the
## second.
func _course() -> Array:
	return _holes([
		[Vector2i(0, 0), Vector2i(10, 0), 4, 400],
		[Vector2i(80, 0), Vector2i(100, 0), 5, 500],
		[Vector2i(110, 0), Vector2i(128, 0), 3, 180],
	])


# ---------------------------------------------------------------------------
# Renumbering and the order of play
# ---------------------------------------------------------------------------

func test_the_round_is_labelled_one_to_n() -> void:
	var holes := _holes([
		[Vector2i(0, 0), Vector2i(10, 0), 4, 400],
		[Vector2i(30, 0), Vector2i(50, 0), 4, 400],
		[Vector2i(60, 0), Vector2i(80, 0), 4, 400],
	])
	var numbers: Array = []
	for hole in holes:
		numbers.append(int(hole.hole_number))
	assert_eq(numbers, [1, 2, 3])


func test_a_hole_is_moved_to_another_place_in_the_round() -> void:
	var holes := _course()
	var second = holes[1]
	assert_true(HoleRouting.move(holes, 1, 0), "moving a hole earlier is allowed")
	assert_eq(holes[0], second, "the moved hole now leads")
	assert_eq(holes[0].hole_number, 1, "and it is renumbered")
	assert_eq(holes[1].hole_number, 2)
	assert_eq(holes[2].hole_number, 3)


func test_a_move_the_course_cannot_make_is_refused() -> void:
	var holes := _course()
	assert_false(HoleRouting.move(holes, 3, 0), "there is no fourth hole")
	assert_false(HoleRouting.move(holes, 0, -1))
	assert_false(HoleRouting.move(holes, 1, 1), "a hole moved onto itself is not a move")
	var first = holes[0]
	HoleRouting.move(holes, 3, 0)
	HoleRouting.move(holes, 0, -1)
	HoleRouting.move(holes, 1, 1)
	assert_eq(holes[0], first, "a refused move leaves the round as it was")


func test_playing_the_round_backwards_turns_it_round() -> void:
	var holes := _course()
	var first = holes[0]
	var last = holes[2]
	assert_true(HoleRouting.reverse(holes))
	assert_eq(holes[0], last, "the last hole now leads")
	assert_eq(holes[2], first)
	assert_eq(holes[0].hole_number, 1, "the round is renumbered")
	assert_eq(holes[2].hole_number, 3)


func test_a_single_hole_course_cannot_be_turned_round() -> void:
	var holes := _holes([[Vector2i(0, 0), Vector2i(10, 0), 4, 400]])
	assert_false(HoleRouting.reverse(holes), "one hole is already the whole round")


func test_a_hole_is_turned_around_at_both_ends() -> void:
	var grid := make_grid(96, 32)
	fill_grid(grid, TerrainTypes.Type.ROUGH)
	var hole := make_hole(1, Vector2i(10, 10), Vector2i(40, 10))
	grid.set_tile_natural(Vector2i(10, 10), TerrainTypes.Type.TEE_BOX)
	grid.set_tile_natural(Vector2i(40, 10), TerrainTypes.Type.GREEN)
	grid.add_cup_tile(Vector2i(40, 10))

	assert_true(HoleRouting.flip(hole, grid))
	assert_eq(hole.tee_position, Vector2i(40, 10), "the old green is the new tee")
	assert_eq(hole.green_position, Vector2i(10, 10), "the old tee is the new green")
	assert_eq(hole.hole_position, Vector2i(10, 10), "and the cup moved with it")
	assert_eq(grid.get_tile(Vector2i(10, 10)), TerrainTypes.Type.GREEN)
	assert_eq(grid.get_tile(Vector2i(40, 10)), TerrainTypes.Type.TEE_BOX)
	assert_true(grid.get_cup_tiles().has(Vector2i(10, 10)), "the cup is cut in the new green")
	assert_false(grid.get_cup_tiles().has(Vector2i(40, 10)), "and lifted out of the old one")
	assert_eq(Vector2(hole.tee_position).distance_to(Vector2(hole.green_position)),
		Vector2(10.0, 10.0).distance_to(Vector2(40.0, 10.0)), "turning a hole round keeps its length")


func test_a_hole_whose_ground_no_longer_matches_is_left_alone() -> void:
	var grid := make_grid(96, 32)
	fill_grid(grid, TerrainTypes.Type.ROUGH)
	var hole := make_hole(1, Vector2i(10, 10), Vector2i(40, 10))
	grid.set_tile_natural(Vector2i(10, 10), TerrainTypes.Type.TEE_BOX)
	grid.set_tile_natural(Vector2i(40, 10), TerrainTypes.Type.FAIRWAY)
	assert_false(HoleRouting.flip(hole, grid), "there is no green to turn the hole onto")
	assert_eq(hole.tee_position, Vector2i(10, 10), "the hole is not half-turned")
	assert_eq(hole.green_position, Vector2i(40, 10))

	var flat := make_hole(1, Vector2i(5, 5), Vector2i(5, 5))
	assert_false(HoleRouting.flip(flat, grid), "a hole with one end is not a hole to turn")


# ---------------------------------------------------------------------------
# The walk between holes
# ---------------------------------------------------------------------------

func test_a_leg_is_the_walk_from_a_green_to_the_next_tee() -> void:
	var holes := _course()
	assert_almost_eq(HoleRouting.leg_tiles(holes, 0), Vector2(10, 0).distance_to(Vector2(80, 0)), 0.001)
	assert_almost_eq(HoleRouting.leg_tiles(holes, 1), Vector2(100, 0).distance_to(Vector2(110, 0)), 0.001)
	assert_eq(HoleRouting.leg_tiles(holes, 2), 0.0, "the round ends at the last green")
	assert_eq(HoleRouting.leg_tiles(holes, 9), 0.0, "there is nothing after the last hole")


func test_a_leg_is_graded_the_way_the_course_paints_it() -> void:
	assert_eq(HoleRouting.SHORT_TILES, RoutingOverlay.SHORT_THRESHOLD,
		"the map and the course read the same threshold")
	assert_eq(HoleRouting.MODERATE_TILES, RoutingOverlay.MODERATE_THRESHOLD)
	assert_eq(HoleRouting.grade_for(HoleRouting.SHORT_TILES - 0.5), HoleRouting.Grade.SHORT)
	assert_eq(HoleRouting.grade_for(HoleRouting.SHORT_TILES), HoleRouting.Grade.MODERATE,
		"a walk at the threshold is the longer grade")
	assert_eq(HoleRouting.grade_for(HoleRouting.MODERATE_TILES - 0.5), HoleRouting.Grade.MODERATE)
	assert_eq(HoleRouting.grade_for(HoleRouting.MODERATE_TILES), HoleRouting.Grade.LONG)
	assert_eq(HoleRouting.grade_for(0.0), HoleRouting.Grade.SHORT)


func test_the_grades_read_green_amber_and_red() -> void:
	var short := HoleRouting.grade_color(HoleRouting.Grade.SHORT)
	var moderate := HoleRouting.grade_color(HoleRouting.Grade.MODERATE)
	var long := HoleRouting.grade_color(HoleRouting.Grade.LONG)
	assert_gt(short.g, short.r, "a short walk is green")
	assert_gt(moderate.r, moderate.b, "a moderate walk is amber")
	assert_gt(moderate.g, moderate.b)
	assert_gt(long.r, long.g, "a long walk is red")
	assert_eq(HoleRouting.grade_name(HoleRouting.Grade.SHORT), "Short")
	assert_eq(HoleRouting.grade_name(HoleRouting.Grade.MODERATE), "Moderate")
	assert_eq(HoleRouting.grade_name(HoleRouting.Grade.LONG), "Long")


func test_every_walk_between_holes_is_reported_in_play_order() -> void:
	var holes := _course()
	var legs := HoleRouting.legs(holes)
	assert_eq(legs.size(), 2, "three holes make two walks")
	assert_eq(int(legs[0]["from_hole"]), 1)
	assert_eq(int(legs[0]["to_hole"]), 2)
	assert_eq(int(legs[0]["after_hole"]), 1, "the walk is reported after the hole it leaves")
	assert_eq(int(legs[0]["yards"]), int(roundf(HoleRouting.leg_tiles(holes, 0) * HoleLayout.YARDS_PER_TILE)))
	assert_eq(int(legs[1]["grade"]), HoleRouting.grade_for(HoleRouting.leg_tiles(holes, 1)))


func test_average_walk_is_zero_for_a_course_with_fewer_than_two_holes() -> void:
	assert_eq(HoleRouting.average_leg_tiles([]), 0.0)
	var one := _holes([[Vector2i(0, 0), Vector2i(10, 0), 4, 400]])
	assert_eq(HoleRouting.average_leg_tiles(one), 0.0)
	# The average is the mean of the legs, not of all the ends.
	var holes := _course()
	assert_almost_eq(HoleRouting.average_leg_tiles(holes),
		(HoleRouting.leg_tiles(holes, 0) + HoleRouting.leg_tiles(holes, 1)) * 0.5, 0.001)


func test_the_route_report_summarises_the_round() -> void:
	var holes := _course()
	holes[1].is_open = false
	var report := HoleRouting.route_report(holes)
	assert_eq(int(report["holes"]), 3)
	assert_eq(int(report["open"]), 2, "a closed hole is still part of the round")
	assert_eq(int(report["total_par"]), 12)
	assert_eq(int(report["total_yards"]), 1080)
	assert_almost_eq(float(report["average_leg_tiles"]), HoleRouting.average_leg_tiles(holes), 0.001)
	assert_eq(int(report["long_legs"]), 1, "the 70-tile walk is the long one")
	assert_almost_eq(float(report["longest_leg"]), HoleRouting.leg_tiles(holes, 0), 0.001)
	assert_eq(int(report["worst_after_hole"]), 1, "it comes after hole 1")


func test_a_route_with_no_long_walks_reports_none() -> void:
	var holes := _holes([
		[Vector2i(0, 0), Vector2i(10, 0), 4, 400],
		[Vector2i(12, 0), Vector2i(30, 0), 4, 400],
	])
	var report := HoleRouting.route_report(holes)
	assert_eq(int(report["long_legs"]), 0)
	assert_eq(int(report["worst_after_hole"]), 1, "even the shortest round has a longest walk")
