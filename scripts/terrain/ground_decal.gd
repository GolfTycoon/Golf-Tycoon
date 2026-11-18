extends RefCounted
class_name GroundDecal
## Paint laid on the course — a tee's aim arrow and its red markers, the cut of a
## cup, a designated-area ring — as one indexed triangle list
## whose UVs name, at every vertex, the grid point of the ground the paint lies
## on. terrain_decal_occlusion.gdshader reads them to hide the paint wherever
## nearer terrain covers it (TerrainOcclusion.hides_decal() is its CPU twin),
## the way the walking trail is hidden (WalkingPathOverlay.TileMesh). Without
## that shader the UVs cost nothing: the paint is untextured, so the default
## canvas shader samples the plain white texture with them.
##
## CanvasItem's own draw_polyline() and draw_circle() take no UVs, so their
## shapes are built here as the engine builds them. Nothing is handed to the
## engine's polygon triangulator either: it gives up ("Invalid polygon data,
## triangulation failed") on an outline that sculpted ground has folded over
## itself, and draws nothing.

## The engine's antialiasing feather, in pixels (FEATHER_SIZE in
## servers/rendering/renderer_canvas_cull.cpp).
const FEATHER := 1.25
## How far a polyline's mitred corner may reach, in half-widths: the engine's
## clamp.
const MITER_LIMIT := 3.0
## The plane that maps every screen offset to no grid offset at all: a vertex
## offset from a point then carries that point's own ground, as a grass blade
## carries its foot's.
const ON_THE_POINT := Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
## At most how many Newton steps ground_under() takes; it lands to a hundredth
## of a pixel in two or three wherever the ground faces the view.
const GROUND_STEPS := 6
## How much of the level ground's on-screen area a slope must keep for
## surface_plane() to follow it. Steeper toward edge-on, a pixel spans more
## ground than a thin line's offset can be trusted to, so the level plane
## stands in.
const MIN_FACING := 0.02

var points := PackedVector2Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()

func is_empty() -> bool:
	return indices.is_empty()

## Hand the triangles to `canvas_item` — an item's own get_canvas_item() inside
## its _draw(), where they take their turn among its other draw commands.
func draw_on(canvas_item: RID) -> void:
	if indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(canvas_item, indices, points, colors, uvs)

## One vertex: where it is drawn, its colour, and the grid point of its ground.
func add_vertex(point: Vector2, color: Color, ground: Vector2) -> int:
	points.append(point)
	colors.append(color)
	uvs.append(ground)
	return points.size() - 1

## A convex outline filled as the fan from its first point, each point on the
## ground `grounds` names for it (or on none yet: see stand_on()).
func add_convex(outline: PackedVector2Array, color: Color,
		grounds: PackedVector2Array = PackedVector2Array()) -> void:
	if outline.size() < 3:
		return
	var first := points.size()
	for i in outline.size():
		add_vertex(outline[i], color, grounds[i] if i < grounds.size() else Vector2.ZERO)
	for i in range(1, outline.size() - 1):
		indices.append_array(PackedInt32Array([first, first + i, first + i + 1]))

## A filled circle, round on screen as draw_circle() draws it: a fan whose rim
## lies on the plane `to_ground` maps screen offsets onto around `ground` — or,
## with ON_THE_POINT, stands entirely on `ground`.
func add_circle(centre: Vector2, radius: float, color: Color, ground: Vector2 = Vector2.ZERO,
		to_ground: Transform2D = ON_THE_POINT, segments: int = 16) -> void:
	if radius <= 0.0 or segments < 3:
		return
	var hub := add_vertex(centre, color, ground)
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		_add_offset_vertex(centre, ground, Vector2(cos(angle), sin(angle)) * radius, color, to_ground)
	for i in segments:
		indices.append_array(PackedInt32Array([hub, hub + 1 + i, hub + 1 + (i + 1) % segments]))

