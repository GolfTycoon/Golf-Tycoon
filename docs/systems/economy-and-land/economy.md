# Economy & Finance

> How money comes in (green fees, buildings, tournaments) and goes out (maintenance, staff, buildings, loans), plus the difficulty presets that change the numbers.

**Source:** `scripts/autoload/game_manager.gd` (`money`, `can_afford()`, `set_green_fee()`, `calculate_operating_costs()`, loans, `DAILY_RATE_SCALE`, stagnation), `scripts/systems/difficulty_presets.gd`, `scripts/systems/course_economy.gd` (`fair_round_price()`, `price_demand()`), `scripts/managers/staff_manager.gd`, `scripts/systems/season_system.gd`, `scripts/systems/milestone_system.gd`, `scripts/main/main.gd` (terrain cost), `data/buildings.json` (building operating costs)
**Tests:** `tests/unit/test_game_manager.gd`, `tests/unit/test_daily_statistics.gd`

---

## Plain English

You start with money on your books, and every day the course earns and spends. Keep the balance above the bankruptcy line.

### Money in

1. **Green fees.** The main income. Each golfer pays a fee for each open hole. You set the fee from **$1 to $200**, but the most you can charge is **$10 per open hole**. A 3-hole course can charge at most $30.
2. **Buildings.** Amenities such as snack bars, pubs, pro shops and driving ranges earn money from golfers who use them. Use depends on how close the golfer is and on their need. Landmark facilities (the Airstrip, Castle, Casino and Theme Park) raise the green fee per hole instead.
3. **Tournaments.** Hosting one brings in gate money and sponsorships. Tournaments mostly build reputation. Most tiers break even or lose money. See [Tournament System](../events/tournament-system.md).
4. **Construction milestones.** One-off rewards for building holes. See construction milestones (section 7 of the algorithm).

### Money out

1. **Terrain upkeep.** Each tile you paint has a daily upkeep, scaled by season, theme and difficulty.
2. **Base overhead.** $100 a day, plus $50 for each hole.
3. **Staff salaries.** Each hire has a daily wage. See [Staff and Weeds](staff-and-weeds.md).
4. **Building upkeep.** Each building has a daily operating cost.
5. **Loan interest.** Charged once a year. See loans (section 6 of the algorithm).

### Bankruptcy

Money can go below zero, down to the bankruptcy threshold. The threshold is **−$1,000** on Normal. A purchase is refused if it would take you below the threshold. You are bankrupt if your money falls below it.

### Green fee and golfer demand

The fee you set against a fair price for your course affects how many golfers come. The fair price depends on reputation, the number of holes and the season. Charge above it and demand falls quickly. Charge below it and the extra demand is capped, so underpricing does not pay for itself. Traffic, weather, group size and reputation also affect actual arrivals. There is no fixed revenue curve.

### Difficulty

