extends Node2D
class_name WalkingPathOverlay
## WalkingPathOverlay - Renders the Path improvement (Improvements tab).
##
## A walking path is a trodden dirt trail laid ON TOP of hostable ground (see
## TerrainTypes.WALKING_PATH_TERRAINS): each tile carries a trodden pad, and
## pads on edge-adjacent tiles join with a ribbon, so a trail reads as one
## continuous walk. A trail whose connected network reaches the clubhouse is
## rendered as a paved stone promenade instead of dirt, and golfers walk quicker
## on a trail than off it (see speed_modifier_at()). A generated course arrives
## with its trails already laid (see CoursePathGenerator).

## Orthogonal sides, also used by the component search below.
const SIDES := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Per connector: [direction offset, shared-edge midpoint in tile units,
## perpendicular grid direction for the ribbon half-width].
const CONNECTORS := [
	[Vector2i(1, 0), Vector2(1.0, 0.5), Vector2(0.0, 1.0)],
	[Vector2i(-1, 0), Vector2(0.0, 0.5), Vector2(0.0, 1.0)],
	[Vector2i(0, 1), Vector2(0.5, 1.0), Vector2(1.0, 0.0)],
	[Vector2i(0, -1), Vector2(0.5, 0.0), Vector2(1.0, 0.0)],
]
## The middle of a tile in tile units.
const CENTRE := Vector2(0.5, 0.5)

## Dirt trail (the default walking path): trodden grass and packed earth at the
## verges, the trail itself, a paler centre the boots polish in, and a scuffed
## rim where the edges crumble.
const DIRT_COLOR := Color(0.62, 0.48, 0.32, 0.96)
const DIRT_LIGHT := Color(0.78, 0.66, 0.47, 0.34)
const DIRT_VERGE := Color(0.53, 0.47, 0.33, 0.32)
## Paved promenade (a trail whose network reaches the clubhouse): light
## flagstones, a kerb of dressed darker stone either side, jointed across the
## walk and bedded in gravel spilled onto the grass.
const PAVED_COLOR := Color(0.80, 0.77, 0.71, 1.0)
const PAVED_LIGHT := Color(0.96, 0.94, 0.89, 0.20)
const PAVED_DARK := Color(0.47, 0.45, 0.41, 0.95)
const PAVED_JOINT := Color(0.55, 0.52, 0.47, 0.7)
const PAVED_VERGE := Color(0.72, 0.68, 0.58, 0.22)
## Grass blades overhanging the verges, whichever surface the walk is made of.
const GRASS_BLADES := Color(0.42, 0.58, 0.32, 0.8)

## Sizes of the walk, in tile units along the tile's isometric axes (one unit
## is a tile edge; on a 64x32 tile that is about 36 px on screen). Widths and
## radii are half-widths, so a band drawn with one is twice that wide. A dirt
## trail is a slim trodden strip; a paved promenade is wider, kerbed and bedded
## in gravel. The dot figures are the trodden pads where a tile's arms meet.
const DIRT_HALF_W := 0.155
const DIRT_CENTRE_W := 0.07
const DIRT_VERGE_W := 0.23
const DIRT_DOT := 0.20
const DIRT_VERGE_DOT := 0.26
const DIRT_LONE_DOT := 0.28      # A dot on its own, with nothing to join.
const DIRT_END_REACH := 0.24     # How far past the centre a trail end runs on.
const PAVED_HALF_W := 0.23
const PAVED_OUTER_W := 0.28
const PAVED_VERGE_W := 0.31
const PAVED_DOT := 0.21
const PAVED_KERB_DOT := 0.17
const PAVED_VERGE_DOT := 0.33
const PAVED_LONE_DOT := 0.30
const PAVED_END_REACH := 0.30

## Walk rates. A laid trail is quicker than the ground it crosses, and a trail
## whose network reaches the clubhouse is a paved promenade and quicker still:
## the pace payoff for connecting the walk to the clubhouse.
const DIRT_SPEED_MODIFIER := 1.25
const PAVED_SPEED_MODIFIER := 1.5

var terrain_grid: TerrainGrid
## Tiles with the walking-path flag, and the subset rendered as paved stone.
var _path_tiles: Dictionary = {}
var _upgraded_tiles: Dictionary = {}
var _is_web: bool = false

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = 1  # Above the terrain surface, below entities (z 2).
	_is_web = OS.get_name() == "Web"
	if grid:
		grid.walking_paths_changed.connect(rebuild)
		grid.elevation_changed.connect(_on_elevation_changed)
	EventBus.load_completed.connect(_on_load_completed)
	rebuild()

func _exit_tree() -> void:
	if terrain_grid:
		if terrain_grid.walking_paths_changed.is_connected(rebuild):
			terrain_grid.walking_paths_changed.disconnect(rebuild)
		if terrain_grid.elevation_changed.is_connected(_on_elevation_changed):
			terrain_grid.elevation_changed.disconnect(_on_elevation_changed)
	if GameManager and GameManager.entity_layer:
		var el: Node = GameManager.entity_layer
		if el.has_signal("building_removed") and el.building_removed.is_connected(_on_entity_building_changed):
			el.building_removed.disconnect(_on_entity_building_changed)
		if el.has_signal("building_placed") and el.building_placed.is_connected(_on_entity_building_placed):
			el.building_placed.disconnect(_on_entity_building_placed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func _on_load_completed(_success: bool) -> void:
	rebuild()

## Trails follow the ground, so sculpted elevation must reproject them.
func _on_elevation_changed(_pos: Vector2i, _old: int, _new: int) -> void:
	queue_redraw()

## The entity layer is created after the grid, so hook its building signals
## lazily: a placed or removed clubhouse changes which trails are paved.
func _ensure_entity_connections() -> void:
	if not GameManager or not GameManager.entity_layer:
		return
	var el: Node = GameManager.entity_layer
	if el.has_signal("building_removed") and not el.building_removed.is_connected(_on_entity_building_changed):
		el.building_removed.connect(_on_entity_building_changed)
	if el.has_signal("building_placed") and not el.building_placed.is_connected(_on_entity_building_placed):
		el.building_placed.connect(_on_entity_building_placed)
	# Moving the clubhouse moves the paving: the trail that reached its old
	# tiles reverts to dirt, and the trail at its new doorstep is paved.
	if el.has_signal("building_moved") and not el.building_moved.is_connected(_on_entity_building_moved):
		el.building_moved.connect(_on_entity_building_moved)

func _on_entity_building_changed(_grid_pos: Vector2i) -> void:
	rebuild()

func _on_entity_building_placed(_building, _cost: int) -> void:
	rebuild()

func _on_entity_building_moved(_building, _from_pos: Vector2i, _to_pos: Vector2i) -> void:
	rebuild()

## Rescan the walking-path layer and the network it forms. Cheap: the walk
## only visits path tiles, and the course carries few of them.
func rebuild() -> void:
	_ensure_entity_connections()
	_path_tiles.clear()
	_upgraded_tiles.clear()
	if not terrain_grid:
		queue_redraw()
		return
	for pos in terrain_grid.get_walking_paths():
		_path_tiles[pos] = true
	if not _path_tiles.is_empty():
		_upgraded_tiles = upgraded_component_tiles(_path_tiles, _clubhouse_edge_tiles())
	queue_redraw()

## True when a tile is a node of the walking network: it carries the trail the
## Path improvement lays.
func _is_walkable(pos: Vector2i) -> bool:
	return _path_tiles.has(pos)

## Speed modifier for a golfer standing on `pos`: a laid trail is walked more
## quickly than the ground around it, and a paved promenade (a trail whose
## network reaches the clubhouse) faster still. Returns 1.0 off the trail, and
## never lowers the terrain's own modifier, so a trail through long grass is
## the quickest way through it — see Golfer._process_walking().
func speed_modifier_at(pos: Vector2i) -> float:
	if not _path_tiles.has(pos):
		return 1.0
	return PAVED_SPEED_MODIFIER if _upgraded_tiles.has(pos) else DIRT_SPEED_MODIFIER

## Every tile orthogonally adjacent to a clubhouse footprint — a trail node
## here means the network reaches the clubhouse.
func _clubhouse_edge_tiles() -> Dictionary:
	var edges: Dictionary = {}
	if not GameManager or not GameManager.entity_layer or not terrain_grid:
		return edges
	for building in GameManager.entity_layer.buildings.values():
		if building.building_type != "clubhouse":
			continue
		var origin: Vector2i = building.grid_position
		for x in range(building.width):
			for y in range(building.height):
				var footprint: Vector2i = origin + Vector2i(x, y)
				for side in SIDES:
					var neighbor: Vector2i = footprint + side
					if terrain_grid.is_valid_position(neighbor):
						edges[neighbor] = true
	return edges

## Flood-fill the walking network (4-way) and return the path tiles that
## belong to components touching any tile in `clubhouse_edges`. Kept static
## so the connection rule is unit-testable without a scene.
static func upgraded_component_tiles(path_tiles: Dictionary,
		clubhouse_edges: Dictionary) -> Dictionary:
	var upgraded: Dictionary = {}
	var visited: Dictionary = {}
	for start in path_tiles.keys():
		if visited.has(start):
			continue
		var component: Array = []
		var frontier: Array = [start]
		visited[start] = true
		while frontier.size() > 0:
			var node: Vector2i = frontier.pop_back()
			component.append(node)
			for side in SIDES:
				var neighbor: Vector2i = node + side
				if not path_tiles.has(neighbor) or visited.has(neighbor):
					continue
				visited[neighbor] = true
				frontier.append(neighbor)
		for node in component:
			if clubhouse_edges.has(node):
				for member in component:
					upgraded[member] = true
				break
	return upgraded

func _draw() -> void:
	if not terrain_grid or _path_tiles.is_empty():
		return
	# Viewport culling: skip tiles whose center is off-screen (with margin).
	var visible_rect = terrain_grid.get_visible_world_rect()
	visible_rect = visible_rect.grow_individual(
			terrain_grid.tile_width, terrain_grid.tile_height,
			terrain_grid.tile_width, terrain_grid.tile_height)
	for pos in _path_tiles.keys():
		var center := to_local(terrain_grid.grid_to_screen_center(pos))
		if not visible_rect.has_point(center):
			continue
		for cmd in tile_draw_commands(pos, _upgraded_tiles.has(pos), not _is_web):
			match cmd.kind:
				"polygon":
					draw_colored_polygon(cmd.points, cmd.color)
				"line":
					draw_line(cmd.a, cmd.b, cmd.color, cmd.width)
				"polyline":
					draw_polyline(cmd.points, cmd.color, cmd.width)
				"circle":
					draw_circle(cmd.center, cmd.radius, cmd.color)

# =============================================================================
# Geometry — computed outside the draw cycle so it can be unit-tested.
# =============================================================================

## One draw command: kind plus its typed payload (see _draw()).
class DrawCommand:
	var kind := "polygon"
	var points: PackedVector2Array
	var a: Vector2
	var b: Vector2
	var center: Vector2
	var radius: float
	var color: Color
	var width: float

static func _cmd(kind: String) -> DrawCommand:
	var c := DrawCommand.new()
	c.kind = kind
	return c

## All draw commands for one trail tile, in local coordinates. `detail`
## trims the decorative passes (speckles, blades, joints) on the web build.
## Verges are computed first, so the translucent trodden margin always sits
## under the trail itself rather than over it.
func tile_draw_commands(pos: Vector2i, upgraded: bool, detail: bool) -> Array:
	if upgraded:
		return _paved_commands(pos, detail)
	return _dirt_commands(pos, detail)

## Every walkable neighbour of this tile, as its CONNECTORS entry.
func _connections(pos: Vector2i) -> Array:
	var connected: Array = []
	for conn in CONNECTORS:
		if _is_walkable(pos + conn[0]):
			connected.append(conn)
	return connected

## A trodden dirt trail: the trodden verge, the packed earth itself, the paler
## centre the boots polish in, and a scatter of dry earth, pebbles and grass.
func _dirt_commands(pos: Vector2i, detail: bool) -> Array:
	var connected := _connections(pos)
	var verge: Array = []
	var body: Array = []
	var extra: Array = []
	if connected.is_empty():
		# A dot on its own: a trodden patch in the grass, with no ribbon at all.
		verge.append(_circle_at(pos, CENTRE, DIRT_VERGE_DOT, DIRT_VERGE))
		body.append(_circle_at(pos, CENTRE, DIRT_LONE_DOT, DIRT_COLOR))
		if detail:
			extra.append(_circle_at(pos, CENTRE, DIRT_LONE_DOT * 0.45, DIRT_LIGHT))
			extra.append_array(_trail_grain(pos, CENTRE, Vector2.RIGHT, Vector2i.ZERO))
		return verge + body + extra
	for conn in connected:
		var edge: Vector2 = conn[1]
		var axis: Vector2 = conn[2]
		verge.append(_tile_polygon(pos, _band(CENTRE, edge, axis, DIRT_VERGE_W), DIRT_VERGE))
		body.append(_tile_polygon(pos, _band(CENTRE, edge, axis, DIRT_HALF_W), DIRT_COLOR))
		if detail:
			extra.append(_tile_polygon(pos, _band(CENTRE, edge, axis, DIRT_CENTRE_W), DIRT_LIGHT))
			extra.append_array(_trail_grain(pos, CENTRE.lerp(edge, 0.55), axis, conn[0]))
	if connected.size() == 1:
		# A trail end: the walk comes to a point past the centre on the side
		# away from its one neighbour, so it dies away into the grass instead
		# of being cut off at the tile line.
		var back := -Vector2(connected[0][0])
		var axis: Vector2 = connected[0][2]
		var tip := CENTRE + back * DIRT_END_REACH
		verge.append(_tile_polygon(pos, _taper(CENTRE + back * (DIRT_END_REACH + 0.06),
				CENTRE, axis, DIRT_VERGE_W), DIRT_VERGE))
		body.append(_tile_polygon(pos, _taper(tip, CENTRE, axis, DIRT_HALF_W), DIRT_COLOR))
		return verge + body + extra
	# Where the arms meet: a trodden pad, cut across the corners, wide enough
	# to fill a bend and narrow enough never to bulge past the trail itself.
	body.append(_tile_polygon(pos, _pad_shape(DIRT_DOT, DIRT_HALF_W, _walk_dir(connected)), DIRT_COLOR))
	if detail:
		extra.append(_tile_polygon(pos, _pad_shape(DIRT_DOT * 0.5, DIRT_CENTRE_W, _walk_dir(connected)), DIRT_LIGHT))
	return verge + body + extra

## The paved promenade: gravel bedded at the verges, a kerb of dressed stone,
## flagstones jointed across the walk, and grass creeping over the edges.
func _paved_commands(pos: Vector2i, detail: bool) -> Array:
	var connected := _connections(pos)
	var verge: Array = []
	var body: Array = []
	var extra: Array = []
	if connected.is_empty():
		verge.append(_circle_at(pos, CENTRE, PAVED_VERGE_DOT, PAVED_VERGE))
		body.append(_circle_at(pos, CENTRE, PAVED_LONE_DOT, PAVED_DARK))
		body.append(_circle_at(pos, CENTRE, PAVED_LONE_DOT - (PAVED_OUTER_W - PAVED_HALF_W), PAVED_COLOR))
		return verge + body + extra
	for conn in connected:
		var edge: Vector2 = conn[1]
		var axis: Vector2 = conn[2]
		verge.append(_tile_polygon(pos, _band(CENTRE, edge, axis, PAVED_VERGE_W), PAVED_VERGE))
		body.append(_tile_polygon(pos, _band(CENTRE, edge, axis, PAVED_OUTER_W), PAVED_DARK))
		body.append(_tile_polygon(pos, _band(CENTRE, edge, axis, PAVED_HALF_W), PAVED_COLOR))
		if detail:
			# Slabs, not bricks: the joints cross the walk at their own rhythm
			# each tile, so no two stretches of paving look stamped out alike.
			var rng := _deterministic_rng(pos + conn[0])
			for t in [rng.randf_range(0.24, 0.42), rng.randf_range(0.6, 0.82)]:
				var at := CENTRE.lerp(edge, t)
				extra.append(_tile_line(pos, at + axis * PAVED_HALF_W,
						at - axis * PAVED_HALF_W, PAVED_JOINT, 1.0))
			# Some slabs catch the light and some do not, so the paving does
			# not repeat one bright patch at every tile centre.
			if rng.randf() < 0.6:
				extra.append(_tile_polygon(pos,
						_band(CENTRE, edge, axis, PAVED_HALF_W * rng.randf_range(0.25, 0.45)), PAVED_LIGHT))
			extra.append_array(_trail_grain(pos, CENTRE.lerp(edge, 0.55), axis, conn[0]))
	if connected.size() == 1:
		# A paved end: kerb and flagstones both come to their point away from
		# the one neighbour, so the paving stops rather than running off the tile.
		var back := -Vector2(connected[0][0])
		var axis: Vector2 = connected[0][2]
		var tip := CENTRE + back * PAVED_END_REACH
		verge.append(_tile_polygon(pos, _taper(CENTRE + back * (PAVED_END_REACH + 0.06),
				CENTRE, axis, PAVED_VERGE_W), PAVED_VERGE))
		body.append(_tile_polygon(pos, _taper(tip, CENTRE, axis, PAVED_OUTER_W), PAVED_DARK))
		body.append(_tile_polygon(pos, _taper(tip + Vector2(connected[0][0]) * 0.06,
				CENTRE, axis, PAVED_HALF_W), PAVED_COLOR))
		return verge + body + extra
	# The paved apron where the arms meet: a kerb ring around flagstones, both
	# cut across the corners so the paving stays as wide as the walk it joins.
	var along := _walk_dir(connected)
	body.append(_tile_polygon(pos, _pad_shape(PAVED_KERB_DOT, PAVED_OUTER_W, along), PAVED_DARK))
	body.append(_tile_polygon(pos, _pad_shape(PAVED_DOT, PAVED_HALF_W, along), PAVED_COLOR))
	if detail:
		extra.append(_tile_polygon(pos, _pad_shape(PAVED_DOT * 0.5, PAVED_HALF_W * 0.38, along), PAVED_LIGHT))
	return verge + body + extra

## Dry patches, pebbles and grass blades along the tile's trail. `from` is a
## point on the walk, `axis` the direction across it and `dir` the arm laid
## through the tile (all in tile units), so every tile is weathered its own way.
func _trail_grain(pos: Vector2i, from: Vector2, axis: Vector2, dir: Vector2i) -> Array:
	var cmds: Array = []
	var rng := _deterministic_rng(pos + dir)
	for i in range(2):
		var t := rng.randf_range(-0.35, 0.35)
		var side := rng.randf_range(-0.8, 0.8)
		var at := _pt(pos, from + axis * side * DIRT_HALF_W + Vector2(dir) * t * 0.5)
		cmds.append(_circle(at, rng.randf_range(0.5, 1.2), DIRT_LIGHT))
	for i in range(2):
		var side := 1.0 if i == 0 else -1.0
		var t := rng.randf_range(0.18, 0.75)
		var at := _pt(pos, from + axis * side * (DIRT_VERGE_W + 0.04) + Vector2(dir) * t * 0.5)
		var lean := rng.randf_range(-1.5, 1.5)
		# Blades lean away from the tile centre and lean with the walk.
		cmds.append(_line(at, at + Vector2(lean, -rng.randf_range(1.6, 2.8)), GRASS_BLADES, 1.0))
	return cmds

# =============================================================================
# Projection and outline helpers (outlines are authored in tile units, so a
# walk is the same width along either grid axis, then projected).
# =============================================================================

## Projected point of grid-space point `pos + t` (t in tile units), local.
func _pt(pos: Vector2i, t: Vector2) -> Vector2:
	return to_local(terrain_grid.grid_point_to_screen(Vector2(pos) + t))

## One tile unit (the tile edge) in local pixels: how wide any of the walks
## above end up, so the same numbers hold at any zoom or tile size.
func _unit(pos: Vector2i, t: Vector2) -> float:
	return (_pt(pos, t + Vector2.RIGHT) - _pt(pos, t)).length()

## One draw command for an outline given in tile units of this tile.
func _tile_polygon(pos: Vector2i, outline: Array[Vector2], color: Color) -> DrawCommand:
	var points := PackedVector2Array()
	for t in outline:
		points.append(_pt(pos, t))
	var c := _cmd("polygon")
	c.points = points
	c.color = color
	return c

## One draw command for a line between two points in tile units of this tile.
func _tile_line(pos: Vector2i, a: Vector2, b: Vector2, color: Color, width: float) -> DrawCommand:
	return _line(_pt(pos, a), _pt(pos, b), color, width)

## One draw command for a filled circle of `radius` tile units around `t`.
func _circle_at(pos: Vector2i, t: Vector2, radius: float, color: Color) -> DrawCommand:
	return _circle(_pt(pos, t), radius * _unit(pos, t), color)

## One draw command for a line between two local points.
func _line(a: Vector2, b: Vector2, color: Color, width: float) -> DrawCommand:
	var c := _cmd("line")
	c.a = a
	c.b = b
	c.color = color
	c.width = width
	return c

## One draw command for a filled circle in local space (pebbles, dust).
func _circle(center: Vector2, radius: float, color: Color) -> DrawCommand:
	var c := _cmd("circle")
	c.center = center
	c.radius = radius
	c.color = color
	return c

## A band of the walk from `from` to `to`, `half_width` across it. `axis` is the
## direction across the walk (a grid axis), so adjoining tiles' bands meet on
## the shared edge without a seam.
static func _band(from: Vector2, to: Vector2, axis: Vector2, half_width: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	pts.append(from + axis * half_width)
	pts.append(to + axis * half_width)
	pts.append(to - axis * half_width)
	pts.append(from - axis * half_width)
	return pts

## The pad where a tile's arms meet: an octagon `reach` along the walk and
## `half_width` across it, its corners cut so a bend reads as a worn patch
## without ever bulging wider than the walk itself.
static func _pad_shape(reach: float, half_width: float, walk: Vector2) -> Array[Vector2]:
	var along := walk if walk.length_squared() > 0.0 else Vector2.RIGHT
	var across := Vector2(-along.y, along.x)
	var strut := 0.45  # Where the cut corners sit, as a fraction of the reach.
	var pts: Array[Vector2] = []
	pts.append(CENTRE + along * reach + across * half_width * strut)
	pts.append(CENTRE + along * reach * strut + across * half_width)
	pts.append(CENTRE - along * reach * strut + across * half_width)
	pts.append(CENTRE - along * reach + across * half_width * strut)
	pts.append(CENTRE - along * reach - across * half_width * strut)
	pts.append(CENTRE - along * reach * strut - across * half_width)
	pts.append(CENTRE + along * reach * strut - across * half_width)
	pts.append(CENTRE + along * reach - across * half_width * strut)
	return pts

## The pointed end of a trail: `tip` narrows to nothing, `to` is full width.
static func _taper(tip: Vector2, to: Vector2, axis: Vector2, half_width: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	pts.append(tip)
	pts.append(to + axis * half_width)
	pts.append(to - axis * half_width)
	return pts

## The direction the walk runs through a tile: the sum of its arms, so a corner
## runs along the bisector of its two arms. A crossroads, with as many arms each
## way, has no single direction and keeps the plain tile centre.
func _walk_dir(connected: Array) -> Vector2:
	var sum := Vector2.ZERO
	for conn in connected:
		sum += Vector2(conn[0])
	if sum.length_squared() < 0.01:
		return Vector2.ZERO
	return sum.normalized()

func _deterministic_rng(pos: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = pos.x * 12289 ^ pos.y * 24593
	return rng
