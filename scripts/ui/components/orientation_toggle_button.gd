extends Button
class_name OrientationToggleButton
## The borderless compass button in the location banner. Its 24-point rose and
## larger golf-flag needle follow the course in precise 15-degree steps.
## Pressing it folds the two Rotate arrows in or out without changing the
## compass's appearance.
##
## The compass is drawn from vector geometry rather than font glyphs, so its
## pixel edges stay crisp at both desktop and touch sizes.

const CARDINAL_COUNT := 4
const DIRECTION_COUNT := 24
const STEPS_PER_CARDINAL := 6
const CARDINAL_LABELS: Array[String] = ["N", "E", "S", "W"]

## Human-readable bearings for the 24 clockwise headings, starting at north.
const DIRECTION_DESCRIPTIONS: Array[String] = [
	"North", "North 15 degrees east", "North 30 degrees east", "Northeast",
	"East 30 degrees north", "East 15 degrees north", "East",
	"East 15 degrees south", "East 30 degrees south", "Southeast",
	"South 30 degrees east", "South 15 degrees east", "South",
	"South 15 degrees west", "South 30 degrees west", "Southwest",
	"West 30 degrees south", "West 15 degrees south", "West",
	"West 15 degrees north", "West 30 degrees north", "Northwest",
	"North 30 degrees west", "North 15 degrees west",
]

## The larger square footprint gives the compass rose room to read clearly.
const SIZE_DESKTOP := Vector2(42, 42)
const SIZE_TOUCH := Vector2(48, 48)
const DIAL_RADIUS := 20.0

var _direction_step := 0

## Heading index in [0, 24), clockwise from north in 15-degree steps.
var direction_step: int:
	get:
		return _direction_step
	set(value):
		var next := wrapi(value, 0, DIRECTION_COUNT)
		if _direction_step == next:
			return
		_direction_step = next
		queue_redraw()

## Compatibility view of the nearest cardinal heading (N/E/S/W).
## Assigning a cardinal continues to select its matching 15-degree step.
var orientation: int:
	get:
		return wrapi(roundi(float(_direction_step) / float(STEPS_PER_CARDINAL)),
			0, CARDINAL_COUNT)
	set(value):
		direction_step = wrapi(value, 0, CARDINAL_COUNT) * STEPS_PER_CARDINAL

## The Rotate arrows' visibility is useful for the tooltip/action, but does not
## affect how the compass is drawn.
var controls_shown := true:
	set(value):
		controls_shown = value

## Nearest cardinal letter, retained for older HUD call sites.
var letter: String:
	get:
		return CARDINAL_LABELS[orientation]


func _init() -> void:
	text = ""
	# The compass owns its appearance. Empty styles in every Button state mean
	# the theme cannot reintroduce a frame or dim it when it is disabled.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = SIZE_DESKTOP


func _ready() -> void:
	apply_screen()
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Adopt the current screen's footprint while keeping the rose crisp.
func apply_screen() -> void:
	var touch := has_node("/root/Screen") and Screen.uses_touch_layout()
	custom_minimum_size = SIZE_TOUCH if touch else SIZE_DESKTOP
	queue_redraw()


## Unit vector pointing in a 15-degree heading, with step zero pointing north.
static func direction_vector_for_step(step: int) -> Vector2:
	var wrapped := wrapi(step, 0, DIRECTION_COUNT)
	return Vector2.UP.rotated(TAU * float(wrapped) / float(DIRECTION_COUNT))


## Human-readable bearing for tooltips and assistive technology.
static func direction_description_for_step(step: int) -> String:
	return DIRECTION_DESCRIPTIONS[wrapi(step, 0, DIRECTION_COUNT)]


## The nearest cardinal letter for a quarter-turn orientation.
static func letter_for(view_orientation: int) -> String:
	return CARDINAL_LABELS[wrapi(view_orientation, 0, CARDINAL_COUNT)]


func _draw() -> void:
	var center := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))
	var radius := minf(DIAL_RADIUS, floorf(minf(size.x, size.y) * 0.5) - 2.0)
	_draw_rose(center, radius)
	_draw_needle(center, radius)

	# A short underline gives the focused compass a keyboard cue without ever
	# drawing a frame around the button.
	if has_focus():
		draw_line(Vector2(center.x - 4.0, size.y - 1.0),
			Vector2(center.x + 4.0, size.y - 1.0), UIConstants.COLOR_GOLD, 1.0, false)


func _draw_rose(center: Vector2, radius: float) -> void:
	for step in DIRECTION_COUNT:
		var direction := direction_vector_for_step(step)
		var cardinal := step % STEPS_PER_CARDINAL == 0
		var diagonal := step % 3 == 0
		var tick_length := 5.2 if cardinal else (3.7 if diagonal else 2.4)
		var color := Color(UIConstants.COLOR_TEXT_MUTED, 0.75)
		if diagonal:
			color = Color(UIConstants.COLOR_TEXT_DIM, 0.9)
		if cardinal or step == _direction_step:
			color = UIConstants.COLOR_GOLD
		draw_line(center + direction * (radius - tick_length),
			center + direction * radius, color, 1.2, false)


func _draw_needle(center: Vector2, radius: float) -> void:
	var forward := direction_vector_for_step(_direction_step)
	var across := Vector2(-forward.y, forward.x)
	var head_base := center + forward * 2.6
	var shaft_front := center + forward * 2.0
	var tail_edge := center - forward * minf(9.0, radius * 0.52)
	var tail_notch := center - forward * minf(5.7, radius * 0.36)

	# The notched tail and broad pennant head make a golf-flag needle rather
	# than a plain triangle; the whole silhouette rotates through all 24 steps.
	var needle := PackedVector2Array([
		center + forward * (radius - 2.5),
		head_base + across * 4.0,
		shaft_front + across * 1.25,
		tail_edge + across * 1.25,
		tail_notch,
		tail_edge - across * 1.25,
		shaft_front - across * 1.25,
		head_base - across * 4.0,
	])
	draw_colored_polygon(_offset_points(needle, Vector2(0.8, 1.0)),
		Color(PixelCircleButton.INK, 0.88))
	draw_colored_polygon(needle, UIConstants.COLOR_GOLD)
	# A pale seam through the pennant gives the rotating needle a two-tone,
	# hand-cut look and remains visible at every 15-degree angle.
	draw_line(center - forward * 4.5, center + forward * 2.1,
		UIConstants.COLOR_TEXT, 1.2, false)
	draw_circle(center + Vector2(0.0, 0.8), 2.8, Color(PixelCircleButton.INK, 0.9))
	draw_circle(center, 2.0, UIConstants.COLOR_TEXT)
	draw_circle(center, 0.9, UIConstants.COLOR_GOLD)


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point in points:
		moved.append(point + offset)
	return moved
