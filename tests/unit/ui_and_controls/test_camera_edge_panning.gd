extends GameTest
## Screen-edge camera panning (the Settings → Controls → Camera toggle).
##
## Hovering an edge of the window pans the course camera, but only when the
## pointer is really on the screen and is the mouse: a camera that has never
## seen a pointer event (a headless run, a window that opens with the OS cursor
## parked in a corner), a pointer that has left the window, a pointer over a
## HUD control and a finger on a touch screen all leave the camera still. The
## preference behind it is persisted in settings.cfg, and an older settings
## file without the key keeps panning on.

# Lets a test pretend a HUD control owns the pointer (headless runs never
# report a hovered control, because there is no real mouse).
class _ProbeCamera extends IsometricCamera:
	var fake_hovered: Control = null

	func _get_hovered_control() -> Control:
		return fake_hovered

## The viewport the camera lives in; only its size matters to the edge zones.
const VIEW := Vector2(1000, 600)
const MARGIN := 24.0
const START := Vector2(1000, 1000)

var camera: _ProbeCamera = null


func before_each() -> void:
	super()
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_edge_pan_enabled(true)
	camera = _ProbeCamera.new()
	add_child_autofree(camera)
	camera.set_zoom_level(1.0, true)
	camera.focus_on(START, true)


func after_each() -> void:
	GameManager.set_edge_pan_enabled(true)
	super()


## Put the pointer where a mouse motion event would: this also marks it as
## being inside the window, which is what edge panning waits for.
func _place_pointer(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.relative = Vector2(1, 1)
	camera._input(motion)


## A point in the camera's real viewport (headless runs use a small window)
## next to the named edge.
func _edge_point(side: String) -> Vector2:
	var size := camera.get_viewport_rect().size
	var middle := size / 2.0
	match side:
		"left":
			return Vector2(2.0, middle.y)
		"right":
			return Vector2(size.x - 2.0, middle.y)
		"top":
			return Vector2(middle.x, 2.0)
		"bottom":
			return Vector2(middle.x, size.y - 2.0)
		"corner":
			return Vector2(2.0, 2.0)
	return middle


func _pan(seconds: float = 0.25) -> Vector2:
	camera._handle_keyboard_input(seconds)
	return camera._target_position - START


# ---------------------------------------------------------------------------
# The edge zones
# ---------------------------------------------------------------------------

func test_the_edge_zones_step_toward_each_edge() -> void:
	var size := VIEW
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(MARGIN - 1.0, 300), size, MARGIN), Vector2(-1, 0),
		"near the left edge pans left")
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(size.x - MARGIN + 1.0, 300), size, MARGIN), Vector2(1, 0),
		"near the right edge pans right")
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(500, MARGIN - 1.0), size, MARGIN), Vector2(0, -1),
		"near the top edge pans up")
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(500, size.y - MARGIN + 1.0), size, MARGIN), Vector2(0, 1),
		"near the bottom edge pans down")
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(1, 1), size, MARGIN), Vector2(-1, -1),
		"a corner pans on both axes")


func test_the_middle_of_the_screen_and_the_edge_boundary_do_not_pan() -> void:
	assert_eq(IsometricCamera.edge_pan_direction(VIEW / 2.0, VIEW, MARGIN), Vector2.ZERO)
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(MARGIN, 300), VIEW, MARGIN), Vector2.ZERO,
		"a pointer exactly on the margin is outside the edge zone")


func test_an_absent_or_disabled_margin_never_pans() -> void:
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(-5, 300), VIEW, MARGIN), Vector2.ZERO,
		"a pointer outside the window pans nothing")
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(VIEW.x + 5, 300), VIEW, MARGIN), Vector2.ZERO)
	assert_eq(IsometricCamera.edge_pan_direction(Vector2(0, 300), VIEW, 0.0), Vector2.ZERO,
		"a zero margin has no edge zone")


# ---------------------------------------------------------------------------
# Panning
# ---------------------------------------------------------------------------

func test_hovering_an_edge_pans_the_camera() -> void:
	_place_pointer(_edge_point("left"))
	var moved := _pan()
	# 800 px/s for a quarter second at zoom 1.0 is 200 world units.
	assert_almost_eq(moved.x, -200.0, 1.0, "the left edge pans left")
	assert_almost_eq(moved.y, 0.0, 0.001, "and does not drift vertically")


