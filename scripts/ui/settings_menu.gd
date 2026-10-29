extends Control
class_name SettingsMenu
const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")
## SettingsMenu - responsive clubhouse settings workspace.
##
## Preferences are grouped into Audio, Display and Controls. Wide
## desktop windows use a navigation rail beside the control cards; tablets
## keep the cards roomy, while phones use a swipeable category strip and one
## scrollable settings column. Every control keeps its original live behavior
## and saves changes to user://settings.cfg.

signal close_requested
## The Display category's benchmark card asks Main to open the fullscreen
## Benchmark Results screen over the settings menu: the last run's report
## and the shelf of past runs behind it.
signal results_requested
## ...or to close the menus and run the course benchmark tour - the game's
## only benchmark - which prepares its own throwaway course (Main owns the
## tour runner). Only emitted when this menu was opened from the Main Menu -
## benchmarks run from the title screen only, never over a game in
## progress.
signal tour_requested(suite_id: String)

## Where this menu was opened from. Main sets it before adding the menu:
## MAIN_MENU from the title screen, PAUSE_MENU from an in-game pause
## session. It decides whether the benchmarks may run (see
## benchmarks_allowed): measuring is a title-screen job, so a paused game
## is never borrowed, paused mid-frame, as the test scene.
enum Origin { MAIN_MENU, PAUSE_MENU }

enum Category { AUDIO, DISPLAY, CONTROLS }

const DESKTOP_MIN_WIDTH := MenuScreenKit.DESKTOP_MIN_WIDTH
const DESKTOP_MIN_HEIGHT := MenuScreenKit.DESKTOP_MIN_HEIGHT
const TABLET_MIN_WIDTH := MenuScreenKit.TABLET_MIN_WIDTH
const TABLET_MIN_HEIGHT := MenuScreenKit.TABLET_MIN_HEIGHT

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

## Set by Main before the menu is added (see Origin). The default treats a
## host that does not say - a test harness adding the menu directly - as
## the title screen; Main always sets it in the game.
var origin: int = Origin.MAIN_MENU

## Why the run button stands down away from the Main Menu, worded once for
## the card, the tooltip and the refused-run message.
const BENCHMARK_GATE_TEXT := "Benchmarks run from the Main Menu - open Settings there to measure this device. Nothing here touches the game in progress."

## What the one benchmark does, for the card that offers it.
const BENCHMARK_TOUR_TEXT := "Prepare a throwaway course, then build and play every fixed test course on it - preparing each one, course types, hole counts, terrain, buildings, golfers, camera moves, editing and game speeds - and measure each part. About 95 seconds; Esc cancels it."
## What the card says once a run has landed on the shelf.
const BENCHMARK_DONE_TEXT := "Complete. Open Past Results for the full report and the runs behind it; reports stay on this machine."

## The course tour - the game's only benchmark - runs only when this menu
## was accessed from the Main Menu screen. Reading the last run and the
## past results is not running one, and stays available wherever Settings
## was opened from.
func benchmarks_allowed() -> bool:
	return origin == Origin.MAIN_MENU

var _category: int = Category.AUDIO
var _layout_mode: int = Kit.LayoutMode.PHONE_PORTRAIT
var _built_size := Vector2.ZERO
var _bg: ColorRect
var _panel: Control
var _benchmark_run_button: Button
var _benchmark_status_label: Label
var _benchmark_summary_label: Label
var _benchmark_details_label: Label
var _benchmark_results_button: Button
var _benchmark_stars_row: BenchmarkVisuals.StarRow
var _benchmark_score_meter: BenchmarkVisuals.SegmentMeter
var _benchmark_stars: int = 0
var _benchmark_score: float = 0.0
var _benchmark_status_text: String = "Ready. The tour prepares its own course and builds every test course on screen - about 95 seconds. Esc cancels it."
var _benchmark_summary_text: String = "No results yet. Every run builds the same fixed test courses - every course type, hole count and game speed - so runs compare on any device."
var _benchmark_details_text: String = "The tour prepares a throwaway course from here and takes it down afterwards; no game is opened or written. Reports stay on this machine."
## Camera zoom limit controls (Controls → Camera). Rebuilt with the page so
## references are cleared each build.
var _min_zoom_slider: HSlider = null
var _max_zoom_slider: HSlider = null
var _min_zoom_value_label: Label = null
var _max_zoom_value_label: Label = null
var _minimap_toggle: CheckButton = null
## The Controls page's editable keycaps and their reset buttons, keyed by
## InputBindings action. They are rebuilt with the page; the signal handlers
## refresh their captions in place instead of rebuilding the page, so focus
## and scroll position survive a rebind.
var _binding_buttons: Dictionary = {}
var _binding_reset_buttons: Dictionary = {}
var _controls_status_label: Label = null
var _reset_all_controls_button: Button = null
## The action whose row is listening for the next key, or "" when none is.
var _capturing_action: String = ""
var _controls_status_text: String = "Click a binding, then press a key or controller button. Esc cancels; Backspace unbinds."

