extends MainSceneTest
## End-to-end integration tests for standalone Tournament Mode:
##   1. Main Menu -> Tournament Mode opens StartTournamentScreen across desktop,
##      tablet, rotated phone, and portrait phone sizes, and Back returns cleanly.
##   2. Difficulty Level selects opposing golfer rosters with progressively
##      higher Golf Skills and applies full golfer details (Name, Skin, Skin
##      Colours, Profession, Age, Gender, Marital Status, Traits, Golfer Skills,
##      and 10 Golf Skills) onto live AI and player Golfer nodes.
##   3. Tournament Format Types (Stroke Play, Stableford, Modified Stableford,
##      Skins), Format Rules (Rounds, Field Size, Cut Line, Playoff), and
##      Community Mod Game Features (Weather, Wind, Seasons) run end-to-end.
##   4. Career Mode exports a custom course & full golfer profile and plays a
##      multi-round tournament in standalone Tournament Mode.

const SCRATCH_ROOT := "user://test_tournament_mode_flow"
const SCRATCH_SAVES := SCRATCH_ROOT + "/saves/"
const SCRATCH_SETTINGS := SCRATCH_ROOT + "/settings.cfg"

func before_each() -> void:
	super()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	PlayerDataStore.saves_dir = SCRATCH_SAVES
	PlayerDataStore.settings_path = SCRATCH_SETTINGS
	DirAccess.make_dir_recursive_absolute(SCRATCH_SAVES)
	if main:
		if main.tournament_manager:
			main.tournament_manager.cancel_tournament()
		if main.tournament_results_popup:
			main.tournament_results_popup.hide()
		GameManager.exit_tournament_mode()
		if main.main_menu == null:
			main._show_main_menu()
			main._set_course_world_visible(false)
			main._set_gameplay_ui_visible(false)
			GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
		await process_frames(2)

func after_each() -> void:
	if main and main.tournament_manager:
		main.tournament_manager.cancel_tournament()
	GameManager.exit_tournament_mode()
	PlayerDataStore.restore_default_paths()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	await super()

func _press_btn(btn: Button) -> void:
	btn.pressed.emit()
	await process_frames(4)

func test_main_menu_opens_start_tournament_screen_and_backs_out_cleanly() -> void:
	await set_window(DESIGN_WINDOW)
	assert_not_null(main.main_menu, "starts on Main Menu")

	var tourney_btn := main.main_menu.find_child("TournamentModeButton", true, false) as Button
	assert_not_null(tourney_btn, "Main Menu has Tournament Mode card")
	await _press_btn(tourney_btn)

	assert_null(main.main_menu, "Main Menu closes when Start Tournament opens")
	assert_not_null(main.start_tournament_screen, "StartTournamentScreen is open")

	# Verify responsive layouts keep Back and Start Tournament inside the viewport
	for size in [Vector2i(1600, 1000), Vector2i(768, 1024), Vector2i(844, 390), Vector2i(390, 844)]:
		await set_window(size)
		var view := Rect2(Vector2.ZERO, Vector2(size))
		var cur_screen: StartTournamentScreen = main.start_tournament_screen
		var back_btn := cur_screen.find_child("BackButton", true, false) as Button
		var start_btn := cur_screen.find_child("StartTournamentButton", true, false) as Button
		assert_not_null(back_btn, "%s: Back button exists" % size)
		assert_not_null(start_btn, "%s: Start Tournament button exists" % size)
		assert_true(rect_within(back_btn.get_global_rect(), view), "%s: Back button on screen" % size)
		assert_true(rect_within(start_btn.get_global_rect(), view), "%s: Start Tournament on screen" % size)
		var prev_right := -1.0
		for chip_name in ["FieldSize_Auto", "FieldSize_8", "FieldSize_12", "FieldSize_18", "FieldSize_24"]:
			var chip := cur_screen.find_child(chip_name, true, false) as Button
			assert_not_null(chip, "%s: %s exists" % [size, chip_name])
			var r := chip.get_global_rect()
			assert_gte(r.position.x, 0.0, "%s: %s stays inside left edge" % [size, chip_name])
			assert_lte(r.end.x, float(size.x), "%s: %s stays inside right edge" % [size, chip_name])
			assert_gt(r.position.x, prev_right, "%s: %s does not overlap previous chip" % [size, chip_name])
			prev_right = r.end.x

	await set_window(DESIGN_WINDOW)
	var back := (main.start_tournament_screen as StartTournamentScreen).find_child("BackButton", true, false) as Button
	await _press_btn(back)
	assert_null(main.start_tournament_screen, "StartTournamentScreen closed")
	assert_not_null(main.main_menu, "Back returns to Main Menu")

