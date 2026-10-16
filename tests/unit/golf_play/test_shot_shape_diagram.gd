extends GameTest
## The shot-type buttons' legends (`ShotShapeDiagram`): each button's picture of
## its own arc and roll, built from the aim guide's profile so the two can never
## disagree, and fitted at one shared scale so the five compare side by side.

func _box() -> Rect2:
	return Rect2(Vector2.ZERO, ShotShapeDiagram.DIAGRAM_SIZE)

func _diagram(shape: int) -> ShotShapeDiagram:
	var diagram := ShotShapeDiagram.new()
	diagram.shape = shape
	add_child_autofree(diagram)
	return diagram

## The corners of everything a fitted geometry draws, so a test can hold the
## whole legend inside the slot its button reserves.
func _enclosure(geometry: Dictionary) -> Rect2:
	var rect := Rect2(geometry["origin"], Vector2.ZERO)
	for key in ["arc", "ground", "roll", "roll_dots", "arrow"]:
		var points: PackedVector2Array = geometry[key]
		for point in points:
			rect = rect.expand(point)
	return rect

# ============================================================================
# PROFILE
# ============================================================================

func test_the_legend_is_the_guides_own_profile() -> void:
	for shape in ShotShapeDiagram.SHOT_COUNT:
		var profile := ShotShapeDiagram.profile(shape)
		assert_eq(profile["roll_ratio"], AimGuide.roll_ratio_for_shape(shape),
			"shape %d rolls the way the guide rolls" % shape)
		assert_eq(profile["arc_scale"], AimGuide.arc_scale_for_shape(shape),
			"shape %d lofts the way the guide lofts" % shape)
		assert_eq(profile["bend_deg"], Golfer.shape_bend_degrees(shape),
			"shape %d bends the way the shot bends" % shape)
		# The rest point is one unit from the ball, carry and roll together.
		var roll: float = profile["roll_length"]
		var carry: float = profile["carry_length"]
		var total := carry + roll if not profile["reversed"] else carry - roll
		assert_almost_eq(total, 1.0, 0.0001, "shape %d's carry and roll reach the rest point" % shape)

func test_backspin_checks_back_while_the_others_run_on() -> void:
	var backspin := ShotShapeDiagram.profile(3)
	assert_true(backspin["reversed"], "Backspin reverses its rollout")
	assert_gt(backspin["carry_length"], 1.0, "so it lands past where it will rest")
	for shape in [0, 1, 2, 4]:
		var profile := ShotShapeDiagram.profile(shape)
		assert_false(profile["reversed"], "shape %d rolls forward" % shape)
		assert_lt(profile["carry_length"], 1.0, "landing short of its rest")
	var geometry := ShotShapeDiagram.build_geometry(3, _box())
	assert_gt(geometry["carry"].distance_to(geometry["origin"]),
		geometry["rest"].distance_to(geometry["origin"]),
		"the drawn carry sits beyond the rest point")
	assert_gte((geometry["arrow"] as PackedVector2Array).size(), 3,
		"and carries the guide's arrow back toward the ball")
	for shape in [0, 4]:
		var forward := ShotShapeDiagram.build_geometry(shape, _box())
		assert_eq((forward["arrow"] as PackedVector2Array).size(), 0,
			"a forward roll needs no arrow")

func test_the_arcs_and_rolls_rank_the_way_the_shots_do() -> void:
	var apex: Array[float] = []
	var roll: Array[float] = []
	for shape in ShotShapeDiagram.SHOT_COUNT:
		var geometry := ShotShapeDiagram.build_geometry(shape, _box())
		apex.append(geometry["apex_height"])
		roll.append(geometry["roll_length"])
	assert_gt(apex[3], apex[0], "Backspin climbs highest")
	assert_gt(apex[0], apex[4], "Punch stays lowest")
	assert_almost_eq(apex[1], apex[0], 0.0001, "a fade flies the standard arc")
	assert_almost_eq(apex[2], apex[0], 0.0001, "and so does a draw")
	assert_gt(roll[4], roll[0], "Punch runs on furthest")
	assert_gt(roll[0], roll[3], "Backspin gives back some of its roll")
	assert_gt(roll[3], 0.0, "but still shows a roll, reversed")

