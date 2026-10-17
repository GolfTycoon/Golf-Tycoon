extends GameTest
## The ground the Course Map draws: a colour key of the course, tile for tile,
## the same one the minimap draws with and the course surface is painted with.
##
## The texture the map builds is read back here and sampled tile by tile, so what
## is checked is the real painting rather than the palette that feeds it: water
## reads as water, a bunker as sand, woodland as the theme's dark trees.

var grid: TerrainGrid
var view: CourseMapView

const SIDE := 16


func before_each() -> void:
	super()
	# The live palette is a static the running game fills from the theme (and,
	# with a colourblind mode on, from the remapped colours). Pin it to the
	# course's own theme so the colours under test are the ones the game applies.
	TerrainPalette.set_theme_colors(CourseTheme.get_terrain_colors(GameManager.current_theme))
	grid = make_grid(SIDE, SIDE)
	fill_grid(grid, TerrainTypes.Type.GRASS)
	GameManager.terrain_grid = grid
	view = CourseMapView.new()
	add_child_autofree(view)
	view.size = Vector2(480, 360)
	await process_frames(1)
	view.refresh()


## The palette's floats sit between the steps of an 8-bit image, so a colour read
## back out of the texture is compared channel by channel rather than by hex.
func _assert_painted(got: Color, expected: Color, text: String) -> void:
	assert_almost_eq(got.r, expected.r, 0.01, text + " (red)")
	assert_almost_eq(got.g, expected.g, 0.01, text + " (green)")
	assert_almost_eq(got.b, expected.b, 0.01, text + " (blue)")


## The colour the map's texture holds for one tile.
func _painted(tile: Vector2i) -> Color:
	view._ensure_texture()
	var image: Image = view._map_texture.get_image()
	var side := image.get_width()
	var px := mini(side - 1, int((float(tile.x) + 0.5) / float(SIDE) * float(side)))
	var py := mini(side - 1, int((float(tile.y) + 0.5) / float(SIDE) * float(side)))
	return image.get_pixel(px, py)


## Sample the texture at the UV assigned to a tile's position on the drawn
## diamond. Sampling the image alone misses a texture stretched over the wrong
## polygon: all the visible tiles then read from the same tiny patch of it.
func _projected_color(tile: Vector2i) -> Color:
	view._ensure_texture()
	var quad := view._terrain_polygon()
	var across: Vector2 = quad[1] - quad[0]
	var down: Vector2 = quad[3] - quad[0]
	var offset: Vector2 = view._local_of_grid(Vector2(tile) + Vector2(0.5, 0.5)) - quad[0]
	var uv := Vector2(offset.cross(down), across.cross(offset)) / across.cross(down)
	var image: Image = view._map_texture.get_image()
	return image.get_pixel(
		clampi(floori(uv.x * image.get_width()), 0, image.get_width() - 1),
		clampi(floori(uv.y * image.get_height()), 0, image.get_height() - 1))


func test_the_map_paints_every_tile_with_the_colour_of_its_terrain() -> void:
	var painted := {
		Vector2i(3, 4): TerrainTypes.Type.BUNKER,
		Vector2i(8, 9): TerrainTypes.Type.WATER,
		Vector2i(12, 2): TerrainTypes.Type.TREES,
		Vector2i(1, 14): TerrainTypes.Type.GREEN,
		Vector2i(6, 6): TerrainTypes.Type.GRASS,
	}
	for tile in painted:
		grid.set_tile(tile, int(painted[tile]))
	for tile in painted:
		var terrain_type: int = painted[tile]
		_assert_painted(_painted(tile), CourseSurface.map_color(terrain_type),
			"tile %d, %d reads as %s" % [tile.x, tile.y, TerrainTypes.get_type_name(terrain_type)])


