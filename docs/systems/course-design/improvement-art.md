# Improvement Art

> The Path, Park Bench, Fountain, Golfer Statue, Ball Washer and Sundial are drawn
> at the same density, with the same sun and the same ink outline as the
> buildings, trees and ground cover. Most of them are tiny 3D models baked to
> pixel art; the two read from above are painted directly, because a rendered rim
> hides its own water.

**Source:** `tools/improvement_art/props.py` (bench, statue, washer models), `tools/improvement_art/paint2d.py` (fountain and sundial painters), `tools/improvement_art/generate.py` (bake, palette, foot anchors, preview, `--check`), `tools/path_art/generate.py` (dirt and paved grain), `scripts/entities/improvement_art.gd` (runtime loader and foot anchor), `scripts/entities/decoration.gd`, `scripts/entities/path_furniture.gd`, `scripts/terrain/walking_path_overlay.gd`, `assets/sprites/improvements/`, `assets/sprites/paths/`
**Tests:** `tests/unit/course_design/test_path_furniture.gd`, `python3 tools/improvement_art/generate.py --check`, `python3 tools/path_art/generate.py --check`

---

## Art direction

The improvements are **garden furniture on the same afternoon as the clubhouse**,
not a separate set of icons.

| Rule | What it means |
| --- | --- |
| One sun | Every render uses the buildings' warm sun, cool fill and quantised shade steps. The props then get a gentle shadow lift so a bench's front face is as readable as a wall's lit face. |
| One palette | Cream and warm stone, slate iron, warm timber, brass and one bronze family. Colours are chosen bright, because the front faces land near half exposure under the building sun. |
| Silhouette first | At 1× a bench must read as open slats and a leaning back; a statue as a golfer mid-swing; a washer as post, drum and towel. Fine detail that only shows at 4× is noise. |
| Compact palette | Every baked sprite is reduced to 24 colours with no dithering. That is what turns the renderer's hundreds of near-identical facets back into hand-painted tones. |
| Four fronts | The bench and ball washer are laid beside a walk and turn to face it, so each ships four drawings (south, east, north, west). The fountain, statue and sundial stand in the open and ship one. |
| Painted, not modelled, when read from above | The fountain's basin and the sundial's face are horizontal. A 3D rim is taller than the water behind it and a dial face projects to a handful of pixels, so both are painted in screen space at 4× and reduced once. |

### Style split

| Improvement | How it is made | Why |
| --- | --- | --- |
| Park Bench | 3D model | Slats, back, arms and iron legs are all side-on shapes the renderer models well. |
| Golfer Statue | 3D model | A figure needs real limbs and a turned torso; the bronze facets shade the pose. |
| Ball Washer | 3D model | Post, drum, lid, tank, towel and enamel sign read as volumes. |
| Fountain | Painted at 4× | A wide basin, visible water and a bright plume need a clean ellipse the camera looks into. |
| Sundial | Painted at 4× | The engraved face and the gnomon shadow have to be legible; a horizontal face rendered in 3D is only a few pixels tall. |

---

## The pipeline

### 3D props

1. `props.py` builds each prop on the centre of a 1×1 tile at `(32, 16, 0)` in
   world-pixel space, using the buildings' `Builder` and renderer. Each limb is a
   crease group, so a bronze arm shades as one cast limb rather than a stack of
   segments.
2. `generate.py` renders it through `tools/building_art/render.py` at one pixel
   per world pixel with 2× supersampling and the standard ink outline.
3. `enhance()` lifts the shadows (gamma 0.80, saturation ×1.22), protects the
   ink, and quantises to 24 colours.
4. The drawing is cropped to its painted pixels; `layout.json` records where the
   tile-centre foot landed in that crop.

### Painted props

`paint2d.py` draws the fountain and sundial on a 4× canvas with Pillow
primitives — stone blocks, water gradient, ripples, brass rim, cream dial, hour
marks, gnomon shadow — then reduces it once with Lanczos and the same 24-colour
quantiser. The result is the same size and outline weight as a rendered prop.

