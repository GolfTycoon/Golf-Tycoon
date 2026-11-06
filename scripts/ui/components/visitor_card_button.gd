extends Button
class_name VisitorCardButton
## One visiting golfer as a pocket name plate on the Golfers tab register.
##
## The plate carries exactly two things: the golfer's own skin sprite on the
## left, and the golfer's name beside it. The round's details - hole, strokes,
## score - are what the profile view is for; the plate itself is a door into
## it, so it stays readable at a glance.
##
## Whoever is on the course wears the visiting green frame; the rounds already
## played wear the past-visitor tan, the same accents the register has always
## used. The frame is the shared PixelButtonStyle card, so hover lifts it and
## keyboard focus floats the shared ring, exactly like the rest of the dock.
##
## `portrait` is the skin frame snapshot the on-course golfer, this plate and
## the profile detail share (see VisitorPortrait.for_golfer), drawn at whole
## pixels so the art stays crisp. The native `text` stays the golfer's name -
## tests and assistive tech read it - but the card paints its own caption, so
## every font colour is transparent.

const FONT := PixelCircleButton.FONT
const CREAM := PixelCircleButton.CREAM
const NAME_LIT := Color("ffffff")

## Whole card footprint. Three to a column (GOLFER_COLUMN_HEIGHT in
## TerrainToolbar) inside the 190px bottom bar; the columns run off to the
## right, so the width never makes the bar grow taller.
const BUTTON_SIZE := Vector2(228, 44)

## The sprite's drawing area, and where the caption starts.
const SPRITE_AREA := Rect2(2, 1, 40, 42)
const TEXT_X := 49.0

const NAME_FONT_SIZE := 13
const NAME_FONT_MIN := 9

## The skin frame snapshot to draw, or null when there is no art.
var portrait: Texture2D = null
## Frame and accent colour: the visiting green for a golfer on the course,
## the past-visitor tan for a round already played.
var accent := Color("83c9a4")
## True while the golfer is on the course. The plate draws the same either
## way; the flag lets callers and tests tell the two cards apart without
## parsing captions.
var active := true

var _hovered := false


func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	PixelButtonStyle.paint_card(self, accent, 0, 0, Color("e4e7d5"), Color.WHITE)
	# The card draws its own caption, so the native text never fights the art.
	for font_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color", "font_disabled_color",
			"font_outline_color"]:
		add_theme_color_override(font_state, Color.TRANSPARENT)
	if accessibility_name.is_empty():
		accessibility_name = text
	accessibility_description = "Visiting golfer. Activate for their profile."
	for event in [mouse_entered, mouse_exited, button_down, button_up,
			focus_entered, focus_exited]:
		event.connect(queue_redraw)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return  # Not laid out yet.
	var dip := 1.0 if is_pressed() and not disabled else 0.0
	var lit := (_hovered or has_focus()) and not disabled
	_draw_sprite(dip)
	_draw_name(dip, lit)


## The golfer's skin sprite, drawn straight onto the card at whole pixels with
## no backdrop - the way the golfer stands on the course.
func _draw_sprite(dip: float) -> void:
	if portrait == null:
		return
	var source := portrait.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var scale_factor := minf(SPRITE_AREA.size.x / source.x, SPRITE_AREA.size.y / source.y)
	# Use whole-pixel scaling wherever the source art fits at native size.
	if scale_factor >= 1.0:
		scale_factor = floorf(scale_factor)
	var drawn_size := source * scale_factor
	var drawn_origin := SPRITE_AREA.position + Vector2(0.0, dip) \
		+ ((SPRITE_AREA.size - drawn_size) / 2.0).floor()
	draw_texture_rect(portrait, Rect2(drawn_origin, drawn_size), false)


## The golfer's name, fitted to the room between the sprite and the frame:
## shrunk a step at a time for long names, clipped at the frame's edge if it
## still does not fit.
func _draw_name(dip: float, lit: bool) -> void:
	var available := size.x - TEXT_X - 6.0
	var font_size := NAME_FONT_SIZE
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while font_size > NAME_FONT_MIN and width > available:
		font_size -= 1
		width = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := dip + (size.y + FONT.get_ascent(font_size) - FONT.get_descent(font_size)) * 0.5
	var color := NAME_LIT if lit else CREAM
	draw_string(FONT, Vector2(TEXT_X, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, available, font_size, color)
