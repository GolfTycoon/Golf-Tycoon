extends GameTest
## Touch input (the TouchInput autoload): taps, drags, pinches and two-finger
## pans translated into the mouse and camera actions the game already handles.
##
## Real touch events are pushed through the normal input pipeline; a sentinel
## node in the test scene records the synthetic mouse events that come out.

class EventSink:
	extends Node
	var mouse_events: Array = []
	var motion_events: Array = []
	var touch_events: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			mouse_events.append(event)
		elif event is InputEventMouseMotion:
			motion_events.append(event)
		elif event is InputEventScreenTouch or event is InputEventScreenDrag:
			touch_events.append(event)

var touch: Node  # the TouchInput autoload
var sink: EventSink
var camera: IsometricCamera

func before_each() -> void:
	super()
	touch = get_node("/root/TouchInput")
	touch.camera = null
	touch.paint_mode_provider = func() -> bool: return false
	# Clear any gesture state left over from a previous test.
	touch._touches.clear()
	touch._two_finger = {}
	touch._gesture = touch.Gesture.NONE
	touch._suppressed_single = false
	sink = autofree(EventSink.new())
	add_child(sink)
	# GameManager mode gates camera panning (no panning on the main menu).
	GameManager.current_mode = GameManager.GameMode.PLAYING

func after_each() -> void:
	touch.camera = null
	super()

