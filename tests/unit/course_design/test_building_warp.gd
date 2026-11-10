extends GameTest
## Building sprites in a gradual turn: the shear that keeps their bases on the
## angled tiles while every wall stays vertical and keeps its height.
##
## The four quarter-turn pictures are pixel-identical to what they always were;
## only the angles between them are warped.

const FOOTPRINT := Vector2(256, 128)  # the clubhouse: four by four tiles


func _rotate(offset: Vector2, turns: float) -> Vector2:
	var angle := turns * PI * 0.5
	var c := cos(angle)
	var s := sin(angle)
	return Vector2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)


## The corner of the footprint at `turns` (which may be fractional), in the
## local draw space of the building node.
func _corner(offset: Vector2, turns: float) -> Vector2:
	return CourseArchitecture.footprint_pivot(FOOTPRINT) \
		+ CourseArchitecture.screen_delta(_rotate(offset, turns))


# ---------------------------------------------------------------------------
# The shear's geometry
# ---------------------------------------------------------------------------

func test_the_four_quarter_turns_are_left_exactly_alone() -> void:
	for facing in range(4):
		for corner in [Vector2(0, 0), Vector2(256, 0), Vector2(256, 128), Vector2(0, 128)]:
			assert_eq(CourseArchitecture.warp_point(corner, FOOTPRINT, facing, 0.0), corner,
				"A quarter turn keeps every pixel where it has always been")


func test_the_front_base_corners_land_on_the_angled_footprint() -> void:
	# The ground under a building is its front edges: the bottom corner of the
	# footprint and the two beside it. Those are the visible pieces of the base,
	# and the shear must put them exactly where the terrain draws the tiles.
	var corners := CourseArchitecture.footprint_corners(FOOTPRINT, 0)
	var left: Vector2 = corners[3]
	var bottom: Vector2 = corners[2]
	var right: Vector2 = corners[1]
	var residual := TerrainGrid.GRADUAL_VIEW_STEP_QUARTER_TURNS
	# The same three corners in grid space, from the footprint's centre.
	var targets := {
		"left": _corner(Vector2(-2, 2), residual),
		"bottom": _corner(Vector2(2, 2), residual),
		"right": _corner(Vector2(2, -2), residual),
	}
	for entry in [["left", left], ["bottom", bottom], ["right", right]]:
		var warped := CourseArchitecture.warp_point(entry[1], FOOTPRINT, 0, residual)
		assert_almost_eq(warped.x, targets[entry[0]].x, 0.01,
			"The %s front corner follows the tiles" % entry[0])
		assert_almost_eq(warped.y, targets[entry[0]].y, 0.01,
			"The %s front corner follows the tiles down as well" % entry[0])


func test_walls_stay_vertical_and_storeys_keep_their_height() -> void:
	var x := 180.0
	var base := CourseArchitecture.ground_y(
		CourseArchitecture.ground_lines(FOOTPRINT, 0), x)
	var ground := CourseArchitecture.warp_point(Vector2(x, base), FOOTPRINT, 0, 0.3)
	var roof := CourseArchitecture.warp_point(Vector2(x, base - 60.0), FOOTPRINT, 0, 0.3)
	assert_almost_eq(roof.x, ground.x, 0.01, "A wall stays under its own base")
	assert_almost_eq(roof.y, ground.y - 60.0, 0.01, "and the storey is not squashed")


func test_the_front_ground_edge_is_the_footprint_diamond() -> void:
	var lines := CourseArchitecture.ground_lines(FOOTPRINT, 0)
	assert_almost_eq(float(lines["hinge_x"]), 128.0, 0.01)
	assert_almost_eq(CourseArchitecture.ground_y(lines, 0.0), 128.0, 0.01,
		"The base runs through the left corner")
	assert_almost_eq(CourseArchitecture.ground_y(lines, 128.0), 192.0, 0.01,
		"down to the bottom corner")
	assert_almost_eq(CourseArchitecture.ground_y(lines, 256.0), 128.0, 0.01,
		"and back up to the right one")