You choose a difficulty when you start. It changes starting money, upkeep, golfer numbers, reputation decay, the bankruptcy line, how harshly overpricing is judged, and building costs. See the [difficulty presets](#difficulty-presets).

---

## Algorithm

### 1. Money and bankruptcy

```
starting money        = 25,000 on Normal (40,000 Easy; 15,000 Hard)
bankruptcy threshold  = −1,000 on Normal (−5,000 Easy; 0 Hard)

can_afford(cost) = cost ≤ 0  or  (money − cost) ≥ threshold
is_bankrupt()    = money < threshold
```

### 2. Green fee

```
MIN_GREEN_FEE = 1
MAX_GREEN_FEE = 200
effective_max = max(MIN_GREEN_FEE, min(open_holes × 10, MAX_GREEN_FEE))
green_fee     = clamp(new_fee, MIN_GREEN_FEE, effective_max)
```

| Open holes | Highest allowed fee |
| --- | --- |
| 1 | $10 |
| 3 | $30 |
| 6 | $60 |
| 9 | $90 |
| 20 or more | $200 |

Revenue from a golfer is the green fee for each open hole, plus the pro shop bonus.

### 3. Fair price and demand

```
size_factor   = clamp(holes / 18, 0.15, 1.0)
fair_price    = max(reputation × 2, 20) × size_factor × fee_tolerance(season, theme)

ratio         = fee_per_hole × holes / fair_price
demand_factor = min(1.25, 1 / max(ratio, 0.1)²)
```

Doubling an already fair fee cuts potential groups to about a quarter. The 1.25 cap means cheap pricing does not add unlimited demand.

### 4. Daily operating costs

```
terrain_cost        = Σ per-tile upkeep (player-placed tiles) × theme and difficulty maintenance multiplier
terrain_maintenance = terrain_cost × season/theme maintenance modifier

base_overhead       = 100 + 50 × hole_count
staff_salaries      = Σ daily wage of each hired staff member
building_costs      = Σ operating cost of each building
decoration_costs    = Σ upkeep of each decoration

operating_costs     = terrain_maintenance + base_overhead + staff_salaries
                      + building_costs + decoration_costs
```

The daily charges are applied in small steps across the day (`apply_daily_charge()`, `DAILY_RATE_SCALE`), so a day's total matches the daily figure however the clock runs.

**Upkeep multipliers**

| Source | Multiplier |
| --- | --- |
| Theme maintenance | See [Course Themes](../course-design/course-themes.md) (0.6× to 1.4×) |
| Difficulty maintenance | 0.8 Easy, 1.0 Normal, 1.3 Hard |
| Season and theme | See [Seasonal Calendar](../environment-and-time/seasonal-calendar.md) |

### 5. Daily profit

```
total_revenue = green_fees + building_revenue + tournament_revenue
daily_profit  = total_revenue − operating_costs − tournament_entry_fee
```

Arrivals and completed rounds are counted separately. Revenue from a hole is booked when its green fee is paid, not again when the round finishes. Daily accounts and feedback are saved. Older saves start with empty daily counters.

### 6. Loans

```
MAX_LOAN                 = 50,000
LOAN_ANNUAL_INTEREST_RATE = 0.10     # 10% a year, charged at year end

borrow(amount):
    amount = clamp(amount, 10,000, MAX_LOAN)
    reject if loan_balance + amount > MAX_LOAN
    loan_balance += amount;  money += amount

year end:
    interest     = int(loan_balance × 0.10)
    loan_balance += interest

repay(amount):
    amount = min(amount, loan_balance)
    reject if not can_afford(amount)
    loan_balance −= amount;  money −= amount
```

### 7. Construction milestones

Course-building milestones pay a one-off reward. They do not grant reputation, except the par-3 course milestone.

| Milestone | Requirement | Reward |
| --- | --- | --- |
| First Tee | Build 1 hole | $300 |
| Front Three | Build 3 holes | $600 |
| The Front Nine | Build 9 holes | $2,000 |
| Full Course | Build 18 holes | $4,000 |
| Short Game Special | Build a course of all par 3s | $2,000 and +5 reputation |

Milestones need a recorded completed round before reputation and star milestones can fire. Loading a save does not pay milestone rewards again.

### 8. Staff

There are two staff systems.

**Staff tier** (`StaffTier` in `game_manager.gd`) sets the per-hole wage cost and the modifiers used in operating costs.

| Tier | Cost per hole per day | Condition modifier | Satisfaction modifier |
| --- | --- | --- | --- |
| Part-Time | $5 | 0.85 | 0.90 |
| Full-Time | $10 | 1.00 | 1.00 |
| Premium | $20 | 1.15 | 1.10 |

**Individual staff** (`StaffManager`) are the people who walk the course. Each job has a standard and a premium hire.

| Job | Standard | Premium | Wage per day |
| --- | --- | --- | --- |
| Groundskeeper | Groundskeeper | Technician | $80 / $155 |
| Greeter | Club Pro | Celebrity | $60 / $130 |
| Marshal | Ranger | Marshall | $50 / $110 |
| Drinks vendor | Soda Vendor | Cart Refresher | $40 / $95 |

See [Staff and Weeds](staff-and-weeds.md).

**Course condition** is recalculated each day from weed pressure. Groundskeeper coverage reduces that pressure. Coverage is the number of groundskeepers divided by the number of holes, capped at 1. A fully covered course ignores 70% of weed pressure. Condition runs from 0 to 1 and feeds the Condition rating (25% of the overall star rating).

### 9. Seasonal and theme effects

```
maintenance = terrain_cost × SeasonSystem.get_blended_maintenance_modifier(day, theme)
spawn_rate  = base × SeasonSystem.get_blended_spawn_modifier(day, theme)
fair_price  = fair_price × SeasonSystem.get_fee_tolerance(day, theme)
```

Each season and theme pair has its own values. See [Seasonal Calendar](../environment-and-time/seasonal-calendar.md).

### 10. Stagnation

If you have not added to the course for more than **28 days**, and reputation is above **40**, reputation falls by **0.3** a day.

### Difficulty presets

| Setting | Easy | Normal | Hard |
| --- | --- | --- | --- |
| Starting money | $40,000 | $25,000 | $15,000 |
| Maintenance multiplier | 0.8× | 1.0× | 1.3× |
| Spawn rate multiplier | 1.2× | 1.0× | 0.8× |
| Reputation decay multiplier | 0.5× | 1.0× | 2.0× |
| Bankruptcy threshold | −$5,000 | −$1,000 | $0 |
| Green fee sensitivity | 0.7× | 1.0× | 1.5× |
| Building cost multiplier | 0.8× | 1.0× | 1.2× |

Green fee sensitivity sets how harshly overpricing lowers the value rating. See [Course Rating](../ratings-and-reputation/course-rating.md).

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Starting money | `difficulty_presets.gd` | $40K / $25K / $15K | Starting cash |
| Bankruptcy threshold | `difficulty_presets.gd` | −$5K / −$1K / $0 | How far into debt you can go |
| Minimum green fee | `game_manager.gd` `MIN_GREEN_FEE` | $1 | Lowest price |
| Maximum green fee | `game_manager.gd` `MAX_GREEN_FEE` | $200 | Highest price |
| Fee per open hole | `game_manager.gd` `effective_max` | $10 per hole | Pricing ceiling |
| Base overhead | `game_manager.gd` `BASE_DAILY_OVERHEAD`, `PER_HOLE_DAILY_COST` | $100 + $50 per hole | Fixed daily cost |
| Maximum loan | `game_manager.gd` `MAX_LOAN` | $50,000 | Largest loan |
| Loan interest | `game_manager.gd` `LOAN_ANNUAL_INTEREST_RATE` | 10% a year | Charged at year end |
| Stagnation threshold | `game_manager.gd` `STAGNATION_DAYS_THRESHOLD` | 28 days | Days before the decay starts |
| Stagnation decay | `game_manager.gd` `STAGNATION_DECAY_PENALTY` | 0.3 rep a day | Reputation lost while stagnating |
| Stagnation floor | `game_manager.gd` `STAGNATION_REPUTATION_FLOOR` | 40 | Decay stops below this |
| Groundskeeper coverage | `staff_manager.gd` | 70% of weed pressure | How much a full crew reduces weeds |
| Weed pressure | `weed_manager.gd` `WEEDS_PER_HOLE_FULL_PRESSURE` | 4.0 per hole | How fast weeds drag condition down |
| Milestone rewards | `milestone_system.gd` | $300 / $600 / $2,000 / $4,000 | Construction rewards |

---

## Related

- [Premium Land](premium-land.md) covers buying land, which is the main cost of expansion.
- [Staff and Weeds](staff-and-weeds.md) covers hired staff and course condition.
- [Course Rating](../ratings-and-reputation/course-rating.md) explains how value and condition feed the star rating.
- [Seasonal Calendar](../environment-and-time/seasonal-calendar.md) lists the season and theme modifiers.
