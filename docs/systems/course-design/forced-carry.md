# Forced Carry Distance

> A forced carry is a stretch of water or bunker that lies directly between the tee and the pin. This page explains how each carry is measured, drawn and scored.

**Source:** `scripts/course/forced_carry_calculator.gd` (`calculate_carries()`, `CarrySegment`), `scripts/course/difficulty_calculator.gd` (`_calculate_carry_difficulty()`), `scripts/course/hole_visualizer.gd` (dashed carry lines and yardage labels)

---

## Plain English

A **forced carry** is a run of hazard (water, stream, bunker or pot bunker) that sits on the straight line from tee to pin. Golfers have to fly the ball over it. The system walks that line, finds each hazard run, and measures the carry in yards from the last safe tile before it to the first safe tile after it.

On the hole visualizer, each carry is a dashed line with a yardage label at its midpoint:

- **Orange:** the carry is 150 yards or less, which is within the beginner's club range.
- **Red:** the carry is more than 150 yards.

Carries also add to the hole's difficulty rating. See [Difficulty Calculator](difficulty-calculator.md).

---

## Algorithm

### 1. Hazard scan

```
walk the tee-to-pin centre line in steps of 1 tile
for each sample:
    if it enters a hazard (water, stream, bunker or pot bunker):
        remember the last safe tile
    if it leaves a hazard:
        carry = distance from last safe tile to this tile
        store a CarrySegment
    remember this tile as the last safe tile when it is not a hazard
```

The scan measures straight-line distance. It does not use A* or the AI's planned waypoints. The result describes the hole's geometry, not what a golfer will decide to do.

### 2. Segment data

Each segment is a `CarrySegment` with:

| Field | Meaning |
| --- | --- |
| `hazard_type` | The hazard's terrain type (water or stream, bunker or pot bunker) |
| `start_grid` | Last safe tile before the hazard |
| `end_grid` | First safe tile after the hazard |
| `carry_yards` | Tile distance × **22** yards per tile |
| `exceeds_beginner_range` | `true` when `carry_yards > 150` |

### 3. Difficulty contribution

`_calculate_carry_difficulty()` scores each segment:

| Hazard | Carry length | Difficulty added |
| --- | --- | --- |
| Water or stream | over 200 yards | +1.5 |
| Water or stream | 151 to 200 yards | +1.0 |
| Water or stream | 101 to 150 yards | +0.5 |
| Water or stream | 100 yards or less | +0.2 |
| Bunker or pot bunker | over 150 yards | +0.5 |
| Bunker or pot bunker | 81 to 150 yards | +0.3 |
| Bunker or pot bunker | 80 yards or less | +0.1 |

The total is capped at **2.0**.

### 4. Display

- Orange dashed line: carry is 150 yards or less.
- Red dashed line: carry is over 150 yards.
- Yardage label at the midpoint of each segment.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Beginner range threshold | `forced_carry_calculator.gd` `exceeds_beginner_range` | `150` yards | Changes when a carry is shown red |
| Yards per tile | `terrain_grid.gd` `calculate_distance_yards()` | `22` | Converts tile distance to yards |
| Water carry difficulty | `_calculate_carry_difficulty()` | `0.2` to `1.5` per segment | Harder water carries |
| Bunker carry difficulty | `_calculate_carry_difficulty()` | `0.1` to `0.5` per segment | Harder bunker carries |
| Carry difficulty cap | `_calculate_carry_difficulty()` | `2.0` | Maximum total from carries |

---

## Related

- [Difficulty Calculator](difficulty-calculator.md) combines carries with the other factors.
- [Terrain Types](terrain-types.md) describes the Bunker and Pot Bunker tiles that count as carries.
- [Hole Creation](hole-creation.md) covers how holes are laid out.
