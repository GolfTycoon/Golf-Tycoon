# Hole Difficulty Calculator

> Every hole gets an automatic difficulty rating from 1.0 (easy) to 10.0 (extremely hard), built from its length, hazards, elevation, doglegs, green and landing zones.

**Source:** `scripts/course/difficulty_calculator.gd` (`calculate()`, `_calculate_hazard_difficulty()`, `_calculate_elevation_difficulty()`, `_calculate_dogleg_difficulty()`, `_calculate_green_difficulty()`, `_calculate_landing_difficulty()`, `_get_corridor_tiles()`), `scripts/course/forced_carry_calculator.gd`

---

## Plain English

A hole's difficulty is calculated from its physical design, so you don't set it by hand. The factors are:

- **Par.** Longer holes need more shots, so they are harder.
- **Hazards in the corridor.** Water, bunkers, trees and out-of-bounds ground between tee and green.
- **Forced carries.** Water or bunkers that a golfer must hit over. See [Forced Carry](forced-carry.md).
- **Elevation.** The total up-and-down along the hole, not the net change.
- **Doglegs.** A hole whose fairway bends sharply.
- **The green.** Its size and slope.
- **Landing zones.** Hazards near where a drive or a layup usually comes down.

Hazards near the usual landing zone count more than hazards far off the fairway. So where you place hazards matters as much as how many there are.

The rating feeds into other systems:

- **Course slope rating**, averaged across holes. See [Course Rating](../ratings-and-reputation/course-rating.md).
- **Golfer tier attraction.** Harder courses attract better golfers. See [Golfer Spawning](../golfers/golfer-spawning.md).
- **Tournament qualification.** Regional and higher tournaments require a minimum difficulty.
- **Prestige.** Difficult, well-rated courses earn bonus reputation.

---

## Algorithm

### 1. Total

```
total = base + hazard + elevation + dogleg + green + landing_zone
total = clamp(total, 1.0, 10.0)
```

### 2. Base (from par)

```
base = par − 2.0        # par 3 → 1.0, par 4 → 2.0, par 5 → 3.0
```

### 3. Corridor scan and hazard difficulty

`_get_corridor_tiles()` collects every tile in a corridor along the tee-to-green line. The width is 10, so the corridor reaches 5 tiles either side of the centre line, which is 11 tiles across. Each tile is classified:

```
difficulty  = water_count × 0.30
            + ob_count × 0.20
            + tree_count × 0.10
            + bunker_difficulty         # 0.15 shallow, 0.25 deep, 0.30 pot bunker, per tile
            + trouble_difficulty        # per tile, see table
```

| Tile | Weight per tile | Why |
| --- | --- | --- |
| Water, stream | 0.30 | Penalty stroke and a drop |
| Pot bunker | 0.30 | Wedge-only escape, barely advances |
| Deep bunker | 0.25 | See [Bunker Depth](bunker-depth.md) |
| Out of bounds | 0.20 | Stroke and distance penalty |
| Shallow bunker | 0.15 | Hard to escape, no penalty |
| Trees (any species) | 0.10 | Blocked shots, little recovery |
| Brush, rocks, small and large boulders | 0.08 | Wedge-only hack-outs |
| Deep rough | 0.04 | Poor lie, ball snags |
| Waste bunker | 0.03 | Sandy lie, no penalty |

Streams count as water, and pot bunkers count as bunkers, for landing-zone checks. Dogleg detection treats firm fairway as fairway.

### 4. Elevation

```
change = Σ |elevation[i] − elevation[i−1]|     # sampled along the tee-to-green line
elevation_difficulty = clamp(change × 0.15, 0.0, 1.5)
```

This measures total change, not net change. An up-and-down hole is harder than a flat one, even if both start and end at the same height.

### 5. Dogleg

Applies only to par 4 and longer holes that are more than 8 tiles long. It checks the sides of the midpoint, 2 to 6 tiles out, for fairway.

