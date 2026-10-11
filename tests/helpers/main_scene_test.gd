class_name MainSceneTest
extends GameTest
## Base class for every integration test: the real main scene, driven the way a
## player drives it.
##
## The scene is built once per test script, in before_all(), and freed in
## after_all(). While it runs it owns the game's global state, so GameManager is
## snapshotted around the whole script instead of around each test.
##
## Starting a course is the expensive part, so a script starts the one its tests
## share in before_all(): new_game() for an empty lot, or quick_start() for the
## nine-hole Quick Start course when the tests need holes, golfers or the
## generated layout. Prefer the empty lot: every terrain edit on a course re-plans
## each hole's shot line, which costs a couple of seconds on Quick Start. Each
## test then works on its own tiles, so it does not depend on what the tests
## before it built.
##
## A subclass that overrides before_all() or after_all() calls super() — first
## in before_all(), last in after_all().

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
## The window the game is designed at (project.godot); layout tests that resize
## the window are put back to it.
const DESIGN_WINDOW := Vector2i(1600, 1000)
## Frames a new course needs: the loading overlay paints for two, generation
## runs on the third, and Quick Start seats its first group a frame later.
const NEW_COURSE_FRAMES := 8

var main: Node


func before_all() -> void:
	_saved_state = GameState.capture()
	get_window().size = DESIGN_WINDOW
	main = load(MAIN_SCENE_PATH).instantiate()
	add_child(main)
	await process_frames(2)


func after_all() -> void:
	if is_instance_valid(main):
		main.free()
	main = null
	# The scene handed these autoloads references into itself.
	TouchInput.camera = null
	TouchInput.paint_mode_provider = func() -> bool: return false
	SaveManager.milestone_manager = null
	get_window().size = DESIGN_WINDOW
	GameState.restore(_saved_state)


## The scene owns the global state between its tests (see before_all).
func before_each() -> void:
	pass


## A test ends on a frame, so whatever it queued for freeing is gone before GUT
## counts orphans. A subclass that overrides this awaits super(), last.
func after_each() -> void:
	await process_frames(1)


# ---------------------------------------------------------------------------
# Starting a game
# ---------------------------------------------------------------------------

## Start a game on an empty lot (the direct entry point, past the world map).
func new_game(course_name: String = "Integration test", theme: int = CourseTheme.Type.PARKLAND) -> void:
	main._on_main_menu_new_game(course_name, theme)
	await process_frames(NEW_COURSE_FRAMES)


## Start the Quick Start course: nine landscaped holes, their paths and a
## clubhouse, with the first group on its way.
func quick_start(course_name: String = "Integration test", theme: int = CourseTheme.Type.PARKLAND) -> void:
	main._on_main_menu_quick_start(course_name, theme)
	await process_frames(NEW_COURSE_FRAMES)


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

## Paint `tile` with `terrain` through the real brush, as one undoable stroke.
func paint(terrain: int, tile: Vector2i) -> void:
	main._on_tool_selected(terrain)
	stroke(tile)


## One brush stroke of the selected tool on `tile`.
func stroke(tile: Vector2i) -> void:
	main.undo_manager.begin_stroke()
	main._paint_terrain_stamp(tile)
	main.undo_manager.end_stroke()


## Paint a tee box and a green with its cup, then open the hole they make, the
## way a player builds one. Returns the hole, or null if it did not open.
func build_hole(tee: Vector2i, cup: Vector2i) -> GameManager.HoleData:
	var holes_before: int = GameManager.current_course.holes.size()
	paint(TerrainTypes.Type.TEE_BOX, tee)
	paint(TerrainTypes.Type.GREEN, cup)
	main._on_open_hole_pressed()
	if GameManager.current_course.holes.size() == holes_before:
		return null
	return GameManager.current_course.holes[-1]


# ---------------------------------------------------------------------------
# Screens and input
# ---------------------------------------------------------------------------

## Resize the game window and let the layout follow it. after_all() puts the
## design size back.
func set_window(size: Vector2i) -> void:
	get_window().size = size
	await process_frames(4)


## A real left click in the middle of `control`, through the viewport: like the
## player's, it only reaches the control when nothing is drawn over it.
func click(control: Control) -> void:
	assert_not_null(control, "There is a control to click")
	if control == null:
		return
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)
		await process_frames(1)
	await process_frames(1)


## Press a key through the viewport, as the player would.
func press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	get_viewport().push_input(event)


## Every node of the engine class `type_name` under `root`, `root` included.
static func nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root == null:
		return found
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(nodes_of_class(child, type_name))
	return found


## The text of every Label under `root`, one per line.
static func labels_text(root: Node) -> String:
	var text := ""
	for label in nodes_of_class(root, "Label"):
		text += (label as Label).text + "\n"
	return text


## `inner` lies inside `outer`, give or take `slack` pixels.
static func rect_within(inner: Rect2, outer: Rect2, slack: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - slack \
		and inner.position.y >= outer.position.y - slack \
		and inner.end.x <= outer.end.x + slack \
		and inner.end.y <= outer.end.y + slack


## Whether `node` sits inside a ScrollContainer.
static func inside_scroll(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


## The part of `control` that is actually visible: clipped by every
## ScrollContainer it sits in.
static func visible_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect()
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			rect = rect.intersection((parent as Control).get_global_rect())
		parent = parent.get_parent()
	return rect


## Whether a ScrollContainer under `root` holds more than it shows.
static func scrolls(root: Node) -> bool:
	for node in nodes_of_class(root, "ScrollContainer"):
		var scroll: ScrollContainer = node
		if scroll.get_v_scroll_bar().max_value > scroll.size.y + 1.0:
			return true
	return false
