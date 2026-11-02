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
	Screen.set_portrait_map_open(false)

func after_each() -> void:
	Screen.set_portrait_tools_open(false)
	Screen.set_portrait_map_open(false)
	await set_window(DESIGN_WINDOW)
	await super()

func _view() -> Rect2:
	return Rect2(Vector2.ZERO, Screen.window_size)

func test_every_phone_size_keeps_primary_controls_reachable_and_non_overlapping() -> void:
	for dimensions in SIZES:
		await set_window(dimensions)
		var dock: BottomControlDock = main.left_controls
		var menu: Control = main.portrait_hud.get_node("ClubhouseLedger/MenuBtn")
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
	assert_gt(Screen.portrait_course_rect().size.y, 250.0, "The smallest phone gets its course view back")

func test_brush_controls_and_horizontal_catalogue_do_not_move_the_camera() -> void:
	await set_window(Vector2i(360, 640))
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(4)
	var toolbar: TerrainToolbar = main.terrain_toolbar
	for control in [toolbar._header_terrain_shape, toolbar._header_terrain_size, toolbar.inspect_button()]:
		assert_true(rect_within(control.get_global_rect(), toolbar.get_global_rect()), "Pinned tool controls stay inside the tray")
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

func test_rotation_restores_the_original_desktop_controls_and_signals() -> void:
	await set_window(Vector2i(390, 844))
	var funds: Control = main.hud_status_column.get_node("PortraitLedger/PrimaryStats/FundsRow")
	await click(main.left_controls.section_buttons[TerrainToolbar.Section.MANAGE])
	await process_frames(2)
	await click(main.speed_btn)
	assert_ne(GameManager.current_speed, GameManager.GameSpeed.PAUSED, "The moved speed button still drives simulation")
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await set_window(Vector2i(1600, 1000))
	assert_false(Screen.uses_portrait_hud())
	assert_eq(main.left_controls.get_parent(), main.bottom_bar, "The original dock returns")
	assert_eq(main.terrain_toolbar.get_parent(), main.bottom_bar, "The original shelf returns")
	assert_eq(main.bottom_bar.get_child(0), main.left_controls, "Desktop ordering is restored")
	assert_true(main.terrain_toolbar._backdrop.visible, "The desktop fairway returns")
	assert_eq(funds.get_parent(), main.hud_status_column.get_node("Column"), "The live funds card returns without duplicate signals")
	assert_true(rect_within(main.pause_btn.get_global_rect(), main.left_controls.get_global_rect()), "Pause returns to the fan")
	var restored_menu: Control = main.left_controls.get_node("MenuBtn")
	assert_eq(restored_menu.get_parent(), main.left_controls, "Menu returns to the desktop dock")
	assert_eq(restored_menu.get_index(), main.portrait_hud._menu_home_index, "Menu restores its original child order")
	await click(main.left_controls.section_buttons[TerrainToolbar.Section.BUILD])
	assert_eq(main.terrain_toolbar.current_section, TerrainToolbar.Section.BUILD)

func test_overview_camera_controls_and_safe_area_are_live() -> void:
	await set_window(Vector2i(390, 844))
	var rail: Control = main.portrait_hud.get_node("CameraRail")
	await click(rail.get_node("OverviewButton"))
	assert_true(main.mini_map.visible, "Overview is available even when the desktop minimap preference is off")
	assert_true(rect_within(main.mini_map.get_global_rect(), Screen.portrait_course_rect()), "Overview stays inside the course region")
	var before: float = main.camera.get_zoom_level()
	await click(rail.get_node("ZoomIn"))
	assert_gt(main.camera.get_zoom_level(), before, "The explicit zoom target changes the real camera")
	await click(rail.get_node("OverviewButton"))
	assert_false(main.mini_map.visible)
	var saved := Screen.safe_insets
	Screen.safe_insets = Vector4(12, 44, 12, 34)
	Screen.changed.emit(Screen.window_size, Screen.world_scale)
	await process_frames(3)
	assert_gte(main.course_location_banner.position.y, 44.0, "The notch does not cover the course identity")
	assert_lte(main.speed_btn.get_global_rect().end.y, 844.0 - 34.0, "The home indicator does not cover time controls")
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
