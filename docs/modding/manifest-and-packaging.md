# The manifest (`mod.json`) and packaging

> Player overview: [../modding.md](../modding.md) ·
> Scripting: [mod-api.md](mod-api.md) ·
> Workshop: [steam-workshop.md](steam-workshop.md)

A mod is a folder whose root holds one JSON file, `mod.json` - the
manifest. It says who the mod is, what it needs, what it ships, and
whether it wants to run code. The parser and validator live in
`scripts/modding/mod_manifest.gd` (`ModManifest`); anything listed as an
**error** below keeps the mod in the list but never loads it, anything a
**warning** loads and is shown to the player.

## A complete manifest

```json
{
	"format_version": 1,
	"id": "yourname.my_mod",
	"name": "My Mod",
	"version": "1.0.0",
	"api_version": 1,
	"author": "Your Name",
	"description": "What players read before enabling it.",
	"homepage": "https://example.org/my-mod",
	"min_game_version": "0.4.7",
	"max_game_version": "",
	"types": ["gameplay"],
	"entry_point": "mod_main.gd",
	"permissions": ["script"],
	"dependencies": [
		{"id": "golf_tycoon.seasons", "min_version": "1.0.0", "optional": true}
	],
	"conflicts": [],
	"load_after": [],
	"load_before": [],
	"enabled_by_default": false,
	"load_priority": 0,
	"content": {
		"buildings": "data/buildings.json"
	},
	"resource_packs": [],
	"config": {
		"payout": {"type": "int", "default": 500, "description": "…"}
	},
	"workshop": {
		"published_file_id": 0,
		"tags": ["Gameplay"]
	}
}
```

## Field reference

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `format_version` | int | yes (must be `1`) | The manifest format itself. |
| `id` | string | yes | Stable unique identity: 3–64 chars, starts with a lower-case letter, then lower-case letters/digits separated by `.`, `-` or `_` (e.g. `yourname.my_mod`). Namespaces everything the mod adds; never change it. |
| `name` | string | yes | Player-facing title. |
| `version` | string | yes | Dotted version like `1.2.0` (suffixes after the patch number are ignored when ordering). Used for dependency ranges, save records, and same-source duplicate tie-breaking. |
| `api_version` | int | yes | Which Golf Tycoon Mod API the mod was built for - currently `1`. The API only grows within a major version, so an exact match is required to load. |
| `author` | string | no | Shown in the Mods screen and used as the Workshop item author line. |
| `description` | string | no (warns) | Player-facing blurb in the details pane. |
| `homepage` | string | no | Link shown with the details. |
| `min_game_version` / `max_game_version` | string | no | Game-version window the mod supports; outside it the mod is listed but does not load. Empty = open-ended. |
| `types` | string[] | no | Free-form kind tags (`data`, `script`, `gameplay`, `balance`, …) displayed in the Mods screen. Cosmetic. |
| `entry_point` | string | script mods only | Mod-root-relative path to the GDScript the loader instantiates (must end `.gd`, must extend `GolfTycoonMod`). |
| `permissions` | string[] | script mods only | `["script"]` declares "run my code". An entry point without it is an error (it would silently never run); the permission without an entry point is a warning. Data-only mods declare neither, and any `.gd` files they carry are ignored. |
| `dependencies` | array | no | See below. |
| `conflicts` | string[] | no | Mod ids this mod cannot run alongside (either side declaring it is enough). |
| `load_after` / `load_before` | string[] | no | Soft ordering hints honoured when both mods load. |
| `enabled_by_default` | bool | no | **Bundled mods only:** seeds the player's first-run list. Ignored everywhere else - an installed mod always starts off. |
| `load_priority` | int | no | Tie-breaker for that first-run seeding only (lower earlier). The player's order wins afterwards. |
| `content` | object | no | Declarative data the game merges for you; keys below. All values are mod-root-relative paths. |
| `resource_packs` | string[] | no | Godot `.pck`/`.zip` resource packs to mount (`ProjectSettings.load_resource_pack`) before content/script loading - the escape hatch for shipping scenes and imported art. |
| `config` | object | no | Per-key settings schema: `{key: {type, default, description}}`. Read with the Mod API's `get_config_value`; stored per mod outside saves. |
| `workshop` | object | no | `published_file_id` (0 until first upload - the game writes it back after a successful one) and `tags` for the item. |

