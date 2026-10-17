extends VBoxContainer
class_name CourseMapRoutingPanel
## CourseMapRoutingPanel - Routing Holes: the order of play, and how it walks.
##
## Every hole gets a row, in the order it is played. The arrows move a hole up
## or down the round (HoleManager.move_hole, which renumbers the holes, keeps
## their statistics with them and carries golfers part-way round on to the hole
## they were playing); "P4" cycles the hole's par; the turn button plays the hole
## the other way round (HoleManager.flip_hole); and the last row plays the whole
## course backwards.
##
## Above the rows the panel judges the route: the average walk from green to next
## tee, the worst leg, and how many legs are long enough to cost the course its
## pace rating (HoleRouting, the same numbers RoutingOverlay paints on the
## course).

signal hole_selected(hole_number: int)
signal move_requested(from_index: int, to_index: int)
signal flip_requested(hole_number: int)
signal par_requested(hole_number: int, new_par: int)
signal toggle_requested(hole_number: int)
signal reverse_requested()

var compact: bool = false
var _selected: int = -1

func _ready() -> void:
	refresh()

func set_selected(hole_number: int) -> void:
	if hole_number == _selected:
		return
	_selected = hole_number
	refresh()

func set_compact(value: bool) -> void:
	if compact == value:
		return
	compact = value
	refresh()

func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 8 if not compact else 6)
	add_child(CourseMapStyle.kicker("Routing holes", 10))
	add_child(CourseMapStyle.title("The round", 19 if not compact else 17))

	var course = GameManager.current_course
	if course == null or course.holes.is_empty():
		add_child(CourseMapStyle.hint(
			"No holes yet. Paint a tee box and a green on the course, then press H to open the first hole."))
		return

	var holes: Array = course.holes
	add_child(_report_card(holes))
	add_child(_holes_list(holes))
	add_child(_order_actions(holes))

# --- Cards -------------------------------------------------------------------

## How the round reads as a walk: length, par, and the legs worth fixing.
func _report_card(holes: Array) -> Control:
	var report := HoleRouting.route_report(holes)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.add_child(CourseMapStyle.label(
		"%d holes · Par %d · %s yds" % [int(report["open"]), int(report["total_par"]),
			_grouped(int(report["total_yards"]))],
		12 if not compact else 11, CourseMapStyle.TEXT_BRIGHT, CourseMapStyle.SUBTITLE_FONT))
	var walk := float(report["average_leg_tiles"])
	body.add_child(CourseMapStyle.label(
		"Average walk between holes: %d tiles (%.1f min)" % [int(roundf(walk)), _walk_minutes(walk)],
		11, CourseMapStyle.TEXT_SECONDARY))
	var long_legs := int(report["long_legs"])
	if long_legs > 0:
		body.add_child(CourseMapStyle.label(
			"%d long walk%s: worst is %d tiles after hole %d" % [
				long_legs, "" if long_legs == 1 else "s", int(roundf(float(report["longest_leg"]))),
				int(report["worst_after_hole"])],
			11, CourseMapStyle.WARNING))
	else:
		body.add_child(CourseMapStyle.label("No long walks: the round flows green to tee.", 11,
			CourseMapStyle.MINT))
	return CourseMapStyle.framed(body)

func _holes_list(holes: Array) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.add_child(CourseMapStyle.kicker("Play order", 10))
	for i in holes.size():
		body.add_child(_hole_row(holes, i))
	return CourseMapStyle.framed(body)

