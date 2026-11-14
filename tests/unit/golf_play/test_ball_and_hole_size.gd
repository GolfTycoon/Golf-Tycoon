extends GameTest
## The size of a golf ball, and the hole cut under the flag that matches it.
##
## Balls used to be drawn at a 4 px radius; they are smaller now. The hole under
## every flag is cut to exactly the ball's width, so the black disc a player
## putts into is as wide as the ball they are putting — under the gold pin of a
## cup still waiting for a tee box and under the red pin of an open hole alike.
## Every ball also lays one contact shadow on the ground: beneath it at rest,
## and on its ground track while it flies.

const CUP := Vector2i(3, 3)
const OPEN_HOLE_CUP := Vector2i(5, 5)

## What the ball was drawn at before it was shrunk.
const OLD_BALL_RADIUS := 4.0

var grid: TerrainGrid
var overlay: CupOverlay

var _original_shadow_detail: int
var _original_preset: int

func before_each() -> void:
	super()
	# Test machines pick Auto, which can be the low-detail profile with shadows
	# off. The shadow tests need a ball that is allowed to paint one.
	_original_shadow_detail = PerformanceSettings.shadow_detail
	_original_preset = PerformanceSettings.graphics_preset
	PerformanceSettings.set_graphics_setting(
			PerformanceSettings.GraphicsSetting.SHADOW_DETAIL,
			PerformanceSettings.ShadowDetail.CONTACT_ONLY)
	GameManager.current_course = GameManager.CourseData.new()

	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)

	overlay = CupOverlay.new()
	add_child_autofree(overlay)
	overlay.initialize(grid)

func after_each() -> void:
	PerformanceSettings.set_graphics_setting(
			PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, _original_shadow_detail)
	PerformanceSettings.set_graphics_preset(_original_preset)
	super()

func _ball() -> Ball:
	var ball := Ball.new()
	add_child_autofree(ball)
	return ball

## The ball's own polygon: the first shape in the visual node the most recent
## _update_visual() built. Every state draws the ball before its motion blur or
## splash, and the newest visual is always the last child; the contact shadow
## is the Ball's own GroundShadow node, painted before the visual.
func _drawn_ball(ball: Ball) -> Polygon2D:
	var visual := ball.get_child(ball.get_child_count() - 1)
	for node in visual.get_children():
		if node is Polygon2D:
			return node
	return null

func _shadow(ball: Ball) -> Polygon2D:
	return ball.get_node("GroundShadow")

func _widest(polygon: Polygon2D) -> float:
	var widest := 0.0
	for point in polygon.polygon:
		widest = maxf(widest, point.length())
	return widest

func _hole_extents(pos: Vector2i) -> Vector2:
	var polygon := CupOverlay.hole_polygon(grid, overlay, pos)
	var center := OverlayGeometry.tile_center(grid, overlay, pos)
	var extents := Vector2.ZERO
	for point in polygon:
		extents.x = maxf(extents.x, absf(point.x - center.x))
		extents.y = maxf(extents.y, absf(point.y - center.y))
	return extents

func _paint_cup(pos: Vector2i) -> void:
	grid.set_tile(pos, TerrainTypes.Type.GREEN)
	assert_true(grid.add_cup_tile(pos))

func _open_hole_at(pos: Vector2i) -> void:
	grid.set_tile(pos, TerrainTypes.Type.GREEN)
	var hole := GameManager.HoleData.new()
	hole.hole_number = GameManager.course_data.holes.size() + 1
	hole.hole_position = pos
	GameManager.course_data.holes.append(hole)


# ---------------------------------------------------------------------------
# The golf ball
# ---------------------------------------------------------------------------

func test_the_ball_is_drawn_smaller_than_it_used_to_be() -> void:
	var ball := _ball()
	assert_almost_eq(_widest(_drawn_ball(ball)), Ball.BALL_RADIUS, 0.001,
			"The ball at rest is drawn at Ball.BALL_RADIUS")
	assert_lt(Ball.BALL_RADIUS, OLD_BALL_RADIUS,
			"The ball used to be drawn at a %s px radius" % OLD_BALL_RADIUS)

