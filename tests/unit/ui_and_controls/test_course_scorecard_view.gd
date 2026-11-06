extends GameTest
## The Holes Map's scorecard: the course, its OUT/IN nines, live scoring and
## records, in a narrow table whose hole buttons pick the same map selection.

var view: CourseScorecardView

func before_each() -> void:
	super()
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.course_name = "Sandbelt Test"
	GameManager.hole_statistics.clear()
	GameManager.course_records = CourseRecords.create_empty_records()
	GameManager.course_rating = {"course_rating": 71.6, "slope": 127, "stars": 3}
	view = add_child_autofree(CourseScorecardView.new())

## Hole n plays n * 10 yards longer than 300, and its stroke index is n.
func _add_holes(count: int) -> void:
	for n in range(1, count + 1):
		var hole := make_hole(n, Vector2i(n, 0), Vector2i(n, 5), 4)
		hole.distance_yards = 300 + n * 10
		hole.stroke_index = n
		GameManager.current_course.add_hole(hole)

func _show() -> void:
	view.refresh()
	await process_frames(2)

func _row(number: int) -> HBoxContainer:
	return view.find_child("HoleRow%d" % number, true, false) as HBoxContainer

func _texts(node: Node) -> Array:
	var texts: Array = []
	for label in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts

func test_the_front_and_back_nines_show_each_hole_and_their_totals() -> void:
	_add_holes(18)
	# The course's storage order need not be the scorecard's display order.
	GameManager.current_course.holes.reverse()
	await _show()

	var out := view.find_child("OutNine", true, false)
	var back := view.find_child("InNine", true, false)
	assert_not_null(out, "Holes 1 to 9 form OUT")
	assert_not_null(back, "Holes 10 to 18 form IN")
	for n in range(1, 19):
		var row := _row(n)
		assert_not_null(row, "Hole %d has a row" % n)
		assert_eq((row.get_child(0) as Button).text, str(n))
		assert_eq((row.get_node("Yards") as Label).text, str(300 + n * 10))
		assert_eq((row.get_node("Par") as Label).text, "4")
		assert_eq((row.get_node("Hcp") as Label).text, str(n))
		assert_eq((row.get_node("Average") as Label).text, "-")
		if n > 1 and n != 10:
			assert_gt(row.get_index(), _row(n - 1).get_index(), "A nine is sorted by hole number")

	var out_total := out.find_child("OutTotal", true, false)
	var in_total := back.find_child("InTotal", true, false)
	assert_eq(_texts(out_total), ["OUT", "3150", "36", "-", "-"])
	assert_eq(_texts(in_total), ["IN", "3960", "36", "-", "-"])

func test_the_identity_carries_the_theme_rating_stars_and_course_totals() -> void:
	_add_holes(18)
	await _show()
	assert_eq((view.find_child("CourseName", true, false) as Label).text, "SANDBELT TEST")
	var details := (view.find_child("CourseRating", true, false) as Label).text
	assert_string_contains(details, CourseTheme.get_theme_name(GameManager.current_theme))
	assert_string_contains(details, "Rating 71.6")
	assert_string_contains(details, "Slope 127")
	assert_eq((view.find_child("ScorecardTotal", true, false) as Label).text,
		"3 stars · Par 72 · 7110 yards")

func test_an_empty_course_or_no_course_explains_what_is_missing() -> void:
	for course in [null, GameManager.CourseData.new()]:
		GameManager.current_course = course
		await _show()
		assert_string_contains(" ".join(_texts(view)), "No holes created yet")
		assert_null(view.find_child("OutNine", true, false))

func test_a_single_nine_and_an_in_only_course_show_just_their_own_table() -> void:
	_add_holes(9)
	await _show()
	assert_not_null(view.find_child("OutNine", true, false))
	assert_null(view.find_child("InNine", true, false))

	GameManager.current_course = GameManager.CourseData.new()
	var hole := make_hole(10, Vector2i(10, 0), Vector2i(10, 5), 4)
	GameManager.current_course.add_hole(hole)
	await _show()
	assert_null(view.find_child("OutNine", true, false))
	assert_not_null(view.find_child("InNine", true, false))

