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

func test_stream_pond_bank_leaves_the_channel_mouth_open() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/course_surface.gdshader")
	var surface_start := source.find("vec3 surface(")
	var rough_branch_start := source.find(
		"} else if (id == 3.0 || id == 4.0 || id == 1.0 || id == T_STREAM) {", surface_start)
	var firm_branch_start := source.find("} else if (id == T_FIRM_FAIRWAY) {", rough_branch_start)
	assert_gt(rough_branch_start, surface_start, "Rough and stream banks share a surface branch")
	assert_gt(firm_branch_start, rough_branch_start, "The shared turf branch is complete")
	var rough_bank_branch := source.substr(rough_branch_start, firm_branch_start - rough_branch_start)
	assert_true(rough_bank_branch.contains("base = palette_color(3.0);"),
		"Stream banks use the Rough palette colour")
	assert_true(rough_bank_branch.contains("noise(world * vec2(0.32, 0.65))"),
		"Stream banks use the same ground variation as Rough")

	var boundary_start := source.find("float boundary_class(")
	var boundary_end := source.find("// 1 where two tiles need", boundary_start)
	assert_gt(boundary_end, boundary_start, "The shader boundary rule is present")
	var boundary_rule := source.substr(boundary_start, boundary_end - boundary_start)
	assert_true(boundary_rule.contains("if (id == T_STREAM) { return T_STREAM; }"),
		"Streams have a shoreline boundary against pond water")
	var mouth_start := source.find("float edge_between_at(")
	var mouth_end := source.find("vec3 palette_color(", mouth_start)
	assert_gt(mouth_end, mouth_start, "Stream-to-pond edge treatment is present")
	var mouth_rule := source.substr(mouth_start, mouth_end - mouth_start)
	assert_true(mouth_rule.contains("float mouth_radius = main_width * 11.0 + 0.02;"),
		"The unbanked opening matches the water mask, leaving muddy and rough edges banked")
	assert_true(mouth_rule.contains("smoothstep(mouth_radius, mouth_radius + 0.06, abs(along_edge - 0.5))"),
		"The bank fades in outside the stream mouth")
	assert_true(source.contains("float ee = is_wet(e);"),
		"The stream channel still links to adjacent pond water")
	assert_true(source.contains("edge_between_at(a, t_e, f.y, stream_end_e, tile_world)"),
		"The stream mouth opening is used on the shared edge")
	assert_true(source.contains("edge_between_at(t_e, a, f.y, stream_end_e, tile_world)"),
		"The pond-side shoreline has the same opening, so water remains continuous")
