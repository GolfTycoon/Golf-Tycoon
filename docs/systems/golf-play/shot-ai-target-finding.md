# Shot AI: Target Finding & Club Selection

> How an AI golfer decides where to aim and which club to hit: a structured pipeline that plans the hole, scores landing zones, and then weighs risk and personality.

**Source:** `scripts/systems/shot_ai.gd` (`decide_shot_for()`, `_decide_recovery_shot()`, `_evaluate_all_candidates()`, `_score_landing_zone()`, `_assess_miss_risk()`, `_decide_putt()`)
**Tests:** `tests/unit/test_shot_ai.gd`, `tests/unit/test_shot_path_calculator.gd`

---

## Plain English

When an AI golfer's turn comes, they must decide **where to aim** and **which club to use**. The ShotAI system is the golfer's "brain," and it works through a fixed pipeline:

1. **Assess the lie.** Is the ball in trouble, such as trees, deep rough or rocks? If the lie is poor, switch to recovery mode.
2. **Plan the sequence.** How many shots will the hole take? Work backwards from the green to find the ideal distance for *this* shot.
3. **Evaluate candidates.** For each club, scan a fan of angles and distances around the line to the hole. Score each landing zone on terrain, distance gained, hazard risk and the setup for the next shot.
4. **Apply personality and situation.** Aggressive golfers discount hazards. Cautious golfers amplify them. Golfers over par play more aggressively, and golfers well under par play safe.
5. **Pick the best.** Return the highest-scoring option; equally scored candidates use scan order as a deterministic tie-break.

### Search efficiency

Within a decision, repeated landing scores and miss risks are cached. Miss sampling is skipped when the landing score plus any accuracy bonus cannot beat the best candidate: miss risk cannot improve the score for normal aggression values. The full scan remains in use if an unusual aggression value would make risk negative. Tree collision and canopy density share one flight scan. The route calculator uses this same decision engine.

### Recovery mode

In trees, heavy or deep rough, bunkers, brush or stony ground, the golfer switches to recovery mode. Club choice is restricted (no woods through trees or long grass, and wedges only from rocks, brush and pot bunkers). The AI scans a full 360° for an escape route, and sideways or backward shots are allowed. It strongly prefers nearby safe targets and gives modest bonuses for fairway or green. This stops a golfer escaping a bunker from choosing a distant fairway over a nearby green.

### Wind compensation

The AI predicts where the ball will actually land in the wind, then shifts its aim the other way. Better players compensate more fully: pros adjust about 77% of the wind effect, beginners about 32%.

### Green-centre bias

On approach shots, less skilled golfers aim partly at the middle of the green instead of the pin, which reduces the chance of missing the green altogether. Pros aim about 95% at the pin; beginners about 58%.

### Multi-shot planning

For par 4s and par 5s the AI plans backwards from the green. The ideal is to leave a comfortable wedge approach of about **3.5 tiles (roughly 77 yards)**. On a par 5 it splits the rest of the distance into two long shots before the approach.

---

## Algorithm

### 1. Lie quality and recovery trigger

`_assess_lie_quality()` maps the terrain the ball sits on to a quality score. Woodland is treated as one family: the trees tile and every species tile share the same lie.

| Terrain | Quality |
| --- | --- |
| Fairway, firm fairway, tee box, green | 1.0 |
| Grass | 0.8 |
| Path | 0.7 |
| Waste bunker | 0.6 |
| Rough | 0.5 |
| Heavy rough, bunker | 0.3 |
| Deep rough | 0.2 |
| Pot bunker, trees | 0.15 |
| Brush | 0.12 |
| Rocks, small and large boulders | 0.1 |
| Water, stream, out of bounds, empty | 0.0 |
| Anything else | 0.2 |

A score below **0.4** triggers recovery mode. A green always uses the putting logic instead (see [Putting System](putting-system.md)).

### 2. Shots remaining

`_estimate_shots_to_hole()` uses the driver's skill-adjusted maximum distance (`max_driver`):

```
distance ≤ max_driver                    → 1 shot   (wedge and short range included)
distance ≤ max_driver × 2                → 2 shots
otherwise                                → 3 shots
```

The ideal distance for the current shot (`_get_ideal_shot_distance()`):

