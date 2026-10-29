extends GameTest
## ShelfPageWindow: the curved window every shelf page is cut to. The pages
## start at a curve parallel to the fairway's rim — reaching under the curved
## tab buttons, further left the lower they sit — and the same shape gates input
## so the course outside it stays clickable.

func _window(canvas: Vector2, width: float, inset: float = 0.0) -> ShelfPageWindow:
	var window := ShelfPageWindow.new()
	add_child_autofree(window)
	window.size = canvas
	window.set_curve(width, inset)
	return window

# ---------------------------------------------------------------------------
# THE CURVED EDGE
# ---------------------------------------------------------------------------

func test_the_window_starts_a_frame_inside_the_painted_rim() -> void:
	var canvas := Vector2(400, 190)
	for y in [0.0, 40.0, 90.0, 140.0, 189.0]:
		assert_almost_eq(
			ShelfPageWindow.content_left(y, canvas, 224.0, 6.0),
			ShelfFanBackdrop.rim_x_at(y, canvas, 224.0, 6.0) + ShelfPageWindow.EDGE_MARGIN,
			0.01, "the content curve runs parallel to the rim, at %s" % y)
	assert_gte(ShelfPageWindow.EDGE_MARGIN, DockArcBackdrop.BAND_SHEEN,
		"a page leaves the rim's whole frame — ink, trim, bevel, sheen — in view")

func test_the_window_reaches_further_left_the_lower_it_sits() -> void:
	# The wedged turf under the curved tab buttons is widest along the bottom.
	var canvas := Vector2(400, 190)
	var previous := INF
	var top := 0.0
	for i in 20:
		var left := ShelfPageWindow.content_left(i * canvas.y / 19.0, canvas, 224.0, 6.0)
		assert_lte(left, previous, "the edge only ever moves left as it descends")
		previous = left
		top = left
	assert_gt(ShelfPageWindow.content_left(0.0, canvas, 224.0, 6.0),
		canvas.x * 0.25, "the top of the shelf starts well right of its left edge")
	assert_lt(top, ShelfPageWindow.EDGE_MARGIN + 1.0,
		"and the bottom reaches the shelf's own left padding")

func test_the_edge_follows_the_rail_as_it_narrows() -> void:
	# A phone-sized rail mirrors a smaller ellipse, so the whole curve moves.
	var canvas := Vector2(400, 232)
	var wide := ShelfPageWindow.content_left(120.0, canvas, 224.0, 6.0)
	var narrow := ShelfPageWindow.content_left(120.0, canvas, 66.0, 1.18)
	assert_lt(narrow, wide, "the narrow rail's page starts further left")
	assert_gt(narrow, 0.0, "but still inside the shelf")

func test_a_window_without_a_curve_yet_keeps_every_page() -> void:
	# The first frame of a new shelf has no rail geometry: nothing is cut away.
	var canvas := Vector2(200, 100)
	assert_eq(ShelfPageWindow.content_left(50.0, canvas, 0.0), 0.0)
	for point in [Vector2(0, 0), Vector2(199, 0), Vector2(0, 99), Vector2(199, 99)]:
		assert_true(ShelfPageWindow.content_contains(point, canvas, 0.0),
			"the whole page area is content while the rail settles")

# ---------------------------------------------------------------------------
# WHAT IS INSIDE
# ---------------------------------------------------------------------------

func test_the_cut_out_left_of_the_curve_is_outside_the_window() -> void:
	var canvas := Vector2(400, 190)
	var width := 224.0
	var inset := 6.0
	var left := ShelfPageWindow.content_left(60.0, canvas, width, inset)
	assert_false(ShelfPageWindow.content_contains(Vector2(left - 1.0, 60.0), canvas, width, inset),
		"just left of the curve is the course showing through")
	assert_true(ShelfPageWindow.content_contains(Vector2(left + 1.0, 60.0), canvas, width, inset),
		"just right of it is the page")
	assert_false(ShelfPageWindow.content_contains(Vector2(0.0, 0.0), canvas, width, inset),
		"the shelf's top-left corner is cut away")
	assert_true(ShelfPageWindow.content_contains(Vector2(canvas.x - 1.0, 0.0), canvas, width, inset),
		"while the pages run right up to the top of their column")
	assert_true(ShelfPageWindow.content_contains(Vector2(canvas.x - 1.0, canvas.y - 1.0),
		canvas, width, inset), "and down to the bottom")
	assert_false(ShelfPageWindow.content_contains(Vector2(-1.0, 60.0), canvas, width, inset),
		"nothing outside the shelf's own rect is a page")
	assert_false(ShelfPageWindow.content_contains(Vector2(canvas.x, 60.0), canvas, width, inset))

