extends GameTest
## The game-over card on small windows.
##
## It used to be a fixed 450px card with no scroll region, so on a phone it
## hung over the right edge and on a phone held sideways its lowest option —
## Quit to Menu — sat below the bottom of the screen where no tap could reach
## it. The legacy now scrolls and the three options stay pinned on screen.

const PHONE_LANDSCAPE := Vector2i(844, 390)
const SMALL_LANDSCAPE := Vector2i(640, 360)
const PHONE_PORTRAIT := Vector2i(390, 844)

func _panel() -> GameOverPanel:
	var panel := autofree(GameOverPanel.new()) as GameOverPanel
	add_child(panel)
	return panel

func _inside_view(rect: Rect2, size: Vector2i) -> bool:
	return Rect2(Vector2.ZERO, Vector2(size)).encloses(rect)

func _assert_actions_reachable(panel: GameOverPanel, size: Vector2i) -> void:
	var actions := panel.find_child("GameOverActions", true, false)
	assert_not_null(actions, "the card has its actions box")
	if actions == null:
		return
	assert_true(_inside_view((actions as Control).get_global_rect(), size),
		"the actions sit inside a %s window" % size)
	assert_eq((actions as Control).get_child_count(), 3, "all three options are together")


func test_every_game_over_option_is_on_screen_on_a_phone() -> void:
	for size in [PHONE_LANDSCAPE, SMALL_LANDSCAPE, PHONE_PORTRAIT]:
		await resize_window(size)
		var panel := _panel()
		await process_frames(4)
		assert_true(_inside_view(panel._panel.get_global_rect(), size),
			"the card fits a %s window" % size)
		_assert_actions_reachable(panel, size)
		var quit_button: Button = null
		for child in panel.find_children("*", "Button", true, false):
			if (child as Button).text == "Quit to Menu":
				quit_button = child as Button
		assert_not_null(quit_button, "the card offers Quit to Menu")
		if quit_button != null:
			assert_true(_inside_view(quit_button.get_global_rect(), size),
				"Quit to Menu is on screen at %s" % size)
			var asked: Array = []
			panel.quit_to_menu_requested.connect(func() -> void: asked.append(true))
			await touch_tap(quit_button.get_global_rect().get_center())
			assert_eq(asked.size(), 1, "a tap on Quit to Menu is answered at %s" % size)
		panel.free()
		await process_frames(2)


func test_the_legacy_scrolls_when_the_window_is_short() -> void:
	await resize_window(SMALL_LANDSCAPE)
	var panel := _panel()
	await process_frames(4)
	assert_true(_inside_view(panel._panel.get_global_rect(), SMALL_LANDSCAPE),
		"the card stays inside the window")
	var legacy: Control = panel.find_child("Legacy", true, false)
	assert_not_null(legacy, "the card keeps its legacy section")
	if legacy == null:
		return
	# A Phone-landscape card cannot show the whole legacy at once.
	assert_true(legacy.get_combined_minimum_size().y > panel._scroll.custom_minimum_size.y,
		"the legacy is taller than the space it is given")
	assert_ne(panel._scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"so it scrolls while the options stay put")
