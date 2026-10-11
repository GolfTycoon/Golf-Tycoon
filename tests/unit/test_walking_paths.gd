extends GutTest
## The Path improvement: a thin walking trail laid ON TOP of hostable ground
## (rough, deep rough, waste bunker, brush, rocks/boulders, stream, flower
## bed, trees) that connects dot-to-dot and is paved once it reaches the
## clubhouse.

var grid: TerrainGrid

func before_each() -> void:
	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)
	for x in range(8):
		for y in range(8):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)

# ---------------------------------------------------------------------------
# Placement rules
# ---------------------------------------------------------------------------

func test_walking_paths_only_lay_on_hostable_ground() -> void:
	var hostable: Array = TerrainTypes.WALKING_PATH_TERRAINS
	for t in hostable:
		grid.set_tile(Vector2i(1, 1), t)
		assert_true(grid.can_place_walking_path(Vector2i(1, 1)),
				"%s should host a walking path" % TerrainTypes.get_type_name(t))
		assert_true(grid.set_walking_path(Vector2i(1, 1), true))
		grid.set_walking_path(Vector2i(1, 1), false)

	var unhostable: Array = [
		TerrainTypes.Type.EMPTY, TerrainTypes.Type.GRASS, TerrainTypes.Type.FAIRWAY,
		TerrainTypes.Type.FIRM_FAIRWAY, TerrainTypes.Type.HEAVY_ROUGH,
		TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.BUNKER,
		TerrainTypes.Type.POT_BUNKER, TerrainTypes.Type.WATER,
		TerrainTypes.Type.RETIRED_PATH, TerrainTypes.Type.OUT_OF_BOUNDS,
	]
	for t in unhostable:
		grid.set_tile(Vector2i(2, 2), t)
		assert_false(grid.can_place_walking_path(Vector2i(2, 2)),
				"%s must not host a walking path" % TerrainTypes.get_type_name(t))
		assert_false(grid.set_walking_path(Vector2i(2, 2), true))

func test_placement_refuses_out_of_bounds_tiles() -> void:
	assert_false(grid.set_walking_path(Vector2i(99, 99), true))
	assert_false(grid.set_walking_path(Vector2i(-1, 0), true))
	assert_false(grid.can_place_walking_path(Vector2i(8, 0)))
	assert_ne(grid.walking_path_placement_error(Vector2i(99, 99)), "")

func test_set_walking_path_is_idempotent() -> void:
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.ROUGH)
	watch_signals(grid)
	assert_true(grid.set_walking_path(Vector2i(3, 3), true))
	assert_false(grid.set_walking_path(Vector2i(3, 3), true), "A dot stays a dot")
	assert_signal_emit_count(grid, "walking_paths_changed", 1)
	assert_true(grid.set_walking_path(Vector2i(3, 3), false))
	assert_false(grid.set_walking_path(Vector2i(3, 3), false), "Nothing left to remove")
	assert_signal_emit_count(grid, "walking_paths_changed", 2)

func test_paths_do_not_change_the_tile_terrain() -> void:
	grid.set_tile(Vector2i(4, 4), TerrainTypes.Type.DEEP_ROUGH)
	grid.set_walking_path(Vector2i(4, 4), true)
	assert_eq(grid.get_tile(Vector2i(4, 4)), TerrainTypes.Type.DEEP_ROUGH)
	assert_true(grid.has_walking_path(Vector2i(4, 4)))

func test_painting_non_hostable_ground_removes_the_path() -> void:
	grid.set_tile(Vector2i(5, 5), TerrainTypes.Type.BRUSH)
	grid.set_walking_path(Vector2i(5, 5), true)
	watch_signals(grid)
	grid.set_tile(Vector2i(5, 5), TerrainTypes.Type.FAIRWAY)
	assert_false(grid.has_walking_path(Vector2i(5, 5)))
	assert_signal_emitted(grid, "walking_paths_changed")

