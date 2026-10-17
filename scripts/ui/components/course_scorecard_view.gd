extends HBoxContainer
class_name CourseScorecardView
## The course scorecard, shown on the Holes tab in place of the hole register.
## Every hole with its par, yardage, stroke index and average score, split into
## the OUT and IN nines the way a printed card is, with the course's records
## beside them. The Holes tab's Scorecard card opens it, and so does the K
## shortcut. It replaces the old Course Scorecard popup.

## The back button asks the Holes tab for the hole register again.
signal back_requested

# Grid cell styling
const CELL_WIDTH := 36
const LABEL_COL_WIDTH := 54
const TOTAL_COL_WIDTH := 44
const ROW_HEIGHT := 22
const TITLE_FONT_SIZE := 16
const SECTION_FONT_SIZE := 13
const CELL_FONT_SIZE := 11
## The records list scrolls inside its own column, so a long list of best
## scores never grows the Holes tab past the bottom bar's height.
const RECORDS_WIDTH := 300.0
const RECORDS_HEIGHT := 120.0

const BG_HEADER_ROW := Color(0.18, 0.35, 0.24, 0.9)  # Green header
const BG_DATA_ROW_A := Color(0.14, 0.14, 0.14)
const BG_DATA_ROW_B := Color(0.11, 0.11, 0.11)
const BORDER_COLOR := Color(0.25, 0.25, 0.25)

## Marks a records list that has been given its scroll position.
const SCROLL_RESTORED_META := "scroll_restored"

var _content: HBoxContainer = null
var _records_scroll: ScrollContainer = null
var _records_scroll_to := 0  # Where the reader has the records list scrolled to

func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var back := Button.new()
	back.name = "BackButton"
	back.text = "< Holes"
	back.tooltip_text = "Return to the course holes list"
	back.add_theme_font_size_override("font_size", 12)
	PixelButtonStyle.paint_card(back, Color("e2c681"), 0, 6, Color("e4e7d5"), Color.WHITE)
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)

	_content = HBoxContainer.new()
	_content.name = "ScorecardContent"
	_content.add_theme_constant_override("separation", 14)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)

## Rebuild the card from the live course. The records list keeps its scroll
## position, so a refresh while the player is reading it does not jump back.
func refresh() -> void:
	# A list that has not been given its position yet keeps the place it was
	# last given, so two refreshes in one frame still land where the reader is.
	if is_instance_valid(_records_scroll) and _records_scroll.has_meta(SCROLL_RESTORED_META):
		_records_scroll_to = int(_records_scroll.scroll_vertical)
	_records_scroll = null
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	if not GameManager.current_course or GameManager.current_course.holes.is_empty():
		_content.add_child(_label("No holes created yet", CELL_FONT_SIZE, UIConstants.COLOR_TEXT_MUTED))
		return

	var course = GameManager.current_course
	var holes: Array = course.holes

	# Split into front/back nine, each sorted by hole number
	var front_holes: Array = []
	var back_holes: Array = []
	for hole in holes:
		if hole.hole_number <= 9:
			front_holes.append(hole)
		else:
			back_holes.append(hole)
	front_holes.sort_custom(func(a, b): return a.hole_number < b.hole_number)
	back_holes.sort_custom(func(a, b): return a.hole_number < b.hole_number)

	_content.add_child(_build_identity(course, holes, front_holes, back_holes))

	# Build scorecard grid(s), one column per nine
	if back_holes.is_empty():
		_content.add_child(_build_nine_grid(front_holes, "OUT"))
	elif front_holes.is_empty():
		_content.add_child(_build_nine_grid(back_holes, "IN"))
	else:
		_content.add_child(_build_nine_grid(front_holes, "OUT"))
		_content.add_child(_build_nine_grid(back_holes, "IN"))

	# Course records section
	var separator := VSeparator.new()
	_content.add_child(separator)
	_content.add_child(_build_records_section())

	# The list only takes its scroll once it has been laid out, so the position
	# is put back a frame later. The list is looked up again by id then, since a
	# second refresh in the same frame frees this one first.
	if is_instance_valid(_records_scroll):
		call_deferred("_restore_records_scroll", _records_scroll.get_instance_id())

