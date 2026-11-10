extends MainSceneTest
## Regression coverage for the dedicated portrait composition. These are real
## viewport clicks and live resizes, not just checks on a layout calculator.

const SIZES := [Vector2i(320, 568), Vector2i(360, 640), Vector2i(375, 667),
	Vector2i(390, 844), Vector2i(412, 915), Vector2i(430, 932), Vector2i(540, 960)]

func before_each() -> void:
	super()
	if main.main_menu:
		main.main_menu.queue_free()
		main.main_menu = null
	main._set_gameplay_ui_visible(true)
	Screen.set_portrait_tools_open(false)

func after_each() -> void:
	Screen.set_portrait_tools_open(false)
	await set_window(DESIGN_WINDOW)
	await super()

func _view() -> Rect2:
	return Rect2(Vector2.ZERO, Screen.window_size)

## The page tabs the open section shows, left to right.
func _shown_tabs() -> Array[PixelCircleButton]:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	var tabs: Array[PixelCircleButton] = []
	for tab in TerrainToolbar.SECTION_TABS[toolbar.current_section]:
		var button: PixelCircleButton = toolbar._tab_buttons[tab]
		if button.visible:
			tabs.append(button)
	return tabs

## Every tool the open page floats over the course, cell by cell: a brush size
## stepper counts as its two step buttons and the readout between them.
func _shown_tools() -> Array[Control]:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	var tools: Array[Control] = []
	for row: Control in [toolbar._header_row, toolbar._header_upper_row]:
		if not row.is_visible_in_tree():
			continue
		for child: Control in row.get_children():
			if not child.visible:
				continue
			if child in [toolbar._header_terrain_size, toolbar._header_elevation_size]:
				for cell: Control in child.get_children():
					tools.append(cell)
			else:
				tools.append(child)
	return tools

## The control the pointer lands on at `at`, by the engine's own hit test.
func _control_under(at: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion)
	return get_viewport().gui_get_hovered_control()

## A real left click at `at`, through the viewport.
func _click_at(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)
		await process_frames(1)
	await process_frames(1)

func test_every_phone_size_keeps_primary_controls_reachable_and_non_overlapping() -> void:
	for dimensions in SIZES:
		await set_window(dimensions)
		var dock: BottomControlDock = main.left_controls
		var menu: Control = main.portrait_hud.get_node("ClubhouseLedger/MenuBtn")
		var sections := dock.section_buttons
		assert_almost_eq(sections[0].get_global_rect().position.x, Screen.safe_insets.x + 8.0, 0.5, "Navigation starts at the safe left edge")
		assert_almost_eq(sections[2].get_global_rect().end.x, Screen.window_size.x - Screen.safe_insets.z - 8.0, 0.5, "Navigation fills the safe width")
		for section in sections:
			assert_almost_eq(section.size.x, sections[0].size.x, 0.5, "Navigation tabs share the width equally")
			assert_true(section._has_point(Vector2(2, section.size.y * 0.5)), "The full tab is a touch target")
		var buttons: Array = dock.section_buttons.duplicate()
		buttons.append_array([menu, main.pause_btn, main.speed_btn])
		for i in buttons.size():
			var button: Control = buttons[i]
			assert_true(rect_within(button.get_global_rect(), _view()), "%s: %s stays on screen" % [dimensions, button.accessibility_name])
			assert_gte(button.size.x, 44.0, "Every thumb destination has a 44px target")
			assert_gte(button.size.y, 44.0, "Every thumb destination has a 44px target")
			for j in range(i + 1, buttons.size()):
				assert_false(button.get_global_rect().intersects(buttons[j].get_global_rect()), "Thumb targets do not overlap")
		assert_eq(menu.get_parent(), main.portrait_hud.get_node("ClubhouseLedger"), "Menu lives in the portrait header")
		assert_almost_eq(menu.position.x, Screen.safe_insets.x + 8.0, 0.5, "Menu owns the top-left corner")
		assert_almost_eq(menu.position.y, Screen.safe_insets.y + 6.0, 0.5, "Menu clears the top safe area")
		assert_gte(main.course_location_banner.get_global_rect().position.x, menu.get_global_rect().end.x + 4.0, "The course identity strip does not cover Menu")
		assert_eq(main.speed_controls.get_parent(), main.portrait_hud.get_node("ClubhouseLedger"), "Time controls live in the header")
		assert_almost_eq(main.speed_btn.get_global_rect().end.x, Screen.window_size.x - Screen.safe_insets.z - 8.0, 0.5, "Speed owns the top-right corner")
		assert_almost_eq(main.pause_btn.get_global_rect().position.y, Screen.safe_insets.y + 6.0, 0.5, "Time controls clear the top safe area")
		assert_lte(main.course_location_banner.get_global_rect().end.x, main.pause_btn.get_global_rect().position.x - 4.0, "The banner clears the time controls")
		assert_gte(main.scores_dock.offset_top, Screen.portrait_header_height(), "Score cards start below the portrait ledger")
		assert_true(rect_within(main.hud_status_column.get_global_rect(), _view()), "%s: ledger %s" % [dimensions, main.hud_status_column.get_global_rect()])
		assert_false(main.hud_status_column.get_global_rect().intersects(main.course_location_banner.get_global_rect()), "%s: banner %s ledger %s" % [dimensions, main.course_location_banner.get_global_rect(), main.hud_status_column.get_global_rect()])
		assert_false(main.bottom_bar.visible, "The desktop fan is not also rendered")
		assert_true(rect_within(main.portrait_hud.get_node("CameraRail").get_global_rect(), Screen.portrait_course_rect().grow(1.0)), "Camera controls stay in the course region")

