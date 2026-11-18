# Ball Physics & Rollout

> How the ball travels on screen: an arc through the air, then a roll that depends on the ground it lands on, the slope and any backspin.

**Source:** `scripts/entities/ball.gd` (flight and rollout animation, `ground_point()`, `refresh_terrain_occlusion()`), `scripts/managers/ball_manager.gd` (`animate_shot()`, `_on_ball_shot_precise()`, `_shot_ground()`), `scripts/entities/golfer.gd` (`_calculate_rollout()`, `_estimate_flight_duration()`, `_record_shot_ground()`), `scripts/systems/golf_rules.gd` (`get_roll_multiplier()`, `stops_ball_on_landing()`, `catches_rolling_ball()`), `shaders/terrain_sprite_occlusion.gdshader` and `scripts/terrain/terrain_occlusion.gd` (`hides_ball()`, `contact_reach()`: hills in front)
**Tests:** `tests/unit/golf_play/test_ball_and_hole_size.gd`, `tests/unit/golf_play/test_aim_guide.gd`, `tests/unit/course_design/test_terrain_occlusion.gd` (hills in front), `tests/integration/ui_and_controls/test_view_controls.gd` (view turns)

---

## Plain English

Ball physics has two phases: **flight** (the carry through the air) and **rollout** (the roll after landing). Both are visual. The landing position is calculated mathematically by the [shot accuracy](shot-accuracy.md) system before the animation starts, and the ball animates to that answer.

### Flight

Full shots follow a **parabolic arc**. The ball rises to a peak mid-flight and comes down at the landing point. The arc height scales with distance and is capped at 150 pixels. Putts have no arc and roll along the ground, up and over any crown in the green.

**Wind drift** is a bell curve of sideways displacement. The ball drifts most at mid-flight and returns to the landing point at the end. It is cosmetic, because wind has already been applied to the landing.

The ball is drawn with a 1.75 px radius on the ground and a slightly larger 2.24 px radius in flight for visibility. It also grows slightly at the peak of its arc, which gives a sense of depth as it comes closer to the camera. The visible cup and ball shadow scale with the ground ball size; this does not change the rules for holing a shot.

Every ball lays a **contact shadow** on the ground, painted beneath the ball so the ball sits on the course rather than hovering over it. At rest it is a soft, flat ellipse at the ball's foot. In flight it stays on the ground the ball is flying over - directly under the ball's line of flight - and tightens to 55% of its resting size and fades to 50% of its darkness at the top of the arc, then settles back as the ball comes down. The shadow follows the Display page's **Prop & ball shadows** setting: *Contact only* keeps it, *Off* drops it, and an already-placed ball obeys a change without being rebuilt.

### Behind hills

A hill nearer the camera hides the ball behind it, pixel by pixel and contact shadow included, as it hides a tree's trunk or a golfer. A ball on the hill's face, on its top or in front of it is drawn as before, and the shadow of a ball on a slope rising toward the camera is never cut by the slope it lies on. A drive over a ridge stays in view as it climbs and clears the crest, and disappears as it comes down behind it; it lands, rolls and lies behind the ridge, and stays there when the view turns. A low chip is taken to clear a crown it crosses, never to bore through it, and putts and rolls are drawn on the ground. The **Terrain-aware occlusion** graphics setting turns this off, and a flat course never pays for it.

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

A putt (no arc) whose ground is known is drawn on the ground under it instead, `grid_point_to_screen(ground_point())`, so it follows the green's contours rather than the straight screen line between its ends (§12). On level ground the two are the same line.

### 2. Depth scale

```
if max_height > 0:
    scale = 1.0 + (arc_height / max_height) × 0.5   # 1.5× at the peak, 1.0× on the ground
```

### 3. Contact shadow

```
lift_ratio = arc_height / max_height                    # 0 on the ground, 1 at the peak

shadow_position = ball_position + (0, arc_height)       # pushed back down to the ground
                + SHADOW_OFFSET * BALL_RADIUS
                  all divided by the depth scale

shadow_scale    = lerp(1.0, 0.55, lift_ratio) / depth scale
shadow_alpha    = lerp(0.30, 0.15, lift_ratio)
```

The depth scale is divided out because it enlarges everything under the ball with it; without that the shadow would swell exactly when it should read as distance. The shadow's centre sits `(0.2, 0.9)` ball radii from the ball - at its foot, a touch to the right - and its ellipse is `(1.0, 0.5)` ball radii: wider across the tile than up the screen, like every contact shadow in the isometric view, and a shade wider than the ball so a dark rim shows around its foot.