```
if fairway exists on exactly one side:  dogleg = 0.8
else:                                    dogleg = 0.0
```

### 6. Green

Size is the flood-fill count of green tiles, capped at 100.

| Green size | Difficulty |
| --- | --- |
| 1 tile | +0.8 |
| 2 or 3 tiles | +0.4 |
| 4 to 6 tiles | 0.0 |
| 7 tiles or more | −0.2 |

Slope is the elevation range across the green tiles:

```
slope_difficulty = clamp((max_elevation − min_elevation) × 0.25, 0.0, 0.6)
```

### 7. Landing zones

| Par | Landing zones (tiles from tee) |
| --- | --- |
| 3 | None (approach goes straight to the green) |
| 4 | 10 (about 220 yards) |
| 5 | 10, and `min(hole_length − 6, 18)` |

For each zone, every tile within a 3-tile radius is checked:

| Hazard in radius | Added difficulty |
| --- | --- |
| Water | +0.15 |
| Bunker | +0.08 |
| Out of bounds | +0.12 |

The zone total is clamped to 1.5.

### 8. Forced carries

`_calculate_carry_difficulty()` adds the total from [Forced Carry](forced-carry.md), capped at 2.0. Water carries score 0.2 to 1.5 per segment. Bunker carries score 0.1 to 0.5.

### 9. Distance units

Distances use `calculate_distance_yards()`, which multiplies tiles by **22 yards per tile**.

### Worked examples

These are approximate, to show the scale of each term.

| Hole | Par | Features | Approximate rating |
| --- | --- | --- | --- |
| Straight par 3, no hazards, large green | 3 | None | 0.8 |
| Par 4, two bunkers near the landing zone | 4 | Two bunkers | 3.0 |
| Par 5, dogleg, water carry, small green | 5 | Five water tiles | 6.5 |
| Par 4, water, trees, OB, sloped small green | 4 | 8 water, 6 trees, 4 OB | 7.5 |

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Corridor width | `calculate()` | `10` (5 tiles either side of centre) | Wider counts more hazards |
| Water weight | `_calculate_hazard_difficulty()` | `0.30` | Higher makes water scarier |
| Bunker weights | `_calculate_hazard_difficulty()` | `0.15` / `0.25` / `0.30` | Shallow / deep / pot bunker |
| OB weight | `_calculate_hazard_difficulty()` | `0.20` | Higher makes OB scarier |
| Tree weight | `_calculate_hazard_difficulty()` | `0.10` | Higher makes trees scarier |
| Elevation multiplier and cap | `_calculate_elevation_difficulty()` | `0.15` per unit, cap `1.5` | How much hills matter |
| Dogleg value | `_calculate_dogleg_difficulty()` | `0.8` | Higher makes doglegs harder |
| Green size thresholds | `_calculate_green_difficulty()` | `1`, `2–3`, `4–6`, `7+` tiles | What counts as small or large |
| Slope multiplier and cap | `_calculate_green_difficulty()` | `0.25` per unit, cap `0.6` | How much green slope matters |
| Landing zone radius | `_calculate_landing_difficulty()` | `3` tiles | Wider counts more landing-zone hazards |
| Landing zone weights | `_calculate_landing_difficulty()` | `0.15` / `0.08` / `0.12` | Water / bunker / OB near a landing zone |
| Landing zone cap | `_calculate_landing_difficulty()` | `1.5` | Maximum landing-zone contribution |
| Yards per tile | `terrain_grid.gd` `calculate_distance_yards()` | `22` | Converts tiles to yards for the carry and distance readouts |

---

## Related

- [Forced Carry](forced-carry.md) covers the carry segments that feed into this rating.
- [Bunker Depth](bunker-depth.md) explains the deep and pot bunker weights.
- [Course Rating](../ratings-and-reputation/course-rating.md) covers how holes average into the slope rating.
- [Terrain Types](terrain-types.md) lists the tiles that are classified here.
