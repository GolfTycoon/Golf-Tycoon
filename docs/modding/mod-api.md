# The Mod API (script mods)

> Overview: [../modding.md](../modding.md) ·
> Manifest & packaging: [manifest-and-packaging.md](manifest-and-packaging.md) ·
> Workshop: [steam-workshop.md](steam-workshop.md)

Data mods need none of this - they are JSON the game merges (see the
manifest doc). A **script mod** declares `entry_point` plus the `script`
permission and gets a GDScript file run by the loader, a stable API
object, and the whole `EventBus` to listen to.

**Stability promise:** within one Mod API major version
(`api_version` in your manifest, `ModManifest.CURRENT_API_VERSION` -
currently **1**), the methods below keep their names and meanings;
additions happen, renames do not. A mod built for a different major API
version is listed but never loaded, so a game update can never run your
script against an API you didn't target.

## The entry point

```gdscript
extends GolfTycoonMod

func _mod_load(mod_api: ModAPI) -> void:
	mod_api.log_info("Hello from %s" % mod_id)
```

The loader instantiates your entry script (it must extend
`GolfTycoonMod`, `scripts/modding/mod_base.gd`), names it
`Mod_<your.id>`, adds it under the `ModManager` autoload, sets `mod_id`
and `api`, then calls `_mod_load(api)`.

Lifecycle, in order:

| Callback | When |
| --- | --- |
| `_mod_load(mod_api)` | Once, when the loader reaches your mod in load order. Register everything and connect signals here. |
| `_mod_new_game()` | A brand-new company started (after the world was rolled). `EventBus.new_game_started` is the same moment. |
| `_mod_save() -> Dictionary` | Every time the game saves. Return plain JSON-shaped data (`{}` for none). |
| `_mod_restore(data)` | After a save finishes loading, handed back exactly what `_mod_save` returned - `{}` for saves made without your mod. |
| `_mod_unload()` | The mod set is being reloaded or your mod switched off. The loader already drops your content, hooks, providers and widgets and frees your node right after - only tidy up things you put *outside* the mod (e.g. a node you added to the main scene). |

Hard rules for mod scripts:

- **No `class_name`** in your files. Only the base game's global classes
  are registered; two mods picking the same class name would collide.
  `preload("sibling.gd")` with **relative paths** instead - that is what
  lets the identical folder run from `res://`, `user://`, a zip install,
  or a Workshop directory unchanged.
- Never assume where you were loaded from: ask `api.mod_root()` /
  `api.path(relative)` for your own files.
- GDScript mods are **not sandboxed** - the whole engine and game are
  reachable. Prefer the API (it is what stays stable); reaching into game
  internals works today but only the API carries the stability promise.
- Content from your own `mod.json` is applied by the loader (before your
  script runs for resource packs and content), so data needs no code.

## The `ModAPI` object

One per mod, bound to your id (`scripts/modding/mod_api.gd`). Everything
you register through it is stamped with your id, which is how the loader
undoes a mod cleanly and how the Mods screen can say who provides what.

**Versions and neighbours**

