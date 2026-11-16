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
	GameManager.set_gradual_view_rotation(true)
	main.terrain_grid.set_view_orientation(0)
	await process_frames(1)

func _wait_for_view_settled() -> void:
	if main.terrain_grid.is_view_turning():
		await wait_for_signal(main.terrain_grid.view_rotation_settled, 1.5)
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
	assert_almost_eq(chip.get_global_rect().get_center().y, card_rect.get_center().y, 0.5,
		"The larger compass is vertically centered in the details card")
	assert_eq(chip.letter, OrientationToggleButton.letter_for(
		main.terrain_grid.get_view_orientation()),
		"The letter names the direction the course faces")

func test_clicking_an_arrow_turns_the_course_and_the_chip_follows() -> void:
	await _restore_orientation()
	assert_eq(_chip().letter, "N")

	await click(main.rotate_cw_btn)
	await _wait_for_view_settled()
	assert_almost_eq(main.terrain_grid.get_view_angle(), 1.0 / 6.0, 0.001,
		"One clockwise arrow press turns the course 15 degrees")
	assert_eq(_chip().direction_step, 1,
		"The compass advances to its second 15-degree heading")
	assert_string_contains(_chip().tooltip_text, "North 15 degrees east",
		"The tooltip retains the precise heading without a face readout")
	assert_false(_chip().tooltip_text.contains("of 24"),
		"The button no longer displays a numbered direction readout")
	assert_eq(_chip().letter, "N",
		"The compatibility cardinal remains north until the course approaches east")

	for _i in range(5):
		await click(main.rotate_cw_btn)
	await _wait_for_view_settled()
	assert_eq(main.terrain_grid.get_view_orientation(), 1,
		"Six clockwise presses reach a full quarter turn clockwise")
	assert_almost_eq(main.terrain_grid.get_view_angle(), 1.0, 0.001)
	assert_eq(_chip().direction_step, 6, "The compass has reached its east heading")
	assert_string_contains(_chip().tooltip_text, "East",
		"The tooltip follows the compass heading")
	assert_eq(_chip().letter, "E", "The nearest-cardinal label agrees")

	for _i in range(6):
		await click(main.rotate_ccw_btn)
	await _wait_for_view_settled()
	assert_eq(main.terrain_grid.get_view_orientation(), 0,
		"Six counter-clockwise presses turn it back")
	assert_almost_eq(main.terrain_grid.get_view_angle(), 0.0, 0.001)
	assert_eq(_chip().letter, "N", "and the chip comes back to north")
	await _restore_orientation()

func test_q_and_e_turn_the_course_from_the_keyboard() -> void:
	await _restore_orientation()

	press_key(KEY_Q)
	await _wait_for_view_settled()
	assert_almost_eq(main.terrain_grid.get_view_angle(), 3.0 + 5.0 / 6.0, 0.001,
		"Q turns the course 15 degrees counter-clockwise")
	assert_eq(_chip().letter, "N", "staying north before crossing 45 degrees")

	for _i in range(3):
		press_key(KEY_Q)
	await _wait_for_view_settled()
	assert_eq(main.terrain_grid.get_view_orientation(), 3,
		"Crossing 45 degrees switches the four-way facing to west")
	assert_eq(_chip().letter, "W", "and the chip follows it to west")

	for _i in range(2):
		press_key(KEY_Q)
	await _wait_for_view_settled()
	assert_almost_eq(main.terrain_grid.get_view_angle(), 3.0, 0.001,
		"Six Q presses reach a full quarter turn counter-clockwise")

	for _i in range(6):
		press_key(KEY_E)
	await _wait_for_view_settled()
	assert_eq(main.terrain_grid.get_view_orientation(), 0,
		"Six E presses turn the course back clockwise")
	assert_almost_eq(main.terrain_grid.get_view_angle(), 0.0, 0.001)
	assert_eq(_chip().letter, "N", "and the chip comes back to north")
	await _restore_orientation()

