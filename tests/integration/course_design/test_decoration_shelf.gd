extends MainSceneTest
## Decorations live on the toolbar's Improvements tab: every decoration is a
## tile there, picking one starts placement straight away, a locked ornament
## stays unselectable and says what it needs, and no separate picker window
## opens any more.

var toolbar: TerrainToolbar
var placements: PlacementManager
var registry: Dictionary


func before_all() -> void:
	await super()
	await new_game("Decoration shelf")
	toolbar = main.terrain_toolbar
	placements = main.placement_manager
	registry = JSON.parse_string(FileAccess.get_file_as_string("res://data/decorations.json"))["decorations"]


## A tile near the clubhouse a decoration may stand on, or (-1, -1).
func _placement_tile() -> Vector2i:
	var clubhouse := CourseClubhouse.find(main.entity_layer)
	for radius in range(3, 10):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var pos: Vector2i = clubhouse.grid_position + Vector2i(dx, dy)
				if placements.can_place_at(pos, main.terrain_grid):
					return pos
	return Vector2i(-1, -1)


func test_decorations_open_as_a_toolbar_tab_with_the_whole_catalogue() -> void:
	# O still opens the decorations — as the toolbar tab, not a popup window.
	main._on_decoration_placement_pressed()
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.IMPROVEMENTS, "Decorations open the Improvements tab")
	assert_eq(placements.placement_mode, PlacementManager.PlacementMode.NONE,
		"Opening the tab does not start a placement")
	for child in main.get_children():
		assert_false(child is Window, "Decorations no longer open a separate window")

	# The shelf carries the whole catalogue, locked ornaments included, with the
	# walking path leading its top row.
	assert_eq(toolbar._decoration_shelf.get_child_count(), registry.size() + 1,
		"Every decoration is a tile on the shelf, after the leading path tile")
	assert_eq(toolbar._decoration_shelf.columns, ceili(float(registry.size() + 1) / 2.0),
		"The shelf is laid out in two interlocking rows")
	assert_eq(toolbar._decoration_shelf.get_child(0), toolbar._path_tile, "The path tile leads the honeycomb")
	assert_eq(toolbar._path_tile.text, "", "The path is drawn as a course tile, not a labelled button")
	assert_null(toolbar._path_tile.icon, "and carries no icon")


func test_a_locked_ornament_never_starts_placement() -> void:
	# The statue needs a 4-star course.
	GameManager.course_rating["stars"] = 1
	toolbar.refresh_decoration_unlocks()
	var locked = toolbar._decoration_tiles["golfer_statue"]
	assert_true(locked.disabled, "The 4-star statue locks while the course holds one star")
	assert_string_contains(locked.tool_description, "4★ rating", "The tile says what it still needs")
	locked.pressed.emit()
	assert_eq(placements.placement_mode, PlacementManager.PlacementMode.NONE, "A locked ornament never starts placement")
	GameManager.course_rating["stars"] = 5
	toolbar.refresh_decoration_unlocks()
	assert_false(locked.disabled, "Meeting the requirement unlocks the tile")


func test_a_tile_places_its_decoration_at_the_catalogue_price() -> void:
	var tile = toolbar._decoration_tiles["ball_washer"]
	tile.pressed.emit()
	assert_eq(placements.placement_mode, PlacementManager.PlacementMode.DECORATION,
		"Pressing a decoration tile starts decoration placement")
	assert_eq(placements.selected_decoration_type, "ball_washer", "Placement uses the tile's decoration")
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.IMPROVEMENTS, "Picking a tile keeps the tab open")

	var pos := _placement_tile()
	assert_ne(pos, Vector2i(-1, -1), "A legal decoration tile exists near the clubhouse")
	if pos == Vector2i(-1, -1):
		return
	var cash := GameManager.money
	main._handle_placement_click(pos)
	assert_not_null(main.entity_layer.get_decoration_at(pos), "The clicked tile carries the decoration")
	assert_eq(GameManager.money, cash - int(registry["ball_washer"]["cost"]), "The Ball Washer costs its catalogue price")
