extends GameTest
## The four angles of a tree (TreeOverlay's N / E / S / W sprites).
##
## Every core species ships four independently authored views —
## `<species>_n.png` and its `_e`, `_s`, `_w` siblings — and the overlay paints
## the matching facing on each tile. Their canvases may differ; `layout.json`
## keeps each view scaled and anchored to its own dimensions. These tests pin
## the lookup and stepping: every facing loads, the layout adapts to image size,
## and per-tree angles stay mixed, fixed to the tile and rotated with the grid.
##
## A season's drawings are not the core's: they ship inside the Seasons mod
## (`mods/golf_tycoon.seasons/tree_art/<season>/`) and reach the lookup through
## its manifest's `tree_art_root`, so the last section here pins that door too —
## the mod's art is worn, a later mod's replaces it, art from outside the
## imported project is decoded from its bytes, and a game without the mod stays
## evergreen all year.

# Mid-season days of the first year (see test_season_system.gd for the edges).
const SPRING_DAY := 100
const SUMMER_DAY := 200
const FALL_DAY := 300
const WINTER_DAY := 350

## Where the Seasons mod keeps the wardrobe it lends the trees.
const SEASONS_MOD_ROOT := "res://mods/golf_tycoon.seasons"
const SEASONS_ART := SEASONS_MOD_ROOT + "/tree_art/"
const USER_TREE_SPRITES_MOD_ROOT := "res://mods/example.tree_sprites"
const USER_TREE_SPRITES_ART := USER_TREE_SPRITES_MOD_ROOT + "/tree_art/"

## Throwaway art folders, for the registration tests (cleaned up after each).
const TEMP_ART := "user://ut_tree_art"


func before_each() -> void:
	super()
	GameManager.set_seasons_enabled(true)


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

func test_every_species_has_a_sprite_from_each_angle() -> void:
	for type in TerrainTypes.TREE_SPECIES_TILES:
		var species := TerrainTypes.get_tree_species(type)
		var seen: Dictionary = {}
		for facing in range(TreeOverlay.FACINGS.size()):
			var path := TreeOverlay.sprite_path(species, SUMMER_DAY,
					CourseTheme.Type.PARKLAND, facing)
			assert_true(path.ends_with("_%s.png" % TreeOverlay.facing_name(facing)),
					"%s has its %s view (%s)" % [species, TreeOverlay.facing_name(facing), path])
			assert_false(seen.has(path), "and it is its own file, not a repeat of another angle")
			assert_not_null(TreeOverlay.texture_at(path), "and the sprite loads")
			seen[path] = true


func test_different_canvas_sizes_use_a_dimension_relative_ground_anchor() -> void:
	var oak_sizes: Array[Vector2] = []
	for facing in range(TreeOverlay.FACINGS.size()):
		var path := TreeOverlay.sprite_path("oak", SUMMER_DAY,
				CourseTheme.Type.PARKLAND, facing)
		var texture := TreeOverlay.texture_at(path)
		assert_not_null(texture, "the oak's %s view loads" % TreeOverlay.facing_name(facing))
		var source_size := texture.get_size()
		var scale := TreeOverlay.art_scale(path)
		var anchor := TreeOverlay.art_anchor_offset("oak", path, source_size)
		assert_almost_eq(anchor.x, 0.0, 0.0001, "the trunk is horizontally centred")
		assert_almost_eq(anchor.y, source_size.y * scale * 0.5, 0.0001,
				"the layout anchors this canvas at its own bottom edge")
		oak_sizes.append(source_size)
	assert_ne(oak_sizes[0], oak_sizes[1],
			"the supplied views have different canvas dimensions")


func test_the_default_view_uses_the_authored_north_file() -> void:
	var north_path := TreeOverlay.sprite_path("oak", SUMMER_DAY, CourseTheme.Type.PARKLAND,
			TreeOverlay.DEFAULT_FACING)
	assert_eq(north_path, TreeOverlay.SPRITE_DIR + "oak_n.png",
			"orientation zero wears the authored north sprite")
	assert_not_null(TreeOverlay.texture_at(north_path))
	assert_same(TreeOverlay.texture_for("oak"), TreeOverlay.texture_for("oak", 0),
			"and naming no angle (the toolbar's preview) means the north view")


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
			var angle := TreeOverlay.facing_name(facing)
			var expected := "%s%s/oak_%s.png" % [SEASONS_ART, seasons[day], angle]
			assert_eq(TreeOverlay.sprite_path("oak", day, CourseTheme.Type.PARKLAND, facing),
					expected, "a %s oak viewed from %s wears the mod's %s art"
					% [seasons[day], angle, seasons[day]])
			assert_not_null(TreeOverlay.texture_at(expected),
					"and that file is readable from inside the mod")


