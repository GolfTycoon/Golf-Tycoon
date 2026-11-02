extends Control
class_name PortraitHUD
## Portrait-only composition around the live game controls.
##
## The desktop fan and its shelf are moved into a full-width tray and a fixed
## five-button thumb rail; Menu moves to the top-left of the header. They are
## the very same controls, not copies: focus, bindings, unread badges, tool
## state and signals survive rotation untouched. A compact ledger replaces the
## two competing top corners. The middle remains a touch surface, with a small
## camera rail and an optional course overview.

const INK := Color("091f19")
const FIELD := Color("15392d")
const GOLD := Color("e5c57c")
const CREAM := Color("f4edd9")
const FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

var _main: Node
var _header: Panel
var _nav: Panel
var _tray: Panel
var _context: Button
var _camera_rail: HBoxContainer
var _map_button: PixelCircleButton
var _menu_button: PixelCircleButton
var _menu_home_parent: Node
var _menu_home_index: int = -1
var _active := false
var _hud_visible := true
var _layout_busy := false

func setup(main: Node) -> void:
	_main = main
	name = "PortraitHUD"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header = _panel("ClubhouseLedger", INK, GOLD)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)
	_tray = _panel("ToolTray", FIELD, GOLD)
	add_child(_tray)
	_nav = _panel("ThumbRail", INK, Color("63715a"))
	add_child(_nav)
	_context = Button.new()
	_context.name = "OpenToolsButton"
	_context.add_theme_font_override("font", FONT)
	_context.add_theme_font_size_override("font_size", 14)
	_context.custom_minimum_size.y = 44
	_context.accessibility_name = "Open tool tray"
	_context.clip_text = true
	_context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_context.pressed.connect(_open_tools)
	PixelButtonStyle.paint_primary(_context, GOLD)
	add_child(_context)
	_build_camera_rail()
	_menu_button = _main.left_controls.get_node("MenuBtn") as PixelCircleButton
	_menu_home_parent = _menu_button.get_parent()
	_menu_home_index = _menu_button.get_index()
	_main.terrain_toolbar.section_visibility_changed.connect(_on_tray_visibility)
	_main.terrain_toolbar.section_changed.connect(func(_section: int): _sync_context())
	_main.terrain_toolbar.page_changed.connect(func(_tab: int): _sync_context())
	hide()

