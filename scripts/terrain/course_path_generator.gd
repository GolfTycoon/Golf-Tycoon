extends RefCounted
class_name CoursePathGenerator
## CoursePathGenerator - lays the paths a generated course arrives with.
##
## Course generation paints tees, corridors, greens and hazards and then opens
## the holes, but it never laid a walk between any of them: a generated course
## opened with no way from the clubhouse to the first tee, nothing alongside a
## fairway, and no link from a green to the next tee. This class lays that
## network in one pass once the holes exist:
##
##     clubhouse door → tee 1 ⋯ green 1 → tee 2 ⋯ green 2 → … → green N → clubhouse
##
## What it lays is the Path improvement — the trail the player buys a tile at a
## time (see TerrainGrid.set_walking_path), trodden dirt over the ground it
## crosses, and paved stone once its network reaches the clubhouse. It is not a
## terrain of its own, so it never replaces the ground underneath and never
## appears on the maintenance books.
##
## Every leg is an A* walk over the ground that is already painted. The leg that
## follows a hole is guided along the mown edge of that hole's corridor, so the
## path hugs the fairway instead of cutting across the playing line, and every
## leg steers around water, sand, buildings, decorations and land the player
## does not own. A trail only sits on ground the Path improvement accepts (see
## TerrainTypes.WALKING_PATH_TERRAINS), so the playing line of every hole stays
## clear of it by rule rather than by preference: where a green is ringed by its
## own fairway and bunkers, the walk stops short at the nearest ground that can
## host it. Legs are laid in playing order over ground that gets cheaper once it
## carries a trail, so the legs join into one connected network.
##
## The network reaching the clubhouse matters twice over: a paved trail is walked
## at 1.5x (see WalkingPathOverlay.PAVED_SPEED_MODIFIER), and it paves any trail
## the player lays later that joins it.

## A tile that does not exist: no hub, no clubhouse door, no route.
const NO_TILE := Vector2i(-1, -1)

## What one tile of ground costs a leg. Only ground the Path improvement can be
## laid on is listed at all: everything else — the mown playing line, a green, a
## tee, sand, water, out of bounds, natural grass and heavy rough — is
## BLOCKED_COST (see _step_cost), so the walk of every hole stays clear of it by
## rule rather than by preference.
##
##  * open rough is the cheap default a leg settles on;
##  * scrub, stone, flowers and a stream cost the ground they cross;
##  * woodland costs the clearing;
##  * a trail an earlier leg laid is nearly free, so legs merge into one network
##    instead of running beside it.
const TERRAIN_COSTS: Dictionary = {
	TerrainTypes.Type.ROUGH: 1.0,
	TerrainTypes.Type.DEEP_ROUGH: 1.0,
	TerrainTypes.Type.WASTE_BUNKER: 2.0,
	TerrainTypes.Type.BRUSH: 2.0,
	TerrainTypes.Type.FLOWER_BED: 2.0,
	TerrainTypes.Type.ROCKS: 2.0,
	TerrainTypes.Type.SMALL_BOULDERS: 2.0,
	TerrainTypes.Type.LARGE_BOULDERS: 2.0,
	TerrainTypes.Type.STREAM: 2.0,
}

## What a tile an earlier leg already laid a trail on costs: nearly nothing, so
## the legs of a course join into one network. It is also the cheapest step a leg
## can ever take, and so the floor of the search's estimate of the walk
## remaining; under-estimating keeps the search honest, over-estimating would
## trade the shape of the path for speed.
const LAID_TRAIL_COST := 0.25

## Cost of any woodland tile: the generic Trees ground and every species.
const WOODLAND_COST := 3.0

## Ground a leg cannot cross at all.
const BLOCKED_COST := INF

## How far a path keeps out from the mown edge of the corridor it follows, in
## tiles. Just outside the fairway, where a path belongs.
const PATH_CLEARANCE := 1.25

