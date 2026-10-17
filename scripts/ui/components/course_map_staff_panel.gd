extends VBoxContainer
class_name CourseMapStaffPanel
## CourseMapStaffPanel - Staff Management: who works the course, and where.
##
## The map draws the ground each employee covers. This panel is the roster that
## goes with it: the payroll line, the course condition the groundskeepers earn,
## one row per employee (tap the row to find their ground on the map, Move to
## hand them a new patch, Fire to let them go), and the hire desk underneath -
## every job, standard and premium, priced by the day.
##
## Hiring two-step: a hire button arms the map, and the next tap on the course
## both hires the employee and bases them there (StaffManager.hire_staff then
## move_staff_area), so a new hire is never left standing in the middle of the
## course by accident. Moving works the same way and is the one the course has
## always used (see main.gd's staff area move mode).

signal staff_selected(index: int)
signal move_requested(index: int)
signal fire_requested(index: int)
## Emitted when a hire button is tapped: the screen arms the map with this type.
signal hire_armed(staff_type: int)

var compact: bool = false
var _selected: int = -1
## The hire type the map is waiting for, so the panel can keep its button lit.
var _armed_type: int = -1

func _ready() -> void:
	refresh()

func set_selected(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	refresh()

## Mirror the map's pending action back into the hire buttons (and the roster
## buttons), so the panel shows what the next tap on the course will do.
func set_armed(staff_type: int) -> void:
	if _armed_type == staff_type:
		return
	_armed_type = staff_type
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
	add_child(CourseMapStyle.kicker("Staff management", 10))
	add_child(CourseMapStyle.title("The crew", 19 if not compact else 17))

	var manager: StaffManager = GameManager.staff_manager
	if manager == null:
		add_child(CourseMapStyle.hint("No staff manager on this course yet."))
		return
	add_child(_summary_card(manager))
	add_child(_roster_card(manager))
	add_child(_hire_card(manager))
	add_child(CourseMapStyle.hint(
		"Payroll is charged every day. Groundskeepers keep the weeds down and the condition up; "
		+ "greeters lift moods, marshals keep the pace, drinks vendors serve the thirsty."))

# --- Cards -------------------------------------------------------------------

func _summary_card(manager: StaffManager) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.add_child(CourseMapStyle.label(
		"%d on the payroll · %s a day" % [manager.hired_staff.size(),
			CourseMapStyle.money(manager.get_daily_payroll())],
		12 if not compact else 11, CourseMapStyle.TEXT_BRIGHT, CourseMapStyle.SUBTITLE_FONT))
	body.add_child(CourseMapStyle.chip_row([
		{"text": "Condition: %s" % manager.get_condition_description(), "color": _condition_color(manager.course_condition)},
		{"text": "%d weeds out there" % manager.get_weed_count(), "color": CourseMapStyle.WARNING},
	]))
	var holes := maxi(1, GameManager.get_open_hole_count())
	var groundskeepers := manager.get_staff_count_by_job(StaffManager.Job.GROUNDSKEEPER)
	body.add_child(CourseMapStyle.label(
		"Groundskeepers per open hole: %d / %d" % [groundskeepers, holes], 11,
		CourseMapStyle.MINT if groundskeepers > 0 else CourseMapStyle.TEXT_QUIET))
	return CourseMapStyle.framed(body)

func _roster_card(manager: StaffManager) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.add_child(CourseMapStyle.kicker("Current staff", 10))
	if manager.hired_staff.is_empty():
		body.add_child(CourseMapStyle.hint("Nobody hired yet. Pick a job below, then tap the course to base them there."))
		return CourseMapStyle.framed(body)
	for index in manager.hired_staff.size():
		body.add_child(_staff_row(manager, index))
	return CourseMapStyle.framed(body)

func _staff_row(manager: StaffManager, index: int) -> Control:
	var record: Dictionary = manager.hired_staff[index]
	var data: Dictionary = manager.get_staff_data(int(record.type))
	var job := manager.get_job_for_type(int(record.type))
	var type_name := str(data.get("name", "Staff"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var pick := CourseMapStyle.choice(
		"%s · %s · $%d/day" % [str(record.get("name", "Staff")), type_name, int(record.get("salary", 0))], 11)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.button_pressed = index == _selected
	pick.tooltip_text = "Covers %.0f tiles — tap to find their ground on the map" \
		% float(record.get("area_radius", 6.0))
	pick.add_theme_color_override("font_pressed_color", _job_color(job))
	pick.pressed.connect(func(): staff_selected.emit(index))
	row.add_child(pick)

	var move := CourseMapStyle.icon_button("Move", CourseMapStyle.MINT, 11)
	move.custom_minimum_size = Vector2(46, 26)
	move.tooltip_text = "Hand this employee a new area: tap the course next"
	move.pressed.connect(func(): move_requested.emit(index))
	row.add_child(move)

	var fire := CourseMapStyle.icon_button("Fire", CourseMapStyle.DANGER, 11)
	fire.custom_minimum_size = Vector2(40, 26)
	fire.tooltip_text = "Let this employee go"
	fire.pressed.connect(func(): fire_requested.emit(index))
	row.add_child(fire)
	return row

## The hire desk: one button per job, standard beside premium.
func _hire_card(manager: StaffManager) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.add_child(CourseMapStyle.kicker("Hire staff", 10))
	body.add_child(CourseMapStyle.hint("Tap a job, then tap the course where they should work.", 10))
	var jobs: Array = [
		StaffManager.Job.GROUNDSKEEPER, StaffManager.Job.GREETER,
		StaffManager.Job.MARSHAL, StaffManager.Job.DRINKS_VENDOR,
	]
	for job in jobs:
		body.add_child(_job_row(manager, job))
	return CourseMapStyle.framed(body)

func _job_row(manager: StaffManager, job: int) -> Control:
	var job_data: Dictionary = manager.get_job_data(job)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.add_child(CourseMapStyle.label(str(job_data.get("name", "Staff")), 11,
		_job_color(job), CourseMapStyle.SUBTITLE_FONT))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 5)
	for staff_type in manager.get_types_for_job(job):
		var data: Dictionary = manager.get_staff_data(staff_type)
		var hired := manager.get_staff_count_by_type(staff_type)
		var control := CourseMapStyle.choice(
			"%s · %s%s" % [str(data.get("name", "Staff")),
				CourseMapStyle.short_money(int(data.get("base_salary", 0))),
				"" if hired == 0 else " (%d)" % hired], 10)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.button_pressed = _armed_type == staff_type
		control.custom_minimum_size.y = 34.0 if compact else 30.0
		control.tooltip_text = "%s — %s" % [str(data.get("description", "")),
			"tap, then tap the course where they should work"]
		control.pressed.connect(func(): hire_armed.emit(staff_type))
		buttons.add_child(control)
	row.add_child(buttons)
	return row

# --- Helpers -----------------------------------------------------------------

static func _job_color(job: int) -> Color:
	if job >= 0 and job < CourseMapView.JOB_COLORS.size():
		return CourseMapView.JOB_COLORS[job]
	return CourseMapStyle.TEXT_BRIGHT

static func _condition_color(condition: float) -> Color:
	if condition >= 0.7:
		return CourseMapStyle.SUCCESS
	if condition >= 0.4:
		return CourseMapStyle.WARNING
	return CourseMapStyle.DANGER