### Dependencies

Each entry is either a bare mod id string or an object
`{"id", "min_version", "max_version", "optional"}`:

- **Hard** (`optional` absent/false): the dependency is pulled into the
  load set just before your mod even if the player didn't tick it
  (shown as auto-enabled), and if it is missing, uninstallable, or out of
  the version range, your mod does not load either - with the reason in
  its details.
- **Optional**: never blocks and never pulls; if the other mod is in the
  set anyway, it is ordered before yours. That is how the Weather mod
  says "use Seasons when present".

### Content keys

All paths are relative to the mod folder. The merge rules below apply to
every key: entries apply **in load order**, **later wins**, and the Mods
screen reports every cross-mod overwrite by name.

| Key | File shape | Semantics |
| --- | --- | --- |
| `buildings` | `{id: entry}` - same fields as `data/buildings.json` | Deep-merge over the current catalog; see namespacing/patch rules below. |
| `decorations` | `{id: entry}` - same fields as `data/decorations.json` | Same as buildings. |
| `terrain_overrides` | `{"terrain": {terrain_name: {property: value}}}` | Property-wise override of `TerrainTypes` values (`placement_cost`, `maintenance_cost`, …). Terrain names are the shipped ids (`fairway`, `green`, `bunker`, …). |
| `themes` | `{"themes": {theme_id: {…}}}` | Deep-merged over a shipped theme's record (name/description/`modifiers`/`colors` as hex strings). |
| `tournament_tiers` | `{"tiers": {tier_id: {…}}}` | Deep-merged over `TournamentSystem` tiers (e.g. `prize_pool`). |
| `world_locations` | `{"locations": [{id, name, region, theme, size, lat, lon, prestige, description}]}` | `theme` and `size` accept names (`"links"`, `"medium"`); ids are namespaced unless they replace a shipped location. Latitude/longitude/prestige are clamped to sane ranges. |
| `visiting_golfers` | `{location_id: path}` where each path holds a JSON **array** of golfer cards (same shape as `data/visiting_golfers/*.json`) | Cards are appended to that location's visitor pool; your own location may be named bare. |
| `golfer_names` | `{"professions": [], "female_first_names": [], "male_first_names": [], "last_names": []}` | Strings are added to `GolferAttributes`' pools. |
| `golfer_skins_root` | a **directory** of skin folders | Merged into `GolferSkinLibrary` - see [../golfer-skins.md](../golfer-skins.md) for the `skin.txt` format. A skin may ship no painted layers and just re-color a shipped sprite set's groups (see `example.golfers`). |
| `tree_art_root` | a **directory** of tree sprites, optionally with `<season>/` subfolders and `layout.json` | A root-level `<species>[_n/_e/_s/_w].png` is an **all-season sprite replacement**: it takes priority over the base and seasonal art for that species/view, so one flat folder can repaint every tree all year (see `example.tree_sprites`). A `<season>/<species>[_n/_e/_s/_w].png` is a seasonal wardrobe drawing, where `<season>` is a lower-cased `SeasonSystem.get_season_name()` (`spring`, `summer`, `fall`, `winter`); a species with no root-level replacement or current-season art keeps wearing its evergreen sprite. The unsuffixed drawing answers for any angle not generated. `layout.json` can scale or re-anchor art at draw time. Later enabled mods win a repeated file on the same shelf; root-level art always wins over seasonal art. The official Seasons mod ships the game's seasonal wardrobe (`golf_tycoon.seasons`). |
| `seasonal_events` | `{"events": [{id, name, season, …}]}` | Registered whole into `SeasonalEvents` (full records only - no field-level merge). See namespacing below; painting-by-id is how `example.more_seasons` re-opens the Seasons mod's Spring event. |
| `tuning` | `{"tuning": {"dotted.key": number}}` | Flat numeric levers read by the game and by mods via `get_tuning`. Non-numbers are skipped with a warning. The game's own keys are listed in [mod-api.md](mod-api.md). |

