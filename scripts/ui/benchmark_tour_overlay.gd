extends CanvasLayer
class_name BenchmarkTourOverlay
## BenchmarkTourOverlay - the banner the course benchmark tour runs under.
##
## The whole point of the tour is watching each benchmark course being built
## and played, so this overlay never covers the course: a slim banner across
## the top names the course and the phase being measured, a slimmer bar
## across the bottom carries the live frame rate and the cancel button, and
## everything between them is the game itself (the root control ignores the
## mouse, so the course shows through untouched).

signal cancel_requested

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")
const BAR_BG := Color(0.012, 0.045, 0.032, 0.92)
const GOLD := Color("e5c57c")
const TEXT := Color("f2ead2")
const TEXT_QUIET := Color("b9c4a8")

var _title_label: Label = null
var _scenario_label: Label = null
var _phase_label: Label = null
var _live_label: Label = null
var _progress: ProgressBar = null
var _cancel_button: Button = null

func _ready() -> void:
	name = "BenchmarkTourOverlay"
	# Above the HUD, below the GPU fill test's canvas (layer 100) so the
	# device check that ends a tour can still paint over everything.
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	var root := Control.new()
	root.name = "TourRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := _bar("TourTopBar")
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	top.offset_bottom = 74
	root.add_child(top)
	var top_rows := VBoxContainer.new()
	top_rows.add_theme_constant_override("separation", 1)
	top.add_child(top_rows)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	top_rows.add_child(title_row)
	_title_label = _label("COURSE BENCHMARK TOUR", 15, GOLD, TITLE_FONT)
	_title_label.name = "TourTitle"
	title_row.add_child(_title_label)
	_scenario_label = _label("", 13, TEXT, TITLE_FONT)
	_scenario_label.name = "TourScenario"
	_scenario_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scenario_label.clip_text = true
	_scenario_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(_scenario_label)
	_cancel_button = Button.new()
	_cancel_button.name = "CancelTourButton"
	_cancel_button.text = "Cancel (Esc)"
	_cancel_button.tooltip_text = "Stop the tour and put your course back exactly as it was."
	_cancel_button.custom_minimum_size = Vector2(118, 30)
	_cancel_button.add_theme_font_override("font", BODY_FONT)
	_cancel_button.add_theme_font_size_override("font_size", 12)
	_cancel_button.pressed.connect(func(): cancel_requested.emit())
	title_row.add_child(_cancel_button)
	_phase_label = _label("Preparing...", 12, TEXT_QUIET, BODY_FONT)
	_phase_label.name = "TourPhase"
	_phase_label.clip_text = true
	_phase_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_rows.add_child(_phase_label)

	var bottom := _bar("TourBottomBar")
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 10
	bottom.offset_right = -10
	bottom.offset_top = -46
	bottom.offset_bottom = -8
	root.add_child(bottom)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	bottom.add_child(bottom_row)
	_live_label = _label("", 12, TEXT, BODY_FONT)
	_live_label.name = "TourLive"
	_live_label.custom_minimum_size.x = 330
	bottom_row.add_child(_live_label)
	_progress = ProgressBar.new()
	_progress.name = "TourProgress"
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.custom_minimum_size.y = 10
	bottom_row.add_child(_progress)

func _bar(bar_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = bar_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = BAR_BG
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## One status update from the tour: which course, which phase, how far
## through the suite, and the live read-out for the bottom bar.
func update_status(status: Dictionary) -> void:
	if _title_label == null:
		return
	var suite := str(status.get("suite_name", ""))
	_title_label.text = "COURSE BENCHMARK TOUR" if suite.is_empty() \
		else "COURSE BENCHMARK TOUR · %s" % suite.to_upper()
	var index := int(status.get("scenario_index", 0))
	var total := int(status.get("scenario_total", 0))
	var scenario_name := str(status.get("scenario_name", ""))
	_scenario_label.text = "Course %d/%d — %s" % [index + 1, total, scenario_name] \
		if total > 0 else scenario_name
	var description := str(status.get("description", ""))
	var phase := str(status.get("phase", ""))
	_phase_label.text = "%s    %s" % [phase, description] if not description.is_empty() \
		else phase
	_live_label.text = str(status.get("live", ""))
	_progress.value = clampf(float(status.get("fraction", 0.0)), 0.0, 1.0)
