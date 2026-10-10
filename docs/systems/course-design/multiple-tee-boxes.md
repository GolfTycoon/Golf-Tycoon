# Multiple Tee Boxes

> Each hole can have forward, middle and back tees. Golfers pick a tee by skill tier, and each tee has its own par. This is an optional setting, off by default.

**Source:** `scripts/autoload/game_manager.gd` (`HoleData`: `tee_positions`, `par_by_tee`, `get_tee_for_tier()`, `recalculate_par_by_tee()`, `multi_tee_enabled`), `scripts/managers/golfer_manager.gd` (tee selection and per-tee scoring), `scripts/systems/golf_rules.gd` (`calculate_par()`), `scripts/ui/settings_menu.gd` (the toggle), `scripts/autoload/save_manager.gd` (loads the setting)

---

## Plain English

**The feature is off by default.** Turn it on in **Settings** under the tee option. While it is off, every golfer plays from the back tee, and the hole shows only one tee.

When it is on, each hole has three tees:

- **Forward** (red), for beginners.
- **Middle** (white), for casual and serious golfers.
- **Back** (blue), for pros and tournaments.

You place the back tee during hole creation. The game places the forward and middle tees on the same line from tee to green. The forward tee is 40% of the way from the back tee toward the green, so 60% of the distance remains. The middle tee is 25% of the way, so 75% of the distance remains.

Each tee has its own par, based on its distance to the green. A 480-yard par 5 from the back tee might play as a 360-yard par 4 from the forward tees. A golfer is scored against the par for the tee they played.

---

## Algorithm

### 1. Placing the tees

```
back_tee, green = positions
length = distance(back_tee, green)

if length < 2 tiles:
    forward = middle = back_tee          # too short to tell apart
else:
    forward = back_tee + direction × 0.40 × length     # 60% of distance remains
    middle  = back_tee + direction × 0.25 × length     # 75% of distance remains
    snap each to the nearest valid grid tile
    if a tile is invalid, use back_tee instead
```

### 2. Tee choice by tier

`get_tee_for_tier()` runs for each golfer starting a hole:

| Golfer | Tee |
| --- | --- |
| Tournament golfer | Back (always) |
| Beginner | Forward |
| Casual | Forward or middle, 50/50 |
| Serious | Middle or back, 50/50 |
| Pro | Back |

If the hole has no tee positions, the golfer uses the single back tee. The key of the tee chosen is stored on the golfer as `current_tee_key`.

### 3. Per-tee par

```
distance_yards = distance(tee, green) × 22
par = GolfRules.calculate_par(distance_yards)
      ≤ 250 yards  → 3
      ≤ 470 yards  → 4
      > 470 yards  → 5
```

`recalculate_par_by_tee()` fills `par_by_tee` for all three tees.

### 4. Scoring

When a golfer finishes a hole, the score is compared with `get_par_for_tee(current_tee_key)`. The hole's main `par` stays at the back-tee value. The scorecard and course rating use that value.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Feature toggle | `game_manager.gd` `multi_tee_enabled`, `settings_menu.gd` | `false` (off) | Turns multiple tees on or off |
| Forward tee position | `game_manager.gd` `forward_t` | `0.4` along the line (60% remains) | Closer to the green is easier |
| Middle tee position | `game_manager.gd` `middle_t` | `0.25` along the line (75% remains) | Closer to the green is easier |
| Par thresholds | `golf_rules.gd` `calculate_par()` | 250 and 470 yards | Where par changes for each tee |
| Yards per tile | `terrain_grid.gd` `calculate_distance_yards()` | `22` | Converts distance for par |
| Beginner tee | `golfer_manager.gd` / `get_tee_for_tier()` | Forward | Which tee beginners use |
| Casual tee mix | `get_tee_for_tier()` | 50% forward, 50% middle | Casual golfer tee distribution |
| Serious tee mix | `get_tee_for_tier()` | 50% middle, 50% back | Serious golfer tee distribution |
| Pro tee | `get_tee_for_tier()` | Back | Which tee pros use |

---

## Related

- [Difficulty Calculator](difficulty-calculator.md) uses the back-tee layout.
- [Stroke Index](stroke-index.md) uses the hole's main par and difficulty.
- [Hole Creation](hole-creation.md) covers how the back tee is placed.
- [Golfer Spawning](../golfers/golfer-spawning.md) covers the golfer tiers.
