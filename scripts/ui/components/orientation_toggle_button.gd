extends Button
class_name OrientationToggleButton
## The facing chip in the top-right corner of the location banner's details
## card: a pixel arrow pointing the way the course faces, beside its compass
## letter. Pressing it folds the two Rotate arrows away and brings them back.
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
##
## How many facings there are to point at is the player's choice (Settings →
## Controls → Camera → Fine Rotation): four, N / E / S / W, or eight, those
## plus NE / SE / SW / NW. `orientation` counts in whichever of the two is in
## force, so the chip is told the number of facings as well as the facing.

const FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

## Facings in a full turn: the classic compass, and the compass with its
## diagonals. Both spellings come from GridProjection, which owns the step.
const ORIENTATION_COUNT := GridProjection.ORIENTATION_COUNT
const EIGHTH_TURN_COUNT := GridProjection.EIGHTH_TURN_COUNT
## The letters the facings read as, in orientation order, per step: N, E, S and
## W, or those with the diagonals between them.
const LABELS := {
	4: ["N", "E", "S", "W"],
	8: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
}

## Footprint per layout, for a one-letter facing. The arrow and letter stay the
## same size; the chip only gains padding, so a touch-friendly target never
## blurs the pixel art — and a two-letter compass point ("NE") widens it by
## just the room its extra letter needs.
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

## The eight facing arrows, one 9-character row per row of source pixels,
## indexed by eighth turn: 0 north, 1 north-east, 2 east, and so on round the
## compass. Each is the last one turned an eighth of a turn clockwise.
const ARROWS := {
	# N
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
	# NE
	1: [
		"........x",
		".......xx",
		"......xxx",
		".....xx..",
		"....xx...",
		"...xx....",
		"..xx.....",
		".xx......",
		"xx.......",
	],
	# E
	2: [
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
	# SE
	3: [
		"x........",
		"xx.......",
		".xx......",
		"..xx.....",
		"...xx....",
		"....xx...",
		".....xx..",
		"......xx.",
		"......xxx",
	],
	# S
	4: [
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
	# SW
	5: [
		".......xx",
		"......xx.",
		".....xx..",
		"....xx...",
		"...xx....",
		"..xx.....",
		"xxx......",
		"xx.......",
		"x........",
	],
	# W
	6: [
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
	# NW
	7: [
		"xxx......",
		".xx......",
		"..xx.....",
		"...xx....",
		"....xx...",
		".....xx..",
		"......xx.",
		".......xx",
		"........x",
	],
}

## View orientation, counted in the facings the chip was told about (0..3 for
## quarter turns, 0..7 for eighth turns). Values outside the range wrap round.
var orientation := 0:
	set(value):
		var next := wrapi(value, 0, facings)
		if orientation == next:
			return
		orientation = next
		_apply_size()
		queue_redraw()

## How many facings there are to point at: ORIENTATION_COUNT (N, E, S, W) or
## EIGHTH_TURN_COUNT (those and the four diagonals). Set by the banner from the
## course's own step, so the chip and the course agree on what a facing is.
var facings: int = ORIENTATION_COUNT:
	set(value):
		var next := EIGHTH_TURN_COUNT if value >= EIGHTH_TURN_COUNT else ORIENTATION_COUNT
		if facings == next:
			return
		facings = next
		orientation = wrapi(orientation, 0, facings)
		_apply_size()
		queue_redraw()

## True while the two Rotate arrows are out beside the card, so the chip can
## read as a switch as well as a compass.
var controls_shown := true:
	set(value):
		if controls_shown == value:
			return
		controls_shown = value
		queue_redraw()

## The letters the facing reads as: "N", or "NE" on the finer step.
var letter: String:
	get:
		return letter_for(orientation, facings)


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
	_apply_size()
	queue_redraw()


func _apply_size() -> void:
	var touch := has_node("/root/Screen") and Screen.uses_touch_layout()
	var base := SIZE_TOUCH if touch else SIZE_DESKTOP
	custom_minimum_size = base + Vector2(_extra_letter_width(), 0.0)


## The room the letters past the first one need: "NE" is a wider facing than
## "N", and the chip grows by exactly that much and no more.
func _extra_letter_width() -> float:
	return maxf(0.0, _text_width(letter) - _text_width("N"))


static func _text_width(value: String) -> float:
	return FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


## The arrow rows for `view_orientation` counted in `facings_per_turn`: N up,
## NE up and to the right, E right, and so on round the compass.
static func arrow_rows(view_orientation: int, facings_per_turn: int = ORIENTATION_COUNT) -> Array:
	return ARROWS[_eighths_for(view_orientation, facings_per_turn)]


## The letter for `view_orientation`, wrapping like the arrow.
static func letter_for(view_orientation: int, facings_per_turn: int = ORIENTATION_COUNT) -> String:
	var count := EIGHTH_TURN_COUNT if facings_per_turn >= EIGHTH_TURN_COUNT else ORIENTATION_COUNT
	return LABELS[count][wrapi(view_orientation, 0, count)]


## The facing as a whole number of eighth turns (0..7): the count the arrows
## are indexed by, whichever step the view is turning in.
static func _eighths_for(view_orientation: int, facings_per_turn: int) -> int:
	var count := EIGHTH_TURN_COUNT if facings_per_turn >= EIGHTH_TURN_COUNT else ORIENTATION_COUNT
	# Exact: the facings always divide the eight arrows whole.
	@warning_ignore("integer_division")
	return wrapi(view_orientation, 0, count) * EIGHTH_TURN_COUNT / count


func _eighth_turns() -> int:
	return _eighths_for(orientation, facings)


func _draw() -> void:
	draw_style_box(_chip_style(), Rect2(Vector2.ZERO, size))

	# The arrow: one rect per lit source pixel, with the same ink drop shadow
	# the dock's medallions carry (light comes from above).
	var rows: Array = ARROWS[_eighth_turns()]
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