func test_the_start_button_alone_starts_a_one_round_event() -> void:
	await set_window(DESIGN_WINDOW)
	await _press_btn(main.main_menu.find_child("TournamentModeButton", true, false) as Button)

	var screen: StartTournamentScreen = main.start_tournament_screen
	assert_not_null(screen, "StartTournamentScreen is open")
	assert_true((screen.find_child("Rounds_1", true, false) as Button).button_pressed,
		"the Rounds picker opens on 1R")
	assert_eq(int(screen.get_options()["rounds"]), 1, "and the screen would start a 1-round event")

	# Pressing Start without touching a single option plays the shortest event.
	await _press_btn(screen.find_child("StartTournamentButton", true, false) as Button)
	await process_frames(6)

	assert_true(GameManager.is_tournament_mode, "the untouched screen starts Tournament Mode")
	assert_eq(main.tournament_manager.total_rounds, 1, "an untouched Start button starts 1 round")
	assert_eq(str(GameManager.tournament_mode_options.get("cut_rule", "")), "none",
		"a 1-round event has no halfway cut")

	main.tournament_manager.simulate_remaining_and_complete()
	await process_frames(4)
	assert_true(main.tournament_results_popup.visible, "and the event completes")
	assert_eq(int(main.tournament_manager.tournament_results.get("total_rounds", 0)), 1)

func test_difficulty_selects_opponent_roster_and_live_golfers_carry_full_details() -> void:
	await set_window(DESIGN_WINDOW)
	var tourney_btn := main.main_menu.find_child("TournamentModeButton", true, false) as Button
	await _press_btn(tourney_btn)

	var screen: StartTournamentScreen = main.start_tournament_screen
	screen.select_difficulty(TournamentLibrary.Difficulty.EASY)
	screen.select_rounds(1)
	screen.select_field_size(8)
	screen.select_course("default:highland_ridge")
	screen.select_golfer("default:marcus_cole")

	var start_btn := screen.find_child("StartTournamentButton", true, false) as Button
	await _press_btn(start_btn)
	await process_frames(6)

	assert_true(GameManager.is_tournament_mode, "standalone Tournament Mode is active")
	assert_eq(GameManager.course_name, "Highland Ridge")
	assert_eq(main.tournament_manager.total_rounds, 1, "Easy difficulty uses selected 1-round format rule")
	assert_eq(main.tournament_manager._sim_field.size(), 8, "field size matches selected 8 golfers")

	var easy_roster_names: Array[String] = []
	for g in TournamentLibrary.get_difficulty_roster(TournamentLibrary.Difficulty.EASY):
		easy_roster_names.append(str(g["name"]))

	var easy_opp_ability_sum := 0.0
	for i in range(1, main.tournament_manager._sim_field.size()):
		var sg = main.tournament_manager._sim_field[i]
		assert_has(easy_roster_names, sg.name, "Easy opponent '%s' comes from Easy roster" % sg.name)
		easy_opp_ability_sum += (sg.driving_ability + sg.accuracy_ability + sg.putting_ability + sg.recovery_ability) * 0.25
	var easy_avg_ability := easy_opp_ability_sum / 7.0

	# Inspect live Golfer nodes spawned on the course in Round 1 (player + AI opponent)
	var live_golfers: Array = main.golfer_manager.golfers_container.get_children()
	assert_gte(live_golfers.size(), 2, "at least the opening pairing spawned on the course")
	var player_node: Golfer = null
	var ai_node: Golfer = null
	for child in live_golfers:
		if child is Golfer:
			var g_node := child as Golfer
			if g_node.golfer_name == "Marcus Cole":
				player_node = g_node
			elif ai_node == null:
				ai_node = g_node
	assert_not_null(player_node, "Marcus Cole spawned live on the course")
	assert_eq(player_node.attributes.profession, "Long-Drive Champion")
	assert_eq(player_node.attributes.age, 26)
	assert_true(player_node.attributes.skill_on("length"), "Marcus Cole's Length Golfer Skill applied")
	assert_eq(player_node.group_color_overrides.size(), 5, "player skin colour overrides applied")

	assert_not_null(ai_node, "opposing AI tournament golfer spawned live on the course")
	assert_false(ai_node.attributes.profession.is_empty(), "AI opponent carries full profession")
	assert_eq(ai_node.group_color_overrides.size(), 5, "AI opponent carries all 5 skin colour overrides")

	# Pause menu check + Return to Tournament Setup, then launch Championship with same 1-round rule
	main._show_pause_menu()
	await process_frames(3)
	assert_not_null(main.pause_menu)
	assert_eq(main.pause_menu._title.text, "Tournament Paused")
	main._close_pause_menu()

	main._on_return_to_tournament_setup()
	await process_frames(3)
	assert_false(GameManager.is_tournament_mode)
	assert_not_null(main.start_tournament_screen)

	var screen2: StartTournamentScreen = main.start_tournament_screen
	screen2.select_difficulty(TournamentLibrary.Difficulty.CHAMPIONSHIP)
	screen2.select_rounds(1)
	screen2.select_field_size(8)
	await _press_btn(screen2.find_child("StartTournamentButton", true, false) as Button)

	assert_eq(main.tournament_manager.total_rounds, 1, "Championship keeps the chosen 1-round format rule")
	var champ_roster_names: Array[String] = []
	for g in TournamentLibrary.get_difficulty_roster(TournamentLibrary.Difficulty.CHAMPIONSHIP):
		champ_roster_names.append(str(g["name"]))

	var champ_opp_ability_sum := 0.0
	for i in range(1, main.tournament_manager._sim_field.size()):
		var sg = main.tournament_manager._sim_field[i]
		assert_has(champ_roster_names, sg.name, "Championship opponent '%s' comes from Championship roster" % sg.name)
		champ_opp_ability_sum += (sg.driving_ability + sg.accuracy_ability + sg.putting_ability + sg.recovery_ability) * 0.25
	var champ_avg_ability := champ_opp_ability_sum / 7.0
	assert_gt(champ_avg_ability, easy_avg_ability, "Championship roster has higher Golf Skills than Easy roster")

	main.tournament_manager.simulate_remaining_and_complete()
	await process_frames(4)
	assert_true(main.tournament_results_popup.visible)

