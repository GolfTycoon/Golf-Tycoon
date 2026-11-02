extends MainSceneTest
## The view controls in the running HUD: the two Rotate arrows at the top-left
## corner, on the right of the location banner's details card, and the facing
## chip in that card's top-right corner that shows the direction the course
## faces and folds the arrows away.
##
## Every test drives the real buttons through real clicks, so a control that
## something else draws over - or that sits off screen - fails here.

func before_all() -> void:
	await super()
	await new_game()

func _banner() -> CourseLocationBanner:
	return main.course_location_banner

func _details_card() -> Control:
	return main.course_location_banner.get_node("Columns/DetailsPanel")

func _chip() -> OrientationToggleButton:
	return main.course_location_banner.orientation_toggle

func _restore_orientation() -> void:
	main.terrain_grid.set_view_orientation(0)
	await process_frames(1)

func test_the_arrows_stand_in_the_top_left_corner_on_the_right_of_the_card() -> void:
	var arrows: Control = main.rotate_view_controls
	var card := _details_card()
	await process_frames(2)
	assert_eq(arrows.get_parent(), main.course_location_banner.get_node("Columns"),
		"The arrows share the columns' row")
	assert_gte(arrows.get_global_rect().position.x, card.get_global_rect().end.x,
		"They stand to the right of the details card")
	assert_lt(arrows.get_global_rect().position.y, _screen().size.y * 0.5,
		"and stay in the top-left corner of the screen")
	assert_lt(arrows.get_global_rect().end.x, _screen().size.x * 0.5,
		"well clear of the top-right status column")

func test_the_chip_shows_the_facing_in_the_card_s_top_right_corner() -> void:
	var chip := _chip()
	var card := _details_card()
	await process_frames(2)
	var card_rect := card.get_global_rect()
	assert_true(rect_within(chip.get_global_rect(), card_rect),
		"The chip lives inside the details card")
	assert_gt(chip.get_global_rect().position.x, card_rect.get_center().x,
		"on its right-hand side")
	assert_lt(chip.get_global_rect().get_center().y, card_rect.get_center().y,
		"and along its top edge")
	assert_eq(chip.letter, OrientationToggleButton.letter_for(
		main.terrain_grid.get_view_orientation()),
		"The letter names the direction the course faces")

func test_clicking_an_arrow_turns_the_course_and_the_chip_follows() -> void:
	await _restore_orientation()
	var start: int = main.terrain_grid.get_view_orientation()
	assert_eq(_chip().letter, "N")

	await click(main.rotate_cw_btn)
	assert_eq(main.terrain_grid.get_view_orientation(), wrapi(start + 1, 0, 4),
		"The clockwise arrow turns the course a quarter turn clockwise")
	assert_eq(_chip().letter, "E", "and the chip follows it to east")

	await click(main.rotate_ccw_btn)
	assert_eq(main.terrain_grid.get_view_orientation(), start,
		"The counter-clockwise arrow turns it back")
	assert_eq(_chip().letter, "N", "and the chip comes back to north")
	await _restore_orientation()

func test_q_and_e_turn_the_course_from_the_keyboard() -> void:
	await _restore_orientation()
	var start: int = main.terrain_grid.get_view_orientation()

	press_key(KEY_Q)
	await process_frames(2)
	assert_eq(main.terrain_grid.get_view_orientation(), wrapi(start - 1, 0, 4),
		"Q turns the course a quarter turn counter-clockwise")
	assert_eq(_chip().letter, "W", "and the chip follows it to west")

	press_key(KEY_E)
	await process_frames(2)
	assert_eq(main.terrain_grid.get_view_orientation(), start,
		"E turns the course back clockwise")
	assert_eq(_chip().letter, "N", "and the chip comes back to north")
	await _restore_orientation()


