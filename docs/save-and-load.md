# Save & Load

> Saves are JSON files under `user://`. A save holds the whole company and the active course. Golfers are not stored, and they arrive again after loading.

**Source:** `scripts/autoload/save_manager.gd` (`SAVE_DIR`, `SETTINGS_PATH`, `SAVE_VERSION`, `SITE_STATE_KEYS`, `SNAPSHOT_COMPANY_KEYS`, `build_location_snapshot()`, autosave), `scripts/autoload/game_manager.gd` (`AUTOSAVE_INTERVAL_DAYS`), `scripts/systems/player_data_store.gd` (the catalogue of on-device data the Settings screen deletes)
**Tests:** `tests/unit/test_save_manager.gd`, `tests/unit/test_save_load_validation.gd`, `tests/unit/ui_and_controls/test_player_data_store.gd`, `tests/integration/world_map_flow.gd`, `tests/integration/ui_and_controls/test_save_and_settings_screens.gd`

---

## Where Files Go

| File | Path | Contents |
| --- | --- | --- |
| Saves | `user://saves/*.save` | One JSON file per save slot |
| Autosave | `user://saves/autosave.save` | Written automatically |
| Settings | `user://settings.cfg` | Display, audio, gameplay and rebindable control settings, the tutorial flag, and the achievement unlocks that stay with the player between saves |
| Benchmark shelf | `user://benchmark_history.json` | The last twelve device benchmark runs and their reports (see [Device Benchmark](development/benchmark.md)) |
| Diagnostic snapshot | `user://economic_snapshots.json` | Optional day-by-day economy log, written only while `economic_snapshots_enabled` is on |
| Custom golfer skins | `user://golfer_skins/` | Skins painted in the studio (see [Golfer Skins](golfer-skins.md)) |

`user://` is Godot's per-user data folder. Its location depends on your operating system.

## Deleting Player Data

**Settings → Data** lists what this device holds, group by group, with the delete
action beside each one and a single **Delete All Player Data** button at the end.
`PlayerDataStore` is the catalogue behind it; every group names the file the
game already writes, so nothing is guessed at:

| Group | Removes | Leaves alone |
| --- | --- | --- |
| Saved courses | Every `*.save` file in `user://saves/` - the autosave and all checkpoints | Preferences, career records, reports, custom skins |
| Preferences | The `audio`, `display`, `controls`, `camera`, `gameplay` and `graphics` sections of `user://settings.cfg` | Saved courses, achievements, the tutorial flag |
| Career records | The `achievements` and `tutorial` sections of `user://settings.cfg` | Saved courses, preferences |
| Benchmark reports | `user://benchmark_history.json` and the diagnostic snapshot | Everything else |
| Custom golfer skins | The `user://golfer_skins/` folder | Shipped skins, saved courses |

Every deletion opens a confirm card first, with **Keep it** focused as the safe
answer. Once deleted, the running game follows the change at once: preferences
return to the shipped mixer, graphics, display, control and camera defaults
(UI scale and VSync included), the career shelf empties, the benchmark card
forgets the last run, custom skins unload and a golfer wearing one falls back to
a shipped skin, and the title screen's Continue card is rebuilt from the save
list that is left.

Deleting the **saved courses** during a pause session would leave the running
course with nowhere to autosave, so the confirm card says the course will close:
confirming ends the pause session and returns to the title screen instead of
quietly writing a new autosave over the files that were just deleted. Deleting
preferences, career records, reports or skins alone leaves the course open.

Mods are not one of the groups. A loaded mod cannot be removed while it runs, so
the Mods screen keeps ownership of uninstalling them; the Data page says so.

`erase_all()` leaves the device in the state a first launch starts from: no
settings file (the game writes a fresh one the next time a preference changes),
no saves, no reports, no custom skins.

## When Saves Happen

- **Quick save:** `Ctrl+S`.
- **Save menu:** Pause menu, then Save, which uses named slots. The archive lists each save with its course, day, balance and hole count. Saving over an existing name asks first.
- **Autosave:** every 30 game days, and at the end of each year.

## Loading