func test_painting_more_hostable_ground_keeps_the_path() -> void:
	grid.set_tile(Vector2i(6, 6), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(6, 6), true)
	grid.set_tile(Vector2i(6, 6), TerrainTypes.Type.DEEP_ROUGH)
	assert_true(grid.has_walking_path(Vector2i(6, 6)))

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func test_walking_paths_round_trip_through_save_data() -> void:
	grid.set_tile(Vector2i(1, 2), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(1, 2), true)
	grid.set_walking_path(Vector2i(2, 2), true)
	var saved_paths := grid.serialize_walking_paths()
	assert_eq(saved_paths.size(), 2)

	grid.deserialize({})  # Everything back to grass: the trails' ground is gone.
	grid.deserialize_walking_paths(saved_paths)
	assert_eq(grid.get_walking_paths(), [], "Paths need hostable ground to survive")

	grid.set_tile(Vector2i(1, 2), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.ROUGH)
	grid.deserialize_walking_paths(saved_paths)
	assert_eq(grid.get_walking_paths().size(), 2)
	assert_true(grid.has_walking_path(Vector2i(1, 2)))
	assert_true(grid.has_walking_path(Vector2i(2, 2)))

func test_paths_on_cleared_trees_are_dropped_on_load() -> void:
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.TREES)
	grid.set_walking_path(Vector2i(3, 3), true)
	var saved_paths := grid.serialize_walking_paths()
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.GRASS)  # Tree bulldozed.
	assert_false(grid.has_walking_path(Vector2i(3, 3)))
	grid.deserialize_walking_paths(saved_paths)
	assert_eq(grid.get_walking_paths(), [])

func test_reset_for_new_course_clears_walking_paths() -> void:
	grid.set_tile(Vector2i(2, 2), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(2, 2), true)
	grid.reset_for_new_course()
	assert_eq(grid.get_walking_paths(), [])
	assert_eq(grid.serialize_walking_paths(), [])

# ---------------------------------------------------------------------------
# Clubhouse connection (the paved look)
# ---------------------------------------------------------------------------

func test_component_touching_clubhouse_is_upgraded() -> void:
	var paths := {Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(2, 0): true}
	var edges := {Vector2i(2, 0): true}  # Clubhouse footprint at (3, 0).
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, edges)
	assert_eq(upgraded.size(), 3, "The whole trail reaches the clubhouse")
	for pos in paths:
		assert_true(upgraded.has(pos), "Trail tile %s should be paved" % pos)

func test_disconnected_trail_stays_dirt() -> void:
	var paths := {Vector2i(0, 0): true, Vector2i(5, 5): true}
	var edges := {Vector2i(5, 5): true}  # Clubhouse footprint at (6, 5).
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, edges)
	assert_false(upgraded.has(Vector2i(0, 0)))
	assert_true(upgraded.has(Vector2i(5, 5)))

func test_diagonal_contact_does_not_reach_the_clubhouse() -> void:
	var paths := {Vector2i(0, 0): true}
	# Clubhouse footprint at (1, 1): its edge ring never includes (0, 0).
	var edges := {Vector2i(0, 1): true, Vector2i(1, 0): true}
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, edges)
	assert_eq(upgraded, {})

func test_only_the_trail_that_reaches_the_clubhouse_is_paved() -> void:
	# Two parallel trails; only one touches the clubhouse footprint at (2, 0).
	var paths := {
		Vector2i(0, 0): true, Vector2i(1, 0): true,   # Trail A (reaches the clubhouse)
		Vector2i(0, 3): true, Vector2i(1, 3): true,   # Trail B (no contact)
	}
	var edges := {Vector2i(1, 0): true}
	var upgraded := WalkingPathOverlay.upgraded_component_tiles(paths, edges)
	assert_true(upgraded.has(Vector2i(0, 0)))
	assert_true(upgraded.has(Vector2i(1, 0)))
	assert_false(upgraded.has(Vector2i(0, 3)))
	assert_false(upgraded.has(Vector2i(1, 3)))

# ---------------------------------------------------------------------------
# Clubhouse edge discovery through a real entity layer
# ---------------------------------------------------------------------------