func test_the_rotate_tooltips_name_the_keys_in_force() -> void:
	assert_string_contains(main.rotate_ccw_btn.tooltip_text, "(Q)",
		"the counter-clockwise arrow names its default key")
	assert_string_contains(main.rotate_cw_btn.tooltip_text, "(E)",
		"and the clockwise arrow names E")

	var rebound := InputEventKey.new()
	rebound.keycode = KEY_F6
	InputBindings.assign_binding("rotate_camera_cw", rebound)
	assert_string_contains(main.rotate_cw_btn.tooltip_text, "(F6)",
		"the tooltip follows a rebind instead of going stale")
	InputBindings.reset_binding("rotate_camera_cw")
	assert_string_contains(main.rotate_cw_btn.tooltip_text, "(E)",
		"and Reset brings the default name back")


func test_the_chip_folds_the_arrows_away_and_brings_them_back() -> void:
	await _restore_orientation()
	var banner := _banner()
	var wide := banner.size.x
	assert_true(main.rotate_ccw_btn.is_visible_in_tree(), "The arrows start out")

	await click(_chip())
	assert_false(main.rotate_ccw_btn.is_visible_in_tree(), "The first click folds them away")
	assert_false(main.rotate_cw_btn.is_visible_in_tree())
	assert_true(_chip().is_visible_in_tree(), "The chip stays in the corner")
	assert_lt(banner.size.x, wide, "and the postcard narrows back into their room")
	assert_gt(_chip().size.x, 0.0, "The chip keeps its own footprint")

	await click(_chip())
	assert_true(main.rotate_ccw_btn.is_visible_in_tree(), "The second click brings them back")
	assert_almost_eq(banner.size.x, wide, 1.0, "and the corner takes their room again")

func test_the_whole_corner_stays_on_screen_at_every_window_size() -> void:
	for window_size in [Vector2i(1600, 1000), Vector2i(1024, 768),
			Vector2i(390, 844), Vector2i(360, 800), Vector2i(844, 390)]:
		await set_window(window_size)
		var screen := Rect2(Vector2.ZERO, Vector2(window_size))
		if Screen.uses_portrait_hud():
			# Portrait moves rotation to the camera rail; the banner's arrows
			# and facing chip fold away so the ledger owns the top strip.
			assert_false(main.rotate_ccw_btn.is_visible_in_tree(),
				"The banner arrows fold away in portrait at %s" % window_size)
			assert_false(_chip().is_visible_in_tree(),
				"The facing chip folds away in portrait at %s" % window_size)
			var rail: Control = main.portrait_hud.get_node("CameraRail")
			for action_name in ["RotateLeft", "RotateRight"]:
				var arrow: Control = rail.get_node(action_name)
				assert_true(rect_within(arrow.get_global_rect(), screen),
					"%s stays on screen in the portrait camera rail at %s" % [action_name, window_size])
				assert_gte(arrow.size.x, float(UIConstants.TOUCH_TARGET_SIZE),
					"The portrait rotate action is touch sized at %s" % window_size)
			continue
		for control in [_chip(), main.rotate_ccw_btn, main.rotate_cw_btn]:
			assert_true(rect_within(control.get_global_rect(), screen),
				"%s stays on screen at %s" % [control.name, window_size])
		if Screen.uses_touch_layout():
			for arrow in [main.rotate_ccw_btn, main.rotate_cw_btn]:
				assert_gte(arrow.size.x, float(UIConstants.TOUCH_TARGET_SIZE),
					"The arrows grow to the touch target at %s" % window_size)
			assert_gte(_chip().size.x, float(UIConstants.TOUCH_TARGET_SIZE),
				"The facing chip grows with them at %s" % window_size)
		# Folding the arrows away never strands the chip or the card.
		main.course_location_banner.set_rotate_controls_visible(false)
		await process_frames(2)
		assert_true(rect_within(_chip().get_global_rect(), screen),
			"The folded corner still shows the chip at %s" % window_size)
		main.course_location_banner.set_rotate_controls_visible(true)
		await process_frames(2)
		assert_true(rect_within(main.rotate_ccw_btn.get_global_rect(), screen),
			"The arrows come back on screen at %s" % window_size)
	await set_window(DESIGN_WINDOW)
	await _restore_orientation()

## The whole window, in the same coordinates the controls report.
func _screen() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(get_window().size))
