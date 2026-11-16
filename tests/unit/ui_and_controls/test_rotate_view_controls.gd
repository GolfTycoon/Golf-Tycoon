extends GameTest
## The view controls: the two Rotate arrows at the top-left corner, on the right
## of the location banner's details card, and the facing chip in that card's
## top-right corner that shows the direction and folds the arrows away.
##
## The arrows are mirrored bitmaps rather than font glyphs, and the chip's
## arrow is a drawn 9x9 grid for the same reason (see RotateViewButton): the UI
## font carries no arrow glyphs at all.

func before_each() -> void:
	super()
	# A desktop window, so the banner starts in its wide layout.
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)

func after_each() -> void:
	get_window().size = Vector2i(1600, 1000)
	await process_frames(1)
	super()

## A banner in the tree, freed after the test.
func _make_banner() -> CourseLocationBanner:
	WorldMap.active_location_id = "monterey"
	var banner: CourseLocationBanner = autofree(CourseLocationBanner.new())
	add_child(banner)
	return banner

func _arrow_names(banner: CourseLocationBanner) -> Array[String]:
	var names: Array[String] = []
	for child in banner.rotate_controls.get_children():
		names.append(String(child.name))
	return names

func test_font_has_no_glyph_for_the_old_rotate_arrows() -> void:
	# U+27F2 / U+27F3 — the arrows the buttons used to be labelled with.
	assert_false(ThemeDB.fallback_font.has_char(0x27F2),
		"The ⟲ glyph is missing from the font, so the button must draw its arrow")
	assert_false(ThemeDB.fallback_font.has_char(0x27F3),
		"The ⟳ glyph is missing from the font, so the button must draw its arrow")

func test_pixel_arrows_are_mirrored_and_keep_their_direction() -> void:
	var ccw: Array = PixelCircleButton.ICONS["rotate_ccw"]
	var cw: Array = PixelCircleButton.ICONS["rotate_cw"]
	assert_eq(ccw.size(), cw.size())
	for row in ccw.size():
		assert_eq(ccw[row].reverse(), cw[row], "Each arrow mirrors the other")
	var button := RotateViewButton.new()
	add_child_autofree(button)
	assert_eq(button.glyph, "rotate_ccw")
	button.clockwise = true
	assert_eq(button.glyph, "rotate_cw")

func test_buttons_are_drawn_not_typed() -> void:
	var ccw_button := RotateViewButton.new()
	add_child_autofree(ccw_button)
	assert_eq(ccw_button.text, "", "The sweep is the label: no glyph is typed on the face")
	assert_false(ccw_button.clockwise, "The Q button sweeps counter-clockwise")
	# The drawn arrow keeps the footprint the text buttons had.
	assert_eq(ccw_button.custom_minimum_size, Vector2(32, 32))

	var cw_button := RotateViewButton.new()
	cw_button.clockwise = true
	add_child_autofree(cw_button)
	assert_true(cw_button.clockwise, "The E button sweeps clockwise")
	assert_eq(cw_button.text, "")

# ---------------------------------------------------------------------------
# The 24-point direction compass
# ---------------------------------------------------------------------------

func test_the_compass_rose_has_24_unique_heading_vectors() -> void:
	assert_eq(OrientationToggleButton.letter_for(0), "N", "N is the first cardinal")
	assert_eq(OrientationToggleButton.letter_for(1), "E")
	assert_eq(OrientationToggleButton.letter_for(2), "S")
	assert_eq(OrientationToggleButton.letter_for(3), "W")
	assert_eq(OrientationToggleButton.DIRECTION_COUNT, 24)

	var vectors: Array[Vector2] = []
	for step in OrientationToggleButton.DIRECTION_COUNT:
		var direction := OrientationToggleButton.direction_vector_for_step(step)
		assert_almost_eq(direction.length(), 1.0, 0.001,
			"Every compass needle direction has unit length")
		for previous in vectors:
			assert_gt(direction.distance_to(previous), 0.25,
				"Every 15-degree heading points somewhere distinct")
		vectors.append(direction)
	assert_eq(vectors.size(), 24)
	assert_eq(OrientationToggleButton.direction_description_for_step(0), "North")
	assert_eq(OrientationToggleButton.direction_description_for_step(1), "North 15 degrees east")
	assert_eq(OrientationToggleButton.direction_description_for_step(23), "North 15 degrees west")
	assert_eq(OrientationToggleButton.direction_description_for_step(24), "North",
		"The spoken bearing wraps")

	var north := OrientationToggleButton.direction_vector_for_step(0)
	var east := OrientationToggleButton.direction_vector_for_step(6)
	var south := OrientationToggleButton.direction_vector_for_step(12)
	var west := OrientationToggleButton.direction_vector_for_step(18)
	assert_almost_eq(north.x, 0.0, 0.001)
	assert_almost_eq(north.y, -1.0, 0.001, "Step 01 points north")
	assert_almost_eq(east.x, 1.0, 0.001, "Step 07 points east")
	assert_almost_eq(east.y, 0.0, 0.001)
	assert_almost_eq(south.y, 1.0, 0.001, "Step 13 points south")
	assert_almost_eq(west.x, -1.0, 0.001, "Step 19 points west")

