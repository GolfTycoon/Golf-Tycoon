# Wind (official mod)

The game's wind, as a mod: a daily breeze that drifts from day to day,
occasionally swings with a passing front, and bends shots downwind.

- `wind_system.gd` extends the game's neutral `WindSystem` base (dead
  calm) and overrides generation plus the shot displacement/distance
  maths; `mod_main.gd` registers a factory for it.
- The flags on the greens are core presentation reading
  `EventBus.wind_changed`, so they hang limp when this mod is off -
  simulation in the mod, display in the core.
- `mod_main.gd` also adds this mod's switch under **Game features** on the
  Start New Game screen (`api.register_feature("wind")`); the section is
  hidden while no mod puts an option there.

The smallest of the three official feature mods, and the clearest
**provider mod** reference: fork it for gusts, thermals, trade winds...
