extends GameTest
## The four view variants of a tree (TreeOverlay's `_0` to `_3` sprites).
##
## Every core species ships four independently drawn variants —
## `<species>_0.png` and its `_1`, `_2`, `_3` siblings — and each tile wears
## one of them for the life of the course. Their canvases may differ;
## `layout.json` keeps each view scaled and anchored to its own dimensions.
## These tests pin the lookup and the mix: every variant loads, the layout
## adapts to image size, and per-tree variants stay mixed, fixed to the tile
## and unchanged as the grid turns.
##
## A season's drawings are not the core's: they ship inside the Seasons mod
## (`repository/packages/golf_tycoon.seasons/tree_art/<season>/`) and reach the
## lookup through its manifest's `tree_art_root`, so the last section here pins
## that door too — the mod's art is worn, a later mod's replaces it, art from
## outside the imported project is decoded from its bytes, and a game without
## the mod stays evergreen all year.

# Mid-season days of the first year (see test_season_system.gd for the edges).
const SPRING_DAY := 100
const SUMMER_DAY := 200
const FALL_DAY := 300
const WINTER_DAY := 350

## Where the Seasons mod keeps the wardrobe it lends the trees.
const SEASONS_MOD_ROOT := "res://repository/packages/golf_tycoon.seasons"
const SEASONS_ART := SEASONS_MOD_ROOT + "/tree_art/"
const USER_TREE_SPRITES_MOD_ROOT := "res://repository/packages/example.tree_sprites"
const USER_TREE_SPRITES_ART := USER_TREE_SPRITES_MOD_ROOT + "/tree_art/"

## Throwaway art folders, for the registration tests (cleaned up after each).
const TEMP_ART := "user://ut_tree_art"


func before_all() -> void:
	# The season lookup itself answers to the Seasons mod's provider, which
	# only a loaded mod has: install the official set as a player's Browse
	# Mods session leaves it.
	install_environment_mods()

func after_all() -> void:
	uninstall_environment_mods()

func before_each() -> void:
	super()
	GameManager.set_seasons_enabled(true)
	# The seasonal wardrobe comes from the Seasons mod; re-apply its package
	# each test (the registration tests below reset the live registries).
	apply_package_content(SEASONS_MOD_ROOT)


func after_each() -> void:
	# The registration tests below write into the live overlay's art registry
	# and into user://; put the shipped set back for every test after this file.
	ModPackage.remove_directory_recursive(TEMP_ART)
	restore_live_content()
	super()


## A one-colour PNG in a temp art folder, and the path it was written to.
func _write_art(root: String, relative: String, color: Color) -> String:
	var path := root.path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.save_png(path)
	return path


# ---------------------------------------------------------------------------
# Every independently-sized view exists, and the layout anchors it by its own dimensions
# ---------------------------------------------------------------------------

func test_every_species_has_a_sprite_for_each_view_variant() -> void:
	for type in TerrainTypes.TREE_SPECIES_TILES:
		var species := TerrainTypes.get_tree_species(type)
		var seen: Dictionary = {}
		for facing in range(TreeOverlay.FACINGS.size()):
			var path := TreeOverlay.sprite_path(species, SUMMER_DAY,
					CourseTheme.Type.PARKLAND, facing)
			assert_true(path.ends_with("_%s.png" % TreeOverlay.facing_name(facing)),
					"%s has its %s variant (%s)" % [species, TreeOverlay.facing_name(facing), path])
			assert_false(seen.has(path), "and it is its own file, not a repeat of another variant")
			assert_not_null(TreeOverlay.texture_at(path), "and the sprite loads")
			seen[path] = true


func test_different_canvas_sizes_use_a_dimension_relative_ground_anchor() -> void:
	var oak_sizes: Array[Vector2] = []
	for facing in range(TreeOverlay.FACINGS.size()):
		var path := TreeOverlay.sprite_path("oak", SUMMER_DAY,
				CourseTheme.Type.PARKLAND, facing)
		var texture := TreeOverlay.texture_at(path)
		assert_not_null(texture, "the oak's %s variant loads" % TreeOverlay.facing_name(facing))
		var source_size := texture.get_size()
		var scale := TreeOverlay.art_scale(path)
		var anchor := TreeOverlay.art_anchor_offset("oak", path, source_size)
		assert_almost_eq(anchor.x, 0.0, 0.0001, "the trunk is horizontally centred")
		assert_almost_eq(anchor.y, source_size.y * scale * 0.5, 0.0001,
				"the layout anchors this canvas at its own bottom edge")
		oak_sizes.append(source_size)
	assert_ne(oak_sizes[0], oak_sizes[1],
			"the supplied views have different canvas dimensions")