- `api_version() -> int`, `game_version() -> String`
- `is_mod_loaded(other_id) -> bool`, `get_mod_version(other_id) -> String`,
  `get_load_order() -> Array` - for optional integrations ("if Seasons is
  here, use it").

**Your own files** (all mod-root-relative)

- `mod_root()`, `path(relative)`, `file_exists(relative)`
- `read_text(relative) -> String`, `read_json(relative) -> Variant`
- `load_texture(relative) -> Texture2D` - decodes a raw PNG/JPG directly;
  mods never need Godot's import pipeline (results are cached per mod).

**Logging and player messages**

- `log_info / log_warning / log_error(message)` - prefixed with your id.
- `notify(message, kind = "info")` - a toast in the game's notification
  feed (`kind`: `info`, `warning`, `error`, `success`).

**Registering things**

- `register_weather_factory(factory)` / `register_wind_factory(factory)` -
  [providers](#providers-replacing-weather-wind-or-seasons).
- `register_season_provider(provider)` - likewise.
- `add_hook(name, callable)` - [value hooks](#value-hooks).
- `register_hud_widget(factory)` - `factory()` is called when the main
  scene builds its HUD and must return a `Control`, added to the HUD
  layer; position it with anchors/offsets. Widgets are (re)created with
  each scene, so build fresh state per call (`example.hud_clock`).
- `on_main_scene_ready(callable)` - `callable(main)` runs when the main
  scene is ready, immediately if it already is. Note callbacks are
  consumed once; for every scene (re)load, connect to
  `EventBus.main_scene_ready` instead. The main node is the game's root
  scene script (`Main`) - treat its API as internal, not promised.
- `register_feature_option(option)` / `register_feature(id)` -
  [Start New Game features](#start-new-game-features): the toggles under
  **Game features** on the company setup screen. The section is hidden until
  a mod adds one.
- `register_building_sprite(building_id, relative_png, draw_rect) -> bool`
  - real art for one of your buildings (bare or namespaced id - bare ids
  resolve exactly like content ids). The rect is in the building node's
  draw space (see `BuildingSprites` and
  `assets/sprites/buildings/sprites.json` for existing buildings'
  rects). Without it, your building draws the procedural fallback in its
  data's `color`.

**Content and config**

- `get_content_registry()` - the merged `ContentRegistry` autoload:
  `get_buildings()`/`get_building(id)`/`has_building(id)`,
  `get_decorations()`/`get_decoration(id)`/`has_decoration(id)`,
  `get_tuning(key, default)`/`has_tuning(key)`,
  `source_of(kind, id)` (provenance), `get_conflicts()`,
  `get_warnings()`, `get_content_summary()`, `resolve_new_id(mod_id, raw)`.
  It's how a script mod reads "what the player is actually playing with"
  after every mod's data merged.
- `get_tuning(key, default) -> float` - shortcut for the registry.
- `get_config_value(key, fallback)` / `set_config_value(key, value)` -
  your per-player settings. Defaults come from the manifest's `config`
  schema (`{type, default, description}` per key); values persist in
  `user://mods/config/<mod id>.json`, survive save/load, and never travel
  in save files. Per-save state belongs in `_mod_save`/`_mod_restore`.

## Start New Game features

The **Game features** section of the Start New Game screen (the company
setup shown after *Start New Game*) lists the optional systems a company can
switch on for its world. It is not part of the base game: **the section is
hidden while no mod has added an option to it**, and the first registration
is what makes it appear. A game running no mods (or `--no-mods`) therefore
has no Features section at all, and the screen's other choices are unchanged.

The three official environment mods add the shipped switches - that is all
they do for the screen:

```gdscript
func _mod_load(mod_api: ModAPI) -> void:
	mod_api.register_feature("weather")   # the game's own title, caption and icon
```

A shipped id (`"weather"`, `"wind"`, `"seasons"`) registered bare takes the
game's wording. For your own option, give it all of its copy:

```gdscript
mod_api.register_feature_option({
	"id": "night_play",              # required, stable: it is the save's key
	"title": "Night play",
	"caption": "Floodlit rounds",
	"tooltip": "The course stays open after dark.",
	"glyph": SetupGlyph.Kind.WEATHER,  # optional: the switch's icon
})
```

- Options appear in the order they are registered (shipped features first),
  and a later mod replacing an id replaces that option. Registration order is
  load order.
- The choice reaches your mod through the game's game-start path: the
  company's flags land in `GameManager` (`weather_enabled` and friends for
  the shipped ids), and the same options dictionary - `features` keyed by
  your id, `true`/`false` - is what `WorldMap.new_world` stores for the
  company and what a save carries. Read yours with
  `WorldMap.features.get("night_play", false)` or keep your own flag from
  `_mod_new_game()`.
- A flag is only a request: nothing in the game is wired to your key until
  your mod reads it (the shipped features pair theirs with a provider, so
  `GameManager.is_feature_enabled` asks for the per-save flag *and* a loaded
  provider - that is what lets a save keep working when the mod that
  provided a feature is switched off).

## Providers: replacing weather, wind or seasons

Three game systems sit behind stable facades and are *provided* by
whichever loaded mod last registered them (load order decides):

| System | Register | Contract | Fallback with no provider |
| --- | --- | --- | --- |
| Weather | `register_weather_factory(factory)` | `factory()` → a `WeatherSystem` instance (subclass the base, override the daily generation/modifiers) | The neutral base: always `WeatherType.SUNNY`, every modifier 1.0, no rain, neutral light. |
| Wind | `register_wind_factory(factory)` | `factory()` → a `WindSystem` instance | The neutral base: calm, zero displacement. |
| Seasons | `register_season_provider(provider)` | a `SeasonProvider` object; `SeasonSystem` (the facade callers use) delegates its tables to it | The neutral provider: no seasonal modifiers, neutral weights, summer visuals all year. |

The bundled `golf_tycoon.weather` / `golf_tycoon.wind` /
`golf_tycoon.seasons` are the canonical implementations - copy one and
change the numbers. Points of the contract worth knowing:

- The vocabulary lives in the **core** classes and stays fixed:
  `WeatherSystem.WeatherType` (SUNNY, PARTLY_CLOUDY, CLOUDY, LIGHT_RAIN, RAIN,
  HEAVY_RAIN), wind directions/strengths, season and theme ids are
  **plain ints** across the provider boundary (`SeasonProvider` methods
  take and return ints/floats/arrays only), so mods never couple to enums
  inside another mod.
- Weather/wind systems are per-scene nodes created by the main scene via
  `ModManager.create_weather_system()` / `create_wind_system()`; a factory
  returning the wrong type falls back to the neutral base with a warning.
  They listen to `EventBus.day_changed` (the bases do this for you) and
  report through `EventBus.weather_changed(weather_type, intensity)` /
  `wind_changed(direction, speed)` (call `_emit_weather_changed()` /
  `_emit_wind_changed()`).
- `SeasonSystem` keeps the old call signatures (`get_season(day)`,
  `get_spawn_modifier(...)`, `get_maintenance_modifier(...)`, blended
  variants, fee/prestige modifiers) including its quirks - notably the
  unblended `get_spawn_modifier` ignores the per-save `disabled` flag
  while the blended/fee/prestige ones honor it. Provider authors extend
  `SeasonProvider`'s tables (`season_for_month`,
  `season_start_months`, `spawn_modifier`, `maintenance_modifier`,
  `tournament_prestige`, `theme_weather_modifiers`, `weather_weights`)
  rather than replacing the facade.
- Seasonal **events** are data (`content.seasonal_events`), registered
  into `SeasonalEvents` by id; record fields are `id`, `name`,
  `description`, `season` (name string), `day_in_season`,
  `duration_days`, `revenue_modifier`, `spawn_modifier`,
  `reputation_bonus`. An event with an existing full id replaces that
  record whole; a new bare id is namespaced.
- Whether a provider exists is visible everywhere the game cares:
  `GameManager.feature_available("seasons"|"weather"|"wind")`, and the
  effective on/off is `GameManager.is_feature_enabled(...)` = per-save
  flag **AND** a provider is loaded - so disabling the mod cleanly
  disables the feature in existing saves without editing them.

## Value hooks

A hook is a named chain the game pushes a number through, in load order,
at a specific point in the simulation. Your callable receives
`(value: float, context: Dictionary)` and returns the new value; a return
that isn't a number is ignored (the value passes through unchanged), so a
typo can't void the chain.

| Hook | Where | Value in | `context` keys |
| --- | --- | --- | --- |
| `golfer_spawn_rate` | `GolferManager.get_spawn_rate_modifier()`, after all built-in multipliers and the `golfers.spawn_multiplier` tuning | The golfer-arrival modifier | `day`, `theme`, `holes` (open holes) |
| `green_fee_per_hole` | `GameManager.process_green_fee_payment()`, after fee bonus and the `economy.green_fee_multiplier` tuning | Dollars charged per hole (then rounded, clamped ≥ 0, × holes) | `day`, `holes`, `golfer_name` |
| `terrain_maintenance_cost` | Daily statistics, after the seasonal modifier and the `economy.maintenance_multiplier` tuning | The day's terrain upkeep in dollars | `day`, `terrain_cost` (untuned base), `season` (int) |

Hooks run where they sit in the chain - if you need "after every other
mod", that is what load order is for; tell your users in the README.
(`example.jackpot` uses `golfer_spawn_rate` after hole-in-one jackpots.)

### Tuning keys

Flat dotted numbers any mod can set declaratively via `content.tuning`
(later in load order wins per key). The game itself reads, all defaulting
to `1.0` so no tuning = the shipped game:

| Key | Scales |
| --- | --- |
| `golfers.spawn_multiplier` | Golfer arrival rate (before hooks). |
| `economy.green_fee_multiplier` | Every green fee (before the hook). |
| `economy.maintenance_multiplier` | Daily terrain upkeep (before the hook). |
| `reputation.decay_multiplier` | How fast reputation drifts back down. |

Your own keys are just as legal - read them with
`ContentRegistry.get_tuning("your.key", default)` / `api.get_tuning(...)`.

## Listening to the game: EventBus

The `EventBus` autoload is the game's signal hub; mods connect exactly
like game systems do (`EventBus.day_changed.connect(_on_day)`), and
disconnect in `_mod_unload` any connection whose target would outlive the
mod node. (Connections to methods on your own mod node die with it.) The
signals mods most often want:

- **Time:** `day_changed(new_day)`, `end_of_day(day_number)`,
  `year_ended(finished_year)`, `game_speed_changed`, `pause_toggled`.
- **Money & reputation:** `money_changed(old, new)`,
  `reputation_changed(old, new)`, `green_fee_paid(golfer_id,
  golfer_name, amount)`, `transaction_completed(description, amount)`.
- **Golfers:** `golfer_spawned`, `golfer_started_hole`,
  `golfer_finished_hole(golfer_id, hole_number, strokes, par)`,
  `golfer_finished_round` / `golfer_completed_round`,
  `golfer_left_course`, `golfer_attitude_changed`, `golfer_thought`.
- **Building:** `building_placed(building_type, position)`,
  `building_removed`, `building_upgraded`, `decoration_placed`,
  `decoration_removed`, `terrain_tile_changed`, `hole_created`,
  `hole_toggled`, …
- **Environment:** `weather_changed(weather_type, intensity)`,
  `wind_changed(direction, speed)`, `season_changed(old, new)`,
  `seasonal_event_upcoming`, `theme_changed`.
- **Tournaments:** `tournament_scheduled`, `tournament_started`,
  `tournament_completed(tier, results)`, and friends.
- **Modding itself:** `mods_loaded(load_order)`, `mod_loaded(mod_id)`,
  `mod_failed(mod_id, message)`, `main_scene_ready(main_node)`.

The full list is the top of `scripts/autoload/event_bus.gd`; unlike the
`ModAPI` methods, individual game signals aren't individually versioned -
they change only with the systems that emit them, in step with Mod API
major bumps.

## Save data

Every save carries a `mods` section:
`{api_version, load_order: [{id, version}…], data: {mod_id: slice}}`.
Your slice is exactly your `_mod_save()` return (empty dictionaries are
not stored). On load, `ModManager.apply_save_data` hands each loaded mod
its slice via `_mod_restore`; mods present in the save but not loaded are
named in a `warning` toast, and their content is simply absent from the
course - so write restores defensively (missing keys = fresh state).
Because a player may re-enable your mod later on an old save, treat `{}`
as "start clean", not as an error.

State split to remember: **config** (player preferences, follows the
player) ≠ **save data** (course state, follows the save).
