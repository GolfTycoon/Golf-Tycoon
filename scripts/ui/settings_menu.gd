extends Control
class_name SettingsMenu
## SettingsMenu - responsive clubhouse settings workspace.
##
## Preferences are grouped into Audio, Display and Controls. Wide
## desktop windows use a navigation rail beside the control cards and a small
## course context panel; tablets keep the cards roomy, while phones use a
## swipeable category strip and one scrollable settings column. Every control
## keeps its original live behavior and saves changes to user://settings.cfg.

signal close_requested
## The Display category's benchmark card asks Main to open the fullscreen
## Benchmark Results screen over the settings menu.
signal results_requested

enum Category { AUDIO, DISPLAY, CONTROLS }
enum LayoutMode { DESKTOP, TABLET, LANDSCAPE, PHONE }

const DESKTOP_MIN_WIDTH := 1180.0
const DESKTOP_MIN_HEIGHT := 700.0
const TABLET_MIN_WIDTH := 680.0
const TABLET_MIN_HEIGHT := 640.0

const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_RAISED := MenuStyle.RAIL_BG
const COLOR_INSET := MenuStyle.INSET_BG
const COLOR_BORDER := UIConstants.COLOR_BORDER
const COLOR_TEXT := MenuStyle.TITLE_COLOR
const COLOR_MUTED := UIConstants.COLOR_TEXT_DIM
const COLOR_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

## Set by Main when opened from a pause session so the course camera can still
## be moved from the dimmed backdrop.
var camera: IsometricCamera = null
var close_label: String = "Done"

var _category: int = Category.AUDIO
var _layout_mode: int = LayoutMode.PHONE
var _built_size := Vector2.ZERO
var _bg: ColorRect
var _panel: Control
var _reference_course_label: Label
var _reference_day_label: Label
var _benchmark_runner: PerformanceBenchmark
var _benchmark_run_button: Button
var _benchmark_copy_button: Button
var _benchmark_status_label: Label
var _benchmark_summary_label: Label
var _benchmark_details_label: Label
var _benchmark_progress_bar: ProgressBar
var _benchmark_results_button: Button
var _benchmark_stars_row: BenchmarkVisuals.StarRow
var _benchmark_score_meter: BenchmarkVisuals.SegmentMeter
var _benchmark_running: bool = false
var _benchmark_progress: float = 0.0
var _benchmark_stars: int = 0
var _benchmark_score: float = 0.0
var _benchmark_status_text: String = "Ready to run. A test takes about seven seconds."
var _benchmark_summary_text: String = "No results yet. Run from a course view for the most useful frame-rate sample."
var _benchmark_details_text: String = "For fair comparisons, use the same save, camera view, resolution, VSync and power mode. Reports stay local unless you copy them."
var _benchmark_report_text: String = ""

func _ready() -> void:
	name = "SettingsMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_benchmark_runner = PerformanceBenchmark.new()
	_benchmark_runner.name = "PerformanceBenchmark"
	_benchmark_runner.progress_changed.connect(_on_benchmark_progress)
	_benchmark_runner.completed.connect(_on_benchmark_completed)
	add_child(_benchmark_runner)
	_adopt_last_benchmark()
	if has_node("/root/Screen") and not Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.connect(_on_screen_changed)
	_build()

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)

## Pure responsive breakpoint decision, also used by the layout tests.
static func layout_mode_for(view: Vector2) -> int:
	if view.x >= DESKTOP_MIN_WIDTH and view.y >= DESKTOP_MIN_HEIGHT and view.x > view.y:
		return LayoutMode.DESKTOP
	if view.x >= TABLET_MIN_WIDTH and view.y >= TABLET_MIN_HEIGHT:
		return LayoutMode.TABLET
	if view.x > view.y and view.y < TABLET_MIN_HEIGHT:
		return LayoutMode.LANDSCAPE
	return LayoutMode.PHONE

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

func _on_screen_changed(window_size: Vector2, _world_scale: float) -> void:
	var new_layout := layout_mode_for(window_size)
	var remeasure := absf(window_size.x - _built_size.x) > maxf(128.0, _built_size.x * 0.16) \
		or absf(window_size.y - _built_size.y) > maxf(112.0, _built_size.y * 0.16)
	if new_layout != _layout_mode or remeasure:
		_build()

func _build() -> void:
	for child in get_children():
		if child == _benchmark_runner:
			continue
		remove_child(child)
		child.queue_free()
	_bg = null
	_panel = null
	_reference_course_label = null
	_reference_day_label = null
	_benchmark_run_button = null
	_benchmark_copy_button = null
	_benchmark_status_label = null
	_benchmark_summary_label = null
	_benchmark_details_label = null
	_benchmark_progress_bar = null
	_benchmark_results_button = null
	_benchmark_stars_row = null
	_benchmark_score_meter = null
	_layout_mode = layout_mode_for(_window_size())
	_built_size = _window_size()

	_bg = ColorRect.new()
	_bg.name = "SettingsScrim"
	_bg.color = Color(0.006, 0.022, 0.016, 0.78)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	var frame := MarginContainer.new()
	frame.name = "SettingsFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var padding := _outer_padding(_layout_mode, _built_size)
	_set_margins(frame, padding)
	add_child(frame)

	var page := VBoxContainer.new()
	page.name = "SettingsPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", _page_gap(_layout_mode))
	frame.add_child(page)
	page.add_child(_build_header(_layout_mode))
	page.add_child(_build_workspace(_layout_mode, _built_size))
	page.add_child(_build_footer(_layout_mode))

