extends Control
class_name PauseMenu
## PauseMenu - Full-screen pause overlay with game options
##
## Triggered by Escape key. Provides Resume, Save, Load, Settings, Quit to Menu,
## and Quit to Desktop options. Dims the game behind it.
##
## The World Map is not here: it lives on the Club tab, where the company's
## sites are managed.
##
## The simulation is frozen while this menu is open, but the player can still
## look around the course: pointer events that land on the dimmed backdrop
## (not on the menu panel) are forwarded to the isometric camera, which runs
## on wall-clock time.
##
## The menu fits the window it opens in: on a short window (a phone held
## sideways, a small browser frame) the buttons scroll inside the panel instead
## of running off the bottom of the screen, where they could not be tapped.

signal resume_requested
signal save_requested
signal load_requested
signal settings_requested
signal quit_to_menu_requested
signal quit_to_desktop_requested

## Set by Main so camera controls work while the game is paused behind the
## menu. Null when the camera is unavailable (forwarding is then skipped).
var camera: IsometricCamera = null

var _bg: ColorRect = null
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null
var _hint: Label = null
var _info: Label = null
var _title: Label = null
var _spacer: Control = null
var _buttons: Array[Button] = []
var _compact := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("touch_camera_backdrop")
	_build_ui()
	_fit_to_view.call_deferred()
	# Re-fit when the window changes shape (rotation, a browser resize).
	resized.connect(_fit_to_view)
	if has_node("/root/Screen"):
		Screen.changed.connect(func(_size: Vector2, _scale: float) -> void: _fit_to_view())

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _build_ui() -> void:
	# Semi-transparent dark overlay
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = bg
	add_child(bg)

	# Center container for the menu panel
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Menu panel
	var panel = PanelContainer.new()
	var compact := has_node("/root/Screen") and Screen.uses_touch_layout()
	_compact = compact
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.1, 0.95)
	style.border_color = UIConstants.COLOR_PRIMARY
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	var margin_h := 16 if compact else 30
	var margin_v := 16 if compact else 24
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(_menu_width(), 0)
	_panel = panel
	center.add_child(panel)

	# The buttons live in a ScrollContainer: on a screen too short for the
	# whole menu it scrolls (touch drags scroll it, see TouchInput), so Quit to
	# Menu and Quit to Desktop never sit off the bottom where nothing can reach
	# them.
	var scroll = ScrollContainer.new()
	scroll.name = "PauseScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll = scroll
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox = vbox
	scroll.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Game Paused"
	title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XL)
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = title
	vbox.add_child(title)

	# Separator
	vbox.add_child(HSeparator.new())

	# Course info
	var info_label = Label.new()
	info_label.text = "%s - Day %d" % [GameManager.course_name, GameManager.current_day]
	info_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	info_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrapped, so a long course name never forces the panel wider than a phone.
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info = info_label
	vbox.add_child(info_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_spacer = spacer
	vbox.add_child(spacer)

	# Menu buttons. Resume is the default focus, so A/Enter continues the game.
	var resume := _add_menu_button(vbox, "Resume", _on_resume_pressed)
	resume.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	_add_menu_button(vbox, "Save Game", _on_save_pressed)
	_add_menu_button(vbox, "Load Game", _on_load_pressed)
	_add_menu_button(vbox, "Settings", _on_settings_pressed)

	# Separator before destructive actions
	vbox.add_child(HSeparator.new())

	_add_menu_button(vbox, "Quit to Menu", _on_quit_to_menu_pressed, UIConstants.COLOR_WARNING)
	_add_menu_button(vbox, "Quit to Desktop", _on_quit_to_desktop_pressed, UIConstants.COLOR_DANGER)

	# Hint at bottom (touch-specific gesture help on touch screens)
	var hint = Label.new()
	if has_node("/root/Screen") and Screen.uses_touch_layout():
		hint.text = "Look around while paused: drag to pan, pinch to zoom\nTap Resume to continue"
	else:
		hint.text = "Look around while paused: middle-mouse drag or WASD to pan, scroll to zoom\nPress Escape to resume"
	hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint = hint
	vbox.add_child(hint)

## Keep the whole menu on screen: the panel is clamped to the space a modal may
## use and its content scrolls when it does not fit. Called after the first
## layout pass, and again whenever the window or the screen metrics change, so
## the menu is right in every window it can open in.
func _fit_to_view() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_vbox) or not is_instance_valid(_scroll):
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

	# A short window (a phone held sideways) gets tighter spacing and loses the
	# gesture footnote, so every option — Quit to Menu and Quit to Desktop
	# included — is on screen without scrolling.
	var short_window := available.y < 420.0
	_vbox.add_theme_constant_override("separation", 6 if short_window else 12)
	if is_instance_valid(_hint):
		_hint.visible = not short_window
	# On a short window the course line and its spacer give way first: the
	# options themselves are what the player opened the menu for.
	if is_instance_valid(_info):
		_info.visible = not short_window
	if is_instance_valid(_spacer):
		_spacer.visible = not short_window
	if is_instance_valid(_title):
		_title.add_theme_font_size_override("font_size",
			UIConstants.FONT_SIZE_LG if short_window else UIConstants.FONT_SIZE_XL)
	if _compact:
		for button in _buttons:
			if is_instance_valid(button):
				button.custom_minimum_size.y = 40 if short_window else 44

	var natural_size := _vbox.get_combined_minimum_size()
	var width := minf(maxf(_menu_width(), natural_size.x + horizontal_padding), available.x)
	var natural_height := natural_size.y + vertical_padding
	var height := minf(natural_height, available.y)
	var needs_scroll := natural_height > height + 1.0
	_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO if needs_scroll
		else ScrollContainer.SCROLL_MODE_DISABLED)
	_panel.custom_minimum_size = Vector2(width, height)


