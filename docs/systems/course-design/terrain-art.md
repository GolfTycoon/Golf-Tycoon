# Ground-Cover Art

> Brush, Rocks and Boulder are drawn, not just painted. Each tile is a tiny 3D
> model baked to pixel art through the same isometric renderer as the trees and
> buildings, then stood on the course's Rough ground.

**Source:** `tools/terrain_art/features.py` (palette, `rock_solid()`, `rock_dome()`, `lichen_patch()`, `draw_rocks()`, `draw_boulder()`, `draw_brush()`), `tools/terrain_art/generate.py` (`render_one()`, `anchor_ratios()`, `validate()`, `check()`), `tools/building_art/render.py` (projection, lighting, patterns, outlines), `scripts/terrain/terrain_feature_overlay.gd` (`TerrainFeatureOverlay`), `shaders/course_surface.gdshader` (`surface()`, `boundary_class()`), `assets/sprites/terrain/layout.json`
**Tests:** `tests/unit/course_design/test_terrain_feature_sprites.gd`, `python3 tools/terrain_art/generate.py --check`

---

## What is drawn, and what is painted

A Brush, Rocks or Boulder tile has two layers, the arrangement a woodland tile
and its canopy already share:

| Layer | Who draws it | What it is |
| --- | --- | --- |
| Ground | `CourseSurface` (band 0) | The course's own Rough turf: Rough's palette, grass tufts and hollows, with no bed or rim of its own. Brush, Rocks and Boulder share Rough's `boundary_class()`, so their grass runs straight into the rough around them |
| Sprite | `TerrainFeatureOverlay` (band 1) | The objects the tile is named for: angular slate slabs and chunks, a rounded granite boulder with a shoulder lobe and a leaning shard, low gorse bushes with yellow blossom. Rocks and Brush scatter two or three different variant drawings across one tile; Boulder stands a single drawing |

The split is what keeps the tiles readable as terrain rather than as props.
Rough is the course's default ground, so a rocky stretch, a boulder field and a
scrub bank all sit on the same grass as the rough around them; the sprites add
the stones or scrub that stand proud of it, and the terrain id still owns the
lie, the cost and the edge of the tile. A tile with no art on the machine still
shows its Rough ground and a fallback silhouette, never a bare patch.

The three tiles deliberately lost their own beds. Scree, fissured granite and
tangled undergrowth turned a painted tile into a slab of alien material in the
middle of a links course; grass under the sprite makes it read as rough studded
with stone or scrub instead. It also means the tiles can never be mistaken for
two copies of the same thing, and the shader has one ground to maintain rather
than three.

---

## Art direction

The ground-cover sprites continue the woodland's art direction, so a boulder
beside an oak belongs to the same afternoon.

| Rule | What it means |
| --- | --- |
| Silhouette first | A gorse clump reads as a low thorny bush at one pixel per world pixel; a boulder reads as a rounded standing stone with a broad sunlit crown and a dark lee; a rocky tile reads as scattered angular slabs, not gravel noise. |
| One sun, four tones | Every stone facet and leaf cluster takes one of four tones by the direction it faces the renderer's warm sun (`render.SUN`, upper right). Geometry alone would leave every camera-facing plane in shadow and turn a boulder into a hole; the toned faces keep a stone readable from every side. |
| Shard, not pebble | `rock_solid()` builds two irregular rings of corners – a buried foot and a narrower, twisted crown – bridged by flat side planes and closed with a flat cap. The result has hard facets, a broad lit top and a footprint that is never a smooth circle. It is the slate slab and the broken chip. |
| Boulder, not block | `rock_dome()` lathes rings whose radius falls away towards the top, so the mass is widest where it meets the turf, shoulders through the middle and rounds to a broad crown. It is what makes a Boulder read as one weathered stone rather than as a stack of slabs. |
| Grounded | Stones are set into the rough, scrub springs from woody stems that fork out of it, and each drawing keeps some bare ground so the Rough turf still shows at the edges. |
| Four drawings, one feature | The four variants are independent seeded drawings (`feature_seed()`), not rotations. Every Rocks and Brush tile wears two or three of them at once, spread across the tile; Boulder wears one. Neighbouring tiles pick different mixes, and turning the course never swaps the art under a tile. |

### The features

