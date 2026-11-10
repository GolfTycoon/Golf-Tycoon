extends GameTest
## Gradual View Rotation: the view angle, the projection math behind it and the
## small animated steps the grid takes instead of snapping a quarter turn.
##
## The projection takes any angle in quarter turns. Whole turns keep the exact
## integer arithmetic the four classic directions use, and the box the course
## fits in at those four directions still covers every angle in between.

const STEP := TerrainGrid.GRADUAL_VIEW_STEP_QUARTER_TURNS


# ---------------------------------------------------------------------------
# The projection at any angle
# ---------------------------------------------------------------------------

func test_a_fractional_angle_projects_and_unprojects_back_to_the_same_point() -> void:
	var projection := GridProjection.new(Vector2i(16, 16))
	for angle in [0.0, 0.25, 0.5, 1.0 / 3.0, 2.75, 3.9]:
		projection.set_orientation(angle)
		var point := Vector2(3.25, 7.75)
		var unprojected := projection.unproject(projection.project(point))
		assert_almost_eq(unprojected.x, point.x, 0.0001,
			"angle %.2f keeps the x coordinate" % angle)
		assert_almost_eq(unprojected.y, point.y, 0.0001,
			"angle %.2f keeps the y coordinate" % angle)


func test_whole_turns_still_use_the_exact_four_direction_arithmetic() -> void:
	var projection := GridProjection.new(Vector2i(16, 16))
	projection.set_orientation(1.0)
	assert_eq(projection.axis_x(), Vector2(-32.0, 16.0),
		"A quarter turn maps the first tile axis exactly where it always has")
	assert_eq(projection.axis_y(), Vector2(-32.0, -16.0),
		"and the second axis too")


func test_the_four_direction_box_still_holds_the_course_at_every_angle() -> void:
	var grid := make_grid(16, 16)
	var bounds := grid.projection.world_bounds()
	for step in range(25):
		var angle := step / 6.0
		grid.projection.set_orientation(angle)
		for corner in [Vector2(0, 0), Vector2(16, 0), Vector2(16, 16), Vector2(0, 16)]:
			assert_true(bounds.grow(0.5).has_point(grid.projection.project(corner)),
				"The course stays inside its box at angle %.2f" % angle)


func test_a_tile_keeps_its_ground_area_at_every_angle() -> void:
	var grid := make_grid(16, 16)
	for step in range(25):
		var angle := step / 6.0
		grid.projection.set_orientation(angle)
		assert_almost_eq(absf(_polygon_area(grid.tile_polygon(Vector2i(4, 4)))),
			grid.tile_width * grid.tile_height * 0.5, 0.5,
			"A tile covers the same ground at angle %.2f" % angle)


func test_a_tile_can_still_be_picked_after_a_gradual_turn() -> void:
	var grid := make_grid(16, 16)
	grid.set_gradual_view_rotation(true)
	grid.set_view_orientation(STEP)
	var tile := Vector2i(5, 7)
	assert_eq(grid.screen_to_grid(grid.grid_to_screen_center(tile)), tile,
		"The pointer still lands on the tile under it at a 15° view")


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func test_the_nearest_direction_rounds_from_any_angle() -> void:
	var projection := GridProjection.new()
	projection.set_orientation(0.2)
	assert_eq(projection.orientation_steps(), 0, "A little off north is still north")
	projection.set_orientation(0.4)
	assert_eq(projection.orientation_steps(), 0)
	projection.set_orientation(0.6)
	assert_eq(projection.orientation_steps(), 1, "Past halfway it reads east")
	projection.set_orientation(3.9)
	assert_eq(projection.orientation_steps(), 0, "And wraps home to north")


# ---------------------------------------------------------------------------
# The grid's gradual turns
# ---------------------------------------------------------------------------

func test_the_classic_mode_still_snaps_a_quarter_turn() -> void:
	var grid := make_grid(8, 8)
	assert_false(grid.is_gradual_view_rotation_enabled(), "Classic is the default")
	grid.rotate_view_cw()
	assert_false(grid.is_view_turning(), "Nothing animates")
	assert_eq(grid.get_view_orientation(), 1)
	assert_almost_eq(grid.get_view_angle(), 1.0, 0.0001)


func test_a_gradual_turn_animates_through_the_angles_between() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	var angles: Array[float] = []
	grid.view_rotated.connect(func(_orientation: int, _isometric: bool) -> void:
		angles.append(grid.get_view_angle()))

	grid.rotate_view_cw()
	assert_true(grid.is_view_turning(), "The turn is spread out instead of snapping")
	# Step the turn by hand, so the angles it passes through do not depend on
	# how fast the frame after this one happens to arrive.
	var turn: Tween = grid._view_turn
	assert_not_null(turn, "The turn is an animated tween")
	if turn == null:
		return
	turn.custom_step(TerrainGrid.GRADUAL_VIEW_TURN_SECONDS * 0.5)
	var midway := grid.get_view_angle()
	assert_gt(midway, 0.0, "The course has started to turn")
	assert_lt(midway, STEP, "but has not arrived yet")

	turn.custom_step(TerrainGrid.GRADUAL_VIEW_TURN_SECONDS)
	assert_false(grid.is_view_turning(), "The turn finishes")
	assert_almost_eq(grid.get_view_angle(), STEP, 0.0001,
		"One gradual step is a sixteenth of a full turn (15°)")
	assert_gte(angles.size(), 2, "The view was drawn at the angles in between")


