# Mod starters

This folder holds only the two **starter templates** a new mod begins
from — `_template/` for a script-or-data mod, `_gui_template/` for a GUI
theme. Neither is ever loaded: folders starting with `_` are skipped by
every scan. Copy one (or press **Create New Mod** on the in-game Mods
screen, which fills a copy out for you) and edit the `id`, the `name`
and the `description`.

**The game ships no mods.** What used to live here — the three official
environment mods and the fifteen examples — now lives in
[`repository/packages/`](../repository/) one level up, from where:

- `make repository` packs every package into `repository/zips/` and
  writes the catalogue `repository/official.json`,
- the **Official Repository** (the `official.json` feed on GitHub, added
  to every player's game by default) serves that catalogue, and
- the in-game **Browse Mods** screen (top-right of the Mods screen)
  downloads from it — and from any other JSON feed the player adds.

Each package carries an `icon.png` (declared in its `mod.json`) that the
Mods and Browse Mods screens show next to the mod.

| Package (under `repository/packages/`) | What it is |
| --- | --- |
| `golf_tycoon.seasons/` | **Seasons (official).** The four theme-aware seasons, their calendar events and the woodland's seasonal tree art. |
| `golf_tycoon.weather/` | **Weather (official).** Multi-day weather spells, rain and weather lighting. |
| `golf_tycoon.wind/` | **Wind (official).** The daily breeze and what it does to a shot. |
| `example.buildings/` | Data mod: new buildings, and patching a shipped one. |
| `example.decorations/` | Data mod: new decorations. |
| `example.balance/` | Balance mod: terrain overrides, tuning values, tournament patches. |
| `example.theme/` | Theme mod: repainting a shipped course theme. |
| `example.world/` | World mod: new world-map locations and their visiting golfers. |
| `example.golfers/` | Golfer content: name pools and a golfer skin. |
| `example.tree_sprites/` | Visual mod: user-created, all-season replacements for every shipped tree sprite. |
| `example.more_seasons/` | Add-on mod: extra events for the Seasons mod, via a hard dependency. |
| `example.backgrounds/` | Visual mod: two menu background pictures, three overlay patterns and an overlay setting of its own. |
| `example.jackpot/` | Script mod: events, hooks, config and save data. |
| `example.hud_clock/` | UI mod: a HUD widget. |

Players' own mods live in the user data folder (`user://mods/` - open it
from the Mods screen), not here; this folder is inside the game package.

The guide for players and modders is docs/modding.md (in the repository).
From a source checkout, `make mod-validate MOD=repository/packages/<mod>`
checks one package and `make mod-pack MOD=repository/packages/<mod>`
packs it into a shareable zip under `dist/mods/`.
