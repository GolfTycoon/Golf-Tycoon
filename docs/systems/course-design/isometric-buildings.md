# Isometric Buildings

> Every facility is a pixel image standing on the tiles it was bought for: one sprite per upgrade tier and per quarter-turn of the view. The same picture draws the placed building, its placement ghost and its tile on the Buildings tab.

**Source:** `scripts/entities/course_architecture.gd` (`grid_origin_offset()`, `project_point()`, `draw_building()`), `scripts/entities/building_sprites.gd` (manifest, textures, drawing), `assets/sprites/buildings/` (72 PNGs and `sprites.json`), `tools/building_art/` (the generator that produced them), `scripts/entities/building.gd` (`set_position_in_grid()`), `scripts/ui/placement_preview.gd` (ghosts), `scripts/ui/components/building_tile_art.gd` (Buildings tab pictures)
**Tests:** `tests/unit/course_design/test_isometric_architecture.gd`, `tests/unit/ui_and_controls/test_building_tile_art.gd`, `tests/integration/course_design/test_buildings_isometric.gd` (all three check the sprite's painted rectangle, not the source PNG's pixel grid)

---

## Plain English

Each facility is a small piece of pixel art drawn in isometric projection. Its walls run along the same 2:1 diamonds as the terrain, its roof slopes along the course's own isometric axes, and its door faces the edge golfers actually walk to. Nothing is a flat elevation laid over the grid.

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
"clubhouse": {
  "tiers": {
    "1": {
      "facings": [
        { "file": "clubhouse_1_e.png", "rect": [7.0, 24.0, 242.0, 164.0] },
        ...
      ],
      "height": 63.0
    }
  },
  "sprite_height": 115.0
}
```

`BuildingSprites.draw()` draws the texture into that rectangle 1:1: one drawn pixel is one world pixel, so a 4-tile-wide clubhouse is about 242 pixels across on screen. The **source PNG does not have to be that size**. The shipped sprites are higher-resolution art (roughly 600 x 460 pixels) so their roof tiles, windows and paving keep their detail; `BuildingSprites.texture()` resamples each PNG once, when it is first loaded, into the manifest rectangle with a Lanczos filter. That keeps the draw call a 1:1 blit — the GPU never has to minify a big texture with nearest filtering, which would alias and flicker as the camera zooms — and it means replacing the art does not move a building off its tiles. Textures are cached after the first load, so `_draw()` stays cheap.

`BuildingSprites.painted_rect()` maps a texture's opaque pixels into the same local draw space (`rect.size / texture.size` world pixels per image pixel). Use it anywhere the *painted* bounds matter rather than assuming the source resolution; `source_texture()` returns the untouched PNG for tools and previews. Mods keep their registered texture and draw rect unchanged, and the same mapping applies to them.

### 2. Pixel size

| Thing | Size |
| --- | --- |
| Tile | 64 x 32 world pixels |
| Drawn pixel | 1 world pixel (1/64 of a tile across) |
| Source art pixel | 1/2 to 1/5 world pixel in the current sprites (resampled at load) |
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

The view can be rotated a quarter turn at a time, and buildings turn with it. Each rotation has its own pre-rendered image. After a rotation, `Building.set_position_in_grid()` passes the new `facing` to the architecture node, which swaps in that rotation's file.

| Function | What it does |
| --- | --- |
| `grid_origin_offset(size, view_facing)` | Finds where grid `(0, 0)` falls in the building's local space. This matches the anchor used by `set_position_in_grid()`. |
| `project_point(origin, p, view_facing)` | Converts a grid point to local draw space. |
| `screen_delta(offset)` | Converts a grid offset to a screen offset, for extents and shadows. |
| `footprint_corners(size, view_facing)` | The four tile corners of a footprint, in local draw space. |
| `BuildingSprites.rect(kind, tier, facing)` | The rectangle a sprite covers in the same space. |

### 5. Footprint anchor

`Building.set_position_in_grid()` places the node at the footprint centre minus `(size.x × 0.5, size.y)`. The art is projected around that same anchor, not around the footprint's centre. Getting this wrong moves every building half a tile across its own square. The mistake is hard to see on one tile and obvious on four, which is why `grid_origin_offset()` exists.

### 6. Facilities

| Building | Distinguishing features |
| --- | --- |
| Clubhouse | Paved terrace, cream hall, hipped tiled roof, chimney, a club plaque over the door and a flagpole. Tier 2 adds a pro-shop wing with a striped awning. Tier 3 adds a storey, a long front range whose awning carries a "CLUBHOUSE" sign, and a clock tower. |
| Putting Green | Manicured practice green, fringe, cup with a flag, stray practice balls |
| Snack Bar | Serving hatch, striped awning, counter, menu board on a post |
| Pub | Stone inn with a smoking chimney, hanging sign, lantern, barrel by the door |
| Pro Shop | Display window with merchandise, striped awning, bag stand |
| Driving Range | A row of covered bays with padded dividers and ball baskets |
| Cart Garage | Open bays with parked carts, roof vent, wheel stops |
| Tennis Court | Blue hard court, white lines, net across the middle, corner fence posts |
| Stable | Timber barn with split doors, hay-loft hatch, paddock fence |
| Spa | Treatment hut beside a bathing pool ringed by loungers, palm |
| Swim Club | Pink-roofed changing hut beside a bright pool with a diving board and ladder |
| Resort Hotel | Four storeys of guest-room windows, entrance canopy, red carpet, palms |
| Airstrip | Tarmac strip with a dashed centreline, hangar, windsock and a parked light plane |
| Castle | Stone keep with crenellated walls and corner towers, gate and pennant |
| Casino | Wide hall with lit windows, a marquee of chasing lights, gold columns, palms |
| Theme Park | A ferris wheel over a midway, striped ticket tent and string lights |

---

## How the art is made

`tools/building_art/` is a small offline pipeline, run from the repository root:

```bash
python3 tools/building_art/generate.py            # write every sprite and sprites.json
python3 tools/building_art/generate.py --preview  # also write contact sheets to tmp_preview/
```

| File | Job |
| --- | --- |
| `render.py` | A z-buffered isometric pixel rasteriser. Faces are vertical walls, flat ground and slopes; every pixel solves the projection backwards to find the grid point it shows. |
| `buildings.py` | The 16 facility designs, built from shared primitives (`box`, `gable`, `hip`, `pyramid`, `awning`, `fence`, …) and one palette. |
| `generate.py` | Renders every tier at every rotation, writes the PNGs and the manifest, and can draw preview sheets. |

The generator is not part of the game build. The PNGs and `sprites.json` are committed, so the game and the tests need nothing but Godot. Regenerate and commit when a design changes; the shapes, palette and building list all live in `buildings.py`. Its PNGs happen to be written at one pixel per world pixel. Art replaced by hand at a higher resolution is equally valid: keep the file names and manifest rects, and `BuildingSprites.texture()` fits the new image to the rect at load time.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Footprint size | `data/buildings.json` `size` | Per building (clubhouse `[4, 4]`) | How many tiles a building covers |
| Projection axes | `course_architecture.gd` `project_point()` | Terrain's 2:1 axes | Shape of the building on screen |
| Pixel size | `tools/building_art/render.py` `ART_SCALE` | 1 world pixel per art pixel | Texture density; above 1 the art gets chunkier and the sprite grows |
| Palette | `tools/building_art/render.py` | Cream walls, red/brown/slate roofs, green trim | The course's look |
| Catalogue scale | `building_tile_art.gd` `preview_transform()` | `min(0.34, 60 / width)`, tile/84 | How big a facility looks on its tab tile |

---

## Related

- [Clubhouse](clubhouse.md) covers the one building that is always present.
- [Improvement Catalog](garden-catalog.md) lists all facilities and improvements.
- [Course Architecture](course-character.md) covers landforms and the redraw timer.
- [Path Furniture](path-furniture.md) covers the bench exception.