func test_the_default_variant_is_the_authored_first_file() -> void:
	var first_path := TreeOverlay.sprite_path("oak", SUMMER_DAY, CourseTheme.Type.PARKLAND,
			TreeOverlay.DEFAULT_FACING)
	assert_eq(first_path, TreeOverlay.SPRITE_DIR + "oak_0.png",
			"variant zero wears the authored first sprite")
	assert_not_null(TreeOverlay.texture_at(first_path))
	assert_same(TreeOverlay.texture_for("oak"), TreeOverlay.texture_for("oak", 0),
			"and naming no variant (the toolbar's preview) means the first drawing")


# ---------------------------------------------------------------------------
# The seasonal wardrobe turns too
# ---------------------------------------------------------------------------

func test_the_seasons_mod_ships_the_wardrobe_the_core_no_longer_does() -> void:
	var manifest := ModManifest.from_json_text(
			FileAccess.get_file_as_string(SEASONS_MOD_ROOT.path_join("mod.json")), SEASONS_MOD_ROOT)
	assert_eq(str(manifest.content.get("tree_art_root", "")), "tree_art",
			"its manifest declares the folder its tree art lives in")
	for season in ["spring", "fall", "winter"]:
		assert_true(DirAccess.dir_exists_absolute(SEASONS_ART + season),
				"the %s drawings ship inside the mod" % season)
		assert_false(DirAccess.dir_exists_absolute(TreeOverlay.SPRITE_DIR + season),
				"and the core keeps no %s folder of its own" % season)


func test_the_seasonal_views_come_from_the_seasons_mod() -> void:
	var seasons := {SPRING_DAY: "spring", FALL_DAY: "fall", WINTER_DAY: "winter"}
	for day in seasons:
		for facing in range(TreeOverlay.FACINGS.size()):
			var variant := TreeOverlay.facing_name(facing)
			var expected := "%s%s/oak_%s.png" % [SEASONS_ART, seasons[day], variant]
			assert_eq(TreeOverlay.sprite_path("oak", day, CourseTheme.Type.PARKLAND, facing),
					expected, "a %s oak in its %s variant wears the mod's %s art"
					% [seasons[day], variant, seasons[day]])
			assert_not_null(TreeOverlay.texture_at(expected),
					"and that file is readable from inside the mod")


func test_a_snowy_pine_wears_its_variant_and_a_desert_one_does_not_melt() -> void:
	for facing in range(TreeOverlay.FACINGS.size()):
		var variant := TreeOverlay.facing_name(facing)
		assert_eq(TreeOverlay.sprite_path("pine", WINTER_DAY, CourseTheme.Type.PARKLAND, facing),
				"%swinter/pine_%s.png" % [SEASONS_ART, variant],
				"a parkland pine keeps its snow in the %s variant" % variant)
		assert_eq(TreeOverlay.sprite_path("pine", WINTER_DAY, CourseTheme.Type.DESERT, facing),
				"%spine_%s.png" % [TreeOverlay.SPRITE_DIR, variant],
				"a desert pine never held snow, in any variant")


