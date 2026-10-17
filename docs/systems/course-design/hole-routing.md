# Hole Routing & the Order of Play

> A course is its holes played in order, so the order is part of the design: reorder the round, turn a hole around, set its par, and read how far golfers walk between holes.

**Source:** `scripts/course/hole_routing.gd` (`SHORT_TILES`, `MODERATE_TILES`, `Grade`, `move()`, `reverse()`, `flip()`, `legs()`, `route_report()`), `scripts/managers/hole_manager.gd` (`MIN_PAR`, `MAX_PAR`, `find_hole()`, `move_hole()`, `reverse_hole_order()`, `flip_hole()`, `set_hole_par()`, `rebuild_visualizations()`), `scripts/autoload/event_bus.gd` (`holes_reordered`), `scripts/ui/components/course_map_routing_panel.gd`
**Tests:** `tests/unit/course_design/test_hole_routing.gd`, `tests/integration/ui_and_controls/test_course_map_screen.gd`

---

## Plain English

A course is an array of holes (`GameManager.current_course.holes`) and golfers
play it from the first entry to the last. `hole_number` is that order's label:
hole 3 is whichever hole is third, not a fixed piece of ground.

Everything that reshuffles the round is done from the **Course Map**'s Routing
mode (see [Course Map](course-map.md)), and it all ends in the same place —
`HoleRouting.renumber()`, which labels the holes 1..N in play order. That is why
a hole's number can never disagree with where it sits in the round.

| Edit | What happens |
| --- | --- |
| Move a hole up or down | It changes places with its neighbour and both are renumbered. Golfers part-way round keep playing the hole they were on. |
| Play the round the other way round | The array is reversed: the last hole is played first, everything renumbered, every hole still played from its own tee to its own green. |
| Turn a hole around (flip) | The tee and the green swap ends on the grid, the cup is re-cut in the new green, and the hole plays the other way across the same ground. |
| Change a hole's par | Par is set between `MIN_PAR` and `MAX_PAR`, written as `par_override` so it survives a reload, or cleared back to automatic when you pick the par the distance already implies. |
| Shut a hole | The hole stays in the round but is closed to play (`is_open`), so it can be repaired or replaced without being deleted. |

The routing changes are the routing overlay's business too: the walk from each
green to the next tee is measured here, and the same numbers decide the colour
of the lines drawn on the course itself (see
[Routing Overlay](routing-overlay.md)).

---

## Algorithm

### 1. Legs

Every pair of consecutive holes has one leg: the straight-line walk from the
green just played to the next tee.

```
leg_tiles(i) = distance( holes[i].green_position, holes[i+1].tee_position )   # in tiles
yards        = tiles × HoleLayout.YARDS_PER_TILE
```

The last hole has no leg after it, so a course of N holes has N − 1 legs and an
empty course has none.

### 2. Grades

A leg is graded by length, using the same thresholds the on-course overlay
paints with, so the map and the course can never disagree:

| Grade | Length | Colour | Meaning |
| --- | --- | --- | --- |
| Short | under 30 tiles | green | The next tee is a short walk away |
| Moderate | 30 to 60 tiles | amber | Acceptable, but the round starts to drag |
| Long | 60 tiles and over | red | A long walk that costs the course its pace rating |

`SHORT_TILES` and `MODERATE_TILES` are read from
`RoutingOverlay.SHORT_THRESHOLD` and `RoutingOverlay.MODERATE_THRESHOLD` rather
than copied, so tuning the overlay tunes the map.

### 3. The route report

The Routing panel's headline is `route_report(holes)`, which describes the shape
of the round in numbers:

| Key | Meaning |
| --- | --- |
| `holes`, `open` | How many holes the round has, and how many of them are open |
| `total_par`, `total_yards` | The round's par and its length |
| `average_leg_tiles` | The average walk between holes — the number the Pace rating penalises |
| `longest_leg`, `worst_after_hole` | The worst walk, and which hole it comes after |
| `long_legs` | How many legs are long enough to count against pace |

### 4. Routes and the rest of the game

A reorder, a flip and a par change are all done through `HoleManager`, which
keeps the rest of the game in step:

1. `HoleRouting.renumber()` labels the round.
2. `StrokeIndexCalculator.recalculate_for_course()` re-ranks the holes by
   difficulty (see [Stroke Index](stroke-index.md)).
3. `EventBus.hole_updated` / `hole_tee_moved` / `hole_green_moved` tell the
   course-side views what moved, and `EventBus.holes_reordered` carries the new
   order to anything that lists holes.
4. `rebuild_visualizations()` rebuilds each hole's marker in the world.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Short leg | `routing_overlay.gd` `SHORT_THRESHOLD` | `30` tiles | Below this a leg is short (and drawn green) |
| Long leg | `routing_overlay.gd` `MODERATE_THRESHOLD` | `60` tiles | At and above this a leg is long (and drawn red) |
| Par range | `hole_manager.gd` `MIN_PAR` / `MAX_PAR` | `3` to `6` | What a hole's par may be set to from the map |
| Yards per tile | `hole_layout.gd` `YARDS_PER_TILE` | `22` | Converts a leg's tiles into the yards shown in reports |

---

## Related

- [Course Map](course-map.md) covers the screen the reordering is done from.
- [Routing Overlay](routing-overlay.md) covers the same legs drawn on the course.
- [Hole Creation](hole-creation.md) covers painting a tee and a green and opening a hole.
- [Stroke Index](stroke-index.md) covers the ranking that is recalculated after every reorder.
- [Course Rating](../ratings-and-reputation/course-rating.md) explains how the average walk reaches the Pace rating.
