extends GolfTycoonMod
## Weather (official mod) - entry point.
##
## Two jobs: hand the game this mod's weather simulation (a factory the
## main scene calls when it builds its systems), and put the weather's
## visuals - the rain and the ambient tint - into the main scene. The
## visuals are per-scene nodes, so the mod listens for
## EventBus.main_scene_ready as well as using api.on_main_scene_ready, and
## checks before adding so a reloaded scene never gets two of anything.

const WeatherImpl := preload("weather_system.gd")
const WeatherTint := preload("weather_tint_system.gd")
const Rain := preload("rain_overlay.gd")

var _rain_canvas: CanvasLayer = null
var _tint: Node = null


func _mod_load(mod_api: ModAPI) -> void:
	# This mod's switch under Game features on Start New Game (that section is
	# hidden while no mod adds an option to it).
	mod_api.register_feature("weather")
	mod_api.register_weather_factory(func() -> WeatherSystem: return WeatherImpl.new())
	mod_api.on_main_scene_ready(_setup_in_main_scene)
	EventBus.main_scene_ready.connect(_setup_in_main_scene)


func _mod_unload() -> void:
	if EventBus.main_scene_ready.is_connected(_setup_in_main_scene):
		EventBus.main_scene_ready.disconnect(_setup_in_main_scene)
	if is_instance_valid(_rain_canvas):
		_rain_canvas.queue_free()
	if is_instance_valid(_tint):
		_tint.queue_free()
	_rain_canvas = null
	_tint = null


func _setup_in_main_scene(main_scene: Node) -> void:
	if main_scene.get_node_or_null("RainCanvas") == null:
		# A CanvasLayer at layer 0 keeps the rain in screen space, above the
		# world and below the HUD, exactly where the core game kept it.
		_rain_canvas = CanvasLayer.new()
		_rain_canvas.name = "RainCanvas"
		_rain_canvas.layer = 0
		main_scene.add_child(_rain_canvas)
		var rain: Node2D = Rain.new()
		rain.name = "RainOverlay"
		_rain_canvas.add_child(rain)
		if GameManager.weather_system != null:
			rain.call("setup", GameManager.weather_system)
	if main_scene.get_node_or_null("WeatherTintSystem") == null:
		_tint = WeatherTint.new()
		_tint.name = "WeatherTintSystem"
		main_scene.add_child(_tint)