func test_sections_toggle_a_full_width_tray_and_keep_all_tabs_reachable() -> void:
	await set_window(Vector2i(320, 568))
	for section in TerrainToolbar.SECTION_TABS:
		await click(main.left_controls.section_buttons[section])
		await process_frames(3)
		assert_true(Screen.portrait_tools_open, "A section opens the tray")
		assert_eq(main.terrain_toolbar.current_section, section)
		assert_almost_eq(main.terrain_toolbar.size.x, 320.0, 1.0, "The tray uses the full phone width")
		for tab in TerrainToolbar.SECTION_TABS[section]:
			await click(main.terrain_toolbar._tab_buttons[tab])
			await process_frames(2)
			assert_eq(main.terrain_toolbar.current_tab, tab)
			assert_true(rect_within(main.terrain_toolbar._tab_buttons[tab].get_global_rect(), _view()), "Every page tab is reachable")
		assert_true(rect_within(main.terrain_toolbar.get_global_rect(), _view()), "The whole tray fits")
	await click(main.left_controls.section_buttons[TerrainToolbar.Section.GOLFERS])
	assert_false(Screen.portrait_tools_open, "Tapping the active section puts the tray away")
	assert_null(main.portrait_hud.get_node_or_null("OpenToolsButton"), "No redundant open-tools button remains")
	assert_eq(Screen.bottom_bar_height(), Screen.portrait_nav_height(), "The collapsed tray leaves space for the course")
	await click(main.left_controls.section_buttons[TerrainToolbar.Section.GOLFERS])
	assert_true(Screen.portrait_tools_open, "The section button reopens the tray")
	await click(main.left_controls.section_buttons[TerrainToolbar.Section.GOLFERS])
	assert_gt(Screen.portrait_course_rect().size.y, 250.0, "The smallest phone gets its course view back")

