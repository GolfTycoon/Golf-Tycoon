extends RefCounted
class_name PixelButtonStyle
## The glass-pill frame every menu control in the game is dressed in: the title
## screen's cards and tiles, the Start New Game pickers, the World Map, the
## Course Map, the milestone and achievement ledgers and the clubhouse
## dashboards.
##
## The recipe is a rounded slab of tinted glass on a dark green card:
##
##  * a soft ink outline, drawn on the inside of the shape so a pill never
##    grows past the control it is painted on;
##  * a slim accent rim that catches the light - it runs bright along the top
##    left, where the key light falls, and deepens towards the bottom right;
##  * a glassy gloss band laid across the top of the body, fading out before it
##    reaches the label, with a hot highlight line where it meets the rim;
##  * a faint inner bevel: lit just under the top rim, shadowed along the bottom
##    edge, so the surface reads as slightly domed;
##  * a translucent body that lets the clubhouse art behind the menu show
##    through, mixed with a wash of the card's own accent;
##  * a short soft contact shadow underneath, and a barely-there accent bloom
##    above, so a card sits on the screen instead of being pasted onto it.
##
## Frames are generated as nine-patch StyleBoxTextures: one small image holds
## the rounded corners, and the flat middle stretches. The margins are snapped
## to whole pixels, so the rims stay crisp at every window size, and every
## button state is the same recipe re-mixed:
##
##  * hover lifts the body, brightens the rim and the gloss, and pushes the
##    contact shadow further out - the card comes towards the pointer;
##  * pressed sinks it: the gloss goes out, the fill darkens, the rim dims and
##    the shadow pulls in under the card;
##  * focus wraps the whole pill in a cream ring over a warm wash, distinct
##    from both hover and an already-picked option;
##  * disabled drops the accent to a grey and takes the gloss and shadow away;
##  * inset is the same cross-section pressed the other way - dark along the
##    top, lit along the bottom, no gloss - for a field or a preview's frame.
##
## Generated images are cached on their palette, so a menu rebuild after a
## window resize reuses the frames it drew before. The StyleBoxes handed out
## with content margins are copies, so one card's padding can never leak into
## another card that shares its palette.

## Frame states a button can ask for. INSET and PRIMARY are not button states
## as such: INSET is the recessed cross-section a field or a preview frame
## wears, and PRIMARY is the normal card lit as a solid accent slab (the one
## call to action on a screen).
enum State { NORMAL, HOVER, PRESSED, FOCUS, DISABLED, INSET, PRIMARY }

# =============================================================================
# GEOMETRY
# =============================================================================

## Side of the generated texture. The corners need room for the curve, the ink
## and the contact shadow; the rest is the flat middle the nine-patch stretches.
const TEXTURE_SIZE := 60
## How far the pill is inset from the texture's edges, leaving room for the
## contact shadow and the accent bloom that sit outside it.
const BLEED := 3
## Nine-patch margins: the area of the texture drawn 1:1 rather than stretched.
## They are generous on the top (the gloss band lives there) and on the right
## (where the focus ring's extra width is kept), so neither feature can be
## smeared by a wide card.
const MARGIN_LEFT := 20
const MARGIN_RIGHT := 20
const MARGIN_TOP := 12
const MARGIN_BOTTOM := 12
## Corner radius of the pill, in texture pixels.
const RADIUS := 9.0
## Radius of the recessed surfaces (fields, previews): a tighter curve, so an
## inset reads as a trough cut into the card around it.
const INSET_RADIUS := 8.0
## Thickness of the frame bands, from the outside in: the ink outline and the
## accent rim that runs inside it.
const INK_WIDTH := 1.9
const RIM_WIDTH := 3.4
## How far the focus ring reaches beyond the card, in pixels.
const FOCUS_EXPAND := 3.0

## Height of the bar strip's frame bands. A strip pinned to a screen's bottom
## edge is furniture, not a card, so it wears a slimmer cross-section than a
## pill: ink, rim, gloss and body in eight rows.
const BAR_BAND := 8
## The nine-patch width the bar strip needs: the stripe repeats across it.
const BAR_WIDTH := 8
## Rows of flat fill under the bar's frame that stretch to the bar's height.
const BAR_STRETCH := 4

