# Ball Physics & Rollout

> How the ball travels on screen: an arc through the air, then a roll that depends on the ground it lands on, the slope and any backspin.

**Source:** `scripts/entities/ball.gd` (flight and rollout animation), `scripts/managers/ball_manager.gd` (`animate_shot()`, `_on_ball_shot_precise()`), `scripts/entities/golfer.gd` (`_calculate_rollout()`, `_estimate_flight_duration()`), `scripts/systems/golf_rules.gd` (`get_roll_multiplier()`, `stops_ball_on_landing()`, `catches_rolling_ball()`)
**Tests:** `tests/unit/test_ball_and_hole_size.gd`, `tests/unit/test_aim_guide.gd`

---

## Plain English

Ball physics has two phases: **flight** (the carry through the air) and **rollout** (the roll after landing). Both are visual. The landing position is calculated mathematically by the [shot accuracy](shot-accuracy.md) system before the animation starts, and the ball animates to that answer.

### Flight

Full shots follow a **parabolic arc**. The ball rises to a peak mid-flight and comes down at the landing point. The arc height scales with distance and is capped at 150 pixels. Putts have no arc and roll along the ground.

**Wind drift** is a bell curve of sideways displacement. The ball drifts most at mid-flight and returns to the landing point at the end. It is cosmetic, because wind has already been applied to the landing.

The ball also grows slightly at the peak of its arc, which gives a sense of depth as it comes closer to the camera.

### Rollout

After the carry lands, the ball may roll forward, or backward with backspin on a full wedge. The distance depends on four things:

- **Club:** drivers roll 5–15% of carry, wedge chips 6–18%.
- **Landing ground:** firm fairway runs fastest (1.6×), greens are fast (1.3×), rough grabs the ball (0.3×), and deep rough and brush almost stop it.
- **Slope:** a downhill roll can run up to 50% farther. Uphill rolls are shorter.
- **Backspin:** skilled golfers can generate backspin on full wedge shots, so the ball rolls backwards.

The rollout is walked one step at a time and checked for hazards:

- A ball that **lands** in water, a stream, out of bounds, a bunker, a pot bunker, or a flower bed does not roll at all.
- A ball that **rolls** into water, a stream, out of bounds, a bunker, deep rough or brush stops there.
- Rolling from fairway into rough loses 40% of the remaining roll.

