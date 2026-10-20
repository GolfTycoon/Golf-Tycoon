extends Node
class_name WeatherSystem
## WeatherSystem - The game's stable weather interface, and its neutral base.
##
## Everything that reads the weather - golfer spawning, shot accuracy, the
## ambience lighting, the HUD, saves - talks to this class. Whether any
## weather actually *happens* is up to the mods that are loaded: a mod
## registers a weather factory whose WeatherSystem subclass produces real
## weather (the bundled Weather mod in res://mods/golf_tycoon.weather/ is
## the shipped one, with spells, fronts and theme-aware rolls). Without
## one, ModManager hands the game this base class, which is permanently,
## changelessly sunny and affects nothing - the same contract the game
## gives wind and seasons, so no caller ever has to wonder whether
## "the weather" exists.
##
## A subclass overrides generate_daily_weather(), update_weather_daily(),
## get_spawn_rate_modifier() and get_accuracy_modifier(); the shared
## vocabulary (the WeatherType enum, the read-outs, the sky and light each
## kind of weather brings) lives here so every implementation agrees on
## what "Rain" means.

## Weather types
enum WeatherType {
	SUNNY,
	PARTLY_CLOUDY,
	CLOUDY,
	LIGHT_RAIN,
	RAIN,
	HEAVY_RAIN
}

## Current weather state
var weather_type: WeatherType = WeatherType.SUNNY
var intensity: float = 0.0  # 0.0 = clear, 1.0 = severe

func _ready() -> void:
	generate_daily_weather()
	EventBus.day_changed.connect(_on_day_changed)

func _exit_tree() -> void:
	if EventBus.day_changed.is_connected(_on_day_changed):
		EventBus.day_changed.disconnect(_on_day_changed)

## Generate weather for a new day. The neutral base stays clear.
func generate_daily_weather() -> void:
	force_clear_weather()

## Advance the weather by one game day. The neutral base stays clear:
## no weather mod, no weather.
func update_weather_daily() -> void:
	force_clear_weather()

## Pin the course to clear, neutral weather (feature off, or no provider).
func force_clear_weather() -> void:
	var changed := weather_type != WeatherType.SUNNY or intensity != 0.0
	weather_type = WeatherType.SUNNY
	intensity = 0.0
	if changed:
		_emit_weather_changed()

## Get spawn rate modifier based on weather (bad weather reduces spawning).
func get_spawn_rate_modifier() -> float:
	return 1.0

## Get accuracy modifier for shots (rain makes aiming harder).
func get_accuracy_modifier() -> float:
	return 1.0

## Get sky tint color for the weather ambience.
func get_sky_tint() -> Color:
	match weather_type:
		WeatherType.SUNNY:
			return Color(1.0, 1.0, 1.0, 0.0)  # No tint
		WeatherType.PARTLY_CLOUDY:
			return Color(0.95, 0.95, 0.95, 0.1)
		WeatherType.CLOUDY:
			return Color(0.85, 0.85, 0.9, 0.2)
		WeatherType.LIGHT_RAIN:
			return Color(0.75, 0.78, 0.85, 0.3)
		WeatherType.RAIN:
			return Color(0.65, 0.68, 0.75, 0.35)
		WeatherType.HEAVY_RAIN:
			return Color(0.55, 0.58, 0.65, 0.4)
	return Color(1.0, 1.0, 1.0, 0.0)

## Get light intensity modifier for elevation shader (1.0 = full sun, lower = dimmer)
func get_light_modifier() -> float:
	match weather_type:
		WeatherType.SUNNY:
			return 1.0
		WeatherType.PARTLY_CLOUDY:
			return 0.85
		WeatherType.CLOUDY:
			return 0.65
		WeatherType.LIGHT_RAIN:
			return 0.55
		WeatherType.RAIN:
			return 0.45
		WeatherType.HEAVY_RAIN:
			return 0.35
	return 1.0

## Check if it's currently raining
func is_raining() -> bool:
	return weather_type >= WeatherType.LIGHT_RAIN

## Get weather description text
func get_weather_text() -> String:
	match weather_type:
		WeatherType.SUNNY:
			return "Sunny"
		WeatherType.PARTLY_CLOUDY:
			return "Partly Cloudy"
		WeatherType.CLOUDY:
			return "Cloudy"
		WeatherType.LIGHT_RAIN:
			return "Light Rain"
		WeatherType.RAIN:
			return "Rain"
		WeatherType.HEAVY_RAIN:
			return "Heavy Rain"
	return "Unknown"

## Get weather icon character
func get_weather_icon() -> String:
	match weather_type:
		WeatherType.SUNNY:
			return "O"  # Sun
		WeatherType.PARTLY_CLOUDY:
			return "o~"  # Partial cloud
		WeatherType.CLOUDY:
			return "~~"  # Cloud
		WeatherType.LIGHT_RAIN:
			return "~."  # Light rain
		WeatherType.RAIN:
			return "~:"  # Rain
		WeatherType.HEAVY_RAIN:
			return "~|"  # Heavy rain
	return "?"

func _on_day_changed(_new_day: int) -> void:
	update_weather_daily()

func _emit_weather_changed() -> void:
	EventBus.weather_changed.emit(weather_type, intensity)
