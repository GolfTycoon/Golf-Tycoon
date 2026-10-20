extends RefCounted
## Seasons Mod - Builtin mod that provides the Seasons/Calendar feature.
##
## When enabled, spawn rates, upkeep, fee tolerance, prestige and weather
## weights follow calendar seasons per theme (SeasonSystem). When disabled,
## every seasonal modifier stays neutral and the course plays as a single
## year-round season. Includes the SeasonalEvents calendar.

var api: ModAPI = null
var mod_manifest: ModManifest = null

func _mod_on_load() -> bool:
	print("[Seasons Mod] Loaded v%s" % (mod_manifest.version if mod_manifest else "1.0.0"))
	return true

func _mod_on_enable() -> bool:
	if api == null:
		return false
	api.register_feature("seasons", "Seasons", "Demand and upkeep shift with the calendar")
	if GameManager:
		GameManager.seasons_enabled = true
		SeasonSystem.disabled = false
	print("[Seasons Mod] Enabled — calendar seasons are active")
	return true

func _mod_on_disable() -> bool:
	if GameManager:
		GameManager.seasons_enabled = false
		SeasonSystem.disabled = true
	print("[Seasons Mod] Disabled — year-round season")
	return true

func _mod_on_unload() -> bool:
	_mod_on_disable()
	return true
