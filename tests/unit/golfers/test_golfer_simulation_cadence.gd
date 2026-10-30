extends GameTest
## Course-wide golfer coordination is throttled independently from each
## golfer's per-frame movement and shot animation.

var _manager: GolferManager
var _original_preset: int
var _original_graphics_settings: Dictionary = {}

func before_each() -> void:
	super.before_each()
	_original_preset = PerformanceSettings.graphics_preset
	_original_graphics_settings.clear()
	for setting in PerformanceSettings.GRAPHICS_SETTINGS:
		_original_graphics_settings[setting] = PerformanceSettings.get_graphics_setting(setting)
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.BALANCED)
	GameManager.current_mode = GameManager.GameMode.SIMULATING
	GameManager.is_paused = false
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	_manager = add_child_autofree(GolferManager.new())

func after_each() -> void:
	if _original_preset == PerformanceSettings.GraphicsPreset.CUSTOM:
		PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.CUSTOM)
		for setting in PerformanceSettings.GRAPHICS_SETTINGS:
			PerformanceSettings.set_graphics_setting(setting, _original_graphics_settings[setting])
	else:
		PerformanceSettings.set_graphics_preset(_original_preset)
	super.after_each()

func test_balanced_schedules_group_checks_at_30_hz() -> void:
	_manager._process(0.02)
	assert_true(_manager._groups_dirty, "the first partial interval must not scan the group table")
	_manager._process(0.02)
	assert_false(_manager._groups_dirty, "the manager scans once the 30 Hz interval elapses")

func test_performance_preset_reduces_group_checks_to_15_hz() -> void:
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.PERFORMANCE)
	_manager._process(0.04)
	assert_true(_manager._groups_dirty, "a 40 ms step is shorter than the 15 Hz interval")
	_manager._process(0.04)
	assert_false(_manager._groups_dirty, "the manager scans after the 15 Hz interval elapses")

func test_high_quality_keeps_group_checks_at_60_hz() -> void:
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.HIGH)
	_manager._process(0.02)
	assert_false(_manager._groups_dirty, "High quality uses the 60 Hz group interval")

func test_group_cadence_scales_with_simulation_speed() -> void:
	GameManager.set_speed(GameManager.GameSpeed.FAST)
	_manager._process(0.05)
	assert_true(_manager._groups_dirty, "half a scaled interval is not enough for a group check")
	_manager._process(0.05)
	assert_false(_manager._groups_dirty, "the cadence follows game time at 3x speed")