## The shelf's page tabs (Terrain, Club and the rest) are full-width touch
## tabs like the section buttons under the tray: the row runs between the same
## margins, and every tab is one rectangle of target with its caption inside.
func test_page_tabs_fill_the_tray_width_on_every_phone() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	for dimensions in SIZES:
		await set_window(dimensions)
		for section in TerrainToolbar.SECTION_TABS:
			toolbar.select_section(section)
			await process_frames(3)
			var where := "%s, %s" % [dimensions, TerrainToolbar.SECTION_TITLES[section]]
			assert_true(Screen.portrait_tools_open, "%s: the tray is open" % where)
			var tray := toolbar.get_global_rect()
			var tabs := _shown_tabs()
			assert_eq(tabs.size(), TerrainToolbar.SECTION_TABS[section].size(), "%s shows every tab" % where)
			assert_almost_eq(tabs[0].get_global_rect().position.x, Screen.safe_insets.x + 8.0, 0.5, "%s: page tabs start at the safe left edge" % where)
			assert_almost_eq(tabs[-1].get_global_rect().end.x, Screen.window_size.x - Screen.safe_insets.z - 8.0, 0.5, "%s: page tabs fill the safe width" % where)
			for i in tabs.size():
				var tab := tabs[i]
				var rect := tab.get_global_rect()
				assert_true(tab.wide_face, "%s: %s is a full-width tab" % [where, tab.caption])
				assert_almost_eq(rect.size.x, tabs[0].size.x, 1.0, "%s: page tabs share the width equally" % where)
				assert_gt(rect.size.x, rect.size.y, "%s: %s is wider than it is tall" % [where, tab.caption])
				assert_gte(rect.size.y, 44.0, "%s: %s is a 44px target" % [where, tab.caption])
				assert_true(tab._has_point(Vector2(2, rect.size.y * 0.5)), "%s: the full tab is a touch target" % where)
				assert_true(tray.encloses(rect), "%s: %s stays inside the tray" % [where, tab.caption])
				assert_true(tab.is_stacked(), "%s: %s wears its caption under its icon" % [where, tab.caption])
				var face := Rect2(Vector2.ZERO, rect.size).grow(-2.0)
				assert_true(face.encloses(tab.stacked_icon_rect()), "%s: the %s icon fits its tab" % [where, tab.caption])
				assert_true(face.encloses(tab.stacked_caption_rect()), "%s: the %s caption fits its tab" % [where, tab.caption])
				assert_almost_eq(tab.stacked_caption_rect().size.x, PixelCircleButton.FONT.get_string_size(tab.caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 0.01, "%s: %s is not trimmed" % [where, tab.caption])
				for j in range(i + 1, tabs.size()):
					assert_false(rect.intersects(tabs[j].get_global_rect()), "%s: page tabs do not overlap" % where)
			# The tabs clear the heading and the catalogue below them; the
			# tool buttons are out of the tray altogether, above its top.
			var row_end: float = tabs[0].get_global_rect().end.y
			assert_true(toolbar._page_title.visible, "%s: the page keeps its heading" % where)
			assert_gte(toolbar._page_title.get_global_rect().position.y, row_end, "%s: the tabs clear the heading" % where)
			assert_gte(toolbar._pages_container.get_global_rect().position.y, row_end, "%s: the tabs clear the catalogue" % where)
			for tool in _shown_tools():
				assert_lte(tool.get_global_rect().end.y, tray.position.y, "%s: %s stands above the tab row" % [where, tool.name])
			if tabs.size() == main.left_controls.section_buttons.size():
				for i in tabs.size():
					var below: Rect2 = main.left_controls.section_buttons[i].get_global_rect()
					assert_almost_eq(tabs[i].get_global_rect().position.x, below.position.x, 0.5, "%s: %s stands over its section button" % [where, tabs[i].caption])
					assert_almost_eq(tabs[i].get_global_rect().end.x, below.end.x, 0.5, "%s: %s is as wide as its section button" % [where, tabs[i].caption])

func test_a_tap_anywhere_on_a_page_tab_opens_its_page() -> void:
	# The corners are the part a round medallion never answered to.
	var toolbar: TerrainToolbar = main.terrain_toolbar
	await set_window(Vector2i(320, 568))
	for section in TerrainToolbar.SECTION_TABS:
		toolbar.select_section(section)
		await process_frames(3)
		for corner: Vector2 in [Vector2(3, 3), Vector2(-3, -3)]:
			for tab in TerrainToolbar.SECTION_TABS[section]:
				var others: Array = TerrainToolbar.SECTION_TABS[section].filter(func(other): return other != tab)
				toolbar.select_tab(others[0])
				await process_frames(2)
				var rect: Rect2 = toolbar._tab_buttons[tab].get_global_rect()
				var at: Vector2 = rect.position + corner if corner.x > 0.0 else rect.end + corner
				assert_true(bool(TouchInput._touch_target_at(at)["over_ui"]), "Touch sees the %s tab's corner as UI" % TerrainToolbar.TAB_TITLES[tab])
				await _click_at(at)
				assert_eq(toolbar.current_tab, tab, "A tap in the corner of %s opens it" % TerrainToolbar.TAB_TITLES[tab])
				assert_true(toolbar._tab_buttons[tab].button_pressed, "and lights its tab")

func test_page_tabs_respect_the_side_cutouts_and_tournament_mode() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	await set_window(Vector2i(390, 844))
	toolbar.select_section(TerrainToolbar.Section.BUILD)
	await process_frames(3)
	var saved := Screen.safe_insets
	Screen.safe_insets = Vector4(12, 44, 20, 34)
	Screen.changed.emit(Screen.window_size, Screen.world_scale)
	await process_frames(3)
	var tabs := _shown_tabs()
	assert_almost_eq(tabs[0].get_global_rect().position.x, 12.0 + 8.0, 0.5, "Page tabs clear the left cutout")
	assert_almost_eq(tabs[-1].get_global_rect().end.x, 390.0 - 20.0 - 8.0, 0.5, "Page tabs clear the right cutout")
	for tab in tabs:
		assert_almost_eq(tab.size.x, tabs[0].size.x, 1.0, "and still share the safe width equally")
	Screen.safe_insets = saved
	Screen.changed.emit(Screen.window_size, Screen.world_scale)
	await process_frames(3)
	# Tournament Mode hides Edit and Skills: the two tabs left take the row.
	var was_tournament := GameManager.is_tournament_mode
	GameManager.is_tournament_mode = true
	toolbar.select_tab(TerrainToolbar.Tab.PLAYER)
	await process_frames(3)
	tabs = _shown_tabs()
	assert_eq(tabs.size(), 2, "Tournament Mode shows two Golfers tabs")
	assert_almost_eq(tabs[0].get_global_rect().position.x, 8.0, 0.5, "The two tabs start at the left margin")
	assert_almost_eq(tabs[1].get_global_rect().end.x, 390.0 - 8.0, 0.5, "and fill the tray between them")
	assert_almost_eq(tabs[0].size.x, tabs[1].size.x, 1.0, "half each")
	GameManager.is_tournament_mode = was_tournament
	toolbar.select_tab(TerrainToolbar.Tab.PLAYER)
	await process_frames(3)
	assert_eq(_shown_tabs().size(), 4, "A career gets all four Golfers tabs back")

func test_brush_controls_and_horizontal_catalogue_do_not_move_the_camera() -> void:
	# The camera only answers a finger on a course, never behind the main menu.
	var mode := GameManager.current_mode
	GameManager.set_mode(GameManager.GameMode.BUILDING)
	await set_window(Vector2i(360, 640))
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(4)
	var toolbar: TerrainToolbar = main.terrain_toolbar
	for control in [toolbar._header_terrain_shape, toolbar._header_terrain_size, toolbar.inspect_button()]:
		assert_true(rect_within(control.get_global_rect(), Screen.portrait_course_rect()), "Tool controls float over the course view")
		assert_lte(control.get_global_rect().end.y, toolbar.get_global_rect().position.y, "above the tray, not inside it")
		assert_gte(control.size.y, 44.0, "Brush and inspect controls are touch sized")
	var scroll := toolbar.page_scroll(TerrainToolbar.Tab.TERRAIN)
	assert_gt(scroll.get_h_scroll_bar().max_value, scroll.get_h_scroll_bar().page, "The catalogue can scroll")
	var before: Vector2 = main.camera._target_position
	var start := scroll.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = start if pressed else start - Vector2(80, 0)
		get_viewport().push_input(touch, true)
		if pressed:
			var drag_event := InputEventScreenDrag.new()
			drag_event.index = 0
			drag_event.position = start - Vector2(80, 0)
			get_viewport().push_input(drag_event, true)
	await process_frames(3)
	assert_gt(scroll.scroll_horizontal, 0, "A finger scrolls the catalogue")
	assert_eq(main.camera._target_position, before, "Scrolling tools never pans or paints the course")
	# The tools float over the course. A finger that lands on one and slides
	# away across the course is still a touch on the HUD.
	var bare := Screen.portrait_course_rect().position + Vector2(100, 60)
	assert_false(bool(TouchInput._touch_target_at(bare)["over_ui"]), "The slides below end on the bare course")
	for control: Control in [toolbar.inspect_button(), toolbar._header_terrain_size.get_child(1), main.portrait_hud.get_node("CameraRail/ZoomIn")]:
		await _slide(control.get_global_rect().get_center(), bare)
		assert_eq(main.camera._target_position, before, "A slide that starts on %s does not pan the course" % control.name)
	# The same slide between two points of the bare course does pan it.
	await _slide(bare + Vector2(60, 0), bare)
	assert_ne(main.camera._target_position, before, "while a slide across the bare course still pans it")
	GameManager.set_mode(mode)

## One finger lands at `from`, slides to `to` and lifts.
func _slide(from: Vector2, to: Vector2) -> void:
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = from if pressed else to
		get_viewport().push_input(touch, true)
		if pressed:
			var drag_event := InputEventScreenDrag.new()
			drag_event.index = 0
			drag_event.position = to
			get_viewport().push_input(drag_event, true)
	await process_frames(2)

## The brush shape, the brush size stepper, the Bulldozer and Inspect float over
## the course above the tray's right-hand corner, level with the camera rail in
## the left-hand one. Where a whole brush does not fit beside the rail its size
## stepper stands on a second row; either way nothing in the HUD covers a tool.
func test_tool_buttons_float_above_the_tray_beside_the_camera_rail_on_every_phone() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	var rail: Control = main.portrait_hud.get_node("CameraRail")
	for dimensions in SIZES:
		await set_window(dimensions)
		for tab: int in TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.BUILD]:
			toolbar.select_tab(tab)
			await process_frames(3)
			var where := "%s, %s" % [dimensions, TerrainToolbar.TAB_TITLES[tab]]
			var tray := toolbar.get_global_rect()
			var course := Screen.portrait_course_rect()
			var rail_rect := rail.get_global_rect()
			var tools := _shown_tools()
			var is_brush: bool = tab in [TerrainToolbar.Tab.TERRAIN, TerrainToolbar.Tab.ELEVATION]
			var stacked: bool = dimensions.x < 470
			assert_eq(tools.size(), 5 if is_brush else 2, "%s shows its tools: %s" % [where, tools])
			assert_eq(toolbar._header_upper_row.visible, is_brush and stacked, "%s: the stepper takes a second row only where the brush cannot fit beside the rail" % where)
			for i in tools.size():
				var tool := tools[i]
				var rect := tool.get_global_rect()
				assert_true(rect_within(rect, course, 0.0), "%s: %s %s floats over the course view %s" % [where, tool.name, rect, course])
				assert_lte(rect.end.y, tray.position.y - TerrainToolbar.PORTRAIT_TOOLS_LIFT, "%s: %s stands above the tray" % [where, tool.name])
				assert_false(rect.intersects(rail_rect), "%s: %s leaves the camera rail alone" % [where, tool.name])
				assert_gte(minf(rect.size.x, rect.size.y), 44.0, "%s: %s is a 44px target" % [where, tool.name])
				for j in range(i + 1, tools.size()):
					assert_false(rect.intersects(tools[j].get_global_rect()), "%s: tools do not overlap" % where)
				# Nothing is drawn over a tool: the pointer lands on the button
				# itself, or for the size readout on the row that carries it.
				var under := _control_under(rect.get_center())
				if tool is Label:
					assert_eq(under, tool.get_parent().get_parent(), "%s: the size readout belongs to its tool row" % where)
				else:
					assert_eq(under, tool, "%s: %s is on top at %s" % [where, tool.name, rect.get_center()])
			var corner := toolbar.inspect_button().get_global_rect()
			assert_almost_eq(corner.end.x, course.end.x, 0.5, "%s: Inspect sits at the course view's right edge" % where)
			assert_almost_eq(corner.end.y, rail_rect.end.y, 0.5, "%s: level with the camera rail" % where)
			assert_almost_eq(corner.end.y, tray.position.y - TerrainToolbar.PORTRAIT_TOOLS_LIFT, 0.5, "%s: just above the tray" % where)
		# The tools belong to the open tray: putting it away takes them along.
		await click(main.left_controls.section_buttons[TerrainToolbar.Section.BUILD])
		assert_false(Screen.portrait_tools_open, "%s: tapping Build puts the tray away" % dimensions)
		assert_eq(_shown_tools().size(), 0, "%s: no tool is left floating over the course" % dimensions)
		await click(main.left_controls.section_buttons[TerrainToolbar.Section.MANAGE])
		assert_true(Screen.portrait_tools_open, "%s: Manage opens the tray" % dimensions)
		assert_eq(_shown_tools().size(), 0, "%s: Manage has no tools to float" % dimensions)