## What reaching one ring further out costs a leg, and what standing on the
## playing side of the tee or green costs it.
##
## Both are charged once, on the tile the walk comes in on, and both are dear
## against a tile of ordinary walking: a leg that could come in two rings closer
## for a detour of three tiles takes the detour. Priced in the same units as the
## walk itself, a leg settles for the first ground it can reach and leaves the
## tee or the green a long way off.
const RING_COST := 4.0
const WRONG_SIDE_COST := 6.0

## How far out the ground a walk may come in on is looked for, in rings around
## the tee or the putting surface. A tee or a green ringed by its own fairway and
## bunkers is met a few tiles out, where ground the Path improvement accepts
## begins; past this the hole keeps no walk at all, so a leg always stops short
## of the play rather than crossing it. Reaching out costs a ring a tile (see
## RING_COST), so the walk comes as close to the play as the ground lets it.
const HUB_RINGS := 8

## How far from the clubhouse door the network may arrive when no tile beside the
## footprint can host a trail.
const CLUBHOUSE_REACH := 6

## How far either side of the tee-green line the mown edge is looked for. Wider
## than the widest generated corridor plus its bend, so a leg never loses the
## fairway it is following.
const CORRIDOR_SCAN := 7

## The edge used when a sample finds no mown ground at all (a corridor a hazard
## has taken, say): far enough out that the path still clears the playing line.
const FALLBACK_EDGE := 2.0

## Most points one guide polyline carries. A leg is guided, not traced, so a
## sample about a tile apart is plenty.
const GUIDE_MAX_POINTS := 48

## Pull toward the guide, per tile of deviation from it. Above the cost of open
## ground, so a leg follows the fairway edge; below the cost of cutting a
## corridor in half, so a leg still steps round a hazard.
const HOLE_GUIDE_WEIGHT := 1.6

## How far off the guide a leg is charged for being, at most. The guide keeps a
## walk beside the corridor it follows; past a few tiles of it the ground has
## taken the walk somewhere else — round a pond, behind a green, or up the far
## side of the hole before it — and being further off there is no worse than
## being a little off, so it should not cost more either. Without the cap, coming
## round the end of a corridor to the back of a green is charged as though the
## walk had wandered off, and the cheapest arrival ends up short of the play.
const GUIDE_MAX_DISTANCE := 4.0

## A walk between two holes longer than this, in tiles, is left unlaid: a leg
## that long would snake across the property rather than read as a path, and the
## hole it was reaching for keeps its own walk instead.
const MAX_LINK_TILES := 80

## The search box is the leg's two ends grown by this many tiles, and one leg
## may settle at most this many tiles. Both keep an 18-hole course's paths
## inside the generation loading screen: the box holds fewer tiles than the
## budget, so a leg that can be walked at all is walked to the end.
const ROUTE_SLACK := 8
const NODE_BUDGET := 9000

## The four steps a leg may take. A trail is a ribbon, and ribbons in this game
## join edge to edge: the walking network floods 4-connected (see
## WalkingPathOverlay.upgraded_component_tiles) and the course draws a walk as
## one continuous band only where tiles share an edge. A diagonal step would
## leave two tiles touching at a corner, which reads as a row of separate dots
## and splits the network in two.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


# =============================================================================
# GENERATING
# =============================================================================

