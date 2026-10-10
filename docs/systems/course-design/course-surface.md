# Course Surface

> The course ground is drawn as one continuous, shader-based landscape, with mower passes, collars, recessed sand, moving water and painted tree grounds, instead of per-tile sprites.

**Source:** `scripts/terrain/course_surface.gd` (data and palette textures, `PALETTE_KEYS`, upload coalescing), `shaders/course_surface.gdshader` (`surface()`, `edge_between()`, `inset_tile()`, `tree_ground()`, `link_distance()`), `shaders/foliage_breeze.gdshader`, `scripts/terrain/terrain_grid.gd` (`grid_width`, `refresh_all_overlays()`)
**Tests:** `tests/unit/test_course_surface.gd`, `tests/unit/test_new_terrain_types.gd`

---

## Plain English

The course is no longer a grid of coloured squares. The ground is one connected landscape:

- **Turf** has diagonal mower passes. Putting greens have fine turf and a collar around them.
- **Bunkers** are recessed sand, and deep bunkers have a visible lip.
- **Water** moves gently.
- **Trees** each have a ground painted under them, such as leaf litter, pine needles or sand.

The simulation still uses the same tile grid (128 × 128 by default). This is a rendering change only. Camera controls, saved courses, hazards and shot logic all keep their existing coordinates. Soft edge blends are drawn for looks and do not change a ball's lie.

Desktop and web use the same shader. The terrain data is stored in a small texture, one pixel per tile. Theme colours live in a separate palette texture, with one texel per terrain type. A new terrain type therefore needs only a new palette key.

Some terrain types share looks. Rocks, Small Boulders and Large Boulders use one stone base colour, with three stone sizes. The twelve woodland types all paint ground from the same trees palette entry.

### Paintable features

| Tile | Look |
| --- | --- |
| Firm Fairway | Fairway mower passes, paler, with sun-dried straw patches. It reads as faster, drier turf inside a normal fairway. |
| Deep Rough | Long standing blades, darker clumps and pale seed-head dots. |
| Rocks | Gravel field. |
| Small Boulders | Pebbles, with the odd larger stone. |
| Large Boulders | Big stones that stand up out of the ground, with a contact shadow. |
| Brush | Sparse shrubs with occasional blossoms. |
| Waste Bunker | Coarse sand with pebbles and wiregrass tufts. It breaks up raggedly into the surrounding turf. |
| Pot Bunker | A turf lip, a stacked-turf wall and a sand floor. |
| Stream | A narrow channel with a muddy, pebbled margin, and soft crests drifting downstream. |

Rocks, boulders, brush and waste bunkers are **inset terrain**. They are drawn over whatever turf surrounds them, so a patch has a natural outline rather than a square one.

### Trees

Every tree is a painted tile, including the generic Trees tile and its species. Each species paints one of six grounds:

| Ground | Species | Look |
| --- | --- | --- |
| Leaf litter | Trees, Oak, Maple, Birch, Shrub | Shaded earth with fallen leaves and twigs |
| Pine needles | Pine | Rust-brown needle bed, with cones |
| Bare sand | Cactus, Palm, Dead Tree | Waste-bunker sand with grit and pebbles |
| Waterlogged silt | Cattails | Wet mud with reed litter |
| Acid peat | Heather | Dark peat over stone, with purple heather |
| Dry straw | Fescue | Uncut firm-fairway sward gone to straw |

A lone tree is a patch around its trunk, and a grove is one unbroken floor.

---

## Algorithm

### 1. Data flow

`CourseSurface` listens for local tile changes and coalesces GPU uploads to one per frame. Quiet terrain generation rebuilds explicitly through `TerrainGrid.refresh_all_overlays()`. Deserializing terrain or depth data, and successful load events, rebuild the data. Theme changes replace only the palette.

### 2. Edges between materials

Material boundaries sit on the shared tile edges, inside a narrow anti-aliased band (`AA` = 0.04 tiles half-width). They do not blend across the tile centre. This keeps each tile's square footprint, so an isolated tile does not bulge into a rounded blob.