func test_the_user_tree_sprite_pack_replaces_every_species_view_all_year() -> void:
	# The example deliberately contains only root-level art. That makes it an
	# all-season replacement rather than a four-folder seasonal wardrobe.
	var manifest := ModManifest.from_json_text(
			FileAccess.get_file_as_string(USER_TREE_SPRITES_MOD_ROOT.path_join("mod.json")),
			USER_TREE_SPRITES_MOD_ROOT)
	assert_true(manifest.is_valid(), "the complete user-art pack is a valid mod")
	assert_eq(str(manifest.content.get("tree_art_root", "")), "tree_art")
	ContentRegistry.apply_mod_content(manifest.id, USER_TREE_SPRITES_MOD_ROOT, manifest.content)

	var expected_scales := {
		"birch": 0.45, "bush": 0.32, "cactus": 0.50, "cattails": 0.42,
		"dead_tree": 0.46, "fescue": 0.27, "heather": 0.26, "maple": 0.44,
		"oak": 0.41, "palm": 0.45, "pine": 0.49,
	}
	var expected_offsets := {
		"birch": -11.0, "bush": -5.0, "cactus": -13.0, "cattails": -9.0,
		"dead_tree": -9.0, "fescue": -5.0, "heather": -3.0, "maple": -9.0,
		"oak": -9.0, "palm": -8.0, "pine": -15.0,
	}
	for type in TerrainTypes.TREE_SPECIES_TILES:
		var species := TerrainTypes.get_tree_species(type)
		for facing in range(TreeOverlay.FACINGS.size()):
			var variant := TreeOverlay.facing_name(facing)
			var expected := "%s%s_%s.png" % [USER_TREE_SPRITES_ART, species, variant]
			assert_true(FileAccess.file_exists(expected), "the pack ships %s" % expected)
			assert_almost_eq(TreeOverlay.art_scale(expected), float(expected_scales[species]), 0.0001,
					"the layout scales %s without changing its PNG" % species)
			assert_almost_eq(TreeOverlay.art_offset_y(expected), float(expected_offsets[species]), 0.0001,
					"the layout lifts %s onto its terrain ground line" % species)
			for day in [SPRING_DAY, SUMMER_DAY, FALL_DAY, WINTER_DAY]:
				assert_eq(TreeOverlay.sprite_path(species, day, CourseTheme.Type.PARKLAND, facing),
						expected, "%s's %s variant is replaced on day %d" % [species, variant, day])
	# The pine rule normally keeps mild-weather pines on evergreen art; a full
	# replacement is deliberately above that seasonal decision too.
	assert_eq(TreeOverlay.sprite_path("pine", SPRING_DAY, CourseTheme.Type.DESERT, 0),
			"%spine_0.png" % USER_TREE_SPRITES_ART)


# ---------------------------------------------------------------------------
# The door the art comes through: registration, load order and raw files
# ---------------------------------------------------------------------------

func test_a_later_mod_wins_the_season_it_repeats() -> void:
	# A palm: no shipped mod dresses one, so the two temp mods below are the
	# only art this season and species has — and any species can be given a
	# wardrobe, not just the ones the game's own calendar turns.
	var early := _write_art(TEMP_ART.path_join("early"), "spring/palm.png", Color.RED)
	var late := _write_art(TEMP_ART.path_join("late"), "spring/palm.png", Color.BLUE)
	TreeOverlay.register_mod_art("tester.early", TEMP_ART.path_join("early"))
	assert_eq(TreeOverlay.art_file("spring/palm", TreeOverlay.DEFAULT_FACING), early,
			"a registered folder answers for its season and species")
	TreeOverlay.register_mod_art("tester.late", TEMP_ART.path_join("late"))
	assert_eq(TreeOverlay.art_file("spring/palm", TreeOverlay.DEFAULT_FACING), late,
			"the later mod in the load order wins the drawing it repeats")
	TreeOverlay.unregister_mod_art("tester.late")
	assert_eq(TreeOverlay.art_file("spring/palm", TreeOverlay.DEFAULT_FACING), "",
			"and holds the slot alone: a mod set that changes is re-applied whole, in order")
	TreeOverlay.unregister_mod_art("tester.early")
	assert_eq(TreeOverlay.art_file("spring/palm", TreeOverlay.DEFAULT_FACING), "",
			"so with both gone the species has no spring art to wear")
	assert_eq(TreeOverlay.register_mod_art("tester.early", TEMP_ART.path_join("nothing")), 0,
			"a folder that is not there registers nothing")


func test_a_season_the_mod_only_partly_drew_falls_back_to_its_own_first_view() -> void:
	var root := TEMP_ART.path_join("partly")
	var authored := _write_art(root, "fall/palm.png", Color.ORANGE)
	TreeOverlay.register_mod_art("tester.early", root)
	for facing in range(TreeOverlay.FACINGS.size()):
		assert_eq(TreeOverlay.art_file("fall/palm", facing), authored,
				"every variant wears the one drawing the mod shipped")
	TreeOverlay.unregister_mod_art("tester.early")


