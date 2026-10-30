extends MainSceneTest
## Exercise the real main-scene overlay and the Display controls from both
## entry points, including persistence, responsive placement and click-through.

var _saved_fps: Dictionary = {}
var _had_settings_file := false
var _settings_bytes := PackedByteArray()
var _time_scale := 1.0
var _ui_scale := 1.0

func before_each() -> void:
	super()
	_saved_fps = {
		"enabled": PerformanceSettings.fps_counter_enabled,
		"position": PerformanceSettings.fps_counter_position,
		"size": PerformanceSettings.fps_counter_size,
		"refresh": PerformanceSettings.fps_counter_refresh,
	}
	_time_scale = Engine.time_scale
	_ui_scale = get_tree().root.content_scale_factor
	_had_settings_file = FileAccess.file_exists(SaveManager.SETTINGS_PATH)
	if _had_settings_file:
		_settings_bytes = FileAccess.get_file_as_bytes(SaveManager.SETTINGS_PATH)
	PerformanceSettings.set_fps_counter_enabled(false)
	PerformanceSettings.set_fps_counter_position(PerformanceSettings.FpsCounterPosition.TOP_CENTER)
	PerformanceSettings.set_fps_counter_size(PerformanceSettings.FpsCounterSize.MEDIUM)
	PerformanceSettings.set_fps_counter_refresh(PerformanceSettings.FpsCounterRefresh.NORMAL)

func after_each() -> void:
	var menu := main.get_node_or_null("UI/HUD/SettingsMenu")
	if menu != null:
		menu.free()
	Engine.time_scale = _time_scale
	get_tree().root.content_scale_factor = _ui_scale
	PerformanceSettings.set_fps_counter_enabled(false)
	PerformanceSettings.set_fps_counter_position(_saved_fps["position"])
	PerformanceSettings.set_fps_counter_size(_saved_fps["size"])
	PerformanceSettings.set_fps_counter_refresh(_saved_fps["refresh"])
	PerformanceSettings.set_fps_counter_enabled(_saved_fps["enabled"])
	if _had_settings_file:
		var file := FileAccess.open(SaveManager.SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(_settings_bytes)
		file.close()
	elif FileAccess.file_exists(SaveManager.SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SETTINGS_PATH))
	await super()

func _choose(selector: OptionButton, value: int) -> void:
	var index := selector.get_item_index(value)
	assert_gte(index, 0, "the choice is available")
	if index >= 0:
		selector.select(index)
		selector.item_selected.emit(index)