func _outer_padding(mode: int, view: Vector2) -> int:
	match mode:
		LayoutMode.DESKTOP:
			return int(clampf(minf(view.x, view.y) * 0.025, 20.0, 36.0))
		LayoutMode.TABLET:
			return int(clampf(minf(view.x, view.y) * 0.022, 14.0, 26.0))
		LayoutMode.LANDSCAPE:
			return 8
		_:
			return int(clampf(view.x * 0.030, 9.0, 16.0))

func _page_gap(mode: int) -> int:
	match mode:
		LayoutMode.DESKTOP: return 13
		LayoutMode.TABLET: return 10
		LayoutMode.LANDSCAPE: return 7
		_: return 8

func _build_header(mode: int) -> Control:
	var compact := mode == LayoutMode.PHONE or mode == LayoutMode.LANDSCAPE
	var header := HBoxContainer.new()
	header.name = "SettingsHeader"
	header.custom_minimum_size.y = (44.0 if mode == LayoutMode.LANDSCAPE else 54.0) if compact else 74.0
	header.add_theme_constant_override("separation", 9 if not compact else 6)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "‹ Back" if not compact else "‹"
	back.tooltip_text = "Return to the previous screen"
	back.custom_minimum_size = Vector2(82 if not compact else 46, 44)
	back.add_theme_font_size_override("font_size", 14 if not compact else 18)
	_paint_utility_button(back)
	back.pressed.connect(_on_close)
	header.add_child(back)

	var mark := MenuFlagMark.new()
	mark.name = "SettingsMark"
	mark.mark_size = 45 if mode == LayoutMode.DESKTOP else (36 if mode == LayoutMode.TABLET else 29)
	header.add_child(mark)

	var title_box := VBoxContainer.new()
	title_box.name = "SettingsTitleBlock"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(_label("THE CLUBHOUSE OFFICE", 10 if compact else 11, COLOR_GOLD))
	var title := _label("Settings", 21 if compact else 28, COLOR_TEXT)
	title.name = "Title"
	title_box.add_child(title)
	var subtitle := _label("Make the course yours. Changes take effect immediately.", 12, COLOR_MUTED)
	subtitle.name = "Subtitle"
	subtitle.visible = not compact
	title_box.add_child(subtitle)
	header.add_child(title_box)

	var autosave_chip := _make_status_chip("SAVED AUTOMATICALLY", mode)
	autosave_chip.name = "AutosaveChip"
	autosave_chip.visible = mode == LayoutMode.DESKTOP or mode == LayoutMode.TABLET
	header.add_child(autosave_chip)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "×"
	close.tooltip_text = "Close settings"
	close.custom_minimum_size = Vector2(44, 44)
	close.add_theme_font_size_override("font_size", 22)
	_paint_utility_button(close)
	close.pressed.connect(_on_close)
	header.add_child(close)
	return header

func _build_workspace(mode: int, view: Vector2) -> Control:
	var side_navigation := _uses_side_navigation(mode, view)
	if side_navigation:
		var row := HBoxContainer.new()
		row.name = "SettingsWorkspace"
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12 if mode == LayoutMode.DESKTOP else 8)
		var nav := _build_navigation(mode, true)
		nav.custom_minimum_size.x = _navigation_width(mode, view)
		nav.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(nav)
		var content := _build_category_content(mode, view)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.size_flags_stretch_ratio = 1.0
		row.add_child(content)
		if mode == LayoutMode.DESKTOP:
			var context := _build_context_card(mode)
			context.custom_minimum_size.x = clampf(view.x * 0.17, 240.0, 292.0)
			context.size_flags_vertical = Control.SIZE_EXPAND_FILL
			row.add_child(context)
		return row

	var stack := VBoxContainer.new()
	stack.name = "SettingsWorkspace"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	stack.add_child(_build_navigation(mode, false))
	var content_panel := _build_category_content(mode, view)
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(content_panel)
	return stack

func _uses_side_navigation(mode: int, view: Vector2) -> bool:
	if mode == LayoutMode.DESKTOP or mode == LayoutMode.LANDSCAPE:
		return true
	return mode == LayoutMode.TABLET and view.x > view.y

func _navigation_width(mode: int, view: Vector2) -> float:
	if mode == LayoutMode.LANDSCAPE:
		return clampf(view.x * 0.17, 120.0, 148.0)
	if mode == LayoutMode.TABLET:
		return clampf(view.x * 0.19, 166.0, 210.0)
	return clampf(view.x * 0.15, 210.0, 252.0)