func test_floating_tool_buttons_answer_real_clicks_and_taps() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	# The narrowest phone stacks the stepper; the widest carries it in the row.
	for dimensions in [Vector2i(320, 568), Vector2i(540, 960)]:
		await set_window(dimensions)
		toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
		await process_frames(3)
		var stepper := toolbar._header_terrain_size
		toolbar.set_brush_size(2)
		await click(stepper.get_child(2))
		assert_eq(toolbar.get_brush_size(), 3, "%s: a click on the bigger-brush button grows the brush" % dimensions)
		await click(stepper.get_child(0))
		assert_eq(toolbar.get_brush_size(), 2, "%s: a click on the smaller-brush button shrinks it" % dimensions)
		await touch_tap(stepper.get_child(2).get_global_rect().get_center())
		assert_eq(toolbar.get_brush_size(), 3, "%s: a finger tap on the bigger-brush button grows it too" % dimensions)
		assert_eq((stepper.get_child(1) as Label).text, "3", "%s: and the readout follows" % dimensions)
		var was_round := toolbar._round_brush
		await click(toolbar._header_terrain_shape)
		assert_ne(toolbar._round_brush, was_round, "%s: a click on the brush shape switches it" % dimensions)
		await touch_tap(toolbar._header_terrain_shape.get_global_rect().get_center())
		assert_eq(toolbar._round_brush, was_round, "%s: and a tap switches it back" % dimensions)
		toolbar.set_brush_size(1)
		await click(toolbar.inspect_button())
		assert_true(main.inspect_mode, "%s: a click on Inspect starts inspecting" % dimensions)
		await touch_tap(toolbar.inspect_button().get_global_rect().get_center())
		assert_false(main.inspect_mode, "%s: and a tap on it stops" % dimensions)

		toolbar.select_tab(TerrainToolbar.Tab.ELEVATION)
		await process_frames(3)
		var elevation_size := toolbar._elevation_size
		await click(toolbar._header_elevation_size.get_child(2))
		assert_gt(toolbar._elevation_size, elevation_size, "%s: the elevation brush grows from its own stepper" % dimensions)
		await click(toolbar._header_elevation_size.get_child(0))
		assert_eq(toolbar._elevation_size, elevation_size, "%s: and shrinks back" % dimensions)

		toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
		await process_frames(3)
		await click(toolbar._bulldozer_button)
		assert_true(main.bulldozer_mode, "%s: a click on the Bulldozer arms it" % dimensions)
		main._cancel_action()
		assert_false(main.bulldozer_mode)