func test_fade_and_draw_bend_as_mirror_images() -> void:
	var fade := ShotShapeDiagram.build_geometry(1, _box())
	var draw := ShotShapeDiagram.build_geometry(2, _box())
	var straight := ShotShapeDiagram.build_geometry(0, _box())
	var fade_bend: Vector2 = fade["bend"]
	var draw_bend: Vector2 = draw["bend"]
	assert_gt(fade_bend.length(), 1.0, "A fade bows off the line")
	assert_almost_eq(fade_bend.x, -draw_bend.x, 0.0001, "a draw bows the same distance")
	assert_almost_eq(fade_bend.y, -draw_bend.y, 0.0001, "the other way")
	for shape in [0, 3, 4]:
		var geometry := ShotShapeDiagram.build_geometry(shape, _box())
		assert_almost_eq((geometry["bend"] as Vector2).length(), 0.0, 0.0001,
			"shape %d flies straight" % shape)
	# The bow shows up in the flight, at mid-flight, in opposite directions.
	var mid := int(ShotShapeDiagram.ARC_STEPS / 2.0)
	var fade_arc: PackedVector2Array = fade["arc"]
	var draw_arc: PackedVector2Array = draw["arc"]
	var straight_arc: PackedVector2Array = straight["arc"]
	var fade_off := fade_arc[mid] - straight_arc[mid]
	var draw_off := draw_arc[mid] - straight_arc[mid]
	assert_gt(fade_off.length(), 1.0, "the fade's mid-flight point leaves the straight line")
	assert_almost_eq(fade_off.x, -draw_off.x, 0.0001, "the draw's leaves it the other way")
	assert_almost_eq(fade_off.y, -draw_off.y, 0.0001)

# ============================================================================
# FIT
# ============================================================================

func test_every_legend_draws_at_one_shared_scale() -> void:
	var first: float = ShotShapeDiagram.build_geometry(0, _box())["scale"]
	for shape in ShotShapeDiagram.SHOT_COUNT:
		var geometry := ShotShapeDiagram.build_geometry(shape, _box())
		assert_almost_eq(float(geometry["scale"]), first, 0.0001,
			"shape %d keeps the row's common scale" % shape)

func test_no_legend_ever_spills_out_of_its_slot() -> void:
	for box in [Rect2(Vector2.ZERO, ShotShapeDiagram.DIAGRAM_SIZE),
			Rect2(Vector2(2, 3), Vector2(44, 26)),
			Rect2(Vector2.ZERO, Vector2(30, 26)),
			Rect2(Vector2.ZERO, Vector2(16, 10)),
			Rect2(Vector2.ZERO, Vector2(5, 5))]:
		for shape in ShotShapeDiagram.SHOT_COUNT:
			var geometry := ShotShapeDiagram.build_geometry(shape, box)
			var enclosure := _enclosure(geometry)
			assert_true(box.grow(0.01).encloses(enclosure),
				"shape %d in %s draws inside its slot (%s)" % [shape, box, enclosure])

## What is centred is the frame the five legends share: the union of all their
## profiles sits in the middle of the slot, filling the axis that binds. Each
## legend then occupies its own part of that frame — a punch's flat flight sits
## low in the slot precisely because backspin's climbs to the top of it.
func test_the_shared_frame_is_centred_in_its_slot() -> void:
	var box := _box()
	var union := Rect2()
	for shape in ShotShapeDiagram.SHOT_COUNT:
		var enclosure := _enclosure(ShotShapeDiagram.build_geometry(shape, box))
		union = enclosure if union.size.x <= 0.0 and union.size.y <= 0.0 else union.merge(enclosure)
	assert_almost_eq(union.get_center().x, box.get_center().x, 0.01,
		"the shared frame is centred across the slot")
	assert_almost_eq(union.get_center().y, box.get_center().y, 0.01,
		"the shared frame is centred down the slot")
	assert_almost_eq(union.size.y, box.size.y, 0.01,
		"and the tallest legend — backspin's — fills the slot's height")