func _build_navigation(mode: int, vertical: bool) -> Control:
	if vertical:
		var surface := PanelContainer.new()
		surface.name = "CategoryNavigation"
		surface.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_RAISED,
			MenuStyle.with_alpha(COLOR_BORDER, 0.40), 14, 0, 0, 1))
		var margin := MarginContainer.new()
		_set_margins(margin, 11 if mode == LayoutMode.DESKTOP else 7)
		surface.add_child(margin)
		var stack := VBoxContainer.new()
		stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_theme_constant_override("separation", 7 if mode != LayoutMode.LANDSCAPE else 5)
		margin.add_child(stack)
		var kicker := _label("PREFERENCES", 9, COLOR_QUIET)
		kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(kicker)
		for category in Category.values():
			stack.add_child(_build_category_button(category, mode, true))
		if mode != LayoutMode.LANDSCAPE:
			var note := _label("Changes save as you make them.", 9, COLOR_QUIET)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			note.size_flags_vertical = Control.SIZE_EXPAND_FILL
			note.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			stack.add_child(note)
		return surface

	# Phones and short windows: the four categories share the width as equal
	# tiles, so none of them ever needs a sideways scroll.
	var bar := HBoxContainer.new()
	bar.name = "CategoryStrip" if mode == LayoutMode.PHONE else "CategoryNavigation"
	bar.add_theme_constant_override("separation", 5 if mode == LayoutMode.PHONE else 7)
	for category in Category.values():
		bar.add_child(_build_category_button(category, mode, false))
	return bar

func _build_category_button(category: int, mode: int, vertical: bool) -> Button:
	var button := Button.new()
	button.name = "Category_%s" % _category_key(category)
	button.toggle_mode = true
	button.button_pressed = category == _category
	button.text = _category_name(category)
	if vertical and mode != LayoutMode.LANDSCAPE:
		button.text += "\n" + _category_short_description(category)
	button.tooltip_text = _category_description(category)
	if vertical:
		button.custom_minimum_size = Vector2(0, 40 if mode == LayoutMode.LANDSCAPE else 60)
	else:
		# Horizontal tabs share the row evenly; the minimum is only a floor.
		button.custom_minimum_size = Vector2(0, 46 if mode == LayoutMode.PHONE else 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var narrow_phone := mode == LayoutMode.PHONE and _window_size().x < 400.0
	button.add_theme_font_size_override("font_size", 11 if narrow_phone else (12 if mode == LayoutMode.PHONE or mode == LayoutMode.LANDSCAPE else 13))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	MenuStyle.paint_choice(button, COLOR_MINT, 9)
	button.add_theme_color_override("font_color", COLOR_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.pressed.connect(_select_category.bind(category))
	return button

func _build_category_content(mode: int, view: Vector2) -> PanelContainer:
	var panel := _make_card(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_BORDER, 0.44), MenuStyle.CARD_RADIUS + 2)
	panel.name = "CategoryContent"
	_panel = panel
	var margin := MarginContainer.new()
	var pad := 17 if mode == LayoutMode.DESKTOP else (13 if mode == LayoutMode.TABLET else 10)
	_set_margins(margin, pad)
	panel.add_child(margin)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8 if mode == LayoutMode.LANDSCAPE else 11)
	margin.add_child(page)

	var category_header := VBoxContainer.new()
	category_header.add_theme_constant_override("separation", 2)
	category_header.add_child(_label("SETTINGS  /  %s" % _category_name(_category).to_upper(), 9 if mode == LayoutMode.PHONE else 10, COLOR_GOLD))
	var title := _label(_category_title(_category), 18 if mode == LayoutMode.PHONE else 22, COLOR_TEXT)
	title.name = "CategoryTitle"
	category_header.add_child(title)
	var description := _label(_category_description(_category), 10 if mode == LayoutMode.PHONE else 12, COLOR_MUTED)
	description.name = "CategoryDescription"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	category_header.add_child(description)
	page.add_child(category_header)

	var scroll := ScrollContainer.new()
	scroll.name = "SettingsContentScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "SettingsCardGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10 if mode == LayoutMode.DESKTOP else 8)
	grid.add_theme_constant_override("v_separation", 10 if mode == LayoutMode.DESKTOP else 8)
	grid.columns = 2 if _use_two_columns(mode, view) else 1
	scroll.add_child(grid)
	for card in _build_category_cards(mode):
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
	return panel

func _use_two_columns(mode: int, view: Vector2) -> bool:
	return mode == LayoutMode.DESKTOP or (mode == LayoutMode.TABLET and view.x > view.y)

func _build_category_cards(mode: int) -> Array[Control]:
	match _category:
		Category.AUDIO: return _build_audio_cards(mode)
		Category.DISPLAY: return _build_display_cards(mode)
		Category.CONTROLS: return _build_controls_cards(mode)
	return []

func _build_audio_cards(mode: int) -> Array[Control]:
	var cards: Array[Control] = []
	var mixer := _make_group("SOUND MIXER", "Set the balance for your clubhouse atmosphere.", mode)
	var mixer_body: VBoxContainer = mixer["body"]
	_add_volume_control(mixer_body, "Master Volume", "Overall output level", SoundManager.master_volume,
		_set_master_volume, mode)
	mixer_body.add_child(_make_separator())
	_add_volume_control(mixer_body, "Effects", "Clubhouse and course sounds", SoundManager.sfx_volume,
		_set_sfx_volume, mode)
	mixer_body.add_child(_make_separator())
	_add_volume_control(mixer_body, "Ambience", "Wind, rain and birdsong", SoundManager.ambient_volume,
		_set_ambient_volume, mode)
	cards.append(mixer["panel"])

	var output := _make_group("CLUBHOUSE AUDIO", "Mute is useful for a quiet round; your level settings are kept for next time.", mode)
	var output_body: VBoxContainer = output["body"]
	_add_toggle_row(output_body, "Mute all audio", "Silence effects and course ambience.",
		SoundManager.is_muted, _set_muted, mode)
	var badge := _make_status_chip("MUTED" if SoundManager.is_muted else "SOUND ON", mode)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	output_body.add_child(badge)
	cards.append(output["panel"])
	return cards

