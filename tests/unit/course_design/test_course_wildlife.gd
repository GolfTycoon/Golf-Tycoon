extends GameTest
## Course wildlife: duck families on ponds and butterflies over wild flowers —
## where they may live, the routes they keep to, and how the season and the
## weather bring them out.

var grid: TerrainGrid

func before_each() -> void:
	super()
	GameManager.entity_layer = null
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	await process_frames(1)

func after_each() -> void:
	await process_frames(1)
	super()

func test_habitats_are_bounded_repeatable_and_do_not_modify_course_or_rng() -> void:
	grid.begin_batch()
	for x in range(16):
		for y in range(16):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.WATER if x < 8 else TerrainTypes.Type.FLOWER_BED)
	grid.end_batch_quiet()
	var saved := grid.serialize()
	seed(9123)
	var expected := randi()
	seed(9123)
	grid._wildlife.rebuild()
	assert_eq(randi(), expected, "Residents must not change simulation randomness")
	var ducks := grid._wildlife._duck_homes.duplicate()
	var gardens := grid._wildlife._garden_homes.duplicate()
	assert_gt(ducks.size(), 0)
	assert_lte(ducks.size(), CourseWildlife.MAX_DUCK_FAMILIES)
	assert_lte(gardens.size(), CourseWildlife.MAX_GARDENS)
	grid._wildlife.rebuild()
	assert_eq(grid._wildlife._duck_homes, ducks)
	assert_eq(grid._wildlife._garden_homes, gardens)
	assert_eq(grid.serialize(), saved)

func test_repainting_a_pond_removes_its_family() -> void:
	for x in range(6, 9):
		for y in range(6, 9):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.WATER)
	grid._wildlife._refresh_residents()
	assert_eq(grid._wildlife._duck_homes.size(), 1)
	var home: Vector2i = grid._wildlife._duck_homes[0]
	grid.set_tile(home, TerrainTypes.Type.FAIRWAY)
	grid._wildlife._refresh_residents()
	assert_false(grid._wildlife._duck_homes.has(home))
	grid.deserialize({})
	EventBus.load_completed.emit(true)
	assert_true(grid._wildlife._duck_homes.is_empty(), "Loading a dry course must clear old water residents")

func test_duck_family_route_stays_within_its_water_tile() -> void:
	for step in range(128):
		var offset := CourseWildlife.duck_offset(float(step) / 128.0 * TAU)
		assert_lt(absf(offset.x) + 12.0, 32.0, "Including beak/tail, ducks fit within a 64px water tile")
		assert_lt(absf(offset.y) + 4.0, 16.0, "Waterline stays within the 32px tile")

func test_season_and_weather_control_visitors() -> void:
	# With no day/night cycle, butterflies are out whenever it's fair season
	# and dry; fireflies (a dusk/night effect) were removed entirely.
	assert_true(CourseWildlife.butterflies_active(SeasonSystem.Season.SUMMER, false))
	assert_false(CourseWildlife.butterflies_active(SeasonSystem.Season.WINTER, false))
	assert_false(CourseWildlife.butterflies_active(SeasonSystem.Season.SPRING, true))
	assert_true(CourseWildlife.butterflies_active(SeasonSystem.Season.FALL, false))

func test_painting_and_clearing_wild_flowers_updates_visitors() -> void:
	# Wild Flowers are the only garden habitat now that the ornamental
	# decorations have left the Improvements tab.
	var pos := Vector2i(8, 8)
	grid.set_tile(pos, TerrainTypes.Type.FLOWER_BED)
	assert_true(grid._wildlife._habitats_dirty, "Painting flowers invalidates the habitat cache")
	grid._wildlife._process(0.3 * Engine.time_scale)
	assert_true(grid._wildlife._garden_homes.has(pos), "Wild Flowers attract a garden resident")
	grid.set_tile(pos, TerrainTypes.Type.GRASS)
	assert_true(grid._wildlife._habitats_dirty, "Paving the bed over invalidates the habitat cache")
	grid._wildlife._process(0.3 * Engine.time_scale)
	assert_false(grid._wildlife._garden_homes.has(pos))
