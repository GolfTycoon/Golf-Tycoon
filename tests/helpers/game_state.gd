extends RefCounted
## A snapshot of the game's global state, so a test can put back what it changed.
##
## GameManager and WorldMap are autoloads: whatever a test does to them — the
## grid, course or managers it swaps in, the money it spends, the clock it
## pauses, the locations its company buys — would still be there for every test
## that runs after it. capture() records every field of both (arrays and
## dictionaries are copied, so changes made to them in place are undone too),
## the seasons switch and the engine's time scale, and restore() puts them all
## back. An object the test freed meanwhile is put back as null.
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
	}

static func restore(state: Dictionary) -> void:
	_put_back(WorldMap, state.get("world_map", {}))
	_put_back(GameManager, state.get("game_manager", {}))
	SeasonSystem.disabled = state.get("seasons_disabled", false)
	Engine.time_scale = state.get("time_scale", 1.0)

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