func test_holding_rotate_key_or_button_keeps_stepping_while_tap_stays_one_step() -> void:
	await _restore_orientation()
	press_key(KEY_E)
	await _wait_for_view_settled()
	assert_almost_eq(main.terrain_grid.get_view_angle(), 1.0 / 6.0, 0.001,
		"A quick tap stays one precise 15-degree step")

	await _restore_orientation()
	Input.action_press("rotate_camera_cw")
	await wait_seconds(0.65)
	Input.action_release("rotate_camera_cw")
	await _wait_for_view_settled()
	assert_gt(main.terrain_grid.get_view_angle(), 2.0 / 6.0,
		"Holding the CW rotate key keeps stepping past a single 15-degree turn")

	var angle_before_gamepad: float = main.terrain_grid.get_view_angle()
	Input.action_press("gamepad_rotate_ccw")
	await wait_seconds(0.65)
	Input.action_release("gamepad_rotate_ccw")
	await _wait_for_view_settled()
	assert_lt(main.terrain_grid.get_view_angle(), angle_before_gamepad - 1.5 / 6.0,
		"Holding the gamepad rotate button keeps stepping counter-clockwise too")
	await _restore_orientation()

func test_camera_and_moving_entities_stay_pinned_during_gradual_rotation() -> void:
	await _restore_orientation()
	var target_grid := Vector2(64.5, 64.5)
	main.camera.focus_on(main.terrain_grid.grid_to_screen_precise(target_grid), true)
	await process_frames(2)

	var marker := Node2D.new()
	var entity_grid := Vector2(60.25, 62.75)
	marker.global_position = main.terrain_grid.grid_to_screen_precise(entity_grid)
	main.staff_container.add_child(marker)
	autofree(marker)

	main._on_view_rotate_cw()
	for _frame in range(6):
		await process_frames(1)
		var cam_grid: Vector2 = main.terrain_grid.screen_to_grid_precise(main.camera.global_position)
		var marker_grid: Vector2 = main.terrain_grid.screen_to_grid_precise(marker.global_position)
		assert_almost_eq(cam_grid.x, target_grid.x, 0.05,
			"Camera stays pinned horizontally during tween frame")
		assert_almost_eq(cam_grid.y, target_grid.y, 0.05,
			"Camera stays pinned vertically during tween frame")
		assert_almost_eq(marker_grid.x, entity_grid.x, 0.05,
			"Moving entity stays pinned horizontally during tween frame")
		assert_almost_eq(marker_grid.y, entity_grid.y, 0.05,
			"Moving entity stays pinned vertically during tween frame")
	await _wait_for_view_settled()
	await _restore_orientation()

func test_walking_golfer_stays_on_course_route_when_rotated_while_moving() -> void:
	await _restore_orientation()
	var start_tile := Vector2i(50, 50)
	var dest_tile := Vector2i(62, 54)
	var golfer: Golfer = main.golfer_manager.spawn_golfer("Walker")
	golfer.global_position = main.terrain_grid.grid_to_screen_center(start_tile)
	golfer.begin_walk_to(main.terrain_grid.grid_to_screen_center(dest_tile), "Walking to tee")
	assert_gt(golfer.path.size(), 0, "precondition: golfer has a walking path")

	# Rotate 90 degrees across 6 gradual steps while the golfer walks.
	for _i in range(6):
		main._on_view_rotate_cw()
		await wait_seconds(0.05)
	await _wait_for_view_settled()

	assert_gt(golfer.path.size(), 0)
	var dest_after: Vector2 = main.terrain_grid.screen_to_grid_point(golfer.path.back())
	assert_almost_eq(dest_after.x, float(dest_tile.x) + 0.5, 0.1,
		"Walking golfer's destination waypoint X tracks the rotated course")
	assert_almost_eq(dest_after.y, float(dest_tile.y) + 0.5, 0.1,
		"Walking golfer's destination waypoint Y tracks the rotated course")
	main.golfer_manager.clear_all_golfers()
	await _restore_orientation()