# =============================================================================
# PALETTE
# =============================================================================

## The frame's own ink: a near-black green, in the family of the menu cards.
const INK := Color("08130f")
## Focus is deliberately lighter and thicker than any card's accent rim, so a
## keyboard or controller player can find the focused card over bright scenery.
const FOCUS_LIGHT := Color("fff6dc")
const FOCUS_WARM := Color("f4d28c")
## The translucent warm wash the focus ring draws over the card's own surface:
## enough to light the card up, not enough to hide a toggle that is picked.
const FOCUS_WASH := Color(1.0, 0.96, 0.84, 0.14)

## Trim strength of an unpicked option card, and of one under the pointer:
## low enough that the picked card's full-strength rim stands out.
const CHOICE_TRIM := 0.42
const CHOICE_TRIM_HOVER := 0.85

## Cache of generated frame images, keyed on palette + state.
static var _image_cache: Dictionary = {}
## Cache of StyleBoxTextures built from them, keyed the same way.
static var _style_cache: Dictionary = {}

# =============================================================================
# PAINTING A BUTTON
# =============================================================================

## Paint a menu card or tile with the glass frame: the same contract as
## MenuStyle.paint_card (accent, caption room, padding, label colours), so
## screens swap the recipe without changing their layout maths. Content
## margins match the flat cards this replaces, so button minimum sizes - and
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
	paint_focus(button, accent, pad, pad, bottom)

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
## accent and a wash of its own colour in the body, so the choice reads at a
## glance even without colour (the rim weight and the body tint change too).
## Hovering a picked card lifts its body back up, which is what
## "hover_pressed" is for.
##
## The card's own content is drawn by an overlay rather than by the button's
## label, so the frames carry no content margins - the MarginContainer over
## each button supplies the padding inside the frame band.
static func paint_choice(button: Button, accent: Color) -> void:
	var picked_fill := MenuStyle.CARD_BG.lerp(_opaque(accent), 0.16)
	var picked_hover := MenuStyle.CARD_BG_HOVER.lerp(_opaque(accent), 0.22)
	var styles := {
		"normal": texture_style(_with_alpha(accent, CHOICE_TRIM), State.NORMAL, MenuStyle.CARD_BG),
		"hover": texture_style(_with_alpha(accent, CHOICE_TRIM_HOVER), State.HOVER, MenuStyle.CARD_BG_HOVER),
		"pressed": texture_style(accent, State.PRESSED, picked_fill),
		"hover_pressed": texture_style(accent, State.HOVER, picked_hover),
		"disabled": texture_style(_with_alpha(accent, CHOICE_TRIM), State.DISABLED, MenuStyle.CARD_BG_DISABLED),
	}
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])
	paint_focus(button, accent)

## Paint the screen's one solid call to action (Choose Location, Save): the
## same frame recipe with the body itself in the accent colour, so the button
## reads as a solid slab of the palette's "special" gold rather than a card
## with gold trim. The rim is a lighter take on the same colour, the way a
## polished metal edge catches light.
static func paint_primary(button: Button, accent: Color = MenuStyle.ACCENT_PRIMARY) -> void:
	var styles := {
		"normal": texture_style(accent, State.PRIMARY, accent),
		"hover": texture_style(accent.lightened(0.16), State.PRIMARY, accent.lightened(0.14)),
		"pressed": texture_style(accent.darkened(0.20), State.PRESSED, accent.darkened(0.12)),
		"disabled": texture_style(_with_alpha(accent, 0.4), State.DISABLED, _with_alpha(accent, 0.35)),
	}
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])
	paint_focus(button, accent)
	for font_state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_color_override("font_color" if font_state == "normal" \
			else "font_%s_color" % font_state, MenuStyle.INK)
	button.add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)

## Paint a text field as a recessed surface with the same visible focus
## treatment as the buttons. The light wash stays under the field's text.
static func paint_field(field: LineEdit, accent: Color, fill: Color, pad: int) -> void:
	field.add_theme_stylebox_override("normal", inset_style(accent, fill, pad))
	field.add_theme_stylebox_override("read_only", inset_style(accent, fill, pad))
	paint_focus(field, accent, pad, pad, pad)

