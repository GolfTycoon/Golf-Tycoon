# Data Reference

> The JSON data behind buildings, decorations, terrain, golfer skins and visiting golfers, and which of those files the game reads at runtime.

**Source:** `data/` (all files), `scripts/systems/golfer_tier.gd`, `scripts/terrain/terrain_types.gd`, `scripts/systems/world_locations.gd` (`get_visiting_golfers()`), `scripts/systems/prebuilt_course_generator.gd`
**Tests:** `tests/unit/test_new_terrain_types.gd`

---

## Files

| File | Entries | Read at runtime | What it holds |
| --- | --- | --- | --- |
| `data/buildings.json` | 16, keyed by id | Yes | Facilities: size, cost, daily operating cost, upgrades, and whether the facility is required |
| `data/decorations.json` | 5, keyed by id | Yes | Improvements: category, size, cost, upkeep, aesthetic value, allowed terrain, theme bonuses |
| `data/terrain_types.json` | 33 | No | Mirror of terrain ids, names, `playable`, `placement_cost` and `blocks_shots`, for tools |
| `data/golfer_traits.json` | Two sections | No | `golfer_archetypes` and `mood_states`. No runtime code reads them. |
| `data/visiting_golfers/<location>.json` | 27 files | Yes | Visiting golfers for each World Map location |
| `data/golfer_skins/beginner/` and `casual/` | Skin folders | Yes | Built-in golfer skins |

## Buildings

`buildings.json` is an object keyed by building id. Each entry has:

| Field | Meaning |
| --- | --- |
| `id`, `name` | Identifier and display name |
| `size` | Footprint in tiles, for example `[4, 4]` |
| `cost` | Build cost |
| `operating_cost` | Daily operating cost |
| `required` | Whether the course must have it. The clubhouse is required. |
| `upgradeable`, `upgrades` | Upgrade levels, with costs, unlocks and bonuses |

The clubhouse is the only required building. See [Clubhouse](systems/course-design/clubhouse.md).

## Improvements

`decorations.json` is an object keyed by improvement id (the ball washer, park
bench, fountain, golfer statue and sundial). Each entry has:

| Field | Meaning |
| --- | --- |
| `category` | Group: `water`, `structures`, `furniture` or `sculptures` |
| `size` | Footprint in tiles |
| `cost`, `daily_upkeep` | Build cost and daily upkeep |
| `aesthetics_value` | Contribution to the aesthetics rating |
| `placeable_terrain` | Terrain the improvement can be placed on |
| `unlock` | Requirement to unlock it, if any |
| `theme_bonus` | Themes that get a bonus from it |
| `description` | Short text shown in the catalogue |

See [Improvement Catalog](systems/course-design/garden-catalog.md).

## Terrain

Terrain behaviour is defined in `scripts/terrain/terrain_types.gd`. `terrain_types.json` is a mirror for tools. Changing the JSON does not change the game. See [Terrain Types](systems/course-design/terrain-types.md).

## Visiting Golfers

`data/visiting_golfers/` has one file for each of the 27 World Map locations, named after the location in lower case, for example `japan.json`, `new_york.json` or `san_diego.json`. Each file lists the visitors for that location. Each visitor has a name, a `skin_id` (a folder in `data/golfer_skins/`), a tier and group colours.

See [World Map](systems/economy-and-land/world-map.md) for the locations.

## Golfer Skins

Built-in skins are folders in `data/golfer_skins/`. The format and the studio are covered in [Golfer Skins](golfer-skins.md).

## Related

- [Architecture](architecture.md) shows which systems read this data.
- [Save & Load](save-and-load.md) covers what is saved, which is not this static data.