func _restore_records_scroll(scroll_id: int) -> void:
	var scroll := instance_from_id(scroll_id) as ScrollContainer
	if is_instance_valid(scroll):
		scroll.scroll_vertical = _records_scroll_to
		scroll.set_meta(SCROLL_RESTORED_META, true)

## The course's name and rating, and the card's totals beside the nines.
func _build_identity(course, holes: Array, front_holes: Array, back_holes: Array) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "ScorecardIdentity"
	column.add_theme_constant_override("separation", 2)

	column.add_child(_label(GameManager.course_name.to_upper(), TITLE_FONT_SIZE, Color("e2c681")))

	var total_yardage := 0
	for hole in holes:
		total_yardage += hole.distance_yards
	var rating = GameManager.course_rating
	var theme_name := CourseTheme.get_theme_name(GameManager.current_theme)
	column.add_child(_label("%s  |  Rating: %.1f  |  Slope: %d" % [
		theme_name,
		rating.get("course_rating", 72.0),
		rating.get("slope", 113),
	], CELL_FONT_SIZE, UIConstants.COLOR_TEXT_DIM))
	var stars_text: String = "*".repeat(int(rating.get("stars", 0)))
	column.add_child(_label("%s  |  Par %d  |  %d yds" % [stars_text, course.total_par, total_yardage],
		CELL_FONT_SIZE, UIConstants.COLOR_TEXT_DIM))

	if not front_holes.is_empty() and not back_holes.is_empty():
		var front_par := 0
		var front_yards := 0
		var back_par := 0
		var back_yards := 0
		for h in front_holes:
			front_par += h.par
			front_yards += h.distance_yards
		for h in back_holes:
			back_par += h.par
			back_yards += h.distance_yards
		var total_label := _label("TOTAL:  Par %d  |  %d yards" % [front_par + back_par, front_yards + back_yards],
			CELL_FONT_SIZE, UIConstants.COLOR_TEXT_DIM)
		total_label.name = "ScorecardTotal"
		column.add_child(total_label)
	return column

func _build_nine_grid(holes: Array, label: String) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.name = "%sNine" % label.capitalize()
	container.add_theme_constant_override("separation", 0)

	# Row 1: Hole numbers
	container.add_child(_build_row("Hole", holes.map(func(h): return str(h.hole_number)), label, BG_HEADER_ROW, Color.WHITE))

	# Row 2: Yardage
	var yard_sum := 0
	for h in holes:
		yard_sum += h.distance_yards
	container.add_child(_build_row("Yards", holes.map(func(h): return str(h.distance_yards)), str(yard_sum), BG_DATA_ROW_A, UIConstants.COLOR_TEXT_DIM))

	# Row 3: Par
	var par_sum := 0
	for h in holes:
		par_sum += h.par
	container.add_child(_build_row("Par", holes.map(func(h): return str(h.par) + ("*" if h.par_override > 0 else "")), str(par_sum), BG_DATA_ROW_B, Color.WHITE))

	# Row 4: Handicap (stroke index)
	container.add_child(_build_row("Hcp", holes.map(func(h): return str(h.stroke_index) if h.stroke_index > 0 else "-"), "", BG_DATA_ROW_A, UIConstants.COLOR_TEXT_DIM))

	# Row 5: Average score (color-coded)
	container.add_child(_build_avg_row(holes))

	return container

func _build_row(label_text: String, values: Array, total_text: String, bg_color: Color, text_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)

	# Label column
	row.add_child(_make_cell(label_text, LABEL_COL_WIDTH, bg_color, text_color))

	# Value cells
	for val in values:
		row.add_child(_make_cell(str(val), CELL_WIDTH, bg_color, text_color))

	# Total column
	if total_text != "":
		var total_bg := bg_color.lightened(0.05)
		row.add_child(_make_cell(total_text, TOTAL_COL_WIDTH, total_bg, text_color))
	else:
		# Empty total cell for rows without totals
		row.add_child(_make_cell("", TOTAL_COL_WIDTH, bg_color, text_color))

	return row