func _build_display_cards(mode: int) -> Array[Control]:
	var cards: Array[Control] = []
	var window := _make_group("WINDOW", "Choose how Golf Tycoon fills your screen.", mode)
	var window_body: VBoxContainer = window["body"]
	var mode_label := _label("Window mode", 12, COLOR_TEXT)
	window_body.add_child(mode_label)
	var mode_options := OptionButton.new()
	mode_options.name = "WindowMode"
	mode_options.add_item("Windowed", 0)
	mode_options.add_item("Borderless Fullscreen", 1)
	mode_options.add_item("Fullscreen", 2)
	mode_options.custom_minimum_size.y = 42
	mode_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_options.add_theme_font_size_override("font_size", 12)
	var current_mode := DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		mode_options.select(2)
	elif DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		mode_options.select(1)
	else:
		mode_options.select(0)
	mode_options.item_selected.connect(_on_window_mode_selected)
	window_body.add_child(mode_options)
	cards.append(window["panel"])

	var performance := _make_group("PERFORMANCE & SCALE", "Tune redraw timing and the size of the interface.", mode)
	var performance_body: VBoxContainer = performance["body"]
	_add_toggle_row(performance_body, "VSync", "Match the display refresh to reduce tearing.",
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED, _set_vsync, mode)
	performance_body.add_child(_make_separator())
	_add_ui_scale_control(performance_body, mode)
	cards.append(performance["panel"])

	var benchmark := _build_benchmark_card(mode)
	cards.append(benchmark)

	var accessibility := _make_group("ACCESSIBILITY", "Alternative course colours for colour-vision needs.", mode)
	var accessibility_body: VBoxContainer = accessibility["body"]
	accessibility_body.add_child(_label("Course colour palette", 12, COLOR_TEXT))
	var color_options := OptionButton.new()
	color_options.name = "ColorblindMode"
	for color_mode in ColorblindMode.get_all_modes():
		color_options.add_item(ColorblindMode.get_mode_name(color_mode), color_mode)
	color_options.custom_minimum_size.y = 42
	color_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_options.add_theme_font_size_override("font_size", 12)
	color_options.select(GameManager.colorblind_mode)
	color_options.item_selected.connect(func(index: int):
		GameManager.set_colorblind_mode(index)
		_save_display_settings())
	accessibility_body.add_child(color_options)
	cards.append(accessibility["panel"])
	return cards

func _build_benchmark_card(mode: int) -> PanelContainer:
	var benchmark := _make_group("DEVICE BENCHMARK",
		"Measure frame pacing, the GPU fill rate and a repeatable CPU workload, then open the results screen for the full scorecard.", mode)
	var body: VBoxContainer = benchmark["body"]
	body.add_child(_make_separator())

	var summary := _label(_benchmark_summary_text, 11, COLOR_TEXT)
	summary.name = "BenchmarkSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_benchmark_summary_label = summary
	body.add_child(summary)

	# The last run's rating in miniature: the five stars it earned and a
	# segmented meter for the score behind them.
	var rating := HBoxContainer.new()
	rating.name = "BenchmarkRating"
	rating.add_theme_constant_override("separation", 8)
	var stars := BenchmarkVisuals.make_star_row(_benchmark_stars, 16, "BenchmarkStars")
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_benchmark_stars_row = stars
	rating.add_child(stars)
	var meter := BenchmarkVisuals.make_meter(_benchmark_score / 100.0,
		BenchmarkVisuals.score_color(_benchmark_score), "BenchmarkScoreMeter", 12)
	meter.custom_minimum_size.y = 10
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_benchmark_score_meter = meter
	rating.add_child(meter)
	body.add_child(rating)

	var details := _label(_benchmark_details_text, 10, COLOR_MUTED)
	details.name = "BenchmarkDetails"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_benchmark_details_label = details
	body.add_child(details)

	var actions := HBoxContainer.new()
	actions.name = "BenchmarkActions"
	actions.add_theme_constant_override("separation", 7)
	var run_button := Button.new()
	run_button.name = "RunBenchmarkButton"
	run_button.tooltip_text = "Run the local test: frame pacing, the GPU fill ladder and script CPU throughput."
	run_button.custom_minimum_size = Vector2(0, 44)
	run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_button.add_theme_font_size_override("font_size", 11 if mode == LayoutMode.PHONE else 12)
	MenuStyle.paint_card(run_button, COLOR_GOLD, 0.0, 7, COLOR_TEXT, COLOR_TEXT)
	run_button.add_theme_color_override("font_color", COLOR_TEXT)
	run_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	run_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	run_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	run_button.pressed.connect(_start_benchmark)
	_benchmark_run_button = run_button
	actions.add_child(run_button)

	var results_button := Button.new()
	results_button.name = "BenchmarkResultsButton"
	results_button.text = "Full results"
	results_button.tooltip_text = "Open the Benchmark Results screen: charts, the scorecard and past runs."
	results_button.custom_minimum_size = Vector2(0, 44)
	results_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_button.add_theme_font_size_override("font_size", 11 if mode == LayoutMode.PHONE else 12)
	MenuStyle.paint_card(results_button, COLOR_MINT, 0.0, 7, COLOR_TEXT, COLOR_TEXT)
	results_button.add_theme_color_override("font_color", COLOR_TEXT)
	results_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	results_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	results_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	results_button.pressed.connect(func(): results_requested.emit())
	_benchmark_results_button = results_button
	actions.add_child(results_button)

	var copy_button := Button.new()
	copy_button.name = "CopyBenchmarkReportButton"
	copy_button.text = "Copy report"
	copy_button.tooltip_text = "Copy the device and performance report to the clipboard; it is not uploaded."
	copy_button.custom_minimum_size = Vector2(0, 44)
	copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_button.add_theme_font_size_override("font_size", 11 if mode == LayoutMode.PHONE else 12)
	MenuStyle.paint_card(copy_button, COLOR_MINT, 0.0, 7, COLOR_TEXT, COLOR_TEXT)
	copy_button.add_theme_color_override("font_color", COLOR_TEXT)
	copy_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	copy_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	copy_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	copy_button.pressed.connect(_copy_benchmark_report)
	_benchmark_copy_button = copy_button
	actions.add_child(copy_button)
	body.add_child(actions)

	var status := _label(_benchmark_status_text, 10, COLOR_QUIET)
	status.name = "BenchmarkStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_benchmark_status_label = status
	body.add_child(status)

	var progress := ProgressBar.new()
	progress.name = "BenchmarkProgress"
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = _benchmark_progress
	progress.show_percentage = false
	progress.custom_minimum_size.y = 7
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.visible = _benchmark_running
	_benchmark_progress_bar = progress
	body.add_child(progress)

	_refresh_benchmark_controls()
	return benchmark["panel"]

