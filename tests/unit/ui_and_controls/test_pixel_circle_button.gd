extends GameTest
## PixelCircleButton's full-width faces. A medallion can stretch into a wide
## touch tab (the portrait thumb rail's section buttons), and a wide tab can
## stack its caption under its icon (the portrait tray's page tabs, four of
## which have to share a 320px phone). These tests pin the stacked face: what
## turns it on, that the icon and the caption both fit it without touching,
## and that a wide tab keeps its caption beside its icon unless it asks to stack.

## The narrowest page tab a phone produces: four tabs sharing a 320px tray.
const NARROWEST_TAB := Vector2(73, 48)
## A wide face is framed by a two-pixel border.
const BORDER := 2.0
## A pressed or selected face draws its icon this much lower.
const PRESS_NUDGE := 2.0

func _tab(caption: String, face: Vector2 = NARROWEST_TAB, glyph: String = "terrain") -> PixelCircleButton:
	var button := PixelCircleButton.new()
	button.glyph = glyph
	button.caption = caption
	button.wide_face = true
	button.stacked_caption = true
	add_child_autofree(button)
	button.diameter = face.y
	button.size = face
	return button

func _text_width(caption: String) -> float:
	return PixelCircleButton.FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x


func test_a_medallion_does_not_stack_unless_asked() -> void:
	var button := PixelCircleButton.new()
	add_child_autofree(button)
	assert_false(button.wide_face, "A medallion is round out of the box")
	assert_false(button.stacked_caption, "and stacks nothing")
	assert_false(button.is_stacked())
	# The portrait thumb rail: wide, captioned, and side by side.
	button.glyph = "build"
	button.caption = "Build"
	button.wide_face = true
	assert_false(button.is_stacked(),
		"A wide tab keeps its caption beside its icon until it asks to stack")


func test_a_face_stacks_only_when_it_is_wide_and_has_an_icon_and_a_caption() -> void:
	var button := _tab("Terrain")
	assert_true(button.is_stacked(), "Wide, asked, with an icon and a caption: stacked")
	button.wide_face = false
	assert_false(button.is_stacked(), "A round medallion never stacks")
	button.wide_face = true
	button.caption = ""
	assert_false(button.is_stacked(), "There is nothing to stack without a caption")
	button.caption = "Terrain"
	button.glyph = "no such icon"
	assert_false(button.is_stacked(), "or without an icon to stack it under")
	button.glyph = "terrain"
	button.stacked_caption = false
	assert_false(button.is_stacked(), "Turning the flag off goes back to side by side")


func test_every_page_tab_caption_fits_the_narrowest_tab() -> void:
	var face := Rect2(Vector2.ZERO, NARROWEST_TAB).grow(-BORDER)
	for tab in TerrainToolbar.PORTRAIT_TAB_CAPTIONS:
		var caption: String = TerrainToolbar.PORTRAIT_TAB_CAPTIONS[tab]
		var button := _tab(caption, NARROWEST_TAB, TerrainToolbar.TAB_ICONS[tab])
		assert_true(button.is_stacked(), "%s stacks" % caption)
		var icon := button.stacked_icon_rect()
		var text := button.stacked_caption_rect()
		assert_true(face.encloses(icon), "%s: the icon %s sits inside the border" % [caption, icon])
		assert_true(face.encloses(text), "%s: the caption %s sits inside the border" % [caption, text])
		assert_almost_eq(text.size.x, _text_width(caption), 0.01,
			"%s is drawn whole, not trimmed" % caption)
		assert_gte(text.position.x, PixelCircleButton.STACK_SIDE_PAD,
			"%s keeps its side pad on the left" % caption)
		assert_lte(text.end.x, NARROWEST_TAB.x - PixelCircleButton.STACK_SIDE_PAD,
			"%s keeps its side pad on the right" % caption)


func test_the_caption_clears_the_icon_even_while_the_tab_is_pressed() -> void:
	var button := _tab("Elevation", NARROWEST_TAB, "elevation")
	var icon := button.stacked_icon_rect()
	var text := button.stacked_caption_rect()
	var shadow_end := icon.end.y + PixelCircleButton.ICON_SHADOW
	assert_gt(text.position.y, shadow_end + PRESS_NUDGE,
		"The capitals start below the shadow of a pressed icon")
	assert_almost_eq(text.position.y - shadow_end, PixelCircleButton.STACK_GAP, 0.01,
		"exactly the stack gap under the resting icon's shadow")
	# The selected tab wears a pressed icon for as long as its page is open,
	# so the nudged icon has to stay inside the face too.
	assert_lte(shadow_end + PRESS_NUDGE, NARROWEST_TAB.y - BORDER)


func test_the_icon_and_the_capitals_are_centred_as_one_block() -> void:
	for face: Vector2 in [NARROWEST_TAB, Vector2(90, 48), Vector2(91, 48), Vector2(122, 48),
			Vector2(172, 48), Vector2(120, 52)]:
		var button := _tab("Buildings", face, "buildings")
		var icon := button.stacked_icon_rect()
		var text := button.stacked_caption_rect()
		assert_almost_eq(icon.get_center().x, face.x * 0.5, 0.5,
			"%s: the icon is centred across the tab" % face)
		assert_almost_eq(text.get_center().x, face.x * 0.5, 1.0,
			"%s: the caption is centred under it" % face)
		assert_almost_eq(icon.position.y, face.y - text.end.y, 1.0,
			"%s: the block leaves the same room above the icon as below the baseline" % face)
		assert_eq(icon.position, icon.position.floor(), "%s: the icon lands on whole pixels" % face)
		assert_eq(text.position, text.position.floor(), "%s: and so does the caption" % face)
		assert_eq(icon.size, Vector2(18, 18), "%s: a 48px tab wears the two-pixel icon" % face)


func test_a_caption_too_wide_for_the_face_is_held_between_the_side_pads() -> void:
	var face := Vector2(60, 48)
	var button := _tab("Improvements and more", face, "improvements")
	var text := button.stacked_caption_rect()
	assert_gt(_text_width(button.caption), face.x, "The caption is wider than the tab")
	assert_almost_eq(text.position.x, PixelCircleButton.STACK_SIDE_PAD, 0.01,
		"A caption that cannot fit starts at the side pad")
	assert_almost_eq(text.end.x, face.x - PixelCircleButton.STACK_SIDE_PAD, 0.01,
		"and is trimmed at the other one instead of running over the border")


func test_the_whole_wide_face_is_a_touch_target() -> void:
	var button := _tab("Club", Vector2(122, 48), "club")
	for point: Vector2 in [Vector2(1, 1), Vector2(121, 1), Vector2(1, 47), Vector2(121, 47),
			Vector2(61, 24)]:
		assert_true(button._has_point(point), "%s is on the tab" % point)
	assert_false(button._has_point(Vector2(-1, 24)), "Outside the tab is not")
	assert_false(button._has_point(Vector2(123, 24)))
	# The same rectangle as a medallion answers only inside its circle.
	button.wide_face = false
	assert_false(button._has_point(Vector2(1, 1)), "A medallion's corners stay out of reach")
	assert_true(button._has_point(Vector2(61, 24)))
