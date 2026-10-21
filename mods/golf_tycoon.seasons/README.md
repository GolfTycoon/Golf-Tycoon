# Seasons (official mod)

The game's seasons, as a mod: four theme-aware seasons over the calendar
year - demand, upkeep, fee tolerance, tournament prestige, seasonal
weather weights - plus eight seasonal events.

- `season_provider.gd` holds every table and extends the game's
  `SeasonProvider`. `mod_main.gd` registers it in one line.
- `data/seasonal_events.json` declares the events; the loader applies it
  before the script runs (see `content` in `mod.json`).
- The Start New Game "Seasons" toggle decides per company whether the
  seasons act on that company's courses; disabling this mod removes them
  entirely (the game then runs the neutral built-in provider).
- That toggle is the mod's own: `mod_main.gd` adds it there with
  `api.register_feature("seasons")`, which is all it takes to put an option
  in the Features section - a section that is hidden while no mod adds one.

This is the reference for a **feature/provider mod**: copy it to make a
southern-hemisphere calendar, a monsoon climate, a two-season year...
Anything that speaks SeasonProvider can take the job; load order decides
whose seasons the game plays.
