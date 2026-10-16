# Golfer Needs and Statuses

> **Source:** `scripts/systems/golfer_attributes.gd` (`GolferAttributes` status simulation), integrated via `scripts/entities/golfer.gd`

## Plain English

The golfer status simulation lives on the golfer's attribute block ([Golfer Attributes](golfer-attributes.md)). Every golfer carries five **Golfer Statuses** - **Fun, Attitude, Energy, Hunger, Thirst** - and each one starts the course at 50%. Two internal course-flow trackers that are not golfer statuses also ride along: **comfort** (the need for a restroom) and **pace** (how stuck the golfer feels in traffic). Both start full and push Fun and Attitude around when they drop.

### How It Works

Statuses decay as golfers play:

- **Energy** goes down while the golfer is on the course and goes up when using a bench. Active golfers tire more slowly; the Resort Hotel sends guests out rested (0.6x decay).
- **Hunger** goes down while the golfer is on the course and goes up when using a Snack Bar (a Pub feeds them properly).
- **Thirst** goes down while the golfer is on the course and goes up when using a Drink Vendor (snack bars and pubs take the edge off).
- **Fun** is based on the accumulation of the golfer's comments made while playing your course (Positive comments add to it, Negative ones subtract) - and waiting in traffic is no fun either.
- **Attitude** is based on the amount of fun the golfer is having at your resort: it settles toward Fun after every comment, hole and wait, and service shocks (greeters, marshals, drinks) adjust it directly.
- **Comfort** drops after each hole (need for a restroom; the clubhouse visit restores it). **Pace** drops when golfers wait on groups ahead, modified by their patience - normal turns within a group do not count.

When a status drops below the **low threshold** (0.30), the golfer may make a complaint comment (e.g. "Getting tired...", "Need a drink"). When it drops below the **critical threshold** (0.15), the golfer takes a one-time Attitude penalty. Both fire once per episode and reset when an amenity restores the status above the threshold.

### Buildings Satisfy Statuses

Buildings placed on the course restore specific statuses when a golfer walks within range and decides to stop:

| Building | Status | Restore | Attitude boost |
| --- | --- | --- | --- |
| Bench | Energy | +0.20 | +0.02 |
| Snack Bar | Hunger (+Thirst) | +0.30 (+0.20) | +0.03 |
| Pub | Hunger (+Thirst) | +0.50 (+0.25) | +0.05 |
| Putting Green, Pro Shop, Driving Range | Fun | +0.03 | +0.03 |
| Cart Garage | Fun | +0.02 | +0.02 |
| Clubhouse | All | +0.15 each | +0.03 |

Other facilities work before the round starts: the **Tennis Court, Stable, Spa and Swim Club** start every golfer with a better Attitude, and the **Resort Hotel** starts every golfer with more stamina (Energy drains 0.6x as fast).

On-course staff do the rest: **greeters** lift Attitude (Outgoing golfers enjoy it more), **marshals** restore pace, and **drinks vendors** quench Thirst - see [staff-and-weeds.md](../economy-and-land/staff-and-weeds.md).

### Tier Differences

Higher-tier golfers are more demanding - their statuses decay faster:

- Beginners: 0.8x decay rate (resilient)
- Casual: 1.0x (baseline)
- Serious: 1.1x (slightly demanding)
- Pro: 1.3x (very demanding)

### Patience and Pace

The golfer's patience (set by tier) directly affects how fast pace drops during waits. Impatient golfers (pros, patience ~0.3) lose pace 2.5x faster than patient golfers (beginners/retirees, patience ~0.9). Normal play restores pace at 0.0008 per simulation second; a marshal's nudge restores a chunk at once.

### Walking at accelerated simulation speeds

Walking uses `move_and_collide(direction * min(speed * delta, distance_to_waypoint))`. The step is the golfer's walk speed times the ground rate underfoot (`TerrainGrid.walk_speed_modifier_at()`: dirt 1.25x, 1.5x once the trail reaches the clubhouse) and, for Active golfers, times their 1.15x walking multiplier.

### Amenities and traffic

A golfer considers nearby services once per hole until they choose a visit, and uses each chosen facility at most once per round. Functional amenity use pauses the golfer for four simulation seconds so the visit is visible. The golfer manager marks a group as traffic-blocked only when its next player is ready but an earlier group prevents a safe shot; those waiting seconds reduce pace and Fun. A marshal reduces the effective waiting penalty by the ratio `0.6 / staff_pace_modifier`.

---

## Algorithm

### 1. Status Decay Per Hole

```
tier_modifier = { BEGINNER: 0.8, CASUAL: 1.0, SERIOUS: 1.1, PRO: 1.3 }

on_hole_completed():
    energy  -= 0.018 * tier_modifier * hotel_modifier * active_modifier
    hunger  -= 0.012 * tier_modifier    # Low after ~17 holes (casual)
    thirst  -= 0.015 * tier_modifier    # Low after ~13 holes (casual)
    comfort -= 0.06  * tier_modifier    # Internal restroom need
    attitude += (fun - attitude) * 0.3
```

### 2. Waiting (Traffic)

