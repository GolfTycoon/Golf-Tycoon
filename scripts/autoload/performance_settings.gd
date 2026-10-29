extends Node
## Device-aware graphics presets expanded into independent quality controls.
## Presets write every component setting; players can then tune any component
## without changing the others, which turns the preset label into Custom.

# Keep the original preset ids stable: they are persisted in settings.cfg.
enum GraphicsPreset { AUTO, PERFORMANCE, BALANCED, HIGH, CUSTOM }
enum TerrainQuality { FAST, FULL }
enum GrassQuality { OFF, FULL }
enum WaterQuality { REDUCED, FULL }
enum WindFlagQuality { REDUCED, FULL }
enum UpdateRate { LOW, STANDARD, HIGH }
enum GraphicsSetting {
	TERRAIN_QUALITY,
	GRASS_QUALITY,
	TREE_OCCLUSION,
	WATER_QUALITY,
	WIND_FLAG_QUALITY,
	ANIMATION_RATE,
	CAMERA_UPDATE_RATE,
	GOLFER_UPDATE_RATE,
}

const SETTINGS_PATH := "user://settings.cfg"
const PRESET_LABELS: Array[String] = [
	"Auto (recommended)", "Performance", "Balanced", "High quality",
	"Custom (individual settings)",
]
const GRAPHICS_SETTINGS: Array[int] = [
	GraphicsSetting.TERRAIN_QUALITY,
	GraphicsSetting.GRASS_QUALITY,
	GraphicsSetting.TREE_OCCLUSION,
	GraphicsSetting.WATER_QUALITY,
	GraphicsSetting.WIND_FLAG_QUALITY,
	GraphicsSetting.ANIMATION_RATE,
	GraphicsSetting.CAMERA_UPDATE_RATE,
	GraphicsSetting.GOLFER_UPDATE_RATE,
]
const GRAPHICS_SETTING_KEYS: Dictionary = {
	GraphicsSetting.TERRAIN_QUALITY: "terrain_quality",
	GraphicsSetting.GRASS_QUALITY: "grass_quality",
	GraphicsSetting.TREE_OCCLUSION: "tree_occlusion",
	GraphicsSetting.WATER_QUALITY: "water_quality",
	GraphicsSetting.WIND_FLAG_QUALITY: "wind_flag_quality",
	GraphicsSetting.ANIMATION_RATE: "animation_rate",
	GraphicsSetting.CAMERA_UPDATE_RATE: "camera_update_rate",
	GraphicsSetting.GOLFER_UPDATE_RATE: "golfer_update_rate",
}
const ANIMATION_INTERVALS: Array[float] = [0.25, 1.0 / 15.0, 1.0 / 30.0]
const UPDATE_INTERVALS: Array[float] = [1.0 / 15.0, 1.0 / 30.0, 1.0 / 60.0]

## Emitted whenever the preset or any component changes. The argument is true
## when the terrain shader is using its fast, low-detail path.
signal profile_changed(terrain_fast: bool)

var graphics_preset: int = GraphicsPreset.AUTO
var terrain_quality: int = TerrainQuality.FULL
var grass_quality: int = GrassQuality.FULL
var tree_occlusion_enabled: bool = true
var water_quality: int = WaterQuality.FULL
var wind_flag_quality: int = WindFlagQuality.FULL
var animation_rate: int = UpdateRate.STANDARD
var camera_update_rate: int = UpdateRate.STANDARD
var golfer_update_rate: int = UpdateRate.STANDARD

## Compatibility alias for existing callers/tests: terrain detail is the
## setting historically exposed as `low_detail_mode`.
var low_detail_mode: bool:
	get:
		return terrain_quality == TerrainQuality.FAST

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		load_from_config(config)
	else:
		_apply_preset_values(graphics_preset)

func load_from_config(config: ConfigFile) -> void:
	graphics_preset = clampi(
		int(config.get_value("display", "graphics_preset", GraphicsPreset.AUTO)),
		GraphicsPreset.AUTO, GraphicsPreset.CUSTOM)
	if graphics_preset == GraphicsPreset.CUSTOM:
		_load_custom_settings(config)
	else:
		_apply_preset_values(graphics_preset)

