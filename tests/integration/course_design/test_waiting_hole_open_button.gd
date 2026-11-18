extends MainSceneTest
## Integration tests for the inline "Open Hole" button on the waiting tee-to-cup
## line: real mouse clicks, brush-drag passthrough, par 4 dogleg routes, camera
## pan/zoom/rotation/elevation/UI-scale tracking, undo/redo, save/load, pause
## and overlay gating, portrait touch taps and gamepad cursor clicks.

const SAVE_SLOT := "test_waiting_hole_open_button"

func before_all() -> void:
	await super()
	await new_game()

func after_all() -> void:
	SaveManager.delete_save(SAVE_SLOT)
	Screen.set_ui_scale_mode(Screen.UIScaleMode.AUTO, false)
	super()

func _button() -> WaitingHoleOpenButton:
	return main.placement_preview.open_hole_button

func _set_camera(world_pos: Vector2, zoom_level: float = 1.0) -> void:
	main.camera.focus_on(world_pos, true)
	main.camera.set_zoom_level(zoom_level, true)
	await process_frames(2)

func _focus_between(a: Vector2i, b: Vector2i, zoom_level: float = 1.0) -> void:
	var world_a: Vector2 = main.terrain_grid.grid_to_screen_center(a)
	var world_b: Vector2 = main.terrain_grid.grid_to_screen_center(b)
	await _set_camera((world_a + world_b) * 0.5, zoom_level)

func _hover_tile(tile: Vector2i) -> void:
	var world_pos: Vector2 = main.terrain_grid.grid_to_screen_center(tile)
	var screen_pos: Vector2 = main.camera.get_canvas_transform() * world_pos
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	get_viewport().push_input(motion)
	await process_frames(2)

func _wait_for_waiting_route(max_frames: int = 120) -> Array[Vector2i]:
	for _i in range(max_frames):
		await process_frames(1)
		if not main.placement_preview.waiting_hole_route.is_empty():
			return main.placement_preview.waiting_hole_route
	return []

func _tap(at: Vector2) -> void:
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = at
		get_viewport().push_input(touch)
		await process_frames(1)
	await process_frames(2)

func test_inline_button_sits_on_the_waiting_line_across_tools_and_opens_on_click() -> void:
	var btn := _button()
	assert_not_null(btn, "Main mounts an inline WaitingHoleOpenButton in the HUD")
	assert_eq(btn.get_parent(), main.get_node("UI/HUD"))
	assert_eq(btn.get_index(), 0,
			"Inline button stays at HUD index 0 behind PortraitHUD, dock, shelf and panels")
	assert_false(btn.visible, "Hidden before any tee and cup wait")

	var tee := Vector2i(50, 56)
	var cup := Vector2i(60, 56)
	await _focus_between(tee, cup)

	# Painting the tee alone leaves the button hidden; hovering the Green tool
	# shows only the cursor preview, not the committed waiting-line button.
	paint(TerrainTypes.Type.TEE_BOX, tee)
	await process_frames(2)
	assert_false(btn.visible, "Hidden when only the tee has been placed")

	main._on_tool_selected(TerrainTypes.Type.GREEN)
	await _hover_tile(cup)
	assert_false(main.placement_preview.potential_hole.is_empty(),
			"Hover preview shows the potential hole")
	assert_false(btn.visible, "Inline button waits until the cup is actually cut")

	# Cutting the cup commits the waiting pair and seats the button on the line.
	stroke(cup)
	await process_frames(2)
	assert_true(btn.visible, "Visible as soon as tee and cup are both waiting")
	assert_false(btn.disabled, "Enabled for a valid 10-tile par 3")

	var screen_pts: PackedVector2Array = main.placement_preview.waiting_hole_screen_points()
	var center := btn.get_global_rect().get_center()
	assert_lt(PlacementPreview.distance_to_polyline(center, screen_pts), 1.0,
			"Button is centered right on the line connecting waiting tee and hole")
	assert_false(btn.get_global_rect().intersects(main.placement_preview.waiting_hole_plaque_rect()),
			"Button keeps clear of the cup plaque")

	# Switching tools — or clearing the active tool — keeps the button anchored.
	main._on_tool_selected(TerrainTypes.Type.BUNKER)
	await process_frames(1)
	assert_true(btn.visible, "Stays on the line while sculpting bunkers")
	main._cancel_action()
	await process_frames(1)
	assert_true(btn.visible, "Stays on the line with no tool selected")
	main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
	await process_frames(1)
	assert_true(btn.visible, "Stays on the line while painting fairway")

	# Record the tile directly beneath the button so we prove clicking the
	# button does NOT paint fairway on the course underneath it.
	var world_under: Vector2 = main.camera.get_canvas_transform().affine_inverse() * center
	var tile_under: Vector2i = main.terrain_grid.screen_to_grid(world_under)
	var terrain_before: int = main.terrain_grid.get_tile(tile_under)

	# Hovering the button clears the brush preview; clicking it opens Hole 1.
	var hover := InputEventMouseMotion.new()
	hover.position = center
	hover.global_position = center
	get_viewport().push_input(hover)
	await process_frames(2)
	assert_true(main.placement_preview.current_preview_positions.is_empty(),
			"Hovering Open Hole hides the terrain brush ghost beneath it")

	await click(btn)
	assert_eq(GameManager.current_course.holes.size(), 1,
			"Clicking Open Hole on the line creates Hole 1")
	assert_eq(GameManager.current_course.holes[0].tee_position, tee)
	assert_eq(GameManager.current_course.holes[0].hole_position, cup)
	assert_false(btn.visible, "Button disappears as soon as the hole opens")
	assert_true(main.placement_preview.waiting_hole.is_empty())
	assert_eq(main.terrain_grid.get_tile(tile_under), terrain_before,
			"Clicking Open Hole did not paint fairway onto the tile beneath it")
	assert_eq(main.current_tool, TerrainTypes.Type.FAIRWAY,
			"Opening the hole preserves the player's selected build tool")

