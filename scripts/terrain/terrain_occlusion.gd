extends RefCounted
class_name TerrainOcclusion
## The per-pixel depth test the terrain-occlusion shaders run, on the CPU.
##
## One screen pixel is a vertical ray through the course. A point drawn at that
## pixel `t` pixels above its flat (unlifted) projection sits at parameter `t`
## along the ray, and a larger `t` is nearer the viewer. The terrain the pixel
## shows is the ray's greatest crossing with the heightfield — the same surface
## `TerrainGrid.screen_to_grid_point()` picks — so a drawn point is hidden
## exactly when that front surface is nearer than the point.
##
## What differs between the occluded overlays is the point's own `t`:
##   - a tree is a billboard on one ground point (terrain_sprite_occlusion);
##   - trail paint lies on the ground under it (`decal_t()`,
##     terrain_decal_occlusion.gdshader);
##   - a building fills the column over its footprint (`footprint_t()`,
##     terrain_footprint_occlusion.gdshader);
##   - a golfer is a billboard like a tree, on the ground point they stand on
##     (`standing_point()`, terrain_sprite_occlusion.gdshader);
##   - a golf ball is a billboard over the grid point under it, measured from
##     the ground under the foot of its contact shadow (`contact_reach()`) and
##     lifted by its flight arc (`hides_ball()`, terrain_sprite_occlusion.gdshader);
##   - a tee's aim arrow, a cup and a designated-area ring are paint on the
##     ground, like the trail (`decal_t()`, laid out by GroundDecal);
##   - a pin and a decoration are billboards on their foot, measured from the
##     lowest pixel of their art (`contact_reach()`, `hides_with_material()`).
## The shaders and this class compute the same quantities, so building and
## golfer picking and the tests can ask what the GPU will hide.

## The shaders' `occlusion_epsilon` defaults, in screen pixels. A trail's flat
## triangles only approximate the curved ground they are laid on, so they get the
## slack a sprite on one exact ground point does not need.
const DECAL_EPSILON := 1.5
const FOOTPRINT_EPSILON := 0.05
## A golfer's sprite is anchored with the bottom row of their feet one pixel
## under the point they stand on, and walking bobs it by up to 0.75 px more, so
## their material gets this slack instead of the tree default.
const GOLFER_EPSILON := 2.0
## A ball's material gets the same slack: it is measured from the ground under
## the foot of its contact shadow (`contact_reach()`), straight down the screen
## from its ground point, and the ground under the rest of the shadow, a pixel or
## two to either side, can tilt a little higher.
const BALL_EPSILON := 2.0
## A pin and a decoration stand on their foot the way a golfer does: their art
## reaches a pixel or so to either side of it (a pole's width, a prop's slight
## tilt, the rounding of its sprite), so their materials get the same slack.
const PROP_EPSILON := 2.0

## How far, in tiles, a figure can move between two updates and still be taken to
## stand on the surface it stood on. Walking covers a fraction of a tile a frame;
## anything longer is a placement (a tee, a door, a loaded game).
const STANDING_STEP_LIMIT := 1.5
## Roots closer than this along a ray (in pixels) are one crossing found twice,
## once on each side of a tile boundary.
const CROSSING_MERGE := 0.0001
## Ray parameter no terrain reaches (the highest is 5 levels of 10 px above the
## base): a sprite anchored here is never hidden.
const UNHIDDEN_T := 1000.0
## How far `contact_reach()` walks toward the viewer, in pixels of its ray, and in
## what steps: two tiles' diagonal, far enough for a ball's contact shadow on the
## steepest slope whole levels make that still faces the camera, three levels a
## tile toward it (39 px).
const CONTACT_REACH_LIMIT := 64.0
const CONTACT_REACH_STEP := 1.0

## Ray parameter of the terrain a world pixel shows, or -INF where the pixel
## shows no course at all.
static func terrain_t(grid: TerrainGrid, world: Vector2) -> float:
	var point := grid.screen_to_grid_point(world)
	if point == TerrainGrid.INVALID_GRID_POINT:
		return -INF
	return ground_t(grid, point)

