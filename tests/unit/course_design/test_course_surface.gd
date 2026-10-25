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
	var pot_end := source.find("\treturn own;", pot_start)
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

func test_bordered_tiles_have_unique_full_tile_textures_and_bunker_sized_borders() -> void:
	var shader := FileAccess.get_file_as_string("res://shaders/course_surface.gdshader")
	assert_false(shader.is_empty(), "The course surface shader is readable")

	var shader_tokens := [
		"T_DEEP_ROUGH", "T_WASTE_BUNKER", "T_BRUSH",
		"T_ROCKS", "T_SMALL_BOULDERS", "T_LARGE_BOULDERS",
		"T_FLOWER_BED", "T_TREES",
		"T_OAK", "T_PINE", "T_MAPLE", "T_BIRCH", "T_CACTUS", "T_FESCUE",
		"T_CATTAILS", "T_SHRUB", "T_PALM", "T_DEAD_TREE", "T_HEATHER",
	]
	assert_eq(shader_tokens.size(), 19, "All 19 requested terrain tiles are accounted for")

	# None of the 19 tiles blends across open edges into neighbours; each keeps its
	# own boundary class id so same-type tiles connect seamlessly while any
	# different terrain tile type draws a border.
	var boundary_start := shader.find("float boundary_class(")
	var boundary_end := shader.find("float differs(", boundary_start)
	var boundary_fn := shader.substr(boundary_start, boundary_end - boundary_start)
	assert_false(boundary_fn.contains("is_rocks("),
		"Rocks, Small Boulders and Large Boulders do not share a boundary class")
	assert_false(boundary_fn.contains("is_tree("),
		"Different tree tiles do not share a boundary class")

	var turf_start := shader.find("bool is_turf(")
	var turf_end := shader.find("bool is_inset(", turf_start)
	var turf_fn := shader.substr(turf_start, turf_end - turf_start)
	assert_false(turf_fn.contains("T_DEEP_ROUGH"),
		"Deep Rough borders Pot Bunker and Stream instead of running unbordered into them")

	var inset_pred_start := shader.find("bool is_inset(")
	var inset_pred_end := shader.find("bool carries(", inset_pred_start)
	var inset_pred := shader.substr(inset_pred_start, inset_pred_end - inset_pred_start)
	for token in ["is_rocks", "T_WASTE_BUNKER", "T_BRUSH", "is_tree", "T_FLOWER_BED", "T_DEEP_ROUGH"]:
		assert_false(inset_pred.contains(token),
			"%s fills the full tile rather than sitting inset over surrounding turf" % token)

	var inset_fn_start := shader.find("vec3 inset_tile(")
	var inset_fn_end := shader.find("vec3 neighbour_surface(", inset_fn_start)
	var inset_fn := shader.substr(inset_fn_start, inset_fn_end - inset_fn_start)
	assert_false(inset_fn.contains("mix(own, outside"),
		"inset_tile() no longer blends bordered tiles into surrounding turf")

	# Each of the 19 tiles has its own full-tile procedural texture branch.
	var stony_start := shader.find("vec3 stony_surface(")
	var brush_start := shader.find("vec3 brush_surface(", stony_start)
	var flower_start := shader.find("vec3 flower_bed_surface(", brush_start)
	var tree_start := shader.find("vec3 tree_ground(", flower_start)
	var border_start := shader.find("vec3 tile_border(", tree_start)
	assert_gt(stony_start, 0, "stony_surface() paints full-tile stone textures")
	assert_gt(brush_start, stony_start, "brush_surface() paints full-tile scrub bushes")
	assert_gt(flower_start, brush_start, "flower_bed_surface() paints full-tile wildflowers")
	assert_gt(tree_start, flower_start, "tree_ground() paints full-tile woodland grounds")
	assert_gt(border_start, tree_start, "tile_border() defines each tile's border")

	var stony_fn := shader.substr(stony_start, brush_start - stony_start)
	assert_true(stony_fn.contains("id == T_ROCKS") and stony_fn.contains("id == T_SMALL_BOULDERS"),
		"All three stony tiles have distinct ground and stone treatments")

	var tree_fn := shader.substr(tree_start, border_start - tree_start)
	for tree_tok in ["T_TREES", "T_OAK", "T_PINE", "T_MAPLE", "T_BIRCH", "T_CACTUS",
			"T_FESCUE", "T_CATTAILS", "T_SHRUB", "T_PALM", "T_DEAD_TREE"]:
		assert_true(tree_fn.contains("id == " + tree_tok),
			"%s has its own dedicated ground branch in tree_ground()" % tree_tok)

	# Every one of the 19 tiles applies its own distinct border via the exact same
	# `edge = 1.0 - smoothstep(EDGE_LIP_LO, EDGE_LIP_HI, cover)` sizing as Bunker.
	var surface_start := shader.find("vec3 surface(")
	var surface_end := shader.find("float is_wet(", surface_start)
	var surface_fn := shader.substr(surface_start, surface_end - surface_start)
	assert_true(surface_fn.contains("float edge = 1.0 - smoothstep(EDGE_LIP_LO, EDGE_LIP_HI, cover);"),
		"surface() computes the shared Bunker lip edge curve")
	assert_true(surface_fn.contains("if (is_bordered_tile(id)) {")
		and surface_fn.contains("tile_border(id, world / tile_size, grain), edge"),
		"All 19 bordered tiles apply tile_border() across the Bunker-sized `edge` band")
	for surf_branch in ["id == T_DEEP_ROUGH", "id == T_WASTE_BUNKER", "is_rocks(id)",
			"id == T_BRUSH", "id == T_FLOWER_BED", "is_tree(id)"]:
		assert_true(surface_fn.contains(surf_branch),
			"surface() paints full-tile texture for %s" % surf_branch)

	var border_fn := shader.substr(border_start, shader.find("// ---", border_start) - border_start)
	for tok in ["T_DEEP_ROUGH", "T_WASTE_BUNKER", "T_BRUSH", "T_ROCKS", "T_SMALL_BOULDERS",
			"T_LARGE_BOULDERS", "T_FLOWER_BED", "T_TREES", "T_OAK", "T_PINE", "T_MAPLE",
			"T_BIRCH", "T_CACTUS", "T_FESCUE", "T_CATTAILS", "T_SHRUB", "T_PALM", "T_DEAD_TREE"]:
		assert_true(border_fn.contains("id == " + tok),
			"tile_border() gives %s its own border branch" % tok)

	var vec_re := RegEx.new()
	vec_re.compile("vec3\\((0\\.\\d+),\\s*(0\\.\\d+),\\s*(0\\.\\d+)\\)")
	var border_colors: Array[Vector3] = []
	for m in vec_re.search_all(border_fn):
		var c := Vector3(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))
		if c == Vector3(0.30, 0.28, 0.26):
			continue  # Birch's dark lenticel fleck accent
		border_colors.append(c)
	assert_eq(border_colors.size(), 19, "19 primary border colors for the 19 tiles")
	var bunker_lip := Vector3(0.35, 0.40, 0.24)
	for i in range(border_colors.size()):
		assert_gt(border_colors[i].distance_to(bunker_lip), 0.08,
			"Border %d is distinct from Bunker's own lip color" % i)
		for j in range(i + 1, border_colors.size()):
			assert_gt(border_colors[i].distance_to(border_colors[j]), 0.08,
				"Borders %d and %d are distinct from each other" % [i, j])

