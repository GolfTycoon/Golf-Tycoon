extends CanvasLayer
class_name FpsCounter
## A small, input-transparent readout shared by the title screen, menus and
## course. It samples rendered frames against the monotonic wall clock, not
## scaled game time, so pausing or speeding up the simulation does not change
## the measurement. Nothing is sampled while the counter is switched off.

const FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const EDGE_MARGIN := 8.0

var _root: Control
var _panel: PanelContainer
var _label: Label
var _enabled := false
var _refresh_choice := -1
var _sample_started_usec: int = 0
var _sample_frames: int = 0

func _ready() -> void:
	# Above the course and its screens, but below tooltips, the benchmark tour
	# banner and the GPU fill test. The latter must be able to cover the screen.
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	PerformanceSettings.fps_counter_changed.connect(_apply_settings)
	_apply_settings()

func _exit_tree() -> void:
	if PerformanceSettings.fps_counter_changed.is_connected(_apply_settings):
		PerformanceSettings.fps_counter_changed.disconnect(_apply_settings)

func _build() -> void:
	_root = Control.new()
	_root.name = "FpsCounterRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.name = "FpsPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.07, 0.05, 0.88)
	style.border_color = Color(0.50, 0.69, 0.54, 0.70)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	_label = Label.new()
	_label.name = "FpsLabel"
	_label.text = "-- FPS"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_color_override("font_color", Color("e7f3d6"))
	_panel.add_child(_label)
	_root.resized.connect(_place_counter)

func _apply_settings() -> void:
	var enabled: bool = PerformanceSettings.fps_counter_enabled
	var refresh: int = PerformanceSettings.fps_counter_refresh
	_label.add_theme_font_size_override("font_size", PerformanceSettings.fps_counter_font_size())
	_panel.visible = enabled
	set_process(enabled)
	if enabled and (not _enabled or refresh != _refresh_choice):
		_reset_sample(Time.get_ticks_usec())
	_enabled = enabled
	_refresh_choice = refresh
	_place_counter()

func _reset_sample(now_usec: int) -> void:
	_sample_started_usec = now_usec
	_sample_frames = 0
	_label.text = "-- FPS"

func _process(_delta: float) -> void:
	_sample_frame(Time.get_ticks_usec())

## Kept separate from _process so the averaging and refresh cadence can be
## tested with known timestamps, independently of the machine's frame rate.
func _sample_frame(now_usec: int) -> void:
	if now_usec < _sample_started_usec:
		_reset_sample(now_usec)
		return
	_sample_frames += 1
	var elapsed := float(now_usec - _sample_started_usec) / 1_000_000.0
	if elapsed < PerformanceSettings.fps_counter_refresh_interval():
		return
	_label.text = "%d FPS" % roundi(float(_sample_frames) / elapsed)
	_sample_started_usec = now_usec
	_sample_frames = 0
	_place_counter()

## Re-measure as the number of digits, font size or viewport changes. The
## selected edge stays pinned even when a new number is wider or narrower.
func _place_counter() -> void:
	var panel_size := _panel.get_combined_minimum_size()
	_panel.size = panel_size
	var available := (_root.size - panel_size).max(Vector2.ZERO)
	var x := EDGE_MARGIN
	var y := EDGE_MARGIN
	match PerformanceSettings.fps_counter_position:
		PerformanceSettings.FpsCounterPosition.TOP_CENTER:
			x = available.x / 2.0
		PerformanceSettings.FpsCounterPosition.TOP_RIGHT:
			x = available.x - EDGE_MARGIN
		PerformanceSettings.FpsCounterPosition.BOTTOM_LEFT:
			y = available.y - EDGE_MARGIN
		PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT:
			x = available.x - EDGE_MARGIN
			y = available.y - EDGE_MARGIN
	_panel.position = Vector2(clampf(x, 0.0, available.x), clampf(y, 0.0, available.y))
