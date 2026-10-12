extends GameTest
## The paths a generated course arrives with: a walk beside every hole, the links
## from each green to the next tee, and the arrival walk out of the clubhouse
## door. What is laid is the Improvements tab's Path — a trail over the ground it
## crosses, not a terrain of its own. See CoursePathGenerator.

const T := TerrainTypes.Type
const NO_TILE := Vector2i(-1, -1)

## How close a walk has to come to count as reaching a tee or a green. A trail
## can only be laid on ground the Path improvement accepts, so a hole ringed by
## its own fairway and bunkers is met a few tiles out rather than not at all: as
## far as HUB_RINGS from the putting surface, whose own tiles are two or three
## further from the cup.
const REACH := CoursePathGenerator.HUB_RINGS + 2

var grid: TerrainGrid
var entities: EntityLayer

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 64
	grid.grid_height = 64
	add_child_autofree(grid)
	entities = EntityLayer.new()
	entities.map_seed = 4711
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.land_manager = null
	# Generation opens a course on Rough and paints it as natural ground, so the
	# tests plan on the same turf and the same upkeep books.
	grid.begin_batch()
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile_natural(Vector2i(x, y), T.ROUGH)
	grid.end_batch_quiet()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Paint a hole the way every generator does — corridor, green, tee and the
## bunker beside the green — and add it to the course.
func _add_hole(number: int, tee: Vector2i, green: Vector2i, corridor: int = 5):
	QuickStartCourse._paint_hole(grid, tee, green, corridor)
	var hole = GameManager.HoleData.new()
	hole.hole_number = number
	hole.tee_position = tee
	hole.green_position = green
	hole.hole_position = green
	hole.is_open = true
	GameManager.current_course.holes.append(hole)
	return hole

## Three holes snaking across the plot, like the shipped layouts' first three.
func _build_three_holes() -> void:
	_add_hole(1, Vector2i(10, 10), Vector2i(26, 12))
	_add_hole(2, Vector2i(29, 10), Vector2i(38, 10), 3)
	_add_hole(3, Vector2i(40, 12), Vector2i(44, 36))

func _lay_paths(clubhouse_hint: Vector2i = NO_TILE) -> int:
	return CoursePathGenerator.generate(grid, GameManager.current_course.holes,
			entities, clubhouse_hint)

## Every tile that carries a trail.
func _path_tiles() -> Dictionary:
	var tiles: Dictionary = {}
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			var tile := Vector2i(x, y)
			if grid.has_walking_path(tile):
				tiles[tile] = true
	return tiles

## The tiles of a type, snapshotted so a test can prove a path never took one.
func _tiles_of(types: Array) -> Dictionary:
	var tiles: Dictionary = {}
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			var tile := Vector2i(x, y)
			if grid.get_tile(tile) in types:
				tiles[tile] = grid.get_tile(tile)
	return tiles

## Is any trail within `reach` tiles of `centre`?
func _path_within(centre: Vector2i, reach: int) -> bool:
	for offset_x in range(-reach, reach + 1):
		for offset_y in range(-reach, reach + 1):
			if grid.has_walking_path(centre + Vector2i(offset_x, offset_y)):
				return true
	return false