| Feature | Silhouette | Detail |
| --- | --- | --- |
| **Rocks** | One low outcrop per drawing: a cracked slab with a broken ledge, leaning flake, chunks and grit. The overlay scatters two or three of these drawings across every tile | Slate tones from shadow to sunlit grey-blue, a tilted flake of broken slate, quartz flecks and loose grit around the stone |
| **Boulder** | A low bedrock shelf carrying one broad, slightly leaning granite mass, with a second lobe breaking out of its flank | A companion shard leans against the other flank, wedged stones gather at the foot, warm-grey granite tones, cream lichen on the crown and face, and moss gathering in the seam at the foot |
| **Brush** | One low bush per drawing: short woody stems and a flat crown of gorse foliage, about as tall as a rock. The overlay plants two or three of these drawings across every tile | Gorse four-tone foliage, bright yellow blossom sprays on the sunward shell, thorn branches breaking the rim and low sprigs rooting the bush |

---

## The model kit

`rock_solid()`, `rock_dome()` and the tree builder's organic primitives cover
the three features:

| Primitive | Use |
| --- | --- |
| `rock_solid()` | One angular stone block: irregular foot ring, twisted crown ring, flat side facets and a flat cap, with a per-face tone chosen by facing. Slabs, shards and chips |
| `rock_dome()` | One rounded boulder: lathed rings widest at the turf, a wobbled rim, a rounded crown and a per-facet tone chosen by facing. The Boulder's main mass and its shoulder lobe |
| `chip()` | A small angular chunk or pebble among the stones (a `rock_solid()` with few sides) |
| `speckle_stone()` | A rounded quartz fleck or loose pebble at the foot of an outcrop |
| `lichen_patch()` | A crust of lichen dotting a stone's sunlit crown |
| `lichen_face()` | Cream lichen crusts standing proud of a boulder's warm face |
| `canopy()` / `shrub_canopy()` | The gorse leaf clouds (the same crown builder every tree uses) |
| `limb()` | Woody stems, thorn branches and forks |

The palette lives at the top of `features.py`: four slate tones, five granite
tones, lichen and moss greens, four gorse foliage tones, blossom yellows and
scrub-bark browns.

---

## Layout: a tile-centre anchor, per drawing

A tree's sprite is anchored at its trunk's foot, bottom-centre of its canvas.
A ground-cover feature is anchored at its **tile centre**, because the sprite
is the whole tile's content rather than something standing at one point.

The variants are cropped to their own silhouettes, so the tile centre falls in
a different place in each canvas. `assets/sprites/terrain/layout.json` records
the measured anchor for every file:

```json
{
	"features": {
		"boulder": {"scale": 1.0},
		"brush": {"scale": 1.0},
		"rocks": {"scale": 1.0}
	},
	"sprites": {
		"boulder_0": {"ground_x_ratio": 0.4055, "ground_y_ratio": 0.6732},
		"rocks_0": {"ground_x_ratio": 0.4403, "ground_y_ratio": 0.482}
	}
}
```

`features` gives a per-feature draw scale. `sprites` gives each drawing's
normalized `ground_x_ratio` / `ground_y_ratio`: the fraction of its own canvas
where the tile centre lies. `TerrainFeatureOverlay.art_anchor_offset()` turns
those into the offset from the image's centre, so replacing a PNG with another
canvas size needs no code edit. A missing `layout.json` draws the art at native
size, anchored at its own centre.

`TerrainFeatureOverlay` picks the first drawing with `facing_at(pos)`, a mixed
hash of the tile (deliberately salted differently from `TreeOverlay`'s seed, so
a rock and a tree on neighbouring tiles never share a lean). Rocks and Brush
then scatter two or three drawings: `stamps_for()` takes that first variant and
the next ones, drops them on the centre, left, right and back slots of the tile
with a little deterministic jitter and scale, and paints them back to front.
Boulder skips the scatter and stands its one drawing on the centre. Each tile
also gets a small base jitter (±3 px across, ±1.5 px down) and scale (0.94–1.06),
shared with its occlusion material by `ground_jitter()` / `variation_for_tile()`.

---

## Rendering and draw order

- The overlay lives in the ground band (`z_index` 1) with `y_sort_enabled`, so a
  rocky tile in front covers a scrub tile behind it.
