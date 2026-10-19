extends Control
class_name BenchmarkResultsScreen
## BenchmarkResultsScreen - the device's own clubhouse dashboard.
##
## Where Settings carries a one-line summary of the last benchmark, this screen
## spreads the whole report out as instruments: a frame-time oscilloscope, a
## GPU load ladder, segmented meters for every metric, a golf scorecard that
## grades the machine Eagle-to-Double, the shelf of past runs to compare
## against, and the device dossier behind all of it. It is the **Past Results**
## of the Settings card, and from Main Menu Settings it can start the course
## tour itself - the game's only benchmark - so a player can open it cold,
## press Run Benchmark and watch the report fill in.
##
## The composition suits each window shape:
##
##  * Desktop: three columns of instruments - the rating, the meters and the
##    device dossier on the left, the big frame chart with the GPU ladder and
##    the engine read-out under it in the middle, the scorecard and the past
##    runs on the right. At a full-height window the whole report is on screen;
##    a shorter one scrolls the columns as a page.
##  * Tablet landscape: two columns - the rating and the instruments over the
##    charts, the scorecard and the shelf beside them.
##  * Tablet portrait: the rating and the instruments side by side, then the
##    charts, the scorecard and the shelf in one scroll.
##  * Phone landscape: a compact rating card beside a short scroll of charts.
##  * Phone portrait: one scrollable column, rating first, dossier last.
##
## It sits on the World Map's MenuBackdrop artwork and wears the same pixel
## look as the Milestones and Achievements screens: notched nine-patch frames,
## Pixelify Sans, `PixelIcon` sprites (including the four the benchmark
## added - chip, graphics card, pulse trace and memory stick) and charts drawn
## in whole pixels by BenchmarkVisuals.
##
## Reports and the shelf of past runs stay on the machine: the copy button
## puts a report on the clipboard, and nothing here is uploaded.

signal back_requested()
## Asks Main to close this screen and run the course benchmark tour - the
## game's only benchmark - which prepares its own throwaway course. Only
## emitted while the screen may run it at all (`benchmarks_allowed` and
## `tour_available`: reached from Main Menu Settings); away from the Main
## Menu, Run stands down entirely.
signal tour_requested(suite_id: String)

## Why the Run button stands down when this screen was not reached from
## Main Menu Settings (the same wording as the Settings card's).
const BENCHMARK_GATE_TEXT := "Benchmarks run from the Main Menu - open Settings there to measure this device. Nothing here touches the game in progress."

## What Run Benchmark offers on a screen with nothing to show yet.
const BENCHMARK_READY_TEXT := "Run Benchmark prepares a throwaway course and builds every test course on it - about 95 seconds. Esc cancels it."

## What Run Benchmark says once it has handed the screen to the tour.
const BENCHMARK_STARTING_TEXT := "Starting the course tour - watch it prepare, build and play every test course. Esc cancels and takes the benchmark course down."

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

## The metric the past-runs chart plots.
const METRIC_OVERALL := "overall"
const METRIC_FPS := "average_fps"
const METRIC_CPU := "cpu_units_per_second"
const METRIC_GPU := "gpu_megapixels_per_second"
const METRICS := [METRIC_OVERALL, METRIC_FPS, METRIC_CPU, METRIC_GPU]

## Runs listed in the past-runs panel.
const HISTORY_ROWS := 5

var _result: Dictionary = {}
var _history: Array = []
var _history_metric: String = METRIC_OVERALL
var _layout_mode: int = -1
var _built_size := Vector2.ZERO
var _status_text: String = ""
var _live_fps_label: Label = null
var _status_label: Label = null
var _run_button: Button = null
var _copy_button: Button = null
## Set by Main before the screen is added: the screen was reached from
## Main Menu Settings, so its runs may start. Without it the screen is
## read-only - the last report, the shelf and copying still work, but no
## benchmark runs over a game in progress. Main always sets it in the
## game; the default keeps a bare test harness runnable.
var benchmarks_allowed: bool = true
## Set by Main before the screen is added: Run Benchmark starts the on-screen
## course tour (which prepares its own course), the only benchmark there is.
## Without it - or away from the Main Menu - Run stands down and the screen
## is a reader for the last report and the past runs.
var tour_available: bool = false
## Where a copied report goes. Empty means the display server's clipboard; a
## window with none (some Wayland and headless setups) is told so rather than
## failing silently.
var clipboard_writer: Callable = Callable()
var _fps_accumulator: float = 0.0
var _fps_frames: int = 0
var _fps_timer: float = 0.0

func _ready() -> void:
	name = "BenchmarkResultsScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not PerformanceBenchmark.last_result.is_empty():
		_result = PerformanceBenchmark.last_result
	_status_text = _default_status_text()
	_history = BenchmarkHistory.load_runs()
	if has_node("/root/Screen") and not Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.connect(_on_screen_changed)
	_build()

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

## The live frame-rate ticker in the header. It only rewrites one label, so
## the screen stays cheap while it is open.
func _process(delta: float) -> void:
	if _live_fps_label == null or not is_instance_valid(_live_fps_label):
		return
	_fps_accumulator += delta
	_fps_frames += 1
	_fps_timer += delta
	if _fps_timer < 0.5:
		return
	var fps := float(_fps_frames) / maxf(_fps_accumulator, 0.001)
	_fps_accumulator = 0.0
	_fps_frames = 0
	_fps_timer = 0.0
	_live_fps_label.text = "LIVE %.0f FPS" % fps

func _window_size() -> Vector2:
	return Kit.window_size_of(self)

func _on_screen_changed(window_size: Vector2, _scale: float) -> void:
	var mode := Kit.layout_mode_for(window_size)
	var needs_remeasure := absf(window_size.x - _built_size.x) > maxf(96.0, _built_size.x * 0.14) \
		or absf(window_size.y - _built_size.y) > maxf(72.0, _built_size.y * 0.14)
	if mode != _layout_mode or needs_remeasure:
		_build()

func refresh() -> void:
	_history = BenchmarkHistory.load_runs()
	_build()

# =============================================================================
# COMPOSITION
# =============================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_layout_mode = Kit.layout_mode_for(_window_size())
	_built_size = _window_size()
	_live_fps_label = null
	_status_label = null
	_run_button = null
	_copy_button = null

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := Kit.outer_padding(_layout_mode, _built_size)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		frame.add_theme_constant_override(side, pad)
	add_child(frame)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", Kit.page_separation(_layout_mode))
	frame.add_child(page)
	page.add_child(_build_header())

	var body: Control
	match _layout_mode:
		Kit.LayoutMode.DESKTOP:
			body = _build_desktop_body()
		Kit.LayoutMode.TABLET_LANDSCAPE:
			body = _build_tablet_body(true)
		Kit.LayoutMode.TABLET_PORTRAIT:
			body = _build_tablet_body(false)
		Kit.LayoutMode.PHONE_LANDSCAPE:
			body = _build_phone_body(true)
		_:
			body = _build_phone_body(false)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	page.add_child(_build_footer())