```
on_waiting(wait_seconds):
    patience_modifier = 1.0 + (1.0 - patience) * 1.5
    pace -= wait_seconds * 0.003 * patience_modifier
    fun  -= wait_seconds * 0.0012 * (0.75 if Nice else 1.0)
```

Pace is checked in 5-second chunks during the golfer's `_process()` loop.

### 3. Comments -> Fun

```
record_comment(text, sentiment):
    positive: fun += 0.02 * (1.5 if Playful else 1.0)
    neutral:  fun += 0.002
    negative: fun -= 0.02 * (0.7 if Nice else 1.0)
    attitude += (fun - attitude) * 0.3
```

### 4. Building Interaction Chance

```
relevant_status = status mapped to building type (bench→energy, snack_bar/pub→hunger)

if relevant_status < 0.30:  interaction_chance = 1.00   # Desperate - always stop
elif relevant_status < 0.70: interaction_chance = 0.50   # Could use it - coin flip
else:                        interaction_chance = 0.20   # Doing fine - usually walk past

# Buildings with no status mapping (pro_shop, practice facilities): flat 0.30
```

Golfers do NOT pathfind to buildings - they only interact when they happen to walk within proximity range, at most once per round per building.

### 5. Complaint Comments (Low Statuses)

| Status | Trigger | Threshold | Messages |
| --- | --- | --- | --- |
| Energy < 0.30 | TIRED | LOW_NEED_THRESHOLD | "Getting tired...", "Need a break", etc. |
| Comfort < 0.30 | NEEDS_RESTROOM | LOW_NEED_THRESHOLD | "Need a restroom!", etc. |
| Hunger < 0.30 | HUNGRY | LOW_NEED_THRESHOLD | "Getting hungry...", etc. |
| Thirst < 0.30 | THIRSTY | LOW_NEED_THRESHOLD | "So thirsty...", etc. |
| Pace < 0.30 | SLOW_PACE | LOW_NEED_THRESHOLD | "Slow play...", "C'mon!", etc. |

Each fires at most once per episode and is recorded as a Negative comment on the golfer (see [Golfer Attributes](golfer-attributes.md)).

### 6. Attitude Penalties (Critical Statuses)

Each fires once per critical episode (-0.05 Energy, -0.05 Comfort, -0.03 Hunger, -0.04 Thirst, -0.08 Pace) and resets when the status recovers above the critical threshold.

### 7. Overall Satisfaction

```
overall = fun * 0.25 + attitude * 0.25 + energy * 0.20 + hunger * 0.15 + thirst * 0.15
```

## Tuning Levers

| Parameter | Location | Current Value | Effect |
| --- | --- | --- | --- |
| STATUS_START | `golfer_attributes.gd` | 0.5 | Golfer statuses start the course at 50% |
| ENERGY_DECAY_PER_HOLE | `golfer_attributes.gd` | 0.018 | Higher = golfers tire faster |
| HUNGER_DECAY_PER_HOLE | `golfer_attributes.gd` | 0.012 | Higher = more food demand |
| THIRST_DECAY_PER_HOLE | `golfer_attributes.gd` | 0.015 | Higher = more drink demand |
| COMFORT_DECAY_PER_HOLE | `golfer_attributes.gd` | 0.06 | Higher = more restroom demand |
| PACE_DECAY_PER_WAIT_SECOND | `golfer_attributes.gd` | 0.003 | Higher = more pace complaints |
| FUN_DECAY_PER_WAIT_SECOND | `golfer_attributes.gd` | 0.0012 | Higher = waiting hurts Fun faster |
| LOW_NEED_THRESHOLD | `golfer_attributes.gd` | 0.30 | Higher = complaints start sooner |
| CRITICAL_NEED_THRESHOLD | `golfer_attributes.gd` | 0.15 | Higher = attitude penalties start sooner |
| BENCH_ENERGY_RESTORE | `golfer_attributes.gd` | 0.20 | Higher = benches more effective |
| SNACK_BAR_HUNGER_RESTORE | `golfer_attributes.gd` | 0.30 | Higher = snack bars more effective |
| PUB_HUNGER_RESTORE | `golfer_attributes.gd` | 0.50 | Higher = pubs more effective |
| CLUBHOUSE_ALL_RESTORE | `golfer_attributes.gd` | 0.15 | Higher = clubhouse more effective |
| energy_decay_modifier | `GolferAttributes` field | 1.0 (0.6 with a Resort Hotel) | Scales per-hole energy decay |
| INTERACT_CHANCE_* | `golfer_attributes.gd` | 0.2 / 0.5 / 1.0 / 0.3 | Amenity stop chances by status band |
| Tier decay modifiers | `golfer_attributes.gd:_get_tier_decay_modifier()` | 0.8-1.3 | Higher = tier is more demanding |
| Overall satisfaction weights | `golfer_attributes.gd:get_overall_satisfaction()` | F:0.25 A:0.25 E:0.20 H:0.15 T:0.15 | Adjust the relative importance |

---

## Related

- [Golfer Attributes](golfer-attributes.md) is the full attribute model these statuses belong to.
- [Satisfaction and Feedback](satisfaction-feedback.md) covers how visits are scored.
- [Clubhouse](../course-design/clubhouse.md) covers the arrival/departure visit that tops statuses up.