## Ray parameter of the ground at a grid point: how far it is lifted above its
## flat projection, in pixels.
static func ground_t(grid: TerrainGrid, ground: Vector2) -> float:
	return (grid.get_elevation_at(ground) - TerrainGrid.BASE_ELEVATION) * TerrainGrid.ELEVATION_STEP_Y

## Ray parameter of a point drawn at `world` straight above (or on) the grid
## point `ground`, whatever the height of the ground there.
static func point_t_above(grid: TerrainGrid, ground: Vector2, world: Vector2) -> float:
	return grid.projection.project(ground).y - world.y

## Ray parameter of trail paint drawn at `world` for the ground point `ground`
## (the UV WalkingPathOverlay gives the vertices): paint on the ground is at the
## ground's height, and a grass blade standing on it is above it.
static func decal_t(grid: TerrainGrid, ground: Vector2, world: Vector2) -> float:
	return maxf(point_t_above(grid, ground, world), ground_t(grid, ground))

## Ray parameter at which the pixel's ray reaches the column over `footprint`
## (grid units) from the camera side: the building volume's front face. A pixel
## beside the column continues smoothly from its edge.
static func footprint_front_t(grid: TerrainGrid, footprint: Rect2, world: Vector2) -> float:
	var flat := grid.projection.unproject(world)
	var direction := grid.projection.unproject(world + Vector2(0.0, 1.0)) - flat
	var enter_t := -INF
	var leave_t := INF
	for axis in range(2):
		var step: float = direction[axis]
		if absf(step) < 0.000001:
			continue
		var side_a: float = (footprint.position[axis] - flat[axis]) / step
		var side_b: float = (footprint.end[axis] - flat[axis]) / step
		enter_t = maxf(enter_t, minf(side_a, side_b))
		leave_t = minf(leave_t, maxf(side_a, side_b))
	return leave_t if enter_t <= leave_t else 0.5 * (enter_t + leave_t)

## Ray parameter of a building pixel at `world`: the footprint's front face,
## never below the level foundation it stands on.
static func footprint_t(grid: TerrainGrid, footprint: Rect2, world: Vector2) -> float:
	return maxf(ground_t(grid, footprint.get_center()), footprint_front_t(grid, footprint, world))

## Every ray parameter at which the vertical ray of the screen pixel `world`
## meets the course surface, the front-most (greatest) first. The first is the
## surface the pixel shows (`TerrainGrid.screen_to_grid_point()`); the others lie
## behind it. Empty where the ray misses the course, and in a view without relief
## (top-down), where a pixel has no depth to speak of.
static func ray_crossings(grid: TerrainGrid, world: Vector2) -> PackedFloat64Array:
	var crossings := PackedFloat64Array()
	if not grid.view_isometric or TerrainGrid.ELEVATION_STEP_Y == 0.0:
		return crossings
	var flat := grid.projection.unproject(world)
	var direction := grid.projection.unproject(world + Vector2(0.0, 1.0)) - flat
	var lower_t := float(TerrainGrid.MIN_ELEVATION - TerrainGrid.BASE_ELEVATION) * TerrainGrid.ELEVATION_STEP_Y
	var upper_t := float(TerrainGrid.MAX_ELEVATION - TerrainGrid.BASE_ELEVATION) * TerrainGrid.ELEVATION_STEP_Y
	# Clip the ray to the course rectangle, as screen_to_grid_point() does.
	for axis in range(2):
		var start: float = flat[axis]
		var step: float = direction[axis]
		var extent := float(grid.grid_width if axis == 0 else grid.grid_height)
		if absf(step) < 0.000001:
			if start < 0.0 or start > extent:
				return crossings
			continue
		var edge_a := -start / step
		var edge_b := (extent - start) / step
		lower_t = maxf(lower_t, minf(edge_a, edge_b))
		upper_t = minf(upper_t, maxf(edge_a, edge_b))
	if lower_t > upper_t:
		return crossings
	if absf(upper_t - lower_t) <= TerrainGrid.ELEVATION_RAY_EPSILON:
		if absf(upper_t - ground_t(grid, flat + direction * upper_t)) <= TerrainGrid.ELEVATION_RAY_EPSILON:
			crossings.append(upper_t)
		return crossings
	# Walk the crossed tiles from the front backwards. Height is bilinear inside
	# a tile, so each tile holds at most two crossings: the roots of a quadratic.
	# Walking golfers ask this every frame, so the heights are read straight from
	# the grid's vertex array rather than through get_vertex_elevation().
	grid._ensure_vertex_storage()
	var heights: PackedInt32Array = grid._vertex_elevation
	var stride: int = grid.grid_width + 1
	var current_t := upper_t
	for _segment in range(TerrainGrid.ELEVATION_RAY_MAX_TILE_STEPS):
		var current_point := flat + direction * current_t
		var next_t := lower_t
		for axis in range(2):
			var step: float = direction[axis]
			if absf(step) < 0.000001:
				continue
			var boundary := floorf(current_point[axis] - TerrainGrid.ELEVATION_RAY_EPSILON) \
					if step > 0.0 else ceilf(current_point[axis] + TerrainGrid.ELEVATION_RAY_EPSILON)
			var boundary_t := (boundary - flat[axis]) / step
			if boundary_t < current_t and boundary_t > next_t:
				next_t = boundary_t
		if next_t >= current_t - TerrainGrid.ELEVATION_RAY_EPSILON:
			break
		var middle_t := (current_t + next_t) * 0.5
		var middle_point := flat + direction * middle_t
		var cell := Vector2i(floori(middle_point.x), floori(middle_point.y))
		if grid.is_valid_position(cell):
			_append_tile_crossings(crossings, heights, stride, flat, direction, cell,
					current_t, next_t, middle_t)
		if next_t <= lower_t + TerrainGrid.ELEVATION_RAY_EPSILON:
			break
		current_t = next_t
	return crossings

