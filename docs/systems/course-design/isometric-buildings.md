# Isometric Buildings

> Every facility is a pixel image standing on the tiles it was bought for: one sprite per upgrade tier and per fifteen-degree view step. The same picture draws the placed building, its placement ghost and its tile on the Buildings tab.

**Source:** `scripts/entities/course_architecture.gd` (`grid_origin_offset()`, `project_point()`, `draw_building()`), `scripts/entities/building_sprites.gd` (manifest, textures, drawing), `assets/sprites/buildings/` (432 PNGs and `sprites.json`), `tools/building_art/` (the generator that produced them), `scripts/entities/building.gd` (`set_position_in_grid()`), `scripts/ui/placement_preview.gd` (ghosts), `scripts/ui/components/building_tile_art.gd` (Buildings tab pictures), `shaders/terrain_footprint_occlusion.gdshader` and `scripts/terrain/terrain_occlusion.gd` (hills in front)
**Tests:** `tests/unit/course_design/test_isometric_architecture.gd`, `tests/unit/ui_and_controls/test_building_tile_art.gd`, `tests/integration/course_design/test_buildings_isometric.gd` (sprite bounds); `tests/unit/course_design/test_building_foundations.gd`, `tests/integration/course_design/test_building_foundations_flow.gd` (ground, moves, undo and save/load); `tests/unit/course_design/test_terrain_occlusion.gd` (hills in front)

---

## Plain English

Each facility is a **true 3D model** baked into pixel art: walls, pitched roofs, awnings, chimneys, towers, fences and props are built from triangular solids, lit from the same sun, and rasterised through the course's own 2:1 isometric projection. The renderer keeps a z-buffer, so a porch really is in front of the wall behind it, a window reveal is recessed, and a clock tower rises through a roof instead of being pasted over it. Its door faces the edge golfers actually walk to. Nothing is a flat elevation laid over the grid.

Three things use the same image, so they always match:

- the **placed building**;
- the **ghost** that follows the cursor before you click;
- the **picture** on the Buildings tab.

Comparing the picture with the footprint under the cursor shows the same building, only at a different scale.

A hill nearer the camera hides the part of a placed building behind it, just as it hides a tree's trunk: the walls it covers disappear behind the hill, and everything standing above the hill or in front of it is drawn as before. The **Terrain-aware occlusion** graphics setting turns this off.

The park bench is not a building at all: it is a ground fixture on the Improvements tab, drawn by [Path Furniture](path-furniture.md).

---

## Algorithm

### 1. One sprite per tier per view step

`assets/sprites/buildings/` holds a PNG for every building, upgrade tier and fifteen-degree view step (`clubhouse_2_00.png`, `casino_1_06.png`, …), plus `sprites.json`. Step 0 is the east view, 6 south, 12 west and 18 north, matching the classic four-way orientations. The manifest records, for each image, the rectangle it covers in the **local draw space of the building node** — the same space `Building.set_position_in_grid()` anchors — in world pixels:

```json
{
  "tile": [64, 32],
  "pixel_scale": 1.0,
  "buildings": {
    "clubhouse": {
      "tiers": {
        "1": {
          "facings": [
            { "file": "clubhouse_1_00.png", "rect": [10.0, 17.31, 236.0, 171.6] },
            { "file": "clubhouse_1_01.png", "rect": [ ... ] },
            ... 24 entries ...
          ],
          "height": 65.69
        }
      },
      "sprite_height": 118.12
    }
  }
}
```

`BuildingSprites.draw()` draws the texture into that rectangle 1:1: one drawn pixel is one world pixel, so a 4-tile-wide clubhouse is about 236 pixels across on screen. The **source PNG does not have to be that size**. The shipped sprites are baked at one source pixel per world pixel, the smallest useful size; the optional **HD Building Art** mod supplies the same views at 2.5 source pixels per world pixel for players who want the finer detail. `pixel_scale` records the shipped ratio, and `BuildingSprites.texture()` resamples each PNG once, when it is first loaded, into the manifest rectangle with a Lanczos filter. That keeps the draw call a 1:1 blit — the GPU never has to minify a big texture with nearest filtering, which would alias and flicker as the camera zooms — and it means replacing the art does not move a building off its tiles. Textures are cached after the first load, so `_draw()` stays cheap.

