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
## Decorative detail. These three cost draw calls rather than redraw cadence:
## each one paints something the course can do without, so a device that is
## short of fill rate can shed it instead of slowing the whole course down.
enum ShadowDetail { OFF, CONTACT_ONLY, FULL }
enum WildlifeDetail { OFF, REDUCED, FULL }
enum EffectDetail { OFF, REDUCED, FULL }
## These ids are stored in settings.cfg; append new choices rather than
## reordering the existing ones.
enum FpsCounterPosition { TOP_CENTER, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }
enum FpsCounterSize { SMALL, MEDIUM, LARGE }
enum FpsCounterRefresh { FAST, NORMAL, SLOW }
enum GraphicsSetting {
	TERRAIN_QUALITY,
	GRASS_QUALITY,
	TREE_OCCLUSION,
	WATER_QUALITY,
	WIND_FLAG_QUALITY,
	ANIMATION_RATE,
	CAMERA_UPDATE_RATE,
	GOLFER_UPDATE_RATE,
	SHADOW_DETAIL,
	WILDLIFE_DETAIL,
	EFFECT_DETAIL,
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
	GraphicsSetting.SHADOW_DETAIL,
	GraphicsSetting.WILDLIFE_DETAIL,
	GraphicsSetting.EFFECT_DETAIL,
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
	GraphicsSetting.SHADOW_DETAIL: "shadow_detail",
	GraphicsSetting.WILDLIFE_DETAIL: "wildlife_detail",
	GraphicsSetting.EFFECT_DETAIL: "effect_detail",
}
const ANIMATION_INTERVALS: Array[float] = [0.25, 1.0 / 15.0, 1.0 / 30.0]
const UPDATE_INTERVALS: Array[float] = [1.0 / 15.0, 1.0 / 30.0, 1.0 / 60.0]
## Fraction of the wildlife residents a course keeps, and of the particles a
## burst spawns, indexed by the detail choice.
const WILDLIFE_DENSITY: Array[float] = [0.0, 0.5, 1.0]
const EFFECT_PARTICLE_SCALE: Array[float] = [0.0, 0.5, 1.0]
const FPS_POSITION_LABELS: Array[String] = [
	"Top center", "Top left", "Top right", "Bottom left", "Bottom right",
]
const FPS_SIZE_LABELS: Array[String] = ["Small", "Medium", "Large"]
const FPS_FONT_SIZES: Array[int] = [12, 16, 20]
const FPS_REFRESH_LABELS: Array[String] = ["Fast — 0.25 s", "Normal — 0.5 s", "Slow — 1 s"]
const FPS_REFRESH_INTERVALS: Array[float] = [0.25, 0.5, 1.0]

## Emitted whenever the preset or any component changes. The argument is true
## when the terrain shader is using its fast, low-detail path.
signal profile_changed(terrain_fast: bool)
## Separate from graphics presets: these are preferences for the live readout,
## and changing a quality preset must not change or hide the counter.
signal fps_counter_changed

var fps_counter_enabled: bool = false
var fps_counter_position: int = FpsCounterPosition.TOP_CENTER
var fps_counter_size: int = FpsCounterSize.MEDIUM
var fps_counter_refresh: int = FpsCounterRefresh.NORMAL

var graphics_preset: int = GraphicsPreset.AUTO
var terrain_quality: int = TerrainQuality.FULL
var grass_quality: int = GrassQuality.FULL
var tree_occlusion_enabled: bool = true
var water_quality: int = WaterQuality.FULL
var wind_flag_quality: int = WindFlagQuality.FULL
var animation_rate: int = UpdateRate.STANDARD
var camera_update_rate: int = UpdateRate.STANDARD
var golfer_update_rate: int = UpdateRate.STANDARD
var shadow_detail: int = ShadowDetail.FULL
var wildlife_detail: int = WildlifeDetail.FULL
var effect_detail: int = EffectDetail.FULL

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
	_load_fps_counter_settings(config)

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
		GraphicsSetting.SHADOW_DETAIL:
			return shadow_detail
		GraphicsSetting.WILDLIFE_DETAIL:
			return wildlife_detail
		GraphicsSetting.EFFECT_DETAIL:
			return effect_detail
	return 0

func save_to_config(config: ConfigFile) -> void:
	config.set_value("display", "graphics_preset", graphics_preset)
	config.set_value("display", "fps_counter_enabled", fps_counter_enabled)
	config.set_value("display", "fps_counter_position", fps_counter_position)
	config.set_value("display", "fps_counter_size", fps_counter_size)
	config.set_value("display", "fps_counter_refresh", fps_counter_refresh)
	for setting in GRAPHICS_SETTINGS:
		config.set_value("graphics", GRAPHICS_SETTING_KEYS[setting], get_graphics_setting(setting))

func set_fps_counter_enabled(enabled: bool) -> void:
	if fps_counter_enabled == enabled:
		return
	fps_counter_enabled = enabled
	fps_counter_changed.emit()

func set_fps_counter_position(position: int) -> void:
	var choice := clampi(position, FpsCounterPosition.TOP_CENTER, FpsCounterPosition.BOTTOM_RIGHT)
	if fps_counter_position == choice:
		return
	fps_counter_position = choice
	fps_counter_changed.emit()

