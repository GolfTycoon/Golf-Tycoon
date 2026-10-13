extends RefCounted
class_name PixelButtonStyle
## Pixel-art button frames for the title screen.
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
##  * focus is a bright notched ring floating just outside the frame;
##  * disabled desaturates the accent and drops the sheen and bevel.
##
## Generated images are cached on their palette, so a menu rebuild after a
## window resize reuses the frames it drew before.

## Frame states a button can ask for.
enum State { NORMAL, HOVER, PRESSED, FOCUS, DISABLED }

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

## The frame's own ink: a near-black green, in the family of the menu cards.
const INK := Color("08130f")
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
	# The focus ring floats clear of the frame instead of sitting on it, so it
	# never masks the notch or the trim that carries the accent.
	var focus := card_style(accent, State.FOCUS, Color(0, 0, 0, 0), pad, pad, bottom)
	focus.set_expand_margin_all(3.0)
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

## A pixel frame as a nine-patch StyleBoxTexture with explicit content
## margins (a card's label and caption room, or a panel's padding).
static func card_style(accent: Color, state: int, fill: Color,
		pad_left: int, pad_top: int, pad_bottom: int) -> StyleBoxTexture:
	var style := texture_style(accent, state, fill)
	style.content_margin_left = float(pad_left)
	style.content_margin_right = float(pad_left)
	style.content_margin_top = float(pad_top)
	style.content_margin_bottom = float(pad_bottom)
	return style

## A static panel in the same frame recipe (the Continue rail on the title
## screen): ink outline, trim in `accent`, no hover states and no bevel
## drama - furniture, not a button.
static func panel_style(accent: Color, fill: Color, pad_x: int, pad_y: int) -> StyleBoxTexture:
	var style := texture_style(accent, State.NORMAL, fill)
	style.content_margin_left = float(pad_x)
	style.content_margin_right = float(pad_x)
	style.content_margin_top = float(pad_y)
	style.content_margin_bottom = float(pad_y)
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
			# A bright notched ring floating just outside the frame: only the
			# ink and first trim band draw, everything else is air.
			var ring := _mix(UIConstants.COLOR_TEXT, accent, 0.35)
			palette["trim"] = Color(ring.r, ring.g, ring.b, 0.9)
			palette["trim_inner"] = Color(ring.r, ring.g, ring.b, 0.45)
			palette["bevel_light"] = Color(0, 0, 0, 0)
			palette["bevel_dark"] = Color(0, 0, 0, 0)
			palette["sheen_top"] = Color(0, 0, 0, 0)
			palette["sheen_mid"] = Color(0, 0, 0, 0)
			palette["sheen_side"] = Color(0, 0, 0, 0)
			palette["sheen_side_mid"] = Color(0, 0, 0, 0)
			palette["shade_bottom"] = Color(0, 0, 0, 0)
			palette["shade_mid"] = Color(0, 0, 0, 0)
			palette["lip_top"] = Color(0, 0, 0, 0)
			palette["lip_bottom"] = Color(0, 0, 0, 0)
			palette["ink"] = Color(0, 0, 0, 0)
			palette["fill"] = Color(0, 0, 0, 0)
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