## Chart heights track the window, so a short desktop window shrinks the
## oscilloscope instead of pushing the page past the bottom edge.
func _chart_height() -> float:
	match _layout_mode:
		Kit.LayoutMode.DESKTOP:
			return clampf(_built_size.y * 0.26, 150.0, 260.0)
		Kit.LayoutMode.TABLET_LANDSCAPE, Kit.LayoutMode.TABLET_PORTRAIT:
			return clampf(_built_size.y * 0.24, 140.0, 220.0)
		Kit.LayoutMode.PHONE_LANDSCAPE:
			return clampf(_built_size.y * 0.34, 110.0, 170.0)
		_:
			return clampf(_built_size.y * 0.20, 120.0, 190.0)

func _is_compact() -> bool:
	return Kit.is_phone(_layout_mode)

# =============================================================================
# HEADER AND FOOTER
# =============================================================================

func _build_header() -> Control:
	var compact := _is_compact()
	var header := HBoxContainer.new()
	header.name = "BenchmarkHeader"
	header.add_theme_constant_override("separation", 9 if not compact else 6)
	header.custom_minimum_size.y = 62.0 if Kit.is_desktop(_layout_mode) else (54.0 if not compact else 46.0)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "‹  Back" if not compact else "‹ Back"
	back.tooltip_text = "Return to the course (Esc)"
	back.custom_minimum_size = Vector2(94.0 if not compact else 72.0, 42.0 if compact else 46.0)
	Kit.paint_utility_button(back, false)
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)

	var title_box := HBoxContainer.new()
	title_box.name = "TitleBlock"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 8 if compact else 10)
	var mark := Kit.make_sprite(PixelIcon.Kind.PULSE, 20 if compact else 28, Kit.COLOR_GOLD)
	mark.name = "TitleMark"
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_child(mark)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	var kicker := Kit.make_kicker("Device scorecard  ·  %s" % _benchmark_version(), 9)
	kicker.name = "TitleKicker"
	titles.add_child(kicker)
	var title := Kit.make_title_label("Benchmark Results", 19 if compact else 26)
	title.name = "Title"
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(title)
	title_box.add_child(titles)
	header.add_child(title_box)

	var live := Kit.make_chip("LIVE -- FPS", MenuStyle.ACCENT_UTILITY, Kit.COLOR_TEXT_QUIET, 10)
	live.name = "LiveFpsChip"
	live.custom_minimum_size = Vector2(96.0, 24.0)
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	live.visible = not compact
	_live_fps_label = live
	header.add_child(live)

	var tier := _build_tier_chip()
	tier.name = "TierChip"
	tier.visible = not compact
	header.add_child(tier)
	return header

## The rating stamp in the header: the stars, the tier and the score.
func _build_tier_chip() -> PanelContainer:
	var score := _score()
	var stars := int(score.get("stars", 0))
	var accent := BenchmarkVisuals.tier_color(stars)
	var chip := Kit.make_panel(Kit.COLOR_SURFACE_RAISED, MenuStyle.with_alpha(accent, 0.65))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	chip.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var stars_row := BenchmarkVisuals.make_star_row(stars, 16, "HeaderStarRow")
	stars_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(stars_row)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	var tier_label := Kit.make_semibold_label(str(score.get("tier", "Unrated")), 13)
	tier_label.name = "TierName"
	text.add_child(tier_label)
	var overall := Kit.make_label("%d / 100 overall" % int(round(float(score.get("overall", 0.0)))),
		10, Kit.COLOR_TEXT_QUIET)
	overall.name = "OverallScore"
	text.add_child(overall)
	box.add_child(text)
	return chip

func _build_footer() -> Control:
	var compact := _is_compact()
	var footer := VBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 6)

	var status := Kit.make_label(_status_text, 10 if compact else 11, Kit.COLOR_TEXT_QUIET)
	status.name = "StatusLine"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = clampf(_built_size.x * 0.40, 180.0, 520.0)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label = status
	footer.add_child(status)

	# A phone gives the headline run a row of its own and the report buttons
	# the next one, so nothing has to shrink below a tappable size; a wider
	# window fits all three side by side.
	var actions := HBoxContainer.new()
	actions.name = "ActionBar"
	actions.add_theme_constant_override("separation", 7)
	actions.custom_minimum_size.y = 46.0 if compact else 50.0
	var report_parent: HBoxContainer = actions
	if compact:
		report_parent = HBoxContainer.new()
		report_parent.name = "ReportBar"
		report_parent.add_theme_constant_override("separation", 7)
		report_parent.custom_minimum_size.y = 46.0

	var run := Button.new()
	run.name = "RunBenchmarkButton"
	run.text = "Run Benchmark"
	run.tooltip_text = BENCHMARK_GATE_TEXT if not _can_run() \
		else "Close this screen and watch the tour prepare, build and play every test course (about 95 seconds). Esc cancels it."
	run.custom_minimum_size = Vector2(0, 46.0)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run.size_flags_stretch_ratio = 1.6
	run.add_theme_font_size_override("font_size", 13)
	Kit.paint_utility_button(run, true)
	run.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	run.pressed.connect(_start_run)
	actions.add_child(run)
	_run_button = run

	var copy := Button.new()
	copy.name = "CopyReportButton"
	copy.text = "Copy report"
	copy.tooltip_text = "Copy the full report to the clipboard. Nothing is uploaded."
	copy.custom_minimum_size = Vector2(0, 46.0)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_font_size_override("font_size", 12)
	Kit.paint_utility_button(copy, false)
	copy.pressed.connect(_copy_report)
	report_parent.add_child(copy)
	_copy_button = copy

	var clear := Button.new()
	clear.name = "ClearHistoryButton"
	clear.text = "Clear past runs"
	clear.tooltip_text = "Forget every run kept on this machine."
	clear.custom_minimum_size = Vector2(0, 46.0)
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.add_theme_font_size_override("font_size", 12)
	Kit.paint_utility_button(clear, false)
	clear.pressed.connect(_clear_history)
	report_parent.add_child(clear)
	footer.add_child(actions)
	if report_parent != actions:
		footer.add_child(report_parent)

	_refresh_actions()
	return footer

## The action bar after a rebuild: Run stands down away from the Main Menu
## (or without a tour to run), and copying needs a report behind it. The
## report buttons are always live - reading is not running.
func _refresh_actions() -> void:
	if is_instance_valid(_run_button):
		_run_button.disabled = not _can_run()
	if is_instance_valid(_copy_button):
		_copy_button.disabled = _result.is_empty()
	if is_instance_valid(_status_label):
		_status_label.text = _status_text