func set_fps_counter_size(size: int) -> void:
	var choice := clampi(size, FpsCounterSize.SMALL, FpsCounterSize.LARGE)
	if fps_counter_size == choice:
		return
	fps_counter_size = choice
	fps_counter_changed.emit()

func set_fps_counter_refresh(refresh: int) -> void:
	var choice := clampi(refresh, FpsCounterRefresh.FAST, FpsCounterRefresh.SLOW)
	if fps_counter_refresh == choice:
		return
	fps_counter_refresh = choice
	fps_counter_changed.emit()

func fps_counter_font_size() -> int:
	return FPS_FONT_SIZES[fps_counter_size]

func fps_counter_refresh_interval() -> float:
	return FPS_REFRESH_INTERVALS[fps_counter_refresh]

func _load_fps_counter_settings(config: ConfigFile) -> void:
	var enabled: Variant = config.get_value("display", "fps_counter_enabled", false)
	fps_counter_enabled = enabled if typeof(enabled) == TYPE_BOOL else false
	fps_counter_position = _read_fps_option(config, "fps_counter_position",
		FpsCounterPosition.TOP_CENTER, FpsCounterPosition.BOTTOM_RIGHT)
	fps_counter_size = _read_fps_option(config, "fps_counter_size",
		FpsCounterSize.MEDIUM, FpsCounterSize.LARGE)
	fps_counter_refresh = _read_fps_option(config, "fps_counter_refresh",
		FpsCounterRefresh.NORMAL, FpsCounterRefresh.SLOW)
	fps_counter_changed.emit()

## Old settings files have none of these fields; invalid types use the defaults
## and out-of-range ids are kept inside the choices the UI can represent.
func _read_fps_option(config: ConfigFile, key: String, fallback: int, last: int) -> int:
	var value: Variant = config.get_value("display", key, fallback)
	return clampi(value, 0, last) if typeof(value) == TYPE_INT else fallback

func animation_redraw_interval() -> float:
	return ANIMATION_INTERVALS[clampi(animation_rate, UpdateRate.LOW, UpdateRate.HIGH)]

func camera_redraw_interval() -> float:
	return UPDATE_INTERVALS[clampi(camera_update_rate, UpdateRate.LOW, UpdateRate.HIGH)]

## Cadence for course-wide golfer coordination. Individual golfers still run
## their movement and shot animations every frame; only group scheduling slows.
func simulation_update_interval() -> float:
	return UPDATE_INTERVALS[clampi(golfer_update_rate, UpdateRate.LOW, UpdateRate.HIGH)]

## A prop's stretched sun shadow follows the sun and costs a second polygon;
## the contact blob under it is the cheap half and is what keeps a prop
## standing on the ground rather than hovering over it.
func drop_shadows_enabled() -> bool:
	return shadow_detail == ShadowDetail.FULL

func contact_shadows_enabled() -> bool:
	return shadow_detail != ShadowDetail.OFF

## Fraction of the course's duck families and butterflies to keep. Off is a
## clean win: the overlay stops running and drawing altogether.
func wildlife_density() -> float:
	return WILDLIFE_DENSITY[clampi(wildlife_detail, WildlifeDetail.OFF, WildlifeDetail.FULL)]

## The particle effects are decoration too, and one shot can spawn a dozen
## nodes and a tween each. Off builds none of them; Reduced halves the burst.
func effect_particle_scale() -> float:
	return EFFECT_PARTICLE_SCALE[clampi(effect_detail, EffectDetail.OFF, EffectDetail.FULL)]

func particle_burst_enabled() -> bool:
	return effect_detail != EffectDetail.OFF

## How many particles of a burst to build, rounded to whole pieces and kept at
## one rather than eight if the setting says a burst should still play.
func particle_count(base_count: int) -> int:
	if base_count <= 0 or not particle_burst_enabled():
		return 0
	return maxi(1, int(round(float(base_count) * effect_particle_scale())))

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
				GraphicsSetting.SHADOW_DETAIL: ShadowDetail.OFF,
				GraphicsSetting.WILDLIFE_DETAIL: WildlifeDetail.OFF,
				GraphicsSetting.EFFECT_DETAIL: EffectDetail.REDUCED,
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
				GraphicsSetting.SHADOW_DETAIL: ShadowDetail.FULL,
				GraphicsSetting.WILDLIFE_DETAIL: WildlifeDetail.FULL,
				GraphicsSetting.EFFECT_DETAIL: EffectDetail.FULL,
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
				GraphicsSetting.SHADOW_DETAIL: ShadowDetail.FULL,
				GraphicsSetting.WILDLIFE_DETAIL: WildlifeDetail.FULL,
				GraphicsSetting.EFFECT_DETAIL: EffectDetail.FULL,
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
		GraphicsSetting.SHADOW_DETAIL:
			return clampi(value, ShadowDetail.OFF, ShadowDetail.FULL)
		GraphicsSetting.WILDLIFE_DETAIL:
			return clampi(value, WildlifeDetail.OFF, WildlifeDetail.FULL)
		GraphicsSetting.EFFECT_DETAIL:
			return clampi(value, EffectDetail.OFF, EffectDetail.FULL)
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
		GraphicsSetting.SHADOW_DETAIL:
			shadow_detail = value
		GraphicsSetting.WILDLIFE_DETAIL:
			wildlife_detail = value
		GraphicsSetting.EFFECT_DETAIL:
			effect_detail = value

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