func _build_controls_cards(mode: int) -> Array[Control]:
	var cards: Array[Control] = []
	var camera_card := _make_group("CAMERA", "Choose the zoom direction that feels natural.", mode)
	var camera_body: VBoxContainer = camera_card["body"]
	_add_toggle_row(camera_body, "Invert Scroll Zoom", "Reverse the scroll wheel zoom direction.",
		GameManager.invert_zoom_scroll, _on_invert_zoom_toggled, mode)
	cards.append(camera_card["panel"])

	var shortcuts := _make_group("KEYBOARD SHORTCUTS", "A quick reference for the clubhouse desk.", mode)
	var shortcuts_body: VBoxContainer = shortcuts["body"]
	for binding in _keyboard_bindings():
		shortcuts_body.add_child(_build_keybinding_row(str(binding[0]), str(binding[1]), mode))
	cards.append(shortcuts["panel"])
	return cards

func _keyboard_bindings() -> Array:
	return [
		["Esc", "Pause menu"],
		["Space", "Pause / resume"],
		["F1", "Help and shortcut reference"],
		["Ctrl + S", "Quick save"],
		["Ctrl + Z", "Undo"],
		["Ctrl + Shift + Z", "Redo"],
		["H", "Open hole"],
		["T", "Place tree"],
		["B", "Place building"],
		["M", "Marketing"],
		["U", "Tournaments"],
		["Z", "Analytics"],
		["G", "Milestones"],
		["C", "Calendar"],
		["WASD", "Pan camera"],
		["Q", "Rotate camera"],
		["Scroll", "Zoom in / out"],
	]

func _make_group(title: String, description: String, mode: int) -> Dictionary:
	var panel := _make_card(COLOR_RAISED, MenuStyle.with_alpha(COLOR_BORDER, 0.32), 12)
	panel.name = "Group_%s" % title.to_lower().replace(" ", "_").replace("&", "and")
	var margin := MarginContainer.new()
	_set_margins(margin, 13 if mode == LayoutMode.DESKTOP else (11 if mode == LayoutMode.TABLET else 9))
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8 if mode == LayoutMode.LANDSCAPE else 10)
	margin.add_child(stack)
	var kicker := _label(title, 10 if mode == LayoutMode.PHONE else 11, COLOR_GOLD)
	stack.add_child(kicker)
	if not description.is_empty():
		var detail := _label(description, 10 if mode == LayoutMode.PHONE else 11, COLOR_MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(detail)
	return {"panel": panel, "body": stack}

func _add_volume_control(parent: VBoxContainer, title: String, hint: String, value: float,
		on_change: Callable, mode: int) -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	var heading := HBoxContainer.new()
	var label_box := VBoxContainer.new()
	label_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_box.add_theme_constant_override("separation", 0)
	label_box.add_child(_label(title, 12, COLOR_TEXT))
	var hint_label := _label(hint, 9 if mode == LayoutMode.PHONE else 10, COLOR_QUIET)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_box.add_child(hint_label)
	heading.add_child(label_box)
	var value_label := _label("%d%%" % int(value * 100), 11, COLOR_GOLD)
	value_label.custom_minimum_size.x = 42
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(value_label)
	stack.add_child(heading)
	var slider := HSlider.new()
	slider.name = "Volume_%s" % title.replace(" ", "")
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.y = 24
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(new_value: float):
		on_change.call(new_value)
		value_label.text = "%d%%" % int(new_value * 100))
	stack.add_child(slider)
	parent.add_child(stack)