func test_the_inside_of_the_window_is_inside_the_painted_fairway() -> void:
	# A page can never paint over the rim onto the course: every point the
	# window keeps is also fairway the backdrop paints.
	var canvas := Vector2(400, 190)
	var width := 224.0
	var inset := 6.0
	for y in range(0, 190, 7):
		for x in range(0, 400, 11):
			var point := Vector2(x, y)
			if ShelfPageWindow.content_contains(point, canvas, width, inset):
				assert_true(ShelfFanBackdrop.contains_point(point, canvas, width, inset),
					"content at %s stays on the shelf's own turf" % point)

# ---------------------------------------------------------------------------
# THE MASK
# ---------------------------------------------------------------------------

func test_the_mask_runs_down_the_curve_and_back_along_the_square_side() -> void:
	var canvas := Vector2(400, 190)
	var polygon := ShelfPageWindow.content_polygon(canvas, 224.0, 6.0)
	assert_gt(polygon.size(), 40, "the curved edge is sampled finely")
	assert_eq(polygon[0], Vector2(ShelfPageWindow.content_left(0.0, canvas, 224.0, 6.0), 0.0),
		"the silhouette starts at the top of the curve")
	assert_eq(polygon[-1], Vector2(canvas.x, 0.0), "and closes along the top edge")
	assert_eq(polygon[-2], Vector2(canvas.x, canvas.y), "past the bottom-right corner")
	assert_almost_eq(polygon[-3].y, canvas.y, 0.01, "along the bottom edge")
	var previous_x := INF
	for i in polygon.size() - 3:
		assert_lte(polygon[i].x, previous_x, "the curved edge never folds back on itself")
		previous_x = polygon[i].x
	assert_almost_eq(polygon[1].y - polygon[0].y, float(ShelfFanBackdrop.PIXEL), 0.01,
		"the edge steps at the fairway's own two-pixel grain")

func test_the_mask_paints_the_whole_window_before_the_rail_settles() -> void:
	var window := _window(Vector2(200, 100), 0.0)
	assert_eq(window.clip_children, CanvasItem.CLIP_CHILDREN_ONLY,
		"the window is a mask for the pages it holds")
	assert_true(window.clip_contents, "and clipping its contents shapes the input too")
	assert_eq(window.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the window itself takes no clicks: its pages do")

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------

func test_the_window_only_answers_inside_its_curve() -> void:
	var window := _window(Vector2(400, 190), 224.0, 6.0)
	var left := window.content_left_at(60.0)
	assert_true(window._has_point(Vector2(left + 2.0, 60.0)), "a page point is clickable")
	assert_false(window._has_point(Vector2(left - 2.0, 60.0)),
		"the cut-out passes clicks through to the course")
	assert_eq(window.has_touch_point(Vector2(left + 2.0, 60.0)),
		window.contains_content_point(Vector2(left + 2.0, 60.0)),
		"touch reads the same shape the mouse does")
	assert_eq(window.has_touch_point(Vector2(left - 2.0, 60.0)),
		window.contains_content_point(Vector2(left - 2.0, 60.0)))

func test_a_resized_window_reshapes_itself() -> void:
	var window := _window(Vector2(400, 190), 224.0, 6.0)
	var before := window.content_left_at(100.0)
	window.size = Vector2(400, 232)
	assert_almost_eq(window.content_left_at(100.0),
		ShelfPageWindow.content_left(100.0, Vector2(400, 232), 224.0, 6.0), 0.01,
		"the curve is measured against the shelf the window now fills")
	assert_ne(window.content_left_at(100.0), before)