func _ready() -> void:
	name = "SettingsMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_adopt_last_benchmark()
	if not benchmarks_allowed():
		_benchmark_status_text = BENCHMARK_GATE_TEXT
	if has_node("/root/Screen") and not Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.connect(_on_screen_changed)
	_build()

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)
	if not InputBindings.bindings_changed.is_connected(_on_binding_changed):
		InputBindings.bindings_changed.connect(_on_binding_changed)
	if not InputBindings.bindings_reset.is_connected(_on_bindings_reset):
		InputBindings.bindings_reset.connect(_on_bindings_reset)
	if EventBus.has_signal("minimap_enabled_changed") and not EventBus.minimap_enabled_changed.is_connected(_on_minimap_enabled_changed):
		EventBus.minimap_enabled_changed.connect(_on_minimap_enabled_changed)

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)
	if InputBindings.bindings_changed.is_connected(_on_binding_changed):
		InputBindings.bindings_changed.disconnect(_on_binding_changed)
	if InputBindings.bindings_reset.is_connected(_on_bindings_reset):
		InputBindings.bindings_reset.disconnect(_on_bindings_reset)
	if EventBus.has_signal("minimap_enabled_changed") and EventBus.minimap_enabled_changed.is_connected(_on_minimap_enabled_changed):
		EventBus.minimap_enabled_changed.disconnect(_on_minimap_enabled_changed)

## Pure responsive breakpoint decision, also used by the layout tests.
static func layout_mode_for(view: Vector2) -> int:
	return Kit.layout_mode_for(view)

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
		remove_child(child)
		child.queue_free()
	_bg = null
	_panel = null
	_benchmark_run_button = null
	_benchmark_status_label = null
	_benchmark_summary_label = null
	_benchmark_details_label = null
	_benchmark_results_button = null
	_benchmark_stars_row = null
	_benchmark_score_meter = null
	_binding_buttons.clear()
	_binding_reset_buttons.clear()
	_controls_status_label = null
	_reset_all_controls_button = null
	_capturing_action = ""
	_min_zoom_slider = null
	_max_zoom_slider = null
	_min_zoom_value_label = null
	_max_zoom_value_label = null
	_minimap_toggle = null
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
		Kit.LayoutMode.DESKTOP:
			return int(clampf(minf(view.x, view.y) * 0.025, 20.0, 36.0))
		Kit.LayoutMode.TABLET_LANDSCAPE:
			return int(clampf(minf(view.x, view.y) * 0.022, 14.0, 26.0))
		Kit.LayoutMode.PHONE_LANDSCAPE:
			return 8
		_:
			return int(clampf(view.x * 0.030, 9.0, 16.0))

func _page_gap(mode: int) -> int:
	match mode:
		Kit.LayoutMode.DESKTOP: return 13
		Kit.LayoutMode.TABLET_LANDSCAPE: return 10
		Kit.LayoutMode.PHONE_LANDSCAPE: return 7
		_: return 8

func _build_header(mode: int) -> Control:
	var trailing: Control = null
	if mode == Kit.LayoutMode.DESKTOP or Kit.is_tablet(mode):
		trailing = Kit.make_chip("SAVED AUTOMATICALLY", COLOR_GOLD, COLOR_GOLD, 10)
		trailing.custom_minimum_size = Vector2(0.0, 26.0)
	var header := Kit.make_screen_header(mode, "Settings", "The clubhouse office",
		"Make the course yours. Changes take effect immediately.", _on_close, trailing)
	return header

func _build_workspace(mode: int, view: Vector2) -> Control:
	var side_navigation := _uses_side_navigation(mode, view)
	if side_navigation:
		var row := HBoxContainer.new()
		row.name = "SettingsWorkspace"
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12 if mode == Kit.LayoutMode.DESKTOP else 8)
		var nav := _build_navigation(mode, true)
		nav.custom_minimum_size.x = _navigation_width(mode, view)
		nav.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(nav)
		var content := _build_category_content(mode, view)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.size_flags_stretch_ratio = 1.0
		row.add_child(content)
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
	if mode == Kit.LayoutMode.DESKTOP or mode == Kit.LayoutMode.PHONE_LANDSCAPE:
		return true
	return Kit.is_tablet(mode) and view.x > view.y

func _navigation_width(mode: int, view: Vector2) -> float:
	if mode == Kit.LayoutMode.PHONE_LANDSCAPE:
		return clampf(view.x * 0.17, 120.0, 148.0)
	if Kit.is_tablet(mode):
		return clampf(view.x * 0.19, 166.0, 210.0)
	return clampf(view.x * 0.15, 210.0, 252.0)

func _build_navigation(mode: int, vertical: bool) -> Control:
	if vertical:
		var surface := PanelContainer.new()
		surface.name = "CategoryNavigation"
		surface.add_theme_stylebox_override("panel", MenuStyle.panel(COLOR_RAISED,
			MenuStyle.with_alpha(COLOR_BORDER, 0.40), 14, 0, 0, 1))
		var margin := MarginContainer.new()
		_set_margins(margin, 11 if mode == Kit.LayoutMode.DESKTOP else 7)
		surface.add_child(margin)
		var stack := VBoxContainer.new()
		stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_theme_constant_override("separation", 7 if mode != Kit.LayoutMode.PHONE_LANDSCAPE else 5)
		margin.add_child(stack)
		var kicker := Kit.make_label("PREFERENCES", 9, COLOR_QUIET)
		kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(kicker)
		for category in Category.values():
			stack.add_child(_build_category_button(category, mode, true))
		if mode != Kit.LayoutMode.PHONE_LANDSCAPE:
			var note := Kit.make_label("Changes save as you make them.", 9, COLOR_QUIET)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			note.size_flags_vertical = Control.SIZE_EXPAND_FILL
			note.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			stack.add_child(note)
		return surface

	# Phones and short windows: the four categories share the width as equal
	# tiles, so none of them ever needs a sideways scroll.
	var bar := HBoxContainer.new()
	bar.name = "CategoryStrip" if mode == Kit.LayoutMode.PHONE_PORTRAIT else "CategoryNavigation"
	bar.add_theme_constant_override("separation", 5 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 7)
	for category in Category.values():
		bar.add_child(_build_category_button(category, mode, false))
	return bar

