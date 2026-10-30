extends GameTest
## The FPS preference is independent of graphics presets, survives settings
## round trips, and the readout averages frames over real rather than game time.

const PerformanceSettingsScript := preload("res://scripts/autoload/performance_settings.gd")

var _saved_fps: Dictionary = {}

func before_each() -> void:
	super()
	_saved_fps = {
		"enabled": PerformanceSettings.fps_counter_enabled,
		"position": PerformanceSettings.fps_counter_position,
		"size": PerformanceSettings.fps_counter_size,
		"refresh": PerformanceSettings.fps_counter_refresh,
	}

func after_each() -> void:
	PerformanceSettings.set_fps_counter_enabled(false)
	PerformanceSettings.set_fps_counter_position(_saved_fps["position"])
	PerformanceSettings.set_fps_counter_size(_saved_fps["size"])
	PerformanceSettings.set_fps_counter_refresh(_saved_fps["refresh"])
	PerformanceSettings.set_fps_counter_enabled(_saved_fps["enabled"])
	super()

func test_old_settings_default_to_a_hidden_counter() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "graphics_preset", PerformanceSettings.GraphicsPreset.HIGH)
	var settings = PerformanceSettingsScript.new()
	settings.load_from_config(config)
	assert_false(settings.fps_counter_enabled)
	assert_eq(settings.fps_counter_position, PerformanceSettings.FpsCounterPosition.TOP_CENTER)
	assert_eq(settings.fps_counter_size, PerformanceSettings.FpsCounterSize.MEDIUM)
	assert_eq(settings.fps_counter_refresh, PerformanceSettings.FpsCounterRefresh.NORMAL)
	settings.free()

func test_preferences_round_trip_without_changing_graphics_or_other_sections() -> void:
	var settings = PerformanceSettingsScript.new()
	settings.set_graphics_preset(PerformanceSettings.GraphicsPreset.HIGH)
	settings.set_fps_counter_enabled(true)
	settings.set_fps_counter_position(PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	settings.set_fps_counter_size(PerformanceSettings.FpsCounterSize.LARGE)
	settings.set_fps_counter_refresh(PerformanceSettings.FpsCounterRefresh.FAST)
	assert_eq(settings.graphics_preset, PerformanceSettings.GraphicsPreset.HIGH,
		"customizing the counter does not make the graphics preset Custom")
	settings.set_graphics_preset(PerformanceSettings.GraphicsPreset.PERFORMANCE)
	assert_true(settings.fps_counter_enabled, "a graphics preset does not hide the counter")
	assert_eq(settings.fps_counter_position, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)

	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", 0.3)
	config.set_value("display", "vsync", 1)
	settings.save_to_config(config)
	var restored = PerformanceSettingsScript.new()
	restored.load_from_config(config)
	assert_true(restored.fps_counter_enabled)
	assert_eq(restored.fps_counter_position, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	assert_eq(restored.fps_counter_size, PerformanceSettings.FpsCounterSize.LARGE)
	assert_eq(restored.fps_counter_refresh, PerformanceSettings.FpsCounterRefresh.FAST)
	assert_eq(restored.graphics_preset, PerformanceSettings.GraphicsPreset.PERFORMANCE)
	assert_eq(config.get_value("audio", "master_volume"), 0.3)
	assert_eq(config.get_value("display", "vsync"), 1)
	restored.free()
	settings.free()

func test_invalid_saved_choices_are_bounded_or_use_defaults() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fps_counter_enabled", "not a boolean")
	config.set_value("display", "fps_counter_position", 500)
	config.set_value("display", "fps_counter_size", -4)
	config.set_value("display", "fps_counter_refresh", "not a choice")
	var settings = PerformanceSettingsScript.new()
	settings.load_from_config(config)
	assert_false(settings.fps_counter_enabled)
	assert_eq(settings.fps_counter_position, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	assert_eq(settings.fps_counter_size, PerformanceSettings.FpsCounterSize.SMALL)
	assert_eq(settings.fps_counter_refresh, PerformanceSettings.FpsCounterRefresh.NORMAL)
	assert_eq(settings.fps_counter_font_size(), PerformanceSettings.FPS_FONT_SIZES[0])
	assert_almost_eq(settings.fps_counter_refresh_interval(), 0.5, 0.001)
	settings.free()

func test_counter_is_idle_when_hidden_and_uses_wall_clock_samples() -> void:
	PerformanceSettings.set_fps_counter_enabled(false)
	PerformanceSettings.set_fps_counter_refresh(PerformanceSettings.FpsCounterRefresh.NORMAL)
	var counter: FpsCounter = add_child_autofree(FpsCounter.new())
	assert_false(counter._panel.visible)
	assert_false(counter.is_processing(), "a hidden counter does not sample each frame")
	assert_eq(counter.process_mode, Node.PROCESS_MODE_ALWAYS, "it can run while the tree is paused")
	assert_eq(counter._root.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(counter._panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(counter._label.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	PerformanceSettings.set_fps_counter_enabled(true)
	assert_true(counter._panel.visible)
	assert_true(counter.is_processing())
	# Drive exact timestamps instead of relying on the test runner's frame rate.
	counter.set_process(false)
	counter._reset_sample(1_000_000)
	Engine.time_scale = 0.0
	for tick in [1_100_000, 1_200_000, 1_300_000, 1_400_000]:
		counter._sample_frame(tick)
	assert_eq(counter._label.text, "-- FPS", "the readout waits for its interval")
	counter._sample_frame(1_500_000)
	assert_eq(counter._label.text, "10 FPS", "five frames in half a real second")
	counter._sample_frame(1_700_000)
	counter._sample_frame(2_000_000)
	assert_eq(counter._label.text, "4 FPS", "the next interval is measured afresh")

	PerformanceSettings.set_fps_counter_refresh(PerformanceSettings.FpsCounterRefresh.FAST)
	counter.set_process(false)
	counter._reset_sample(3_000_000)
	counter._sample_frame(3_250_000)
	assert_eq(counter._label.text, "4 FPS", "the fast choice uses a quarter-second sample")
	PerformanceSettings.set_fps_counter_enabled(false)
	assert_false(counter._panel.visible)
	assert_false(counter.is_processing())
