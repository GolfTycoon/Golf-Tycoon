extends GameTest
## Golfers prefer to walk on the paths: a laid trail is walked quicker than the
## ground around it, and route planning pulls a walk onto the quickest surface
## whenever that is genuinely faster — see Golfer._find_path_to() /
## _find_quickest_route() and TerrainGrid.walk_speed_modifier_at().

const GRID := 40

var grid: TerrainGrid
var golfer: Golfer

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = GRID
	grid.grid_height = GRID
	add_child_autofree(grid)
	for x in range(GRID):
		for y in range(GRID):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.ROUGH)
	golfer = add_child_autofree(Golfer.new())
	GameManager.terrain_grid = grid
	GameManager.entity_layer = null

func after_each() -> void:
	var previous = GameManager.terrain_grid
	if grid and is_instance_valid(grid) and previous == grid:
		GameManager.terrain_grid = null
	GameManager.entity_layer = null
	super()

## A straight trail west to east across the middle of the plot.
func _lay_trail(row: int, from_x: int, to_x: int) -> void:
	for x in range(from_x, to_x + 1):
		grid.set_walking_path(Vector2i(x, row), true)

func _world(pos: Vector2i) -> Vector2:
	return grid.grid_to_screen_center(pos)

## Walk `golfer` from one tile to another with the game's own routing.
func _route(from: Vector2i, to: Vector2i) -> Array[Vector2]:
	golfer.global_position = _world(from)
	return golfer._find_path_to(grid.grid_to_screen_precise(Vector2(to)))


# ---------------------------------------------------------------------------
# Walk rate
# ---------------------------------------------------------------------------

func test_a_trail_is_quicker_than_the_ground_it_crosses() -> void:
	_lay_trail(20, 4, 30)
	var on_trail: float = grid.walk_speed_modifier_at(Vector2i(15, 20))
	var off_trail: float = grid.walk_speed_modifier_at(Vector2i(15, 22))
	assert_almost_eq(on_trail, WalkingPathOverlay.DIRT_SPEED_MODIFIER, 0.001)
	assert_almost_eq(off_trail, TerrainTypes.get_speed_modifier(TerrainTypes.Type.ROUGH), 0.001)
	assert_gt(on_trail, off_trail, "The trail is walked quicker than the rough")

func test_a_paved_trail_is_quicker_than_a_dirt_one() -> void:
	var saved_entity_layer = GameManager.entity_layer
	var entities := EntityLayer.new()
	entities.set_terrain_grid(grid)
	add_child_autofree(entities)
	GameManager.entity_layer = entities

	_lay_trail(20, 10, 14)
	assert_almost_eq(grid.walk_speed_modifier_at(Vector2i(12, 20)),
			WalkingPathOverlay.DIRT_SPEED_MODIFIER, 0.001, "Dirt before the trail reaches the clubhouse")

	# A clubhouse at the trail's end paves it, and the walk quickens.
	var clubhouse: Building = autofree(Building.new())
	clubhouse.building_type = "clubhouse"
	clubhouse.grid_position = Vector2i(15, 20)
	clubhouse.width = 1
	clubhouse.height = 1
	entities.buildings[clubhouse.grid_position] = clubhouse
	entities.building_placed.emit(clubhouse, 0)

	assert_almost_eq(grid.walk_speed_modifier_at(Vector2i(12, 20)),
			WalkingPathOverlay.PAVED_SPEED_MODIFIER, 0.001, "Paved once it reaches the clubhouse")
	GameManager.entity_layer = saved_entity_layer

func test_a_trail_through_long_grass_is_the_quickest_way_through_it() -> void:
	grid.set_tile(Vector2i(8, 8), TerrainTypes.Type.BRUSH)
	var brush: float = grid.walk_speed_modifier_at(Vector2i(8, 8))
	grid.set_walking_path(Vector2i(8, 8), true)
	var trail: float = grid.walk_speed_modifier_at(Vector2i(8, 8))
	assert_gt(trail, brush, "A trail through the brush beats ploughing through it")
	assert_lt(trail, 1.0, "and the brush still costs the walker time")

