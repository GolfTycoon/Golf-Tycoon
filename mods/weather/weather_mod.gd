extends RefCounted
## Weather Mod - Builtin mod that provides the WeatherSystem feature.
##
## When enabled, daily weather is rolled and affects golfer spawning and
## shot accuracy. When disabled, the course stays clear (SUNNY, no effects).
##
## The actual WeatherSystem node still exists for API compatibility, but this
## mod owns the "weather" feature flag and gates the system via ModManager.
## This makes it easy for other mods to depend on or replace weather logic.

var api: ModAPI = null
var mod_manifest: ModManifest = null


func _mod_on_load() -> bool:
	print("[Weather Mod] Loaded v%s" % (mod_manifest.version if mod_manifest else "1.0.0"))
	return true

func _mod_on_enable() -> bool:
	if api == null:
		return false
	# Register the "weather" feature so is_feature_enabled("weather") is true
	api.register_feature("weather", "Weather", "Storms change turnout and sky tint")
	# Hook into daily day_changed to drive weather evolution (system already does this;
	# mod ensures it only runs when enabled by toggling GameManager flag in sync).
	# We sync GameManager for backward-compat callers that still check weather_enabled directly.
	if GameManager:
		GameManager.weather_enabled = true
	print("[Weather Mod] Enabled — weather will roll daily")
	return true

func _mod_on_disable() -> bool:
	if GameManager:
		GameManager.weather_enabled = false
		if GameManager.weather_system:
			GameManager.weather_system.force_clear_weather()
	print("[Weather Mod] Disabled — sky cleared")
	return true

func _mod_on_unload() -> bool:
	_mod_on_disable()
	return true