## The tools and the camera rail float over ground the brush can paint. A tap
## that misses a button by a pixel (the gap between two of them, the size
## readout) is still a tap on the HUD: it must not paint the tile underneath.
func test_taps_on_and_between_the_floating_controls_never_paint_the_course() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	var rail: Control = main.portrait_hud.get_node("CameraRail")
	var mode := GameManager.current_mode
	GameManager.set_mode(GameManager.GameMode.BUILDING)
	for dimensions in [Vector2i(320, 568), Vector2i(540, 960)]:
		await set_window(dimensions)
		toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
		await process_frames(3)
		main.camera.focus_on(main.terrain_grid.grid_to_screen_center(Vector2i(64, 64)), true)
		main.camera.force_update_scroll()
		main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
		await process_frames(2)
		main.undo_manager.clear()
		# The bare course does take the brush, so the taps below have a tile to miss.
		await _click_at(Screen.portrait_course_rect().position + Vector2(100, 60))
		assert_eq(main.undo_manager.undo_stack.size(), 1, "%s: a click on the bare course paints" % dimensions)
		var readout: Control = toolbar._header_terrain_size.get_child(1)
		var shape := toolbar._header_terrain_shape.get_global_rect()
		var spots := {
			"the size readout": readout.get_global_rect().get_center(),
			"the gap after the size readout": readout.get_global_rect().get_center() + Vector2(readout.size.x * 0.5 + 1.0, 0.0),
			"the gap after the brush shape": shape.get_center() + Vector2(shape.size.x * 0.5 + 1.0, 0.0),
			"the gap between two camera actions": rail.get_node("RotateLeft").get_global_rect().get_center() + Vector2(PortraitHUD.CAMERA_ACTION_SIZE * 0.5 + 2.0, 0.0),
		}
		for spot: String in spots:
			var at: Vector2 = spots[spot]
			for tool in _shown_tools() + rail.get_children():
				if not tool is Label:
					assert_false((tool as Control).get_global_rect().has_point(at), "%s: %s is not on a button" % [dimensions, spot])
			assert_true(bool(TouchInput._touch_target_at(at)["over_ui"]), "%s: touch sees %s as HUD" % [dimensions, spot])
			await _click_at(at)
			assert_eq(main.undo_manager.undo_stack.size(), 1, "%s: a click on %s does not paint" % [dimensions, spot])
			await touch_tap(at)
			assert_eq(main.undo_manager.undo_stack.size(), 1, "%s: nor does a finger tap there" % dimensions)
			assert_false(main.is_painting, "%s: and no stroke is left open" % dimensions)
		assert_eq(main.current_tool, TerrainTypes.Type.FAIRWAY, "%s: the brush stays armed throughout" % dimensions)
		main._perform_undo()
		main._cancel_action()
	main.undo_manager.clear()
	GameManager.set_mode(mode)