func test_the_walk_field_reads_a_box_of_the_course_for_a_walker() -> void:
	var empty := grid.walk_field(Rect2i(0, 0, 10, 10))
	assert_eq(empty.best, 0.0, "No walk in the box, no rate to walk at")
	assert_eq(empty.rate.size(), 100)
	assert_almost_eq(empty.rate[11], TerrainTypes.get_speed_modifier(TerrainTypes.Type.ROUGH),
			0.001, "Ordinary ground is walked at its own rate")
	_lay_trail(4, 2, 6)
	var with_trail := grid.walk_field(Rect2i(0, 0, 10, 10))
	assert_almost_eq(with_trail.best, WalkingPathOverlay.DIRT_SPEED_MODIFIER, 0.001,
			"The trail is the quickest surface in the box")
	assert_almost_eq(with_trail.rate[4 * 10 + 4], WalkingPathOverlay.DIRT_SPEED_MODIFIER, 0.001,
			"and its tiles are read at the trail's rate")
	assert_eq(grid.walk_field(Rect2i(20, 20, 10, 10)).best, 0.0, "Nothing over here")
	_lay_trail(25, 25, 25)
	assert_almost_eq(grid.walk_field(Rect2i(20, 20, 10, 10)).best,
			WalkingPathOverlay.DIRT_SPEED_MODIFIER, 0.001,
			"A trail laid over ordinary ground is read at its own rate")

func test_the_walk_field_marks_what_a_walker_cannot_cross() -> void:
	grid.set_tile(Vector2i(3, 3), TerrainTypes.Type.WATER)
	grid.set_tile(Vector2i(4, 3), TerrainTypes.Type.OUT_OF_BOUNDS)
	var field := grid.walk_field(Rect2i(0, 0, 10, 10))
	assert_eq(field.rate[3 * 10 + 3], 0.0, "Water is no tile to walk through")
	assert_eq(field.rate[3 * 10 + 4], 0.0, "Nor is out of bounds")


# ---------------------------------------------------------------------------
# Preferring the walk
# ---------------------------------------------------------------------------

func test_a_golfer_walks_the_trail_that_lies_across_the_way() -> void:
	# Start and finish a tile off a straight trail, so the walk has to leave the
	# turf to join it and walk along it.
	_lay_trail(18, 6, 31)
	var route := _route(Vector2i(8, 17), Vector2i(29, 17))
	assert_gt(route.size(), 1, "The route bends onto the trail: %s" % [route])
	var on_trail := 0
	for point in route:
		if grid.has_walking_path(grid.screen_to_grid(point)):
			on_trail += 1
	assert_gt(on_trail, 0, "The route visits the trail: %s" % [route])

func test_a_detour_is_not_taken_when_the_trail_does_not_help() -> void:
	# A trail far from the walk: the golfer walks straight there instead.
	_lay_trail(2, 2, 30)
	var route := _route(Vector2i(5, 30), Vector2i(25, 30))
	assert_eq(route.size(), 1, "Straight there, with no detour: %s" % [route])

func test_a_golfer_walks_further_to_stay_on_the_walk() -> void:
	# A trail one tile off the line: walking it is a longer way round, but the
	# walker prefers the path and gets there no slower for it.
	var direct_route := _route(Vector2i(6, 26), Vector2i(30, 26))
	assert_eq(direct_route.size(), 1, "Nothing to follow: straight there")
	_lay_trail(24, 6, 30)
	var trail_route := _route(Vector2i(6, 25), Vector2i(30, 25))
	assert_gt(trail_route.size(), 1, "The walk joins the trail: %s" % [trail_route])
	var joined := false
	for point in trail_route:
		if grid.has_walking_path(grid.screen_to_grid(point)):
			joined = true
	assert_true(joined, "The route walks the trail: %s" % [trail_route])

func test_a_long_detour_is_not_worth_any_amount_of_preference() -> void:
	# A trail right across the far side of the plot: the golfer is not going to
	# cross the course to find it.
	_lay_trail(40, 0, 39)
	var route := _route(Vector2i(5, 4), Vector2i(30, 4))
	assert_eq(route.size(), 1, "The far trail is left alone: %s" % [route])

func test_water_is_still_avoided() -> void:
	# Long water across the line of the walk, with dry ground beyond it.
	for y in range(10, 31):
		grid.set_tile(Vector2i(20, y), TerrainTypes.Type.WATER)
	var route := _route(Vector2i(10, 25), Vector2i(30, 25))
	assert_gt(route.size(), 1, "The walker routes around the water: %s" % [route])
	for point in route:
		var tile := grid.screen_to_grid(point)
		if grid.is_valid_position(tile):
			assert_false(TerrainTypes.is_water(grid.get_tile(tile)),
					"The walker never steps in the water (%s)" % [tile])

func test_a_trail_route_still_goes_around_water() -> void:
	# A trail runs under the far end of a pond; the walker joins it, and the
	# pond is still walked around rather than through.
	for y in range(0, 23):
		grid.set_tile(Vector2i(20, y), TerrainTypes.Type.WATER)
	_lay_trail(26, 4, 34)
	for pos in [Vector2i(20, 26)] :
		grid.set_tile(pos, TerrainTypes.Type.ROUGH)  # (The pond ends above it.)
	var route := _route(Vector2i(10, 18), Vector2i(30, 18))
	assert_gt(route.size(), 1, "A route was found: %s" % [route])
	for point in route:
		var tile := grid.screen_to_grid(point)
		if grid.is_valid_position(tile):
			assert_false(TerrainTypes.is_water(grid.get_tile(tile)),
					"The trail route stays out of the water (%s)" % [tile])