func _push_touch(pressed: bool, index: int, pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	get_viewport().push_input(ev, true)

func _push_drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	get_viewport().push_input(ev, true)

func _settle(frames: int = 3) -> void:
	for i in frames:
		await process_frames(1)

func _left_buttons() -> Array:
	var out: Array = []
	for ev in sink.mouse_events:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			out.append(ev)
	return out

func test_tap_synthesizes_a_left_click_at_the_tap_position() -> void:
	var down := Vector2(512, 300)
	var up := down + Vector2(3, 2)
	_push_touch(true, 0, down)
	_push_touch(false, 0, up)
	await _settle()
	var clicks := _left_buttons()
	# press + release at the release position (a tap moved <12px)
	assert_eq(clicks.size(), 2)
	if clicks.size() == 2:
		assert_true(clicks[0].pressed)
		assert_false(clicks[1].pressed)
		assert_eq(clicks[0].position, up)
		assert_eq(clicks[1].position, up)
	# The synthesized click must also reach the sentinel's unhandled input
	# (a preceding mouse motion sets hover state).
	assert_gte(sink.motion_events.size(), 1)

func test_drag_beyond_the_tap_distance_is_not_a_tap() -> void:
	# Panning is disabled (no camera wired up), so a clear drag must produce
	# neither a click nor any camera movement.
	_push_touch(true, 0, Vector2(500, 500))
	_push_drag(0, Vector2(600, 500))
	_push_touch(false, 0, Vector2(600, 500))
	await _settle()
	assert_eq(sink.mouse_events.size(), 0)

func test_single_finger_drag_pans_the_camera() -> void:
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera.set_zoom_level(1.0, true)
	camera._target_position = Vector2(100, 100)
	touch.camera = camera

	_push_touch(true, 0, Vector2(500, 500))
	_push_drag(0, Vector2(550, 510))  # crosses the 12px tap threshold -> panning
	_push_drag(0, Vector2(600, 550))
	_push_touch(false, 0, Vector2(600, 550))
	await _settle()
	# The first threshold-crossing drag now moves the camera too, so the full
	# finger travel (100, 50) is reflected in the inverse camera movement.
	assert_eq(camera._target_position, Vector2(0, 50))
	# A drag must not synthesize mouse clicks.
	assert_eq(sink.mouse_events.size(), 0)

func test_single_finger_drag_paints_when_a_tool_is_active() -> void:
	touch.paint_mode_provider = func() -> bool: return true
	_push_touch(true, 0, Vector2(500, 500))
	_push_drag(0, Vector2(520, 510))  # crosses threshold -> paint stroke starts
	_push_drag(0, Vector2(540, 530))
	_push_touch(false, 0, Vector2(540, 530))
	await _settle()
	var presses := 0
	var releases := 0
	for ev in sink.mouse_events:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				presses += 1
			else:
				releases += 1
	assert_eq(presses, 1, "paint stroke opens with a synthetic mouse press")
	assert_eq(releases, 1, "paint stroke ends with a synthetic mouse release")
	assert_gte(sink.motion_events.size(), 1, "finger motion becomes mouse motion")

func test_touch_drag_scrolls_a_scroll_container_without_painting_or_panning() -> void:
	touch.paint_mode_provider = func() -> bool: return true
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera.set_zoom_level(1.0, true)
	camera._target_position = Vector2(100, 100)
	touch.camera = camera

	var ui: Control = autofree(Control.new())
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(100, 100)
	scroll.size = Vector2(220, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(scroll)
	var shelf := Control.new()
	shelf.custom_minimum_size = Vector2(640, 100)
	scroll.add_child(shelf)
	await _settle(2)
	assert_gt(scroll.get_h_scroll_bar().max_value, scroll.get_h_scroll_bar().page,
		"The shelf has horizontal overflow to scroll")

	var before := camera._target_position
	var start := Vector2(200, 150)
	_push_touch(true, 0, start)
	_push_drag(0, start - Vector2(90, 0))
	_push_touch(false, 0, start - Vector2(90, 0))
	await _settle()
	assert_gt(scroll.scroll_horizontal, 0, "Dragging left scrolls the shelf to the right")
	assert_eq(camera._target_position, before, "The same gesture never pans the course")
	assert_eq(sink.mouse_events.size(), 0, "Scrolling never starts an accidental paint stroke")

func test_touch_drag_on_a_button_does_not_activate_it_or_paint_behind_it() -> void:
	touch.paint_mode_provider = func() -> bool: return true
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera._target_position = Vector2(100, 100)
	touch.camera = camera

	var ui: Control = autofree(Control.new())
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var button := Button.new()
	button.text = "Touch me"
	button.position = Vector2(100, 100)
	button.size = Vector2(120, 60)
	ui.add_child(button)
	var activations := []
	button.pressed.connect(func(): activations.append(true))

	_push_touch(true, 0, Vector2(150, 130))
	_push_drag(0, Vector2(210, 160))
	_push_touch(false, 0, Vector2(210, 160))
	await _settle()
	assert_true(activations.is_empty(), "A drag that leaves a button cancels its tap")
	assert_eq(camera._target_position, Vector2(100, 100), "A UI drag cannot pan the course")
	assert_eq(sink.mouse_events.size(), 0, "A UI drag cannot paint the course")

func test_canceled_touch_releases_a_paint_stroke_without_clicking() -> void:
	touch.paint_mode_provider = func() -> bool: return true
	_push_touch(true, 0, Vector2(500, 500))
	_push_drag(0, Vector2(530, 510))
	var cancel := InputEventScreenTouch.new()
	cancel.index = 0
	cancel.position = Vector2(530, 510)
	cancel.pressed = false
	cancel.canceled = true
	get_viewport().push_input(cancel, true)
	await _settle()

	var presses := 0
	var releases := 0
	for ev in sink.mouse_events:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				presses += 1
			else:
				releases += 1
	assert_eq(presses, 1, "The drag began one paint stroke")
	assert_eq(releases, 1, "Cancellation releases the synthetic mouse button")
	assert_true(touch._touches.is_empty(), "Canceled pointers are removed from gesture state")
	assert_eq(touch._gesture, touch.Gesture.NONE, "Cancellation resets the gesture")

func test_two_finger_drag_zooms_the_camera() -> void:
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera.set_zoom_level(1.0, true)
	camera._target_position = Vector2(0, 0)
	touch.camera = camera

	# Fingers 200px apart, drag 100px further apart -> x1.5 zoom, midpoint
	# (500, 400) stays put.
	_push_touch(true, 0, Vector2(400, 400))
	_push_touch(true, 1, Vector2(600, 400))
	_push_drag(0, Vector2(350, 400))
	_push_drag(1, Vector2(650, 400))
	_push_touch(false, 0, Vector2(350, 400))
	_push_touch(false, 1, Vector2(650, 400))
	await _settle()
	assert_almost_eq(camera._target_zoom, 1.5, 0.01)
	# No taps/clicks should come out of a real pinch.
	assert_eq(sink.mouse_events.size(), 0)

func test_two_finger_pan_moves_camera_with_midpoint() -> void:
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera.set_zoom_level(1.0, true)
	camera._target_position = Vector2(100, 100)
	touch.camera = camera

	# Finger distance stays 200 the whole time (no zoom); the midpoint
	# slides (500,400) -> (525,410) -> (550,420), i.e. (50, 20) total.
	_push_touch(true, 0, Vector2(400, 400))
	_push_touch(true, 1, Vector2(600, 400))
	_push_drag(0, Vector2(425, 410))
	_push_drag(1, Vector2(625, 410))
	_push_drag(0, Vector2(450, 420))
	_push_drag(1, Vector2(650, 420))
	_push_touch(false, 0, Vector2(450, 420))
	_push_touch(false, 1, Vector2(650, 420))
	await _settle()
	# The pan is the midpoint delta (50, 20). Between the interleaved
	# per-finger events the finger distance wobbles briefly, which applies
	# tiny compensating zoom-anchor shifts, so allow a small residual.
	assert_almost_eq(camera._target_position.x, 50.0, 5.0)
	assert_almost_eq(camera._target_position.y, 80.0, 5.0)
	assert_almost_eq(camera._target_zoom, 1.0, 0.05)

func test_two_finger_tap_synthesizes_a_right_click() -> void:
	_push_touch(true, 0, Vector2(400, 400))
	_push_touch(true, 1, Vector2(600, 400))
	_push_touch(false, 0, Vector2(400, 400))
	_push_touch(false, 1, Vector2(600, 400))
	await _settle()
	var rights: Array = []
	for ev in sink.mouse_events:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			rights.append(ev)
	assert_eq(rights.size(), 2)
	if rights.size() == 2:
		assert_true(rights[0].pressed)
		assert_false(rights[1].pressed)
		assert_eq(rights[0].position, Vector2(500, 400))

func test_second_finger_cancels_an_in_flight_paint_stroke() -> void:
	touch.paint_mode_provider = func() -> bool: return true
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera.set_zoom_level(1.0, true)
	camera._target_position = Vector2(100, 100)
	touch.camera = camera

	# Start painting...
	_push_touch(true, 0, Vector2(500, 500))
	_push_drag(0, Vector2(530, 510))
	# ...then a second finger joins: stroke must be released, camera takes
	# over. Both fingers then move together (distance stays 200, no zoom):
	# midpoint (630,510) -> (620,500), i.e. a (-10, -10) screen pan.
	_push_touch(true, 1, Vector2(730, 510))
	_push_drag(0, Vector2(520, 500))
	_push_drag(1, Vector2(720, 500))
	_push_touch(false, 0, Vector2(520, 500))
	_push_touch(false, 1, Vector2(720, 500))
	await _settle()
	var presses := 0
	var releases := 0
	for ev in sink.mouse_events:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				presses += 1
			else:
				releases += 1
	assert_eq(presses, 1)
	assert_eq(releases, 1, "joining finger must release the synthetic paint button")
	# The two-finger pan moved the camera by (-(-10), -(-10)) = (10, 10),
	# modulo the small zoom-anchor residual from the interleaved finger
	# events (same as the pure pan test).
	assert_almost_eq(camera._target_position.x, 110.0, 2.0)
	assert_almost_eq(camera._target_position.y, 110.0, 2.0)
	assert_almost_eq(camera._target_zoom, 1.0, 0.05)

func test_tap_on_main_menu_does_not_pan_the_camera() -> void:
	GameManager.current_mode = GameManager.GameMode.MAIN_MENU
	camera = autofree(IsometricCamera.new())
	add_child(camera)
	camera.set_zoom_level(1.0, true)
	camera._target_position = Vector2(100, 100)
	touch.camera = camera

	_push_touch(true, 0, Vector2(500, 500))
	_push_drag(0, Vector2(600, 500))
	_push_touch(false, 0, Vector2(600, 500))
	await _settle()
	assert_eq(camera._target_position, Vector2(100, 100))
	assert_eq(sink.mouse_events.size(), 0)