func test_formats_rules_and_mod_features_execute_end_to_end() -> void:
	await set_window(DESIGN_WINDOW)
	var tourney_btn := main.main_menu.find_child("TournamentModeButton", true, false) as Button
	await _press_btn(tourney_btn)

	var screen: StartTournamentScreen = main.start_tournament_screen
	screen.select_difficulty(TournamentLibrary.Difficulty.NORMAL)
	screen.select_format_type(TournamentLibrary.FormatType.STABLEFORD)
	screen.select_rounds(3)
	screen.select_field_size(8)
	screen.select_cut_rule("top_50pct")
	screen.set_playoff_enabled(true)
	screen.set_feature_enabled("weather", false)
	screen.set_feature_enabled("wind", true)
	screen.set_feature_enabled("seasons", true)
	screen.select_course("default:emerald_pines")
	screen.select_golfer("default:claire_vance")

	await _press_btn(screen.find_child("StartTournamentButton", true, false) as Button)

	# Verify community mod feature toggles took effect on GameManager & HUD
	assert_false(GameManager.is_feature_enabled("weather"), "Weather mod toggled OFF for this tournament")
	assert_true(GameManager.is_feature_enabled("wind"), "Wind mod toggled ON for this tournament")
	assert_true(GameManager.is_feature_enabled("seasons"), "Seasons mod toggled ON for this tournament")
	assert_false(main.hud_status_column._weather_row.visible, "Weather HUD row hidden when toggled off")
	assert_true(main.hud_status_column._wind_row.visible, "Wind HUD row shown when toggled on")
	assert_true(main.hud_status_column._season_row.visible, "Season HUD row shown in Tournament Mode when toggled on")
	assert_gt(GameManager.wind_system.wind_speed, 0.0, "Wind speed active when Wind feature enabled")

	assert_eq(main.tournament_manager.current_format_type, TournamentLibrary.FormatType.STABLEFORD)
	assert_eq(main.tournament_manager.total_rounds, 3)
	assert_eq(main.tournament_manager._sim_field.size(), 8)

	main.tournament_manager.simulate_remaining_and_complete()
	await process_frames(4)

	var res: Dictionary = main.tournament_manager.tournament_results
	assert_eq(int(res.get("format_type", -1)), TournamentLibrary.FormatType.STABLEFORD)
	assert_eq(str(res.get("format_name", "")), "Stableford")
	assert_eq(int(res.get("total_rounds", 0)), 3)
	assert_eq(int(res.get("participant_count", 0)), 8)
	assert_gt(int(res.get("winning_points", 0)), 0, "Stableford champion scored positive Stableford points")
	assert_gt(int(res.get("cut_golfers", 0)), 0, "Top 50% cut advanced top golfers")
	assert_gt(int(res.get("eliminated_golfers", 0)), 0, "Top 50% cut eliminated bottom golfers")

	# Return to setup and run a 1-round Skins match with Wind OFF
	var setup_btn := (main.tournament_results_popup as Control).find_child("TournamentSetupButton", true, false) as Button
	await _press_btn(setup_btn)

	var skins_screen: StartTournamentScreen = main.start_tournament_screen
	skins_screen.select_format_type(TournamentLibrary.FormatType.SKINS)
	skins_screen.select_rounds(1)
	skins_screen.select_field_size(8)
	skins_screen.set_feature_enabled("wind", false)
	await _press_btn(skins_screen.find_child("StartTournamentButton", true, false) as Button)

	assert_false(GameManager.is_feature_enabled("wind"))
	assert_eq(GameManager.wind_system.wind_speed, 0.0, "Wind is calm when Wind feature is toggled off")
	main.tournament_manager.simulate_remaining_and_complete()
	await process_frames(4)

	var skins_res: Dictionary = main.tournament_manager.tournament_results
	assert_eq(int(skins_res.get("format_type", -1)), TournamentLibrary.FormatType.SKINS)
	assert_eq(str(skins_res.get("format_name", "")), "Skins")
	assert_eq(int(skins_res.get("eliminated_golfers", 0)), 0, "1-round Skins event has no cut")

