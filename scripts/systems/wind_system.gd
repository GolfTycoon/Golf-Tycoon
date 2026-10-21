extends Node
class_name WindSystem
## WindSystem - The game's stable wind interface, and its neutral base.
##
## Shots, the aim guide, flags and the HUD all read the wind through this
## class. Whether the air ever moves is up to the loaded mods: a mod
## registers a wind factory whose WindSystem subclass generates and drifts
## a real breeze (the bundled Wind mod in res://mods/golf_tycoon.wind/ is
## the shipped one). Without one, ModManager hands the game this base
## class - a permanent dead calm that pushes no shot anywhere - so no
## caller ever has to check whether "the wind" exists.
##
## A subclass overrides generate_daily_wind(), update_wind_daily(),
## get_wind_displacement() and get_distance_modifier(); the compass and
## strength read-outs are shared vocabulary and live here.

## Wind state
var wind_direction: float = 0.0  # Radians (0 = North/up, PI/2 = East)
var wind_speed: float = 5.0      # MPH (0-30)
## Kept in step with wind_direction by the weather debug panel, which
## writes it directly; implementations may read it as the day's base
## direction. (It was written-but-never-declared before the mod split.)
@warning_ignore("unused_private_class_variable")  # Set externally by the weather debug panel.
var _base_direction: float = 0.0

func _ready() -> void:
	generate_daily_wind()
	EventBus.day_changed.connect(_on_day_changed)

func _exit_tree() -> void:
	if EventBus.day_changed.is_connected(_on_day_changed):
		EventBus.day_changed.disconnect(_on_day_changed)

## Generate fresh wind conditions. The neutral base stays calm.
func generate_daily_wind() -> void:
	force_calm()

## Advance the wind by one game day. The neutral base stays calm:
## no wind mod, no wind.
func update_wind_daily() -> void:
	force_calm()

## Pin the wind to a dead calm (the Wind feature is off, or no provider).
func force_calm() -> void:
	var changed := wind_speed != 0.0
	wind_speed = 0.0
	if changed:
		_emit_wind_changed()

## Get wind displacement for a shot (in tiles): how far the wind pushes it.
func get_wind_displacement(_shot_direction: Vector2, _distance_tiles: float, _club: int) -> Vector2:
	return Vector2.ZERO

## Get distance modifier from headwind/tailwind (1.0 = unaffected).
func get_distance_modifier(_shot_direction: Vector2, _club: int) -> float:
	return 1.0

## Get wind direction as compass text
func get_direction_text() -> String:
	# Convert radians to 8-point compass
	var degrees = fmod(rad_to_deg(wind_direction) + 360.0, 360.0)
	var directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var index = int(round(degrees / 45.0)) % 8
	return directions[index]

## Get wind strength description
func get_strength_text() -> String:
	if wind_speed < 5.0:
		return "Calm"
	elif wind_speed < 10.0:
		return "Light"
	elif wind_speed < 15.0:
		return "Moderate"
	elif wind_speed < 20.0:
		return "Strong"
	else:
		return "Very Strong"

func _on_day_changed(_new_day: int) -> void:
	update_wind_daily()

func _emit_wind_changed() -> void:
	EventBus.wind_changed.emit(wind_direction, wind_speed)