func _hole_row(holes: Array, index: int) -> Control:
	var hole = holes[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var picked: bool = int(hole.hole_number) == _selected

	# Up and down the round.
	var up := CourseMapStyle.icon_button("▲", CourseMapStyle.MINT, 10)
	up.custom_minimum_size = Vector2(26, 26)
	up.disabled = index == 0
	up.tooltip_text = "Play this hole earlier"
	up.pressed.connect(func(): move_requested.emit(index, index - 1))
	row.add_child(up)
	var down := CourseMapStyle.icon_button("▼", CourseMapStyle.MINT, 10)
	down.custom_minimum_size = Vector2(26, 26)
	down.disabled = index == holes.size() - 1
	down.tooltip_text = "Play this hole later"
	down.pressed.connect(func(): move_requested.emit(index, index + 1))
	row.add_child(down)

	var pick := CourseMapStyle.choice(_hole_label(hole, index, holes), 11)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.button_pressed = picked
	pick.tooltip_text = "Hole %d — tap to show it on the map" % int(hole.hole_number)
	pick.pressed.connect(func(): hole_selected.emit(int(hole.hole_number)))
	row.add_child(pick)

	# Par, the way the hole menu cycles it: one shot either side of the hole's
	# length, which is what par_override is for.
	var auto_par := GolfRules.calculate_par(hole.distance_yards)
	var par := CourseMapStyle.icon_button(_par_label(hole), CourseMapStyle.GOLD, 11)
	par.custom_minimum_size = Vector2(38, 26)
	par.tooltip_text = "Par %d%s — tap to change it" % [hole.par,
		"" if hole.par_override < 0 else " (set by hand)"]
	par.pressed.connect(func(): par_requested.emit(int(hole.hole_number), _next_par(hole.par, auto_par)))
	row.add_child(par)

	var flip := CourseMapStyle.icon_button("⟲", CourseMapStyle.MINT, 12)
	flip.custom_minimum_size = Vector2(28, 26)
	flip.tooltip_text = "Turn this hole around: its green becomes the tee"
	flip.pressed.connect(func(): flip_requested.emit(int(hole.hole_number)))
	row.add_child(flip)

	var toggle := CourseMapStyle.icon_button("Open" if hole.is_open else "Shut",
		CourseMapStyle.UTILITY, 10)
	toggle.custom_minimum_size = Vector2(42, 26)
	toggle.add_theme_color_override("font_color",
		CourseMapStyle.MINT if hole.is_open else CourseMapStyle.WARNING)
	toggle.tooltip_text = "Close this hole to take it out of play" if hole.is_open \
		else "Open this hole for play"
	toggle.pressed.connect(func(): toggle_requested.emit(int(hole.hole_number)))
	row.add_child(toggle)
	return row

func _order_actions(holes: Array) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	if holes.size() >= 2:
		var reverse := CourseMapStyle.button("Play the round the other way round", false, 11)
		reverse.tooltip_text = "Hole %d becomes the first and hole 1 the last" % holes.size()
		reverse.pressed.connect(func(): reverse_requested.emit())
		body.add_child(reverse)
	body.add_child(CourseMapStyle.hint(
		"Moved holes keep their statistics, and golfers who are out on the course carry on at the hole they were playing. "
		+ "Holes themselves stay where they are painted."))
	return CourseMapStyle.framed(body)

# --- Labels ------------------------------------------------------------------

func _hole_label(hole, index: int, holes: Array) -> String:
	var text := "%d.  Par %d · %d yds" % [index + 1, hole.par, hole.distance_yards]
	if not hole.is_open:
		text += " · closed"
	elif index + 1 < holes.size():
		var walk := HoleRouting.leg_tiles(holes, index)
		var grade := HoleRouting.grade_for(walk)
		if grade == HoleRouting.Grade.LONG:
			text += " · %d tile walk" % int(roundf(walk))
	return text

func _par_label(hole) -> String:
	return "P%d%s" % [hole.par, "*" if hole.par_override > 0 else ""]

## The par the next tap gives the hole: the hole menu's cycle, one shot either
## side of what the hole's length asks for.
static func _next_par(current: int, auto_par: int) -> int:
	var lowest := maxi(3, auto_par - 1)
	var highest := mini(6, auto_par + 1)
	var next := current + 1
	if next > highest:
		next = lowest
	return next

## Walk time at a golfer's pace: a tile is about 22 yards, and the game's
## walkers cover roughly 90 yards a minute including the stop at the tee.
static func _walk_minutes(tiles: float) -> float:
	return tiles * HoleLayout.YARDS_PER_TILE / 90.0

static func _grouped(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
