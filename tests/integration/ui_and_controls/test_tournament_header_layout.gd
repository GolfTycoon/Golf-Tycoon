extends MainSceneTest
## The tournament uses the same responsive chrome without losing its actions.

func test_shared_tournament_header_fits_each_layout() -> void:
	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	main.get_node("UI/HUD").add_child(screen)
	for size in [Vector2i(1600, 1000), Vector2i(768, 1024),
			Vector2i(844, 390), Vector2i(640, 360), Vector2i(390, 844)]:
		await set_window(size)
		await get_tree().create_timer(StartTournamentScreen.SETTLE_DELAY + 0.15).timeout
		await process_frames(3)
		var header := screen.find_child("ScreenHeader", true, false) as HBoxContainer
		assert_not_null(header, "%s: shared header is present" % size)
		var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		var title := header.get_node("TitleBlock/Title") as Label
		var icon := header.get_node("ScreenIcon") as TextureRect
		assert_eq(title.text, "Start Tournament")
		assert_gt(title.size.x, 0.0, "%s: title has visible width" % size)
		assert_true(rect_within(header.get_global_rect(), view), "%s: header fits" % size)
		assert_true(rect_within(screen._back_button.get_global_rect(), view), "%s: Back fits" % size)
		assert_true(rect_within(icon.get_global_rect(), view), "%s: icon fits" % size)
		if screen._layout_mode == StartTournamentScreen.Layout.LANDSCAPE:
			assert_eq(header.get_node("StartTournamentButton"), screen._start_button,
				"%s: the header keeps the named Start button" % size)
			assert_true(rect_within(screen._start_button.get_global_rect(), view), "%s: Start fits" % size)
