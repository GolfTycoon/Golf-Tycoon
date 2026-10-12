extends GameTest
## Tournament tiers and their bookkeeping: what a course needs to host each tier,
## the field and rounds each one brings, what it earns, the cooldown between
## events, and what a save keeps of the event in hand.

var manager: TournamentManager

func before_each() -> void:
	super()
	# Not added to the tree: these tests only read its bookkeeping.
	manager = autofree(TournamentManager.new())

## A course of `holes` open holes of `yards` each.
func _course(holes: int, yards: int = 400) -> GameManager.CourseData:
	var course := GameManager.CourseData.new()
	for i in range(holes):
		var hole := make_hole(i + 1, Vector2i(i, 0), Vector2i(i, 10))
		hole.distance_yards = yards
		course.add_hole(hole)
	return course


# ---------------------------------------------------------------------------
# Qualification
# ---------------------------------------------------------------------------

func test_a_course_that_meets_every_requirement_qualifies() -> void:
	var check := TournamentSystem.check_qualification(TournamentSystem.TournamentTier.LOCAL,
		_course(4), {"overall": 2.5, "difficulty": 3.0})
	assert_true(check.qualified)
	assert_eq(check.missing, [])

func test_each_missing_requirement_is_named() -> void:
	var check := TournamentSystem.check_qualification(TournamentSystem.TournamentTier.REGIONAL,
		_course(3, 100), {"overall": 2.0, "difficulty": 1.0})
	assert_false(check.qualified)
	assert_eq(check.missing.size(), 4, "Holes, rating, difficulty and yardage are all short")
	assert_eq(check.missing[0], "Need 9 holes (have 3)")

func test_no_course_yet_asks_for_holes_rather_than_failing() -> void:
	var check := TournamentSystem.check_qualification(TournamentSystem.TournamentTier.LOCAL,
		null, {})
	assert_false(check.qualified)
	assert_eq(check.missing[0], "Need 4 holes (have 0)")

func test_closed_holes_do_not_count_towards_qualification() -> void:
	var course := _course(4)
	course.holes[0].is_open = false
	var check := TournamentSystem.check_qualification(TournamentSystem.TournamentTier.LOCAL,
		course, {"overall": 5.0, "difficulty": 9.0})
	assert_false(check.qualified)
	assert_eq(check.missing[0], "Need 4 holes (have 3)")

func test_a_better_course_qualifies_for_more_tiers() -> void:
	var rating := {"overall": 4.2, "difficulty": 5.5}
	var tiers := TournamentSystem.get_qualified_tiers(_course(18, 420), rating)
	assert_true(TournamentSystem.TournamentTier.LOCAL in tiers)
	assert_true(TournamentSystem.TournamentTier.REGIONAL in tiers)
	assert_true(TournamentSystem.TournamentTier.NATIONAL in tiers)
	assert_false(TournamentSystem.TournamentTier.CHAMPIONSHIP in tiers, "4.2 stars is short of 4.5")


# ---------------------------------------------------------------------------
# Field, rounds and money
# ---------------------------------------------------------------------------

func test_bigger_tiers_play_more_rounds() -> void:
	assert_eq(TournamentSystem.get_round_count(TournamentSystem.TournamentTier.LOCAL), 1)
	assert_eq(TournamentSystem.get_round_count(TournamentSystem.TournamentTier.REGIONAL), 2)
	assert_eq(TournamentSystem.get_round_count(TournamentSystem.TournamentTier.NATIONAL), 4)
	assert_eq(TournamentSystem.get_round_count(TournamentSystem.TournamentTier.CHAMPIONSHIP), 4)

func test_the_field_seats_a_pair_on_every_hole_but_never_shrinks_below_the_tier() -> void:
	assert_eq(TournamentSystem.get_live_field_size(9), 18, "Two competitors per open hole")
	assert_eq(TournamentSystem.get_live_field_size(0), 2, "Always at least one pairing")
	assert_eq(TournamentSystem.get_field_size(TournamentSystem.TournamentTier.LOCAL, 9), 18)
	assert_eq(TournamentSystem.get_field_size(TournamentSystem.TournamentTier.CHAMPIONSHIP, 9), 72,
		"A championship keeps its nominal field on a short course")

