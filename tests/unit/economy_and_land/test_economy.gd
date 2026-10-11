extends GameTest
## The company's money: what it can afford before spending is blocked, the green
## fee and the cap the open holes put on it, staff wage tiers, what a new game
## starts with, and the books a day rollover keeps.

# ---------------------------------------------------------------------------
# Money and bankruptcy
# ---------------------------------------------------------------------------

func test_modify_money_adds_positive_amount() -> void:
	var before := GameManager.money
	GameManager.modify_money(100)
	assert_eq(GameManager.money, before + 100, "Money should increase by 100")

func test_modify_money_subtracts_negative_amount() -> void:
	var before := GameManager.money
	GameManager.modify_money(-50)
	assert_eq(GameManager.money, before - 50, "Money should decrease by 50")

func test_can_afford_returns_true_for_affordable_cost() -> void:
	GameManager.money = 10000
	assert_true(GameManager.can_afford(5000), "Should afford 5000 with 10000")

func test_can_afford_returns_true_when_cost_dips_into_negative() -> void:
	GameManager.money = 500
	# Bankruptcy threshold is -1000, so 500 - 1400 = -900 >= -1000
	assert_true(GameManager.can_afford(1400), "Should allow spending that keeps above bankruptcy threshold")

func test_can_afford_returns_false_when_below_bankruptcy() -> void:
	GameManager.money = 500
	# 500 - 1600 = -1100 < -1000 (BANKRUPTCY_THRESHOLD)
	assert_false(GameManager.can_afford(1600), "Should reject spending below bankruptcy threshold")

func test_can_afford_returns_true_for_zero_cost() -> void:
	GameManager.money = 100
	assert_true(GameManager.can_afford(0), "Zero cost should always be affordable")

func test_can_afford_returns_true_for_negative_cost() -> void:
	# Negative cost means gaining money (not a purchase)
	GameManager.money = -5000
	assert_true(GameManager.can_afford(-100), "Negative cost (income) should always be true")

func test_is_bankrupt_when_below_threshold() -> void:
	GameManager.money = -1001
	assert_true(GameManager.is_bankrupt(), "Should be bankrupt below -1000")

func test_is_not_bankrupt_above_threshold() -> void:
	GameManager.money = -999
	assert_false(GameManager.is_bankrupt(), "Should not be bankrupt above threshold")

func test_is_not_bankrupt_at_threshold() -> void:
	GameManager.money = -1000
	assert_false(GameManager.is_bankrupt(), "-1000 is exactly at threshold, not below it")

## The notice used to say "-$1,000" whatever the difficulty's limit was.
func test_spending_blocked_message_uses_the_difficulty_threshold() -> void:
	GameManager.bankruptcy_threshold = -5000
	assert_eq(GameManager.spending_blocked_message(), "Spending blocked! Balance below -$5,000",
		"Easy's -$5,000 limit is shown")
	GameManager.bankruptcy_threshold = -1000
	assert_eq(GameManager.spending_blocked_message(), "Spending blocked! Balance below -$1,000",
		"Normal's -$1,000 limit is shown")
	GameManager.bankruptcy_threshold = 0
	assert_eq(GameManager.spending_blocked_message(), "Spending blocked! Balance below $0",
		"Hard's zero limit reads as $0, not -$0")


# ---------------------------------------------------------------------------
# Green fee
# ---------------------------------------------------------------------------

## A course of `count` open par 4s, made the game's own.
func _use_course_of_open_holes(count: int) -> void:
	var course := GameManager.CourseData.new()
	for i in range(count):
		var hole := GameManager.HoleData.new()
		hole.par = 4
		hole.is_open = true
		course.add_hole(hole)
	GameManager.current_course = course

func test_set_green_fee_clamps_to_min() -> void:
	GameManager.set_green_fee(1)
	assert_eq(GameManager.green_fee, GameManager.MIN_GREEN_FEE, "Should clamp to minimum")

func test_set_green_fee_clamps_to_effective_max() -> void:
	# With 18 holes, effective max = min(18*10, 200) = $180
	_use_course_of_open_holes(18)
	GameManager.set_green_fee(999)
	assert_eq(GameManager.green_fee, 180, "18 holes should allow max $180")

func test_set_green_fee_clamps_by_hole_count() -> void:
	# With 3 holes, effective max = 3*10 = $30
	_use_course_of_open_holes(3)
	GameManager.set_green_fee(100)
	assert_eq(GameManager.green_fee, 30, "3 holes should cap fee at $30")

