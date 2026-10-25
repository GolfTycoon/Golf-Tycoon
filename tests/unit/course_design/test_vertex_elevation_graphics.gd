extends GameTest
## Vertex elevation graphics: sculpted corners lift the terrain as it is drawn,
## screen picking undoes the lift, and the surface shader is set up for it.

## Flat ground sits at BASE_ELEVATION (mid-range of 0..10); screen displacement
## is measured from it.
const BASE := TerrainGrid.BASE_ELEVATION

var grid: TerrainGrid

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	await process_frames(1)

func test_vertex_elevation_displacement_in_isometric_view() -> void:
	assert_true(grid.view_isometric)
	assert_gt(grid.ELEVATION_STEP_Y, 0.0)

	var v_flat := Vector2i(5, 5)
	grid.set_vertex_elevation(v_flat, BASE)
	var disp_flat := grid.get_vertex_elevation_displacement(v_flat)
	assert_eq(disp_flat, Vector2.ZERO)

	var v_high := Vector2i(6, 6)
	grid.set_vertex_elevation(v_high, BASE + 3)
	var disp_high := grid.get_vertex_elevation_displacement(v_high)
	assert_eq(disp_high.x, 0.0)
	assert_eq(disp_high.y, -3.0 * grid.ELEVATION_STEP_Y)

	var v_low := Vector2i(7, 7)
	grid.set_vertex_elevation(v_low, BASE - 2)
	var disp_low := grid.get_vertex_elevation_displacement(v_low)
	assert_eq(disp_low.x, 0.0)
	assert_eq(disp_low.y, 2.0 * grid.ELEVATION_STEP_Y)

func test_grid_point_to_screen_moves_with_elevation() -> void:
	var v := Vector2i(4, 4)
	grid.set_vertex_elevation(v, BASE)
	var flat_screen: Vector2 = grid.grid_point_to_screen(Vector2(v))

	grid.set_vertex_elevation(v, BASE + 2)
	var raised_screen: Vector2 = grid.grid_point_to_screen(Vector2(v))
	assert_eq(raised_screen.x, flat_screen.x)
	assert_almost_eq(raised_screen.y, flat_screen.y - 2.0 * grid.ELEVATION_STEP_Y, 0.01)

	grid.set_vertex_elevation(v, BASE - 3)
	var lowered_screen: Vector2 = grid.grid_point_to_screen(Vector2(v))
	assert_eq(lowered_screen.x, flat_screen.x)
	assert_almost_eq(lowered_screen.y, flat_screen.y + 3.0 * grid.ELEVATION_STEP_Y, 0.01)

func test_tile_polygon_corners_reflect_varying_vertex_heights() -> void:
	# Tile at (3, 3) has corners at (3,3), (4,3), (4,4), (3,4)
	grid.set_vertex_elevation(Vector2i(3, 3), BASE)
	grid.set_vertex_elevation(Vector2i(4, 3), BASE + 2)
	grid.set_vertex_elevation(Vector2i(4, 4), BASE + 4)
	grid.set_vertex_elevation(Vector2i(3, 4), BASE + 1)

	var poly := grid.tile_polygon(Vector2i(3, 3))
	assert_eq(poly.size(), 4)

	var c0 := grid.grid_point_to_screen(Vector2(3, 3))
	var c1 := grid.grid_point_to_screen(Vector2(4, 3))
	var c2 := grid.grid_point_to_screen(Vector2(4, 4))
	var c3 := grid.grid_point_to_screen(Vector2(3, 4))

	assert_almost_eq(poly[0].y, c0.y, 0.01)
	assert_almost_eq(poly[1].y, c1.y, 0.01)
	assert_almost_eq(poly[2].y, c2.y, 0.01)
	assert_almost_eq(poly[3].y, c3.y, 0.01)

	# Verify slopes are evident between corners
	assert_lt(poly[2].y, poly[0].y, "Higher elevation corner should be higher on screen (smaller Y)")

