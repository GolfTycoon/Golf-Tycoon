extends RefCounted
class_name GridProjection
## GridProjection - Maps simulation grid coordinates onto world/screen space.
##
## The grid is turned in whole steps of a full turn before it is laid down as
## an isometric diamond, so every facing the course can rest at is a whole
## number of steps from north. How big a step is a player preference
## (Settings → Controls → Camera → Fine Rotation):
##
##   ORIENTATION_COUNT (4) — the classic compass: N, E, S and W, a quarter
##                           turn (90°) apart.
##   EIGHTH_TURN_COUNT (8) — the compass with its diagonals: N, NE, E, SE, S,
##                           SW, W and NW, an eighth turn (45°) apart.
##
## `orientation` counts steps of the size currently in force, so it always
## reads 0..steps_per_turn - 1 whichever step that is; `eighth_turns` is the
## same thing said in the fine step, so a facing can be saved, restored and
## compared without knowing which step the player has chosen.

const ORIENTATION_COUNT: int = 4
## Facings in a full turn when the view turns in half steps: the finest step
## there is, and the one every facing is a whole number of.
const EIGHTH_TURN_COUNT: int = 8
## Cosine and sine of an eighth turn (45°): half the square root of two, which
## Godot spells out as no constant of its own.
const EIGHTH_TURN_DIAGONAL: float = 0.7071067811865476

var grid_size: Vector2i = Vector2i(128, 128)
var tile_size: Vector2 = Vector2(64, 32)
const isometric: bool = true

## Which facing the view rests at, counted in steps of `steps_per_turn`.
var orientation: int = 0
## Steps in a full turn: ORIENTATION_COUNT or EIGHTH_TURN_COUNT. Change it
## with set_steps_per_turn(), which keeps the facing the view is on.
var steps_per_turn: int = ORIENTATION_COUNT

# Cached projection state, rebuilt whenever an input above changes.
var _center := Vector2.ZERO
var _origin := Vector2.ZERO
var _axis_x := Vector2.ZERO
var _axis_y := Vector2.ZERO
var _bounds := Rect2()
var _dirty := true

func _init(size: Vector2i = Vector2i(128, 128), tile: Vector2 = Vector2(64, 32),
		facing: int = 0) -> void:
	grid_size = size
	tile_size = tile
	orientation = wrapi(facing, 0, steps_per_turn)

func configure(size: Vector2i, tile: Vector2) -> void:
	grid_size = size
	tile_size = tile
	_dirty = true

# =============================================================================
# FACINGS — the step the view turns in, and the facing it rests at
# =============================================================================

## The view's facing as a whole number of eighth turns (0..7): the one facing
## number that means the same thing whichever step the view is turning in, so
## it is what a save stores and what the two steps are translated through.
var eighth_turns: int:
	get:
		# Exact: a step always divides a full turn whole.
		@warning_ignore("integer_division")
		return orientation * EIGHTH_TURN_COUNT / steps_per_turn

## Turn the view to `facing`, given in eighth turns (0..7, wrapping). A facing
## the current step cannot land on — a diagonal while the view turns in quarter
## turns — settles on the nearest one it can.
func set_eighth_turns(facing: int) -> void:
	var eighths := wrapi(facing, 0, EIGHTH_TURN_COUNT)
	# Exact: a step always divides a full turn whole.
	@warning_ignore("integer_division")
	var per_step: int = EIGHTH_TURN_COUNT / steps_per_turn
	set_orientation(int(round(float(eighths) / float(per_step))))

## Turn the view in eighth turns (45°) instead of quarter turns, or back. The
## facing the course is on is kept: a quarter turn is two eighth turns, so
## turning the finer view on leaves the compass exactly where it was, and
## turning it off rounds a diagonal to the nearest cardinal facing.
func set_steps_per_turn(steps: int) -> void:
	var next := EIGHTH_TURN_COUNT if steps >= EIGHTH_TURN_COUNT else ORIENTATION_COUNT
	if next == steps_per_turn:
		return
	var facing := eighth_turns
	steps_per_turn = next
	set_eighth_turns(facing)
	_dirty = true

## The angle the grid is turned through before it is laid down, in radians.
func angle_radians() -> float:
	return TAU * float(eighth_turns) / float(EIGHTH_TURN_COUNT)

## The quarter turn (0..3) whose art a sprite drawn for this facing should
## wear: the buildings, the trees and the placement ghost are painted for the
## four cardinal facings only, so a diagonal wears the art of the cardinal
## facing it sits nearest.
func art_facing() -> int:
	var eighths := eighth_turns
	return wrapi(int(round(float(eighths) * float(ORIENTATION_COUNT) / float(EIGHTH_TURN_COUNT))),
			0, ORIENTATION_COUNT)

