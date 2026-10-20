extends SeasonProvider
## The Seasons mod's SeasonProvider: the four temperate, theme-aware seasons
## Golf Tycoon ships with. Every table varies by CourseTheme.Type, so Desert
## courses peak in winter while Mountain courses peak in summer.
##
## This file has no class_name on purpose (see GolfTycoonMod): the mod's
## entry point preloads it by relative path, which is what lets this exact
## code run from a zip or a Workshop item.

# Theme enum aliases for readable dictionary keys
const _PARKLAND  = CourseTheme.Type.PARKLAND
const _DESERT    = CourseTheme.Type.DESERT
const _LINKS     = CourseTheme.Type.LINKS
const _MOUNTAIN  = CourseTheme.Type.MOUNTAIN
const _CITY      = CourseTheme.Type.CITY
const _RESORT    = CourseTheme.Type.RESORT
const _HEATHLAND = CourseTheme.Type.HEATHLAND
const _WOODLAND  = CourseTheme.Type.WOODLAND
const _TROPICAL  = CourseTheme.Type.TROPICAL
const _MARSHLAND = CourseTheme.Type.MARSHLAND

## Theme-aware spawn rate modifier tables (theme -> {season -> modifier}).
## Fallback row (PARKLAND) matches the original global values.
const THEME_SPAWN_MODIFIERS: Dictionary = {
	_PARKLAND:  {0: 0.9, 1: 1.4, 2: 0.8, 3: 0.3},
	_DESERT:    {0: 0.6, 1: 0.3, 2: 0.9, 3: 1.4},  # Inverted peak
	_LINKS:     {0: 0.8, 1: 1.3, 2: 0.9, 3: 0.4},
	_MOUNTAIN:  {0: 1.0, 1: 1.5, 2: 0.7, 3: 0.1},
	_CITY:      {0: 0.9, 1: 1.2, 2: 1.0, 3: 0.6},  # Stable year-round
	_RESORT:    {0: 1.0, 1: 1.3, 2: 0.8, 3: 1.2},  # Dual peak
	_HEATHLAND: {0: 0.8, 1: 1.3, 2: 0.9, 3: 0.3},
	_WOODLAND:  {0: 1.0, 1: 1.4, 2: 1.1, 3: 0.2},  # Fall foliage boost
	_TROPICAL:  {0: 1.1, 1: 0.8, 2: 1.2, 3: 1.3},  # Inverted peak
	_MARSHLAND: {0: 0.7, 1: 0.9, 2: 0.8, 3: 0.4},
}

## Theme-aware maintenance cost modifier tables.
const THEME_MAINTENANCE_MODIFIERS: Dictionary = {
	_PARKLAND:  {0: 1.1, 1: 1.4, 2: 0.7, 3: 1.1},
	_DESERT:    {0: 0.8, 1: 0.6, 2: 0.8, 3: 1.0},  # Low year-round
	_LINKS:     {0: 1.0, 1: 1.1, 2: 0.8, 3: 1.3},  # Winter wind damage
	_MOUNTAIN:  {0: 1.2, 1: 1.3, 2: 0.8, 3: 1.5},  # Costly winters
	_CITY:      {0: 1.0, 1: 1.2, 2: 0.9, 3: 1.0},
	_RESORT:    {0: 1.1, 1: 1.3, 2: 0.9, 3: 1.2},
	_HEATHLAND: {0: 0.9, 1: 1.1, 2: 0.8, 3: 1.0},
	_WOODLAND:  {0: 1.0, 1: 1.2, 2: 1.0, 3: 0.9},
	_TROPICAL:  {0: 1.3, 1: 1.5, 2: 1.1, 3: 0.9},  # Summer growth
	_MARSHLAND: {0: 1.2, 1: 1.4, 2: 0.9, 3: 1.0},
}

