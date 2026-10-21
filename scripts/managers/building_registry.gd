extends Node
## BuildingRegistry - Manages all building types and their properties

const REQUIRED_BUILDING_FIELDS := ["id", "name", "size", "cost"]

var buildings: Dictionary = {}

func _ready() -> void:
	_load_buildings()

func _load_buildings() -> void:
	# The merged catalog: data/buildings.json plus every enabled mod's
	# additions and overrides, in load order (ContentRegistry).
	var raw_buildings: Dictionary = ContentRegistry.get_buildings()
	if raw_buildings.is_empty():
		push_error("Failed to load buildings.json")
		return

	var valid_count := 0
	for key in raw_buildings:
		var building = raw_buildings[key]
		if not building is Dictionary:
			push_warning("Building '%s': expected Dictionary, got %s — skipping" % [key, typeof(building)])
			continue

		# Validate required fields
		var missing_fields: Array = []
		for field in REQUIRED_BUILDING_FIELDS:
			if not building.has(field):
				missing_fields.append(field)
		if not missing_fields.is_empty():
			push_warning("Building '%s': missing required fields %s — skipping" % [key, missing_fields])
			continue

		# Validate size is a 2-element array
		var size = building.get("size")
		if not size is Array or size.size() != 2:
			push_warning("Building '%s': 'size' must be [width, height] — got %s, defaulting to [1, 1]" % [key, size])
			building["size"] = [1, 1]

		# Validate cost is a non-negative number
		var cost = building.get("cost", 0)
		if not (cost is int or cost is float) or cost < 0:
			push_warning("Building '%s': 'cost' must be non-negative number — got %s, defaulting to 0" % [key, cost])
			building["cost"] = 0

		buildings[key] = building
		valid_count += 1

	print("Loaded %d building types (%d validated)" % [raw_buildings.size(), valid_count])

func get_building(building_type: String) -> Dictionary:
	return buildings.get(building_type, {})

func get_all_buildings() -> Dictionary:
	return buildings.duplicate(true)

func get_building_names() -> Array:
	return buildings.keys()

func is_valid_building(building_type: String) -> bool:
	return building_type in buildings

func get_building_cost(building_type: String) -> int:
	return buildings.get(building_type, {}).get("cost", 0)

func get_building_size(building_type: String) -> Array:
	return buildings.get(building_type, {}).get("size", [1, 1])

func get_building_name(building_type: String) -> String:
	return buildings.get(building_type, {}).get("name", building_type)

func can_place_on_course(building_type: String) -> bool:
	return buildings.get(building_type, {}).get("placeable_on_course", false)

func is_available_for_theme(building_type: String, theme_type: int) -> bool:
	return BuildingAvailability.is_available(buildings.get(building_type, {}), theme_type)

func get_available_buildings(theme_type: int) -> Dictionary:
	var available: Dictionary = {}
	for building_type in BuildingAvailability.available_types(buildings, theme_type):
		available[building_type] = buildings[building_type]
	return available
