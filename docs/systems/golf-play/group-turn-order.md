# Group Turn Order & Ready Golf

> Who plays next in a group, and what a group waits for: the group owns the turn, and partners keep walking while the next golfer plays.

**Source:** `scripts/managers/golfer_manager.gd` (`_update_group()`, `_determine_next_golfer_in_group()`, `_is_walking_group_clear()`, `_is_landing_area_clear()`, `_advance_golfer()`), `scripts/entities/golfer.gd` (`take_shot()`, `_walk_to_ball()`, `_on_reached_destination()`)
**Tests:** `tests/unit/test_group_turn_order.gd`, `tests/unit/test_tournament_hosting.gd`, `tests/harness/ready_golf_harness.tscn`

---

## Plain English

Golfers play in groups, and the **group owns the turn**. One golfer at a time prepares, swings and watches the ball, and the rest wait their turn.

Turn order follows the usual rules:

- **Honor** off the tee: the best score on the previous hole goes first. On hole 1 the lowest `golfer_id` goes first.
- **The away rule** through the green: the golfer furthest from the cup plays first.

### Ready golf

The group does not wait for every partner to finish walking to their ball. As soon as the previous shot comes to rest, the next golfer away plays, and the partners carry on walking.

A walking partner only holds the turn up when they are physically standing where this ball is going:

- in the **landing zone** of a full swing, or
- on the **route** of a chip or putt, so nobody is struck while bending over the cup.

A partner in the way steps clear in about a second, and the group goes.

### What still stops a group

- **A shot in progress.** Nobody plays while a partner is preparing, swinging or watching their ball.
- **The group ahead.** A shot is refused while its landing cone holds a golfer from an earlier group. The tee and par-3 rules also keep groups apart.
- **A partner standing in the line.** This is narrow: a walker inside the landing cone, or close to a chip or putt route.

Off the tee nothing changes. Every member of the group still tees off in turn before anyone waits, because that is how a tee box empties.

### Measured effect

`tests/harness/ready_golf_harness.tscn` boots the real game, quick-starts a nine-hole course, puts one foursome on it, and plays three holes per golfer at ULTRA speed for three seeds. It counts the frames where a golfer was ready to play, a partner was still walking, and no shot was in progress.

| Measure | Old scheduler | Ready golf |
| --- | --- | --- |
| Ready-but-waiting share of group time | 17.5%, 18.7% | 5.3%, 5.7%, 8.3% |
| Shots struck while a partner was still walking | 33 of 168, 36 of 183 | 62 of 191, 70 of 184, 69 of 182 |

Roughly two thirds of the waiting time has gone, and the share of shots played while someone is on the move about doubled. The remaining few percent are real: a walker genuinely standing in the line, and the walk to the next tee after a hole is finished. The harness is stepped on real frame deltas, so read these as ranges rather than exact figures.

---

## Algorithm

`_update_group()` runs once per group per frame. The order matters:

```
1. clear traffic_blocked on every member
2. if anybody is PREPARING_SHOT, SWINGING or WATCHING        → return   (shot in progress)
3. if a member has holed out and is IDLE                      → advance them, return   (one per frame)
4. next = _determine_next_golfer_in_group(group)              (honor, then away)
5. if next is teeing, or _is_walking_group_clear(next, group):
6.     if _is_landing_area_clear(next, group): _advance_golfer(next)
7.     else: traffic_blocked = true for the group             (group ahead is in the way)
```

Step 2 is the whole turn gate. Walking is not on that list, so a walking partner never blocks the group by itself. Step 5 decides whether *this* shot is safe over the partners who are still walking.

### The walking-partner check

`_is_walking_group_clear(shooting_golfer, group)` takes the target of the shot about to be played (the same target `_is_landing_area_clear()` uses). It only tests partners who are **walking** and on **the same hole**. Partners who have stopped are standing at their own ball, and they never hold a shot up.

A walker's *body* is what a ball would hit, and it is well short of the ball they are heading for. The check therefore reads `terrain_grid.screen_to_grid_precise(global_position)`, not `ball_position`.

**Short shots** (chips and putts, under `GROUP_SHORT_SHOT_DISTANCE_TILES`) keep their whole route clear, because the ball is on the ground the entire way:

```gdscript
if _distance_to_line_segment(partner, origin, target) < GROUP_SHORT_SHOT_CLEARANCE_TILES:
    return false
```

**Full swings** keep the landing cone clear, using the same shape as `_is_cone_clear_of_golfers()`:

```gdscript
min_check_distance = shot_distance * 0.6                 # nothing lands much shorter
max_check_distance = shot_distance + landing_radius      # landing_radius = 2.0 + 0.3 × distance
if to_partner.dot(direction) < 0.0: continue             # behind the golfer
if not min ≤ |to_partner| ≤ max: continue
if abs(direction.angle_to(to_partner)) > LANDING_CONE_HALF_ANGLE: continue   # π/4
return false                                             # inside the cone: hold the shot
```

Because only walkers are tested, the check cannot deadlock. A partner whose ball lies inside the cone walks to it, arrives, goes IDLE, and is no longer checked.

---

## Tuning Levers

| Lever | Where | Current value | Effect |
| --- | --- | --- | --- |
| `GROUP_SHORT_SHOT_DISTANCE_TILES` | `golfer_manager.gd` | `2.5` tiles (about 55 yd) | Longer treats more shots as chips and putts, judged on their whole route |
| `GROUP_SHORT_SHOT_CLEARANCE_TILES` | `golfer_manager.gd` | `1.0` tile (about 22 yd) | Clearance kept around a chip or putt. Bigger makes partners step further aside |
| `LANDING_ZONE_BASE_RADIUS` | `golfer_manager.gd` | `2.0` tiles | Minimum radius of the landing cone that a walker must clear |
| `LANDING_ZONE_VARIANCE` | `golfer_manager.gd` | `0.3` | Fraction of shot distance added to the cone radius |
| `LANDING_CONE_HALF_ANGLE` | `golfer_manager.gd` | `π / 4` | Wider cone makes walkers block from further off the line |
| `PREPARATION_DURATION` | `golfer.gd` | `1.0` s | Time the golfer whose turn it is takes to address the ball |
| `walk_speed` | `golfer.gd` | `100` px/s | How quickly a blocked walker steps clear (about one tile per 0.3–0.6 s). A walking trail multiplies it by 1.25, or 1.5 once paved — see [Walking Paths](../course-design/walking-paths.md) |

---

## Related

- [Player Rounds](player-rounds.md) covers the round your golfer plays.
- [Golfer Spawning](../golfers/golfer-spawning.md) sets how many groups are on the course.
- [Golfer Needs and Statuses](../golfers/golfer-needs.md) covers the pace need that waiting drains.