func test_projected_tiles_keep_their_distinct_colours_in_every_orientation() -> void:
	# The image can contain all the right colours yet look uniform if its quad
	# uses world-pixel bounds instead of the grid's tile counts. Check the four
	# corners used for drawing AND the colour sampled at projected tile centres.
	var painted := {
		Vector2i(3, 4): TerrainTypes.Type.BUNKER,
		Vector2i(8, 9): TerrainTypes.Type.WATER,
		Vector2i(12, 2): TerrainTypes.Type.TREES,
		Vector2i(1, 14): TerrainTypes.Type.GREEN,
	}
	for tile in painted:
		grid.set_tile(tile, int(painted[tile]))
	var corners := [Vector2.ZERO, Vector2(SIDE, 0), Vector2(SIDE, SIDE), Vector2(0, SIDE)]
	for orientation in range(GridProjection.ORIENTATION_COUNT):
		grid.set_view_orientation(orientation)
		var quad := view._terrain_polygon()
		for i in range(4):
			assert_eq(quad[i], view._local_of_grid(corners[i]),
				"the texture's corner %d follows the grid in orientation %d" % [i, orientation])
		for tile in painted:
			_assert_painted(_projected_color(tile), CourseSurface.map_color(int(painted[tile])),
				"%s tile at %s in orientation %d" % [TerrainTypes.get_type_name(int(painted[tile])), tile, orientation])
		_assert_painted(_projected_color(Vector2i(6, 6)), CourseSurface.map_color(TerrainTypes.Type.GRASS),
			"grass still fills the rest of the course in orientation %d" % orientation)


func test_the_ground_stays_coloured_under_a_walking_path() -> void:
	# A trail is laid on the tile rather than painted into it, so the map draws
	# the trail colour over that one tile and leaves its neighbours alone.
	grid.set_tile(Vector2i(4, 4), TerrainTypes.Type.ROUGH)
	assert_true(grid.set_walking_path(Vector2i(4, 4), true), "a trail is laid on the rough")
	var trail: Color = CourseTheme.get_terrain_colors(GameManager.current_theme).get("path", CourseMapView.PATH_COLOR)
	_assert_painted(_painted(Vector2i(4, 4)), trail, "the tile under the trail is the trail")
	_assert_painted(_painted(Vector2i(5, 4)), CourseSurface.map_color(TerrainTypes.Type.GRASS),
		"the tile beside it is still grass")


func test_the_two_maps_of_the_course_use_the_same_colours() -> void:
	# The minimap and the Course Map are the same course seen at two sizes: one
	# lookup decides what a tile looks like, and both of them ask it (see
	# CourseSurface.map_color).
	var mini_map := MiniMap.new()
	add_child_autofree(mini_map)
	await process_frames(1)
	view._build_palette()
	for terrain_type in TerrainTypes.Type.values():
		_assert_painted(view._palette[terrain_type], mini_map._terrain_color(terrain_type),
			"%s is the same colour on both maps" % TerrainTypes.get_type_name(terrain_type))


func test_the_map_follows_the_course_theme() -> void:
	# A course playing a different theme is a different colour of ground, and the
	# map is repainted with it rather than keeping the palette it first read.
	var fairway := Vector2i(7, 7)
	grid.set_tile(fairway, TerrainTypes.Type.FAIRWAY)
	var by_theme := {}
	for theme in CourseTheme.Type.values():
		TerrainPalette.set_theme_colors(CourseTheme.get_terrain_colors(theme))
		view._texture_dirty = true
		var painted := _painted(fairway)
		by_theme[painted.to_html(false)] = true
		_assert_painted(painted, CourseTheme.get_terrain_colors(theme)["fairway_light"],
			"%s fairway" % CourseTheme.to_string_name(theme))
	assert_gt(by_theme.size(), 1, "a different theme is a different colour of ground")


