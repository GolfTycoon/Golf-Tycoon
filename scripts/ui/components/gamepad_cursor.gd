extends Control
class_name GamepadCursor
## GamepadCursor - a pointer for controller players (added to the HUD by Main).
##
## Menus and panels are navigated with focus, but the course itself is a
## pointer surface: terrain painting, placing a building, aiming a shot and
## clicking a hole all read the mouse position. Rather than giving the game a
## second, parallel set of code paths, this node moves the real mouse pointer
## with the controller's right stick (or the keyboard's arrow keys) and clicks
## it with A (or Enter). Every existing mouse feature therefore works unchanged
## with a gamepad or with a keyboard alone.
##
## The cursor is active only while the player is on the course with a
## keyboard/controller and no UI owns the focus. Opening a panel, or focusing
## the HUD with View/Back, hides it and hands input back to Godot's focus
## navigation; abandoning the panel returns the pointer. The camera keeps its
## own controls: left stick or WASD pans, bumpers/triggers zoom, X/Y rotate
## (see Main).
##
## The reticle is drawn in whole pixels, in the palette's gold over an ink
## outline, so it stays legible over bright sand and dark water alike.

const MOVE_SPEED := 980.0
## A slow stick still moves the pointer, so fine placement stays possible.
const MIN_SPEED_SCALE := 0.18
## Margin kept between the pointer and the window edge.
const EDGE_MARGIN := 8.0

const COL_INK := Color("08130f")
const COL_GOLD := Color("e5c47c")
const COL_LIGHT := Color("fff6df")

var camera: Camera2D = null

var _active := false
var _holding := false
var _placed := false
## The right stick is driving a screen (globe, map, skin canvas) instead of
## focus navigation. B or the D-pad hands control back to the focus system.
var _ui_pointer_mode := false
var _scope_id := 0


func _ready() -> void:
	name = "GamepadCursor"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2.ZERO
	z_index = 90
	visible = false


func _exit_tree() -> void:
	# The autoload outlives the course scene. Do not leave its pointer or
	# pointer-mode flag aimed at a cursor that no longer exists.
	if _holding:
		_release_hold()
	if has_node("/root/InputManager"):
		if _active:
			InputManager.virtual_pointer = Vector2.INF
		if _ui_pointer_mode:
			InputManager.pointer_mode = false


func _process(delta: float) -> void:
	_update_ui_pointer_mode()
	var should_be_active := _should_be_active()
	if should_be_active != _active:
		_active = should_be_active
		if _active:
			if not _placed:
				_place_at_center()
			else:
				# A panel or the mouse cleared the virtual pointer while this
				# reticle was hidden. Reclaim it at the remembered position.
				_place_pointer()
		if not _active:
			_release_hold()
			queue_redraw()
	# The HUD-wide visibility pass (Main._set_gameplay_ui_visible) shows every
	# non-popup child, so the pointer keeps its own visibility in sync each
	# frame instead of trusting the last thing that touched it.
	visible = _active
	if not _active:
		if has_node("/root/InputManager"):
			InputManager.virtual_pointer = Vector2.INF
		return

	var stick := Input.get_vector(
		"gamepad_cursor_left", "gamepad_cursor_right",
		"gamepad_cursor_up", "gamepad_cursor_down")
	if InputManager.is_keyboard():
		# No UI has focus (that is part of _should_be_active), so the arrow
		# keys are free to drive the pointer.
		stick = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	elif _ui_pointer_mode:
		# Inside a screen the right stick is the pointer; the left stick stays
		# with focus navigation so the player can return to the buttons.
		stick = Input.get_vector(
			"gamepad_cursor_left", "gamepad_cursor_right",
			"gamepad_cursor_up", "gamepad_cursor_down")
	if stick.length() > 0.01:
		var speed := MOVE_SPEED * maxf(MIN_SPEED_SCALE, stick.length())
		position = _clamp_to_window(position + stick.normalized() * speed * delta)
		_place_pointer()
	queue_redraw()


## Active on the course, with a controller, while no UI screen or focused
## control owns the keyboard/D-pad.
func _should_be_active() -> bool:
	if not has_node("/root/InputManager") or not InputManager.is_navigation_device():
		return false
	if InputManager.is_gamepad():
		# On the course the controller always has its pointer; on a screen it
		# appears when the player moves the right stick (see
		# _update_ui_pointer_mode).
		if InputManager.has_visible_scope():
			return _ui_pointer_mode
		return get_viewport().gui_get_focus_owner() == null
	if has_node("/root/GameManager") and GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return false
	if InputManager.has_visible_scope():
		return false
	return get_viewport().gui_get_focus_owner() == null


