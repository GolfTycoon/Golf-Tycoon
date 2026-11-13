extends GameTest
## Club membership (ClubMembership): the four tiers, the fee premium members
## pay, the joining fee the club banks, and the rules that move a visiting
## golfer up or down after a round. Also the register FeedbackManager keeps:
## who is a member, the reasons they gave, and the referrals members bring in.

var _saved_experience: Dictionary

func before_each() -> void:
	super()
	_saved_experience = FeedbackManager.serialize_experience()
	FeedbackManager.restore_experience({})
	GameManager.daily_stats = GameManager.DailyStatistics.new()

func after_each() -> void:
	FeedbackManager.restore_experience(_saved_experience)
	super()

## A visiting golfer that is not in the scene, freed after the test.
func _visitor(golfer_name: String = "Visitor", tier: int = ClubMembership.Tier.NON_MEMBER) -> Golfer:
	var golfer: Golfer = autofree(Golfer.new())
	golfer.golfer_name = golfer_name
	golfer.attributes = GolferAttributes.new()
	golfer.membership_tier = tier
	return golfer

## A course good enough to sell every tier.
func _open_the_top_tier() -> void:
	GameManager.course_rating = {"overall": 5.0, "difficulty": 5.0}
	GameManager.reputation = 80.0

# ---------------------------------------------------------------------------
# The tiers themselves
# ---------------------------------------------------------------------------

func test_the_four_tiers_are_named_and_ordered() -> void:
	assert_eq(ClubMembership.TIERS.size(), 4)
	assert_eq(ClubMembership.tier_name(ClubMembership.Tier.NON_MEMBER), "Non-member")
	assert_eq(ClubMembership.tier_name(ClubMembership.Tier.BRONZE), "Bronze member")
	assert_eq(ClubMembership.tier_name(ClubMembership.Tier.SILVER), "Silver member")
	assert_eq(ClubMembership.tier_name(ClubMembership.Tier.GOLD), "Gold member")
	assert_false(ClubMembership.is_member(ClubMembership.Tier.NON_MEMBER),
		"A non-member holds no membership")
	for tier in [ClubMembership.Tier.BRONZE, ClubMembership.Tier.SILVER, ClubMembership.Tier.GOLD]:
		assert_true(ClubMembership.is_member(tier), "%s is a membership" % ClubMembership.tier_name(tier))

func test_members_pay_more_and_join_at_higher_cost() -> void:
	var previous_fee := 0.0
	var previous_joining := 0
	var previous_referral := 0.0
	for tier in ClubMembership.TIERS:
		assert_gt(ClubMembership.fee_multiplier(tier), previous_fee,
			"%s pays more than the tier below" % ClubMembership.tier_name(tier))
		assert_gt(ClubMembership.joining_fee(tier), previous_joining - 1,
			"%s never joins for less than the tier below" % ClubMembership.tier_name(tier))
		assert_gte(float(ClubMembership.TIER_DATA[tier].referral_chance), previous_referral,
			"%s recruits at least as well as the tier below" % ClubMembership.tier_name(tier))
		previous_fee = ClubMembership.fee_multiplier(tier)
		previous_joining = ClubMembership.joining_fee(tier)
		previous_referral = float(ClubMembership.TIER_DATA[tier].referral_chance)

func test_only_a_rated_club_with_a_name_sells_the_top_tier() -> void:
	assert_eq(ClubMembership.max_tier_for_course(1.0, 10.0), ClubMembership.Tier.BRONZE)
	assert_eq(ClubMembership.max_tier_for_course(3.0, 50.0), ClubMembership.Tier.SILVER)
	assert_eq(ClubMembership.max_tier_for_course(4.5, 80.0), ClubMembership.Tier.GOLD)
	assert_eq(ClubMembership.max_tier_for_course(5.0, 20.0), ClubMembership.Tier.BRONZE,
		"A famous course with no name to it still sells only Bronze")