# =============================================================================
# BODY: DESKTOP - three columns of instruments
# =============================================================================

## Three columns of instruments. On a full-height desktop window the whole
## report fits without scrolling; at the shortest desktop windows (a 1180x700
## browser window) the columns scroll as one page rather than dropping panels.
func _build_desktop_body() -> Control:
	var scroll := _make_scroll("DesktopScroll")
	var body := HBoxContainer.new()
	body.name = "DesktopLayout"
	body.add_theme_constant_override("separation", 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The rail carries the rating, the meters and the dossier: the three panels
	# a reader returns to, stacked where the eye starts. The dossier takes the
	# slack, so the column always fills its height.
	var left := VBoxContainer.new()
	left.name = "DesktopLeft"
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = clampf(_built_size.x * 0.225, 288.0, 366.0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_build_rating_panel())
	left.add_child(_build_instruments_panel())
	var device := _build_device_panel()
	device.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(device)
	body.add_child(left)

	var middle := VBoxContainer.new()
	middle.name = "DesktopMiddle"
	middle.add_theme_constant_override("separation", 12)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var chart := _build_frame_chart_panel()
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(chart)
	var lower := HBoxContainer.new()
	lower.name = "DesktopChartsRow"
	lower.add_theme_constant_override("separation", 12)
	var gpu := _build_gpu_panel()
	gpu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpu.size_flags_stretch_ratio = 1.15
	lower.add_child(gpu)
	var engine := _build_engine_panel()
	engine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(engine)
	middle.add_child(lower)
	if _show_tour_panel():
		middle.add_child(_build_tour_panel())
	body.add_child(middle)

	var right := VBoxContainer.new()
	right.name = "DesktopRight"
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size.x = clampf(_built_size.x * 0.235, 300.0, 380.0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_build_scorecard_panel())
	var history := _build_history_panel()
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(history)
	body.add_child(right)
	scroll.add_child(body)
	return scroll

# =============================================================================
# BODY: TABLETS
# =============================================================================

func _build_tablet_body(landscape: bool) -> Control:
	var scroll := _make_scroll("TabletLayout")
	var column := VBoxContainer.new()
	column.name = "TabletPage"
	column.add_theme_constant_override("separation", 11)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var top := HBoxContainer.new()
	top.name = "TabletTopRow"
	top.add_theme_constant_override("separation", 11)
	var rating := _build_rating_panel()
	rating.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rating)
	var meters := _build_instruments_panel()
	meters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(meters)
	column.add_child(top)

	if landscape:
		var charts := HBoxContainer.new()
		charts.name = "TabletChartsRow"
		charts.add_theme_constant_override("separation", 11)
		var frame_chart := _build_frame_chart_panel()
		frame_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame_chart.size_flags_stretch_ratio = 1.4
		charts.add_child(frame_chart)
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 11)
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.add_child(_build_gpu_panel())
		side.add_child(_build_engine_panel())
		charts.add_child(side)
		column.add_child(charts)
		var bottom := HBoxContainer.new()
		bottom.name = "TabletBottomRow"
		bottom.add_theme_constant_override("separation", 11)
		var scorecard := _build_scorecard_panel()
		scorecard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scorecard.size_flags_stretch_ratio = 1.25
		bottom.add_child(scorecard)
		var history := _build_history_panel()
		history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(history)
		column.add_child(bottom)
		if _show_tour_panel():
			column.add_child(_build_tour_panel())
		column.add_child(_build_device_panel())
	else:
		column.add_child(_build_frame_chart_panel())
		var pair := HBoxContainer.new()
		pair.name = "TabletLowerRow"
		pair.add_theme_constant_override("separation", 11)
		var gpu := _build_gpu_panel()
		gpu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.add_child(gpu)
		var engine := _build_engine_panel()
		engine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.add_child(engine)
		column.add_child(pair)
		column.add_child(_build_scorecard_panel())
		if _show_tour_panel():
			column.add_child(_build_tour_panel())
		column.add_child(_build_history_panel())
		column.add_child(_build_device_panel())
	return scroll

# =============================================================================
# BODY: PHONES
# =============================================================================

func _build_phone_body(landscape: bool) -> Control:
	var scroll := _make_scroll("PhoneLayout")
	if landscape:
		var row := HBoxContainer.new()
		row.name = "PhoneLandscapeRow"
		row.add_theme_constant_override("separation", 9)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 9)
		left.custom_minimum_size.x = clampf(_built_size.x * 0.40, 210.0, 300.0)
		left.add_child(_build_rating_panel())
		left.add_child(_build_instruments_panel())
		row.add_child(left)
		var right := VBoxContainer.new()
		right.name = "PhoneLandscapeColumn"
		right.add_theme_constant_override("separation", 9)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_child(_build_frame_chart_panel())
		right.add_child(_build_scorecard_panel())
		if _show_tour_panel():
			right.add_child(_build_tour_panel())
		right.add_child(_build_gpu_panel())
		right.add_child(_build_history_panel())
		right.add_child(_build_engine_panel())
		right.add_child(_build_device_panel())
		row.add_child(right)
		scroll.add_child(row)
		return scroll

	var column := VBoxContainer.new()
	column.name = "PhoneColumn"
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_build_rating_panel())
	column.add_child(_build_instruments_panel())
	column.add_child(_build_frame_chart_panel())
	column.add_child(_build_gpu_panel())
	column.add_child(_build_scorecard_panel())
	if _show_tour_panel():
		column.add_child(_build_tour_panel())
	column.add_child(_build_history_panel())
	column.add_child(_build_engine_panel())
	column.add_child(_build_device_panel())
	scroll.add_child(column)
	return scroll

