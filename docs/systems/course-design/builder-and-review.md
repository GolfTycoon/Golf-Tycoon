# Builder Tools & Course Review

> How the terrain brushes paint a course in one undoable stroke, and how the Course Review panel turns the course's current state into up to four concrete suggestions.

**Source:** `scripts/tools/terrain_brush.gd` (`centers()`, `offsets()`), `scripts/tools/undo_manager.gd`, `scripts/main/main.gd` (stroke handling and redo affordability), `scripts/systems/course_advisor.gd` (`review()`)
**Tests:** `tests/unit/test_tile_honeycomb.gd`, `tests/unit/test_terrain_toolbar.gd`, `tests/integration/builder_regression.gd`

---

## Plain English

**Painting.** Dragging with a terrain tool paints a continuous line rather than leaving gaps between clicks. Round brushes make soft contours, and square brushes keep straight edges. Each stroke is recorded as one undo step. That step covers the terrain changed, any trees cleared, and the total amount charged. Releasing the mouse over the UI or cancelling closes the stroke. Painting respects buildings, decorations and land ownership.

**Undo and redo.** Undo restores the terrain, the cleared objects and the cash spent. The undo stack keeps the last 50 actions. Redo checks that you can still afford the action before re-applying it, and refuses if you can't.

**Course Review.** The review looks at the course as it is now and lists up to four suggestions, most urgent first. Each suggestion has a Locate button that focuses the affected hole, or a button that opens the finance or decoration panel where relevant. The end-of-day summary repeats a suggested next step.

---

## Algorithm

### 1. Stroke interpolation

`TerrainBrush.centers()` fills the gap between two mouse samples. It walks the line in steps of `max(|dx|, |dy|)`, so consecutive brush stamps are never more than one tile apart on either axis. `centers_4_connected()` is the variant for a 4-connected path.

### 2. Brush footprint

`TerrainBrush.offsets(diameter, round_shape)` builds the stamp for sizes 1 to 9. These are the same sizes as the Elevation Brush.

- **Odd sizes** centre on the cursor tile.
- **Even sizes** centre on the corner shared by the cursor tile and its neighbours, so an S×S stamp always covers S tiles per side.
- **Square** brushes include every tile in the block.
- **Round** brushes keep a tile only if its centre lies within a circle of radius S/2 around the middle of the block.

### 3. Strokes and undo

1. `begin_stroke()` opens a stroke.
2. Each painted tile calls `record_tile_change()`, which stores the old and new terrain, any cleared object and any cost.
3. `end_stroke()` closes the stroke and pushes it as a single entry onto the undo stack.
4. Redo re-applies the stored change only if `GameManager.money` covers the recorded price. A terrain change with no recorded price is charged the terrain placement cost.

### 4. Course review checks

`CourseAdvisor.review()` returns nothing if no holes are open. Otherwise it runs these checks in order. The list is trimmed to the first **four** entries.

| # | Check | Trigger | Suggestion | Button |
| --- | --- | --- | --- | --- |
| 1 | Guests did not finish | Operating costs above zero and more guests arrived than were served | Reduce bookings and inspect traffic delays | Finance |
| 2 | Incident hotspots | `FeedbackManager.get_hotspots()` reports a problem spot | Incident title and guidance for that hole | Locate |
| 3 | Tee or cup surface | A hole's tee is not a tee box, or its cup is not a green. The first hole that fails stops the loop. | "Finish hole N": restore a tee box and putting green | Locate |
| 4 | Direct corridor | Less than **65%** of the tee-to-green corridor is short turf (fairway, firm fairway, green or tee box), sampled 3 tiles wide | "Improve hole N's landing area" for the worst hole | Locate |
| 5 | Course value | Golfer value rating below **2.8 / 5** | "Review your green fee" | — |
| 6 | Food service | A hole 4 or later has no snack bar, pub or clubhouse within reach of its tee | "Add a refreshment stop near hole N" | Locate |
| 7 | Operating loss | Operating costs above zero and profit below zero | "Close the operating gap" | Finance |
| 8 | Aesthetics | Aesthetics rating below **2.5 / 5** | "Give the course a sense of place" | — |
| — | Nothing flagged | None of the above | "Watch a round before expanding" | — |

The corridor check is a heuristic, not a routing solver. A deliberate dogleg or a hazard placed on purpose can trigger it, so treat its suggestions as prompts for judgment.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Brush sizes | `TerrainToolbar.BRUSH_SIZES` | `1` to `9` | Available stamp widths |
| Round brush edge | `TerrainBrush.offsets()` | Tile centre within S/2 of block middle | Shape of round brushes |
| Undo stack size | `UndoManager.MAX_UNDO_STACK` | `50` | Number of undoable actions kept |
| Corridor coverage threshold | `CourseAdvisor.review()` | `0.65` | Lower allows more rough before advising |
| Corridor sample width | `TerrainBrush.offsets(3)` in `review()` | `3` tiles | Width of the corridor being sampled |
| Value warning | `CourseAdvisor.review()` | `2.8 / 5` | Lower reduces how often value is flagged |
| Aesthetics warning | `CourseAdvisor.review()` | `2.5 / 5` | Lower reduces how often aesthetics is flagged |
| Food service hole cutoff | `CourseAdvisor.review()` | Hole `4` onward | Earlier holes do not need food service |
| Maximum suggestions | `CourseAdvisor.review()` | `4` | Number of suggestions shown at once |

---

## Related

- [Terrain Types](terrain-types.md) covers the terrain tiles these brushes paint.
- [Difficulty Calculator](difficulty-calculator.md) covers the rating that the value and aesthetics checks read alongside.