`BuildingSprites.painted_rect()` maps a texture's opaque pixels into the same local draw space (`rect.size / texture.size` world pixels per image pixel). Use it anywhere the *painted* bounds matter rather than assuming the source resolution; `source_texture()` returns the untouched PNG for tools and previews. Mods keep their registered texture and draw rect unchanged, and the same mapping applies to them.

### 2. Pixel size

| Thing | Size |
| --- | --- |
| Tile | 64 x 32 world pixels |
| Drawn pixel | 1 world pixel (1/64 of a tile across) |
| Source art pixel | 1 world pixel shipped; 0.4 world pixel in the HD art mod (2.5x, resampled at load) |
| Storey | about 46 world pixels |
| Door | 26 world pixels tall, 14 wide |
| Window | 13 world pixels tall, 10 wide |

The fitted textures load without mipmaps, and every node that draws them sets `texture_filter = TEXTURE_FILTER_NEAREST`, so the pixel grid never blurs when the camera zooms. Source PNGs can be replaced with art at any resolution without touching `sprites.json`: the manifest rectangles stay in world pixels and the loader does the fitting.

### 3. Coordinates

The art is authored in **grid space**:

- `x`: tiles across the footprint's own square.
- `y`: tiles down it.
- `z`: world pixels above the ground.

`project_point()` maps a grid point to the screen using the terrain's own 2:1 axes. A wall corner at `(0.4, 0.4)` therefore lands on the tile corner the terrain draws there. Only this one projection exists; the generator draws through it and the game anchors through it.

### 4. Rotation

Each facility has 24 pre-rendered images, one per 15° view step. `Building` reads `TerrainGrid.get_view_facing_angle()` — the view angle snapped to the nearest 15° step — and passes it to the architecture node as a **fractional quarter-turn** (`0.0`, `1/6`, `2/6`, …). The projection helpers use cos/sin for those angles, exactly as `GridProjection` does, so the sprite rect and the terrain diamond stay on the same angle throughout a **Gradual View Rotation** tween. Classic instant rotation lands on whole turns, which still use the exact integer rotation maths. The HUD facing chip and the tree sprites remain four-way: they describe the nearest compass direction, not the building's art angle.

| Function | What it does |
| --- | --- |
| `grid_origin_offset(size, view_facing)` | Finds where grid `(0, 0)` falls in the building's local space. This matches the anchor used by `set_position_in_grid()`. |
| `project_point(origin, p, view_facing)` | Converts a grid point to local draw space. |
| `screen_delta(offset)` | Converts a grid offset to a screen offset, for extents and shadows. |
| `footprint_corners(size, view_facing)` | The four tile corners of a footprint, in local draw space. |
| `BuildingSprites.rect(kind, tier, facing)` | The rectangle a sprite covers in the same space. |
| `TerrainGrid.get_view_facing_angle()` | The current view snapped to the nearest 15° step, in quarter turns. |

### Why twenty-four facings?

Twenty-four facings match the game's own rotation step. **Gradual View Rotation** already turns the terrain in 15° increments (`GRADUAL_TURN_STEP = 1/6`); with four building sprites the architecture snapped only at 90°, so a building visibly lagged the ground it stood on for five of every six steps. One sprite per step removes that mismatch.

The trade is now deliberately in favour of smoothness:

- **Draw cost is unchanged.** A placed building is still one textured quad, so 24 facings cost the same per frame as four. The extra cost is art data and silhouette tracing, both paid at load time.
- **The shipped art is smaller, not bigger.** Baking at 1:1 (one PNG pixel per world pixel) keeps the 432 PNGs to about 14 MB, roughly twice the old 72-image 2.5x set, not six times; fitted textures are cached at the manifest rectangle's size, not the source's. Texture memory is therefore comparable to the four-facing build.
- **The detail is optional.** The official **HD Building Art** community mod re-supplies all 24 views at the old 2.5x density (`golf_tycoon.hd_building_art`). It registers frames lazily through `ModAPI.register_building_sprite_frame()`, so a player who wants the larger images pays for them only when a view is drawn, and can switch the pack off at any time.
- **A runtime 3D model is still a different game.** Reusing the generator's meshes in Godot would give continuous rotation, but it would replace the baked pixel-art lighting, palette and outlines the course is built around, and it would touch the placement ghost, catalogue preview, click silhouettes and every art test. The 3D pipeline stays offline as the authoring tool; the runtime stays 2D sprites.

### 5. Footprint anchor

`Building.set_position_in_grid()` places the node at the footprint centre minus `(size.x × 0.5, size.y)`. The art is projected around that same anchor, not around the footprint's centre. Getting this wrong moves every building half a tile across its own square. The mistake is hard to see on one tile and obvious on four, which is why `grid_origin_offset()` exists.

