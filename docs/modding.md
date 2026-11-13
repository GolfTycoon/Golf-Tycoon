# Modding Golf Tycoon

Golf Tycoon ships with a full mod system. Players install mods as plain
**zip files**, as **folders** in their mods library, or as **Steam
Workshop** items; they switch them on and off and order them in the
in-game **Mods screen**; and modders make them with JSON, and optionally
GDScript, against a versioned Mod API.

Everything first-party goes through the same machinery as a community mod
would - the three environment systems the game was born with (**Seasons**,
**Weather** and **Wind**) are ordinary mods, and fifteen example mods
beside them cover every kind of thing a mod can do — including four that
do nothing but re-dress the interface (see [GUI themes](modding/gui-themes.md)).
The game itself ships **without any of them**: you download what you want
from the **Browse Mods** screen, whose **Official Repository** — a JSON
feed published on GitHub — is set up out of the box, and which accepts
any self-hosted feed you add.

- **For players:** [Using mods](#using-mods)
- **For modders:** [Making your first mod](#making-your-first-mod), then the
  references: [manifest & packaging](modding/manifest-and-packaging.md),
  [the Mod API](modding/mod-api.md), [GUI themes](modding/gui-themes.md),
  [Steam Workshop](modding/steam-workshop.md).
- **For contributors:** [How it fits together](#how-it-fits-together).

## Using mods

Open **Mods** on the main menu. The screen lists every mod the game found,
where it came from, and - most importantly - **the order enabled mods will
load in**.

### Browse Mods

The game installs with an **empty library**: nothing ships inside the
package, so the Mods screen starts bare. Press the **Browse Mods** button
in its top-right corner to open the catalogue.

The catalogue lists **repositories** — JSON feeds, each a card naming its
address — and under each, the mods the feed offers: one row per mod. The
row's card carries the mod's icon, its name and the version on offer, and
underneath where it stands in your library (not installed, installed, or
installed with a newer version available); hovering it shows the
description and author. Beside the card is a **Download** button (or
**Installed** once it is in your library, and **Update** when the feed
offers a newer version than you have). Long names wrap inside the card,
and on a phone held upright the button moves under the card so the name
keeps the full width. Downloading fetches the mod's zip,
installs it into your library and leaves it **switched off**, exactly like
**Install ZIP…** would - nothing loads until you tick it on the Mods
screen, and while a download runs, a status line reports its progress; the
screen takes one download at a time.

Out of the box one repository is on the list: the **Official Repository**,
a feed at `raw.githubusercontent.com/GolfTycoon/Golf-Tycoon` that carries
the three official environment mods and the fifteen examples. Press
**Add Repository** to add your own feed (a URL to a JSON file in the feed
format - self-host it anywhere a plain GET can reach), and **Remove** to
take any repository off the list, Official one included; a **Restore
Official Repository** button brings it back.

### The library

Every mod has a place in the list, enabled or not, and **the list is the
load order**: the enabled mods load from the top of the list down, and
each shows its place as the number in front of its name (`1.` loads
first). Drag any mod (by its row or its `⋮⋮` grip handle) up or down the
list to reorder it, or press ▲ ▼ to nudge it one row at a time; on a
touchscreen, drag the grip handle to reorder while swiping anywhere else
on the list keeps scrolling it, and on a keyboard or a controller the
arrow you pressed stays selected as its row moves, so pressing it again
moves the same mod another row. Pressing Esc or right-clicking mid-drag
puts the mod back where it started. When two mods change
the same thing (a building's price, a terrain's upkeep, which system
drives the weather), **the mod lower in the list wins**. The details pane
names the losers whenever a conflict was overwritten, so nothing is
silently ambiguous. Each row's mod button carries the mod's own icon image
inside it (a large copy heads its field notes too), so a shelf of mods
tells at a glance which is which; a mod that ships no icon wears the
default mark.

Ticking a mod on or off never moves its row: a mod you switch on loads
where it already stands, after the enabled mods above it. The list starts
out in the order your game first found each mod (mods found in the same
scan - a batch of downloads, say - go in by name),
and from then on the order is yours. A mod you have not had before joins
the bottom of the list, whether you installed it from a zip, created it,
or dropped it into the mods folder. A mod you take out of the mods folder
(or uninstall) and later put back returns to the place it had, because
the game keeps a place for every mod it has listed
(`user://mods/library_order.json`).

To find a mod, type in the search box (it matches names, ids and
descriptions) or pick a filter: **All**, **Enabled** or **Disabled**. The
two combine, and neither changes what is enabled or the order. While rows
are hidden, dragging or pressing ▲ ▼ moves a mod past the rows you can
see, so under **Enabled** each slot is one place in the load order. A mod
you tick or untick while a filter is on stays listed until you pick a
filter again, so its row never vanishes from under the pointer.

Changes are written to your lists (`user://mods/load_order.json` for what
is enabled, `user://mods/library_order.json` for the order of the whole
library) immediately, and they take effect the moment you leave the
screen: **Back** (or Esc, or the header's Back) re-runs the loader and
reloads the scene with exactly the new set, in exactly the new order.
There is no Apply button to press and nothing to forget - and leaving
without changing anything reloads nothing. Because the change lands in one
go on the way out, nothing is ever half-applied to a course in play.

### Where mods live

The game scans these places, every launch and on **Rescan**:

| Source | Where | Notes |
| --- | --- | --- |
| Mods folder | `user://mods/` ("Open Mods Folder") | Drop mod folders or `.zip` files here. Zips found here appear as installable entries' sources. |
| Installed zips | `user://mods/installed/` | Where **Install ZIP…** unpacks a mod — and where **Browse Mods** downloads land. Owned by the game; uninstalling deletes the folder. |
| Steam Workshop | Steam's per-game workshop folder | Subscribed items appear automatically once Steam has downloaded them (Steam builds only). |

There is no fourth place: the game package carries **no mods at all** -
everything first-party arrives through the Official Repository like any
community feed would.

If the same mod id turns up in two places, one copy wins: your own mods
folder (folders and installed zips) beats a loose zip there, which beats
a Workshop copy - a modder iterating
locally always tests their own build.

Installing never enables. A new mod always arrives switched **off** until
you tick it, so a zip from a stranger can change nothing until you've read
its details pane - which also says plainly whether the mod **runs code**
(declare `script` permission) or is **data only**. Give code-carrying mods
the same trust you would any program; GDScript mods are not sandboxed.

The three official environment mods can be switched off - the game then
falls back to built-in neutral stand-ins (perpetual clear skies, calm air,
no seasonal modifiers) and everything keeps working, including saves that
had the features "on": a feature toggle in a save is honored only while
some loaded mod actually provides it. Until you download them from the
Browse Mods screen the stand-ins are all there is - the plain game runs
whole on them.

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
  `mod_main.gd` unless you untick the box, a placeholder `icon.png`, and a
  README with the next steps. The new mod appears in the list switched
  off, like an installed zip; tick it, then leave the screen, when you are
  ready.
- From a source checkout, copy `mods/_template/` (or any package under
  `repository/packages/`)
  and edit three things: the `id` (something like `yourname.my_mod` - it
  namespaces everything you add, and must never change once players have
  saves), the `name`, and the `description`.

Every mod carries an `icon` - the picture the Mods screen shows in its
list row and at the head of its field notes (the official and example
mods each ship one, a square PNG next to `mod.json`). Point the manifest's `icon` field
at your own image (PNG, JPG, WebP or BMP); a mod without one, or with a
picture that will not read, gets the shared default mark instead.

Then pick a kind - each row is a working example you can open and copy:
download it from the Browse Mods screen (it lands in your mods library),
or read it in a source checkout under `repository/packages/`:

| You want to… | Manifest needs | No code? | Example |
| --- | --- | --- | --- |
| Add or re-price buildings | `content.buildings` | yes | `example.buildings` |
| Add decorations | `content.decorations` | yes | `example.decorations` |
| Rebalance terrain, fees, tournaments | `content.terrain_overrides` / `tuning` / `tournament_tiers` | yes | `example.balance` |
| Repaint a course theme | `content.themes` | yes | `example.theme` |
| Add world-map locations & their golfers | `content.world_locations` / `visiting_golfers` | yes | `example.world` |
| New golfer names or a skin | `content.golfer_names` / `golfer_skins_root` | yes | `example.golfers` |
| A new menu picture or overlay pattern | `content.menu_backdrops` / `menu_overlays` | yes | `example.backgrounds` |
| Replace every tree sprite, all year | `content.tree_art_root` with root-level sprites | yes | `example.tree_sprites` |
| Seasonal tree art for a woodland | `content.tree_art_root` with `<season>/` folders | yes | `golf_tycoon.seasons` |
| Extra events for another mod | a `dependencies` entry + `content.seasonal_events` | yes | `example.more_seasons` |
| New gameplay rules, reacting to game events | `entry_point` + `permissions: ["script"]` | GDScript | `example.jackpot` |
| A switch under Game features on Start New Game | script + `register_feature_option` | GDScript | `golf_tycoon.weather`, `.wind`, `.seasons` |
| A widget on the HUD | script + `register_hud_widget` | GDScript | `example.hud_clock` |
| Replace weather / wind / seasons entirely | script + a provider registration | GDScript | `golf_tycoon.weather`, `.wind`, `.seasons` |

The workflow is: edit in place (inside your `user://mods/` library, or a
source checkout's `repository/packages/` for the shipped examples), then
in the game hit **Rescan**, tick your mod, and leave the screen - the game
comes back with it loaded. When it works, share it:

- **As a zip:** zip the folder's contents (`mod.json` at the zip root or
  one wrapper folder deep). From a source checkout,
  `make mod-pack MOD=path/to/folder` validates and packs it into
  `dist/mods/`; players install it from the Mods screen. The same folder
  also loads unzipped - just copy it into the mods folder.
- **In a feed:** host the zip anywhere and list the mod in a feed JSON
  (the Official Repository's `repository/official.json` is the worked
  example); players add your feed's URL on the Browse Mods screen and
  download from there like any other catalogue entry.
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
- [gui-themes.md](modding/gui-themes.md) - re-dressing the whole interface
  (HUD, menus, panels, popups, the bottom bar) with one JSON palette:
  every colour role and metric, shipped fonts, targeted rules for one
  screen or a single button, the derivation rules and what a theme
  cannot reach.
- [steam-workshop.md](modding/steam-workshop.md) - how Workshop
  discovery/upload works, what a Steam build needs (GodotSteam + an App
  ID), and how to test without one.

## How it fits together

| Piece | File(s) | Role |
| --- | --- | --- |
| `ModManifest` | `scripts/modding/mod_manifest.gd` | Parses and validates `mod.json`; semver helpers; the Mod API version constant. |
| `ModPackage` | `scripts/modding/mod_package.gd` | Zip reading/installing/packing (static, autoload-free so the CLI can use it). |
| `ModScaffold` | `scripts/modding/mod_scaffold.gd` | Writes a new mod folder - `mod.json`, starter script, README - for the Mods screen's **Create New Mod** button (static, autoload-free). |
| `ContentRegistry` | `scripts/modding/mod_content_registry.gd` (autoload) | Owns merged content: base `data/buildings.json` + `data/decorations.json`, then each mod's declared content in load order; namespacing, deep-merge/patch semantics, provenance and conflict reporting, tuning values; pushes the result into the game's static libraries (`TerrainTypes`, `CourseTheme`, `TournamentSystem`, `WorldLocations`, `GolferAttributes`, `GolferSkinLibrary`, `BuildingSprites`, `TreeOverlay`). |
| `ModManager` | `scripts/modding/mod_manager.gd` (autoload) | Discovery, the player's ordered list (a place for every mod; the enabled ones load in that order), dependency/topological load-order resolution, safe mode, resource packs, script loading, provider registration, hooks, per-mod config and save slices. |
| `GolfTycoonMod` / `ModAPI` | `scripts/modding/mod_base.gd`, `mod_api.gd` | What a script mod extends and the object it is handed. |
| `SteamWorkshopProvider` | `scripts/modding/steam_workshop_provider.gd` | Runtime-detects the GodotSteam `Steam` singleton; subscribed roots, workshop page, async uploads. Safe no-op off Steam. |
| Neutral bases + facade | `scripts/systems/weather_system.gd`, `wind_system.gd`, `season_provider.gd`, `season_system.gd` | The game's built-in "nothing happens" weather/wind/season answers; mods provide the real systems. Same classes, same calls, so callers never know. |
| Mods screen | `scripts/ui/mods_screen.gd` | The Mods tile's screen: list = load order with a row for every mod, search and All / Enabled / Disabled filters, details, create/install/uninstall/upload. Leaving the screen applies a changed loadout (`ModManager.apply_staged_changes()`), so there is no Apply button. A **Browse Mods** button in the top-right corner opens the catalogue. |
| Browse Mods screen | `scripts/ui/browse_mods_screen.gd`, `add_repository_dialog.gd` | The catalogue: one card per repository feed, one row per offered mod (icon, name, version, library state, Download / Installed / Update); feeds are added, removed and restored here. |
| `GuiTheme` / `GuiThemeApplier` | `scripts/ui/gui_theme.gd`, `gui_theme_applier.gd` | The design a GUI theme mod declared: role palette + metrics, the built `Theme`, and the walker that re-maps code-built styles onto it. No mod in force = the stock look, untouched. |
| Repository feed / store / downloader | `scripts/modding/mod_repository_feed.gd`, `mod_repository_store.gd`, `mod_repository_downloader.gd` | The catalogue's plumbing: the feed JSON format; the player's repository list (`user://mods/repositories.json`, the Official one seeded); fetching a feed entry's zip into the library. |
| Official Repository content | `repository/official.json`, `repository/packages/`, `repository/zips/` | The feed the game ships pointing at: the catalogue of official + example mods, regenerated by `make repository`. Fetched from GitHub at runtime; nothing here ships inside the game package. |
| CLI | `tools/mod_tool.gd`, `make repository` / `mod-pack` / `mod-validate` | Validate and pack mods exactly as the game reads them; rebuild the repository catalogue. |

Autoload order matters: `ContentRegistry` loads base content, then
`ModManager` discovers and loads mods on top of it before anything else
reads content. Saves gain a `mods` section (API version, loaded
ids+versions in order, per-mod data) via `SaveManager`; `GameManager`'s
feature toggles are `per-save flag AND a loaded provider`.

Exports carry no mods: the `mods/**` include filter is gone from
`export_presets.cfg`, and players fill their libraries from the Official
Repository (GitHub) and their own feeds.

### The Mod Shed layout

The Mods screen uses a pixel-art workbench layout. Desktop and tablet widths
show the searchable loadout and selected-mod inspector side by side; widths
below 700 px use Library / Inspector tabs. The **Browse Mods** button sits
in the top-right corner of the header, beside the title, on every window
shape. Selecting a mod opens its inspector
on narrow screens. Each pane scrolls independently, and short windows can scroll
the workspace to keep installation reachable. The tool row scrolls sideways
when the window is narrower than its buttons, so **Create New Mod**, **Install
ZIP**, **Rescan**, **Mods folder** and **Disable all** all stay reachable on a
phone.

The rows come from `ModManager.get_all_mod_infos()`, in the player's order
(`ModManager.get_listed_order()`). `ModManager` keeps that order in
`user://mods/library_order.json` (`{"version": 1, "mods": [ids, top of the
list first]}`): every `discover()` adds the ids it has not listed before to
the end (`_update_listed_order()`), ordering mods met in the same scan by name
(`ModManager.listed_before()`), and never takes an id out, which is what lets
a mod that went missing come back to its place. A missing or unreadable file
starts the order over, and a run of the command-line mod tool, which is not
the game, records nothing. `ModManager.move_mod()` moves a mod up or down the
list, enabled or not.

The enabled list in `load_order.json` is always the enabled mods in the order
that list has them (`ModManager.arranged_like()`): a mod switched on is
slotted in where it stands, and a move past another enabled mod swaps the two
in the load order. If the file says otherwise when it is read - it was
written before the list was kept, or edited by hand - the file wins, and the
enabled mods trade places in the list to match it.

On the screen a tick only repaints its row, and dragging a row (or its
`DragHandle` grip) or pressing ▲ ▼ moves the row in place:
`ModsScreen._sync_rows()` keeps every mod's row and puts the rows in order, so
the focused control is still the same one afterwards, and the list scrolls to
keep a moved row on show (`_scroll_to_row()`, plus edge auto-scrolling while a
dragged row is held near the top or bottom of the list). Both drags and arrows
move a mod past the rows on show (`target_slot_for_drag()` / `_on_row_moved()`),
so the arrows greyed out are the up arrow of the first row on show and the down
arrow of the last (`_update_move_buttons()`), and grip handles dim when fewer
than two rows are shown. `DragHandle` skips keyboard focus (`FOCUS_NONE`) and
joins `"native_touch_input"` so touch drags on the grip reorder rows while
swiping on the row body continues to scroll the list.

On a keyboard or a controller the arrow that was pressed keeps the focus as
its row moves, so pressing it again moves the same mod another place. It
keeps the focus when it greys out at the end of the rows on show as well:
pressing it again does nothing, rather than the focus jumping to a button
that does something else. Rows that swap leave the screen measuring exactly
as it did, and its measurements are all `InputManager` looks at to tell
whether its D-pad graph is out of date, so `_sync_rows()` calls
`InputManager.invalidate_focus_graph()` when a row changes places: Up and
Down then step through the rows as they now stand, from a greyed-out arrow
too.

The search box and the **All / Enabled / Disabled** chips (`ModsScreen.Filter`)
only hide rows: they never change enabled mods or the order. The chips share
the search box's row on desktop and on a phone held sideways (where they read
All / On / Off to leave the box room to type), and take a row of their own
under it on tablets and portrait phones. The list follows the controls directly,
and an empty list says why (`ModsScreen.empty_text()`).
A row ticked or unticked under a filter stays listed until a filter is picked
again, and a newly created or installed mod clears a filter or search that
would hide it.
