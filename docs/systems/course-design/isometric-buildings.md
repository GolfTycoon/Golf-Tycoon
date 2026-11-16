# Isometric Buildings

> Every facility is a pixel image standing on the tiles it was bought for: one sprite per upgrade tier and per quarter-turn of the view. The same picture draws the placed building, its placement ghost and its tile on the Buildings tab.

**Source:** `scripts/entities/course_architecture.gd` (`grid_origin_offset()`, `project_point()`, `draw_building()`), `scripts/entities/building_sprites.gd` (manifest, textures, drawing), `assets/sprites/buildings/` (72 PNGs and `sprites.json`), `tools/building_art/` (the generator that produced them), `scripts/entities/building.gd` (`set_position_in_grid()`), `scripts/ui/placement_preview.gd` (ghosts), `scripts/ui/components/building_tile_art.gd` (Buildings tab pictures)
**Tests:** `tests/unit/course_design/test_isometric_architecture.gd`, `tests/unit/ui_and_controls/test_building_tile_art.gd`, `tests/integration/course_design/test_buildings_isometric.gd` (sprite bounds); `tests/unit/course_design/test_building_foundations.gd`, `tests/integration/course_design/test_building_foundations_flow.gd` (ground, moves, undo and save/load)

---

## Plain English

Each facility is a **true 3D model** baked into pixel art: walls, pitched roofs, awnings, chimneys, towers, fences and props are built from triangular solids, lit from the same sun, and rasterised through the course's own 2:1 isometric projection. The renderer keeps a z-buffer, so a porch really is in front of the wall behind it, a window reveal is recessed, and a clock tower rises through a roof instead of being pasted over it. Its door faces the edge golfers actually walk to. Nothing is a flat elevation laid over the grid.

Three things use the same image, so they always match:

- the **placed building**;
- the **ghost** that follows the cursor before you click;
- the **picture** on the Buildings tab.

Comparing the picture with the footprint under the cursor shows the same building, only at a different scale.

The park bench is not a building at all: it is a ground fixture on the Improvements tab, drawn by [Path Furniture](path-furniture.md).

---

## Algorithm

### 1. One sprite per tier per rotation

`assets/sprites/buildings/` holds a PNG for every building, upgrade tier and view rotation (`clubhouse_2_n.png`, `casino_1_e.png`, …), plus `sprites.json`. The manifest records, for each image, the rectangle it covers in the **local draw space of the building node** — the same space `Building.set_position_in_grid()` anchors — in world pixels:

```json
{
  "tile": [64, 32],
  "pixel_scale": 2.5,
  "buildings": {
    "clubhouse": {
      "tiers": {
        "1": {
          "facings": [
            { "file": "clubhouse_1_e.png", "rect": [10.0, 17.31, 236.0, 171.6] },
            { "file": "clubhouse_1_s.png", "rect": [ ... ] },
            ...
          ],
          "height": 65.69
        }
      },
      "sprite_height": 118.12
    }
  }
}
```

`BuildingSprites.draw()` draws the texture into that rectangle 1:1: one drawn pixel is one world pixel, so a 4-tile-wide clubhouse is about 236 pixels across on screen. The **source PNG does not have to be that size**. The shipped sprites are 2.5x art (roughly 600 x 500 pixels) so their roof tiles, windows and paving keep their detail; `pixel_scale` records that ratio. `BuildingSprites.texture()` resamples each PNG once, when it is first loaded, into the manifest rectangle with a Lanczos filter. That keeps the draw call a 1:1 blit — the GPU never has to minify a big texture with nearest filtering, which would alias and flicker as the camera zooms — and it means replacing the art does not move a building off its tiles. Textures are cached after the first load, so `_draw()` stays cheap.

`BuildingSprites.painted_rect()` maps a texture's opaque pixels into the same local draw space (`rect.size / texture.size` world pixels per image pixel). Use it anywhere the *painted* bounds matter rather than assuming the source resolution; `source_texture()` returns the untouched PNG for tools and previews. Mods keep their registered texture and draw rect unchanged, and the same mapping applies to them.

### 2. Pixel size

| Thing | Size |
| --- | --- |
| Tile | 64 x 32 world pixels |
| Drawn pixel | 1 world pixel (1/64 of a tile across) |
| Source art pixel | 0.4 world pixel (the shipped sprites are baked at 2.5x, then resampled at load) |
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

Each facility has four pre-rendered images, one per compass quarter turn (`N`, `E`, `S`, `W`). When **Gradual View Rotation** is on, the terrain turns to the exact 15°-stepped angle while buildings (like trees and the HUD facing chip) continue using the four-way art for the **nearest** compass direction (`TerrainGrid.get_view_orientation()`). After any view change — including intermediate tween frames — `Building.set_position_in_grid()` updates the building's anchor to the terrain's exact projected tile centre and passes that nearest four-way `facing` to the architecture node. Turning Gradual View Rotation off settles the view onto the nearest quarter turn and restores classic instant quarter-turn rotation.