## The focus treatment, in two halves so neither spoils the other:
##
##  * the bright ring - a cream band with an ink edge - is handed to the
##    control's MenuFocusRing layer, which draws it around the pill's rounded
##    edge, a few pixels outside the frame, where a stylebox could not reach;
##  * the warm wash stays on the control's own "focus" stylebox, so it tints
##    the surface under the label rather than over the letters.
##
## Together they keep focus unmistakable against bright scenery and clearly
## different from a hover or an already-picked option. The content margins are
## kept identical to the other states, so focus never moves a title or resizes
## a card.
static func paint_focus(control: Control, accent: Color,
		pad_left: int = 0, pad_top: int = 0, pad_bottom: int = 0) -> void:
	var wash := StyleBoxFlat.new()
	wash.bg_color = FOCUS_WASH
	wash.set_corner_radius_all(int(RADIUS))
	wash.content_margin_left = float(pad_left)
	wash.content_margin_right = float(pad_left)
	wash.content_margin_top = float(pad_top)
	wash.content_margin_bottom = float(pad_bottom)
	control.add_theme_stylebox_override("focus", wash)
	_ring(control, focus_ring(accent))


## The ring on its own: the focus frame's bands and nothing in the middle, so
## it can be drawn around a pill without covering what is inside it. Its expand
## margins record how far past the pill it belongs.
static func focus_ring(accent: Color) -> StyleBoxTexture:
	var style := _styled(accent, State.FOCUS, Color(0, 0, 0, 0))
	style.draw_center = false
	style.set_expand_margin_all(FOCUS_EXPAND)
	return style