```
shots_remaining = 1  →  go for the target (the whole distance)
shots_remaining = 2  →  min(distance − 3.5, max_driver)
shots_remaining = 3  →  min((distance − 3.5) / 2, max_driver)
```

### 3. Skill distance factor

How far each golfer hits a club, relative to its maximum:

| Club | Formula | Range |
| --- | --- | --- |
| Driver | `0.40 + driving × 0.55` | 0.40–0.95 |
| Fairway wood | `0.40 + driving × 0.50` | 0.40–0.90 |
| Iron | `0.50 + accuracy × 0.42` | 0.50–0.92 |
| Wedge | `0.80 + accuracy × 0.18` | 0.80–0.98 |
| Putter | `0.92 + putting × 0.06` | 0.92–0.98 |

### 4. Candidate scan

`_evaluate_all_candidates()` scans each candidate club across angles and distances:

| Shot type | Angle samples | Half-angle | Distance samples |
| --- | --- | --- | --- |
| Approach (green reachable) | 15 | ±15° | 7, from 60% to 110% of the effective maximum |
| Layup | 25 | ±50° | 7, from 60% to 110% of the effective maximum |
| Wedge approach | — | — | Also samples down to 0.25 tile (about 5.5 yd) |

Each angle also samples lateral offsets of 0, ±1 and ±2 tiles around the aim line. If the best approach candidate lands on grass or rough, a **re-scan** runs at ±50° with 12 angle samples, keeping only good terrain. This stops the AI from aiming through rough when the fairway lies at an angle.

**Terrain scores** are large enough to dominate the distance terms:

| Terrain | Score | Terrain | Score |
| --- | --- | --- | --- |
| Green | +180 | Heavy rough | −20 |
| Fairway | +150 | Flower bed | −40 |
| Firm fairway | +145 | Deep rough | −45 |
| Tee box | +130 | Bunker | −50 |
| Grass | +40 | Trees (and every species) | −80 |
| Path | +35 | Brush | −85 |
| Rough | +10 | Pot bunker | −90 |
| Waste bunker | −10 | Rocks and boulders | −100 |
| Water, stream, out of bounds, empty | −1000 | | |

Streams count as water everywhere the AI looks for hazards. Firm fairway counts as fairway for the approach re-scan and the clear-next-shot bonus.

### 5. Scoring a landing zone

`_score_landing_zone()` combines these terms:

```
score = terrain_score[landing]

# Trees: an instant disqualification if the flight path is blocked
if path crosses trees at low altitude:  score = −2000

# Tree overfly penalty, scaled by how many trees the ball passes over
density   = 1 + max(trees_overflown − 2, 0) × 0.5          # three or more trees: near impassable
score    −= 50 × trees_overflown × (1 − accuracy × 0.3) × density

# Progress toward the hole
if no progress:  score −= 500

# Remaining distance
approach (1 shot left):  score −= distance × 5
layup (more shots left): score −= distance × 4
  └ a bonus for landing near the ideal distance:
     if |distance − 3.5| < 2:  score += (2 − |distance − 3.5|) × 25      # up to +50 (layup)

# Clear approach line from a fairway, grass or tee landing (more than one shot left)
if clear of trees to the hole:  score += 40

# Alignment with the aim line
score += alignment × shot_length × 8

# Nearby hazards within 2 tiles
for each tile: water, OB or empty → penalty += 20 / distance × (1 − aggression × 0.5)
               trees              → penalty += 10 / distance × (1 − aggression × 0.3)

# Club choice: when several clubs reach the green, the more accurate club wins
approach: score += accuracy_modifier × 20                   # prevents a driver on a short par 3
```

### 6. Miss risk (Monte Carlo sampling)

`_assess_miss_risk()` samples eight miss positions across the golfer's dispersion, using the same spread model as the real shot (see [Shot Accuracy](shot-accuracy.md)):

```
sigma_values = [−2, −1, −0.5, −0.25, 0.25, 0.5, 1, 2]
for each sigma:
    angle = sigma × spread_std + tendency_bias
    if the miss lands in water or out of bounds: hazard_hits += 1

risk_penalty = (hazard_hits / 8) × 200 × (1 − aggression × 0.4)
```

### 7. Wind compensation

```
wind_displacement   = WindSystem.get_wind_displacement(direction, distance, club)
compensation_factor = 0.2 + accuracy × 0.6                 # pros about 0.77, beginners about 0.32
aim_point           = target − wind_displacement × compensation_factor
```