func _make_scroll(scroll_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	return scroll

# =============================================================================
# PANELS
# =============================================================================

## The rating: five stars, the tier name, the overall score and what changed
## since the run before it.
func _build_rating_panel() -> PanelContainer:
	var score := _score()
	var stars := int(score.get("stars", 0))
	var accent := BenchmarkVisuals.tier_color(stars)
	var panel := _panel("RatingPanel", accent, 14)
	var stack := _panel_stack(panel, 8)
	stack.add_child(Kit.make_kicker("Device rating", 11))

	var head := HBoxContainer.new()
	head.name = "RatingHead"
	head.add_theme_constant_override("separation", 10)
	var stars_row := BenchmarkVisuals.make_star_row(stars, 24 if not _is_compact() else 20,
		"RatingStarRow")
	stars_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(stars_row)
	var numbers := VBoxContainer.new()
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	numbers.add_theme_constant_override("separation", 0)
	var tier := Kit.make_title_label(str(score.get("tier", "Unrated")), 22 if not _is_compact() else 18,
		accent)
	tier.name = "RatingTier"
	numbers.add_child(tier)
	var overall := Kit.make_label("%d / 100 overall score" % int(round(float(score.get("overall", 0.0)))),
		11, Kit.COLOR_TEXT_SECONDARY)
	overall.name = "RatingOverall"
	numbers.add_child(overall)
	head.add_child(numbers)
	stack.add_child(head)

	var verdict := Kit.make_label(str(score.get("verdict", "")), 11, Kit.COLOR_TEXT_QUIET)
	verdict.name = "RatingVerdict"
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(verdict)

	stack.add_child(_build_delta_row())
	stack.add_child(_build_run_meta_row())
	return panel

## What changed since the run before this one - the reason to keep a shelf.
func _build_delta_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "RatingDelta"
	row.add_theme_constant_override("separation", 7)
	var previous := BenchmarkHistory.previous_of(_history)
	if previous.is_empty() or _result.is_empty():
		var hint := Kit.make_label("Run the test again to see how this device changes.", 10,
			Kit.COLOR_TEXT_QUIET)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.clip_text = true
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(hint)
		return row
	var record := BenchmarkHistory.record_from(_result)
	var percent := BenchmarkHistory.change_percent(previous, record, "overall")
	var delta := Kit.make_chip(BenchmarkHistory.format_change(percent),
		BenchmarkVisuals.COLOR_FINE if percent >= 0.0 else BenchmarkVisuals.COLOR_BAD,
		UIConstants.COLOR_TEXT, 10)
	delta.name = "DeltaChip"
	delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(delta)
	var note := Kit.make_label("overall score against the run before it", 10, Kit.COLOR_TEXT_QUIET)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	return row

func _build_run_meta_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "RatingMeta"
	row.add_theme_constant_override("separation", 6)
	var scenario := str(_context().get("scenario", "Unknown scene"))
	var chip := Kit.make_chip(scenario, MenuStyle.ACCENT_UTILITY, Kit.COLOR_TEXT_QUIET, 10)
	chip.name = "ScenarioChip"
	row.add_child(chip)
	var when := Kit.make_label(BenchmarkHistory.time_label(int(_result.get("started_at_unix", 0))),
		10, Kit.COLOR_TEXT_QUIET)
	when.name = "RunTime"
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(when)
	return row

## The instruments: one segmented meter per graded metric.
func _build_instruments_panel() -> PanelContainer:
	var panel := _panel("InstrumentsPanel", MenuStyle.with_alpha(Kit.COLOR_BORDER_SOFT, 0.5), 13)
	var stack := _panel_stack(panel, 8)
	stack.add_child(Kit.make_kicker("Instruments", 11))
	var icons := {
		"pacing": PixelIcon.Kind.PULSE,
		"consistency": PixelIcon.Kind.FLAG,
		"cpu": PixelIcon.Kind.CHIP,
		"gpu": PixelIcon.Kind.GPU,
	}
	for row in PerformanceBenchmark.scorecard_rows(_result):
		var entry: Dictionary = row
		if not bool(entry.get("graded", false)):
			continue
		stack.add_child(_build_meter_row(str(entry["key"]), str(entry["label"]),
			str(entry["value"]), float(entry["score"]), int(icons.get(str(entry["key"]),
				PixelIcon.Kind.STAR))))
	return panel

func _build_meter_row(key: String, label_text: String, value_text: String, score: float,
		icon_kind: int) -> Control:
	var row := VBoxContainer.new()
	row.name = "Meter_%s" % key
	row.add_theme_constant_override("separation", 3)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	var icon := Kit.make_sprite(icon_kind, 16, BenchmarkVisuals.score_color(score))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var label := Kit.make_semibold_label(label_text, 11, Kit.COLOR_TEXT_SECONDARY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	var value := Kit.make_label(value_text, 11, Kit.COLOR_TEXT_BRIGHT)
	value.name = "Value"
	line.add_child(value)
	var stamp := Kit.make_chip("%d/100" % int(round(score)), BenchmarkVisuals.score_color(score),
		UIConstants.COLOR_TEXT, 9)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(stamp)
	row.add_child(line)
	var meter := BenchmarkVisuals.make_meter(score / 100.0, BenchmarkVisuals.score_color(score),
		"Meter")
	meter.custom_minimum_size.y = 11.0
	row.add_child(meter)
	return row

## The oscilloscope: every sampled frame of the run as one chunky column.
func _build_frame_chart_panel() -> PanelContainer:
	var panel := _panel("FrameChartPanel", MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.45), 13)
	var stack := _panel_stack(panel, 7)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var kicker := Kit.make_kicker("Frame pacing", 11)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kicker)
	var frame := _frame()
	var samples := Kit.make_chip("%s frames" % str(frame.get("sample_count", 0)),
		MenuStyle.ACCENT_UTILITY, Kit.COLOR_TEXT_QUIET, 10)
	samples.name = "SampleChip"
	head.add_child(samples)
	stack.add_child(head)

	var chart := BenchmarkVisuals.make_frame_chart(_frame_series(),
		float(frame.get("average_frame_ms", 0.0)), float(frame.get("one_percent_low_fps", 0.0)),
		"FrameChart")
	chart.axis_font_size = 10 if not _is_compact() else 9
	chart.custom_minimum_size.y = _chart_height()
	stack.add_child(chart)

	stack.add_child(_build_chart_legend())
	stack.add_child(_build_frame_stats_row())
	return panel

## The chart's key, as three small colour chips rather than a drawn legend, so
## it stays legible at phone widths.
func _build_chart_legend() -> Control:
	var row := HBoxContainer.new()
	row.name = "ChartLegend"
	row.add_theme_constant_override("separation", 6)
	var entries := [
		["60 FPS budget", BenchmarkVisuals.COLOR_FINE],
		["33 ms stutter line", BenchmarkVisuals.COLOR_WARN],
		["missed frames", BenchmarkVisuals.COLOR_BAD],
	]
	for entry in entries:
		var chip := Kit.make_chip(str(entry[0]), entry[1], UIConstants.COLOR_TEXT, 9)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(chip)
	return row

func _build_frame_stats_row() -> Control:
	var frame := _frame()
	var grid := GridContainer.new()
	grid.name = "FrameStats"
	grid.columns = 2 if _is_compact() else 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stats := [
		["Average", "%.1f FPS" % float(frame.get("average_fps", 0.0))],
		["1% low", "%.1f FPS" % float(frame.get("one_percent_low_fps", 0.0))],
		["p95 frame", "%.1f ms" % float(frame.get("p95_frame_ms", 0.0))],
		["Worst frame", "%.1f ms" % float(frame.get("worst_frame_ms", 0.0))],
	]
	for stat in stats:
		grid.add_child(_build_stat_cell(str(stat[0]), str(stat[1])))
	return grid

