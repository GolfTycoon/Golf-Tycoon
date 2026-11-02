extends MainSceneTest
## The game at phone, tablet and desktop window sizes: the responsive adapters —
## Screen, the camera's world scale, the compact HUD, the clamped popup panels,
## the touch gestures and the world map — all follow the live window size.

const WorldMapStateScript := preload("res://scripts/autoload/world_map_state.gd")

class GestureSentinel:
	extends Node
	var mouse_events: Array = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			mouse_events.append(event)


func _push_touch(pressed: bool, position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = position
	get_viewport().push_input(event, true)


func _push_drag(position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	get_viewport().push_input(event, true)


func _view() -> Rect2:
	return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)


## The location list stays readable and clickable: several rows, and the first
## row's Buy & Play / Play button, inside the list's clip and the window. A list panel
## that collapses would still be "on screen" while hiding every row.
func _assert_rows_visible(world_screen: Node, tag: String) -> void:
	var clip: Rect2 = (world_screen._list_box.get_parent() as Control).get_global_rect()
	var shown := 0
	for row in world_screen._list_box.get_children():
		if rect_within(row.get_global_rect(), clip) and rect_within(row.get_global_rect(), _view()):
			shown += 1
	assert_gte(shown, 4, "%s: the list shows at least four location rows" % tag)
	var first_row: Control = world_screen._list_box.get_child(0)
	assert_true(rect_within(first_row.get_global_rect(), _view()), "%s: the first location row is on screen" % tag)
	var buttons := nodes_of_class(first_row, "Button")
	assert_eq(buttons.size(), 1, "%s: a row has one action button" % tag)
	if buttons.size() == 1:
		var rect: Rect2 = buttons[0].get_global_rect()
		assert_true(rect_within(rect, clip) and rect_within(rect, _view()), "%s: the row's button is clickable" % tag)


func test_a_phone_gets_the_compact_hud_and_a_reachable_menu() -> void:
	await set_window(Vector2i(390, 844))
	assert_true(Screen.is_compact(), "A 390x844 window is compact")
	assert_almost_eq(Screen.world_scale, 1.0, 0.001, "The phone world scale is 1:1")
	assert_true(Screen.uses_portrait_hud(), "The phone gets the dedicated portrait HUD")
	assert_almost_eq(main.hud_status_column.custom_minimum_size.x, 374.0, 1.0, "The ledger spans the phone instead of covering a corner")
	assert_false(main.bottom_bar.visible, "The desktop fan makes way for the thumb rail")
	main._set_gameplay_ui_visible(true)
	await process_frames(2)
	assert_true(main.portrait_hud.visible, "The portrait composition is visible on the course")
	main._set_gameplay_ui_visible(false)
	assert_false(main.portrait_hud.visible, "The portrait composition stays hidden behind the title screen")
	assert_eq(main.terrain_toolbar.get_parent(), main.portrait_hud.get_node("ToolTray"), "The live toolbar moves into the full-width tray")
	# The main menu fits, scrollable, with its nine actions in reach.
	var buttons := nodes_of_class(main.main_menu, "Button")
	assert_eq(buttons.size(), 9, "The main menu shows its nine actions on phones")
	for button in buttons:
		var rect: Rect2 = button.get_global_rect()
		assert_true(rect.size.x <= 390.0 and rect.size.y >= 30.0, "%s fits the phone and stays tappable" % button.text)
	# Touch gestures are wired to the live camera.
	assert_eq(TouchInput.camera, main.camera, "TouchInput is wired to the main camera")
	assert_true(TouchInput.paint_mode_provider.is_valid(), "and to the paint mode")


func test_a_rotated_phone_stays_compact_and_reflows() -> void:
	await set_window(Vector2i(844, 390))
	assert_true(Screen.is_compact(), "An 844x390 rotated phone stays compact")
	assert_almost_eq(Screen.world_scale, 1.0, 0.001, "and keeps the 1:1 world scale")
	assert_almost_eq(main.mini_map.offset_bottom, -Screen.bottom_bar_height(), 1.0, "The minimap re-docks above the touch-sized bottom bar")


func test_tablets_and_desktops_scale_the_world_with_the_window() -> void:
	await set_window(Vector2i(1024, 768))
	assert_false(Screen.is_compact(), "A 1024x768 tablet is not compact")
	assert_almost_eq(Screen.world_scale, 0.879, 0.01, "The tablet world scale tracks the reference view")
	assert_eq(main.mini_map.get("_map_size"), 180, "A tablet gets the standard minimap")
	await set_window(Vector2i(1600, 1000))
	assert_false(Screen.is_compact(), "A 1600x1000 desktop is not compact")
	assert_almost_eq(Screen.world_scale, 1.0, 0.001, "The desktop world scale is 1.0")
	assert_almost_eq(main.hud_status_column.custom_minimum_size.x, 210.0, 1.0, "The desktop status column is standard")
	assert_eq(main.mini_map.get("_map_size"), 180, "The desktop minimap is the standard size")
	await set_window(Vector2i(1920, 1080))
	assert_almost_eq(Screen.world_scale, 1.08, 0.01, "A bigger desktop scales the world up to 1.08")
	assert_almost_eq(main.camera.zoom.x, 1.08, 0.05, "and the camera zoom carries it")


func test_financial_overview_fills_the_viewport_and_reflows_at_every_shape() -> void:
	var panel: FinancialPanel = main.financial_panel
	var cases: Array = [
		{"size": Vector2i(1600, 1000), "mode": MenuScreenKit.LayoutMode.DESKTOP},
		{"size": Vector2i(1024, 768), "mode": MenuScreenKit.LayoutMode.TABLET_LANDSCAPE},
		{"size": Vector2i(768, 1024), "mode": MenuScreenKit.LayoutMode.TABLET_PORTRAIT},
		{"size": Vector2i(844, 390), "mode": MenuScreenKit.LayoutMode.PHONE_LANDSCAPE},
		{"size": Vector2i(390, 844), "mode": MenuScreenKit.LayoutMode.PHONE_PORTRAIT},
	]
	panel.show_centered()
	await process_frames(3)
	for entry in cases:
		await set_window(entry["size"])
		var rect := panel.get_global_rect()
		var viewport := Rect2(Vector2.ZERO, Vector2(entry["size"]))
		assert_true(rect_within(rect, viewport), "Financial Overview fits %s" % entry["size"])
		assert_almost_eq(rect.position.x, 0.0, 1.0, "It starts at the left edge")
		assert_almost_eq(rect.position.y, 0.0, 1.0, "It starts at the top edge")
		assert_almost_eq(rect.size.x, float(entry["size"].x), 1.0, "It fills the window width")
		assert_almost_eq(rect.size.y, float(entry["size"].y), 1.0, "It fills the window height")
		assert_eq(panel._layout_mode, entry["mode"], "It selects the appropriate responsive composition")
		assert_not_null(panel.get_node_or_null("FinancialOverviewRoot/Backdrop"), "It uses the World Map backdrop")
		if entry["mode"] == MenuScreenKit.LayoutMode.DESKTOP:
			var desktop_board := panel.get_node_or_null("FinancialOverviewRoot/Frame/Page/DashboardContent")
			assert_not_null(desktop_board, "Desktop gets the financial board")
			if desktop_board:
				assert_eq(desktop_board.get_child_count(), 3, "The desktop board has finance, course and marketing columns")
		else:
			var tabs := panel.get_node_or_null("FinancialOverviewRoot/Frame/Page/SectionTabs")
			assert_not_null(tabs, "Compact layouts get the three-section navigator")
			if tabs:
				assert_eq(tabs.get_child_count(), 3, "Finance, course and marketing each have a page")
				if entry["mode"] == MenuScreenKit.LayoutMode.PHONE_PORTRAIT or entry["mode"] == MenuScreenKit.LayoutMode.PHONE_LANDSCAPE:
					for tab in tabs.get_children():
						assert_gte(tab.size.y, 44.0, "Phone section tabs meet the touch target")
	var marketing_tab: Button = panel.get_node("FinancialOverviewRoot/Frame/Page/SectionTabs/MarketingTab")
	await click(marketing_tab)
	assert_eq(panel.active_section, FinancialOverviewScreen.Section.MARKETING, "The phone section rail opens the Marketing page")
	assert_not_null(panel.find_child("CampaignOffer_0", true, false), "The phone can scroll to every campaign offer")
	panel.hide()
	await set_window(DESIGN_WINDOW)


func test_a_tap_clicks_and_a_drag_pans_the_camera() -> void:
	await set_window(Vector2i(390, 844))
	main.main_menu.queue_free()
	main.main_menu = null
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	await process_frames(3)
	var sentinel: GestureSentinel = add_child_autofree(GestureSentinel.new())
	var tap := Vector2(195, 300)
	_push_touch(true, tap)
	_push_touch(false, tap)
	await process_frames(3)
	var clicked := false
	for event in sentinel.mouse_events:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.position.distance_to(tap) < 1.0:
			clicked = true
	assert_true(clicked, "A tap makes a left click where the finger is")

	var before: Vector2 = main.camera._target_position
	_push_touch(true, Vector2(200, 300))
	_push_drag(Vector2(260, 320))
	_push_drag(Vector2(320, 340))
	_push_touch(false, Vector2(320, 340))
	await process_frames(3)
	var moved: Vector2 = main.camera._target_position - before
	assert_true(absf(moved.x) > 20.0 and absf(moved.y) > 10.0, "A one-finger drag pans the camera (moved %s)" % moved)


func test_touch_drag_scrolls_the_tool_shelf_instead_of_moving_the_course() -> void:
	await set_window(Vector2i(390, 844))
	if main.main_menu:
		main.main_menu.queue_free()
		main.main_menu = null
	main._set_gameplay_ui_visible(true)
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(3)
	assert_true(Screen.portrait_tools_open, "Choosing a tool page opens the portrait tray")
	var scroll: ScrollContainer = main.terrain_toolbar.page_scroll(TerrainToolbar.Tab.TERRAIN)
	assert_gt(scroll.get_h_scroll_bar().max_value, scroll.get_h_scroll_bar().page,
		"The phone-sized terrain shelf has content to scroll")
	var rect := scroll.get_global_rect()
	var start := Vector2(rect.end.x - 20.0, rect.position.y + rect.size.y * 0.5)
	var camera_before: Vector2 = main.camera._target_position
	_push_touch(true, start)
	_push_drag(start - Vector2(90, 0))
	_push_touch(false, start - Vector2(90, 0))
	await process_frames(3)
	assert_gt(scroll.scroll_horizontal, 0, "A left drag scrolls the toolbar shelf")
	assert_eq(main.camera._target_position, camera_before, "The course camera stays still")

func test_the_world_map_fits_every_window() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options())
	await set_window(Vector2i(1600, 1000))
	main._show_world_map_screen(false)
	await process_frames(3)
	var world_screen: Node = main.get_node("UI/HUD/WorldMapScreen")
	assert_true(world_screen.get_node_or_null("Backdrop") is MenuBackdrop,
		"The world map shares the title screen's backdrop")
	assert_true(world_screen.get_node_or_null("Frame/Page/ScreenHeader/FlagMark") is MenuFlagMark,
		"and its golf-flag mark")
	var globe: Rect2 = world_screen.globe.get_global_rect()
	assert_true(_view().encloses(globe), "The desktop globe is wholly on screen")
	assert_eq(world_screen._rows.size(), WorldLocations.get_all().size(), "Every location has a row")
	assert_gt(world_screen._list_box.get_global_rect().position.x, globe.position.x, "The desktop list sits beside the globe")
	_assert_rows_visible(world_screen, "desktop")

	# Tablets: the selected site beside the globe, every destination on a shelf.
	await set_window(Vector2i(1024, 768))
	assert_eq(world_screen._layout_mode, MenuScreenKit.LayoutMode.TABLET_LANDSCAPE, "A landscape tablet gets the tablet atlas")
	assert_true(world_screen._horizontal_directory, "with the swipeable destination shelf")
	assert_true(_view().encloses(world_screen.globe.get_global_rect()), "The tablet globe is wholly on screen")
	assert_true(_view().encloses(world_screen._featured_action.get_global_rect()), "and the selected site's action")
	assert_eq(world_screen._rows.size(), WorldLocations.get_all().size(), "The shelf keeps every destination")
	var first_card: Control = world_screen._rows[WorldLocations.get_all()[0]["id"]]
	assert_true(rect_within(first_card.get_global_rect(), world_screen._directory_scroll.get_global_rect()),
		"The first destination card is visible on the shelf")
	await set_window(Vector2i(768, 1024))
	assert_eq(world_screen._layout_mode, MenuScreenKit.LayoutMode.TABLET_PORTRAIT, "A portrait tablet gets the tall atlas")
	assert_true(_view().encloses(world_screen.globe.get_global_rect()), "The portrait globe is wholly on screen")
	assert_true(_view().encloses(world_screen._featured_action.get_global_rect()), "and the selected site's action")

	# A rotated phone: a compact globe above a touch-sized list.
	await set_window(Vector2i(844, 390))
	globe = world_screen.globe.get_global_rect()
	assert_true(_view().encloses(globe), "The rotated-phone globe is wholly on screen")
	assert_true(globe.size.x <= _view().size.x and globe.position.y > 0.0, "with the list below it")
	_assert_rows_visible(world_screen, "rotated phone")

	# A phone, where the list is likeliest to be squeezed out.
	await set_window(Vector2i(390, 844))
	_assert_rows_visible(world_screen, "phone")
	var target := ""
	for id in world_screen.globe._marker_positions:
		if str(id) != world_screen._selected_id:
			target = str(id)
			break
	if not target.is_empty():
		var marker: Vector2 = world_screen.globe.get_global_transform_with_canvas() \
			* world_screen.globe.get_marker_position(target)
		_push_touch(true, marker)
		_push_touch(false, marker)
		await process_frames(2)
		assert_eq(world_screen._selected_id, target, "A tap on a globe marker selects its destination")
	main._close_world_map()
