# HD Building Art (official)

The high-resolution option for Golf Tycoon's buildings.

The game ships 1:1 pixel art: one PNG pixel per world pixel, one image for each
of the 24 fifteen-degree view steps of every facility and upgrade tier. That is
the smaller, faster default. This pack supplies the **same 24 views at 2.5
pixels per world pixel** - the density the game used before the 24-facing
rework - so roofs, window frames and paving keep their finer detail on a large
screen.

- `art/sprites.json` is the same manifest the game's own art uses:
  `buildings -> kind -> tiers -> tier -> facings`, one `{file, rect}` per view.
- `mod_main.gd` walks that manifest and calls
  `ModAPI.register_building_sprite_frame(kind, png, rect, facing, tier)`.
  The API decodes a PNG only when that view is first drawn, resized to the
  manifest rectangle, so the pack does not hold 432 full-size textures.
- Turn it off in the Mods screen to return to the shipped art immediately.

The rects are in world pixels, identical to the shipped art's rects; the larger
PNG dimensions are fitted into them at load time (see `BuildingSprites`).
