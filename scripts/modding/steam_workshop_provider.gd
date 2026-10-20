extends RefCounted
class_name SteamWorkshopProvider
## SteamWorkshopProvider - The Steam Workshop as just another place mods
## come from.
##
## Golf Tycoon talks to Steam through the GodotSteam addon (the `Steam`
## engine singleton) when it is present, and not at all when it is not: this
## class looks the singleton up dynamically, so the game builds and runs
## identically with or without GodotSteam installed. Steam builds ship the
## addon and set `modding/steam_app_id` in project.godot; every other build
## simply finds `is_available()` false and the Workshop buttons explain
## themselves.
##
## A Workshop item for this game is the same thing as every other mod: a
## folder holding mod.json and the mod's files (the item's content is that
## folder - no special packaging). Subscribed items therefore flow into the
## exact same discovery, ordering, loading and conflict rules as a folder in
## user://mods, and are shown in the Mods screen with a Workshop badge.

## Project setting the Steam build fills in (0 = not a Steam build).
const APP_ID_SETTING: String = "modding/steam_app_id"

var _steam: Object = null
var _probed: bool = false


## True when GodotSteam is installed and Steam answered. Probed once.
func is_available() -> bool:
	if not _probed:
		_probed = true
		if Engine.has_singleton("Steam"):
			var candidate: Object = Engine.get_singleton("Steam")
			# GodotSteam exposes the UGC calls the Workshop needs.
			if candidate != null and candidate.has_method("getSubscribedItems"):
				_steam = candidate
	return _steam != null


func app_id() -> int:
	return int(ProjectSettings.get_setting(APP_ID_SETTING, 0))


## [{published_file_id, folder}] for every subscribed item that is actually
## downloaded. `folder` is an absolute filesystem path - a mod root the
## manager can read exactly like a folder mod.
func get_subscribed_mod_roots() -> Array:
	var roots: Array = []
	if not is_available():
		return roots
	var subscribed: Variant = _steam.call("getSubscribedItems")
	if not (subscribed is Array or subscribed is PackedInt64Array):
		return roots
	for published_file_id in subscribed:
		var file_id: int = int(published_file_id)
		var folder: String = _install_folder(file_id)
		if not folder.is_empty():
			roots.append({"published_file_id": file_id, "folder": folder})
	return roots


func _install_folder(published_file_id: int) -> String:
	if _steam == null or not _steam.has_method("getItemInstallInfo"):
		return ""
	# GodotSteam: {size_on_disk, folder, timestamp} - key spellings have
	# varied slightly between releases, so read defensively.
	var info: Variant = _steam.call("getItemInstallInfo", published_file_id)
	if info is Dictionary:
		var folder: String = str(info.get("folder", info.get("install_folder", "")))
		if not folder.is_empty() and DirAccess.dir_exists_absolute(folder):
			return folder
	return ""


## Open the game's Workshop page (overlay when Steam has one up, browser
## otherwise). False when there is nowhere to open.
func open_workshop_page() -> bool:
	if app_id() <= 0:
		return false
	var url: String = "https://steamcommunity.com/app/%d/workshop/" % app_id()
	if is_available() and _steam.has_method("activateGameOverlayToWebPage"):
		_steam.call("activateGameOverlayToWebPage", url)
		return true
	return OS.shell_open(url) == OK


