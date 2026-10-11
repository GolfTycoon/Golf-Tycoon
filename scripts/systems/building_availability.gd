extends RefCounted
class_name BuildingAvailability
## BuildingAvailability - Which locations (course themes) a building is offered at.
##
## Every building in the catalogue carries an `availability` block:
##
##   { "all": true }                                  every location
##   { "all": true, "excluded_themes": ["links"] }   everywhere except listed themes
##   { "only_themes": ["desert"] }                    only the listed themes
##
## Theme names are the CourseTheme string names ("parkland", "links", ...).
## The Buildings tab, the placement flow and the course generators all read
## the same rules through this class.

## Buildings whose availability block is missing or malformed are treated as
## buildable everywhere rather than being silently dropped from the catalogue.
static func is_available(building_data: Dictionary, theme_type: int) -> bool:
	var theme_name := CourseTheme.to_string_name(theme_type)
	var availability = building_data.get("availability")
	if availability == null:
		return true
	if not availability is Dictionary:
		return true
	var rules: Dictionary = availability
	var only = rules.get("only_themes")
	if only is Array and not only.is_empty():
		return theme_name in only
	var excluded = rules.get("excluded_themes")
	if excluded is Array and theme_name in excluded:
		return false
	return true

## The building ids of a registry (the raw buildings.json `buildings` map)
## that a course with `theme_type` may build, in catalogue order.
static func available_types(registry: Dictionary, theme_type: int) -> Array:
	var types: Array = []
	for building_type in registry:
		var data = registry[building_type]
		if not data is Dictionary:
			continue
		if is_available(data, theme_type):
			types.append(building_type)
	return types

## Short, human-readable availability line for tooltips and info panels.
static func availability_note(building_data: Dictionary) -> String:
	var availability = building_data.get("availability")
	if not availability is Dictionary:
		return "Available on all locations."
	var rules: Dictionary = availability
	var only = rules.get("only_themes")
	if only is Array and not only.is_empty():
		var names: Array = []
		for theme_name in only:
			names.append(_theme_display_name(str(theme_name)))
		return "Available on all locations that use the %s Course Theme." % _join(names)
	var excluded = rules.get("excluded_themes")
	if excluded is Array and not excluded.is_empty():
		var names: Array = []
		for theme_name in excluded:
			names.append(_theme_display_name(str(theme_name)))
		return "Available on all locations unless it uses the %s Course Theme%s." % [
			_join(names), "" if names.size() == 1 else "s"]
	return "Available on all locations."

static func _theme_display_name(theme_name: String) -> String:
	return CourseTheme.get_theme_name(CourseTheme.from_string(theme_name))

static func _join(names: Array) -> String:
	match names.size():
		0: return ""
		1: return str(names[0])
		2: return "%s or %s" % [names[0], names[1]]
	var joined := ""
	for i in range(names.size() - 1):
		joined += str(names[i]) + ", "
	return joined + "or " + str(names[names.size() - 1])