func test_set_green_fee_accepts_valid_value() -> void:
	# Set up enough holes so $75 is under the cap (need 8+ holes: 8*10=80)
	_use_course_of_open_holes(8)
	GameManager.set_green_fee(75)
	assert_eq(GameManager.green_fee, 75, "Should accept 75 as valid fee with 8 holes")

func test_set_green_fee_accepts_min_boundary() -> void:
	GameManager.set_green_fee(GameManager.MIN_GREEN_FEE)
	assert_eq(GameManager.green_fee, GameManager.MIN_GREEN_FEE, "Should accept min boundary")

func test_get_effective_max_fee_scales_with_holes() -> void:
	_use_course_of_open_holes(6)
	# 6 holes * $10 = $60
	assert_eq(GameManager.get_effective_max_green_fee(), 60, "6 holes should have max fee $60")


# ---------------------------------------------------------------------------
# Staff wage tiers
# ---------------------------------------------------------------------------

func test_staff_tier_data_has_all_tiers() -> void:
	assert_true(GameManager.STAFF_TIER_DATA.has(GameManager.StaffTier.PART_TIME))
	assert_true(GameManager.STAFF_TIER_DATA.has(GameManager.StaffTier.FULL_TIME))
	assert_true(GameManager.STAFF_TIER_DATA.has(GameManager.StaffTier.PREMIUM))

func test_staff_tier_costs_increase() -> void:
	var part_time = GameManager.STAFF_TIER_DATA[GameManager.StaffTier.PART_TIME].cost_per_hole
	var full_time = GameManager.STAFF_TIER_DATA[GameManager.StaffTier.FULL_TIME].cost_per_hole
	var premium = GameManager.STAFF_TIER_DATA[GameManager.StaffTier.PREMIUM].cost_per_hole
	assert_lt(part_time, full_time, "Part-time should be cheaper than full-time")
	assert_lt(full_time, premium, "Full-time should be cheaper than premium")


# ---------------------------------------------------------------------------
# A new game and a new day
# ---------------------------------------------------------------------------

func test_new_game_resets_state() -> void:
	GameManager.money = 999
	GameManager.reputation = 10.0
	GameManager.current_day = 50
	GameManager.green_fee = 100

	GameManager.new_game("Test Course")

	assert_eq(GameManager.money, GameManager.DEFAULT_STARTING_MONEY, "Money should reset to default")
	assert_eq(GameManager.reputation, 50.0, "Reputation should reset to 50")
	assert_eq(GameManager.current_day, 1, "Day should reset to 1")
	assert_eq(GameManager.course_name, "Test Course", "Course name should be set")
	assert_eq(GameManager.green_fee, GameManager.MIN_GREEN_FEE, "Green fee should reset to min (no holes yet)")
	assert_eq(GameManager._day_progress, 0.0, "Day timer should reset")

## yesterday_stats used to be copied field by field and dropped decoration costs.
func test_day_rollover_keeps_every_cost_category_in_yesterdays_books() -> void:
	# Mid-year so the rollover does not trigger the year-end summary.
	GameManager.current_day = 100
	GameManager.yearly_stats = GameManager.DailyStatistics.new()
	GameManager.daily_stats = GameManager.DailyStatistics.new()
	GameManager.daily_stats.revenue = 500
	GameManager.daily_stats.operating_costs = 90
	GameManager.daily_stats.decoration_operating_costs = 7
	GameManager.daily_stats.staff_wages = 40
	GameManager.daily_stats.tier_counts[GolferTier.Tier.PRO] = 3

	GameManager.advance_to_next_day()

	var yesterday := GameManager.yesterday_stats
	assert_not_null(yesterday, "Yesterday's stats are kept after rollover")
	assert_eq(yesterday.revenue, 500, "Revenue is carried over")
	assert_eq(yesterday.operating_costs, 90, "Operating costs are carried over")
	assert_eq(yesterday.decoration_operating_costs, 7, "Decoration costs are carried over")
	assert_eq(yesterday.staff_wages, 40, "Staff wages are carried over")
	assert_eq(yesterday.tier_counts[GolferTier.Tier.PRO], 3, "Tier counts are carried over")
	assert_eq(GameManager.daily_stats.revenue, 0, "The new day starts with zeroed stats")
