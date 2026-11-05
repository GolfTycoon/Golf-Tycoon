extends VBoxContainer
class_name CourseScorecardView
## The course scorecard inside the Course Map's Routing panel. The OUT and IN
## nines run down the dossier instead of across the old, wide Holes shelf, so all
## five columns fit beside the map on a tablet or phone. The enclosing map panel
## supplies the one vertical scroll for the card and its records.

signal hole_selected(hole_number: int)

## Fixed minimums keep the headings, hole rows and totals aligned, while the
## columns share any extra width. Even the narrow phone sheet fits all five.
const COLUMN_WIDTHS := [44.0, 50.0, 34.0, 36.0, 42.0]
const COLUMN_GAP := 2
const COLUMN_FONT_SIZE := 11

var compact := false
var _selected := -1
var _hole_buttons: Dictionary = {}

func _init() -> void:
	name = "CourseScorecard"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

func set_compact(value: bool) -> void:
	compact = value

## Selection is shared with the map and the routing list. Update the buttons in
## place rather than rebuilding the card, so focus and the reader's scroll stay.
func set_selected(hole_number: int) -> void:
	_selected = hole_number
	_sync_hole_buttons()

func _sync_hole_buttons() -> void:
	for number in _hole_buttons:
		var button := _hole_buttons[number] as Button
		if is_instance_valid(button):
			button.set_pressed_no_signal(int(number) == _selected)

## Rebuild from the live course. The parent owns scrolling, so records and both
## nines are read in a single continuous list rather than in nested scrolls.
func refresh() -> void:
	# A live update replaces the rows. Keep keyboard/gamepad focus on the same
	# hole rather than sending the reader back to the screen's Back button.
	var focused_hole := -1
	if is_inside_tree():
		var focused := get_viewport().gui_get_focus_owner()
		for number in _hole_buttons:
			if _hole_buttons[number] == focused:
				focused_hole = int(number)
				break
	_hole_buttons.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var course = GameManager.current_course
	if course == null or course.holes.is_empty():
		add_child(CourseMapStyle.hint("No holes created yet. Open a hole on the course to start the scorecard."))
		return

	var front: Array = []
	var back: Array = []
	for hole in course.holes:
		if hole.hole_number <= 9:
			front.append(hole)
		else:
			back.append(hole)
	front.sort_custom(func(a, b): return a.hole_number < b.hole_number)
	back.sort_custom(func(a, b): return a.hole_number < b.hole_number)

	add_child(_build_identity(course))
	if not front.is_empty():
		add_child(_build_nine(front, "OUT"))
	if not back.is_empty():
		add_child(_build_nine(back, "IN"))

	var note := CourseMapStyle.hint(
		"Tap a hole to find it on the map. * = manually set par. " \
		+ "Nine averages add the holes with recorded scores.")
	note.name = "ScorecardLegend"
	add_child(note)
	add_child(_build_records(course))
	if _hole_buttons.has(focused_hole):
		(_hole_buttons[focused_hole] as Button).grab_focus()

## Course identity and totals include every hole, as the old scorecard did.
func _build_identity(course) -> Control:
	var body := VBoxContainer.new()
	body.name = "ScorecardIdentity"
	body.add_theme_constant_override("separation", 4)
	body.add_child(CourseMapStyle.kicker("Course scorecard"))
	var title := CourseMapStyle.title(GameManager.course_name.to_upper(), 16, CourseMapStyle.GOLD)
	title.name = "CourseName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(title)

	var rating: Dictionary = GameManager.course_rating
	var details := CourseMapStyle.label("%s · Rating %.1f · Slope %d" % [
		CourseTheme.get_theme_name(GameManager.current_theme),
		float(rating.get("course_rating", 72.0)), int(rating.get("slope", 113))],
		11, CourseMapStyle.TEXT_SECONDARY)
	details.name = "CourseRating"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(details)

	var total_yards := 0
	var has_closed := false
	for hole in course.holes:
		total_yards += int(hole.distance_yards)
		has_closed = has_closed or not hole.is_open
	var stars := int(rating.get("stars", 0))
	var total := CourseMapStyle.label("%d star%s · Par %d · %d yards" % [
		stars, "" if stars == 1 else "s", int(course.total_par), total_yards],
		12, CourseMapStyle.TEXT_BRIGHT, CourseMapStyle.SUBTITLE_FONT)
	total.name = "ScorecardTotal"
	total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(total)
	if has_closed:
		body.add_child(CourseMapStyle.hint("Totals include closed holes."))
	return CourseMapStyle.framed(body, 8)

