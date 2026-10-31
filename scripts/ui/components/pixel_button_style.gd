extends RefCounted
class_name PixelButtonStyle
## Pixel-art button frames for the out-of-game screens (the title screen and
## the Start New Game setup screen).
##
## The menu's cards and tiles used to be StyleBoxFlat panels with rounded
## corners. This style replaces them with the look of a 16-bit RPG window:
## a straight-edged frame with notched (octagonal) corners, an ink outline,
## a two-pixel accent trim, a bevel that catches light along the top and left
## edges and shades the bottom and right, and a hard-edged sheen band inside
## the top edge over a flat translucent fill. Every colour step is a whole
## pixel - there are no gradients and no curves anywhere in the frame.
##
## Frames are generated as nine-patch StyleBoxTextures: a small image whose
## corners carry the notch art and whose edges carry the frame's layered
## cross-section. The nine-patch margins map 1:1 to screen pixels, so the
## border stays crisp and chunky at every window size while only the flat
## fill stretches. The project's default nearest texture filtering keeps the
## pixels hard.
##
## Because the frame is drawn from a palette rather than a fixed image, each
## action keeps its own accent (gold for the headline card, green for the
## everyday path, muted red for Quit) and every button state - normal, hover,
## pressed, focus, disabled - is the same recipe re-mixed:
##
##  * hover brightens the trim to full strength and lights the bevel up;
##  * pressed swaps the bevel (dark on top and left, lit below) so the card
##    reads as physically pushed into the panel, and darkens the fill;
##  * focus has a high-contrast, ink-edged cream ring and a light surface wash,
##    distinct from both hover and an already-picked option;
##  * disabled desaturates the accent and drops the sheen and bevel;
##  * inset is the same cross-section sunk the other way (dark above, lit
##    below, no sheen), for the recessed surfaces a form sits on: a text
##    field, a preview's frame.
##
## Generated images are cached on their palette, so a menu rebuild after a
## window resize reuses the frames it drew before. The StyleBoxes handed out
## with content margins are copies, so one card's padding can never leak into
## another card that shares its palette.

## Frame states a button can ask for. INSET is not a button state: it is the
## recessed cross-section a field or a preview frame wears.
enum State { NORMAL, HOVER, PRESSED, FOCUS, DISABLED, INSET }

## Width of the frame band, in texture pixels and on screen: the nine-patch
## margins are drawn 1:1. ink(1) + trim(2) + bevel(1) + a three-step hard
## sheen into the fill (3).
const MARGIN := 8
## Side of the flat middle the margins leave between them.
const CENTER := 8
## Side of the generated texture: margins plus the stretchable middle.
const TEXTURE_SIZE := MARGIN * 2 + CENTER
## Pixels cut off each corner diagonally, plus the ink line along the cut:
## the octagonal notch that makes the frame read as pixel art rather than a
## rectangle with the corners sanded down.
const CORNER_CUT := 4

## Trim strength of an unpicked option card, and of one under the pointer:
## low enough that the picked card's full-strength trim stands out.
const CHOICE_TRIM := 0.42
const CHOICE_TRIM_HOVER := 0.85
## Columns of the bottom bar's strip (all identical) and the flat rows below
## its bands that stretch to fill the bar.
const BAR_WIDTH := 4
const BAR_STRETCH := 4

## The frame's own ink: a near-black green, in the family of the menu cards.
const INK := Color("08130f")
## Focus is deliberately lighter and thicker than any card's accent trim. The
## ink edge separates it from bright scenery, while the wash makes the whole
## focused surface read differently even where an outer edge is clipped.
const FOCUS_LIGHT := Color("fff6dc")
const FOCUS_WARM := Color("f4d28c")
const FOCUS_WASH := Color(1.0, 0.96, 0.84, 0.14)
const FOCUS_EXPAND := 3.0
## Ring order, outside in (see MARGIN): what each band of the frame is.
const RING_INK := 0
const RING_TRIM := 1
const RING_TRIM_INNER := 2
const RING_BEVEL := 3
const RING_SHEEN := 4
const RING_SHEEN_MID := 5
const RING_FILL_LIP := 6