### 4. Flight duration

Full shots (`BallManager._on_ball_shot_precise()`, which uses the carry distance):

```
duration = clamp(1.0 + (yards / 300) × 1.5, 0.5, 3.0)
```

A 100-yard shot takes about 1.5 s; a 250-yard drive about 2.25 s.

Putts (`BallManager.animate_shot()`):

```
duration = clamp(0.3 + (yards / 100) × 0.7, 0.3, 1.5)
```

### 5. Base rollout fractions

Rollout is a fraction of carry distance:

| Club | Minimum | Maximum | Notes |
| --- | --- | --- | --- |
| Driver | 5% | 15% | Long, low-spin shots roll the most |
| Fairway wood | 5% | 14% | |
| Iron | 5% | 14% | Moderate trajectory |
| Full wedge | −4% | 8% | Negative values are backspin |
| Wedge chip | 6% | 18% | Low trajectory, always rolls forward |

**Chip or full wedge:** `distance_ratio = carry / wedge_max_distance`. If the ratio is above **0.65** the shot is a full wedge and backspin is possible. Otherwise it is a chip.

### 6. Backspin

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

### 7. Terrain roll multiplier

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

### 8. Slope

```
slope           = terrain.get_slope_direction(carry_position)
slope_influence = clamp(rollout_distance / 3.0, 0.1, 0.5)
roll_direction  = normalise(shot_direction × (1 − slope_influence) + slope × slope_influence)
slope_dot       = slope · roll_direction

if slope_dot > 0:  rollout_distance *= 1.0 + slope_dot × 0.5     # downhill: up to +50%
if slope_dot < 0:  rollout_distance *= max(0.2, 1.0 + slope_dot × 0.5)   # uphill: at least 20% kept
```

### 9. Hazard check along the roll

The roll is checked every quarter tile (`steps = ceil(rollout × 4)`):

```
for each step:
    if catches_rolling_ball(terrain):     stop
    if ROUGH and previous terrain was FAIRWAY:
        rollout_distance *= 0.6           # 40% of the remaining roll is lost
```

`catches_rolling_ball()` covers water, stream, out of bounds, bunkers, deep rough and brush.

### 10. Rollout animation

```
eased_t     = 1 − (1 − roll_progress)²                 # ease-out
screen_dist = rollout_tiles × 64                        # 64 px per tile
duration    = clamp(0.3 + (screen_dist / 200) × 0.8, 0.2, 1.2)
```

Rolls shorter than **0.15 tile** (about 3 yards) skip the animation. The rolling ball is drawn on the ground under it, `grid_point_to_screen(lerp(roll_start_ground, roll_end_ground, eased_t))`, which on level ground is the straight screen line from the carry to the resting point.

### 11. Landing effect

`Ball._spawn_landing_impact()` plays a radial burst of eight particles (`LandingImpactEffect`, 0.4 s) where the ball lands. The colour is chosen from the ground under the carry point:

| Ground | Burst colour set |
| --- | --- |
| Fairway, firm fairway, tee box, green | `fairway` (green) |
| Grass, rough, heavy rough, deep rough, brush | `grass` |
| Bunker, pot bunker, waste bunker | `bunker` (sand) |
| Water, stream | `water` (blue) |
| Anything else | `default` (grey) |

The burst is skipped for putts and short chips (flight height 10 px or less), and it is not created in the web build.

### 12. Hills in front

The ball is a `Node2D` drawn after the course surface, so no draw order can put a hill in front of it. While the course has relief and the **Terrain-aware occlusion** setting is on (`TerrainGrid.terrain_occlusion_enabled()`), the ball wears `terrain_sprite_occlusion.gdshader`, the tree's and the golfer's per-pixel clip, and every part of it - the ball, a flight's motion blur, a splash and the contact shadow - draws with that material (`use_parent_material`). Each pixel is discarded where the heightfield crosses the pixel's screen ray nearer the camera than the ball (`terrain_hides()` in `terrain_heightfield.gdshaderinc`). Only a ball on the course's own canvas is clipped, and a flat course draws it with no material.

