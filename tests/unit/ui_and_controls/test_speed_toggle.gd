extends GameTest
## The speed controls' combined play/fast-forward button.
##
## Normal (1x), Fast (3x) and Ultra (8x) used to sit on separate buttons at
## the bottom of the screen. They now share one toggle that cycles through
## the three running speeds: GameManager owns the cycling, and Main derives
## the button's icon, face and tooltip from the tier that is currently
## running. Pausing keeps its own button, so the cycle never pauses.

const GameManagerScript := preload("res://scripts/autoload/game_manager.gd")
const MainScript := preload("res://scripts/main/main.gd")

func after_each() -> void:
	# Leave the singleton in a clean state for the tests that follow.
	GameManager.is_paused = false
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	super()


# ---------------------------------------------------------------------------
# Cycling logic
# ---------------------------------------------------------------------------

func test_first_press_from_normal_enters_fast() -> void:
	assert_eq(GameManagerScript.next_running_speed(GameManager.GameSpeed.NORMAL),
			GameManager.GameSpeed.FAST,
			"One press from normal speed starts at Fast (3x)")

func test_press_from_ultra_wraps_back_to_normal() -> void:
	assert_eq(GameManagerScript.next_running_speed(GameManager.GameSpeed.ULTRA),
			GameManager.GameSpeed.NORMAL,
			"One press from Ultra returns to Normal (1x)")

func test_first_press_from_paused_resumes_at_normal() -> void:
	assert_eq(GameManagerScript.next_running_speed(GameManager.GameSpeed.PAUSED),
			GameManager.GameSpeed.NORMAL,
			"The toggle unpauses into Normal, never straight into a faster tier")

func test_repeated_presses_cycle_through_all_three_speeds() -> void:
	var speed: int = GameManager.GameSpeed.NORMAL
	var visited: Array = []
	for _press in 6:
		speed = GameManagerScript.next_running_speed(speed)
		visited.append(speed)
	assert_eq(visited,
			[GameManager.GameSpeed.FAST, GameManager.GameSpeed.ULTRA,
			GameManager.GameSpeed.NORMAL, GameManager.GameSpeed.FAST,
			GameManager.GameSpeed.ULTRA, GameManager.GameSpeed.NORMAL],
			"Pressing the one button cycles Fast, Ultra, Normal forever")

func test_all_three_running_speeds_belong_to_the_toggle() -> void:
	assert_true(GameManagerScript.is_running_speed(GameManager.GameSpeed.NORMAL),
			"Normal is a running speed")
	assert_true(GameManagerScript.is_running_speed(GameManager.GameSpeed.FAST),
			"Fast is a running speed")
	assert_true(GameManagerScript.is_running_speed(GameManager.GameSpeed.ULTRA),
			"Ultra is a running speed")
	assert_false(GameManagerScript.is_running_speed(GameManager.GameSpeed.PAUSED),
			"Paused belongs to the pause button")


# ---------------------------------------------------------------------------
# Effect of a press
# ---------------------------------------------------------------------------

func test_cycle_applies_the_tier_it_switches_to() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	GameManager.cycle_running_speed()
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.FAST)
	assert_eq(Engine.time_scale, 3.0, "Fast must run the simulation at 3x")

	GameManager.cycle_running_speed()
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.ULTRA)
	assert_eq(Engine.time_scale, 8.0, "Ultra must run the simulation at 8x")

	GameManager.cycle_running_speed()
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.NORMAL,
			"A press at Ultra wraps back to Normal")
	assert_eq(Engine.time_scale, 1.0)

func test_cycle_emits_the_speed_change_signal() -> void:
	watch_signals(EventBus)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	GameManager.cycle_running_speed()

	assert_signal_emitted_with_parameters(EventBus, "game_speed_changed",
			[GameManager.GameSpeed.FAST])


# ---------------------------------------------------------------------------
# Button face
# ---------------------------------------------------------------------------

func test_button_face_shows_the_running_tier() -> void:
	assert_eq(MainScript.speed_toggle_label(GameManager.GameSpeed.NORMAL), ">",
			"Normal shows the familiar play face")
	assert_eq(MainScript.speed_toggle_label(GameManager.GameSpeed.FAST), ">>")
	assert_eq(MainScript.speed_toggle_label(GameManager.GameSpeed.ULTRA), ">>>",
			"Ultra keeps the familiar three-chevron face")
	assert_eq(MainScript.speed_toggle_label(GameManager.GameSpeed.PAUSED), ">",
			"A paused toggle advertises the Normal a press resumes at")