func test_a_first_view_only_sprite_pack_fills_its_missing_variants() -> void:
	var root := TEMP_ART.path_join("first_only")
	var first := _write_art(root, "palm_0.png", Color.GREEN)
	TreeOverlay.register_mod_art("tester.first_only", root)
	for facing in range(TreeOverlay.FACINGS.size()):
		assert_eq(TreeOverlay.sprite_override_file("palm", facing), first,
				"the first-view-only pack covers the %s variant" % TreeOverlay.facing_name(facing))
	TreeOverlay.unregister_mod_art("tester.first_only")


## Art published before the variants were numbered files them as `_n`..`_w`.
## Those packs keep working, and a folder that carries both spellings draws the
## numbered file.
func test_the_old_compass_suffixes_still_answer_for_their_variants() -> void:
	# A palm: no shipped mod dresses one, so the temp folders below are the
	# only art this species has in either shelf.
	var root := TEMP_ART.path_join("legacy")
	var second := _write_art(root, "palm_e.png", Color.BLUE)
	var seasonal := _write_art(root, "winter/palm_w.png", Color.AQUA)
	TreeOverlay.register_mod_art("tester.legacy", root)
	for facing in range(TreeOverlay.FACINGS.size()):
		var expected := second if facing == 1 else ""
		assert_eq(TreeOverlay.sprite_override_file("palm", facing), expected,
				"the old `_e` file answers for variant 1 only")
	assert_eq(TreeOverlay.art_file("winter/palm", 3), seasonal,
			"and a seasonal wardrobe may use the old spelling too")
	var numbered := _write_art(root, "palm_1.png", Color.RED)
	TreeOverlay.register_mod_art("tester.legacy", root)
	assert_eq(TreeOverlay.sprite_override_file("palm", 1), numbered,
			"but a numbered file wins when a folder has both spellings")
	TreeOverlay.unregister_mod_art("tester.legacy")


func test_a_first_view_only_pack_of_the_old_spelling_fills_every_variant() -> void:
	var root := TEMP_ART.path_join("legacy_first_only")
	var north := _write_art(root, "palm_n.png", Color.GREEN)
	TreeOverlay.register_mod_art("tester.legacy_first_only", root)
	for facing in range(TreeOverlay.FACINGS.size()):
		assert_eq(TreeOverlay.sprite_override_file("palm", facing), north,
				"an old `_n`-only pack covers the %s variant" % TreeOverlay.facing_name(facing))
	TreeOverlay.unregister_mod_art("tester.legacy_first_only")


func test_art_layout_can_scale_and_anchor_one_view_without_editing_its_png() -> void:
	var root := TEMP_ART.path_join("layout")
	var path := _write_art(root, "oak_0.png", Color.WHITE)
	var seasonal_path := _write_art(root, "winter/oak_1.png", Color.WHITE)
	var layout := FileAccess.open(root.path_join("layout.json"), FileAccess.WRITE)
	layout.store_string("""{
		"scale": 0.5,
		"species": {"oak": {"scale": 0.4}},
		"sprites": {"oak_0": {"scale": 0.3, "ground_x": 70, "ground_y": 150,
			"offset_x": 3, "offset_y": -7}}
	}""")
	layout.close()
	TreeOverlay.register_mod_art("tester.layout", root)
	assert_eq(TreeOverlay.sprite_path("oak", SPRING_DAY, CourseTheme.Type.PARKLAND, 0), path)
	assert_almost_eq(TreeOverlay.art_scale(path), 0.3, 0.0001,
			"a view-specific scale wins over species and root defaults")
	assert_almost_eq(TreeOverlay.art_base_offset("oak", path, Vector2(100, 200)), 15.0, 0.0001,
			"ground_y is measured in source pixels, then follows the draw scale")
	assert_eq(TreeOverlay.art_anchor_offset("oak", path, Vector2(100.0, 200.0)), Vector2(6.0, 15.0),
			"ground_x and ground_y position the exact source pixel on the terrain")
	assert_almost_eq(TreeOverlay.art_offset_x(path), 3.0, 0.0001,
			"offset_x is a direct post-scale nudge")
	assert_almost_eq(TreeOverlay.art_offset_y(path), -7.0, 0.0001,
			"offset_y is a direct post-scale nudge for a low or high sprite")
	assert_eq(TreeOverlay.art_file("winter/oak", 1), seasonal_path)
	assert_almost_eq(TreeOverlay.art_scale(seasonal_path), 0.4, 0.0001,
			"the species rule styles the same tree in a seasonal wardrobe too")
	TreeOverlay.unregister_mod_art("tester.layout")
	assert_almost_eq(TreeOverlay.art_scale(path), 1.0, 0.0001,
			"unloading the mod forgets its layout with its art")
	assert_almost_eq(TreeOverlay.art_offset_x(path), 0.0, 0.0001,
			"and the horizontal nudge leaves with the mod too")
	assert_almost_eq(TreeOverlay.art_offset_y(path), 0.0, 0.0001,
			"and the vertical nudge leaves with the mod too")