func _build_category_button(category: int, mode: int, vertical: bool) -> Button:
	var button := Button.new()
	button.name = "Category_%s" % _category_key(category)
	button.toggle_mode = true
	button.button_pressed = category == _category
	button.text = _category_name(category)
	if vertical and mode != Kit.LayoutMode.PHONE_LANDSCAPE:
		button.text += "\n" + _category_short_description(category)
	button.tooltip_text = _category_description(category)
	if vertical:
		button.custom_minimum_size = Vector2(0, 40 if mode == Kit.LayoutMode.PHONE_LANDSCAPE else 60)
	else:
		# Horizontal tabs share the row evenly; the minimum is only a floor.
		button.custom_minimum_size = Vector2(0, 46 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var narrow_phone := mode == Kit.LayoutMode.PHONE_PORTRAIT and _window_size().x < 400.0
	button.add_theme_font_size_override("font_size", 11 if narrow_phone else (12 if Kit.is_phone(mode) else 13))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	MenuStyle.paint_choice(button, COLOR_MINT, 9)
	button.add_theme_color_override("font_color", COLOR_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.pressed.connect(_select_category.bind(category))
	return button

func _build_category_content(mode: int, view: Vector2) -> PanelContainer:
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_BORDER, 0.44))
	panel.name = "CategoryContent"
	_panel = panel
	var margin := MarginContainer.new()
	var pad := 17 if mode == Kit.LayoutMode.DESKTOP else (13 if Kit.is_tablet(mode) else 10)
	_set_margins(margin, pad)
	panel.add_child(margin)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8 if mode == Kit.LayoutMode.PHONE_LANDSCAPE else 11)
	margin.add_child(page)

	var category_header := VBoxContainer.new()
	category_header.add_theme_constant_override("separation", 2)
	category_header.add_child(Kit.make_label("SETTINGS  /  %s" % _category_name(_category).to_upper(), 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_GOLD))
	var title := Kit.make_label(_category_title(_category), 18 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 22, COLOR_TEXT)
	title.name = "CategoryTitle"
	category_header.add_child(title)
	var description := Kit.make_label(_category_description(_category), 10 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 12, COLOR_MUTED)
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
	grid.add_theme_constant_override("h_separation", 10 if mode == Kit.LayoutMode.DESKTOP else 8)
	grid.add_theme_constant_override("v_separation", 10 if mode == Kit.LayoutMode.DESKTOP else 8)
	grid.columns = 2 if _use_two_columns(mode, view) else 1
	scroll.add_child(grid)
	for card in _build_category_cards(mode):
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
	return panel

func _use_two_columns(mode: int, view: Vector2) -> bool:
	return mode == Kit.LayoutMode.DESKTOP or (Kit.is_tablet(mode) and view.x > view.y)

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
	var badge := Kit.make_chip("MUTED" if SoundManager.is_muted else "SOUND ON", COLOR_GOLD, COLOR_GOLD, 9)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	output_body.add_child(badge)
	cards.append(output["panel"])
	return cards

func _build_display_cards(mode: int) -> Array[Control]:
	var cards: Array[Control] = []
	var window := _make_group("WINDOW", "Choose how Golf Tycoon fills your screen.", mode)
	var window_body: VBoxContainer = window["body"]
	var mode_label := Kit.make_label("Window mode", 12, COLOR_TEXT)
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

	var hud := _make_group("COURSE HUD", "Choose which overlays stay on the course screen.", mode)
	var hud_body: VBoxContainer = hud["body"]
	_minimap_toggle = _add_toggle_row(hud_body, "Minimap",
		"Show the course overview map in the bottom-left corner.",
		GameManager.minimap_enabled, _set_minimap_enabled, mode)
	cards.append(hud["panel"])

	var accessibility := _make_group("ACCESSIBILITY", "Alternative course colours for colour-vision needs.", mode)
	var accessibility_body: VBoxContainer = accessibility["body"]
	accessibility_body.add_child(Kit.make_label("Course colour palette", 12, COLOR_TEXT))
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

	var benchmark := _build_benchmark_card(mode)
	cards.append(benchmark)
	return cards