func test_screen_to_grid_point_inverts_elevation_displacement() -> void:
	# For an elevated point on a slope, screen_to_grid_point should retrieve the grid coordinate
	var target_grid := Vector2(5.0, 5.0)
	grid.set_vertex_elevation(Vector2i(5, 5), BASE + 3)

	var screen_pos := grid.grid_point_to_screen(target_grid)
	var unprojected := grid.screen_to_grid_point(screen_pos)

	assert_almost_eq(unprojected.x, target_grid.x, 0.05)
	assert_almost_eq(unprojected.y, target_grid.y, 0.05)

func test_course_surface_shader_uniforms_configured() -> void:
	assert_not_null(grid._course_surface)
	var mat := grid._course_surface.material as ShaderMaterial
	assert_not_null(mat)

	var step_y = mat.get_shader_parameter("elevation_step_y")
	assert_eq(step_y, grid.ELEVATION_STEP_Y)

	var is_iso = mat.get_shader_parameter("is_isometric")
	assert_eq(is_iso, true)

func test_extreme_slope_picking_finds_the_front_surface_and_exact_crossing() -> void:
	# These two points have the same screen position. The higher, farther-front
	# point is at height 6.75, so its crossing lies between the old five-pixel
	# ray samples and used to come back at the wrong grid coordinate.
	for vertex in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3),
			Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]:
		grid.set_vertex_elevation(vertex, 5)
	grid.set_vertex_elevation(Vector2i(2, 2), 3)
	grid.set_vertex_elevation(Vector2i(3, 2), 3)
	grid.set_vertex_elevation(Vector2i(2, 3), 2)
	grid.set_vertex_elevation(Vector2i(3, 3), 2)
	grid.set_vertex_elevation(Vector2i(4, 3), 7)
	grid.set_vertex_elevation(Vector2i(3, 4), 9)
	grid.set_vertex_elevation(Vector2i(4, 4), 9)
	var hidden := Vector2(2.25, 2.25)
	var visible := Vector2(3.5, 3.5)
	assert_almost_eq(grid.get_elevation_at(hidden), 2.75, 0.001)
	assert_almost_eq(grid.get_elevation_at(visible), 6.75, 0.001)
	var hidden_screen := grid.grid_point_to_screen(hidden)
	var visible_screen := grid.grid_point_to_screen(visible)
	assert_almost_eq(hidden_screen.x, visible_screen.x, 0.001)
	assert_almost_eq(hidden_screen.y, visible_screen.y, 0.001)
	var picked := grid.screen_to_grid_point(visible_screen)
	assert_ne(picked, TerrainGrid.INVALID_GRID_POINT)
	var rendered := grid.grid_point_to_screen(picked)
	assert_almost_eq(rendered.x, visible_screen.x, 0.01,
		"the picked point reprojects to the same pixel across the cliff")
	assert_almost_eq(rendered.y, visible_screen.y, 0.01,
		"the picked point is an exact heightfield crossing, not one coarse step away")
	assert_gt(picked.x, visible.x, "the higher surface in front is the one picked")

func test_narrow_extreme_peak_is_not_stepped_over() -> void:
	# Both crossings of this sharp 0-to-10 peak fit between ordinary ray samples.
	# The exact bilinear-tile intersection must retain the tiny patch at its top
	# instead of jumping to the flat ground behind it.
	for x in range(4, 7):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), grid.MIN_ELEVATION)
	grid.set_vertex_elevation(Vector2i(5, 5), grid.MAX_ELEVATION)
	var near_peak := Vector2(5.01, 5.01)
	var screen := grid.grid_point_to_screen(near_peak)
	var picked := grid.screen_to_grid_point(screen)
	assert_almost_eq(picked.x, near_peak.x, 0.005)
	assert_almost_eq(picked.y, near_peak.y, 0.005)
	assert_gt(grid.get_elevation_at(picked), 9.8)
	var rendered := grid.grid_point_to_screen(picked)
	assert_almost_eq(rendered.y, screen.y, 0.01)