func test_a_corner_pans_diagonally_at_the_same_speed() -> void:
	_place_pointer(_edge_point("corner"))
	var moved := _pan()
	assert_almost_eq(moved.length(), 200.0, 1.0, "a corner normalizes to the edge speed")
	assert_almost_eq(moved.x, moved.y, 0.001, "a square corner pans evenly on both axes")


func test_edge_panning_waits_for_a_pointer_that_is_really_on_screen() -> void:
	# The camera's default position (0, 0) is not a pointer parked in the
	# corner: until a mouse event arrives, there is nothing to edge pan from.
	assert_eq(_pan(), Vector2.ZERO, "no pointer has reached the camera yet")

	_place_pointer(_edge_point("middle"))
	assert_eq(_pan(), Vector2.ZERO, "a pointer in the middle of the screen does not pan")

	_place_pointer(_edge_point("left"))
	assert_lt(_pan().x, 0.0, "once the pointer reaches an edge it pans")


func test_a_pointer_that_leaves_the_window_stops_panning() -> void:
	_place_pointer(_edge_point("left"))
	get_window().mouse_exited.emit()
	assert_eq(_pan(), Vector2.ZERO, "a pointer outside the window must not keep scrolling")

	get_window().mouse_entered.emit()
	assert_lt(_pan().x, 0.0, "coming back into the window lets the edge pan again")


func test_a_control_at_the_edge_owns_the_pointer() -> void:
	camera.fake_hovered = Control.new()
	_place_pointer(_edge_point("left"))
	assert_eq(_pan(), Vector2.ZERO, "a HUD panel at the edge is not a camera edge")
	camera.fake_hovered.free()
	camera.fake_hovered = null
	assert_lt(_pan().x, 0.0, "with no control under it the edge pans again")


func test_dragging_the_camera_suppresses_edge_panning() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(500, 300)
	camera.handle_input_event(press)
	assert_true(camera.is_dragging(), "precondition: the middle button starts a drag")

	_place_pointer(_edge_point("left"))
	assert_eq(_pan(), Vector2.ZERO, "the drag owns the pointer")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	release.position = Vector2(500, 300)
	camera.handle_input_event(release)
	assert_lt(_pan().x, 0.0, "releasing the drag hands the edge back")


func test_touch_input_never_edge_pans() -> void:
	_place_pointer(_edge_point("left"))
	InputManager.device = InputManager.Device.TOUCH
	assert_eq(_pan(), Vector2.ZERO, "a finger at the edge has no cursor to pan with")

	InputManager.device = InputManager.Device.MOUSE
	assert_lt(_pan().x, 0.0, "moving the mouse again brings edge panning back")


# ---------------------------------------------------------------------------
# The preference
# ---------------------------------------------------------------------------

func test_the_setting_switches_a_live_camera_off_and_on() -> void:
	_place_pointer(_edge_point("left"))
	GameManager.set_edge_pan_enabled(false)
	assert_false(camera.edge_pan_enabled, "the live camera follows the setting")
	assert_eq(_pan(), Vector2.ZERO, "with the setting off the edge stays still")

	GameManager.set_edge_pan_enabled(true)
	assert_true(camera.edge_pan_enabled)
	assert_lt(_pan().x, 0.0, "with the setting on the edge pans again")


func test_the_settings_file_stores_and_defaults_the_preference() -> void:
	var off := ConfigFile.new()
	off.set_value("camera", "edge_pan_enabled", false)
	SaveManager._apply_camera_settings(off)
	assert_false(GameManager.edge_pan_enabled, "a stored off preference disables edge panning")

	var on := ConfigFile.new()
	on.set_value("camera", "edge_pan_enabled", true)
	SaveManager._apply_camera_settings(on)
	assert_true(GameManager.edge_pan_enabled)

	var older := ConfigFile.new()
	older.set_value("camera", "min_zoom", 0.6)
	GameManager.set_edge_pan_enabled(false)
	SaveManager._apply_camera_settings(older)
	assert_true(GameManager.edge_pan_enabled,
		"a settings file from before the preference existed keeps edge panning on")
