extends GameTest
## Decorative graphics settings: the ball shadow, course wildlife and impact
## particle bursts. Each follows presets and validates saved values. Improvement
## art stays shadow-free at every quality level.

const PerformanceSettingsScript := preload("res://scripts/autoload/performance_settings.gd")

var _original_preset: int = PerformanceSettings.GraphicsPreset.AUTO
var _original_settings: Dictionary = {}


func before_each() -> void:
	super()
	_original_preset = PerformanceSettings.graphics_preset
	_original_settings.clear()
	for setting in PerformanceSettings.GRAPHICS_SETTINGS:
		_original_settings[setting] = PerformanceSettings.get_graphics_setting(setting)


func after_each() -> void:
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.CUSTOM)
	for setting in PerformanceSettings.GRAPHICS_SETTINGS:
		PerformanceSettings.set_graphics_setting(setting, _original_settings[setting])
	PerformanceSettings.set_graphics_preset(_original_preset)
	super()


# ---------------------------------------------------------------------------
# The settings themselves
# ---------------------------------------------------------------------------

func test_a_fresh_settings_file_asks_for_full_detail() -> void:
	var settings = PerformanceSettingsScript.new()
	assert_eq(settings.shadow_detail, PerformanceSettings.ShadowDetail.FULL)
	assert_eq(settings.wildlife_detail, PerformanceSettings.WildlifeDetail.FULL)
	assert_eq(settings.effect_detail, PerformanceSettings.EffectDetail.FULL)
	settings.free()


func test_each_detail_setting_is_independent_and_labels_custom() -> void:
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.BALANCED)
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.OFF)
	assert_eq(PerformanceSettings.graphics_preset, PerformanceSettings.GraphicsPreset.CUSTOM,
		"editing one detail setting makes the preset Custom")
	assert_eq(PerformanceSettings.wildlife_detail, PerformanceSettings.WildlifeDetail.FULL,
		"the other detail settings keep the preset's values")
	assert_eq(PerformanceSettings.effect_detail, PerformanceSettings.EffectDetail.FULL)


func test_detail_values_are_clamped_to_their_choices() -> void:
	var shadow := PerformanceSettings.GraphicsSetting.SHADOW_DETAIL
	PerformanceSettings.set_graphics_setting(shadow, 99)
	assert_eq(PerformanceSettings.shadow_detail, PerformanceSettings.ShadowDetail.FULL)
	PerformanceSettings.set_graphics_setting(shadow, -4)
	assert_eq(PerformanceSettings.shadow_detail, PerformanceSettings.ShadowDetail.OFF)

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, 99)
	assert_eq(PerformanceSettings.wildlife_detail, PerformanceSettings.WildlifeDetail.FULL)
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.EFFECT_DETAIL, -1)
	assert_eq(PerformanceSettings.effect_detail, PerformanceSettings.EffectDetail.OFF)


func test_performance_preset_trims_decoration_and_the_others_keep_it() -> void:
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.PERFORMANCE)
	assert_eq(PerformanceSettings.shadow_detail, PerformanceSettings.ShadowDetail.OFF)
	assert_eq(PerformanceSettings.wildlife_detail, PerformanceSettings.WildlifeDetail.OFF)
	assert_eq(PerformanceSettings.effect_detail, PerformanceSettings.EffectDetail.REDUCED,
		"Performance keeps a lighter burst rather than dropping the shot's feedback")

	for preset in [PerformanceSettings.GraphicsPreset.BALANCED, PerformanceSettings.GraphicsPreset.HIGH]:
		PerformanceSettings.set_graphics_preset(preset)
		assert_eq(PerformanceSettings.shadow_detail, PerformanceSettings.ShadowDetail.FULL)
		assert_eq(PerformanceSettings.wildlife_detail, PerformanceSettings.WildlifeDetail.FULL)
		assert_eq(PerformanceSettings.effect_detail, PerformanceSettings.EffectDetail.FULL)


func test_detail_settings_round_trip_through_the_settings_file() -> void:
	var settings = PerformanceSettingsScript.new()
	settings.set_graphics_preset(PerformanceSettings.GraphicsPreset.CUSTOM)
	settings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.OFF)
	settings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.REDUCED)
	settings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.EFFECT_DETAIL, PerformanceSettings.EffectDetail.OFF)
	var config := ConfigFile.new()
	settings.save_to_config(config)
	settings.free()

	var restored = PerformanceSettingsScript.new()
	restored.load_from_config(config)
	assert_eq(restored.graphics_preset, PerformanceSettings.GraphicsPreset.CUSTOM)
	assert_eq(restored.shadow_detail, PerformanceSettings.ShadowDetail.OFF)
	assert_eq(restored.wildlife_detail, PerformanceSettings.WildlifeDetail.REDUCED)
	assert_eq(restored.effect_detail, PerformanceSettings.EffectDetail.OFF)
	restored.free()


