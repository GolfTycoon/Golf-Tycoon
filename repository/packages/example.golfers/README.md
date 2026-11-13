# Example: New Faces (a golfer-content mod)

Two cosmetics in one mod:

- `golfer_names` widens the pools random golfers are rolled from -
  professions and first/last names are *added* to the game's lists (in
  load order), never replaced, so several name mods mix happily.
- `golfer_skins_root` points at a folder of skins in the exact format the
  game ships under `data/golfer_skins/` (see docs/golfer-skins.md). This
  one is a single `skin.txt` re-colouring the shipped Casual sprites;
  a skin with painted `layers/` works too. Skin ids are *not* namespaced
  (they name folders and player preferences), so pick ids nobody else
  will - later mods in the load order win an id clash, and the player's
  own edited skins in `user://golfer_skins/` win over every mod.