func test_extreme_peak_picking_survives_every_view_rotation() -> void:
	for x in range(4, 7):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), grid.MIN_ELEVATION)
	grid.set_vertex_elevation(Vector2i(5, 5), grid.MAX_ELEVATION)
	var near_peak := Vector2(5.01, 5.01)
	for facing in range(4):
		grid.set_view_orientation(facing)
		var screen := grid.grid_point_to_screen(near_peak)
		var picked := grid.screen_to_grid_point(screen)
		assert_ne(picked, TerrainGrid.INVALID_GRID_POINT, "facing %d hits the peak" % facing)
		assert_gt(grid.get_elevation_at(picked), 9.8,
			"facing %d does not select the ground behind the peak" % facing)
		var rendered := grid.grid_point_to_screen(picked)
		assert_almost_eq(rendered.x, screen.x, 0.01)
		assert_almost_eq(rendered.y, screen.y, 0.01)

func test_picking_does_not_invent_ground_above_or_below_the_course() -> void:
	# A wholly lowered course cannot cover the flat position of its back corner.
	for x in range(grid.grid_width + 1):
		for y in range(grid.grid_height + 1):
			grid.set_vertex_elevation(Vector2i(x, y), grid.MIN_ELEVATION)
	var above_lowered_rim := grid.projection.project(Vector2(0.5, 0.5))
	assert_eq(grid.screen_to_grid_point(above_lowered_rim), TerrainGrid.INVALID_GRID_POINT)

func test_elevation_changes_reproject_ground_detail_and_waiting_pins() -> void:
	var pos := Vector2i(5, 5)
	var cup_pos := pos + Vector2i(-1, 0)
	grid.set_tile(pos, TerrainTypes.Type.OAK)
	grid.set_tile(cup_pos, TerrainTypes.Type.GREEN)
	assert_true(grid.add_cup_tile(cup_pos))
	var trees := grid._tree_overlay as TreeOverlay
	trees._sync_visuals()
	var tree := trees._visuals[pos] as Node2D
	var old_tree_position := tree.position
	var pin := grid._cup_overlay._pins[0] as Node2D
	var old_pin_position := pin.position

	# A single level at one corner changes the exact centre by a quarter level.
	# It does not change the tile's rounded elevation, so listening only to
	# elevation_changed would leave this art behind.
	var tree_redrawn := [false]
	trees.draw.connect(func(): tree_redrawn[0] = true)
	grid.set_vertex_elevation(pos, grid.BASE_ELEVATION + 1)
	assert_eq(pin.position, grid.grid_to_screen_center(cup_pos))
	assert_ne(pin.position, old_pin_position)
	await process_frames(2)
	assert_true(tree_redrawn[0], "the tree redraw follows the vertex, not a camera move")
	assert_eq(tree.position, grid.grid_to_screen_center(pos))
	assert_ne(tree.position, old_tree_position)

func test_decoration_reanchors_when_its_ground_moves() -> void:
	var entities := make_entity_layer(grid)
	var pos := Vector2i(6, 6)
	var decoration := entities.place_decoration("park_bench", pos, {
		"park_bench": {"size": [1, 1], "category": "path", "cost": 0},
	})
	assert_not_null(decoration)
	var old_position := decoration.global_position
	grid.set_vertex_elevation(pos, grid.BASE_ELEVATION + 4)
	await process_frames(2)
	assert_eq(decoration.global_position, grid.grid_to_screen_center(pos))
	assert_ne(decoration.global_position, old_position)

func test_elevation_texture_decodes_flat_and_every_level_exactly() -> void:
	var vertex := Vector2i(4, 4)
	for level in range(grid.MIN_ELEVATION, grid.MAX_ELEVATION + 1):
		grid.set_vertex_elevation(vertex, level)
		var encoded := grid._course_surface._elevation_image.get_pixel(vertex.x, vertex.y).r
		var decoded := (encoded * 255.0 - CourseSurface.ELEVATION_TEXTURE_ZERO) \
				/ CourseSurface.ELEVATION_TEXTURE_SCALE
		assert_almost_eq(decoded, float(level - grid.BASE_ELEVATION), 0.00001,
			"level %d has no quantization offset after shader decoding" % level)

