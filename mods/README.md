# Bundled mods

Everything in this folder ships with the game and is loaded by the same
mod loader players use - there is no special treatment for first-party
content beyond being enabled by default where it says so.

| Folder | What it is |
| --- | --- |
| `golf_tycoon.seasons/` | **Seasons (official).** The four theme-aware seasons, their calendar events and the woodland's seasonal tree art. On by default. |
| `golf_tycoon.weather/` | **Weather (official).** Multi-day weather spells, rain and weather lighting. On by default. |
| `golf_tycoon.wind/` | **Wind (official).** The daily breeze and what it does to a shot. On by default. |
| `example.buildings/` | Data mod: new buildings, and patching a shipped one. |
| `example.decorations/` | Data mod: new decorations. |
| `example.balance/` | Balance mod: terrain overrides, tuning values, tournament patches. |
| `example.theme/` | Theme mod: repainting a shipped course theme. |
| `example.world/` | World mod: new world-map locations and their visiting golfers. |
| `example.golfers/` | Golfer content: name pools and a golfer skin. |
| `example.more_seasons/` | Add-on mod: extra events for the Seasons mod, via a hard dependency. |
| `example.jackpot/` | Script mod: events, hooks, config and save data. |
| `example.hud_clock/` | UI mod: a HUD widget. |
| `_template/` | The starter folder for a new mod (never loaded). |

Players' own mods live in the user data folder (`user://mods/` - open it
from the Mods screen), not here; this folder is inside the game package.

The guide for players and modders is docs/modding.md (in the repository).
From a source checkout, `make mods` validates everything in this folder
and packs each mod into a shareable zip under `dist/mods/`.