func _ensure_fresh() -> void:
	if _dirty:
		_refresh()

## Cosine and sine of a whole number of eighth turns, exact for the quarter
## turns: a quarter turn must not pick up the rounding cos(TAU / 4) carries,
## or every projected point drifts by a fraction of a pixel.
static func _turn_basis(eighths: int) -> Vector2:
	match wrapi(eighths, 0, EIGHTH_TURN_COUNT):
		1:
			return Vector2(EIGHTH_TURN_DIAGONAL, EIGHTH_TURN_DIAGONAL)
		2:
			return Vector2(0.0, 1.0)
		3:
			return Vector2(-EIGHTH_TURN_DIAGONAL, EIGHTH_TURN_DIAGONAL)
		4:
			return Vector2(-1.0, 0.0)
		5:
			return Vector2(-EIGHTH_TURN_DIAGONAL, -EIGHTH_TURN_DIAGONAL)
		6:
			return Vector2(0.0, -1.0)
		7:
			return Vector2(EIGHTH_TURN_DIAGONAL, -EIGHTH_TURN_DIAGONAL)
		_:
			return Vector2(1.0, 0.0)

## Rotate a point-space offset by `eighths` eighth turns (negative turns back).
func _rotate(offset: Vector2, eighths: int) -> Vector2:
	var basis := _turn_basis(eighths)
	return Vector2(offset.x * basis.x - offset.y * basis.y,
			offset.x * basis.y + offset.y * basis.x)

func _refresh() -> void:
	_center = Vector2(grid_size.x * 0.5, grid_size.y * 0.5)

	var eighths := eighth_turns
	var rx := _rotate(Vector2(1, 0), eighths)
	var ry := _rotate(Vector2(0, 1), eighths)
	var half_w := tile_size.x * 0.5
	var half_h := tile_size.y * 0.5
	_axis_x = Vector2((rx.x - rx.y) * half_w, (rx.x + rx.y) * half_h)
	_axis_y = Vector2((ry.x - ry.y) * half_w, (ry.x + ry.y) * half_h)
	var span := _center.x + _center.y
	_bounds = Rect2(Vector2.ZERO, Vector2(span * tile_size.x, span * tile_size.y))
	_origin = _bounds.get_center()
	_dirty = false

func project(grid_pos: Vector2) -> Vector2:
	_ensure_fresh()
	var r := _rotate(grid_pos - _center, eighth_turns)
	return _origin + Vector2(
			(r.x - r.y) * tile_size.x * 0.5,
			(r.x + r.y) * tile_size.y * 0.5)


## Fractional grid-space point for a world position. Exact inverse of project().
func unproject(world_pos: Vector2) -> Vector2:
	_ensure_fresh()
	var d := world_pos - _origin
	var a := d.x / (tile_size.x * 0.5)
	var b := d.y / (tile_size.y * 0.5)
	var r := Vector2((a + b) * 0.5, (b - a) * 0.5)
	return _rotate(r, -eighth_turns) + _center

func cell_corner(cell: Vector2i) -> Vector2:
	return project(Vector2(cell))

func cell_center(cell: Vector2i) -> Vector2:
	return project(Vector2(cell) + Vector2(0.5, 0.5))

func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var p := Vector2(cell)
	return PackedVector2Array([
		project(p),
		project(p + Vector2(1, 0)),
		project(p + Vector2(1, 1)),
		project(p + Vector2(0, 1)),
	])

func cell_world_rect(cell: Vector2i) -> Rect2:
	var poly := cell_polygon(cell)
	var rect := Rect2(poly[0], Vector2.ZERO)
	for i in range(1, poly.size()):
		rect = rect.expand(poly[i])
	return rect

func world_to_cell(world_pos: Vector2) -> Vector2i:
	var g := unproject(world_pos)
	return Vector2i(floori(g.x), floori(g.y))

func grid_origin() -> Vector2:
	_ensure_fresh()
	return project(Vector2.ZERO)

func axis_x() -> Vector2:
	_ensure_fresh()
	return _axis_x

func axis_y() -> Vector2:
	_ensure_fresh()
	return _axis_y

func world_bounds() -> Rect2:
	_ensure_fresh()
	return _bounds

func rotate_cw() -> void:
	set_orientation(orientation + 1)

func rotate_ccw() -> void:
	set_orientation(orientation - 1)

func set_orientation(facing: int) -> void:
	orientation = wrapi(facing, 0, steps_per_turn)
	_dirty = true