## A settings file written before these controls existed names no detail keys;
## a Custom profile falls back to the Balanced values rather than zero (Off).
func test_older_settings_files_keep_full_detail() -> void:
	var named := ConfigFile.new()
	named.set_value("display", "graphics_preset", PerformanceSettings.GraphicsPreset.HIGH)
	var settings = PerformanceSettingsScript.new()
	settings.load_from_config(named)
	assert_eq(settings.shadow_detail, PerformanceSettings.ShadowDetail.FULL)
	assert_eq(settings.wildlife_detail, PerformanceSettings.WildlifeDetail.FULL)
	assert_eq(settings.effect_detail, PerformanceSettings.EffectDetail.FULL)
	settings.free()

	var custom := ConfigFile.new()
	custom.set_value("display", "graphics_preset", PerformanceSettings.GraphicsPreset.CUSTOM)
	custom.set_value("graphics", "terrain_quality", PerformanceSettings.TerrainQuality.FAST)
	var old_custom = PerformanceSettingsScript.new()
	old_custom.load_from_config(custom)
	assert_eq(old_custom.terrain_quality, PerformanceSettings.TerrainQuality.FAST,
		"the keys the file does have are still read")
	assert_eq(old_custom.shadow_detail, PerformanceSettings.ShadowDetail.FULL)
	assert_eq(old_custom.wildlife_detail, PerformanceSettings.WildlifeDetail.FULL)
	assert_eq(old_custom.effect_detail, PerformanceSettings.EffectDetail.FULL)
	old_custom.free()


# ---------------------------------------------------------------------------
# What the settings mean
# ---------------------------------------------------------------------------

func test_legacy_contact_only_and_full_choices_both_show_the_ball_shadow() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "graphics_preset", PerformanceSettings.GraphicsPreset.CUSTOM)
	var settings := PerformanceSettingsScript.new()
	for saved in [PerformanceSettings.ShadowDetail.CONTACT_ONLY, PerformanceSettings.ShadowDetail.FULL]:
		config.set_value("graphics", "shadow_detail", saved)
		settings.load_from_config(config)
		assert_eq(settings.shadow_detail, PerformanceSettings.ShadowDetail.FULL,
			"legacy choice %s selects the same On option" % saved)
		assert_true(settings.contact_shadows_enabled())
	settings.free()


func test_wildlife_density_halves_and_clears_the_residents() -> void:
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.FULL)
	assert_almost_eq(PerformanceSettings.wildlife_density(), 1.0, 0.0001)
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.REDUCED)
	assert_almost_eq(PerformanceSettings.wildlife_density(), 0.5, 0.0001)
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.OFF)
	assert_almost_eq(PerformanceSettings.wildlife_density(), 0.0, 0.0001)


func test_particle_bursts_shrink_with_the_setting() -> void:
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.EFFECT_DETAIL, PerformanceSettings.EffectDetail.FULL)
	assert_true(PerformanceSettings.particle_burst_enabled())
	assert_eq(PerformanceSettings.particle_count(8), 8)
	assert_eq(PerformanceSettings.particle_count(12), 12)

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.EFFECT_DETAIL, PerformanceSettings.EffectDetail.REDUCED)
	assert_eq(PerformanceSettings.particle_count(8), 4)
	assert_eq(PerformanceSettings.particle_count(12), 6)
	assert_eq(PerformanceSettings.particle_count(1), 1, "a burst still keeps one particle")

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.EFFECT_DETAIL, PerformanceSettings.EffectDetail.OFF)
	assert_false(PerformanceSettings.particle_burst_enabled())
	assert_eq(PerformanceSettings.particle_count(8), 0)


# ---------------------------------------------------------------------------
# The things that paint the decoration
# ---------------------------------------------------------------------------

