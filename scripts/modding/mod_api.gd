extends RefCounted
class_name ModAPI
## ModAPI - The stable surface a mod talks to the game through.
##
## Every mod gets its own ModAPI, bound to its id, in `_mod_load`. Everything
## a mod registers through the API - providers, hooks, widgets, sprites -
## is stamped with that id, which is what lets the loader undo a mod cleanly
## and tell the player which mod provided what.
##
## Stability promise: within one Mod API major version
## (ModManifest.CURRENT_API_VERSION) these methods keep their names and
## meanings; new ones may be added, old ones are not renamed or repurposed.
## The full reference is docs/modding/mod-api.md.

var mod_id: String = ""
var _manager: Node = null  # The ModManager autoload (typed loosely on purpose).
var _mod_root: String = ""


func _init(p_mod_id: String, manager: Node, p_mod_root: String) -> void:
	mod_id = p_mod_id
	_manager = manager
	_mod_root = p_mod_root


# =============================================================================
# VERSIONS AND NEIGHBOURS
# =============================================================================

func api_version() -> int:
	return ModManifest.CURRENT_API_VERSION


func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Is another mod loaded (useful for optional integrations between mods)?
func is_mod_loaded(other_id: String) -> bool:
	return _manager != null and _manager.is_mod_loaded(other_id)


func get_mod_version(other_id: String) -> String:
	return str(_manager.get_mod_version(other_id)) if _manager != null else ""


## The ids of every loaded mod, in load order.
func get_load_order() -> Array:
	return _manager.get_load_order() if _manager != null else []


# =============================================================================
# THE MOD'S OWN FILES
# =============================================================================

## The folder this mod was loaded from (res:// for bundled mods, user:// for
## installed ones, a Workshop path for Steam items).
func mod_root() -> String:
	return _mod_root


## A path inside the mod's own folder.
func path(relative: String) -> String:
	return _mod_root.path_join(relative)


func file_exists(relative: String) -> bool:
	return FileAccess.file_exists(path(relative))


func read_text(relative: String) -> String:
	return FileAccess.get_file_as_string(path(relative))


## Parsed JSON from a file in the mod, or null when it will not parse.
func read_json(relative: String) -> Variant:
	return ModManifest.parse_json_quietly(read_text(relative))


## A texture from a raw image file (PNG/JPG) in the mod. Works from every
## mod source because the bytes are decoded directly - mods never need
## Godot's import pipeline.
func load_texture(relative: String) -> Texture2D:
	if _manager != null:
		return _manager.load_mod_texture(mod_id, path(relative))
	return null


# =============================================================================
# LOGGING AND PLAYER-FACING MESSAGES
# =============================================================================

func log_info(message: String) -> void:
	print("[%s] %s" % [mod_id, message])


func log_warning(message: String) -> void:
	push_warning("[%s] %s" % [mod_id, message])


func log_error(message: String) -> void:
	push_error("[%s] %s" % [mod_id, message])


## A toast in the game's notification feed. `kind` is "info", "warning",
## "error" or "success", matching EventBus.notify.
func notify(message: String, kind: String = "info") -> void:
	EventBus.notify(message, kind)


# =============================================================================
# PROVIDERS (taking over a game system behind its stable facade)
# =============================================================================

## Provide the game's weather. `factory` is called with no arguments and
## must return a WeatherSystem (the bundled Weather mod returns its own
## subclass with spells and fronts). The last mod in load order to register
## wins; with none, the game uses the neutral WeatherSystem base - always
## sunny, nothing affected.
func register_weather_factory(factory: Callable) -> void:
	if _manager != null:
		_manager.register_weather_factory(mod_id, factory)


## Provide the game's wind; same contract as register_weather_factory.
func register_wind_factory(factory: Callable) -> void:
	if _manager != null:
		_manager.register_wind_factory(mod_id, factory)


## Provide the seasons: a SeasonProvider whose tables SeasonSystem reads.
func register_season_provider(provider: SeasonProvider) -> void:
	if _manager != null:
		_manager.register_season_provider(mod_id, provider)


# =============================================================================
# HOOKS, UI AND ART
# =============================================================================

## Join a named value chain. The game passes a number (a spawn rate, a cost)
## through every registered hook in load order; each hook receives
## (value: float, context: Dictionary) and returns the new value. The hooks
## the game calls are listed in docs/modding/mod-api.md.
func add_hook(hook_name: String, callable: Callable) -> void:
	if _manager != null:
		_manager.add_hook(mod_id, hook_name, callable)


## Add a widget to the course HUD. `factory` is called (with no arguments)
## when the main scene builds its HUD and must return a Control, which is
## added to the HUD layer. Position it with anchors/offsets as usual.
func register_hud_widget(factory: Callable) -> void:
	if _manager != null:
		_manager.register_hud_widget(mod_id, factory)


## Run `callable(main)` when the main scene is ready - immediately if it
## already is. The same moment is EventBus.main_scene_ready.
func on_main_scene_ready(callable: Callable) -> void:
	if _manager != null:
		_manager.call_on_main_scene_ready(mod_id, callable)


## Give one of this mod's buildings real art: a PNG inside the mod and the
## rectangle, in the building node's local draw space, the art covers (see
## BuildingSprites for that space; other buildings' rects live in
## assets/sprites/buildings/sprites.json). `building_id` is the id used in
## the mod's data, bare or namespaced. Without this call a building draws
## the built-in procedural stand-in in its data's `color`.
func register_building_sprite(building_id: String, relative_png: String, draw_rect: Rect2) -> bool:
	var texture_value: Texture2D = load_texture(relative_png)
	if texture_value == null:
		log_warning("No readable image at '%s' for building '%s'." % [relative_png, building_id])
		return false
	var content: Node = get_content_registry()
	var full_id: String = building_id
	if content != null and not building_id.contains(":") and not content.has_building(building_id):
		full_id = content.resolve_new_id(mod_id, building_id)
	BuildingSprites.register_mod_sprite(full_id, texture_value, draw_rect)
	return true


# =============================================================================
# CONTENT AND CONFIG
# =============================================================================

## The merged content registry (every mod's data plus the base game's).
## Most mods never need it - declaring content in mod.json does the same
## job - but a script mod can read what the player is actually playing with.
func get_content_registry() -> Node:
	return _manager.content_registry() if _manager != null else null


## A tuning value from the merged data (see ContentRegistry.get_tuning).
func get_tuning(key: String, default_value: float) -> float:
	var content: Node = get_content_registry()
	return content.get_tuning(key, default_value) if content != null else default_value


## One of this mod's own config values: the manifest's declared default,
## unless the player (or the mod) has set it. Config is per-player, kept in
## user://mods/config/<mod id>.json, and never travels in save files - use
## _mod_save/_mod_restore for per-save state.
func get_config_value(key: String, fallback: Variant = null) -> Variant:
	return _manager.get_mod_config_value(mod_id, key, fallback) if _manager != null else fallback


func set_config_value(key: String, value: Variant) -> void:
	if _manager != null:
		_manager.set_mod_config_value(mod_id, key, value)
