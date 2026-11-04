extends GameTest
## PixelButtonStyle: every menu control wears a rounded glass pill, so the
## generated frames are the contract - a pill shape with ink and accent bands
## that run the rounded edge, a glassy gloss under the top rim, an asymmetric
## nine-patch so the wide middle stretches without smearing the corners, and a
## palette per state. These tests read the generated images pixel by pixel (the
## whole recipe is pure Image work, so it runs headless), then check the
## StyleBoxes the menu actually puts on its buttons.

const M := PixelButtonStyle.MARGIN_LEFT
const T := PixelButtonStyle.TEXTURE_SIZE
const GOLD := UIConstants.COLOR_GOLD
## Middle row/column of the frame texture.
const MID := PixelButtonStyle.TEXTURE_SIZE >> 1
## Horizontal centre of the pill inside the texture.
const MID_X := PixelButtonStyle.TEXTURE_SIZE >> 1


func _px(image: Image, x: int, y: int) -> Color:
	return image.get_pixel(x, y)


func _frame(state: int, accent: Color = GOLD,
		fill: Color = MenuStyle.CARD_BG) -> Image:
	return PixelButtonStyle.frame_image(accent, state, fill)


## Local Y of the top rim band inside the texture, and of the bottom rim.
func _rim_rows() -> Array:
	return [PixelButtonStyle.BLEED + int(PixelButtonStyle.INK_WIDTH) + 2,
		T - PixelButtonStyle.BLEED - int(PixelButtonStyle.INK_WIDTH) - 3]


# ---------------------------------------------------------------------------
# GEOMETRY
# ---------------------------------------------------------------------------

func test_the_corners_are_rounded_not_cut_off() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var bleed := PixelButtonStyle.BLEED
	# The very corner of the shape is outside the pill: nothing is drawn in the
	# texture's corner, and the curve has begun a few pixels in.
	assert_eq(_px(img, 0, 0).a, 0.0, "the texture's corner is outside the pill")
	assert_lt(_px(img, bleed - 1, bleed - 1).a, 0.2,
		"the pill's corner is rounded away (only the soft shadow reaches it)")
	assert_gt(_px(img, bleed + 6, bleed + 6).a, 0.5,
		"the rounded corner closes a few pixels into the shape")
	# A straight edge between the corners is drawn right at the pill's edge.
	assert_gt(_px(img, MID_X, bleed).a, 0.5, "the top edge between the corners draws")


func test_the_corner_is_a_smooth_quarter_circle() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var bleed := PixelButtonStyle.BLEED
	var radius := PixelButtonStyle.RADIUS
	# Every pixel just inside the radius, measured from the corner's centre,
	# belongs to the pill; every pixel just outside it does not. This is what
	# makes the corner a round arc rather than a diagonal cut.
	var centre := Vector2(bleed + radius, bleed + radius)
	var inside_drawn := 0
	var outside_clear := 0
	for step in 12:
		var angle := PI + PI * 0.5 * (float(step) / 11.0)
		var inside := centre + Vector2(cos(angle), sin(angle)) * (radius - 2.5)
		var outside := centre + Vector2(cos(angle), sin(angle)) * (radius + 1.5)
		if _px(img, int(inside.x), int(inside.y)).a > 0.5:
			inside_drawn += 1
		if _px(img, int(outside.x), int(outside.y)).a < 0.5:
			outside_clear += 1
	assert_gte(inside_drawn, 10, "the arc is drawn all the way round the corner")
	assert_gte(outside_clear, 10, "and nothing spills outside it")


func test_the_frame_bands_run_ink_rim_gloss_body() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var bleed := PixelButtonStyle.BLEED
	# Top edge cross-section, outside in.
	assert_lt(_px(img, MID_X, bleed).get_luminance(), 0.12, "outermost band is ink")
	var rim := _px(img, MID_X, bleed + 1 + int(PixelButtonStyle.INK_WIDTH))
	assert_gt(rim.a, 0.5, "the accent rim draws")
	assert_gt(abs(rim.r - rim.g), 0.05, "the rim carries the accent hue")
	var gloss := _px(img, MID_X, bleed + int(PixelButtonStyle.INK_WIDTH
		+ PixelButtonStyle.RIM_WIDTH) + 2)
	var body := _px(img, MID_X, MID)
	assert_gt(gloss.get_luminance(), body.get_luminance(),
		"a glassy gloss sits between the rim and the body")


