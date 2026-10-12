extends GameTest
## The price reference ratings, demand and the financial advice share: the fair
## price of a round, and how many golfers a fee above it turns away.

func test_overpricing_reduces_demand_and_expected_green_fee_income() -> void:
	var fair_demand := CourseEconomy.price_demand(5, 9, 45.0)
	var expensive_demand := CourseEconomy.price_demand(10, 9, 45.0)
	assert_eq(fair_demand, 1.0)
	assert_eq(expensive_demand, 0.25, "Doubling a fair fee keeps a quarter of the demand")
	assert_lt(10 * expensive_demand, 5 * fair_demand, "so the extra income does not pay for itself")
	assert_lt(CourseEconomy.price_demand(100, 9, 45.0), 0.01, "There is no floor to exploit")

func test_a_bargain_draws_a_little_more_demand_but_never_unlimited() -> void:
	var cheap := CourseEconomy.price_demand(1, 9, 45.0)
	assert_gt(cheap, 1.0)
	assert_lte(cheap, 1.25, "Demand is capped however cheap the round")

func test_the_fair_price_grows_with_reputation_and_course_size() -> void:
	var day := 100
	var theme := CourseTheme.Type.PARKLAND
	var small := CourseEconomy.fair_round_price(50.0, 9, day, theme)
	assert_gt(CourseEconomy.fair_round_price(50.0, 18, day, theme), small, "More holes, a dearer round")
	assert_gt(CourseEconomy.fair_round_price(80.0, 9, day, theme), small, "A better name, a dearer round")

func test_a_tiny_course_with_no_name_still_has_a_floor_price() -> void:
	var price := CourseEconomy.fair_round_price(0.0, 1, 100, CourseTheme.Type.PARKLAND)
	assert_gt(price, 0.0)
	assert_almost_eq(price, 20.0 * 0.15 * SeasonSystem.get_fee_tolerance(100, CourseTheme.Type.PARKLAND), 0.0001,
		"The reputation floor and the smallest size factor apply")
