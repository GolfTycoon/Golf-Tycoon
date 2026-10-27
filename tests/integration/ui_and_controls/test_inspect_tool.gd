extends MainSceneTest
## The Inspect tool and its new home: a toggle pinned to every Build tab's
## bottom-right corner of the terrain toolbar, in the real HUD (no course is
## generated: the HUD is shown over the empty grid). Menu stays alone in the
## bottom-left stack; the Feed card on the Club tab opens the event feed and
## carries the unread count; the Map button sits in the minimap's corner, off
## its diamond, and follows the minimap. Inspect clears and blocks the other
## tools, Esc and right-click leave it, and hovering a tile shows its details
## without painting, measuring or spending.


var inspector_on_title_screen: bool


func before_all() -> void:
	await super()
	inspector_on_title_screen = main.tile_inspector.visible
	main.main_menu.queue_free()
	main.main_menu = null
	GameManager.set_mode(GameManager.GameMode.BUILDING)
	main._set_gameplay_ui_visible(true)
	await process_frames(1)


func after_each() -> void:
	main._cancel_inspect_mode()
	await super()


func _escape() -> void:
	press_key(KEY_ESCAPE)
	await process_frames(1)


## The pinned toggle a player could click on the tab currently shown. When a
## test has left the toolbar on a Manage or Golfers tab, none is visible, so
## fall back to the stable Course Terrain alias main.gd keeps for the mode —
## programmatic presses work whether or not the page is shown.
func _inspect_toggle() -> InspectButton:
	for btn in main.terrain_toolbar._inspect_buttons:
		if btn.is_visible_in_tree():
			return btn
	return main.inspect_btn


func _set_inspect(enabled: bool) -> void:
	_inspect_toggle().button_pressed = enabled


func test_inspect_left_the_bottom_left_stack_for_the_build_tabs() -> void:
	assert_false(inspector_on_title_screen, "The inspector is hidden on the title screen")
	assert_false(main.tile_inspector.visible, "Showing the HUD does not show the inspector")
	assert_null(main.left_controls.get_node_or_null("FeedBtn"),
		"The Feed button has left the bottom-left stack for the Club tab")
	assert_null(main.left_controls.get_node_or_null("InspectBtn"),
		"The Inspect button has left the bottom-left stack for the Build tabs")
	assert_false(main.left_controls.is_ancestor_of(main.inspect_btn),
		"The tracked Inspect toggle no longer lives in the dock")
	var build_tabs := [TerrainToolbar.Tab.TERRAIN, TerrainToolbar.Tab.IMPROVEMENTS,
		TerrainToolbar.Tab.BUILDINGS, TerrainToolbar.Tab.ELEVATION]
	assert_eq(main.terrain_toolbar._inspect_buttons.size(), build_tabs.size(),
		"One pinned Inspect toggle per Build tab")
	for tab in build_tabs:
		var page: Control = main.terrain_toolbar._pages[tab]
		var found: Array = page.find_children("*", "InspectButton", false, false)
		assert_eq(found.size(), 1,
			"%s page pins exactly one Inspect toggle" % TerrainToolbar.TAB_TITLES[tab])
		assert_true(found[0] is InspectButton and found[0].toggle_mode)
	for tab in [TerrainToolbar.Tab.CLUB, TerrainToolbar.Tab.HOLES, TerrainToolbar.Tab.STAFF,
			TerrainToolbar.Tab.GOLFERS]:
		var other_page: Control = main.terrain_toolbar._pages[tab]
		assert_eq(other_page.find_children("*", "InspectButton", true, false).size(), 0,
			"%s pins no Inspect toggle" % TerrainToolbar.TAB_TITLES[tab])
	# Menu remains the dock's only utility circle, still fitting the bar.
	var menu: Control = main.left_controls.get_node("MenuBtn")
	assert_not_null(menu)
	assert_lte(main.left_controls.size.y, Screen.bottom_bar_height(),
		"The controls fit the responsive bottom bar")