func test_rotation_restores_the_original_desktop_controls_and_signals() -> void:
	await set_window(Vector2i(390, 844))
	var funds: Control = main.hud_status_column.get_node("PortraitLedger/PrimaryStats/FundsRow")
	await click(main.left_controls.section_buttons[TerrainToolbar.Section.MANAGE])
	await process_frames(2)
	await click(main.pause_btn)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.PAUSED, "The moved pause button pauses simulation")
	await click(main.speed_btn)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.NORMAL, "The moved speed button resumes simulation")
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await set_window(Vector2i(1600, 1000))
	assert_false(Screen.uses_portrait_hud())
	assert_eq(main.left_controls.get_parent(), main.bottom_bar, "The original dock returns")
	assert_eq(main.terrain_toolbar.get_parent(), main.bottom_bar, "The original shelf returns")
	assert_eq(main.bottom_bar.get_child(0), main.left_controls, "Desktop ordering is restored")
	assert_true(main.terrain_toolbar._backdrop.visible, "The desktop fairway returns")
	assert_false(main.left_controls.section_buttons[0].wide_face, "Desktop sections return to circular medallions")
	for tab_button: PixelCircleButton in main.terrain_toolbar._tab_buttons.values():
		assert_false(tab_button.wide_face, "Desktop page tabs return to circular medallions")
		assert_eq(tab_button.size, Vector2.ONE * TerrainToolbar.TAB_DIAMETER, "at the curved rail's one diameter")
		assert_eq(tab_button.caption, "", "and without their portrait captions")
	var shelf_row: Control = main.terrain_toolbar._header_row
	assert_eq(shelf_row.get_children(), [main.terrain_toolbar._header_terrain_shape, main.terrain_toolbar._header_terrain_size,
		main.terrain_toolbar._bulldozer_button, main.terrain_toolbar._header_elevation_shape,
		main.terrain_toolbar._header_elevation_size, main.terrain_toolbar.inspect_button()],
		"The stacked brush steppers return to the shelf's tool row, each after its brush shape")
	assert_false(main.terrain_toolbar._header_upper_row.visible, "The portrait stepper row is put away")
	assert_eq(shelf_row.mouse_filter, Control.MOUSE_FILTER_IGNORE, "The shelf's tool row lets the pointer through between its buttons again")
	assert_true(rect_within(main.terrain_toolbar._header_terrain_size.get_global_rect(), shelf_row.get_global_rect()), "The stepper sits in the row")
	assert_almost_eq(shelf_row.get_global_rect().end.x, main.terrain_toolbar.get_global_rect().end.x - TerrainToolbar.SHELF_PAD_X, 0.5, "The tool row is back in the shelf's top-right corner")
	assert_gt(shelf_row.get_global_rect().end.y, main.terrain_toolbar.get_global_rect().position.y, "straddling the shelf's top border")
	assert_eq(funds.get_parent(), main.hud_status_column.get_node("Column"), "The live funds card returns without duplicate signals")
	assert_true(rect_within(main.pause_btn.get_global_rect(), main.left_controls.get_global_rect()), "Pause returns to the fan")
	assert_true(rect_within(main.speed_btn.get_global_rect(), main.left_controls.get_global_rect()), "Speed returns to the fan")
	var restored_menu: Control = main.left_controls.get_node("MenuBtn")
	assert_eq(restored_menu.get_parent(), main.left_controls, "Menu returns to the desktop dock")
	assert_eq(restored_menu.get_index(), main.portrait_hud._menu_home_index, "Menu restores its original child order")
	await click(main.left_controls.section_buttons[TerrainToolbar.Section.BUILD])
	assert_eq(main.terrain_toolbar.current_section, TerrainToolbar.Section.BUILD)

