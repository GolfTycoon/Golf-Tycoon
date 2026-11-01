extends MainSceneTest
## The shelf's mirrored rim and curved tab rail, exercised through the real HUD.

func before_all() -> void:
	await super()
	await new_game()

func test_tabs_follow_the_rim_and_stay_on_screen_at_each_size() -> void:
	for window_size in [DESIGN_WINDOW, Vector2i(1024, 768), Vector2i(390, 844),
			Vector2i(360, 800), Vector2i(844, 390)]:
		await set_window(window_size)
		var toolbar: TerrainToolbar = main.terrain_toolbar
		var screen := Rect2(Vector2.ZERO, Vector2(window_size))
		for section in TerrainToolbar.SECTION_TABS:
			toolbar.select_section(section)
			await process_frames(3)
			var tabs: Array = TerrainToolbar.SECTION_TABS[section]
			if is_equal_approx(toolbar._tab_rail.size.x, TerrainToolbar.TAB_RAIL_WIDTH):
				var last_dock: PixelCircleButton = main.left_controls.section_buttons[-1]
				var dock_radius: float = last_dock.get_global_rect().end.x \
						- main.left_controls.get_global_position().x + DockArcBackdrop.RIM_SIDE_MARGIN
				assert_almost_eq(toolbar._backdrop.curve_width, dock_radius, 0.1,
						"at full size the shelf reflects the dock's actual radius")
			var previous := Vector2(INF, -INF)
			var previous_radius := 0.0
			assert_eq(toolbar._backdrop.circles.size(), tabs.size(), "one socket per visible tab")
			for i in tabs.size():
				var button: PixelCircleButton = toolbar._tab_buttons[tabs[i]]
				var rect := button.get_global_rect()
				var center := rect.get_center()
				var radius := rect.size.x * 0.5
				assert_eq(rect.size.x, rect.size.y, "tab hit areas remain circular")
				assert_gte(rect.size.x, 44.0, "each tab remains a comfortable target")
				assert_true(rect_within(rect, screen), "tabs stay on screen at %s" % window_size)
				assert_true(toolbar._tab_rail.get_global_rect().encloses(rect),
						"tabs stay clear of the scrolling page")
				if i > 0:
					assert_gte(center.y, previous.y, "tabs descend along the rim")
					assert_lte(center.x, previous.x, "the mirrored arc bends left")
					assert_gte(center.distance_to(previous), radius + previous_radius,
							"neighbouring touch targets do not overlap")
				var socket: Vector3 = toolbar._backdrop.circles[i]
				var local := center - toolbar.get_global_position()
				assert_almost_eq(socket.x, local.x, 0.1, "socket tracks the tab")
				assert_almost_eq(socket.y, local.y, 0.1, "socket tracks the tab")
				previous = center
				previous_radius = radius
			var first: Control = toolbar._tab_buttons[tabs[0]]
			var last: Control = toolbar._tab_buttons[tabs[-1]]
			assert_gt(first.get_global_rect().get_center().x,
					last.get_global_rect().get_center().x, "the rail is curved, not a column")
	await set_window(DESIGN_WINDOW)

func test_every_tab_can_be_clicked_on_a_compact_shelf() -> void:
	# Toasts are intentionally clickable overlays and may arrive while the
	# simulation runs; keep this test focused on the unobscured shelf itself.
	var notifications := main.get_node("UI/NotificationToast") as Control
	var notifications_visible := notifications.visible
	notifications.hide()
	for window_size in [Vector2i(390, 844), Vector2i(360, 800)]:
		await set_window(window_size)
		var toolbar: TerrainToolbar = main.terrain_toolbar
		toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
		await process_frames(3)
		var cutout := toolbar.get_global_position() + Vector2(4, 8)
		assert_false(bool(TouchInput._touch_target_at(cutout)["over_ui"]),
				"touches in the cutout reach the course at %s" % window_size)
		for section in TerrainToolbar.SECTION_TABS:
			toolbar.select_section(section)
			await process_frames(3)
			for tab in TerrainToolbar.SECTION_TABS[section]:
				var button: PixelCircleButton = toolbar._tab_buttons[tab]
				assert_true(bool(TouchInput._touch_target_at(button.get_global_rect().get_center())["over_ui"]),
						"touch recognises each tab at %s" % window_size)
				await click(button)
				assert_eq(toolbar.current_tab, tab, "every curved tab works at %s" % window_size)
	notifications.visible = notifications_visible
	await set_window(DESIGN_WINDOW)

func test_course_cutout_passes_input_but_exposed_tab_edges_work() -> void:
	await set_window(DESIGN_WINDOW)
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	await process_frames(3)
	var cutout := toolbar.get_global_position() + Vector2(4, 8)
	assert_false(toolbar._has_point(Vector2(4, 8)), "empty air is outside the shelf's mouse shape")
	assert_false(bool(TouchInput._touch_target_at(cutout)["over_ui"]),
			"touch gestures in the cutout belong to the course")
	var motion := InputEventMouseMotion.new()
	motion.position = cutout
	motion.global_position = cutout
	get_viewport().push_input(motion)
	await process_frames(1)
	assert_null(get_viewport().gui_get_hovered_control(), "the cutout also passes mouse input")

	# The first tab partly projects beyond the painted rim. Its round face must
	# still receive a real click and be recognised as UI by touch input.
	var first: PixelCircleButton = toolbar._tab_buttons[TerrainToolbar.Tab.TERRAIN]
	var exposed := first.get_global_rect().position + first.size * 0.2
	assert_true(first._has_point(first.size * 0.2))
	assert_false(toolbar._has_point(exposed - toolbar.get_global_position()),
			"the chosen point is on the part of the tab outside the rim")
	assert_true(bool(TouchInput._touch_target_at(exposed)["over_ui"]))
	motion = InputEventMouseMotion.new()
	motion.position = exposed
	motion.global_position = exposed
	get_viewport().push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = exposed
		event.global_position = exposed
		get_viewport().push_input(event)
		await process_frames(1)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.TERRAIN, "the exposed tab face is clickable")