## The one card the game's only benchmark gets: what the tour does, the
## rating the last run earned, and two buttons - Run Benchmark, which hands
## the screen to the tour, and Past Results, which opens the full report and
## the shelf of runs behind it.
func _build_benchmark_card(mode: int) -> PanelContainer:
	var card_text := BENCHMARK_TOUR_TEXT \
		if benchmarks_allowed() else BENCHMARK_GATE_TEXT + " The last run and the past results still show here."
	var benchmark := _make_group("BENCHMARK", card_text, mode)
	var body: VBoxContainer = benchmark["body"]
	body.add_child(_make_separator())

	var summary := Kit.make_label(_benchmark_summary_text, 11, COLOR_TEXT)
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

	var details := Kit.make_label(_benchmark_details_text, 10, COLOR_MUTED)
	details.name = "BenchmarkDetails"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_benchmark_details_label = details
	body.add_child(details)

	var actions := HBoxContainer.new()
	actions.name = "BenchmarkActions"
	actions.add_theme_constant_override("separation", 7)

	var run_button := Button.new()
	run_button.name = "RunBenchmarkButton"
	run_button.text = "Run Benchmark"
	run_button.tooltip_text = ("Close the menus and watch the benchmark prepare, build and play every test course (about 95 seconds). Esc cancels it and the throwaway course is taken down afterwards." \
		if benchmarks_allowed() else BENCHMARK_GATE_TEXT)
	run_button.custom_minimum_size = Vector2(0, 44)
	run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_button.size_flags_stretch_ratio = 1.4
	run_button.add_theme_font_size_override("font_size", 11 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 12)
	MenuStyle.paint_card(run_button, COLOR_GOLD, 0.0, 7, COLOR_TEXT, COLOR_TEXT)
	run_button.add_theme_color_override("font_color", COLOR_TEXT)
	run_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	run_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	run_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	run_button.pressed.connect(_request_tour)
	_benchmark_run_button = run_button
	actions.add_child(run_button)

	var results_button := Button.new()
	results_button.name = "PastResultsButton"
	results_button.text = "Past Results"
	results_button.tooltip_text = "Open the Benchmark Results screen: the last report, the scorecard and the runs kept on this machine."
	results_button.custom_minimum_size = Vector2(0, 44)
	results_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_button.add_theme_font_size_override("font_size", 11 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 12)
	MenuStyle.paint_card(results_button, COLOR_MINT, 0.0, 7, COLOR_TEXT, COLOR_TEXT)
	results_button.add_theme_color_override("font_color", COLOR_TEXT)
	results_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	results_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	results_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	results_button.pressed.connect(func(): results_requested.emit())
	_benchmark_results_button = results_button
	actions.add_child(results_button)
	body.add_child(actions)

	var status := Kit.make_label(_benchmark_status_text, 10, COLOR_QUIET)
	status.name = "BenchmarkStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_benchmark_status_label = status
	body.add_child(status)

	_refresh_benchmark_controls()
	return benchmark["panel"]

## The Controls page: one editable keycap per rebindable action, grouped the
## way InputBindings groups them, plus the camera's own invert-zoom toggle
## and the zoom-limit sliders. Changes apply live and save at once; the intro
## card carries the listening hint, the result message and Reset All.
func _build_controls_cards(mode: int) -> Array[Control]:
	var cards: Array[Control] = []
	cards.append(_build_controls_intro_card(mode))
	for group in InputBindings.groups():
		var group_id := str(group.get("id", ""))
		var group_card := _make_group(str(group.get("title", group_id)).to_upper(),
			str(group.get("description", "")), mode)
		var body: VBoxContainer = group_card["body"]
		if group_id == "camera":
			_add_toggle_row(body, "Invert Scroll Zoom", "Reverse the scroll wheel zoom direction.",
				GameManager.invert_zoom_scroll, _on_invert_zoom_toggled, mode)
			body.add_child(_make_separator())
			_add_camera_zoom_controls(body, mode)
			body.add_child(_make_separator())
		for action in InputBindings.actions_in_group(group_id):
			body.add_child(_build_binding_row(action, mode))
		cards.append(group_card["panel"])
	return cards

func _build_controls_intro_card(mode: int) -> Control:
	var intro := _make_group("EDIT CONTROLS",
		"Every course action can be rebound to the key or controller button that suits you.", mode)
	var body: VBoxContainer = intro["body"]

	var status := Kit.make_label(_controls_status_text, 10 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 11, COLOR_MINT)
	status.name = "ControlsStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_status_label = status
	body.add_child(status)

	var note := Kit.make_label("Click a keycap to listen. Esc cancels, Backspace unbinds, and the arrow button resets one control. Mouse, touch and the menu keys (Esc, Tab, Enter and the arrows) stay fixed.",
		9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_QUIET)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	body.add_child(_make_separator())

	var reset_all := Button.new()
	reset_all.name = "ResetAllControlsButton"
	reset_all.text = "Reset All Controls"
	reset_all.tooltip_text = "Put every course control back on its default key or button. Changes save as you make them."
	reset_all.custom_minimum_size = Vector2(0, 44)
	reset_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_all.add_theme_font_size_override("font_size", 11 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 12)
	MenuStyle.paint_card(reset_all, COLOR_GOLD, 0.0, 8, COLOR_TEXT, COLOR_TEXT)
	reset_all.add_theme_color_override("font_color", COLOR_TEXT)
	reset_all.add_theme_color_override("font_hover_color", COLOR_TEXT)
	reset_all.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	reset_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset_all.disabled = not InputBindings.has_custom_bindings()
	reset_all.pressed.connect(_reset_all_controls)
	_reset_all_controls_button = reset_all
	body.add_child(reset_all)
	return intro["panel"]

