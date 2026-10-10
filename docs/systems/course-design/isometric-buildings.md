# Isometric Buildings

> Every facility is drawn as an isometric building that stands on the tiles it was bought for. The same routine draws the placed building, its placement ghost and its picture on the Buildings tab.

**Source:** `scripts/entities/course_architecture.gd` (`grid_origin_offset()`, `project_point()`, `face_shade()`, `draw_building()`, `Sketch`), `scripts/entities/building.gd` (`set_position_in_grid()`), `scripts/ui/placement_preview.gd` (ghosts), `scripts/ui/components/building_tile_art.gd` (Buildings tab pictures), `scripts/entities/path_furniture.gd` (bench delegation)
**Tests:** `tests/unit/test_isometric_architecture.gd`, `tests/integration/buildings_isometric.gd`

---

## Plain English

Each facility is a small isometric building. Its walls run along the same 2:1 diamonds as the terrain, its roof slopes along the course's own isometric axes, and its door faces the edge golfers actually walk to. Nothing is a flat picture laid over the grid.

Three things use the same drawing code, so they always match:

- the **placed building**;
- the **ghost** that follows the cursor before you click;
- the **picture** on the Buildings tab.

Comparing the picture with the footprint under the cursor shows the same geometry, only at a different scale.

Buildings used to be pixel-art sprites. Those assets have been removed. Window glow, lit windows and chimney smoke are now part of the drawing. A bench is the only exception: it is a ground fixture, so it uses [Path Furniture](path-furniture.md).

---

## Algorithm

### 1. Coordinates

Everything about a building is written in **grid space**:

- `x`: tiles across the footprint's own square.
- `y`: tiles down it.
- `z`: pixels above the ground.

`project_point()` maps a grid point to the screen using the terrain's own 2:1 axes. A wall corner at `(0.4, 0.4)` therefore lands on the tile corner the terrain draws there. Only this one projection exists. Facility routines never convert between spaces themselves.

### 2. Rotation

The view can be rotated a quarter turn at a time, and buildings turn with it. `facing` is a rotation inside the same transform, not a separate set of drawings. After a rotation, `Building.set_position_in_grid()` passes the new `facing` to the architecture node. The walls you see are therefore always the walls the building has.

| Function | What it does |
| --- | --- |
| `grid_origin_offset(size, view_facing)` | Finds where grid `(0, 0)` falls in the building's local space. This matches the anchor used by `set_position_in_grid()`. |
| `project_point(origin, p, view_facing)` | Converts a grid point to local draw space. |
| `screen_delta(offset)` | Converts a grid offset to a screen offset, for extents and shadows. |
| `face_shade(normal)` | How brightly a plane facing a grid direction is lit. |
| `Sketch` | The shared drawing surface, with `walls`, `hip_roof`, `window_at`, `door_at`, `awning`, `terrace`, `contact_shadow` and others. |

`Sketch` also records the grid-space box of everything it has drawn. `draw_building()` returns that box. The unit tests use it to check that every facility stays inside its footprint at every rotation. Chimney smoke is the one exception, since it is drawn straight to the canvas and does not count as part of the building.

### 3. Footprint anchor

`Building.set_position_in_grid()` places the node at the footprint centre minus `(size.x × 0.5, size.y)`. The art must be projected around that same anchor, not around the footprint's centre. Getting this wrong moves every building half a tile across its own square. The mistake is hard to see on one tile and obvious on four, which is why `grid_origin_offset()` exists.

### 4. Shadow

The contact shadow is the footprint diamond, nudged in the shadow direction. It is drawn at `ShadowSystem.shadow_intensity` and tinted green so it reads as shade on grass. It is not a detached oval under the terrace.

### 5. Scale

A storey is about 20 to 30 pixels, and a door is 14 to 17 pixels. Windows sit on the two walls that face the viewer. A facility fills the tiles it stands on. A one-tile hut fills its diamond, and a six-tile driving range runs along its line of tiles.

### 6. Facilities

| Building | Distinguishing features |
| --- | --- |
| Clubhouse | Paved terrace, stone plinth, hipped roof, chimney, entrance canopy. Tier 2 adds a front range. Tier 3 adds a storey and a clock tower. |
| Pro Shop | Display window with merchandise, striped awning, bag stand |
| Restaurant | Lit windows with flower boxes, awning, chimney with smoke, terrace table |
| Snack Bar | Serving hatch, menu board, cup badge |
| Driving Range | A row of covered bays with padded dividers and ball baskets |
| Cart Shed | Open bays with parked carts, roof vent, wheel stops |
| Restroom | Two labelled doors, trellis and roses |
| Conservatory | Glazed, mullioned walls and a glass lantern roof |
| Tea Pavilion | Corner posts holding a wide shade roof, tea tables |
| Garden Spa | Bathing pool ringed by loungers |
| Golf Academy | Teaching bays with netting and a sign board |
| Locker Room | Twin doors, club rack, benches |
| Coffee House, Halfway House, Ice Cream Kiosk | A counter, a striped awning, and a landmark: a chimney, a scoop sign or a steam cup |

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Footprint size | `data/buildings.json` `size` | Per building (clubhouse `[4, 4]`) | How many tiles a building covers |
| Projection axes | `course_architecture.gd` `project_point()` | Terrain's 2:1 axes | Shape of the building on screen |
| Depth recession | `course_architecture.gd` | `(−0.55, −0.5) × depth` | How far back the building recedes |
| Shadow tint | `ShadowSystem.shadow_intensity` | Global | Strength of the contact shadow |

---

## Related

- [Clubhouse](clubhouse.md) covers the one building that is always present.
- [Improvement Catalog](garden-catalog.md) lists all facilities and improvements.
- [Course Architecture](course-character.md) covers landforms and the redraw timer.
- [Path Furniture](path-furniture.md) covers the bench exception.