func test_each_speed_has_its_own_icon() -> void:
	var glyphs: Dictionary = {}
	for speed in [GameManager.GameSpeed.NORMAL, GameManager.GameSpeed.FAST,
			GameManager.GameSpeed.ULTRA]:
		var glyph: String = MainScript.speed_toggle_glyph(speed)
		assert_true(PixelCircleButton.ICONS.has(glyph),
				"The %s speed's icon exists" % glyph)
		assert_false(glyphs.has(glyph), "Each speed has a different icon")
		glyphs[glyph] = PixelCircleButton.ICONS[glyph]
	assert_eq(MainScript.speed_toggle_glyph(GameManager.GameSpeed.NORMAL), "play",
			"One triangle at Normal")
	assert_eq(MainScript.speed_toggle_glyph(GameManager.GameSpeed.FAST), "fast",
			"Two triangles at Fast")
	assert_eq(MainScript.speed_toggle_glyph(GameManager.GameSpeed.ULTRA), "ultra",
			"Three triangles at Ultra")
	assert_eq(MainScript.speed_toggle_glyph(GameManager.GameSpeed.PAUSED), "play",
			"The play triangle offers Normal while paused")
	# The three bitmaps really differ, so the tiers read apart at a glance
	# rather than by a mark added to one shared icon.
	assert_ne(glyphs["play"], glyphs["fast"])
	assert_ne(glyphs["fast"], glyphs["ultra"])
	assert_ne(glyphs["play"], glyphs["ultra"])

func test_button_tooltip_names_the_tier_a_press_switches_to() -> void:
	var at_normal: String = MainScript.speed_toggle_tooltip(GameManager.GameSpeed.NORMAL)
	assert_string_contains(at_normal, "Normal (1x)", "Tooltip names the running tier")
	assert_string_contains(at_normal, "Fast (3x)", "Tooltip names where the press goes")

	var at_fast: String = MainScript.speed_toggle_tooltip(GameManager.GameSpeed.FAST)
	assert_string_contains(at_fast, "Fast (3x)", "Tooltip names the running tier")
	assert_string_contains(at_fast, "Ultra (8x)", "Tooltip names where the press goes")

	var at_ultra: String = MainScript.speed_toggle_tooltip(GameManager.GameSpeed.ULTRA)
	assert_string_contains(at_ultra, "Ultra (8x)", "Tooltip names the running tier")
	assert_string_contains(at_ultra, "Normal (1x)", "Tooltip names where the press wraps to")

	var paused: String = MainScript.speed_toggle_tooltip(GameManager.GameSpeed.PAUSED)
	assert_string_contains(paused, "Normal (1x)", "Paused tooltip teaches the first press")
	assert_string_contains(paused, "Fast (3x)", "Paused tooltip teaches the second press")
	assert_string_contains(paused, "Ultra (8x)", "Paused tooltip teaches the third press")


# ---------------------------------------------------------------------------
# Button width
# ---------------------------------------------------------------------------

func test_button_keeps_one_width_across_all_three_faces() -> void:
	# Sized loose, the faces measure differently: ">" fits the button's old
	# 28px slot, ">>>" needs more, and every tier toggle would resize the
	# button and nudge the speed-controls row. The lock sizes it for the widest
	# face once so every face then claims the same width.
	var button := Button.new()
	button.custom_minimum_size = Vector2(28, 24)
	add_child_autofree(button)

	var widths: Dictionary = {}
	for face in [">", ">>", ">>>"]:
		button.text = face
		widths[face] = button.get_combined_minimum_size().x
	assert_gt(widths[">>>"], widths[">"],
			"The three-chevron face really is the wider one, so the lock is needed")

	button.custom_minimum_size = Vector2(28, 24)
	MainScript.lock_button_width_to_faces(button, [">", ">>", ">>>"])
	for face in [">", ">>", ">>>"]:
		button.text = face
		assert_eq(button.get_combined_minimum_size().x, widths[">>>"],
				"Locked, the %s face keeps the width of the widest face" % face)

func test_width_lock_keeps_the_face_it_was_given() -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(28, 24)
	button.text = ">>"
	add_child_autofree(button)

	MainScript.lock_button_width_to_faces(button, [">", ">>", ">>>"])
	assert_eq(button.text, ">>", "The lock measures every face but leaves the face it found")
