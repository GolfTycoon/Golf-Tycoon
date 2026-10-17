extends Node
class_name HoleManager
## HoleManager - Manages all hole visualizations on the course

## Cup radius and ball-holed check — delegates to GolfRules for single source of truth.
## Kept here as a convenience wrapper since many systems reference HoleManager.is_ball_holed.
const CUP_RADIUS: float = GolfRules.CUP_RADIUS

## The pars a hole may be given by hand: 3, 4 and 5 by length, a shot either side
## of that by the player (see the hole menu's Cycle Par, which stays inside the
## same range).
const MIN_PAR: int = 3
const MAX_PAR: int = 6

static func is_ball_holed(ball_pos: Vector2, hole_pos: Vector2) -> bool:
	return GolfRules.is_ball_holed(ball_pos, hole_pos)

var terrain_grid: TerrainGrid
var hole_visualizers: Dictionary = {}  # key: hole_number, value: HoleVisualizer

@onready var holes_container: Node2D = get_parent().get_node("Holes") if get_parent().has_node("Holes") else null

signal hole_visualization_created(hole_number: int)
signal hole_visualization_removed(hole_number: int)
signal hole_selected(hole_number: int)

func _ready() -> void:
	# Connect to EventBus for hole events
	EventBus.hole_created.connect(_on_hole_created)
	EventBus.hole_deleted.connect(_on_hole_deleted)
	EventBus.hole_updated.connect(_on_hole_updated)
	EventBus.hole_toggled.connect(_on_hole_toggled)
	EventBus.load_completed.connect(_on_load_completed)

func _exit_tree() -> void:
	if EventBus.hole_created.is_connected(_on_hole_created):
		EventBus.hole_created.disconnect(_on_hole_created)
	if EventBus.hole_deleted.is_connected(_on_hole_deleted):
		EventBus.hole_deleted.disconnect(_on_hole_deleted)
	if EventBus.hole_updated.is_connected(_on_hole_updated):
		EventBus.hole_updated.disconnect(_on_hole_updated)
	if EventBus.hole_toggled.is_connected(_on_hole_toggled):
		EventBus.hole_toggled.disconnect(_on_hole_toggled)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

	# Initialize visualizations for existing holes
	_initialize_existing_holes()

func _initialize_existing_holes() -> void:
	if not GameManager.current_course:
		return

	for hole in GameManager.current_course.holes:
		_create_hole_visualization(hole)

func _create_hole_visualization(hole: GameManager.HoleData) -> void:
	if not holes_container:
		push_error("HoleManager: No holes container found")
		return

	if not terrain_grid:
		push_error("HoleManager: Terrain grid not set")
		return

	# Remove existing visualization if it exists
	if hole_visualizers.has(hole.hole_number):
		remove_hole_visualization(hole.hole_number)

	# Create new visualizer
	var visualizer = HoleVisualizer.new()
	visualizer.name = "Hole%d" % hole.hole_number
	holes_container.add_child(visualizer)

	visualizer.initialize(hole, terrain_grid)
	visualizer.hole_selected.connect(_on_hole_visualization_selected)

	hole_visualizers[hole.hole_number] = visualizer
	hole_visualization_created.emit(hole.hole_number)

func remove_hole_visualization(hole_number: int) -> void:
	if not hole_visualizers.has(hole_number):
		return

	var visualizer = hole_visualizers[hole_number]
	visualizer.destroy()
	hole_visualizers.erase(hole_number)
	hole_visualization_removed.emit(hole_number)

## Drop every hole visualization. Used when the whole course is replaced (New
## Game), where the disappearing holes never emit hole_deleted.
func clear_visualizations() -> void:
	for hole_number in hole_visualizers.keys():
		remove_hole_visualization(hole_number)

func get_hole_visualizer(hole_number: int) -> HoleVisualizer:
	return hole_visualizers.get(hole_number, null)

func get_all_hole_visualizers() -> Array:
	return hole_visualizers.values()