## One action's row: what it does, its current keycap and a per-action reset.
func _build_binding_row(action: String, mode: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "BindingRow_%s" % action
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 7)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation", 0)
	var action_label := Kit.make_label(InputBindings.action_label(action), 11 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 12, COLOR_TEXT)
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(action_label)
	var hint := InputBindings.action_hint(action)
	if not hint.is_empty():
		var hint_label := Kit.make_label(hint, 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_QUIET)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_child(hint_label)
	row.add_child(copy)

	var keycap := Button.new()
	keycap.name = "Binding_%s" % action
	keycap.text = InputBindings.binding_text(action)
	_update_keycap_tooltip(action, keycap)
	keycap.custom_minimum_size = Vector2(98 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 130, 44)
	keycap.add_theme_font_size_override("font_size", 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10)
	keycap.clip_text = true
	keycap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	keycap.focus_mode = Control.FOCUS_ALL
	keycap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_paint_keycap(keycap, false)
	keycap.pressed.connect(_begin_rebinding.bind(action))
	_binding_buttons[action] = keycap
	row.add_child(keycap)

	var reset := Button.new()
	reset.name = "Reset_%s" % action
	reset.text = "↺"
	reset.tooltip_text = "Reset %s to its default (%s)." % [
		InputBindings.action_label(action), InputBindings.default_binding_text(action)]
	reset.custom_minimum_size = Vector2(40, 44)
	reset.add_theme_font_size_override("font_size", 16)
	reset.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Kit.paint_utility_button(reset, false)
	reset.disabled = not InputBindings.is_customized(action)
	reset.pressed.connect(_reset_one_binding.bind(action))
	_binding_reset_buttons[action] = reset
	row.add_child(reset)
	return row

func _paint_keycap(button: Button, listening: bool) -> void:
	var accent := COLOR_GOLD if listening else COLOR_MINT
	MenuStyle.paint_card(button, accent, 0.0, 6, accent, COLOR_TEXT)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", accent)

## Start listening on one row. Clicking the keycap again, clicking elsewhere,
## Escape or B leaves the binding as it was.
func _begin_rebinding(action: String) -> void:
	if not InputBindings.has_action(action):
		return
	if not _capturing_action.is_empty():
		_restore_binding_button(_capturing_action)
	_capturing_action = action
	var button := _binding_buttons.get(action) as Button
	if is_instance_valid(button):
		button.text = "Press a key…"
		_paint_keycap(button, true)
	_set_controls_status("Listening for %s. Press a key or controller button; Esc cancels, Backspace unbinds." % InputBindings.action_label(action))

func _restore_binding_button(action: String) -> void:
	var button := _binding_buttons.get(action) as Button
	if is_instance_valid(button):
		button.text = InputBindings.binding_text(action)
		_update_keycap_tooltip(action, button)
		_paint_keycap(button, false)

func _update_keycap_tooltip(action: String, button: Button) -> void:
	button.tooltip_text = "%s: %s. Click, then press a key or controller button." % [
		InputBindings.action_label(action), InputBindings.binding_text(action)]

## Returns true when the event belonged to the capture and must not reach the
## rest of the screen. A mouse press cancels the capture but is passed on, so
## clicking another keycap starts on that row.
func _handle_capture(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return true
		if key.keycode == KEY_ESCAPE:
			_finish_capture("Binding unchanged.")
			return true
		if key.keycode == KEY_BACKSPACE or key.keycode == KEY_DELETE:
			_unbind_captured_action()
			return true
		if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]:
			return true
		_apply_captured_event(event)
		return true
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return true
		if button.button_index == JOY_BUTTON_B:
			_finish_capture("Binding unchanged.")
			return true
		_apply_captured_event(event)
		return true
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < InputBindings.JOY_MOTION_CAPTURE_THRESHOLD:
			return false
		_apply_captured_event(event)
		return true
	if event is InputEventMouseButton and event.pressed:
		_finish_capture("Binding unchanged.")
		return false
	return false

func _apply_captured_event(event: InputEvent) -> void:
	if _capturing_action.is_empty():
		return
	var action := _capturing_action
	var label := InputBindings.action_label(action)
	var result := InputBindings.assign_binding(action, event)
	if not bool(result.get("ok", false)):
		# A reserved key keeps the row listening so the player can try again.
		_set_controls_status(str(result.get("message", "That cannot be bound.")))
		return
	if bool(result.get("unchanged", false)):
		_finish_capture("%s is already bound to %s." % [label, InputBindings.binding_text(action)])
		return
	var message := "Bound %s to %s." % [label, InputBindings.binding_text(action)]
	var conflicts: Array = result.get("conflicts", [])
	if not conflicts.is_empty():
		var names: Array[String] = []
		for other in conflicts:
			names.append(InputBindings.action_label(str(other)))
		if bool(result.get("swapped", false)):
			message += " %s took over the key it replaced." % ", ".join(names)
		else:
			message += " Removed it from %s." % ", ".join(names)
	_finish_capture(message)

func _unbind_captured_action() -> void:
	if _capturing_action.is_empty():
		return
	var action := _capturing_action
	var label := InputBindings.action_label(action)
	InputBindings.clear_binding(action)
	_finish_capture("%s is unbound. ↺ restores its default (%s)." % [
		label, InputBindings.default_binding_text(action)])

func _finish_capture(message: String) -> void:
	var action := _capturing_action
	_capturing_action = ""
	_restore_binding_button(action)
	_refresh_binding_rows()
	_set_controls_status(message)
	var button := _binding_buttons.get(action) as Button
	if is_instance_valid(button):
		button.grab_focus()

func _reset_one_binding(action: String) -> void:
	if not _capturing_action.is_empty():
		_finish_capture("")
	InputBindings.reset_binding(action)
	_refresh_binding_rows()
	_set_controls_status("%s is back on its default (%s)." % [
		InputBindings.action_label(action), InputBindings.default_binding_text(action)])

