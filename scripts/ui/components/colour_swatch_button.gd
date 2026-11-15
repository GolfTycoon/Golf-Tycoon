extends Button
class_name ColourSwatchButton
## One of the colours a golfer can pick as their favourite, as a small plate on
## the owner's Edit Player Golfer shelf.
##
## The plate carries exactly one thing: its colour, as a crisp chip inside the
## same pixel card every other card on the shelf wears (see PixelButtonStyle and
## SkinGroupColorButton). It stands beside the Favourite Colour plate, so the
## owner can pick the colour another golfer already wears - the palette every
## golfer the game rolls is given one from (see GolferFavouriteColour) - instead
## of opening a picker for it.
##
## The plate is its own colour, not a picker: pressing it emits `chosen`, and
## whoever built it writes the favourite colour. The native `text` is left empty
## on purpose (the swatch is the whole plate); `accessibility_name` and the
## tooltip carry the colour's hex for player and assistive tech alike.

const ACCENT := Color("83c9a4")
const CHIP_AREA := Rect2(3, 3, 18, 20)

## Whole plate footprint, matching the Group Colour plates' height so a palette
## reads as one more row of the same shelf.
const BUTTON_SIZE := Vector2(24, 26)

## Emitted when the plate is pressed: the colour it wears is the one to pick.
signal chosen(colour: Color)

## The colour the plate wears.
var color := Color.WHITE:
	set(value):
		if color != value:
			color = value
			queue_redraw()

var _hovered := false


func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	PixelButtonStyle.paint_card(self, ACCENT, 0, 0, Color("e4e7d5"), Color.WHITE)
	# The swatch is the plate: the native text must not draw over it.
	text = ""
	for font_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color", "font_disabled_color",
			"font_outline_color"]:
		add_theme_color_override(font_state, Color.TRANSPARENT)
	mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
	for event_signal in [button_down, button_up, focus_entered, focus_exited]:
		event_signal.connect(queue_redraw)
	pressed.connect(func() -> void: chosen.emit(color))


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return  # Not laid out yet.
	var dip := 1.0 if is_pressed() and not disabled else 0.0
	var area := Rect2(CHIP_AREA.position + Vector2(0.0, dip), CHIP_AREA.size)
	draw_rect(area, PixelCircleButton.INK)
	# A hovered or focused plate lifts its chip, the way the shelf's other cards
	# light up, so a palette reads as a row of choices rather than a swatch book.
	var chip := area.grow(-2.0)
	if (_hovered or has_focus()) and not disabled:
		chip = chip.grow(-1.0)
	draw_rect(chip, color)
