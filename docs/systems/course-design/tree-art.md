# Tree Art

> Every woodland sprite is a tiny 3D tree, baked to pixel art through the same
> isometric renderer as the buildings. One afternoon sun, chunky silhouettes and
> leaf-scale foliage clusters keep all eleven species in one illustrated world.

**Source:** `tools/tree_art/trees.py` (palette, `TreeBuilder`, `canopy()`, the eleven species draw functions), `tools/tree_art/generate.py` (`render_one()`, `anchor_to_ground()`, `validate()`, `check()`), `tools/building_art/render.py` (projection, lighting, surface patterns, outlines), `assets/sprites/trees/layout.json`
**Tests:** `tests/unit/course_design/test_tree_sprites.gd`, `python3 tools/tree_art/generate.py --check`

---

## Art direction

The trees are **sunlit storybook woodland** that sits beside the cream-and-
terracotta clubhouses. The rules are deliberately shared by every species, so a
palm and a pine still look like neighbours.

| Rule | What it means |
| --- | --- |
| Silhouette first | A species must be readable as a solid shape at one pixel per world pixel: the oak's broad goblet, the pine's scalloped spire, the birch's airy clump, the palm's wheel of feathers, the cactus's raised arms. |
| One sun | Every model is lit by the renderer's single warm sun from the upper right (`render.SUN`). Foliage picks one of four tones from where a cluster faces that sun, so all crowns shade together and a wood shares one afternoon. |
| Leaf-scale grain | A crown is a cloud of small leaf clusters (roughly 2–7 world px), not a smooth ball. The `leaf_fine` pattern dapples every cluster, and small rim tufts fray the edge. The cluster sets the detail scale, so a heather cushion and a 70 px oak carry the same visual grain. |
| Wood shows | A root-flared, tapered trunk and real forking limbs carry the crown. Bark is bark: vertical ridges, a warm lit side and a shadowed lee. |
| Four drawings, one tree | The four view variants are independent seeded drawings of the species, not rotations. A wood wears several different trees at once and turning the course never swaps the art under a canopy. |

### Foliage tones

Each species has four leaf materials: deep shadow, mass, lit face and a warm
sun rim. `canopy()` chooses between them with `tone_for()` and the shared sun
direction; the same four-tone idea covers bark, palm fronds and heather bloom.

| Species | Leaf family |
| --- | --- |
| Oak | Deep summer green with a warm lime rim |
| Maple | Ember red through burnt orange to a gold rim |
| Birch | Yellow-green, airy, pale against white trunks |
| Pine | Blue-green needles, dark and quiet |
| Palm | Bright yellow-green feathers with brown spent fronds |
| Shrub | Rich garden green with red berries in some variants |
| Fescue | Olive to straw, a tuft that has gone to seed |
| Heather | Dark foliage under magenta bloom |
| Cattails | Reed green with chocolate-cigar heads |
| Cactus | Sage skin, pale spines, pink crown bloom |
| Dead tree | Warm grey bark, bare and splintered |

---

## The model kit

`TreeBuilder` extends the building kit with organic shapes:

| Primitive | Use |
| --- | --- |
| `limb()` / `taper_path()` | Tapered branches and curved trunks |
| `blob()` | A leaf cluster, oriented by `yaw`/`tilt` and roughened with `wobble` |
| `blade()` | A grass blade or leaf ribbon; `cross=True` adds a second vane so thin blades stay visible from every view |
| `leaf_tuft()` | A handful of small leaves breaking a rim |
| `roots()` | The root flare and toes cut off at the turf |
| `gnarl()` | A recursively forking, wandering limb (dead trees and boughs) |
| `ribbed_column()` | A ribbed cactus column with pale spines |
| `pebble()` | A half-sunk stone at a clump's foot |

`canopy()` assembles a crown: a dark under-mass, Fibonacci-spaced leaf clusters
over an ellipsoid shell, filler caps that close the middle, under-shoulders that
keep the top connected, and rim tufts anchored to real clusters so no leaf ever
floats free. Because the renderer's outlines follow *crease groups*, the
clusters inside one canopy mass share a group, so they merge into foliage
instead of reading as a bag of marbles. A separate cloud lobe (an oak's
shoulders, a maple's wings) keeps its own group and so keeps a soft ink seam
where it meets the crown.

The tree palette lives in `trees.py`. The renderer gained four surface patterns
for it: `leaf_fine` (dappled leaves), `needle` (conifer strokes), `bloom`
(heather baubles), `reed` (grass fibres), and a bolder `birch` paper-bark dash.

---

## Regenerating

```bash
python3 tools/tree_art/generate.py             # bake all 44 sprites + layout.json
python3 tools/tree_art/generate.py --preview   # also draw contact sheets in tmp_preview/
python3 tools/tree_art/generate.py --only oak,pine --preview
python3 tools/tree_art/generate.py --check     # fail if the committed art is stale
```

The generator is offline and not part of the game build. It needs Pillow and
NumPy (`pip install -r tools/tree_art/requirements.txt`). Commit the PNGs and
`layout.json`; the game and its tests only need Godot.

Each sprite keeps the contract the game's layout assumes:

- one PNG per species and variant, `<species>_<0|1|2|3>.png`;
- the trunk's ground point at the bottom-centre of the canvas;
- `layout.json` at the same density (`scale` × `ground_x_ratio` ×
  `ground_y_ratio`), so differently-sized variants place correctly;
- variants are genuinely different drawings, and the oak's first two views are
  independently sized (the shipped art and `test_tree_sprites.gd` pin this).

The crop step centres the drawn content on the trunk's ground point rather than
on the renderer's padded canvas, so no sprite carries a wide empty margin. The
generator's invariant check fails on an empty canvas, content that misses the
bottom edge, a missing variant or a canvas still padded on both sides.

Seasonal and mod tree art does not pass through this generator: the Seasons mod
ships authored drawings in `repository/packages/golf_tycoon.seasons/tree_art/`,
and `tools/tree_art/mod_views.py` derives their numbered views. The core
`assets/sprites/trees/` set is the evergreen summer wardrobe.

---

## Related

- [Terrain Types](terrain-types.md) — the woodland tiles, their ground and shot rules.
- [Buildings on the Grid](isometric-buildings.md) — the shared isometric renderer and palette.
- [Course Surface](course-surface.md) — the painted grounds under the trees.
