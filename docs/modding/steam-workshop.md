# Steam Workshop support

> Overview: [../modding.md](../modding.md) ·
> Manifest & packaging: [manifest-and-packaging.md](manifest-and-packaging.md) ·
> Mod API: [mod-api.md](mod-api.md)

Workshop items are not a special mod format: an item's content is **the
same folder** a zip would carry (`mod.json` + files). Subscribed items
flow through the same discovery, load-order, conflict and safety rules as
every other source, appear in the Mods screen badged with their Workshop
item number, and lose to a same-id copy in the player's own mods folder
(so authors can test patches locally). The integration lives in
`scripts/modding/steam_workshop_provider.gd`.

## How it behaves per build

| Build | Steam bits | Workshop behaviour |
| --- | --- | --- |
| Steam build (GodotSteam addon + `modding/steam_app_id` set in `project.godot`, Steam running) | full | Subscribed-and-downloaded items are discovered; **Steam Workshop** opens the game's Workshop page (overlay if available, browser otherwise); **Upload to Workshop…** creates/updates items. |
| Everything else (including open-source builds) | absent by design | The provider looks the `Steam` singleton up dynamically (`Engine.has_singleton`), finds nothing, and reports unavailable; the buttons explain themselves. Nothing references GodotSteam at compile time, so these builds compile and run identically. |

The provider probes once: `Steam` singleton present **and** exposing the
UGC calls (`getSubscribedItems`) = available. `modding/steam_app_id = 0`
(currently in `project.godot`) means "not a Steam build" - uploads and
the workshop page refuse with that exact reason rather than failing
inside Steam.

## For players (Steam build)

1. Subscribe on the game's Workshop page (the **Steam Workshop** button
   in the Mods screen takes you there).
2. Wait for Steam to finish downloading, then **Rescan** (or relaunch).
3. The mod appears, badged `Steam Workshop item <id>`, **disabled** -
   subscribing is not enabling, same as installing a zip. Ticking it,
   ordering it and Apply & Reload work exactly like any mod.
4. Steam keeps subscribed items up to date; unsubscribing (in Steam) is
   how they go away - the in-game Uninstall refuses Workshop mods.

Discovery asks GodotSteam for subscribed ids, then for each item's
install folder (`getItemInstallInfo`, read defensively because the key
spellings have varied between GodotSteam releases), and scans that
folder as a mod root. Items still downloading (no folder yet) are just
absent until a rescan.

## For modders

Uploading needs a **folder** copy of your mod (your library folder, or an
installed zip's folder - uploading straight from a zip is refused with
"install it first"). In a Steam build, select the mod in the Mods screen
and press **Upload to Workshop…**:

1. If `workshop.published_file_id` is 0, a new item is created
   (`createItem`, community file type). First-time creators may be asked
   to accept the Workshop legal agreement - the game opens that page
   when Steam flags `needs_legal`.
2. An item update is then submitted, driven by the manifest's `workshop`
   block:

   ```json
   "workshop": {
       "published_file_id": 3241231234,
       "title": "Optional - defaults to the mod's name",
       "description": "Optional - defaults to the mod's description",
       "preview": "preview.png",
       "tags": ["Gameplay"],
       "visibility": "public"
   }
   ```

   - `published_file_id`: 0 = create; afterwards, **put the returned id
     in `mod.json` yourself** (the result message names it) so future
     uploads update the same item. The game does not edit your manifest.
   - `preview`: an image inside the mod folder (default `preview.png`,
     skipped silently when absent).
   - `tags`: strings passed to `setItemTags`; the item's tag list must
     match tags configured for the app in Steamworks.
   - `visibility`: `public` | `friends` | `private` (default public).
3. Both steps are async Steam callbacks (`item_created` /
   `item_updated`, EResult 1 = OK); the provider awaits them with a 120s
   timeout and reports `{ok, message, published_file_id}` to the screen.
   `ModManager.upload_to_workshop(mod_id, change_note)` is a coroutine -
   callers must `await` it.

Updates replace the item's content with the current folder. Bump your
mod `version` for players (it's what saves and dependency ranges see);
the Workshop change note can carry the human-facing summary.

## For packagers: making a Steam build

1. Install the [GodotSteam](https://godotsteam.com/) addon/beta build
   for the game's Godot version (4.6) so the `Steam` engine singleton
   exists. No code changes - the provider detects it at runtime.
2. Set the real App ID: `modding/steam_app_id = <app id>` in
   `project.godot`, plus whatever the GodotSteam build needs
   (`steam_appid.txt` for local testing, Steam-provided libraries).
3. In Steamworks for that App ID: enable the Workshop, define the tags
   manifests use, and (for subscribed-item downloads) configure the
   content type as user-generated folders.
4. Export normally. The `mods/**` include filter and the mod loader are
   unchanged; bundled official mods keep loading from `res://mods`.

**Testing without Steam:** everything except actual subscribe/upload
round-trips is exercised without it - discovery precedence, ordering,
installing, and the provider's graceful absence are covered by unit
tests (`tests/unit/modding/`). A fake `Steam` singleton can also be
registered in a test scene to exercise the provider paths, because it
only ever calls `has_method`-gated dynamic calls.