func _add_ui_scale_control(parent: VBoxContainer, mode: int) -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	var label := _label("UI Scale", 12, COLOR_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := _label("", 11, COLOR_GOLD)
	value_label.custom_minimum_size.x = 44
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_label)
	stack.add_child(header)
	var scale_slider := HSlider.new()
	scale_slider.name = "UIScale"
	scale_slider.min_value = 0.8
	scale_slider.max_value = 1.5
	scale_slider.step = 0.1
	scale_slider.value = _load_ui_scale()
	scale_slider.custom_minimum_size.y = 25
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.text = "%d%%" % int(scale_slider.value * 100)
	scale_slider.value_changed.connect(func(value: float):
		value_label.text = "%d%%" % int(value * 100)
		get_tree().root.content_scale_factor = value
		_save_display_settings())
	stack.add_child(scale_slider)
	var range_label := _label("80%  ·  150%", 9 if mode == LayoutMode.PHONE else 10, COLOR_QUIET)
	range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(range_label)
	parent.add_child(stack)

func _add_toggle_row(parent: VBoxContainer, title: String, description: String, enabled: bool,
		on_change: Callable, mode: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	var label := _label(title, 12 if mode != LayoutMode.DESKTOP else 13, COLOR_TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(label)
	var detail := _label(description, 10 if mode == LayoutMode.PHONE else 11, COLOR_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(detail)
	row.add_child(copy)
	var toggle := CheckButton.new()
	toggle.name = "Toggle_%s" % title.to_lower().replace(" ", "_")
	toggle.button_pressed = enabled
	toggle.custom_minimum_size = Vector2(54, 42)
	toggle.tooltip_text = description
	toggle.toggled.connect(func(value: bool): on_change.call(value))
	row.add_child(toggle)
	parent.add_child(row)

func _build_keybinding_row(key: String, action: String, mode: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var keycap := PanelContainer.new()
	keycap.custom_minimum_size = Vector2(82 if mode == LayoutMode.PHONE else 112, 29)
	keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keycap.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_INSET,
		MenuStyle.with_alpha(COLOR_MINT, 0.27), 7, 6, 3, 1))
	var key_label := _label(key, 9 if mode == LayoutMode.PHONE else 10, COLOR_MINT)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keycap.add_child(key_label)
	row.add_child(keycap)
	var action_label := _label(action, 10 if mode == LayoutMode.PHONE else 11, COLOR_MUTED)
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(action_label)
	return row

func _build_context_card(mode: int) -> PanelContainer:
	var panel := _make_card(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_GOLD, 0.34), MenuStyle.CARD_RADIUS + 2)
	panel.name = "CourseContextCard"
	var margin := MarginContainer.new()
	_set_margins(margin, 16)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 9)
	margin.add_child(stack)
	stack.add_child(_label("AT A GLANCE", 10, COLOR_GOLD))
	var mark := MenuFlagMark.new()
	mark.mark_size = 70
	mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stack.add_child(mark)
	stack.add_child(_label("Your clubhouse", 19, COLOR_TEXT))
	stack.add_child(_label("Preferences are saved separately from course checkpoints, so your sound, display and controls stay yours.", 11, COLOR_MUTED))
	var separator := _make_separator()
	stack.add_child(separator)
	stack.add_child(_label("CURRENT SESSION", 9, COLOR_QUIET))
	_reference_course_label = _label("", 14, COLOR_TEXT)
	_reference_course_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_reference_course_label)
	_reference_day_label = _label("", 11, COLOR_GOLD)
	stack.add_child(_reference_day_label)
	var footer := Control.new()
	footer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(footer)
	var badge := _make_status_chip("LOCAL PREFERENCES", mode)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stack.add_child(badge)
	_update_context_copy()
	return panel

func _update_context_copy() -> void:
	if not is_instance_valid(_reference_course_label) or not is_instance_valid(_reference_day_label):
		return
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		_reference_course_label.text = "Ready for the first tee"
		_reference_day_label.text = "TITLE SCREEN"
	else:
		_reference_course_label.text = GameManager.course_name
		_reference_day_label.text = "DAY %02d" % GameManager.current_day

