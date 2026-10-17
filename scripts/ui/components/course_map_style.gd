extends RefCounted
class_name CourseMapStyle
## CourseMapStyle - The Course Map's shared look.
##
## The screen and its four mode panels are one design: the same pixel-art
## frames (PixelButtonStyle), the same Pixelify Sans weights and the same
## cream / golf-green / flag-gold palette as the title screen, the World Map and
## the Start New Game setup, which is where these constants come from.
##
## Everything in here is a static builder, so a panel says what a thing is
## rather than how it is painted: `CourseMapStyle.button("Buy", true)` is the
## screen's one solid call to action wherever it appears.

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

const SURFACE := MenuStyle.SHEET_BG
const SURFACE_RAISED := MenuStyle.RAIL_BG
const INSET := MenuStyle.INSET_BG
const BORDER := UIConstants.COLOR_BORDER
const TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const TEXT_SECONDARY := UIConstants.COLOR_TEXT_DIM
const TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const GOLD := MenuStyle.ACCENT_PRIMARY
const MINT := MenuStyle.ACCENT_SECONDARY
const UTILITY := MenuStyle.ACCENT_UTILITY
## The palette's "leave" colour: Back, Fire, Cancel.
const QUIT := MenuStyle.ACCENT_QUIT
const DANGER := UIConstants.COLOR_DANGER
const WARNING := UIConstants.COLOR_WARNING
const SUCCESS := UIConstants.COLOR_SUCCESS

## The panel's own frame: a pixel nine-patch card, no rounded corners. The
## border is given at full strength and softened here, so callers pass the
## colour they mean rather than a faded copy of it.
static func panel(bg: Color = SURFACE, border: Color = BORDER,
		pad_x: int = 12, pad_y: int = 10) -> StyleBoxTexture:
	return PixelButtonStyle.panel_style(with_alpha(border, 0.45), bg, pad_x, pad_y)

## The border alpha the frames are drawn with.
static func with_alpha(color: Color, alpha: float) -> Color:
	return MenuStyle.with_alpha(color, alpha)

## A recessed surface inside a card: the frame a preview or a text field sits in.
static func inset(padding: int = 8) -> StyleBoxTexture:
	return PixelButtonStyle.inset_style(with_alpha(BORDER, 0.5), INSET, padding)

static func label(text: String, font_size: int, color: Color = TEXT_SECONDARY,
		font: Font = BODY_FONT) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_override("font", font)
	out.add_theme_font_size_override("font_size", font_size)
	out.add_theme_color_override("font_color", color)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out

## The bold weight: screen titles, section headings, money.
static func title(text: String, font_size: int, color: Color = TEXT_BRIGHT) -> Label:
	return label(text, font_size, color, TITLE_FONT)

## The small gold caption above a section.
static func kicker(text: String, font_size: int = 10) -> Label:
	var out := label(text, font_size, GOLD, SUBTITLE_FONT)
	out.uppercase = true
	return out

## Explanatory copy: wrapped, quiet, and never taller than it needs to be.
static func hint(text: String, font_size: int = 11) -> Label:
	var out := label(text, font_size, TEXT_QUIET)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return out

## Wrap a built row stack in a card frame: panels fill a VBox with rows and hand
## it here, so a card is one line at the call site.
static func framed(body: Control, padding: int = 10, bg: Color = SURFACE_RAISED) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", panel(bg, BORDER, padding, padding - 2))
	frame.add_child(body)
	return frame

## A row of small chips: used for counts ("3 happy", "1 unhappy").
static func chip_row(entries: Array, font_size: int = 10) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	for entry in entries:
		row.add_child(chip(str(entry.get("text", "")), entry.get("color", TEXT_SECONDARY), font_size))
	return row

## Give a painted control room for its label. The pixel frames are shared, and
## carry no content margins of their own, so each control sets its own on a copy
## - which is also what makes the frame the button's minimum size.
static func pad(control: Control, pad_x: int, pad_y: int) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		if not control.has_theme_stylebox_override(state):
			continue
		var style := control.get_theme_stylebox(state)
		if style == null:
			continue
		var copy := style.duplicate()
		copy.content_margin_left = float(pad_x)
		copy.content_margin_right = float(pad_x)
		copy.content_margin_top = float(pad_y)
		copy.content_margin_bottom = float(pad_y)
		control.add_theme_stylebox_override(state, copy)

