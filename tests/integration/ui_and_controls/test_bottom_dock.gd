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

func test_financial_overview_opens_the_existing_panel() -> void:
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.REVIEW)
	await process_frames(2)
	var cards: Array = main.terrain_toolbar.page_content(TerrainToolbar.Tab.REVIEW).get_children()
	await click(cards[2])
	assert_true(main.financial_panel.visible)
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

func test_utility_circles_and_section_circles_do_not_overlap() -> void:
	var buttons: Array = main.left_controls.section_buttons.duplicate()
	buttons.append_array([main.left_controls.get_node("MenuBtn"), main.feed_btn, main.inspect_btn,
		main.rotate_ccw_btn, main.rotate_cw_btn, main.pause_btn, main.play_btn, main.fast_btn])
	for i in buttons.size():
		var first: Rect2 = buttons[i].get_global_rect()
		assert_eq(first.size.x, first.size.y)
		for j in range(i + 1, buttons.size()):
			var second: Rect2 = buttons[j].get_global_rect()
			assert_gte(first.get_center().distance_to(second.get_center()),
				(first.size.x + second.size.x) * 0.5, "Circle hit targets must not overlap")
