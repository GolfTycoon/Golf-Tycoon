extends RefCounted
class_name HoleRouting
## HoleRouting - The order of play: how the holes are sequenced and how well the
## route walks.
##
## A course is `GameManager.current_course.holes`, an array played in order, and
## `hole_number` is that order's label (1..N). The two are kept in step in one
## place - renumber(), the same rule HoleCreationTool.delete_hole() follows when a
## hole is removed - and everything that changes the route goes through here, so a
## hole's number can never disagree with where it sits in the round.
##
## The route is judged here too. Golfers walk from the green they have just holed
## out on to the next tee; RoutingOverlay paints that walk green, amber or red by
## length. route_report() gathers the same walk for the Course Map's Routing mode:
## the average leg, the worst leg, and how many legs are long enough to cost the
## course its pace rating.

## Walk lengths (in tiles) at which a leg between two holes stops being short and
## starts being a problem. Shared with the on-course RoutingOverlay so the map and
## the course agree.
const SHORT_TILES: float = RoutingOverlay.SHORT_THRESHOLD
const MODERATE_TILES: float = RoutingOverlay.MODERATE_THRESHOLD

enum Grade { SHORT, MODERATE, LONG }

## Label the holes of a course 1..N in play order. Adding, removing or moving a
## hole always ends here.
static func renumber(holes: Array) -> void:
	for i in holes.size():
		holes[i].hole_number = i + 1

## Move one hole to another place in the round. Indices are 0-based positions in
## `holes`; returns false when either index is off the end of the course.
static func move(holes: Array, from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= holes.size():
		return false
	if to_index < 0 or to_index >= holes.size():
		return false
	if from_index == to_index:
		return false
	var hole = holes[from_index]
	holes.remove_at(from_index)
	holes.insert(to_index, hole)
	renumber(holes)
	return true

## Play the course the other way round: the last hole becomes the first.
static func reverse(holes: Array) -> bool:
	if holes.size() < 2:
		return false
	holes.reverse()
	renumber(holes)
	return true

## Turn a hole around: the green becomes the tee and the tee box is cut with the
## cup. Both ends already stand on painted tiles, so the tiles change places with
## the hole's data. The length of the hole is unchanged.
##
## Refused (returns false) when either end is not painted the way the hole says it
## is - a hole whose tee or green has been repainted is left alone rather than
## half-turned.
static func flip(hole: GameManager.HoleData, grid: TerrainGrid) -> bool:
	if hole == null or grid == null:
		return false
	var tee: Vector2i = hole.tee_position
	var green: Vector2i = hole.green_position
	if tee == green:
		return false
	if not grid.is_valid_position(tee) or not grid.is_valid_position(green):
		return false
	if grid.get_tile(tee) != TerrainTypes.Type.TEE_BOX:
		return false
	if grid.get_tile(green) != TerrainTypes.Type.GREEN:
		return false
	# The old green becomes the tee box (painting over a Green With Hole tile
	# takes its cup with it), then the old tee box becomes the green with the cup.
	grid.set_tile(green, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(tee, TerrainTypes.Type.GREEN)
	grid.add_cup_tile(tee)
	hole.tee_position = green
	hole.green_position = tee
	hole.hole_position = tee
	hole.difficulty_rating = DifficultyCalculator.calculate_hole_difficulty(hole, grid)
	return true

# =============================================================================
# The walk
# =============================================================================

## How far golfers walk from the green after hole `index` to the tee of the hole
## after it, in tiles. Returns 0.0 when there is no next hole.
static func leg_tiles(holes: Array, index: int) -> float:
	if index < 0 or index + 1 >= holes.size():
		return 0.0
	return Vector2(holes[index].green_position).distance_to(Vector2(holes[index + 1].tee_position))

## Every walk between consecutive holes, in play order. Each entry is
## {after_hole, from_hole, to_hole, tiles, yards, grade}.
static func legs(holes: Array) -> Array:
	var out: Array = []
	for i in range(maxi(0, holes.size() - 1)):
		var tiles := leg_tiles(holes, i)
		out.append({
			"after_hole": i + 1,
			"from_hole": int(holes[i].hole_number),
			"to_hole": int(holes[i + 1].hole_number),
			"tiles": tiles,
			"yards": int(roundf(tiles * HoleLayout.YARDS_PER_TILE)),
			"grade": grade_for(tiles),
		})
	return out

static func grade_for(tiles: float) -> int:
	if tiles < SHORT_TILES:
		return Grade.SHORT
	if tiles < MODERATE_TILES:
		return Grade.MODERATE
	return Grade.LONG

static func grade_name(grade: int) -> String:
	match grade:
		Grade.MODERATE: return "Moderate"
		Grade.LONG: return "Long"
		_: return "Short"

static func grade_color(grade: int) -> Color:
	match grade:
		Grade.MODERATE: return Color(0.9, 0.9, 0.3)
		Grade.LONG: return Color(0.9, 0.3, 0.3)
		_: return Color(0.3, 0.9, 0.3)

## Average walk between holes, in tiles (0.0 for a course with fewer than two
## holes). Same number RoutingOverlay.calculate_avg_walk_distance() reports.
static func average_leg_tiles(holes: Array) -> float:
	var walks := legs(holes)
	if walks.is_empty():
		return 0.0
	var total: float = 0.0
	for walk in walks:
		total += float(walk["tiles"])
	return total / float(walks.size())

## What the Routing mode shows above the list: the shape of the round.
## Returns {holes, open, total_par, total_yards, average_leg_tiles, longest_leg,
## long_legs, worst_after_hole}.
static func route_report(holes: Array) -> Dictionary:
	var report := {
		"holes": holes.size(),
		"open": 0,
		"total_par": 0,
		"total_yards": 0,
		"average_leg_tiles": 0.0,
		"longest_leg": 0.0,
		"worst_after_hole": 0,
		"long_legs": 0,
	}
	for hole in holes:
		if hole.is_open:
			report["open"] += 1
		report["total_par"] += int(hole.par)
		report["total_yards"] += int(hole.distance_yards)
	var walks := legs(holes)
	if walks.is_empty():
		return report
	var total: float = 0.0
	for walk in walks:
		var tiles := float(walk["tiles"])
		total += tiles
		if tiles > float(report["longest_leg"]):
			report["longest_leg"] = tiles
			report["worst_after_hole"] = int(walk["after_hole"])
		if int(walk["grade"]) == Grade.LONG:
			report["long_legs"] += 1
	report["average_leg_tiles"] = total / float(walks.size())
	return report