func test_bunker_is_a_raked_bowl_sunk_into_its_lip() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/course_surface.gdshader")
	assert_false(source.is_empty(), "The course surface shader is readable")

	# One rim, measured from the edges the tile shares with other terrain: two
	# bunker tiles side by side are one floor, so only different ground is rim.
	var rim_start := source.find("float bunker_rim(")
	var rim_end := source.find("float bunker_lip(", rim_start)
	assert_gt(rim_start, 0, "bunker_rim() measures the pit's rim")
	assert_gt(rim_end, rim_start, "bunker_rim() is complete")
	var rim_fn := source.substr(rim_start, rim_end - rim_start)
	for edge in ["1.0 - q.x", "1.0 - q.y", "q.x", "q.y"]:
		assert_true(rim_fn.contains("mix(9.0, %s, open_edges." % edge),
			"Each edge only counts as rim where the tile meets other ground")
	assert_true(rim_fn.contains("smin("), "The rim's corners are rounded into a pit")

	# The lip is the shared edge band, so it stays exactly as wide as every
	# other bordered tile's border and a stream's bank rim.
	var lip_start := source.find("float bunker_lip(")
	var lip_end := source.find("vec3 bunker_bowl(", lip_start)
	assert_gt(lip_end, lip_start, "bunker_lip() is complete")
	var lip_fn := source.substr(lip_start, lip_end - lip_start)
	assert_true(lip_fn.contains("smoothstep(-FRINGE, FRINGE, -rim)"),
		"The lip runs in the shared FRINGE band")
	assert_true(lip_fn.contains("smoothstep(EDGE_LIP_LO, EDGE_LIP_HI, cover)"),
		"The lip fades in across the same coverage as every other bordered tile")

	# The bowl is lit as a pit: the sun's reach across it is measured by
	# stepping the sand toward the light, so the side the lip shades is dark and
	# the rest of the floor is lit.
	var bowl_start := source.find("vec3 bunker_bowl(")
	var bowl_end := source.find("vec3 surface(", bowl_start)
	assert_gt(bowl_start, 0, "bunker_bowl() shades the bowl")
	assert_gt(bowl_end, bowl_start, "bunker_bowl() is complete")
	var bowl_fn := source.substr(bowl_start, bowl_end - bowl_start)
	assert_true(bowl_fn.contains("bunker_rim(q + GROUND_LIGHT * BUNKER_SUN_STEP, open_edges)"),
		"The lip's shade is measured by stepping the rim toward the sun")
	assert_true(bowl_fn.contains("float sun = smoothstep(0.0, 0.30,"),
		"The lip between the sand and the sun shades it, and the rest of the pit is lit")
	assert_true(bowl_fn.contains("sin(rim * BUNKER_RAKE_ARCS"),
		"The floor is raked in arcs that follow the lip")
	assert_true(bowl_fn.contains("float shade = smoothstep(0.24, BUNKER_LIP_FOOT - 0.02, rim)"),
		"The sand darkens into the lip's contact shadow, so the pit keeps an edge")
	assert_true(bowl_fn.contains("return mix(turf, floor_sand, 1.0 - lip);"),
		"The grass lip sits over the sand it stands on")
	assert_true(bowl_fn.contains("BUNKER_SUN_STEP") or source.contains("const float BUNKER_SUN_STEP"),
		"The sun step is a named tuning lever")

	# The fragment shades a Bunker with it, and only a Bunker.
	var fragment := source.substr(source.find("void fragment()"))
	assert_true(fragment.contains("if (a == 7.0) {") and fragment.contains(
		"own = bunker_bowl(own, f, open_edges, tile_world, grain, patch);"),
		"A Bunker's own tile is shaded as a bowl")

	# A Bunker still keeps the border every other bordered tile draws: its lip
	# grass is mixed in at the open edges by surface().
	var surface_start := source.find("vec3 surface(")
	var bunker_branch_start := source.find("} else if (id == 7.0) {", surface_start)
	var bunker_branch_end := source.find("} else if (id == 8.0) {", bunker_branch_start)
	assert_gt(bunker_branch_end, bunker_branch_start, "The Bunker branch of surface() is complete")
	var bunker_branch := source.substr(bunker_branch_start, bunker_branch_end - bunker_branch_start)
	assert_true(bunker_branch.contains("base = mix(base, lip_turf(world, grain, patch), edge * 0.94);"),
		"A Bunker's open edges show its lip grass, drawn on the shared edge band")
	assert_false(bunker_branch.contains("vec3(0.35, 0.40, 0.24)"),
		"`vec3(0.35, 0.40, 0.24)` is the shared lip turf, not a colour written twice")

	# That lip grass is the turf the bordered tiles' borders are built from.
	var lip_turf_start := source.find("vec3 lip_turf(")
	var lip_turf_end := source.find("bool keeps_own_turf(", lip_turf_start)
	assert_gt(lip_turf_end, lip_turf_start, "lip_turf() is complete")
	var lip_turf_fn := source.substr(lip_turf_start, lip_turf_end - lip_turf_start)
	assert_true(lip_turf_fn.contains("bank_turf(world, grain, patch)"),
		"The lip is rough turf, the same grass a stream's banks keep")
	assert_true(source.contains("const vec3 BUNKER_LIP_TURF = vec3(0.35, 0.40, 0.24);"),
		"The lip settles toward the olive the bordered tiles draw their own borders in")
