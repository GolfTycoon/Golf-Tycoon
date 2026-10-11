extends GameTest
## The terrain brush: the stamps a drag lays between two mouse positions (with no
## gaps however fast the mouse moved), the edge-connected stamps a stream needs,
## and the square and round footprints of each brush size.

func test_fast_brush_drag_has_no_gaps_and_includes_endpoints() -> void:
	var points := TerrainBrush.centers(Vector2i(3, 4), Vector2i(32, 19))
	assert_eq(points.front(), Vector2i(3, 4))
	assert_eq(points.back(), Vector2i(32, 19))
	for i in range(1, points.size()):
		assert_lte(absi(points[i].x - points[i - 1].x), 1)
		assert_lte(absi(points[i].y - points[i - 1].y), 1)

func test_a_click_without_a_drag_is_one_stamp() -> void:
	assert_eq(TerrainBrush.centers(Vector2i(5, 5), Vector2i(5, 5)), [Vector2i(5, 5)])

func test_stream_strokes_step_along_one_axis_at_a_time() -> void:
	var points := TerrainBrush.centers_4_connected(Vector2i(0, 0), Vector2i(6, 4))
	assert_eq(points.front(), Vector2i(0, 0))
	assert_eq(points.back(), Vector2i(6, 4))
	for i in range(1, points.size()):
		var step: Vector2i = points[i] - points[i - 1]
		assert_eq(absi(step.x) + absi(step.y), 1, "Stamp %d shares an edge with the last" % i)

func test_round_brushes_clip_the_corners_and_square_ones_do_not() -> void:
	assert_false(TerrainBrush.offsets(5).has(Vector2i(2, 2)), "A round 5x5 loses its corners")
	assert_true(TerrainBrush.offsets(5, false).has(Vector2i(2, 2)), "A square 5x5 keeps them")
	for size in [1, 2, 3, 4, 5, 7]:
		assert_eq(TerrainBrush.offsets(size, false).size(), size * size,
			"A square %dx%d paints %d tiles" % [size, size, size * size])
		assert_lte(TerrainBrush.offsets(size).size(), size * size)

func test_even_sizes_cover_a_block_around_the_vertex() -> void:
	# Even sizes cover an SxS block, matching the Elevation Brush: a 2x2 stamp
	# is four tiles, not the 1x1 the old odd-only radius produced.
	assert_eq(TerrainBrush.offsets(2, false).size(), 4)
	assert_eq(TerrainBrush.offsets(4, false).size(), 16)
	assert_true(TerrainBrush.offsets(2, false).has(Vector2i(-1, -1)))
	assert_true(TerrainBrush.offsets(2, false).has(Vector2i(0, 0)))
	assert_false(TerrainBrush.offsets(2, false).has(Vector2i(1, 0)))