- `TerrainGrid.GROUND_DETAIL_ORDER` ranks it **after** `WalkingPathOverlay` and
  **before** `TreeOverlay`: a boulder covers the trail trodden under it, and a
  canopy covers the rock beneath it.
- One `Node2D` CanvasItem per visible tile is created lazily and pooled, exactly
  as `TreeOverlay` does for canopies; the camera moving only changes membership,
  not how any sprite is drawn. A Rocks or Brush tile draws its two or three
  variant stamps inside that one CanvasItem, back to front.
- With terrain-aware occlusion on, each sprite samples the shared heightfield
  (`shaders/terrain_sprite_occlusion.gdshader`), so a hill rising in front of a
  boulder clips it pixel by pixel.
- The Course Terrain tab's tile buttons use `stamps_for()`, `sprite_path()` and
  `art_anchor_offset()` to stand the same scatter of variant drawings on the
  catalogue diamond.

---

## Regenerating the art

```bash
python3 tools/terrain_art/generate.py            # write every sprite
python3 tools/terrain_art/generate.py --preview  # contact sheets in tmp_preview/
python3 tools/terrain_art/generate.py --only boulder --preview
python3 tools/terrain_art/generate.py --check    # fail if the committed art is stale
```

Dependencies are the same as the tree art (`pip install -r tools/tree_art/requirements.txt`).
The generator is offline and not part of the game build; the PNGs and
`layout.json` are committed, so the game and the tests need only Godot. New PNGs
need Godot's import step once (`godot --headless --editor --quit`).

The rendered canvas is cropped to the painted pixels and the generator records
the tile centre's position inside it, so changing a model's size or stance only
needs a re-run. `--preview` writes `terrain_sheet.png` (all variants on a flat
sheet) and `terrain_on_course.png` (each variant standing on a tile diamond
exactly as the overlay places it).

---

## Tuning levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Feature art mapping | `terrain_feature_overlay.gd` `FEATURE_KEYS` | Brush, Rocks, Boulder → `brush`, `rocks`, `boulder` | Which tiles get a sprite, and the file name each wears |
| Per-tile lean and size | `terrain_feature_overlay.gd` `JITTER_X`, `JITTER_Y`, `SCALE_MIN`, `SCALE_MAX` | ±3 px, ±1.5 px, 0.94–1.06 | How varied one rocky field reads; large values open gaps between tiles |
| Draw scale and anchors | `assets/sprites/terrain/layout.json` | Scale 1.0, per-file tile-centre ratios | Replace independently sized outcrop art without editing renderer code |
| Stone geometry | `tools/terrain_art/features.py` `rock_solid()` | 4–7 sides, taper 0.45–0.97, wobble 0.15–0.26 | Facet count, blockiness and irregularity of every stone |
| Stone tones | `tools/terrain_art/features.py` `SLATE_*`, `GRANITE_*` | Four slate and five granite tones | How cold, light and readable stone is against the ground |
| Gorse tones and blossom | `tools/terrain_art/features.py` `GORSE_*`, `BLOSSOM*` | Four foliage tones, two yellows | The scrub's colour and how thickly it flowers |
| Ground under a sprite | `shaders/course_surface.gdshader` `surface()` (`palette_color(3.0)` and Rough's tuft noise) and `boundary_class()` | Rough's own turf, shared with Rough tiles | Whether the three tiles read as rough studded with stone or scrub, and where their grass merges into adjacent rough |
| Object height | `tools/terrain_art/features.py` `draw_rocks()`, `draw_brush()` | Slabs 1.4–5.6 high; bush crowns 2.6–3.6 tall, centred 3.8–5.2 up | How tall one stone or bush stands; both should stay low ground cover |
| Drawings per tile | `terrain_feature_overlay.gd` `MIN_STAMPS`, `MAX_STAMPS` | Two or three | How many variant drawings a Rocks or Brush tile wears at once |
| Stamp slots | `terrain_feature_overlay.gd` `STAMP_SLOTS` | Centre, left, right and back, in screen pixels from the tile centre | Where the scattered drawings stand, and how far they spread |

---

## Related

- [Terrain Types](terrain-types.md) lists every tile, its cost and its rules.
- [Course Surface](course-surface.md) explains the procedural ground beneath the sprites.
- [Tree Art](tree-art.md) is the woodland art this pipeline shares.
- [Walking Paths](walking-paths.md) covers the trail the ground-cover sprites are ranked over.
