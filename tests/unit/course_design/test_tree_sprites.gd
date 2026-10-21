extends GameTest
## The four angles of a tree (TreeOverlay's N / E / S / W sprites).
##
## Every species ships four views — `<species>_n.png` and its `_e`, `_s`, `_w`
## rotations, generated from the authored north drawing by
## `tools/tree_art/generate.py` — and the overlay paints one of them on each
## tile: the course's view orientation stepped by that tree's own quarter-turn
## offset, so a wood holds several angles at once while a turn of the course
## still takes every tree on to its next view. These tests pin the lookup and
## the stepping: all four views exist for every species and season, they are
## four genuinely different images on the one canvas (so a trunk never hops
## across its tile when the view turns), and the per-tree angles are mixed,
## fixed to the tile, and rotated with the grid's view.

# Mid-season days of the first year (see test_season_system.gd for the edges).
const SPRING_DAY := 100
const SUMMER_DAY := 200
const FALL_DAY := 300
const WINTER_DAY := 350


func before_each() -> void:
	super()
	GameManager.set_seasons_enabled(true)


# ---------------------------------------------------------------------------
# The four views exist, and are four images rather than one worn four ways
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
			seen[path] = true


func test_the_four_views_are_different_images_on_the_same_canvas() -> void:
	# An asymmetric pair: a leaning palm and a broadleaf. The canopy's
	# highlights and limbs move between angles, but the canvas — and so the
	# ground line TreeOverlay anchors to the tile — never does.
	for species in ["oak", "palm"]:
		var images: Array = []
		var size := Vector2.ZERO
		for facing in range(TreeOverlay.FACINGS.size()):
			var path := TreeOverlay.sprite_path(species, SUMMER_DAY,
					CourseTheme.Type.PARKLAND, facing)
			var texture := load(path) as Texture2D
			assert_not_null(texture, "%s loads from %s" % [species, path])
			if size == Vector2.ZERO:
				size = texture.get_size()
			assert_eq(texture.get_size(), size,
					"every angle of %s keeps the authored canvas" % species)
			images.append(hash(texture.get_image().get_data()))
		for facing in range(1, TreeOverlay.FACINGS.size()):
			assert_ne(images[facing], images[0],
					"the %s view of %s is drawn differently from the north view"
					% [TreeOverlay.facing_name(facing), species])


func test_the_north_view_is_the_authored_drawing() -> void:
	# Orientation 0 is the course's default view: it must keep wearing the
	# art as authored, so the unsuffixed and the _n sprite are one image.
	# (The unsuffixed drawing is the summer art; look the north view up on a
	# summer day so the comparison is of the same season's image.)
	var authored := (load(TreeOverlay.SPRITE_DIR + "oak.png") as Texture2D).get_image().get_data()
	var north_path := TreeOverlay.sprite_path("oak", SUMMER_DAY, CourseTheme.Type.PARKLAND,
			TreeOverlay.DEFAULT_FACING)
	var north := (load(north_path) as Texture2D).get_image().get_data()
	assert_eq(hash(north), hash(authored), "the north view is the authored oak, unchanged")
	assert_same(TreeOverlay.texture_for("oak"), TreeOverlay.texture_for("oak", 0),
			"and naming no angle (the toolbar's preview) means the north view")


# ---------------------------------------------------------------------------
# The seasonal wardrobe turns too
# ---------------------------------------------------------------------------

func test_deciduous_views_come_from_the_season_folder() -> void:
	var seasons := {SPRING_DAY: "spring", FALL_DAY: "fall", WINTER_DAY: "winter"}
	for day in seasons:
		for facing in range(TreeOverlay.FACINGS.size()):
			var expected := "%s%s/oak_%s.png" % [TreeOverlay.SPRITE_DIR, seasons[day],
					TreeOverlay.facing_name(facing)]
			assert_eq(TreeOverlay.sprite_path("oak", day, CourseTheme.Type.PARKLAND, facing),
					expected, "a %s oak viewed from %s wears its %s art"
					% [seasons[day], TreeOverlay.facing_name(facing), seasons[day]])


func test_a_snowy_pine_turns_with_the_view_and_a_desert_one_does_not_melt() -> void:
	for facing in range(TreeOverlay.FACINGS.size()):
		var angle := TreeOverlay.facing_name(facing)
		assert_eq(TreeOverlay.sprite_path("pine", WINTER_DAY, CourseTheme.Type.PARKLAND, facing),
				"%swinter/pine_%s.png" % [TreeOverlay.SPRITE_DIR, angle],
				"a parkland pine keeps its snow from the %s" % angle)
		assert_eq(TreeOverlay.sprite_path("pine", WINTER_DAY, CourseTheme.Type.DESERT, facing),
				"%spine_%s.png" % [TreeOverlay.SPRITE_DIR, angle],
				"a desert pine never held snow, from any angle")


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
		assert_gt(counts[facing], tiles / 8.0,
				"the %s angle covers a fair share of the wood"
				% TreeOverlay.facing_name(facing))
	assert_gt(turned, neighbours / 2.0,
			"and neighbours face different ways rather than striping the wood")