func _make_status_chip(text: String, mode: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_RAISED,
		MenuStyle.with_alpha(COLOR_GOLD, 0.35), 8, 8, 5, 1))
	var label := _label(text, 8 if mode == LayoutMode.PHONE else 9, COLOR_GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip

func _build_footer(mode: int) -> Control:
	var footer := HBoxContainer.new()
	footer.name = "SettingsFooter"
	footer.custom_minimum_size.y = 44 if mode == LayoutMode.LANDSCAPE else 48
	footer.add_theme_constant_override("separation", 8)
	# The notice only earns its room when the footer has the width to spare.
	var note := _label("CHANGES APPLY IMMEDIATELY  ·  SAVED ON THIS DEVICE", 10, COLOR_QUIET)
	note.name = "SaveNotice"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.visible = mode == LayoutMode.DESKTOP or mode == LayoutMode.TABLET
	footer.add_child(note)
	var done := Button.new()
	done.name = "DoneButton"
	done.text = close_label
	done.custom_minimum_size = Vector2(136 if mode != LayoutMode.PHONE else 96, 44)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL if mode == LayoutMode.PHONE else Control.SIZE_SHRINK_END
	done.add_theme_font_size_override("font_size", 12)
	MenuStyle.paint_primary(done, 9)
	done.add_theme_color_override("font_color", MenuStyle.INK)
	done.add_theme_color_override("font_hover_color", MenuStyle.INK)
	done.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	done.pressed.connect(_on_close)
	footer.add_child(done)
	return footer

func _start_benchmark() -> void:
	if _benchmark_running or not is_instance_valid(_benchmark_runner):
		return
	_benchmark_running = true
	_benchmark_progress = 0.0
	_benchmark_report_text = ""
	_benchmark_summary_text = "Running the benchmark..."
	_benchmark_details_text = "Frame pacing is measured first; the CPU workload then runs in short slices to keep the screen responsive."
	_benchmark_status_text = "Preparing benchmark..."
	var in_course := GameManager.current_mode != GameManager.GameMode.MAIN_MENU
	var context := {"scenario": "Paused course view" if in_course else "Main menu"}
	if in_course:
		context["day"] = GameManager.current_day
	if not _benchmark_runner.start(context):
		_benchmark_running = false
		_benchmark_status_text = "The benchmark is already running."
	_refresh_benchmark_controls()

func _on_benchmark_progress(message: String, fraction: float) -> void:
	_benchmark_running = true
	_benchmark_status_text = message
	_benchmark_progress = fraction
	_refresh_benchmark_controls()

## Pick up a run another screen finished (the results screen runs the same
## benchmark), so the card opens showing the newest report on this machine.
func _adopt_last_benchmark() -> void:
	var result := PerformanceBenchmark.last_result
	if result.is_empty():
		return
	_benchmark_report_text = str(result.get("report_text", ""))
	_benchmark_summary_text = _benchmark_summary_for(result)
	_benchmark_details_text = _benchmark_details_for(result)
	_benchmark_status_text = "Complete. Copy the report to compare devices; nothing is uploaded."
	_apply_benchmark_score(result)

func _apply_benchmark_score(result: Dictionary) -> void:
	var score: Dictionary = result.get("score", PerformanceBenchmark.score_result(result))
	_benchmark_stars = int(score.get("stars", 0))
	_benchmark_score = float(score.get("overall", 0.0))

## The card's headline: the tier and the score first, then the frame pacing.
func _benchmark_summary_for(result: Dictionary) -> String:
	var score: Dictionary = result.get("score", PerformanceBenchmark.score_result(result))
	var frame: Dictionary = result.get("frame", {})
	if int(frame.get("sample_count", 0)) <= 0:
		return PerformanceBenchmark.format_summary(result)
	return "%s · %d/100 · avg %.1f FPS · 1%% low %.1f FPS" % [
		str(score.get("tier", "Unrated")), int(round(float(score.get("overall", 0.0)))),
		float(frame.get("average_fps", 0.0)), float(frame.get("one_percent_low_fps", 0.0)),
	]

## The card's second line: what the run pointed at, GPU included.
func _benchmark_details_for(result: Dictionary) -> String:
	var frame: Dictionary = result.get("frame", {})
	var engine: Dictionary = result.get("engine", {})
	var gpu: Dictionary = result.get("gpu", {})
	if int(frame.get("sample_count", 0)) <= 0:
		return "No frame samples were captured. Run again with the settings screen visible for a full frame-pacing sample."
	var gpu_text := "GPU %.0f MPix/s" % float(gpu.get("peak_megapixels_per_second", 0.0)) \
		if bool(gpu.get("available", false)) else "GPU test skipped"
	return "Frame p95 %.1f ms · game process %.1f ms/frame · %s. Open the full results for the scorecard and past runs." % [
		float(frame.get("p95_frame_ms", 0.0)), float(engine.get("process_ms_per_frame", 0.0)),
		gpu_text,
	]

func _on_benchmark_completed(result: Dictionary) -> void:
	_benchmark_running = false
	_benchmark_progress = 1.0
	_benchmark_report_text = str(result.get("report_text", ""))
	_benchmark_summary_text = _benchmark_summary_for(result)
	_apply_benchmark_score(result)
	_benchmark_details_text = _benchmark_details_for(result)
	_benchmark_status_text = "Complete. Copy the report to compare devices; nothing is uploaded."
	_refresh_benchmark_controls()

func _copy_benchmark_report() -> void:
	if _benchmark_report_text.is_empty() or _benchmark_running:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_benchmark_status_text = "This window has no clipboard to copy into. The report stays on this machine."
		_refresh_benchmark_controls()
		return
	DisplayServer.clipboard_set(_benchmark_report_text)
	_benchmark_status_text = "Report copied. It includes device and hardware details; nothing was uploaded."
	_refresh_benchmark_controls()

func _refresh_benchmark_controls() -> void:
	if is_instance_valid(_benchmark_run_button):
		_benchmark_run_button.text = "Running..." if _benchmark_running \
			else ("Run again" if not _benchmark_report_text.is_empty() else "Run benchmark")
		_benchmark_run_button.disabled = _benchmark_running
	if is_instance_valid(_benchmark_copy_button):
		_benchmark_copy_button.disabled = _benchmark_running or _benchmark_report_text.is_empty()
	if is_instance_valid(_benchmark_status_label):
		_benchmark_status_label.text = _benchmark_status_text
	if is_instance_valid(_benchmark_summary_label):
		_benchmark_summary_label.text = _benchmark_summary_text
	if is_instance_valid(_benchmark_details_label):
		_benchmark_details_label.text = _benchmark_details_text
	if is_instance_valid(_benchmark_progress_bar):
		_benchmark_progress_bar.value = _benchmark_progress
		_benchmark_progress_bar.visible = _benchmark_running
	if is_instance_valid(_benchmark_stars_row):
		_benchmark_stars_row.set_stars(_benchmark_stars)
	if is_instance_valid(_benchmark_score_meter):
		_benchmark_score_meter.set_fraction(_benchmark_score / 100.0,
			BenchmarkVisuals.score_color(_benchmark_score))

func _select_category(category: int) -> void:
	if category == _category:
		return
	_category = category
	_build()

func _on_window_mode_selected(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_save_display_settings()

func _set_master_volume(value: float) -> void:
	SoundManager.set_master_volume(value)

func _set_sfx_volume(value: float) -> void:
	SoundManager.sfx_volume = clampf(value, 0.0, 1.0)
	SoundManager._save_settings()

func _set_ambient_volume(value: float) -> void:
	SoundManager.ambient_volume = clampf(value, 0.0, 1.0)
	SoundManager._update_ambient_volumes()
	SoundManager._save_settings()

func _set_muted(value: bool) -> void:
	SoundManager.set_muted(value)

func _set_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	_save_display_settings()

func _on_invert_zoom_toggled(enabled: bool) -> void:
	GameManager.invert_zoom_scroll = enabled
	_save_controls_settings()

func _load_ui_scale() -> float:
	var config := ConfigFile.new()
	if config.load(SaveManager.SETTINGS_PATH) == OK:
		return clampf(float(config.get_value("display", "ui_scale", 1.0)), 0.8, 1.5)
	return 1.0

func _save_controls_settings() -> void:
	var config := ConfigFile.new()
	config.load(SaveManager.SETTINGS_PATH)
	config.set_value("controls", "invert_zoom_scroll", GameManager.invert_zoom_scroll)
	config.save(SaveManager.SETTINGS_PATH)

func _save_display_settings() -> void:
	var config := ConfigFile.new()
	config.load(SaveManager.SETTINGS_PATH)
	config.set_value("display", "window_mode", DisplayServer.window_get_mode())
	config.set_value("display", "borderless", DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS))
	config.set_value("display", "vsync", DisplayServer.window_get_vsync_mode())
	config.set_value("display", "ui_scale", get_tree().root.content_scale_factor)
	config.set_value("display", "colorblind_mode", ColorblindMode.to_string_name(GameManager.colorblind_mode))
	config.save(SaveManager.SETTINGS_PATH)

func _category_key(category: int) -> String:
	return ["audio", "display", "controls"][category]

func _category_name(category: int) -> String:
	return ["Audio", "Display", "Controls"][category]

func _category_title(category: int) -> String:
	return ["Sound & ambience", "Screen & accessibility", "Course preferences", "Your controls"][category]

func _category_short_description(category: int) -> String:
	return ["Mixer", "Screen", "Course", "Keys"][category]

func _category_description(category: int) -> String:
	return [
		"Balance the master, effects and ambient volume for the course.",
		"Adjust how the game looks and feels on this display.",
		"Choose the tee-box options used when creating holes.",
		"Tune camera zoom and check the keyboard shortcuts.",
	][category]

func _make_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_color_override("color", MenuStyle.with_alpha(COLOR_BORDER, 0.5))
	return separator

func _make_card(bg: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(bg, border, radius, 0, 0, 1))
	return panel

func _set_margins(container: MarginContainer, margin: int) -> void:
	for side in ["left", "right", "top", "bottom"]:
		container.add_theme_constant_override("margin_" + side, margin)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _paint_utility_button(button: Button) -> void:
	MenuStyle.paint_card(button, COLOR_MINT, 0.0, 8, COLOR_TEXT, COLOR_TEXT)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _on_close() -> void:
	close_requested.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
		return
	if camera != null and _is_camera_event(event):
		camera.handle_input_event(event, true)

func _is_camera_event(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		return _hover_is_backdrop()
	if event is InputEventMouseMotion:
		return camera.is_dragging() or _hover_is_backdrop()
	if event is InputEventMouseButton:
		if camera.is_dragging():
			return true
		if not _hover_is_backdrop():
			return false
		return event.button_index == MOUSE_BUTTON_MIDDLE \
			or event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	return false

func _hover_is_backdrop() -> bool:
	var hovered := _get_hovered_control()
	return hovered == null or not _is_interactive_control(hovered)

func _get_hovered_control() -> Control:
	return get_viewport().gui_get_hovered_control()

func _is_interactive_control(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		if node is Button or node is LineEdit or node is Range or node is ScrollContainer:
			return true
		node = node.get_parent()
	return false
