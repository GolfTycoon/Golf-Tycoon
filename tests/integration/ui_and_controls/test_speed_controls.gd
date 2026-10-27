extends MainSceneTest
## The speed controls in the real HUD, through real clicks: pause and one
## combined speed button that cycles Normal (1x), Fast (3x) and Ultra (8x),
## with an icon, a face, a tooltip and a highlight that say which, all
## filling the bottom bar's left control stack.

var speed: PixelCircleButton


func before_all() -> void:
	await super()
	# Drop the title screen so the speed controls are on screen and take input.
	main.main_menu.queue_free()
	main.main_menu = null
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	main._set_gameplay_ui_visible(true)
	await process_frames(2)
	speed = main.speed_btn


func test_pause_and_one_speed_button_fill_the_stack() -> void:
	var names: Array = []
	for child in main.speed_controls.get_children():
		names.append(String(child.name))
	assert_eq(names, ["PauseBtn", "SpeedBtn"], "Pause and one combined speed button")
	assert_null(main.speed_controls.get_node_or_null("PlayBtn"), "No separate play button")
	assert_null(main.speed_controls.get_node_or_null("FastBtn"), "No separate fast-forward button")
	assert_null(main.speed_controls.get_node_or_null("UltraBtn"), "No separate Ultra button")
	var dock: BottomControlDock = main.left_controls
	assert_almost_eq(dock.size.y, main.bottom_bar.size.y, 0.5)
	for i in 2:
		var button: PixelCircleButton = [main.pause_btn, speed][i]
		var diameter := BottomControlDock.DESKTOP_UTILITY_SIZE - (i + 1) * BottomControlDock.UTILITY_SIZE_STEP
		assert_eq(button.size, Vector2.ONE * diameter, "Arc controls stay square")
		assert_true(dock.get_global_rect().encloses(button.get_global_rect()))
	assert_almost_eq(speed.position.y + speed.size.y, dock.size.y - 2, 0.5)


func test_speed_button_cycles_through_all_three_speeds() -> void:
	# Running at Normal: one triangle, lit ring, Fast offered next.
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.NORMAL)
	assert_eq(speed.text, ">", "Normal reads >")
	assert_eq(speed.glyph, "play", "with the single-triangle play icon")
	assert_true(speed.active, "Its ring is lit while a running speed is active")
	assert_string_contains(speed.tooltip_text, "Normal (1x)", "Its tooltip names Normal")
	assert_string_contains(speed.tooltip_text, "Fast (3x)", "and offers Fast next")
	assert_eq(speed.accessibility_name, "Game speed: Normal")
	# Every face keeps one width, so cycling never nudges the row.
	var width := speed.size.x

	await click(speed)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.FAST, "The first press runs at Fast")
	assert_eq(Engine.time_scale, 3.0, "and scales the engine by 3")
	assert_eq(speed.text, ">>", "Fast reads >>")
	assert_eq(speed.glyph, "fast", "with the two-triangle icon")
	assert_almost_eq(speed.size.x, width, 0.5, "and the button's width")
	assert_true(speed.active, "The ring stays lit while Fast runs")
	assert_string_contains(speed.tooltip_text, "Ultra (8x)", "and offers Ultra next")
	assert_eq(speed.accessibility_name, "Game speed: Fast")

	await click(speed)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.ULTRA, "The second press runs at Ultra")
	assert_eq(Engine.time_scale, 8.0, "and scales the engine by 8")
	assert_eq(speed.text, ">>>", "Ultra reads >>>")
	assert_eq(speed.glyph, "ultra", "with the three-triangle icon")
	assert_almost_eq(speed.size.x, width, 0.5, "and the wider face keeps the width")
	assert_true(speed.active, "The ring stays lit at Ultra")
	assert_string_contains(speed.tooltip_text, "Normal (1x)", "and offers Normal next")
	assert_eq(speed.accessibility_name, "Game speed: Ultra")

	await click(speed)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.NORMAL, "The third press wraps back to Normal")
	assert_eq(Engine.time_scale, 1.0, "in real time")
	assert_eq(speed.text, ">", "reading > again")
	assert_eq(speed.glyph, "play", "with the play icon again")
	assert_almost_eq(speed.size.x, width, 0.5, "at the same width")


func test_pause_keeps_its_own_button_and_the_speed_button_resumes() -> void:
	await click(main.pause_btn)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.PAUSED, "The pause button pauses")
	assert_eq(Engine.time_scale, 0.0, "and freezes the engine")
	assert_true(main.pause_btn.active, "The pause ring lights up")
	assert_eq(speed.text, ">", "The paused speed button advertises Normal")
	assert_eq(speed.glyph, "play", "with the play icon")
	assert_false(speed.active, "Its ring is not selected")
	assert_string_contains(speed.tooltip_text, "Ultra (8x)", "and still teaches the full cycle")
	await click(speed)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.NORMAL, "The speed button resumes at 1x")
	assert_eq(Engine.time_scale, 1.0, "in real time")
	assert_true(speed.active, "and its ring lights up again")
