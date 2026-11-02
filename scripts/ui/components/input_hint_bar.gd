extends PanelContainer
class_name InputHintBar
## InputHintBar - a compact strip of the controls that work right now.
##
## The same screen is driven by five input methods, and the prompts people
## expect are different for each. This bar follows InputManager's active
## device and the screen on top:
##
##  * gamepad - A/B/D-pad/Start on a screen, or the course controls in play;
##  * keyboard - Enter/Esc/arrows/Tab while a screen or panel is open;
##  * touch - tap, drag and pinch reminders;
##  * mouse - hidden (the pointer is its own explanation).
##
## It never takes input (MOUSE_FILTER_IGNORE) and sits centred just above the
## bottom bar, clear of the minimap, the status column and the shelves.

const BAR_HEIGHT := 26.0
const COL_BG := Color(0.024, 0.075, 0.059, 0.94)
const COL_BORDER := Color("718f69")
const COL_TEXT := Color("d8cfae")
const COL_ACCENT := Color("e5c47c")

var _label: Label = null
var _last_text := ""
var _last_width := -1.0
var _last_view := Vector2.ZERO


func _ready() -> void:
	name = "InputHintBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 80
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.name = "HintText"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_label.add_theme_color_override("font_color", COL_TEXT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false
	if has_node("/root/InputManager"):
		InputManager.device_changed.connect(_on_device_changed)
		InputManager.focus_scope_changed.connect(_on_scope_changed)
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _exit_tree() -> void:
	if has_node("/root/InputManager"):
		if InputManager.device_changed.is_connected(_on_device_changed):
			InputManager.device_changed.disconnect(_on_device_changed)
		if InputManager.focus_scope_changed.is_connected(_on_scope_changed):
			InputManager.focus_scope_changed.disconnect(_on_scope_changed)
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)


func _on_device_changed(_device: int) -> void:
	_refresh()


func _on_scope_changed(_scope: Control) -> void:
	_refresh()


func _on_screen_changed(_size: Vector2, _world_scale: float) -> void:
	_layout()


func _refresh() -> void:
	if not is_inside_tree() or not has_node("/root/InputManager"):
		return
	var device: int = InputManager.device
	var in_screen: bool = InputManager.has_visible_scope()
	var gamepad: bool = device == InputManager.Device.GAMEPAD
	var touch: bool = device == InputManager.Device.TOUCH
	var keyboard: bool = device == InputManager.Device.KEYBOARD
	var should_show := gamepad or keyboard or (touch and in_screen)
	if not should_show:
		visible = false
		return
	var hints: Array[String] = _hints_for(device, in_screen)
	if hints.is_empty():
		visible = false
		return
	var text := "   ".join(hints)
	if text != _last_text:
		_last_text = text
		_label.text = text
		_last_width = -1.0
	visible = true
	_layout()


func _hints_for(device: int, in_screen: bool) -> Array[String]:
	if in_screen:
		match device:
			InputManager.Device.GAMEPAD:
				return ["A  Select", "B  Back", "D-pad  Navigate", "Right stick  Pointer",
					"LB/RB  Tabs", "Start  Pause"]
			InputManager.Device.KEYBOARD:
				return ["Enter  Select", "Esc  Back", "Arrows  Navigate", "Tab  Next"]
			InputManager.Device.TOUCH:
				return ["Tap  Select", "Drag  Scroll"]
			_:
				return []
	match device:
		InputManager.Device.GAMEPAD:
			return ["Left stick  Pan", "Right stick  Pointer", "A  Click", "B  Cancel",
				"X/Y  Rotate", "LT/RT  Zoom", "View  UI", "Start  Pause"]
		InputManager.Device.KEYBOARD:
			return ["WASD  Pan", "Shift+Arrows  Pointer", "Arrows  HUD", "Enter  Click", "Esc  Back", "F1  Help"]
		_:
			return []


func _layout() -> void:
	if not is_inside_tree():
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	if has_node("/root/Screen"):
		view = Screen.window_size
	var bar_height: float = get_combined_minimum_size().y
	# Centred inside the full-width strip so the panel hugs its text.
	var text_width: float = _label.get_combined_minimum_size().x + 22.0
	if text_width == _last_width and size.y == bar_height and view == _last_view:
		return
	_last_width = text_width
	_last_view = view
	size = Vector2(minf(view.x - 16.0, text_width), bar_height)
	position = Vector2((view.x - size.x) * 0.5, view.y - _bottom_clearance() - bar_height - 4.0)


func _bottom_clearance() -> float:
	if has_node("/root/Screen"):
		return Screen.bottom_bar_height() + (48.0 if Screen.uses_portrait_hud() else 0.0)
	return 0.0