## Paint a menu button: the quiet green card, or the screen's one gold call to
## action when `primary`.
static func button(text: String, primary: bool = false, font_size: int = 12) -> Button:
	var out := Button.new()
	out.text = text
	out.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		PixelButtonStyle.paint_primary(out)
		out.add_theme_font_override("font", TITLE_FONT)
	else:
		PixelButtonStyle.paint_card(out, UTILITY, 0.0, 7, TEXT_BRIGHT, MenuStyle.TITLE_COLOR)
		out.add_theme_font_override("font", SUBTITLE_FONT)
		out.add_theme_color_override("font_disabled_color", TEXT_QUIET)
	out.add_theme_font_size_override("font_size", font_size)
	out.custom_minimum_size.y = float(font_size + (21 if primary else 19))
	pad(out, 12, 0)
	return out

## A selectable card: the mode tabs and the roster rows use this.
static func choice(text: String, font_size: int = 12) -> Button:
	var out := Button.new()
	out.text = text
	out.toggle_mode = true
	out.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	PixelButtonStyle.paint_choice(out, MINT)
	out.add_theme_font_override("font", SUBTITLE_FONT)
	out.add_theme_font_size_override("font_size", font_size)
	out.add_theme_color_override("font_color", TEXT_SECONDARY)
	out.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	out.add_theme_color_override("font_pressed_color", GOLD)
	out.add_theme_color_override("font_focus_color", TEXT_BRIGHT)
	out.add_theme_color_override("font_disabled_color", TEXT_QUIET)
	out.custom_minimum_size.y = float(font_size + 18)
	pad(out, 10, 0)
	return out

## A small action button (move up, turn a hole around, fire). Words rather than
## sprites: the course map's rows are dense, and a word is never ambiguous.
static func icon_button(text: String, accent: Color = UTILITY, font_size: int = 11) -> Button:
	var out := Button.new()
	out.text = text
	out.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	PixelButtonStyle.paint_card(out, accent, 0.0, 5, TEXT_BRIGHT, MenuStyle.TITLE_COLOR)
	out.add_theme_font_override("font", SUBTITLE_FONT)
	out.add_theme_font_size_override("font_size", font_size)
	out.add_theme_color_override("font_disabled_color", TEXT_QUIET)
	out.custom_minimum_size.y = float(font_size + 15)
	pad(out, 7, 0)
	return out

## A chip: a small read-only badge of a colour and a word or two.
static func chip(text: String, color: Color, font_size: int = 10) -> Control:
	var out := Label.new()
	out.text = " " + text + " "
	out.add_theme_font_override("font", SUBTITLE_FONT)
	out.add_theme_font_size_override("font_size", font_size)
	out.add_theme_color_override("font_color", color)
	out.add_theme_stylebox_override("normal", panel(Color(0, 0, 0, 0.32), with_alpha(color, 0.55), 5, 2))
	out.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out

## One of the menu sprites (PixelIcon), nearest-filtered so its pixels stay hard.
static func icon(kind: int, side: int, accent: Color, dimmed: bool = false) -> TextureRect:
	var grid_side := PixelIcon.snapped_side(side)
	var sprite := TextureRect.new()
	sprite.texture = PixelIcon.texture(kind, grid_side, accent, dimmed)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(grid_side, grid_side)
	sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sprite

## "$12,500" - the game's money text, with thousands separators.
static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-$" if amount < 0 else "$") + out

## "$12K" for places where the exact figure would crowd the row.
static func short_money(amount: int) -> String:
	if absi(amount) >= 1000000:
		return "$%.1fM" % (float(amount) / 1000000.0)
	if absi(amount) >= 10000:
		return "$%dK" % int(roundf(float(amount) / 1000.0))
	return money(amount)

## A percentage of the comments that were happy, for the aura readout.
static func percent(value: float) -> String:
	return "%d%%" % int(roundf(clampf(value, 0.0, 1.0) * 100.0))
