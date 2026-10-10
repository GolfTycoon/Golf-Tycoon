# Play the Course

> Play your own round alongside the management sim: a practice round or a match against a pro, with persistent skills, shot shapes and an aim guide.

**Source:** `scripts/managers/player_round_manager.gd`, `scripts/systems/player_golfer_profile.gd`, `scripts/ui/aim_guide.gd`, `scripts/ui/components/shot_type_bar.gd`, `scripts/entities/golfer.gd` (`preview_shot()`, `preview_shot_to_rest()`, `play_shot()`), `scripts/terrain/terrain_grid.gd` (`snap_world_to_tile_anchor()`)
**Tests:** `tests/unit/test_player_golfer.gd`, `tests/unit/test_aim_guide.gd`, `tests/unit/test_player_round.gd`, `tests/unit/test_shot_type_bar.gd`

---

## Plain English

The **Play the Course** button lets the owner walk onto their own course and play. It is available in building and simulation modes, and at least one hole must be open.

Starting a round does **not** pause the management game. The clock, finances and visiting golfers keep running while the owner plays. Leaving the round restores the camera and any tool state.

### Formats

- **Practice round:** the owner alone.
- **Play vs a Pro:** the owner against one of three pros (Alex, Morgan or Riley), each using the Pro skill tier.

All participants play the open holes from the back tees. The owner and any opponents share a `group_id` and follow the same etiquette as visitor groups: the honor system on tees, the away rule on the green, and waiting for groups ahead to clear. Lowest total wins; equal totals are a tie. Leaving early abandons the round with no result.

### Appearance and skills

The owner chooses a name and their shirt, pants, cap, hair and skin colours. Because baked tier sprites cannot show those colours, the owner is drawn with the procedural golfer renderer. Opponents keep their tier sprites.

Skill points are spent on the **Player Skills** page. The navigation button shows how many points are still unspent. A round can start with points unspent, and the points stay banked for later.

### Tournaments take priority

A hosted tournament starts on click and puts the owner in the field as a competitor (see [Tournament System](../events/tournament-system.md)). Starting an owner round is refused while an event is live. The warning points to the shelf's **Play It Out** button, which settles the event and frees the course.

### The aim guide

On the owner's turn off the green, the cursor becomes a crosshair and an **aim guide** shows the intended shot: the flight arc, the carry point, and the roll that follows. The mouse snaps to a tile centre or vertex, and the guide shows the ball coming to rest exactly there.

The guide shows the *intent*, not a promise. It runs the real execution maths with the random terms removed, so lie, wind, elevation, slope, shape and punch all appear, while miss angle, hook or slice tendency, distance loss and shanks do not. On the green the automatic putting system takes over, with no click needed.

---

## Algorithm

### Persistent skills

`PlayerGolferProfile` stores ten skills, each with a point count from **0 to 99**.

- The owner's **budget is 10 points** (`remaining() = 10 − spent`). `allocate()` spends a point only while the profile is uninitialised. After that, `reallocate()` moves points between skills at any time, including during a round.
- Each point is a **10 percentage-point bonus**: `bonus = points × 0.1`.
- Changes save automatically and take effect on the next shot.
- The profile is saved under `player_golfer`. Older saves receive a fresh profile, and new games reset it. Active rounds are not resumed from saves.

Normalised execution skill uses the bonus `b`:

```
s = 1 − 0.5 / (1 + b)
```

This keeps the normalised AI formulas below 1 even at a 990% bonus.

| Skill | Effect |
| --- | --- |
| Power Hitter | Adds to every non-putter club's range factor |
| Long Driver | Adds to the driver's range factor only |
| Accurate Driver | Driver and fairway-wood accuracy |
| Accurate Irons | Iron and wedge accuracy |
| Accurate Putter | Putting skill (the same automatic putting system) |
| Draw Shot (R to L) / Fade Shot (L to R) | Reduces inaccuracy when that shape is selected |
| High Backspin Shot | Reduces inaccuracy and increases reverse rollout |
| Recovery Skills | Reduces the lie accuracy penalty |
| Luck | Reduces remaining inaccuracy, including shank chance |

**Carry range:** `club.max_distance × 0.7 × (1 + power_bonus + long_driver_bonus)`. The long-driver bonus applies to the driver only. Punch multiplies the range by 0.7. Terrain penalties still reduce the actual distance.

