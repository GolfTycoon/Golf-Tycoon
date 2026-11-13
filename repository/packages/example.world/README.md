# Example: Tasmania & the Alps (a world mod)

New dots on the world map, as pure data:

- `world_locations` entries name a theme and a size **by name**
  (`"links"`, `"medium"`) instead of the game's internal numbers, and a
  pin by latitude/longitude. Prices come from the usual formula (size,
  cleared land, theme multiplier, prestige). New locations are namespaced
  like all content, and become buyable the next time a world is rolled
  (a new company, or Reset World - an existing company's rolled prices
  are never disturbed mid-game).
- `visiting_golfers` maps a location to a JSON array of golfer cards in
  exactly the format `data/visiting_golfers/*.json` ships. The key names
  this mod's own location bare (`"tasmania"`); the loader resolves it to
  the namespaced in-game id. Ship 50 cards for the full effect - fewer
  just means familiar faces sooner. Keys naming shipped locations
  (`"hawaii"`) *append* to that location's pool.
