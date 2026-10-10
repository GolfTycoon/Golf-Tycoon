# Shot Accuracy & Angular Dispersion

> How a struck ball misses its target: a gaussian angular error, a persistent hook or slice, rare shanks, and distance loss.

**Source:** `scripts/entities/golfer.gd` (`_calculate_shot_precise()`), `scripts/systems/golf_rules.gd` (lie and distance tables)
**Tests:** `tests/unit/test_shot_simulator.gd`, `tests/unit/test_golf_rules.gd`

---

## Plain English

When a golfer swings, the ball does not go exactly where they aimed. Rather than scattering shots in a circle around the target, the game rotates the shot direction by a small **error angle**. This produces believable misses: hooks that curve left, slices that curve right, and the occasional catastrophic shank.

The error angle is drawn from a **bell curve (gaussian distribution)**, so most shots finish near the target line and only a few land in the tails. Four properties make this feel right:

- **Misses scale with distance.** The same 3° error is a much bigger miss at 250 yards than at 100 yards.
- **Each golfer has a consistent shot shape.** Some slice and some hook. That is a persistent trait, not random noise on every swing.
- **Skilled players compensate.** High-accuracy golfers can counteract their natural tendency. Low-accuracy golfers cannot.
- **Short shots still scatter.** A lateral floor stops beginners from landing every short iron in one tight cluster.

### Miss tendency (hook / slice bias)

Each golfer has a `miss_tendency` between **-1.0** (strong hook) and **+1.0** (strong slice). Its size depends on tier: beginners have strong tendencies (0.4–0.8), pros are nearly neutral (0.0–0.15). The golfer either fights this natural shape or plays into it.

### Shanks

Rarely, a golfer hits a shank: the ball flies **35–55°** off line at **30–60%** of normal distance. Shanks only happen on full swings, not on putts or wedges. Their likelihood falls as accuracy rises, so beginners shank far more often than pros. The shank direction follows the golfer's miss tendency.

### Distance loss (topped and fat shots)

Independently of the angular error, each shot has a small chance of losing distance, as if topped or fat. The loss is bell-curve distributed, so most shots are near full distance and only occasional ones come up short.

---

## Algorithm

### 1. Total accuracy

```
skill_accuracy = blend of driving, accuracy and recovery skill (depends on club)
base_accuracy  = club accuracy modifier
lie_modifier   = GolfRules.get_lie_modifier(terrain, club, bunker_depth)

total_accuracy = base_accuracy × skill_accuracy × lie_modifier
```

**Club accuracy modifiers:** Driver 0.70 · Fairway Wood 0.78 · Iron 0.85 · Wedge 0.95 · Putter 0.98

**Skill blend by club:**

| Club | Skill formula |
| --- | --- |
| Driver | `driving × 0.7 + accuracy × 0.3` |
| Fairway Wood | `driving × 0.5 + accuracy × 0.5` |
| Iron | `driving × 0.4 + accuracy × 0.6` |
| Wedge | `accuracy × 0.7 + recovery × 0.3` |
| Putter | `putting` |

**Accuracy floors**

- **Wedge:** `lerp(0.96, 0.80, distance_ratio)`. Close chips are always accurate.
- **Putter:** `lerp(skill_floor_max, skill_floor_min, distance_ratio)`, scaled by skill. A skill of 0.3 gives a 50%–85% range; a skill of 0.95 gives 80%–95%.

The headless tournament simulator (`tournament_simulator.gd`) applies the same wedge and putter floors, so simulated events play like the live course.

**Lie and distance by terrain** (`GolfRules.get_lie_modifier()` and `get_terrain_distance_modifier()`):

| Terrain | Lie (wedge / other clubs) | Distance | Notes |
| --- | --- | --- | --- |
| Fairway, grass, green | 1.0 | 1.0 | Perfect lie |
| Tee box | 1.0 (1.05 driver) | 1.0 | Tee bonus for the driver |
| Firm fairway | 0.92 / 1.0 | 1.0 | Tight lie: clean full swings, little cushion for wedges |
| Rough | 0.75 | 0.85 | |
| Waste bunker | 0.8 / 0.7 | 0.85 | Firm sand; the club may be grounded, so not a hazard |
| Heavy rough | 0.5 | 0.70 | |
| Deep rough | 0.4 | 0.60 | Ball sits down in knee-high grass |
| Bunker | 0.6 / 0.4 (deep: 0.45 / 0.25) | 0.75 (deep: 0.60) | See [Bunker Depth](../course-design/bunker-depth.md) |
| Pot bunker | 0.35 / 0.15 | 0.45 | Steep revetted face; ShotAI only takes a wedge |
| Trees | 0.3 | 0.60 | One lie for the whole tree family |
| Brush | 0.3 | 0.50 | ShotAI only takes a wedge |
| Rocks, small and large boulders | 0.25 | 0.50 | One stone lie |

### 2. Angular spread

```
max_spread_deg = (1.0 - total_accuracy) × 12.0
spread_std_dev = max_spread_deg / 2.5      # ≈95% of shots fall inside max_spread_deg
```

- Worst case (accuracy near 0): **12°** maximum spread.
- Pro level (95% accuracy): about **0.6°** maximum spread.