func test_art_from_outside_the_imported_project_is_decoded_from_its_bytes() -> void:
	# An installed or Workshop copy of a mod is never imported by Godot, so its
	# art has to load from the file itself — the contract ModAPI.load_texture
	# gives mods that read their own pictures. Root-level art takes the same path.
	var root := TEMP_ART.path_join("raw")
	var path := _write_art(root, "palm_1.png", Color.WHITE)
	assert_false(ResourceLoader.exists(path), "a file in user:// has no imported resource")
	assert_eq(TreeOverlay.register_mod_art("tester.raw", root), 1, "and it still registers")
	var texture := TreeOverlay.texture_at(TreeOverlay.sprite_path("palm", SPRING_DAY,
			CourseTheme.Type.PARKLAND, 1))
	assert_not_null(texture, "so the overlay decodes its bytes")
	assert_eq(texture.get_size(), Vector2(8.0, 8.0), "and the pixels are the file's own")
	TreeOverlay.unregister_mod_art("tester.raw")
	assert_null(TreeOverlay.texture_at(path), "its texture goes when the mod does")


func test_a_game_without_the_seasons_mod_wears_evergreen_art_all_year() -> void:
	TreeOverlay.clear_mod_art()
	for day in [SPRING_DAY, FALL_DAY, WINTER_DAY]:
		for facing in range(TreeOverlay.FACINGS.size()):
			assert_eq(TreeOverlay.sprite_path("oak", day, CourseTheme.Type.PARKLAND, facing),
					"%soak_%s.png" % [TreeOverlay.SPRITE_DIR, TreeOverlay.facing_name(facing)],
					"with no mod art registered the oak keeps the drawing the game ships")
	assert_eq(TreeOverlay.art_file("spring/oak", 0), "",
			"and a season nobody registered has no art at all")


# ---------------------------------------------------------------------------
# The variant itself: wrapping, the fallback, and what the course's view does
# ---------------------------------------------------------------------------

func test_variant_names_wrap_round_the_four_drawings() -> void:
	assert_eq(TreeOverlay.facing_name(0), "0")
	assert_eq(TreeOverlay.facing_name(1), "1")
	assert_eq(TreeOverlay.facing_name(2), "2")
	assert_eq(TreeOverlay.facing_name(3), "3")
	assert_eq(TreeOverlay.facing_name(4), "0", "a full turn of four wraps back to 0")
	assert_eq(TreeOverlay.facing_name(-1), "3", "one step back from 0 wraps to 3")
	assert_eq(TreeOverlay.sprite_path("oak", SUMMER_DAY, CourseTheme.Type.PARKLAND, -1),
			TreeOverlay.sprite_path("oak", SUMMER_DAY, CourseTheme.Type.PARKLAND, 3),
			"and the lookup wraps with the naming")


func test_a_species_with_no_art_at_any_variant_has_no_sprite() -> void:
	assert_eq(TreeOverlay.sprite_path("no_such_tree", SUMMER_DAY, CourseTheme.Type.PARKLAND, 1),
			"", "so the tile falls back to its silhouette, shaped the same way")
	assert_null(TreeOverlay.texture_for("no_such_tree", 1))