For shape, luck and recovery skills, the relevant residual inaccuracy or lie penalty is divided by `1 + bonus`. AI golfers without a profile are unchanged.

### Shot shapes

`ShotTypeBar` shows one button per shot type across the top of the Play Course page: **straight, fade, draw, high backspin and low punch**. The buttons are mutually exclusive, and the lit button is the shot that `play_shot()` will hit. A shot that the current lie forbids is greyed out in place rather than hidden.

| Shape | Rule |
| --- | --- |
| Straight | Available from every off-green lie |
| Fade | Bends 8° left to right; tee or fairway only |
| Draw | Bends 8° right to left; tee or fairway only |
| High backspin | Reverses rollout by `min(1.5, 0.25 × (1 + bonus))` tiles on green or fairway landings and raises the arc 40%; tee or fairway only |
| Low punch | 70% range, 35% crosswind displacement, 30% arc height, 150% normal rollout; cannot combine with fade, draw or backspin |

An invalid choice falls back to straight, in both the button row and the shot execution, so they always agree.

### Aim guide

`AimGuide` is a `Node2D` child of `PlayerRoundManager`. Every frame the owner is lining up a shot, `update_aim_guide()` snaps the mouse to an anchor and asks `Golfer.preview_shot_to_rest()` for the resting point.

`preview_shot()` clamps the aim the same way `play_shot()` does, then runs `_calculate_shot(..., deterministic = true)` and `_calculate_rollout(..., true)`:

| Random term | Real shot | Preview |
| --- | --- | --- |
| Swing distance variance | Sampled per club | Midpoint of the range |
| Miss angle (gaussian × spread) | Sampled | 0 |
| Miss tendency | Applied | 0 |
| Shank | Possible | Never |
| Distance loss (topped or fat) | Sampled | 0 |
| Rollout fraction | Sampled | 0.5 (its mean) |

Lie and terrain distance, wind, elevation, landing-terrain roll, slope pull, hazard stops, shape bend, punch and backspin all apply. The preview returns the same dictionary shape as the real shot, plus the walked `roll_path`, club and yardage readouts, and a `blocked` flag for shots that would finish in water, out of bounds, a bunker or a flower bed.

**What the guide draws**

- **Arc:** a straight line from ball to carry point, with the ±8° shape bend (converted to screen space so it survives view rotation) and cosmetic wind drift. Both swell as `sin(πt)` and fade to zero at landing. Arc height is `min(carry_screen_distance × 0.3, 150px)`, scaled ×0.3 for punch and ×1.4 for backspin, matching `Ball._process_flight()`.
- **Ground track:** a faint line under the arc that follows terrain elevation.
- **Carry ring:** the landing point.
- **Roll trail:** dotted, along the actual rollout. It turns red if the ball would finish in a hazard, and violet with a back arrow for backspin.
- **Labels:** club, expected carry, shape, "out of range" (with a red X at the raw mouse target when the aim was reined in), roll distance and hazard caption.

The guide is deterministic, so it does not flicker, and it updates live when the shape, punch or wind changes.

### Aiming at a centre or vertex

The mouse does not aim at a free point. It snaps to a terrain **anchor**, meaning a tile centre or a tile vertex. Every anchor on the map must be pickable and reachable by some club.

**Snapping.** `TerrainGrid.snap_world_to_tile_anchor()` ray-marches to the surface under the pointer, so sculpted ground is hit where it is drawn. It compares the screen distance to the centre and four vertices of that tile and its eight neighbours, after elevation and view rotation, and the nearest anchor wins. Pointers up to `ANCHOR_RIM_MARGIN` (0.5 tile) past the map edge still pick a rim anchor.

**Solving for the launch point.** `_solve_aim_for_rest()` inverts the deterministic flight and roll model for one club:

1. Aim at the anchor, run the shot and move the aim by the miss (`aim += anchor − predicted_rest`). Repeat up to `REST_SOLVE_ITERATIONS` (12) times, or until the ball rests within `REST_SOLVE_EXACT_ERROR` (0.02 tile). The closest shot seen is kept.
2. The resting point can jump. Landing in a bunker or water stops the ball, the green rolls differently from the fairway, and a roll under 0.15 tile is dropped. At such an edge the fixed-point pass oscillates, so the solver keeps the latest short and long shots and bisects between them (up to `REST_SOLVE_BISECTIONS`, 14).
3. The shot lands on the anchor when the best resting point is within `REST_SOLVE_TOLERANCE` (0.12 tile).