func test_the_modes_only_lightly_dim_what_the_course_looks_like() -> void:
	# The map is read for the colours on it, so the wash each mode lays over the
	# ground is kept light - deep enough for the mode's own marks to read, never
	# deep enough to turn the course grey. The aura leans on the mood instead.
	assert_lt(CourseMapView.SCRIM_LAND, 0.1, "the land mode barely dims the course")
	assert_lt(CourseMapView.SCRIM_OVERLAY, 0.1, "so do the routing and staff modes")
	assert_lt(CourseMapView.LAND_LOCKED_FILL.a, 0.3, "land out of reach is dimmed, not blacked out")
	assert_gt(CourseMapView.SCRIM_AURA, CourseMapView.SCRIM_LAND,
		"the aura mode hands the map to the golfers' mood")


func test_the_tile_grid_is_there_when_it_is_worth_counting() -> void:
	assert_lt(CourseMapView.TILE_GRID_MIN_PX, CourseMapView.TILE_GRID_FULL_PX,
		"the grid fades in as the tiles grow")
	assert_lt(CourseMapView.TILE_GRID_COLOR.a, 0.5, "the grid stays a hairline under the terrain colours")
	# What decides the grid is how big a tile is drawn, not the zoom factor: a
	# small map at 3x has smaller tiles than a big one at 1x.
	view.size = Vector2(80, 70)
	view.fit()
	assert_lt(view.tile_pixels().x, CourseMapView.TILE_GRID_MIN_PX, "a squeezed map: the tiles are too small")
	view.size = Vector2(1200, 900)
	view.fit()
	assert_gt(view.tile_pixels().x, CourseMapView.TILE_GRID_MIN_PX, "a roomy one: the tiles are countable")


func test_the_legend_names_the_ground_the_course_is_made_of() -> void:
	# The map is a colour key of the tiles, so the key has to say what the
	# colours are called - and to name only what is really there.
	for tile in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]:
		grid.set_tile(tile, TerrainTypes.Type.BUNKER)
	grid.set_tile(Vector2i(9, 9), TerrainTypes.Type.WATER)
	var key := view.terrain_key()
	assert_gt(key.size(), 0, "the course has ground to name")
	var labels: Array = key.map(func(entry): return entry["label"])
	assert_true(labels.has(TerrainTypes.get_type_name(TerrainTypes.Type.GRASS)),
		"the grass the course is mostly made of is in the key: %s" % str(labels))
	assert_true(labels.has(TerrainTypes.get_type_name(TerrainTypes.Type.BUNKER)),
		"and the bunkers")
	assert_false(labels.has(TerrainTypes.get_type_name(TerrainTypes.Type.WATER)),
		"a single tile of water is not worth a chip in the key")
	# Every chip wears the colour that tile is painted with, and the biggest
	# patch of ground comes first.
	var cover := view.terrain_cover()
	assert_eq(int(cover[0]["type"]), TerrainTypes.Type.GRASS, "the ground covering most of the course leads")
	for entry in key:
		var found := false
		for terrain in cover:
			if str(terrain["label"]) == str(entry["label"]):
				_assert_painted(entry["color"], terrain["color"], "%s has the colour it is painted with" % entry["label"])
				found = true
		assert_true(found, "%s is a terrain type on this course" % entry["label"])


func test_the_legend_key_follows_the_mode() -> void:
	# The aura map is the golfers' mood over a dimmed course, so its key stays
	# about the comments; the other modes key the ground they are drawn on.
	view.set_mode(CourseMapView.Mode.AURA)
	for entry in view.legend_entries():
		assert_false(str(entry["label"]) == TerrainTypes.get_type_name(TerrainTypes.Type.GRASS),
			"no terrain chips in the aura's key")
	for mode in [CourseMapView.Mode.LAND, CourseMapView.Mode.ROUTING, CourseMapView.Mode.STAFF]:
		view.set_mode(mode)
		var labels: Array = view.legend_entries().map(func(entry): return entry["label"])
		assert_true(labels.has(TerrainTypes.get_type_name(TerrainTypes.Type.GRASS)),
			"the ground is keyed in mode %d: %s" % [mode, str(labels)])