func test_manual_par_and_closed_holes_are_explained() -> void:
	_add_holes(2)
	var hole = GameManager.current_course.holes[0]
	hole.par = 5
	hole.par_override = 5
	hole.stroke_index = 0
	hole.is_open = false
	GameManager.current_course._recalculate_par()
	await _show()
	assert_eq((_row(1).get_node("Par") as Label).text, "5*")
	assert_eq((_row(1).get_node("Hcp") as Label).text, "-")
	assert_string_contains((_row(1).get_child(0) as Button).tooltip_text, "closed")
	assert_string_contains(" ".join(_texts(view)), "Totals include closed holes")
	assert_string_contains((view.find_child("ScorecardLegend", true, false) as Label).text, "manually set par")

func test_average_scores_and_partial_nine_total_keep_their_colours() -> void:
	_add_holes(4)
	for data in [[1, 7], [2, 9], [3, 10]]:
		var stats := GameManager.HoleStatistics.new(data[0])
		stats.total_rounds = 2
		stats.total_strokes = data[1]
		GameManager.hole_statistics[data[0]] = stats
	await _show()

	var expected := [["3.5", UIConstants.COLOR_SCORE_UNDER], ["4.5", UIConstants.COLOR_WARNING],
		["5.0", UIConstants.COLOR_SCORE_OVER]]
	for i in expected.size():
		var average := _row(i + 1).get_node("Average") as Label
		assert_eq(average.text, expected[i][0])
		assert_eq(average.get_theme_color("font_color"), expected[i][1])
	assert_eq((_row(4).get_node("Average") as Label).text, "-", "Unplayed holes have no average")
	var total := view.find_child("OutTotal", true, false)
	assert_eq((total.get_child(4) as Label).text, "13.0", "Only played holes contribute")
	assert_eq((total.get_child(4) as Label).get_theme_color("font_color"), UIConstants.COLOR_SCORE_OVER)
	assert_string_contains((view.find_child("ScorecardLegend", true, false) as Label).text, "recorded scores")

func test_records_list_lowest_round_holes_in_one_and_best_per_hole() -> void:
	_add_holes(9)
	GameManager.course_records["lowest_round"] = CourseRecords.RecordEntry.new("Ada", 34, 3, -1)
	GameManager.course_records["total_hole_in_ones"] = 1
	GameManager.course_records["best_per_hole"] = {
		2: CourseRecords.RecordEntry.new("Lin", 4, 4, 2),
		1: CourseRecords.RecordEntry.new("Ada", 3, 3, 1),
	}
	await _show()
	var texts := _texts(view.find_child("RecordLines", true, false))
	assert_has(texts, "Lowest Round: 34 (-2) by Ada (Day 3)")
	assert_has(texts, "Holes-in-One: 1")
	assert_has(texts, "#1: 3 (Birdie) - Ada")
	assert_has(texts, "#2: 4 (Par) - Lin")
	assert_lt(texts.find("#1: 3 (Birdie) - Ada"), texts.find("#2: 4 (Par) - Lin"))

func test_records_say_when_no_round_has_been_played() -> void:
	_add_holes(1)
	await _show()
	assert_has(_texts(view.find_child("RecordLines", true, false)), "Lowest Round: No rounds completed")

func test_hole_buttons_emit_selection_and_follow_the_map_selection() -> void:
	_add_holes(2)
	await _show()
	watch_signals(view)
	var first := _row(1).get_child(0) as Button
	var second := _row(2).get_child(0) as Button
	first.pressed.emit()
	assert_signal_emitted_with_parameters(view, "hole_selected", [1])
	view.set_selected(2)
	assert_false(first.button_pressed)
	assert_true(second.button_pressed)
	assert_eq(first.accessibility_name, "Select hole 1 on the map")
	view.set_selected(-1)
	assert_false(second.button_pressed)

func test_refresh_rebuilds_the_card_from_the_live_course() -> void:
	_add_holes(1)
	await _show()
	assert_null(_row(2))
	var second := make_hole(2, Vector2i(2, 0), Vector2i(2, 5), 4)
	second.distance_yards = 320
	GameManager.current_course.add_hole(second)
	await _show()
	assert_not_null(_row(2))
	assert_eq((_row(2).get_node("Yards") as Label).text, "320")