func test_a_slot_with_no_area_draws_nothing() -> void:
	for box in [Rect2(), Rect2(Vector2.ZERO, Vector2(0, 26)), Rect2(Vector2.ZERO, Vector2(44, 0))]:
		assert_true(ShotShapeDiagram.build_geometry(0, box).is_empty(),
			"%s has no room for a legend" % box)
	assert_true(ShotShapeDiagram.fit_transform(Rect2()).is_empty())

func test_out_of_range_shapes_fall_back_into_range() -> void:
	var diagram := _diagram(0)
	diagram.shape = 99
	assert_eq(diagram.shape, ShotShapeDiagram.SHOT_COUNT - 1)
	diagram.shape = -4
	assert_eq(diagram.shape, 0)
	var geometry := ShotShapeDiagram.build_geometry(77, _box())
	assert_eq(geometry["shape"], ShotShapeDiagram.SHOT_COUNT - 1,
		"the geometry clamps rather than indexing past the shots")

# ============================================================================
# DRAWING
# ============================================================================

func test_the_legend_paints_flight_roll_and_markers() -> void:
	var diagram := _diagram(0)
	var canvas := RecordingCanvas.new()
	diagram._paint(canvas)
	assert_gte(canvas.polylines, 3, "ground reference, flight and rollout")
	assert_eq(canvas.arcs, 1, "the carry ring")
	assert_gte(canvas.circles, 4, "the roll dots and the ball")
	var backspin := _diagram(3)
	var spin_canvas := RecordingCanvas.new()
	backspin._paint(spin_canvas)
	assert_eq(spin_canvas.polylines, canvas.polylines + 1,
		"backspin adds its arrow back toward the ball")

func test_a_greyed_shot_keeps_its_picture_in_muted_grey() -> void:
	var diagram := _diagram(1)
	var lit := RecordingCanvas.new()
	diagram._paint(lit)
	assert_gt(lit.count_color(ShotShapeDiagram.line_color(1, true)), 0,
		"a live shot draws in the guide's gold")
	diagram.enabled = false
	var muted := RecordingCanvas.new()
	diagram._paint(muted)
	assert_eq(muted.count_color(ShotShapeDiagram.line_color(1, true)), 0,
		"the gold is gone")
	assert_gt(muted.count_color(ShotShapeDiagram.line_color(1, false)), 0,
		"and the muted grey is in")
	var backspin := _diagram(3)
	var spin := RecordingCanvas.new()
	backspin._paint(spin)
	assert_gt(spin.count_color(AimGuide.BACKSPIN_COLOR), 0,
		"backspin keeps the guide's violet")

func test_a_legend_with_no_room_paints_nothing() -> void:
	var diagram := _diagram(2)
	diagram.size = Vector2.ZERO
	var canvas := RecordingCanvas.new()
	diagram._paint(canvas)
	assert_eq(canvas.calls, 0, "an unplaced legend stays blank")

## Draws nothing; records what the legend asked a canvas to draw.
class RecordingCanvas:
	var calls := 0
	var polylines := 0
	var arcs := 0
	var circles := 0
	var colors: Array = []

	func draw_polyline(_points: PackedVector2Array, color: Color, _width: float = -1.0,
			_aa: bool = false) -> void:
		calls += 1
		polylines += 1
		colors.append(color)

	func draw_circle(_position: Vector2, _radius: float, color: Color, _filled: bool = true,
			_width: float = -1.0, _aa: bool = false) -> void:
		calls += 1
		circles += 1
		colors.append(color)

	func draw_arc(_center: Vector2, _radius: float, _from: float, _to: float, _points: int,
			color: Color, _width: float = -1.0, _aa: bool = false) -> void:
		calls += 1
		arcs += 1
		colors.append(color)

	func draw_line(_from: Vector2, _to: Vector2, color: Color, _width: float = -1.0,
			_aa: bool = false) -> void:
		calls += 1
		polylines += 1
		colors.append(color)

	func count_color(color: Color) -> int:
		var count := 0
		for seen in colors:
			if (seen as Color).is_equal_approx(color):
				count += 1
		return count
