extends SceneTree
## Course path preview - prints an ASCII plan of the paths a generated course
## arrives with, so the layout can be eyeballed and the constants tuned without
## opening the editor.
##
##     godot --headless --path . -s tests/harness/course_path_preview.gd
##     godot --headless --path . -s tests/harness/course_path_preview.gd -- generated18
##
## The course is built by the same code the game runs — natural terrain, then the
## layout asked for — followed by the path network main.gd lays over it: the
## trail the Improvements tab's Path lays, trodden dirt over the ground it
## crosses and paved stone once it reaches the clubhouse.
## The layouts are `quickstart` (the default), `generated3`, `generated6`,
## `generated9` and `generated18` for the Start New Game courses, and `starter`,
## `executive`, `standard9` and `championship18` for the prebuilt packages.
##
## Uses dynamic loads for anything that reads an autoload: a `-s` script compiles
## before the autoloads exist, so a static reference to one of them (or to a
## script that has one) fails to compile.

## Plan characters, in the order the map is drawn.
const KEY := "  . rough   , scrub   * flowers   r stone   f fairway   T tee   G green   B bunker   ~ water   t woodland   # path   C building"

## How much ground either side of the holes the plan prints.
const MAP_MARGIN := 6

var grid
var entities
var game_manager
var generator
var clubhouse_system
var quick_start
var generated_course
var prebuilt
var natural_terrain


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	game_manager = root.get_node("GameManager")
	generator = load("res://scripts/terrain/course_path_generator.gd")
	clubhouse_system = load("res://scripts/systems/course_clubhouse.gd")
	quick_start = load("res://scripts/systems/quick_start_course.gd")
	generated_course = load("res://scripts/systems/generated_course.gd")
	prebuilt = load("res://scripts/systems/prebuilt_course_generator.gd")
	natural_terrain = load("res://scripts/terrain/natural_terrain_generator.gd")
	var hole_tool = load("res://scripts/tools/hole_creation_tool.gd").new()
	root.add_child(hole_tool)

	grid = load("res://scripts/terrain/terrain_grid.gd").new()
	root.add_child(grid)
	entities = load("res://scripts/course/entity_layer.gd").new()
	root.add_child(entities)
	entities.set_terrain_grid(grid)
	game_manager.terrain_grid = grid
	game_manager.entity_layer = entities
	game_manager.land_manager = null
	game_manager.current_course = game_manager.CourseData.new()

	var which := "quickstart"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		which = args[0]

	grid.begin_batch()
	natural_terrain.generate(grid, entities, 1234)
	_build(which, hole_tool)
	grid.end_batch_quiet()
	grid.refresh_all_overlays()

	var clubhouse = clubhouse_system.ensure(grid, entities, _clubhouse_hint(which))
	grid.refresh_all_overlays()
	var mown := _tiles_of([TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY])
	var play := _tiles_of([TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX,
			TerrainTypes.Type.BUNKER, TerrainTypes.Type.POT_BUNKER,
			TerrainTypes.Type.WATER, TerrainTypes.Type.OUT_OF_BOUNDS])
	var woodland := _count_woodland()

	print(KEY)
	print("The %s course as it is built, before any path is laid:" % which)
	_print_plan()

	var started := Time.get_ticks_msec()
	var laid: int = generator.generate(grid, game_manager.current_course.holes,
			entities, clubhouse.grid_position if clubhouse else Vector2i(-1, -1))
	var elapsed := Time.get_ticks_msec() - started
	grid.refresh_all_overlays()

	print("The same course with its paths:")
	_print_plan()
	print("Holes: %d   path tiles laid: %d in %d ms"
			% [game_manager.current_course.holes.size(), laid, elapsed])

	# The trail never replaces the ground it crosses, so the playing surfaces are
	# all still there — the check is that a path is on none of them.
	var taken := 0
	var taken_tiles: Array = []
	for tiles in [mown, play]:
		for tile in tiles:
			if grid.has_walking_path(tile):
				taken += 1
				taken_tiles.append(tile)
	print("Playing surfaces a path was laid on: %d of %d mown and %d green, tee, sand or water"
			% [taken, mown.size(), play.size()])
	if not taken_tiles.is_empty():
		print("  ", taken_tiles)
	print("Woodland tiles the paths run through: %d of %d" % [woodland - _count_woodland(), woodland])

	# A trail is only walked at 1.5x once its own network touches the clubhouse,
	# and the ground a trail can be laid on never includes the mown playing line,
	# so a course's trails fall into as many networks as its corridors seal off.
	# What a layout ships with is therefore three numbers: how much path there is,
	# how much of it is paved, and how many holes each network reaches.
	var paths := _path_tiles()
	var paved := _paved_tiles(paths, clubhouse)
	var networks := _networks(paths)
	var sizes: Array = []
	for network in networks:
		sizes.append(network.size())
	sizes.sort()
	sizes.reverse()
	print("Path tiles on the course: %d in %d networks %s" % [paths.size(), networks.size(), str(sizes)])
	print("Paved (the network reaching the clubhouse): %d" % paved.size())
	# A hole is served when a network reaches the ground a walk may come in on,
	# which is as far as HUB_RINGS tiles out from the tee or the cup.
	var reach: int = generator.HUB_RINGS
	var served_tees := 0
	var served_greens := 0
	var paved_tees := 0
	var paved_greens := 0
	print("Per hole:")
	for hole in game_manager.current_course.holes:
		var tee: bool = _network_touches(paths, hole.tee_position, reach)
		var green: bool = _network_touches(paths, hole.hole_position, reach)
		var tee_paved: bool = _network_touches(paved, hole.tee_position, reach)
		var green_paved: bool = _network_touches(paved, hole.hole_position, reach)
		served_tees += 1 if tee else 0
		served_greens += 1 if green else 0
		paved_tees += 1 if tee_paved else 0
		paved_greens += 1 if green_paved else 0
		print("  H%-2d tee %s → green %s   path by the tee: %s (%d out), by the green: %s (%d out)   paved: %s / %s" % [
			hole.hole_number, hole.tee_position, hole.hole_position,
			_yes_no(tee), _rings_out(paths, hole.tee_position),
			_yes_no(green), _rings_out(paths, hole.hole_position),
			_yes_no(tee_paved), _yes_no(green_paved)])
	var holes: int = game_manager.current_course.holes.size()
	print("Holes with a path: %d tees and %d greens of %d; paved: %d tees and %d greens"
			% [served_tees, served_greens, holes, paved_tees, paved_greens])
	quit(0)