func test_a_short_walk_is_straight_there() -> void:
	_lay_trail(20, 6, 30)
	var route := _route(Vector2i(12, 20), Vector2i(14, 20))
	assert_eq(route.size(), 1, "Under MIN_ROUTE_DISTANCE tiles the golfer just walks: %s" % [route])


# ---------------------------------------------------------------------------
# Walking on the trail really is quicker
# ---------------------------------------------------------------------------

func test_walking_the_trail_covers_more_ground_than_the_rough() -> void:
	golfer.walk_speed = 100.0
	var waypoints: Array[Vector2] = [_world(Vector2i(30, 20))]
	golfer.path = waypoints
	golfer.path_index = 0
	golfer.current_state = Golfer.State.WALKING
	golfer.global_position = _world(Vector2i(10, 20))
	grid.set_tile(Vector2i(10, 20), TerrainTypes.Type.ROUGH)
	golfer._process_walking(0.1)
	var rough_step: float = golfer.global_position.distance_to(_world(Vector2i(10, 20)))

	_lay_trail(20, 10, 30)
	golfer.global_position = _world(Vector2i(10, 20))
	var again: Array[Vector2] = [_world(Vector2i(30, 20))]
	golfer.path = again
	golfer.path_index = 0
	golfer._process_walking(0.1)
	var trail_step: float = golfer.global_position.distance_to(_world(Vector2i(10, 20)))

	assert_almost_eq(rough_step, 10.0, 0.01, "Ten units of ground in a tenth of a second")
	assert_almost_eq(trail_step, 12.5, 0.01, "The trail covers a quarter more ground")
	assert_gt(trail_step, rough_step, "Golfers walk quicker on the path")


func _building(pos: Vector2i, size: Vector2i) -> Building:
	if GameManager.entity_layer == null:
		var entities := EntityLayer.new()
		add_child_autofree(entities)
		GameManager.entity_layer = entities
	var building: Building = autofree(Building.new())
	building.grid_position = pos
	building.width = size.x
	building.height = size.y
	GameManager.entity_layer.buildings[pos] = building
	return building

func _assert_route_clear(start: Vector2, route: Array[Vector2]) -> void:
	var previous := start
	for point in route:
		assert_false(golfer._building_on_segment(previous, point), "Every segment must avoid the footprint")
		previous = point

func test_routes_around_multi_tile_building() -> void:
	_building(Vector2i(18, 18), Vector2i(4, 5))
	var start := Vector2i(14, 20)
	var route := _route(start, Vector2i(26, 20))
	assert_gt(route.size(), 1)
	_assert_route_clear(_world(start), route)
	assert_eq(route.back(), _world(Vector2i(26, 20)))

func test_short_and_diagonal_walks_do_not_clip_buildings() -> void:
	_building(Vector2i(11, 10), Vector2i.ONE)
	var start := Vector2i(10, 10)
	var route := _route(start, Vector2i(12, 10))
	assert_gt(route.size(), 1)
	_assert_route_clear(_world(start), route)
	assert_true(golfer._building_on_segment(_world(Vector2i(10, 9)), _world(Vector2i(12, 11))))

func test_trail_route_avoids_building() -> void:
	_lay_trail(20, 5, 32)
	_building(Vector2i(18, 19), Vector2i(3, 3))
	var start := Vector2i(6, 20)
	var route := _route(start, Vector2i(30, 20))
	assert_gt(route.size(), 1)
	_assert_route_clear(_world(start), route)

func test_unreachable_destination_falls_back_through_building() -> void:
	_building(Vector2i(20, 0), Vector2i(1, GRID))
	var destination := Vector2i(30, 20)
	golfer.global_position = _world(Vector2i(10, 20))
	golfer.begin_walk_to(_world(destination), "Walking")
	assert_true(golfer._walk_through_buildings)
	for i in 200:
		if golfer.current_state != Golfer.State.WALKING:
			break
		golfer._process_walking(0.1)
	assert_eq(golfer.current_state, Golfer.State.IDLE)
	assert_almost_eq(golfer.global_position.distance_to(_world(destination)), 0.0, 0.01)

func test_fallback_still_avoids_water_when_possible() -> void:
	_building(Vector2i(20, 0), Vector2i(1, GRID))
	for y in range(15, 26):
		grid.set_tile(Vector2i(15, y), TerrainTypes.Type.WATER)
	var route := _route(Vector2i(10, 20), Vector2i(30, 20))
	assert_true(golfer._walk_through_buildings)
	assert_gt(route.size(), 1)
	var previous := Vector2i(10, 20)
	for point in route:
		var tile := grid.screen_to_grid(point)
		assert_false(golfer._path_crosses_obstacle(previous, tile, true, false))
		previous = tile

