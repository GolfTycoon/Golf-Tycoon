extends GameTest
## PixelButtonStyle: the title screen's frames are nine-patch sprite windows,
## so the pixels themselves are the contract - notched corners, an ink
## outline, an accent trim, a bevel lit from above and a flat stretchable
## middle. These tests read the generated images pixel by pixel (the whole
## recipe is pure Image work, so it runs headless), and check the StyleBoxes
## the menu actually puts on its buttons.

const M := PixelButtonStyle.MARGIN
const T := PixelButtonStyle.TEXTURE_SIZE
const GOLD := UIConstants.COLOR_GOLD
## Middle row/column of the frame texture (TEXTURE_SIZE is even).
const HALF := PixelButtonStyle.TEXTURE_SIZE >> 1


func _px(image: Image, x: int, y: int) -> Color:
	return image.get_pixel(x, y)


func _frame(state: int, accent: Color = GOLD,
		fill: Color = MenuStyle.CARD_BG) -> Image:
	return PixelButtonStyle.frame_image(accent, state, fill)


# ---------------------------------------------------------------------------
# GEOMETRY
# ---------------------------------------------------------------------------

func test_the_corners_are_notched_not_rounded() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	# The octagonal cut: the corner triangle is air, and the diagonal that
	# closes it is the frame's ink.
	for i in range(PixelButtonStyle.CORNER_CUT):
		assert_eq(_px(img, i, PixelButtonStyle.CORNER_CUT - 1 - i).a, 0.0,
			"corner cut pixel %d is air" % i)
	assert_gt(_px(img, 1, PixelButtonStyle.CORNER_CUT).a, 0.5,
		"the diagonal closing the notch is drawn")
	# A rounded StyleBox would fade the corner; a notch leaves the edge
	# pixels of the next rows fully drawn.
	assert_gt(_px(img, 0, M).a, 0.5, "the left edge draws below the notch")


func test_the_frame_bands_run_ink_trim_bevel_sheen_fill() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var mid := HALF
	# Top edge cross-section, outside in.
	assert_lt(_px(img, mid, 0).get_luminance(), 0.1, "outermost band is ink")
	var trim := _px(img, mid, 1)
	assert_gt(trim.a, 0.5, "the trim draws")
	assert_gt(abs(trim.r - trim.g), 0.05, "the trim carries the accent hue")
	var bevel := _px(img, mid, PixelButtonStyle.RING_BEVEL)
	assert_gt(bevel.get_luminance(), trim.get_luminance(),
		"the top bevel catches the light")
	var sheen := _px(img, mid, PixelButtonStyle.RING_SHEEN)
	var fill := _px(img, mid, HALF)
	assert_gt(sheen.get_luminance(), fill.get_luminance(),
		"a hard sheen step sits between bevel and fill")
	assert_gt(_px(img, mid, PixelButtonStyle.RING_SHEEN_MID).get_luminance(), fill.get_luminance(),
		"the sheen falls in steps, not a gradient")


func test_the_bevel_is_lit_from_the_top_left() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var mid := HALF
	var top := _px(img, mid, PixelButtonStyle.RING_BEVEL)
	var left := _px(img, PixelButtonStyle.RING_BEVEL, mid)
	var bottom := _px(img, T - 1 - PixelButtonStyle.RING_BEVEL, mid)
	var right := _px(img, mid, T - 1 - PixelButtonStyle.RING_BEVEL)
	assert_gt(top.get_luminance(), bottom.get_luminance(), "top lit, bottom shaded")
	assert_gt(left.get_luminance(), right.get_luminance(), "left lit, right shaded")


func test_the_nine_patch_middle_is_flat_so_stretching_cannot_smear_it() -> void:
	var img := _frame(PixelButtonStyle.State.NORMAL)
	var first := _px(img, M, M)
	for y in range(M, T - M):
		for x in range(M, T - M):
			assert_eq(_px(img, x, y), first,
				"middle pixel (%d,%d) matches: the stretched band is uniform" % [x, y])


func test_pressed_flips_the_bevel_and_hover_lights_the_trim() -> void:
	var normal := _frame(PixelButtonStyle.State.NORMAL)
	var pressed := _frame(PixelButtonStyle.State.PRESSED)
	var hover := _frame(PixelButtonStyle.State.HOVER)
	var mid := HALF
	var top := T - 1 - PixelButtonStyle.RING_BEVEL
	assert_gt(_px(normal, mid, PixelButtonStyle.RING_BEVEL).get_luminance(),
		_px(normal, mid, top).get_luminance(), "normal is lit above")
	assert_lt(_px(pressed, mid, PixelButtonStyle.RING_BEVEL).get_luminance(),
		_px(pressed, mid, top).get_luminance(), "pressed is lit below: sunken")
	assert_gt(_px(hover, mid, 1).get_luminance(), _px(normal, mid, 1).get_luminance(),
		"hover brightens the trim")


