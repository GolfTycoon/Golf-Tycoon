extends GolfTycoonMod
## Wind (official mod) - entry point.
##
## Hands the game this mod's wind simulation, through a factory the main
## scene calls when it builds its systems. The flags on the greens are
## core presentation: they read EventBus.wind_changed, so they stand limp
## under the neutral calm when this mod is off.

const WindImpl := preload("wind_system.gd")


func _mod_load(mod_api: ModAPI) -> void:
	# Wind's switch on the Start New Game screen. The Features section there
	# is hidden until a mod (this one) adds an option.
	mod_api.register_feature("wind")
	mod_api.register_wind_factory(func() -> WindSystem: return WindImpl.new())