func _build_avg_row(holes: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)

	# Label
	row.add_child(_make_cell("Avg", LABEL_COL_WIDTH, BG_DATA_ROW_B, UIConstants.COLOR_TEXT_DIM))

	var total_avg := 0.0
	var total_par_with_data := 0
	var has_any_data := false

	for hole in holes:
		var stats = GameManager.get_hole_statistics(hole.hole_number)
		if stats and stats.total_rounds > 0:
			has_any_data = true
			var avg = stats.get_average_score()
			total_avg += avg
			total_par_with_data += hole.par
			var avg_to_par = avg - hole.par
			row.add_child(_make_cell("%.1f" % avg, CELL_WIDTH, BG_DATA_ROW_B, _get_avg_color(avg_to_par)))
		else:
			row.add_child(_make_cell("-", CELL_WIDTH, BG_DATA_ROW_B, UIConstants.COLOR_TEXT_MUTED))

	# Total average (only compare against par of holes that have data)
	if has_any_data:
		var avg_to_par := total_avg - total_par_with_data
		row.add_child(_make_cell("%.1f" % total_avg, TOTAL_COL_WIDTH, BG_DATA_ROW_B.lightened(0.05), _get_avg_color(avg_to_par)))
	else:
		row.add_child(_make_cell("-", TOTAL_COL_WIDTH, BG_DATA_ROW_B, UIConstants.COLOR_TEXT_MUTED))

	return row

func _build_records_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = "CourseRecords"
	section.add_theme_constant_override("separation", 4)
	section.add_child(_label("Course Records", SECTION_FONT_SIZE, Color.WHITE))

	var lines := VBoxContainer.new()
	lines.name = "RecordLines"
	lines.add_theme_constant_override("separation", 2)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var records = GameManager.course_records

	# Lowest round
	var lowest = records.get("lowest_round")
	if lowest != null:
		var diff: int = lowest.value - GameManager.current_course.total_par
		var diff_text := ""
		if diff > 0:
			diff_text = " (+%d)" % diff
		elif diff < 0:
			diff_text = " (%d)" % diff
		else:
			diff_text = " (E)"
		var text := "Lowest Round: %d%s by %s (Day %d)" % [lowest.value, diff_text, lowest.golfer_name, lowest.date_day]
		lines.add_child(_record_label(text, UIConstants.COLOR_GOLD))
	else:
		lines.add_child(_record_label("Lowest Round: No rounds completed", UIConstants.COLOR_TEXT_MUTED))

	# Holes-in-one count
	var hio_count: int = records.get("total_hole_in_ones", 0)
	if hio_count > 0:
		lines.add_child(_record_label("Holes-in-One: %d" % hio_count, UIConstants.COLOR_GOLD))

	# Best per hole
	var best_per_hole: Dictionary = records.get("best_per_hole", {})
	if not best_per_hole.is_empty():
		lines.add_child(_label("Best Scores:", CELL_FONT_SIZE, UIConstants.COLOR_TEXT_DIM))

		var sorted_holes := best_per_hole.keys()
		sorted_holes.sort()
		for hole_num in sorted_holes:
			var record = best_per_hole[hole_num]
			# Find par for this hole
			var par := 4
			for hole in GameManager.current_course.holes:
				if hole.hole_number == hole_num:
					par = hole.par
					break
			var score_name = GolfRules.get_score_name(record.value, par)
			var text := "  #%d: %d (%s) - %s" % [hole_num, record.value, score_name, record.golfer_name]
			lines.add_child(_record_label(text, UIConstants.get_score_color(record.value - par)))

	_records_scroll = ScrollContainer.new()
	_records_scroll.name = "RecordsScroll"
	_records_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_records_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_records_scroll.custom_minimum_size = Vector2(RECORDS_WIDTH, RECORDS_HEIGHT)
	_records_scroll.add_child(lines)
	section.add_child(_records_scroll)
	return section

func _make_cell(text: String, width: float, bg_color: Color, text_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, ROW_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = BORDER_COLOR
	style.border_width_bottom = 1
	style.border_width_right = 1
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", CELL_FONT_SIZE)
	label.add_theme_color_override("font_color", text_color)
	panel.add_child(label)

	return panel

func _record_label(text: String, color: Color) -> Label:
	var label := _label(text, CELL_FONT_SIZE, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _get_avg_color(avg_to_par: float) -> Color:
	if avg_to_par <= 0:
		return UIConstants.COLOR_SCORE_UNDER
	if avg_to_par <= 0.5:
		return UIConstants.COLOR_WARNING
	return UIConstants.COLOR_SCORE_OVER