func _build_stat_cell(caption: String, value: String) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 0)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Kit.make_kicker(caption, 9)
	cell.add_child(label)
	var number := Kit.make_semibold_label(value, 13, Kit.COLOR_TEXT_BRIGHT)
	cell.add_child(number)
	return cell

## The GPU fill test: the load ladder as bars, with the peak throughput under
## it. A skipped test says why instead of drawing empty bars.
func _build_gpu_panel() -> PanelContainer:
	var panel := _panel("GpuPanel", MenuStyle.with_alpha(Kit.COLOR_MINT, 0.45), 13)
	var stack := _panel_stack(panel, 7)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var kicker := Kit.make_kicker("GPU fill test", 11)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kicker)
	var gpu := _gpu()
	var peak := Kit.make_chip("%.0f MPix/s" % float(gpu.get("peak_megapixels_per_second", 0.0)),
		Kit.COLOR_MINT, UIConstants.COLOR_TEXT, 10)
	peak.name = "GpuPeakChip"
	peak.visible = bool(gpu.get("available", false))
	head.add_child(peak)
	stack.add_child(head)

	var ladder: Array = gpu.get("levels", [])
	var values: Array[float] = []
	var labels: Array[String] = []
	for step in ladder:
		var entry: Dictionary = step
		values.append(float(entry.get("megapixels_per_second", 0.0)))
		labels.append("%dx" % int(round(float(entry.get("overdraw", 0.0)))))
	var chart := BenchmarkVisuals.make_bar_chart(values, labels, "", "GpuLadderChart")
	chart.custom_minimum_size.y = clampf(_chart_height() * 0.55, 84.0, 140.0)
	chart.highlight_last = false
	stack.add_child(chart)

	var note := _gpu_note(gpu)
	note.name = "GpuNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(note)
	return panel

func _gpu_note(gpu: Dictionary) -> Label:
	if not bool(gpu.get("available", false)):
		return Kit.make_label("Skipped: %s." % str(gpu.get("reason", "not available")), 10,
			Kit.COLOR_TEXT_QUIET)
	var capped := false
	for step in gpu.get("levels", []):
		if bool((step as Dictionary).get("capped", false)):
			capped = true
	var text := "The weave is redrawn at each overdraw level; peak %.0f MPix/s at %dx, %.2f ms a frame on the render side." % [
		float(gpu.get("peak_megapixels_per_second", 0.0)),
		int(round(float(gpu.get("peak_overdraw", 0.0)))),
		float(gpu.get("gpu_ms_per_frame", 0.0)),
	]
	if capped:
		text += " A level hit the frame cap, so the peak is a floor rather than a limit."
	return Kit.make_label(text, 10, Kit.COLOR_TEXT_QUIET)

## The scene the run measured: engine timings, render counts and memory.
func _build_engine_panel() -> PanelContainer:
	var panel := _panel("EnginePanel", MenuStyle.with_alpha(Kit.COLOR_BORDER_SOFT, 0.5), 13)
	var stack := _panel_stack(panel, 6)
	stack.add_child(Kit.make_kicker("Engine & memory", 11))
	var engine := _engine()
	var memory := _memory()
	var rows := [
		[PixelIcon.Kind.GEAR, "Game logic", "%.2f ms / frame" % float(engine.get("process_ms_per_frame", 0.0))],
		[PixelIcon.Kind.GEAR, "Physics", "%.2f ms / frame" % float(engine.get("physics_ms_per_frame", 0.0))],
		[PixelIcon.Kind.PIN, "Nodes", str(engine.get("node_count", 0))],
		[PixelIcon.Kind.PIN, "Render objects", "%s | %s primitives" % [str(engine.get("render_objects", 0)),
			str(engine.get("render_primitives", 0))]],
		[PixelIcon.Kind.PIN, "Draw calls", str(engine.get("draw_calls", 0))],
		[PixelIcon.Kind.MEMORY, "Static memory", "%.0f MB" % float(memory.get("static_mb", 0.0))],
		[PixelIcon.Kind.MEMORY, "Video memory", "%.0f MB (%.0f MB textures)" % [
			float(memory.get("video_mb", 0.0)), float(memory.get("texture_mb", 0.0))]],
	]
	for row in rows:
		stack.add_child(_build_detail_row(int(row[0]), str(row[1]), str(row[2])))
	return panel

## Whether this screen has a tour to show or to offer: a finished tour in
## the report, or a course open behind it that one could run on.
func _show_tour_panel() -> bool:
	return tour_available or not (_result.get("tour", {}) as Dictionary).is_empty()

