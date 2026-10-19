extends RefCounted
class_name MenuStyle
## The palette and card styling shared by the out-of-game menu screens (the
## title screen and the Start New Game setup screen).
##
## Both screens sit on the same background-image MenuBackdrop and use the same dark,
## translucent cards with an accent-coloured border, so the colours and the
## StyleBoxFlat recipe live here once instead of being copied between them.

const TITLE_COLOR := Color("e7f3d6")

const CARD_RADIUS := 12
const CARD_BG := Color(0.043, 0.098, 0.078, 0.88)
const CARD_BG_HOVER := Color(0.086, 0.180, 0.141, 0.95)
const CARD_BG_PRESSED := Color(0.027, 0.063, 0.051, 0.97)
const CARD_BG_DISABLED := Color(0.043, 0.098, 0.078, 0.55)
const RAIL_BG := Color(0.031, 0.071, 0.059, 0.72)
## A large form panel: like the rail, but dense enough that the backdrop's
## flag and trees read as behind it rather than through it.
const SHEET_BG := Color(0.031, 0.071, 0.059, 0.88)
## Recessed surfaces inside a card: text fields, the course plan's frame.
const INSET_BG := Color(0.020, 0.051, 0.039, 0.92)

## Gold is the palette's "special" colour: the headline action on each screen.
const ACCENT_PRIMARY := UIConstants.COLOR_GOLD
## The green, everyday path into the game.
const ACCENT_SECONDARY := Color("7fb08a")
const ACCENT_UTILITY := Color("6d8a76")
const ACCENT_QUIT := UIConstants.COLOR_DANGER_MUTED
## Dark ink for text sitting on a gold fill.
const INK := Color("10241f")

## StyleBoxFlat with uniform side margins, its own top margin and the room a
## caption needs below the label.
static func flat(bg: Color, border: Color, border_width: int, radius: int,
		pad: int, top: int, bottom: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = float(pad)
	style.content_margin_right = float(pad)
	style.content_margin_top = float(top)
	style.content_margin_bottom = float(bottom)
	return style

static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

## Paint a card button. Every menu card is the notched pixel frame of
## PixelButtonStyle (the title screen's recipe), so the screens share one look.
## `caption_block` reserves a strip under the label; `pad` is the content margin.
static func paint_card(button: Button, accent: Color, caption_block: float, pad: int,
		text_color: Color, hover_color: Color) -> void:
	PixelButtonStyle.paint_card(button, accent, caption_block, pad, text_color, hover_color)

## Paint a selectable (toggle) card: a quiet pixel frame that sinks and lights
## its trim when selected. `radius` is kept for the existing call sites; the
## pixel frame has no corner radius.
static func paint_choice(button: Button, accent: Color, _radius: int = CARD_RADIUS) -> void:
	PixelButtonStyle.paint_choice(button, accent)

## Paint the screen's one solid call to action: the gold pixel slab with dark
## ink type. `_radius` is kept for the existing call sites.
static func paint_primary(button: Button, _radius: int = CARD_RADIUS) -> void:
	PixelButtonStyle.paint_primary(button)

## A panel frame (cards, rails, insets): the notched pixel frame with its own
## padding. `radius` and `border_width` are kept for the existing call sites;
## the pixel frame has one fixed trim weight and no corner radius.
static func panel(bg: Color, border: Color, _radius: int, pad_x: int, pad_y: int,
		_border_width: int = 1) -> StyleBox:
	return PixelButtonStyle.panel_style(border, bg, pad_x, pad_y)

## Height of `lines` lines of text at `font_size` in the game's font, including
## Label's line spacing between them. Lets builders size cards up front
## instead of waiting a frame for wrapped labels to measure themselves.
static func text_block(font: Font, font_size: int, lines: int, line_spacing: float = 3.0) -> float:
	if font == null or font_size <= 0 or lines <= 0:
		return 0.0
	return font.get_height(font_size) * float(lines) + line_spacing * float(lines - 1)

## How many lines `text` takes when word-wrapped at `width` - the same greedy
## break a Label with AUTOWRAP_WORD_SMART makes. Screens use it to reserve a
## fixed height for wrapped text, so layouts are measurable before the first
## layout pass and never cut a description short.
static func wrapped_lines(text: String, font: Font, font_size: int, width: float) -> int:
	if font == null or text.is_empty():
		return 1
	var limit := maxf(width - 1.0, 1.0)
	var space := _string_width(" ", font, font_size)
	var lines := 1
	var line := ""
	for word in text.split(" ", false):
		# Each candidate line is measured whole (a shaped line is a few pixels
		# wider than its words measured one by one), and with the space that
		# follows it: the text server only breaks after the space.
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and _string_width(candidate, font, font_size) + space > limit:
			lines += 1
			line = word
		else:
			line = candidate
		# A word wider than the line is broken across lines by the label.
		var overflow := _string_width(line, font, font_size)
		if overflow > limit and line == word:
			lines += ceili(overflow / limit) - 1
	return lines

static func _string_width(text: String, font: Font, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