func test_the_overlay_follows_the_course_view_orientation() -> void:
	GameManager.set_gradual_view_rotation(false)
	var grid := make_grid(8, 8)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	assert_eq(trees.view_facing(), 0, "a fresh course is viewed from orientation 0")
	grid.rotate_view_cw()
	assert_eq(trees.view_facing(), 1, "one clockwise turn of the course moves to 1")
	grid.rotate_view_cw()
	assert_eq(trees.view_facing(), 2, "and again to 2")
	grid.rotate_view_ccw()
	assert_eq(trees.view_facing(), 1, "turning back retraces the orientations")
	grid.set_view_orientation(3)
	assert_eq(trees.view_facing(), 3, "a loaded view orientation is honoured too")


func test_fractional_view_angles_pick_the_nearest_quarter_turn() -> void:
	var grid := make_grid(8, 8)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	grid.set_view_angle(0.25)
	assert_eq(trees.view_facing(), 0, "angles under 45 degrees keep orientation 0")
	grid.set_view_angle(0.6)
	assert_eq(trees.view_facing(), 1, "crossing 45 degrees moves to orientation 1")
	grid.set_view_angle(3.7)
	assert_eq(trees.view_facing(), 0, "angles past 315 degrees wrap to 0")


func test_rotating_the_view_keeps_each_tree_on_its_assigned_sprite() -> void:
	GameManager.set_gradual_view_rotation(false)
	var grid := make_grid(8, 8)
	var tile := Vector2i(3, 3)
	grid.set_tile(tile, TerrainTypes.Type.PALM)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	var assigned_variant := trees.facing_for(tile)
	var assigned_texture := TreeOverlay.texture_for("palm", assigned_variant)
	for step in range(4):
		assert_eq(trees.facing_for(tile), assigned_variant,
				"course orientation %d does not change the tree's variant" % trees.view_facing())
		assert_same(TreeOverlay.texture_for("palm", trees.facing_for(tile)), assigned_texture,
				"the tree keeps the same texture through every turn")
		grid.rotate_view_cw()


func test_tree_lean_rotates_around_its_tile_without_turning_the_tree_over() -> void:
	var grid := make_grid(8, 8)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	var original := Vector2(3.0, -2.0)
	var tile := Vector2i(3, 3)
	assert_eq(trees._tile_surface_offset(tile, original), original,
			"the default flat view keeps the tile offset")
	grid.set_view_orientation(2)
	assert_eq(trees._tile_surface_offset(tile, original), -original,
			"a half turn moves the lean to the opposite side of its planted point")


func test_repainting_a_tree_species_redraws_its_existing_sprite() -> void:
	var grid := make_grid(8, 8)
	var tile := Vector2i(3, 3)
	grid.set_tile(tile, TerrainTypes.Type.OAK)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	trees._sync_visuals()
	var visual := trees._visuals[tile] as Node2D
	await process_frames(2)  # Let the oak's first cached draw finish.

	var sprite_redrawn := [false]
	visual.draw.connect(func(): sprite_redrawn[0] = true)
	grid.set_tile(tile, TerrainTypes.Type.PINE)
	await process_frames(2)

	assert_eq(trees._tree_tiles[tile], "pine", "the terrain index has the replacement species")
	assert_same(trees._visuals[tile], visual, "the renderer still reuses the visible tree node")
	assert_true(sprite_redrawn[0], "and that node paints the pine instead of keeping the cached oak")


# ---------------------------------------------------------------------------
# Every tree wears its own variant
# ---------------------------------------------------------------------------

## A wood is not a plantation of identical canopies: whichever way the course
## is viewed, the trees on one screen wear all four variants at once.
func test_a_wood_shows_every_variant_whichever_way_it_is_viewed() -> void:
	for view in range(TreeOverlay.FACINGS.size()):
		var seen: Dictionary = {}
		for x in range(8):
			for y in range(8):
				seen[TreeOverlay.facing_at(Vector2i(x, y), view)] = true
		for facing in range(TreeOverlay.FACINGS.size()):
			assert_true(seen.has(facing),
					"viewed from orientation %s, a wood still shows variant %s"
					% [view, TreeOverlay.facing_name(facing)])


