extends RefCounted
class_name SeasonProvider
## SeasonProvider - The tables and rules behind SeasonSystem, supplied by a mod.
##
## SeasonSystem is the stable facade the whole game reads (which season a day
## falls in, what that does to golfer demand, upkeep, green-fee tolerance,
## tournament prestige and the weather). *Which* seasons those are and what
## they do comes from whichever SeasonProvider the loaded mods registered
## through the Mod API - the bundled Seasons mod ships the four temperate
## seasons this game has always had. With no provider, this base class is
## used as-is: the calendar still turns, but every seasonal effect is
## neutral, which is exactly how the game behaves without the Seasons mod.
##
## Season values are SeasonSystem.Season (0 spring, 1 summer, 2 fall,
## 3 winter); theme values are CourseTheme.Type. They are passed as plain
## ints so a provider never depends on the facade that reads it.

## Which season a calendar month (1-12) falls in.
func season_for_month(month: int) -> int:
	match month:
		3, 4, 5:
			return 0  # Spring
		6, 7, 8:
			return 1  # Summer
		9, 10, 11:
			return 2  # Fall
		_:
			return 3  # Winter


## The month each season starts in, season -> month. SeasonSystem derives
## season lengths and days-in-season from this, so a provider that moves
## the boundaries only has to say so here.
func season_start_months() -> Dictionary:
	return {0: 3, 1: 6, 2: 9, 3: 12}


## Golfer demand multiplier (theme -1 means "no theme given").
func spawn_modifier(_season: int, _theme: int) -> float:
	return 1.0


## Terrain maintenance cost multiplier.
func maintenance_modifier(_season: int, _theme: int) -> float:
	return 1.0


## Tournament reputation reward multiplier.
func tournament_prestige(_season: int, _theme: int) -> float:
	return 1.0


## Per-theme weather character: {"wind": multiplier, "rain": multiplier}.
func theme_weather_modifiers(_theme: int) -> Dictionary:
	return {"wind": 1.0, "rain": 1.0}


## Cumulative weather probability thresholds for one season, in
## WeatherSystem.WeatherType order:
## [SUNNY, PARTLY_CLOUDY, CLOUDY, LIGHT_RAIN, RAIN, HEAVY_RAIN].
func weather_weights(_season: int) -> Array:
	return [0.40, 0.70, 0.85, 0.93, 0.98, 1.0]
