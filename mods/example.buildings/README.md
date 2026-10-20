# Example: More Facilities (a data mod)

The simplest useful mod: new entries in a data catalog, no code at all.

- `mod.json` declares one content file, `data/buildings.json`.
- The two new buildings are entered under short ids (`viewing_tower`,
  `festival_marquee`). The game namespaces them automatically, so in saves
  they are `example.buildings:viewing_tower` and can never collide with
  another mod's tower.
- `snack_bar` already exists in the shipped game, so the same entry
  *patches* it: the object is deep-merged over the shipped one and only the
  `cost` changes. Move this mod later in the load order than another mod
  that touches the Snack Bar and this price wins.
- New buildings need the fields the shipped ones have (`name`, `size`,
  `cost`, and whatever effects they use - these reuse the game's
  `food_service` and `skill_training` effects). `availability` uses the
  same rules as shipped buildings.
- `"color"` is what the built-in procedural stand-in paints the building
  until a sprite is registered (see ModAPI.register_building_sprite in
  docs/modding/mod-api.md), so a data-only building is visible immediately.

Copy this folder to `user://mods/` (the Mods screen's "Open mods folder"
button), change the id, and it is your mod.