func test_camera_controls_and_safe_area_are_live() -> void:
	await set_window(Vector2i(390, 844))
	var rail: Control = main.portrait_hud.get_node("CameraRail")
	var actions: Array = rail.get_children().map(func(action: Node) -> String: return str(action.name))
	assert_eq(actions, ["RotateLeft", "RotateRight", "ZoomOut", "ZoomIn"], "The rail turns and zooms the view, and nothing else")
	assert_null(rail.get_node_or_null("OverviewButton"), "There is no minimap button on the rail")
	var course := Screen.portrait_course_rect()
	assert_eq(rail.get_global_rect(), Rect2(course.position.x, course.end.y - PortraitHUD.CAMERA_ACTION_SIZE, PortraitHUD.CAMERA_RAIL_WIDTH, PortraitHUD.CAMERA_ACTION_SIZE), "The rail holds the bottom-left corner of the course view")
	assert_eq(rail.get_combined_minimum_size().x, PortraitHUD.CAMERA_RAIL_WIDTH, "and is exactly as wide as its four actions")
	assert_almost_eq(rail.get_node("ZoomIn").get_global_rect().end.x, rail.get_global_rect().end.x, 0.5, "with no empty slot left where the fifth button was")
	var before: float = main.camera.get_zoom_level()
	await click(rail.get_node("ZoomIn"))
	assert_gt(main.camera.get_zoom_level(), before, "The explicit zoom target changes the real camera")
	var zoomed_in: float = main.camera._target_zoom
	await click(rail.get_node("ZoomOut"))
	assert_lt(main.camera._target_zoom, zoomed_in, "and the zoom-out target takes it back")
	# The phone HUD has no minimap, whatever the desktop preference says.
	var minimap_setting := GameManager.minimap_enabled
	for enabled in [true, false]:
		GameManager.set_minimap_enabled(enabled)
		await process_frames(1)
		assert_false(main.mini_map.visible, "The minimap stays out of the portrait HUD with the setting %s" % ("on" if enabled else "off"))
	GameManager.set_minimap_enabled(true)
	await set_window(DESIGN_WINDOW)
	assert_true(main.mini_map.visible, "Turning the phone brings the desktop minimap back")
	await set_window(Vector2i(390, 844))
	assert_false(main.mini_map.visible, "and upright it is gone again")
	GameManager.set_minimap_enabled(minimap_setting)
	var saved := Screen.safe_insets
	Screen.safe_insets = Vector4(12, 44, 12, 34)
	Screen.changed.emit(Screen.window_size, Screen.world_scale)
	await process_frames(3)
	assert_gte(main.course_location_banner.position.y, 44.0, "The notch does not cover the course identity")
	assert_almost_eq(main.speed_btn.get_global_rect().end.x, 390.0 - 12.0 - 8.0, 0.5, "Time controls clear the right cutout")
	assert_gte(main.pause_btn.get_global_rect().position.y, 44.0, "Time controls clear the notch")
	assert_lte(main.left_controls.section_buttons[0].get_global_rect().end.x, 390.0 - 12.0, "Thumb targets respect the side cutout")
	Screen.safe_insets = saved
	Screen.changed.emit(Screen.window_size, Screen.world_scale)

