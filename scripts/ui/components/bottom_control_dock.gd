extends Control
class_name BottomControlDock
## Fixed-footprint quarter wheel. Plain Control children keep circles round;
## the toolbar takes the remaining width and scrolls its content, not the HUD.
## The utility circles fill the space below Build and beside Golfers, growing
## with the taller dock on compact/touch layouts. Behind them all,
## DockArcBackdrop paints a mown quarter-green fan cut to the arc the circles
## describe, its rim trim in the open section's colour - the straight bottom
## bar now only backs the shelf to this dock's right (see main.gd).

const WIDTH := 218.0
const TOUCH_WIDTH := 220.0
const SECTION_SIZES := [84.0, 74.0, 64.0]
const SECTION_POSITIONS := [Vector2(8, 0), Vector2(99, 18), Vector2(144, 104)]
const DESKTOP_UTILITY_SIZE := 52.0
const TOUCH_UTILITY_SIZE := 64.0
const UTILITY_SIZE_STEP := 4.0
const DESKTOP_UTILITY_POSITIONS := [Vector2(8, 88), Vector2(70, 96), Vector2(92, 144)]
const TOUCH_UTILITY_POSITIONS := [Vector2(8, 92), Vector2(80, 106), Vector2(104, 174)]
const UTILITY_BOTTOM := 2.0
var section_buttons: Array[PixelCircleButton] = []
var _current_section: int = 0
var _section_open: bool = true
## The fan-shaped backdrop behind the medallions, cut around their arc
## (see DockArcBackdrop). It is this control's first child, so every
## circle the dock adds later lands on top of it.
var _backdrop: DockArcBackdrop = null

func _ready() -> void:
	_backdrop = DockArcBackdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	move_child(_backdrop, 0)

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

	# Echo the section buttons' left-to-right descending arc, including their
	# gently decreasing diameters. A plain Control keeps Pause and Play free
	# to follow the curve instead of forcing them onto a horizontal row.
	var positions := TOUCH_UTILITY_POSITIONS if touch_layout else DESKTOP_UTILITY_POSITIONS
	var utility_paths := ["MenuBtn", "SpeedControls/PauseBtn", "SpeedControls/SpeedBtn"]
	var speed := get_node_or_null("SpeedControls") as Control
	if speed:
		speed.position = Vector2.ZERO
		speed.size = custom_minimum_size
	var inner_circles: Array = []
	for i in utility_paths.size():
		var button := get_node_or_null(utility_paths[i]) as PixelCircleButton
		if button:
			_size_utility_button(button, utility_size - i * UTILITY_SIZE_STEP)
			button.position = positions[i]
			inner_circles.append(_circle_of(button))

	# Shape the backdrop's fan around the circles as they now stand: the
	# rim curves around the section medallions, the utilities echo inside.
	# Pause and Speed sit under SpeedControls, which the loop above keeps
	# at this control's origin, so their positions are already local here.
	if _backdrop:
		var outer_circles: Array = []
		for button in section_buttons:
			outer_circles.append(_circle_of(button))
		_backdrop.set_circles(outer_circles, inner_circles)

## A medallion as the backdrop needs it: centre and radius, packed.
static func _circle_of(button: Control) -> Vector3:
	return Vector3(button.position.x + button.size.x * 0.5,
			button.position.y + button.size.y * 0.5, button.size.x * 0.5)

func _size_utility_button(button: PixelCircleButton, utility_size: float) -> void:
	button.diameter = utility_size
	button.custom_minimum_size = Vector2.ONE * utility_size
	button.size = Vector2.ONE * utility_size
	button.queue_redraw()

func _sync_section(section: int) -> void:
	_current_section = section
	for i in section_buttons.size():
		section_buttons[i].active = i == section and _section_open
		section_buttons[i].set_pressed_no_signal(i == section and _section_open)
	# The backdrop's rim wears the open section's colour; with no section
	# open it falls back to the bar's sage, like the straight bar it replaces.
	if _backdrop:
		if _section_open and section >= 0 and section < TerrainToolbar.SECTION_COLORS.size():
			_backdrop.accent = TerrainToolbar.SECTION_COLORS[section]
		else:
			_backdrop.accent = DockArcBackdrop.FALLBACK_ACCENT

## The Club tab's Feed card is only on screen while Manage is open on Club,
## so the Manage button carries the unread count the rest of the time.
func _sync_feed_unread(count: int) -> void:
	if section_buttons.size() > TerrainToolbar.Section.MANAGE:
		section_buttons[TerrainToolbar.Section.MANAGE].notification_count = count

## A hidden section lights no button, so the dock shows nothing as open.
func _sync_visibility(open: bool) -> void:
	_section_open = open
	_sync_section(_current_section)
