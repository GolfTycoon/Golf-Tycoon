extends RefCounted
class_name ModAPI
## ModAPI - Safe, versioned interface exposed to mods.
##
## Each mod receives a ModAPI instance (via `instance.api = api`) that is
## scoped to that mod. Mods must go through this API to touch game state;
## direct autoload access still works but is discouraged and not stable.
##
## The API is versioned (api_version = "1.0"). Mods declare required api_version
## in their manifest; ModManager checks compatibility before loading.
##
## Design goals:
## - Stable: same calls work across game patches (semver).
## - Safe: all mutations are validated, logged, and conflict-checked.
## - Observable: every registration is tracked for conflict resolution.
## - Reversible: unloading a mod cleanly removes everything it added.

const API_VERSION := "1.0"

var mod_id: String = ""
## Reference to the manager for low-level operations.
var _manager = null  # ModManager (untyped to avoid cycle)

func _init(for_mod_id: String, manager) -> void:
	mod_id = for_mod_id
	_manager = manager

# ---------------------------------------------------------------------------
# Logging & notifications
# ---------------------------------------------------------------------------

func log_info(message: String) -> void:
	print("[Mod:%s] %s" % [mod_id, message])

func log_warning(message: String) -> void:
	push_warning("[Mod:%s] %s" % [mod_id, message])

func log_error(message: String) -> void:
	push_error("[Mod:%s] %s" % [mod_id, message])

func notify_player(message: String, type: String = "info") -> void:
	var eb = Engine.get_main_loop().root.get_node_or_null("EventBus") if Engine.get_main_loop() and Engine.get_main_loop().root else null
	if eb == null and _manager and _manager.has_method("get_node_or_null"):
		eb = _manager.get_node_or_null("/root/EventBus")
	if eb and eb.has_method("notify"):
		eb.notify("[%s] %s" % [mod_id, message], type)

# ---------------------------------------------------------------------------
# Game state (read/write through validated setters)
# ---------------------------------------------------------------------------

func get_money() -> int:
	return GameManager.money if GameManager else 0

func get_day() -> int:
	return GameManager.current_day if GameManager else 1

func get_theme() -> int:
	return GameManager.current_theme if GameManager else 0

func get_course() -> GameManager.CourseData:
	return GameManager.current_course if GameManager else null

func is_mod_enabled(other_id: String) -> bool:
	if _manager:
		return _manager.is_mod_enabled(other_id)
	return false

# ---------------------------------------------------------------------------
# Hook system — observe game events without overriding core logic
# ---------------------------------------------------------------------------
## Register a hook: `event` is a signal name on EventBus (e.g. "day_changed",
## "money_changed", "golfer_spawned"). `callable` is called with the signal's
## args. Returns a handle for unregistering.
func register_hook(event: String, callable: Callable) -> Dictionary:
	if _manager == null:
		log_error("No manager for hook registration")
		return {}
	return _manager.register_hook(mod_id, event, callable)

func unregister_hook(handle: Dictionary) -> void:
	if _manager:
		_manager.unregister_hook(handle)

## Register a per-frame callback (called every _process). Use sparingly.
func register_tick(callable: Callable) -> Dictionary:
	return register_hook("__tick__", callable)

# ---------------------------------------------------------------------------
# Content registries — add new game content
# ---------------------------------------------------------------------------

func register_building_type(id: String, data: Dictionary) -> bool:
	if _manager == null:
		return false
	return _manager.register_building_type(mod_id, id, data)

func register_decoration_type(id: String, data: Dictionary) -> bool:
	if _manager == null:
		return false
	return _manager.register_decoration_type(mod_id, id, data)

func register_terrain_type(id: String, data: Dictionary) -> bool:
	if _manager == null:
		return false
	return _manager.register_terrain_type(mod_id, id, data)

func register_golfer_trait(id: String, data: Dictionary) -> bool:
	if _manager == null:
		return false
	return _manager.register_trait(mod_id, id, data)

func register_seasonal_event(event_data: Dictionary) -> bool:
	if _manager == null:
		return false
	return _manager.register_seasonal_event(mod_id, event_data)

## Override an existing building/decoration by id. Last-enabled mod wins.
func override_building_type(id: String, patch: Dictionary) -> bool:
	if _manager == null:
		return false
	return _manager.override_building_type(mod_id, id, patch)

## Add a hook that modifies a calculation (e.g. spawn rate, maintenance).
## `modifier` is a Callable that takes (current_value: float, context: Dictionary) -> float
func register_modifier(modifier_id: String, callable: Callable) -> Dictionary:
	if _manager == null:
		return {}
	return _manager.register_modifier(mod_id, modifier_id, callable)

func unregister_modifier(handle: Dictionary) -> void:
	if _manager:
		_manager.unregister_modifier(handle)

# ---------------------------------------------------------------------------
# UI extension
# ---------------------------------------------------------------------------

func add_settings_section(title: String, panel_builder: Callable) -> Dictionary:
	if _manager == null:
		return {}
	return _manager.register_ui_section(mod_id, title, panel_builder)

func add_main_menu_action(label: String, icon: int, action: Callable) -> Dictionary:
	if _manager == null:
		return {}
	return _manager.register_menu_action(mod_id, label, icon, action)

# ---------------------------------------------------------------------------
# Save data — per-save mod state
# ---------------------------------------------------------------------------

func set_save_data(key: String, value) -> void:
	if _manager:
		_manager.set_mod_save_data(mod_id, key, value)

func get_save_data(key: String, default = null):
	if _manager:
		return _manager.get_mod_save_data(mod_id, key, default)
	return default

# ---------------------------------------------------------------------------
# Feature flags — declare/query gameplay features (weather, wind, seasons, etc.)
# ---------------------------------------------------------------------------

func register_feature(feature_id: String, feature_name: String, description: String) -> bool:
	if _manager == null:
		return false
	return _manager.register_feature(mod_id, feature_id, feature_name, description)

func is_feature_enabled(feature_id: String) -> bool:
	if _manager:
		return _manager.is_feature_enabled(feature_id)
	# Fallback to GameManager feature flags
	if GameManager and GameManager.has_method("is_feature_enabled"):
		return GameManager.is_feature_enabled(feature_id)
	return false

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func get_mod_manifest(other_id: String) -> ModManifest:
	if _manager:
		return _manager.get_manifest(other_id)
	return null

func get_enabled_mods() -> Array[String]:
	if _manager:
		return _manager.get_enabled_mods_ordered()
	return []

func get_api_version() -> String:
	return API_VERSION
