# Modding

Golf Tycoon ships with a mod system designed for safe, composable extensions.

## Overview

A **mod** is a folder that contains a `mod.json` manifest and an entry script
(`mod.gd`). The game discovers mods in two places:

* `res://mods/` — **builtin mods** shipped with the game (Weather, Wind, Seasons).
* `user://mods/` — user-installed mods (drop a folder here and restart).

Each mod declares an id, version, dependencies, load priority and permissions.
At startup `ModManager` discovers every manifest, validates them, and loads
the ones that are enabled — in the order the player chose.

## The ordered enabled list (conflict resolution)

The single source of truth for which mods run is an **ordered list** of enabled
mod ids, stored in `user://mods.json` (and per-save in the save file).

*Order matters.* When two enabled mods define the same thing (a building type,
a terrain tile, a fee modifier, or a signal override) the **later mod in the
list wins**. The Mods screen makes this visible and controllable:

* Enabled mods are shown top-to-bottom in load order.
* Each row has **Up / Down** arrows to re-order; moving a mod down gives it
  higher priority.
* A conflict banner lists every overlapping id and which mod currently wins.
* The save file records which mods (and versions) were active so a save can
  warn about missing or mismatched mods without refusing to load.

This satisfies the requirement "ordered, enabled-mods list to help with conflict
resolution" with the least surprise: the player's ordering is the resolver.

## Manifest (`mod.json`)

```json
{
  "id": "my_golf_pack",
  "name": "My Golf Pack",
  "version": "1.0.0",
  "description": "Adds a driving range.",
  "author": "You",
  "api_version": "1.0",
  "category": "content",
  "entry_point": "res://mods/my_golf_pack/mod.gd",
  "dependencies": ["weather"],
  "optional_dependencies": [],
  "conflicts": ["other_pack"],
  "load_after": [],
  "load_before": [],
  "permissions": ["buildings", "event_bus"],
  "load_priority": 100,
  "enabled_by_default": false,
  "tags": ["content"]
}
```

Fields:

* `id` — `/^[a-z][a-z0-9_]*$/` (3–32 chars, lower-case).
* `version` — semver-like `1.2.3` or `1.2.3-alpha`.
* `api_version` — which `ModAPI` the mod was written against.
* `dependencies` — hard requirements (mod is not enabled if missing).
* `conflicts` — if both are enabled a warning is shown; later still wins.
* `load_after` / `load_before` — soft ordering hints.
* `permissions` — sandbox capabilities the mod may request.
* `entry_point` — GDScript loaded when the mod is enabled.

Validation is lenient on first party mods and strict on user mods; the game
never crashes because a mod is missing or broken — it is marked `FAILED`.

## Entry script

```gdscript
extends RefCounted
var api: ModAPI = null
var mod_manifest: ModManifest = null

func _mod_on_load() -> bool: return true
func _mod_on_enable() -> bool:
    api.register_building_type("my_range", {"name": "Driving Range", "cost": 4000})
    api.register_hook("day_changed", func(d): print("new day ", d))
    api.log("enabled")
    return true
func _mod_on_disable() -> bool: return true
func _mod_on_unload() -> bool: return true
```

`api` is injected before load. Every call is wrapped in `_call_safely` — a
failing mod logs and is marked failed without affecting others.

## What a mod can do (API v1.0)

Via `ModAPI` (scoped to its `mod_id`):

* **Content** — `register_building_type`, `register_decoration`, `register_terrain`,
  `register_trait`, `register_seasonal_event`, `override_building_type`.
  Overrides respect the ordered list: later registrations win.
* **Economy** — `register_modifier("green_fee", callable)` chains modifiers in
  enabled order (later sees earlier's result).
* **Hooks** — `register_hook("day_changed", callable)` fans out to all mods;
  one mod's error does not stop the rest.
* **UI** — `register_ui_section`, `register_menu_action`.
* **Sprites** — `register_sprite(category, id, {fallback: "res://...png"})`
  replaces a building/decoration/tree/golfer sprite without touching core.
* **Save data** — `set_mod_save_data(key, value)` / `get_mod_save_data(key)` per-mod
  namespaced blob, serialized inside the save file.
* **Feature flags** — `register_feature("my_feature", ...)` then
  `ModManager.is_feature_enabled("my_feature")` / `GameManager.is_feature_enabled`.

A failing mod is never fatal; hooks and modifiers are isolated per-call.

## Builtin mods

The previous hardcoded features were extracted to builtin mods in `mods/`:

* `mods/weather` — the WeatherSystem (rain/spawn/accuracy/tint). Feature id `weather`.
* `mods/wind` — the WindSystem (direction/speed/drift). Feature id `wind`.
* `mods/seasons` — SeasonSystem + SeasonalEvents (spawn/maintenance/prestige/weights). Feature id `seasons`.

Each is a normal mod with `is_builtin = true` and `enabled_by_default = false`
(legacy defaults were all off; a new game enables the ones the setup screen
checked). Toggling them drives `GameManager.weather_enabled` etc via
`_sync_feature_to_mod` so old code keeps working.

## Save compatibility

* The save records `mods.enabled` (ordered) and `mods.versions` at save time.
* Loading warns on missing or version-mismatched mods but still loads.
* `SaveManager` delegates to `ModManager.serialize_for_save` / `deserialize_from_save`;
  `ModManager` keeps `mod_save_data` per-save. Location snapshots keep `mods`
  as a company-level key (not per-site) so switching sites does not lose the
  global mod order.

## Adding a sprite

Pack individual PNGs with `tools/pack_sprites.py` → `assets/sprite_sheets/`.
Code prefers the atlas via `SpriteSheet.get_texture(sheet, id)` and falls back
to the individual PNG so unsheeted mod art still works. Mods can inject via
`SpriteAtlasRegistry.register_mod_sprite(category, id, info)`.

## Refactors for stability

* `ModManager` is an autoload (after `GameManager`/`EventBus`/`SaveManager`) and
  re-syncs feature flags on ready and on `enabled_order_changed`.
* `GameManager` booleans remain for save compat but sync to/from the mod list
  (`_sync_feature_to_mod` / `_sync_mods_to_features`).
* Sprite drawing now goes through `SpriteSheet` / `SpriteAtlasRegistry` —
  `BuildingSprites`, `TreeOverlay`, `Decoration` all check the atlas first.
* `MainMenu` gains a **Mods** tile (Gear icon) emitting `mods_requested`; `Main`
  shows `ModsScreen`. `HUDStatusColumn` and `StartNewGameScreen` read feature
  flags through `is_feature_enabled` so they reflect mod state.

## Writing a mod

1. Create `user://mods/my_mod/mod.json` and `user://mods/my_mod/mod.gd`.
2. Implement `_mod_on_enable`; use `api.*` to register content.
3. Test with the atlas packer if adding sprites.
4. Open Mods in the main menu to enable and order it; conflicts show up there.

A minimal example is kept in `mods/example/` (not enabled by default).