func test_clubhouse_edge_tiles_follow_the_footprint() -> void:
	var overlay: WalkingPathOverlay = grid.get_node_or_null("WalkingPathOverlay") as WalkingPathOverlay
	assert_not_null(overlay, "TerrainGrid must host the walking path overlay")

	var saved_entity_layer = GameManager.entity_layer
	var saved_grid = GameManager.terrain_grid
	GameManager.terrain_grid = grid
	var entities := EntityLayer.new()
	entities.set_terrain_grid(grid)
	add_child_autofree(entities)
	GameManager.entity_layer = entities

	var building := Building.new()
	building.building_type = "clubhouse"
	building.grid_position = Vector2i(4, 4)
	building.width = 2
	building.height = 2
	entities.buildings[Vector2i(4, 4)] = building

	var edges := overlay._clubhouse_edge_tiles()
	# The ring of tiles orthogonally around the 2x2 footprint.
	assert_true(edges.has(Vector2i(3, 4)), "West edge")
	assert_true(edges.has(Vector2i(4, 3)), "North edge")
	assert_true(edges.has(Vector2i(6, 5)), "Southeast corner ring")
	assert_false(edges.has(Vector2i(3, 3)), "Diagonal corners are not edges")
	assert_false(edges.has(Vector2i(2, 2)), "Unrelated tiles are not edges")

	GameManager.entity_layer = saved_entity_layer
	GameManager.terrain_grid = saved_grid

func test_building_signals_update_the_paved_state() -> void:
	var overlay: WalkingPathOverlay = grid.get_node_or_null("WalkingPathOverlay") as WalkingPathOverlay
	assert_not_null(overlay)

	var saved_entity_layer = GameManager.entity_layer
	var saved_grid = GameManager.terrain_grid
	GameManager.terrain_grid = grid
	var entities := EntityLayer.new()
	entities.set_terrain_grid(grid)
	add_child_autofree(entities)
	GameManager.entity_layer = entities

	# A trail with no clubhouse anywhere: dirt.
	grid.set_tile(Vector2i(0, 0), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(1, 0), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(0, 0), true)
	grid.set_walking_path(Vector2i(1, 0), true)
	assert_false(overlay._upgraded_tiles.has(Vector2i(0, 0)), "No clubhouse, no paving")

	# Placing a clubhouse at the trail's end paves the whole trail.
	var building := Building.new()
	building.building_type = "clubhouse"
	building.grid_position = Vector2i(2, 0)
	building.width = 1
	building.height = 1
	entities.buildings[Vector2i(2, 0)] = building
	entities.building_placed.emit(building, 0)
	assert_true(overlay._upgraded_tiles.has(Vector2i(0, 0)), "Placing the clubhouse paves the trail")
	assert_true(overlay._upgraded_tiles.has(Vector2i(1, 0)))

	# Removing it reverts the trail to dirt.
	entities.buildings.erase(Vector2i(2, 0))
	entities.building_removed.emit(Vector2i(2, 0))
	assert_false(overlay._upgraded_tiles.has(Vector2i(0, 0)), "Removing the clubhouse reverts to dirt")

	GameManager.entity_layer = saved_entity_layer
	GameManager.terrain_grid = saved_grid

# ---------------------------------------------------------------------------
# The look: the trail the overlay draws on the course
# ---------------------------------------------------------------------------

## The overlay that belongs to the test grid.
func _overlay() -> WalkingPathOverlay:
	return grid.get_node_or_null("WalkingPathOverlay") as WalkingPathOverlay

## Unproject a draw command's point back into grid space, so the look can be
## checked in tile units rather than in pixels of one zoom level.
func _grid_point(overlay: WalkingPathOverlay, local: Vector2) -> Vector2:
	return grid.projection.unproject(overlay.to_global(local))

## Every point of the commands drawn in `color` for a tile, in grid space.
func _points_of(overlay: WalkingPathOverlay, pos: Vector2i, color: Color,
		upgraded: bool) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for cmd in overlay.tile_draw_commands(pos, upgraded, true):
		if cmd.color != color:
			continue
		if cmd.kind == "polygon":
			for point in cmd.points:
				points.append(_grid_point(overlay, point))
		elif cmd.kind == "line":
			points.append(_grid_point(overlay, cmd.a))
			points.append(_grid_point(overlay, cmd.b))
		elif cmd.kind == "circle":
			points.append(_grid_point(overlay, cmd.center))
	return points