## One row per hole keeps a complete nine readable in the narrow dossier. The
## total average, like the old card, sums only holes that have been played.
func _build_nine(holes: Array, nine: String) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	body.add_child(CourseMapStyle.kicker("%s · %s nine" % [nine, "Front" if nine == "OUT" else "Back"]))

	var headings := _row("ColumnHeadings")
	for i in COLUMN_WIDTHS.size():
		headings.add_child(_column_label(["Hole", "Yards", "Par", "Hcp", "Avg"][i], i,
			CourseMapStyle.TEXT_QUIET))
	body.add_child(headings)

	var yards_sum := 0
	var par_sum := 0
	var avg_sum := 0.0
	var avg_par := 0
	var has_average := false
	for hole in holes:
		var number := int(hole.hole_number)
		var row := _row("HoleRow%d" % number)
		var pick := CourseMapStyle.choice(str(number), 11)
		pick.name = "Hole%d" % number
		pick.accessibility_name = "Select hole %d on the map" % number
		pick.tooltip_text = "Show hole %d on the map%s" % [number, " (closed)" if not hole.is_open else ""]
		pick.custom_minimum_size = Vector2(COLUMN_WIDTHS[0], 44 if compact else 30)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		CourseMapStyle.pad(pick, 4, 0)
		pick.set_pressed_no_signal(number == _selected)
		pick.pressed.connect(func():
			hole_selected.emit(number)
			_sync_hole_buttons())
		_hole_buttons[number] = pick
		row.add_child(pick)

		var yards := int(hole.distance_yards)
		var par := int(hole.par)
		yards_sum += yards
		par_sum += par
		row.add_child(_named_column("Yards", str(yards), 1))
		row.add_child(_named_column("Par", "%d%s" % [par, "*" if hole.par_override > 0 else ""], 2))
		row.add_child(_named_column("Hcp", str(hole.stroke_index) if hole.stroke_index > 0 else "-", 3))

		var stats: GameManager.HoleStatistics = GameManager.get_hole_statistics(number)
		if stats != null and stats.total_rounds > 0:
			var average := stats.get_average_score()
			avg_sum += average
			avg_par += par
			has_average = true
			row.add_child(_named_column("Average", "%.1f" % average, 4, _avg_color(average - par)))
		else:
			row.add_child(_named_column("Average", "-", 4, CourseMapStyle.TEXT_QUIET))
		body.add_child(row)

	var total := _row("%sTotal" % nine.capitalize())
	total.add_child(_column_label(nine, 0, CourseMapStyle.GOLD))
	total.add_child(_column_label(str(yards_sum), 1, CourseMapStyle.TEXT_BRIGHT))
	total.add_child(_column_label(str(par_sum), 2, CourseMapStyle.TEXT_BRIGHT))
	total.add_child(_column_label("-", 3, CourseMapStyle.TEXT_QUIET))
	total.add_child(_column_label("%.1f" % avg_sum if has_average else "-", 4,
		_avg_color(avg_sum - avg_par) if has_average else CourseMapStyle.TEXT_QUIET))
	body.add_child(total)

	var card := CourseMapStyle.framed(body, 7)
	card.name = "%sNine" % nine.capitalize()
	return card

func _row(node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", COLUMN_GAP)
	return row

func _named_column(node_name: String, text: String, column: int,
		color: Color = CourseMapStyle.TEXT_SECONDARY) -> Label:
	var cell := _column_label(text, column, color)
	cell.name = node_name
	return cell

func _column_label(text: String, column: int, color: Color) -> Label:
	var label := CourseMapStyle.label(text, COLUMN_FONT_SIZE, color)
	label.custom_minimum_size.x = COLUMN_WIDTHS[column]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	return label

func _build_records(course) -> Control:
	var body := VBoxContainer.new()
	body.name = "RecordLines"
	body.add_theme_constant_override("separation", 4)
	body.add_child(CourseMapStyle.kicker("Course records"))
	var records: Dictionary = GameManager.course_records
	var lowest = records.get("lowest_round")
	if lowest != null:
		var diff: int = int(lowest.value) - int(course.total_par)
		var to_par := "+%d" % diff if diff > 0 else (str(diff) if diff < 0 else "E")
		body.add_child(_record_label("Lowest Round: %d (%s) by %s (Day %d)" % [
			int(lowest.value), to_par, str(lowest.golfer_name), int(lowest.date_day)], CourseMapStyle.GOLD))
	else:
		body.add_child(_record_label("Lowest Round: No rounds completed", CourseMapStyle.TEXT_QUIET))

	var holes_in_one := int(records.get("total_hole_in_ones", 0))
	if holes_in_one > 0:
		body.add_child(_record_label("Holes-in-One: %d" % holes_in_one, CourseMapStyle.GOLD))

	var best_per_hole: Dictionary = records.get("best_per_hole", {})
	if not best_per_hole.is_empty():
		body.add_child(_record_label("Best Scores:", CourseMapStyle.TEXT_SECONDARY))
		var numbers := best_per_hole.keys()
		numbers.sort()
		for number in numbers:
			var record = best_per_hole[number]
			var par := 4
			for hole in course.holes:
				if hole.hole_number == number:
					par = int(hole.par)
					break
			var score_name := GolfRules.get_score_name(int(record.value), par)
			body.add_child(_record_label("#%d: %d (%s) - %s" % [number, record.value,
				score_name, record.golfer_name], UIConstants.get_score_color(int(record.value) - par)))

	var card := CourseMapStyle.framed(body, 8)
	card.name = "CourseRecords"
	return card

func _record_label(text: String, color: Color) -> Label:
	var label := CourseMapStyle.label(text, 11, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

static func _avg_color(avg_to_par: float) -> Color:
	if avg_to_par <= 0.0:
		return UIConstants.COLOR_SCORE_UNDER
	if avg_to_par <= 0.5:
		return UIConstants.COLOR_WARNING
	return UIConstants.COLOR_SCORE_OVER