func test_tree_sprites_share_the_terrain_occlusion_heightfield() -> void:
	var pos := Vector2i(5, 5)
	grid.set_tile(pos, TerrainTypes.Type.OAK)
	var trees := grid._tree_overlay as TreeOverlay
	trees._sync_visuals()
	var tree := trees._visuals[pos] as Node2D
	var mat := tree.material as ShaderMaterial
	assert_not_null(mat)
	assert_eq(mat.shader, TreeOverlay.TERRAIN_SPRITE_OCCLUSION)
	assert_same(mat.get_shader_parameter("vertex_elevation"),
		grid._course_surface._elevation_texture, "sculpts update the ground and sprite mask together")
	assert_eq(mat.get_shader_parameter("ground_grid"), Vector2(pos) + Vector2(0.5, 0.5))
	assert_eq(mat.get_shader_parameter("ground_offset"), TreeOverlay.ground_jitter(pos))
	grid.set_view_orientation(1)
	assert_eq(mat.get_shader_parameter("grid_origin"), grid.projection.grid_origin(),
		"the occlusion projection turns with the tree and the ground")

func test_elevated_terrain_occludes_only_sprite_pixels_behind_it() -> void:
	var tree_ground := Vector2(5.5, 5.5)
	var hill_ground := Vector2(6.5, 6.5)
	for vertex in [Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)]:
		grid.set_vertex_elevation(vertex, grid.MAX_ELEVATION)
	var tree_base := grid.grid_point_to_screen(tree_ground)
	var hill_base := grid.grid_point_to_screen(hill_ground)
	# The front hill's ground is 50 pixels up its elevation ray. Its nearest
	# corner also lifts the tree's ground, leaving this trunk pixel only 5.5
	# pixels above that sloped anchor, so the hill must hide it.
	var covered_point := grid.screen_to_grid_point(hill_base)
	var covered_terrain_t := (grid.get_elevation_at(covered_point) - grid.BASE_ELEVATION) \
			* grid.ELEVATION_STEP_Y
	var covered_sprite_t := tree_base.y - hill_base.y
	assert_almost_eq(covered_terrain_t, 50.0, 0.001)
	assert_almost_eq(covered_sprite_t, 5.5, 0.001)
	assert_gt(covered_terrain_t, covered_sprite_t)
	# Sixty pixels above the tree, only flat ground lies behind the crown. The
	# nearer sprite remains visible instead of being erased with the trunk.
	var crown_screen := tree_base - Vector2(0.0, 60.0)
	var crown_point := grid.screen_to_grid_point(crown_screen)
	assert_ne(crown_point, TerrainGrid.INVALID_GRID_POINT)
	var crown_terrain_t := (grid.get_elevation_at(crown_point) - grid.BASE_ELEVATION) \
			* grid.ELEVATION_STEP_Y
	var crown_sprite_t := tree_base.y - crown_screen.y
	assert_almost_eq(crown_terrain_t, 0.0, 0.001)
	assert_lt(crown_terrain_t, crown_sprite_t)
	var source := FileAccess.get_file_as_string("res://shaders/terrain_sprite_occlusion.gdshader")
	assert_true(source.contains("terrain_t > sprite_t + occlusion_epsilon"))
	assert_true(source.contains("discard;"), "covered pixels are clipped, not merely darkened")

func test_surface_shader_uses_front_most_ray_intersection() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/course_surface.gdshader")
	assert_true(source.contains("#include \"res://shaders/terrain_heightfield.gdshaderinc\""))
	var common := FileAccess.get_file_as_string("res://shaders/terrain_heightfield.gdshaderinc")
	assert_true(common.contains("vec2 surface_grid_at_world(vec2 world, out bool hit)"),
		"the shader and picking share the same heightfield-intersection model")
	assert_true(common.contains("float intersect_elevation_tile(vec2 flat_point, vec2 ray_direction, vec2 cell,"),
		"each bilinear tile patch is intersected exactly instead of stretching across cliff pixels")
	assert_false(source.contains("for (int iter = 0; iter < 4; iter++)"),
		"the unstable four-step fixed-point elevation lookup is gone")

func after_each() -> void:
	await process_frames(1)
	super()