## Right stick on a screen enters pointer mode; a new screen (or closing one)
## leaves it. D-pad movement and B exit it in _unhandled_input.
func _update_ui_pointer_mode() -> void:
	if not has_node("/root/InputManager"):
		return
	var scope := InputManager.active_scope()
	var id := scope.get_instance_id() if scope != null else 0
	if id != _scope_id:
		_scope_id = id
		if _ui_pointer_mode:
			_set_ui_pointer_mode(false)
	if not InputManager.is_gamepad() or scope == null:
		return
	var stick := Input.get_vector(
		"gamepad_cursor_left", "gamepad_cursor_right",
		"gamepad_cursor_up", "gamepad_cursor_down")
	if not _ui_pointer_mode and stick.length() > 0.2:
		_set_ui_pointer_mode(true)
		if not _placed:
			_place_at_center()


func _set_ui_pointer_mode(enabled: bool) -> void:
	if _ui_pointer_mode == enabled:
		return
	_ui_pointer_mode = enabled
	if has_node("/root/InputManager"):
		InputManager.pointer_mode = enabled
		if enabled:
			InputManager.clear_focus()
		else:
			var scope := InputManager.active_scope()
			if scope != null:
				InputManager.focus_scope(scope)


func _place_at_center() -> void:
	var view := get_viewport().get_visible_rect().size
	position = view * 0.5
	_placed = true
	_place_pointer()


func _clamp_to_window(value: Vector2) -> Vector2:
	var view := get_viewport().get_visible_rect().size
	return value.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN),
		Vector2(maxf(EDGE_MARGIN, view.x - EDGE_MARGIN), maxf(EDGE_MARGIN, view.y - EDGE_MARGIN)))


## Put the real pointer under the reticle. The camera, placement previews,
## tooltips and the tile inspector all read the viewport's mouse position, so
## moving it keeps every mouse-driven feature working. The synthetic motion
## carries zero travel so InputManager does not think a mouse was used.
func _place_pointer() -> void:
	var viewport := get_viewport()
	var manager := get_node_or_null("/root/InputManager")
	# warp_mouse() can itself report a mouse move. Wrap it with the synthetic
	# guard so moving the reticle never makes InputManager think the player
	# picked up the mouse (which would hide the pointer on the next frame).
	if manager != null:
		manager.begin_synthetic_mouse()
	viewport.warp_mouse(position)
	if manager != null:
		manager.virtual_pointer = position
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	if manager != null:
		manager.end_synthetic_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# On a screen, B leaves pointer mode first (the screen stays open), and a
	# D-pad or left-stick nudge hands control back to focus navigation.
	if _ui_pointer_mode:
		if event.is_action_pressed("cancel"):
			_set_ui_pointer_mode(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed \
				and (event as InputEventJoypadButton).button_index in [
					JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
					JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			_set_ui_pointer_mode(false)
			return
	# A / Enter - click (and hold, so brushing and dragging work).
	var click_action := "gamepad_click" if InputManager.is_gamepad() else "ui_accept"
	if event.is_action(click_action):
		# Space stays the pause shortcut for keyboard players; Enter clicks.
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE:
			return
		var pressed: bool = event.is_pressed() and not event.is_echo()
		if pressed:
			_holding = true
			_send_button(true)
		else:
			_release_hold()
		get_viewport().set_input_as_handled()
		return
	# B/Esc - cancel: when a HUD control had focus, the first press simply
	# returns to the pointer instead of leaving the player stuck in the dock.
	if event.is_action_pressed("cancel") and get_viewport().gui_get_focus_owner() != null:
		if has_node("/root/InputManager"):
			InputManager.clear_focus()
		get_viewport().set_input_as_handled()


func _release_hold() -> void:
	if _holding:
		_holding = false
		_send_button(false)


func _send_button(pressed: bool) -> void:
	_place_pointer()
	var viewport := get_viewport()
	if has_node("/root/InputManager"):
		InputManager.begin_synthetic_mouse()
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = position
	button.global_position = position
	viewport.push_input(button, true)
	if has_node("/root/InputManager"):
		InputManager.end_synthetic_mouse()
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var center := Vector2.ZERO
	var radius := 11.0
	# Corner brackets: a chunky pixel reticle that leaves the middle clear.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var x: float = corner.x * radius
		var y: float = corner.y * radius
		# Outline first, then the gold face, so the reticle reads on any tile.
		draw_rect(Rect2(center + Vector2(x - signf(x) * 5.0, y) - Vector2(0, 1), Vector2(6, 3)), COL_INK)
		draw_rect(Rect2(center + Vector2(x - signf(x) * 4.0, y), Vector2(4, 1)), COL_GOLD)
		draw_rect(Rect2(center + Vector2(x, y - signf(y) * 5.0) - Vector2(1, 0), Vector2(3, 6)), COL_INK)
		draw_rect(Rect2(center + Vector2(x, y - signf(y) * 4.0), Vector2(1, 4)), COL_GOLD)
	# A single lit pixel in the exact spot the click lands.
	draw_rect(Rect2(center - Vector2(1, 1), Vector2(3, 3)), COL_INK)
	draw_rect(Rect2(center, Vector2(1, 1)), COL_LIGHT if _holding else COL_GOLD)
