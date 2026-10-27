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
	assert_true(cw_button.clockwise, "The Shift+Q button sweeps clockwise")
	assert_eq(cw_button.text, "")

# ---------------------------------------------------------------------------
# The facing chip
# ---------------------------------------------------------------------------

func test_the_chip_points_the_way_the_course_faces() -> void:
	assert_eq(OrientationToggleButton.letter_for(0), "N", "N is the first facing")
	assert_eq(OrientationToggleButton.letter_for(1), "E")
	assert_eq(OrientationToggleButton.letter_for(2), "S")
	assert_eq(OrientationToggleButton.letter_for(3), "W")
	# The arrows are all the same shape, each turned a quarter turn.
	var north: Array = OrientationToggleButton.arrow_rows(0)
	assert_eq(north.size(), OrientationToggleButton.ARROW_GRID)
	for row in north:
		assert_eq(String(row).length(), OrientationToggleButton.ARROW_GRID,
			"Every arrow row is a full slice of the grid")
	# The north arrow's tip is the top-middle pixel: an arrow, not a blob.
	assert_eq(String(north[0])[4], "x", "The arrow points up from its top edge")
	assert_eq(String(OrientationToggleButton.arrow_rows(2)[8])[4], "x",
		"and down from its bottom edge when the course faces south")
	assert_eq(String(OrientationToggleButton.arrow_rows(1)[4])[8], "x",
		"the east arrow's tip points right")
	assert_eq(String(OrientationToggleButton.arrow_rows(3)[4])[0], "x",
		"and the west arrow's tip points left")
	for orientation in OrientationToggleButton.ORIENTATION_COUNT:
		assert_ne(OrientationToggleButton.arrow_rows(orientation),
			OrientationToggleButton.arrow_rows(orientation + 1),
			"Each quarter turn repaints the arrow")

func test_the_chip_follows_its_orientation_and_wraps() -> void:
	var chip := OrientationToggleButton.new()
	add_child_autofree(chip)
	assert_eq(chip.orientation, 0, "A fresh chip faces north")
	assert_eq(chip.letter, "N")
	chip.orientation = 3
	assert_eq(chip.letter, "W", "West")
	chip.orientation = 4
	assert_eq(chip.orientation, 0, "Four quarter turns come back to north")
	assert_eq(OrientationToggleButton.letter_for(-1), "W", "Turning back from north faces west")

func test_the_chip_reads_as_a_switch_for_the_arrows() -> void:
	var chip := OrientationToggleButton.new()
	add_child_autofree(chip)
	assert_true(chip.controls_shown, "The arrows start out beside the card")
	chip.controls_shown = false
	assert_false(chip.controls_shown, "Folding them away dims the chip")
	# The chip itself is a real, focusable button: it is the way back.
	assert_eq(chip.focus_mode, Control.FOCUS_ALL)
	assert_eq(chip.text, "", "Its face is drawn, not typed")
	assert_gt(chip.custom_minimum_size.x, 0.0)

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
