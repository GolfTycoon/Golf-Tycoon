extends SceneTree
## Generated courses (Quick Start and the prebuilt packages) must keep delivering
## every hole, must not leave tee boxes or cups waiting — otherwise the player's
## next tee box would be blocked by a generated one — and must arrive with the
## path network that walks the course: the Improvements tab's trail laid beside
## every tee and green, over ground the player could have laid it on themselves.
##
## Uses dynamic loads because a `-s` script compiles before autoloads exist.

var main: Node
var grid
var gm
var layout
var clubhouse_system
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	print("GENERATED_HOLE_LAYOUT_FAIL: ", message)

func run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	layout = load("res://scripts/tools/hole_layout.gd")
	clubhouse_system = load("res://scripts/systems/course_clubhouse.gd")
	main._on_main_menu_quick_start("Generated Layout Check", 0)
	for i in range(8): await process_frame

	gm = root.get_node("GameManager")
	grid = main.terrain_grid

	check(gm.current_course.holes.size() == 9, "Quick Start builds nine holes, got %d" % gm.current_course.holes.size())
	check(grid.get_cup_tiles().is_empty(), "Quick Start leaves no waiting cup")
	check(layout.unused_tee_boxes(grid, gm.current_course).is_empty(),
			"Quick Start leaves no unused tee box, so the player can place one")
	check(layout.can_place_tee_box(grid, gm.current_course), "The player can add a tee box after Quick Start")
	check(layout.green_places_cup(grid, gm.current_course), "The player's next green carries a cup")

	for hole in gm.current_course.holes:
		check(grid.get_tile(hole.hole_position) == TerrainTypes.Type.GREEN,
				"Hole %d cup sits on its green" % hole.hole_number)

	_check_paths("Quick Start")

	# Prebuilt packages replace the course; each must deliver its full hole count.
	var generator = load("res://scripts/systems/prebuilt_course_generator.gd")
	var expected := {"starter": 3, "executive": 9, "standard9": 9, "championship18": 18}
	for package_id in expected:
		# A prebuilt package is only ever built on a fresh course: reset the grid so
		# tee boxes from the previous package do not leak into this one.
		grid.begin_batch()
		grid.deserialize({})
		grid.clear_cup_tiles()
		grid.end_batch_quiet()
		grid.begin_batch()
		generator.build(package_id, grid, main.hole_tool)
		grid.end_batch_quiet()
		grid.refresh_all_overlays()
		for i in range(4): await process_frame
		var holes: int = gm.current_course.holes.size()
		check(holes == expected[package_id],
				"%s builds %d holes, got %d" % [package_id, expected[package_id], holes])
		check(grid.get_cup_tiles().is_empty(), "%s leaves no waiting cup" % package_id)
		check(layout.unused_tee_boxes(grid, gm.current_course).is_empty(),
				"%s leaves no unused tee box" % package_id)

	# A prebuilt package reaches the player through the same new-game step as
	# Quick Start, so it arrives with its paths too. Building one here the way
	# main.gd does is the check that the step covers every layout.
	main._prebuilt_pending = "starter"
	main._prebuilt_money = gm.money
	main._on_new_game_started()
	for i in range(12): await process_frame
	check(gm.current_course.holes.size() == expected["starter"],
			"A prebuilt package started through main builds %d holes, got %d"
			% [expected["starter"], gm.current_course.holes.size()])
	_check_paths("Starter Pack")

	if failures == 0:
		print("GENERATED_HOLE_LAYOUT_PASS: quick start and all four prebuilt packages deliver every hole with nothing left waiting, and the courses arrive with their paths")
	quit(1 if failures > 0 else 0)

## The paths a generated course arrives with.
##
## A trail can only be laid on the ground the Path improvement accepts — never on
## the mown playing line, a green, a tee, sand or water — and a generated
## corridor walls the rough in beside it, so what a course arrives with is a walk
## beside every tee and green that stops short where the ground runs out, in as
## many networks as the corridors seal off. What must hold on every layout is that
## no hole is left without its walk, and that no walk is laid on ground the player
## could not have laid it on.
func _check_paths(course_name: String) -> void:
	var generator = load("res://scripts/terrain/course_path_generator.gd")
	var reach: int = generator.HUB_RINGS + 2
	var paths := _path_tiles()
	check(paths.size() >= 10,
			"%s arrives with paths, got %d trail tiles" % [course_name, paths.size()])

	# The ground a walk may never be laid on, wherever the course put it.
	var taken := 0
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			var tile := Vector2i(x, y)
			if not grid.has_walking_path(tile):
				continue
			if not TerrainTypes.can_host_walking_path(grid.get_tile(tile)):
				taken += 1
	check(taken == 0, "%s lays no trail on ground the Path tool refuses (%d tiles)"
			% [course_name, taken])

	for hole in gm.current_course.holes:
		var tee_walked := _within(paths, hole.tee_position, reach)
		var green_walked := _within(paths, hole.hole_position, reach)
		if not tee_walked or not green_walked:
			print("GENERATED_HOLE_LAYOUT_MISS: %s hole %d tee %s walked %s, green %s walked %s"
					% [course_name, hole.hole_number, hole.tee_position, tee_walked,
						hole.hole_position, green_walked])
		check(tee_walked, "%s hole %d tee has its walk" % [course_name, hole.hole_number])
		check(green_walked, "%s hole %d green has its walk" % [course_name, hole.hole_number])
		check(grid.get_tile(hole.tee_position) == TerrainTypes.Type.TEE_BOX,
				"%s hole %d tee is still a tee box" % [course_name, hole.hole_number])
		check(grid.get_tile(hole.hole_position) == TerrainTypes.Type.GREEN,
				"%s hole %d cup is still on its green" % [course_name, hole.hole_number])

	var clubhouse = clubhouse_system.find(main.entity_layer)
	check(clubhouse != null, "%s has a clubhouse to walk out of" % course_name)
	var paved := 0
	if clubhouse != null:
		var edges: Dictionary = {}
		for footprint in clubhouse.get_footprint():
			for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				edges[footprint + side] = true
		var overlay = load("res://scripts/terrain/walking_path_overlay.gd")
		paved = overlay.upgraded_component_tiles(paths, edges).size()
	print("GENERATED_HOLE_LAYOUT_PATHS: %s laid %d trail tiles in %d networks, %d of them paved by the clubhouse"
			% [course_name, paths.size(), _network_count(paths), paved])


## Every tile of the course that carries a trail.
func _path_tiles() -> Dictionary:
	var tiles: Dictionary = {}
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			var tile := Vector2i(x, y)
			if grid.has_walking_path(tile):
				tiles[tile] = true
	return tiles


## How many separate networks the trail falls into, stepping edge to edge the way
## the walking-path overlay floods the network it paves.
func _network_count(paths: Dictionary) -> int:
	var left := paths.duplicate()
	var count := 0
	while not left.is_empty():
		count += 1
		var stack: Array = [left.keys()[0]]
		while not stack.is_empty():
			var tile: Vector2i = stack.pop_back()
			left.erase(tile)
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = tile + step
				if left.has(next):
					stack.append(next)
	return count


## Is a trail within `reach` tiles of `centre`?
func _within(paths: Dictionary, centre: Vector2i, reach: int) -> bool:
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			if paths.has(centre + Vector2i(x, y)):
				return true
	return false
