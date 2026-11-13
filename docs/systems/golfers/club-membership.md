# Club Membership

> Visiting golfers join the club, move up a tier while they are enjoying the course, and drop a tier - or leave - when they are not. Members pay a higher green fee, talk other golfers into joining, and make the club busier.

**Source:** `scripts/systems/club_membership.gd` (tiers, rules, fees, referrals), `scripts/autoload/feedback_manager.gd` (the member register, `record_visit` / `settle_membership`), `scripts/managers/golfer_manager.gd` (spawning members), `scripts/autoload/game_manager.gd` (`process_green_fee_payment`)
**Tests:** `tests/unit/golfers/test_club_membership.gd`

---

## Plain English

Every visiting golfer is a **Non-member**, a **Bronze member**, a **Silver member** or a **Gold member** of your club. Membership is not bought at the door: it is **earned after a round**, from how much the golfer enjoyed the visit.

- A **Non-member** who loved a fair-priced round **joins at Bronze**.
- A **member** who loved it **moves up one tier** - Bronze → Silver → Gold.
- A member whose round went poorly - overpriced, slow, hungry, thirsty or just not much fun - **moves down one tier**, and a Bronze member who has had enough **cancels back to Non-member**.
- A round in between changes nothing.

Every change comes with a **reason** the golfer gives, drawn from what actually decided it: "Great value for the money", "Rounds are too slow", "Green fees felt too high", "Ran out of food, drink or rest". The reason is shown on the round-complete toast, kept on the golfer's customer profile, and announced in the event feed.

### Why members matter

| Benefit | What it does |
| --- | --- |
| **Higher green fees** | A member pays the public fee times their tier's multiplier (Bronze 1.15x, Silver 1.30x, Gold 1.50x) every round they play. |
| **Joining fees** | The club banks a one-off joining fee when a golfer signs up or moves up: $25 Bronze, $60 Silver, $130 Gold. |
| **Referrals** | After a good round a contented member may talk **one other visiting golfer** into a round. That golfer arrives as a **referred guest**, and starts better disposed to the club - it takes less of a good round to sign them up. |
| **Word of mouth** | Every member is a small lift on arrivals (2% each, capped at +20%), so a club with a healthy membership gets busier on its own. |
| **Loyalty** | Members are likelier to come back: each tier adds 10% to a returning guest's chance of booking again. |

### The club's standing limits what it can sell

A golfer can only move up as far as the club's standing allows:

| Best tier on sale | Needs |
| --- | --- |
| **Gold** | Course rating 3.5 stars **and** reputation 65 |
| **Silver** | Course rating 2.5 stars **and** reputation 40 |
| **Bronze** | Always available |

The ceiling never blocks a move **down** - a Gold member on a course that has slipped can still drop to Silver, or out of the club.

### Where it shows

- The **round-complete toast** names the change and its reason ("Joined as a bronze member - enjoyed the round").
- The **event feed** announces joinings and upgrades (and, quietly, cancellations).
- The **Golfer Info popup**, the **Golfers tab guest register** and hovering a golfer's **name label** all show the membership and the green-fee premium.
- **Course Review**, the **course map's Guest experience card** and the **Year Summary** report the club's membership: how many Gold, Silver and Bronze members, the average fee premium, the word-of-mouth lift, the referrals the members brought in, and the best tier the club can sell today.
- The **daily accounts** carry membership income alongside green fees.

---

## Algorithm

### 1. The round's verdict

```
visit_score = 0.50 * needs_satisfaction + 0.25 * attitude + 0.25 * value
value       = clamp(fair_round_price / paid_fee, 0, 1)

promoted = visit_score + referral_boost >= 0.68  and  value >= 0.30
demoted  = visit_score <= 0.35  or  value < 0.30
```

`referral_boost` is `0.08` for a golfer a member recommended, otherwise `0`.

```
non-member : Bronze   if promoted            else Non-member
member     : tier - 1 if demoted
             tier + 1 if promoted (capped at the club's ceiling)
             tier     otherwise
```

The tier is stored on the golfer for the rest of the visit and on their customer profile for next time, so a returning golfer arrives with the membership they left with.

### 2. Green fees

```
member_per_hole = round(green_fee * tier.fee_multiplier * (1 + facility_bonus) * tuning)
total           = member_per_hole * open_holes
```

The `green_fee_per_hole` mod hook sees the same number, and its `context` carries `membership_tier`. A member also judges their fee against their **own** fair price - the public fair price times their tier's `price_tolerance` - so the premium they agreed to is not something they call overpriced.

### 3. Referrals

```
chance = tier.referral_chance * clamp((visit_score - 0.5) / 0.5, 0, 1)
if randf() < chance: referrals_pending += 1     # capped at 4
```

A referral is spent on the next golfer through the door: a named visitor card is marked as referred, and a walk-up guest takes the referral directly. `referrals_today` counts them for the day's summary.

---

## Tuning levers

| Parameter | Location | Value | Effect |
| --- | --- | --- | --- |
| `UPGRADE_THRESHOLD` | `club_membership.gd` | 0.68 | Lower = easier to sign golfers up |
| `DOWNGRADE_THRESHOLD` | `club_membership.gd` | 0.35 | Higher = members churn faster |
| `VALUE_FLOOR` | `club_membership.gd` | 0.30 | Value below this blocks promotion and costs a tier |
| `SLOW_ROUND_SECONDS` | `club_membership.gd` | 60 | Waiting past this reads as "rounds are too slow" |
| `NEGLECTED_NEEDS` | `club_membership.gd` | 0.35 | Needs satisfaction below this reads as neglect |
| `REFERRAL_PROMOTION_BOOST` | `club_membership.gd` | 0.08 | How much a member's word is worth at sign-up |
| `fee_multiplier`, `joining_fee`, `referral_chance`, `price_tolerance` | `club_membership.gd` `TIER_DATA` | 1.0–1.5, $0–$120, 0–0.35, 1.0–1.5 | Per-tier economy |
| `max_tier_for_course()` | `club_membership.gd` | see table | The club's ceiling |
| `demand_modifier()` | `club_membership.gd` | +2%/member, cap +20% | Word-of-mouth arrivals |

## Related

- [Satisfaction and Feedback](satisfaction-feedback.md) computes the visit score and the value every membership decision is made from.
- [Golfer Spawning](golfer-spawning.md) brings returning members and referred guests onto the course.
- [Golfer Attributes](golfer-attributes.md) is the status block the reasons are drawn from.
- [Economy](../economy-and-land/economy.md) covers the green fees members pay into.
- [Reputation](../ratings-and-reputation/reputation.md) sets the club's ceiling and the fair price members judge.