## The tour's scorecard-by-course: a bar per built course at its simulation
## frame rate, then a row per course with what it was, what building it cost
## and how its camera, simulation and editing phases ran, and the rollups
## that compare the game's subsystems against each other.
func _build_tour_panel() -> PanelContainer:
	var panel := _panel("TourPanel", MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.55), 13)
	var stack := _panel_stack(panel, 7)
	var tour: Dictionary = _result.get("tour", {})
	var suite_name := str(tour.get("suite_name", "Course tour"))
	var head := Kit.make_kicker("Course tour · %s" % suite_name, 11)
	head.name = "TourTitle"
	stack.add_child(head)

	var rows := PerformanceBenchmark.tour_scenario_rows(_result)
	if rows.is_empty():
		var empty := Kit.make_label("No tour in this report yet. Run the course tour to watch fixed test courses being built and played - every course type, hole count, golfer field, camera move, terrain edit and game speed - then read each course's numbers here.", 11, Kit.COLOR_TEXT_QUIET)
		empty.name = "TourEmpty"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(empty)
		return panel

	var values: Array[float] = []
	var labels: Array[String] = []
	for row in rows:
		var entry: Dictionary = row
		values.append(float(entry.get("sim_fps", 0.0)))
		labels.append("%dh" % int(entry.get("holes", 0)))
	var chart := BenchmarkVisuals.make_bar_chart(values, labels, "FPS", "TourScenarioChart")
	chart.custom_minimum_size.y = _chart_height() * 0.55
	stack.add_child(chart)
	var chart_caption := Kit.make_label("Simulation FPS per toured course (label: holes)", 9,
		Kit.COLOR_TEXT_QUIET)
	stack.add_child(chart_caption)

	var index := 0
	for row in rows:
		stack.add_child(_build_tour_row(row, index))
		index += 1

	var rollup: Dictionary = tour.get("rollup", {})
	var generation: Dictionary = rollup.get("generation", {})
	var editing: Dictionary = rollup.get("editing", {})
	var totals: Dictionary = rollup.get("totals", {})
	var lines: Array[String] = []
	var tour_prepare: Dictionary = tour.get("prepare", {})
	if bool(tour_prepare.get("prepared", false)):
		lines.append("Benchmark course prepared in %.0f ms; preparing each course is part of the measured sample." % float(tour_prepare.get("prepare_ms", 0.0)))
	lines.append("Built %d courses in %.0f ms total (slowest %s, %.0f ms)." % [
		int(rollup.get("scenario_count", 0)), float(generation.get("total_ms", 0.0)),
		str(generation.get("slowest_scenario", "-")),
		float(generation.get("slowest_ms", 0.0))])
	var build_by_holes := PackedStringArray()
	for group in generation.get("by_hole_count", []):
		var entry: Dictionary = group
		build_by_holes.append("%d holes: %.0f ms" % [int(entry.get("holes", 0)),
			float(entry.get("average_ms", 0.0))])
	if not build_by_holes.is_empty():
		lines.append("Generation by size: " + " · ".join(build_by_holes))
	var simulation: Dictionary = rollup.get("simulation", {})
	var by_speed := PackedStringArray()
	for group in simulation.get("by_speed", []):
		var entry: Dictionary = group
		by_speed.append("%s %.1f FPS (%.2f days/s)" % [
			CourseBenchmarkScenarios.speed_name(int(entry.get("speed", 1))),
			float(entry.get("average_fps", 0.0)),
			float(entry.get("days_per_second", 0.0))])
	if not by_speed.is_empty():
		lines.append("Simulation by game speed: " + " · ".join(by_speed))
	var edited := int(editing.get("tiles_changed", 0)) + int(editing.get("vertices_changed", 0))
	if edited > 0:
		lines.append("Terrain editing moved %s tiles/vertices at %.0f per second of brush work." % [
			PerformanceBenchmark.format_integer(edited),
			float(editing.get("tiles_per_second", 0.0))])
	var restored_text := ("Main menu restored" if bool(tour_prepare.get("prepared", false)) \
		else "Player's course restored") + ": " + ("yes" if bool(tour.get("restored", false)) else "no")
	lines.append("Totals: %d holes · %d buildings · %d decorations · %s path tiles · %d golfers (%d visiting). %s." % [
		int(totals.get("holes", 0)), int(totals.get("buildings", 0)),
		int(totals.get("decorations", 0)),
		PerformanceBenchmark.format_integer(int(totals.get("path_tiles", 0))),
		int(totals.get("golfers_spawned", 0)), int(totals.get("visiting_spawned", 0)),
		restored_text])
	for line in lines:
		var label := Kit.make_label(line, 10, Kit.COLOR_TEXT_QUIET)
		label.name = "TourRollup"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(label)
	return panel

func _build_tour_row(row: Dictionary, index: int) -> Control:
	var striped := index % 2 == 1
	var fill := MenuStyle.with_alpha(Kit.COLOR_SURFACE_INSET, 0.85) if striped \
		else MenuStyle.with_alpha(Kit.COLOR_SURFACE_RAISED, 0.6)
	var line := Kit.make_panel(fill, MenuStyle.with_alpha(Kit.COLOR_MINT, 0.30))
	line.name = "TourRow_%d" % index
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	line.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(Kit.make_semibold_label(str(row.get("name", "")), 11,
		Kit.COLOR_TEXT_BRIGHT))
	var detail := Kit.make_label(str(row.get("detail", "")), 9, Kit.COLOR_TEXT_QUIET)
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(detail)
	box.add_child(text)
	var numbers := "prep %.1f FPS · build %.0f ms\nsim %.1f FPS · cam %.1f\n%s" % [
		float(row.get("prepare_fps", 0.0)),
		float(row.get("build_ms", 0.0)), float(row.get("sim_fps", 0.0)),
		float(row.get("camera_fps", 0.0)), str(row.get("edit_text", ""))]
	var value := Kit.make_label(numbers, 10, Kit.COLOR_TEXT_SECONDARY)
	value.name = "TourNumbers"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value)
	return line

## The golf scorecard: each metric graded Eagle to Double, with the scene load
## as the ungraded line at the bottom.
func _build_scorecard_panel() -> PanelContainer:
	var panel := _panel("ScorecardPanel", MenuStyle.with_alpha(Kit.COLOR_GOLD, 0.55), 13)
	var stack := _panel_stack(panel, 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var kicker := Kit.make_kicker("Performance scorecard", 11)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kicker)
	stack.add_child(head)

	var header_row := HBoxContainer.new()
	header_row.name = "ScorecardHeader"
	header_row.add_theme_constant_override("separation", 6)
	var hole := Kit.make_kicker("Metric", 9)
	hole.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(hole)
	var result := Kit.make_kicker("Result", 9)
	result.custom_minimum_size.x = _scorecard_value_width()
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_row.add_child(result)
	var score := Kit.make_kicker("Grade", 9)
	score.custom_minimum_size.x = 62.0
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_row.add_child(score)
	stack.add_child(header_row)

	var index := 0
	for row in PerformanceBenchmark.scorecard_rows(_result):
		stack.add_child(_build_scorecard_row(row, index % 2 == 1))
		index += 1

	var total := HBoxContainer.new()
	total.name = "ScorecardTotal"
	total.add_theme_constant_override("separation", 6)
	var total_label := Kit.make_semibold_label("Overall", 12, Kit.COLOR_TEXT_BRIGHT)
	total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total.add_child(total_label)
	var score_text := _score()
	var total_value := Kit.make_semibold_label("%d / 100" % int(round(float(score_text.get("overall", 0.0)))),
		13, Kit.COLOR_GOLD)
	total_value.custom_minimum_size.x = _scorecard_value_width()
	total_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_child(total_value)
	var tier_chip := Kit.make_chip(str(score_text.get("tier", "Unrated")),
		BenchmarkVisuals.tier_color(int(score_text.get("stars", 0))), UIConstants.COLOR_TEXT, 10)
	tier_chip.custom_minimum_size.x = 62.0
	tier_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_child(tier_chip)
	stack.add_child(total)
	return panel

func _scorecard_value_width() -> float:
	return 92.0 if _is_compact() else 132.0

func _build_scorecard_row(row: Dictionary, striped: bool) -> Control:
	var graded := bool(row.get("graded", false))
	var score := float(row.get("score", 0.0))
	var accent := BenchmarkVisuals.score_color(score) if graded else MenuStyle.ACCENT_UTILITY
	var fill := MenuStyle.with_alpha(Kit.COLOR_SURFACE_INSET, 0.85) if striped \
		else MenuStyle.with_alpha(Kit.COLOR_SURFACE_RAISED, 0.6)
	var line := Kit.make_panel(fill, MenuStyle.with_alpha(accent, 0.30))
	line.name = "Row_%s" % str(row.get("key", "row"))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	line.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var label := Kit.make_semibold_label(str(row.get("label", "")), 11,
		Kit.COLOR_TEXT_BRIGHT if graded else Kit.COLOR_TEXT_SECONDARY)
	text.add_child(label)
	var detail := Kit.make_label(str(row.get("detail", "")), 9, Kit.COLOR_TEXT_QUIET)
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(detail)
	box.add_child(text)

	var value := Kit.make_label(str(row.get("value", "")), 11, Kit.COLOR_TEXT_SECONDARY)
	value.name = "Result"
	value.custom_minimum_size.x = _scorecard_value_width()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value)

	var grade_text := PerformanceBenchmark.grade_for(score) if graded else "—"
	var grade := Kit.make_chip(grade_text, accent if graded else MenuStyle.ACCENT_UTILITY,
		UIConstants.COLOR_TEXT if graded else Kit.COLOR_TEXT_QUIET, 10)
	grade.name = "Grade"
	grade.custom_minimum_size.x = 62.0
	grade.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(grade)
	return line