func test_the_rim_is_lit_from_the_top_left() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var rim_row := PixelButtonStyle.BLEED + 1 + int(PixelButtonStyle.INK_WIDTH)
	var top := _px(img, MID_X, rim_row)
	var bottom := _px(img, MID_X, T - 1 - rim_row + PixelButtonStyle.BLEED)
	var left := _px(img, rim_row, MID)
	var right := _px(img, T - 1 - rim_row + PixelButtonStyle.BLEED, MID)
	assert_gt(top.get_luminance(), bottom.get_luminance(), "the rim is bright above")
	assert_gt(left.get_luminance(), right.get_luminance(), "and on the left")


func test_the_nine_patch_middle_is_flat_so_stretching_cannot_smear_it() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var left := PixelButtonStyle.MARGIN_LEFT
	var right := T - PixelButtonStyle.MARGIN_RIGHT
	var top := PixelButtonStyle.MARGIN_TOP
	var bottom := T - PixelButtonStyle.MARGIN_BOTTOM
	var first := _px(img, left, top)
	for y in range(top, bottom):
		for x in range(left, right):
			assert_eq(_px(img, x, y), first,
				"middle pixel (%d,%d) matches: the stretched band is uniform" % [x, y])


func test_the_margins_cover_every_band_that_must_not_stretch() -> void:
	# The margins are what the nine-patch draws 1:1. They have to be wide
	# enough to hold the whole corner curve and the gloss band, and to keep the
	# body flat between them.
	assert_gte(PixelButtonStyle.MARGIN_LEFT, int(PixelButtonStyle.RADIUS) + PixelButtonStyle.BLEED,
		"the left margin holds the full corner curve")
	assert_gte(PixelButtonStyle.MARGIN_RIGHT, int(PixelButtonStyle.RADIUS) + PixelButtonStyle.BLEED,
		"the right margin holds it too")
	assert_gte(PixelButtonStyle.MARGIN_TOP, int(PixelButtonStyle.RADIUS) + PixelButtonStyle.BLEED,
		"the top margin holds the curve and the gloss band")
	assert_gte(PixelButtonStyle.MARGIN_BOTTOM, int(PixelButtonStyle.RADIUS) + PixelButtonStyle.BLEED,
		"the bottom margin holds the curve")
	assert_gte(PixelButtonStyle.MARGIN_LEFT + PixelButtonStyle.MARGIN_RIGHT, 40,
		"together the side margins leave the corners their room")
	assert_lt(PixelButtonStyle.MARGIN_LEFT + PixelButtonStyle.MARGIN_RIGHT, T,
		"and still leave a middle to stretch")


func test_an_inset_is_a_pill_without_the_gloss() -> void:
	var img := _frame(PixelButtonStyle.State.INSET, GOLD, MenuStyle.INSET_BG)
	assert_gt(_px(img, MID_X, 0).a, 0.5, "an inset fills its frame's whole width")
	assert_eq(_px(img, 0, 0).a, 0.0, "but still has rounded corners")
	var top_band := _px(img, MID_X, 3)
	var bottom_band := _px(img, MID_X, T - 4)
	assert_lt(top_band.get_luminance(), bottom_band.get_luminance(),
		"the inset is shaded above and lit below: a recess")


func test_pressed_sinks_the_card_and_hover_lifts_it() -> void:
	var normal := _frame(PixelButtonStyle.State.NORMAL)
	var pressed := _frame(PixelButtonStyle.State.PRESSED)
	var hover := _frame(PixelButtonStyle.State.HOVER)
	var rim_row := PixelButtonStyle.BLEED + 1 + int(PixelButtonStyle.INK_WIDTH)
	assert_gt(_px(normal, MID_X, MID).get_luminance(),
		_px(pressed, MID_X, MID).get_luminance(), "pressing darkens the body")
	assert_gt(_px(hover, MID_X, MID).get_luminance(),
		_px(normal, MID_X, MID).get_luminance(), "hover lights the body up")
	assert_gt(_px(hover, MID_X, rim_row).get_luminance(),
		_px(normal, MID_X, rim_row).get_luminance(), "and brightens the rim")