## A polyline `width` pixels wide, shaped as draw_polyline() shapes it: mitred
## joints clamped to MITER_LIMIT, closed when its last point repeats its first,
## and — `antialiased` — faded out over FEATHER pixels along its edges and past
## its ends. `grounds` names the ground under every point of `line` (or none
## yet: see stand_on()). A vertex offset from a point lies on the plane
## `planes` gives it through that point's ground: one plane per point, one for
## them all, or none - each offset vertex then on its point's own ground.
func add_polyline(line: PackedVector2Array, color: Color, width: float,
		antialiased: bool = false, grounds: PackedVector2Array = PackedVector2Array(),
		planes: Array = []) -> void:
	var count := line.size()
	if count < 2:
		return
	var loop := line[0].is_equal_approx(line[count - 1])
	var half := width * 0.5
	var feather := FEATHER * minf(width, 1.0) if antialiased else 0.0
	var clear := Color(color, 0.0)
	# The first and last segments that go anywhere, as the engine finds them.
	var first_dir := Vector2.ZERO
	for i in range(1, count):
		first_dir = (line[i] - line[i - 1]).normalized()
		if not first_dir.is_zero_approx():
			break
	var last_dir := Vector2.ZERO
	for i in range(count - 1, 0, -1):
		last_dir = (line[i] - line[i - 1]).normalized()
		if not last_dir.is_zero_approx():
			break
	var prev_dir := Vector2.ZERO
	# The previous point's vertices: outer left, left, right, outer right.
	var row := PackedInt32Array()
	for i in count:
		var pos := line[i]
		var ground := grounds[i] if i < grounds.size() else Vector2.ZERO
		var plane: Transform2D = ON_THE_POINT
		if planes.size() == count:
			plane = planes[i]
		elif planes.size() == 1:
			plane = planes[0]
		var first := i == 0
		var last := i == count - 1
		var dir := prev_dir if last else (line[i + 1] - pos).normalized()
		if dir.is_zero_approx():
			dir = prev_dir
		if first and loop:
			prev_dir = last_dir
		elif last and loop:
			prev_dir = first_dir
		var normal: Vector2
		if first and not loop:
			normal = first_dir.orthogonal()
		elif last and not loop:
			normal = last_dir.orthogonal()
		else:
			normal = _joint_normal(dir, prev_dir)
		var edge := normal * half
		var border := normal * feather
		var left := _add_offset_vertex(pos, ground, edge, color, plane)
		var right := _add_offset_vertex(pos, ground, -edge, color, plane)
		var outer_left := -1
		var outer_right := -1
		if antialiased:
			outer_left = _add_offset_vertex(pos, ground, edge + border, clear, plane)
			outer_right = _add_offset_vertex(pos, ground, -edge - border, clear, plane)
		if not first:
			_add_quad(row[1], row[2], right, left)
			if antialiased:
				_add_quad(row[0], row[1], left, outer_left)
				_add_quad(row[2], row[3], outer_right, right)
		var here := PackedInt32Array([outer_left, left, right, outer_right])
		if antialiased and not loop:
			# The fade past either end, pushed out along the line: back from the
			# first point, on from the last.
			if first:
				_add_end(pos, ground, edge, border, -dir * feather, here, clear, plane)
			if last:
				_add_end(pos, ground, edge, border, prev_dir * feather, here, clear, plane)
		row = here
		prev_dir = dir

## Name the ground under every vertex as for a mark standing on the grid point
## `ground` - a sign planted there - rather than lying flat over the ground
## around it: every vertex gets the point on its own pixel's ray at the depth a
## sprite anchored on `ground` gives that pixel, measured from the mark's lowest
## pixel (standing_ground()). Nearer terrain then hides the mark pixel by pixel
## as it hides a tree standing there, while the ground it is painted on never
## does: not however steeply that ground rises toward the camera, nor where a
## fixed-size mark overhangs the sliver such a tile is squeezed to on screen.
## `to_world` takes the vertices to world space.
func stand_on(grid: TerrainGrid, ground: Vector2, to_world: Transform2D) -> void:
	var world_points := PackedVector2Array()
	world_points.resize(points.size())
	for i in points.size():
		world_points[i] = to_world * points[i]
	var depth_y := standing_depth_y(grid, ground, world_points)
	# standing_ground() for every vertex at once: the flat unprojection of the
	# point at the mark's depth row straight above or below it.
	var to_flat_grid := _flat_projection(grid).affine_inverse()
	for i in points.size():
		uvs[i] = to_flat_grid * Vector2(world_points[i].x, depth_y)

## A vertex `offset` pixels from a point of the paint drawn at `pos` on `ground`.
func _add_offset_vertex(pos: Vector2, ground: Vector2, offset: Vector2, color: Color,
		to_ground: Transform2D) -> int:
	return add_vertex(pos + offset, color, ground + to_ground.basis_xform(offset))

