extends GolfTycoonMod
## My Mod - entry point skeleton.
##
## Copy the whole _template folder, rename it, and:
##   1. set your own id/name/version in mod.json (the id namespaces
##      everything your mod adds - make it yours and never change it),
##   2. either declare data under "content" in mod.json (a data mod needs
##      no script at all - delete this file and the entry_point/permissions
##      lines), or write your system here,
##   3. develop it in place: a folder here, in user://mods/ or zipped by
##      tools/mod_tool.gd all load the same way.
##
## Rules that keep a mod loadable everywhere (details in
## docs/modding/mod-api.md):
##   * no class_name in your files - preload() siblings by relative path,
##   * keep all state you need across a save in _mod_save/_mod_restore,
##   * undo in _mod_unload whatever you added outside the registry.


func _mod_load(mod_api: ModAPI) -> void:
	# Register providers, hooks and HUD widgets; connect EventBus signals.
	mod_api.log_info("Hello from %s (Mod API %d, game %s)." % [
		mod_id, mod_api.api_version(), mod_api.game_version()])


func _mod_unload() -> void:
	# Disconnect signals and free nodes you added to the main scene. Data,
	# hooks and providers registered through the API are undone for you.
	pass


func _mod_new_game() -> void:
	# A brand new company just started.
	pass


func _mod_save() -> Dictionary:
	# Plain JSON-shaped state to keep in the save file, or {} for none.
	return {}


func _mod_restore(_data: Dictionary) -> void:
	# The dictionary _mod_save returned ({} for older or foreign saves).
	pass
