# Data Reference

> The JSON data behind buildings, decorations, terrain, menu backdrops, menu overlays, golfer skins and visiting golfers, and which of those files the game reads at runtime.

**Source:** `data/` (all files), `scripts/systems/golfer_tier.gd`, `scripts/terrain/terrain_types.gd`, `scripts/systems/world_locations.gd` (`get_visiting_golfers()`), `scripts/systems/prebuilt_course_generator.gd`, `scripts/systems/menu_backdrop_catalog.gd`
**Tests:** `tests/unit/test_new_terrain_types.gd`

---

## Files

| File | Entries | Read at runtime | What it holds |
| --- | --- | --- | --- |
| `data/buildings.json` | 16, keyed by id | Yes | Facilities: size, cost, daily operating cost, effect, location availability, upgrades, and whether the facility is required |
| `data/decorations.json` | 5, keyed by id | Yes | Improvements: category, size, cost, upkeep, aesthetic value, allowed terrain, theme bonuses |
| `data/terrain_types.json` | 33 | No | Mirror of terrain ids, names, `playable`, `placement_cost` and `blocks_shots`, for tools |
| `data/golfer_traits.json` | Two sections | No | `golfer_archetypes` and `mood_states`. No runtime code reads them. |
| `data/menu_backdrops.json` | 4, keyed by id | Yes | Menu background pictures: image, tint and the season/theme tags Auto reads |
| `data/menu_overlays.json` | 18, keyed by id + a `settings` block | Yes | Menu overlay patterns, the ink and feature size each one draws with, and the settings the Display card offers |
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
| `description` | The blurb shown on the building's tile tooltip |
| `availability` | Which course themes may build it (see below) |
| `effect` | Structured effect metadata: `skill_training`, `food_service`, `walking_speed`, `starting_attitude`, `starting_stamina` or `green_fee` |

The clubhouse is the only required building. See [Clubhouse](systems/course-design/clubhouse.md).

### The fifteen location facilities

Beside the clubhouse, the Buildings tab offers exactly these facilities:

| Building | What it does | Where it is offered |
| --- | --- | --- |
| Putting Green | Boosts the imagination skill of visiting golfers | All locations |
| Snack Bar | Food stop for hungry golfers | All locations except the Links theme |
| Pub | Food stop for hungry golfers | Links theme only |
| Pro Shop | Boosts the accuracy skill of visiting golfers | All locations |
| Driving Range | Boosts the length skill of visiting golfers | All locations |
| Cart Garage | Boosts the walking speed of visiting golfers | All locations |
| Tennis Court | Starts every golfer with a more positive attitude | All locations except Links, Desert and Tropical |
| Stable | Starts every golfer with a more positive attitude | Links theme only |
| Spa | Starts every golfer with a more positive attitude | Desert theme only |
| Swim Club | Starts every golfer with a more positive attitude | Tropical theme only |
| Resort Hotel | Starts every golfer with more stamina for the round | All locations |
| Airstrip | Boosts green fees per hole, scaled by the hole's rating | All locations except Links, Desert and Tropical |
| Castle | Boosts green fees per hole, scaled by the hole's rating | Links theme only |
| Casino | Boosts green fees per hole, scaled by the hole's rating | Desert theme only |
| Theme Park | Boosts green fees per hole, scaled by the hole's rating | Tropical theme only |

### Availability rules

The `availability` block names the course themes (by their `CourseTheme`
string names) a facility is offered at. `BuildingAvailability`
(`scripts/systems/building_availability.gd`) reads it; the Buildings tab,
the placement flow and the course generators all go through that class.

| Block | Meaning |
| --- | --- |
| `{ "all": true }` | Offered at every location |
| `{ "all": true, "excluded_themes": ["links"] }` | Everywhere except the listed themes |
| `{ "only_themes": ["desert"] }` | Only the listed themes |

A building with no `availability` block is treated as available everywhere.
Every theme therefore gets exactly one food stop (Snack Bar or Pub), one
attitude facility and one green-fee landmark.

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

## Menu Backdrops

`menu_backdrops.json` is an object keyed by backdrop id, each entry naming the
picture the menus can sit on. `MenuBackdropCatalog` reads it once at startup and
merges every loaded mod's entries over it; `Backdrops` (the autoload) picks one -
the player's choice, or Auto's - and `MenuBackdrop` draws it. The art lives in
`assets/ui/backdrops/`; a mod can point at art of its own instead.

