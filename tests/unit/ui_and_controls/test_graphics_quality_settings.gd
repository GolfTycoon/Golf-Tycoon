extends GameTest
## The decoration half of the graphics settings: prop shadows, course wildlife
## and impact particle bursts. Each is a quality choice of its own, follows the
## presets, clamps what a hand-edited settings file asks for, and reaches the
## things that paint it - the shadow renderer, the wildlife overlay and the
## effect that is never built at Off.

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
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.CONTACT_ONLY)
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
	assert_eq(restored.shadow_detail, PerformanceSettings.ShadowDetail.CONTACT_ONLY)
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

func test_shadow_choices_split_drop_and_contact_shadows() -> void:
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.OFF)
	assert_false(PerformanceSettings.contact_shadows_enabled())
	assert_false(PerformanceSettings.drop_shadows_enabled())

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.CONTACT_ONLY)
	assert_true(PerformanceSettings.contact_shadows_enabled(), "a contact blob still grounds a prop")
	assert_false(PerformanceSettings.drop_shadows_enabled(), "the stretched sun shadow is the extra polygon")

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.FULL)
	assert_true(PerformanceSettings.contact_shadows_enabled())
	assert_true(PerformanceSettings.drop_shadows_enabled())


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

func test_shadow_renderer_builds_only_the_shapes_the_choice_allows() -> void:
	var config := ShadowRenderer.ShadowConfig.new(36.0, 40.0)
	var off := ShadowRenderer.shadow_plan(config, PerformanceSettings.ShadowDetail.OFF)
	assert_false(off["contact"])
	assert_false(off["drop"])
	var contact := ShadowRenderer.shadow_plan(config, PerformanceSettings.ShadowDetail.CONTACT_ONLY)
	assert_true(contact["contact"])
	assert_false(contact["drop"])
	var full := ShadowRenderer.shadow_plan(config, PerformanceSettings.ShadowDetail.FULL)
	assert_true(full["contact"])
	assert_true(full["drop"])

	var parent: Node2D = add_child_autofree(Node2D.new())
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.OFF)
	assert_true(ShadowRenderer.add_shadows_to_entity(parent, config).is_empty(),
		"no shadow polygons are built when shadows are off")
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.CONTACT_ONLY)
	var only_contact := ShadowRenderer.add_shadows_to_entity(parent, config)
	assert_true(only_contact.has("contact"))
	assert_false(only_contact.has("drop"))
	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.FULL)
	var both := ShadowRenderer.add_shadows_to_entity(parent, config)
	assert_true(both.has("contact"))
	assert_true(both.has("drop"))
	for shadow in only_contact.values() + both.values():
		shadow.queue_free()


func test_a_placed_decoration_rebuilds_its_shadows_when_the_setting_changes() -> void:
	var grid := make_grid(8, 8)
	await process_frames(1)
	var decoration := Decoration.new()
	decoration.terrain_grid = grid
	decoration.grid_position = Vector2i(4, 4)
	add_child_autofree(decoration)
	await process_frames(1)

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.FULL)
	decoration.set_decoration_type("golfer_statue", {})
	await process_frames(1)
	assert_eq(decoration._shadow_refs.size(), 2, "a tall prop casts a contact and a sun shadow")

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.CONTACT_ONLY)
	assert_eq(decoration._shadow_refs.size(), 1,
		"an existing prop follows the setting without being rebuilt")
	assert_true(decoration._shadow_refs.has("contact"))

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.OFF)
	assert_true(decoration._shadow_refs.is_empty())
	await process_frames(1)
	assert_null(decoration.get_node("Visual").get_node_or_null("DropShadow"),
		"the freed polygons are gone from the prop, not merely forgotten")
	assert_null(decoration.get_node("Visual").get_node_or_null("ContactShadow"))

	PerformanceSettings.set_graphics_setting(
		PerformanceSettings.GraphicsSetting.SHADOW_DETAIL, PerformanceSettings.ShadowDetail.FULL)
	assert_eq(decoration._shadow_refs.size(), 2, "and puts them back when shadows return")


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