func test_a_snowy_pine_turns_with_the_view_and_a_desert_one_does_not_melt() -> void:
	for facing in range(TreeOverlay.FACINGS.size()):
		var angle := TreeOverlay.facing_name(facing)
		assert_eq(TreeOverlay.sprite_path("pine", WINTER_DAY, CourseTheme.Type.PARKLAND, facing),
				"%swinter/pine_%s.png" % [SEASONS_ART, angle],
				"a parkland pine keeps its snow from the %s" % angle)
		assert_eq(TreeOverlay.sprite_path("pine", WINTER_DAY, CourseTheme.Type.DESERT, facing),
				"%spine_%s.png" % [TreeOverlay.SPRITE_DIR, angle],
				"a desert pine never held snow, from any angle")


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
			var angle := TreeOverlay.facing_name(facing)
			var expected := "%s%s_%s.png" % [USER_TREE_SPRITES_ART, species, angle]
			assert_true(FileAccess.file_exists(expected), "the pack ships %s" % expected)
			assert_almost_eq(TreeOverlay.art_scale(expected), float(expected_scales[species]), 0.0001,
					"the layout scales %s without changing its PNG" % species)
			assert_almost_eq(TreeOverlay.art_offset_y(expected), float(expected_offsets[species]), 0.0001,
					"the layout lifts %s onto its terrain ground line" % species)
			for day in [SPRING_DAY, SUMMER_DAY, FALL_DAY, WINTER_DAY]:
				assert_eq(TreeOverlay.sprite_path(species, day, CourseTheme.Type.PARKLAND, facing),
						expected, "%s's %s view is replaced on day %d" % [species, angle, day])
	# The pine rule normally keeps mild-weather pines on evergreen art; a full
	# replacement is deliberately above that seasonal decision too.
	assert_eq(TreeOverlay.sprite_path("pine", SPRING_DAY, CourseTheme.Type.DESERT, 0),
			"%spine_n.png" % USER_TREE_SPRITES_ART)


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


func test_a_season_the_mod_only_partly_drew_falls_back_to_its_own_north_view() -> void:
	var root := TEMP_ART.path_join("partly")
	var authored := _write_art(root, "fall/palm.png", Color.ORANGE)
	TreeOverlay.register_mod_art("tester.early", root)
	for facing in range(TreeOverlay.FACINGS.size()):
		assert_eq(TreeOverlay.art_file("fall/palm", facing), authored,
				"every angle wears the one drawing the mod shipped")
	TreeOverlay.unregister_mod_art("tester.early")


func test_a_north_only_sprite_pack_fills_its_missing_angles() -> void:
	var root := TEMP_ART.path_join("north_only")
	var north := _write_art(root, "palm_n.png", Color.GREEN)
	TreeOverlay.register_mod_art("tester.north_only", root)
	for facing in range(TreeOverlay.FACINGS.size()):
		assert_eq(TreeOverlay.sprite_override_file("palm", facing), north,
				"the north-only pack covers the %s angle" % TreeOverlay.facing_name(facing))
	TreeOverlay.unregister_mod_art("tester.north_only")


