# Routing Overlay & Walk Distance

> The routing overlay draws a coloured line from each green to the next tee, showing how far golfers walk between holes. Long walks reduce the course's Pace rating.

**Source:** `scripts/course/routing_overlay.gd` (`SHORT_THRESHOLD`, `MODERATE_THRESHOLD`), `scripts/systems/course_rating_system.gd` (`_calculate_pace_rating()`, walk penalty), `scripts/main/main.gd` (Shift+R toggle)

---

## Plain English

The routing overlay shows the walk from each hole's green to the next hole's tee. It helps you spot where golfers walk a long way between holes.

Long walks slow down the pace of play. That feeds into the **Pace** rating, which is one of the course rating's categories. To keep pace high, cluster your holes or link them with paths.

Toggle the overlay with **Shift+R**.

---

## Algorithm

### 1. Route segments

For each pair of consecutive holes (hole N and hole N+1):

```
from     = hole N green position
to       = hole N+1 tee position
distance = straight-line distance, in tiles
```

The straight-line distance is a quick, deterministic estimate. The real walk is never shorter than it, so it gives a lower bound.

### 2. Colour coding

| Distance | Colour | Meaning |
| --- | --- | --- |
| Under 30 tiles | Green | Short walk, good routing |
| 30 to 60 tiles | Yellow | Moderate walk, acceptable |
| Over 60 tiles | Red | Long walk, pace penalty |

At 22 yards per tile, 30 tiles is about 660 yards and 60 tiles is about 1,320 yards.

### 3. Pace walk penalty

`_calculate_pace_rating()` calculates the average walk between holes, `avg_walk`, in tiles. The penalty is applied before the marshal modifier.

```
if avg_walk > 60:
    walk_penalty = clamp((avg_walk − 60) × 0.033, 0.0, 1.0)
elif avg_walk > 40:
    walk_penalty = (avg_walk − 40) × 0.005
else:
    walk_penalty = 0

pace_rating = (base_rating − walk_penalty) × marshal_modifier
```

The largest penalty is **1.0** star, reached at an average walk of about 90 tiles.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Short threshold | `routing_overlay.gd` `SHORT_THRESHOLD` | `30` tiles | Below this the line is green |
| Moderate threshold | `routing_overlay.gd` `MODERATE_THRESHOLD` | `60` tiles | Above this the line is red |
| Penalty start | `course_rating_system.gd` `_calculate_pace_rating()` | `40` tiles average | Walk length before any penalty |
| Penalty scale (above 60) | `course_rating_system.gd` | `0.033` per tile | Rate of penalty for long walks |
| Penalty scale (40 to 60) | `course_rating_system.gd` | `0.005` per tile | Rate of mild penalty |
| Penalty cap | `course_rating_system.gd` | `1.0` star | Largest possible reduction |

---

## Related

- [Course Rating](../ratings-and-reputation/course-rating.md) explains how the Pace rating feeds the overall score.
- [Hole Creation](hole-creation.md) covers where greens and tees are placed.
- [Hole Routing](hole-routing.md) covers reordering the round, which is what moves the legs.
- [Course Map](course-map.md) draws the same legs in its Routing mode.