## The width the menu wants when there is room for it: a little narrower in the
## touch layout, where it may share the window with a small phone's edges.
func _menu_width() -> float:
	return 280.0 if has_node("/root/Screen") and Screen.uses_touch_layout() else 320.0


func _add_menu_button(parent: VBoxContainer, text: String, callback: Callable, text_color: Color = Color.WHITE) -> Button:
	var btn = Button.new()
	btn.text = text
	var compact := has_node("/root/Screen") and Screen.uses_touch_layout()
	if compact:
		# Full-width, tall targets: easy to tap on touch screens.
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		btn.custom_minimum_size = Vector2(260, 40)
	_buttons.append(btn)
	btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	if text_color != Color.WHITE:
		btn.add_theme_color_override("font_color", text_color)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_resume_pressed()
			get_viewport().set_input_as_handled()
		return
	# Controller B (the cancel action) resumes, like Escape.
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		_on_resume_pressed()
		get_viewport().set_input_as_handled()
		return

	# The game is paused behind this menu, but the player should still be
	# able to look around the course. This overlay is full-screen with
	# MOUSE_FILTER_STOP, so pointer events never reach the camera's
	# _unhandled_input — forward the ones that are over the dimmed backdrop
	# (not over the menu panel) to the camera instead.
	if camera != null and _is_camera_event(event):
		camera.handle_input_event(event, true)

## True when a pointer event should be forwarded to the camera: the pointer
## is over the dimmed backdrop rather than an interactive part of the menu,
## or the camera is already mid-drag (so the drag keeps flowing — including
## the release — even if the pointer moves over the panel).
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
	if hovered == null:
		return false
	return not _is_inside_panel(hovered)

## The control under the pointer. Split out so tests can simulate hover
## state (headless runs have no real mouse, so the viewport never reports a
## hovered control).
func _get_hovered_control() -> Control:
	return get_viewport().gui_get_hovered_control()

func _is_inside_panel(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		if node == _panel:
			return true
		node = node.get_parent()
	return false

## The pause overlay blocks normal GUI input across the screen, but its dimmed
## backdrop still allows camera gestures. TouchInput checks this before it
## decides whether a drag belongs to the UI.
func allows_touch_camera_gesture(screen_pos: Vector2) -> bool:
	if camera == null or not is_visible_in_tree():
		return false
	if _panel == null:
		return true
	var local_pos := _panel.get_global_transform_with_canvas().affine_inverse() * screen_pos
	return not Rect2(Vector2.ZERO, _panel.size).has_point(local_pos)

func _on_resume_pressed() -> void:
	resume_requested.emit()

func _on_save_pressed() -> void:
	save_requested.emit()

func _on_load_pressed() -> void:
	load_requested.emit()

func _on_settings_pressed() -> void:
	settings_requested.emit()

func _on_quit_to_menu_pressed() -> void:
	quit_to_menu_requested.emit()

func _on_quit_to_desktop_pressed() -> void:
	quit_to_desktop_requested.emit()