The walk records `roll_path` (carry point to resting point), so the [aim guide](player-rounds.md#aim-guide) can draw the real roll. `_calculate_shot()` and `_calculate_rollout()` take a `deterministic` flag. `preview_shot()` uses it to replace random terms with their expected values, which gives the *intended* shot.

---

## Algorithm

### 1. Flight arc

```
flight_progress += delta / flight_duration

linear_pos  = start.lerp(end, flight_progress)
arc_height  = sin(flight_progress × PI) × max_height
max_height  = min(distance_pixels × 0.3, 150)     # putts: 0
wind_drift  = wind_visual_offset × sin(flight_progress × PI)

position    = linear_pos − (0, arc_height) + wind_drift
```

### 2. Depth scale

```
if max_height > 0:
    scale = 1.0 + (arc_height / max_height) × 0.5   # 1.5× at the peak, 1.0× on the ground
```

### 3. Flight duration

Full shots (`BallManager._on_ball_shot_precise()`, which uses the carry distance):

```
duration = clamp(1.0 + (yards / 300) × 1.5, 0.5, 3.0)
```

A 100-yard shot takes about 1.5 s; a 250-yard drive about 2.25 s.

Putts (`BallManager.animate_shot()`):

```
duration = clamp(0.3 + (yards / 100) × 0.7, 0.3, 1.5)
```

### 4. Base rollout fractions

Rollout is a fraction of carry distance:

| Club | Minimum | Maximum | Notes |
| --- | --- | --- | --- |
| Driver | 5% | 15% | Long, low-spin shots roll the most |
| Fairway wood | 5% | 14% | |
| Iron | 5% | 14% | Moderate trajectory |
| Full wedge | −4% | 8% | Negative values are backspin |
| Wedge chip | 6% | 18% | Low trajectory, always rolls forward |

**Chip or full wedge:** `distance_ratio = carry / wedge_max_distance`. If the ratio is above **0.65** the shot is a full wedge and backspin is possible. Otherwise it is a chip.

### 5. Backspin

```
spin_skill = accuracy × 0.6 + recovery × 0.4

if spin_skill > 0.7:
    spin_bonus = (spin_skill − 0.7) / 0.3             # 0.0 → 1.0
    base_rollout −= spin_bonus × 0.10

base_rollout = max(base_rollout, −0.04)               # never more than 4% of carry back
is_backspin  = base_rollout < 0
```

Backspin is only partly affected by the ground, because the spin is on the ball:

```
terrain_mult = lerp(1.0, terrain_mult, 0.4)           # 40% of the terrain effect applies
```

### 6. Terrain roll multiplier

`GolfRules.get_roll_multiplier(terrain)` is the single table used for every roll.

| Landing ground | Multiplier | Feel |
| --- | --- | --- |
| Firm fairway | 1.6× | Hard, fast turf: the ball bounds on and releases |
| Green | 1.3× | Fast, smooth |
| Path | 1.4× | Hard surface, extra bounce |
| Fairway, tee box | 1.0× | Baseline |
| Grass | 0.35× | Natural grass grabs the ball |
| Rough | 0.3× | Rough grabs the ball |
| Waste bunker | 0.3× | Firm sand lets the ball skid a little |
| Heavy rough | 0.12× | Stops fast |
| Trees | 0.2× | Dense ground cover |
| Rocks, small and large boulders | 0.15× | Stony ground kills momentum |
| Deep rough | 0.06× | Nestles down almost where it lands |
| Brush | 0.05× | Swallowed by the scrub |
| Water, stream, out of bounds, bunker, pot bunker, flower bed | — | No roll |

### 7. Slope

```
slope           = terrain.get_slope_direction(carry_position)
slope_influence = clamp(rollout_distance / 3.0, 0.1, 0.5)
roll_direction  = normalise(shot_direction × (1 − slope_influence) + slope × slope_influence)
slope_dot       = slope · roll_direction

if slope_dot > 0:  rollout_distance *= 1.0 + slope_dot × 0.5     # downhill: up to +50%
if slope_dot < 0:  rollout_distance *= max(0.2, 1.0 + slope_dot × 0.5)   # uphill: at least 20% kept
```

### 8. Hazard check along the roll

The roll is checked every quarter tile (`steps = ceil(rollout × 4)`):

```
for each step:
    if catches_rolling_ball(terrain):     stop
    if ROUGH and previous terrain was FAIRWAY:
        rollout_distance *= 0.6           # 40% of the remaining roll is lost
```

`catches_rolling_ball()` covers water, stream, out of bounds, bunkers, deep rough and brush.

### 9. Rollout animation

```
eased_t     = 1 − (1 − roll_progress)²                 # ease-out
screen_dist = rollout_tiles × 64                        # 64 px per tile
duration    = clamp(0.3 + (screen_dist / 200) × 0.8, 0.2, 1.2)
```

Rolls shorter than **0.15 tile** (about 3 yards) skip the animation.

### 10. Landing effect

`Ball._spawn_landing_impact()` plays a radial burst of eight particles (`LandingImpactEffect`, 0.4 s) where the ball lands. The colour is chosen from the ground under the carry point:

| Ground | Burst colour set |
| --- | --- |
| Fairway, firm fairway, tee box, green | `fairway` (green) |
| Grass, rough, heavy rough, deep rough, brush | `grass` |
| Bunker, pot bunker, waste bunker | `bunker` (sand) |
| Water, stream | `water` (blue) |
| Anything else | `default` (grey) |

The burst is skipped for putts and short chips (flight height 10 px or less), and it is not created in the web build.

---

## Tuning Levers

| Lever | Where | Current value | Effect |
| --- | --- | --- | --- |
| Maximum arc height | `Ball.start_flight()` | `150.0` px | Higher gives a more dramatic arc |
| Arc height ratio | `Ball.start_flight()` | `0.3` × distance in pixels | Higher gives higher shots |
| Peak depth scale | `Ball._process_flight()` | `0.5` added (1.5× at peak) | Higher gives a stronger depth effect |
| Full-shot flight duration | `BallManager._on_ball_shot_precise()` | `1.0 + yards/300 × 1.5`, 0.5–3.0 s | Longer is a slower animation |
| Putt flight duration | `BallManager.animate_shot()` | `0.3 + yards/100 × 0.7`, 0.3–1.5 s | Longer is a slower putt |
| Rollout fractions | `Golfer._calculate_rollout()` | See the table in §4 | Higher rolls the ball further |
| Chip threshold | `Golfer._calculate_rollout()` | `0.65` distance ratio | Higher treats more shots as chips |
| Backspin skill threshold | `Golfer._calculate_rollout()` | `0.7` | Lower gives backspin to more players |
| Maximum backspin | `Golfer._calculate_rollout()` | `−4%` of carry | More negative gives more backspin |
| Terrain roll multipliers | `GolfRules.get_roll_multiplier()` | See §6 | Higher rolls the ball further on that surface |
| Ground that stops a rolling ball | `GolfRules.catches_rolling_ball()` | Water, stream, OB, bunkers, deep rough, brush | Add a type to make it swallow rolling balls |
| Slope influence range | `Golfer._calculate_rollout()` | `0.1–0.5` | Higher makes slope bend the roll more |
| Downhill bonus | `Golfer._calculate_rollout()` | `+50%` | Higher gives a longer downhill run |
| Rough deceleration | `Golfer._calculate_rollout()` | `0.6×` | Lower makes rough stop the ball faster |
| Minimum rollout | `Golfer._calculate_rollout()` | `0.15` tile | Lower shows shorter rolls |
| Preview rollout fraction | `Golfer._calculate_rollout()` (deterministic) | `0.5` (mean) | Higher makes the aim guide roll further |
| Ease-out exponent | `Ball._start_rollout()` | `2.0` | Higher gives a more dramatic slowdown |
| Ball states | `Ball.BallState` | `AT_REST`, `IN_FLIGHT`, `ROLLING`, `IN_WATER`, `OUT_OF_BOUNDS` | Drives what the rest of the game reacts to |

---

## Related

- [Shot Accuracy](shot-accuracy.md) sets where the ball starts.
- [Shot AI: Target Finding](shot-ai-target-finding.md) chooses the shots that are simulated.
- [Wind System](../environment-and-time/wind-system.md) pushes the ball in flight.
- [Terrain Types](../course-design/terrain-types.md) sets the roll-out for each lie.
