extends RefCounted
class_name ClubMembership
## ClubMembership - the club's four membership tiers and the rules that move a
## visiting golfer between them.
##
## Every visiting golfer is a **Non-member**, a **Bronze member**, a **Silver
## member** or a **Gold member**. Membership is earned on the course: a golfer
## who enjoys their round signs up or moves up a tier, and a golfer who has a
## poor one - overpriced, slow, hungry or just not much fun - moves down, and a
## Bronze member who has had enough cancels back to Non-member.
##
## Members are worth more to the club in two ways:
##
##   * they pay a higher green fee - a member greens fee is the public fee times
##     that tier's `fee_multiplier`, and the club also banks a one-off joining
##     fee when a golfer signs up;
##   * they are more likely to talk other visiting golfers into joining, which is
##     what `referral_chance()` is for (see FeedbackManager.attempt_referrals).
##
## This class is pure data and arithmetic: it holds no live golfer state, so the
## rules can be tested and tuned without a course. FeedbackManager owns the
## register (the customer profiles keep each member's tier) and the Golfer node
## carries the tier for the round it is playing.

enum Tier {
	NON_MEMBER = 0,  # Pays the public green fee
	BRONZE = 1,      # First tier: a golfer who liked what they saw
	SILVER = 2,      # A regular who keeps coming back happy
	GOLD = 3,        # The club's staunchest member
}

## A round at or above this satisfaction signs a guest up or moves them up.
const UPGRADE_THRESHOLD: float = 0.68
## A member whose round scores at or below this moves down a tier.
const DOWNGRADE_THRESHOLD: float = 0.35
## Below this value-for-money ratio a round blocks promotion and costs a tier:
## nobody joins a club that charges far more than the round is worth.
const VALUE_FLOOR: float = 0.30
## A round is "slow" past this many seconds waiting on the group ahead.
const SLOW_ROUND_SECONDS: float = 60.0
## Below this needs satisfaction the golfer went without food, drink or rest.
const NEGLECTED_NEEDS: float = 0.35

## Per-tier data. `fee_multiplier` is what the golfer pays per hole on top of
## the public fee, `joining_fee` is the one-off club income when a golfer signs
## up at that tier, `referral_chance` is how likely a contented member of that
## tier is to recruit one other visiting golfer, and `price_tolerance` widens
## the fair price a member compares their fee against (members expect to pay
## more, so they do not call their own fee overpriced).
const TIER_DATA: Dictionary = {
	Tier.NON_MEMBER: {
		"name": "Non-member",
		"fee_multiplier": 1.0,
		"joining_fee": 0,
		"referral_chance": 0.0,
		"price_tolerance": 1.0,
		"color": "b9c7af",
	},
	Tier.BRONZE: {
		"name": "Bronze member",
		"fee_multiplier": 1.15,
		"joining_fee": 25,
		"referral_chance": 0.10,
		"price_tolerance": 1.15,
		"color": "c98b5e",
	},
	Tier.SILVER: {
		"name": "Silver member",
		"fee_multiplier": 1.30,
		"joining_fee": 60,
		"referral_chance": 0.20,
		"price_tolerance": 1.30,
		"color": "cdd3d6",
	},
	Tier.GOLD: {
		"name": "Gold member",
		"fee_multiplier": 1.50,
		"joining_fee": 120,
		"referral_chance": 0.35,
		"price_tolerance": 1.50,
		"color": "e5c57c",
	},
}

## The four tier values, low to high.
const TIERS: Array[int] = [Tier.NON_MEMBER, Tier.BRONZE, Tier.SILVER, Tier.GOLD]

# ---------------------------------------------------------------------------
# Tier data
# ---------------------------------------------------------------------------

static func tier_name(tier: int) -> String:
	return str(TIER_DATA.get(tier, TIER_DATA[Tier.NON_MEMBER]).get("name", "Non-member"))

## The multiplier a member pays on the public per-hole green fee.
static func fee_multiplier(tier: int) -> float:
	return float(TIER_DATA.get(tier, TIER_DATA[Tier.NON_MEMBER]).get("fee_multiplier", 1.0))

## One-off club income when a golfer signs up at `tier` (0 for Non-member).
static func joining_fee(tier: int) -> int:
	return int(TIER_DATA.get(tier, TIER_DATA[Tier.NON_MEMBER]).get("joining_fee", 0))

## The fair price a golfer of this tier judges their fee against.
static func price_tolerance(tier: int) -> float:
	return float(TIER_DATA.get(tier, TIER_DATA[Tier.NON_MEMBER]).get("price_tolerance", 1.0))

static func tier_color(tier: int) -> Color:
	return Color(str(TIER_DATA.get(tier, TIER_DATA[Tier.NON_MEMBER]).get("color", "b9c7af")))

## Whether `tier` is a real membership (anything above Non-member).
static func is_member(tier: int) -> bool:
	return tier > Tier.NON_MEMBER

## Keep a raw value inside the four tiers.
static func clamp_tier(tier: int) -> int:
	return clampi(tier, Tier.NON_MEMBER, Tier.GOLD)

