extends MainSceneTest
## Pointer-level checks of the curved dock and its persistent section tabs.

func before_all() -> void:
	await super()
	await new_game()

func test_primary_circles_are_ordered_and_open_their_sections() -> void:
	var buttons: Array = main.left_controls.section_buttons
	assert_gt(buttons[0].size.x, buttons[1].size.x)
	assert_gt(buttons[1].size.x, buttons[2].size.x)
	# Start from a hidden shelf: pressing the already-open section hides it.
	main.terrain_toolbar.collapse_section()
	for i in buttons.size():
		await click(buttons[i])
		assert_eq(main.terrain_toolbar.current_section, i)
		for j in buttons.size():
			assert_eq(buttons[j].button_pressed, i == j)
		for tab in TerrainToolbar.SECTION_TABS[i]:
			await click(main.terrain_toolbar._tab_buttons[tab])
			assert_eq(main.terrain_toolbar.current_tab, tab, "Each icon can be clicked")

func test_the_rotate_arrows_left_the_dock_for_the_location_banner() -> void:
	assert_null(main.left_controls.get_node_or_null("RotateViewControls"),
		"The dock no longer carries a view row")
	assert_eq(main.rotate_view_controls.get_parent().get_parent(), main.course_location_banner,
		"The arrows ride on the top-left postcard instead")
	assert_false(main.left_controls.get_global_rect().intersects(
		main.rotate_ccw_btn.get_global_rect()),
		"and stand clear of the bottom bar")

func test_financial_overview_opens_as_a_fullscreen_dashboard() -> void:
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.CLUB)
	await process_frames(2)
	var finance: Button = null
	for node in nodes_of_class(main.terrain_toolbar.page_content(TerrainToolbar.Tab.CLUB), "Button"):
		if node.get("tool_type") == "finance":
			finance = node
			break
	assert_not_null(finance, "The Club tab carries the Financial Overview card")
	await click(finance)
	assert_true(main.financial_panel.visible)
	assert_not_null(main.financial_panel.get_node_or_null("FinancialOverviewRoot/Backdrop"), "The dashboard uses the World Map backdrop")
	assert_not_null(main.financial_panel.get_node_or_null("FinancialOverviewRoot/Frame/Page/DashboardContent"), "The full-screen dashboard content is present")
	main._on_financial_panel_closed()

func test_event_feed_opens_from_the_club_tab() -> void:
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.CLUB)
	await process_frames(2)
	var feed: Button = null
	for node in nodes_of_class(main.terrain_toolbar.page_content(TerrainToolbar.Tab.CLUB), "Button"):
		if node.get("tool_type") == "feed":
			feed = node
			break
	assert_not_null(feed, "The Club tab carries the Feed card")
	assert_eq(feed, main.feed_btn, "and it is the feed button main tracked")
	assert_null(main.left_controls.get_node_or_null("FeedBtn"), "It left the bottom-left stack")
	await click(feed)
	assert_true(main.event_feed_panel.visible, "The Feed card opens the event feed")
	main._toggle_event_feed()

func test_marketing_opens_inside_the_same_financial_overview() -> void:
	main._toggle_marketing_panel()
	await process_frames(3)
	assert_true(main.financial_panel.visible, "Marketing opens the unified dashboard")
	assert_eq(main.financial_panel.active_section, FinancialOverviewScreen.Section.MARKETING)
	assert_null(main.marketing_panel, "There is no second Marketing popup")
	var text := labels_text(main.financial_panel)
	for channel_name in ["Local Newspaper Ads", "Social Media Campaign", "Golf Magazine Feature", "Radio Advertising", "Tournament Promotion"]:
		assert_true(text.contains(channel_name), "%s remains available in Marketing" % channel_name)
	var active_before: int = GameManager.marketing_manager.get_active_campaign_count()
	main.financial_panel._launch_campaign(MarketingManager.Channel.LOCAL_ADS)
	await process_frames(3)
	assert_eq(GameManager.marketing_manager.get_active_campaign_count(), active_before + 1, "A campaign launches from the combined screen")
	assert_true(labels_text(main.financial_panel).contains("Local Newspaper Ads"), "The active campaign is shown after launch")
	main._on_financial_panel_closed()

