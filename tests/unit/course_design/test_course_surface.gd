extends GameTest
## The course surface: painted terrain reaches the surface texture, bunkers
## always use the shallow surface, quiet generation and loads refresh it, theme
## changes repaint it, and Quick Start's fairways replace generated water.

var grid: TerrainGrid

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)

func after_each() -> void:
	TerrainPalette.set_theme_colors(CourseTheme.get_terrain_colors(GameManager.current_theme))
	super()

func test_bunker_uses_the_shallow_surface_data() -> void:
	var pos := Vector2i(3, 3)
	grid.set_tile(pos, TerrainTypes.Type.BUNKER)
	var data := grid._course_surface._data.get_pixel(3, 3)
	assert_eq(roundi(data.r * 255.0), TerrainTypes.Type.BUNKER)
	assert_eq(data.g, 0.0, "The reserved surface channel no longer carries bunker depth")
	assert_eq(grid.serialize()["3,3"], TerrainTypes.Type.BUNKER)

func test_quiet_generation_and_deserialize_refresh_surface() -> void:
	grid.begin_batch()
	grid.set_tile(Vector2i(0, 0), TerrainTypes.Type.WATER)
	grid.set_tile(Vector2i(7, 7), TerrainTypes.Type.GREEN)
	grid.end_batch_quiet()
	grid.refresh_all_overlays()
	assert_eq(roundi(grid._course_surface._data.get_pixel(0, 0).r * 255.0), TerrainTypes.Type.WATER)
	assert_eq(roundi(grid._course_surface._data.get_pixel(7, 7).r * 255.0), TerrainTypes.Type.GREEN)
	var saved := grid.serialize()
	grid.set_tile(Vector2i(0, 0), TerrainTypes.Type.GRASS)
	grid.deserialize(saved)
	assert_eq(roundi(grid._course_surface._data.get_pixel(0, 0).r * 255.0), TerrainTypes.Type.WATER)

func test_theme_refresh_preserves_terrain_and_player_placement() -> void:
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.FAIRWAY)
	var saved := grid.serialize()
	var placed := grid.serialize_player_placed()
	for theme in CourseTheme.Type.values():
		var colors := CourseTheme.get_terrain_colors(theme)
		TerrainPalette.set_theme_colors(colors)
		EventBus.theme_changed.emit(theme)
		var grass_index := CourseSurface.PALETTE_KEYS.find("grass")
		var rendered_grass := grid._course_surface._palette.get_image().get_pixel(grass_index, 0)
		var expected_grass: Color = colors["grass"]
		assert_almost_eq(rendered_grass.r, expected_grass.r, 1.0 / 255.0)
		assert_almost_eq(rendered_grass.g, expected_grass.g, 1.0 / 255.0)
		assert_almost_eq(rendered_grass.b, expected_grass.b, 1.0 / 255.0)
		assert_eq(grid.serialize(), saved)
		assert_eq(grid.serialize_player_placed(), placed)

func test_quick_start_paint_hole_replaces_generated_water_with_fairway() -> void:
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile_natural(Vector2i(x, y), TerrainTypes.Type.WATER)
	var tee := Vector2i(1, 4)
	var green := Vector2i(6, 4)
	QuickStartCourse._paint_hole(grid, tee, green, 3)
	assert_eq(grid.get_tile(tee), TerrainTypes.Type.TEE_BOX)
	assert_eq(grid.get_tile(green), TerrainTypes.Type.GREEN)
	for x in range(2, 5):
		assert_eq(grid.get_tile(Vector2i(x, 4)), TerrainTypes.Type.FAIRWAY,
			"Fairway must replace generated water at (%d, 4)" % x)

# =============================================================================
# Seams between materials
#
# The shader cannot run headless (the test renderer is a dummy), so these tests
# read the shader source the way test_globe_map.gd reads the planet shader, and
# hold on to the rules the surface depends on: boundaries sit on the shared tile
# edge, a tile's own edge treatment never paints over its neighbour, inset
# ground keeps square corners, and a corner pixel always gets a colour.
# =============================================================================

const SHADER_PATH := "res://shaders/course_surface.gdshader"

func _shader() -> String:
	return FileAccess.get_file_as_string(SHADER_PATH)

func _has(line_fragment: String) -> bool:
	return _shader().contains(line_fragment)

func test_boundary_band_straddles_the_shared_tile_edge() -> void:
	# The seam is anti-aliased across the edge (d = 0), half of the band in
	# each tile, so a straight boundary is an even blend of the two materials
	# and neither tile's footprint shrinks. A band wholly inside one tile
	# leaves a hard, jagged line on the other side.
	assert_true(_has("smoothstep(-aa_x, aa_x, d_e)") and _has("smoothstep(-aa_x, aa_x, d_w)"),
		"Boundary band must be symmetric around the east and west shared tile edges")
	assert_true(_has("smoothstep(-aa_y, aa_y, d_s)") and _has("smoothstep(-aa_y, aa_y, d_n)"),
		"Boundary band must be symmetric around the south and north shared tile edges")

func test_boundary_band_is_about_one_pixel_wide_at_any_zoom() -> void:
	# A fixed grid-space band is invisible zoomed out and a fat smear zoomed
	# in. The band follows the pixel footprint instead, floored so it never
	# collapses to a hard step.
	assert_true(_has("fwidth(f.x)") and _has("fwidth(f.y)"),
		"The boundary band must follow the pixel footprint (fwidth)")
	assert_true(_has("max(0.5 * fwidth(f.x), 0.015)"),
		"The boundary band must keep a floor so it never becomes a hard step")

func test_edge_treatments_fade_inward_only() -> void:
	# A green's collar, a bunker's lip and a shoreline are painted inside the
	# tile that owns them: full strength on the edge, fading inward. Reaching
	# past the edge doubles every treatment up on the seam.
	for edge in ["d_e", "d_s", "d_w", "d_n"]:
		assert_true(_has("smoothstep(-TREAT, 0.0, %s)" % edge),
			"Edge treatment must fade inward from %s, never cross into the neighbour" % edge)

func test_ground_fade_keeps_square_corners() -> void:
	# Inset terrain ends where its ground does. The ground thins out by
	# distance to the nearest open edge (a minimum, so a square patch of tiles
	# stays square) instead of by distance to the tile centre or a corner arc,
	# which rounded one painted tile into a blob.
	assert_true(_has("float ground_fade(vec2 q, vec2 g, vec4 open_edges, float width)"),
		"The ground fade between materials must be edge-aligned")
	assert_true(_has("return 1.0 - smoothstep(0.0, width,") and _has("edge_room(q, open_edges)"),
		"The ground fade must be measured from the open edges of the patch")

func test_corner_pixels_always_get_a_colour() -> void:
	# A pixel sitting on a convex corner straddles two edges, so part of it
	# falls in the tile diagonally across the corner. That share completes the
	# weights: without it a corner pixel is left unfilled and used to drop to
	# black.
	assert_true(_has("float w_es = k_e * k_s"),
		"Corner pixels must take the share of the tile diagonally across the corner")
	assert_true(_has("w_c + w_e + w_s + w_w + w_n + w_es + w_ws + w_wn + w_ne"),
		"The surface weights, diagonals included, must be what the colour is normalised by")

func test_palette_still_matches_the_shader_ids() -> void:
	# The tests above pin the surface's behaviour; this one pins the data it
	# reads, so a terrain id added without a palette slot still fails here
	# rather than showing as grey on the course.
	for terrain_type in TerrainTypes.Type.values():
		assert_true(terrain_type < CourseSurface.PALETTE_KEYS.size(),
			"Terrain id %d has no palette slot" % terrain_type)