func test_art_layout_can_scale_and_anchor_one_view_without_editing_its_png() -> void:
	var root := TEMP_ART.path_join("layout")
	var path := _write_art(root, "oak_n.png", Color.WHITE)
	var seasonal_path := _write_art(root, "winter/oak_e.png", Color.WHITE)
	var layout := FileAccess.open(root.path_join("layout.json"), FileAccess.WRITE)
	layout.store_string("""{
		"scale": 0.5,
		"species": {"oak": {"scale": 0.4}},
		"sprites": {"oak_n": {"scale": 0.3, "ground_x": 70, "ground_y": 150,
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
	var path := _write_art(root, "palm_e.png", Color.WHITE)
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
# The angle itself: wrapping, the fallback, and following the course's view
# ---------------------------------------------------------------------------

func test_orientations_wrap_round_the_compass() -> void:
	assert_eq(TreeOverlay.facing_name(0), "n")
	assert_eq(TreeOverlay.facing_name(1), "e")
	assert_eq(TreeOverlay.facing_name(2), "s")
	assert_eq(TreeOverlay.facing_name(3), "w")
	assert_eq(TreeOverlay.facing_name(4), "n", "a full turn is north again")
	assert_eq(TreeOverlay.facing_name(-1), "w", "one turn back from north is west")
	assert_eq(TreeOverlay.sprite_path("oak", SUMMER_DAY, CourseTheme.Type.PARKLAND, -1),
			TreeOverlay.sprite_path("oak", SUMMER_DAY, CourseTheme.Type.PARKLAND, 3),
			"and the lookup wraps with the naming")


func test_a_species_with_no_art_at_any_angle_has_no_sprite() -> void:
	assert_eq(TreeOverlay.sprite_path("no_such_tree", SUMMER_DAY, CourseTheme.Type.PARKLAND, 1),
			"", "so the tile falls back to its silhouette, turned the same way")
	assert_null(TreeOverlay.texture_for("no_such_tree", 1))


func test_the_overlay_draws_the_angle_the_course_is_viewed_from() -> void:
	var grid := make_grid(8, 8)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	assert_eq(trees.view_facing(), 0, "a fresh course is viewed from the north")
	grid.rotate_view_cw()
	assert_eq(trees.view_facing(), 1, "one clockwise turn of the course turns the wood to its east view")
	grid.rotate_view_cw()
	assert_eq(trees.view_facing(), 2, "and again to its south view")
	grid.rotate_view_ccw()
	assert_eq(trees.view_facing(), 1, "turning back retraces the angles")
	grid.set_view_orientation(3)
	assert_eq(trees.view_facing(), 3, "a loaded view orientation is honoured too")


func test_rotating_the_view_changes_the_texture_a_tree_is_drawn_with() -> void:
	var grid := make_grid(8, 8)
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.PALM)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	var worn: Dictionary = {}
	for step in range(4):
		var texture := TreeOverlay.texture_for("palm", trees.view_facing())
		assert_not_null(texture, "the palm has art at orientation %d" % trees.view_facing())
		assert_false(worn.has(texture.resource_path),
				"orientation %d draws a view the earlier orientations did not" % trees.view_facing())
		worn[texture.resource_path] = true
		grid.rotate_view_cw()
	assert_eq(worn.size(), 4, "a full turn of the course walks the palm through all four angles")


# ---------------------------------------------------------------------------
# Every tree stands at its own angle
# ---------------------------------------------------------------------------

## A wood is not a plantation all facing the camera: whichever way the course
## is viewed, the trees on one screen are drawn from all four angles at once.
func test_a_wood_is_drawn_from_every_angle_whichever_way_it_is_viewed() -> void:
	for view in range(TreeOverlay.FACINGS.size()):
		var seen: Dictionary = {}
		for x in range(8):
			for y in range(8):
				seen[TreeOverlay.facing_at(Vector2i(x, y), view)] = true
		for facing in range(TreeOverlay.FACINGS.size()):
			assert_true(seen.has(facing),
					"viewed from the %s, a wood still shows trees from the %s"
					% [TreeOverlay.facing_name(view), TreeOverlay.facing_name(facing)])


## Turning the screen keeps the promise of the four views: every tree moves on
## to its next angle — one step, not two, and never staying on the angle it was
## just drawn from — and a full turn brings each one back to where it began.
func test_rotating_the_course_steps_every_tree_to_its_next_angle() -> void:
	var angles := TreeOverlay.FACINGS.size()
	for x in range(6):
		for y in range(6):
			var pos := Vector2i(x, y)
			for view in range(angles):
				var here := TreeOverlay.facing_at(pos, view)
				var next := TreeOverlay.facing_at(pos, view + 1)
				assert_eq(next, wrapi(here + 1, 0, angles),
						"the tree on %s turns on to its next angle" % pos)
				assert_ne(next, here, "and never stays at the angle it was drawn from")
			assert_eq(TreeOverlay.facing_at(pos, angles), TreeOverlay.facing_at(pos, 0),
					"a full turn brings the tree on %s back to its first angle" % pos)


## The offset is the tile's own: fixed for the life of the course, so the wood
## does not reshuffle between redraws, reloads or seasons — only the turn of the
## course moves it.
func test_a_trees_angle_belongs_to_its_tile() -> void:
	var grid := make_grid(8, 8)
	for x in range(8):
		for y in range(8):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.PINE)
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	assert_eq(trees._tree_tiles.size(), grid.grid_width * grid.grid_height,
			"the overlay is drawing the whole plantation")
	var first: Dictionary = {}
	for pos in trees._tree_tiles:
		first[pos] = trees.facing_for(pos)
		# The sprite of that angle is the one it wears: the same tile asked
		# again (a redraw, a reload, a season change) answers the same.
		assert_eq(TreeOverlay.facing_at(pos, trees.view_facing()), first[pos],
				"the pine on %s keeps its angle" % pos)
		var path := TreeOverlay.sprite_path("pine", SUMMER_DAY, CourseTheme.Type.PARKLAND,
				first[pos])
		assert_true(path.ends_with("_%s.png" % TreeOverlay.facing_name(first[pos])),
				"and wears its %s art (%s)" % [TreeOverlay.facing_name(first[pos]), path])
	# A rescan rebuilds the wood from the tiles; the angles must survive it.
	trees.rescan()
	for pos in first:
		assert_eq(trees.facing_for(pos), first[pos],
				"a rescan leaves the pine on %s as it was" % pos)


## Neighbouring trees do not march in step: a plain linear seed would stripe the
## wood with diagonals of identically turned trees, and one angle would cover a
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
				"the %s angle covers a fair share of the wood"
				% TreeOverlay.facing_name(facing))
	assert_gt(float(turned), neighbours / 2.0,
			"and neighbours face different ways rather than striping the wood")