func test_display_settings_apply_save_and_restore_the_live_counter() -> void:
	await set_window(DESIGN_WINDOW)
	var counter := main.get_node("FpsCounter") as FpsCounter
	assert_false(counter._panel.visible, "the counter starts disabled")
	# Verify saving the display card keeps unrelated preferences in the file.
	SaveManager.set_user_preference("fps_test", "keep", "untouched")
	main._on_main_menu_settings()
	await process_frames(3)
	var menu := main.get_node("UI/HUD/SettingsMenu") as SettingsMenu
	menu._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(3)
	var toggle := menu.find_child("Toggle_show_fps_counter", true, false) as CheckButton
	var position := menu.find_child("FpsCounterPosition", true, false) as OptionButton
	var size := menu.find_child("FpsCounterSize", true, false) as OptionButton
	var refresh := menu.find_child("FpsCounterRefresh", true, false) as OptionButton
	assert_not_null(toggle, "Display offers the counter toggle")
	assert_not_null(position, "and a position selector")
	assert_not_null(size, "and a size selector")
	assert_not_null(refresh, "and a refresh selector")
	if toggle == null or position == null or size == null or refresh == null:
		return
	assert_false(toggle.button_pressed)
	assert_false(position.disabled, "it can be configured before being enabled")
	_choose(position, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	_choose(size, PerformanceSettings.FpsCounterSize.LARGE)
	_choose(refresh, PerformanceSettings.FpsCounterRefresh.FAST)
	assert_false(counter._panel.visible)
	toggle.button_pressed = true
	assert_true(counter._panel.visible, "enabling the toggle updates the overlay immediately")
	assert_eq(counter._label.get_theme_font_size("font_size"), PerformanceSettings.FPS_FONT_SIZES[2])
	assert_eq(PerformanceSettings.fps_counter_position, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	assert_eq(PerformanceSettings.fps_counter_refresh, PerformanceSettings.FpsCounterRefresh.FAST)

	var saved := ConfigFile.new()
	assert_eq(saved.load(SaveManager.SETTINGS_PATH), OK)
	assert_true(saved.get_value("display", "fps_counter_enabled", false))
	assert_eq(saved.get_value("display", "fps_counter_position", -1), PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	assert_eq(saved.get_value("display", "fps_counter_size", -1), PerformanceSettings.FpsCounterSize.LARGE)
	assert_eq(saved.get_value("display", "fps_counter_refresh", -1), PerformanceSettings.FpsCounterRefresh.FAST)
	assert_eq(saved.get_value("fps_test", "keep", ""), "untouched")

	# Simulate the next launch loading the saved file: the existing overlay also
	# reacts to a reload, just as a new one would read the restored preferences.
	PerformanceSettings.set_fps_counter_enabled(false)
	PerformanceSettings.set_fps_counter_position(PerformanceSettings.FpsCounterPosition.TOP_LEFT)
	PerformanceSettings.load_from_config(saved)
	assert_true(counter._panel.visible)
	assert_eq(PerformanceSettings.fps_counter_position, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	assert_eq(PerformanceSettings.fps_counter_size, PerformanceSettings.FpsCounterSize.LARGE)
	assert_eq(PerformanceSettings.fps_counter_refresh, PerformanceSettings.FpsCounterRefresh.FAST)
	main._set_gameplay_ui_visible(false)
	assert_true(counter._panel.visible, "the readout is not hidden with the gameplay HUD")
	main._set_gameplay_ui_visible(true)
	assert_true(counter._panel.visible, "it is also shown over the course")
	main._set_gameplay_ui_visible(false)

	# Pause-menu Settings uses the same preferences, and can turn it back off.
	menu.free()
	main._show_settings_menu()
	await process_frames(3)
	var pause_settings := main.get_node("UI/HUD/SettingsMenu") as SettingsMenu
	assert_eq(pause_settings.origin, SettingsMenu.Origin.PAUSE_MENU)
	pause_settings._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(3)
	var pause_toggle := pause_settings.find_child("Toggle_show_fps_counter", true, false) as CheckButton
	var pause_position := pause_settings.find_child("FpsCounterPosition", true, false) as OptionButton
	assert_true(pause_toggle.button_pressed)
	assert_eq(pause_position.get_selected_id(), PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	pause_toggle.button_pressed = false
	assert_false(counter._panel.visible, "disabling it from the pause menu takes effect immediately")
	assert_false(counter.is_processing())

func test_counter_follows_every_edge_on_window_resize_and_text_changes() -> void:
	var counter := main.get_node("FpsCounter") as FpsCounter
	PerformanceSettings.set_fps_counter_enabled(true)
	PerformanceSettings.set_fps_counter_size(PerformanceSettings.FpsCounterSize.LARGE)
	for window_size in [Vector2i(390, 844), Vector2i(844, 390), DESIGN_WINDOW]:
		await set_window(window_size)
		for position in PerformanceSettings.FpsCounterPosition.values():
			PerformanceSettings.set_fps_counter_position(position)
			counter.set_process(false)
			counter._label.text = "120 FPS"
			counter._place_counter()
			await process_frames(2)
			var rect := Rect2(counter._panel.position, counter._panel.size)
			var view := Rect2(Vector2.ZERO, counter._root.size)
			assert_true(rect_within(rect, view), "%s stays on screen at %s" % [position, window_size])
			if position in [PerformanceSettings.FpsCounterPosition.TOP_RIGHT, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT]:
				assert_almost_eq(rect.end.x, view.end.x - FpsCounter.EDGE_MARGIN, 1.0, "right edge stays pinned")
			if position in [PerformanceSettings.FpsCounterPosition.BOTTOM_LEFT, PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT]:
				assert_almost_eq(rect.end.y, view.end.y - FpsCounter.EDGE_MARGIN, 1.0, "bottom edge stays pinned")

	PerformanceSettings.set_fps_counter_position(PerformanceSettings.FpsCounterPosition.TOP_RIGHT)
	counter.set_process(false)
	counter._label.text = "9 FPS"
	counter._place_counter()
	await process_frames(2)
	var right_edge := counter._panel.position.x + counter._panel.size.x
	counter._label.text = "123456 FPS"
	counter._place_counter()
	await process_frames(2)
	assert_almost_eq(counter._panel.position.x + counter._panel.size.x, right_edge, 1.0,
		"gaining digits grows the panel leftward instead of off screen")
	get_tree().root.content_scale_factor = 1.5
	await process_frames(4)
	PerformanceSettings.set_fps_counter_position(PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT)
	counter.set_process(false)
	await process_frames(2)
	var scaled_rect := Rect2(counter._panel.position, counter._panel.size)
	var scaled_view := Rect2(Vector2.ZERO, counter._root.size)
	assert_true(rect_within(scaled_rect, scaled_view), "the readout fits when UI scale changes")
	assert_almost_eq(scaled_rect.end.x, scaled_view.end.x - FpsCounter.EDGE_MARGIN, 1.0)
	assert_almost_eq(scaled_rect.end.y, scaled_view.end.y - FpsCounter.EDGE_MARGIN, 1.0)

func test_counter_does_not_intercept_clicks_and_updates_at_zero_game_speed() -> void:
	await set_window(DESIGN_WINDOW)
	var counter := main.get_node("FpsCounter") as FpsCounter
	PerformanceSettings.set_fps_counter_refresh(PerformanceSettings.FpsCounterRefresh.FAST)
	PerformanceSettings.set_fps_counter_enabled(true)
	await process_frames(3)
	var layer := CanvasLayer.new()
	layer.layer = 19 # Immediately under the counter, above the main menu.
	add_child_autofree(layer)
	var button := Button.new()
	button.position = counter._panel.position
	button.size = counter._panel.size
	button.text = "Click"
	layer.add_child(button)
	var presses := [0]
	button.pressed.connect(func(): presses[0] += 1)
	await process_frames(2)
	await click(button)
	assert_eq(presses[0], 1, "clicks pass through every part of the readout")

	Engine.time_scale = 0.0
	counter._reset_sample(Time.get_ticks_usec())
	await get_tree().create_timer(0.45, true, false, true).timeout
	assert_ne(counter._label.text, "-- FPS", "the display keeps measuring real time while the game is paused")
	assert_gt(int(counter._label.text.trim_suffix(" FPS")), 0)

func test_counter_remains_live_on_a_course_and_through_a_pause_session() -> void:
	await set_window(DESIGN_WINDOW)
	PerformanceSettings.set_fps_counter_refresh(PerformanceSettings.FpsCounterRefresh.FAST)
	PerformanceSettings.set_fps_counter_enabled(true)
	var counter := main.get_node("FpsCounter") as FpsCounter
	await new_game("Counter course")
	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING)
	assert_true(counter._panel.visible, "starting a course does not hide the counter")
	main._show_pause_menu()
	assert_true(GameManager.is_paused)
	assert_eq(Engine.time_scale, 0.0)
	main._on_pause_settings()
	await process_frames(3)
	var settings := main.get_node("UI/HUD/SettingsMenu") as SettingsMenu
	settings._select_category(SettingsMenu.Category.DISPLAY)
	await process_frames(2)
	var toggle := settings.find_child("Toggle_show_fps_counter", true, false) as CheckButton
	assert_true(toggle.button_pressed, "the actual pause session sees the same preference")
	counter._reset_sample(Time.get_ticks_usec())
	await get_tree().create_timer(0.45, true, false, true).timeout
	assert_ne(counter._label.text, "-- FPS", "the real paused course still produces samples")
	settings._on_close()
	await process_frames(2)
	main._on_pause_resume()
	assert_false(GameManager.is_paused)
	assert_true(counter._panel.visible, "resuming leaves the readout enabled")
