extends WindSystem
## The Wind mod's wind: a breeze that drifts a little from day to day, with
## a rare full reshuffle when a front passes, pushing shots downwind and
## stretching or shortening them into the breeze.
##
## This overrides the neutral WindSystem base behind the same interface
## (see GolfTycoonMod); with the mod off, the game simply runs the base's
## permanent calm. No class_name here on purpose - the mod entry point
## preloads this file by relative path.

## Chance that a day brings a full wind reshuffle (weather front passing)
const DAILY_RESHUFFLE_CHANCE: float = 0.08

## Club sensitivity to wind — delegated to GolfRules for single source of truth

## Public method to generate fresh wind conditions (used by debug tools)
func generate_daily_wind() -> void:
	_generate_new_wind()

## Generate new wind conditions (full reshuffle, e.g. a weather front passing)
func _generate_new_wind() -> void:
	# Wind can be turned off as a game feature: the air is then dead calm and
	# shots fly unaffected.
	if not GameManager.wind_enabled:
		force_calm()
		return
	wind_direction = randf() * TAU
	_base_direction = wind_direction
	wind_speed = randf_range(2.0, 20.0)
	_emit_wind_changed()

## Advance the wind by one game day: mostly a small random walk around the
## current direction, with a rare full reshuffle when conditions change.
func update_wind_daily() -> void:
	if not GameManager.wind_enabled:
		force_calm()
		return
	if randf() < DAILY_RESHUFFLE_CHANCE:
		_generate_new_wind()
		return
	# Drift the direction slightly day-to-day
	wind_direction = fposmod(wind_direction + randf_range(-0.35, 0.35), TAU)
	_base_direction = wind_direction
	# Slight speed variation
	wind_speed = clampf(wind_speed + randf_range(-1.5, 1.5), 0.0, 30.0)
	_emit_wind_changed()

## Get wind displacement for a shot (in tiles)
## Returns how far the ball will be pushed by wind
func get_wind_displacement(shot_direction: Vector2, distance_tiles: float, club: int) -> Vector2:
	if not GameManager.wind_enabled:
		return Vector2.ZERO
	var sensitivity = GolfRules.get_club_wind_sensitivity(club)
	if sensitivity == 0.0:
		return Vector2.ZERO

	var wind_vector = Vector2(-sin(wind_direction), cos(wind_direction)) * wind_speed

	# Decompose wind into headwind/tailwind and crosswind components
	var shot_dir_normalized = shot_direction.normalized()
	var headwind = wind_vector.dot(shot_dir_normalized)  # Positive = tailwind
	var crosswind_vec = wind_vector - shot_dir_normalized * headwind

	# Scale effect by distance and sensitivity
	# Longer shots are more affected by wind
	var distance_factor = distance_tiles / 20.0  # Normalize to ~driver distance
	var wind_factor = sensitivity * distance_factor

	# Crosswind pushes ball laterally (main visible effect)
	var displacement = crosswind_vec * wind_factor * 0.15

	# Headwind/tailwind handled separately in get_distance_modifier
	return displacement

## Get distance modifier from headwind/tailwind
## Returns multiplier: <1.0 for headwind, >1.0 for tailwind
func get_distance_modifier(shot_direction: Vector2, club: int) -> float:
	if not GameManager.wind_enabled:
		return 1.0
	var sensitivity = GolfRules.get_club_wind_sensitivity(club)
	if sensitivity == 0.0:
		return 1.0

	var wind_vector = Vector2(-sin(wind_direction), cos(wind_direction)) * wind_speed
	var shot_dir_normalized = shot_direction.normalized()

	# Dot product: positive = tailwind (wind going same direction as shot)
	var headwind_component = wind_vector.dot(shot_dir_normalized)

	# Normalize to a reasonable modifier range
	# At 30mph headwind, up to 15% distance reduction
	# At 30mph tailwind, up to 10% distance increase
	var modifier = 1.0
	if headwind_component < 0:
		# Headwind - reduces distance
		modifier -= abs(headwind_component) / 30.0 * 0.15 * sensitivity
	else:
		# Tailwind - increases distance
		modifier += headwind_component / 30.0 * 0.10 * sensitivity

	return clampf(modifier, 0.75, 1.15)

