extends RefCounted
class_name GridProjection
## GridProjection - Maps simulation grid coordinates onto world/screen space.

const ORIENTATION_COUNT: int = 4
const WHOLE_TURN_EPSILON: float = 0.00001

var grid_size: Vector2i = Vector2i(128, 128)
var tile_size: Vector2 = Vector2(64, 32)
const isometric: bool = true
## Quarter-turn angle in [0, 4). Whole numbers (0..3) are the four compass
## facings (N, E, S, W); fractional values sit between them.
var orientation: float = 0.0

# Cached projection state, rebuilt whenever an input above changes.
var _center := Vector2.ZERO
var _origin := Vector2.ZERO
var _axis_x := Vector2.ZERO
var _axis_y := Vector2.ZERO
var _bounds := Rect2()
var _dirty := true

func _init(size: Vector2i = Vector2i(128, 128), tile: Vector2 = Vector2(64, 32),
		facing: float = 0.0) -> void:
	grid_size = size
	tile_size = tile
	orientation = _wrap_angle(facing)

static func _wrap_angle(facing: float) -> float:
	var wrapped := wrapf(facing, 0.0, float(ORIENTATION_COUNT))
	if wrapped >= float(ORIENTATION_COUNT) or is_equal_approx(wrapped, float(ORIENTATION_COUNT)):
		return 0.0
	var nearest := roundi(wrapped)
	if absf(wrapped - float(nearest)) <= WHOLE_TURN_EPSILON:
		return float(nearest % ORIENTATION_COUNT)
	return wrapped

func configure(size: Vector2i, tile: Vector2) -> void:
	grid_size = size
	tile_size = tile
	_dirty = true

func _ensure_fresh() -> void:
	if _dirty:
		_refresh()

## Rotate a point-space offset by `turns` quarter turns. Whole turns use the
## exact original integer math so classic views remain bit-identical; fractional
## turns use cos/sin.
func _rotate(offset: Vector2, turns: float) -> Vector2:
	var wrapped := wrapf(turns, 0.0, float(ORIENTATION_COUNT))
	var nearest := roundi(wrapped)
	if absf(wrapped - float(nearest)) <= WHOLE_TURN_EPSILON:
		match nearest % ORIENTATION_COUNT:
			1:
				return Vector2(-offset.y, offset.x)
			2:
				return Vector2(-offset.x, -offset.y)
			3:
				return Vector2(offset.y, -offset.x)
			_:
				return offset
	var radians := wrapped * (PI * 0.5)
	var c := cos(radians)
	var s := sin(radians)
	return Vector2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)

## Convert an offset authored in the default view's screen pixels into a
## fractional tile-space displacement. Sprite anchors use this to stay attached
## to the same point on an isometric tile as the view changes.
func screen_offset_to_grid(offset: Vector2) -> Vector2:
	var half_width := tile_size.x * 0.5
	var half_height := tile_size.y * 0.5
	if is_zero_approx(half_width) or is_zero_approx(half_height):
		return Vector2.ZERO
	var horizontal := offset.x / half_width
	var vertical := offset.y / half_height
	return Vector2((horizontal + vertical) * 0.5, (vertical - horizontal) * 0.5)

## Project a fractional tile-space displacement through the active view.
func project_grid_offset(offset: Vector2) -> Vector2:
	_ensure_fresh()
	return _axis_x * offset.x + _axis_y * offset.y

## Reproject a default-view screen offset through the active isometric basis.
## This preserves its terrain point, unlike rotating screen pixels directly
## (the isometric axes are not square).
func reproject_screen_offset(offset: Vector2) -> Vector2:
	return project_grid_offset(screen_offset_to_grid(offset))

func _refresh() -> void:
	_center = Vector2(grid_size.x * 0.5, grid_size.y * 0.5)

	var rx := _rotate(Vector2(1, 0), orientation)
	var ry := _rotate(Vector2(0, 1), orientation)
	var half_w := tile_size.x * 0.5
	var half_h := tile_size.y * 0.5
	_axis_x = Vector2((rx.x - rx.y) * half_w, (rx.x + rx.y) * half_h)
	_axis_y = Vector2((ry.x - ry.y) * half_w, (ry.x + ry.y) * half_h)
	var span := _center.x + _center.y
	_origin = Vector2(span * half_w, span * half_h)
	var half_ext := Vector2(
		absf(_axis_x.x) * _center.x + absf(_axis_y.x) * _center.y,
		absf(_axis_x.y) * _center.x + absf(_axis_y.y) * _center.y)
	_bounds = Rect2(_origin - half_ext, half_ext * 2.0)
	_dirty = false

func project(grid_pos: Vector2) -> Vector2:
	_ensure_fresh()
	var r := _rotate(grid_pos - _center, orientation)
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
	return _rotate(r, float(ORIENTATION_COUNT) - orientation) + _center

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
	set_orientation(orientation + 1.0)

func rotate_ccw() -> void:
	set_orientation(orientation - 1.0)

func set_orientation(facing: float) -> void:
	orientation = _wrap_angle(facing)
	_dirty = true

## Nearest compass quarter turn (0..3) to the current angle.
func nearest_orientation() -> int:
	return wrapi(roundi(orientation), 0, ORIENTATION_COUNT)