func _add_quad(a: int, b: int, c: int, d: int) -> void:
	indices.append_array(PackedInt32Array([a, b, c, a, c, d]))

## The fade past an open polyline's end: the end pushed `push` pixels on, faded
## out, with its two corners rounded off by the edges' own fade.
func _add_end(pos: Vector2, ground: Vector2, edge: Vector2, border: Vector2, push: Vector2,
		end_row: PackedInt32Array, clear: Color, to_ground: Transform2D) -> void:
	var cap_left := _add_offset_vertex(pos, ground, edge + push, clear, to_ground)
	var cap_right := _add_offset_vertex(pos, ground, -edge + push, clear, to_ground)
	var corner_left := _add_offset_vertex(pos, ground, edge + push + border, clear, to_ground)
	var corner_right := _add_offset_vertex(pos, ground, -edge + push - border, clear, to_ground)
	_add_quad(cap_left, cap_right, end_row[2], end_row[1])
	_add_quad(corner_left, cap_left, end_row[1], end_row[0])
	_add_quad(cap_right, corner_right, end_row[3], end_row[2])

## The offset of a polyline's joint from its point, per half-width: the bisector
## of the segments meeting there, lengthened to keep the line's width through
## the turn but never past MITER_LIMIT (the engine's
## compute_polyline_edge_offset_clamped()).
static func _joint_normal(dir: Vector2, prev_dir: Vector2) -> Vector2:
	var bisector := (prev_dir * dir.length() - dir * prev_dir.length()).normalized()
	var angle := atan2(bisector.cross(prev_dir), bisector.dot(prev_dir))
	var sin_angle := sin(angle)
	var length := 1.0
	if not is_zero_approx(sin_angle) and not dir.is_equal_approx(prev_dir):
		length = clampf(1.0 / sin_angle, -MITER_LIMIT, MITER_LIMIT)
	else:
		bisector = dir.orthogonal()
	if bisector.is_zero_approx():
		bisector = dir.orthogonal()
	return bisector * length

## The flat screen y a mark standing on `ground` is measured from when its
## lowest pixel among `world_points` lies under the ground's own: the ground's
## flat projection pushed down by how far along its ray the ground under that
## lowest pixel lies (TerrainOcclusion.contact_reach() - the mark's reach down
## the screen on level ground, further where the ground rises toward the camera).
static func standing_depth_y(grid: TerrainGrid, ground: Vector2,
		world_points: PackedVector2Array) -> float:
	var lowest := -INF
	for point in world_points:
		lowest = maxf(lowest, point.y)
	var below := lowest - grid.grid_point_to_screen(ground).y
	var reach := TerrainOcclusion.contact_reach(grid, ground, below) if below > 0.0 else 0.0
	return grid.projection.project(ground).y + reach

## The point on the ray through the world point `world` at the depth of a
## standing mark's pixel there: `depth_y - world.y` pixels along the ray, where
## `depth_y` is the mark's standing_depth_y(). The decal shader measures a pixel
## whose ground lies on its own ray exactly that deep (and never deeper than
## that ground itself), as the sprite shader measures a sprite's.
static func standing_ground(grid: TerrainGrid, world: Vector2, depth_y: float) -> Vector2:
	return TerrainOcclusion.point_on_ray(grid, world, depth_y - world.y)

## The view's projection of the flat (unlifted) course: grid point to world.
static func _flat_projection(grid: TerrainGrid) -> Transform2D:
	var view := grid.projection
	return Transform2D(view.axis_x(), view.axis_y(), view.grid_origin())

## How steeply the ground rises at a grid point, in pixels of lift per tile
## along x and along y: the slope of the bilinear tile under it (the tile up
## and to the left of a corner it lies on).
static func ground_rise(grid: TerrainGrid, ground: Vector2) -> Vector2:
	var width := grid.grid_width
	var height := grid.grid_height
	if width <= 0 or height <= 0:
		return Vector2.ZERO
	var gx := clampf(ground.x, 0.0, float(width))
	var gy := clampf(ground.y, 0.0, float(height))
	var x0 := clampi(floori(gx), 0, width - 1)
	var y0 := clampi(floori(gy), 0, height - 1)
	var fx := gx - float(x0)
	var fy := gy - float(y0)
	var h00 := float(grid.get_vertex_elevation(Vector2i(x0, y0)))
	var h10 := float(grid.get_vertex_elevation(Vector2i(x0 + 1, y0)))
	var h01 := float(grid.get_vertex_elevation(Vector2i(x0, y0 + 1)))
	var h11 := float(grid.get_vertex_elevation(Vector2i(x0 + 1, y0 + 1)))
	var rise := Vector2(lerpf(h10 - h00, h11 - h01, fy), lerpf(h01 - h00, h11 - h10, fx))
	# Off the edge of the course the ground is held level (get_elevation_at()).
	if ground.x < 0.0 or ground.x > float(width):
		rise.x = 0.0
	if ground.y < 0.0 or ground.y > float(height):
		rise.y = 0.0
	return rise * TerrainGrid.ELEVATION_STEP_Y