## Apply a named preset. Auto maps to Performance on mobile, Web and
## four-core-or-smaller devices, and Balanced on other desktop-class devices.
func set_graphics_preset(preset: int) -> void:
	var next_preset := clampi(preset, GraphicsPreset.AUTO, GraphicsPreset.CUSTOM)
	if graphics_preset == next_preset:
		return
	graphics_preset = next_preset
	if next_preset != GraphicsPreset.CUSTOM:
		_apply_preset_values(next_preset)
	profile_changed.emit(low_detail_mode)

## Change one component without disturbing the others. A real component change
## labels the resulting combination Custom; choosing a preset applies a fresh
## complete set of component values.
func set_graphics_setting(setting: int, value: int) -> void:
	if setting not in GRAPHICS_SETTINGS:
		return
	var normalized := _normalize_setting_value(setting, value)
	if get_graphics_setting(setting) == normalized:
		return
	_set_graphics_setting_value(setting, normalized)
	graphics_preset = GraphicsPreset.CUSTOM
	profile_changed.emit(low_detail_mode)

func get_graphics_setting(setting: int) -> int:
	match setting:
		GraphicsSetting.TERRAIN_QUALITY:
			return terrain_quality
		GraphicsSetting.GRASS_QUALITY:
			return grass_quality
		GraphicsSetting.TREE_OCCLUSION:
			return int(tree_occlusion_enabled)
		GraphicsSetting.WATER_QUALITY:
			return water_quality
		GraphicsSetting.WIND_FLAG_QUALITY:
			return wind_flag_quality
		GraphicsSetting.ANIMATION_RATE:
			return animation_rate
		GraphicsSetting.CAMERA_UPDATE_RATE:
			return camera_update_rate
		GraphicsSetting.GOLFER_UPDATE_RATE:
			return golfer_update_rate
	return 0

func save_to_config(config: ConfigFile) -> void:
	config.set_value("display", "graphics_preset", graphics_preset)
	for setting in GRAPHICS_SETTINGS:
		config.set_value("graphics", GRAPHICS_SETTING_KEYS[setting], get_graphics_setting(setting))

func animation_redraw_interval() -> float:
	return ANIMATION_INTERVALS[clampi(animation_rate, UpdateRate.LOW, UpdateRate.HIGH)]

func camera_redraw_interval() -> float:
	return UPDATE_INTERVALS[clampi(camera_update_rate, UpdateRate.LOW, UpdateRate.HIGH)]

## Cadence for course-wide golfer coordination. Individual golfers still run
## their movement and shot animations every frame; only group scheduling slows.
func simulation_update_interval() -> float:
	return UPDATE_INTERVALS[clampi(golfer_update_rate, UpdateRate.LOW, UpdateRate.HIGH)]

func preset_label(preset: int) -> String:
	return PRESET_LABELS[clampi(preset, GraphicsPreset.AUTO, GraphicsPreset.CUSTOM)]

func _load_custom_settings(config: ConfigFile) -> void:
	var defaults := _preset_values(GraphicsPreset.BALANCED)
	for setting in GRAPHICS_SETTINGS:
		var key: String = GRAPHICS_SETTING_KEYS[setting]
		var value := int(config.get_value("graphics", key, defaults[setting]))
		_set_graphics_setting_value(setting, _normalize_setting_value(setting, value))

func _apply_preset_values(preset: int) -> void:
	var effective_preset := preset
	if preset == GraphicsPreset.AUTO:
		effective_preset = GraphicsPreset.PERFORMANCE if should_use_low_detail(
			GraphicsPreset.AUTO, OS.get_name(), OS.get_processor_count()) else GraphicsPreset.BALANCED
	var values := _preset_values(effective_preset)
	for setting in GRAPHICS_SETTINGS:
		_set_graphics_setting_value(setting, values[setting])