## The shelf: a metric switch, the comparison chart and the newest runs with
## the change against the run above each one.
func _build_history_panel() -> PanelContainer:
	var panel := _panel("HistoryPanel", MenuStyle.with_alpha(Kit.COLOR_MINT, 0.40), 13)
	var stack := _panel_stack(panel, 7)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var kicker := Kit.make_kicker("Past runs", 11)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kicker)
	var count := Kit.make_chip("%d kept" % _history.size(), MenuStyle.ACCENT_UTILITY,
		Kit.COLOR_TEXT_QUIET, 10)
	count.name = "HistoryCount"
	head.add_child(count)
	stack.add_child(head)

	if not _is_compact():
		stack.add_child(_build_metric_switch())

	var values := _history_chart_values()
	var labels: Array[String] = []
	for record in _history:
		labels.append(BenchmarkHistory.time_label(int(record.get("at_unix", 0))).split(" ")[0])
	var chart := BenchmarkVisuals.make_bar_chart(values, labels, _metric_unit(), "HistoryChart")
	chart.custom_minimum_size.y = clampf(_chart_height() * 0.5, 76.0, 120.0)
	stack.add_child(chart)

	var shown := 0
	for index in range(_history.size() - 1, -1, -1):
		if shown >= HISTORY_ROWS:
			break
		stack.add_child(_build_history_row(_history[index], index))
		shown += 1
	if _history.is_empty():
		var note := Kit.make_label("Finished runs are kept here - up to %d - so devices and settings changes can be compared."
			% BenchmarkHistory.MAX_RUNS, 10, Kit.COLOR_TEXT_QUIET)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(note)
	return panel

func _build_metric_switch() -> Control:
	var switch := HBoxContainer.new()
	switch.name = "MetricSwitch"
	switch.add_theme_constant_override("separation", 5)
	var group := ButtonGroup.new()
	for metric in METRICS:
		var button := Button.new()
		button.name = "Metric_%s" % str(metric)
		button.text = _metric_short(metric)
		button.tooltip_text = _metric_name(metric)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = metric == _history_metric
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 36.0
		button.add_theme_font_size_override("font_size", 10)
		Kit.paint_toggle(button, Kit.COLOR_MINT)
		button.pressed.connect(_select_metric.bind(metric))
		switch.add_child(button)
	return switch

func _select_metric(metric: String) -> void:
	if metric == _history_metric:
		return
	_history_metric = metric
	_build()

func _build_history_row(record: Dictionary, index: int) -> Control:
	var newest: Dictionary = BenchmarkHistory.latest(_history)
	var previous := BenchmarkHistory.previous_of(_history, index)
	var line := Kit.make_panel(MenuStyle.with_alpha(Kit.COLOR_SURFACE_RAISED, 0.6),
		MenuStyle.with_alpha(Kit.COLOR_BORDER_SOFT, 0.35))
	line.name = "Run_%d" % index
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	line.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)

	var stars := BenchmarkVisuals.make_star_row(int(record.get("stars", 0)), 16, "RunStars")
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(stars)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var title := Kit.make_semibold_label(BenchmarkHistory.device_label(record), 11,
		Kit.COLOR_TEXT_BRIGHT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var meta := Kit.make_label("%s · %s · %s" % [
		BenchmarkHistory.time_label(int(record.get("at_unix", 0))),
		str(record.get("resolution", "?")),
		str(record.get("scenario", "?")),
	], 9, Kit.COLOR_TEXT_QUIET)
	meta.clip_text = true
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(meta)
	box.add_child(text)

	var numbers := VBoxContainer.new()
	numbers.add_theme_constant_override("separation", 0)
	var headline := Kit.make_semibold_label(_metric_readout(record, _history_metric), 12,
		Kit.COLOR_GOLD)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	numbers.add_child(headline)
	var delta := BenchmarkHistory.change_percent(previous, record, _history_metric)
	var delta_label := Kit.make_label(BenchmarkHistory.format_change(delta) if not previous.is_empty() \
		else ("newest" if record == newest else "—"), 9,
		BenchmarkVisuals.COLOR_FINE if delta >= 0.0 else BenchmarkVisuals.COLOR_BAD)
	delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	numbers.add_child(delta_label)
	box.add_child(numbers)
	return line

## The machine behind the numbers, one line at a time.
func _build_device_panel() -> PanelContainer:
	var panel := _panel("DevicePanel", MenuStyle.with_alpha(Kit.COLOR_BORDER_SOFT, 0.5), 13)
	var stack := _panel_stack(panel, 5)
	stack.add_child(Kit.make_kicker("Device dossier", 11))
	var rows := [
		[PixelIcon.Kind.SHIRT, "Device", "%s · %s" % [str(_result.get("device_model", "Unknown model")),
			str(_result.get("platform", "Unknown"))]],
		[PixelIcon.Kind.GEAR, "Operating system", str(_result.get("os_version", "Unknown version"))],
		[PixelIcon.Kind.CHIP, "CPU", "%s (%s cores)" % [str(_result.get("cpu_name", "Unknown CPU")),
			str(_result.get("cpu_cores", "?"))]],
		[PixelIcon.Kind.GPU, "GPU", str(_result.get("gpu_name", "Unknown"))],
		[PixelIcon.Kind.GPU, "Renderer", str(_result.get("renderer", "Unknown"))],
		[PixelIcon.Kind.PULSE, "Display", "%s · %s · VSync %s · cap %s" % [
			str(_result.get("display_server", "Unknown")), str(_result.get("resolution", "Unknown")),
			str(_result.get("vsync", "Unknown")), _fps_cap_text()]],
		[PixelIcon.Kind.MEMORY, "Game and engine", "Golf Tycoon %s · Godot %s · %s build" % [
			str(_result.get("game_version", "Unknown")), str(_result.get("engine_version", "Unknown")),
			str(_result.get("build_type", "Unknown"))]],
		[PixelIcon.Kind.TROPHY, "Benchmark", "%s · %.1f s frame sample · %.1f s GPU test" % [
			_benchmark_version(), float(_result.get("frame_sample_seconds", 0.0)),
			float(_result.get("gpu_sample_seconds", 0.0))]],
	]
	for row in rows:
		stack.add_child(_build_detail_row(int(row[0]), str(row[1]), str(row[2])))
	var privacy := Kit.make_label("Everything here stays on this machine. Copying a report puts device details on the clipboard; nothing is uploaded.",
		9, Kit.COLOR_TEXT_QUIET)
	privacy.name = "PrivacyNote"
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(privacy)
	return panel

## One dossier line: the sprite and the caption on the first line, the value
## wrapped underneath it. The value is the only wrapping text in the row, and
## it sits in a VBox rather than beside the caption, so it measures against the
## panel's real width instead of reporting a one-pixel-wide minimum.
func _build_detail_row(icon_kind: int, caption: String, value: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 7)
	var icon := Kit.make_sprite(icon_kind, 14, MenuStyle.ACCENT_UTILITY)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var label := Kit.make_kicker(caption, 9)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	row.add_child(head)
	var value_label := Kit.make_semibold_label(value, 10, Kit.COLOR_TEXT_SECONDARY)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value_label)
	return row