## The linear map from a screen offset to the grid offset that reaches it along
## ground rising `rise` (ground_rise()): the inverse of the ground's projection
## there, for the thin offsets of a line laid on it. Ground turned edge-on to
## the view, or away from it, has no such map; there the level plane stands in.
static func surface_plane(grid: TerrainGrid, rise: Vector2) -> Transform2D:
	var axis_x := grid.projection.axis_x()
	var axis_y := grid.projection.axis_y()
	var level := Transform2D(axis_x, axis_y, Vector2.ZERO)
	var slope := Transform2D(axis_x - Vector2(0.0, rise.x), axis_y - Vector2(0.0, rise.y),
			Vector2.ZERO)
	var level_det := level.determinant()
	if absf(level_det) < 0.000001:
		return Transform2D.IDENTITY
	if slope.determinant() / level_det < MIN_FACING:
		return level.affine_inverse()
	return slope.affine_inverse()

## The linear map from a screen offset at `ground` to the grid offset that
## reaches it along the ground's tangent plane there, measured across a tile:
## the inverse of grid_point_to_screen()'s derivative. Where the ground turns
## edge-on to the view the plane cannot be inverted, so the level plane is used
## instead (used for the walking trail's round patches, a few pixels across).
static func screen_to_ground(grid: TerrainGrid, ground: Vector2) -> Transform2D:
	var projection := grid.projection
	var axis_x := projection.axis_x()
	var axis_y := projection.axis_y()
	var level := Transform2D(axis_x, axis_y, Vector2.ZERO)
	var rise := Vector2(
		grid.get_elevation_at(ground + Vector2(0.5, 0.0))
			- grid.get_elevation_at(ground - Vector2(0.5, 0.0)),
		grid.get_elevation_at(ground + Vector2(0.0, 0.5))
			- grid.get_elevation_at(ground - Vector2(0.0, 0.5))) \
		* TerrainGrid.ELEVATION_STEP_Y
	var slope := Transform2D(axis_x - Vector2(0.0, rise.x), axis_y - Vector2(0.0, rise.y),
			Vector2.ZERO)
	var level_det := level.determinant()
	if absf(level_det) < 0.000001:
		return Transform2D.IDENTITY
	if slope.determinant() / level_det < 0.25:
		return level.affine_inverse()
	return slope.affine_inverse()

## The grid point whose ground is drawn at the world point `world`, found from
## `near` - a point of the same ground close by, such as a prop's foot - by
## Newton's method on grid_point_to_screen(), each step along the slope of the
## tile it stands on (ground_rise()), halved while it overshoots. Where no step
## gets closer (ground turned away from the view), the closest point found is
## kept.
static func ground_under(grid: TerrainGrid, world: Vector2, near: Vector2) -> Vector2:
	var axis_x := grid.projection.axis_x()
	var axis_y := grid.projection.axis_y()
	var level_det := absf(Transform2D(axis_x, axis_y, Vector2.ZERO).determinant())
	var ground := near
	var miss := world - grid.grid_point_to_screen(ground)
	for _step in GROUND_STEPS:
		if miss.length_squared() < 0.0001:
			break
		var rise := ground_rise(grid, ground)
		var slope := Transform2D(axis_x - Vector2(0.0, rise.x), axis_y - Vector2(0.0, rise.y),
				Vector2.ZERO)
		if absf(slope.determinant()) < 0.000001 * level_det:
			break
		var stride := slope.affine_inverse().basis_xform(miss)
		var improved := false
		for _halving in 4:
			var next := ground + stride
			var next_miss := world - grid.grid_point_to_screen(next)
			if next_miss.length_squared() < miss.length_squared():
				ground = next
				miss = next_miss
				improved = true
				break
			stride *= 0.5
		if not improved:
			break
	return ground
