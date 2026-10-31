extends GameTest
## The Course Map's touch gestures: one finger taps and pans, two fingers pinch
## open or closed to zoom (and, moved together, pan), and a pinch never picks a
## tile or leaves the map jumping when one finger comes up.
##
## Real InputEventScreenTouch/Drag events are pushed through the viewport, so
## what is checked is the gesture the map sees on a phone rather than its
## helper functions in isolation.

const SIDE := 16

var grid: TerrainGrid
var view: CourseMapView


func before_each() -> void:
	super()
	grid = make_grid(SIDE, SIDE)
	fill_grid(grid, TerrainTypes.Type.GRASS)
	GameManager.terrain_grid = grid
	view = CourseMapView.new()
	add_child_autofree(view)
	view.size = Vector2(480, 360)
	await process_frames(1)


func _push_touch(pressed: bool, index: int, pos: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	get_viewport().push_input(event, true)


func _push_drag(index: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	get_viewport().push_input(event, true)


## Two fingers starting `from_span` apart around `centre` and moved to
## `to_span` apart, then released.
func _pinch(centre: Vector2, from_span: float, to_span: float) -> void:
	var left_from := centre - Vector2(from_span * 0.5, 0.0)
	var right_from := centre + Vector2(from_span * 0.5, 0.0)
	var left_to := centre - Vector2(to_span * 0.5, 0.0)
	var right_to := centre + Vector2(to_span * 0.5, 0.0)
	_push_touch(true, 0, left_from)
	_push_touch(true, 1, right_from)
	_push_drag(0, left_to)
	_push_drag(1, right_to)
	_push_touch(false, 0, left_to)
	_push_touch(false, 1, right_to)


func test_a_pinch_open_zooms_the_map_in() -> void:
	# 100px -> 150px: the map opens 1.5x around the point between the fingers.
	_pinch(view.size * 0.5, 100.0, 150.0)
	await process_frames(1)
	assert_almost_eq(view.get_zoom(), 1.5, 0.01,
		"opening two fingers from 100px to 150px zooms the map in 1.5x")


func test_a_pinch_closed_zooms_the_map_out() -> void:
	view.zoom_by(2.0)
	# 150px -> 75px: half the span takes the map back to the whole-course view.
	_pinch(view.size * 0.5, 150.0, 75.0)
	await process_frames(1)
	assert_almost_eq(view.get_zoom(), 1.0, 0.01,
		"closing the fingers to half their span zooms the map back out")


func test_a_pinch_stops_at_the_map_zoom_limits() -> void:
	_pinch(view.size * 0.5, 40.0, 400.0)
	await process_frames(1)
	assert_almost_eq(view.get_zoom(), CourseMapView.MAX_ZOOM, 0.001,
		"opening the fingers wide stops at the map's maximum zoom")
	_pinch(view.size * 0.5, 400.0, 40.0)
	await process_frames(1)
	assert_almost_eq(view.get_zoom(), CourseMapView.MIN_ZOOM, 0.001,
		"closing them stops at the whole-course view")


func test_a_pinch_never_picks_the_tile_under_a_finger() -> void:
	var pressed: Array = []
	view.map_pressed.connect(func(tile: Vector2i, hit: Dictionary) -> void: pressed.append([tile, hit]))
	_pinch(view.size * 0.5, 100.0, 180.0)
	await process_frames(1)
	assert_eq(pressed.size(), 0, "letting go of a pinch must not pick a tile")


func test_a_finger_left_after_a_pinch_pans_from_where_it_is() -> void:
	var centre := view.size * 0.5
	var left := centre - Vector2(50.0, 0.0)
	var right := centre + Vector2(50.0, 0.0)
	_push_touch(true, 0, left)
	_push_touch(true, 1, right)
	_push_drag(0, left - Vector2(20.0, 0.0))
	_push_drag(1, right + Vector2(20.0, 0.0))
	# The right finger comes up, leaving the left one down.
	_push_touch(false, 1, right + Vector2(20.0, 0.0))
	var pan_before := view._pan
	# The finger left over should take the pan over where it is, not jump by
	# the whole travel of the pinch.
	_push_drag(0, left - Vector2(10.0, 6.0))
	await process_frames(1)
	assert_almost_eq(view._pan.x, pan_before.x + 10.0, 0.5,
		"the last finger's drag moves the map by its own travel")
	assert_almost_eq(view._pan.y, pan_before.y - 6.0, 0.5)
	_push_touch(false, 0, left - Vector2(10.0, 6.0))


func test_two_fingers_moving_together_pan_the_map() -> void:
	view.zoom_by(2.0)
	var pan_before := view._pan
	var centre := view.size * 0.5
	# Both fingers travel 40px right. The span wobbles between 80 and 100 as
	# the fingers are reported one at a time, then settles back, so this is a
	# two-finger pan rather than a zoom.
	_push_touch(true, 0, centre - Vector2(50.0, 0.0))
	_push_touch(true, 1, centre + Vector2(50.0, 0.0))
	_push_drag(0, centre - Vector2(10.0, 0.0))
	_push_drag(1, centre + Vector2(90.0, 0.0))
	await process_frames(1)
	assert_almost_eq(view.get_zoom(), 2.0, 0.02, "the pair's span is unchanged, so the zoom is too")
	assert_almost_eq(view._pan.x, pan_before.x + 40.0, 1.0,
		"two fingers moving together pan the map with them")
	_push_touch(false, 0, centre - Vector2(10.0, 0.0))
	_push_touch(false, 1, centre + Vector2(90.0, 0.0))


func test_a_cancelled_touch_is_not_a_pick() -> void:
	var pressed: Array = []
	view.map_pressed.connect(func(tile: Vector2i, hit: Dictionary) -> void: pressed.append([tile, hit]))
	_push_touch(true, 0, view.size * 0.5)
	var cancel := InputEventScreenTouch.new()
	cancel.index = 0
	cancel.pressed = false
	cancel.canceled = true
	cancel.position = view.size * 0.5
	get_viewport().push_input(cancel, true)
	await process_frames(1)
	assert_eq(pressed.size(), 0, "an interrupted touch must not pick the tile under it")
	assert_true(view._touches.is_empty(), "the interrupted finger is forgotten")