func highlight_hole(hole_number: int, enabled: bool) -> void:
	var visualizer = get_hole_visualizer(hole_number)
	if visualizer:
		visualizer.highlight(enabled)

func set_hole_visibility(hole_number: int, is_visible: bool) -> void:
	var visualizer = get_hole_visualizer(hole_number)
	if visualizer:
		visualizer.set_visible_state(is_visible)

func set_all_holes_visibility(is_visible: bool) -> void:
	for visualizer in hole_visualizers.values():
		visualizer.set_visible_state(is_visible)

func update_hole_visualization(hole_number: int) -> void:
	var visualizer = get_hole_visualizer(hole_number)
	if visualizer:
		visualizer.update_visualization()

func update_all_visualizations() -> void:
	for visualizer in hole_visualizers.values():
		visualizer.update_visualization()

## Rebuild every hole visual from the course data. Used when the route changes
## shape (holes moved, the round played the other way round), where the hole
## numbers - and with them every visualizer's name - have moved.
func rebuild_visualizations() -> void:
	clear_visualizations()
	_initialize_existing_holes()

# =============================================================================
# Route editing (the Course Map's Routing Holes mode)
# =============================================================================

## The hole carrying `hole_number`, or null.
func find_hole(hole_number: int) -> GameManager.HoleData:
	if not GameManager.current_course:
		return null
	for hole in GameManager.current_course.holes:
		if hole.hole_number == hole_number:
			return hole
	return null

## Move the hole at `from_index` to `to_index` (0-based places in the round).
## Everything that depends on the order comes along: the holes are renumbered,
## each hole keeps its own statistics as it moves, golfers part-way round carry
## on at the hole they were playing, and stroke indices are recalculated.
func move_hole(from_index: int, to_index: int) -> bool:
	var course: GameManager.CourseData = GameManager.current_course
	if course == null:
		return false
	var before := _route_snapshot(course)
	if not HoleRouting.move(course.holes, from_index, to_index):
		return false
	_after_reroute(course, before)
	return true

## Play the course the other way round.
func reverse_hole_order() -> bool:
	var course: GameManager.CourseData = GameManager.current_course
	if course == null:
		return false
	var before := _route_snapshot(course)
	if not HoleRouting.reverse(course.holes):
		return false
	_after_reroute(course, before)
	return true

## Turn one hole around: its green becomes the tee and its old tee box is cut
## with the cup. The hole keeps its place in the round and its length.
func flip_hole(hole_number: int) -> bool:
	var hole := find_hole(hole_number)
	var course: GameManager.CourseData = GameManager.current_course
	if hole == null or course == null:
		return false
	if not HoleRouting.flip(hole, terrain_grid):
		return false
	course._recalculate_par()
	StrokeIndexCalculator.recalculate_for_course()
	EventBus.hole_updated.emit(hole_number)
	EventBus.hole_tee_moved.emit(hole_number, hole.green_position, hole.tee_position)
	EventBus.hole_green_moved.emit(hole_number, hole.tee_position, hole.green_position)
	update_hole_visualization(hole_number)
	EventBus.notify("Hole %d turned around — it now plays the other way." % hole_number, "info")
	return true

## Set a hole's par by hand (par_override), or hand it back to the distance
## (new_par == the par its length gives, see GolfRules.calculate_par). Returns
## false when there is no such hole.
func set_hole_par(hole_number: int, new_par: int) -> bool:
	var hole := find_hole(hole_number)
	var course: GameManager.CourseData = GameManager.current_course
	if hole == null or course == null:
		return false
	if new_par < MIN_PAR or new_par > MAX_PAR:
		return false
	var auto_par := GolfRules.calculate_par(hole.distance_yards)
	hole.par_override = -1 if new_par == auto_par else new_par
	hole.par = new_par
	hole.difficulty_rating = DifficultyCalculator.calculate_hole_difficulty(hole, terrain_grid)
	course._recalculate_par()
	StrokeIndexCalculator.recalculate_for_course()
	EventBus.hole_updated.emit(hole_number)
	return true

