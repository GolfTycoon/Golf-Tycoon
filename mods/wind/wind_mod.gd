extends RefCounted
## Wind Mod - Builtin mod that provides the WindSystem feature.
##
## When enabled, wind drifts daily and affects shots. When disabled, air is
## dead calm and shots ignore wind. Like Weather, the WindSystem node remains
## but this mod owns the feature flag and gates it.

var api: ModAPI = null
var mod_manifest: ModManifest = null

func _mod_on_load() -> bool:
	print("[Wind Mod] Loaded v%s" % (mod_manifest.version if mod_manifest else "1.0.0"))
	return true

func _mod_on_enable() -> bool:
	if api == null:
		return false
	api.register_feature("wind", "Wind", "Shots drift and carry changes with wind")
	if GameManager:
		GameManager.wind_enabled = true
		# Regenerate wind now that it's on
		if GameManager.wind_system:
			GameManager.wind_system.generate_daily_wind()
	print("[Wind Mod] Enabled — wind will drift daily")
	return true

func _mod_on_disable() -> bool:
	if GameManager:
		GameManager.wind_enabled = false
		if GameManager.wind_system:
			GameManager.wind_system.force_calm()
	print("[Wind Mod] Disabled — air is calm")
	return true

func _mod_on_unload() -> bool:
	_mod_on_disable()
	return true
