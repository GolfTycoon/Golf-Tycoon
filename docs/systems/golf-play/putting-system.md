# Putting System

> A probability model for putts: a make or miss roll on an exponential decay curve, a realistic miss position, and a green-reading aim point.

**Source:** `scripts/systems/golf_rules.gd` (`get_putt_make_rate()`, `get_putt_miss_characteristics()`), `scripts/entities/golfer.gd` (`_calculate_putt()`), `scripts/systems/shot_ai.gd` (`_decide_putt()`, `_read_green_slope()`)
**Tests:** `tests/unit/test_golf_rules.gd`, `tests/unit/test_gimme_thresholds.gd`, `tests/unit/test_shot_ai.gd`

---

## Plain English

Putting uses a different model from full shots. Instead of angular dispersion, it uses a **probability-based make or miss model**, calibrated to professional putting statistics.

For each putt the game first asks **does it go in?** This is a yes or no roll on an exponential decay curve: the farther the putt, the lower the chance. Putts inside 3 feet (about 0.045 tiles) are automatic tap-ins.

If the putt misses, the game generates a **realistic miss position** from separate distance and lateral error distributions:

- **Short putts** usually miss sideways (lip-outs), with tight distance control.
- **Medium putts** mix distance and direction error.
- **Long putts** are dominated by distance control (lag putting).

Better putters have higher make rates at every distance, tighter miss patterns, and a slight **long bias**, because good putters are taught "never up, never in."

### Green reading

Before putting, `ShotAI` reads the slope and aims **opposite** to it, because the ball breaks downhill. Better putters read more of the break: pros read about 70–90%, beginners about 20–40%. The compensation is capped at 30% of the putt distance so golfers never aim wildly off target.

---

## Algorithm

### 1. Tap-in

```
TAP_IN_DISTANCE = 0.045 tiles    # about 3 feet
CUP_RADIUS      = 0.01 tiles     # about 8 inches

if distance_to_hole < TAP_IN_DISTANCE:  the putt is holed automatically
```

### 2. Make rate (exponential decay)

```
distance_feet    = distance_tiles × 66          # 1 tile = 22 yards = 66 feet

base_decay       = 0.053
skill_multiplier = 1.0 + (1.0 − putting_skill) × 2.5
decay            = base_decay × skill_multiplier

make_rate        = max(exp(−distance_feet × decay), 0.01)     # 1% floor
```

**Make rate by distance at putting skill 0.95 (pro):**

| Distance | Feet | Make rate |
| --- | --- | --- |
| 0.045 tile | 3 | Automatic (tap-in) |
| 0.076 tile | 5 | 74% |
| 0.121 tile | 8 | 62% |
| 0.152 tile | 10 | 55% |
| 0.227 tile | 15 | 41% |
| 0.455 tile | 30 | 17% |
| 0.758 tile | 50 | 5% |

**Skill effect on the decay multiplier:**

| Putting skill | Multiplier | Feel |
| --- | --- | --- |
| 0.95 (pro) | 1.125 | Gentle decay, high make rates |
| 0.70 (serious) | 1.75 | Moderate decay |
| 0.50 (casual) | 2.25 | Steeper decay |
| 0.35 (beginner) | 2.625 | Very steep decay |

### 3. Miss distribution

The distribution depends on the distance band, measured in feet:

| Band | Distance error (std dev, tiles) | Lateral error (std dev, tiles) |
| --- | --- | --- |
| Under 10 ft | `0.015 + (1 − skill) × 0.02` | `0.008 + (1 − skill) × 0.017` |
| 10–30 ft | `0.03 + (1 − skill) × 0.06` | `0.015 + (1 − skill) × 0.035` |
| 30 ft and over | `distance × (0.06 + (1 − skill) × 0.12)` | `0.025 + (1 − skill) × 0.06` |

Short putts therefore miss sideways, and long putts miss short or long in proportion to their length.

### 4. Long bias

```
long_bias = 0.02 + putting_skill × 0.03
```

- Skill 0.35: about 0.031 tile (roughly 2 ft past the hole).
- Skill 0.95: about 0.049 tile (roughly 3.2 ft past the hole).

Better players hit the ball firmer, because a putt that does not reach the hole cannot go in.

### 5. Landing position

```
distance_error = gaussian_random() × distance_std + long_bias
lateral_error  = gaussian_random() × lateral_std

landing = hole + direction × distance_error + perpendicular × lateral_error
```

### 6. Miss distance caps

Caps stop cascading multi-putt cycles, so misses end inside easy tap-in range for skilled putters:

```
if distance < 0.15 tile (short):    max_miss = 0.03 + (1 − skill) × 0.025      # about 2–3.6 ft
elif distance < 0.45 tile (medium): max_miss = 0.04 + (1 − skill) × 0.05       # about 2.6–5.9 ft
else (long):                        max_miss = distance × (0.08 + (1 − skill) × 0.12)

if |landing − hole| > max_miss:
    landing = hole + normalise(landing − hole) × max_miss

if |landing − hole| < CUP_RADIUS:
    landing = hole          # the ball drops in
```

### 7. Green edge

If the putt would roll off the green, the path is traced and the ball stops at the last green tile:

```
for each point along the path:
    if terrain is GREEN:       entered_green = true; last_valid = point
    elif entered_green:        break
landing = last_valid
```

### 8. Green reading (ShotAI)

```
slope = _read_green_slope(hole)
if |slope| < 0.1:  aim straight at the hole

read_ability      = 0.2 + putting_skill × 0.7        # pro 0.87, beginner 0.41
break_compensation = min(|slope| × putt_distance × read_ability × 0.5,
                         putt_distance × 0.3)         # never more than 30% of the putt
aim_point          = hole − normalise(slope) × break_compensation

if aim_point is not green:  aim_point = hole         # never aim off the green
```

---

## Tuning Levers

| Lever | Where | Current value | Effect |
| --- | --- | --- | --- |
| Base decay constant | `GolfRules.get_putt_make_rate()` | `0.053` | Higher makes long putts harder to hole |
| Skill multiplier scale | `GolfRules.get_putt_make_rate()` | `2.5` | Higher widens the gap between pros and beginners |
| Tap-in distance | `GolfRules.TAP_IN_DISTANCE` | `0.045` tile (about 3 ft) | Higher gives more automatic makes |
| Cup radius | `GolfRules.CUP_RADIUS` | `0.01` tile (about 8 in) | Higher makes holing out easier |
| Make rate floor | `GolfRules.get_putt_make_rate()` | `0.01` (1%) | Higher allows more lucky long makes |
| Long bias range | `GolfRules.get_putt_miss_characteristics()` | `0.02 + skill × 0.03` | Higher means putts roll further past |
| Miss caps | `Golfer._calculate_putt()` | `0.03–0.055` tile (short and medium) | Higher allows longer comeback putts |
| Green read ability | `ShotAI._decide_putt()` | `0.2 + skill × 0.7` | Range of green reading skill |
| Maximum break compensation | `ShotAI._decide_putt()` | `30%` of putt distance | Higher allows more break adjustment |
| Flat-green threshold | `ShotAI._decide_putt()` | `0.1` slope | Higher treats more greens as flat |

---

## Related

- [Shot Accuracy](shot-accuracy.md) covers full swings.
- [Ball Physics](ball-physics.md) covers the flight of the ball.
- [Player Rounds](player-rounds.md) uses putting in a round.
