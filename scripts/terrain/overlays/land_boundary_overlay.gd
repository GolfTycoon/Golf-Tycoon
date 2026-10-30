extends Node2D
class_name LandBoundaryOverlay
## LandBoundaryOverlay - Draws property lines around owned land
##
## Shows a visible border between owned and unowned parcels, and
## applies a subtle tint to unowned areas so players know where
## they can and cannot build.

var terrain_grid: TerrainGrid

## Visual settings
const BOUNDARY_COLOR = Color(0.9, 0.6, 0.2, 0.8)  # Orange/gold property line
const BOUNDARY_WIDTH: float = 2.5
const UNOWNED_TINT = Color(0.4, 0.3, 0.3, 0.15)  # Subtle dark tint on unowned land

## Cache the boundary edges to avoid recalculating every frame
var _boundary_edges: Array = []  # Array of {start: Vector2, end: Vector2}
var _needs_recalculate: bool = true
## Projected tint polygon per tile, in this overlay's local space. A tile's
## diamond only moves when the ground is sculpted or the course is turned, so a
## camera-driven repaint re-emits it instead of re-projecting four corners for
## every one of the thousands of unowned tiles in view.
var _tile_polygons: Dictionary = {}  # Vector2i -> PackedVector2Array
## The whole default map, as a ceiling: a session that pans over every tile
## shelves one outline each and no more.
const MAX_CACHED_TILE_POLYGONS: int = 16384

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	z_index = 5  # Above terrain but below UI elements

	# Defer signal connection - land_manager may not exist yet
	call_deferred("_connect_land_signals")
	if grid:
		grid.vertex_elevation_changed.connect(_on_vertex_elevation_changed)
	EventBus.view_rotated.connect(_on_view_rotated)

	_needs_recalculate = true
	queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(terrain_grid) \
			and terrain_grid.vertex_elevation_changed.is_connected(_on_vertex_elevation_changed):
		terrain_grid.vertex_elevation_changed.disconnect(_on_vertex_elevation_changed)
	if EventBus.view_rotated.is_connected(_on_view_rotated):
		EventBus.view_rotated.disconnect(_on_view_rotated)

## The tinted diamonds lie on the ground: sculpting a vertex lifts the corners
## of the tiles that share it, so the cached outlines are stale.
func _on_vertex_elevation_changed(_vertex: Vector2i, _old: int, _new: int) -> void:
	invalidate_ground()
	queue_redraw()

## A quarter turn changes where every tile is on screen.
func _on_view_rotated(_orientation: int, _isometric: bool) -> void:
	invalidate_ground()
	queue_redraw()

func _connect_land_signals() -> void:
	# Connect to land manager signals (deferred to ensure manager exists)
	if GameManager.land_manager:
		if not GameManager.land_manager.land_purchased.is_connected(_on_land_changed):
			GameManager.land_manager.land_purchased.connect(_on_land_changed)
		if not GameManager.land_manager.land_boundary_changed.is_connected(_on_land_boundary_changed):
			GameManager.land_manager.land_boundary_changed.connect(_on_land_boundary_changed)

func _on_land_boundary_changed() -> void:
	_needs_recalculate = true
	queue_redraw()

func _on_land_changed(_parcel = null) -> void:
	_needs_recalculate = true
	queue_redraw()

func _draw() -> void:
	if not terrain_grid:
		return
	if not GameManager.land_manager:
		return

	# Recalculate boundary edges if needed
	if _needs_recalculate:
		_calculate_boundary_edges()
		_needs_recalculate = false

	_draw_unowned_tint()

	# Draw property line borders.
	for edge in _boundary_edges:
		var start_world = terrain_grid.grid_point_to_screen(
				Vector2(edge.start_tile) + edge.start_offset)
		var end_world = terrain_grid.grid_point_to_screen(
				Vector2(edge.end_tile) + edge.end_offset)
		draw_line(to_local(start_world), to_local(end_world), BOUNDARY_COLOR,
				BOUNDARY_WIDTH, true)

## Tint every unowned tile in view as one triangle batch. A tile is a convex
## quad (a diamond in the isometric view, a square in the top-down one), so a
## fan from its first corner fills it exactly. Recording thousands of
## `draw_colored_polygon()` calls was the overlay's cost on a camera-driven
## repaint; one batched array is a single renderer call for all of them.
func _draw_unowned_tint() -> void:
	var vertices := PackedVector2Array()
	var indices := PackedInt32Array()
	for pos in visible_unowned_tiles():
		var poly := _tile_polygon(pos)
		if poly.size() < 3:
			continue
		var base := vertices.size()
		vertices.append_array(poly)
		for i in range(1, poly.size() - 1):
			indices.append(base)
			indices.append(base + i)
			indices.append(base + i + 1)
	if indices.is_empty():
		return
	# Every vertex wears the same tint, so one fill beats appending per corner.
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(UNOWNED_TINT)
	RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), indices, vertices, colors)

