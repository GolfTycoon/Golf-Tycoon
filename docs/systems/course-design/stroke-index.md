# Stroke Index

> The stroke index ranks each open hole from 1 (hardest) to N (easiest), like the "Hcp" row on a scorecard. It is worked out automatically from each hole's difficulty rating.

**Source:** `scripts/systems/stroke_index_calculator.gd` (`calculate()`), `scripts/autoload/game_manager.gd` (`HoleData.stroke_index`)
**Depends on:** [Difficulty Calculator](difficulty-calculator.md) ratings (1.0 to 10.0)
**Used by:** `scripts/ui/components/course_scorecard_view.gd`, `scripts/ui/hole_stats_panel.gd`

---

## Plain English

On a real scorecard, each hole has a handicap index. The hardest hole gets 1, and the easiest gets the highest number. Here the index is worked out from each hole's difficulty rating, so you never set it by hand.

Only open holes are ranked. For more than nine holes, the front nine gets the odd numbers and the back nine gets the even numbers. This spreads the hard holes evenly across both halves of the course, as real courses do.

The index is derived data. It is recalculated on load rather than saved.

---

## Algorithm

### 1. Filter and sort

1. Keep only open holes.
2. Sort by `difficulty_rating`, hardest first.
3. If two ratings are within 0.01 of each other, the lower hole number ranks harder.

### 2. Assign indices

**Nine or fewer open holes:** sequential. The hardest hole gets 1, the next gets 2, and so on.

**Ten or more open holes:** interleaved.

- Front nine (holes 1 to 9) take the odd indices in order: 1, 3, 5, 7, 9, ...
- Back nine (hole 10 onward) take the even indices in order: 2, 4, 6, 8, 10, ...

### 3. Store

`calculate()` returns a map from hole number to stroke index. The result is written to each `HoleData.stroke_index`.

### 4. When it runs

- A hole is created.
- A hole is deleted.
- A hole is opened or closed.
- A game is loaded.

---

## Example

| Hole | Difficulty | Stroke index |
| --- | --- | --- |
| 3 | 7.8 | 1 (hardest) |
| 7 | 6.5 | 3 |
| 1 | 5.9 | 5 |
| 5 | 4.2 | 7 |
| 9 | 3.1 | 9 (easiest) |

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Tie window | `stroke_index_calculator.gd` | `0.01` | Ratings closer than this are treated as equal |
| Tie-break rule | `stroke_index_calculator.gd` sort | Lower hole number ranks harder | Could use hazard count or length instead |
| Sequential threshold | `stroke_index_calculator.gd` | `9` holes or fewer | Above this, the interleaved rule applies |
| Difficulty source | `difficulty_calculator.gd` | See [Difficulty Calculator](difficulty-calculator.md) | Changing the difficulty formula also changes stroke indices |

---

## Related

- [Hole Creation](hole-creation.md) opens the holes that are ranked here.
- [Difficulty Calculator](difficulty-calculator.md) supplies the difficulty rating used for the ranking.
- [Course Rating](../ratings-and-reputation/course-rating.md) uses the same difficulty figures.