func test_dock_stays_on_screen_at_desktop_tablet_and_phone_widths() -> void:
	for window_size in [Vector2i(1600, 1000), Vector2i(1024, 768), Vector2i(390, 844), Vector2i(360, 800)]:
		await set_window(window_size)
		var screen := Rect2(Vector2.ZERO, Vector2(window_size))
		for section in TerrainToolbar.SECTION_TABS:
			for tab in TerrainToolbar.SECTION_TABS[section]:
				main.terrain_toolbar.select_tab(tab)
				await process_frames(2)
				assert_true(rect_within(main.bottom_bar.get_global_rect(), screen), "Bar stays on screen: %s, tab %s" % [window_size, tab])
				for button in main.left_controls.section_buttons:
					assert_eq(button.size.x, button.size.y)
					assert_true(rect_within(button.get_global_rect(), screen))
				assert_true(rect_within(main.terrain_toolbar._tab_buttons[tab].get_global_rect(), screen))
	await set_window(DESIGN_WINDOW)

func test_touch_layout_enlarges_targets_and_keeps_the_dock_on_screen() -> void:
	for window_size in [Vector2i(390, 844), Vector2i(360, 800), Vector2i(844, 390)]:
		await set_window(window_size)
		assert_true(Screen.uses_touch_layout(), "%s gets the touch layout" % window_size)
		assert_eq(main.left_controls.size.y, Screen.bottom_bar_height(), "The dock uses the expanded touch height")
		# The Rotate arrows left the dock for the top-left location banner.
		var utility_buttons: Array = [main.left_controls.get_node("MenuBtn"),
			main.pause_btn, main.speed_btn]
		for button in utility_buttons:
			assert_gte(button.size.x, float(UIConstants.TOUCH_TARGET_SIZE),
				"%s meets the minimum touch target" % button.accessibility_name)
		# Inspect left the dock for the toolbar's header row; the shared toggle
		# keeps a fixed footprint that still clears the touch minimum.
		assert_null(main.left_controls.get_node_or_null("InspectBtn"),
			"Inspect no longer occupies the dock's utility row")
		var inspect: InspectButton = main.terrain_toolbar.inspect_button()
		assert_not_null(inspect, "The header row holds the Inspect toggle")
		assert_gte(inspect.size.x, float(UIConstants.TOUCH_TARGET_SIZE),
			"%s meets the minimum touch target" % inspect.accessibility_name)
		if inspect.is_visible_in_tree():
			assert_true(rect_within(inspect.get_global_rect(),
				Rect2(Vector2.ZERO, Vector2(window_size))),
				"The Inspect toggle stays on screen")
		for button in main.terrain_toolbar._tab_buttons.values():
			assert_gte(button.size.x, 40.0, "Toolbar tabs also grow for touch")

		var all_circles: Array = main.left_controls.section_buttons.duplicate()
		all_circles.append_array(utility_buttons)
		for i in all_circles.size():
			var first: Rect2 = all_circles[i].get_global_rect()
			assert_true(rect_within(first, Rect2(Vector2.ZERO, Vector2(window_size))),
				"Touch target %s stays on the screen" % all_circles[i].accessibility_name)
			for j in range(i + 1, all_circles.size()):
				var second: Rect2 = all_circles[j].get_global_rect()
				assert_gte(first.get_center().distance_to(second.get_center()),
					(first.size.x + second.size.x) * 0.5,
					"Touch targets %s and %s do not overlap" % [all_circles[i].accessibility_name, all_circles[j].accessibility_name])
	await set_window(DESIGN_WINDOW)