## Every tree keeps its deterministic tile variant at each course orientation.
func test_tree_sprite_variant_stays_fixed_across_course_turns() -> void:
	var angles := TreeOverlay.FACINGS.size()
	for x in range(6):
		for y in range(6):
			var pos := Vector2i(x, y)
			var assigned := TreeOverlay.facing_offset(pos)
			for view in range(angles):
				assert_eq(TreeOverlay.facing_at(pos, view), assigned,
						"the tree on %s keeps its sprite at view %d" % [pos, view])


## The offset is the tile's own: fixed for the life of the course, so the wood
## does not reshuffle between redraws, reloads, seasons or turns of the course.
func test_a_trees_variant_belongs_to_its_tile() -> void:
	var grid := make_grid(8, 8)
	for x in range(8):
		for y in range(8):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.PINE)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	assert_eq(trees._tree_tiles.size(), grid.grid_width * grid.grid_height,
			"the overlay indexes the whole plantation")
	var first: Dictionary = {}
	for pos in trees._tree_tiles:
		first[pos] = trees.facing_for(pos)
		# The sprite of that variant is the one it wears: the same tile asked
		# again (a redraw, a reload, a season change) answers the same.
		assert_eq(TreeOverlay.facing_at(pos, trees.view_facing()), first[pos],
				"the pine on %s keeps its variant" % pos)
		var path := TreeOverlay.sprite_path("pine", SUMMER_DAY, CourseTheme.Type.PARKLAND,
				first[pos])
		assert_true(path.ends_with("_%s.png" % TreeOverlay.facing_name(first[pos])),
				"and wears its %s art (%s)" % [TreeOverlay.facing_name(first[pos]), path])
	# A rescan rebuilds the wood from the tiles; the variants must survive it.
	trees.rescan()
	for pos in first:
		assert_eq(trees.facing_for(pos), first[pos],
				"a rescan leaves the pine on %s as it was" % pos)

func test_only_visible_tree_tiles_have_nodes_and_pan_reuses_them() -> void:
	var grid := make_grid(64, 64)
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.PINE
	var camera := Camera2D.new()
	camera.zoom = Vector2(4.0, 4.0)
	camera.position = grid.grid_to_screen_center(Vector2i(16, 16))
	grid.add_child(camera)
	camera.make_current()
	await process_frames(2)

	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	trees.rescan()
	assert_eq(trees._tree_tiles.size(), grid.grid_width * grid.grid_height,
		"the lightweight terrain index still covers every tree")
	assert_lt(trees._visuals.size(), trees._tree_tiles.size(),
		"only trees inside the camera range get CanvasItems")
	var first_ids: Dictionary = {}
	for visual in trees._visuals.values():
		first_ids[visual.get_instance_id()] = true

	camera.position = grid.grid_to_screen_center(Vector2i(52, 52))
	await process_frames(2)
	trees.update_visible_trees()
	var reused := false
	for visual in trees._visuals.values():
		if first_ids.has(visual.get_instance_id()):
			reused = true
			break
	assert_true(reused, "panning recycles nearby tree visual nodes")
	assert_lte(trees._pooled_visuals.size(), TreeOverlay.MAX_POOLED_VISUALS,
		"the hidden visual pool has a fixed memory ceiling")


## Neighbouring trees do not march in step: a plain linear seed would stripe the
## wood with diagonals of identical drawings, and one variant would cover a
## corner of the course while another went unseen.
func test_the_offsets_are_mixed_across_the_wood() -> void:
	var counts: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}
	var neighbours := 0
	var turned := 0
	for x in range(16):
		for y in range(16):
			var facing := TreeOverlay.facing_offset(Vector2i(x, y))
			counts[facing] += 1
			if x > 0:
				neighbours += 1
				if facing != TreeOverlay.facing_offset(Vector2i(x - 1, y)):
					turned += 1
	var tiles := 16 * 16
	for facing in range(TreeOverlay.FACINGS.size()):
		assert_gt(float(counts[facing]), tiles / 8.0,
				"the %s variant covers a fair share of the wood"
				% TreeOverlay.facing_name(facing))
	assert_gt(float(turned), neighbours / 2.0,
			"and neighbours wear different drawings rather than striping the wood")