# ---------------------------------------------------------------------------
# The round's verdict
# ---------------------------------------------------------------------------

func test_an_enjoyed_round_signs_a_non_member_up() -> void:
	var new_tier := ClubMembership.change_for_round(
		ClubMembership.Tier.NON_MEMBER, 0.9, 0.9, ClubMembership.Tier.GOLD)
	assert_eq(new_tier, ClubMembership.Tier.BRONZE, "A happy guest joins at Bronze")

func test_a_middling_round_leaves_the_tier_alone() -> void:
	var tier := ClubMembership.change_for_round(
		ClubMembership.Tier.SILVER, 0.5, 0.8, ClubMembership.Tier.GOLD)
	assert_eq(tier, ClubMembership.Tier.SILVER)

func test_a_member_who_loved_the_round_moves_up_one_tier() -> void:
	var tier := ClubMembership.change_for_round(
		ClubMembership.Tier.BRONZE, 0.9, 0.9, ClubMembership.Tier.GOLD)
	assert_eq(tier, ClubMembership.Tier.SILVER, "One tier at a time")
	tier = ClubMembership.change_for_round(tier, 0.9, 0.9, ClubMembership.Tier.GOLD)
	assert_eq(tier, ClubMembership.Tier.GOLD)

func test_the_clubs_standing_caps_the_tier_it_can_sell() -> void:
	var tier := ClubMembership.change_for_round(
		ClubMembership.Tier.BRONZE, 0.95, 1.0, ClubMembership.Tier.BRONZE)
	assert_eq(tier, ClubMembership.Tier.BRONZE, "A modest club has nothing higher to sell")
	# The ceiling still never blocks a move down.
	tier = ClubMembership.change_for_round(
		ClubMembership.Tier.SILVER, 0.1, 0.1, ClubMembership.Tier.BRONZE)
	assert_eq(tier, ClubMembership.Tier.BRONZE)

func test_a_poor_round_moves_a_member_down_and_a_bronze_member_out() -> void:
	assert_eq(ClubMembership.change_for_round(
		ClubMembership.Tier.GOLD, 0.2, 0.9, ClubMembership.Tier.GOLD),
		ClubMembership.Tier.SILVER)
	assert_eq(ClubMembership.change_for_round(
		ClubMembership.Tier.BRONZE, 0.2, 0.9, ClubMembership.Tier.GOLD),
		ClubMembership.Tier.NON_MEMBER, "A Bronze member who had enough cancels")

func test_an_overpriced_round_blocks_promotion_and_costs_a_tier() -> void:
	assert_eq(ClubMembership.change_for_round(
		ClubMembership.Tier.NON_MEMBER, 0.95, 0.1, ClubMembership.Tier.GOLD),
		ClubMembership.Tier.NON_MEMBER, "Nobody joins a club that charges far too much")
	assert_eq(ClubMembership.change_for_round(
		ClubMembership.Tier.SILVER, 0.95, 0.1, ClubMembership.Tier.GOLD),
		ClubMembership.Tier.BRONZE)

func test_a_members_recommendation_helps_a_referred_golfer_join() -> void:
	var satisfaction := ClubMembership.UPGRADE_THRESHOLD - 0.04
	assert_eq(ClubMembership.change_for_round(
		ClubMembership.Tier.NON_MEMBER, satisfaction, 0.9, ClubMembership.Tier.GOLD),
		ClubMembership.Tier.NON_MEMBER, "On their own, the round was not quite enough")
	assert_eq(ClubMembership.change_for_round(
		ClubMembership.Tier.NON_MEMBER, satisfaction, 0.9, ClubMembership.Tier.GOLD,
		ClubMembership.REFERRAL_PROMOTION_BOOST),
		ClubMembership.Tier.BRONZE, "A member's word tips the scale")

