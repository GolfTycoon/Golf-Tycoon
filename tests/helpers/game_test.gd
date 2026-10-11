class_name GameTest
extends GutTest
## Base class for every unit test.
##
## GameManager is an autoload, so whatever one test changes there would still be
## there for the tests after it. GameTest snapshots GameManager (and the engine's
## time scale) before each test and restores it afterwards, so a test only sets
## up what it uses and never cleans up after itself. A subclass that overrides
## before_each() calls super() first; one that overrides after_each() calls
## super() last, once its own teardown is done.
##
## It also builds the small worlds most tests need: a terrain grid, an entity
## layer on it, the holes of a course, and a golfer manager seated the way
## main.tscn seats it.

const GameState := preload("res://tests/helpers/game_state.gd")

var _saved_state: Dictionary = {}


func before_each() -> void:
	_saved_state = GameState.capture()


func after_each() -> void:
	GameState.restore(_saved_state)


# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------

## Let `count` frames pass, so every node's _process() runs `count` more times.
## (GUT's wait_frames() counts physics ticks: several can pass within one slow
## frame and leave _process() behind, and they come at most 60 a second.)
func process_frames(count: int = 1) -> void:
	for i in range(count):
		await get_tree().process_frame


## Let frames pass until `condition` holds, for at most `max_frames`. Returns
## whether it held.
func process_frames_until(condition: Callable, max_frames: int) -> bool:
	for i in range(max_frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

## A `width` x `height` terrain grid in the scene tree, freed after the test.
## Its tiles start as grass (TerrainGrid._ready).
func make_grid(width: int, height: int) -> TerrainGrid:
	var grid := TerrainGrid.new()
	grid.grid_width = width
	grid.grid_height = height
	add_child_autofree(grid)
	return grid


## Paint every tile of `grid` with `terrain` as natural ground — what course
## generation lays, so it is not a player edit and carries no upkeep.
func fill_grid(grid: TerrainGrid, terrain: int) -> void:
	grid.begin_batch()
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			grid.set_tile_natural(Vector2i(x, y), terrain)
	grid.end_batch_quiet()


## An entity layer standing on `grid`, freed after the test.
func make_entity_layer(grid: TerrainGrid, map_seed: int = 1234) -> EntityLayer:
	var entities := EntityLayer.new()
	entities.map_seed = map_seed
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	return entities


## An open hole from `tee` to `cup`.
func make_hole(number: int, tee: Vector2i, cup: Vector2i, par: int = 4) -> GameManager.HoleData:
	var hole := GameManager.HoleData.new()
	hole.hole_number = number
	hole.par = par
	hole.tee_position = tee
	hole.green_position = cup
	hole.hole_position = cup
	hole.is_open = true
	return hole


## A GolferManager seated the way main.tscn seats it: beside an Entities node
## that holds the Golfers and Balls containers it spawns into. The whole
## arrangement is freed after the test; its root is the manager's parent.
func make_golfer_manager() -> GolferManager:
	var root := Node2D.new()
	root.name = "GolfFixture"
	add_child_autofree(root)
	var entities := Node2D.new()
	entities.name = "Entities"
	root.add_child(entities)
	for container_name in ["Golfers", "Balls"]:
		var container := Node2D.new()
		container.name = container_name
		entities.add_child(container)
	var golfers := GolferManager.new()
	golfers.name = "GolferManager"
	root.add_child(golfers)
	return golfers


## Every Button under `node`, depth first.
static func find_buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	if node == null:
		return found
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(find_buttons(child))
	return found


## `inner` lies inside `outer`, allowing `slack` pixels of float error.
static func rect_within(inner: Rect2, outer: Rect2, slack: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - slack \
		and inner.position.y >= outer.position.y - slack \
		and inner.end.x <= outer.end.x + slack \
		and inner.end.y <= outer.end.y + slack
