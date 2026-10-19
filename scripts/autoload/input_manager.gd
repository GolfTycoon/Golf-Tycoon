extends Node
## InputManager - One place for every input method the game supports (autoload).
##
## Golf Tycoon can be played with a mouse, a keyboard, both together, a
## gamepad or a touchscreen. The rest of the game already speaks Godot's
## Control language (focus, ui_accept, ui_cancel), so this autoload supplies
## the two pieces that make every screen work with all five:
##
##  * Device tracking. Every input event is classified as mouse, keyboard,
##    gamepad or touch. Screens can ask `is_navigation_device()` to show
##    keyboard/controller hints, and `device_changed` tells the input hint bar
##    which prompts to draw. A real mouse move switches back to mouse, so a
##    keyboard/controller and a mouse can be used together all the time.
##
##  * Focus scopes. Full-screen screens and popup panels call
##    `register_scope(self)` when they are built, and `focus_scope(self)` when
##    they open. While a navigation device (keyboard or gamepad) is in use and
##    a scope is visible, this manager makes sure something inside the newest
##    visible scope has focus. That single rule gives every screen a sensible
##    starting point for the arrow keys / D-pad and for Tab.
##
## `focus_first()` also builds a geometric focus graph for the scope (nearest
## control in each direction, plus a reading-order Tab cycle), so directional
## navigation follows what the player sees rather than the order the screen
## happened to add its controls in. `gui_focus_changed` scrolls the focused
## control into view inside any ScrollContainer, which keeps long panels
## usable on a gamepad at any window size.
##
## Touch input is translated to mouse events by TouchInput; this manager only
## records it as the active device so hints and focus rings stay out of a
## touch player's way.

## Which input method the player used most recently.
enum Device { MOUSE, KEYBOARD, GAMEPAD, TOUCH }

signal device_changed(device: int)
## A visible screen/panel opened or closed, or the focus scope changed.
signal focus_scope_changed(scope: Control)
## The focused control changed (also emitted for a cleared focus, with null).
signal focus_changed(control: Control)

## Group a screen root can join instead of calling register_scope(). Both are
## supported; the explicit call is preferred because it can be made in _ready.
const FOCUS_SCOPE_GROUP := "input_focus_scope"
## Metadata on a Control that should receive focus when its scope opens.
const DEFAULT_FOCUS_META := "input_default_focus"
## Joystick magnitude that counts as "the player touched the stick".
const JOYPAD_DEADZONE := 0.35

var device: int = Device.MOUSE
## True while the gamepad pointer is deliberately operating a screen (moving
## the right stick in a panel). Focus navigation stands down until the player
## presses the D-pad or B, so freeform surfaces such as the world globe, the
## course map and the golfer-skin canvas stay usable with a controller.
var pointer_mode: bool = false
## Screen position of the keyboard/controller pointer while it is up. INF means
## "use the real mouse". Camera and aiming read this so the pointer still works
## on platforms where warping the OS cursor is unavailable (web builds).
var virtual_pointer: Vector2 = Vector2.INF
## Visible scopes in open order; the last visible one owns the focus.
var _scopes: Array[Control] = []
## Scopes whose directional graph has been built, and the layout signature it
## was built from, so a screen that reflows (resize, rotation, a new page)
## rebuilds its D-pad neighbours instead of keeping stale geometry.
var _wired_scopes: Dictionary = {}
var _last_wire_ms: int = 0
## The scope that owned the focus on the previous frame, so opening or closing
## a screen can move focus in and out without any screen having to call us.
var _last_active_scope: Control = null
## Depth counter for mouse events the game synthesizes itself (touch taps and
## the gamepad cursor). They must not make the UI think a real mouse moved.
var _synthetic_mouse_depth: int = 0


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(_delta: float) -> void:
	if _scopes.is_empty():
		_last_active_scope = null
		return
	_prune_scopes()
	var scope := active_scope()
	if scope != _last_active_scope:
		# A screen/panel opened or closed. Navigation players get focus in the
		# new screen; mouse and touch players are left alone until they switch.
		_last_active_scope = scope
		if scope != null and is_navigation_device():
			focus_scope(scope)
		return
	if not is_navigation_device() or scope == null:
		return
	if pointer_mode:
		return
	_refresh_focus_graph_if_stale(scope)
	if get_viewport().gui_get_focus_owner() != null:
		return
	focus_scope(scope)