### 6. Foundations and the ground underneath

Placing a building changes its entire footprint to **Rough** and levels every
corner vertex to the first tile's elevation. The drawing is positioned again
after leveling so it sits on the new ground. Two touching buildings share edge
or corner vertices, so a new foundation adopts the neighbouring building's
level. The placement and move ghosts show that final level, including the
ground restored by an overlapping move. If neighbours demand different
levels, the previews explain why the footprint cannot fit without changing an
existing building.

`EntityLayer` remembers the original terrain, maintenance markers, paths, cups
and each actual vertex height. Demolition or a move restores those values;
shared vertices remain level until the last neighbouring building leaves.
Overlapping moves restore the old footprint before capturing the new one.
Foundation changes notify terrain renderers but do not create extra terrain
undo actions or new maintenance tiles. These snapshots are saved with each
building, so the same restoration works after a save or location switch. An
older save without snapshots keeps the ground it contains as the starting
point; connected legacy buildings are leveled together if necessary rather
than losing a building. Ground already lost before that save cannot be
reconstructed.

### 7. Hills in front

A building sorts with the other standing sprites in band 2, which puts every pixel of its art over the course surface. While the course has relief and the **Terrain-aware occlusion** setting is on (`TerrainGrid.terrain_occlusion_enabled()`), the placed building's `Architecture` node draws with `terrain_footprint_occlusion.gdshader`, which discards the pixels a nearer hill covers (`Building.refresh_terrain_occlusion()`).

A tree's shader measures every pixel against one ground point. That suits a thin trunk, not a building: anchored at its centre, a building would have its own foundation cut away the walls in front of that centre. The footprint shader measures against the building's volume instead. Every pixel of the art shows a point inside the column standing on the footprint, and the only terrain inside that column is the level foundation (section 6), so terrain can only be in front of the building where it is in front of the column. Each pixel's screen ray is met with the column's front face — a slab test against `footprint_position` and `footprint_size` — and the pixel is hidden only where the heightfield crosses the ray nearer the camera than that face (`terrain_hides()` in `terrain_heightfield.gdshaderinc`, the intersection the surface and the trees use). On level ground nothing is hidden; a mound before the front corner hides the foot of the walls and leaves whatever rises above the mound's top; a hill behind the building hides nothing. Art that overhangs the footprint continues smoothly from its edge, and a pixel below the foundation is measured at the foundation's height.

The heightfield texture is the surface's own, so a sculpt reaches every building at once. The footprint and the projection are set again by `set_position_in_grid()`, which a move, a new foundation and every step of a view turn already run, and by `_update_visuals()` after an upgrade or a restore. A flat course, the placement ghost and the Buildings tab picture draw with no material. A click on a covered pixel belongs to the hill, not the building: `terrain_hides_point()` asks `TerrainOcclusion.hides_footprint()`, the same test on the CPU.

### 8. Facilities

| Building | Distinguishing features |
| --- | --- |
| Clubhouse | Paved terrace, cream hall, hipped tiled roof, brick chimney, a club plaque over the door, planted urns and a flagpole. Tier 2 adds a pro-shop wing with a striped awning and dormers. Tier 3 adds a storey, a long front range whose awning carries a "CLUBHOUSE" sign, and a central clock tower with a clock face towards every rotation. |
| Putting Green | Manicured practice green with mowing stripes, a flat sand bunker, cup with a flag, stray practice balls, bench and club rack |
| Snack Bar | Serving hatch, striped awning, counter, menu board on a post |
| Pub | Stone inn with a smoking chimney, hanging sign, lantern, barrel by the door |
| Pro Shop | Display window with merchandise, striped awning, bag stand |
| Driving Range | A long covered range with six open bays, padded dividers, ball baskets, range flags and roof vents |
| Cart Garage | Open cart port under a three-bay canopy, two parked carts with seats, wheels and roofs, a third cart outside, roof vent and wheel stops |
| Tennis Court | Blue hard court, white lines, net across the middle, corner fence posts |
| Stable | Timber barn with split doors, hay-loft hatch, paddock fence |
| Spa | Thatched treatment hut beside a sunken tiled pool (coping, water surface and ripples), sun beds, umbrellas and palms |
| Swim Club | Rose-roofed changing hut beside a bright lane pool with a diving board, ladder, lane ropes and sun beds |
| Resort Hotel | Four storeys of guest-room windows, entrance canopy, red carpet, palms |
| Airstrip | Tarmac strip with a dashed centreline, a green-roofed hangar with sliding doors, a fuel bowser, fuel drums, windsock and a parked light plane with tapered wings, canopy and tailplane |
| Castle | Stone keep with crenellated walls and corner towers, an open gatehouse with a raised portcullis, drawbridge planks, torches and pennants |
| Casino | Wide hall with lit windows, a marquee of chasing lights, gold columns, palms |
| Theme Park | A ferris wheel over a midway, striped ticket tent and string lights |

