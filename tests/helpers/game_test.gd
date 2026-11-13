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


## Put the live content back after a test pushed a throwaway ContentRegistry
## over the real one (see tests/unit/modding/). The live state is the state
## the game boots in: base data only, no mod content - the official and
## example mods are no longer bundled, so nothing is loaded until the player
## downloads some from the Browse Mods screen. A test that wants a mod's
## content applies it itself (the repository packages under
## res://repository/packages/ are its source), and this undoes exactly that.
static func restore_live_content() -> void:
	ContentRegistry.reset_mod_content()
	ContentRegistry.refresh_live_libraries()


## Apply a repository package's declared content to the live registry, the
## way the loader would had the mod been downloaded and enabled. `root` is
## the package folder under res://repository/packages/. Done by hand rather
## than through ModManager so the script set and its safe-mode marker are
## never disturbed mid-run.
static func apply_package_content(package_folder: String) -> void:
	var manifest := ModManifest.from_json_text(
			FileAccess.get_file_as_string(package_folder.path_join("mod.json")),
			package_folder)
	ContentRegistry.apply_mod_content(manifest.id, package_folder, manifest.content)
	ContentRegistry.refresh_live_libraries()


## The official Weather, Wind and Seasons mods, installed and enabled through
## the real pipeline - pack the repository package, unpack it into the
## library, tick it, reload - exactly where a player ends up after a Browse
## Mods session (the game no longer bundles them: even Wind's factory and
## its Start New Game switch come from the wind mod). A suite whose subject
## is one of those systems calls this in before_all() and
## uninstall_environment_mods() in after_all(): GameState does not snapshot
## ModManager, so the library must be put back by hand or the modding suites
## after this one would find a polluted one.
const _ENVIRONMENT_FIXTURE: Array[String] = [
	"golf_tycoon.weather", "golf_tycoon.wind", "golf_tycoon.seasons",
]

func install_environment_mods() -> void:
	# Start from a known library whatever an earlier suite left behind: a mod
	# still marked loaded whose files that suite deleted would fail to reload
	# and its stale record would then shadow the fresh install. Switch the
	# pair off, reload so the manager drops what no longer exists on disk,
	# and uninstall whatever files remain.
	for mod_id in _ENVIRONMENT_FIXTURE:
		if not ModManager.get_mod_info(mod_id).is_empty():
			ModManager.set_mod_enabled(mod_id, false)
	ModManager.reload_mods()
	for mod_id in _ENVIRONMENT_FIXTURE:
		if not ModManager.get_mod_info(mod_id).is_empty():
			ModManager.uninstall_mod(mod_id)
	for mod_id in _ENVIRONMENT_FIXTURE:
		_install_package_fixture(mod_id)
	ModManager.discover()
	for mod_id in _ENVIRONMENT_FIXTURE:
		ModManager.set_mod_enabled(mod_id, true)
	ModManager.reload_mods()

func uninstall_environment_mods() -> void:
	# Switch off and reload first: uninstalling refuses a loaded mod.
	for mod_id in _ENVIRONMENT_FIXTURE:
		ModManager.set_mod_enabled(mod_id, false)
	ModManager.reload_mods()
	for mod_id in _ENVIRONMENT_FIXTURE:
		if not ModManager.get_mod_info(mod_id).is_empty():
			ModManager.uninstall_mod(mod_id)

## One package from the repository, into the library the Browse screen fills.
func _install_package_fixture(mod_id: String) -> void:
	var scratch := ModManager.user_root.path_join("fixture.zip")
	var packed: Dictionary = ModPackage.pack_folder(
			"res://repository/packages".path_join(mod_id), scratch)
	if not bool(packed.get("ok", false)):
		push_error("environment fixture: could not pack %s (%s)" % [mod_id, packed.get("errors", [])])
		return
	ModPackage.install_zip(scratch, ModManager.user_root.path_join("installed"))
	DirAccess.remove_absolute(scratch)


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
# Touch
# ---------------------------------------------------------------------------

## Resize the window (and so the viewport) and let the layout settle. Touch
## tests need a realistic window: a finger outside the viewport reaches no
## control at all, and the headless default is a 64x64 window.
func resize_window(size: Vector2i) -> void:
	if get_window().size != size:
		get_window().size = size
	await process_frames(3)


## Tap the screen at `pos` with one finger, the way a player does: the raw
## touch goes through TouchInput, which turns the tap into the mouse click the
## Control toolkit understands.
func touch_tap(pos: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	get_viewport().push_input(down, true)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	get_viewport().push_input(up, true)
	await process_frames(2)


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
