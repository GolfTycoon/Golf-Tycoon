extends MainSceneTest
## Hosting a tournament from the shelf on the Quick Start course: the event
## starts on the click rather than on a later day, the field opens with a pairing
## on every hole and the owner plays in it, the scores read out in the top-left
## corner, Play It Out settles the event on full cards, and the results, the
## cooldown and the cleanup follow.
##
## The tests follow one event from the click to the cooldown, in order.

const REGIONAL := TournamentSystem.TournamentTier.REGIONAL

var tournaments: TournamentManager
var open_holes: int
## Par of the open circuit as a tournament measures it: the back tees, which is
## what both live play and Play It Out score a hole against.
var circuit_par: int
var field_size: int
var money_before_hosting: int


func before_all() -> void:
	await super()
	await quick_start("Tournament")
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)
	await process_frames(10)
	tournaments = GameManager.tournament_manager
	open_holes = GameManager.get_open_hole_count()
	for hole in GameManager.current_course.holes:
		if hole.is_open:
			circuit_par += hole.par
	field_size = TournamentSystem.get_field_size(REGIONAL, open_holes)
	# Hold the clock from here: the qualification the shelf reports and the
	# qualification the host click reads must be the same one, and a day
	# rolling between the two tests would re-rate the course out from under
	# the click (pace and value follow the day's scores). The live tests
	# below run their own clock.
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)


func _tournament_golfers() -> Array[Golfer]:
	var golfers: Array[Golfer] = []
	for golfer in main.golfer_manager.active_golfers:
		if golfer.is_tournament_golfer:
			golfers.append(golfer)
	return golfers


## The first label on the shelf whose text starts with `prefix`.
func _panel_label(prefix: String) -> String:
	for label in main.tournament_panel.find_children("*", "Label", true, false):
		if str(label.text).begins_with(prefix):
			return str(label.text)
	return ""


func _status_text() -> String:
	return main.tournament_panel._status_label.text.replace("\n", " | ")


func test_the_shelf_offers_a_live_host_button_on_a_qualifying_course() -> void:
	# The shelf is the Player tab's Play page; opening it is what a player does.
	main._toggle_tournament_panel()
	await process_frames(5)
	var host_button: Button = main.tournament_panel.get_host_button(REGIONAL)
	assert_not_null(host_button, "The Regional card carries a Host button")
	if host_button:
		assert_false(host_button.disabled, "It is live on a qualifying course: %s" % host_button.tooltip_text)
	assert_eq(tournaments.can_schedule_tournament(REGIONAL).reason, "", "Hosting reports no outstanding requirement")


func test_hosting_starts_the_event_on_the_click() -> void:
	var day := GameManager.current_day
	money_before_hosting = GameManager.money
	# `pressed` is synchronous: no frame passes in which a day could roll over
	# and bring its operating costs into the comparison.
	main.tournament_panel.get_host_button(REGIONAL).pressed.emit()
	var fee: int = TournamentSystem.TIER_DATA[REGIONAL].entry_cost
	assert_eq(GameManager.money, money_before_hosting - fee, "The entry fee is charged on the click")
	# The event plays live from here: the field assembles and the pairs spread
	# over the course while the day runs.
	GameManager.set_speed(GameManager.GameSpeed.FAST)
	await process_frames(2)
	assert_eq(tournaments.current_tournament_state, TournamentSystem.TournamentState.IN_PROGRESS,
		"The tournament is live straight away")
	assert_eq(tournaments.tournament_start_day, day, "It is dated today, not a day still to come")
	assert_eq(tournaments.current_round, 1, "Round 1 is under way")
	assert_eq(tournaments._sim_field.size(), field_size, "The field is assembled on the click")


func test_the_field_plays_in_pairs_spread_over_the_course() -> void:
	assert_eq(TournamentSystem.get_group_size(), 2, "Competitors play in pairs")
	assert_eq(tournaments._live_count, open_holes * 2, "The field seats two per open hole")
	assert_eq(tournaments._total_groups, open_holes, "One pairing per hole")
	await process_frames(90)
	var by_hole := {}
	var group_sizes := {}
	for golfer in _tournament_golfers():
		by_hole[golfer.current_hole] = int(by_hole.get(golfer.current_hole, 0)) + 1
		group_sizes[golfer.group_id] = int(group_sizes.get(golfer.group_id, 0)) + 1
	assert_false(_tournament_golfers().is_empty(), "Golfers are on the course playing")
	for group in group_sizes:
		assert_eq(group_sizes[group], 2, "Pairing %d has two competitors" % group)
	# A catch-up pairing can share a hole with the one ahead while it clears the
	# green, so what is checked is that the field is spread over the course.
	assert_gte(by_hole.size(), mini(4, open_holes), "The field is spread over the course: %s" % by_hole)