## Append the crossings of the ray with one tile's bilinear patch in
## [low_t, high_t], the greater first - the same quadratic
## TerrainGrid._intersect_elevation_tile() solves for the front-most one - unless
## one repeats the crossing just found on the other side of the tile boundary.
static func _append_tile_crossings(crossings: PackedFloat64Array, heights: PackedInt32Array,
		stride: int, flat: Vector2, direction: Vector2, cell: Vector2i,
		high_t: float, low_t: float, middle_t: float) -> void:
	var index := cell.y * stride + cell.x
	var h00 := float(heights[index] - TerrainGrid.BASE_ELEVATION)
	var h10 := float(heights[index + 1] - TerrainGrid.BASE_ELEVATION)
	var h01 := float(heights[index + stride] - TerrainGrid.BASE_ELEVATION)
	var h11 := float(heights[index + stride + 1] - TerrainGrid.BASE_ELEVATION)
	var hx := h10 - h00
	var hy := h01 - h00
	var hxy := h11 - h10 - h01 + h00
	var middle_point := flat + direction * middle_t
	var u := middle_point.x - float(cell.x)
	var v := middle_point.y - float(cell.y)
	var c0 := h00 + hx * u + hy * v + hxy * u * v
	var c1 := hx * direction.x + hy * direction.y + hxy * (u * direction.y + v * direction.x)
	var c2 := hxy * direction.x * direction.y
	# q = t - middle_t; F(q) = a*q^2 + b*q + c is zero where the ray meets the patch.
	var a := -TerrainGrid.ELEVATION_STEP_Y * c2
	var b := 1.0 - TerrainGrid.ELEVATION_STEP_Y * c1
	var c := middle_t - TerrainGrid.ELEVATION_STEP_Y * c0
	var low_q := low_t - middle_t
	var high_q := high_t - middle_t
	var epsilon := TerrainGrid.ELEVATION_RAY_EPSILON
	if absf(a) <= epsilon:
		if absf(b) <= epsilon:
			# An edge-on patch can lie along the whole interval: its front end.
			if absf(c) <= epsilon:
				_append_crossing(crossings, high_t)
			return
		var q := -c / b
		if q >= low_q - epsilon and q <= high_q + epsilon:
			_append_crossing(crossings, middle_t + clampf(q, low_q, high_q))
		return
	var discriminant := b * b - 4.0 * a * c
	if discriminant < -epsilon:
		return
	var root := sqrt(maxf(0.0, discriminant))
	var first := (-b + root) / (2.0 * a)
	var second := (-b - root) / (2.0 * a)
	var near_q := maxf(first, second)
	if near_q >= low_q - epsilon and near_q <= high_q + epsilon:
		_append_crossing(crossings, middle_t + clampf(near_q, low_q, high_q))
	var far_q := minf(first, second)
	if root > epsilon and far_q >= low_q - epsilon and far_q <= high_q + epsilon:
		_append_crossing(crossings, middle_t + clampf(far_q, low_q, high_q))