func test_disabled_drops_the_accent_the_gloss_and_the_shadow() -> void:
	var normal := _frame(PixelButtonStyle.State.NORMAL, GOLD)
	var disabled := _frame(PixelButtonStyle.State.DISABLED, GOLD)
	var rim_row := PixelButtonStyle.BLEED + 1 + int(PixelButtonStyle.INK_WIDTH)
	var trim := _px(disabled, MID_X, rim_row)
	var live := _px(normal, MID_X, rim_row)
	assert_lt(trim.s, live.s * 0.6, "the disabled rim is greyed out")
	assert_lt(trim.a, live.a, "and faded")
	assert_eq(_px(disabled, MID_X, 0).a, 0.0,
		"the contact shadow is gone, so the rows above the pill stay empty")


func test_focus_has_a_high_contrast_ring_and_a_translucent_wash() -> void:
	var img := _frame(PixelButtonStyle.State.FOCUS)
	var bleed := PixelButtonStyle.BLEED
	assert_gt(_px(img, MID_X, bleed).a, 0.95, "a solid outline separates focus from the background")
	for band in [1, 2]:
		var light := _px(img, MID_X, bleed + band)
		assert_gt(light.a, 0.95, "focus band %d is solid" % band)
		assert_gt(light.get_luminance(), 0.85, "focus band %d is bright" % band)
	var wash := _px(img, MID_X, MID)
	assert_lt(wash.a, 0.99, "the surface is washed, not hidden by an opaque focus fill")


func test_focus_is_brighter_than_hover_for_every_menu_accent() -> void:
	var rim_row := PixelButtonStyle.BLEED + 1 + int(PixelButtonStyle.INK_WIDTH)
	for accent in [MenuStyle.ACCENT_PRIMARY, MenuStyle.ACCENT_SECONDARY,
			MenuStyle.ACCENT_UTILITY, MenuStyle.ACCENT_QUIT]:
		var focus := _frame(PixelButtonStyle.State.FOCUS, accent)
		var hover := _frame(PixelButtonStyle.State.HOVER, accent)
		assert_gt(_px(focus, MID_X, rim_row).get_luminance(),
			_px(hover, MID_X, rim_row).get_luminance(),
			"focus is unmistakable even against a hovered %s card" % accent)


func test_frames_are_cached_per_palette() -> void:
	var a := _frame(PixelButtonStyle.State.NORMAL)
	var b := _frame(PixelButtonStyle.State.NORMAL)
	assert_true(a == b, "the same palette reuses one image")
	var other := _frame(PixelButtonStyle.State.NORMAL, MenuStyle.ACCENT_SECONDARY)
	assert_true(a != other, "a different accent gets its own frame")


# ---------------------------------------------------------------------------
# STYLEBOXES
# ---------------------------------------------------------------------------

func test_paint_card_puts_a_glass_frame_on_every_state() -> void:
	var button := Button.new()
	add_child_autofree(button)
	PixelButtonStyle.paint_card(button, GOLD, 28.0, 20, UIConstants.COLOR_TEXT, Color.WHITE)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := button.get_theme_stylebox(state) as StyleBoxTexture
		assert_not_null(box, "%s carries a nine-patch frame" % state)
		if box:
			assert_eq(box.texture_margin_left, float(PixelButtonStyle.MARGIN_LEFT),
				"%s margins map 1:1" % state)
			assert_eq(box.content_margin_left, 20.0, "%s keeps the card's padding" % state)
			assert_eq(box.content_margin_bottom, 20.0 + 28.0,
				"%s leaves room for the caption" % state)