func test_improvements_stay_shadow_free_across_graphics_presets() -> void:
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.HIGH)
	var grid := make_grid(8, 8)
	var entities := make_entity_layer(grid)
	var catalogue: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/decorations.json"))["decorations"]
	# Also cover a data-defined improvement without sprite or path furniture art.
	catalogue["test_ornament"] = {"color": "#808080"}
	var art_counts := {
		"fountain": 2, # Sprite and spray.
		"ball_washer": 1, "park_bench": 1, "golfer_statue": 1, "sundial": 1,
		"test_ornament": 1,
	}
	var x := 1
	for type in art_counts:
		var improvement := entities.place_decoration(type, Vector2i(x, 4), catalogue)
		assert_not_null(improvement, "%s is placed" % type)
		x += 1

	for preset in [PerformanceSettings.GraphicsPreset.HIGH, PerformanceSettings.GraphicsPreset.PERFORMANCE,
			PerformanceSettings.GraphicsPreset.BALANCED]:
		PerformanceSettings.set_graphics_preset(preset)
		await process_frames(1)
		for improvement in entities.decorations.values():
			var type: String = improvement.decoration_type
			assert_eq(improvement.get_node("Visual").get_child_count(), art_counts[type],
				"%s draws only its art in %s" % [type, PerformanceSettings.preset_label(preset)])


func test_wildlife_overlay_follows_the_setting_without_a_reload() -> void:
	var grid := make_grid(20, 20)
	await process_frames(1)
	grid.begin_batch()
	for x in range(10):
		for y in range(10):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.WATER)
	grid.end_batch_quiet()
	# Batch edits are quiet so the overlays are not redrawn once per tile: the
	# overlay rescans the painted course as it would after a load.
	grid._wildlife.rebuild()

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.FULL)
	assert_true(grid._wildlife.visible)
	assert_gt(grid._wildlife._duck_homes.size(), 0, "ponds carry duck families at Full")
	assert_eq(grid._wildlife._resident_limit(CourseWildlife.MAX_DUCK_FAMILIES),
		CourseWildlife.MAX_DUCK_FAMILIES)
	var full_ducks := grid._wildlife._duck_homes.size()

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.REDUCED)
	assert_true(grid._wildlife.visible)
	assert_lte(grid._wildlife._duck_homes.size(), full_ducks,
		"Reduced never keeps more residents than Full")
	assert_eq(grid._wildlife._resident_limit(CourseWildlife.MAX_DUCK_FAMILIES),
		int(floor(float(CourseWildlife.MAX_DUCK_FAMILIES) * 0.5)))

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.OFF)
	assert_false(grid._wildlife.visible, "the overlay stops drawing entirely")
	assert_true(grid._wildlife._duck_homes.is_empty(), "the residents are cleared with it")
	assert_true(grid._wildlife._garden_homes.is_empty())
	var stopped_at := grid._wildlife._time
	grid._wildlife._process(0.5)
	assert_almost_eq(grid._wildlife._time, stopped_at, 0.0001,
		"a switched-off overlay does not even keep its clock")

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.WILDLIFE_DETAIL, PerformanceSettings.WildlifeDetail.FULL)
	assert_true(grid._wildlife.visible)
	assert_eq(grid._wildlife._duck_homes.size(), full_ducks,
		"turning the residents back on restores the same families")


func test_impact_effects_are_not_built_at_off_and_halve_at_reduced() -> void:
	var parent: Node2D = add_child_autofree(Node2D.new())
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.EFFECT_DETAIL, PerformanceSettings.EffectDetail.OFF)
	assert_null(LandingImpactEffect.create_at(parent, Vector2.ZERO))
	assert_null(SandSprayEffect.create_at(parent, Vector2.ZERO))
	assert_null(WaterSplashEffect.create_at(parent, Vector2.ZERO))

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.EFFECT_DETAIL, PerformanceSettings.EffectDetail.REDUCED)
	var sand := SandSprayEffect.create_at(parent, Vector2.ZERO)
	assert_not_null(sand)
	await process_frames(1)
	assert_eq(sand._particle_count, int(round(float(SandSprayEffect.PARTICLE_COUNT) * 0.5)),
		"a reduced burst spawns half the particles")
	assert_eq(sand.get_child_count(), sand._particle_count)

	var splash := WaterSplashEffect.create_at(parent, Vector2.ZERO)
	assert_not_null(splash)
	await process_frames(1)
	assert_eq(splash._particle_count, int(round(float(WaterSplashEffect.PARTICLE_COUNT) * 0.5)))

	var impact := LandingImpactEffect.create_at(parent, Vector2.ZERO)
	assert_not_null(impact)
	await process_frames(1)
	assert_eq(impact._particle_count, int(round(float(LandingImpactEffect.PARTICLE_COUNT) * 0.5)))