func test_the_reasons_name_what_the_round_was_like() -> void:
	assert_eq(ClubMembership.reason_for(0, {}), "", "No change, no reason")
	assert_eq(ClubMembership.reason_for(1, {"value": 0.95}), "Great value for the money")
	assert_eq(ClubMembership.reason_for(1, {"value": 0.6, "score_vs_par": -3}),
		"Played well and loved the course")
	assert_eq(ClubMembership.reason_for(-1, {"value": 0.1}), "Green fees felt too high")
	assert_eq(ClubMembership.reason_for(-1, {"value": 0.8, "wait_seconds": 300.0}),
		"Rounds are too slow")
	assert_eq(ClubMembership.reason_for(-1, {"value": 0.8, "needs": 0.1}),
		"Ran out of food, drink or rest")

func test_a_referred_golfer_is_more_likely_to_be_signed_up() -> void:
	var golfer := _visitor()
	golfer.guest_key = "referred"
	golfer._round_total_holes = 9
	golfer.attributes.fun = 0.95
	golfer.attributes.attitude = 0.95
	golfer.attributes.energy = 0.95
	golfer.attributes.hunger = 0.95
	golfer.attributes.thirst = 0.95
	golfer.paid_round_fee = 1
	golfer.referred_by_member = true
	_open_the_top_tier()
	var result := FeedbackManager.settle_membership(golfer, "referred", 0.66, 1.0)
	assert_eq(result["new"], ClubMembership.Tier.BRONZE,
		"A referred guest signs up on a slightly-less-than-perfect round")

# ---------------------------------------------------------------------------
# The register FeedbackManager keeps
# ---------------------------------------------------------------------------

func test_a_visit_records_the_membership_and_its_reason() -> void:
	GameManager.course_rating = {"overall": 5.0, "difficulty": 5.0}
	GameManager.reputation = 80.0
	var golfer := _visitor()
	golfer.guest_key = "member-to-be"
	golfer._round_total_holes = 9
	golfer.paid_round_fee = 10
	golfer.attributes.fun = 0.95
	golfer.attributes.attitude = 0.95
	golfer.attributes.energy = 0.95
	golfer.attributes.hunger = 0.95
	golfer.attributes.thirst = 0.95
	FeedbackManager.record_visit(golfer)
	assert_eq(golfer.membership_tier, ClubMembership.Tier.BRONZE,
		"The golfer is a member for the rest of their visit")
	assert_eq(int(FeedbackManager.customers[0].membership), ClubMembership.Tier.BRONZE,
		"The customer profile keeps the membership for next time")
	assert_eq(FeedbackManager.membership_for_customer("member-to-be"), ClubMembership.Tier.BRONZE)
	assert_false(FeedbackManager.membership_reason_for("member-to-be").is_empty(),
		"The golfer's reason is kept with the profile")
	assert_eq(FeedbackManager.membership_summary().members, 1)
	assert_gt(GameManager.daily_stats.membership_income, 0, "The joining fee is banked")
	assert_eq(GameManager.daily_stats.members_joined, 1)

func test_a_poor_visit_cancels_a_bronze_membership() -> void:
	var golfer := _visitor("Unhappy", ClubMembership.Tier.BRONZE)
	golfer.guest_key = "unhappy"
	golfer._round_total_holes = 9
	golfer.paid_round_fee = 100000  # Wildly overpriced
	golfer.attributes.fun = 0.0
	golfer.attributes.attitude = 0.0
	golfer.attributes.energy = 0.0
	golfer.attributes.hunger = 0.0
	golfer.attributes.thirst = 0.0
	FeedbackManager.record_visit(golfer)
	assert_eq(golfer.membership_tier, ClubMembership.Tier.NON_MEMBER)
	assert_eq(FeedbackManager.membership_summary().members, 0)
	assert_eq(GameManager.daily_stats.membership_income, 0, "No joining fee for a cancellation")