func test_the_focus_ring_is_drawn_around_the_pill_by_its_own_layer() -> void:
	var button := Button.new()
	add_child_autofree(button)
	PixelButtonStyle.paint_card(button, GOLD, 0.0, 20, UIConstants.COLOR_TEXT, Color.WHITE)
	var ring := button.get_node_or_null("FocusRing") as MenuFocusRing
	assert_not_null(ring, "the card gets a focus ring layer")
	if ring == null:
		return
	assert_true(ring is Node2D,
		"the ring is a Node2D: it adds nothing to the card's size and cannot take a click")
	assert_not_null(ring.ring_style, "the ring carries the shared focus stylebox")
	assert_eq(ring.ring_style.get_expand_margin(SIDE_LEFT), PixelButtonStyle.FOCUS_EXPAND,
		"the ring reaches past the pill's edge")
	assert_false(ring.ring_style.draw_center,
		"the ring draws bands only, so it never covers the card's own text")
	# The ring's box sits exactly on the pill's ink outline.
	var box := ring.ring_box()
	var reach := float(PixelButtonStyle.FOCUS_EXPAND)
	var pad := float(MenuFocusRing.RING_REACH + MenuFocusRing.TEXTURE_PADDING)
	assert_eq(box.position, Vector2(pad - reach, pad - reach),
		"the ring's box starts inside the layer that draws it")
	assert_eq(box.size, ring.owner_button.size + Vector2(reach, reach) * 2.0,
		"and wraps the whole pill")
	assert_eq(ring.position, Vector2(-pad, -pad),
		"the layer itself sits off the card's top-left corner")
	assert_true(ring.position + box.position == Vector2(-reach, -reach),
		"so the ring's outer edge lands exactly one reach outside the card")
	# The wash stays on the button itself, under the label, and keeps the
	# card's padding so focus never moves the title.
	var wash := button.get_theme_stylebox("focus")
	assert_not_null(wash, "the focus state carries the warm wash")
	if wash:
		assert_gt(wash.bg_color.a, 0.0, "the wash is drawn")
		assert_lt(wash.bg_color.a, 0.4, "and stays translucent over the card")
		assert_eq(wash.content_margin_left, 20.0, "focus preserves the card's padding")


func test_every_painted_button_gets_exactly_one_focus_ring() -> void:
	var card := Button.new()
	var choice := Button.new()
	var primary := Button.new()
	var field := LineEdit.new()
	add_child_autofree(card)
	add_child_autofree(choice)
	add_child_autofree(primary)
	add_child_autofree(field)
	PixelButtonStyle.paint_card(card, GOLD, 0.0, 10, UIConstants.COLOR_TEXT, Color.WHITE)
	PixelButtonStyle.paint_choice(choice, GOLD)
	PixelButtonStyle.paint_primary(primary, GOLD)
	PixelButtonStyle.paint_field(field, GOLD, MenuStyle.INSET_BG, 9)
	for control in [card, choice, primary, field]:
		var rings: Array = []
		for child in control.get_children():
			if child is MenuFocusRing:
				rings.append(child)
		assert_eq(rings.size(), 1, "%s wears one focus ring" % control.name)
	# Repainting must not stack a second ring on top of the first.
	PixelButtonStyle.paint_card(card, GOLD, 0.0, 10, UIConstants.COLOR_TEXT, Color.WHITE)
	var again := 0
	for child in card.get_children():
		if child is MenuFocusRing:
			again += 1
	assert_eq(again, 1, "repainting a card reuses its ring")


func test_the_ring_is_hidden_until_its_button_has_focus() -> void:
	var button := Button.new()
	add_child_autofree(button)
	var ring := MenuFocusRing.attach(button, PixelButtonStyle.focus_ring(GOLD))
	assert_not_null(ring, "a ring can be attached directly")
	if ring == null:
		return
	assert_false(ring.visible, "an unfocused card draws no ring")
	button.grab_focus()
	assert_true(button.has_focus(), "the button took focus")
	await process_frames(1)
	assert_true(ring.visible, "the focused card draws its ring")


func test_the_fallback_button_theme_has_a_matching_focus_treatment() -> void:
	var theme := load("res://assets/themes/game_theme.tres") as Theme
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_not_null(focus, "ordinary buttons such as the pause menu get a focus style")
	if focus == null:
		return
	assert_gte(focus.border_width_left, 3, "the focus outline is thicker than the normal border")
	assert_gt(focus.border_color.get_luminance(), 0.85, "the outline is light")
	assert_gt(focus.bg_color.a, 0.0, "the surface is tinted")
	assert_lt(focus.bg_color.a, 0.2, "the normal/pressed appearance remains visible beneath it")
	assert_gt(focus.get_expand_margin(SIDE_LEFT), 0.0, "focus extends beyond the button")
	assert_gte(focus.corner_radius_top_left, 12, "the ordinary buttons are pills too")


