extends Button
class_name VisitorRegisterTab
## The way back out of a Visiting Golfer profile: a tall file tab at the far
## left of the row.
##
## It stands as tall as the dossier cards beside it, like the tab of a folder
## pulled half out of the rack, and carries three things: a pixel arrow, the
## words GUEST and REGISTER, and how many visitors the book holds. It wears the
## same glass frame as the visitor plates (the past-visitor tan, because the
## register is where every visitor started), so the way out reads as part of
## the set rather than a stray control.
##
## The native `text` stays "Guest register" for assistive tech and tests; the
## button paints its own caption, so every font colour is transparent.

const FONT := VisitorCardButton.FONT
const CREAM := VisitorCardButton.CREAM
const LIT := Color("ffffff")
const ACCENT := Color("e2c681")

const TAB_SIZE := Vector2(84, VisitorProfileStyle.CARD_HEIGHT)

## How many visitors the guest book holds, written at the foot of the tab.
var count := 0

var _hovered := false


func _ready() -> void:
	custom_minimum_size = TAB_SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	PixelButtonStyle.paint_card(self, ACCENT, 0, 6, CREAM, LIT)
	for font_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color", "font_disabled_color",
			"font_outline_color"]:
		add_theme_color_override(font_state, Color.TRANSPARENT)
	if accessibility_name.is_empty():
		accessibility_name = "Guest register"
	accessibility_description = "Close this profile and go back to the guest register."
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
	var cream := LIT if lit else CREAM
	var centre := size.x * 0.5

	# The arrow, sized like the tab buttons' glyphs rather than a caption.
	var arrow_size := 24
	var arrow_width := FONT.get_string_size("<", HORIZONTAL_ALIGNMENT_LEFT, -1,
		arrow_size).x
	var arrow_baseline := dip + 34.0
	draw_string(FONT, Vector2(floorf(centre - arrow_width * 0.5), arrow_baseline), "<",
		HORIZONTAL_ALIGNMENT_LEFT, -1, arrow_size, ACCENT.lightened(0.28 if lit else 0.1))

	# GUEST / REGISTER, one above the other like a label on a file tab.
	for entry in [[0, "GUEST"], [1, "REGISTER"]]:
		var caption_text: String = entry[1]
		var font_size := 10
		var width := FONT.get_string_size(caption_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x
		var baseline := dip + 55.0 + float(entry[0]) * 15.0
		draw_string(FONT, Vector2(floorf(centre - width * 0.5), baseline), caption_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, cream)

	# A hairline and the guest book's count, quiet at the foot of the tab.
	var rule_y := size.y - 30.0 + dip
	draw_rect(Rect2(12, rule_y, size.x - 24.0, 1), Color(0.29, 0.25, 0.16, 0.75))
	var caption := "GUEST BOOK" if count <= 0 else "%d IN BOOK" % count
	var caption_size := 8
	var caption_width := FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1,
		caption_size).x
	draw_string(FONT, Vector2(floorf(centre - caption_width * 0.5), size.y - 15.0 + dip),
		caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size,
		ACCENT.darkened(0.15) if not lit else LIT)