## Cache of generated frame images, keyed on palette + state.
static var _image_cache: Dictionary = {}
## Cache of StyleBoxTextures built from them, keyed the same way.
static var _style_cache: Dictionary = {}

# =============================================================================
# PAINTING A BUTTON
# =============================================================================

## Paint a menu card or tile with the pixel frame: the same contract as
## MenuStyle.paint_card (accent, caption room, padding, label colours), so
## screens swap the recipe without changing their layout maths. Content
## margins match the old flat cards exactly, so button minimum sizes - and
## the responsive layouts measured from them - do not move.
static func paint_card(button: Button, accent: Color, caption_block: float, pad: int,
		text_color: Color, hover_color: Color) -> void:
	var bottom := pad + int(caption_block)
	var fills := {
		State.NORMAL: MenuStyle.CARD_BG,
		State.HOVER: MenuStyle.CARD_BG_HOVER,
		State.PRESSED: MenuStyle.CARD_BG_PRESSED,
		State.DISABLED: MenuStyle.CARD_BG_DISABLED,
	}
	var names := {
		State.NORMAL: "normal",
		State.HOVER: "hover",
		State.PRESSED: "pressed",
		State.FOCUS: "focus",
		State.DISABLED: "disabled",
	}
	for state in [State.NORMAL, State.HOVER, State.PRESSED, State.DISABLED]:
		button.add_theme_stylebox_override(names[state], card_style(accent, state, fills[state],
			pad, pad, bottom))
	# Keep the focus overlay's margins identical to the other states: adding a
	# visible selection must not move the title or change the card's size.
	var focus := card_style(accent, State.FOCUS, Color(0, 0, 0, 0), pad, pad, bottom)
	focus.set_expand_margin_all(FOCUS_EXPAND)
	button.add_theme_stylebox_override("focus", focus)

	var font_colors := {
		"normal": text_color,
		"hover": hover_color,
		"pressed": text_color,
		"focus": hover_color,
		"disabled": UIConstants.COLOR_TEXT_MUTED,
	}
	for font_state in font_colors:
		button.add_theme_color_override("font_color" if font_state == "normal" \
			else "font_%s_color" % font_state, font_colors[font_state])

## Paint a selectable (toggle) card: one option among a group, as on the
## setup screen's difficulty, budget and hole pickers. Unpicked it is an
## ordinary card with a trimmed-back accent; the picked one carries the full
## accent, the sunken bevel and a wash of its own colour in the fill, so the
## choice reads at a glance even without colour (the frame sinks and the trim
## weight changes too). Hovering a picked card lifts its fill back up, which
## is what "hover_pressed" is for.
##
## The card's own content is drawn by an overlay rather than by the button's
## label, so the frames carry no content margins - the MarginContainer over
## each button supplies the padding inside the frame band.
static func paint_choice(button: Button, accent: Color) -> void:
	var picked_fill := MenuStyle.CARD_BG.lerp(_opaque(accent), 0.15)
	var picked_hover := MenuStyle.CARD_BG_HOVER.lerp(_opaque(accent), 0.20)
	var styles := {
		"normal": texture_style(_with_alpha(accent, CHOICE_TRIM), State.NORMAL, MenuStyle.CARD_BG),
		"hover": texture_style(_with_alpha(accent, CHOICE_TRIM_HOVER), State.HOVER, MenuStyle.CARD_BG_HOVER),
		"pressed": texture_style(accent, State.PRESSED, picked_fill),
		"hover_pressed": texture_style(accent, State.HOVER, picked_hover),
		"disabled": texture_style(_with_alpha(accent, CHOICE_TRIM), State.DISABLED, MenuStyle.CARD_BG_DISABLED),
	}
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])
	button.add_theme_stylebox_override("focus", focus_ring(accent))

