# Clubhouse

> Every course has exactly one clubhouse. The player cannot buy, bulldoze or duplicate it, but can move it. It is also where golfers start and finish their visit.

**Source:** `scripts/systems/course_clubhouse.gd` (`ensure()`, `front_tile()`, `move_error()`, `move_to()`), `scripts/entities/building.gd` (`destroy()`), `scripts/course/entity_layer.gd` (`move_building()`, `remove_building()`), `scripts/entities/golfer.gd` (`State.LEAVING`, `_begin_departure()`, `_arrive_at_clubhouse()`), `scripts/managers/golfer_manager.gd` (`_on_golfer_left_course()`), `scripts/main/main.gd` (move and bulldozer handlers), `data/buildings.json` (`clubhouse` entry)
**Tests:** `tests/unit/test_course_clubhouse.gd`, `tests/integration/`

---

## Plain English

The clubhouse is a required building. It is always present, it is not like other buildings, and it has four special rules.

1. **It is guaranteed.** However a course starts (Quick Start, a generated layout, a prebuilt package or an empty plot), the game makes sure a clubhouse stands somewhere legal before play begins. A save made before this rule, or one whose layout cannot fit the clubhouse where it wanted it, gets one on load.
2. **It is never demolished.** The player never buys it and cannot bulldoze it. If you click it with the Bulldozer, the game tells you to move it instead, and no demolition fee is taken.
3. **It can be moved.** The **Move Clubhouse** button in its panel picks it up. A ghost follows the cursor, and the next click sets it down wherever the normal building rules allow. Its own footprint is ignored, so nudging it a tile or two works. Escape or right-click cancels. Moving is free, and Ctrl+Z restores the old spot.
4. **It is where golfers come from and go back to.** Groups walk out of the clubhouse door to the first tee, and walk back to the door when they finish. The visit at the door pays the clubhouse's per-golfer income and restores needs.

Its appearance is drawn by the shared building renderer. It is a four-tile isometric solid with a paved terrace, a stone plinth and a hipped roof. Each upgrade adds a storey or a wing, but never grows past the tiles it stands on. See [Isometric Buildings](isometric-buildings.md).

---

## Algorithm

### 1. Placement: `CourseClubhouse.ensure()`

`ensure(terrain_grid, entity_layer, preferred)` is the single entry point. It returns the existing clubhouse if there is one, so every caller can call it repeatedly. If there is none, it searches square rings outward (up to `SEARCH_RADIUS` = 40 tiles) from these anchors, in order:

1. `preferred`: the spot the course layout leaves for it. Quick Start uses its arrival garden at `(54, 61)`. Generated layouts use their amenity pocket at `anchor + (1, 6)`.
2. `arrival_corner()`: the corner of owned land that every shipped layout keeps clear. Used for empty lots and prebuilt packages. Quick Start's garden is at owned-land centre plus `ARRIVAL_CORNER_OFFSET` = `(-9, -2)`.
3. The centre of the owned land, then the centre of the course.

Each anchor is searched in two passes. The first pass uses only ground that needs no clearing. The second pass lets the clubhouse clear trees, brush and stony ground in its own plot.

A footprint is legal only if all of these hold:

- Every tile is owned and free of other buildings and decorations.
- Every tile is buildable (`PlacementManager.building_terrain_ok()`): grass, rough in all its grades, fairway or firm fairway. A trail laid on the plot is no obstacle — the clubhouse stands on the ground, and the walk runs on underneath it.
- No tile is a green, tee, fairway, bunker, water, stream or out-of-bounds tile (`FORBIDDEN_TERRAINS`).

Trees, brush and stony ground inside the chosen footprint are cleared and re-laid as grass. This is landscaping, not a player edit, so it does not enter the undo history or the maintenance books. The door tile is also cleared so guests have somewhere to stand.

### 2. The front door: `front_tile()`

`front_tile()` returns the first walkable tile just outside the footprint. It starts at the middle of the south (screen-facing) edge and fans out to the corners, then the flanks, then the back. Woodland counts as walkable ground, so a clubhouse at the edge of a grove gets a doorstep too. Golfers spawn on this tile, walk home to it, and the walking-path overlay paves up to it. Moving the clubhouse moves the doorstep, and the paving follows.

### 3. Moving: `move_error()` and `move_to()`

`move_error()` is the one authority that the move preview, the click handler and any future UI all ask, so they cannot disagree:

| Rule | Message shown |
| --- | --- |
| Whole footprint must be on the course | "The whole clubhouse must fit on the course." |
| Whole footprint must be owned land | "Buy this land first — the whole footprint must be owned." |
| No other building in the footprint | "Move the footprint clear of the other building." |
| No decoration in the footprint | "Remove the decoration in this footprint first." |
| Buildable terrain only | "Move it off the greens, tees, sand and water." |
| Already there | "The clubhouse is already there." |

`move_to()` runs the same checks, so a click cannot place the building somewhere the preview refused. A legal move keeps the same `Building` node. Its upgrade level, architecture and lifetime revenue all come along. `EntityLayer.move_building()` re-keys the building and emits `building_moved`, and the walking-path overlay listens for that and re-paves.

### 4. Never demolished

Three layers stop any code path from losing the clubhouse:

- `Building.destroy()` refuses a `required: true` building unless the caller passes `force: true`. Only `EntityLayer.clear_all()` does, because clearing a layer means emptying it, not demolishing what the rules allow.
- `EntityLayer.remove_building()` refuses a required building. It resolves a click on any footprint tile to the building covering it.
- `main.gd` checks in `_handle_bulldozer_click()` before any fee is taken, and points the player to the move action instead.

### 5. Golfers arriving and leaving

The golfer state machine gained one state, `LEAVING`, appended last so saved state numbers do not shift. `FINISHED` still means "gone".

| Stage | What happens |
| --- | --- |
| Spawn | `GolferManager.spawn_golfer()` seats the guest on the clubhouse door tile, places their ball on the first open tee and walks them there (`begin_arrival_from_clubhouse()`). The turn system only picks `IDLE` golfers, so an arriving guest cannot be given a shot until they arrive. |
| Round over | `finish_round()` records score, reputation and feedback as usual, then calls `_begin_departure()`. The golfer walks to the door in `LEAVING`. A 30-second timeout means a blocked route can never strand them. |
| At the door | `_arrive_at_clubhouse()` applies the visit: per-golfer income for upgraded clubhouses, need restoration and a satisfaction bonus. The golfer pauses for `CLUBHOUSE_VISIT_SECONDS` = 1.6 s. |
| Gone | `_leave_course()` sets the golfer to `FINISHED` and emits `EventBus.golfer_left_course` once. |
| Removal | `GolferManager._on_golfer_left_course()` waits until every member of the group is inside, then removes the group after a 1-second send-off pause. This is the only removal path for a finished group. |

`LEAVING` counts as off the course everywhere it matters: capacity, tee and landing-zone clearance, hole-clear checks, staff service and amenity visits. A group walking home never blocks play or keeps a slot. Tournament groups use the same path.

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Footprint and cost | `data/buildings.json` (`clubhouse`) | 4×4, $10,000, `required: true` | The one building that is not optional |
| Guarantee cost | `course_clubhouse.gd` `ensure()` | Free | The course always has one, and it is never charged |
| Search radius | `course_clubhouse.gd` `SEARCH_RADIUS` | 40 tiles | How far from an anchor a home is searched for |
| Arrival corner offset | `course_clubhouse.gd` `ARRIVAL_CORNER_OFFSET` | `(-9, -2)` from owned-land centre | Where empty lots and prebuilt packages put the clubhouse |
| Forbidden terrain | `course_clubhouse.gd` `FORBIDDEN_TERRAINS` | Greens, tees, fairways, sand, water, OB | Ground the guarantee will not build over |
| Move cost | `main.gd` `_handle_building_move_click()` | Free | Moving is free; undo still restores the old spot |
| Visit length | `golfer.gd` `CLUBHOUSE_VISIT_SECONDS` | `1.6` s | How long a golfer stands at the door |
| Walk-home timeout | `golfer.gd` `DEPARTURE_TIMEOUT_SECONDS` | `30` s | After this the visit happens wherever the golfer is |
| Send-off pause | `golfer_manager.gd` `_on_golfer_left_course()` | `1.0` s | Pause after the last golfer is inside, before removal |

---

## Related

- [Walking Paths](walking-paths.md) covers the trails the clubhouse paves.
- [Generated Walking Paths](generated-walking-paths.md) covers the network planned out of the clubhouse door.
- [Isometric Buildings](isometric-buildings.md) covers how buildings are drawn.
- [Course Architecture](course-character.md) covers facade and landform rendering.
- [Golfer Needs](../golfers/golfer-needs.md) covers how the visit restores needs.
- [Golfer Spawning](../golfers/golfer-spawning.md) covers how groups enter the course.