func test_utility_cluster_fills_the_pocket_and_reflows_back_to_desktop() -> void:
	# Finish at desktop to catch stale sizes or positions after growing for touch.
	for window_size in [DESIGN_WINDOW, Vector2i(390, 844), Vector2i(844, 390), DESIGN_WINDOW]:
		await set_window(window_size)
		var dock: BottomControlDock = main.left_controls
		var menu: PixelCircleButton = dock.get_node("MenuBtn")
		var diameter := BottomControlDock.TOUCH_UTILITY_SIZE if Screen.uses_touch_layout() else BottomControlDock.DESKTOP_UTILITY_SIZE
		var utilities: Array = [menu, main.pause_btn, main.speed_btn]
		for i in utilities.size():
			var button: PixelCircleButton = utilities[i]
			var expected_size := diameter - i * BottomControlDock.UTILITY_SIZE_STEP
			assert_eq(button.size, Vector2.ONE * expected_size, "Utility circles taper along the arc")
			assert_eq(button.diameter, expected_size, "Drawing and hit target use the same diameter")
			assert_true(dock.get_global_rect().encloses(button.get_global_rect()),
				"Every utility stays inside the dock")
		var pause_rect: Rect2 = main.pause_btn.get_global_rect()
		var play_rect: Rect2 = main.speed_btn.get_global_rect()
		var menu_center := menu.get_global_rect().get_center()
		var pause_center := pause_rect.get_center()
		var play_center := play_rect.get_center()
		assert_lt(menu_center.x, pause_center.x, "Menu starts the arc at the left")
		assert_lt(pause_center.x, play_center.x, "Play finishes the arc at the right")
		assert_lt(menu_center.y, pause_center.y, "The arc descends from Menu to Pause")
		assert_lt(pause_center.y, play_center.y, "The arc descends from Pause to Play")
		assert_gt(play_center.y - pause_center.y, pause_center.y - menu_center.y,
			"The arc bends down more steeply toward Play, like the section buttons")
		assert_almost_eq(play_rect.end.y, dock.get_global_rect().end.y - BottomControlDock.UTILITY_BOTTOM, 0.5,
			"Play anchors the end of the arc to the foot of the dock")
		var buttons: Array = dock.section_buttons.duplicate()
		buttons.append_array(utilities)
		for i in buttons.size():
			var first: Rect2 = buttons[i].get_global_rect()
			for j in range(i + 1, buttons.size()):
				var second: Rect2 = buttons[j].get_global_rect()
				assert_gte(first.get_center().distance_to(second.get_center()),
					(first.size.x + second.size.x) * 0.5,
					"The enlarged circles never overlap adjacent controls")

func test_the_corner_wears_an_arc_backdrop_in_the_open_sections_colour() -> void:
	var dock: BottomControlDock = main.left_controls
	var backdrop := dock.get_node_or_null("ArcBackdrop") as DockArcBackdrop
	assert_not_null(backdrop, "The corner is backed by the arc fan, not the bar's rectangle")
	assert_eq(backdrop.get_index(), 0, "It paints behind every medallion")
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"Clicks above the fan's rim reach the course")
	assert_true(backdrop.get_global_rect().is_equal_approx(dock.get_global_rect()),
		"The fan's canvas is the dock itself, so it hugs the live layout")

	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.CLUB)
	await process_frames(2)
	assert_eq(main.terrain_toolbar.current_section, TerrainToolbar.Section.MANAGE)
	assert_eq(backdrop.accent, TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.MANAGE],
		"The rim trim takes the open section's colour")
	main.terrain_toolbar.collapse_section()
	await process_frames(2)
	assert_eq(backdrop.accent, DockArcBackdrop.FALLBACK_ACCENT,
		"A hidden shelf drops the trim to the bar's sage")

	# The shelf paints its own mirrored rim instead of placing a rectangular bar
	# behind either the shelf's cutout or the left fan.
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(2)
	assert_null(main.get_node_or_null("UI/HUD/BottomBarBG"), "no opaque rectangle remains")
	var shelf_backdrop: ShelfFanBackdrop = main.terrain_toolbar._backdrop
	assert_true(shelf_backdrop.get_global_rect().is_equal_approx(main.terrain_toolbar.get_global_rect()))
	assert_eq(shelf_backdrop.accent, TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.BUILD])

func test_utility_circles_and_section_circles_do_not_overlap() -> void:
	var buttons: Array = main.left_controls.section_buttons.duplicate()
	buttons.append_array([main.left_controls.get_node("MenuBtn"),
		main.pause_btn, main.speed_btn])
	for i in buttons.size():
		var first: Rect2 = buttons[i].get_global_rect()
		assert_eq(first.size.x, first.size.y)
		for j in range(i + 1, buttons.size()):
			var second: Rect2 = buttons[j].get_global_rect()
			assert_gte(first.get_center().distance_to(second.get_center()),
				(first.size.x + second.size.x) * 0.5, "Circle hit targets must not overlap")