| Field | Meaning |
| --- | --- |
| `name`, `description` | What the picker in **Settings → Display → Background** shows |
| `image` | `res://` path to the picture. Drawn 16:9 and cropped cover-fit, so no window shape letterboxes it |
| `tint` | Colour multiplied over the picture (hex, `[r, g, b, a]` or a name); `ffffff` leaves it alone |
| `tags` | Free-form words, not read by the game |
| `seasons`, `themes` | Which season and course theme the picture suits. **Auto** prefers a match, then falls back to `clubhouse` |

The shipped four: `clubhouse` (no tags — the fallback), `golden_hour` (fall;
resort, tropical and links courses), `winter` (winter; mountain, woodland and
heathland) and `desert` (desert and marshland).

A picture is only the picture. Anything drawn over it - shading, a wash, a
pattern - is an overlay entry, chosen separately. That includes the dark bands
the headings sit on, which are the `edge_scrim` overlay; `MenuBackdrop` draws
no layer of its own.

`menu_overlays.json` holds the patterns laid over that picture plus the
`settings` block their controls read.

| Overlay field | Meaning |
| --- | --- |
| `name`, `description` | What the overlay picker shows |
| `pattern` | Which painter `MenuBackdropOverlay` runs: `none`, `wash`, `vignette`, `glow`, `split`, `stripes`, `grid`, `scanlines`, `dots`, `sparkle`, `edges`, `aurora`, `sunburst`, `contours`, `deco`, `argyle` or `bokeh` |
| `color` | The ink; its alpha is the overlay's whole opacity, so `strength` multiplies it further |
| `strength` | 0–1 multiplier on the ink's alpha, so one pattern can be shipped at several weights |
| `scale` | Feature size in whole pixels at the design resolution (band pitch, dot spacing) |
| `setting_ids` | Which keys of the `settings` block this overlay reacts to; each becomes a row under the picker and is remembered per overlay |
| `seasons`, `themes` | As for pictures. Auto prefers a match and otherwise falls back to `edge_scrim` |

The `settings` block is the same schema mods use: `{key: {name, description,
kind, default, choices, values}}` where `kind` is `choice` (a picker) or
`toggle`. `angle` (0–165° in 15° steps) turns `split`, `stripes`, `grid`,
`aurora`, `sunburst`, `contours` and `argyle`; `density` (Light/Medium/Heavy)
sets the detail in `sparkle`, `aurora`, `sunburst`, `contours` and `bokeh`.
The six signature painters are procedural: flowing aurora bands, fading radial
sun shafts, nested topographic contours, gilded corner fans, an argyle knit and
soft photographic light orbs. They need no imported textures.

`edge_scrim` is the default Auto falls back to: the 28 slices (`edges`) that
shade the top and bottom edges, so cream headings stay readable on a bright
picture. It was painted under every picture before overlays existed, so it
ships as an overlay to keep that look while making it a choice.

## Visiting Golfers

`data/visiting_golfers/` has one file for each of the 27 World Map locations, named after the location in lower case, for example `japan.json`, `new_york.json` or `san_diego.json`. Each file lists the 50 visitors for that location, and every visitor has a unique name within it (and across the whole game).

Each visitor is a full golfer card:

| Field | Meaning |
| --- | --- |
| `name` | The golfer's unique first and last name |
| `skin_id` | A folder in `data/golfer_skins/` the golfer wears |
| `tier` | Beginner (0), Casual (1), Serious (2) or Pro (3) — the tier decides personality, patience and miss tendency |
| `profession`, `marital_status`, `age`, `gender` | Identity. The status is Single, Married, Divorced or Widowed; the gender is the golfer's own and matches the name |
| `traits` | The Golfer Traits that are On (neat, outgoing, active, playful, nice); any the golfer does not have are left out |
| `golfer_skills` | The Golfer Skills that are On (length, accuracy, imagination) |
| `golf_skills` | The Golf Skill points, by the skill's name (1-99, each point +10%). Skills with no points are left out |
| `group_colors` | Shirt, Pants, Cap, Hair and Skin hex colours for the group's kit |

`GolferAttributes.apply_visitor_card()` reads the card, and `GolferManager.spawn_visiting_golfer()` gives it to the golfer they spawn. A card is the whole person: a returning guest keeps this same block through their visits. See [Golfer Attributes](systems/golfers/golfer-attributes.md).

See [World Map](systems/economy-and-land/world-map.md) for the locations.

## Golfer Skins

Built-in skins are folders in `data/golfer_skins/`. The format and the studio are covered in [Golfer Skins](golfer-skins.md).

## Related

- [UI & Controls](ui-and-controls.md#menu-background) covers the Background card that sets these.
- [Architecture](architecture.md) shows which systems read this data.
- [Save & Load](save-and-load.md) covers what is saved, which is not this static data.
