# Modding Golf Tycoon

Golf Tycoon ships with a full mod system. Players install mods as plain
**zip files**, as **folders** in their mods library, or as **Steam
Workshop** items; they switch them on and off and order them in the
in-game **Mods screen**; and modders make them with JSON, and optionally
GDScript, against a versioned Mod API.

Everything first-party goes through the same machinery as a community mod
would - the three environment systems the game was born with (**Seasons**,
**Weather** and **Wind**) are now ordinary mods in the bundled mods
folder, enabled by default, and nine small example mods beside them cover
every kind of thing a mod can do.

- **For players:** [Using mods](#using-mods)
- **For modders:** [Making your first mod](#making-your-first-mod), then the
  references: [manifest & packaging](modding/manifest-and-packaging.md),
  [the Mod API](modding/mod-api.md), [Steam Workshop](modding/steam-workshop.md).
- **For contributors:** [How it fits together](#how-it-fits-together).

## Using mods

Open **Mods** on the main menu. The screen lists every mod the game found,
where it came from, and - most importantly - **the order enabled mods will
load in**. Enabled mods sit at the top of the list in load order; the ▲ ▼
buttons move them. When two mods change the same thing (a building's
price, a terrain's upkeep, which system drives the weather), **the mod
lower in the list wins**. The details pane names the losers whenever a
conflict was overwritten, so nothing is silently ambiguous.

Changes are written to your list (`user://mods/load_order.json`)
immediately but do not hot-swap a running game: **Apply & Reload** reloads
the scene with exactly the new set, in exactly the new order. Nothing is
ever half-applied to a course in play.

### Where mods live

The game scans these places, every launch and on **Rescan**:

| Source | Where | Notes |
| --- | --- | --- |
| Bundled | `res://mods/` inside the game | The official Seasons/Weather/Wind mods and the examples. Cannot be uninstalled. |
| Mods folder | `user://mods/` ("Open Mods Folder") | Drop mod folders or `.zip` files here. Zips found here appear as installable entries' sources. |
| Installed zips | `user://mods/installed/` | Where **Install ZIP…** unpacks a mod. Owned by the game; uninstalling deletes the folder. |
| Steam Workshop | Steam's per-game workshop folder | Subscribed items appear automatically once Steam has downloaded them (Steam builds only). |

If the same mod id turns up in two places, one copy wins: your own mods
folder (folders and installed zips) beats a loose zip there, which beats
a Workshop copy, which beats the bundled one - a modder iterating
locally always tests their own build, and players can override even a
bundled mod.

Installing never enables. A new mod always arrives switched **off** until
you tick it, so a zip from a stranger can change nothing until you've read
its details pane - which also says plainly whether the mod **runs code**
(declare `script` permission) or is **data only**. Give code-carrying mods
the same trust you would any program; GDScript mods are not sandboxed.

The three official environment mods can be switched off - the game then
falls back to built-in neutral stand-ins (perpetual clear skies, calm air,
no seasonal modifiers) and everything keeps working, including saves that
had the features "on": a feature toggle in a save is honored only while
some loaded mod actually provides it.

Those switches are mod content too. The **Game features** section of the
Start New Game screen is hidden unless a mod has added an option there (see
[Start New Game features](modding/mod-api.md#start-new-game-features)): the
Weather, Wind and Seasons mods each add theirs when they load, so a game
with no mods - or with those three switched off - shows no Features section
at all, just a shorter company setup. Any other mod can add its own switch
the same way.

### Safety rails, for players

- Script mods load behind a crash marker: if the game dies while loading
  script mods, the next launch loads data only ("safe mode") and says so
  in the Mods screen, instead of crash-looping.
- Start with `--no-mods` (Steam launch options work) to run the plain game
  with your list untouched.
- Saves record which mods and versions were loaded and each script mod's
  own save data. Loading a save made with a mod you no longer run warns
  you by name and plays on without it; content added by missing mods is
  simply absent, never half-present. To be safe, keep old saves with the
  mod set that made them.

## Making your first mod

A mod is a folder with a `mod.json` at its root. There are two ways in:

- In the game, **Mods -> Create New Mod** scaffolds a folder in your
  library (`user://mods/<id>/`): a valid `mod.json`, a starter
  `mod_main.gd` unless you untick the box, and a README with the next
  steps. The new mod appears in the list switched off, like an installed
  zip; tick it and **Apply & Reload** when you are ready.
- From a source checkout, copy `mods/_template/` (or unzip any example)
  and edit three things: the `id` (something like `yourname.my_mod` - it
  namespaces everything you add, and must never change once players have
  saves), the `name`, and the `description`.

Then pick a kind - each row is a working bundled example you can open and
copy, `mods/` directory included with the game:

| You want to… | Manifest needs | No code? | Example |
| --- | --- | --- | --- |
| Add or re-price buildings | `content.buildings` | yes | `example.buildings` |
| Add decorations | `content.decorations` | yes | `example.decorations` |
| Rebalance terrain, fees, tournaments | `content.terrain_overrides` / `tuning` / `tournament_tiers` | yes | `example.balance` |
| Repaint a course theme | `content.themes` | yes | `example.theme` |
| Add world-map locations & their golfers | `content.world_locations` / `visiting_golfers` | yes | `example.world` |
| New golfer names or a skin | `content.golfer_names` / `golfer_skins_root` | yes | `example.golfers` |
| Extra events for another mod | a `dependencies` entry + `content.seasonal_events` | yes | `example.more_seasons` |
| New gameplay rules, reacting to game events | `entry_point` + `permissions: ["script"]` | GDScript | `example.jackpot` |
| A switch under Game features on Start New Game | script + `register_feature_option` | GDScript | `golf_tycoon.weather`, `.wind`, `.seasons` |
| A widget on the HUD | script + `register_hud_widget` | GDScript | `example.hud_clock` |
| Replace weather / wind / seasons entirely | script + a provider registration | GDScript | `golf_tycoon.weather`, `.wind`, `.seasons` |

The workflow is: edit in place (inside your `user://mods/` library or a
source checkout's `mods/`), then in the game hit **Rescan**, tick your
mod, **Apply & Reload**. When it works, share it:

- **As a zip:** zip the folder's contents (`mod.json` at the zip root or
  one wrapper folder deep). From a source checkout,
  `make mod-pack MOD=path/to/folder` validates and packs it into
  `dist/mods/`; players install it from the Mods screen. The same folder
  also loads unzipped - just copy it into the mods folder.
- **Steam Workshop (deferred):** the integration remains available internally,
  but browsing and upload controls are currently hidden from the Mods screen.
  Use ZIP sharing for now. See [modding/steam-workshop.md](modding/steam-workshop.md).

Two rules keep mods healthy and shareable: never use `class_name` in a mod
(two mods could pick the same name; `preload()` your siblings by relative
path instead), and never change your mod `id`. The rest is in the
references:

- [manifest-and-packaging.md](modding/manifest-and-packaging.md) - every
  `mod.json` field, ids and namespacing, merge/patch/remove semantics,
  load-order resolution rules, zip/installed layouts, versioning, safety
  rails, the command-line tool.
- [mod-api.md](modding/mod-api.md) - the `GolfTycoonMod` lifecycle, the
  `ModAPI` surface, providers (weather/wind/seasons), value hooks, tuning
  keys, config, save data, EventBus signals, building sprites and effects.
- [steam-workshop.md](modding/steam-workshop.md) - how Workshop
  discovery/upload works, what a Steam build needs (GodotSteam + an App
  ID), and how to test without one.

## How it fits together

| Piece | File(s) | Role |
| --- | --- | --- |
| `ModManifest` | `scripts/modding/mod_manifest.gd` | Parses and validates `mod.json`; semver helpers; the Mod API version constant. |
| `ModPackage` | `scripts/modding/mod_package.gd` | Zip reading/installing/packing (static, autoload-free so the CLI can use it). |
| `ModScaffold` | `scripts/modding/mod_scaffold.gd` | Writes a new mod folder - `mod.json`, starter script, README - for the Mods screen's **Create New Mod** button (static, autoload-free). |
| `ContentRegistry` | `scripts/modding/mod_content_registry.gd` (autoload) | Owns merged content: base `data/buildings.json` + `data/decorations.json`, then each mod's declared content in load order; namespacing, deep-merge/patch semantics, provenance and conflict reporting, tuning values; pushes the result into the game's static libraries (`TerrainTypes`, `CourseTheme`, `TournamentSystem`, `WorldLocations`, `GolferAttributes`, `GolferSkinLibrary`, `BuildingSprites`). |
| `ModManager` | `scripts/modding/mod_manager.gd` (autoload) | Discovery, the player's ordered list, dependency/topological load-order resolution, safe mode, resource packs, script loading, provider registration, hooks, per-mod config and save slices. |
| `GolfTycoonMod` / `ModAPI` | `scripts/modding/mod_base.gd`, `mod_api.gd` | What a script mod extends and the object it is handed. |
| `SteamWorkshopProvider` | `scripts/modding/steam_workshop_provider.gd` | Runtime-detects the GodotSteam `Steam` singleton; subscribed roots, workshop page, async uploads. Safe no-op off Steam. |
| Neutral bases + facade | `scripts/systems/weather_system.gd`, `wind_system.gd`, `season_provider.gd`, `season_system.gd` | The game's built-in "nothing happens" weather/wind/season answers; mods provide the real systems. Same classes, same calls, so callers never know. |
| Mods screen | `scripts/ui/mods_screen.gd` | The Mods tile's screen: list = load order, details, create/install/uninstall/upload, Apply & Reload. |
| Bundled mods | `res://mods/` | Three official feature mods + nine examples + `_template`. |
| CLI | `tools/mod_tool.gd`, `make mods` / `mod-pack` / `mod-validate` | Validate and pack mods exactly as the game reads them. |

Autoload order matters: `ContentRegistry` loads base content, then
`ModManager` discovers and loads mods on top of it before anything else
reads content. Saves gain a `mods` section (API version, loaded
ids+versions in order, per-mod data) via `SaveManager`; `GameManager`'s
feature toggles are `per-save flag AND a loaded provider`.

Bundled mod folders ship in exports via the `mods/**` include filter
(alongside `data/buildings.json` / `data/decorations.json`) in
`export_presets.cfg`.

### The Mod Shed layout

The Mods screen uses a pixel-art workbench layout. Desktop and tablet widths
show the searchable loadout and selected-mod inspector side by side; widths
below 700 px use Library / Inspector tabs. Selecting a mod opens its inspector
on narrow screens. Each pane scrolls independently, and short windows can scroll
the workspace to keep installation and Apply & Reload reachable. The tool row
scrolls sideways when the window is narrower than its buttons, so **Create New
Mod**, **Install ZIP**, **Rescan**, **Mods folder**, **Disable all** and
**Apply & Reload** all stay reachable on a phone. Search only filters the
visible cards: it never changes enabled mods or their order.