`edge_between(self, other)` decides whether a boundary is drawn:

- A turf tile (grass, fairway or rough) next to an inset tile draws **no** boundary band. The inset tile shows turf near the edge instead, which fades in across an edge-treatment band (`FRINGE` = 0.30 tiles half-width).
- Stones and shrubs are never cut by a tile edge. A feature is kept only if it clears every open edge by its own radius, and a standing stone that would not clear is set back and shrunk rather than dropped.
- All three stony ids share one base ground and one boundary class, so a patch that changes stone size draws no material edge.
- Every tree id folds onto a boundary class based on its ground, so litter next to litter draws no edge, and litter next to sand fades across one.
- Water and streams share a boundary class, so there is no shoreline between a stream and a pond.

### 3. Pot bunkers and streams

Pot bunkers and streams use `link_distance()`, which measures the distance to a skeleton line joining the tile centre to each linked neighbour. Pots link to neighbouring pot tiles, and streams link to neighbouring stream or pond tiles. A tile with one horizontal and one vertical link becomes a quarter arc, so stepped lines of tiles read as smooth curves. Runs meet with a smooth minimum.

- A pot's floor is offset toward the viewer, which exposes its far wall.
- A stream is a channel with a muddy margin and crests that drift downstream over time. The Stream tool paints 4-connected strokes (`TerrainBrush.centers_4_connected()`), because channels only join edge-adjacent tiles.

### 4. Turf and water animation

Noise and mower passes use world coordinates. Moving or zooming the camera therefore does not move the pattern. Water animates from GPU time and needs no per-tile script updates. Bunker lip depth increases with the bunker's depth setting (see [Bunker Depth](bunker-depth.md)). Greens blend into the theme's fringe colour at their edges.

### 5. Foliage

Foliage uses one shared vertex shader. Each tree sways with a phase set by its world position, and movement falls off toward the base of the trunk. Cacti and dead trees do not move.

### 6. Layering and lighting

`EntityLayer` sits at Z = 2. Its shadows stay above the ground and below the sprites. Elevation lighting is separate, and contour lines appear only while the elevation tool is active. Continuous light and smooth ambient occlusion avoid rectangular bands from the low-resolution heightmap.

### 7. Quick Start

Quick Start paints the course it wants directly. A wood is a tile, so clearing a spot for a hole is one tile change, with no entity removal. This avoids leaving holes in fairways and greens.

---

## Tuning Levers

| Setting | Location | Current value | Effect |
| --- | --- | --- | --- |
| Grid size | `terrain_grid.gd` `grid_width` | `128` | Size of the tile grid |
| Boundary band | `course_surface.gdshader` `AA` | `0.04` tiles | Sharpness of material edges |
| Edge treatment band | `course_surface.gdshader` `FRINGE` | `0.30` tiles | How far inset edges blend |
| Stream channel width | `inset_tile()` | Half-width about `0.25` tiles | Width of streams |
| Waste margin raggedness | `inset_tile()` | Edge noise, up to about `0.2` tiles | How ragged sand edges look |
| Stone size and density | `rocks_radius()`, `rocks_present_threshold()` | See the table in the source | How many stones and how big |
| Boulder height | `rocks_tallness()` | `1.7` for Large Boulders | How far boulders stand up |
| Water animation | `course_surface.gdshader` | GPU time | Speed of water movement |
| Foliage breeze | `foliage_breeze.gdshader` | Small amplitude | Strength of canopy motion |
| Palette | `course_surface.gd` `PALETTE_KEYS` | One key per terrain type | Colour of each terrain type |

---

## Related

- [Terrain Types](terrain-types.md) lists every tile type and its look.
- [Bunker Depth](bunker-depth.md) covers the shallow and deep bunker settings.
- [Course Architecture](course-character.md) covers landforms and facility drawing.
- [Builder Tools](builder-and-review.md) covers the paint tools.