## Paint the screen's one solid call to action (Choose Location): the same
## frame recipe with the fill itself in gold, so the button reads as a chunky
## slab of the palette's "special" colour rather than a card with gold trim.
static func paint_primary(button: Button, accent: Color = MenuStyle.ACCENT_PRIMARY) -> void:
	var styles := {
		"normal": texture_style(accent, State.NORMAL, accent),
		"hover": texture_style(accent.lightened(0.12), State.HOVER, accent.lightened(0.12)),
		"pressed": texture_style(accent.darkened(0.18), State.PRESSED, accent.darkened(0.12)),
		"disabled": texture_style(_with_alpha(accent, 0.4), State.DISABLED, _with_alpha(accent, 0.35)),
	}
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])
	button.add_theme_stylebox_override("focus", focus_ring(accent))
	for font_state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_color_override("font_color" if font_state == "normal" \
			else "font_%s_color" % font_state, MenuStyle.INK)
	button.add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)

## Paint a text field as a recessed pixel surface with the same visible focus
## treatment as the buttons. The light wash stays under the field's text.
static func paint_field(field: LineEdit, accent: Color, fill: Color, pad: int) -> void:
	field.add_theme_stylebox_override("normal", inset_style(accent, fill, pad))
	field.add_theme_stylebox_override("read_only", inset_style(accent, fill, pad))
	var focus := focus_ring(accent)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		focus.set_content_margin(side, float(pad))
	field.add_theme_stylebox_override("focus", focus)

## The focus overlay: a notched, ink-edged light band and a translucent wash.
## It is drawn over the normal/hover/pressed frame but under the control's text,
## so focus remains distinct from a choice that has actually been selected.
static func focus_ring(accent: Color) -> StyleBoxTexture:
	var style := _styled(accent, State.FOCUS, Color(0, 0, 0, 0))
	style.set_expand_margin_all(FOCUS_EXPAND)
	return style

## A full-width strip of the frame's cross-section - ink, trim, bevel and the
## hard sheen steps down into the fill - with no notches and no side bands,
## for the bar a screen pins to its bottom edge.
static func bar_style(accent: Color, fill: Color) -> StyleBoxTexture:
	var key := _cache_key(accent, State.NORMAL, fill) + "|bar"
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(bar_image(accent, fill))
	style.texture_margin_top = float(MARGIN)
	style.texture_margin_left = 0.0
	style.texture_margin_right = 0.0
	style.texture_margin_bottom = 0.0
	_style_cache[key] = style
	return style

## The strip's image: BAR_WIDTH identical columns of the frame's cross-section
## (outside in) over a few rows of flat fill, which is what stretches.
static func bar_image(accent: Color, fill: Color) -> Image:
	var key := _cache_key(accent, State.NORMAL, fill) + "|bar"
	if _image_cache.has(key):
		return _image_cache[key]
	var palette := _palette(accent, State.NORMAL, fill)
	var bands: Array[Color] = [
		palette["ink"], palette["trim"], palette["trim_inner"], palette["bevel_light"],
		palette["sheen_top"], palette["sheen_mid"], palette["lip_top"], fill,
	]
	var image := Image.create_empty(BAR_WIDTH, MARGIN + BAR_STRETCH, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		var color: Color = bands[y] if y < bands.size() else fill
		for x in BAR_WIDTH:
			image.set_pixel(x, y, color)
	_image_cache[key] = image
	return image

## A copy of the cached frame, so a caller can set content margins on it
## without changing every other frame that shares the palette.
static func _styled(accent: Color, state: int, fill: Color) -> StyleBoxTexture:
	return (texture_style(accent, state, fill) as StyleBoxTexture).duplicate()

static func _with_alpha(color: Color, alpha: float) -> Color:
	return MenuStyle.with_alpha(color, alpha)

static func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)