### Tree sprite layout (`tree_art_root/layout.json`)

PNG dimensions do not need to match Golf Tycoon's built-in art. Put an
optional `layout.json` at the root of the folder declared as `tree_art_root`
to alter the **draw transform**, not the image itself:

```json
{
  "scale": 0.5,
  "species": {
    "oak": {"scale": 0.42, "offset_y": -8}
  },
  "sprites": {
    "oak_e": {"ground_y": 124}
  }
}
```

- `scale` is a number from `0.05` to `4.0`; `1.0` is native size. Root-level
  values apply to every image in the folder, `species.<name>` overrides a
  species, and `sprites.<name>_<facing>` is the final per-view override.
- `offset_y` is the quickest visual correction: it is a rendered-pixel nudge
  after scaling. Negative values move the sprite up; positive values move it
  down. It is ideal when a replacement simply sits too high or low.
- `ground_y` is the source-image pixel coordinate, measured from its top edge,
  that should sit on the terrain. It is useful when a replacement PNG has more
  transparent padding, or a different crop, above or below the trunk. Omit it
  to use the shipped species' ground point, scaled with the art.
- Layout values apply to root-level replacements and seasonal subfolders alike.
  Invalid or unknown entries are ignored so the artwork still loads.

`mods/example.tree_sprites/tree_art/layout.json` is a complete, working
per-species scaling example using the supplied large user sprites.

### Namespacing, patching, replacing, removing

For catalogs (buildings, decorations) each entry id resolves as:

- An id that **already exists** (shipped, or from an earlier mod) →
  **patch**: deep-merged over the existing entry - nested objects merge
  key by key, everything else (including arrays) is replaced. Write only
  the fields you are changing.
- A **new bare id** → your entry, stored under `"your_mod.id:entry"`
  automatically, so two mods can both add a twin tower without colliding.
  In saves and anywhere ids surface, that namespaced form is what you see.
- `"__replace__": true` inside an entry → the existing entry is discarded
  and yours used whole (the marker itself is stripped).
- `"__remove__": true` → the entry is deleted - except entries the shipped
  data marks `"required": true`, which refuse with a warning.
- An id containing `:` in **another mod's** namespace that does not exist
  yet is skipped: you can patch other mods' existing entries, never forge
  entries inside their namespace.

Seasonal events and world locations follow the same "existing id = patch,
new id = namespaced" idea, but records are replaced whole rather than
merged (events have cross-field invariants; locations are replaced so a
mod can move a pin outright). Mod-added seasonal events only have meaning
while a seasons provider is loaded (the official Seasons mod or a
replacement).

Sparse new entries are padded out so they still work: a building or
decoration without `name` is named from its id, without a valid
`size: [w, h]` becomes 1×1, without `cost` is free; decorations default to
category `structures` on grass/path. A building may also carry a `color`
(hex) used by the procedural building sprite fallback, and decorations
tint similarly - you can ship a fully working painted-looking catalog
with zero art. Building fields the game reads (including effect fields
like `green_fee_bonus`, `food_service`, `skill_training` and the optional
`availability` block - missing availability means "available everywhere")
are the same ones `data/buildings.json` uses; see that file and
[../data-reference.md](../data-reference.md).

## Load order: how a list becomes a set