## Lay the path network for a course whose holes have just been generated.
## `holes` are the holes in playing order (they are sorted here, so a caller may
## pass the course's own array), and `clubhouse_hint` is where the clubhouse
## stands or is about to stand — it is only consulted when the course has no
## clubhouse yet. Returns how many tiles this call laid, which is nothing at all
## when the network is already on the ground.
static func generate(grid: TerrainGrid, holes: Array, entity_layer: EntityLayer = null,
		clubhouse_hint: Vector2i = NO_TILE) -> int:
	if grid == null or holes.is_empty():
		return 0
	var ordered := _playing_order(holes)
	if ordered.is_empty():
		return 0

	var count := ordered.size()
	var door := _clubhouse_door(grid, entity_layer, clubhouse_hint)
	var laid: Dictionary = {}
	# Where the network has got to. Every leg starts here, and every leg that is
	# laid moves it on, so the legs join into one network instead of lying beside
	# each other.
	var end := door

	for index in count:
		var hole = ordered[index]
		var tees := _tee_ground(grid, entity_layer, hole)
		var greens := _green_ground(grid, entity_layer, hole)

		# The walk in: from the clubhouse for the first hole, and from the green
		# before it for the rest.
		var arrived := _lay_leg(grid, entity_layer, end, tees, laid, true)
		if not tees.has(arrived):
			# The network could not reach this tee — the ground near it is sealed
			# off by the mown playing line, or the walk in was too long to be
			# worth laying. The hole still gets its own walk, starting where a
			# golfer steps off the tee.
			arrived = _preferred(grid, tees)
		end = arrived
		if end == NO_TILE:
			continue

		var walked := _lay_leg(grid, entity_layer, end, greens, laid, false,
				_hole_guide(grid, hole), HOLE_GUIDE_WEIGHT)
		end = walked if greens.has(walked) else _preferred(grid, greens)

	# Home again: the last green back to the clubhouse closes the loop. Where the
	# ground lets it be walked it is also the leg that joins the round to the
	# clubhouse, and so the one that paves the network.
	if door != NO_TILE and count > 1:
		_lay_leg(grid, entity_layer, end, {door: 0.0}, laid, true)

	return laid.size()


## Lay one leg, from wherever the network has got to onto the best of `goals` —
## the ground a walk may come in on, each with what standing there costs beyond
## the ground itself. Returns the tile the network has now got to: the end of the
## walk when one was laid, and `start` unchanged when it was not.
##
## A leg that has to walk further than MAX_LINK_TILES is not worth laying: it
## would snake across the property rather than read as a path, so the ground is
## left alone and the holes stay separate.
static func _lay_leg(grid: TerrainGrid, entity_layer: EntityLayer, start: Vector2i,
		goals: Dictionary, laid: Dictionary, capped: bool,
		guide: PackedVector2Array = PackedVector2Array(), guide_weight: float = 0.0) -> Vector2i:
	if start == NO_TILE or goals.is_empty():
		return start
	var route := _plan_route(grid, entity_layer, start, goals, guide, guide_weight)
	if route.is_empty():
		return start
	if capped and route.size() > MAX_LINK_TILES:
		return start
	_lay(grid, entity_layer, route, laid)
	return route[route.size() - 1]


## The ground a walk should come in on if it cannot be walked to: the cheapest of
## the candidates, nearest the play and off the playing side of it.
static func _preferred(grid: TerrainGrid, goals: Dictionary) -> Vector2i:
	var best := NO_TILE
	var best_score := BLOCKED_COST
	for tile in goals:
		var score: float = goals[tile] + _step_cost(grid, tile)
		if score < best_score:
			best_score = score
			best = tile
	return best


## The holes to lay paths for, in playing order and with both ends on the grid.
static func _playing_order(holes: Array) -> Array:
	var ordered: Array = []
	for hole in holes:
		if hole == null:
			continue
		if not hole.is_open:
			continue
		ordered.append(hole)
	ordered.sort_custom(func(a, b): return int(a.hole_number) < int(b.hole_number))
	return ordered


# =============================================================================
# THE ENDS OF A LEG
# =============================================================================

## The ground a path may meet a tee on, and what standing on each tile costs
## beyond the ground itself. Behind the tee rather than in front of it, so the
## walk never stands in the line of play. The back tee is the one met — the
## forward and middle tees of a multi-tee course sit along the corridor the path
## follows anyway, and meeting one of them would leave the walk short of the tee
## the hole is measured from.
static func _tee_ground(grid: TerrainGrid, entity_layer: EntityLayer, hole) -> Dictionary:
	var tees: Array[Vector2i] = [hole.tee_position]
	return _hub_ground(grid, entity_layer, tees, hole.green_position)

## The ground a path may meet a green on: past the cup rather than short of it,
## so a golfer walks up behind the green and never across the putting surface.
static func _green_ground(grid: TerrainGrid, entity_layer: EntityLayer, hole) -> Dictionary:
	return _hub_ground(grid, entity_layer, _green_tiles(grid, hole), hole.tee_position)