func _panel(title: String, fill: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.name = title
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(border, 0.65)
	style.border_width_top = 2
	style.border_width_bottom = 0
	style.border_width_left = 0
	style.border_width_right = 0
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _build_camera_rail() -> void:
	_camera_rail = HBoxContainer.new()
	_camera_rail.name = "CameraRail"
	_camera_rail.add_theme_constant_override("separation", 4)
	add_child(_camera_rail)
	_camera_action("RotateLeft", "rotate_ccw", "Rotate view left", _main._on_view_rotate_ccw)
	_camera_action("RotateRight", "rotate_cw", "Rotate view right", _main._on_view_rotate_cw)
	_camera_action("ZoomOut", "minus", "Zoom out", func(): _main.camera.zoom_by_factor(1.0 / 1.2, Screen.window_size * 0.5))
	_camera_action("ZoomIn", "plus", "Zoom in", func(): _main.camera.zoom_by_factor(1.2, Screen.window_size * 0.5))
	_map_button = _camera_action("OverviewButton", "maps", "Show course overview", _toggle_map)
	_map_button.toggle_mode = true

func _camera_action(title: String, glyph: String, tip: String, action: Callable) -> PixelCircleButton:
	var button := PixelCircleButton.new()
	button.name = title
	button.glyph = glyph
	button.diameter = 44
	button.tooltip_text = tip
	button.accessibility_name = tip
	button.pressed.connect(action)
	_camera_rail.add_child(button)
	return button

func _toggle_map() -> void:
	Screen.set_portrait_map_open(not Screen.portrait_map_open)

func _open_tools() -> void:
	_main.terrain_toolbar.expand_section()
	Screen.set_portrait_tools_open(true)

func _on_tray_visibility(open: bool) -> void:
	if _active and not _layout_busy:
		Screen.set_portrait_tools_open(open)

func set_hud_visible(shown: bool) -> void:
	_hud_visible = shown
	visible = shown and _active

func apply_layout() -> void:
	if _main == null or _layout_busy:
		return
	_layout_busy = true
	var portrait := Screen.uses_portrait_hud()
	if portrait != _active:
		_active = portrait
		if portrait:
			_main.left_controls.reparent(_nav)
			_main.terrain_toolbar.reparent(_tray)
			_menu_button.reparent(_header)
		else:
			# Restore Menu before the dock reflows so its desktop arc sees the
			# original child list, order and signal wiring.
			_menu_button.reparent(_menu_home_parent)
			_menu_home_parent.move_child(_menu_button, _menu_home_index)
			_main.left_controls.reparent(_main.bottom_bar)
			_main.terrain_toolbar.reparent(_main.bottom_bar)
			_main.bottom_bar.move_child(_main.left_controls, 0)
	visible = portrait and _hud_visible
	_main.bottom_bar.visible = not portrait and _hud_visible
	if not portrait:
		_layout_busy = false
		return
	var view := Screen.window_size
	var left := Screen.safe_insets.x
	var width := view.x - left - Screen.safe_insets.z
	_header.position = Vector2.ZERO
	_header.size = Vector2(view.x, Screen.portrait_header_height())
	# Menu owns the top-left corner; the course identity strip shifts right by
	# one touch slot (see CourseLocationBanner) so neither covers the other.
	_menu_button.diameter = float(UIConstants.TOUCH_TARGET_SIZE)
	_menu_button.custom_minimum_size = Vector2.ONE * float(UIConstants.TOUCH_TARGET_SIZE)
	_menu_button.size = Vector2.ONE * float(UIConstants.TOUCH_TARGET_SIZE)
	_menu_button.position = Vector2(left + 8.0, Screen.safe_insets.y + 6.0)
	_menu_button.caption = "Menu"
	_menu_button.queue_redraw()
	var nav_height := Screen.portrait_nav_height()
	_nav.position = Vector2(0, view.y - nav_height)
	_nav.size = Vector2(view.x, nav_height)
	_main.left_controls.position = Vector2(left, 0)
	_main.left_controls.size = Vector2(width, nav_height)
	var tray_height := Screen.portrait_tray_height()
	_tray.position = Vector2(left, view.y - nav_height - tray_height)
	_tray.size = Vector2(width, tray_height)
	_main.terrain_toolbar.position = Vector2.ZERO
	_main.terrain_toolbar.size = _tray.size
	# Preserve the user's collapsed tray across rotation; section visibility is
	# the toolbar's existing source of truth, including keyboard/tool reveals.
	if Screen.portrait_tools_open:
		_main.terrain_toolbar.expand_section()
	else:
		_main.terrain_toolbar.collapse_section()
	_tray.visible = Screen.portrait_tools_open
	_context.visible = not Screen.portrait_tools_open
	_context.position = Vector2(left + 8, view.y - nav_height - 44)
	_context.size = Vector2(width - 16, 44)
	_sync_context()
	var course := Screen.portrait_course_rect()
	_camera_rail.position = Vector2(course.position.x, course.end.y - 44)
	_camera_rail.size = Vector2(236, 44)
	_map_button.set_pressed_no_signal(Screen.portrait_map_open)
	_map_button.active = Screen.portrait_map_open
	_map_button.accessibility_name = ("Hide" if Screen.portrait_map_open else "Show") + " course overview"
	_layout_busy = false

func _sync_context() -> void:
	if _main == null or _context == null:
		return
	var toolbar: TerrainToolbar = _main.terrain_toolbar
	_context.text = "%s / %s   ·   Open tools" % [TerrainToolbar.SECTION_TITLES[toolbar.current_section], TerrainToolbar.TAB_TITLES[toolbar.current_tab]]
	_context.tooltip_text = "Open the %s tool tray. Tap the active section below to put it away." % TerrainToolbar.SECTION_TITLES[toolbar.current_section]