func test_membership_counts_add_up_and_raise_demand() -> void:
	FeedbackManager.customers = [
		{"key": "a", "membership": ClubMembership.Tier.GOLD},
		{"key": "b", "membership": ClubMembership.Tier.SILVER},
		{"key": "c", "membership": ClubMembership.Tier.BRONZE},
		{"key": "d", "membership": ClubMembership.Tier.NON_MEMBER},
		{"key": "e"},
	]
	var summary := FeedbackManager.membership_summary()
	assert_eq(summary.members, 3)
	assert_eq(summary.gold, 1)
	assert_eq(summary.silver, 1)
	assert_eq(summary.bronze, 1)
	assert_gt(summary.average_fee_multiplier, 1.0, "Members pay a premium")
	assert_eq(summary.demand_modifier, ClubMembership.demand_modifier(3))
	assert_almost_eq(ClubMembership.demand_modifier(10_000), 1.20, 0.0001,
		"Word of mouth is capped")

func test_membership_survives_a_save_and_a_load() -> void:
	FeedbackManager.customers = [{
		"key": "save-test", "name": "Saved Member", "tier": 1, "last_day": 1, "intent": 0.8,
		"membership": ClubMembership.Tier.GOLD, "membership_reason": "Enjoyed the round",
	}]
	FeedbackManager.referrals_today = 2
	FeedbackManager.referrals_pending = 1
	var data: Dictionary = JSON.parse_string(JSON.stringify(FeedbackManager.serialize_experience()))
	FeedbackManager.restore_experience({})
	assert_eq(FeedbackManager.membership_summary().members, 0, "Starting over has no members")
	FeedbackManager.restore_experience(data)
	assert_eq(FeedbackManager.membership_for_guest("Saved Member"), ClubMembership.Tier.GOLD)
	assert_eq(FeedbackManager.referrals_today, 2)
	assert_eq(FeedbackManager.referrals_pending, 1)

func test_an_older_save_makes_everyone_a_non_member() -> void:
	FeedbackManager.restore_experience({"customers": [
		{"key": "old", "name": "Old Save", "tier": 2, "last_day": 1, "intent": 0.7},
	]})
	assert_eq(FeedbackManager.membership_for_guest("Old Save"), ClubMembership.Tier.NON_MEMBER,
		"Profiles saved before club membership existed start as non-members")

# ---------------------------------------------------------------------------
# Green fees and referrals
# ---------------------------------------------------------------------------

func test_a_member_pays_a_higher_green_fee() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	for i in range(9):
		GameManager.current_course.add_hole(make_hole(i + 1, Vector2i(i, 0), Vector2i(i, 10)))
	GameManager.green_fee = 10
	var before := GameManager.money
	GameManager.process_green_fee_payment(1, "Public Golfer", ClubMembership.Tier.NON_MEMBER)
	var public_fee := GameManager.money - before
	before = GameManager.money
	GameManager.process_green_fee_payment(2, "Gold Golfer", ClubMembership.Tier.GOLD)
	var member_fee := GameManager.money - before
	assert_gt(member_fee, public_fee,
		"A Gold member's green fee is the public fee plus the membership premium")
	assert_eq(member_fee, int(round(public_fee * ClubMembership.fee_multiplier(ClubMembership.Tier.GOLD))),
		"The premium is exactly the tier's multiplier")

func test_a_member_is_not_overcharged_by_their_own_premium() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	for i in range(18):
		GameManager.current_course.add_hole(make_hole(i + 1, Vector2i(i, 0), Vector2i(i, 10)))
	GameManager.reputation = 50.0
	GameManager.current_day = 100
	# A fee 60% over the public fair price: the Gold member's own fair price is
	# half again as high, so they are content, while a Non-member - who never
	# agreed to a premium - calls the same fee overpriced.
	var fair := CourseEconomy.fair_round_price(50.0, 18, GameManager.current_day, GameManager.current_theme)
	var fee := int(round(fair * 1.6))
	assert_eq(FeedbackTriggers.get_price_trigger(fee, 50.0, ClubMembership.Tier.GOLD),
		FeedbackTriggers.TriggerType.NONE, "Members expect to pay more")
	assert_eq(FeedbackTriggers.get_price_trigger(fee, 50.0, ClubMembership.Tier.NON_MEMBER),
		FeedbackTriggers.TriggerType.OVERPRICED,
		"The same fee is overpriced for a non-member, who never agreed to it")