**Wedge partial swings** narrow the spread further:

```
if club == WEDGE:
    distance_ratio = actual_distance / club_max_distance
    spread_std_dev *= lerp(0.3, 1.0, distance_ratio)
```

### 3. Miss angle

```
base_angle_deg    = gaussian_random() × spread_std_dev
tendency_strength = miss_tendency × (1.0 - total_accuracy) × 6.0
miss_angle_deg    = base_angle_deg + tendency_strength
```

Lower accuracy amplifies the tendency. At the worst accuracy the persistent bias reaches **6°**.

### 4. Gaussian generator

```gdscript
func _gaussian_random() -> float:
    return (randf() + randf() + randf() + randf() - 2.0) / 0.5774
```

The sum of four uniform values, centred and scaled (central limit theorem). Mean ≈ 0, standard deviation ≈ 1, range roughly ±3.5. About 68% of values fall within ±1, 95% within ±2 and 99.7% within ±3.

### 5. Shank check

```
if club != PUTTER and club != WEDGE:
    shank_chance = (1.0 - total_accuracy) × 0.04
    if randf() < shank_chance:
        shank_direction = +1.0 if miss_tendency >= 0 else -1.0
        miss_angle_deg  = shank_direction × randf_range(35.0, 55.0)
        actual_distance *= randf_range(0.3, 0.6)
```

| Accuracy | Shank chance |
| --- | --- |
| 0.30 | 2.8% |
| 0.50 | 2.0% |
| 0.70 | 1.2% |
| 0.95 | 0.2% |

### 6. Direction and landing

```
miss_direction = aim_direction.rotated(deg_to_rad(miss_angle_deg))
landing_point  = from + miss_direction × actual_distance
```

### 7. Lateral dispersion floor

Angular error alone gives very tight clusters at short range, because a small angle means only a few yards off target. Real golfers scatter short shots, so a floor adds sideways scatter:

```
angular_lateral_std = actual_distance × sin(deg_to_rad(spread_std_dev))
min_lateral_std     = (1.0 - total_accuracy) × 0.8

if angular_lateral_std < min_lateral_std:
    extra_std = sqrt(min_lateral_std² - angular_lateral_std²)
    landing_point += perpendicular × (gaussian_random() × extra_std)
```

### 8. Distance loss (topped and fat)

```
distance_loss = abs(gaussian_random()) × (1.0 - total_accuracy) × 0.12
landing_point -= miss_direction × (actual_distance × distance_loss)
```

Loss is capped at about **12%** at the worst accuracy. The `abs()` means a topped shot can only lose distance, never gain it.

### 9. Execution variance

Each swing also varies a little, which is natural swing inconsistency:

| Club | Distance modifier range | Approx. spread |
| --- | --- | --- |
| Driver | 0.91 – 1.01 | ±5% |
| Fairway wood | 0.92 – 1.01 | ±4.5% |
| Iron | 0.94 – 1.01 | ±3.5% |
| Wedge | 0.95 – 1.00 | ±2.5% |
| Putter | 0.97 – 1.00 | ±1.5% |

### 10. External distance modifiers

These multiply the distance modifier:

- **Terrain:** the distance column in the table above.
- **Wind:** the headwind or tailwind factor from `WindSystem.get_distance_modifier()` (see [Wind System](../environment-and-time/wind-system.md)).
- **Elevation:** `1.0 − (elevation_difference × 0.03)`, clamped to [0.75, 1.25]. Roughly 3% per elevation level.

---

## Tuning Levers

| Lever | Where | Current value | Effect |
| --- | --- | --- | --- |
| Max spread multiplier | `_calculate_shot_precise()` | `12.0` | Higher widens the spread for inaccurate golfers |
| Spread divisor | `_calculate_shot_precise()` | `2.5` | Higher tightens the spread within the maximum |
| Tendency multiplier | `_calculate_shot_precise()` | `6.0` | Higher means stronger hooks and slices for inaccurate golfers |
| Shank probability | `_calculate_shot_precise()` | `0.04` | Higher produces more shanks |
| Shank angle range | `_calculate_shot_precise()` | `35°–55°` | Wider makes shanks more severe |
| Shank distance range | `_calculate_shot_precise()` | `0.3–0.6` | Lower makes shanks shorter |
| Distance loss multiplier | `_calculate_shot_precise()` | `0.12` | Higher produces more topped and fat shots |
| Minimum lateral dispersion | `_calculate_shot_precise()` | `0.8` | Higher scatters short shots more |
| Club accuracy modifiers | `golfer.gd` `CLUB_STATS` | 0.70–0.98 | Lower makes a club less accurate |
| Wedge floor range | `_calculate_shot_precise()` | `0.80–0.96` | Lower makes wedges less consistent |
| Lie modifiers | `golf_rules.gd` `get_lie_modifier()` | See table | Lower makes a terrain harder to strike cleanly |

---

## Related

- [Ball Physics](ball-physics.md) covers flight after the shot is struck.
- [Shot AI: Target Finding](shot-ai-target-finding.md) shows how AI chooses shots.
- [Terrain Types](../course-design/terrain-types.md) lists the lie values.
- [Wind System](../environment-and-time/wind-system.md) adds the wind effect.