func test_header_row_controls_stay_on_screen_on_a_narrow_phone() -> void:
	await set_window(Vector2i(360, 800))
	var toolbar: TerrainToolbar = main.terrain_toolbar
	# The Terrain shelf's row (brush shape + size + Inspect) is too wide for
	# the narrow shelf, so it hides and touches in the cutout reach the course.
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(3)
	assert_false(toolbar._header_row.visible,
		"the Terrain row hides on the narrow shelf so the tab rail keeps its room")
	var cutout := toolbar.get_global_position() + Vector2(4, 8)
	assert_false(bool(TouchInput._touch_target_at(cutout)["over_ui"]),
		"touches in the cutout reach the course on Terrain")
	# The Improvements and Buildings rows (Bulldozer + Inspect) fit, so they
	# stay visible and their buttons are on screen.
	for tab in [TerrainToolbar.Tab.IMPROVEMENTS, TerrainToolbar.Tab.BUILDINGS]:
		toolbar.select_tab(tab)
		await process_frames(3)
		assert_true(toolbar._header_row.visible,
			"the %s row fits on the narrow shelf" % TerrainToolbar.TAB_TITLES[tab])
		var phone_screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		var dozer: BulldozerButton = toolbar._bulldozer_button
		assert_true(rect_within(dozer.get_global_rect(), phone_screen),
			"the Bulldozer stays on screen on %s" % TerrainToolbar.TAB_TITLES[tab])
		var phone_inspect: InspectButton = toolbar.inspect_button()
		assert_true(rect_within(phone_inspect.get_global_rect(), phone_screen),
			"Inspect stays on screen on %s" % TerrainToolbar.TAB_TITLES[tab])
	await set_window(DESIGN_WINDOW)
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(3)
	# On desktop the header row sits at the top-right of the shelf, and the
	# Inspect toggle can be pressed there.
	assert_true(toolbar._header_row.visible, "the row shows on a wide shelf")
	var inspect: InspectButton = toolbar.inspect_button()
	assert_not_null(inspect, "The header row holds the Inspect toggle")
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	assert_true(rect_within(inspect.get_global_rect(), screen),
		"Inspect stays on screen on desktop")
	await click(inspect)
	assert_true(toolbar.is_inspect_active(), "Inspect can be pressed on desktop")
	await click(inspect)
	assert_false(toolbar.is_inspect_active())
	var row_rect := toolbar._header_row.get_global_rect()
	var shelf_rect := toolbar.get_global_rect()
	assert_almost_eq(row_rect.end.x - shelf_rect.end.x,
		-TerrainToolbar.SHELF_PAD_X, 0.01, "The row hugs the shelf's right padding")

## The scrollable section of every tab reaches under the curved tab buttons,
## with its left side cut along the rim: the course above the cut stays part of
## the course for mouse and touch, and the tiles below it are clickable.
func test_every_tab_scrolls_in_a_window_curved_under_the_rail() -> void:
	for window_size in [DESIGN_WINDOW, Vector2i(1024, 768), Vector2i(390, 844)]:
		await set_window(window_size)
		var toolbar: TerrainToolbar = main.terrain_toolbar
		var window: ShelfPageWindow = toolbar._page_window
		assert_not_null(window, "the shelf cuts its pages to a curved window")
		for tab in TerrainToolbar.TAB_TITLES:
			toolbar.select_tab(tab)
			await process_frames(3)
			var scroll: ScrollContainer = toolbar.page_scroll(tab)
			var rect := scroll.get_global_rect()
			assert_almost_eq(rect.position.x,
				toolbar.get_global_rect().position.x + TerrainToolbar.SHELF_PAD_X, 0.01,
				"%s starts at the shelf's left padding at %s" % [TerrainToolbar.TAB_TITLES[tab], window_size])
			assert_lt(rect.position.x, toolbar._tab_rail.get_global_rect().end.x,
				"%s reaches under the curved rail at %s" % [TerrainToolbar.TAB_TITLES[tab], window_size])

		# A point inside the scroll rect but above the curve belongs to the
		# course: the window's cut-out is not UI, for touch or for the mouse.
		var cutout := toolbar.get_global_position() + Vector2(4.0, 60.0)
		var local := cutout - window.get_global_position()
		assert_false(window.contains_content_point(local),
			"the shelf's upper-left cut is still course at %s" % window_size)
		assert_false(bool(TouchInput._touch_target_at(cutout)["over_ui"]),
			"touches in the cut reach the course at %s" % window_size)
		var motion := InputEventMouseMotion.new()
		motion.position = cutout
		motion.global_position = cutout
		get_viewport().push_input(motion)
		await process_frames(1)
		assert_null(get_viewport().gui_get_hovered_control(),
			"the cut also passes the mouse through at %s" % window_size)

		# And the turf below the cut is the page: its first tile still answers.
		toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
		await process_frames(3)
		# The first tile of the first row: on a narrow shelf the shifted
		# bottom row can start past the scroll window, so the row's leading
		# tile is the one that proves the grid reaches in under the rail.
		var first_tile: Control = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]
		assert_true(first_tile.get_global_rect().position.x < toolbar._tab_rail.get_global_rect().end.x,
			"the first row of tiles runs under the rail at %s" % window_size)
		var first_tile_local := first_tile.get_global_rect().get_center() - window.get_global_position()
		assert_true(window.contains_content_point(first_tile_local),
			"and sits inside the curved window at %s" % window_size)
	await set_window(DESIGN_WINDOW)