## A pixel frame as a nine-patch StyleBoxTexture with explicit content
## margins (a card's label and caption room, or a panel's padding). The cached
## frame is copied first: the margins belong to this caller alone.
static func card_style(accent: Color, state: int, fill: Color,
		pad_left: int, pad_top: int, pad_bottom: int) -> StyleBoxTexture:
	var style := _styled(accent, state, fill)
	style.content_margin_left = float(pad_left)
	style.content_margin_right = float(pad_left)
	style.content_margin_top = float(pad_top)
	style.content_margin_bottom = float(pad_bottom)
	return style

## A static panel in the same frame recipe (the Continue rail on the title
## screen, the setup screen's option sheet and its company rail): ink outline,
## trim in `accent`, no hover states and no bevel drama - furniture, not a
## button.
static func panel_style(accent: Color, fill: Color, pad_x: int, pad_y: int) -> StyleBoxTexture:
	var style := _styled(accent, State.NORMAL, fill)
	style.content_margin_left = float(pad_x)
	style.content_margin_right = float(pad_x)
	style.content_margin_top = float(pad_y)
	style.content_margin_bottom = float(pad_y)
	return style

## A recessed surface in the same recipe, lit from below so it reads as sunk
## into the panel around it: the frame a text field or a preview sits in.
static func inset_style(accent: Color, fill: Color, pad: int) -> StyleBoxTexture:
	var style := _styled(accent, State.INSET, fill)
	style.content_margin_left = float(pad)
	style.content_margin_right = float(pad)
	style.content_margin_top = float(pad)
	style.content_margin_bottom = float(pad)
	return style

## The nine-patch StyleBoxTexture itself, from the cache when this palette has
## been generated before.
static func texture_style(accent: Color, state: int, fill: Color) -> StyleBoxTexture:
	var key := _cache_key(accent, state, fill)
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxTexture.new()
	style.texture = texture_for(accent, state, fill)
	style.texture_margin_left = float(MARGIN)
	style.texture_margin_top = float(MARGIN)
	style.texture_margin_right = float(MARGIN)
	style.texture_margin_bottom = float(MARGIN)
	_style_cache[key] = style
	return style

static func texture_for(accent: Color, state: int, fill: Color) -> ImageTexture:
	return ImageTexture.create_from_image(frame_image(accent, state, fill))

# =============================================================================
# FRAME GEOMETRY
# =============================================================================

## The frame image for one palette and state. Pure Image work, so it runs
## headless and tests can inspect it pixel by pixel.
static func frame_image(accent: Color, state: int, fill: Color) -> Image:
	var key := _cache_key(accent, state, fill)
	if _image_cache.has(key):
		return _image_cache[key]
	var palette := _palette(accent, state, fill)
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			image.set_pixel(x, y, _pixel_color(x, y, palette))
	_image_cache[key] = image
	return image

## The colour of one texture pixel: the notch cut first, then the frame band
## the pixel falls in, then the flat fill.
static func _pixel_color(x: int, y: int, palette: Dictionary) -> Color:
	var last := TEXTURE_SIZE - 1
	# Distance to each edge; the ring is the nearest edge's distance.
	var dt := y
	var db := last - y
	var dl := x
	var dr := last - x
	var ring := mini(mini(dt, db), mini(dl, dr))

	# Octagonal notch: everything outside the diagonal is air, and the diagonal
	# itself is ink, outlining the cut through the trim and bevel.
	var corner_u := mini(x, last - x)
	var corner_v := mini(y, last - y)
	if corner_u + corner_v < CORNER_CUT:
		return Color(0, 0, 0, 0)
	if corner_u + corner_v == CORNER_CUT and ring < CORNER_CUT:
		return palette["ink"]

	# Which edge owns the pixel decides the bevel: light from the top left,
	# shadow along the bottom right. Ties (a corner) go to the lit edges.
	var lit := (dt == ring and dt <= db) or (dl == ring and dl <= dr)
	var shaded := (db == ring and db < dt) or (dr == ring and dr < dl)

	match ring:
		RING_INK:
			return palette["ink"]
		RING_TRIM:
			return palette["trim"]
		RING_TRIM_INNER:
			return palette["trim_inner"]
		RING_BEVEL:
			if lit:
				return palette["bevel_light"]
			if shaded:
				return palette["bevel_dark"]
			return palette["bevel_light"]
		RING_SHEEN:
			if dt == ring:
				return palette["sheen_top"]
			if db == ring:
				return palette["shade_bottom"]
			return palette["sheen_side"]
		RING_SHEEN_MID:
			if dt == ring:
				return palette["sheen_mid"]
			if db == ring:
				return palette["shade_mid"]
			return palette["sheen_side_mid"]
		RING_FILL_LIP:
			if dt == ring:
				return palette["lip_top"]
			if db == ring:
				return palette["lip_bottom"]
			return palette["fill"]
	return palette["fill"]