func test_a_column_bends_by_the_same_map_as_the_ground() -> void:
	var lines := CourseArchitecture.ground_lines(FOOTPRINT, 0)
	var pivot := CourseArchitecture.footprint_pivot(FOOTPRINT)
	var matrix := CourseArchitecture.warp_matrix(0.25)
	var x := 70.0
	var ground := Vector2(x, CourseArchitecture.ground_y(lines, x))
	var expected := pivot + matrix * (ground - pivot)
	var move := CourseArchitecture.column_warp(x, lines, pivot, matrix)
	assert_almost_eq(x + move.x, expected.x, 0.01)
	assert_almost_eq(ground.y + move.y, expected.y, 0.01)


# ---------------------------------------------------------------------------
# The view angle's offset from the nearest of the four directions
# ---------------------------------------------------------------------------

func test_the_offset_is_how_far_the_view_sits_from_the_nearest_direction() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	grid.set_view_orientation(0.0)
	assert_almost_eq(grid.get_view_angle_offset(), 0.0, 0.0001)
	grid.set_view_orientation(TerrainGrid.GRADUAL_VIEW_STEP_QUARTER_TURNS)
	assert_almost_eq(grid.get_view_angle_offset(),
		TerrainGrid.GRADUAL_VIEW_STEP_QUARTER_TURNS, 0.0001,
		"15° past north reads as a small offset on the north picture")
	grid.set_view_orientation(0.6)
	assert_eq(grid.get_view_orientation(), 1, "just past halfway the east picture is nearest")
	assert_almost_eq(grid.get_view_angle_offset(), -0.4, 0.0001,
		"and the offset swings the other way on it")
	grid.set_view_orientation(3.9)
	assert_eq(grid.get_view_orientation(), 0)
	assert_almost_eq(grid.get_view_angle_offset(), -0.1, 0.0001,
		"the turn across north keeps a small offset on the north picture")


func test_the_shear_leans_the_same_way_either_side_of_a_direction() -> void:
	var left := CourseArchitecture.warp_point(Vector2(0, 128), FOOTPRINT, 0, -0.2)
	var right := CourseArchitecture.warp_point(Vector2(0, 128), FOOTPRINT, 0, 0.2)
	assert_almost_eq(left.x, right.x, 0.01, "Both lean the same way across")
	assert_almost_eq(left.y + right.y, 256.0, 0.01,
		"and the two sides of north lift and drop by the same amount")


func test_the_ground_edge_follows_each_of_the_four_directions() -> void:
	for facing in range(4):
		var lines := CourseArchitecture.ground_lines(FOOTPRINT, facing)
		var corners := CourseArchitecture.footprint_corners(FOOTPRINT, facing)
		var bottom := 0
		for i in range(corners.size()):
			if corners[i].y > corners[bottom].y:
				bottom = i
		for corner in [corners[bottom], corners[(bottom + 1) % 4],
				corners[(bottom + 3) % 4]]:
			assert_almost_eq(CourseArchitecture.ground_y(lines, corner.x), corner.y, 0.01,
				"The front base runs through the footprint corners at facing %d" % facing)


func test_the_front_corners_follow_the_tiles_at_each_facing() -> void:
	# Grid-space corners of the four-by-four footprint, in the order
	# footprint_corners() returns them.
	var offsets := [Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)]
	var residual := TerrainGrid.GRADUAL_VIEW_STEP_QUARTER_TURNS
	for facing in range(4):
		var corners := CourseArchitecture.footprint_corners(FOOTPRINT, facing)
		var bottom := 0
		for i in range(corners.size()):
			if corners[i].y > corners[bottom].y:
				bottom = i
		for index in [bottom, (bottom + 1) % 4, (bottom + 3) % 4]:
			var target := _corner(offsets[index], facing + residual)
			var warped := CourseArchitecture.warp_point(
				corners[index], FOOTPRINT, facing, residual)
			assert_almost_eq(warped.x, target.x, 0.01,
				"Facing %d carries its front base corners on to the angled tiles" % facing)
			assert_almost_eq(warped.y, target.y, 0.01,
				"Facing %d carries its front base corners on to the angled tiles" % facing)


func test_the_shear_stops_short_of_the_halfway_point() -> void:
	assert_almost_eq(CourseArchitecture.clamp_warp(0.5), 0.4, 0.0001,
		"45° draws as far as 36°: nearer than that the wall face folds to a line")
	assert_almost_eq(CourseArchitecture.clamp_warp(-0.5), -0.4, 0.0001)
	assert_almost_eq(CourseArchitecture.clamp_warp(0.2), 0.2, 0.0001,
		"small turns are drawn exactly")
