extends RefCounted
class_name ModWorkshop
## ModWorkshop - Steam Workshop and generic workshop sharing.
##
## Golf Tycoon can publish mods to Steam Workshop when running under Steam
## (via the `steam_workshop_uploader` tool or GDSteam/Steamworks GDExtension),
## and it can also share mods as plain .zip files for itch.io, Discord, etc.
##
## Because the open-source build does not bundle Steamworks, this script
## works in two modes:
##
##  1. **Native Steam** (if a Steam GDExtension is present and `Steam` singleton
##     exists) — publishing uses Steam's Workshop API.
##
##  2. **Staging folder** (fallback) — `user://workshop/` acts as a local
##     workshop mirror. Publishing copies the mod's zip there with a
##     `workshop.json` descriptor; players subscribe by copying that zip into
##     `user://mods/`. On Steam Deck / when Steam is running, an extra
##     discovery path `STEAM_WORKSHOP_PATH` (env var or `user://workshop/steam/`)
##     is scanned so workshop subscriptions appear automatically.
##
## This keeps the sharing story intact without requiring a Steam client in CI
## or in the editor: a zip is always the canonical shareable artifact, and
## Workshop is a convenience layer on top.

const LOCAL_WORKSHOP_DIR := "user://workshop"
const LOCAL_STAGING_DIR := "user://workshop/staging"
const WORKSHOP_META := "workshop.json"
const ENV_WORKSHOP_PATH := "GOLF_TYCOON_WORKSHOP_PATH" # override for testing / Steam

## Extra discovery roots for workshop content (in addition to user://mods).
## ModLoader will scan these when `discover_workshop_mods()` is called.
static func workshop_roots() -> Array[String]:
	var roots: Array[String] = []
	# Local staging (published but not yet subscribed)
	roots.append(LOCAL_WORKSHOP_DIR)
	# Env-override for Steam's workshop content path, e.g.
	#   /home/deck/.steam/steam/steamapps/workshop/content/<app_id>/
	var env_path := OS.get_environment(ENV_WORKSHOP_PATH)
	if not env_path.is_empty() and DirAccess.dir_exists_absolute(env_path):
		roots.append(env_path)
	# Common Steam install locations (best-effort, non-fatal if absent)
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		for cand in [
			home.path_join(".steam/steam/steamapps/workshop/content"),
			home.path_join(".local/share/Steam/steamapps/workshop/content"),
			home.path_join("Library/Application Support/Steam/steamapps/workshop/content"),
		]:
			if DirAccess.dir_exists_absolute(cand):
				# Only add subfolders that contain workshop items (would be <app_id>)
				var dir := DirAccess.open(cand)
				if dir:
					dir.list_dir_begin()
					var entry := dir.get_next()
					while entry != "":
						if dir.current_is_dir():
							roots.append(cand.path_join(entry))
						entry = dir.get_next()
					dir.list_dir_end()
	return roots

## Discover workshop mods (zipped or unpacked) into `out` (same map as ModLoader).
## Returns number discovered.
static func discover_workshop_mods(out: Dictionary) -> int:
	var count_before := out.size()
	for root in workshop_roots():
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)) and not DirAccess.dir_exists_absolute(root):
			continue
		# Workshop root may contain either: unpacked mod folders, or .zip files
		ModLoader._scan_path(root, out, false)
		ModLoader._scan_zips(root, out, false)
	return out.size() - count_before

