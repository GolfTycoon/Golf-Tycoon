# Course Surface

> The course ground is drawn as one continuous, shader-based landscape, with mower passes, collars, recessed sand, moving water and painted tree grounds, instead of per-tile sprites.

**Source:** `scripts/terrain/course_surface.gd` (data and palette textures, `PALETTE_KEYS`, `palette_key()`, `map_color()`, upload coalescing), `shaders/course_surface.gdshader` (`surface()`, `edge_between()`, `ground_fade()`, `inset_tile()`, `tree_ground()`, `link_distance()`), `shaders/foliage_breeze.gdshader`, `scripts/terrain/terrain_grid.gd` (`grid_width`, `refresh_all_overlays()`)
**Tests:** `tests/unit/course_design/test_course_surface.gd`, `tests/unit/course_design/test_terrain_types.gd`

---

## Plain English

The course is no longer a grid of coloured squares. The ground is one connected landscape:

- **Turf** has diagonal mower passes. Putting greens have fine turf and a collar around them.
- **Bunkers** are shallow recessed sand with a subtle grass lip. Pot Bunkers are a separate tile with a stacked-turf face.
- **Water** moves gently.
- **Trees** each have a ground painted under them, such as leaf litter, pine needles or sand.

The simulation still uses the same tile grid (128 × 128 by default). This is a rendering change only. Camera controls, saved courses, hazards and shot logic all keep their existing coordinates. Soft edge blends are drawn for looks and do not change a ball's lie.

Desktop and web use the same shader. The terrain data is stored in a small texture, one pixel per tile. Theme colours live in a separate palette texture, with one texel per terrain type. A new terrain type therefore needs only a new palette key.

Some terrain types share looks. Rocks, Small Boulders and Large Boulders use one stone base colour, with three stone sizes. The twelve woodland types all paint ground from the same trees palette entry.

The same palette colours the two small maps of the course: the minimap and the
Course Map both ask `CourseSurface.map_color(type)` for each tile, so the ground
reads identically at every size, and a theme change (or a colourblind mode)
repaints all three together. See [Course Map](course-map.md).

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

`CourseSurface` listens for local tile changes and coalesces GPU uploads to one per frame. Quiet terrain generation rebuilds explicitly through `TerrainGrid.refresh_all_overlays()`. Deserializing terrain or elevation data, and successful load events, rebuild the data. Theme changes replace only the palette.

### 2. Edges between materials

Three rules keep a boundary clean and keep every tile the size of the tile it was painted on.

**The boundary sits on the shared edge, never across the tile.** Each pixel's share of its own tile and of the neighbour beyond an open edge is the product of its per-edge shares, so a pixel's colour is the area of it that falls in each tile. A straight seam is an even blend of the two materials; a stepped run of tiles keeps the exact outline it was painted with; and an isolated tile keeps its full square footprint — including its four corners. The seam is anti-aliased across the edge inside a narrow band that follows the pixel footprint (`fwidth`), one pixel wide at any camera zoom, so it feathers at every zoom instead of tearing or smearing.

**Edge treatments fade inward only.** A green's collar, a bunker's lip, a shoreline and the dark cut along a fairway's edge are painted *inside* the tile that owns them: full strength on the boundary, fading inward across `TREAT` (0.10 tiles). Nothing of one tile's treatment reaches into its neighbour, so two treatments can never pile up on the same seam, which used to double them into a bright, uneven border.

**Inset terrain ends at the edge of its ground, square like the tiles under it.** A patch of stones, shrubs, sand, trees, silt or a stream gives way to the surrounding turf through `ground_fade()`, which measures distance to the nearest open edge of the patch rather than a distance to a tile centre or a corner arc. A square patch of tiles therefore thins out square — its corners stay sharp — while a lone tile still reads as a full square of its own material with a soft rim, not a shrunken blob.

`edge_between(self, other)` decides whether a boundary band is drawn, and `differs(self, other)` whether the ground changes hands at all (the two differ only for inset terrain the neighbour can carry — the sand under a stone field).

- A turf tile (grass, fairway or rough) next to an inset tile draws **no** boundary band. The inset tile shows turf near the edge instead, feathering in across the ground fade.
- Stones and shrubs are never cut by a tile edge. A feature is kept only if it clears every open edge by its own radius, and a standing stone that would not clear is set back and shrunk rather than dropped.
- All three stony ids share one base ground and one boundary class, so a patch that changes stone size draws no material edge.
- Every tree id folds onto a boundary class based on its ground, so litter next to litter draws no edge, and litter next to sand fades across one.
- Water and streams share a boundary class, so there is no shoreline between a stream and a pond.

### 3. Pot bunkers and streams

Pot bunkers and streams use `link_distance()`, which measures the distance to a skeleton line joining the tile centre to each linked neighbour. Pots link to neighbouring pot tiles, and streams link to neighbouring stream or pond tiles. A tile with one horizontal and one vertical link becomes a quarter arc, so stepped lines of tiles read as smooth curves. Runs meet with a smooth minimum.

- A pot's floor is offset toward the viewer, which exposes its far wall.
- A stream is a channel with a muddy margin and crests that drift downstream over time. The Stream tool paints 4-connected strokes (`TerrainBrush.centers_4_connected()`), because channels only join edge-adjacent tiles.

### 4. Turf and water animation

Noise and mower passes use world coordinates. Moving or zooming the camera therefore does not move the pattern.

Water animates from GPU time and needs no per-tile script updates. Standard Bunkers always use the shallow sand treatment; Pot Bunkers draw their own stacked-turf lip. Greens blend into the theme's fringe colour at their edges.

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
| Boundary band | `course_surface.gdshader` `aa_x`, `aa_y` | Half a pixel, floor `0.015` tiles | Sharpness of material edges at every zoom |
| Edge treatment band | `course_surface.gdshader` `TREAT` | `0.10` tiles | How far a collar, lip or shoreline fades inward |
| Ground fade width | `course_surface.gdshader` `ground_width()` | `0.13`–`0.16` tiles | How far an inset patch's own ground feathers into the turf around it |
| Ground fade band | `course_surface.gdshader` `GROUND` | `0.35` tiles | How far the ground around a patch blends toward its neighbours |
| Stream channel width | `inset_tile()` | Half-width about `0.25` tiles | Width of streams |
| Waste margin raggedness | `ground_width()`, `ground_fade()` | Width varies by up to about `40%` | How ragged sand and patch edges look |
| Stone size and density | `rocks_radius()`, `rocks_present_threshold()` | See the table in the source | How many stones and how big |
| Boulder height | `rocks_tallness()` | `1.7` for Large Boulders | How far boulders stand up |
| Water animation | `course_surface.gdshader` | GPU time | Speed of water movement |
| Foliage breeze | `foliage_breeze.gdshader` | Small amplitude | Strength of canopy motion |
| Palette | `course_surface.gd` `PALETTE_KEYS` | One key per terrain type | Colour of each terrain type |

---

## Related

- [Terrain Types](terrain-types.md) lists every tile type and its look.
- [Course Architecture](course-character.md) covers landforms and facility drawing.
- [Builder Tools](builder-and-review.md) covers the paint tools.
