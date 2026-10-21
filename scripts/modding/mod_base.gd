extends Node
class_name GolfTycoonMod
## GolfTycoonMod - The base class every script mod's entry point extends.
##
## A script mod is one `.gd` file (the manifest's `entry_point`) that starts
## with `extends GolfTycoonMod`. The loader creates it, adds it to the scene
## tree under the ModManager, and calls `_mod_load(api)` with a ModAPI bound
## to the mod. From there the mod registers whatever it provides - an
## environment system, a hook, a HUD widget - and listens to the game's
## EventBus signals like any other system.
##
## Mod scripts must not rely on their own `class_name` declarations: only the
## base game's global classes are registered. Load sibling files with
## preload() using paths relative to the script, exactly as the bundled
## example mods under res://mods/ do - that is what lets the same mod run
## unchanged from a folder, an installed zip or a Steam Workshop item.
##
## The lifecycle, in order:
##   _mod_load(api)   once, when the loader reaches this mod in load order
##   _mod_new_game()  when a brand new company starts (also on EventBus)
##   _mod_save()      whenever the game saves; return a Dictionary to store
##   _mod_restore(d)  after a save loads, with what _mod_save returned
##   _mod_unload()    when mods are reloaded or the mod is switched off

## This mod's id, from its manifest (set before `_mod_load`).
var mod_id: String = ""
## The Mod API bound to this mod (set before `_mod_load`).
var api: ModAPI = null


## Called once when the mod loads. Register providers, hooks and UI here,
## and connect the EventBus signals the mod lives by.
func _mod_load(_mod_api: ModAPI) -> void:
	pass


## Called when the mod is switched off or the mod set is reloaded. Undo
## anything the loader cannot undo for the mod: the loader already drops the
## mod's data, hooks, providers and widgets, and frees this node right
## after - so only outside-the-mod changes (a node added to the main scene,
## say) need tidying here.
func _mod_unload() -> void:
	pass


## Called when a new game starts, after the world has been rolled. The same
## moment is on EventBus (`new_game_started`); this hook is for mods that
## would rather not manage a connection.
func _mod_new_game() -> void:
	pass


## Return this mod's slice of the save file - plain JSON-shaped data only
## (dictionaries, arrays, numbers, strings, bools). It is stored under the
## mod's id, so it can never collide with another mod's. Return {} (the
## default) for nothing to store.
func _mod_save() -> Dictionary:
	return {}


## Handed back exactly what `_mod_save` returned, after the rest of the save
## has been applied. A save from before the mod existed - or made without it
## - calls this with {}.
func _mod_restore(_data: Dictionary) -> void:
	pass