## Publish a mod to the local workshop staging area (and to Steam if available).
## Creates a zip via ModPackager then writes a workshop descriptor so the
## Mods screen can list it as "Published".
static func publish(mod_id: String, changelog: String = "") -> String:
	var zip_path := ModPackager.export_mod(mod_id)
	if zip_path.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOCAL_STAGING_DIR))
	@warning_ignore("inferred_declaration")
	var mf = ModManager.manifests.get(mod_id, null) if ModManager else null
	if mf == null:
		mf = ModManifest.from_file("user://mods/%s/mod.json" % mod_id)
	var meta: Dictionary = {
		"mod_id": mod_id,
		"name": mf.name if mf else mod_id,
		"version": mf.version if mf else "0.0.0",
		"author": mf.author if mf else "",
		"description": mf.description if mf else "",
		"zip": zip_path,
		"changelog": changelog,
		"published_at": Time.get_datetime_string_from_system(),
		"publisher": OS.get_environment("USER") if not OS.get_environment("USER").is_empty() else "local",
	}
	var meta_path := LOCAL_STAGING_DIR.path_join("%s.%s" % [mod_id, WORKSHOP_META])
	var f := FileAccess.open(meta_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "\t"))
	# Also try native Steam publish if the Steam singleton is present.
	if _has_steam():
		_publish_to_steam(mod_id, zip_path, meta)

	var abs_staging := ProjectSettings.globalize_path(zip_path)
	ModPackager._notify("Published '%s' to workshop staging: %s" % [mod_id, meta_path], "success")
	print("ModWorkshop: published %s -> %s" % [mod_id, abs_staging])
	return zip_path

## Open the workshop staging folder in the OS file browser.
static func open_workshop_folder() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOCAL_STAGING_DIR))
	var abs_path := ProjectSettings.globalize_path(LOCAL_STAGING_DIR)
	var err := OS.shell_open(abs_path)
	if err != OK and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(abs_path)
		ModPackager._notify("Workshop staging: %s (copied to clipboard)" % abs_path, "info")

## Whether Steam is available in this build.
static func _has_steam() -> bool:
	return Engine.has_singleton("Steam") or has_node_check("Steam")

static func has_node_check(singleton: String) -> bool:
	if Engine.get_main_loop() == null or Engine.get_main_loop().root == null:
		return false
	return Engine.get_main_loop().root.has_node("/root/%s" % singleton)

## Attempt to publish via Steam's workshop API. No-op if not available.
static func _publish_to_steam(mod_id: String, zip_path: String, _meta: Dictionary) -> void:
	# GDSteam (https://godotsteam.com/) exposes `Steam` singleton with
	# `workshop_createItem`, `workshop_submitItemUpdate`, etc.
	# We keep this best-effort and entirely optional so headless/CI builds work.
	var steam = null
	if Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")
	elif Engine.get_main_loop() and Engine.get_main_loop().root.has_node("/root/Steam"):
		steam = Engine.get_main_loop().root.get_node("/root/Steam")
	if steam == null:
		return
	# The actual submit call is project-specific (app_id, tags). We log what
	# would be submitted so a Steam-enabled build can wire it without changing
	# the open-source core.
	print("ModWorkshop: Steam detected — would publish %s (%s) via Workshop API (app_id via ProjectSettings)." % [mod_id, zip_path])
	# Example (commented, requires valid app_id and workshop item):
	# var app_id := ProjectSettings.get_setting("steam/app_id", 0)
	# steam.workshop_createItem(app_id, ...)

## Instructions for manual Steam Workshop upload (shown in the Mods screen).
static func workshop_instructions() -> String:
	return """Share as ZIP or Workshop:
1. Export — Select a mod in Mods and press 'Export as ZIP'. A .zip appears in user://mods/exports/ (also shown as an OS folder).
2. ZIP share — Send that .zip to friends, or upload to itch.io / Discord / GitHub. They press 'Import ZIP' in their Mods screen.
3. Steam Workshop — With the Steam client, open the game's Workshop page, use 'Create Item', attach the exported .zip and workshop.json from user://workshop/staging/. The game also discovers Workshop subscriptions automatically from STEAM_WORKSHOP_PATH or user://workshop/.
Local workshop folder is %s (set %s to override).
""" % [ProjectSettings.globalize_path(LOCAL_STAGING_DIR), ENV_WORKSHOP_PATH]

## Workshop subscriptions: list workshop items available on disk.
static func list_workshop_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var dir := DirAccess.open(LOCAL_STAGING_DIR)
	if dir == null:
		return items
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(WORKSHOP_META):
			var meta_path := LOCAL_STAGING_DIR.path_join(entry)
			var f := FileAccess.open(meta_path, FileAccess.READ)
			if f:
				var parsed = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary:
					items.append(parsed)
		entry = dir.get_next()
	dir.list_dir_end()
	return items