func test_career_saved_course_and_golfer_roundtrip_into_tournament_mode() -> void:
	await set_window(DESIGN_WINDOW)
	# Launch Career Quick Start
	var quick_btn := main.main_menu.find_child("QuickStartButton", true, false) as Button
	await _press_btn(quick_btn)
	for _i in range(40):
		if GameManager.current_mode == GameManager.GameMode.SIMULATING and GameManager.get_open_hole_count() >= 1:
			break
		await process_frames(2)

	assert_false(GameManager.is_tournament_mode)
	assert_gte(GameManager.get_open_hole_count(), 1, "Career Quick Start built playable holes")
	var career_holes := GameManager.get_open_hole_count()
	GameManager.course_name = "Royal Sydney Club"
	GameManager.player_profile.golfer_name = "Bennelong Star"
	GameManager.player_profile.profession = "Tour Winner"
	GameManager.player_profile.age = 34
	GameManager.player_profile.gender = GolferAttributes.Gender.FEMALE
	GameManager.player_profile.marital_status = GolferAttributes.MaritalStatus.MARRIED
	GameManager.player_profile.traits = {
		"neat": true, "outgoing": true, "active": true, "playful": false, "nice": true,
	}
	GameManager.player_profile.golfer_skills = {
		"length": true, "accuracy": true, "imagination": true,
	}
	GameManager.player_profile.appearance["shirt_color"] = "1f7a68"
	GameManager.player_profile.initialized = true
	GameManager.player_profile.points = [15, 14, 17, 17, 19, 8, 7, 9, 12, 6]
	main.player_round.open_setup()
	await process_frames(2)

	# Export Career Course & Career Golfer using the Golfers -> Play Course shelf buttons
	main.terrain_toolbar.select_player_section(PlayerTab.PAGE_PLAY)
	await process_frames(2)
	var save_course_btn := (main.terrain_toolbar as Control).find_child("SaveTournamentCourseButton", true, false) as Button
	var save_golfer_btn := (main.terrain_toolbar as Control).find_child("SaveTournamentGolferButton", true, false) as Button
	assert_not_null(save_course_btn)
	assert_not_null(save_golfer_btn)

	await _press_btn(save_course_btn)
	await _press_btn(save_golfer_btn)

	assert_eq(TournamentLibrary.saved_course_count(), 1)
	assert_eq(TournamentLibrary.saved_golfer_count(), 1)

	# Open Start Tournament screen and configure a 4-round Modified Stableford event on Hard
	main.golfer_manager.clear_all_golfers()
	main.ball_manager.clear_all_balls()
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	main._open_start_tournament_screen()
	await process_frames(3)

	var screen: StartTournamentScreen = main.start_tournament_screen
	assert_not_null(screen)
	screen.select_difficulty(TournamentLibrary.Difficulty.HARD)
	screen.select_format_type(TournamentLibrary.FormatType.MODIFIED_STABLEFORD)
	screen.select_rounds(4)
	screen.select_field_size(12)
	screen.select_cut_rule("top_50pct")
	screen.select_course("saved:royal_sydney_club")
	screen.select_golfer("saved:bennelong_star")

	var start_btn := screen.find_child("StartTournamentButton", true, false) as Button
	await _press_btn(start_btn)
	await process_frames(6)

	assert_true(GameManager.is_tournament_mode)
	assert_eq(GameManager.course_name, "Royal Sydney Club")
	assert_eq(GameManager.get_open_hole_count(), career_holes, "saved Career course holes restored")
	assert_eq(GameManager.player_profile.golfer_name, "Bennelong Star")
	assert_eq(GameManager.player_profile.profession, "Tour Winner")
	assert_eq(GameManager.player_profile.age, 34)
	assert_eq(GameManager.player_profile.gender, GolferAttributes.Gender.FEMALE)
	assert_eq(GameManager.player_profile.marital_status, GolferAttributes.MaritalStatus.MARRIED)
	assert_true(bool(GameManager.player_profile.traits["neat"]))
	assert_true(bool(GameManager.player_profile.golfer_skills["imagination"]))
	assert_eq(GameManager.player_profile.points[4], 19, "saved Career golfer putting skill restored")
	assert_eq(main.tournament_manager.total_rounds, 4)

	# Complete all 4 rounds and verify player appears in final standings
	main.tournament_manager.simulate_remaining_and_complete()
	await process_frames(4)
	var entries: Array = main.tournament_manager.tournament_results.get("all_entries", [])
	var found_player := false
	for e in entries:
		if bool(e.get("is_player", false)) and str(e.get("name", "")) == "Bennelong Star":
			found_player = true
			break
	assert_true(found_player, "Career-saved golfer competed and finished on the final leaderboard")