### 8. Green-centre bias

```
pin_weight = clamp(accuracy × 0.6 + 0.4, 0.5, 0.95)
blended    = aim × pin_weight + green_centre × (1 − pin_weight)
```

`green_centre` is the green position of the hole being played. A hole that is not in the course yet, such as the potential-hole preview, skips the bias rather than borrowing another green. `decide_shot_for()` takes an optional `grid`, so `HolePathPlanner` can plan on a detached `TerrainGrid.create_analysis_copy()` off the main thread.

### 9. Personality and situation

```
if aggression < 0.3:   bunker landing −80;  rough landing −30
if aggression > 0.7:   +20 to every landing (hazards discounted)

if over par by 3 or more and on the approach:  +15     # push to catch up
if 2 or more under par:                        −10     # protect the lead
```

### 10. Recovery mode

`_decide_recovery_shot()` restricts the clubs and scans out from the ball:

| Trouble lie | Clubs allowed |
| --- | --- |
| Trees | Wedge, iron |
| Rocks, boulders, brush, pot bunker | Wedge |
| Bunker | Wedge, iron |
| Heavy or deep rough | Wedge, iron |

```
max_distance = club_max × skill_factor × 0.7
for 24 directions over 360°:
    for 4 distances from 30% to 100% of max_distance:
        score  = terrain score
        score −= distance from ball × 2            # prefer nearby safe targets
        score += advancement × 3 (toward the hole)
        if moving backward: score −= 50
        if fairway: +30;  if green: +50
        score −= nearby hazard penalty
        score += recovery × 30
```

### 11. Tree collision

A ball flying over trees is only blocked while it is low. The height factor follows the flight arc:

```
t             = position along the path (0 → 1)
height_factor = 4 × t × (1 − t)                  # parabolic arc
blocked       = any TREES tile on the path with height_factor < 0.3
```

---

## Tuning Levers

| Lever | Where | Current value | Effect |
| --- | --- | --- | --- |
| Approach half-angle | `APPROACH_HALF_ANGLE` | `0.26` rad (±15°) | Wider considers more off-line targets |
| Layup half-angle | `LAYUP_HALF_ANGLE` | `0.87` rad (±50°) | Wider considers more creative layup routes |
| Angle samples | `APPROACH_ANGLE_SAMPLES`, `LAYUP_ANGLE_SAMPLES`, `RESCAN_ANGLE_SAMPLES` | `15`, `25`, `12` | More samples means finer scans and more CPU |
| Distance samples | `DISTANCE_SAMPLES` | `7` | More samples means finer distance choice |
| Ideal approach distance | `_get_ideal_shot_distance()`, `_score_landing_zone()` | `3.5` tiles (about 77 yd) | Higher means a longer approach preference |
| Terrain scores | `TERRAIN_SCORES` | See §4 | Higher makes a landing zone more attractive |
| Miss sample count | `MISS_SAMPLE_COUNT` | `8` | More samples give a more accurate risk estimate |
| Risk penalty scale | `_assess_miss_risk()` | `200` | Higher makes targeting more risk-averse |
| Aggression risk discount | `_assess_miss_risk()` | `0.4` | Higher means aggressive players care less about risk |
| Wind compensation | `compensation_factor` | `0.2 + accuracy × 0.6` | Range of wind adjustment by skill |
| Pin weight | `_apply_green_center_bias()` | `0.5–0.95` | Lower minimum makes beginners aim more at the centre |
| Tree height threshold | `_path_crosses_trees()` | `0.3` | Higher makes trees harder to clear |
| Recovery maximum distance | `_decide_recovery_shot()` | `0.7×` | Lower makes recovery shots shorter |
| Recovery scan directions | `_decide_recovery_shot()` | `24` | More directions evaluate more escape routes |
| Recovery threshold | `decide_shot_for()` | `0.4` lie quality | Higher switches to recovery more often |

---

## Related

- [Shot Accuracy](shot-accuracy.md) is applied to the chosen shot.
- [Terrain Types](../course-design/terrain-types.md) lists the terrain scores.
- [Wind System](../environment-and-time/wind-system.md) explains the wind compensation.
- [Tournament Simulation](../events/tournament-simulation.md) reuses this AI for tournament rounds.
