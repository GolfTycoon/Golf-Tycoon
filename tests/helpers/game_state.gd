extends RefCounted
## A snapshot of the game's global state, so a test can put back what it changed.
##
## GameManager and WorldMap are autoloads: whatever a test does to them — the
## grid, course or managers it swaps in, the money it spends, the clock it
## pauses, the locations its company buys — would still be there for every test
## that runs after it. capture() records every field of both (arrays and
## dictionaries are copied, so changes made to them in place are undone too),
## the seasons switch, the engine's time scale, input device and pointer, and
## the player's key bindings, and restore() puts them all back. An object the test freed meanwhile is put
## back as null.
##
## Used by GameTest around every unit test, and by MainSceneTest around each
## integration script.

## Computed GameManager properties: they read other fields and have nothing of
## their own.
const COMPUTED_FIELDS: Array[String] = ["course_data", "game_mode"]

static func capture() -> Dictionary:
	return {
		"game_manager": _fields_of(GameManager, COMPUTED_FIELDS),
		"world_map": _fields_of(WorldMap, []),
		"seasons_disabled": SeasonSystem.disabled,
		"time_scale": Engine.time_scale,
		"input_bindings": InputBindings.capture_state(),
		"input_device": InputManager.device,
		"input_pointer_mode": InputManager.pointer_mode,
		"input_virtual_pointer": InputManager.virtual_pointer,
		"input_synthetic_mouse_depth": InputManager._synthetic_mouse_depth,
	}

static func restore(state: Dictionary) -> void:
	_put_back(WorldMap, state.get("world_map", {}))
	_put_back(GameManager, state.get("game_manager", {}))
	SeasonSystem.disabled = state.get("seasons_disabled", false)
	Engine.time_scale = state.get("time_scale", 1.0)
	InputManager.device = state.get("input_device", InputManager.Device.MOUSE)
	InputManager.pointer_mode = state.get("input_pointer_mode", false)
	InputManager.virtual_pointer = state.get("input_virtual_pointer", Vector2.INF)
	InputManager._synthetic_mouse_depth = state.get("input_synthetic_mouse_depth", 0)
	var bindings: Variant = state.get("input_bindings", {})
	if bindings is Dictionary:
		InputBindings.restore_state(bindings)

## Every script variable of `node` but the `skipped` ones, by name.
static func _fields_of(node: Node, skipped: Array[String]) -> Dictionary:
	var fields: Dictionary = {}
	for property in node.get_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field: String = property.name
		if field in skipped:
			continue
		var value: Variant = node.get(field)
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		fields[field] = value
	return fields

static func _put_back(node: Node, fields: Dictionary) -> void:
	for field in fields:
		var value: Variant = fields[field]
		if value is Object and not is_instance_valid(value):
			value = null
		elif value is Array or value is Dictionary:
			value = value.duplicate(true)
		node.set(field, value)