## What the order looked like before an edit: the holes in their old sequence,
## the number each one carried, and which hole every golfer part-way round was
## playing.
func _route_snapshot(course: GameManager.CourseData) -> Dictionary:
	var numbers: Dictionary = {}
	for hole in course.holes:
		numbers[hole] = hole.hole_number
	var playing: Array = []
	for golfer in _golfers_on_course():
		var index: int = golfer.current_hole
		if index >= 0 and index < course.holes.size():
			playing.append({"golfer": golfer, "hole": course.holes[index]})
	return {"numbers": numbers, "playing": playing}

## Golfers whose round is under way: the visitors and the owner's own golfer.
func _golfers_on_course() -> Array:
	var golfers: Array = []
	if GameManager.golfer_manager:
		for golfer in GameManager.golfer_manager.get_active_golfers():
			golfers.append(golfer)
	var owner_manager = GameManager.player_golfer_manager
	if owner_manager and owner_manager.golfer and not golfers.has(owner_manager.golfer):
		golfers.append(owner_manager.golfer)
	return golfers

func _after_reroute(course: GameManager.CourseData, snapshot: Dictionary) -> void:
	course._recalculate_par()
	# A golfer part-way round carries on at the hole they were playing, wherever
	# it now sits in the round.
	for entry in snapshot["playing"]:
		var golfer = entry["golfer"]
		if not is_instance_valid(golfer):
			continue
		var index: int = course.holes.find(entry["hole"])
		if index >= 0:
			golfer.current_hole = index
	_realign_statistics(snapshot["numbers"])
	StrokeIndexCalculator.recalculate_for_course()
	rebuild_visualizations()
	EventBus.holes_reordered.emit(course.holes.map(func(hole): return hole.hole_number))

## Hole statistics follow the hole they describe. They are stored by hole number,
## so after a move the numbers are handed back to the same holes.
func _realign_statistics(old_numbers: Dictionary) -> void:
	var previous: Dictionary = GameManager.hole_statistics
	var rebuilt: Dictionary = {}
	for hole in GameManager.current_course.holes:
		var old_number: int = int(old_numbers.get(hole, -1))
		if not previous.has(old_number):
			continue
		var stats: GameManager.HoleStatistics = previous[old_number]
		stats.hole_number = hole.hole_number
		rebuilt[hole.hole_number] = stats
	GameManager.hole_statistics = rebuilt

## EventBus signal handlers
func _on_hole_created(hole_number: int, _par: int, _distance_yards: int) -> void:
	# Get the hole data from GameManager
	if not GameManager.current_course:
		return

	for hole in GameManager.current_course.holes:
		if hole.hole_number == hole_number:
			_create_hole_visualization(hole)
			break

func _on_hole_deleted(hole_number: int) -> void:
	remove_hole_visualization(hole_number)

func _on_hole_updated(hole_number: int) -> void:
	update_hole_visualization(hole_number)

func _on_load_completed(_success: bool) -> void:
	if not _success: return
	for number in hole_visualizers.keys():
		remove_hole_visualization(number)
	_initialize_existing_holes()

func _on_hole_toggled(hole_number: int, is_open: bool) -> void:
	var visualizer = get_hole_visualizer(hole_number)
	if visualizer:
		visualizer.modulate = Color(1, 1, 1, 1) if is_open else Color(0.4, 0.4, 0.4, 0.5)

func _on_hole_visualization_selected(hole_number: int) -> void:
	hole_selected.emit(hole_number)
	EventBus.hole_selected.emit(hole_number)

## Find which hole a grid position belongs to (tee, green, or pin)
func get_hole_at_position(grid_pos: Vector2i) -> GameManager.HoleData:
	if not GameManager.current_course:
		return null
	for hole in GameManager.current_course.holes:
		if grid_pos == hole.tee_position or grid_pos == hole.green_position or grid_pos == hole.hole_position:
			return hole
	return null

## Get hole count
func get_hole_count() -> int:
	return hole_visualizers.size()

## Get total par for all holes
func get_total_par() -> int:
	if GameManager.current_course:
		return GameManager.current_course.total_par
	return 0