func test_every_ball_state_draws_a_ball_the_same_size() -> void:
	var ball := _ball()
	for state in [Ball.BallState.IN_FLIGHT, Ball.BallState.IN_WATER,
			Ball.BallState.OUT_OF_BOUNDS, Ball.BallState.ROLLING, Ball.BallState.AT_REST]:
		ball._change_state(state)
		var expected := Ball.FLIGHT_RADIUS if state == Ball.BallState.IN_FLIGHT else Ball.BALL_RADIUS
		assert_almost_eq(_widest(_drawn_ball(ball)), expected, 0.001,
				"State %s keeps the one ball size" % Ball.BallState.keys()[state])
		assert_lt(expected, OLD_BALL_RADIUS + 1.0,
				"State %s is smaller than the old airborne ball" % Ball.BallState.keys()[state])


# ---------------------------------------------------------------------------
# The ball's shadow
# ---------------------------------------------------------------------------

## How wide the shadow paints on screen, after both its own shrink and the
## ball's flight depth scale have been applied.
func _shadow_footprint(ball: Ball) -> float:
	var shadow := _shadow(ball)
	var widest := 0.0
	for point in shadow.polygon:
		widest = maxf(widest, absf(point.x))
	return widest * shadow.scale.x * ball.scale.x

func test_every_ball_state_rests_on_a_contact_shadow() -> void:
	var ball := _ball()
	for state in [Ball.BallState.IN_FLIGHT, Ball.BallState.IN_WATER,
			Ball.BallState.OUT_OF_BOUNDS, Ball.BallState.ROLLING, Ball.BallState.AT_REST]:
		ball._change_state(state)
		var state_name: String = Ball.BallState.keys()[state]
		assert_true(ball.has_node("GroundShadow"),
				"State %s keeps the ball's one contact shadow" % state_name)
		var shadow := _shadow(ball)
		assert_true(shadow.visible, "State %s draws it" % state_name)
		assert_eq(shadow.get_index(), 0, "State %s paints it beneath the ball" % state_name)
		assert_gt(shadow.color.a, 0.0)
		assert_lt(shadow.color.a, 0.5, "a small ball needs a soft shadow, not a black disc")

		# One shadow, and it is flat on the ground: wider across the tile than up
		# the screen, the way the isometric view squashes a circle.
		var extents: Vector2 = Vector2.ZERO
		for point in shadow.polygon:
			extents.x = maxf(extents.x, absf(point.x))
			extents.y = maxf(extents.y, absf(point.y))
		assert_gt(extents.x, extents.y, "State %s lies flat" % state_name)
	assert_eq(ball.get_children().filter(
			func(node: Node) -> bool: return node.name == "GroundShadow").size(), 1,
			"A ball carries exactly one shadow through every state")

func test_the_shadow_sits_under_the_ball_at_rest() -> void:
	var ball := _ball()
	ball.global_position = Vector2(40, 60)
	var shadow := _shadow(ball)
	assert_gt(shadow.global_position.y, ball.global_position.y,
			"The shadow is below the ball, not beside it")
	assert_lt(shadow.global_position.y, ball.global_position.y + Ball.BALL_RADIUS * 2.0,
			"It is a contact shadow at the ball's foot, not a stain across the tile")
	assert_almost_eq(shadow.global_position.x, ball.global_position.x + Ball.SHADOW_OFFSET.x * Ball.BALL_RADIUS, 0.001)