## Create or update a Workshop item from a mod folder. The manifest's
## `workshop` block drives it: published_file_id (0 creates a new item,
## and the new id is written back into mod.json by the caller-facing result
## message), title/description default to the mod's name/description,
## "preview" names a preview image inside the mod (default "preview.png"),
## "tags" and "visibility" ("public" | "friends" | "private").
##
## Steam item creation is asynchronous (create, then an update submit, each
## answered by callback); this waits for the two steps so the Mods screen
## and the mod tool can call it plainly. Returns
## {ok: bool, message: String, published_file_id: int}.
func upload_mod(manifest: ModManifest, absolute_folder: String, change_note: String = "") -> Dictionary:
	if not is_available():
		return {"ok": false, "message": "Steam is not available (GodotSteam not present, or Steam is not running).", "published_file_id": 0}
	if app_id() <= 0:
		return {"ok": false, "message": "modding/steam_app_id is not set in project.godot, so there is no Workshop to upload to.", "published_file_id": 0}
	if not _steam.has_method("createItem") or not _steam.has_method("startItemUpdate"):
		return {"ok": false, "message": "This GodotSteam build lacks the UGC upload calls.", "published_file_id": 0}

	var published_file_id: int = manifest.workshop_file_id()
	if published_file_id <= 0:
		var created: Dictionary = await _await_signal("item_created", func() -> void:
			# WorkshopFileType: 0 = community item.
			_steam.call("createItem", app_id(), 0))
		if not bool(created.get("ok", false)):
			return {"ok": false, "message": "Steam did not create the item: %s" % str(created.get("message", "unknown error")), "published_file_id": 0}
		published_file_id = int(created.get("published_file_id", 0))
		if bool(created.get("needs_legal", false)):
			# New creators must accept the Workshop legal agreement once.
			if is_available() and _steam.has_method("activateGameOverlayToWebPage"):
				_steam.call("activateGameOverlayToWebPage",
					"https://steamcommunity.com/sharedfiles/workshoplegalagreement")

	var workshop: Dictionary = manifest.workshop
	var handle: Variant = _steam.call("startItemUpdate", app_id(), published_file_id)
	_call_if("setItemTitle", [handle, str(workshop.get("title", manifest.name))])
	_call_if("setItemDescription", [handle, str(workshop.get("description", manifest.description))])
	_call_if("setItemContent", [handle, absolute_folder])
	var preview: String = str(workshop.get("preview", "preview.png"))
	if FileAccess.file_exists(absolute_folder.path_join(preview)):
		_call_if("setItemPreview", [handle, absolute_folder.path_join(preview)])
	var tags: Array = []
	var raw_tags: Variant = workshop.get("tags", [])
	if raw_tags is Array:
		for tag in raw_tags:
			tags.append(str(tag))
	if not tags.is_empty():
		_call_if("setItemTags", [handle, tags])
	# RemoteStoragePublishedFileVisibility: 0 public, 1 friends, 2 private.
	var visibility: int = int({"public": 0, "friends": 1, "private": 2}.get(
		str(workshop.get("visibility", "public")).to_lower(), 0))
	_call_if("setItemVisibility", [handle, visibility])

	var submitted: Dictionary = await _await_signal("item_updated", func() -> void:
		_steam.call("submitItemUpdate", handle, change_note))
	if not bool(submitted.get("ok", false)):
		return {"ok": false, "message": "Steam did not accept the update: %s" % str(submitted.get("message", "unknown error")), "published_file_id": published_file_id}
	return {"ok": true, "message": "Uploaded. Record workshop.published_file_id = %d in mod.json so the next upload updates this item." % published_file_id,
		"published_file_id": published_file_id}


func _call_if(method: String, args: Array) -> void:
	if _steam != null and _steam.has_method(method):
		_steam.callv(method, args)


## Run `kickoff`, then wait for one of GodotSteam's completion signals. The
## callbacks arrive as (result, published_file_id, needs_legal) flavour
## tuples; normalize them into {ok, message, published_file_id, needs_legal}.
## A mod-facing timeout keeps a dead Steam from hanging the screen forever.
func _await_signal(signal_name: String, kickoff: Callable) -> Dictionary:
	if _steam == null or not _steam.has_signal(signal_name):
		return {"ok": false, "message": "GodotSteam has no '%s' signal." % signal_name}
	var outcome: Dictionary = {"done": false, "ok": false, "message": "", "published_file_id": 0, "needs_legal": false}
	var on_created := func(result: int, file_id: int, needs_legal: bool = false) -> void:
		outcome["done"] = true
		outcome["ok"] = result == 1  # EResult: 1 = OK.
		outcome["message"] = "" if result == 1 else "Steam result %d." % result
		outcome["published_file_id"] = file_id
		outcome["needs_legal"] = needs_legal
	# GodotSteam's UGC signals have different signatures: item_created is
	# (result, id, legal), item_updated is (result, legal).
	var on_updated := func(result: int, needs_legal: bool) -> void:
		outcome["done"] = true
		outcome["ok"] = result == 1
		outcome["message"] = "" if result == 1 else "Steam result %d." % result
		outcome["needs_legal"] = needs_legal
	var callback: Callable = on_created if signal_name == "item_created" else on_updated
	_steam.connect(signal_name, callback, CONNECT_ONE_SHOT)
	kickoff.call()
	var deadline: int = Time.get_ticks_msec() + 120000
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	while not bool(outcome["done"]) and Time.get_ticks_msec() < deadline and tree != null:
		await tree.process_frame
		_call_if("run_callbacks", [])
	if not bool(outcome["done"]):
		if _steam.is_connected(signal_name, callback):
			_steam.disconnect(signal_name, callback)
		outcome["message"] = "Timed out waiting for Steam."
	return outcome
