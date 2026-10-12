extends MainSceneTest
## The speed controls in the real HUD, through real clicks: pause, play and one
## fast-forward button that steps between Fast (3x) and Ultra (8x), with a face,
## a tooltip and a highlight that say which, all filling the bottom bar's left
## control stack.

var fast: Button


func before_all() -> void:
	await super()
	# Drop the title screen so the speed controls are on screen and take input.
	main.main_menu.queue_free()
	main.main_menu = null
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	main._set_gameplay_ui_visible(true)
	await process_frames(2)
	fast = main.fast_btn


func test_pause_play_and_one_fast_forward_button_fill_the_stack() -> void:
	var names: Array = []
	for child in main.speed_controls.get_children():
		names.append(String(child.name))
	assert_eq(names, ["PauseBtn", "PlayBtn", "FastBtn"], "Pause, play and one fast-forward button")
	assert_null(main.speed_controls.get_node_or_null("UltraBtn"), "No separate Ultra button")
	# The stack fills the bottom bar, its rows run its full height and the
	# buttons fill their row.
	var stack: VBoxContainer = main.left_controls
	var top_row: Control = stack.get_child(0)
	var bottom_row: Control = stack.get_child(stack.get_child_count() - 1)
	assert_almost_eq(stack.size.y, main.bottom_bar.size.y, 0.5, "The stack fills the bottom bar's height")
	assert_lte(top_row.position.y, 0.5, "with no dead space above its rows")
	assert_gte(bottom_row.position.y + bottom_row.size.y, stack.size.y - 0.5, "or below them")
	assert_almost_eq(fast.size.y, main.speed_controls.size.y, 0.5, "The speed buttons fill their row")


func test_fast_forward_steps_between_fast_and_ultra() -> void:
	# Idle: the button advertises the tier it starts at, dimmed.
	assert_eq(fast.text, ">>", "The idle button reads >>")
	assert_lt(fast.modulate.a, 1.0, "and is dimmed")
	assert_string_contains(fast.tooltip_text, "Fast (3x)", "Its tooltip teaches Fast")
	assert_string_contains(fast.tooltip_text, "Ultra (8x)", "and Ultra")
	# Both faces keep one width, so toggling never nudges the row.
	var width := fast.size.x

	await click(fast)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.FAST, "The first press runs at Fast")
	assert_eq(Engine.time_scale, 3.0, "and scales the engine by 3")
	assert_eq(fast.text, ">>", "Fast keeps the >> face")
	assert_almost_eq(fast.size.x, width, 0.5, "and the button's width")
	assert_eq(fast.modulate.a, 1.0, "The button lights up while Fast runs")
	assert_string_contains(fast.tooltip_text, "Ultra (8x)", "and offers Ultra next")

	await click(fast)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.ULTRA, "The second press runs at Ultra")
	assert_eq(Engine.time_scale, 8.0, "and scales the engine by 8")
	assert_eq(fast.text, ">>>", "Ultra reads >>>")
	assert_almost_eq(fast.size.x, width, 0.5, "and the wider face keeps the width")
	assert_eq(fast.modulate.a, 1.0, "The button stays lit at Ultra")
	assert_string_contains(fast.tooltip_text, "Fast (3x)", "and offers Fast next")

	await click(fast)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.FAST, "The third press drops back to Fast")
	assert_eq(Engine.time_scale, 3.0, "at 3x")
	assert_eq(fast.text, ">>", "reading >> again")
	assert_almost_eq(fast.size.x, width, 0.5, "at the same width")


func test_pause_and_play_keep_their_own_buttons() -> void:
	await click(main.pause_btn)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.PAUSED, "The pause button pauses")
	assert_eq(Engine.time_scale, 0.0, "and freezes the engine")
	assert_eq(fast.text, ">>", "The paused fast-forward button advertises Fast")
	assert_lt(fast.modulate.a, 1.0, "dimmed")
	await click(main.play_btn)
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.NORMAL, "The play button resumes at 1x")
	assert_eq(Engine.time_scale, 1.0, "in real time")