func test_feed_respects_the_ledger_and_collapsed_dock() -> void:
	await set_window(Vector2i(320, 568))
	main._toggle_event_feed()
	await process_frames(3)
	var rect: Rect2 = main.event_feed_panel.get_global_rect()
	assert_true(rect_within(rect, _view()), "The feed fits the smallest phone")
	assert_gte(rect.position.y, Screen.portrait_header_height(), "The feed starts below the ledger")
	assert_lte(rect.end.y, 568.0 - Screen.bottom_bar_height(), "The feed does not cover the thumb rail")
	main._toggle_event_feed()


func test_menu_opens_the_pause_menu_from_the_top_left_and_restores_to_the_dock() -> void:
	await set_window(Vector2i(390, 844))
	var menu: Control = main.portrait_hud.get_node("ClubhouseLedger/MenuBtn")
	# The GUT runner's own title bar sits in the top-left corner of the test
	# viewport; hide it so this pointer-level click reaches the game's Menu.
	var gut_box := _gut_main_box()
	if gut_box:
		gut_box.hide()
	await process_frames(1)
	await click(menu)
	await process_frames(2)
	if gut_box:
		gut_box.show()
	assert_not_null(main.pause_menu, "The portrait Menu button opens the real pause menu")
	assert_true(main.pause_menu.visible)
	main._toggle_pause_menu()
	await process_frames(2)
	assert_null(main.pause_menu, "Closing the pause menu frees it")
	await set_window(DESIGN_WINDOW)
	var dock_menu: Control = main.left_controls.get_node("MenuBtn")
	await click(dock_menu)
	await process_frames(2)
	assert_not_null(main.pause_menu, "The restored desktop Menu button still opens the pause menu")
	assert_true(main.pause_menu.visible)
	main._toggle_pause_menu()

## The GUT GUI's root panel (ancestor of its TitleBox), if a GUI is present.
func _gut_main_box() -> Control:
	var title := get_tree().root.find_child("TitleBox", true, false) as Control
	if title == null:
		return null
	var title_bar := title.get_parent() as Control
	if title_bar == null:
		return null
	var main_box := title_bar.get_parent() as Control
	if main_box == null:
		return null
	return main_box.get_parent() as Control