static func _append_crossing(crossings: PackedFloat64Array, crossing_t: float) -> void:
	if crossings.is_empty() or crossings[crossings.size() - 1] - crossing_t > CROSSING_MERGE:
		crossings.append(crossing_t)

## The grid point a figure drawn with its feet at `world` stands on: one of the
## surface crossings of the ray through its feet. Which one, when hills overlap
## on screen:
##   1. the crossing nearest `near` - where the figure stood a moment ago, or a
##      position it is known to have - so a golfer walking behind a hill stays
##      behind it while they walk;
##   2. after a longer jump, the crossing at a tile centre: every spawn, tee,
##      clubhouse door and work area is one;
##   3. else the crossing nearest the base level, where a figure stood while
##      the course was flat (the first sculpted hill must not lift them onto it);
##      skipped with `prefer_level` false, for a point with no such past;
##   4. else the front-most crossing, the surface the pixel shows.
## INVALID_GRID_POINT where the ray misses the course.
static func standing_point(grid: TerrainGrid, world: Vector2,
		near: Vector2 = TerrainGrid.INVALID_GRID_POINT, prefer_level: bool = true) -> Vector2:
	return standing_point_among(grid, world, ray_crossings(grid, world), near, prefer_level)

## standing_point() for a ray whose crossings (ray_crossings()) are already
## known: the caller can also tell from them whether the front-most surface,
## crossings[0], hides the point found.
static func standing_point_among(grid: TerrainGrid, world: Vector2, crossings: PackedFloat64Array,
		near: Vector2 = TerrainGrid.INVALID_GRID_POINT, prefer_level: bool = true) -> Vector2:
	if crossings.is_empty():
		return TerrainGrid.INVALID_GRID_POINT
	var flat := grid.projection.unproject(world)
	var direction := grid.projection.unproject(world + Vector2(0.0, 1.0)) - flat
	if near != TerrainGrid.INVALID_GRID_POINT:
		var tracked := _crossing_near(flat, direction, crossings, near)
		if tracked != TerrainGrid.INVALID_GRID_POINT:
			return tracked
	for crossing_t in crossings:
		var point := flat + direction * crossing_t
		if is_tile_centre(point):
			# Exactly: a view turn re-derives every waypoint from the screen, and
			# one rounding error a turn would add up over a gradual turn's frames.
			return point.floor() + Vector2(0.5, 0.5)
	if prefer_level:
		var level := _crossing_near(flat, direction, crossings, flat)
		if level != TerrainGrid.INVALID_GRID_POINT:
			return level
	return flat + direction * crossings[0]

## The crossing nearest `target` (grid units), or INVALID when even the nearest
## lies further than STANDING_STEP_LIMIT from it.
static func _crossing_near(flat: Vector2, direction: Vector2, crossings: PackedFloat64Array,
		target: Vector2) -> Vector2:
	var best := TerrainGrid.INVALID_GRID_POINT
	var best_distance := STANDING_STEP_LIMIT
	for crossing_t in crossings:
		var point := flat + direction * crossing_t
		var distance := point.distance_to(target)
		if distance <= best_distance:
			best_distance = distance
			best = point
	return best

## Whether a grid point is (to a thousandth of a tile) the centre of a tile.
static func is_tile_centre(point: Vector2) -> bool:
	return absf(fposmod(point.x, 1.0) - 0.5) <= 0.001 and absf(fposmod(point.y, 1.0) - 0.5) <= 0.001

## A grid point on the ray through `world` at ray parameter `t`: the anchor that
## puts a sprite's pixel at `world` exactly `t` pixels up its ray. With
## UNHIDDEN_T it is an anchor no terrain can be in front of.
static func point_on_ray(grid: TerrainGrid, world: Vector2, t: float) -> Vector2:
	var flat := grid.projection.unproject(world)
	return flat + (grid.projection.unproject(world + Vector2(0.0, 1.0)) - flat) * t