## The cup's tile and the rest of the putting surface around it.
static func _green_tiles(grid: TerrainGrid, hole) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [hole.hole_position]
	for offset in _neighbour_offsets(1):
		var tile: Vector2i = hole.hole_position + offset
		if grid.get_tile(tile) == TerrainTypes.Type.GREEN and not tiles.has(tile):
			tiles.append(tile)
	return tiles

## Every tile a walk may come in on around `targets`, on the side away from
## `away_from`, mapped to what standing there costs beyond the ground: a ring
## further out costs a tile of walk, and standing on the far side of the tee from
## the green — behind the play, where nobody is aiming — costs more again. A leg
## is planned onto the whole set at once, so it comes in on whichever tile it can
## actually reach, as near the play as that lets it.
##
## Empty when there is no ground within HUB_RINGS that the Path improvement can
## be laid on, which is what a green sealed in by its own fairway and bunkers
## comes to: that hole keeps no walk rather than one that crosses the turf.
static func _hub_ground(grid: TerrainGrid, entity_layer: EntityLayer, targets: Array[Vector2i],
		away_from: Vector2i) -> Dictionary:
	var goals: Dictionary = {}
	for ring in range(1, HUB_RINGS + 1):
		for target in targets:
			for offset in _neighbour_offsets(ring):
				var tile := target + offset
				if not _is_layable(grid, entity_layer, tile):
					continue
				var bonus := float(ring - 1) * RING_COST
				if Vector2(tile - target).dot(Vector2(away_from - target)) > 0.0:
					bonus += WRONG_SIDE_COST
				# A tile rings two green tiles at once from inside a putting
				# surface's corner: the closer of the two readings is the one that
				# counts.
				goals[tile] = minf(bonus, float(goals.get(tile, bonus)))
	return goals