---

## How the art is made

`tools/building_art/` is a small offline 3D pipeline, run from the repository root:

```bash
pip install -r tools/building_art/requirements.txt
python3 tools/building_art/generate.py                  # every sprite and sprites.json
python3 tools/building_art/generate.py --preview        # plus contact sheets in tmp_preview/
python3 tools/building_art/generate.py --only castle,spa --jobs 4
python3 tools/building_art/generate.py --scale 2.5 \
    --out-dir repository/packages/golf_tycoon.hd_building_art/art
```

The last command rebuilds the optional HD art pack at its 2.5x density; it writes
the pack's own `sprites.json`, which `mod_main.gd` registers view by view.

| File | Job |
| --- | --- |
| `render.py` | A z-buffered isometric rasteriser: projects triangles through the game's 2:1 axes, shades each face from its normal, bakes procedural plaster/brick/shingle/slate/grass/sand/water textures and texture decals, then supersamples 2x, outlines silhouette and face creases, and crops to the painted pixels. |
| `buildings.py` | The 16 facility models, built from shared 3D primitives (`box`, `slab`, `roof_gable`, `roof_hip`, `roof_pyramid`, `roof_shed`, `cylinder`, `ellipsoid`, `awning`, `pool`, `golf_cart`, `plane`, `ferris_wheel`, …) in world-pixel space with one palette. |
| `generate.py` | Builds and renders every tier and view step, writes the PNGs and manifest, validates the manifest invariants, and draws preview sheets. `--out-dir` writes an art pack instead of the shipped folder. |
| `requirements.txt` | Pillow and NumPy, the only dependencies. |

The generator is offline and is not part of the game build. The PNGs and `sprites.json` are committed, so the game and the tests need nothing but Godot. Regenerate and commit all 432 PNGs and the manifest when a design changes; the geometry, palette and building list all live in `buildings.py`. The shipped output is 1:1 art by default (`OUTPUT_SCALE = 1.0`); run `--scale 2.5 --out-dir …` to rebuild the HD pack. Art replaced by hand at another resolution is equally valid: keep the file names and manifest rects, and `BuildingSprites.texture()` fits the new image to the rect at load time.

The woodland sprites are baked the same way by `tools/tree_art/`, which reuses
this renderer (`render.py`) and its primitives: each species is a 3D model in
`tools/tree_art/trees.py`, and `tools/tree_art/generate.py` writes
`assets/sprites/trees/` and its `layout.json` (see [Tree Art](tree-art.md) and
[Terrain Types](terrain-types.md)).

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Footprint size | `data/buildings.json` `size` | Per building (clubhouse `[4, 4]`) | How many tiles a building covers |
| Projection axes | `course_architecture.gd` `project_point()` | Terrain's 2:1 axes | Shape of the building on screen |
| Pixel scale | `tools/building_art/render.py` `OUTPUT_SCALE` (or `--scale`) | 1.0 art pixel per world pixel (2.5 in the HD art pack) | Texture density in the source PNGs; the manifest rects stay in world pixels |
| Palette | `tools/building_art/render.py` | Cream walls, red/brown/slate roofs, green trim | The course's look |
| Catalogue scale | `building_tile_art.gd` `preview_transform()` | `min(0.34, 60 / width)`, tile/84 | How big a facility looks on its tab tile |
| Occlusion slack | `terrain_footprint_occlusion.gdshader` `occlusion_epsilon` (mirrored by `TerrainOcclusion.FOOTPRINT_EPSILON`) | `0.05` px | How far in front of a wall a hill must rise before it hides it |

---

## Related

- [Clubhouse](clubhouse.md) covers the one building that is always present.
- [Improvement Catalog](garden-catalog.md) lists all facilities and improvements.
- [Course Architecture](course-character.md) covers landforms and the redraw timer.
- [Path Furniture](path-furniture.md) covers the bench exception.