func test_brush_drag_and_inspect_pass_through_button_and_dogleg_tracks_camera() -> void:
	var btn := _button()
	var tee := Vector2i(50, 62)
	var cup := Vector2i(68, 64)  # Par 4 with an intermediate landing waypoint
	await _focus_between(tee, cup)

	# Lay a dogleg fairway north of the straight line so the planned route bends.
	for x in range(52, 65):
		for y in range(59, 61):
			main.terrain_grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	paint(TerrainTypes.Type.TEE_BOX, tee)
	paint(TerrainTypes.Type.GREEN, cup)

	var route := await _wait_for_waiting_route()
	assert_gt(route.size(), 2, "Par 4 waiting hole plans a multi-waypoint route")
	assert_true(btn.visible)

	# Button sits right on the multi-waypoint route's arc-length midpoint.
	var pts: PackedVector2Array = main.placement_preview.waiting_hole_screen_points()
	var expected_mid := PlacementPreview.polyline_point_at(pts, 0.5)
	assert_lt(btn.get_global_rect().get_center().distance_to(expected_mid), 1.5,
			"Button sits on the planned dogleg route's midpoint")

	# Dragging a Fairway brush stroke straight across the button paints through
	# it without triggering Open Hole.
	main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
	main._on_brush_size_changed(1)
	var center := btn.get_global_rect().get_center()
	var start := center - Vector2(btn.size.x + 28.0, 0.0)
	var finish := center + Vector2(btn.size.x + 28.0, 0.0)
	var world_under: Vector2 = main.camera.get_canvas_transform().affine_inverse() * center
	var tile_under: Vector2i = main.terrain_grid.screen_to_grid(world_under)
	main.terrain_grid.set_tile(tile_under, TerrainTypes.Type.GRASS)

	var vp := get_viewport()
	var move_start := InputEventMouseMotion.new()
	move_start.position = start
	move_start.global_position = start
	vp.push_input(move_start)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	vp.push_input(press)
	assert_eq(btn.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"Button ignores mouse events the instant a paint stroke begins")
	for step in range(1, 9):
		var at := start.lerp(finish, float(step) / 8.0)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		vp.push_input(motion)
		await process_frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = finish
	release.global_position = finish
	vp.push_input(release)
	await process_frames(2)

	assert_eq(main.terrain_grid.get_tile(tile_under), TerrainTypes.Type.FAIRWAY,
			"Paint drag swept right across the button and painted the tile beneath it")
	assert_true(btn.visible, "Paint drag across the button did not accidentally open the hole")
	assert_eq(btn.mouse_filter, Control.MOUSE_FILTER_STOP,
			"Button resumes catching clicks once the paint stroke ends")

	# Inspect mode passes hover through to the tile beneath the button.
	main._on_inspect_toggled(true)
	assert_eq(btn.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	main._on_inspect_toggled(false)
	assert_eq(btn.mouse_filter, Control.MOUSE_FILTER_STOP)

	# Camera pan, zoom in, deep zoom out, view rotation, elevation and UI scale
	# all keep the button aligned with the line and clear of the plaque.
	var pos_before_pan := btn.position
	await _set_camera(main.camera.position + Vector2(90.0, -45.0))
	assert_ne(btn.position, pos_before_pan, "Panning the camera moves the button with the course")
	assert_lt(PlacementPreview.distance_to_polyline(
			btn.get_global_rect().get_center(),
			main.placement_preview.waiting_hole_screen_points()), 1.5)

	for zoom_level in [1.75, 0.25, 1.0]:
		await _focus_between(tee, cup, zoom_level)
		assert_true(btn.visible, "Visible at zoom %.2f" % zoom_level)
		assert_false(btn.get_global_rect().intersects(
				main.placement_preview.waiting_hole_plaque_rect()),
				"Never covers the cup plaque at zoom %.2f" % zoom_level)

	# Rotate the isometric view by 90 degrees and back.
	main.terrain_grid.set_view_orientation(1.0)
	await _focus_between(tee, cup)
	assert_true(btn.visible, "Visible after rotating the course view")
	assert_lt(PlacementPreview.distance_to_polyline(
			btn.get_global_rect().get_center(),
			main.placement_preview.waiting_hole_screen_points()), 1.5,
			"Stays on the rotated connecting line")
	main.terrain_grid.set_view_orientation(0.0)
	await _focus_between(tee, cup)

	# Raise elevation around the cup and verify alignment holds.
	for v in main.terrain_grid.vertices_of_tile(cup):
		main.terrain_grid.set_vertex_elevation(v, 3)
	await _wait_for_waiting_route()
	await process_frames(2)
	assert_lt(PlacementPreview.distance_to_polyline(
			btn.get_global_rect().get_center(),
			main.placement_preview.waiting_hole_screen_points()), 1.5,
			"Stays on the line when terrain elevation changes")

	# Explicit UI scale keeps the button aligned with the line in HUD coords.
	Screen.set_ui_scale(1.25, false)
	await _focus_between(tee, cup)
	assert_lt(PlacementPreview.distance_to_polyline(
			btn.get_global_rect().get_center(),
			main.placement_preview.waiting_hole_screen_points()), 1.5,
			"Stays aligned with the line under custom UI scale")
	Screen.set_ui_scale_mode(Screen.UIScaleMode.AUTO, false)
	await _focus_between(tee, cup)

	# Panning far away hides the off-screen button; panning back restores it.
	await _set_camera(main.terrain_grid.grid_to_screen_center(Vector2i(8, 8)))
	assert_false(btn.visible, "Hidden when the waiting hole is panned off screen")
	await _focus_between(tee, cup)
	assert_true(btn.visible, "Shown again when the camera returns to the waiting hole")

	# Sim-clock pause keeps the button usable; modal screens hide it cleanly.
	var prev_speed := GameManager.current_speed
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	await process_frames(2)
	assert_true(btn.visible, "Stays visible and clickable while the sim clock is paused")
	GameManager.set_speed(prev_speed)

	main._toggle_pause_menu()
	await process_frames(2)
	assert_false(btn.visible, "Hidden behind the pause menu")
	main._toggle_pause_menu()
	await process_frames(2)
	assert_true(btn.visible, "Restored after closing the pause menu")

	main._open_course_map()
	await process_frames(2)
	assert_false(btn.visible, "Hidden on the Course Map screen")
	main._on_course_map_back()
	await process_frames(2)
	assert_true(btn.visible, "Restored on returning from the Course Map")

	main._toggle_panel(main.financial_panel)
	await process_frames(2)
	assert_false(btn.visible, "Hidden on the Financial Overview screen")
	main._toggle_panel(main.financial_panel)
	await process_frames(2)
	assert_true(btn.visible, "Restored on closing Financial Overview")

	# Existing H shortcut and toolbar notch button continue to work alongside it.
	var holes_before := GameManager.current_course.holes.size()
	main._on_open_hole_pressed()
	await process_frames(2)
	assert_eq(GameManager.current_course.holes.size(), holes_before + 1)
	assert_false(btn.visible)

func test_undo_redo_save_load_touch_tap_and_gamepad_pointer_open_holes() -> void:
	var btn := _button()
	var tee := Vector2i(50, 70)
	var cup := Vector2i(60, 70)
	await _focus_between(tee, cup)

	paint(TerrainTypes.Type.TEE_BOX, tee)
	paint(TerrainTypes.Type.GREEN, cup)
	await process_frames(2)
	assert_true(btn.visible)

	# Undo removes the cup and hides the button; redo restores both.
	main._perform_undo()
	await process_frames(2)
	assert_false(btn.visible, "Undoing the waiting cup hides Open Hole")
	main._perform_redo()
	await process_frames(2)
	assert_true(btn.visible, "Redoing the waiting cup restores Open Hole")

	# Save and reload preserves the waiting pair and its inline button.
	assert_true(SaveManager.save_game(SAVE_SLOT))
	assert_true(SaveManager.load_game(SAVE_SLOT))
	await _focus_between(tee, cup)
	assert_true(btn.visible, "Waiting hole's inline Open Hole button survives save + load")

	# Portrait phone viewport: 44 px thumb target, behind PortraitHUD, answers a real tap.
	await set_window(Vector2i(390, 844))
	await _focus_between(tee, cup, 0.7)
	assert_true(btn.visible, "Visible in portrait phone layout")
	assert_gte(btn.size.y, float(UIConstants.TOUCH_TARGET_SIZE),
			"Meets 44 px minimum touch target height on phones")
	assert_lt(btn.get_index(), main.portrait_hud.get_index(),
			"Stays behind PortraitHUD so open trays always cover it")

	var holes_before := GameManager.current_course.holes.size()
	await _tap(btn.get_global_rect().get_center())
	assert_eq(GameManager.current_course.holes.size(), holes_before + 1,
			"Finger tap on the inline Open Hole pill opens the hole")
	assert_false(btn.visible)

	# Return to desktop layout and open one more hole via GamepadCursor click.
	await set_window(DESIGN_WINDOW)
	var tee2 := Vector2i(50, 75)
	var cup2 := Vector2i(60, 75)
	await _focus_between(tee2, cup2)
	paint(TerrainTypes.Type.TEE_BOX, tee2)
	paint(TerrainTypes.Type.GREEN, cup2)
	await process_frames(2)
	assert_true(btn.visible)

	# Drive the real GamepadCursor over the button and click with controller A.
	InputManager.clear_focus()
	InputManager.device = InputManager.Device.GAMEPAD
	await process_frames(3)
	var cursor: GamepadCursor = main.gamepad_cursor
	assert_true(cursor.visible, "Controller pointer is active on the course")
	cursor.position = btn.get_global_rect().get_center()
	cursor._place_pointer()
	await process_frames(1)
	for pressed in [true, false]:
		var click_action := InputEventAction.new()
		click_action.action = "gamepad_click"
		click_action.pressed = pressed
		get_viewport().push_input(click_action)
		await process_frames(1)
		if pressed:
			assert_true(cursor._active,
					"FOCUS_NONE keeps GamepadCursor alive between press and release")
	await process_frames(2)
	InputManager.device = InputManager.Device.MOUSE
	await process_frames(1)
	assert_eq(GameManager.current_course.holes.size(), holes_before + 2,
			"Controller/keyboard virtual pointer opens the hole through the inline button")
	assert_false(btn.visible)

func test_too_short_pair_stays_disabled_and_special_course_modes_hide_button() -> void:
	var btn := _button()
	var tee := Vector2i(50, 80)
	var short_cup := Vector2i(52, 80)
	var legal_cup := Vector2i(60, 80)
	await _focus_between(tee, short_cup)

	paint(TerrainTypes.Type.TEE_BOX, tee)
	paint(TerrainTypes.Type.GREEN, short_cup)
	await process_frames(2)
	assert_true(btn.visible, "Too-short pair shows the inline button on its red dashed line")
	assert_true(btn.disabled, "Too-short pair cannot be opened yet")

	var holes_before := GameManager.current_course.holes.size()
	await click(btn)
	assert_eq(GameManager.current_course.holes.size(), holes_before,
			"Clicking a disabled too-short Open Hole button does not create a hole")
	assert_true(btn.visible)

	# Replace the too-short cup with a legal one: button enables immediately.
	paint(TerrainTypes.Type.GRASS, short_cup)
	await process_frames(1)
	assert_false(btn.visible)
	await _focus_between(tee, legal_cup)
	paint(TerrainTypes.Type.GREEN, legal_cup)
	await process_frames(2)
	assert_true(btn.visible)
	assert_false(btn.disabled, "Moving the cup past MIN_HOLE_TILES enables Open Hole")

	# Owner work-area pick, player practice round and tournament mode all hide it.
	main._owner_area_mode = true
	await process_frames(2)
	assert_false(btn.visible, "Hidden while picking the owner's work area on the turf")
	main._owner_area_mode = false
	await process_frames(2)
	assert_true(btn.visible)

	main.player_round.active = true
	await process_frames(2)
	assert_false(btn.visible, "Hidden while playing a round on the course")
	main.player_round.active = false
	await process_frames(2)
	assert_true(btn.visible)

	GameManager.is_tournament_mode = true
	await process_frames(2)
	assert_false(btn.visible, "Hidden in standalone tournament mode")
	GameManager.is_tournament_mode = false
	await process_frames(2)
	assert_true(btn.visible)

	# Clean up by opening the hole through the inline button.
	await click(btn)
	assert_eq(GameManager.current_course.holes.size(), holes_before + 1)
	assert_false(btn.visible)

