extends RefCounted
class_name Mod
## Mod - Runtime wrapper around a ModManifest + its loaded code.
##
## Created by ModManager when a mod is discovered. Holds manifest, load
## state, error info, and the instantiated hook object (if any). Provides
## lifecycle: validate -> load -> enable -> disable -> unload.

enum State { DISCOVERED, VALIDATED, LOADED, ENABLED, DISABLED, FAILED }

var manifest: ModManifest = null
var state: int = State.DISCOVERED
var enabled: bool = false
## Position in the ordered enabled list (0 = first, loads first). -1 = not enabled.
var load_order: int = -1
var error_message: String = ""
## Instance of the entry_point script (has _mod_* hooks).
var instance: Object = null
## When this mod was last loaded (for hot-reload).
var loaded_at: int = 0
## Whether this mod's hooks are currently active.
var hooks_active: bool = false
## List of hooks this mod registered (for cleanup).
var registered_hooks: Array[Dictionary] = []
## Content contributed (cached for conflict reporting).
var contributed_content: Dictionary = {}

func _init(manifest_: ModManifest) -> void:
	manifest = manifest_
	if manifest:
		enabled = manifest.enabled_by_default

func get_id() -> String:
	return manifest.id if manifest else ""

func get_name() -> String:
	return manifest.name if manifest else "Unknown"

func is_builtin() -> bool:
	return manifest.is_builtin if manifest else false

func has_entry_point() -> bool:
	return manifest != null and not manifest.entry_point.is_empty()

## Validate this mod's manifest and entry point.
func validate(_all_manifests: Dictionary) -> bool:
	if manifest == null or not manifest.is_valid():
		state = State.FAILED
		error_message = "Invalid manifest"
		return false
	# Check entry point exists
	if has_entry_point():
		if not ResourceLoader.exists(manifest.entry_point):
			state = State.FAILED
			error_message = "Entry point not found: %s" % manifest.entry_point
			return false
		# Try to load to verify it compiles
		var script: Script = load(manifest.entry_point)
		if script == null:
			state = State.FAILED
			error_message = "Failed to load entry script: %s" % manifest.entry_point
			return false
	# Dependencies will be checked by ModManager at enable-time (ordering)
	# Conflicts are warnings, not failures — later mod wins
	state = State.VALIDATED
	error_message = ""
	return true

## Instantiate the mod's entry script. Called when the mod is enabled.
func load_instance(api: ModAPI = null) -> bool:
	if not has_entry_point():
		state = State.LOADED
		loaded_at = Time.get_ticks_msec()
		return true
	var script: Script = load(manifest.entry_point)
	if script == null:
		state = State.FAILED
		error_message = "Failed to load script: %s" % manifest.entry_point
		return false
	# Create instance — pass ModAPI if the mod's _init expects it
	instance = script.new()
	if instance == null:
		state = State.FAILED
		error_message = "Failed to instantiate mod script"
		return false
	# Inject api reference if the script has an `api` property
	if api != null and "api" in instance:
		instance.api = api
	if "mod_manifest" in instance:
		instance.mod_manifest = manifest
	# Call mod's on_load hook if present
	if instance.has_method("_mod_on_load"):
		var ok := _call_safely("_mod_on_load", [])
		if not ok:
			state = State.FAILED
			return false
	state = State.LOADED
	loaded_at = Time.get_ticks_msec()
	return true

func unload_instance() -> void:
	if instance != null:
		if instance.has_method("_mod_on_unload"):
			_call_safely("_mod_on_unload", [])
		# If instance is a Node inside the tree, remove it
		if instance is Node and instance.is_inside_tree():
			instance.get_parent().remove_child(instance)
			instance.queue_free()
		instance = null
	state = State.DISCOVERED
	hooks_active = false
	registered_hooks.clear()

## Enable this mod (load + activate hooks).
func enable(api: ModAPI = null) -> bool:
	if enabled and state == State.ENABLED:
		return true
	if state == State.FAILED:
		return false
	if state == State.DISCOVERED:
		if not validate({}):
			return false
	if state != State.LOADED:
		if not load_instance(api):
			return false
	enabled = true
	state = State.ENABLED
	# Activate hooks
	if instance != null and instance.has_method("_mod_on_enable"):
		_call_safely("_mod_on_enable", [])
	hooks_active = true
	return true

func disable() -> void:
	if not enabled:
		return
	enabled = false
	hooks_active = false
	if instance != null and instance.has_method("_mod_on_disable"):
		_call_safely("_mod_on_disable", [])
	# Keep instance loaded but inactive; full unload happens on manager reload
	state = State.DISABLED

func _call_safely(method: String, args: Array) -> bool:
	if instance == null or not instance.has_method(method):
		return true
	var result = instance.callv(method, args)
	# Mods return false to signal failure
	if result is bool and result == false:
		error_message = "Mod hook %s returned false" % method
		push_warning("Mod %s: %s failed: %s" % [get_id(), method, error_message])
		return false
	return true

func get_status_text() -> String:
	match state:
		State.DISCOVERED: return "Discovered"
		State.VALIDATED: return "Validated"
		State.LOADED: return "Loaded"
		State.ENABLED: return "Enabled"
		State.DISABLED: return "Disabled"
		State.FAILED: return "Failed: %s" % error_message
	return "Unknown"

func to_dict() -> Dictionary:
	return {
		"id": get_id(),
		"name": get_name(),
		"version": manifest.version if manifest else "0.0.0",
		"enabled": enabled,
		"load_order": load_order,
		"state": state,
		"error": error_message,
		"is_builtin": is_builtin(),
	}
