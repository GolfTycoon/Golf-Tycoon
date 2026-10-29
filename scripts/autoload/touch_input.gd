extends Node
## TouchInput - Translates touch gestures into camera, UI-scroll and mouse actions (autoload).
##
## The engine's touch->mouse emulation is disabled (see project.godot), so
## this node is the single translator between touch input and the game:
##
##   * tap                  -> synthetic left mouse click (UI and world)
##   * one-finger drag      -> camera pan, terrain painting, or UI scrolling
##   * two-finger drag      -> camera pan (midpoint) + zoom (pinch distance)
##   * two-finger tap       -> synthetic right click (cancel / close menus)
##
## Touches that begin on controls are kept out of the course: drags scroll a
## ScrollContainer, while a drag on a button/card cancels the tap instead of
## accidentally panning or painting behind the UI. Desktop mouse input is
## completely unaffected.

## Set by the main scene (the isometric camera). Null disables camera gestures.
var camera: Camera2D = null
## Set by the main scene: func() -> bool, true while a tool is selected or
## a stroke is in progress (one-finger drags then paint instead of panning).
var paint_mode_provider: Callable = func() -> bool: return false

const TAP_DISTANCE := 12.0
const TAP_DURATION_MS := 400

enum Gesture { NONE, TAP_PENDING, PANNING, PAINTING, SCROLLING, UI_DRAG, SLIDING }

var _touches: Dictionary = {}  # index -> {pos, start, start_ms, over_ui, scroll}
var _gesture: int = Gesture.NONE
var _last_drag_pos: Vector2 = Vector2.ZERO
var _two_finger: Dictionary = {}
var _suppressed_single: bool = false  # a remaining finger after a multi-touch gesture
var _native_touch_indices: Dictionary = {}  # fingers owned by controls with custom touch handling

func _input(event: InputEvent) -> void:
	# Capture gestures before the GUI can swallow raw touch events. UI taps are
	# replayed as mouse clicks on release, while scrollable controls are moved
	# directly below. A few custom controls (the globe and minimap) own their
	# raw touch stream and are explicitly allowed through.
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			if not _native_touch_indices.is_empty() or _has_native_touch_target(touch_event.position):
				_native_touch_indices[touch_event.index] = true
				return
			_handle_screen_touch(touch_event)
			get_viewport().set_input_as_handled()
		elif _native_touch_indices.has(touch_event.index):
			_native_touch_indices.erase(touch_event.index)
			return
		else:
			_handle_screen_touch(touch_event)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if _native_touch_indices.has(drag_event.index) or not _native_touch_indices.is_empty():
			return
		_handle_screen_drag(drag_event)
		get_viewport().set_input_as_handled()

# =============================================================================
# GESTURE STATE MACHINE
# =============================================================================

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_pressed(event.index, event.position)
	elif event.canceled:
		_cancel_touch(event.index)
	else:
		_touch_released(event.index, event.position)

func _touch_pressed(index: int, pos: Vector2) -> void:
	var target := _touch_target_at(pos)
	_touches[index] = {
		"pos": pos,
		"start": pos,
		"start_ms": Time.get_ticks_msec(),
		"over_ui": bool(target.get("over_ui", false)),
		"scroll": target.get("scroll", null),
		"slider": target.get("slider", null),
	}
	_suppressed_single = false

	if _touches.size() == 2:
		# A second finger joined: cancel whatever the first finger was doing
		# (camera pan or a paint stroke) and enter two-finger camera mode. A
		# gesture that began on UI remains UI-owned; it must not move the world.
		_cancel_paint_stroke()
		_two_finger = _begin_two_finger_state()
		_gesture = Gesture.NONE
	elif _touches.size() == 1:
		var slider := _touches[index].get("slider") as Slider
		if is_instance_valid(slider) and slider.is_visible_in_tree():
			# A touch on a slider is a slide, not a tap: the finger owns the
			# value from the moment it lands (no mouse emulation involved).
			_gesture = Gesture.SLIDING
			_set_slider_from_touch(slider, pos)
		else:
			_gesture = Gesture.TAP_PENDING
		_last_drag_pos = pos
	else:
		# A third finger makes this a deliberate multi-touch gesture, not a tap.
		# The first two fingers continue to drive the camera, matching the
		# documented two-finger control while avoiding a false right-click.
		_two_finger["moved"] = true

