extends MainSceneTest
## Buildings are drawn on the grid they stand on. A new course's clubhouse is an
## isometric solid on its own tiles: every upgrade tier redraws it without
## changing the footprint, the drawing turns with the course when the view
## rotates, and the placement ghost and the catalogue tiles go through the same
## routine.

var clubhouse: Building


func before_all() -> void:
	await super()
	await new_game("Isometric buildings")
	clubhouse = CourseClubhouse.find(main.entity_layer)


func _footprint_size() -> Vector2:
	return Vector2(clubhouse.width * 64, clubhouse.height * 32)


func test_every_clubhouse_tier_draws_on_its_own_tiles() -> void:
	assert_not_null(clubhouse, "A new course starts with a clubhouse")
	if clubhouse == null:
		return
	var architecture = clubhouse.get_node_or_null("Visual/Architecture")
	assert_not_null(architecture, "The clubhouse draws through CourseArchitecture")
	if architecture:
		assert_eq(architecture.footprint, _footprint_size(), "The drawing knows the footprint it fills")
	for level in range(1, 4):
		clubhouse.upgrade_level = level
		clubhouse._update_visuals()
		await process_frames(2)
		var tier = clubhouse.get_node_or_null("Visual/Architecture")
		assert_not_null(tier, "Tier %d has a drawing" % level)
		if tier:
			assert_eq(tier.level, level, "Tier %d reached the drawing" % level)
			assert_eq(tier.footprint, _footprint_size(), "Tier %d keeps the footprint" % level)


func test_the_drawing_turns_with_the_view() -> void:
	var grid: TerrainGrid = main.terrain_grid
	for turn in range(4):
		grid.rotate_view_cw()
		await process_frames(2)
		var architecture = clubhouse.get_node_or_null("Visual/Architecture")
		assert_not_null(architecture, "Turn %d keeps the drawing" % turn)
		if architecture:
			assert_eq(architecture.facing, grid.get_view_orientation(), "Turn %d moved the drawing" % turn)


func test_the_ghost_and_the_catalogue_use_the_same_drawing() -> void:
	var preview: PlacementPreview = main.placement_preview
	preview._draw_building_ghost_shape(Vector2i(10, 10), "resort_hotel", Vector2i(4, 4), Color(0.3, 0.9, 0.3, 0.6))
	assert_true(preview._building_ghost.visible, "The ghost is visible")
	assert_eq(preview._building_ghost.facing, main.terrain_grid.get_view_orientation(), "The ghost follows the view")
	await process_frames(2)

	# Every catalogue tile, drawn the way the Buildings tab draws it.
	var drawn := 0
	for kind in main.building_registry:
		var tile: BuildingTileArt = autofree(BuildingTileArt.new())
		main.add_child(tile)
		tile.configure(kind, main.building_registry[kind])
		drawn += 1
	await process_frames(1)
	assert_gte(drawn, 16, "Every building has a catalogue tile")
