# Weather (official mod)

The game's weather, as a mod: multi-day spells of sun, cloud and rain
that change turnout, shot accuracy, light and the on-screen rain.

- `weather_system.gd` extends the game's neutral `WeatherSystem` base and
  overrides its generation and modifiers; `mod_main.gd` registers a
  factory for it. The main scene asks the ModManager for a weather system
  and gets this - or the permanently-sunny base when the mod is off.
- `weather_tint_system.gd` and `rain_overlay.gd` are the visuals. The mod
  adds them to the main scene on `EventBus.main_scene_ready`, and tidies
  them away again in `_mod_unload` - the pattern for any per-scene nodes.
- The dependency on Seasons is *optional*: with Seasons loaded, rolls
  follow the time of year (and the course theme); without it, a flat
  year-round profile is used.
- `mod_main.gd` also adds this mod's switch under **Game features** on the
  Start New Game screen (`api.register_feature("weather")`); that section is
  hidden while no mod puts an option there.

Reference for a **feature/provider mod with visuals**. Fork it for
snow, fog, heatwaves - anything that speaks WeatherSystem can take over.