func test_a_members_referral_brings_one_golfer_and_is_counted() -> void:
	assert_false(FeedbackManager.consume_referral("Nobody"), "No referral, no arrival")
	FeedbackManager.referrals_pending = 1
	assert_true(FeedbackManager.consume_referral("First Arrival"))
	assert_eq(FeedbackManager.referrals_today, 1)
	assert_false(FeedbackManager.consume_referral("Second Arrival"),
		"One referral brings one golfer")
	assert_eq(FeedbackManager.referrals_pending, 0)
	assert_gt(FeedbackManager.visit_summary().referrals, 0,
		"The day's reviews report the referrals")

func test_an_unhappy_member_recruits_nobody() -> void:
	assert_eq(ClubMembership.referral_chance(ClubMembership.Tier.GOLD, 0.4), 0.0)
	assert_eq(ClubMembership.referral_chance(ClubMembership.Tier.NON_MEMBER, 1.0), 0.0,
		"A non-member has no club to talk up")
	assert_almost_eq(ClubMembership.referral_chance(ClubMembership.Tier.GOLD, 1.0), 0.35, 0.0001)
	assert_gt(ClubMembership.referral_chance(ClubMembership.Tier.GOLD, 0.9),
		ClubMembership.referral_chance(ClubMembership.Tier.BRONZE, 0.9),
		"A Gold member's word carries further")

# ---------------------------------------------------------------------------
# Arriving golfers
# ---------------------------------------------------------------------------

func test_a_returning_member_arrives_as_a_member_and_pays_the_premium() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	for i in range(9):
		GameManager.current_course.add_hole(make_hole(i + 1, Vector2i(i, 0), Vector2i(i, 10)))
	GameManager.green_fee = 10
	GameManager.reputation = 50.0
	var golfers := make_golfer_manager()
	# A Gold member who last played three days ago, and is certain to return.
	FeedbackManager.customers = [{
		"key": "regular", "name": "Regular Member", "tier": GolferTier.Tier.CASUAL,
		"last_day": GameManager.current_day - 3, "intent": 1.0,
		"patience": 0.5, "aggression": 0.5, "miss_tendency": 0.1,
		"membership": ClubMembership.Tier.GOLD, "attributes": {},
	}]
	var before := GameManager.money
	var golfer := golfers.spawn_random_golfer(1)
	assert_not_null(golfer, "The member comes back")
	if golfer == null:
		return
	assert_true(golfer.is_returning_guest)
	assert_eq(golfer.membership_tier, ClubMembership.Tier.GOLD,
		"A returning member keeps their membership")
	assert_eq(GameManager.money - before,
		int(round(10.0 * ClubMembership.fee_multiplier(ClubMembership.Tier.GOLD))) * 9,
		"...and pays the member's green fee")

func test_a_card_holder_keeps_their_membership_across_rounds() -> void:
	var golfers := make_golfer_manager()
	WorldMap.active_location_id = "scotland"
	# Every card in Scotland's pool is a Silver member of this club, so whichever
	# one the pool sends is a member (the pool picks at random).
	var customers: Array = []
	for entry in WorldLocations.get_visiting_golfers("scotland"):
		customers.append({
			"key": "card-" + str(entry["name"]), "name": str(entry["name"]),
			"tier": int(entry["tier"]), "last_day": GameManager.current_day - 5,
			"intent": 0.0, "membership": ClubMembership.Tier.SILVER, "attributes": {},
		})
	FeedbackManager.customers = customers
	var golfer := golfers.spawn_visiting_golfer(1)
	assert_not_null(golfer)
	if golfer == null:
		return
	assert_eq(golfer.membership_tier, ClubMembership.Tier.SILVER,
		"A named visitor's membership follows their name")