## A full-width slab of the frame's cross-section - ink, rim, gloss and the
## body - with no rounded ends, for the bar a screen pins to its bottom edge.
static func bar_style(accent: Color, fill: Color) -> StyleBoxTexture:
	var key := _cache_key(accent, State.NORMAL, fill) + "|bar"
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(bar_image(accent, fill))
	style.texture_margin_top = float(BAR_BAND)
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
		palette["ink"], palette["rim"], palette["rim_light"], palette["gloss"],
		palette["body_top"], palette["body_top"], palette["body_bottom"], fill,
	]
	var image := Image.create_empty(BAR_WIDTH, BAR_BAND + BAR_STRETCH, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		var color: Color = bands[y] if y < bands.size() else fill
		for x in BAR_WIDTH:
			image.set_pixel(x, y, color)
	_image_cache[key] = image
	return image

## Hand a control's focus ring to its own layer (MenuFocusRing), which draws
## the ring around the pill's rounded edge and lets the pointer through. Doing
## it here, in the one place every painted control goes through, keeps a screen
## from forgetting - and makes attaching twice impossible.
static func _ring(control: Control, style: StyleBoxTexture) -> void:
	if style == null:
		return
	if control.has_node("FocusRing"):
		return
	MenuFocusRing.attach(control, style)


# =============================================================================
# STYLEBOXES
# =============================================================================

## A copy of the cached frame, so a caller can set content margins on it
## without changing every other frame that shares the palette.
static func _styled(accent: Color, state: int, fill: Color) -> StyleBoxTexture:
	return (texture_style(accent, state, fill) as StyleBoxTexture).duplicate()

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
## rim in `accent`, no hover states and no rim drama - furniture, not a button.
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
	style.texture_margin_left = float(MARGIN_LEFT)
	style.texture_margin_top = float(MARGIN_TOP)
	style.texture_margin_right = float(MARGIN_RIGHT)
	style.texture_margin_bottom = float(MARGIN_BOTTOM)
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
	if state == State.INSET:
		_image_cache[key] = _inset_image(accent, fill)
		return _image_cache[key]
	var palette := _palette(accent, state, fill)
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var shape := Vector2(TEXTURE_SIZE, TEXTURE_SIZE) - Vector2(BLEED, BLEED) * 2.0
	# The glassy band inside the top rim, in texture rows below the rim. It has
	# to finish inside the top margin: a nine-patch stretches everything past
	# it, and a half-drawn gloss would smear along the top of a wide card.
	var gloss_span := maxf(float(MARGIN_TOP) - BLEED - INK_WIDTH - RIM_WIDTH - 2.0, 2.0)
	# Key light: above and a little to the left, as on every sprite in the game.
	var light := Vector2(-0.32, -1.0).normalized()
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var local := point - Vector2(BLEED, BLEED)
			var distance := _pill_distance(local, shape, RADIUS)
			var coverage := clampf(0.5 - distance, 0.0, 1.0)
			# Contact shadow: the same pill, nudged down and faded out short.
			var shadow_distance := _pill_distance(point - Vector2(0.0, 1.8),
				Vector2(TEXTURE_SIZE, TEXTURE_SIZE), RADIUS + 1.0)
			var shadow_alpha := clampf(1.0 - shadow_distance / 2.4, 0.0, 1.0) * float(palette["shadow"])
			var shadow := Color(0.008, 0.043, 0.031, shadow_alpha)
			if coverage <= 0.0:
				if shadow_alpha > 0.0:
					image.set_pixel(x, y, shadow)
				continue
			var normal := _pill_normal(local, shape, RADIUS)
			var facing := clampf(normal.dot(light) * 0.5 + 0.5, 0.0, 1.0)
			var depth := -distance
			var color := _body_color(palette, y, x, depth, facing, gloss_span)
			# Bounce light: a single lit line just inside the bottom rim, where
			# a glassy surface catches the light coming back off the screen.
			var rim_edge := INK_WIDTH + RIM_WIDTH
			if depth > rim_edge - 0.4 and depth < rim_edge + 0.9 and facing < 0.45:
				color = color.lerp(palette["rim_light"], 0.30 * (0.45 - facing) / 0.45)
			# Rim: the accent, lit where it turns towards the key light.
			if depth < rim_edge:
				var rim: Color = (palette["rim_dark"] as Color).lerp(palette["rim_light"], facing)
				rim = rim.lerp(palette["rim"], 0.30)
				# A hot pin where the rim faces the light head on.
				var pin := pow(clampf((facing - 0.80) / 0.20, 0.0, 1.0), 2.2)
				rim = rim.lerp(Color(1, 1, 1, rim.a), pin * 0.30)
				color = rim
				# Ink outline, with a deeper bite along the shaded side.
				if depth < INK_WIDTH:
					color = (palette["ink"] as Color).darkened((1.0 - facing) * 0.35)
				elif depth < INK_WIDTH + 0.5:
					color = _with_alpha(palette["ink"], 0.45)
			if coverage < 1.0:
				color = _with_alpha(color, coverage)
			image.set_pixel(x, y, _over(color, shadow))
	_image_cache[key] = image
	return image

## The recessed surface: a trough with an ink edge, dark along the top and lit
## along the bottom the way a hole catches light from above.
static func _inset_image(accent: Color, fill: Color) -> Image:
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var shape := Vector2(TEXTURE_SIZE, TEXTURE_SIZE)
	var light := Vector2(-0.32, -1.0).normalized()
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var distance := _pill_distance(point, shape, INSET_RADIUS)
			var coverage := clampf(0.5 - distance, 0.0, 1.0)
			if coverage <= 0.0:
				continue
			var depth := -distance
			var color := fill
			if depth < 2.2:
				color = _with_alpha(INK, 0.85)
			elif depth < 5.2:
				var normal := _pill_normal(point, shape, INSET_RADIUS)
				var facing := clampf(normal.dot(light) * 0.5 + 0.5, 0.0, 1.0)
				var falloff := clampf((5.2 - depth) / 3.0, 0.0, 1.0)
				color = fill.lerp(fill.darkened(0.42), falloff * facing)
				color = color.lerp(_with_alpha(accent, 0.45), 0.4 * falloff)
			if coverage < 1.0:
				color = _with_alpha(color, coverage)
			image.set_pixel(x, y, color)
	return image

## The body of one frame pixel: the flat fill, the two-tone top band, the
## glassy gloss and the inner bevel under the rim.
static func _body_color(palette: Dictionary, y: int, _x: int, depth: float,
		facing: float, gloss_span: float) -> Color:
	var body: Color = palette["body_bottom"]
	# The two-tone body starts inside the top rim and finishes with room to
	# spare inside the top margin: past the margin a nine-patch stretches the
	# row, so the gradient must already be flat by then.
	if y < MARGIN_TOP - 2:
		var down := clampf((float(y) - BLEED) / float(MARGIN_TOP - BLEED - 2), 0.0, 1.0)
		body = (palette["body_top"] as Color).lerp(palette["body_bottom"], pow(down, 0.75))
	var rim_edge := INK_WIDTH + RIM_WIDTH
	# Glassy gloss: a hard highlight line, then a band that fades out.
	if depth > rim_edge:
		var gloss: float = palette["gloss"]
		if gloss > 0.0:
			var into := float(y) - (BLEED + rim_edge)
			if into >= 0.0 and into < gloss_span:
				var strength := gloss * pow(1.0 - into / gloss_span, 1.35)
				if into < 1.5:
					strength = gloss * 2.1
				body = body.lerp(Color(1, 0.995, 0.95), clampf(strength, 0.0, 0.5))
	# Inner bevel: lit just under the rim at the top, shaded along the bottom.
	if depth > rim_edge - 0.3 and depth < rim_edge + 1.3:
		var topness := clampf(1.0 - (float(y) - BLEED) / (float(TEXTURE_SIZE) * 0.31), 0.0, 1.0)
		body = body.lerp(palette["inner_top"], topness * facing)
	if depth > rim_edge - 0.3 and depth < rim_edge + 2.0:
		var bottomness := clampf(((float(y) - BLEED) / float(TEXTURE_SIZE) - 0.5) / 0.5, 0.0, 1.0)
		body = body.lerp(palette["inner_bottom"], bottomness)
	return body

## Signed distance from `point` to a rounded rectangle of `size` and corner
## radius `radius`, measured in the controller's own pixels. Negative inside.
static func _pill_distance(point: Vector2, size: Vector2, radius: float) -> float:
	var half := size * 0.5
	var q := Vector2(absf(point.x - half.x), absf(point.y - half.y)) - (half - Vector2(radius, radius))
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	return outside + minf(maxf(q.x, q.y), 0.0) - radius

## The outward normal of the pill at `point`, from the distance field's
## gradient. Used to light the rim and bevel.
static func _pill_normal(point: Vector2, size: Vector2, radius: float) -> Vector2:
	var step := 0.8
	var gradient := Vector2(
		_pill_distance(point + Vector2(step, 0), size, radius)
			- _pill_distance(point - Vector2(step, 0), size, radius),
		_pill_distance(point + Vector2(0, step), size, radius)
			- _pill_distance(point - Vector2(0, step), size, radius))
	if gradient.length() < 0.0001:
		return Vector2(0.0, -1.0)
	return gradient.normalized()

# =============================================================================
# PALETTES
# =============================================================================

## Every colour the frame recipe needs, mixed from the card's accent, its fill
## and the state. Keeping the mixing in one place is what lets hover, pressed
## and disabled read as the same object under different light.
static func _palette(accent: Color, state: int, fill: Color) -> Dictionary:
	var palette := {
		"ink": _with_alpha(INK, 0.92),
		"rim": accent,
		"rim_light": accent.lightened(0.40),
		"rim_dark": accent.darkened(0.30),
		"gloss": 0.13,
		"body_top": _wash(fill, accent, 0.20, 0.20),
		"body_bottom": _wash(fill, accent, 0.07, 0.04),
		"inner_top": Color(1, 1, 1, 0.10),
		"inner_bottom": Color(0, 0, 0, 0.16),
		"shadow": 0.30,
	}
	match state:
		State.HOVER:
			palette["rim"] = accent.lightened(0.22)
			palette["rim_light"] = accent.lightened(0.72)
			palette["rim_dark"] = accent.darkened(0.14)
			palette["gloss"] = 0.20
			palette["body_top"] = _wash(fill, accent, 0.26, 0.20)
			palette["body_bottom"] = _wash(fill, accent, 0.10, 0.04)
			palette["inner_top"] = Color(1, 1, 1, 0.17)
			palette["shadow"] = 0.36
		State.PRESSED:
			# Sunken: the gloss goes out, the rim dims and the body darkens.
			palette["rim"] = accent.darkened(0.22)
			palette["rim_light"] = accent.darkened(0.04)
			palette["rim_dark"] = accent.lightened(0.26)
			palette["body_top"] = _wash(fill, accent, 0.04, -0.28)
			palette["body_bottom"] = _wash(fill, accent, 0.06, -0.22)
			palette["inner_top"] = Color(0, 0, 0, 0.24)
			palette["inner_bottom"] = Color(1, 1, 1, 0.10)
			palette["shadow"] = 0.18
		State.PRIMARY:
			# A solid accent slab (gold for the one call to action on a screen):
			# the body is the accent itself, so the rim has to go lighter and
			# warmer to stay visible, the way polished metal catches light.
			palette["rim"] = accent.lightened(0.30)
			palette["rim_light"] = accent.lightened(0.85)
			palette["rim_dark"] = accent.darkened(0.45)
			palette["gloss"] = 0.24
			palette["body_top"] = _opaque(accent).lightened(0.16)
			palette["body_bottom"] = _opaque(accent).darkened(0.10)
			palette["inner_top"] = Color(1, 1, 1, 0.26)
			palette["inner_bottom"] = Color(0.1, 0.06, 0.0, 0.18)
			palette["shadow"] = 0.36
		State.FOCUS:
			# A cream ring with an ink edge and a warm wash: unmistakable on
			# both dark cards and the bright scenery behind them.
			palette["ink"] = Color(1, 0.99, 0.94, 0.98)
			palette["rim"] = FOCUS_LIGHT
			palette["rim_light"] = Color("fffdf4")
			palette["rim_dark"] = FOCUS_WARM
			palette["gloss"] = 0.09
			palette["body_top"] = _with_alpha(_wash(fill, FOCUS_WARM.lerp(Color.WHITE, 0.4),
				0.30, 0.16), 0.42)
			palette["body_bottom"] = _with_alpha(_wash(fill, FOCUS_WARM, 0.24, 0.02), 0.34)
			palette["shadow"] = 0.34
		State.DISABLED:
			# Desaturated rim, no gloss and no shadow: the card is furniture
			# until a save turns up.
			var grey := _desaturate(accent, 0.75)
			palette["ink"] = _with_alpha(INK, 0.55)
			palette["rim"] = _with_alpha(grey, 0.40)
			palette["rim_light"] = _with_alpha(grey, 0.28)
			palette["rim_dark"] = _with_alpha(grey, 0.28)
			palette["body_top"] = _opaque(fill)
			palette["body_bottom"] = _opaque(fill)
			palette["shadow"] = 0.0
	return palette

## The body two-tone: the card's fill, tinted with its accent, then lifted or
## sunk by `tone` towards white (positive) or ink (negative).
static func _wash(fill: Color, accent: Color, tint: float, tone: float) -> Color:
	var mixed := _opaque(fill).lerp(_opaque(accent), clampf(tint, 0.0, 1.0))
	if tone >= 0.0:
		return mixed.lerp(Color(1, 1, 1, mixed.a), tone)
	return mixed.lerp(Color(INK.r, INK.g, INK.b, mixed.a), -tone)

## Pull a colour towards its own luminance: the disabled rim's grey.
static func _desaturate(color: Color, amount: float) -> Color:
	var lum := color.get_luminance()
	return color.lerp(Color(lum, lum, lum, color.a), clampf(amount, 0.0, 1.0))

## Composite `top` over `bottom`, both premultiplied by their own alpha.
static func _over(top: Color, bottom: Color) -> Color:
	var alpha := top.a + bottom.a * (1.0 - top.a)
	if alpha <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Color(top.r, top.g, top.b) * top.a
		+ Color(bottom.r, bottom.g, bottom.b) * bottom.a * (1.0 - top.a)) / alpha
	return Color(rgb.r, rgb.g, rgb.b, alpha)

static func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)

static func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)

static func _cache_key(accent: Color, state: int, fill: Color) -> String:
	return "%s|%d|%s" % [accent.to_html(), state, fill.to_html()]
