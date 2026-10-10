# Landforms, Architecture & Golfer Expressions

> How the course's landforms are sculpted and shaded, how facilities are drawn with their own details, and how golfers react to their scores.

**Source:** `scripts/terrain/sculpted_terrain.gd` (`delta_for()`, `stamp()`, `stamp_at_tile()`), `scripts/systems/quick_start_course.gd` (landform stamps), `scripts/tools/elevation_tool.gd` (selector tools), `scripts/entities/course_architecture.gd` (redraw timer), `scripts/effects/golfer_expression.gd` (reactions and address waggle), `shaders/course_surface.gdshader`
**Tests:** `tests/unit/test_course_character.gd`

---

## Plain English

**Landforms.** Elevation is edited with three selector tools on the Elevation tab: **Vertex**, **Flat Square** and **Gradual Square**. Right-click raises the selected terrain, and left-click lowers it. The soft hill-and-hollow falloff survives as `SculptedTerrain`, which course generation uses. Quick Start's holes 2, 5 and 8 get raised tees, crowned greens and a shallow valley between them. Other courses are not reshaped when they load. These elevation changes are real and the simulation uses them.

**Architecture.** Facilities share cream siding, green shutters and tiled gable roofs, with fixed window and door proportions. Clubhouses grow by adding facade bays at each upgrade. Each facility has its own details: a clock dormer, striped shop awnings, cart bays, chimney smoke, pro-shop merchandise, restaurant window boxes, snack-hut menus, restroom trellises and range-pavilion ball baskets. Windows glow warm at dusk. Upgraded clubhouses fly a small animated pennant. All of these details are cosmetic, and buildings and ghosts share the same geometry.

**Golfer expressions.** Golfers have a small address waggle while preparing a shot. After a hole, they react to their score: a happy hop with glints under par, a slump over par, and a small nod at par. The reaction is a short cosmetic animation that never changes the shot timing.

---

## Algorithm

### 1. Sculpting stamps

For a stamp of radius `r`, each vertex at offset `(dx, dy)` changes by:

```
distance = |offset| / r
falloff  = max(0, 1 − distance²)²
delta    = round(amount × falloff)
```

The resulting level is clamped to `MIN_ELEVATION` (0) through `MAX_ELEVATION` (10). Flat ground sits in the middle at level 5. Each changed tile records its old and new elevation so the stroke can be undone.

Quick Start uses three stamps:

| Feature | Radius | Amount | Position |
| --- | --- | --- | --- |
| Green crown | 5 | +2 | Hole green |
| Raised tee | 4 | +3 | Hole tee |
| Valley between tee and green | 4 | −1 | Midpoint of tee and green |

The three square selectors do not use this falloff. They move whole squares or single vertices. Sculpt radius for a brush is `max(3, brush_size / 2)`.

### 2. Shading from elevation

The surface texture's blue channel stores elevation as `(elevation − MIN) / (MAX − MIN)`. A second, linearly filtered sampler reads the same texture at ±1.5 tiles to estimate a broad normal. The sun direction drives restrained shading on sloped ground. Flat ground stays neutral. Four extra samples are taken to avoid visible repeating patterns. Elevation edits feed the same texture upload as other terrain edits. Physics elevations do not change through rendering.

### 3. Architecture drawing

`CourseArchitecture` builds buildings and placement ghosts from the same geometry. Footprints in the world never change. Facades are horizontal, and depth recedes by `(−0.55 × depth, −0.5 × depth)`. Roof planes share one ridge, and the foundation, porch posts, stairs and apron all use the same base coordinate. Chimney smoke and window light come from the actual architecture, not from offsets tied to sprite size.

The cosmetic clock redraws at **10 Hz** (`redraw_elapsed >= 0.1`) and respects pause. Rebuilding removes the old visual and its click area before adding the replacements.

### 4. Golfer expressions

`GolferExpression` is a parent of the golfer's Visual node. It moves only the body, so the golfer's world position, ball, path and labels stay where they are.

- **Address waggle** (while the golfer is preparing a shot): a small rotation and sideways sway.
- **Reaction** (after `finish_hole`): lasts **2.2** real seconds.
  - Under par: a hop of up to 4 px, with a slight rotation.
  - Over par: a slump, with a small rotation and a drop of 1.5 px.
  - At par: a small nod.
- **Interruption**: starting preparation or a swing cancels the reaction immediately. The existing shot-preparation duration and swing timing stay authoritative.
- **Pause** freezes the cosmetic timer.

---

## Tuning Levers

| Setting | Location | Current value | Effect |
| --- | --- | --- | --- |
| Green crown strength | `quick_start_course.gd` | `+2` | Height of the green crown |
| Tee raise strength | `quick_start_course.gd` | `+3` | Height of the raised tee |
| Valley depth | `quick_start_course.gd` | `−1` | Depth of the valley between tee and green |
| Green and tee radius | `quick_start_course.gd` | `5` and `4` tiles | Size of the landforms |
| Elevation range | `terrain_grid.gd` `MIN_ELEVATION`, `MAX_ELEVATION` | `0` to `10` | Range of elevation levels |
| Sculpt radius | `sculpted_terrain.gd` `sculpt_radius()` | `max(3, brush_size / 2)` | Width of the tapering slope from a brush |
| Architecture redraw | `course_architecture.gd` | `0.1` s (10 Hz) | How often the ambient drawing updates |
| Reaction duration | `golfer_expression.gd` | `2.2` s | How long the score reaction lasts |
| Happy hop height | `golfer_expression.gd` | `4` px | Height of the celebratory hop |

---

## Related

- [Elevation Tools](elevation-tools.md) covers the selector tools in detail.
- [Isometric Buildings](isometric-buildings.md) covers how buildings are drawn.
- [Clubhouse](clubhouse.md) covers the clubhouse's placement and visits.
- [Course Surface](course-surface.md) covers the shader that renders the ground.