func test_the_compass_follows_15_degree_steps_and_wraps() -> void:
	var chip := OrientationToggleButton.new()
	add_child_autofree(chip)
	assert_eq(chip.orientation, 0, "A fresh compass faces north")
	assert_eq(chip.letter, "N")
	assert_eq(chip.direction_step, 0)

	chip.direction_step = 1
	assert_eq(OrientationToggleButton.direction_description_for_step(chip.direction_step),
		"North 15 degrees east")
	chip.orientation = 3
	assert_eq(chip.direction_step, 18, "A legacy west assignment selects the west heading")
	assert_eq(chip.letter, "W")
	chip.orientation = 4
	assert_eq(chip.orientation, 0, "Four quarter turns come back to north")
	chip.direction_step = -1
	assert_eq(chip.direction_step, 23, "Counter-clockwise past north wraps to the final heading")
	assert_eq(OrientationToggleButton.letter_for(-1), "W",
		"The cardinal compatibility helper wraps too")

func test_the_compass_is_borderless_and_keeps_its_appearance_when_folded_or_disabled() -> void:
	var chip := OrientationToggleButton.new()
	add_child_autofree(chip)
	var states := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
	for state in states:
		assert_true(chip.get_theme_stylebox(state) is StyleBoxEmpty,
			"The %s state has no frame or fill" % state)
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		assert_eq(chip.get_theme_color(state), Color.TRANSPARENT,
			"The %s font state cannot dim or restyle the custom compass" % state)

	assert_true(chip.controls_shown, "The Rotate arrows start out beside the card")
	chip.controls_shown = false
	assert_false(chip.controls_shown, "The arrows can fold away")
	chip.disabled = true
	assert_eq(chip.direction_step, 0, "Disabled state keeps the same compass heading")
	chip.disabled = false
	chip.controls_shown = true

	# The button itself stays real and focusable: it is the way to bring the
	# Rotate arrows back, without a frame around its larger compass face.
	assert_eq(chip.focus_mode, Control.FOCUS_ALL)
	assert_eq(chip.text, "", "Its face is drawn, not typed")
	assert_eq(chip.custom_minimum_size, Vector2(42, 42))
	assert_eq(OrientationToggleButton.SIZE_TOUCH, Vector2(48, 48))
	assert_gt(OrientationToggleButton.DIAL_RADIUS, 10.0,
		"The rose is substantially larger than the original 20-pixel dial")

# ---------------------------------------------------------------------------
# The banner's corner
# ---------------------------------------------------------------------------

func test_the_arrows_stand_to_the_right_of_the_details_card() -> void:
	var banner := _make_banner()
	var columns: Node = banner.get_node("Columns")
	assert_eq(banner.rotate_controls.get_parent(), columns,
		"The arrows share the row with the two columns")
	assert_eq(columns.get_child(columns.get_child_count() - 1), banner.rotate_controls,
		"and sit after both of them, on their right")
	assert_eq(_arrow_names(banner), ["RotateCCWBtn", "RotateCWBtn"],
		"The two sweep arrows stand side by side")
	assert_eq(banner.rotate_ccw_btn.glyph, "rotate_ccw")
	assert_eq(banner.rotate_cw_btn.glyph, "rotate_cw")
	assert_false(banner.rotate_ccw_btn.clockwise, "Only the right-hand arrow sweeps clockwise")
	assert_true(banner.rotate_cw_btn.clockwise)
	for button in [banner.rotate_ccw_btn, banner.rotate_cw_btn]:
		assert_string_contains(button.tooltip_text, "Rotate course",
			"Each arrow says what it does")

func test_the_chip_rides_in_the_top_right_corner_of_the_details_card() -> void:
	var banner := _make_banner()
	var details: Node = banner.get_node("Columns/DetailsPanel")
	assert_eq(banner.orientation_toggle.get_parent(), details.get_node("Details"),
		"The chip belongs to the details card")
	var card_children: Array = details.get_node("Details").get_children()
	assert_eq(card_children[card_children.size() - 1], banner.orientation_toggle,
		"It is the right-hand end of the card's row")
	assert_eq(banner.orientation_toggle.size_flags_vertical, Control.SIZE_SHRINK_BEGIN,
		"and rides the card's top edge rather than its middle")

func test_the_chip_folds_the_arrows_away_and_brings_them_back() -> void:
	var banner := _make_banner()
	var wide := banner.size.x
	assert_true(banner.rotate_controls_visible(), "The arrows start out")
	assert_true(banner.rotate_ccw_btn.is_visible_in_tree())

	banner.toggle_rotate_controls()
	await process_frames(1)
	assert_false(banner.rotate_controls_visible(), "A press folds them away")
	assert_false(banner.rotate_ccw_btn.is_visible_in_tree())
	assert_false(banner.rotate_cw_btn.is_visible_in_tree())
	assert_true(banner.orientation_toggle.is_visible_in_tree(),
		"The chip stays put: it is the way back to them")
	assert_true(banner.orientation_toggle.controls_shown == false,
		"and reads as switched off")
	assert_true(banner.size.x < wide, "The corner narrows back into their room")

	banner.toggle_rotate_controls()
	await process_frames(1)
	assert_true(banner.rotate_controls_visible(), "A second press brings them back")
	assert_true(banner.rotate_ccw_btn.is_visible_in_tree())
	assert_almost_eq(banner.size.x, wide, 0.5, "and the corner takes their room again")

func test_the_chip_names_the_facing_in_its_tooltip() -> void:
	var banner := _make_banner()
	banner.set_orientation(1)
	assert_eq(banner.orientation_toggle.letter, "E", "The chip follows the course")
	assert_string_contains(banner.orientation_toggle.tooltip_text, "E",
		"The tooltip names the facing")
	assert_string_contains(banner.orientation_toggle.tooltip_text, "hide",
		"and offers to fold the arrows away")
	banner.toggle_rotate_controls()
	assert_string_contains(banner.orientation_toggle.tooltip_text, "show",
		"and to bring them back once they are gone")