func test_a_straight_trail_reaches_the_shared_edges_of_its_tiles() -> void:
	var overlay := _overlay()
	assert_not_null(overlay)
	for x in range(1, 7):
		grid.set_tile(Vector2i(x, 3), TerrainTypes.Type.ROUGH)
		grid.set_walking_path(Vector2i(x, 3), true)
	# The earth of tile (3,3) runs from its centre to the middle of the edge it
	# shares with (4,3), and is just as wide there as it is over the centre, so
	# one tile's trail butts up against the next with no step or seam.
	var earth := _points_of(overlay, Vector2i(3, 3), WalkingPathOverlay.DIRT_COLOR, false)
	assert_gt(earth.size(), 0, "The trail is drawn in earth")
	var at_edge := 0
	for point in earth:
		assert_lte(point.x, 4.0 + 0.001, "The trail never spills into the next tile")
		if is_equal_approx(point.x, 4.0):
			at_edge += 1
			assert_almost_eq(absf(point.y - 3.5), WalkingPathOverlay.DIRT_HALF_W, 0.01,
					"The trail meets the shared edge at its full width")
	assert_eq(at_edge, 2, "Both sides of the ribbon reach the shared edge")

## The pad drawn for `pos`, as its own polygon (the one with eight sides).
func _pad_points(overlay: WalkingPathOverlay, pos: Vector2i) -> Array[Vector2]:
	for cmd in overlay.tile_draw_commands(pos, false, false):
		if cmd.kind == "polygon" and cmd.color == WalkingPathOverlay.DIRT_COLOR \
				and cmd.points.size() == 8:
			var points: Array[Vector2] = []
			for point in cmd.points:
				points.append(_grid_point(overlay, point))
			return points
	return []

func test_a_straight_run_of_trail_is_one_width_all_the_way_along() -> void:
	var overlay := _overlay()
	for x in range(1, 7):
		grid.set_tile(Vector2i(x, 3), TerrainTypes.Type.ROUGH)
		grid.set_walking_path(Vector2i(x, 3), true)
	# The trodden pad in the middle of a straight tile is exactly as wide as
	# the ribbon either side of it: the trail is one surface, not a string of
	# beads with a bulge at every tile.
	var pad := _pad_points(overlay, Vector2i(3, 3))
	assert_eq(pad.size(), 8, "The tile's middle is a pad, settled into the walk")
	for point in pad:
		assert_lte(absf(point.y - 3.5), WalkingPathOverlay.DIRT_HALF_W + 0.001,
				"The pad never bulges past the ribbons: %s" % point)

func test_a_corner_pad_fills_the_bend_without_ballooning_out() -> void:
	var overlay := _overlay()
	# A corner: arms west and south. The mud must join them without spreading
	# further than a walk's width from the turn.
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(2, 3), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(3, 4), TerrainTypes.Type.ROUGH)
	for pos in [Vector2i(3, 3), Vector2i(2, 3), Vector2i(3, 4)]:
		grid.set_walking_path(pos, true)
	var pad := _pad_points(overlay, Vector2i(3, 3))
	assert_eq(pad.size(), 8)
	var widest := 0.0
	for point in pad:
		widest = maxf(widest, absf(point.x - 3.5) + absf(point.y - 3.5))
	assert_gt(widest, WalkingPathOverlay.DIRT_HALF_W, "The pad reaches into both arms")
	assert_lte(widest, WalkingPathOverlay.DIRT_HALF_W * 2.0 + 0.001,
			"but never stands out of the walk it joins")

func test_a_lone_dot_is_a_round_patch_with_no_ribbons() -> void:
	var overlay := _overlay()
	grid.set_tile(Vector2i(4, 4), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(4, 4), true)
	var cmds := overlay.tile_draw_commands(Vector2i(4, 4), false, true)
	var earth := _points_of(overlay, Vector2i(4, 4), WalkingPathOverlay.DIRT_COLOR, false)
	assert_gt(earth.size(), 0)
	for point in earth:
		assert_lte(absf(point.x - 4.5) + absf(point.y - 4.5),
				WalkingPathOverlay.DIRT_LONE_DOT + 0.01,
				"A dot on its own is a trodden patch, not a trail: %s" % point)
	for cmd in cmds:
		if cmd.kind == "polygon":
			assert_lte(cmd.points.size(), 8, "The dot has no long ribbons")