## How many tiles out from `centre` the nearest trail is, or -1 for none.
func _rings_out(paths: Dictionary, centre: Vector2i) -> int:
	for ring in range(0, 16):
		for x in range(-ring, ring + 1):
			for y in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				if paths.has(centre + Vector2i(x, y)):
					return ring
	return -1


## The trail's separate networks, largest first, each a dictionary of its tiles.
func _networks(paths: Dictionary) -> Array:
	var left := paths.duplicate()
	var found: Array = []
	while not left.is_empty():
		var start: Vector2i = left.keys()[0]
		var network := _flood(paths, start)
		for tile in network:
			left.erase(tile)
		found.append(network)
	found.sort_custom(func(a, b): return a.size() > b.size())
	return found


func _flood(paths: Dictionary, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not paths.has(start):
		return seen
	var stack: Array = [start]
	seen[start] = true
	while not stack.is_empty():
		var tile: Vector2i = stack.pop_back()
		for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = tile + side
			if paths.has(next) and not seen.has(next):
				seen[next] = true
				stack.append(next)
	return seen


## The tile the network arrives at the clubhouse on, the way the generator picks
## it: a tile beside the footprint that can host a trail.
func _clubhouse_door(clubhouse) -> Vector2i:
	if clubhouse == null:
		return Vector2i(-1, -1)
	var door: Vector2i = clubhouse_system.front_tile(clubhouse, grid, entities)
	var arrival: Vector2i = generator._clubhouse_arrival(grid, entities, clubhouse, door)
	return arrival if arrival != Vector2i(-1, -1) else door


## The trail tiles the clubhouse paves, by the overlay's own rule.
func _paved_tiles(paths: Dictionary, clubhouse) -> Dictionary:
	if clubhouse == null:
		return {}
	var edges: Dictionary = {}
	for footprint in clubhouse.get_footprint():
		for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			edges[footprint + side] = true
	var overlay = load("res://scripts/terrain/walking_path_overlay.gd")
	return overlay.upgraded_component_tiles(paths, edges)


## Build the layout asked for, the way main.gd builds it.
func _build(which: String, hole_tool) -> void:
	match which:
		"quickstart":
			quick_start.build(grid, entities, hole_tool)
		"generated3", "generated6", "generated9", "generated18":
			generated_course.generate(int(which.trim_prefix("generated")), grid, entities, hole_tool)
		_:
			prebuilt.build(which, grid, hole_tool)


## Where each layout keeps the pocket its clubhouse stands in.
func _clubhouse_hint(which: String) -> Vector2i:
	match which:
		"quickstart":
			return quick_start.CLUBHOUSE_TILE
		"generated3", "generated6", "generated9", "generated18":
			var count := int(which.trim_prefix("generated"))
			return generated_course.get_anchor(count) + generated_course.CLUBHOUSE_OFFSET
		_:
			return clubhouse_system.arrival_corner()


func _count_woodland() -> int:
	var count := 0
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			if TerrainTypes.is_tree(grid.get_tile(Vector2i(x, y))):
				count += 1
	return count


func _tiles_of(types: Array) -> Dictionary:
	var tiles: Dictionary = {}
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			var tile := Vector2i(x, y)
			if grid.get_tile(tile) in types:
				tiles[tile] = grid.get_tile(tile)
	return tiles


func _path_tiles() -> Dictionary:
	var tiles: Dictionary = {}
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			var tile := Vector2i(x, y)
			if grid.has_walking_path(tile):
				tiles[tile] = true
	return tiles


func _network_touches(network: Dictionary, centre: Vector2i, reach: int) -> bool:
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			if network.has(centre + Vector2i(x, y)):
				return true
	return false


func _yes_no(value: bool) -> String:
	return "yes" if value else "NO"


## The plan covers every hole of the layout, plus a margin, so the map is the
## course whatever its size.
func _plan_bounds() -> Array[Vector2i]:
	var low := Vector2i(grid.grid_width, grid.grid_height)
	var high := Vector2i.ZERO
	for hole in game_manager.current_course.holes:
		for tile in [hole.tee_position, hole.hole_position]:
			low = Vector2i(mini(low.x, tile.x), mini(low.y, tile.y))
			high = Vector2i(maxi(high.x, tile.x), maxi(high.y, tile.y))
	low = Vector2i(maxi(low.x - MAP_MARGIN, 0), maxi(low.y - MAP_MARGIN, 0))
	high = Vector2i(mini(high.x + MAP_MARGIN, grid.grid_width - 1),
			mini(high.y + MAP_MARGIN, grid.grid_height - 1))
	return [low, high]


func _print_plan() -> void:
	var bounds := _plan_bounds()
	var header := "     "
	for x in range(bounds[0].x, bounds[1].x + 1):
		header += str(x % 10)
	print(header)
	for y in range(bounds[0].y, bounds[1].y + 1):
		var row := "%3d  " % y
		for x in range(bounds[0].x, bounds[1].x + 1):
			row += _character(Vector2i(x, y))
		print(row)


func _character(tile: Vector2i) -> String:
	if entities != null and entities.is_tile_occupied_by_building(tile):
		return "C"
	# The trail is laid over the ground it crosses, so it is what a plan wants to
	# show: the ground underneath is the rough the walk was cut through.
	if grid.has_walking_path(tile):
		return "#"
	var type: int = grid.get_tile(tile)
	if TerrainTypes.is_tree(type):
		return "t"
	if TerrainTypes.is_rocks(type):
		return "r"
	match type:
		TerrainTypes.Type.TEE_BOX: return "T"
		TerrainTypes.Type.GREEN: return "G"
		TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY: return "f"
		TerrainTypes.Type.BUNKER, TerrainTypes.Type.POT_BUNKER: return "B"
		TerrainTypes.Type.WATER, TerrainTypes.Type.STREAM: return "~"
		TerrainTypes.Type.FLOWER_BED: return "*"
		TerrainTypes.Type.OUT_OF_BOUNDS, TerrainTypes.Type.EMPTY: return " "
		_: return "."