The player's list (`user://mods/load_order.json`, `{"version": 1,
"enabled": [ids in order]}`) is the starting point, not the whole story.
Resolution (`ModManager.resolve_load_order`, a pure function) then:

1. Drops mods that cannot load at all: invalid manifest, wrong
   `api_version`, game version outside `min/max_game_version` - each with
   an explanation shown in its details pane.
2. Pulls **hard dependencies** in just before the mods that need them
   (auto-enabled, recursively). If any hard dependency is missing,
   excluded, or the wrong version, its dependants fall out too.
3. Applies **conflicts**: walking the player's order, the first of a
   conflicting pair stays; the later one is excluded and told which mod
   it clashed with, so the player can move or disable one.
4. Topologically sorts over dependency and `load_after`/`load_before`
   edges, stable by the player's order (among mods that could go next,
   the earliest-listed does). A cycle excludes the mods in it.

The result is *the* order for everything: content merges, provider
take-overs (the last registration wins) and hook chaining all run in it.
First launch, the list is seeded with bundled mods that set
`enabled_by_default`, by `load_priority` then id - that is the only time
`load_priority` ever matters.

**Duplicate copies**: the same id discovered twice resolves by source
precedence - folders in your library (including installed zips) > a loose
zip in the library > a Workshop download > bundled - and within the same
source the higher `version` wins.

**Folders starting with `_` or `.`** (like `_template`) are never
discovered, in every root.

**ZIP-sourced mods** in `user://mods/*.zip` are discovered from their
manifest without extracting; the first time one is actually in a load set
it is installed (extracted) into `user://mods/installed/<id>/` and from
then on behaves as that folder.

## Packaging & distribution

A shareable mod is the folder's contents in a zip, `mod.json` at the zip
root (a single wrapper folder around everything is also accepted).
`.import` files, `.uid` sidecars, nested zips and OS junk
(`.DS_Store`, `Thumbs.db`) are excluded when packing. Practical limits,
also enforced on install: zip ≤ 512 MB, ≤ 5000 files, ≤ 128 MB per file,
and no zip entry may escape its destination (`../`, absolute paths) -
such zips are rejected outright.

Players install a zip from the Mods screen (**Install ZIP…**) or by
dropping it (or the bare folder) into the mods folder and hitting
**Rescan**. Installing always lands the mod **disabled**. An installed
copy is replaced wholesale when a newer zip of the same id installs, and
user-provided mods (folder, zip, installed) can be **uninstalled** from
the details pane - bundled and Workshop copies cannot (disable them or
manage the subscription on Steam).

From a source checkout, the command-line tool does exactly what the game
does (`tools/mod_tool.gd`, exit code 0/1 for CI):

```
make mod-validate MOD=mods/example.jackpot     # or a .zip
make mod-pack     MOD=mods/example.jackpot     # -> dist/mods/<id>-<version>.zip
make mods                                       # validate + pack every bundled mod
godot --headless --path . --script tools/mod_tool.gd -- list some-mod.zip
```

Validation is manifest validity plus existence of the entry point and
every declared content path - a mod that validates here will at least be
listed (disabled) in players' Mods screens.

## Safety rails (the loader's contract with players)

- Nothing runs from a zip until it is installed, and nothing loads until
  the player enables it and applies. Browsing is always inert.
- **Safe mode:** before running any script mod the loader writes
  `user://mods/.loading_mods`; surviving a few frames deletes it. If it is
  still there next launch - the previous session died while loading -
  that session loads **data only** and says so, so a bad mod can never
  crash-loop the game. Apply & Reload tries the set again.
- `--no-mods` on the command line loads nothing and leaves the saved list
  untouched.
- A mod that fails mid-load (missing entry point, script not a
  `GolfTycoonMod`, unmountable pack) is marked failed with the reason;
  the rest of the set continues.

Script permissions are a trust disclosure, not a sandbox. GDScript runtime
errors are logged by Godot and cannot be caught as exceptions by the loader;
only manifest/package/entry-point validation failures can be reliably isolated.
Resource packs can replace engine resources and require the same trust as code.
Back up saves before changing a mod set. Mounted resource packs cannot be
unmounted in-process; restart the game after changing a pack-carrying mod.