## A titled, padded panel in the screen's pixel frame.
func _panel(panel_name: String, border: Color, pad: int) -> PanelContainer:
	var panel := Kit.make_panel(Kit.COLOR_SURFACE, border)
	panel.name = panel_name
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, pad)
	panel.add_child(margin)
	return panel

## The VBox a panel's contents go in, inside its margins.
func _panel_stack(panel: PanelContainer, separation: int) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", separation)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(panel.get_child(0) as MarginContainer).add_child(stack)
	return stack

# =============================================================================
# RUNNING THE TEST
# =============================================================================

## The one run there is: reached from Main Menu Settings, Run Benchmark asks
## Main to close this screen and start the course tour, which prepares its own
## throwaway course and builds every test course of the suite on it. Main
## reopens this screen on the finished report. Away from the Main Menu -
## or without a tour on offer - nothing runs, and the screen says where it
## is allowed instead.
func _start_run() -> void:
	if not _can_run():
		_status_text = BENCHMARK_GATE_TEXT
		_refresh_actions()
		return
	_status_text = BENCHMARK_STARTING_TEXT
	_refresh_actions()
	tour_requested.emit(CourseBenchmarkScenarios.SUITE_FULL)

func _copy_report() -> void:
	var report := str(_result.get("report_text", ""))
	if report.is_empty():
		return
	if not _write_clipboard(report):
		_status_text = "This window has no clipboard to copy into. The report stays on this machine."
		_refresh_actions()
		return
	_status_text = "Report copied to the clipboard. It carries device details; nothing was uploaded."
	_refresh_actions()

## Put `text` on the clipboard, reporting whether there was one to use.
func _write_clipboard(text: String) -> bool:
	if clipboard_writer.is_valid():
		clipboard_writer.call(text)
		return true
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	DisplayServer.clipboard_set(text)
	return true

func _clear_history() -> void:
	BenchmarkHistory.clear()
	_history = []
	_status_text = "The past runs are forgotten. A finished tour lands here again as soon as one ends."
	_build()

## Whether the screen may start a run: reached from Main Menu Settings
## (`benchmarks_allowed`) and with the tour on offer (`tour_available`).
## Everything else on the screen - the report, the shelf, copying - is
## reading, and stays available wherever the screen was opened from.
func _can_run() -> bool:
	return benchmarks_allowed and tour_available

## The line under the action bar when nothing has just happened: the gate
## away from the Main Menu, an invitation to run where it is allowed, or
## the newest report's own verdict.
func _default_status_text() -> String:
	if not _can_run():
		return BENCHMARK_GATE_TEXT
	if not _result.is_empty():
		return _completed_status_text()
	return BENCHMARK_READY_TEXT

func _completed_status_text() -> String:
	var score := _score()
	return "%s · %d/100 · %s. Copy the report to compare devices; nothing is uploaded." % [
		str(score.get("tier", "Unrated")), int(round(float(score.get("overall", 0.0)))),
		str(score.get("verdict", "")),
	]

# =============================================================================
# REPORT ACCESS
# =============================================================================

func _score() -> Dictionary:
	if _result.is_empty():
		return PerformanceBenchmark.score_result({})
	if not _result.has("score"):
		return PerformanceBenchmark.score_result(_result)
	return _result["score"]

func _frame() -> Dictionary:
	return _result.get("frame", {})

func _gpu() -> Dictionary:
	return _result.get("gpu", {})

func _engine() -> Dictionary:
	return _result.get("engine", {})

func _memory() -> Dictionary:
	return _result.get("memory", {})

func _context() -> Dictionary:
	return _result.get("context", {})

## The frame series the oscilloscope draws, tolerant of reports from before
## the series was kept.
func _frame_series() -> Array[float]:
	var series: Array[float] = []
	for sample in _frame().get("series_ms", []):
		series.append(float(sample))
	return series

func _benchmark_version() -> String:
	var version := str(_result.get("benchmark_version", ""))
	return version if not version.is_empty() else PerformanceBenchmark.BENCHMARK_VERSION

func _fps_cap_text() -> String:
	var cap := int(_result.get("max_fps", 0))
	return "unlimited" if cap <= 0 else "%d FPS" % cap

func _metric_name(metric: String) -> String:
	match metric:
		METRIC_OVERALL: return "Overall score"
		METRIC_FPS: return "Average frame rate"
		METRIC_CPU: return "Script CPU throughput"
		_: return "GPU fill rate"

func _metric_short(metric: String) -> String:
	match metric:
		METRIC_OVERALL: return "Score"
		METRIC_FPS: return "FPS"
		METRIC_CPU: return "CPU"
		_: return "GPU"

## The shelf chart's values for the picked metric. Script throughput reads in
## thousands, so a phone and a workstation share an axis without the label
## running off the bar.
func _history_chart_values() -> Array[float]:
	var values := BenchmarkHistory.series_of(_history, _history_metric)
	if _history_metric != METRIC_CPU:
		return values
	var thousands: Array[float] = []
	for value in values:
		thousands.append(value / 1000.0)
	return thousands

func _metric_unit() -> String:
	return "K" if _history_metric == METRIC_CPU else ""

func _metric_readout(record: Dictionary, metric: String) -> String:
	match metric:
		METRIC_OVERALL:
			return "%d/100" % int(round(BenchmarkHistory.metric_of(record, metric)))
		METRIC_FPS:
			return "%.0f FPS" % BenchmarkHistory.metric_of(record, metric)
		METRIC_CPU:
			return PerformanceBenchmark.format_integer(
				int(BenchmarkHistory.metric_of(record, metric)))
		_:
			return "%.0f MPix/s" % BenchmarkHistory.metric_of(record, metric)
