extends GameTest
## The land boundary overlay: the tint over unowned land and the property lines.
##
## The tint is drawn only for the tiles the camera can actually see, and those
## tiles are walked a parcel row at a time instead of asking the land manager
## about all 16,384 tiles of the map on every camera-driven repaint. These tests
## pin that window to the camera, prove the parcel-row walk agrees with a
## tile-by-tile ownership check, and prove the projected diamonds are dropped
## when the ground or the view moves under them.

var grid: TerrainGrid
var land: LandManager
var overlay: LandBoundaryOverlay
var camera: Camera2D

func before_each() -> void:
	super()
	grid = make_grid(96, 96)
	land = LandManager.new()
	add_child_autofree(land)
	GameManager.land_manager = land
	camera = Camera2D.new()
	camera.zoom = Vector2(4.0, 4.0)
	camera.position = grid.grid_to_screen_center(Vector2i(46, 46))
	grid.add_child(camera)
	camera.make_current()
	overlay = grid.get_node("LandBoundaryOverlay") as LandBoundaryOverlay

# ---------------------------------------------------------------------------
# Which tiles get tinted
# ---------------------------------------------------------------------------

func test_the_tint_is_culled_to_the_cameras_tile_window() -> void:
	var tiles := overlay.visible_unowned_tiles()
	var window := grid.get_visible_tile_range()
	var first: Vector2i = window[0]
	var last: Vector2i = window[1]

	assert_gt(tiles.size(), 0, "the unowned land around the plot is tinted")
	assert_lt(tiles.size(), grid.grid_width * grid.grid_height,
		"but not the tiles behind the camera")
	for pos in tiles:
		assert_true(pos.x >= first.x and pos.x <= last.x
			and pos.y >= first.y and pos.y <= last.y,
			"%s is inside the visible window %s..%s" % [pos, first, last])
		assert_false(land.is_tile_owned(pos), "%s is unowned" % pos)


## The ownership walk skips whole parcels for speed; it must still produce
## exactly the tiles a naive per-tile check would.
func test_the_parcel_row_walk_agrees_with_a_tile_by_tile_check() -> void:
	var window := grid.get_visible_tile_range()
	var first: Vector2i = window[0]
	var last: Vector2i = window[1]
	var expected: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var pos := Vector2i(x, y)
			if not land.is_tile_owned(pos):
				expected.append(pos)

	assert_eq(overlay.visible_unowned_tiles(), expected,
		"every unowned tile in the window, and nothing else")


## The parcel grid leaves a four-tile margin around the map, and no parcel can
## ever own it. The segment walk must tint that margin too.
func test_the_map_margins_are_tinted_like_any_other_unowned_land() -> void:
	var edge := make_grid(128, 128)
	var edge_overlay := edge.get_node("LandBoundaryOverlay") as LandBoundaryOverlay
	var edge_camera := Camera2D.new()
	edge_camera.zoom = Vector2(3.0, 3.0)
	edge_camera.position = edge.grid_to_screen_center(Vector2i(124, 124))
	edge.add_child(edge_camera)
	edge_camera.make_current()
	await process_frames(2)

	var window := edge.get_visible_tile_range()
	var first: Vector2i = window[0]
	var last: Vector2i = window[1]
	var expected: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if not land.is_tile_owned(Vector2i(x, y)):
				expected.append(Vector2i(x, y))
	assert_eq(edge_overlay.visible_unowned_tiles(), expected,
		"the right and bottom margins are unowned and tinted")
	assert_true(expected.has(Vector2i(126, 126)), "precondition: the window reaches the margin")


func test_owned_land_is_never_tinted() -> void:
	# The starting plot is the centre 2x2 parcels, which is inside this window.
	var window := grid.get_visible_tile_range()
	var owned_in_view := 0
	for x in range(window[0].x, window[1].x + 1):
		for y in range(window[0].y, window[1].y + 1):
			if land.is_tile_owned(Vector2i(x, y)):
				owned_in_view += 1
	assert_gt(owned_in_view, 0, "precondition: the camera looks at owned land")
	for pos in overlay.visible_unowned_tiles():
		assert_false(land.is_tile_owned(pos), "%s is owned and must not be tinted" % pos)


# ---------------------------------------------------------------------------
# The projected diamonds follow the ground and the view
# ---------------------------------------------------------------------------

func test_turning_the_course_drops_the_projected_diamonds() -> void:
	overlay._tile_polygon(Vector2i(30, 30))
	assert_false(overlay._tile_polygons.is_empty(), "precondition: a diamond is cached")

	grid.rotate_view_cw()
	assert_true(overlay._tile_polygons.is_empty(),
		"a quarter turn reprojects every diamond")


func test_sculpting_the_ground_drops_the_projected_diamonds() -> void:
	overlay._tile_polygon(Vector2i(30, 30))
	assert_false(overlay._tile_polygons.is_empty(), "precondition: a diamond is cached")

	grid.set_vertex_elevation(Vector2i(31, 31), TerrainGrid.BASE_ELEVATION + 2)
	assert_true(overlay._tile_polygons.is_empty(),
		"a lifted vertex moves the diamonds that share it")


func test_a_bulk_elevation_load_can_drop_the_projected_diamonds() -> void:
	overlay._tile_polygon(Vector2i(30, 30))
	overlay.invalidate_ground()
	assert_true(overlay._tile_polygons.is_empty(),
		"a load that writes the heightfield without a per-vertex signal clears the shelf")
