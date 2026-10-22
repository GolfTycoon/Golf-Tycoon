# Example: User Tree Sprite Pack

A complete **data-only** replacement for Golf Tycoon's standing-tree art.
There is no script and no dependency: enable it in the Mods screen, then use
**Apply & Reload**. Every existing course keeps its terrain, saves and tree
species; only the pictures change.

## What is in this pack

`tree_art/` holds the supplied user art directly at its root. It includes all
four views (`_n`, `_e`, `_s`, `_w`) for every shipped tree terrain species:

- oak, pine, maple, birch and palm;
- dead tree, cactus and bush;
- fescue, cattails and heather.

Root-level art is an **all-season replacement**. It takes priority over both
the base game's evergreen art and the Seasons mod's spring/fall/winter
wardrobe, so this one folder replaces every tree sprite all year — even when
Seasons is disabled.

The supplied drawings are larger than Golf Tycoon's built-in sprite canvases,
so `tree_art/layout.json` scales them down **at draw time**. The PNGs stay
untouched: users can tune the numbers without losing detail or maintaining a
second resized copy of their art.

## Make it yours

Copy this folder into `user://mods/` (open it from **Mods**) and change the
`id`, `name`, `author` and `description` in `mod.json` before sharing it. Keep
the filename pattern:

```text
tree_art/
  layout.json
  oak_n.png  oak_e.png  oak_s.png  oak_w.png
  pine_n.png pine_e.png pine_s.png pine_w.png
  ...
```

### Tune size and footing in `layout.json`

`layout.json` is optional. It changes **how** the game draws an image, not the
image file itself. A layout can set a `scale` from `0.05` to `4.0`, a simple
`offset_y` nudge in rendered pixels, and a precise `ground_y`: the source-image
Y coordinate (from the top) where the tree meets the terrain. Use a general
value, then refine a species or one facing only:

```json
{
  "scale": 0.5,
  "species": {
    "oak": {"scale": 0.42, "offset_y": -8},
    "bush": {"scale": 0.32, "ground_y": 68}
  },
  "sprites": {
    "oak_e": {"offset_y": 2}
  }
}
```

The rules merge in this order: root defaults, the species (`oak`), then an
exact sprite/view (`oak_e`). `offset_y: -8` moves a sprite eight pixels **up**;
a positive number moves it down. Omit `ground_y` to retain Golf Tycoon's normal
anchor for that species, scaled with the image. This pack's own layout uses
per-species scales and upward placement nudges because its supplied art has a
variety of canvas sizes and ground-line crops.

An unsuffixed `<species>.png` is allowed when the same drawing should answer
for every facing, but a full set of four views produces the best result. To
repaint just one species, include only that species' files; missing files fall
back to the normal seasonal/base art. If two all-season sprite packs include
the same species and view, the one lower in the Mods screen's enabled load
order wins.

Seasonal-only art still belongs in subfolders such as
`tree_art/fall/oak_n.png`; see `golf_tycoon.seasons` for that wardrobe format.
A root-level file deliberately wins over a seasonal file, so do not put both
forms of the same species in one pack unless the all-season art is meant to
win.
