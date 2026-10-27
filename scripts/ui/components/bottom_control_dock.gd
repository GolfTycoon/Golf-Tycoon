extends Control
class_name BottomControlDock
## Fixed-footprint quarter wheel. Plain Control children keep circles round;
## the toolbar takes the remaining width and scrolls its content, not the HUD.
## On compact/touch layouts the small utility buttons reflow to a taller dock
## and grow to a comfortable 44px target.

const WIDTH := 218.0
const TOUCH_WIDTH := 220.0
const SECTION_SIZES := [84.0, 74.0, 64.0]
const SECTION_POSITIONS := [Vector2(8, 0), Vector2(99, 18), Vector2(144, 104)]
const DESKTOP_UTILITY_SIZE := 32.0
const TOUCH_UTILITY_SIZE := float(UIConstants.TOUCH_TARGET_SIZE)
var section_buttons: Array[PixelCircleButton] = []
var _current_section: int = 0
var _section_open: bool = true

func setup(toolbar: TerrainToolbar) -> void:
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
	# The Feed card lives on the Club tab now, so its unread badge rides on
	# the Manage section button to stay visible from every section.
	toolbar.feed_unread_count_changed.connect(_sync_feed_unread)
	_sync_section(toolbar.current_section)
	_sync_visibility(toolbar.visible)
	_sync_feed_unread(toolbar.feed_unread_count)
	apply_screen()

## Reflow the fixed controls for the current viewport. The terrain shelf already
## scrolls horizontally, so the dock only changes its own width/height and the
## touch targets; it does not squeeze or hide any game action.
func apply_screen() -> void:
	var touch_layout := Screen.uses_touch_layout()
	var utility_size := TOUCH_UTILITY_SIZE if touch_layout else DESKTOP_UTILITY_SIZE
	var bar_height := Screen.bottom_bar_height()
	custom_minimum_size = Vector2(TOUCH_WIDTH if touch_layout else WIDTH, bar_height)

	for i in section_buttons.size():
		var button := section_buttons[i]
		button.diameter = SECTION_SIZES[i]
		button.custom_minimum_size = Vector2.ONE * SECTION_SIZES[i]
		button.position = SECTION_POSITIONS[i]
		button.size = Vector2.ONE * SECTION_SIZES[i]
		button.queue_redraw()

	var utility_names := ["MenuBtn", "InspectBtn"]
	var utility_y := 96.0 if touch_layout else 88.0
	var utility_gap := 2.0 if touch_layout else 4.0
	for i in utility_names.size():
		var button := get_node_or_null(utility_names[i]) as Control
		if button == null:
			continue
		button.custom_minimum_size = Vector2.ONE * utility_size
		button.size = Vector2.ONE * utility_size
		button.position = Vector2(8.0 + i * (utility_size + utility_gap), utility_y)
		if button is PixelCircleButton:
			button.diameter = utility_size
			button.queue_redraw()

	var rotate := get_node_or_null("RotateViewControls") as HBoxContainer
	if rotate:
		rotate.position = Vector2(8.0, 142.0 if touch_layout else 122.0)
		var rotate_size := Vector2(128.0 if touch_layout else 104.0, utility_size)
		rotate.custom_minimum_size = rotate_size
		rotate.size = rotate_size
		rotate.add_theme_constant_override("separation", 2)
		# Keep the heading readable between the arrows, without spending a whole
		# extra button's width on the old needle.
		var needle := rotate.get_node_or_null("OrientationNeedle")
		if needle:
			needle.hide()
		var heading := rotate.get_node_or_null("OrientationLabel") as Label
		if heading:
			heading.custom_minimum_size = Vector2(36, 0)
			heading.add_theme_font_override("font", PixelCircleButton.FONT)
		for child in rotate.get_children():
			if child is RotateViewButton:
				child.custom_minimum_size = Vector2.ONE * utility_size
				child.size = Vector2.ONE * utility_size
				child.queue_redraw()
		# Shrink only after the children have adopted the new target size; the
		# HBoxContainer otherwise holds on to its previous touch minimum.
		rotate.custom_minimum_size = rotate_size
		rotate.size = rotate_size

	var speed := get_node_or_null("SpeedControls") as HBoxContainer
	if speed:
		speed.position = Vector2(8.0, 188.0 if touch_layout else 156.0)
		var speed_size := Vector2(140.0 if touch_layout else 104.0, utility_size)
		speed.custom_minimum_size = speed_size
		speed.size = speed_size
		speed.add_theme_constant_override("separation", 4)
		for child in speed.get_children():
			if child is PixelCircleButton:
				child.custom_minimum_size = Vector2.ONE * utility_size
				child.size = Vector2.ONE * utility_size
				child.diameter = utility_size
				child.queue_redraw()
		# Apply again after lowering child minima so the row can contract on desktop.
		speed.custom_minimum_size = speed_size
		speed.size = speed_size

func _sync_section(section: int) -> void:
	_current_section = section
	for i in section_buttons.size():
		section_buttons[i].active = i == section and _section_open
		section_buttons[i].set_pressed_no_signal(i == section and _section_open)

## The Club tab's Feed card is only on screen while Manage is open on Club,
## so the Manage button carries the unread count the rest of the time.
func _sync_feed_unread(count: int) -> void:
	if section_buttons.size() > TerrainToolbar.Section.MANAGE:
		section_buttons[TerrainToolbar.Section.MANAGE].notification_count = count

## A hidden section lights no button, so the dock shows nothing as open.
func _sync_visibility(open: bool) -> void:
	_section_open = open
	_sync_section(_current_section)