## The trail tiles reachable from `start` stepping edge to edge — the same flood
## the walking-path overlay uses to decide what is one network.
func _network_from(start: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not grid.has_walking_path(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_back()
		for step in CoursePathGenerator.DIRECTIONS:
			var next: Vector2i = tile + step
			if seen.has(next) or not grid.has_walking_path(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen

## The nearest trail tile to `centre`, or NO_TILE when there is none.
func _nearest_path(centre: Vector2i) -> Vector2i:
	var best := NO_TILE
	var best_distance := INF
	for tile in _path_tiles():
		var distance: float = Vector2(tile - centre).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = tile
	return best


# ---------------------------------------------------------------------------
# Laying the network
# ---------------------------------------------------------------------------

func test_a_generated_course_arrives_with_a_walk_beside_every_hole() -> void:
	_build_three_holes()
	var laid := _lay_paths()
	assert_gt(laid, 0, "A generated course is laid with paths")
	for hole in GameManager.current_course.holes:
		assert_true(_path_within(hole.tee_position, REACH),
				"Hole %d's path reaches its tee" % hole.hole_number)
		assert_true(_path_within(hole.hole_position, REACH),
				"Hole %d's path reaches its green" % hole.hole_number)

func test_the_whole_network_is_one_edge_connected_walk() -> void:
	_build_three_holes()
	_lay_paths()
	var network := _network_from(_nearest_path(GameManager.current_course.holes[0].tee_position))
	assert_false(network.is_empty(), "The walk out of the first tee is a trail")
	for hole in GameManager.current_course.holes:
		var by_the_green := false
		for offset_x in range(-REACH, REACH + 1):
			for offset_y in range(-REACH, REACH + 1):
				if network.has(hole.hole_position + Vector2i(offset_x, offset_y)):
					by_the_green = true
		assert_true(by_the_green,
				"Hole %d's green joins the same network as the first tee" % hole.hole_number)

func test_a_course_with_no_holes_or_no_grid_gets_no_paths() -> void:
	assert_eq(CoursePathGenerator.generate(grid, [], entities, NO_TILE), 0)
	assert_eq(CoursePathGenerator.generate(null, [], entities, NO_TILE), 0)
	_add_hole(1, Vector2i(10, 10), Vector2i(26, 12))
	GameManager.current_course.holes[0].is_open = false
	assert_eq(_lay_paths(), 0, "A closed hole is not walked")

func test_laying_again_keeps_the_network_and_takes_little_more_ground() -> void:
	_build_three_holes()
	var first := _lay_paths()
	assert_gt(first, 0)
	var before := _path_tiles()
	var second := _lay_paths()
	assert_lt(second, first, "A second run finds most of the network already laid")
	for tile in before:
		assert_true(grid.has_walking_path(tile), "A path already laid is never taken back")


# ---------------------------------------------------------------------------
# What a path may be laid on
# ---------------------------------------------------------------------------

func test_a_path_never_takes_a_playing_surface_a_hazard_or_a_building() -> void:
	_build_three_holes()
	var protected := _tiles_of([T.GREEN, T.TEE_BOX, T.BUNKER, T.POT_BUNKER, T.WATER,
			T.OUT_OF_BOUNDS, T.EMPTY])
	_lay_paths()
	for tile in protected:
		assert_eq(grid.get_tile(tile), protected[tile],
				"%s stays %s under a laid path" % [tile, TerrainTypes.get_type_name(protected[tile])])
		assert_false(grid.has_walking_path(tile),
				"%s carries no trail: it is %s" % [tile, TerrainTypes.get_type_name(protected[tile])])

## The ground a trail is laid over is the ground the player's own Path tool
## accepts, so a generated course never arrives with a path the player could not
## have laid — and never with one across the mown playing line.
func test_a_path_is_never_laid_on_ground_the_player_could_not_lay_it_on() -> void:
	_build_three_holes()
	var refused := _tiles_of([T.FAIRWAY, T.FIRM_FAIRWAY, T.GRASS, T.HEAVY_ROUGH,
			T.GREEN, T.TEE_BOX, T.BUNKER, T.POT_BUNKER, T.WATER, T.OUT_OF_BOUNDS, T.EMPTY])
	assert_gt(refused.size(), 0, "The corridors are painted before the paths are")
	_lay_paths()
	for tile in _path_tiles():
		assert_true(TerrainTypes.can_host_walking_path(grid.get_tile(tile)),
				"%s carries a trail on %s, which the Path tool refuses"
						% [tile, TerrainTypes.get_type_name(grid.get_tile(tile))])
	for tile in refused:
		assert_false(grid.has_walking_path(tile), "%s is %s, so no trail crosses it"
				% [tile, TerrainTypes.get_type_name(refused[tile])])
	assert_gt(_path_tiles().size(), 0, "The holes are still walked")

## Where the ground leaves a hole no walk that reaches it, the walk stops short at
## the nearest ground that can carry one rather than crossing the playing line.
func test_a_hole_sealed_in_by_its_own_fairway_is_walked_to_the_nearest_open_ground() -> void:
	var green := Vector2i(32, 32)
	_add_hole(1, Vector2i(10, 10), green)
	# Ring the green with the corridor and a bunker: no tile the Path tool
	# accepts within four rings of the cup.
	for offset_x in range(-4, 5):
		for offset_y in range(-4, 5):
			var tile := green + Vector2i(offset_x, offset_y)
			grid.set_tile(tile, T.FAIRWAY)
	for offset_x in range(-5, 6):
		grid.set_tile(green + Vector2i(offset_x, -5), T.BUNKER)
		grid.set_tile(green + Vector2i(offset_x, 5), T.BUNKER)
	for offset_y in range(-5, 6):
		grid.set_tile(green + Vector2i(-5, offset_y), T.BUNKER)
		grid.set_tile(green + Vector2i(5, offset_y), T.BUNKER)
	var sealed := _tiles_of([T.FAIRWAY, T.BUNKER])

	_lay_paths()

	assert_gt(_path_tiles().size(), 0, "The hole still gets its walk")
	for tile in sealed:
		assert_false(grid.has_walking_path(tile),
				"The walk stops short of the turf and the sand that seal the green")
	assert_true(_path_within(green, REACH + 2),
			"It ends on the nearest ground that can carry it, a few tiles out")

func test_a_path_walks_round_water_rather_than_filling_it_in() -> void:
	_add_hole(1, Vector2i(8, 32), Vector2i(52, 32))
	# A pond across the corridor, with dry ground either side to walk round.
	for y in range(26, 39):
		grid.set_tile(Vector2i(30, y), T.WATER)
	var water := _tiles_of([T.WATER])
	var laid := _lay_paths()
	assert_gt(laid, 0, "The hole still gets its path")
	for tile in water:
		assert_eq(grid.get_tile(tile), T.WATER, "The pond is walked round, not filled in")
		assert_false(grid.has_walking_path(tile), "Water carries no trail")
	assert_true(_path_within(Vector2i(52, 32), REACH), "and the walk still reaches the green")

func test_a_path_is_walked_round_a_building_and_a_decoration() -> void:
	_add_hole(1, Vector2i(10, 32), Vector2i(50, 32))
	var clubhouse = CourseClubhouse.ensure(grid, entities, Vector2i(28, 22))
	assert_not_null(clubhouse)
	var decor: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/decorations.json")).decorations
	var bench := entities.place_decoration("park_bench", Vector2i(30, 36), decor)
	assert_not_null(bench)
	var occupied: Dictionary = {}
	for tile in clubhouse.get_footprint():
		occupied[tile] = true
	occupied[bench.grid_position] = true
	_lay_paths()
	for tile in occupied:
		assert_false(grid.has_walking_path(tile), "%s is built on, so no path runs under it" % tile)

func test_paths_stay_on_land_the_player_owns() -> void:
	var land := LandManager.new()
	add_child_autofree(land)
	land.owned_parcels = {Vector2i(0, 0): true, Vector2i(1, 0): true,
			Vector2i(0, 1): true, Vector2i(1, 1): true}
	GameManager.land_manager = land
	assert_true(land.is_tile_owned(Vector2i(20, 20)))
	assert_false(land.is_tile_owned(Vector2i(50, 50)), "Parcels past the plot are not owned")

	_add_hole(1, Vector2i(10, 10), Vector2i(26, 12))
	# A hole that runs off the property, the way a championship layout may.
	_add_hole(2, Vector2i(38, 38), Vector2i(56, 56))
	_lay_paths()
	for tile in _path_tiles():
		assert_true(land.is_tile_owned(tile),
				"%s is not owned, so no path is laid on it" % tile)

func test_a_laid_path_leaves_the_ground_alone_and_is_not_a_player_edit() -> void:
	var tile := Vector2i(20, 20)
	grid.set_tile_natural(tile, T.ROUGH)
	assert_false(grid._player_placed_tiles.has(tile), "The ground generation paints is natural")
	var route: Array[Vector2i] = [tile]
	CoursePathGenerator._lay(grid, entities, route, {})
	assert_true(grid.has_walking_path(tile), "The path is laid on it")
	assert_eq(grid.get_tile(tile), T.ROUGH, "and the ground it crosses is left as it was")
	assert_false(grid._player_placed_tiles.has(tile),
			"A generated path is not an edit the player is billed for")

func test_laying_paths_never_raises_the_maintenance_bill() -> void:
	_build_three_holes()
	var upkeep := grid.get_total_maintenance_cost()
	_lay_paths()
	assert_gt(_path_tiles().size(), 0)
	assert_eq(grid.get_total_maintenance_cost(), upkeep,
			"A trail is trodden ground: it carries no upkeep at all")

func test_a_link_too_long_to_read_as_a_path_is_left_as_grass() -> void:
	_add_hole(1, Vector2i(6, 6), Vector2i(10, 6), 3)
	# Far beyond MAX_LINK_TILES: the two holes each get their own path, but the
	# walk between them is not laid.
	_add_hole(2, Vector2i(58, 58), Vector2i(62, 58), 3)
	_lay_paths()
	assert_true(_path_within(Vector2i(6, 6), REACH), "The first hole still gets its walk")
	assert_true(_path_within(Vector2i(62, 58), REACH), "and so does the far one")
	assert_false(_network_from(_nearest_path(Vector2i(10, 6))).has(_nearest_path(Vector2i(58, 58))),
			"The two are not joined by a path across the property")


# ---------------------------------------------------------------------------
# The clubhouse
# ---------------------------------------------------------------------------

func test_the_network_reaches_the_clubhouse_door() -> void:
	_build_three_holes()
	var clubhouse = CourseClubhouse.ensure(grid, entities, Vector2i(18, 22))
	assert_not_null(clubhouse)
	var door := CourseClubhouse.front_tile(clubhouse, grid, entities)
	assert_true(grid.is_valid_position(door), "The clubhouse has a door")
	_lay_paths()
	var walk := _network_from(_nearest_path(door))
	assert_false(walk.is_empty(), "A path meets the clubhouse")
	assert_true(walk.has(_nearest_path(GameManager.current_course.holes[2].hole_position)),
			"The walk home from the last green is the same network as the door")

func test_a_course_whose_clubhouse_is_not_built_yet_is_laid_to_its_hint() -> void:
	_build_three_holes()
	var hint := Vector2i(18, 22)
	_lay_paths(hint)
	assert_true(_path_within(hint + Vector2i(2, 4), 4),
			"The network is laid to the tile the clubhouse door will be on")

## The network arrives on a tile beside the clubhouse footprint, which is the tile
## that decides whether the whole walk is paved (see
## WalkingPathOverlay.upgraded_component_tiles).
func test_the_network_arrives_beside_the_clubhouse_so_it_is_paved() -> void:
	_build_three_holes()
	var clubhouse = CourseClubhouse.ensure(grid, entities, Vector2i(18, 22))
	assert_not_null(clubhouse)
	var edges: Dictionary = {}
	for footprint in clubhouse.get_footprint():
		for side in CoursePathGenerator.DIRECTIONS:
			edges[footprint + side] = true
	_lay_paths()
	var paved: Dictionary = WalkingPathOverlay.upgraded_component_tiles(_path_tiles(), edges)
	assert_false(paved.is_empty(), "The clubhouse paves the network that reaches it")
	assert_gt(paved.size() * 2, _path_tiles().size(),
			"More than half the network is paved: the walk out of the clubhouse is the network, not a corner of it")


# ---------------------------------------------------------------------------
# Reading the corridor
# ---------------------------------------------------------------------------

func test_the_mown_edge_is_read_from_the_painted_corridor() -> void:
	# A five-wide corridor centred on the line reaches two tiles either side.
	for x in range(10, 40):
		for y in range(30, 35):
			grid.set_tile(Vector2i(x, y), T.FAIRWAY)
	assert_eq(CoursePathGenerator._mown_edge(grid, Vector2(20, 32), Vector2(0, 1)), 2.0)
	assert_eq(CoursePathGenerator._mown_edge(grid, Vector2(20, 32), Vector2(0, -1)), 2.0)

	# A corridor that has bent away from the line is still followed: the scan
	# looks past one tile of open ground for the rest of the mown edge.
	grid.set_tile(Vector2i(20, 35), T.ROUGH)
	grid.set_tile(Vector2i(20, 36), T.FAIRWAY)
	assert_eq(CoursePathGenerator._mown_edge(grid, Vector2(20, 32), Vector2(0, 1)), 4.0)

	# A generated corridor bends, so the edge either side of its own line differs.
	_add_hole(1, Vector2i(10, 50), Vector2i(50, 50), 5)
	var south := CoursePathGenerator._mown_edge(grid, Vector2(30, 50), Vector2(0, 1))
	var north := CoursePathGenerator._mown_edge(grid, Vector2(30, 50), Vector2(0, -1))
	assert_between(south, 1.0, 5.0, "The mown edge is read from the painted ground")
	assert_between(north, 1.0, 5.0)
	assert_ne(south, north, "A bending corridor is wider on one side than the other")

	# Open ground has no mown edge, so the fallback keeps the walk clear of it.
	var bare := TerrainGrid.new()
	bare.grid_width = 12
	bare.grid_height = 12
	add_child_autofree(bare)
	assert_eq(CoursePathGenerator._mown_edge(bare, Vector2(6, 6), Vector2(0, 1)),
			CoursePathGenerator.FALLBACK_EDGE)

func test_the_guide_runs_outside_the_corridor_it_follows() -> void:
	var hole = _add_hole(1, Vector2i(10, 32), Vector2i(50, 32), 5)
	var guide := CoursePathGenerator._corridor_guide(grid, hole, 1.0)
	assert_gt(guide.size(), 2, "The guide is sampled along the hole")
	for point in guide:
		var tile := Vector2i(point.round())
		assert_ne(grid.get_tile(tile), T.FAIRWAY,
				"The guide asks for ground outside the mown corridor")
		assert_true(grid.is_valid_position(tile))

func test_a_short_pair_gets_no_guide_at_all() -> void:
	var hole = GameManager.HoleData.new()
	hole.tee_position = Vector2i(10, 10)
	hole.green_position = Vector2i(11, 10)
	assert_eq(CoursePathGenerator._corridor_guide(grid, hole, 1.0).size(), 0)
