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

func test_stream_bank_draws_a_border_instead_of_blending() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/course_surface.gdshader")
	# The border runs in the same edge-treatment band as the Bunker's grass
	# lip, so the two borders are exactly the same size.
	var helper_start := source.find("float stream_bank_border(")
	var helper_end := source.find("// Features of inset terrain", helper_start)
	assert_gt(helper_start, 0, "The stream bank border helper is present")
	assert_gt(helper_end, helper_start, "The stream bank border helper is complete")
	var helper := source.substr(helper_start, helper_end - helper_start)
	assert_true(source.contains("float edge = 1.0 - smoothstep(EDGE_LIP_LO, EDGE_LIP_HI, cover);"),
		"Every surface's edge treatment, the Bunker lip among them, uses the shared thresholds")
	assert_true(helper.contains("smoothstep(-FRINGE, FRINGE, q.x - 1.0)"),
		"The stream's border runs in the same FRINGE band as the Bunker's lip")
	assert_true(helper.contains("smoothstep(EDGE_LIP_LO + wobble, EDGE_LIP_HI + wobble, cover)"),
		"The stream's border fades in across the same coverage as the Bunker's lip")

	# Water, Rough and Pot Bunker meet the bank with no border at all, while
	# every other different terrain still gets one.
	assert_true(source.contains(
		"return (other == 8.0 || other == 3.0 || other == T_POT_BUNKER) ? 0.0 : 1.0;"),
		"Water, Rough and Pot Bunker are the terrains a stream never borders")
	var stream_start := source.find("if (id == T_STREAM) {", source.find("vec3 inset_tile("))
	var pot_start := source.find("} else if (id == T_POT_BUNKER) {", stream_start)
	assert_gt(pot_start, stream_start, "The stream branch of inset_tile() is complete")
	var stream_branch := source.substr(stream_start, pot_start - stream_start)
	assert_true(stream_branch.contains("vec4 bordered = vec4(stream_borders(e), stream_borders(s),"),
		"The border is gated per neighbouring edge")
	assert_true(stream_branch.contains("float border = stream_bank_border(q, open_edges * bordered, g);"),
		"An edge a stream does not border loses only its rim, keeping its boundary")
	assert_true(stream_branch.contains("vec3 bank = mix(own, rim, border);"),
		"The bank keeps its own turf away from the border")
	assert_false(stream_branch.contains("mix(own, outside, edge_mix)"),
		"The bank no longer blends into the terrain beside it")
	assert_true(stream_branch.contains(
		"return mix(mix(bank, mud, mud_mask), clamp(water, vec3(0.0), vec3(1.0)), water_mask);"),
		"The border lies under the mud and the water, so the channel stays clean")

	# The surface no longer samples a stream's or a pot bunker's surround to
	# blend into: both paint their own turf.
	var fragment_start := source.find("void fragment()")
	var fragment := source.substr(fragment_start)
	assert_true(fragment.contains("if (!keeps_own_turf(a)) {"),
		"Only inset terrain that sits in the turf around it samples that turf")
	assert_true(fragment.contains("vec3 outside = own;"),
		"A stream and a pot bunker are handed no surround, because they keep their own turf")

func test_stream_and_pot_share_the_bank_turf() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/course_surface.gdshader")

	# One helper paints the rough turf a stream's banks keep and a pot bunker's
	# lip is cut into, so the two tiles show the same grass.
	var helper_start := source.find("vec3 bank_turf(")
	var helper_end := source.find("\n}\n", helper_start)
	assert_gt(helper_start, 0, "The shared bank turf helper is present")
	assert_gt(helper_end, helper_start, "The shared bank turf helper is complete")
	var helper := source.substr(helper_start, helper_end - helper_start)
	assert_true(helper.contains("palette_color(3.0)"), "The bank turf uses the Rough palette colour")
	assert_true(helper.contains("noise(world * vec2(0.32, 0.65))"),
		"The bank turf uses the same ground variation as Rough")

	var surface_start := source.find("vec3 surface(")
	var turf_branch_start := source.find("} else if (id == 3.0 || id == 4.0 || id == 1.0) {", surface_start)
	var stream_branch_start := source.find("} else if (id == T_STREAM) {", turf_branch_start)
	var firm_branch_start := source.find("} else if (id == T_FIRM_FAIRWAY) {", stream_branch_start)
	assert_gt(turf_branch_start, surface_start, "Rough and Natural Grass share a surface branch")
	assert_gt(stream_branch_start, turf_branch_start, "Rough's branch ends before the stream's")
	assert_gt(firm_branch_start, stream_branch_start, "The stream branch is complete")
	var turf_branch := source.substr(turf_branch_start, stream_branch_start - turf_branch_start)
	assert_true(turf_branch.contains("noise(world * vec2(0.32, 0.65))"),
		"Rough's turf carries the tuft variation")
	var stream_branch := source.substr(stream_branch_start, firm_branch_start - stream_branch_start)
	assert_true(stream_branch.contains("return bank_turf(world, grain, patch);"),
		"A stream's banks are painted with the shared turf")

	# The pot bunker's lip is that same grass, not the turf of its surroundings.
	var pot_start := source.find("} else if (id == T_POT_BUNKER) {", source.find("vec3 inset_tile("))
	var pot_end := source.find("} else if (id == T_WASTE_BUNKER) {", pot_start)
	assert_gt(pot_start, 0, "The pot bunker branch is present")
	assert_gt(pot_end, pot_start, "The pot bunker branch is complete")
	var pot_branch := source.substr(pot_start, pot_end - pot_start)
	assert_true(pot_branch.contains("vec3 lip = bank_turf(world, grain, patch)"),
		"A pot bunker's lip uses the same rough turf as a stream's banks")
	assert_false(pot_branch.contains("vec3 lip = outside"),
		"The lip no longer borrows the turf of the tiles around it")

	# A stream or a pot bunker is the same grass inside a neighbouring tile's
	# boundary band, so neither shows a strip of another grass at its edge.
	var band_start := source.find("vec3 neighbour_surface(")
	var band_end := source.find("void fragment()", band_start)
	assert_gt(band_start, 0, "The boundary band surface helper is present")
	assert_gt(band_end, band_start, "The boundary band surface helper is complete")
	var band := source.substr(band_start, band_end - band_start)
	assert_true(band.contains("if (keeps_own_turf(tile)) {"),
		"A stream or a pot bunker keeps its own turf in the band")
	assert_true(band.contains("return bank_turf(world, grain, patch);"),
		"That turf is the shared bank grass")

func test_stream_pond_bank_leaves_the_channel_mouth_open() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/course_surface.gdshader")
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