## One unowned tile's projected outline, from the shelf when it is there.
func _tile_polygon(pos: Vector2i) -> PackedVector2Array:
	if _tile_polygons.has(pos):
		return _tile_polygons[pos]
	if _tile_polygons.size() >= MAX_CACHED_TILE_POLYGONS:
		_tile_polygons.clear()
	var poly := OverlayGeometry.tile_polygon(terrain_grid, self, pos)
	_tile_polygons[pos] = poly
	return poly

## Drop the projected tile outlines after a bulk elevation load, which writes
## the heightfield without a per-vertex signal (see TerrainGrid).
func invalidate_ground() -> void:
	_tile_polygons.clear()

## The unowned tiles worth tinting: the camera's visible tile window, clipped
## to the grid. The whole map is 128x128 tiles, so walking every tile on every
## camera-driven repaint was the overlay's cost; the window is all that can be
## seen and it already carries the shared prefetch margin.
func visible_unowned_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not terrain_grid or not GameManager.land_manager:
		return tiles
	var tile_range := terrain_grid.get_visible_tile_range()
	if tile_range.size() < 2:
		return tiles
	var lm = GameManager.land_manager
	var first: Vector2i = tile_range[0]
	var last: Vector2i = tile_range[1]
	# Ownership is per parcel, so a row is walked a parcel segment at a time
	# instead of asking the land manager about every tile of it.
	var parcel_first: int = LandManager.GRID_OFFSET
	var parcel_last_y: int = parcel_first + LandManager.PARCEL_GRID_ROWS * LandManager.PARCEL_SIZE - 1
	for y in range(first.y, last.y + 1):
		if y < parcel_first or y > parcel_last_y:
			_append_tile_run(tiles, first.x, last.x, y)
			continue
		var x := first.x
		while x <= last.x:
			var parcel: Vector2i = lm.tile_to_parcel(Vector2i(x, y))
			var run_end := last.x
			var owned := false
			if parcel == Vector2i(-1, -1):
				# The grid margin belongs to no parcel, so nobody owns it.
				if x < parcel_first:
					run_end = mini(last.x, parcel_first - 1)
			else:
				run_end = mini(last.x, lm.parcel_to_tile_rect(parcel).end.x - 1)
				owned = lm.owned_parcels.has(parcel)
			if not owned:
				_append_tile_run(tiles, x, run_end, y)
			x = run_end + 1
	return tiles

static func _append_tile_run(tiles: Array[Vector2i], from_x: int, to_x: int, y: int) -> void:
	for x in range(from_x, to_x + 1):
		tiles.append(Vector2i(x, y))

func _calculate_boundary_edges() -> void:
	"""Calculate all boundary edges between owned and unowned tiles."""
	_boundary_edges.clear()

	if not GameManager.land_manager:
		return

	var lm = GameManager.land_manager

	# Check every tile for boundary edges
	for x in range(terrain_grid.grid_width):
		for y in range(terrain_grid.grid_height):
			var pos = Vector2i(x, y)
			var is_owned = lm.is_tile_owned(pos)

			if not is_owned:
				continue  # Only draw borders from owned side

			# Check each neighbor
			# Right neighbor
			var right = Vector2i(x + 1, y)
			if not lm.is_tile_owned(right):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(1, 0),
					"end_tile": pos,
					"end_offset": Vector2(1, 1)
				})

			# Bottom neighbor
			var bottom = Vector2i(x, y + 1)
			if not lm.is_tile_owned(bottom):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(0, 1),
					"end_tile": pos,
					"end_offset": Vector2(1, 1)
				})

			# Left neighbor
			var left = Vector2i(x - 1, y)
			if not lm.is_tile_owned(left):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(0, 0),
					"end_tile": pos,
					"end_offset": Vector2(0, 1)
				})

			# Top neighbor
			var top = Vector2i(x, y - 1)
			if not lm.is_tile_owned(top):
				_boundary_edges.append({
					"start_tile": pos,
					"start_offset": Vector2(0, 0),
					"end_tile": pos,
					"end_offset": Vector2(1, 0)
				})