func _reset_all_controls() -> void:
	if not _capturing_action.is_empty():
		_finish_capture("")
	InputBindings.reset_all()
	_refresh_binding_rows()
	_set_controls_status("All controls are back on their defaults.")

func _on_binding_changed(_action: String) -> void:
	_refresh_binding_rows()

func _on_bindings_reset() -> void:
	_refresh_binding_rows()

## Refresh captions and reset availability in place (a rebind must not rebuild
## the page and throw away focus or scroll position).
func _refresh_binding_rows() -> void:
	for action in _binding_buttons:
		var button := _binding_buttons[action] as Button
		if not is_instance_valid(button) or action == _capturing_action:
			continue
		button.text = InputBindings.binding_text(str(action))
		_update_keycap_tooltip(str(action), button)
		_paint_keycap(button, false)
	for action in _binding_reset_buttons:
		var reset := _binding_reset_buttons[action] as Button
		if is_instance_valid(reset):
			reset.disabled = not InputBindings.is_customized(str(action))
	if is_instance_valid(_reset_all_controls_button):
		_reset_all_controls_button.disabled = not InputBindings.has_custom_bindings()

func _set_controls_status(text: String) -> void:
	_controls_status_text = text
	if is_instance_valid(_controls_status_label):
		_controls_status_label.text = text