- **Continue** (main menu): plays the newest save without opening the archive, and takes the player onto that course. A save that will not come back — deleted while the menu was up, or written by a version this build cannot read — leaves the title screen standing and says why.
- **Load Game** (main menu) or **Pause menu → Load**: the archive, where any slot can be picked.
- The archive lists saves newest first, and the title screen's Continue card plays whichever is on top. The stamp inside a save is only good to the second, so two written within one second — a year-end autosave landing beside a manual save — are ordered by the file's own modified time, then by slot name. The newest save is always the same save.

## What Is Saved

| Area | Saved |
| --- | --- |
| Company | Money, reputation, calendar, the Course Location and World Milestones earned in this save, the unlimited-money flag, owned locations and unlocked land |
| Active site | Terrain tiles, the walking trails laid on them (`walking_paths`), elevation, cups waiting for holes |
| Entities | Buildings (including their original foundation terrain and vertex heights), decorations, path furniture; legacy tree entities are migrated |
| Holes | Tee and cup positions, par, yardage, and the order they are played in (the saved list *is* the round) |
| Course Aura | Where golfers spoke up: the newest comments kept, each with its cell, sentiment, trigger, hole and day |

The stroke index is not saved. It is recalculated after each load.
| Economy | Green fee, daily accounts, loan balance, yearly totals and feedback totals |
| Environment | Wind, weather, season, active seasonal event |
| Staff | Hired staff, their areas and the course condition |
| Weeds | Each weed clump and how far it has grown |
| Your own golfer | The ground they work between rounds (`owner_duty`). Their name, colours and skills are saved with the company, under `player_golfer`. |
| Tournaments | Tournament state (a live round cannot be resumed, so it is cleared on load) |
| Golfers | **Not saved.** They respawn when the simulation resumes. |

A building's foundation snapshot preserves the terrain, maintenance markers,
paths, cups and vertex heights hidden by its footprint, so moving or demolishing
it after loading can restore the original ground. Older saves without this data
use the ground present when loaded. If an older layout joins buildings at
different heights, the connected foundations are leveled together so no saved
building is dropped. Pre-construction terrain that was not recorded by an older
version cannot be recovered.

Older saves may still contain bunker-depth metadata. It is ignored on load: every standard Bunker tile is shallow, and new saves omit that retired field.

**Achievements are not in saves.** They stay unlocked between saves and live in `user://settings.cfg` instead (see [Milestones & Achievements](systems/economy-and-land/milestones-and-achievements.md)). The milestone block in a save carries only the per-save tracks: each course location's progress and the company's world milestones. Saves from before the three tracks keep one flat completed list, which migrates on load.

## Locations and Company State

Each owned location is a separate **site**. The company state lives in a shared block. When you switch sites, `SaveManager` takes the active site's state and puts it back into the company, so switching never resets your business.

`SITE_STATE_KEYS` lists the per-site keys. `SNAPSHOT_COMPANY_KEYS` lists the company keys. See [World Map](systems/economy-and-land/world-map.md).

## Versions

The current format is version **5** (`SAVE_VERSION`). Older saves are read with defaults for any missing field. For example, saves from before daily accounts existed start with empty daily counters.

Terrain ids are stored raw and are only ever appended, never renumbered, so a saved course always reads back as the ground it was painted with. The one id that has changed meaning is **9**, the retired cart path: `TerrainGrid.deserialize()` turns each stored 9 into Rough and remembers the tile, and `deserialize_walking_paths()` — which `SaveManager` always calls after it — lays the Path improvement's trail over each of those tiles. An older course therefore loads as the rough its gravel was bedded into, with the walk still on it, and saving it again writes Rough and the trail. See [Terrain Types](systems/course-design/terrain-types.md) and [Walking Paths](systems/course-design/walking-paths.md).

## Related

- [Architecture](architecture.md) covers the autoloads involved.
- [Data Reference](data-reference.md) covers the static data that is not saved.

## Mods in a save

Saves also carry `mods: {api_version, load_order: [{id, version}], data}`.
Each loaded script mod can return a JSON-shaped slice in `_mod_save` and
restore it via `_mod_restore`. The enabled mod set is still the player's
library preference, not automatically changed by loading a save. Missing
mods are named in a warning; keep a backup before saving without them,
because their content can be lost from the newly written save.
See [Modding](modding.md) for load-order and compatibility details.