func test_panel_style_is_a_frame_without_button_states() -> void:
	var box := PixelButtonStyle.panel_style(UIConstants.COLOR_BORDER, MenuStyle.RAIL_BG, 18, 20)
	assert_eq(box.texture_margin_top, float(PixelButtonStyle.MARGIN_TOP),
		"the rail wears the same frame")
	assert_eq(box.content_margin_left, 18.0, "with its own padding")
	assert_eq(box.content_margin_top, 20.0, "top and bottom")


func test_choice_cards_keep_glass_frames_for_every_selection_state() -> void:
	var button := Button.new()
	add_child_autofree(button)
	PixelButtonStyle.paint_choice(button, GOLD)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := button.get_theme_stylebox(state) as StyleBoxTexture
		assert_not_null(box, "%s has a glass frame" % state)
		if box:
			assert_eq(box.texture_margin_left, float(PixelButtonStyle.MARGIN_LEFT),
				"%s edges stay 1:1" % state)
	var normal := button.get_theme_stylebox("normal") as StyleBoxTexture
	var selected := button.get_theme_stylebox("pressed") as StyleBoxTexture
	assert_ne(normal.texture, selected.texture, "the selected card switches to its lit accent palette")
	assert_not_null(button.get_theme_stylebox("focus"), "choice cards keep the focus wash")
	assert_not_null(button.get_node_or_null("FocusRing"), "and the focus ring around them")


func test_primary_buttons_and_fields_share_the_focus_ring() -> void:

	var primary := Button.new()
	var field := LineEdit.new()
	add_child_autofree(primary)
	add_child_autofree(field)
	PixelButtonStyle.paint_primary(primary, GOLD)
	PixelButtonStyle.paint_field(field, GOLD, MenuStyle.INSET_BG, 9)
	var primary_ring := primary.get_node_or_null("FocusRing") as MenuFocusRing
	var field_ring := field.get_node_or_null("FocusRing") as MenuFocusRing
	assert_not_null(primary_ring)
	assert_not_null(field_ring)
	if primary_ring and field_ring:
		assert_eq(primary_ring.ring_style.texture, field_ring.ring_style.texture,
			"both use the shared ring texture")
	var field_wash := field.get_theme_stylebox("focus")
	assert_not_null(field_wash, "the field carries the focus wash")
	if field_wash:
		assert_eq(field_wash.content_margin_left, 9.0, "the field keeps its own padding")


func test_content_margins_are_copied_per_glass_frame() -> void:
	var narrow := PixelButtonStyle.card_style(GOLD, PixelButtonStyle.State.NORMAL,
		MenuStyle.CARD_BG, 12, 10, 14)
	var wide := PixelButtonStyle.card_style(GOLD, PixelButtonStyle.State.NORMAL,
		MenuStyle.CARD_BG, 24, 20, 28)
	assert_eq(narrow.texture, wide.texture, "both cards reuse the same cached sprite frame")
	assert_eq(narrow.content_margin_left, 12.0, "the first keeps its own left pad")
	assert_eq(wide.content_margin_left, 24.0, "the second keeps its own left pad")
	assert_eq(narrow.content_margin_bottom, 14.0, "the first keeps its caption room")
	assert_eq(wide.content_margin_bottom, 28.0, "the second keeps its caption room")


func test_footer_bar_is_a_glass_frame_cross_section() -> void:
	var image := PixelButtonStyle.bar_image(GOLD, MenuStyle.RAIL_BG)
	assert_eq(image.get_width(), PixelButtonStyle.BAR_WIDTH, "the strip has a small repeatable width")
	assert_eq(image.get_height(), PixelButtonStyle.BAR_BAND + PixelButtonStyle.BAR_STRETCH,
		"the cross-section has a flat stretch zone")
	var first := image.get_pixel(0, 0)
	for x in image.get_width():
		assert_eq(image.get_pixel(x, 0), first, "bar pixel column %d repeats exactly" % x)
	var box := PixelButtonStyle.bar_style(GOLD, MenuStyle.RAIL_BG)
	assert_eq(box.texture_margin_top, float(PixelButtonStyle.BAR_BAND),
		"only the top frame bands stay 1:1")
	assert_eq(box.texture_margin_bottom, 0.0, "the interior can stretch to the bar's height")