**Choosing the club.** `select_club()` proposes a club from the distance: driver from 9 tiles, fairway wood from 8, iron from 5, wedge below. The owner's ranges are 0.7 times the AI table, so the bands can leave gaps. The solver tries the proposed club, then each longer club (nearest first), then the shorter ones, and plays the first that lands within tolerance. Every anchor inside the bag's reach therefore has a club that lands on it, except where the terrain itself leaves a gap.

**When an anchor cannot be reached.** The guide still ends on the nearest anchor the ball can actually reach, and reports one of two reasons:

- **Out of range:** the aim is already at the club's maximum (the red X marks the requested anchor).
- **Terrain limited:** there was range to spare, but the ball cannot stop there. A ball that carries a bunker rolls past its far edge, so the tiles just behind it cannot hold the ball.

### State and cleanup

`GolferManager._update_group()` schedules the round the same way as visitor groups. The owner and playing partners share a `group_id`. The `PREPARING_SHOT` wait applies only to an owner off the green; AI and green putting keep their timers.

`play_shot` ignores input while swinging, walking or watching, while paused, off the map, or when aimed at the ball itself. This stops double-click extra strokes.

Owner-round golfers use the tournament spawning path, which skips entrance fees and closing-time limits. `is_owner_round` tells `PlayerRoundManager` to handle completion and results. Visitors and the course simulation keep running throughout. Cleanup removes the owner's group members and balls and leaves visitors alone.

---

## Tuning Levers

| Lever | Where | Default |
| --- | --- | --- |
| Budget and per-skill cap | `player_golfer_profile.gd` (`remaining()`, `allocate()`) | 10 points total / 99 per skill |
| Bonus per point | `PlayerGolferProfile.bonus()` | 0.1 (10%) |
| Normalised baseline | `PlayerGolferProfile.normalized_skill()` | `1 − 0.5 / (1 + bonus)` |
| Carry range factor | `Golfer._get_skill_distance_factor()` | 0.7 |
| Shape bend | `Golfer.shape_bend_degrees()` (`PLAYER_SHAPE_BEND_DEG`) | ±8° |
| Punch range, wind, roll | `player_max_distance()`, `_calculate_shot()` | 0.7, 0.35, 1.5 |
| Backspin distance | `Golfer._calculate_shot()` | 0.25–1.5 tiles |
| Guide arc height ratio and cap | `AimGuide.ARC_HEIGHT_RATIO`, `AimGuide.MAX_ARC_HEIGHT` | 0.3, 150 px |
| Guide bend factor | `AimGuide.BEND_FACTOR` (matches `BallManager`) | 0.06 |
| Guide roll dot spacing and radius | `AimGuide._draw_dotted_trail()` | 9 px, 2.4 px |
| Shortest captioned roll | `AimGuide._draw_labels()` | 5 yd |
| Anchor lands on target within | `Golfer.REST_SOLVE_TOLERANCE` | 0.12 tile |
| Solver stops refining within | `Golfer.REST_SOLVE_EXACT_ERROR` | 0.02 tile |
| Fixed-point passes and bisections | `Golfer.REST_SOLVE_ITERATIONS`, `Golfer.REST_SOLVE_BISECTIONS` | 12, 14 |
| Club change must end this much closer | `Golfer.CLUB_SWITCH_MARGIN` | 0.05 tile |
| Clubs tried, shortest reach first | `Golfer.OWNER_CLUB_LADDER` | wedge, iron, fairway wood, driver |
| Pointer tolerance past the map edge | `TerrainGrid.ANCHOR_RIM_MARGIN` | 0.5 tile |

---

## Related

- [Shot Accuracy](shot-accuracy.md) is used for each shot.
- [Group Turn Order](group-turn-order.md) decides when your golfer plays.
- [Putting System](putting-system.md) covers putts.
- [Course Rating](../ratings-and-reputation/course-rating.md) uses the round results.