func test_a_trail_end_tapers_away_from_its_one_neighbour() -> void:
	var overlay := _overlay()
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.ROUGH)
	grid.set_tile(Vector2i(4, 3), TerrainTypes.Type.ROUGH)
	grid.set_walking_path(Vector2i(3, 3), true)
	grid.set_walking_path(Vector2i(4, 3), true)
	# (4,3) is the head of the trail: its earth comes to a point west of its
	# centre and never reaches the east edge of the tile.
	var earth := _points_of(overlay, Vector2i(4, 3), WalkingPathOverlay.DIRT_COLOR, false)
	var west := 5.0
	var east := 0.0
	for point in earth:
		west = minf(west, point.x)
		east = maxf(east, point.x)
	assert_lt(west, 4.5, "The trail runs on past the middle of the tile")
	assert_lt(east, 5.0, "and stops short of the tile's far edge")

func test_a_paved_trail_is_kerbed_and_jointed() -> void:
	var overlay := _overlay()
	var saved_entity_layer = GameManager.entity_layer
	var saved_grid = GameManager.terrain_grid
	GameManager.terrain_grid = grid
	var entities := EntityLayer.new()
	entities.set_terrain_grid(grid)
	add_child_autofree(entities)
	GameManager.entity_layer = entities
	for x in range(2, 6):
		grid.set_tile(Vector2i(x, 4), TerrainTypes.Type.ROUGH)
		grid.set_walking_path(Vector2i(x, 4), true)
	var building := Building.new()
	building.building_type = "clubhouse"
	building.grid_position = Vector2i(6, 4)
	building.width = 1
	building.height = 1
	entities.buildings[Vector2i(6, 4)] = building
	entities.building_placed.emit(building, 0)
	assert_true(overlay._upgraded_tiles.has(Vector2i(3, 4)), "The trail is paved")

	# Flagstones sit inside a kerb of darker stone: the kerb is the widest band
	# of paving drawn on the tile.
	var stones := _points_of(overlay, Vector2i(3, 4), WalkingPathOverlay.PAVED_COLOR, true)
	var kerb := _points_of(overlay, Vector2i(3, 4), WalkingPathOverlay.PAVED_DARK, true)
	assert_gt(stones.size(), 0)
	var stone_widest := 0.0
	var kerb_widest := 0.0
	for point in stones:
		stone_widest = maxf(stone_widest, absf(point.y - 4.5))
	for point in kerb:
		kerb_widest = maxf(kerb_widest, absf(point.y - 4.5))
	assert_almost_eq(stone_widest, WalkingPathOverlay.PAVED_HALF_W, 0.01)
	assert_gte(kerb_widest, WalkingPathOverlay.PAVED_OUTER_W,
			"The kerb is the outer edge of the paving")
	assert_lt(stone_widest / kerb_widest, 1.0, "and the flagstones sit inside it")

	# Joints cross the walk: the detail pass draws them.
	var joints := _points_of(overlay, Vector2i(3, 4), WalkingPathOverlay.PAVED_JOINT, true)
	assert_gt(joints.size(), 0, "The paving is laid in slabs, not one grey ribbon")

	GameManager.entity_layer = saved_entity_layer
	GameManager.terrain_grid = saved_grid

func test_the_web_build_draws_the_trail_without_the_weathering() -> void:
	var overlay := _overlay()
	for x in range(2, 6):
		grid.set_tile(Vector2i(x, 4), TerrainTypes.Type.ROUGH)
		grid.set_walking_path(Vector2i(x, 4), true)
	var full := overlay.tile_draw_commands(Vector2i(3, 4), false, true)
	var trimmed := overlay.tile_draw_commands(Vector2i(3, 4), false, false)
	assert_lt(trimmed.size(), full.size(), "The web build skips the detail passes")
	assert_gt(trimmed.size(), 0, "The trail itself is still drawn")
	for cmd in trimmed:
		assert_true(cmd is WalkingPathOverlay.DrawCommand)
