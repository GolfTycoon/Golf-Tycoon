extends GameTest
## The saved UI scale preference: automatic for a fresh settings file, a
## deliberate manual size kept, and older files (which stored the effective
## scale after every display change) migrated without pinning everyone to the
## old fixed 100%.

var _saved_mode: int = 0
var _saved_scale: float = 1.0
var _saved_root_scale: float = 1.0


func before_each() -> void:
	super()
	_saved_mode = Screen.ui_scale_mode
	_saved_scale = Screen.ui_scale
	_saved_root_scale = get_tree().root.content_scale_factor


func after_each() -> void:
	if _saved_mode == Screen.UIScaleMode.AUTO:
		Screen.set_ui_scale_mode(Screen.UIScaleMode.AUTO, false)
	else:
		Screen.set_ui_scale(_saved_scale, false)
	get_tree().root.content_scale_factor = _saved_root_scale
	super()


func _config_with(values: Dictionary) -> ConfigFile:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("display", key, values[key])
	return config


func test_a_fresh_settings_file_uses_the_detected_scale() -> void:
	Screen.load_ui_scale_from_config(ConfigFile.new())
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.AUTO, "automatic is the shipped default")
	assert_almost_eq(get_tree().root.content_scale_factor, Screen.detected_ui_scale, 0.001,
		"the detected scale is what the root is given")


func test_an_older_settings_file_at_100_percent_migrates_to_automatic() -> void:
	# Before this setting existed the game wrote ui_scale = 1.0 whenever any
	# display option changed; that was the fixed default, not a choice.
	Screen.load_ui_scale_from_config(_config_with({"ui_scale": 1.0}))
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.AUTO,
		"a stored 100% from an older build is the old default")


func test_an_older_settings_file_with_another_scale_stays_manual() -> void:
	Screen.load_ui_scale_from_config(_config_with({"ui_scale": 1.35}))
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.MANUAL,
		"a non-default scale was a deliberate choice")
	assert_almost_eq(Screen.ui_scale, 1.35, 0.001)
	assert_almost_eq(get_tree().root.content_scale_factor, 1.35, 0.001,
		"the chosen size is applied to the running game")


func test_a_saved_automatic_choice_ignores_the_stored_effective_scale() -> void:
	var config := _config_with({
		"ui_scale_mode": Screen.UIScaleMode.AUTO,
		"ui_scale": 2.0,
	})
	Screen.load_ui_scale_from_config(config)
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.AUTO)
	assert_almost_eq(Screen.ui_scale, Screen.detected_ui_scale, 0.001,
		"automatic sizing re-detects instead of trusting the last effective size")


func test_a_saved_manual_scale_is_restored() -> void:
	var config := _config_with({
		"ui_scale_mode": Screen.UIScaleMode.MANUAL,
		"ui_scale": 1.5,
	})
	Screen.load_ui_scale_from_config(config)
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.MANUAL)
	assert_almost_eq(Screen.ui_scale, 1.5, 0.001)
	assert_almost_eq(get_tree().root.content_scale_factor, 1.5, 0.001)


func test_moving_the_slider_takes_manual_control() -> void:
	Screen.set_ui_scale_mode(Screen.UIScaleMode.AUTO, false)
	Screen.set_ui_scale(1.4, false)
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.MANUAL,
		"choosing a size turns automatic sizing off")
	assert_almost_eq(Screen.ui_scale, 1.4, 0.001)
	assert_almost_eq(get_tree().root.content_scale_factor, 1.4, 0.001)


func test_the_preference_round_trips_through_the_settings_file() -> void:
	Screen.set_ui_scale(1.4, false)
	var written := ConfigFile.new()
	Screen.save_ui_scale_to_config(written)
	assert_eq(int(written.get_value("display", "ui_scale_mode")), Screen.UIScaleMode.MANUAL)
	assert_almost_eq(float(written.get_value("display", "ui_scale")), 1.4, 0.001)

	# A new session starting from that file.
	Screen.set_ui_scale_mode(Screen.UIScaleMode.AUTO, false)
	Screen.load_ui_scale_from_config(written)
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.MANUAL)
	assert_almost_eq(Screen.ui_scale, 1.4, 0.001)


func test_resetting_preferences_goes_back_to_automatic_sizing() -> void:
	Screen.set_ui_scale(2.0, false)
	Screen.reset_ui_scale(false)
	assert_eq(Screen.ui_scale_mode, Screen.UIScaleMode.AUTO)
	assert_almost_eq(Screen.ui_scale, Screen.detected_ui_scale, 0.001)


func test_a_manual_scale_is_clamped_to_the_supported_range() -> void:
	Screen.set_ui_scale(50.0, false)
	assert_almost_eq(Screen.ui_scale, Screen.MAX_UI_SCALE, 0.001)
	Screen.set_ui_scale(0.1, false)
	assert_almost_eq(Screen.ui_scale, Screen.MIN_UI_SCALE, 0.001)