func _make_group(title: String, description: String, mode: int) -> Dictionary:
	var panel := Kit.make_panel(COLOR_RAISED, MenuStyle.with_alpha(COLOR_BORDER, 0.32))
	panel.name = "Group_%s" % title.to_lower().replace(" ", "_").replace("&", "and")
	var margin := MarginContainer.new()
	_set_margins(margin, 13 if mode == Kit.LayoutMode.DESKTOP else (11 if Kit.is_tablet(mode) else 9))
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8 if mode == Kit.LayoutMode.PHONE_LANDSCAPE else 10)
	margin.add_child(stack)
	var kicker := Kit.make_label(title, 10 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 11, COLOR_GOLD)
	stack.add_child(kicker)
	if not description.is_empty():
		var detail := Kit.make_label(description, 10 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 11, COLOR_MUTED)
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
	label_box.add_child(Kit.make_label(title, 12, COLOR_TEXT))
	var hint_label := Kit.make_label(hint, 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_QUIET)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_box.add_child(hint_label)
	heading.add_child(label_box)
	var value_label := Kit.make_label("%d%%" % int(value * 100), 11, COLOR_GOLD)
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
	var label := Kit.make_label("UI Scale", 12, COLOR_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := Kit.make_label("", 11, COLOR_GOLD)
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
	var range_label := Kit.make_label("80%  ·  150%", 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_QUIET)
	range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(range_label)
	parent.add_child(stack)

func _add_toggle_row(parent: VBoxContainer, title: String, description: String, enabled: bool,
		on_change: Callable, mode: int) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	var label := Kit.make_label(title, 12 if mode != Kit.LayoutMode.DESKTOP else 13, COLOR_TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(label)
	var detail := Kit.make_label(description, 10 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 11, COLOR_MUTED)
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
	return toggle

## Zoom limits (Settings → Controls → Camera).
func _format_zoom_value(value: float) -> String:
	return "%.1f×" % value

func _update_zoom_labels() -> void:
	if is_instance_valid(_min_zoom_value_label):
		_min_zoom_value_label.text = _format_zoom_value(GameManager.camera_min_zoom)
	if is_instance_valid(_max_zoom_value_label):
		_max_zoom_value_label.text = _format_zoom_value(GameManager.camera_max_zoom)
	# Keep sliders in sync if limits were clamped elsewhere.
	if is_instance_valid(_min_zoom_slider) and not is_equal_approx(_min_zoom_slider.value, GameManager.camera_min_zoom):
		_min_zoom_slider.value = GameManager.camera_min_zoom
	if is_instance_valid(_max_zoom_slider) and not is_equal_approx(_max_zoom_slider.value, GameManager.camera_max_zoom):
		_max_zoom_slider.value = GameManager.camera_max_zoom

func _add_zoom_slider_row(parent: VBoxContainer, title: String, hint: String, value: float, on_change: Callable, mode: int, slider_name: String) -> Dictionary:
	var stack := VBoxContainer.new()
	stack.name = slider_name + "Row"
	stack.add_theme_constant_override("separation", 1)
	var heading := HBoxContainer.new()
	var label_box := VBoxContainer.new()
	label_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_box.add_theme_constant_override("separation", 0)
	label_box.add_child(Kit.make_label(title, 12, COLOR_TEXT))
	var hint_label := Kit.make_label(hint, 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_QUIET)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_box.add_child(hint_label)
	heading.add_child(label_box)
	var value_label := Kit.make_label(_format_zoom_value(value), 11, COLOR_GOLD)
	value_label.custom_minimum_size.x = 42
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(value_label)
	stack.add_child(heading)
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = GameManager.CAMERA_ZOOM_ABSOLUTE_MIN
	slider.max_value = GameManager.CAMERA_ZOOM_ABSOLUTE_MAX
	slider.step = 0.1
	slider.value = value
	slider.custom_minimum_size.y = 24
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = hint
	var captured_label := value_label
	slider.value_changed.connect(func(new_value: float):
		on_change.call(new_value)
		captured_label.text = _format_zoom_value(new_value))
	stack.add_child(slider)
	var range_label := Kit.make_label("%.1f×  ·  %.1f×" % [GameManager.CAMERA_ZOOM_ABSOLUTE_MIN, GameManager.CAMERA_ZOOM_ABSOLUTE_MAX], 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_QUIET)
	range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(range_label)
	parent.add_child(stack)
	return {"slider": slider, "value_label": value_label, "root": stack}

func _add_camera_zoom_controls(parent: VBoxContainer, mode: int) -> void:
	var hint := Kit.make_label("Set how far the camera can zoom out and in. The view stays inside these limits whether you use the wheel, keys, pinch or the Course Map drag.", 9 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 10, COLOR_QUIET)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)
	var min_row := _add_zoom_slider_row(parent, "Minimum Zoom", "Farthest out — widest view of the course", GameManager.camera_min_zoom, _on_min_zoom_changed, mode, "MinZoom")
	_min_zoom_slider = min_row["slider"]
	_min_zoom_value_label = min_row["value_label"]
	parent.add_child(_make_separator())
	var max_row := _add_zoom_slider_row(parent, "Maximum Zoom", "Closest in — most detail on the fairway", GameManager.camera_max_zoom, _on_max_zoom_changed, mode, "MaxZoom")
	_max_zoom_slider = max_row["slider"]
	_max_zoom_value_label = max_row["value_label"]
	parent.add_child(_make_separator())
	var reset := Button.new()
	reset.name = "ResetZoomButton"
	reset.text = "Reset Zoom Limits"
	reset.tooltip_text = "Put the zoom limits back on %.1f× to %.1f×." % [GameManager.CAMERA_MIN_ZOOM_DEFAULT, GameManager.CAMERA_MAX_ZOOM_DEFAULT]
	reset.custom_minimum_size = Vector2(0, 40)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.add_theme_font_size_override("font_size", 11 if mode == Kit.LayoutMode.PHONE_PORTRAIT else 12)
	MenuStyle.paint_card(reset, COLOR_MINT, 0.0, 7, COLOR_TEXT, COLOR_TEXT)
	reset.add_theme_color_override("font_color", COLOR_TEXT)
	reset.add_theme_color_override("font_hover_color", COLOR_TEXT)
	reset.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	reset.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset.pressed.connect(_on_reset_zoom_limits)
	parent.add_child(reset)

func _on_min_zoom_changed(value: float) -> void:
	var clamped := clampf(value, GameManager.CAMERA_ZOOM_ABSOLUTE_MIN, GameManager.CAMERA_ZOOM_ABSOLUTE_MAX)
	if clamped >= GameManager.camera_max_zoom:
		clamped = GameManager.camera_max_zoom - 0.1
		clamped = clampf(clamped, GameManager.CAMERA_ZOOM_ABSOLUTE_MIN, GameManager.CAMERA_ZOOM_ABSOLUTE_MAX - 0.1)
		if is_instance_valid(_min_zoom_slider) and not is_equal_approx(_min_zoom_slider.value, clamped):
			_min_zoom_slider.value = clamped
			return
	GameManager.set_camera_min_zoom(clamped)
	_update_zoom_labels()
	_save_camera_settings()

func _on_max_zoom_changed(value: float) -> void:
	var clamped := clampf(value, GameManager.CAMERA_ZOOM_ABSOLUTE_MIN, GameManager.CAMERA_ZOOM_ABSOLUTE_MAX)
	if clamped <= GameManager.camera_min_zoom:
		clamped = GameManager.camera_min_zoom + 0.1
		clamped = clampf(clamped, GameManager.CAMERA_ZOOM_ABSOLUTE_MIN + 0.1, GameManager.CAMERA_ZOOM_ABSOLUTE_MAX)
		if is_instance_valid(_max_zoom_slider) and not is_equal_approx(_max_zoom_slider.value, clamped):
			_max_zoom_slider.value = clamped
			return
	GameManager.set_camera_max_zoom(clamped)
	_update_zoom_labels()
	_save_camera_settings()

func _on_reset_zoom_limits() -> void:
	GameManager.reset_camera_zoom_limits()
	_update_zoom_labels()
	_save_camera_settings()
	if is_instance_valid(_min_zoom_slider):
		_min_zoom_slider.value = GameManager.camera_min_zoom
	if is_instance_valid(_max_zoom_slider):
		_max_zoom_slider.value = GameManager.camera_max_zoom

func _build_footer(mode: int) -> Control:
	var footer := HBoxContainer.new()
	footer.name = "SettingsFooter"
	footer.custom_minimum_size.y = 44 if mode == Kit.LayoutMode.PHONE_LANDSCAPE else 48
	footer.add_theme_constant_override("separation", 8)
	# The notice only earns its room when the footer has the width to spare.
	var note := Kit.make_label("CHANGES APPLY IMMEDIATELY  ·  SAVED ON THIS DEVICE", 10, COLOR_QUIET)
	note.name = "SaveNotice"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.visible = mode == Kit.LayoutMode.DESKTOP or Kit.is_tablet(mode)
	footer.add_child(note)
	var done := Button.new()
	done.name = "DoneButton"
	done.text = close_label
	done.custom_minimum_size = Vector2(136 if mode != Kit.LayoutMode.PHONE_PORTRAIT else 96, 44)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL if mode == Kit.LayoutMode.PHONE_PORTRAIT else Control.SIZE_SHRINK_END
	done.add_theme_font_size_override("font_size", 12)
	MenuStyle.paint_primary(done, 9)
	done.add_theme_color_override("font_color", MenuStyle.INK)
	done.add_theme_color_override("font_hover_color", MenuStyle.INK)
	done.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	done.pressed.connect(_on_close)
	footer.add_child(done)
	return footer

## The one run there is: Main closes this menu and the tour prepares its own
## throwaway course to build every test course on. Only a menu accessed from
## the Main Menu may ask - away from it the card says so instead.
func _request_tour() -> void:
	if not benchmarks_allowed():
		_benchmark_status_text = BENCHMARK_GATE_TEXT
		_refresh_benchmark_controls()
		return
	_benchmark_status_text = "Starting the course tour - watch it prepare, build and play every test course. Esc cancels and takes the benchmark course down."
	_refresh_benchmark_controls()
	tour_requested.emit(CourseBenchmarkScenarios.SUITE_FULL)

## Pick up the run the tour finished, so the card opens showing the newest
## report this machine holds - the tour publishes it as it ends.
func _adopt_last_benchmark() -> void:
	var result := PerformanceBenchmark.last_result
	if result.is_empty():
		return
	_benchmark_summary_text = _benchmark_summary_for(result)
	_benchmark_details_text = _benchmark_details_for(result)
	_benchmark_status_text = BENCHMARK_DONE_TEXT
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
	var tour: Dictionary = result.get("tour", {})
	if not tour.is_empty():
		var rollup: Dictionary = tour.get("rollup", {})
		var simulation: Dictionary = rollup.get("simulation", {})
		return "Course tour: %d courses · heaviest %s at %.1f FPS · frame p95 %.1f ms · %s. Open Past Results for every course." % [
			int(rollup.get("scenario_count", 0)),
			str(simulation.get("worst_scenario", "-")),
			float(simulation.get("worst_fps", 0.0)),
			float(frame.get("p95_frame_ms", 0.0)), gpu_text,
		]
	return "Frame p95 %.1f ms · game process %.1f ms/frame · %s. Open Past Results for the scorecard and the runs behind it." % [
		float(frame.get("p95_frame_ms", 0.0)), float(engine.get("process_ms_per_frame", 0.0)),
		gpu_text,
	]

## The card after a rebuild: Run stands down away from the Main Menu, the
## last run's rating is drawn, and every line says what it currently is.
## Past Results is never locked - reading a report is not running one.
func _refresh_benchmark_controls() -> void:
	if is_instance_valid(_benchmark_run_button):
		_benchmark_run_button.disabled = not benchmarks_allowed()
	if is_instance_valid(_benchmark_status_label):
		_benchmark_status_label.text = _benchmark_status_text
	if is_instance_valid(_benchmark_summary_label):
		_benchmark_summary_label.text = _benchmark_summary_text
	if is_instance_valid(_benchmark_details_label):
		_benchmark_details_label.text = _benchmark_details_text
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

func _set_minimap_enabled(enabled: bool) -> void:
	GameManager.set_minimap_enabled(enabled)
	_save_display_settings()

func _on_minimap_enabled_changed(enabled: bool) -> void:
	if is_instance_valid(_minimap_toggle):
		_minimap_toggle.set_pressed_no_signal(enabled)

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

func _save_camera_settings() -> void:
	var config := ConfigFile.new()
	config.load(SaveManager.SETTINGS_PATH)
	config.set_value("camera", "min_zoom", GameManager.camera_min_zoom)
	config.set_value("camera", "max_zoom", GameManager.camera_max_zoom)
	config.save(SaveManager.SETTINGS_PATH)

func _save_display_settings() -> void:
	var config := ConfigFile.new()
	config.load(SaveManager.SETTINGS_PATH)
	config.set_value("display", "window_mode", DisplayServer.window_get_mode())
	config.set_value("display", "borderless", DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS))
	config.set_value("display", "vsync", DisplayServer.window_get_vsync_mode())
	config.set_value("display", "ui_scale", get_tree().root.content_scale_factor)
	config.set_value("display", "colorblind_mode", ColorblindMode.to_string_name(GameManager.colorblind_mode))
	config.set_value("display", "minimap_enabled", GameManager.minimap_enabled)
	config.save(SaveManager.SETTINGS_PATH)

func _category_key(category: int) -> String:
	return ["audio", "display", "controls"][category]

func _category_name(category: int) -> String:
	return ["Audio", "Display", "Controls"][category]

func _category_title(category: int) -> String:
	return ["Sound & ambience", "Screen & accessibility", "Your controls"][category]

func _category_short_description(category: int) -> String:
	return ["Mixer", "Screen", "Keys"][category]

func _category_description(category: int) -> String:
	return [
		"Balance the master, effects and ambient volume for the course.",
		"Adjust how the game looks and feels on this display.",
		"Rebind every course action, reset one control or reset them all.",
	][category]

func _make_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_color_override("color", MenuStyle.with_alpha(COLOR_BORDER, 0.5))
	return separator

func _set_margins(container: MarginContainer, margin: int) -> void:
	for side in ["left", "right", "top", "bottom"]:
		container.add_theme_constant_override("margin_" + side, margin)

func _on_close() -> void:
	close_requested.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	# A listening keycap consumes the next key or controller button before
	# Escape can close the menu, the GUI can press a button, or a gameplay
	# hotkey can reach the course behind it.
	if not _capturing_action.is_empty():
		if _handle_capture(event):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
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