## Offsets at exactly `ring` tiles from a tile, nearest side first.
static func _neighbour_offsets(ring: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if ring <= 0:
		offsets.append(Vector2i.ZERO)
		return offsets
	for x in range(-ring, ring + 1):
		offsets.append(Vector2i(x, -ring))
		offsets.append(Vector2i(x, ring))
	for y in range(-ring + 1, ring):
		offsets.append(Vector2i(-ring, y))
		offsets.append(Vector2i(ring, y))
	return offsets

## The tile the path network reaches the clubhouse on. A built clubhouse is
## answered by a tile beside its own footprint; a course whose clubhouse has not
## been placed yet is answered by the tile its door will be on, so the network is
## laid to meet it.
##
## Beside the footprint matters: a trail is paved once its network touches a tile
## orthogonally adjacent to the clubhouse (see
## WalkingPathOverlay.upgraded_component_tiles), so arriving on one of those
## tiles is what turns the whole generated network from dirt to stone.
static func _clubhouse_door(grid: TerrainGrid, entity_layer: EntityLayer,
		hint: Vector2i) -> Vector2i:
	var clubhouse = CourseClubhouse.find(entity_layer)
	if clubhouse != null:
		var door := CourseClubhouse.front_tile(clubhouse, grid, entity_layer)
		var arrival := _clubhouse_arrival(grid, entity_layer, clubhouse, door)
		if arrival != NO_TILE:
			return arrival
		if _is_layable(grid, entity_layer, door):
			return door
		return _nearest_layable(grid, entity_layer, door, CLUBHOUSE_REACH)
	if hint == NO_TILE or not grid.is_valid_position(hint):
		return NO_TILE
	# No clubhouse yet: aim at the middle of the south edge of the footprint the
	# hint anchors, which is where its door is looked for first.
	var data := CourseClubhouse.building_data()
	var size: Array = data.get("size", [4, 4])
	var width: int = maxi(1, int(size[0]))
	var height: int = maxi(1, int(size[1]))
	var expected := hint + Vector2i(floori(width * 0.5), height)
	if _is_layable(grid, entity_layer, expected):
		return expected
	return _nearest_layable(grid, entity_layer, hint, CLUBHOUSE_REACH)

## The nearest tile beside the clubhouse footprint that can host a trail, so the
## network arrives where its paving is decided. NO_TILE when the clubhouse stands
## in ground none of its edges can take a trail on.
static func _clubhouse_arrival(grid: TerrainGrid, entity_layer: EntityLayer,
		clubhouse, door: Vector2i) -> Vector2i:
	var best := NO_TILE
	var best_distance := INF
	for footprint in clubhouse.get_footprint():
		for side in DIRECTIONS:
			var tile: Vector2i = footprint + side
			if not _is_layable(grid, entity_layer, tile):
				continue
			var distance: float = Vector2(tile - door).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = tile
	return best

## The nearest tile a path may be laid on, searching outward from `centre`.
static func _nearest_layable(grid: TerrainGrid, entity_layer: EntityLayer, centre: Vector2i,
		radius: int) -> Vector2i:
	if _is_layable(grid, entity_layer, centre):
		return centre
	for ring in range(1, radius + 1):
		for offset in _neighbour_offsets(ring):
			var tile := centre + offset
			if _is_layable(grid, entity_layer, tile):
				return tile
	return NO_TILE


# =============================================================================
# GUIDES
# =============================================================================

## The polyline a hole's walk is guided along: both mown edges of its corridor,
## so the walk hugs whichever side of the playing line the ground has left it on.
##
## Picking a side up front does not survive the ground: a walk that comes round a
## bunker, a pond or the hole before it arrives on the side it is told to follow,
## and then pays to be away from its own guide for the rest of the hole. The
## corridor is ground no trail may be laid on, so a walk can never cross from one
## edge to the other part way up — it commits at the tee or at the green, where
## the two edges meet, and which way round it goes is the search's to settle.
static func _hole_guide(grid: TerrainGrid, hole) -> PackedVector2Array:
	var guide := _corridor_guide(grid, hole, 1.0)
	for point in _corridor_guide(grid, hole, -1.0):
		guide.append(point)
	return guide

## The polyline a hole's path is guided along: the mown edge of the corridor,
## pushed out by PATH_CLEARANCE, sampled about a tile apart from tee to green.
## The edge is read from the painted ground rather than from a layout table, so
## the guide follows the corridor's own bend and width — and so a hole any
## generator painted, or the player painted, can be followed too.
static func _corridor_guide(grid: TerrainGrid, hole, side: float) -> PackedVector2Array:
	var guide := PackedVector2Array()
	var tee := Vector2(hole.tee_position)
	var green := Vector2(hole.green_position)
	var run := green - tee
	var length := run.length()
	if length < 2.0:
		return guide
	var along := run / length
	var across := Vector2(-along.y, along.x) * side
	var samples := mini(int(length), GUIDE_MAX_POINTS)
	for step in range(samples + 1):
		var t := float(step) / float(samples)
		var centre := tee.lerp(green, t)
		var edge := _mown_edge(grid, centre, across)
		guide.append(centre + across * (edge + PATH_CLEARANCE))
	return guide

## How far out the mown ground reaches from `centre`, measured along `across`.
## Scanning the whole width rather than stopping at the first turf tile takes
## the corridor's bend into account: the centre of a bending fairway can sit
## beside its own line, and the edge is still the outermost mown tile.
static func _mown_edge(grid: TerrainGrid, centre: Vector2, across: Vector2) -> float:
	var edge := 0.0
	var misses := 0
	for step in range(1, CORRIDOR_SCAN + 1):
		var tile := Vector2i((centre + across * float(step)).round())
		if TerrainTypes.is_fairway(grid.get_tile(tile)):
			edge = float(step)
			misses = 0
		elif edge > 0.0:
			misses += 1
			if misses >= 2:
				break
	return edge if edge > 0.0 else FALLBACK_EDGE


# =============================================================================
# ROUTING
# =============================================================================

## Lay a planned route. Every tile is re-checked as it is laid: an earlier leg
## may have changed the ground, and a trail is never allowed on a green, a tee, a
## hazard, the mown playing line or a building's tile.
static func _lay(grid: TerrainGrid, entity_layer: EntityLayer, route: Array[Vector2i],
		laid: Dictionary) -> void:
	for tile in route:
		if laid.has(tile):
			continue
		if not _is_layable(grid, entity_layer, tile):
			continue
		# A trail already there — the course's own, or an earlier leg's — is
		# walked over rather than counted again.
		if grid.has_walking_path(tile):
			continue
		# Laying the course's grounds is generation, not a player edit: the trail
		# is laid quiet, off the maintenance books, out of the undo history the
		# caller is suppressing, and leaving the ground underneath untouched.
		grid.set_walking_path_quiet(tile, true)
		laid[tile] = true

## Can the Path improvement be laid on this tile right now? The ground rule is
## the grid's own, so a generated trail is never laid where the player's could
## not be.
static func _is_layable(grid: TerrainGrid, entity_layer: EntityLayer, tile: Vector2i) -> bool:
	if not grid.can_place_walking_path(tile):
		return false
	if not _is_owned(tile):
		return false
	if _is_occupied(entity_layer, tile):
		return false
	return true

## Land the player does not own cannot take a path, the same as it cannot take a
## building or a brush stroke. With no land manager there is nothing to check.
static func _is_owned(tile: Vector2i) -> bool:
	var land_manager = GameManager.land_manager
	if land_manager == null:
		return true
	return land_manager.is_tile_owned(tile)

## A building or a decoration occupies its tiles; a path cannot run under one.
static func _is_occupied(entity_layer: EntityLayer, tile: Vector2i) -> bool:
	if entity_layer == null:
		return false
	return entity_layer.is_tile_occupied_by_building(tile) \
			or entity_layer.is_tile_occupied_by_decoration(tile)

## What one tile costs a leg: nearly nothing once a trail is on it, the ground's
## own entry in TERRAIN_COSTS, the woodland rate for any tree tile, and
## BLOCKED_COST for ground the Path improvement cannot be laid on at all.
static func _step_cost(grid: TerrainGrid, tile: Vector2i) -> float:
	if grid.has_walking_path(tile):
		return LAID_TRAIL_COST
	var type: int = grid.get_tile(tile)
	if not TerrainTypes.can_host_walking_path(type):
		return BLOCKED_COST
	if TerrainTypes.is_tree(type):
		return WOODLAND_COST
	return float(TERRAIN_COSTS.get(type, BLOCKED_COST))

## The cheapest walk from `start` to any tile of `goals` — the ground a leg may
## come in on, mapped to what standing there costs beyond the ground itself — as
## the tiles it steps on including both ends. Empty when none of them can be
## walked to inside the budget, which is what ground sealed off by the mown
## playing line comes to.
##
## Planning onto a set rather than one chosen tile is what lets a leg stop short:
## the walk ends on whichever ground it can actually reach, as near the play as
## that leaves it. `guide_weight` pulls the walk toward `guide`; a leg with no
## guide is left to the ground and the distance, which is what the walks between
## holes want.
static func _plan_route(grid: TerrainGrid, entity_layer: EntityLayer, start: Vector2i,
		goals: Dictionary, guide: PackedVector2Array, guide_weight: float) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	if start == NO_TILE or goals.is_empty() or not _is_layable(grid, entity_layer, start):
		return route
	if goals.has(start):
		route.append(start)
		return route

	var area := _search_area(grid, start, goals)
	var width := area.size.x
	var total := width * area.size.y
	var cost := PackedFloat32Array()
	cost.resize(total)
	cost.fill(INF)
	var came_from := PackedInt32Array()
	came_from.resize(total)
	came_from.fill(-1)
	var settled := PackedByteArray()
	settled.resize(total)
	# The guide is read once for the whole box rather than once per step: a leg
	# looks at each of its tiles up to eight times, and the pull of the guide
	# never changes underneath it.
	var guide_field := _guide_field(area, guide) if guide_weight > 0.0 else PackedFloat32Array()
	var goal_field := _goal_field(area, width, goals)
	var cheapest := _cheapest_ground(grid, area)

	var start_cell := _cell_of(area, width, start)
	cost[start_cell] = 0.0
	var frontier := _Frontier.new()
	frontier.push(start_cell, float(goal_field[start_cell]) * cheapest)

	# The walk ends on the ground it can arrive at most cheaply, and arriving has
	# a price of its own — a ring further out, or behind the play — so the first
	# tile the search could end on is not necessarily the one it should: the
	# ground it would end on next is reached through it. The search therefore
	# settles every arrival it can and stops once nothing left in the frontier
	# could beat the best one it has.
	var best_cell := -1
	var best_arrival := INF
	var budget := NODE_BUDGET
	while not frontier.is_empty() and budget > 0:
		if frontier.peek_key() >= best_arrival:
			break
		budget -= 1
		var current := frontier.pop()
		if settled[current] == 1:
			continue
		settled[current] = 1
		var tile := _tile_of(area, width, current)
		if goals.has(tile):
			var arrival := cost[current] + float(goals[tile])
			if arrival < best_arrival:
				best_arrival = arrival
				best_cell = current
		for direction in DIRECTIONS:
			var next_tile := tile + direction
			if not area.has_point(next_tile):
				continue
			var next_cell := current + direction.y * width + direction.x
			if settled[next_cell] == 1:
				continue
			if not _is_layable(grid, entity_layer, next_tile):
				continue
			var step := _step_cost(grid, next_tile)
			if not guide_field.is_empty():
				step += guide_weight * guide_field[next_cell]
			var total_cost := cost[current] + step
			if total_cost < cost[next_cell]:
				cost[next_cell] = total_cost
				came_from[next_cell] = current
				frontier.push(next_cell, total_cost + _arrival(next_tile, next_cell,
						goals, goal_field, cheapest))
	return _trace_back(area, width, came_from, best_cell) if best_cell >= 0 else route


## What the search expects a walk through `tile` to end up costing: on ground a
## walk may come in on, what standing there costs — a ring further out, or behind
## the play — and anywhere else, a floor on the walk that is left.
##
## The bonus is charged on arrival and never on the way past. A walk into a tee or
## a green passes through every ring around it, and charging each of them would
## make the outermost ring the cheapest place to stop, leaving the play a long way
## off — so the rings a walk crosses on its way in are just ground.
static func _arrival(tile: Vector2i, cell: int, goals: Dictionary,
		goal_field: PackedInt32Array, cheapest: float) -> float:
	if goals.has(tile):
		return float(goals[tile])
	return float(goal_field[cell]) * cheapest

## How far every tile of a search box is from a guide polyline, indexed the same
## way as the box (empty when the leg has no guide to follow).
static func _guide_field(area: Rect2i, guide: PackedVector2Array) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	if guide.is_empty():
		return field
	field.resize(area.size.x * area.size.y)
	for row in range(area.size.y):
		for column in range(area.size.x):
			var point := Vector2(area.position.x + column, area.position.y + row)
			field[row * area.size.x + column] = _guide_distance(point, guide)
	return field

## How far a point is from the nearest point of a guide polyline, capped at
## GUIDE_MAX_DISTANCE.
static func _guide_distance(point: Vector2, guide: PackedVector2Array) -> float:
	var best := INF
	for sample in guide:
		best = minf(best, point.distance_squared_to(sample))
	return minf(sqrt(best), GUIDE_MAX_DISTANCE)

## How many steps every tile of a search box is from the nearest tile a walk may
## end on, indexed the same way as the box. It is read over the whole box at once
## rather than per step, and it ignores the ground entirely: a floor on the walk
## that is left, which is what an A* estimate has to be to stay optimal.
static func _goal_field(area: Rect2i, width: int, goals: Dictionary) -> PackedInt32Array:
	var field := PackedInt32Array()
	field.resize(area.size.x * area.size.y)
	field.fill(-1)
	var queue: Array[int] = []
	for tile in goals:
		if not area.has_point(tile):
			continue
		var cell := _cell_of(area, width, tile)
		field[cell] = 0
		queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		var tile := _tile_of(area, width, cell)
		for direction in DIRECTIONS:
			var next_tile := tile + direction
			if not area.has_point(next_tile):
				continue
			var next_cell := cell + direction.y * width + direction.x
			if field[next_cell] >= 0:
				continue
			field[next_cell] = field[cell] + 1
			queue.append(next_cell)
	return field

## The cheapest ground in a search box. Read once per leg, so the estimate is as
## tight as the ground allows: one that assumed a path everywhere would settle
## the whole box before it reached the goal.
static func _cheapest_ground(grid: TerrainGrid, area: Rect2i) -> float:
	var cheapest := BLOCKED_COST
	for row in range(area.size.y):
		for column in range(area.size.x):
			var tile := area.position + Vector2i(column, row)
			cheapest = minf(cheapest, _step_cost(grid, tile))
	return LAID_TRAIL_COST if cheapest == BLOCKED_COST else cheapest

## The box a leg is planned inside: its start and every tile it may end on grown
## by ROUTE_SLACK, so a leg steps round what is in its way without searching the
## whole property.
static func _search_area(grid: TerrainGrid, start: Vector2i, goals: Dictionary) -> Rect2i:
	var low := start
	var high := start
	for tile in goals:
		low = Vector2i(mini(low.x, tile.x), mini(low.y, tile.y))
		high = Vector2i(maxi(high.x, tile.x), maxi(high.y, tile.y))
	low -= Vector2i(ROUTE_SLACK, ROUTE_SLACK)
	high += Vector2i(ROUTE_SLACK, ROUTE_SLACK)
	low = Vector2i(maxi(low.x, 0), maxi(low.y, 0))
	high = Vector2i(mini(high.x, grid.grid_width - 1), mini(high.y, grid.grid_height - 1))
	var size := high - low + Vector2i.ONE
	return Rect2i(low, Vector2i(maxi(size.x, 1), maxi(size.y, 1)))

static func _cell_of(area: Rect2i, width: int, tile: Vector2i) -> int:
	return (tile.y - area.position.y) * width + (tile.x - area.position.x)

static func _tile_of(area: Rect2i, width: int, cell: int) -> Vector2i:
	@warning_ignore("integer_division")
	var row := cell / width
	return area.position + Vector2i(cell - row * width, row)

## The tiles of a finished walk, from its first end to its last.
static func _trace_back(area: Rect2i, width: int, came_from: PackedInt32Array,
		cell: int) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	var current := cell
	while current >= 0:
		route.append(_tile_of(area, width, current))
		current = came_from[current]
	route.reverse()
	return route


## The search's frontier: a binary heap of cells keyed by the estimated cost of
## the walk that goes through them. Small and hot, so it keeps its own typed
## arrays rather than a dictionary of Vector2i keys.
class _Frontier:
	var _cells := PackedInt32Array()
	var _keys := PackedFloat32Array()

	func is_empty() -> bool:
		return _cells.is_empty()

	## The key the next pop would return, without taking it off the heap.
	func peek_key() -> float:
		return _keys[0] if not _cells.is_empty() else INF

	func push(cell: int, key: float) -> void:
		_cells.append(cell)
		_keys.append(key)
		var child := _cells.size() - 1
		while child > 0:
			# Integer division is exact here: halving a heap index truncates nothing.
			@warning_ignore("integer_division")
			var parent := (child - 1) / 2
			if _keys[parent] <= _keys[child]:
				break
			_swap(parent, child)
			child = parent

	func pop() -> int:
		var top := _cells[0]
		var last := _cells.size() - 1
		_cells[0] = _cells[last]
		_keys[0] = _keys[last]
		_cells.remove_at(last)
		_keys.remove_at(last)
		var parent := 0
		while true:
			var left := parent * 2 + 1
			if left >= _cells.size():
				break
			var smallest := left
			var right := left + 1
			if right < _cells.size() and _keys[right] < _keys[left]:
				smallest = right
			if _keys[parent] <= _keys[smallest]:
				break
			_swap(parent, smallest)
			parent = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var cell := _cells[a]
		_cells[a] = _cells[b]
		_cells[b] = cell
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
