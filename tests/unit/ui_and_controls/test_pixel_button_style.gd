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


func test_the_focus_ring_is_only_a_ring() -> void:
	var img := _frame(PixelButtonStyle.State.FOCUS)
	assert_eq(_px(img, HALF, HALF).a, 0.0, "the middle is air")
	assert_eq(_px(img, HALF, PixelButtonStyle.RING_SHEEN).a, 0.0, "no frame bands")
	assert_gt(_px(img, HALF, 1).a, 0.5, "the ring draws in the trim band")
	assert_eq(_px(img, 0, 0).a, 0.0, "and follows the notch")


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
	assert_eq(focus.get_expand_margin(SIDE_LEFT), 3.0,
		"the ring floats clear of the frame")


func test_panel_style_is_a_frame_without_button_states() -> void:
	var box := PixelButtonStyle.panel_style(UIConstants.COLOR_BORDER, MenuStyle.RAIL_BG, 18, 20)
	assert_eq(box.texture_margin_top, float(M), "the rail wears the same frame")
	assert_eq(box.content_margin_left, 18.0, "with its own padding")
	assert_eq(box.content_margin_top, 20.0, "top and bottom")