func test_flying_and_rolling_ball_lands_on_target_when_rotated_in_flight() -> void:
	await _restore_orientation()
	var from_precise := Vector2(45.0, 48.0)
	var carry_precise := Vector2(58.0, 52.0)
	var final_precise := Vector2(61.0, 53.0)
	var ball: Ball = main.ball_manager.get_or_create_ball(999)
	ball.visible = true
	var from_screen: Vector2 = main.terrain_grid.grid_to_screen_precise(from_precise)
	var carry_screen: Vector2 = main.terrain_grid.grid_to_screen_precise(carry_precise)
	var final_screen: Vector2 = main.terrain_grid.grid_to_screen_precise(final_precise)
	ball.set_rollout(final_screen, 0.25)
	ball.start_flight_screen_with_arc(from_screen, carry_screen, 0.35, Vector2(18.0, -6.0))

	# Rotate while the ball is mid-flight and wait until it lands and finishes rolling.
	for _i in range(6):
		main._on_view_rotate_cw()
		await process_frames(2)
	await _wait_for_view_settled()
	var wait_guard := 0
	while ball.ball_state != Ball.BallState.AT_REST and wait_guard < 120:
		await process_frames(1)
		wait_guard += 1

	assert_eq(ball.ball_state, Ball.BallState.AT_REST, "Ball finishes flight and rollout")
	var landed_precise: Vector2 = main.terrain_grid.screen_to_grid_precise(ball.global_position)
	assert_almost_eq(landed_precise.x, final_precise.x, 0.15,
		"Ball lands and rolls to exact final X after mid-flight rotation")
	assert_almost_eq(landed_precise.y, final_precise.y, 0.15,
		"Ball lands and rolls to exact final Y after mid-flight rotation")
	main.ball_manager.remove_ball(999)
	await _restore_orientation()

func test_course_owner_keeps_position_on_rotation_when_not_playing_a_round() -> void:
	await _restore_orientation()
	var owner_golfer: Golfer = main.player_golfer_manager.ensure_golfer()
	assert_not_null(owner_golfer, "precondition: course owner exists on the course")
	assert_false(owner_golfer in main.golfer_manager.get_active_golfers(),
		"precondition: owner is on duty, not in active round golfers")

	var start_tile := Vector2i(54, 56)
	var duty_target_tile := Vector2i(58, 59)
	owner_golfer.global_position = main.terrain_grid.grid_to_screen_center(start_tile)
	var duty: OwnerDuty = main.player_golfer_manager.duty
	duty.step = OwnerDuty.Step.IDLE
	duty._timer = 10.0

	var before_grid: Vector2 = main.terrain_grid.screen_to_grid_point(owner_golfer.global_position)
	for _i in range(6):
		main._on_view_rotate_cw()
	await _wait_for_view_settled()

	var after_grid: Vector2 = main.terrain_grid.screen_to_grid_point(owner_golfer.global_position)
	assert_almost_eq(after_grid.x, before_grid.x, 0.05,
		"Off-round course owner keeps X tile position across rotation")
	assert_almost_eq(after_grid.y, before_grid.y, 0.05,
		"Off-round course owner keeps Y tile position across rotation")

	duty.step = OwnerDuty.Step.WALKING
	duty._target = main.terrain_grid.grid_to_screen_center(duty_target_tile)
	for _i in range(6):
		main._on_view_rotate_cw()
	await _wait_for_view_settled()

	var after_target: Vector2 = main.terrain_grid.screen_to_grid_point(duty._target)
	assert_almost_eq(after_target.x, float(duty_target_tile.x) + 0.5, 0.05,
		"OwnerDuty walk target X tracks the rotated course")
	assert_almost_eq(after_target.y, float(duty_target_tile.y) + 0.5, 0.05,
		"OwnerDuty walk target Y tracks the rotated course")
	duty.step = OwnerDuty.Step.IDLE
	duty._timer = 0.3
	await _restore_orientation()

func test_turning_gradual_rotation_off_settles_and_restores_instant_quarter_turns() -> void:
	await _restore_orientation()
	for _i in range(4):
		await click(main.rotate_cw_btn)
	await _wait_for_view_settled()
	assert_almost_eq(main.terrain_grid.get_view_angle(), 4.0 / 6.0, 0.001)

	GameManager.set_gradual_view_rotation(false)
	await process_frames(1)
	assert_almost_eq(main.terrain_grid.get_view_angle(), 1.0, 0.001,
		"Turning gradual view rotation off settles onto the nearest quarter turn (E)")
	assert_eq(_chip().letter, "E")

	await click(main.rotate_cw_btn)
	assert_false(main.terrain_grid.is_view_turning(),
		"With gradual rotation off, turning snaps immediately without a tween")
	assert_eq(main.terrain_grid.get_view_orientation(), 2)
	assert_eq(_chip().letter, "S")

	await click(main.rotate_ccw_btn)
	assert_eq(main.terrain_grid.get_view_orientation(), 1)
	assert_eq(_chip().letter, "E")
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