func test_the_shadow_stays_on_the_ground_while_the_ball_flies() -> void:
	var ball := _ball()
	ball.start_flight_screen_with_arc(Vector2(100, 200), Vector2(300, 200), 1.0)
	# Halfway through a 200 px carry the arc peaks at 60 px (30% of the distance).
	ball._process_flight(0.5)

	assert_almost_eq(ball.global_position.y, 140.0, 0.01,
			"the ball is at the top of its arc")
	var shadow := _shadow(ball)
	assert_almost_eq(shadow.global_position.y, 200.0 + Ball.SHADOW_OFFSET.y * Ball.BALL_RADIUS, 0.01,
			"the shadow stays down on the ground the ball is flying over")
	assert_gt(shadow.global_position.y, ball.global_position.y + Ball.FLIGHT_RADIUS,
			"the ball is clearly in the air above its shadow")
	assert_almost_eq(shadow.global_position.x, ball.global_position.x + Ball.SHADOW_OFFSET.x * Ball.BALL_RADIUS, 0.01,
			"the shadow keeps the ball's line of flight")

func test_the_shadow_tightens_and_fades_as_the_ball_rises() -> void:
	var ball := _ball()
	var resting_footprint := _shadow_footprint(ball)
	var resting_alpha := _shadow(ball).color.a

	ball.start_flight_screen_with_arc(Vector2(100, 200), Vector2(300, 200), 1.0)
	ball._process_flight(0.5)  # top of the arc
	assert_lt(_shadow_footprint(ball), resting_footprint,
			"the shadow tightens while the ball is high")
	assert_lt(_shadow(ball).color.a, resting_alpha,
			"and fades, so the height reads")

	ball._process_flight(0.5)  # landing
	assert_almost_eq(_shadow_footprint(ball), resting_footprint, 0.001,
			"the shadow settles back to its full size once the ball lands")
	assert_almost_eq(_shadow(ball).color.a, resting_alpha, 0.001,
			"and to full darkness")

func test_switching_contact_shadows_off_hides_the_ball_shadow() -> void:
	var ball := _ball()
	assert_true(_shadow(ball).visible)

	PerformanceSettings.set_graphics_setting(
			PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.OFF)
	assert_false(_shadow(ball).visible,
			"a ball already on the course follows the Display page")

	PerformanceSettings.set_graphics_setting(
			PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.CONTACT_ONLY)
	assert_true(_shadow(ball).visible, "contact-only keeps the ball grounded")


# ---------------------------------------------------------------------------
# The hole under the flag
# ---------------------------------------------------------------------------

func test_the_hole_is_cut_to_the_golf_balls_width() -> void:
	assert_eq(CupOverlay.hole_radius(), Ball.BALL_RADIUS, "The hole is as wide as the ball")

	_paint_cup(CUP)
	var extents := _hole_extents(CUP)
	assert_almost_eq(extents.x * 2.0, Ball.BALL_RADIUS * 2.0, 0.001,
			"The black disc is exactly the ball's diameter across")
	assert_almost_eq(CupOverlay.hole_radius() * 2.0, Ball.BALL_RADIUS * 2.0, 0.001)

func test_the_hole_lies_flat_on_the_green_rather_than_facing_the_camera() -> void:
	_paint_cup(CUP)
	var extents := _hole_extents(CUP)
	assert_lt(extents.y, extents.x, "The hole is squashed, not a circle on the screen")
	assert_almost_eq(extents.y / extents.x, float(grid.tile_height) / float(grid.tile_width), 0.001,
			"Squashed exactly the way the tile under it is")

func test_every_flag_gets_a_hole_under_it() -> void:
	_paint_cup(CUP)
	_open_hole_at(OPEN_HOLE_CUP)

	var tiles := overlay.hole_tiles()
	assert_has(tiles, CUP, "The waiting cup keeps its hole")
	assert_has(tiles, OPEN_HOLE_CUP, "An open hole's flag stands in a hole too")
	assert_eq(tiles.size(), 2, "One hole per flag")

func test_a_cup_an_open_hole_claims_is_only_cut_once() -> void:
	_paint_cup(CUP)
	_open_hole_at(CUP)
	assert_eq(overlay.hole_tiles(), [CUP], "A tile carries one hole, waiting cup or open hole")

func test_a_course_without_flags_has_no_holes_in_the_ground() -> void:
	assert_eq(overlay.hole_tiles(), [], "Nothing to cut until a cup exists")