func test_a_gradual_turn_settles_once_and_leaves_the_compass_alone() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	var settled := [0]
	grid.view_rotation_settled.connect(func() -> void: settled[0] += 1)

	grid.rotate_view_cw()
	await process_frames_until(func() -> bool: return not grid.is_view_turning(), 120)

	assert_eq(settled[0], 1, "The turn announced that it was done, once")
	assert_eq(grid.get_view_orientation(), 0,
		"15° does not reach the next of the four directions")


func test_six_gradual_steps_make_a_quarter_turn() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	for i in range(6):
		grid.rotate_view_cw()
		await process_frames_until(func() -> bool: return not grid.is_view_turning(), 120)
	assert_almost_eq(grid.get_view_angle(), 1.0, 0.0001, "Six 15° steps are 90°")
	assert_eq(grid.get_view_orientation(), 1, "and the compass reads east")


func test_a_held_turn_chains_onto_the_angle_it_is_already_heading_for() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	grid.rotate_view_cw()
	var first: Tween = grid._view_turn
	first.custom_step(TerrainGrid.GRADUAL_VIEW_TURN_SECONDS * 0.4)
	var before := grid.get_view_angle()
	assert_gt(before, 0.0)
	assert_lt(before, STEP)

	# A second press while the first is still animating must keep going, not
	# start again from the angle on screen.
	grid.rotate_view_cw()
	assert_true(grid.is_view_turning())
	var second: Tween = grid._view_turn
	second.custom_step(TerrainGrid.GRADUAL_VIEW_TURN_SECONDS * 2.0)

	assert_almost_eq(grid.get_view_angle(), STEP * 2.0, 0.0001,
		"Two quick presses turn twice as far")
	assert_gt(grid.get_view_angle(), before)


func test_a_turn_across_north_keeps_going_the_way_it_was_turned() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	grid.set_view_orientation(3.99)
	grid.rotate_view_cw()
	var first: Tween = grid._view_turn
	first.custom_step(TerrainGrid.GRADUAL_VIEW_TURN_SECONDS * 2.0)
	assert_almost_eq(grid.get_view_angle(), fposmod(3.99 + STEP, 4.0), 0.0001,
		"The turn crosses north into the start of the next turn")

	# An immediate second press has to carry on forward from just past north,
	# not animate the long way round to reach the same angle.
	grid.rotate_view_cw()
	var second: Tween = grid._view_turn
	second.custom_step(TerrainGrid.GRADUAL_VIEW_TURN_SECONDS * 0.5)
	var midway := grid.get_view_angle()
	assert_gt(midway, fposmod(3.99 + STEP, 4.0) - 0.001)
	assert_lt(midway, fposmod(3.99 + STEP * 2.0, 4.0) + 0.001)


func test_turning_gradual_rotation_off_settles_on_the_nearest_direction() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	grid.set_view_orientation(0.6)
	assert_almost_eq(grid.get_view_angle(), 0.6, 0.0001, "Between north and east")

	grid.set_gradual_view_rotation(false)
	assert_false(grid.is_view_turning())
	assert_almost_eq(grid.get_view_angle(), 1.0, 0.0001,
		"The classic view is grid aligned again")


func test_a_stored_preference_restores_gradual_rotation() -> void:
	var config := ConfigFile.new()
	config.set_value("camera", "gradual_view_rotation", true)
	SaveManager._apply_camera_settings(config)
	assert_true(GameManager.gradual_view_rotation,
		"A saved preference turns gradual rotation back on")

	var older := ConfigFile.new()
	older.set_value("camera", "min_zoom", 0.6)
	SaveManager._apply_camera_settings(older)
	assert_false(GameManager.gradual_view_rotation,
		"A settings file from before the preference keeps the four directions")


func test_a_loaded_angle_between_two_directions_is_restored() -> void:
	var grid := make_grid(8, 8)
	grid.set_gradual_view_rotation(true)
	grid.set_view_orientation(2.25)
	assert_almost_eq(grid.get_view_angle(), 2.25, 0.0001,
		"A load keeps the exact facing gradual rotation left the course at")
	assert_eq(grid.get_view_orientation(), 2,
		"while the four-way art and the compass read the nearest direction")

	grid.set_gradual_view_rotation(false)
	assert_almost_eq(grid.get_view_angle(), 2.0, 0.0001,
		"and the classic view settles back onto that direction")