func test_auto_field_size_scales_with_selected_course_holes_end_to_end() -> void:
	await set_window(DESIGN_WINDOW)
	var tourney_btn := main.main_menu.find_child("TournamentModeButton", true, false) as Button
	await _press_btn(tourney_btn)

	var screen: StartTournamentScreen = main.start_tournament_screen
	assert_true(screen.is_field_size_auto(), "StartTournamentScreen defaults to Auto field size")

	# Select 18-hole Dunbar Links with Auto field size -> 36 golfers
	screen.select_rounds(1)
	screen.select_course("default:dunbar_links")
	assert_eq(int(screen.get_options()["field_size"]), 36, "18-hole Dunbar Links resolves Auto field size to 36")
	assert_string_contains(screen._dossier_diff_label.text, "36 Golfers (Auto)")

	await _press_btn(screen.find_child("StartTournamentButton", true, false) as Button)
	await process_frames(6)

	assert_eq(GameManager.get_open_hole_count(), 18)
	assert_eq(main.tournament_manager._sim_field.size(), 36, "live tournament field has 36 golfers (2x 18 holes)")

	main.tournament_manager.simulate_remaining_and_complete()
	await process_frames(4)
	assert_eq(int(main.tournament_manager.tournament_results.get("participant_count", 0)), 36)

	# Return to Tournament Setup -> Auto remains selected; switch to 6-hole Highland Ridge -> 12 golfers
	var setup_btn := (main.tournament_results_popup as Control).find_child("TournamentSetupButton", true, false) as Button
	await _press_btn(setup_btn)

	var screen2: StartTournamentScreen = main.start_tournament_screen
	assert_true(screen2.is_field_size_auto(), "Auto field size selection persists when returning to Tournament Setup")
	screen2.select_course("default:highland_ridge")
	assert_eq(int(screen2.get_options()["field_size"]), 12, "6-hole Highland Ridge resolves Auto field size to 12")

	await _press_btn(screen2.find_child("StartTournamentButton", true, false) as Button)
	await process_frames(6)

	assert_eq(GameManager.get_open_hole_count(), 6)
	assert_eq(main.tournament_manager._sim_field.size(), 12, "live tournament field has 12 golfers (2x 6 holes)")
	main.tournament_manager.simulate_remaining_and_complete()
	await process_frames(4)
	assert_eq(int(main.tournament_manager.tournament_results.get("participant_count", 0)), 12)

