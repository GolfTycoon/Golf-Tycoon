# Hole Creation

> A hole is built by painting a tee box and a green cup on the map, then pressing **Open Hole**. The rules keep at most one unused tee and one unused cup waiting at a time.

**Source:** `scripts/tools/hole_layout.gd` (`open_hole_request()`, `potential_hole()`, `max_brush_size()`, `used_tee_tiles()`, `unused_cups()`), `scripts/tools/hole_creation_tool.gd` (`open_hole()`, `create_generated_hole()`), `scripts/course/hole_path_planner.gd` (background route planning and cache), `scripts/terrain/terrain_grid.gd` (tee and cup indexes, `reset_for_new_course()`, `create_analysis_copy()`), `scripts/terrain/cup_overlay.gd`, `scripts/ui/placement_preview.gd` (potential hole preview), `scripts/main/main.gd` (`_paint_terrain_stamp()`, `_on_new_game_started()`)
**Tests:** `tests/unit/test_hole_layout.gd`, `tests/unit/test_hole_creation_tool.gd`, `tests/unit/test_potential_hole.gd`, `tests/unit/test_hole_path_planner.gd`, `tests/unit/test_cup_tiles.gd`, `tests/integration/hole_creation_flow.gd`, `tests/integration/hole_path_preview.gd`, `tests/integration/new_game_resets_course.gd`

---

## Plain English

A hole is built from its two ends with the ordinary terrain brushes, then opened.

1. **Tee Box** paints one tile. While a tee box is waiting, no second one can be placed. At most one tee waits on the course at a time.
2. **Green** paints a **Green With Hole** when no cup is waiting. This is a single tile with a cup cut into it, shown with a **gold pin** so it stands apart from the red pins of open holes. Once a cup is waiting, the Green tool switches to a normal green brush, so you can widen the putting surface around the cup.
3. **Open Hole** (`H`, or the tile between the tee and green tools on the Course Terrain tab) pairs the waiting tee with the waiting cup and creates the hole. It is enabled only when there is exactly one tee and one cup ready.

Opening a hole sets its yardage, par, and difficulty rating. The cup stays on its tile for the life of the hole. It moves only when you move the whole green. Opening a hole also clears the waiting cup, so the next green you paint starts the next hole.

### The potential hole preview

While a tee is waiting and the Green tool is about to cut a cup, the cursor shows the **potential hole** before you paint anything. The preview has three parts:

- A dashed path from the waiting tee to the hovered tile.
- Marks for the expected landing zones, and the cup's gold pin.
- A plaque, such as `Hole 3 · Par 4 · 398 yds`.

The route comes from the same shot planner that draws an open hole's path, so the preview matches the hole you get. If the pair cannot open, the path and pin turn red, and the plaque says why:

- the tee and cup are too close together;
- the tile is already green;
- you don't own the land;
- a building or decoration is in the way;
- more than one tee box is waiting.

The preview disappears when the cup is cut, when you switch tool, or when no tee is waiting.

### Other rules

- **Unused** means not already claimed by a hole. A hole's tee box belongs to it, so it never counts as unused.
- **Deleting a hole** returns its tee box to the unused pool, so you can pair it with a new cup instead of bulldozing it.
- **Painting over** a Green With Hole with any other terrain removes its cup.
- **Undo and redo** restore cups with their tiles. Waiting cups are saved in the save file.
- **Brush limits** are enforced. While a tee tool or a cup-cutting green is selected, the toolbar shows `1x1` and locks its size controls. A drag that cuts the first cup finishes as an ordinary green brush.

---

## Algorithm

### 1. Rules

`HoleLayout` is the one source of truth. The toolbar, the placement preview and the paint path all use the same functions.

```
used_tee_tiles(course)  = { hole.tee_position }                              for every hole
used_cup_tiles(course)  = { hole.hole_position }                               for every hole
unused_tee_boxes(grid)  = grid tee-box tiles − used_tee_tiles
unused_cups(grid)       = grid cup tiles − used_cup_tiles

green_places_cup   = unused_cups is empty
can_place_tee_box  = unused_tee_boxes is empty

max_brush_size(TEE_BOX) = 1
max_brush_size(GREEN)   = 1 if green_places_cup, else UNLIMITED_BRUSH (0)
max_brush_size(other)   = UNLIMITED_BRUSH
```

`TerrainGrid` keeps two indexes in step with its tile data, so these checks are dictionary lookups, not grid scans. `_tee_box_tiles` is updated by `set_tile()` and rebuilt on load. `_cup_tiles` is updated by `add_cup_tile()` and `remove_cup_tile()`, and it drops any cup whose tile stops being a green.

### 2. Opening a hole

`open_hole_request()` returns `{ready, reason, tee, cup}`:

| Condition | Result |
| --- | --- |
| No waiting tee and no waiting cup | Not ready: "Paint a tee box (T) and a green (3) to lay out a hole." |
| No waiting tee | Not ready: "Paint a tee box to go with the waiting green." |
| No waiting cup | Not ready: "Paint a green to cut a cup for the waiting tee box." |
| More than one waiting tee or cup | Not ready: "Holes open one at a time…" |
| Tee and cup closer than `MIN_HOLE_TILES` | Not ready: "…a hole needs at least 110 yards." |
| Exactly one of each, far enough apart | Ready, with the pair |

`HoleCreationTool.open_hole(tee, cup)` checks the same preconditions and then builds the `HoleData`:

- yardage from `calculate_distance_yards()`;
- par from `GolfRules.calculate_par()`.

`hole_position` is the Green With Hole tile itself, so golfers always putt to the cup you cut.

Quick Start and the four prebuilt packages use `create_generated_hole(tee, green)` instead. It skips the preconditions. Those layouts only paint land the player owns, so a championship hole that runs off the property still exists. Its tee surface can be finished later.

### 3. Potential hole

`HoleLayout.potential_hole()` decides whether the preview is shown and what it says. `PlacementPreview` calls it every frame while terrain is being painted, and only then. It is never called in elevation, bulldozer, entity-placement or hole-move modes.

```
show only if all of:
    tool == GREEN
    green_places_cup
    an unused tee box exists
    the hovered tile is valid

tee            = nearest unused tee box to the cup (ties go to the first in sorted order)
distance_yards = calculate_distance_yards(tee, cup)
par            = GolfRules.calculate_par(distance_yards)
hole_number    = course.holes.size() + 1
can_cut_cup    = cup_site_blocker() is empty
ready          = can_cut_cup and exactly one tee waiting and distance ≥ MIN_HOLE_TILES
```

`cup_site_blocker()` matches what `main._paint_terrain_stamp()` does. A stamp skips land you don't own and tiles under buildings or decorations. Painting green on a tile that is already green changes nothing, so no cup is cut there either. On a tile where the cup can be cut, `ready` predicts what `open_hole_request()` returns once the cup is cut. The unit tests check that the two agree.

### 4. Route planning

`HolePathPlanner` returns the route for a tee and cup pair. It calls `ShotPathCalculator.calculate_route()`, the same function that `HoleVisualizer` uses for an open hole, so the preview and the opened hole show the same waypoints. Two adjustments make them match:

- **`hole_index = −1`.** The pair is not in `course.holes` yet. Without this flag, ShotAI's green-centre bias would read `holes[0]` and bend the approach toward another hole's green.
- **Preview terrain.** The route is planned on a copy of the terrain painted the way it will look once the hole opens: the cup tile is green.

ShotAI takes about 0.2 s for a par 4 and 0.4 s for a par 5. That is too slow for the main thread on every tile the cursor crosses, so the planner works as follows:

| Case | What happens |
| --- | --- |
| Par 3 | Returns `[tee, cup]` immediately. ShotAI is not used. |
| Par 4 or 5, cached | Returns the cached route immediately. |
| Par 4 or 5, not cached | Returns `[]`, so the preview draws a faded straight line. A `WorkerThreadPool` task plans the route on `TerrainGrid.create_analysis_copy()`, a detached copy of tiles and elevation that is not in the scene tree. One task runs at a time. Only the newest request is kept, so the route catches up once the cursor settles. |
| No thread support (Web export) | Plans on the main thread after the cursor has rested on the tile for `inline_dwell_msec` (500 ms). |

Routes are cached by tee, cup, par and extra tees. The cache is cleared whenever `TerrainGrid.terrain_revision` changes. That counter increases on every write to tiles or elevation, including loads and generation. A route planned while the terrain changed is thrown away.

### 5. New game

Tee and cup rules count tiles on the current course, so a new game starts from an empty grid. `_on_new_game_started()` clears entities and hole flags first. Removing an entity restores the terrain beneath it. Then `TerrainGrid.reset_for_new_course()` sets every tile back to grass and clears the player-placed marks, sculpted elevation, waiting cups and walking trails. Finally, the undo stack is cleared.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Minimum tee-to-cup distance | `hole_layout.gd` `MIN_HOLE_TILES` | `5` tiles (110 yd) | Shortest allowed hole |
| Yards per tile | `terrain_grid.gd` `calculate_distance_yards()` | `22` | Converts tiles to yards |
| Tee box brush cap | `hole_layout.gd` `max_brush_size()` | `1` × `1` | One tile per tee |
| Green cup brush cap | `hole_layout.gd` `max_brush_size()` | `1` × `1` | One tile per cup |
| Green brush (after cup is waiting) | `terrain_toolbar.gd` `BRUSH_SIZES` | Up to `9` × `9` | Widens the putting surface |
| Tee box cost | `terrain_types.gd` | `$12` per tile | Placement cost |
| Green cost | `terrain_types.gd` | `$20` per tile | Placement cost |
| Waiting cup pin colour | `cup_overlay.gd` `WAITING_PIN_COLOR` | Gold `(0.98, 0.83, 0.25)` | Marks a cup not yet in a hole |
| Potential hole plaque size | `placement_preview.gd` `HOLE_PATH_FONT_SIZE` | `13` px | Plaque text size on screen |
| Cached routes | `hole_path_planner.gd` `MAX_CACHED_ROUTES` | `256` | Routes kept before the cache is trimmed |
| No-thread delay | `hole_path_planner.gd` `inline_dwell_msec` | `500` ms | Dwell time before a Web-export route is planned |

---

## Related

- [Tee Aim Arrow](tee-aim-arrow.md) covers the aiming arrow drawn on each tee.
- [Stroke Index](stroke-index.md) and [Difficulty Calculator](difficulty-calculator.md) are updated when a hole opens.
- [Forced Carry](forced-carry.md) covers the carry shown on the open hole.
- [Clubhouse](clubhouse.md) covers the required building that is never sold.
- [Generated Walking Paths](generated-walking-paths.md) covers the paths laid once a generated course's holes exist.