func _input(event: InputEvent) -> void:
	if _synthetic_mouse_depth > 0 and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var detected := device_for_event(event)
	if detected < 0:
		return
	if detected == Device.MOUSE or detected == Device.TOUCH:
		virtual_pointer = Vector2.INF
	if detected == device:
		return
	device = detected
	if not is_navigation_device():
		# A pointer player should not be left with a focus ring from the
		# keyboard/controller; clicking a control gives it focus again.
		clear_focus()
	device_changed.emit(device)
	if is_navigation_device():
		# Keyboard/gamepad was just picked up: give the open screen a starting
		# focus right away, so the very first arrow press moves something.
		_ensure_focus.call_deferred()


# =============================================================================
# DEVICE DETECTION
# =============================================================================

## Classify an event as a Device, or -1 when it carries no device information
## (echoes, zero-length synthetic motion, and so on). Pure, so it is testable.
static func device_for_event(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return Device.GAMEPAD if (event as InputEventJoypadButton).pressed else -1
	if event is InputEventJoypadMotion:
		return Device.GAMEPAD if absf((event as InputEventJoypadMotion).axis_value) > JOYPAD_DEADZONE else -1
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return Device.TOUCH
	if event is InputEventKey:
		var key := event as InputEventKey
		return Device.KEYBOARD if key.pressed and not key.echo else -1
	if event is InputEventMouseButton:
		return Device.MOUSE
	if event is InputEventMouseMotion:
		# Synthetic motion (touch taps, the gamepad cursor) has no travel; only
		# a real moving mouse should switch the UI back to mouse prompts.
		return Device.MOUSE if (event as InputEventMouseMotion).relative.length() > 0.5 else -1
	return -1


## True while the player is navigating with the keyboard or a gamepad. Screens
## use it to show the focus ring and the control prompts.
func is_navigation_device() -> bool:
	return device == Device.KEYBOARD or device == Device.GAMEPAD


func is_gamepad() -> bool:
	return device == Device.GAMEPAD


func is_keyboard() -> bool:
	return device == Device.KEYBOARD


func is_touch() -> bool:
	return device == Device.TOUCH


func is_mouse() -> bool:
	return device == Device.MOUSE


## Where the player's pointer is, in viewport pixels: the synthetic pointer
## while a keyboard/controller is driving it, otherwise the real mouse.
func pointer_screen_position() -> Vector2:
	if virtual_pointer.is_finite():
		return virtual_pointer
	return get_viewport().get_mouse_position()


func device_name() -> String:
	return device_label(device)


static func device_label(value: int) -> String:
	match value:
		Device.KEYBOARD:
			return "keyboard"
		Device.GAMEPAD:
			return "gamepad"
		Device.TOUCH:
			return "touch"
		_:
			return "mouse"


## Whether a physical controller is currently connected. Used by settings and
## hint text; navigation works the moment a joypad event arrives either way.
func has_gamepad() -> bool:
	return not Input.get_connected_joypads().is_empty()


## Wrap events the game synthesizes itself so they are not mistaken for real
## mouse input. Always pair with end_synthetic_mouse().
func begin_synthetic_mouse() -> void:
	_synthetic_mouse_depth += 1


func end_synthetic_mouse() -> void:
	_synthetic_mouse_depth = maxi(0, _synthetic_mouse_depth - 1)


# =============================================================================
# FOCUS SCOPES
# =============================================================================

## Call from a screen's or panel's _ready(). Safe to call more than once.
func register_scope(scope: Control) -> void:
	if not is_instance_valid(scope):
		return
	if not _scopes.has(scope):
		_scopes.append(scope)
		if not scope.tree_exiting.is_connected(_on_scope_exiting):
			scope.tree_exiting.connect(_on_scope_exiting.bind(scope))
	if scope.is_visible_in_tree():
		focus_scope(scope)


func unregister_scope(scope: Control) -> void:
	_scopes.erase(scope)
	_wired_scopes.erase(scope.get_instance_id())


## A screen that opens should call this (usually it only needs register_scope()
## in _ready; show_centered() does it for popup panels).
func focus_scope(scope: Control) -> void:
	if not is_instance_valid(scope) or not scope.is_visible_in_tree():
		return
	pointer_mode = false
	if not _scopes.has(scope):
		register_scope(scope)
	_wire_focus_graph(scope)
	_wired_scopes[scope.get_instance_id()] = _layout_signature(scope)
	focus_first(scope)
	focus_scope_changed.emit(scope)


## The newest visible scope, which is the screen on top of the stack.
func active_scope() -> Control:
	_prune_scopes()
	for index in range(_scopes.size() - 1, -1, -1):
		var scope := _scopes[index]
		if is_instance_valid(scope) and scope.is_visible_in_tree():
			return scope
	return null


func has_visible_scope() -> bool:
	return active_scope() != null


## Give focus to the first suitable control in `root` (or the one marked with
## the `input_default_focus` metadata). Returns the control that was focused.
func focus_first(root: Control) -> Control:
	var controls := collect_focusables(root)
	if controls.is_empty():
		return null
	var target: Control = controls[0]
	for control in controls:
		if control.has_meta(DEFAULT_FOCUS_META):
			target = control
			break
	if get_viewport().gui_get_focus_owner() == target:
		return target
	target.grab_focus()
	return target


## Focus a specific control, for gameplay shortcuts such as "controller Back
## opens the bottom dock". Neighbour wiring is left alone: gameplay controls
## keep their own layout order.
func focus_control(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree() \
			and control.focus_mode != Control.FOCUS_NONE:
		control.grab_focus()


func clear_focus() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_release_focus()


## Every visible, enabled control under `root` that can take focus, in tree
## order. Used by focus_first and by the tests.
func collect_focusables(root: Control) -> Array[Control]:
	var controls: Array[Control] = []
	_collect_focusables(root, controls)
	return controls


func _collect_focusables(node: Node, controls: Array[Control]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	var control := node as Control
	if control != null and control.focus_mode != Control.FOCUS_NONE:
		var disabled := false
		if control is BaseButton:
			disabled = (control as BaseButton).disabled
		elif control is LineEdit:
			disabled = (control as LineEdit).editable == false
		if not disabled:
			controls.append(control)
	for child in node.get_children():
		_collect_focusables(child, controls)


func _ensure_focus() -> void:
	if not is_navigation_device():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	var scope := active_scope()
	if scope != null:
		focus_scope(scope)


func _prune_scopes() -> void:
	for index in range(_scopes.size() - 1, -1, -1):
		if not is_instance_valid(_scopes[index]):
			_scopes.remove_at(index)


func _on_scope_exiting(scope: Control) -> void:
	unregister_scope(scope)
	var restore := active_scope()
	if restore != null and is_navigation_device():
		focus_scope(restore)
	focus_scope_changed.emit(restore)


func _on_joy_connection_changed(_device_id: int, connected: bool) -> void:
	if connected and has_gamepad():
		device = Device.GAMEPAD
		device_changed.emit(device)
		_ensure_focus.call_deferred()


# =============================================================================
# FOCUS GRAPH (D-pad / arrow-key navigation)
# =============================================================================

## Build directional neighbours from the controls' screen positions and a
## reading-order Tab cycle. Explicit neighbours already set by a screen are
## left alone. Rebuilt whenever a scope is focused, which covers screens that
## are torn down and rebuilt for a new window size.
func _wire_focus_graph(scope: Control) -> void:
	var controls := collect_focusables(scope)
	if controls.size() < 2:
		return

	# Recompute rather than add: a control can move to a different side when
	# the screen reflows, so old neighbours are cleared first.
	for control in controls:
		control.focus_neighbor_left = NodePath()
		control.focus_neighbor_right = NodePath()
		control.focus_neighbor_top = NodePath()
		control.focus_neighbor_bottom = NodePath()
		control.focus_next = NodePath()
		control.focus_previous = NodePath()

	# Reading order: top-to-bottom rows, left-to-right inside a row. Controls
	# within a quarter of the average height are treated as one row.
	var row_height := _average_height(controls) * 0.5
	var ordered: Array[Control] = controls.duplicate()
	ordered.sort_custom(func(a: Control, b: Control) -> bool:
		var ar := a.get_global_rect()
		var br := b.get_global_rect()
		if absf(ar.get_center().y - br.get_center().y) > row_height:
			return ar.get_center().y < br.get_center().y
		return ar.get_center().x < br.get_center().x)
	for index in ordered.size():
		var control: Control = ordered[index]
		var next: Control = ordered[(index + 1) % ordered.size()]
		var previous: Control = ordered[(index - 1 + ordered.size()) % ordered.size()]
		control.focus_next = control.get_path_to(next)
		control.focus_previous = control.get_path_to(previous)

	for control in controls:
		var center := control.get_global_rect().get_center()
		var best := {
			"left": [null, INF], "right": [null, INF],
			"top": [null, INF], "bottom": [null, INF],
		}
		for other in controls:
			if other == control:
				continue
			var delta := other.get_global_rect().get_center() - center
			var distances := {
				"left": -delta.x, "right": delta.x,
				"top": -delta.y, "bottom": delta.y,
			}
			for direction in distances:
				var primary: float = distances[direction]
				if primary <= 1.0:
					continue
				var secondary := absf(delta.y) if direction in ["left", "right"] else absf(delta.x)
				# Prefer the nearest control in that direction, with a penalty
				# for drifting off axis so a row of buttons stays a row.
				var score := primary + secondary * 1.8
				if score < float(best[direction][1]):
					best[direction] = [other, score]
		_assign_neighbor(control, "left", best["left"][0])
		_assign_neighbor(control, "right", best["right"][0])
		_assign_neighbor(control, "top", best["top"][0])
		_assign_neighbor(control, "bottom", best["bottom"][0])


## Rebuild the graph when the screen has reflowed. Checks at most a few times a
## second: layout can settle over several frames (a panel sizes itself after the
## first process_frame), so one deferred pass is not enough.
func _refresh_focus_graph_if_stale(scope: Control) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_wire_ms < 200:
		return
	_last_wire_ms = now
	var id := scope.get_instance_id()
	if _wired_scopes.get(id, -1) == _layout_signature(scope):
		return
	_wire_focus_graph(scope)
	_wired_scopes[id] = _layout_signature(scope)


## A cheap value that changes whenever the focusable controls move or resize.
func _layout_signature(scope: Control) -> int:
	var signature := 0
	for control in collect_focusables(scope):
		var rect := control.get_global_rect()
		signature = hash([signature, Vector2i(rect.position), Vector2i(rect.size)])
	return signature


func _assign_neighbor(control: Control, direction: String, other: Control) -> void:
	if other == null:
		return
	var property := "focus_neighbor_%s" % direction
	control.set(property, control.get_path_to(other))


func _average_height(controls: Array[Control]) -> float:
	var total := 0.0
	for control in controls:
		total += control.get_global_rect().size.y
	return total / float(maxi(1, controls.size()))


# =============================================================================
# FOCUS VISIBILITY
# =============================================================================

func _on_gui_focus_changed(control: Control) -> void:
	if control != null:
		# A control can be focused before its container has laid it out; wait a
		# frame so ensure_control_visible() sees the final rect.
		_scroll_into_view_deferred.call_deferred(control.get_instance_id())
		_wire_focus_graph_for_control(control)
	focus_changed.emit(control)


func _wire_focus_graph_for_control(control: Control) -> void:
	# If a gameplay control (the dock) is focused outside any scope, wire the
	# nearest visible screen region so the D-pad still behaves predictably.
	if has_visible_scope():
		return
	var parent := control.get_parent()
	if parent == null:
		return
	for scope in _scopes:
		if is_instance_valid(scope) and scope.is_visible_in_tree():
			return
	var root := parent.get_parent() as Control
	if root != null and root.is_visible_in_tree():
		var id := root.get_instance_id()
		if not _wired_scopes.has(id):
			_wire_focus_graph(root)


## Deferred by instance id: a control can be freed (a screen rebuilding after a
## resize) between the focus change and the deferred call.
func _scroll_into_view_deferred(instance_id: int) -> void:
	var control := instance_from_id(instance_id) as Control
	if control == null or not control.is_inside_tree():
		return
	_scroll_into_view(control)


func _scroll_into_view(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer and (node as ScrollContainer).is_visible_in_tree():
			(node as ScrollContainer).ensure_control_visible(control)
		node = node.get_parent()


# =============================================================================
# HINTS
# =============================================================================

## Short prompts for the status/hint bar, chosen for the active device.
func action_hints() -> Array[String]:
	match device:
		Device.GAMEPAD:
			return ["A  Select", "B  Back", "D-pad  Navigate", "Start  Pause"]
		Device.KEYBOARD:
			return ["Enter  Select", "Esc  Back", "Arrows  Navigate", "Tab  Next", "F1  Help"]
		Device.TOUCH:
			return ["Tap  Select", "Drag  Scroll", "Pinch  Zoom"]
		_:
			return ["Click  Select", "Right-click  Cancel", "Scroll  Zoom", "F1  Help"]