| Function | What it does |
| --- | --- |
| `grid_origin_offset(size, view_facing)` | Finds where grid `(0, 0)` falls in the building's local space. This matches the anchor used by `set_position_in_grid()`. |
| `project_point(origin, p, view_facing)` | Converts a grid point to local draw space. |
| `screen_delta(offset)` | Converts a grid offset to a screen offset, for extents and shadows. |
| `footprint_corners(size, view_facing)` | The four tile corners of a footprint, in local draw space. |
| `BuildingSprites.rect(kind, tier, facing)` | The rectangle a sprite covers in the same space. |

### Why four facings?

Four facings are a deliberate performance and art-budget choice, not a limitation of the pipeline:

- **Draw cost is already minimal.** A placed building is one textured quad, so four or twenty-four facings cost the same per frame. The extra cost of more facings is in art data, load time, texture memory and click-silhouette tracing, not in drawing.
- **Texture memory grows linearly.** The shipped 72 PNGs are 8.2 MB on disk. Each fitted texture is cached at roughly its manifest rectangle (about 150-250 KB of RGBA), so 24 facings would multiply that cache by six — roughly 50-60 MB if every facility and tier were on screen — which is a poor trade on low-end and web builds.
- **The game's rotation is quarter-turn.** Classic rotation is exactly four views; Gradual View Rotation tweens the terrain at 15° steps while buildings take the nearest quarter turn, so extra facings would only smooth that snap. If that snap ever needs smoothing, **eight facings** (45°) is the sensible pixel-art step: twice the data for most of the visual gain. Twenty-four facings (15°) would cost six times the art and cache for a subtle improvement.
- **A runtime 3D model is a different game.** Reusing the generator's meshes in Godot would give continuous rotation and cheap geometry reuse, but it would replace the baked pixel-art lighting, palette and outlines that the course is built around, and it would touch the placement ghost, catalogue preview, click silhouettes and every art test. The 3D pipeline is best kept offline as the authoring tool; the runtime stays 2D sprites.

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

### 7. Facilities

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
```

| File | Job |
| --- | --- |
| `render.py` | A z-buffered isometric rasteriser: projects triangles through the game's 2:1 axes, shades each face from its normal, bakes procedural plaster/brick/shingle/slate/grass/sand/water textures and texture decals, then supersamples 2x, outlines silhouette and face creases, and crops to the painted pixels. |
| `buildings.py` | The 16 facility models, built from shared 3D primitives (`box`, `slab`, `roof_gable`, `roof_hip`, `roof_pyramid`, `roof_shed`, `cylinder`, `ellipsoid`, `awning`, `pool`, `golf_cart`, `plane`, `ferris_wheel`, …) in world-pixel space with one palette. |
| `generate.py` | Builds and renders every tier and rotation, writes the PNGs and manifest, validates the manifest invariants, and draws preview sheets. |
| `requirements.txt` | Pillow and NumPy, the only dependencies. |

The generator is offline and is not part of the game build. The PNGs and `sprites.json` are committed, so the game and the tests need nothing but Godot. Regenerate and commit all 72 PNGs and the manifest when a design changes; the geometry, palette and building list all live in `buildings.py`. The output is 2.5x art by default so the baked detail survives the game's 1:1 blit. Art replaced by hand at another resolution is equally valid: keep the file names and manifest rects, and `BuildingSprites.texture()` fits the new image to the rect at load time.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Footprint size | `data/buildings.json` `size` | Per building (clubhouse `[4, 4]`) | How many tiles a building covers |
| Projection axes | `course_architecture.gd` `project_point()` | Terrain's 2:1 axes | Shape of the building on screen |
| Pixel scale | `tools/building_art/render.py` `OUTPUT_SCALE` (or `--scale`) | 2.5 art pixels per world pixel | Texture density in the source PNGs; the manifest rects stay in world pixels |
| Palette | `tools/building_art/render.py` | Cream walls, red/brown/slate roofs, green trim | The course's look |
| Catalogue scale | `building_tile_art.gd` `preview_transform()` | `min(0.34, 60 / width)`, tile/84 | How big a facility looks on its tab tile |

---

## Related

- [Clubhouse](clubhouse.md) covers the one building that is always present.
- [Improvement Catalog](garden-catalog.md) lists all facilities and improvements.
- [Course Architecture](course-character.md) covers landforms and the redraw timer.
- [Path Furniture](path-furniture.md) covers the bench exception.