# ---------------------------------------------------------------------------
# What the club can sell
# ---------------------------------------------------------------------------

## The highest tier a club of this standing can sell. Every club signs Bronze
## members; Silver needs a club golfers rate, and Gold needs a club with both a
## rating and a name.
static func max_tier_for_course(course_rating: float, reputation: float) -> int:
	if course_rating >= 3.5 and reputation >= 65.0:
		return Tier.GOLD
	if course_rating >= 2.5 and reputation >= 40.0:
		return Tier.SILVER
	return Tier.BRONZE

# ---------------------------------------------------------------------------
# The round's verdict
# ---------------------------------------------------------------------------

## The tier a golfer holds after a round, given the visit satisfaction (0..1,
## needs + attitude + value), the value-for-money ratio (fair / paid, 0..1) and
## the club's ceiling.
##
##   * a non-member who loved a fair-priced round joins at Bronze;
##   * a member who loved it moves up one tier, up to the club's ceiling;
##   * a member who had a poor round, or paid far over the fair price, moves
##     down one tier (Bronze falls back to Non-member);
##   * everything else holds.
## `promotion_boost` is how much a member's recommendation is worth to this
## golfer: a golfer a member talked into a round is quicker to sign up.
static func change_for_round(current_tier: int, satisfaction: float,
		value: float, max_tier: int, promotion_boost: float = 0.0) -> int:
	var tier := clamp_tier(current_tier)
	var ceiling: int = clampi(max_tier, Tier.BRONZE, Tier.GOLD)
	var promoted := satisfaction + promotion_boost >= UPGRADE_THRESHOLD and value >= VALUE_FLOOR
	var demoted := satisfaction <= DOWNGRADE_THRESHOLD or value < VALUE_FLOOR

	if tier == Tier.NON_MEMBER:
		return mini(Tier.BRONZE, ceiling) if promoted else Tier.NON_MEMBER
	if demoted:
		return tier - 1
	if promoted:
		return mini(tier + 1, ceiling)
	return tier

## A human-readable reason for the tier change, drawn from what actually made
## the round good or bad. `facts` carries the round's numbers:
## `value`, `wait_seconds`, `needs`, `attitude`, `fun`, `score_vs_par`, `score`.
static func reason_for(change: int, facts: Dictionary) -> String:
	if change == 0:
		return ""
	var value := float(facts.get("value", 0.5))
	var wait := float(facts.get("wait_seconds", 0.0))
	var needs := float(facts.get("needs", 0.5))
	var attitude := float(facts.get("attitude", 0.5))
	var fun := float(facts.get("fun", 0.5))
	var score_vs_par := int(facts.get("score_vs_par", 0))
	if change > 0:
		if value >= 0.70:
			return "Great value for the money"
		if score_vs_par < 0:
			return "Played well and loved the course"
		if attitude >= 0.70 or fun >= 0.70:
			return "Enjoyed the round"
		if wait < 30.0:
			return "Friendly club and a good pace of play"
		return "Enjoyed the round"
	# A downgrade: name the worst thing about the round first.
	if value < VALUE_FLOOR:
		return "Green fees felt too high"
	if wait >= SLOW_ROUND_SECONDS:
		return "Rounds are too slow"
	if needs < NEGLECTED_NEEDS:
		return "Ran out of food, drink or rest"
	if attitude <= 0.35:
		return "Did not enjoy the round"
	return "A disappointing round"

## How much a member's recommendation is worth when the golfer's round is
## judged: a referred golfer starts out well disposed to the club.
const REFERRAL_PROMOTION_BOOST: float = 0.08

## The round facts `reason_for` reads, taken from a golfer and the visit score.
static func round_facts(golfer, satisfaction: float, value: float) -> Dictionary:
	var attributes = golfer.attributes
	return {
		"score": satisfaction,
		"value": value,
		"wait_seconds": float(golfer.traffic_wait_seconds),
		"needs": float(attributes.get_overall_satisfaction()) if attributes else 0.5,
		"attitude": float(attributes.attitude) if attributes else 0.5,
		"fun": float(attributes.fun) if attributes else 0.5,
		"score_vs_par": int(golfer.total_strokes) - int(golfer.total_par),
	}

# ---------------------------------------------------------------------------
# Referrals and demand
# ---------------------------------------------------------------------------

## How likely a member of `tier` is to talk one other visiting golfer into
## joining, after a round they scored `satisfaction` on. An unhappy member
## recruits nobody: the chance rises from zero at a middling round to the
## tier's full `referral_chance` at a perfect one.
static func referral_chance(tier: int, satisfaction: float) -> float:
	if not is_member(tier):
		return 0.0
	var base := float(TIER_DATA[tier].get("referral_chance", 0.0))
	var mood := clampf((satisfaction - 0.5) / 0.5, 0.0, 1.0)
	return base * mood

## The word-of-mouth demand bonus a club's members bring: each member a small
## lift, capped so a popular club never spawns golfers without limit.
static func demand_modifier(member_count: int) -> float:
	return clampf(1.0 + 0.02 * float(maxi(member_count, 0)), 1.0, 1.20)