## Whether the terrain hides a point drawn at `world` whose ray parameter
## (including any slack) is `point_t`.
static func hides(grid: TerrainGrid, world: Vector2, point_t: float) -> bool:
	return terrain_t(grid, world) > point_t

## Whether the terrain hides the trail paint drawn at `world` for `ground`.
static func hides_decal(grid: TerrainGrid, ground: Vector2, world: Vector2) -> bool:
	return hides(grid, world, decal_t(grid, ground, world) + DECAL_EPSILON)

## Whether the terrain hides the pixel of a building on `footprint` at `world`.
static func hides_footprint(grid: TerrainGrid, footprint: Rect2, world: Vector2) -> bool:
	return hides(grid, world, footprint_t(grid, footprint, world) + FOOTPRINT_EPSILON)

## Whether the terrain hides the pixel at `world` of a sprite standing on the
## grid point `ground` (the golfer's anchor), with the golfers' slack.
static func hides_standing(grid: TerrainGrid, ground: Vector2, world: Vector2,
		epsilon: float = GOLFER_EPSILON) -> bool:
	return hides(grid, world, point_t_above(grid, ground, world) + epsilon)

## How far along its ray, past the ball's own ground point `ground`, lies the
## ground a ball's contact shadow reaching `below` pixels down the screen is
## drawn on: what its billboard must be lifted by for the ground under its
## shadow not to cut the shadow. On level ground that is `below` itself. On a
## slope rising toward the camera the shadow's foot lies on ground nearer the
## viewer, `below / (1 - s)` for a slope rising `s` pixels a pixel - the ground
## is found by walking toward the viewer straight down the screen. Where the
## ground turns back toward the ball first, it folds over the ball (a step or a
## cliff in front of it) and its near side must hide the ball, so the answer is
## `below` again; a slope steep enough that the walk never reaches the foot is
## held to CONTACT_REACH_LIMIT.
static func contact_reach(grid: TerrainGrid, ground: Vector2, below: float) -> float:
	var flat := grid.projection.project(ground)
	var toward := grid.projection.unproject(flat + Vector2(0.0, 1.0)) - ground
	var ground_lift := ground_t(grid, ground)
	var reach := 0.0
	var drop := 0.0  # How far under the ground point the ground at `reach` is drawn.
	while reach < CONTACT_REACH_LIMIT:
		var next := minf(reach + CONTACT_REACH_STEP, CONTACT_REACH_LIMIT)
		var next_drop := next - (ground_t(grid, ground + toward * next) - ground_lift)
		if next_drop >= below:
			return maxf(below, reach + (next - reach) * (below - drop) / (next_drop - drop))
		if next_drop < drop:
			return below
		reach = next
		drop = next_drop
	return CONTACT_REACH_LIMIT

## Whether the terrain hides the pixel at `world` of a ball over the grid point
## `ground`, measured from `lift` pixels along its rays past the ground point
## (the sprite shader's ground_offset.y: `contact_reach()` of the ball's contact
## shadow, plus however far a straight flight track runs under the ground
## there), with the balls' slack.
static func hides_ball(grid: TerrainGrid, ground: Vector2, lift: float, world: Vector2) -> bool:
	return hides(grid, world, point_t_above(grid, ground, world) + lift + BALL_EPSILON)

## Whether the terrain hides the pixel at `world` of whatever wears
## `sprite_material` (terrain_sprite_occlusion.gdshader): the shader's own test,
## read from the anchor, the lift and the slack that material carries.
static func hides_with_material(grid: TerrainGrid, sprite_material: ShaderMaterial,
		world: Vector2) -> bool:
	var ground: Vector2 = _uniform(sprite_material, "ground_grid")
	var lift: Vector2 = _uniform(sprite_material, "ground_offset")
	var epsilon: float = _uniform(sprite_material, "occlusion_epsilon")
	return hides(grid, world, point_t_above(grid, ground, world) + lift.y + epsilon)

## A material's uniform, or the shader's default for one never set on it.
static func _uniform(shader_material: ShaderMaterial, uniform: String) -> Variant:
	var value: Variant = shader_material.get_shader_parameter(uniform)
	if value == null and shader_material.shader != null:
		value = RenderingServer.shader_get_parameter_default(shader_material.shader.get_rid(), uniform)
	return value
