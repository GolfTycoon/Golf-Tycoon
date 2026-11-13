# Example: Groundskeeper's Balance Pass (a balance mod)

Three levers, all data:

- `terrain_overrides` patches fields of existing terrain types by name
  (the names in `data/terrain_types.json`). Terrain *ids* are allocated by
  the game - saves store them as numbers - so mods rebalance the shipped
  surfaces rather than minting new ids.
- `tuning` sets the dotted keys the game reads through
  ContentRegistry.get_tuning (the full list is in
  docs/modding/mod-api.md). Multiplication-friendly by design: one mod's
  0.9 and another's 1.1 compose by load order, last writer wins per key.
- `tournament_tiers` patches the shipped tournament tiers by save name
  (`local`, `regional`, `national`, `championship`).

A balance mod is the classic load-order citizen: put it after a
total-conversion mod to fine-tune that mod, or before it to be overridden.