func test_destination_inside_building_is_reached() -> void:
	_building(Vector2i(20, 20), Vector2i(2, 2))
	var route := _route(Vector2i(15, 20), Vector2i(20, 20))
	assert_true(golfer._walk_through_buildings)
	assert_eq(route.back(), _world(Vector2i(20, 20)))

func test_building_placed_during_walk_triggers_replan() -> void:
	var start := Vector2i(10, 20)
	var destination := Vector2i(25, 20)
	golfer.global_position = _world(start)
	golfer.begin_walk_to(_world(destination), "Walking")
	_building(Vector2i(16, 19), Vector2i(3, 3))
	golfer._process_walking(0.1)
	assert_false(golfer._building_on_segment(_world(start), golfer.global_position))
	_assert_route_clear(golfer.global_position, golfer.path.slice(golfer.path_index))

func test_golfer_starting_inside_building_can_leave() -> void:
	_building(Vector2i(10, 20), Vector2i(2, 2))
	var destination := Vector2i(16, 20)
	golfer.global_position = _world(Vector2i(10, 20))
	golfer.begin_walk_to(_world(destination), "Walking")
	for i in 100:
		if golfer.current_state != Golfer.State.WALKING:
			break
		golfer._process_walking(0.1)
	assert_eq(golfer.current_state, Golfer.State.IDLE)
	assert_almost_eq(golfer.global_position.distance_to(_world(destination)), 0.0, 0.01)


# ---------------------------------------------------------------------------
# The pace
# ---------------------------------------------------------------------------

func test_a_golfer_starts_at_the_base_walk() -> void:
	var fresh: Golfer = add_child_autofree(Golfer.new())
	assert_almost_eq(fresh.walk_speed, Golfer.BASE_WALK_SPEED, 0.001,
		"A golfer walks at the base pace before any trait or surface quickens it")
	assert_lt(Golfer.BASE_WALK_SPEED, 100.0,
		"A stroll, not the old 100 px/s trot: a round is a walk between shots")

func test_a_base_pace_step_covers_the_base_ground() -> void:
	# The default walk speed reaches the movement itself, not just the property.
	golfer.walk_speed = Golfer.BASE_WALK_SPEED
	var waypoints: Array[Vector2] = [_world(Vector2i(30, 20))]
	golfer.path = waypoints
	golfer.path_index = 0
	golfer.current_state = Golfer.State.WALKING
	golfer.global_position = _world(Vector2i(10, 20))
	grid.set_tile(Vector2i(10, 20), TerrainTypes.Type.ROUGH)
	golfer._process_walking(0.1)
	var expected: float = Golfer.BASE_WALK_SPEED * 0.1 \
			* TerrainTypes.get_speed_modifier(TerrainTypes.Type.ROUGH)
	assert_almost_eq(golfer.global_position.distance_to(_world(Vector2i(10, 20))),
		expected, 0.01, "A tenth of a second covers the base pace times the ground rate")

func test_reset_walk_speed_gives_the_active_trait_its_edge() -> void:
	golfer.attributes.set_trait("active", true)
	golfer.walk_speed = 999.0  # a cart rental, a test, anything that overwrote it
	golfer.reset_walk_speed()
	assert_almost_eq(golfer.walk_speed,
		Golfer.BASE_WALK_SPEED * golfer.attributes.walk_speed_multiplier(), 0.001,
		"The natural pace is the base walk, quickened by the Active trait")

func test_the_legs_swing_in_step_with_the_ground_covered() -> void:
	# The walk cycle is drawn for a stride, so a slower walker swings their
	# legs less often instead of scurrying — the same ground per leg swap.
	golfer._use_sprites = false
	golfer._walk_frame = 0
	golfer._walk_timer = 0.0
	golfer.velocity = Vector2(100, 0)
	golfer._animate_walking(0.2)
	assert_eq(golfer._walk_frame, 0, "Most of a stride at 100 px/s is not a step yet")
	golfer._animate_walking(0.1)
	assert_eq(golfer._walk_frame, 1, "100 px/s swaps legs once a stride is covered")

	golfer._walk_frame = 0
	golfer._walk_timer = 0.0
	golfer.velocity = Vector2(0, 50)
	golfer._animate_walking(0.3)
	assert_eq(golfer._walk_frame, 0, "The same ground at half the pace is only part of a stride")
	golfer._animate_walking(0.3)
	assert_eq(golfer._walk_frame, 1, "At half the pace the legs take twice as long to swap")