func test_pinned_inspect_toggles_stay_on_screen_and_clear_the_other_corner() -> void:
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for tab in TerrainToolbar.INSPECT_TABS:
		main.terrain_toolbar.select_tab(tab)
		await process_frames(2)
		var toggle := _inspect_toggle()
		assert_not_null(toggle, "%s shows its pinned Inspect toggle" % TerrainToolbar.TAB_TITLES[tab])
		assert_true(rect_within(toggle.get_global_rect(), screen),
			"The Inspect toggle stays on screen on %s" % TerrainToolbar.TAB_TITLES[tab])
		assert_true(rect_within(toggle.get_global_rect(), main.bottom_bar.get_global_rect()),
			"and inside the bottom bar on %s" % TerrainToolbar.TAB_TITLES[tab])
		# The bottom-left corner is already pinned on every Build tab: the
		# Bulldozer on Improvements/Buildings, the brush dock on Course Terrain.
		var page: Control = main.terrain_toolbar._pages[tab]
		var corner := page.find_children("*", "BulldozerButton", false, false)
		if corner.is_empty():
			corner = page.find_children("BrushDock", "", true, false)
		if not corner.is_empty():
			assert_false(toggle.get_global_rect().intersects(corner[0].get_global_rect()),
				"Inspect clears the pinned bottom-left chrome on %s" % TerrainToolbar.TAB_TITLES[tab])


func test_the_club_tab_feed_card_opens_the_feed_and_shows_the_unread_count() -> void:
	assert_false(main.left_controls.is_ancestor_of(main.feed_btn),
		"The Feed button no longer lives in the bottom-left stack")
	assert_true(main.terrain_toolbar.page_content(TerrainToolbar.Tab.CLUB).is_ancestor_of(main.feed_btn),
		"It lives on the Club tab")
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.CLUB)
	main.feed_btn.pressed.emit()
	assert_true(main.event_feed_panel.visible, "The Feed card opens the event feed")
	main.feed_btn.pressed.emit()
	assert_false(main.event_feed_panel.visible, "and closes it")
	main._update_feed_unread(3)
	assert_eq(main.feed_btn.notification_count, 3, "Unread events light the Feed badge")
	assert_string_contains(main.feed_btn.tooltip_text, "3 unread")
	assert_eq(main.terrain_toolbar._tab_buttons[TerrainToolbar.Tab.CLUB].notification_count, 3,
		"and the Club tab button carries the count behind the other Manage tabs")
	assert_eq(main.left_controls.section_buttons[TerrainToolbar.Section.MANAGE].notification_count, 3,
		"and the Manage section button carries it from every other section")
	main._update_feed_unread(0)
	assert_eq(main.feed_btn.notification_count, 0, "and clears with it")
	assert_eq(main.left_controls.section_buttons[TerrainToolbar.Section.MANAGE].notification_count, 0,
		"on every badge it lit")


func test_the_map_button_sits_in_the_minimaps_corner_and_follows_it() -> void:
	var map_btn: Button = main.map_btn
	assert_false(main.left_controls.is_ancestor_of(map_btn), "The Map button left the control stack")
	assert_eq(map_btn.get_parent(), main.mini_map.get_parent(), "for a place beside the minimap")
	assert_not_null(map_btn.icon, "It shows a map icon")
	assert_eq(map_btn.text, "", "rather than a label")
	var map_rect: Rect2 = main.mini_map.get_global_rect()
	var button_rect := map_btn.get_global_rect()
	assert_true(map_rect.encloses(button_rect), "It sits inside the minimap's bounds")
	assert_lte(button_rect.position.x - map_rect.position.x, 4.0, "in the left corner")
	assert_lte(map_rect.end.y - button_rect.end.y, 4.0, "at the bottom")
	var covered: Array = []
	for corner in [button_rect.position, Vector2(button_rect.end.x, button_rect.position.y), button_rect.end,
			Vector2(button_rect.position.x, button_rect.end.y)]:
		if main.mini_map._is_within_map(corner - map_rect.position):
			covered.append(corner)
	assert_eq(covered, [], "The Map button does not cover the minimap's diamond")

	assert_true(map_btn.button_pressed and main.mini_map.visible, "The map starts shown, its button pressed")
	map_btn.button_pressed = false
	assert_false(main.mini_map.visible, "The Map button hides the minimap")
	assert_true(map_btn.is_visible_in_tree(), "and stays on screen itself")
	map_btn.button_pressed = true
	assert_true(main.mini_map.visible, "and shows it again")
	main.mini_map.visible = false
	assert_false(map_btn.button_pressed, "Hiding the minimap (Tab) lets the button up")
	main.mini_map.visible = true
	assert_true(map_btn.button_pressed, "and showing it presses the button again")