func test_the_owner_plays_in_the_field() -> void:
	var owner_name: String = GameManager.player_profile.golfer_name
	var owner_out := false
	for golfer in _tournament_golfers():
		if golfer.golfer_name == owner_name:
			owner_out = true
	assert_true(owner_out, "The owner's golfer is out there")
	assert_eq(int(tournaments._sim_field[0].id), TournamentManager.PLAYER_SIM_ID,
		"The owner leads off the field, so they tee off in the first pairing")
	assert_eq(tournaments._sim_field[0].name, owner_name, "under their own name")
	var owner_row := false
	for entry in tournaments._leaderboard._entries:
		if entry.get("is_player", false):
			owner_row = true
	assert_true(owner_row, "The live leaderboard carries the owner's row")
	assert_eq(int(tournaments.get_player_standing().get("field_size", 0)), field_size,
		"The shelf scores the owner against the whole field")


func test_the_scores_read_out_in_the_top_left_corner() -> void:
	var board: Control = main.tournament_leaderboard
	var dock: Control = main.scores_dock
	assert_eq(board.get_parent(), dock, "The live board docks in the top-left scores corner")
	assert_eq(dock.anchor_left, 0.0, "The corner is pinned to the left of the screen")
	assert_eq(dock.anchor_top, 0.0, "and to its top")
	assert_gt(dock.offset_left, 0.0, "inside the screen edge")
	assert_true(board.visible, "The board shows while the event runs")
	assert_false(main.terrain_toolbar.player_tab.aim_page.is_ancestor_of(board),
		"The board no longer sits in the Play Course page")
	assert_false(dock.round_scores.visible, "The round card steps aside for the board")
	await process_frames(2)
	assert_lt(dock.get_global_rect().end.y, main.bottom_bar.global_position.y,
		"The corner clears the shot controls in the bottom bar")


func test_the_shelf_shows_the_running_event() -> void:
	main.tournament_panel._refresh_display()
	await process_frames(5)
	assert_string_contains(_status_text(), "In progress", "The shelf shows the running event")
	assert_true(_panel_label("You:").begins_with("You:"), "and the owner's scoreline")


func test_play_it_out_settles_the_event_on_full_cards() -> void:
	var settle: Button = main.tournament_panel.get_settle_button()
	assert_not_null(settle, "The running event offers Play It Out")
	if settle == null:
		return
	settle.pressed.emit()
	await process_frames(30)
	assert_false(tournaments.is_tournament_in_progress(), "The event is over")
	var results: Dictionary = tournaments.tournament_results
	assert_false(results.is_empty(), "Results were published")
	var rounds := int(results.get("rounds_played", 0))
	assert_eq(rounds, tournaments.ROUNDS_PER_TIER[REGIONAL], "Every round of the event was scored")
	var entries: Array = results.get("all_entries", [])
	assert_eq(entries.size(), field_size, "Every entry in the field was scored")
	var pars := {}
	for entry in entries:
		pars[int(entry.total_par)] = int(pars.get(int(entry.total_par), 0)) + 1
	assert_eq(pars, {circuit_par * rounds: field_size}, "Every card covers the circuit once per round")
	assert_true(entries.any(func(entry: Dictionary) -> bool: return entry.get("is_player", false)),
		"The owner's result is in the book")
	assert_true(_tournament_golfers().is_empty(), "Nobody stays on the course after the event")
	assert_gt(GameManager.money, money_before_hosting, "The event paid for itself")


func test_the_cooldown_follows_and_the_shelf_says_so() -> void:
	assert_gt(tournaments.get_cooldown_remaining(), 0, "The cooldown started")
	main.tournament_panel._refresh_display()
	await process_frames(5)
	assert_null(main.tournament_panel.get_host_button(REGIONAL), "The tier cards step aside during the cooldown")
	assert_string_contains(_status_text(), "Cooldown", "and the shelf says why")
	assert_string_contains(str(tournaments.can_schedule_tournament(REGIONAL).reason), "Must wait",
		"Hosting again during the cooldown names the wait")
