extends Control
class_name ConfirmDialog
## ConfirmDialog - Modal confirmation dialog for destructive actions
##
## Shows a message with Confirm and Cancel buttons. Used for quit
## confirmations and other actions that could lose progress.
##
## The dialogue is a full-screen modal, so it is drawn above whatever opened it
## (a pause menu entry, the World Map's Reset World, a course-map delete) and
## takes every pointer event: TouchInput only turns a finger into a click when
## the control under it belongs to the dialogue, even over a native touch
## surface such as the globe (see TouchInput.owns_native_touch).
##
## On a small window the panel shrinks to the space a modal may use, the
## message wraps, and the question scrolls when it still does not fit while the
## two answers stay pinned at the bottom, so Confirm and Cancel are always
## reachable by mouse, touch, keyboard and controller alike.

signal confirmed
signal cancelled

const PANEL_WIDTH := 380.0
const COMPACT_PANEL_WIDTH := 300.0
const BUTTON_SIZE := Vector2(140, 38)
const TOUCH_BUTTON_HEIGHT := 44.0

var _message_text: String = ""
var _confirm_text: String = "Confirm"
var _cancel_text: String = "Cancel"
var _confirm_color: Color = UIConstants.COLOR_DANGER

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null
var _text_box: VBoxContainer = null
var _buttons: HBoxContainer = null

func _init(message: String = "", confirm_text: String = "Confirm", cancel_text: String = "Cancel", confirm_color: Color = UIConstants.COLOR_DANGER) -> void:
	_message_text = message
	_confirm_text = confirm_text
	_cancel_text = cancel_text
	_confirm_color = confirm_color

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_fit_to_view.call_deferred()
	resized.connect(_fit_to_view)
	if has_node("/root/Screen"):
		Screen.changed.connect(func(_size: Vector2, _scale: float) -> void: _fit_to_view())

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _build_ui() -> void:
	# Semi-transparent overlay
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var compact := has_node("/root/Screen") and Screen.uses_touch_layout()
	var margin_h := 16 if compact else 24

	var panel = PanelContainer.new()
	panel.name = "ConfirmPanel"
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.98)
	style.border_color = UIConstants.COLOR_WARNING
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH if not compact else COMPACT_PANEL_WIDTH, 0)
	_panel = panel
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox = vbox
	panel.add_child(vbox)

	# Only the question scrolls on a short window. The answers stay put at the
	# bottom of the panel, so Confirm and Cancel can always be tapped or
	# focused — even when the message is longer than the screen is tall.
	var scroll = ScrollContainer.new()
	scroll.name = "ConfirmScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = scroll
	vbox.add_child(scroll)

	var text_box = VBoxContainer.new()
	text_box.name = "ConfirmQuestion"
	text_box.add_theme_constant_override("separation", 16)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_box = text_box
	scroll.add_child(text_box)

	# Warning icon + title
	var title = Label.new()
	title.text = "Are you sure?"
	title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_LG)
	title.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_box.add_child(title)

	# Message
	var message = Label.new()
	message.text = _message_text
	message.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	message.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrapping is driven by the panel's width, so the text fits whatever window
	# the dialogue opens in instead of forcing the panel wider than the screen.
	message.autowrap_mode = TextServer.AUTOWRAP_WORD
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_child(message)

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.name = "ConfirmButtons"
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons = btn_row
	vbox.add_child(btn_row)

	var cancel_btn = _make_button(_cancel_text, compact)
	cancel_btn.name = "CancelButton"
	cancel_btn.pressed.connect(_on_cancel)
	# Destructive confirmations default to the safe answer.
	cancel_btn.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	btn_row.add_child(cancel_btn)

	var confirm_btn = _make_button(_confirm_text, compact)
	confirm_btn.name = "ConfirmButton"
	confirm_btn.add_theme_color_override("font_color", _confirm_color)
	confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(confirm_btn)

## A button that is comfortable to tap on a touch screen: tall, and sharing the
## row's width instead of holding a fixed 140px that a narrow panel cannot give.
func _make_button(text: String, compact: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	if compact:
		button.custom_minimum_size = Vector2(0, TOUCH_BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		button.custom_minimum_size = BUTTON_SIZE
	return button

## The width the dialogue wants when there is room for it.
func _dialogue_width() -> float:
	return COMPACT_PANEL_WIDTH if has_node("/root/Screen") and Screen.uses_touch_layout() else PANEL_WIDTH


## Keep the dialogue fully on screen: clamp the panel to the space a modal may
## use, wrap the message to the resulting width, and scroll the question if it
## is still too tall. Called after the first layout pass and whenever the window
## or the screen metrics change.
func _fit_to_view() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_vbox) \
			or not is_instance_valid(_scroll) or not is_instance_valid(_text_box) \
			or not is_instance_valid(_buttons):
		return
	var view := get_viewport().get_visible_rect().size
	var available := view - Vector2(24.0, 24.0)
	if has_node("/root/Screen"):
		available = Screen.modal_panel_rect().size
	available = available.max(Vector2(160.0, 120.0))

	var style := _panel.get_theme_stylebox("panel") as StyleBox
	var vertical_padding := 0.0
	var horizontal_padding := 0.0
	if style != null:
		vertical_padding = style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
		horizontal_padding = style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)

	var buttons_height := _buttons.get_combined_minimum_size().y
	var separation := float(_vbox.get_theme_constant("separation"))
	var text_size := _text_box.get_combined_minimum_size()
	var natural_size := Vector2(
		maxf(text_size.x, _buttons.get_combined_minimum_size().x),
		text_size.y + separation + buttons_height)
	var width := minf(maxf(_dialogue_width(), natural_size.x + horizontal_padding), available.x)
	var natural_height := natural_size.y + vertical_padding

	# The buttons keep their natural height; the question gets whatever is
	# left, scrolling if that is less than it needs.
	var height := minf(natural_height, available.y)
	var text_height := clampf(height - vertical_padding - separation - buttons_height, 0.0, text_size.y)
	var needs_scroll := text_size.y > text_height + 1.0
	_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO if needs_scroll
		else ScrollContainer.SCROLL_MODE_DISABLED)
	_scroll.custom_minimum_size = Vector2(0.0, text_height)
	_panel.custom_minimum_size = Vector2(width, height)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()

func _on_confirm() -> void:
	confirmed.emit()
	queue_free()

func _on_cancel() -> void:
	cancelled.emit()
	queue_free()
