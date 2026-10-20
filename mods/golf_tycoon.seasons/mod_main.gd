extends GolfTycoonMod
## Seasons (official mod) - entry point.
##
## Registers this mod's SeasonProvider as the game's seasons. The provider
## is the whole simulation - the theme-aware tables in season_provider.gd -
## while SeasonSystem (core) stays the neutral window every system reads
## it through, so the game runs the same code whether or not this mod is
## loaded. The eight seasonal events are plain data, declared under
## "seasonal_events" in mod.json and applied by the loader before this
## script even runs.

const Provider := preload("season_provider.gd")


func _mod_load(mod_api: ModAPI) -> void:
	mod_api.register_season_provider(Provider.new())
