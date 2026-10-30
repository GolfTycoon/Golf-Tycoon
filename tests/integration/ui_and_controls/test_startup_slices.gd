extends MainSceneTest
## The startup of a build that slices it: every web build, and any native run
## started with `--split-startup`.
##
## There the scene builds itself over a handful of frames instead of one long
## _ready(), reporting each step to the exported page's loading screen (see
## WebBoot and web/custom_shell.html) so that screen stays alive while a slow
## device works. The tests here pin that down from the outside: the startup
## really does take more than one frame, every step of it ran, and the title
## screen is up and usable at the end.

func before_all() -> void:
	WebBoot.split_startup_forced = true
	await super()


func after_all() -> void:
	super()
	WebBoot.split_startup_forced = false
	WebBoot.reset()


func test_the_startup_spans_several_frames() -> void:
	assert_true(main._startup_complete, "the startup finished")
	assert_gt(startup_frames, 0,
		"the scene gave the browser frames to paint in instead of blocking it")
	assert_lt(startup_frames, MAX_STARTUP_FRAMES, "and it did finish")


func test_every_startup_step_ran() -> void:
	# One node or manager per startup step: if a slice were skipped the title
	# screen would still open but the course behind it would be missing parts.
	assert_not_null(main.entity_layer, "the course layer")
	assert_not_null(main.terrain_toolbar, "the tool palette")
	assert_not_null(main.hud_status_column, "the status column")
	assert_not_null(main.hud_status_column.get_parent(), "the status column is in the HUD")
	assert_not_null(main.tournament_manager, "the tournament manager")
	assert_not_null(main.player_round, "the player's round")
	assert_not_null(main.main_menu, "the title screen")


func test_the_title_screen_is_the_last_thing_reported() -> void:
	assert_eq(WebBoot.last_stage,
		main._startup_stage_text(main.STARTUP_TITLE_SCREEN),
		"the loading screen was told the menu was the last step")


func test_the_title_screen_is_up_and_reachable() -> void:
	var menu := main.main_menu as Control
	assert_not_null(menu)
	assert_true(menu.is_visible_in_tree(), "the title screen is on screen")
	var labels: Array = []
	for button in nodes_of_class(menu, "Button"):
		labels.append((button as Button).text)
		assert_true((button as Button).is_visible_in_tree(),
			"%s is showing" % (button as Button).text)
	for expected in ["Start New Game", "Quick Start", "Continue", "Quit"]:
		assert_has(labels, expected, "the title screen offers %s" % expected)