### The Path grain

The Path is not a sprite standing on the ground: it is a canvas mesh of tinted
bands (`WalkingPathOverlay`). Its shape, kerbs, joints and grass blades stay
procedural, but two seamless **detail maps** are multiplied over the vertex
colours:

| Texture | Surface | Grain |
| --- | --- | --- |
| `assets/sprites/paths/dirt.png` | Dirt trail | Packed earth, grit, pebbles with a lit edge, a few blades of grass |
| `assets/sprites/paths/paved.png` | Paved promenade | Dressed stone, stone grain, fine courses, a little moss in the joints |

Both are near-white, so the commands keep their tint; the darker specks only add
grit. `WalkingPathOverlay._draw()` supplies the right texture per tile, so a
paved tile and a dirt tile can share one material and one mesh format. The UVs
are still the ground grid points the occlusion shader needs.

Because a vertex UV is the **absolute ground grid point** the occlusion shader
needs (not a 0–1 texture coordinate), `WalkingPathOverlay` sets
`texture_repeat = ENABLED`: one 64 px grain tile per ground unit, continuous
across neighbouring trail tiles. Godot 4 has already multiplied the texture into
`COLOR` when the custom occlusion fragment runs (see the sprite shader's note),
so the grain survives the clip.

---

## Anchoring

Every PNG was baked at 1× and cropped to its pixels, so the game cannot infer the
tile centre from the image. `layout.json` carries it:

```json
"park_bench_1": {
  "foot_x_ratio": 0.425,
  "foot_y_ratio": 0.767,
  "width": 52,
  "height": 46
}
```

`ImprovementArt` reads the sidecar once, converts the ratios to a pixel offset,
and the sprite is drawn at `-foot_offset` from its top-left. A centred
`Sprite2D` is not used: its offset depends on the transparent padding, and the
whole point of cropping is that there is none.

The bench and washer keep the existing `PathFurniture` node, facing and edge
offset. `PathFurniture.draw_item()` now draws the baked texture for that front,
so the placement ghost, the catalogue tile and the placed prop all agree.
`PathFurniture.ground_reach()` is the drawing's own overhang below its foot, not
a hand-tuned constant.

---

## Regenerating

```bash
python3 tools/improvement_art/generate.py            # write every sprite
python3 tools/improvement_art/generate.py --preview  # 4× contact sheet
python3 tools/improvement_art/generate.py --check    # fail if art is stale
python3 tools/path_art/generate.py                   # write the two grain maps
python3 tools/path_art/generate.py --check
```

The PNGs and `layout.json` are committed. The game and the GUT suites need only
Godot; Pillow and NumPy are needed only to rebake.

---

## Tuning levers

| Setting | Location | Current value | Effect |
| --- | --- | --- | --- |
| Sprite palette | `generate.py` `PROP_PALETTE` | 24 | Colours per baked sprite |
| Shadow lift | `generate.py` `_lift_prop_shade()` | gamma 0.88 | Brightness of a prop's front faces |
| Enhance gamma / saturation | `generate.py` `enhance()` | 0.80 / 1.22 | Overall lift and colour of a render |
| Model scale | `props.py` `MODEL_SCALE` | Washer 1.10 | Props authored a little small for a 64×32 tile |
| Fountain / sundial canvas | `paint2d.py` | 64×68 / 48×56 at 4× | Painted proportions and headroom |
| Path grain strength | `paint2d` / `tools/path_art/generate.py` | near-white base | How strongly the texture darkens the tint |

---

## Related

- [Improvement Catalog](garden-catalog.md) lists the improvements and their data.
- [Path Furniture](path-furniture.md) covers placement and facing.
- [Walking Paths](walking-paths.md) covers the trail mesh the grain is drawn on.
- [Tree Art](tree-art.md) and [Ground-Cover Art](terrain-art.md) share the renderer and palette.