**The ground under the ball.** The shader stands the ball over one grid point, `Ball.ground_point()`, and a screen position cannot supply it: where hills overlap on screen, the front-most surface on a ball's pixel can be the hill in front of it rather than the ground under it. So the ball keeps grid points of its own - `rest_ground`, the ends of its flight (`flight_start_ground`, `flight_end_ground`) and of its roll (`roll_start_ground`, `roll_end_ground`) - and `ground_point()` lerps along them as the screen position lerps between the matching screen ends. The golfer records each shot's ground points just before the shot signals go out (`Golfer.shot_ground_from`, `shot_ground_carry`, `shot_ground_rest`), and `BallManager._shot_ground()` hands them to the ball when they project onto the signalled screen positions (within `Ball.GROUND_MATCH_PX`); anything else falls back to the ground under the screen position, nearest a known point (`TerrainOcclusion.standing_point()`). The tile a ball lands or stops on is the one under that ground point, and a view turn carries the ball across on it (`main.gd`'s `_ball_point_entry()`).

**How high the ball is.** The ball is measured from `ground_offset.y` pixels along its rays past its ground point:

```
reach  = contact_reach(ground_point, OCCLUSION_FOOT)       # OCCLUSION_FOOT = (0.9 + 0.5) × BALL_RADIUS = 2.45 px
track  = flat_y(ground_point) − (position.y + arc_height)  # how high the straight flight track is there
lift   = reach + max(0, ground_t(ground_point) − track)
hidden = terrain_t(pixel) > flat_y(ground_point) + lift − pixel.y + BALL_EPSILON
```

`OCCLUSION_FOOT` is how far down the screen the ball's art reaches below its ground point: the foot of its contact shadow. `TerrainOcclusion.contact_reach()` walks from the ground point toward the camera, straight down the screen, to the ground drawn that far down, and returns how far along the ray it lies. On level ground that is `OCCLUSION_FOOT` itself. On a slope rising `s` pixels a pixel toward the camera, it is `OCCLUSION_FOOT / (1 − s)` - 6.5 px for two levels a tile, 39 px for three - so the slope under the shadow does not cut it. Where the ground in front turns its face away from the camera before the walk gets there, it folds over the ball, and the walk falls back to `OCCLUSION_FOOT` so that its near side hides the ball. A flight's arc is drawn over a straight track between its ends, and the ground in between can rise above that track; the second term lifts the ball to the ground there, so it flies over a hill, never through it. A ball at rest, a putt and a roll are drawn on the ground, so the term is zero for them. A sculpt refreshes the uniforms before the next frame, a view turn re-projects them, and a ball moved from outside its own flight or roll - main.gd carrying a resting ball across the turn - is followed as it is moved. `TerrainOcclusion.hides_ball()` runs the same test on the CPU, and `Ball.terrain_hides_point()` asks it for the tests.

---

## Tuning Levers

| Lever | Where | Current value | Effect |
| --- | --- | --- | --- |
| Ground ball radius | `Ball.BALL_RADIUS` | `1.75` px | Sets the ball, cup and contact shadow size |
| Flight ball radius | `Ball.FLIGHT_RADIUS` | `1.28 × BALL_RADIUS` | Keeps airborne shots visible while scaling with the ball |
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
| Ease-out exponent | `Ball._roll_eased()` | `2.0` | Higher gives a more dramatic slowdown |
| Occlusion slack | `TerrainOcclusion.BALL_EPSILON` (the ball material's `occlusion_epsilon`) | `2.0` px | How far in front of a ball a hill must rise before it hides it |
| Contact shadow reach | `Ball.OCCLUSION_FOOT` | `2.45` px (the shadow's foot) | How far below its ground point a ball's art is kept clear of the ground it lies on |
| Contact reach limit | `TerrainOcclusion.CONTACT_REACH_LIMIT` | `64` px | How far toward the camera the ground under a ball's shadow is looked for |
| Ground match | `Ball.GROUND_MATCH_PX` | `0.5` px | How near a recorded ground point must project to a shot's screen position to be used |
| Ball states | `Ball.BallState` | `AT_REST`, `IN_FLIGHT`, `ROLLING`, `IN_WATER`, `OUT_OF_BOUNDS` | Drives what the rest of the game reacts to |

---

## Related

- [Shot Accuracy](shot-accuracy.md) sets where the ball starts.
- [Shot AI: Target Finding](shot-ai-target-finding.md) chooses the shots that are simulated.
- [Wind System](../environment-and-time/wind-system.md) pushes the ball in flight.
- [Terrain Types](../course-design/terrain-types.md) sets the roll-out for each lie.