func _preset_values(preset: int) -> Dictionary:
	match preset:
		GraphicsPreset.PERFORMANCE:
			return {
				GraphicsSetting.TERRAIN_QUALITY: TerrainQuality.FAST,
				GraphicsSetting.GRASS_QUALITY: GrassQuality.OFF,
				GraphicsSetting.TREE_OCCLUSION: 0,
				GraphicsSetting.WATER_QUALITY: WaterQuality.REDUCED,
				GraphicsSetting.WIND_FLAG_QUALITY: WindFlagQuality.REDUCED,
				GraphicsSetting.ANIMATION_RATE: UpdateRate.LOW,
				GraphicsSetting.CAMERA_UPDATE_RATE: UpdateRate.LOW,
				GraphicsSetting.GOLFER_UPDATE_RATE: UpdateRate.LOW,
			}
		GraphicsPreset.HIGH:
			return {
				GraphicsSetting.TERRAIN_QUALITY: TerrainQuality.FULL,
				GraphicsSetting.GRASS_QUALITY: GrassQuality.FULL,
				GraphicsSetting.TREE_OCCLUSION: 1,
				GraphicsSetting.WATER_QUALITY: WaterQuality.FULL,
				GraphicsSetting.WIND_FLAG_QUALITY: WindFlagQuality.FULL,
				GraphicsSetting.ANIMATION_RATE: UpdateRate.HIGH,
				GraphicsSetting.CAMERA_UPDATE_RATE: UpdateRate.HIGH,
				GraphicsSetting.GOLFER_UPDATE_RATE: UpdateRate.HIGH,
			}
		_:
			return {
				GraphicsSetting.TERRAIN_QUALITY: TerrainQuality.FULL,
				GraphicsSetting.GRASS_QUALITY: GrassQuality.FULL,
				GraphicsSetting.TREE_OCCLUSION: 1,
				GraphicsSetting.WATER_QUALITY: WaterQuality.FULL,
				GraphicsSetting.WIND_FLAG_QUALITY: WindFlagQuality.FULL,
				GraphicsSetting.ANIMATION_RATE: UpdateRate.STANDARD,
				GraphicsSetting.CAMERA_UPDATE_RATE: UpdateRate.STANDARD,
				GraphicsSetting.GOLFER_UPDATE_RATE: UpdateRate.STANDARD,
			}

func _normalize_setting_value(setting: int, value: int) -> int:
	match setting:
		GraphicsSetting.TERRAIN_QUALITY:
			return clampi(value, TerrainQuality.FAST, TerrainQuality.FULL)
		GraphicsSetting.GRASS_QUALITY:
			return clampi(value, GrassQuality.OFF, GrassQuality.FULL)
		GraphicsSetting.TREE_OCCLUSION:
			return clampi(value, 0, 1)
		GraphicsSetting.WATER_QUALITY:
			return clampi(value, WaterQuality.REDUCED, WaterQuality.FULL)
		GraphicsSetting.WIND_FLAG_QUALITY:
			return clampi(value, WindFlagQuality.REDUCED, WindFlagQuality.FULL)
		GraphicsSetting.ANIMATION_RATE, GraphicsSetting.CAMERA_UPDATE_RATE, GraphicsSetting.GOLFER_UPDATE_RATE:
			return clampi(value, UpdateRate.LOW, UpdateRate.HIGH)
	return 0

func _set_graphics_setting_value(setting: int, value: int) -> void:
	match setting:
		GraphicsSetting.TERRAIN_QUALITY:
			terrain_quality = value
		GraphicsSetting.GRASS_QUALITY:
			grass_quality = value
		GraphicsSetting.TREE_OCCLUSION:
			tree_occlusion_enabled = value != 0
		GraphicsSetting.WATER_QUALITY:
			water_quality = value
		GraphicsSetting.WIND_FLAG_QUALITY:
			wind_flag_quality = value
		GraphicsSetting.ANIMATION_RATE:
			animation_rate = value
		GraphicsSetting.CAMERA_UPDATE_RATE:
			camera_update_rate = value
		GraphicsSetting.GOLFER_UPDATE_RATE:
			golfer_update_rate = value

## Kept pure so Auto's device policy can be covered without changing the
## machine running the tests.
static func should_use_low_detail(preset: int, platform: String, processor_count: int) -> bool:
	match preset:
		GraphicsPreset.PERFORMANCE:
			return true
		GraphicsPreset.BALANCED, GraphicsPreset.HIGH, GraphicsPreset.CUSTOM:
			return false
		_:
			return platform in ["Android", "iOS", "Web"] or processor_count <= 4