func test_disabled_drops_the_accent_and_the_sheen() -> void:
	var normal := _frame(PixelButtonStyle.State.NORMAL, GOLD)
	var disabled := _frame(PixelButtonStyle.State.DISABLED, GOLD)
	var mid := HALF
	var trim := _px(disabled, mid, 1)
	var live := _px(normal, mid, 1)
	assert_lt(trim.s, live.s * 0.5,
		"the disabled trim is greyed out")
	assert_lt(trim.a, live.a, "and faded")
	assert_eq(_px(disabled, mid, PixelButtonStyle.RING_SHEEN), _px(disabled, mid, M),
		"no sheen on a disabled card")


func test_focus_has_a_high_contrast_ring_and_a_translucent_wash() -> void:
	var img := _frame(PixelButtonStyle.State.FOCUS)
	assert_eq(_px(img, 0, 0).a, 0.0, "the outline follows the notch")
	assert_gt(_px(img, HALF, 0).a, 0.99, "a solid ink edge separates focus from the background")
	assert_lt(_px(img, HALF, 0).get_luminance(), 0.1, "the outer edge is dark")
	for band in [PixelButtonStyle.RING_TRIM, PixelButtonStyle.RING_TRIM_INNER]:
		var light := _px(img, HALF, band)
		assert_gt(light.a, 0.99, "focus band %d is solid" % band)
		assert_gt(light.get_luminance(), 0.85, "focus band %d is bright" % band)
	assert_gt(_px(img, HALF, PixelButtonStyle.RING_BEVEL).a, 0.99,
		"a third warm band makes focus heavier than the normal trim")
	for point in [Vector2i(HALF, HALF), Vector2i(HALF, PixelButtonStyle.RING_SHEEN)]:
		assert_almost_eq(_px(img, point.x, point.y).a, PixelButtonStyle.FOCUS_WASH.a, 0.005,
			"the surface is lightly washed, not hidden by an opaque focus fill")


func test_focus_is_brighter_than_hover_for_every_menu_accent() -> void:
	for accent in [MenuStyle.ACCENT_PRIMARY, MenuStyle.ACCENT_SECONDARY,
			MenuStyle.ACCENT_UTILITY, MenuStyle.ACCENT_QUIT]:
		var focus := _frame(PixelButtonStyle.State.FOCUS, accent)
		var hover := _frame(PixelButtonStyle.State.HOVER, accent)
		assert_gt(_px(focus, HALF, 1).get_luminance(), _px(hover, HALF, 1).get_luminance(),
			"focus is unmistakable even against a hovered %s card" % accent)
		assert_almost_eq(_px(focus, HALF, HALF).a, PixelButtonStyle.FOCUS_WASH.a, 0.005,
			"the wash is equally visible for every accent")


func test_frames_are_cached_per_palette() -> void:
	var a := _frame(PixelButtonStyle.State.NORMAL)
	var b := _frame(PixelButtonStyle.State.NORMAL)
	assert_true(a == b, "the same palette reuses one image")
	var other := _frame(PixelButtonStyle.State.NORMAL, MenuStyle.ACCENT_SECONDARY)
	assert_true(a != other, "a different accent gets its own frame")


# ---------------------------------------------------------------------------
# STYLEBOXES
# ---------------------------------------------------------------------------

func test_paint_card_puts_a_pixel_frame_on_every_state() -> void:
	var button := Button.new()
	add_child_autofree(button)
	PixelButtonStyle.paint_card(button, GOLD, 28.0, 20, UIConstants.COLOR_TEXT, Color.WHITE)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := button.get_theme_stylebox(state) as StyleBoxTexture
		assert_not_null(box, "%s carries a nine-patch frame" % state)
		if box:
			assert_eq(box.texture_margin_left, float(M), "%s margins map 1:1" % state)
			assert_eq(box.content_margin_left, 20.0, "%s keeps the card's padding" % state)
			assert_eq(box.content_margin_bottom, 20.0 + 28.0,
				"%s leaves room for the caption" % state)
	var focus := button.get_theme_stylebox("focus") as StyleBoxTexture
	assert_not_null(focus, "focus has its own ring")
	assert_eq(focus.get_expand_margin(SIDE_LEFT), PixelButtonStyle.FOCUS_EXPAND,
		"the ring extends beyond the frame")
	assert_true(focus.draw_center, "the surface wash is drawn inside the ring")
	assert_eq(focus.content_margin_left, 20.0, "focus does not shift the title")
	assert_eq(focus.content_margin_bottom, 48.0, "focus preserves the caption room")


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


func test_panel_style_is_a_frame_without_button_states() -> void:
	var box := PixelButtonStyle.panel_style(UIConstants.COLOR_BORDER, MenuStyle.RAIL_BG, 18, 20)
	assert_eq(box.texture_margin_top, float(M), "the rail wears the same frame")
	assert_eq(box.content_margin_left, 18.0, "with its own padding")
	assert_eq(box.content_margin_top, 20.0, "top and bottom")