func test_inspect_clears_the_tools_and_esc_or_right_click_leave_it() -> void:
	main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
	_set_inspect(true)
	assert_true(main.inspect_mode and main._has_active_tool(), "Inspect toggles on")
	assert_eq(main.current_tool, -1, "and clears the terrain tool")
	assert_false(main.terrain_toolbar.has_selection(), "and the toolbar's selection")
	assert_false(main.placement_preview.terrain_painting_enabled, "and the paint preview")
	main._start_painting()
	assert_false(main.is_painting, "Inspect cannot paint")

	await _escape()
	assert_false(main.inspect_mode or main.terrain_toolbar.is_inspect_active(),
		"Esc deselects Inspect on every pinned toggle")
	assert_null(main.pause_menu, "without opening the menu")

	_set_inspect(true)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	main._unhandled_input(right_click)
	assert_false(main.inspect_mode, "Right-click leaves Inspect")


func test_another_tool_leaves_inspect_and_inspect_cancels_it() -> void:
	for tool in ["terrain", "building", "tree", "decoration", "elevation", "bulldozer"]:
		_set_inspect(true)
		match tool:
			"terrain":
				main._on_tool_selected(TerrainTypes.Type.ROUGH)
			"building":
				main._on_building_type_selected_from_toolbar("snack_bar")
			"tree":
				main._on_tool_selected(TerrainTypes.Type.OAK)
			"decoration":
				main._on_decoration_type_selected_from_toolbar("fountain")
			"elevation":
				main._on_elevation_tool_pressed(ElevationTool.TOOL_VERTEX)
			"bulldozer":
				main._on_bulldozer_pressed()
		assert_false(main.inspect_mode or main.terrain_toolbar.is_inspect_active(),
			"The %s tool leaves Inspect on every pinned toggle" % tool)
		_set_inspect(true)
		assert_true(not main.elevation_tool.is_active() and not main.bulldozer_mode \
			and main.placement_manager.placement_mode == PlacementManager.PlacementMode.NONE,
			"and Inspect cancels the %s tool" % tool)


func test_hovering_shows_tile_details_without_changing_anything() -> void:
	_set_inspect(true)
	main.camera.focus_on(main.terrain_grid.grid_to_screen_center(Vector2i(64, 64)), true)
	main.camera.force_update_scroll()
	var motion := InputEventMouseMotion.new()
	motion.position = get_viewport().get_visible_rect().size * 0.5
	get_viewport().push_input(motion, true)
	await process_frames(1)
	main._update_tile_inspector()
	assert_true(main.tile_inspector.visible, "Hovering the course shows the details")
	var hovered: Vector2i = main.terrain_grid.screen_to_grid(main.camera.get_mouse_world_position())
	assert_eq(main.tile_inspector._title.text, "Inspect • Tile (%d, %d)" % [hovered.x, hovered.y],
		"of the tile under the pointer, through the camera and the terrain projection")

	var money := GameManager.money
	main.terrain_grid.set_tile(hovered, TerrainTypes.Type.BUNKER)
	for modifier in ["none", "shift", "ctrl"]:
		var press := InputEventMouseButton.new()
		press.position = motion.position
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.shift_pressed = modifier == "shift"
		press.ctrl_pressed = modifier == "ctrl"
		get_viewport().push_input(press, true)
		press.pressed = false
		get_viewport().push_input(press, true)
	assert_false(main.is_painting or main._measuring, "Clicks in Inspect neither paint nor measure")
	assert_eq(GameManager.money, money, "nor spend")
	assert_eq(main.terrain_grid.get_tile(hovered), TerrainTypes.Type.BUNKER,
		"and even Shift-click cannot edit terrain while Inspect is active")

	main._on_view_rotate_cw()
	main.camera.force_update_scroll()
	main._update_tile_inspector()
	assert_true(main.inspect_mode and main.tile_inspector.visible, "Inspect survives turning the view")
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	main._update_tile_inspector()
	assert_true(main.tile_inspector.visible, "Pausing the clock still allows inspection")
	# Hover the real, on-screen pinned toggle on the Course Terrain tab.
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(1)
	var hovered_toggle := _inspect_toggle()
	assert_true(hovered_toggle.is_visible_in_tree(), "The pinned toggle is on screen")
	motion.position = hovered_toggle.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	await process_frames(1)
	main._update_tile_inspector()
	assert_false(main.tile_inspector.visible, "Hovering the HUD hides the details")

	main.tile_inspector.show_tile(main.terrain_grid, main.entity_layer, Vector2i(1, 1), Vector2(100, 100))
	GameManager.is_paused = true
	main._update_tile_inspector()
	assert_false(main.tile_inspector.visible, "The pause menu hides the details")
	GameManager.is_paused = false
	_set_inspect(false)
	assert_false(main.inspect_mode or main.tile_inspector.visible, "The button toggles Inspect off")