func _touch_released(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var info: Dictionary = _touches[index]
	info["pos"] = pos
	_touches[index] = info

	if _two_finger.size() > 0 and _touches.size() >= 2:
		# Account for a final position supplied with release even when the OS did
		# not send a final drag event. This also prevents a moved pinch being
		# mistaken for a two-finger cancel tap.
		_track_two_finger()
		var was_exactly_two: bool = _touches.size() == 2
		var should_cancel: bool = was_exactly_two and _is_two_finger_tap()
		var cancel_position: Vector2 = _midpoint()
		var count_before_release := _touches.size()
		_touches.erase(index)

		if _touches.size() < 2:
			# The two-finger gesture ended. Only a quick, stationary pair on the
			# course maps to right-click; a pair over controls never cancels a tool.
			if should_cancel and not bool(_two_finger.get("blocked", false)):
				_synthesize_click(cancel_position, MOUSE_BUTTON_RIGHT)
			_two_finger = {}
			for remaining in _touches.values():
				remaining["start"] = remaining["pos"]
				remaining["start_ms"] = Time.get_ticks_msec()
			_suppressed_single = not _touches.is_empty()
			_gesture = Gesture.NONE
			return

		# If a third finger was lifted, rebase the two remaining fingers so the
		# camera does not jump when their midpoint/distance is recalculated.
		if count_before_release > 2:
			_rebase_two_finger_state()
		_gesture = Gesture.NONE
		return

	# A single finger may release a few pixels beyond its last drag event.
	# Apply that final movement, so short drags do not lose their last segment.
	if _touches.size() == 1:
		_process_single_touch_drag(info, pos)

	_touches.erase(index)
	if _touches.is_empty():
		_finish_single_touch(info, pos)
	else:
		_gesture = Gesture.NONE

func _cancel_touch(index: int) -> void:
	if not _touches.has(index):
		return
	# OS interruption / app switching must never leave a synthetic paint button
	# held down, or turn a canceled touch into a click.
	_cancel_paint_stroke()
	_touches.erase(index)
	if not _two_finger.is_empty():
		_two_finger["moved"] = true
	if _touches.is_empty():
		_two_finger = {}
		_gesture = Gesture.NONE
		_suppressed_single = false
	else:
		_two_finger = {}
		_gesture = Gesture.NONE
		_suppressed_single = true

func _finish_single_touch(info: Dictionary, pos: Vector2) -> void:
	var gesture: int = _gesture
	_gesture = Gesture.NONE
	if info.is_empty():
		return
	if gesture == Gesture.PAINTING:
		# End the stroke: release the synthetic mouse button.
		_synthesize_mouse_button(MOUSE_BUTTON_LEFT, false, pos)
		return
	if gesture == Gesture.SCROLLING or gesture == Gesture.UI_DRAG:
		return
	if gesture == Gesture.PANNING or gesture == Gesture.SLIDING:
		return
	if _suppressed_single:
		_suppressed_single = false
		return
	var elapsed: int = Time.get_ticks_msec() - int(info["start_ms"])
	if elapsed > TAP_DURATION_MS:
		return
	if pos.distance_to(Vector2(info["start"])) > TAP_DISTANCE:
		return
	# A genuine tap: click whatever is under the finger.
	_synthesize_click(pos, MOUSE_BUTTON_LEFT)

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var info: Dictionary = _touches[event.index]
	info["pos"] = event.position
	_touches[event.index] = info

	if _two_finger.size() > 0 and _touches.size() >= 2:
		# Two-finger camera control: pan with the midpoint, zoom with the
		# distance. This also keeps firing while a paint stroke was interrupted.
		_track_two_finger()
		return

	if _touches.size() == 1:
		_process_single_touch_drag(info, event.position)

func _process_single_touch_drag(info: Dictionary, pos: Vector2) -> void:
	var start: Vector2 = info["start"]
	var moved: float = pos.distance_to(start)

	if _gesture == Gesture.TAP_PENDING:
		if moved <= TAP_DISTANCE:
			return
		if bool(info.get("over_ui", false)):
			var scroll := info.get("scroll") as ScrollContainer
			var axis := _scroll_axis_for_gesture(scroll, pos - start) if is_instance_valid(scroll) else 0
			if axis != 0:
				_gesture = Gesture.SCROLLING
				info["scroll_axis"] = axis
				_scroll_by_drag(scroll, axis, pos - _last_drag_pos)
			else:
				# Dragging a button or card is not a world gesture. Don't activate
				# the control on release after the finger has moved away.
				_gesture = Gesture.UI_DRAG
		elif _is_paint_mode():
			_gesture = Gesture.PAINTING
			_synthesize_mouse_button(MOUSE_BUTTON_LEFT, true, start)
			# Paint the segment that crossed the drag threshold as well as later
			# motion, so a short touch stroke still reaches the finger's endpoint.
			_synthesize_mouse_motion(pos)
		elif _camera_panning_allowed():
			_gesture = Gesture.PANNING
			if camera:
				camera.pan_screen_offset(pos - _last_drag_pos)
		else:
			_gesture = Gesture.NONE  # e.g. main menu backdrop: do nothing
		_last_drag_pos = pos
		return

	match _gesture:
		Gesture.PAINTING:
			# Keep the synthetic mouse button pressed while the finger moves.
			_synthesize_mouse_motion(pos)
		Gesture.PANNING:
			if camera:
				camera.pan_screen_offset(pos - _last_drag_pos)
		Gesture.SCROLLING:
			var scroll := info.get("scroll") as ScrollContainer
			if is_instance_valid(scroll):
				_scroll_by_drag(scroll, int(info.get("scroll_axis", 0)), pos - _last_drag_pos)
		Gesture.SLIDING:
			var slider := info.get("slider") as Slider
			if is_instance_valid(slider):
				_set_slider_from_touch(slider, pos)
	_last_drag_pos = pos

func _begin_two_finger_state() -> Dictionary:
	var indices: Array = []
	for index in _touches.keys():
		indices.append(index)
		if indices.size() == 2:
			break
	var start_positions: Dictionary = {}
	for index in indices:
		start_positions[index] = Vector2(_touches[index]["pos"])
	var blocked := false
	for info in _touches.values():
		if bool(info.get("over_ui", false)):
			blocked = true
	return {
		"start_ms": Time.get_ticks_msec(),
		"mid_prev": _midpoint_for(indices),
		"dist_prev": _pinch_distance_for(indices),
		"moved": false,
		"blocked": blocked,
		"indices": indices,
		"start_positions": start_positions,
	}

func _rebase_two_finger_state() -> void:
	if _two_finger.is_empty():
		return
	var indices: Array = []
	for index in _touches.keys():
		indices.append(index)
		if indices.size() == 2:
			break
	var start_positions: Dictionary = {}
	for index in indices:
		start_positions[index] = Vector2(_touches[index]["pos"])
	_two_finger["indices"] = indices
	_two_finger["start_positions"] = start_positions
	_two_finger["mid_prev"] = _midpoint_for(indices)
	_two_finger["dist_prev"] = _pinch_distance_for(indices)
	_two_finger["moved"] = true

func _track_two_finger() -> void:
	if _two_finger.is_empty():
		return
	var indices: Array = _two_finger.get("indices", [])
	var mid: Vector2 = _midpoint_for(indices)
	var dist: float = _pinch_distance_for(indices)
	var d_mid: Vector2 = mid - Vector2(_two_finger["mid_prev"])
	var prev_dist: float = float(_two_finger["dist_prev"])
	var d_dist: float = dist - prev_dist
	if d_mid.length() > TAP_DISTANCE or absf(d_dist) > TAP_DISTANCE or _two_finger_fingers_moved():
		_two_finger["moved"] = true

	# Zoom is anchored to the live midpoint so the course under the fingers
	# stays under the fingers. Pause-menu backdrops opt into this same gesture.
	if not bool(_two_finger.get("blocked", false)) and _camera_panning_allowed():
		if prev_dist > 0.5 and absf(d_dist) > 0.5 and camera:
			camera.zoom_by_factor(dist / prev_dist, mid)
		if d_mid.length() > 0.5 and camera:
			camera.pan_screen_offset(d_mid)
	_two_finger["mid_prev"] = mid
	_two_finger["dist_prev"] = dist

func _two_finger_fingers_moved() -> bool:
	var starts: Dictionary = _two_finger.get("start_positions", {})
	for index in _two_finger.get("indices", []):
		if not _touches.has(index) or not starts.has(index):
			continue
		var current: Vector2 = Vector2(_touches[index]["pos"])
		if current.distance_to(Vector2(starts[index])) > TAP_DISTANCE:
			return true
	return false

func _is_two_finger_tap() -> bool:
	if _two_finger.is_empty() or bool(_two_finger.get("blocked", false)):
		return false
	var elapsed: int = Time.get_ticks_msec() - int(_two_finger["start_ms"])
	return elapsed <= TAP_DURATION_MS and not bool(_two_finger["moved"])

func _midpoint() -> Vector2:
	return _midpoint_for(_two_finger.get("indices", []))

func _midpoint_for(indices: Array) -> Vector2:
	var positions: Array[Vector2] = []
	for index in indices:
		if _touches.has(index):
			positions.append(Vector2(_touches[index]["pos"]))
		if positions.size() == 2:
			break
	if positions.size() < 2:
		return Vector2.ZERO
	return (positions[0] + positions[1]) / 2.0

func _pinch_distance_for(indices: Array) -> float:
	var positions: Array[Vector2] = []
	for index in indices:
		if _touches.has(index):
			positions.append(Vector2(_touches[index]["pos"]))
		if positions.size() == 2:
			break
	if positions.size() < 2:
		return 0.0
	return positions[0].distance_to(positions[1])

func _scroll_axis_for_gesture(scroll: ScrollContainer, delta: Vector2) -> int:
	if not is_instance_valid(scroll):
		return 0
	var can_scroll_h := scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	var can_scroll_v := scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	var h_bar := scroll.get_h_scroll_bar()
	var v_bar := scroll.get_v_scroll_bar()
	can_scroll_h = can_scroll_h and h_bar != null and h_bar.max_value > h_bar.page + 1.0
	can_scroll_v = can_scroll_v and v_bar != null and v_bar.max_value > v_bar.page + 1.0
	if can_scroll_h and (not can_scroll_v or absf(delta.x) >= absf(delta.y)):
		return 1  # Horizontal
	if can_scroll_v:
		return 2  # Vertical
	return 0

func _scroll_by_drag(scroll: ScrollContainer, axis: int, delta: Vector2) -> void:
	if not is_instance_valid(scroll):
		return
	if axis == 1:
		var bar := scroll.get_h_scroll_bar()
		var max_scroll := maxi(0, roundi(bar.max_value - bar.page)) if bar else 0
		scroll.scroll_horizontal = clampi(scroll.scroll_horizontal - roundi(delta.x), 0, max_scroll)
	elif axis == 2:
		var bar := scroll.get_v_scroll_bar()
		var max_scroll := maxi(0, roundi(bar.max_value - bar.page)) if bar else 0
		scroll.scroll_vertical = clampi(scroll.scroll_vertical - roundi(delta.y), 0, max_scroll)

## Move a slider to the value under a finger. Works for horizontal and
## vertical sliders alike (Godot's slider orientation is `vertical` on Slider).
func _set_slider_from_touch(slider: Slider, pos: Vector2) -> void:
	if not is_instance_valid(slider):
		return
	var rect := slider.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var fraction: float
	if slider is VSlider:
		fraction = 1.0 - clampf((pos.y - rect.position.y) / rect.size.y, 0.0, 1.0)
	else:
		fraction = clampf((pos.x - rect.position.x) / rect.size.x, 0.0, 1.0)
	var value := slider.min_value + fraction * (slider.max_value - slider.min_value)
	if slider.step > 0.0:
		value = slider.min_value + roundf((value - slider.min_value) / slider.step) * slider.step
	slider.set_value_no_signal(clampf(value, slider.min_value, slider.max_value))
	slider.value_changed.emit(slider.value)

func _is_paint_mode() -> bool:
	if paint_mode_provider.is_valid():
		return bool(paint_mode_provider.call())
	return false

func _camera_panning_allowed() -> bool:
	if camera == null:
		return false
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.get("current_mode") == GameManager.GameMode.MAIN_MENU:
		return false
	return true

# =============================================================================
# TOUCH TARGETING
# =============================================================================

## Mark touches on controls so they can't inadvertently paint or pan behind a
## button. ScrollContainers are handled directly here because Godot's mouse
## emulation is disabled for this project.
func _has_native_touch_target(screen_pos: Vector2) -> bool:
	if get_tree() == null:
		return false
	for target in get_tree().get_nodes_in_group("native_touch_input"):
		if not is_instance_valid(target) or not target.is_visible_in_tree() or not target is Control:
			continue
		if (target as Control).get_global_rect().has_point(screen_pos):
			return true
	return false

func _touch_target_at(screen_pos: Vector2) -> Dictionary:
	var result := {"over_ui": false, "scroll": null, "slider": null}
	if get_tree() != null and get_tree().root != null:
		_collect_touch_targets(get_tree().root, screen_pos, result)
	# The pause menu explicitly permits camera gestures on its dimmed backdrop;
	# its buttons and panel still capture touches normally.
	if _allows_pause_backdrop_gesture(screen_pos):
		result["over_ui"] = false
		result["scroll"] = null
	return result

func _collect_touch_targets(node: Node, screen_pos: Vector2, result: Dictionary) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	var control := node as Control
	var inside := false
	if control != null:
		inside = control.get_global_rect().has_point(screen_pos)
		# Respect clipped containers: their off-rect children are not touch UI.
		if control.clip_contents and not inside:
			return
		# Most controls guard their whole rectangle, which is forgiving for touch.
		# A shaped surface may opt in to a more precise hit area, so transparent
		# cutouts (such as the curved bottom shelf) remain part of the course.
		if inside and control.has_method("has_touch_point"):
			var local := control.get_global_transform_with_canvas().affine_inverse() * screen_pos
			inside = bool(control.call("has_touch_point", local))

	# Children are visited first so a nested ScrollContainer wins over its
	# parent. Reverse order approximates GUI draw order for overlapping siblings.
	for child_index in range(node.get_child_count() - 1, -1, -1):
		_collect_touch_targets(node.get_child(child_index), screen_pos, result)

	if control != null and inside and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		result["over_ui"] = true
		if result["scroll"] == null and control is ScrollContainer:
			result["scroll"] = control
		if control is Slider and (control as Slider).editable:
			result["slider"] = control

func _allows_pause_backdrop_gesture(screen_pos: Vector2) -> bool:
	if get_tree() == null:
		return false
	for overlay in get_tree().get_nodes_in_group("touch_camera_backdrop"):
		if is_instance_valid(overlay) and overlay.is_visible_in_tree() \
				and overlay.has_method("allows_touch_camera_gesture") \
				and bool(overlay.call("allows_touch_camera_gesture", screen_pos)):
			return true
	return false

# =============================================================================
# SYNTHETIC MOUSE EVENTS
# =============================================================================

## Push a full press+release click at `pos` through the normal input
## pipeline (a preceding motion event sets hover state for the GUI).
func _synthesize_click(pos: Vector2, button: MouseButton) -> void:
	_synthesize_mouse_motion(pos)
	_synthesize_mouse_button(button, true, pos)
	_synthesize_mouse_button(button, false, pos)

func _synthesize_mouse_button(button: MouseButton, pressed: bool, pos: Vector2) -> void:
	var vp: Viewport = get_viewport()
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	_begin_synthetic_mouse()
	vp.push_input(ev, true)
	_end_synthetic_mouse()

func _synthesize_mouse_motion(pos: Vector2) -> void:
	var vp: Viewport = get_viewport()
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	_begin_synthetic_mouse()
	vp.push_input(ev, true)
	_end_synthetic_mouse()

## Tell InputManager these mouse events came from a finger, not a mouse.
func _begin_synthetic_mouse() -> void:
	var manager := get_node_or_null("/root/InputManager")
	if manager != null:
		manager.begin_synthetic_mouse()

func _end_synthetic_mouse() -> void:
	var manager := get_node_or_null("/root/InputManager")
	if manager != null:
		manager.end_synthetic_mouse()

## End an in-progress paint stroke (release the synthetic mouse button).
func _cancel_paint_stroke() -> void:
	if _gesture == Gesture.PAINTING:
		_gesture = Gesture.NONE
		_synthesize_mouse_button(MOUSE_BUTTON_LEFT, false, _last_drag_pos)