func test_choice_cards_keep_pixel_frames_for_every_selection_state() -> void:
	var button := Button.new()
	add_child_autofree(button)
	PixelButtonStyle.paint_choice(button, GOLD)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := button.get_theme_stylebox(state) as StyleBoxTexture
		assert_not_null(box, "%s has a pixel frame" % state)
		if box:
			assert_eq(box.texture_margin_left, float(M), "%s edges stay 1:1" % state)
	var normal := button.get_theme_stylebox("normal") as StyleBoxTexture
	var selected := button.get_theme_stylebox("pressed") as StyleBoxTexture
	assert_ne(normal.texture, selected.texture, "the selected card switches to its lit accent palette")
	var focus := button.get_theme_stylebox("focus") as StyleBoxTexture
	assert_not_null(focus, "choice cards keep the visible focus overlay")
	if focus:
		assert_ne(focus.texture, normal.texture, "focused is not the unpicked state")
		assert_ne(focus.texture, selected.texture, "focused is not the picked state")


func test_primary_buttons_and_fields_share_the_focus_overlay() -> void:
	var primary := Button.new()
	var field := LineEdit.new()
	add_child_autofree(primary)
	add_child_autofree(field)
	PixelButtonStyle.paint_primary(primary, GOLD)
	PixelButtonStyle.paint_field(field, GOLD, MenuStyle.INSET_BG, 9)
	var primary_focus := primary.get_theme_stylebox("focus") as StyleBoxTexture
	var field_focus := field.get_theme_stylebox("focus") as StyleBoxTexture
	assert_not_null(primary_focus)
	assert_not_null(field_focus)
	if primary_focus and field_focus:
		assert_eq(primary_focus.texture, field_focus.texture, "both use the shared overlay")
		assert_eq(field_focus.content_margin_left, 9.0, "the field keeps its own padding")
		assert_eq(field_focus.get_expand_margin(SIDE_LEFT), PixelButtonStyle.FOCUS_EXPAND)


func test_inset_reverses_the_bevel_for_a_recessed_pixel_surface() -> void:
	var img := PixelButtonStyle.frame_image(GOLD, PixelButtonStyle.State.INSET, MenuStyle.INSET_BG)
	var mid := HALF
	var top := _px(img, mid, PixelButtonStyle.RING_BEVEL)
	var bottom := _px(img, mid, T - 1 - PixelButtonStyle.RING_BEVEL)
	var left := _px(img, PixelButtonStyle.RING_BEVEL, mid)
	var right := _px(img, T - 1 - PixelButtonStyle.RING_BEVEL, mid)
	assert_lt(top.get_luminance(), bottom.get_luminance(), "the inset is shaded above and lit below")
	assert_lt(left.get_luminance(), right.get_luminance(), "the inset is shaded left and lit right")
	assert_eq(_px(img, mid, PixelButtonStyle.RING_SHEEN), _px(img, mid, M), "recesses do not carry a top-edge sheen")


func test_content_margins_are_copied_per_pixel_frame() -> void:
	var narrow := PixelButtonStyle.card_style(GOLD, PixelButtonStyle.State.NORMAL,
		MenuStyle.CARD_BG, 12, 10, 14)
	var wide := PixelButtonStyle.card_style(GOLD, PixelButtonStyle.State.NORMAL,
		MenuStyle.CARD_BG, 24, 20, 28)
	assert_eq(narrow.texture, wide.texture, "both cards reuse the same cached sprite frame")
	assert_eq(narrow.content_margin_left, 12.0, "the first keeps its own left pad")
	assert_eq(wide.content_margin_left, 24.0, "the second keeps its own left pad")
	assert_eq(narrow.content_margin_bottom, 14.0, "the first keeps its caption room")
	assert_eq(wide.content_margin_bottom, 28.0, "the second keeps its caption room")


func test_footer_bar_is_a_pixel_frame_cross_section() -> void:
	var image := PixelButtonStyle.bar_image(GOLD, MenuStyle.RAIL_BG)
	assert_eq(image.get_width(), PixelButtonStyle.BAR_WIDTH, "the strip has a small repeatable width")
	assert_eq(image.get_height(), M + PixelButtonStyle.BAR_STRETCH, "the cross-section has a flat stretch zone")
	var first := image.get_pixel(0, 0)
	for x in image.get_width():
		assert_eq(image.get_pixel(x, 0), first, "bar pixel column %d repeats exactly" % x)
	var box := PixelButtonStyle.bar_style(GOLD, MenuStyle.RAIL_BG)
	assert_eq(box.texture_margin_top, float(M), "only the top frame bands stay 1:1")
	assert_eq(box.texture_margin_bottom, 0.0, "the interior can stretch to the bar's height")
