extends GameTest
## The course scorecard on the Holes tab: every hole on its nine with its par,
## yardage, stroke index and average, the course's header and totals, and the
## course's records beside them.

var view: CourseScorecardView

func before_each() -> void:
	super()
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.course_name = "Sandbelt Test"
	view = add_child_autofree(CourseScorecardView.new())

## Add `count` holes numbered from 1. Hole n plays n * 10 yards longer than
## 300, and its stroke index is n.
func _add_holes(count: int, par: int = 4) -> void:
	for n in range(1, count + 1):
		var hole := make_hole(n, Vector2i(n, 0), Vector2i(n, 5), par)
		hole.distance_yards = 300 + n * 10
		hole.stroke_index = n
		GameManager.current_course.add_hole(hole)

## The cell texts of one grid row, label cell first.
func _cells(row: HBoxContainer) -> Array:
	var texts: Array = []
	for cell in row.get_children():
		texts.append((cell.get_child(0) as Label).text)
	return texts

## The text of every label under `node`, in reading order.
func _label_texts(node: Node) -> Array:
	var texts: Array = []
	for label in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts

## Build the view and let its layout settle, as the Holes tab does once shown.
func _show() -> void:
	view.refresh()
	await process_frames(2)

## Each nine's grid has five rows: holes, yards, par, handicap and average.
func test_the_front_and_back_nines_each_get_a_grid_of_their_holes() -> void:
	_add_holes(18)
	await _show()

	var out_nine := view.find_child("OutNine", true, false) as VBoxContainer
	var in_nine := view.find_child("InNine", true, false) as VBoxContainer
	assert_not_null(out_nine, "Holes 1 to 9 form the OUT nine")
	assert_not_null(in_nine, "Holes 10 to 18 form the IN nine")
	assert_eq(out_nine.get_child_count(), 5, "A nine has five rows")

	var out_holes := _cells(out_nine.get_child(0))
	assert_eq(out_holes.slice(0, 10), ["Hole", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
		"The OUT nine's header names holes 1 to 9")
	assert_eq(out_holes[10], "OUT", "and its total cell says OUT")
	var in_holes := _cells(in_nine.get_child(0))
	assert_eq(in_holes.slice(1, 10), ["10", "11", "12", "13", "14", "15", "16", "17", "18"],
		"The IN nine's header names holes 10 to 18")
	assert_eq(in_holes[10], "IN", "and its total cell says IN")

	var par_row := _cells(out_nine.get_child(2))
	assert_eq(par_row[0], "Par", "The third row is par")
	assert_eq(par_row[10], "36", "The OUT nine's par totals 36")
	var hcp_row := _cells(out_nine.get_child(3))
	assert_eq(hcp_row.slice(1, 4), ["1", "2", "3"], "The handicap row carries each stroke index")

## Holes 1 to 18 play 300 + n * 10 yards, so the card totals 7110 yards.
func test_the_identity_and_totals_describe_the_whole_course() -> void:
	_add_holes(18)
	await _show()

	var identity := view.find_child("ScorecardIdentity", true, false)
	assert_eq((identity.get_child(0) as Label).text, "SANDBELT TEST",
		"The course's name heads the card, in capitals")
	var total := view.find_child("ScorecardTotal", true, false) as Label
	assert_not_null(total, "Both nines give a total line")
	assert_eq(total.text, "TOTAL:  Par 72  |  7110 yards", "which adds up both nines")

func test_a_one_nine_course_shows_only_its_nine() -> void:
	_add_holes(9)
	await _show()

	assert_not_null(view.find_child("OutNine", true, false), "The one nine is the OUT nine")
	assert_null(view.find_child("InNine", true, false), "There is no IN nine")
	assert_null(view.find_child("ScorecardTotal", true, false), "and no total to add up")

func test_a_course_with_no_holes_says_so() -> void:
	GameManager.current_course = null
	await _show()
	assert_eq(_label_texts(view), ["No holes created yet"],
		"With no course, the card says there are no holes yet")

	GameManager.current_course = GameManager.CourseData.new()
	await _show()
	assert_eq(_label_texts(view), ["No holes created yet"],
		"and so does a course with no holes on it")

## Average scores come from the hole statistics once a hole has rounds in it.
func test_average_scores_show_once_a_hole_has_been_played() -> void:
	_add_holes(9)
	var stats := GameManager.HoleStatistics.new(1)
	stats.total_rounds = 2
	stats.total_strokes = 7
	GameManager.hole_statistics[1] = stats
	await _show()

	var avg_row := _cells(view.find_child("OutNine", true, false).get_child(4))
	assert_eq(avg_row[0], "Avg", "The fifth row is the average")
	assert_eq(avg_row[1], "3.5", "Hole 1 averages its strokes over its rounds")
	assert_eq(avg_row[2], "-", "A hole nobody has played has no average yet")

func test_records_list_the_lowest_round_hole_in_ones_and_best_scores() -> void:
	_add_holes(9)
	GameManager.course_records["lowest_round"] = CourseRecords.RecordEntry.new("Ada", 34, 3, -1)
	GameManager.course_records["total_hole_in_ones"] = 1
	GameManager.course_records["best_per_hole"] = {1: CourseRecords.RecordEntry.new("Ada", 3, 3, 1)}
	await _show()

	var lines := view.find_child("RecordLines", true, false)
	var texts := _label_texts(lines)
	assert_has(texts, "Lowest Round: 34 (-2) by Ada (Day 3)",
		"The lowest round is set against the course's par of 36")
	assert_has(texts, "Holes-in-One: 1", "Holes-in-one are counted")
	assert_has(texts, "  #1: 3 (Birdie) - Ada", "Each hole's best score names its scorer")

func test_records_say_so_until_a_round_is_played() -> void:
	_add_holes(9)
	await _show()
	assert_has(_label_texts(view.find_child("RecordLines", true, false)),
		"Lowest Round: No rounds completed", "With no round played, the lowest round says so")

## The view is rebuilt from the live course, so a hole added since the last
## refresh appears on the next one.
func test_refresh_follows_the_course() -> void:
	_add_holes(1)
	await _show()
	var header := view.find_child("OutNine", true, false).get_child(0) as HBoxContainer
	assert_eq(_cells(header).slice(0, 2), ["Hole", "1"], "One hole on the card")

	var second := make_hole(2, Vector2i(2, 0), Vector2i(2, 5), 4)
	second.distance_yards = 320
	second.stroke_index = 2
	GameManager.current_course.add_hole(second)
	await _show()
	header = view.find_child("OutNine", true, false).get_child(0) as HBoxContainer
	assert_eq(_cells(header).slice(0, 3), ["Hole", "1", "2"],
		"A refresh rebuilds the nine from the holes now on the course")

## Reading down a long records list must not jump back to the top when the card
## is refreshed by a golfer finishing a hole.
func test_the_records_list_keeps_its_scroll_across_a_refresh() -> void:
	_add_holes(18)
	for n in range(1, 19):
		GameManager.course_records["best_per_hole"][n] = CourseRecords.RecordEntry.new(
			"Visitor %d" % n, 4, 1, n)
	await _show()

	var scroll := view.find_child("RecordsScroll", true, false) as ScrollContainer
	assert_not_null(scroll, "The records sit in a scrolling list")
	scroll.scroll_vertical = 40
	await process_frames(2)
	# Two refreshes in one frame: the first list is freed before its position
	# is put back, which must not fail.
	view.refresh()
	view.refresh()
	await process_frames(3)
	var rebuilt := view.find_child("RecordsScroll", true, false) as ScrollContainer
	assert_ne(rebuilt, scroll, "Each refresh builds a fresh list")
	assert_eq(rebuilt.scroll_vertical, 40, "and the new list is where the reader left the old one")

## Back is a button the view owns: pressing it asks the Holes tab for the register.
func test_the_back_button_asks_for_the_hole_register() -> void:
	await _show()
	watch_signals(view)
	(view.find_child("BackButton", false, false) as Button).pressed.emit()
	assert_signal_emitted(view, "back_requested")
