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
Seasons is disabled. The files are intentionally kept at their supplied sizes;
the overlay anchors them on the species' established ground point.

## Make it yours

Copy this folder into `user://mods/` (open it from **Mods**) and change the
`id`, `name`, `author` and `description` in `mod.json` before sharing it. Keep
the filename pattern:

```text
tree_art/
  oak_n.png  oak_e.png  oak_s.png  oak_w.png
  pine_n.png pine_e.png pine_s.png pine_w.png
  ...
```

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
