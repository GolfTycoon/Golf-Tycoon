extends Control
class_name BottomControlDock
## Fixed-footprint quarter wheel. Plain Control children keep circles round;
## the toolbar takes the remaining width and scrolls its content, not the HUD.
const WIDTH := 218.0
const SECTION_SIZES := [84.0, 74.0, 64.0]
const SECTION_POSITIONS := [Vector2(8, 0), Vector2(99, 18), Vector2(144, 104)]
var section_buttons: Array[PixelCircleButton] = []
var _current_section: int = 0
var _section_open: bool = true

func setup(toolbar: TerrainToolbar) -> void:
	custom_minimum_size = Vector2(WIDTH, UIConstants.BOTTOM_BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in TerrainToolbar.SECTION_TITLES.size():
		var button := PixelCircleButton.new()
		button.name = TerrainToolbar.SECTION_TITLES[i] + "Button"
		button.diameter = SECTION_SIZES[i]
		button.toggle_mode = true
		button.caption = TerrainToolbar.SECTION_TITLES[i]
		button.glyph = button.caption.to_lower()
		button.accent = TerrainToolbar.SECTION_COLORS[i]
		button.accessibility_name = button.caption
		button.tooltip_text = "Open %s tools" % button.caption
		button.position = SECTION_POSITIONS[i]
		button.pressed.connect(toolbar.toggle_section.bind(i))
		add_child(button)
		section_buttons.append(button)
	toolbar.section_changed.connect(_sync_section)
	toolbar.section_visibility_changed.connect(_sync_visibility)
	_sync_section(toolbar.current_section)
	_sync_visibility(toolbar.visible)

	for i in ["MenuBtn", "FeedBtn", "InspectBtn"].size():
		var button := get_node(["MenuBtn", "FeedBtn", "InspectBtn"][i]) as Control
		button.position = Vector2(8 + i * 36, 88)
		button.size = Vector2(32, 32)
	var rotate := get_node("RotateViewControls") as HBoxContainer
	rotate.position = Vector2(8, 122)
	rotate.size = Vector2(104, 32)
	rotate.add_theme_constant_override("separation", 2)
	# Keep the heading readable between the arrows, without spending a whole
	# extra button's width on the old needle.
	rotate.get_node("OrientationNeedle").hide()
	var heading := rotate.get_node("OrientationLabel") as Label
	heading.custom_minimum_size.x = 36
	heading.add_theme_font_override("font", PixelCircleButton.FONT)
	var speed := get_node("SpeedControls") as HBoxContainer
	speed.position = Vector2(8, 156)
	speed.size = Vector2(104, 32)
	speed.add_theme_constant_override("separation", 4)

func _sync_section(section: int) -> void:
	_current_section = section
	for i in section_buttons.size():
		section_buttons[i].active = i == section and _section_open
		section_buttons[i].set_pressed_no_signal(i == section and _section_open)

## A hidden section lights no button, so the dock shows nothing as open.
func _sync_visibility(open: bool) -> void:
	_section_open = open
	_sync_section(_current_section)
