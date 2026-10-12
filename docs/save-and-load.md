# Save & Load

> Saves are JSON files under `user://`. A save holds the whole company and the active course. Golfers are not stored, and they arrive again after loading.

**Source:** `scripts/autoload/save_manager.gd` (`SAVE_DIR`, `SETTINGS_PATH`, `SAVE_VERSION`, `SITE_STATE_KEYS`, `SNAPSHOT_COMPANY_KEYS`, `build_location_snapshot()`, autosave), `scripts/autoload/game_manager.gd` (`AUTOSAVE_INTERVAL_DAYS`)
**Tests:** `tests/unit/test_save_manager.gd`, `tests/unit/test_save_load_validation.gd`, `tests/integration/world_map_flow.gd`

---

## Where Files Go

| File | Path | Contents |
| --- | --- | --- |
| Saves | `user://saves/` | One JSON file per save slot |
| Settings | `user://settings.cfg` | Display, audio and gameplay settings |
| Autosave | `user://saves/autosave` | Written automatically |

`user://` is Godot's per-user data folder. Its location depends on your operating system.

## When Saves Happen

- **Quick save:** `Ctrl+S`.
- **Save menu:** Pause menu, then Save, which uses named slots. The archive lists each save with its course, day, balance and hole count. Saving over an existing name asks first.
- **Autosave:** every 30 game days, and at the end of each year.

## What Is Saved

| Area | Saved |
| --- | --- |
| Company | Money, reputation, calendar, milestones, the unlimited-money flag, owned locations and unlocked land |
| Active site | Terrain tiles, the walking trails laid on them (`walking_paths`), elevation, cups waiting for holes |
| Entities | Buildings, decorations, path furniture, trees placed as entities |
| Holes | Tee and cup positions, par, yardage |

The stroke index is not saved. It is recalculated after each load.
| Economy | Green fee, daily accounts, loan balance, yearly totals and feedback totals |
| Environment | Wind, weather, season, active seasonal event |
| Staff | Hired staff, their areas and the course condition |
| Weeds | Each weed clump and how far it has grown |
| Tournaments | Tournament state (a live round cannot be resumed, so it is cleared on load) |
| Golfers | **Not saved.** They respawn when the simulation resumes. |

Older saves may still contain bunker-depth metadata. It is ignored on load: every standard Bunker tile is shallow, and new saves omit that retired field.

## Locations and Company State

Each owned location is a separate **site**. The company state lives in a shared block. When you switch sites, `SaveManager` takes the active site's state and puts it back into the company, so switching never resets your business.

`SITE_STATE_KEYS` lists the per-site keys. `SNAPSHOT_COMPANY_KEYS` lists the company keys. See [World Map](systems/economy-and-land/world-map.md).

## Versions

The current format is version **5** (`SAVE_VERSION`). Older saves are read with defaults for any missing field. For example, saves from before daily accounts existed start with empty daily counters.

Terrain ids are stored raw and are only ever appended, never renumbered, so a saved course always reads back as the ground it was painted with. The one id that has changed meaning is **9**, the retired cart path: `TerrainGrid.deserialize()` turns each stored 9 into Rough and remembers the tile, and `deserialize_walking_paths()` — which `SaveManager` always calls after it — lays the Path improvement's trail over each of those tiles. An older course therefore loads as the rough its gravel was bedded into, with the walk still on it, and saving it again writes Rough and the trail. See [Terrain Types](systems/course-design/terrain-types.md) and [Walking Paths](systems/course-design/walking-paths.md).

## Related

- [Architecture](architecture.md) covers the autoloads involved.
- [Data Reference](data-reference.md) covers the static data that is not saved.