func test_revenue_and_profit_follow_the_tier_data() -> void:
	for tier in TournamentSystem.TIER_DATA:
		var data: Dictionary = TournamentSystem.get_tier_data(tier)
		var revenue: int = data.spectator_revenue + data.sponsorship_revenue
		assert_eq(TournamentSystem.get_tournament_revenue(tier), revenue)
		assert_eq(TournamentSystem.get_net_profit(tier), revenue - data.entry_cost)
		assert_gt(TournamentSystem.get_net_profit(tier), 0, "%s pays for itself" % data.name)

func test_results_are_played_to_the_par_of_the_open_holes() -> void:
	var course := _course(9)
	course.holes[0].is_open = false
	var results := TournamentSystem.generate_tournament_results(
		TournamentSystem.TournamentTier.LOCAL, course, {"difficulty": 5.0})
	assert_eq(results.par, 8 * 4, "Eight open par 4s")
	assert_eq(results.scores.size(), 12, "One score per competitor")
	assert_eq(results.winning_score, results.scores.min(), "The winner has the lowest score")


# ---------------------------------------------------------------------------
# Cooldown and saving
# ---------------------------------------------------------------------------

func test_the_cooldown_counts_down_from_the_last_event() -> void:
	manager.last_tournament_end_day = 10
	GameManager.current_day = 10
	assert_eq(manager.get_cooldown_remaining(), TournamentManager.TOURNAMENT_COOLDOWN)
	GameManager.current_day = 13
	assert_eq(manager.get_cooldown_remaining(), TournamentManager.TOURNAMENT_COOLDOWN - 3)
	GameManager.current_day = 10 + TournamentManager.TOURNAMENT_COOLDOWN + 5
	assert_eq(manager.get_cooldown_remaining(), 0, "Never below zero")

func test_an_event_in_progress_is_not_resumed_from_a_save() -> void:
	manager.load_save_data({
		"current_tier": TournamentSystem.TournamentTier.REGIONAL,
		"state": TournamentSystem.TournamentState.IN_PROGRESS,
		"start_day": 10,
		"last_end_day": 5,
	})
	assert_eq(manager.current_tournament_state, TournamentSystem.TournamentState.NONE,
		"IN_PROGRESS should revert to NONE on load")
	assert_eq(manager.current_tournament_tier, -1, "Tier should reset when reverting from IN_PROGRESS")
	assert_eq(manager.last_tournament_end_day, 5, "The cooldown still runs from the last event")

func test_a_scheduled_event_survives_a_save_round_trip() -> void:
	manager.current_tournament_tier = TournamentSystem.TournamentTier.NATIONAL
	manager.current_tournament_state = TournamentSystem.TournamentState.SCHEDULED
	manager.tournament_start_day = 15
	manager.last_tournament_end_day = 5
	var loaded: TournamentManager = autofree(TournamentManager.new())
	loaded.load_save_data(JSON.parse_string(JSON.stringify(manager.get_save_data())))
	assert_eq(loaded.current_tournament_state, TournamentSystem.TournamentState.SCHEDULED)
	assert_eq(loaded.current_tournament_tier, TournamentSystem.TournamentTier.NATIONAL)
	assert_eq(loaded.tournament_start_day, 15)
	assert_eq(loaded.last_tournament_end_day, 5)

func test_a_save_without_tournament_data_starts_with_no_event() -> void:
	manager.load_save_data({})
	assert_eq(manager.current_tournament_state, TournamentSystem.TournamentState.NONE)
	assert_eq(manager.current_tournament_tier, -1)
	GameManager.current_day = 1
	assert_eq(manager.get_cooldown_remaining(), 0, "No past event, no cooldown")