# =============================================================================
# PALETTES
# =============================================================================

## Every colour the frame recipe needs, mixed from the card's accent, its fill
## and the state. Keeping the mixing in one place is what lets hover, pressed
## and disabled read as the same object under different light.
static func _palette(accent: Color, state: int, fill: Color) -> Dictionary:
	var ink := Color(INK.r, INK.g, INK.b, 0.96)
	var palette := {
		"ink": ink,
		"fill": fill,
	}
	match state:
		State.HOVER:
			palette["trim"] = accent.lightened(0.15)
			palette["trim_inner"] = accent.lightened(0.04)
			palette["bevel_light"] = accent.lightened(0.62)
			palette["bevel_dark"] = _mix(accent.darkened(0.55), ink, 0.5)
			palette["sheen_top"] = _mix(fill.lightened(0.16), accent, 0.22)
			palette["sheen_mid"] = _mix(fill.lightened(0.09), accent, 0.13)
			palette["sheen_side"] = _mix(fill.lightened(0.07), accent, 0.10)
			palette["sheen_side_mid"] = _mix(fill.lightened(0.04), accent, 0.06)
			palette["shade_bottom"] = _mix(fill.darkened(0.06), accent, 0.06)
			palette["shade_mid"] = _mix(fill.darkened(0.03), accent, 0.04)
			palette["lip_top"] = _mix(fill.lightened(0.05), accent, 0.07)
			palette["lip_bottom"] = fill.darkened(0.03)
		State.PRESSED:
			# Sunken: the bevel flips, the sheen goes out and the trim dims.
			palette["trim"] = accent.darkened(0.20)
			palette["trim_inner"] = accent.darkened(0.40)
			palette["bevel_light"] = _mix(accent.darkened(0.60), ink, 0.55)
			palette["bevel_dark"] = _mix(accent.lightened(0.30), fill, 0.30)
			palette["sheen_top"] = fill.darkened(0.06)
			palette["sheen_mid"] = fill.darkened(0.03)
			palette["sheen_side"] = fill.darkened(0.02)
			palette["sheen_side_mid"] = fill
			palette["shade_bottom"] = _mix(fill.lightened(0.05), accent, 0.06)
			palette["shade_mid"] = _mix(fill.lightened(0.03), accent, 0.04)
			palette["lip_top"] = fill.darkened(0.02)
			palette["lip_bottom"] = fill
		State.FOCUS:
			# A solid ink outline around two cream pixels and a warm inner band
			# stands out on both dark cards and the bright scenery behind them.
			# The translucent wash is a second cue, without hiding a toggle's
			# pressed frame or changing the contrast of the text drawn over it.
			var inner := FOCUS_WARM.lerp(_opaque(accent), 0.15)
			palette["ink"] = INK
			palette["trim"] = FOCUS_LIGHT
			palette["trim_inner"] = FOCUS_LIGHT
			palette["bevel_light"] = inner
			palette["bevel_dark"] = inner
			palette["sheen_top"] = FOCUS_WASH
			palette["sheen_mid"] = FOCUS_WASH
			palette["sheen_side"] = FOCUS_WASH
			palette["sheen_side_mid"] = FOCUS_WASH
			palette["shade_bottom"] = FOCUS_WASH
			palette["shade_mid"] = FOCUS_WASH
			palette["lip_top"] = FOCUS_WASH
			palette["lip_bottom"] = FOCUS_WASH
			palette["fill"] = FOCUS_WASH
		State.DISABLED:
			# Desaturated trim, no bevel or sheen: the card is furniture until
			# a save turns up.
			var grey := _desaturate(accent, 0.72)
			palette["trim"] = Color(grey.r, grey.g, grey.b, grey.a * 0.55)
			palette["trim_inner"] = Color(grey.r, grey.g, grey.b, grey.a * 0.4)
			palette["bevel_light"] = Color(grey.r, grey.g, grey.b, grey.a * 0.35)
			palette["bevel_dark"] = Color(ink.r, ink.g, ink.b, 0.5)
			palette["sheen_top"] = fill
			palette["sheen_mid"] = fill
			palette["sheen_side"] = fill
			palette["sheen_side_mid"] = fill
			palette["shade_bottom"] = fill
			palette["shade_mid"] = fill
			palette["lip_top"] = fill
			palette["lip_bottom"] = fill
		State.INSET:
			# Sunk the other way: the bevel is shaded along the top and left
			# and lit along the bottom and right, the trim is inked rather
			# than trimmed in the accent, and there is no sheen - a recessed
			# surface catches no light from above.
			palette["trim"] = _mix(accent.darkened(0.50), ink, 0.45)
			palette["trim_inner"] = _mix(accent.darkened(0.30), ink, 0.35)
			palette["bevel_light"] = _mix(ink, accent.darkened(0.62), 0.40)
			palette["bevel_dark"] = _mix(fill.lightened(0.14), accent, 0.12)
			palette["sheen_top"] = fill
			palette["sheen_mid"] = fill
			palette["sheen_side"] = fill
			palette["sheen_side_mid"] = fill
			palette["shade_bottom"] = fill
			palette["shade_mid"] = fill
			palette["lip_top"] = fill
			palette["lip_bottom"] = fill
		_:
			palette["trim"] = Color(accent.r, accent.g, accent.b, accent.a * 0.95)
			palette["trim_inner"] = accent.darkened(0.22)
			palette["bevel_light"] = accent.lightened(0.50)
			palette["bevel_dark"] = _mix(accent.darkened(0.62), ink, 0.45)
			palette["sheen_top"] = _mix(fill.lightened(0.13), accent, 0.18)
			palette["sheen_mid"] = _mix(fill.lightened(0.07), accent, 0.10)
			palette["sheen_side"] = _mix(fill.lightened(0.05), accent, 0.08)
			palette["sheen_side_mid"] = _mix(fill.lightened(0.03), accent, 0.04)
			palette["shade_bottom"] = _mix(fill.darkened(0.05), accent, 0.05)
			palette["shade_mid"] = _mix(fill.darkened(0.02), accent, 0.03)
			palette["lip_top"] = _mix(fill.lightened(0.04), accent, 0.06)
			palette["lip_bottom"] = fill.darkened(0.02)
	return palette

## Blend two colours, keeping the result's alpha at full strength of `a`'s.
static func _mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))

## Pull a colour towards its own luminance: the disabled trim's grey.
static func _desaturate(color: Color, amount: float) -> Color:
	var lum := color.get_luminance()
	return color.lerp(Color(lum, lum, lum, color.a), clampf(amount, 0.0, 1.0))

static func _cache_key(accent: Color, state: int, fill: Color) -> String:
	return "%s|%d|%s" % [accent.to_html(), state, fill.to_html()]