## Tournament prestige multipliers per theme x season.
## Higher prestige seasons reward more reputation for hosting tournaments.
const THEME_TOURNAMENT_PRESTIGE: Dictionary = {
	_PARKLAND:  {0: 1.0, 1: 1.0, 2: 1.2, 3: 0.5},  # Fall classic
	_DESERT:    {0: 0.8, 1: 0.5, 2: 1.2, 3: 1.0},  # Fall/winter
	_LINKS:     {0: 0.8, 1: 1.2, 2: 1.0, 3: 0.5},  # Summer Open
	_MOUNTAIN:  {0: 1.0, 1: 1.2, 2: 0.8, 3: 0.5},
	_CITY:      {0: 1.0, 1: 1.0, 2: 1.2, 3: 0.8},  # No deep off-season
	_RESORT:    {0: 0.8, 1: 1.0, 2: 1.0, 3: 1.2},  # Winter prestige
	_HEATHLAND: {0: 0.8, 1: 1.2, 2: 1.0, 3: 0.5},
	_WOODLAND:  {0: 1.0, 1: 1.0, 2: 1.2, 3: 0.5},  # Fall classic
	_TROPICAL:  {0: 0.8, 1: 0.5, 2: 1.0, 3: 1.2},  # Winter prestige
	_MARSHLAND: {0: 0.8, 1: 0.8, 2: 1.2, 3: 0.5},  # Fall classic
}

## Theme weather modifiers: {theme -> {wind_modifier, rain_modifier}}
## Applied on top of base seasonal weather tables.
const THEME_WEATHER_MODIFIERS: Dictionary = {
	_PARKLAND:  {"wind": 1.0, "rain": 1.0},
	_DESERT:    {"wind": 0.8, "rain": 0.3},  # Dry, moderate wind
	_LINKS:     {"wind": 1.5, "rain": 1.2},  # Windy, frequent rain
	_MOUNTAIN:  {"wind": 1.2, "rain": 1.3},  # Variable, more precip
	_CITY:      {"wind": 1.0, "rain": 1.0},
	_RESORT:    {"wind": 1.0, "rain": 1.0},
	_HEATHLAND: {"wind": 1.0, "rain": 1.0},
	_WOODLAND:  {"wind": 1.0, "rain": 1.0},
	_TROPICAL:  {"wind": 0.7, "rain": 1.8},  # Calm but very rainy
	_MARSHLAND: {"wind": 0.9, "rain": 1.4},  # Damp, frequent rain
}


## Golfer demand multiplier by season, theme-aware. Theme -1 (or unknown)
## falls back to PARKLAND, the original global values.
func spawn_modifier(season: int, theme: int) -> float:
	var t = theme if theme >= 0 else 0
	if THEME_SPAWN_MODIFIERS.has(t):
		return THEME_SPAWN_MODIFIERS[t].get(season, 1.0)
	return THEME_SPAWN_MODIFIERS[0].get(season, 1.0)


## Maintenance cost multiplier by season, theme-aware.
func maintenance_modifier(season: int, theme: int) -> float:
	var t = theme if theme >= 0 else 0
	if THEME_MAINTENANCE_MODIFIERS.has(t):
		return THEME_MAINTENANCE_MODIFIERS[t].get(season, 1.0)
	return THEME_MAINTENANCE_MODIFIERS[0].get(season, 1.0)


## Tournament prestige multiplier for the season and theme.
func tournament_prestige(season: int, theme: int) -> float:
	var t = theme if theme >= 0 else 0
	if THEME_TOURNAMENT_PRESTIGE.has(t):
		return THEME_TOURNAMENT_PRESTIGE[t].get(season, 1.0)
	return 1.0


## Theme weather modifiers for wind and rain probability adjustments.
func theme_weather_modifiers(theme: int) -> Dictionary:
	var t = theme if theme >= 0 else 0
	if THEME_WEATHER_MODIFIERS.has(t):
		return THEME_WEATHER_MODIFIERS[t]
	return {"wind": 1.0, "rain": 1.0}


## Cumulative weather probability thresholds per season.
## Order: [SUNNY, PARTLY_CLOUDY, CLOUDY, LIGHT_RAIN, RAIN, HEAVY_RAIN]
func weather_weights(season: int) -> Array:
	match season:
		0:  # Spring
			return [0.25, 0.50, 0.65, 0.80, 0.93, 1.0]
		1:  # Summer
			return [0.55, 0.80, 0.90, 0.95, 0.98, 1.0]
		2:  # Fall
			return [0.30, 0.55, 0.75, 0.88, 0.96, 1.0]
		3:  # Winter
			return [0.15, 0.35, 0.60, 0.78, 0.92, 1.0]
	return [0.40, 0.70, 0.85, 0.93, 0.98, 1.0]
