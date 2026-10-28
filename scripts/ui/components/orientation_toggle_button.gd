extends Button
class_name OrientationToggleButton
## The facing chip in the top-right corner of the location banner's details
## card: a pixel arrow pointing the way the course faces, beside its N / E / S /
## W letter. Pressing it folds the two Rotate arrows away and brings them back.
##
## The arrow is a 9x9 character grid painted from whole screen pixels, the same
## way the dock's medallions and the menu's sprites are drawn: the UI font
## carries no arrow glyphs (see RotateViewButton), and a drawn arrow keeps its
## hard edges next to the pixel letter the font supplies.
##
## The chip stays in the corner whether the Rotate arrows are out or folded
## away - it is the only way back to them - so it carries the state as well as
## the facing: a gold rim and arrow while they are out, a muted one while they
## are stowed.

const FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

## The compass has four facings; anything outside 0..3 wraps round them.
const ORIENTATION_COUNT := 4
## The letters the four facings read as, in orientation order.
const LABELS: Array[String] = ["N", "E", "S", "W"]

## Footprint per layout. The arrow and letter stay the same size; the chip only
## gains padding, so a touch-friendly target never blurs the pixel art.
const SIZE_DESKTOP := Vector2(42, 26)
const SIZE_TOUCH := Vector2(46, 32)

## Source pixels per arrow pixel, and the arrow's grid side in source pixels.
const ARROW_PIXEL := 2
const ARROW_GRID := 9
## Gap between the arrow and its letter, and the chip's own left padding.
const ARROW_INSET := 5.0
const LETTER_GAP := 3.0
const FONT_SIZE := 12
const RADIUS := 4

## The four facing arrows, one 9-character row per row of source pixels.
## Each is the last one turned a quarter turn round the compass.
const ARROWS := {
	0: [
		"....x....",
		"...xxx...",
		"..xxxxx..",
		".xxxxxxx.",
		"....x....",
		"....x....",
		"....x....",
		"....x....",
		"....x....",
	],
	1: [
		".........",
		".....x...",
		".....xx..",
		".....xxx.",
		"xxxxxxxxx",
		".....xxx.",
		".....xx..",
		".....x...",
		".........",
	],
	2: [
		"....x....",
		"....x....",
		"....x....",
		"....x....",
		"....x....",
		".xxxxxxx.",
		"..xxxxx..",
		"...xxx...",
		"....x....",
	],
	3: [
		".........",
		"...x.....",
		"..xx.....",
		".xxx.....",
		"xxxxxxxxx",
		".xxx.....",
		"..xx.....",
		"...x.....",
		".........",
	],
}

## View orientation 0..3 (N, E, S, W). Values outside the range wrap round.
var orientation := 0:
	set(value):
		var next := wrapi(value, 0, ORIENTATION_COUNT)
		if orientation == next:
			return
		orientation = next
		queue_redraw()

## True while the two Rotate arrows are out beside the card, so the chip can
## read as a switch as well as a compass.
var controls_shown := true:
	set(value):
		if controls_shown == value:
			return
		controls_shown = value
		queue_redraw()

## The single letter the facing reads as.
var letter: String:
	get:
		return LABELS[orientation]


func _init() -> void:
	text = ""
	# The chip paints its own face and states in _draw; the button itself only
	# supplies the input, tooltip and focus handling.
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
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited,
			button_down, button_up]:
		event.connect(queue_redraw)


## Adopt the footprint of the current layout: desktops keep the compact chip,
## touch layouts grow it to a comfortable target.
func apply_screen() -> void:
	var touch := has_node("/root/Screen") and Screen.uses_touch_layout()
	custom_minimum_size = SIZE_TOUCH if touch else SIZE_DESKTOP
	queue_redraw()


## The arrow rows for `view_orientation`: N up, E right, S down, W left.
static func arrow_rows(view_orientation: int) -> Array:
	return ARROWS[wrapi(view_orientation, 0, ORIENTATION_COUNT)]


## The letter for `view_orientation`, wrapping like the arrow.
static func letter_for(view_orientation: int) -> String:
	return LABELS[wrapi(view_orientation, 0, ORIENTATION_COUNT)]


func _draw() -> void:
	draw_style_box(_chip_style(), Rect2(Vector2.ZERO, size))

	# The arrow: one rect per lit source pixel, with the same ink drop shadow
	# the dock's medallions carry (light comes from above).
	var rows: Array = ARROWS[orientation]
	var arrow_side := ARROW_GRID * ARROW_PIXEL
	var origin := Vector2(ARROW_INSET, floorf((size.y - arrow_side) * 0.5))
	for y in ARROW_GRID:
		var row: String = rows[y]
		for x in ARROW_GRID:
			if row[x] != "x":
				continue
			var pixel := Rect2(origin + Vector2(x, y) * ARROW_PIXEL,
				Vector2.ONE * ARROW_PIXEL)
			draw_rect(Rect2(pixel.position + Vector2(0, 1), pixel.size), _shadow_color())
			draw_rect(pixel, _ink_color())

	# The letter sits beside the arrow, on the baseline of the chip's middle.
	draw_string(FONT, Vector2(origin.x + arrow_side + LETTER_GAP, floorf(size.y * 0.5) + 4.0),
		letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _ink_color())
	if has_focus():
		draw_style_box(_focus_style(), Rect2(Vector2.ZERO, size))


## The chip's face: the dark card the status column's rows wear, with a rim
## that lights gold while the Rotate arrows are out.
func _chip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var fill := Color(UIConstants.COLOR_BG_DARK, 0.82)
	if is_pressed():
		fill = fill.lightened(0.18)
	elif is_hovered():
		fill = fill.lightened(0.10)
	style.bg_color = fill
	style.set_border_width_all(1)
	style.border_color = Color(UIConstants.COLOR_GOLD, 0.80) if controls_shown \
		else Color(UIConstants.COLOR_BORDER, 0.60)
	style.set_corner_radius_all(RADIUS)
	return style


## Only the ring: the focused chip does not repaint its face.
func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(1)
	style.border_color = UIConstants.COLOR_GOLD
	style.set_corner_radius_all(RADIUS)
	return style


## Gold while the Rotate arrows are out, muted once they are stowed.
func _ink_color() -> Color:
	return UIConstants.COLOR_GOLD if controls_shown else UIConstants.COLOR_TEXT_MUTED


func _shadow_color() -> Color:
	return Color(PixelCircleButton.INK, 0.7)
