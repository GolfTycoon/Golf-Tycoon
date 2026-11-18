extends Node2D
class_name StaffAreaOverlay
## StaffAreaOverlay - Draws each hired staff member's designated area on the course.
##
## The area is a circle in grid space, so it is projected point-by-point into
## world space to render correctly in both the isometric and top-down views.
## While the player is repositioning an employee (move_staff_area mode) that
## employee's ring is highlighted.
##
## The owner's own golfer works a ground of their own, and it is drawn here
## too - in gold, so it reads as the owner's and not as another employee.
##
## A ring is paint on the ground, laid over whatever hills it takes in. Its disc
## is a mesh of the tiles it covers, built in grid space - each tile whole, or
## cut to the rim - and lifted onto the ground point by point (see
## `build_ring()`), so it never has to be triangulated on screen: sculpted ground
## can fold a projected outline over itself, and the engine cannot fill one that
## does ("Invalid polygon data, triangulation failed"). Every vertex also carries
## its grid point, so a nearer hill hides the ring behind it, as it hides the
## walking trail (terrain_decal_occlusion.gdshader).

const FILL_ALPHA: float = 0.10
const OUTLINE_ALPHA: float = 0.45
const HIGHLIGHT_FILL_ALPHA: float = 0.22
const HIGHLIGHT_OUTLINE_ALPHA: float = 0.95
## The owner's own work area: the owner's colour, and a little brighter than
## a hired employee's ring.
const OWNER_FILL_ALPHA: float = 0.12
const OWNER_OUTLINE_ALPHA: float = 0.7
## The rim is sampled every this many tiles along its length, so it follows the
## ground it crosses instead of cutting chords through the hills.
const RIM_SPACING: float = 0.5
const MIN_RIM_POINTS: int = 32
const MAX_RIM_POINTS: int = 512
## Clips the rings where nearer terrain covers them (see
## TerrainGrid.terrain_occlusion_enabled()).
const TERRAIN_DECAL_OCCLUSION: Shader = preload("res://shaders/terrain_decal_occlusion.gdshader")

var terrain_grid: TerrainGrid = null
## Index into StaffManager.hired_staff currently being repositioned, or -1.
var highlight_index: int = -1
## The rings drawn last, by Vector3(centre x, centre y, radius): an area's mesh
## only depends on where it is, so a redraw (a highlight, a turn of the view, a
## new hire elsewhere) reuses it.
var _rings: Dictionary = {}
## The overlay's material while terrain occlusion is on; null on a flat course.
var _occlusion_material: ShaderMaterial = null

## One designated area in grid space: the disc as triangles and the rim as a
## closed line (its last point repeats its first). Both hold while the area
## stays where it is; the lifts - how far the ground raises each point on
## screen - and the slope under each rim point are measured again whenever the
## terrain has changed.
class AreaRing:
	var fill_grounds := PackedVector2Array()
	var fill_indices := PackedInt32Array()
	var rim_grounds := PackedVector2Array()
	var fill_lifts := PackedFloat32Array()
	var rim_lifts := PackedFloat32Array()
	var rim_rises := PackedVector2Array()
	var lift_revision := -1

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

func _ready() -> void:
	z_index = 1  # Above the opaque terrain, below entities
	var manager = GameManager.staff_manager
	if manager and manager.has_signal("staff_changed"):
		manager.staff_changed.connect(_on_staff_changed)
	if terrain_grid:
		terrain_grid.view_rotated.connect(_on_view_rotated)
		terrain_grid.terrain_occlusion_changed.connect(_on_terrain_occlusion_changed)
		# The rings lie on the ground: a sculpt or a loaded course moves them.
		terrain_grid.vertex_elevation_changed.connect(_on_ground_changed)
		terrain_grid.surface_refreshed.connect(queue_redraw)
	_refresh_occlusion()
	queue_redraw()

func _exit_tree() -> void:
	var manager = GameManager.staff_manager
	if manager and manager.has_signal("staff_changed") and manager.staff_changed.is_connected(_on_staff_changed):
		manager.staff_changed.disconnect(_on_staff_changed)
	if is_instance_valid(terrain_grid):
		if terrain_grid.view_rotated.is_connected(_on_view_rotated):
			terrain_grid.view_rotated.disconnect(_on_view_rotated)
		if terrain_grid.terrain_occlusion_changed.is_connected(_on_terrain_occlusion_changed):
			terrain_grid.terrain_occlusion_changed.disconnect(_on_terrain_occlusion_changed)
		if terrain_grid.vertex_elevation_changed.is_connected(_on_ground_changed):
			terrain_grid.vertex_elevation_changed.disconnect(_on_ground_changed)
		if terrain_grid.surface_refreshed.is_connected(queue_redraw):
			terrain_grid.surface_refreshed.disconnect(queue_redraw)

func _on_staff_changed() -> void:
	queue_redraw()

func refresh() -> void:
	queue_redraw()

## A turn re-projects every ring, and gives the occlusion shader the new view.
func _on_view_rotated(_orientation: int, _isometric: bool) -> void:
	_refresh_occlusion()
	queue_redraw()

func _on_ground_changed(_vertex: Vector2i, _old: int, _new: int) -> void:
	queue_redraw()

func _on_terrain_occlusion_changed(_enabled: bool) -> void:
	_refresh_occlusion()

## Clip the rings behind nearer terrain while the course has relief and the
## graphics setting allows it; a flat course draws them with no material at all.
## The heightfield is shared with the surface and updated in place, so only a
## turn of the view (the projection) needs this again.
func _refresh_occlusion() -> void:
	var surface: CourseSurface = terrain_grid._course_surface if terrain_grid else null
	if surface == null or not terrain_grid.terrain_occlusion_enabled():
		material = null
		return
	if _occlusion_material == null:
		_occlusion_material = ShaderMaterial.new()
		_occlusion_material.shader = TERRAIN_DECAL_OCCLUSION
	surface.configure_terrain_occlusion(_occlusion_material)
	material = _occlusion_material

func _draw() -> void:
	if terrain_grid == null:
		return
	var drawn := {}
	if GameManager.staff_manager != null:
		var staff: Array = GameManager.staff_manager.hired_staff
		for i in range(staff.size()):
			var record: Dictionary = staff[i]
			var center: Vector2i = record.get("area_center", Vector2i.ZERO)
			var radius: float = float(record.get("area_radius", 6.0))
			var highlighted := i == highlight_index
			var fill := Color(0.4, 0.85, 0.5, HIGHLIGHT_FILL_ALPHA if highlighted else FILL_ALPHA)
			var outline := Color(1.0, 0.92, 0.55, HIGHLIGHT_OUTLINE_ALPHA) if highlighted \
				else Color(0.45, 0.9, 0.55, OUTLINE_ALPHA)
			_draw_ring(Vector2(center), radius, fill, outline, 1.5 if not highlighted else 2.5, drawn)
	_draw_owner_area(drawn)
	# Keep only the areas still drawn, so the shelf never outgrows the course.
	_rings = drawn

## The ground the owner's own golfer works, drawn in the owner's gold.
func _draw_owner_area(drawn: Dictionary) -> void:
	var manager = GameManager.player_golfer_manager
	if manager == null or manager.area_center.x < 0:
		return
	_draw_ring(Vector2(manager.area_center), manager.area_radius,
		Color(0.95, 0.78, 0.35, OWNER_FILL_ALPHA), Color(1.0, 0.85, 0.4, OWNER_OUTLINE_ALPHA), 2.0, drawn)

## One area: the disc, then the rim over it, as `ring_geometry()` lays them out.
func _draw_ring(center_grid: Vector2, radius: float, fill: Color, outline: Color, width: float,
		drawn: Dictionary) -> void:
	var geometry := ring_geometry(center_grid, radius, outline, width, drawn)
	var fill_indices: PackedInt32Array = geometry.fill_indices
	if fill_indices.is_empty():
		return
	var canvas_item := get_canvas_item()
	RenderingServer.canvas_item_add_triangle_array(canvas_item, fill_indices,
			geometry.fill_points, PackedColorArray([fill]), geometry.fill_grounds)
	(geometry.rim as GroundDecal).draw_on(canvas_item)

## What one area is drawn with, in this overlay's space: {"fill_points",
## "fill_grounds", "fill_indices"} - the disc's triangles, every vertex with the
## grid point of its ground (its UV) - {"rim_points", "rim_grounds"}, the closed
## line of the rim, and "rim", the GroundDecal that paints that line `width`
## pixels wide in `outline`, each edge of it on the slope under its rim point.
## Empty for an area too small to draw. `drawn` collects the rings a repaint
## used.
func ring_geometry(center_grid: Vector2, radius: float, outline: Color = Color.WHITE,
		width: float = 1.5, drawn: Dictionary = {}) -> Dictionary:
	var ring := _ring_for(center_grid, radius, drawn)
	var rim_points := _project(ring.rim_grounds, ring.rim_lifts)
	var planes := []
	for rise in ring.rim_rises:
		planes.append(GroundDecal.surface_plane(terrain_grid, rise))
	var rim := GroundDecal.new()
	rim.add_polyline(rim_points, outline, width, false, ring.rim_grounds, planes)
	return {
		"fill_points": _project(ring.fill_grounds, ring.fill_lifts),
		"fill_grounds": ring.fill_grounds,
		"fill_indices": ring.fill_indices,
		"rim_points": rim_points,
		"rim_grounds": ring.rim_grounds,
		"rim": rim,
	}

## The ring of the area centred on `center_grid`, from the shelf when it is
## already there, with its lifts brought up to date with the terrain.
func _ring_for(center_grid: Vector2, radius: float, drawn: Dictionary) -> AreaRing:
	var key := Vector3(center_grid.x, center_grid.y, radius)
	var ring: AreaRing = _rings.get(key)
	if ring == null:
		ring = build_ring(center_grid, radius)
		_rings[key] = ring
	drawn[key] = ring
	if ring.lift_revision != terrain_grid.terrain_revision:
		ring.fill_lifts = _lifts(ring.fill_grounds)
		ring.rim_lifts = _lifts(ring.rim_grounds)
		ring.rim_rises.resize(ring.rim_grounds.size())
		for i in ring.rim_grounds.size():
			ring.rim_rises[i] = GroundDecal.ground_rise(terrain_grid, ring.rim_grounds[i])
		ring.lift_revision = terrain_grid.terrain_revision
	return ring

## How far the ground raises each grid point on screen (the y of
## TerrainGrid.get_elevation_displacement()).
func _lifts(grounds: PackedVector2Array) -> PackedFloat32Array:
	var lifts := PackedFloat32Array()
	lifts.resize(grounds.size())
	for i in grounds.size():
		lifts[i] = terrain_grid.get_elevation_displacement(grounds[i]).y
	return lifts

## Where each grid point is drawn, in this overlay's space: projected and lifted
## as TerrainGrid.grid_point_to_screen() does it, with the lifts already
## measured - which is all a turn of the view needs to redo.
func _project(grounds: PackedVector2Array, lifts: PackedFloat32Array) -> PackedVector2Array:
	var view := terrain_grid.projection
	var origin := view.grid_origin()
	var axis_x := view.axis_x()
	var axis_y := view.axis_y()
	var to_overlay := get_global_transform().affine_inverse()
	var drawn_points := PackedVector2Array()
	drawn_points.resize(grounds.size())
	for i in grounds.size():
		var ground := grounds[i]
		drawn_points[i] = to_overlay * (origin + axis_x * ground.x + axis_y * ground.y + Vector2(0.0, lifts[i]))
	return drawn_points

## The disc and the rim of the area centred on `center_grid` with `radius`
## tiles, in grid space. The rim is a polygon with a point every RIM_SPACING
## tiles. The disc is cut along the tiles: a tile wholly inside the rim is four
## triangles about its centre, the rest of the disc is each tile clipped to the
## rim and fanned about its middle. So no triangle crosses a tile edge, where
## the ground bends, and each lies close to the ground under it once lifted.
static func build_ring(center_grid: Vector2, radius: float) -> AreaRing:
	var ring := AreaRing.new()
	if not (radius > 0.0) or not is_finite(radius):
		return ring
	var count := clampi(ceili(TAU * radius / RIM_SPACING), MIN_RIM_POINTS, MAX_RIM_POINTS)
	var rim := PackedVector2Array()
	for i in count:
		var angle := TAU * float(i) / float(count)
		rim.append(center_grid + Vector2(cos(angle), sin(angle)) * radius)
	ring.rim_grounds = rim.duplicate()
	ring.rim_grounds.append(rim[0])
	# A point nearer the centre than the rim polygon's inner radius is inside it.
	var inner := radius * cos(PI / float(count))
	var corner_indices: Dictionary = {}
	for ty in range(floori(center_grid.y - radius), ceili(center_grid.y + radius)):
		for tx in range(floori(center_grid.x - radius), ceili(center_grid.x + radius)):
			var tile := Vector2(tx, ty)
			var nearest := Vector2(clampf(center_grid.x, tile.x, tile.x + 1.0),
					clampf(center_grid.y, tile.y, tile.y + 1.0))
			if nearest.distance_to(center_grid) >= radius:
				continue
			var square := PackedVector2Array([tile, tile + Vector2(1, 0), tile + Vector2(1, 1),
					tile + Vector2(0, 1)])
			var whole := true
			for corner in square:
				if corner.distance_to(center_grid) > inner:
					whole = false
					break
			if whole:
				var hub := ring.fill_grounds.size()
				ring.fill_grounds.append(tile + Vector2(0.5, 0.5))
				var around := PackedInt32Array()
				for corner in square:
					if not corner_indices.has(corner):
						corner_indices[corner] = ring.fill_grounds.size()
						ring.fill_grounds.append(corner)
					around.append(corner_indices[corner])
				for i in 4:
					ring.fill_indices.append_array(PackedInt32Array([hub, around[i], around[(i + 1) % 4]]))
			else:
				for piece in Geometry2D.intersect_polygons(square, rim):
					_fan(ring, piece)
	return ring

## A convex piece of the disc as the fan about the average of its points.
static func _fan(ring: AreaRing, piece: PackedVector2Array) -> void:
	if piece.size() < 3:
		return
	var middle := Vector2.ZERO
	for point in piece:
		middle += point
	var hub := ring.fill_grounds.size()
	ring.fill_grounds.append(middle / float(piece.size()))
	var first := ring.fill_grounds.size()
	ring.fill_grounds.append_array(piece)
	for i in piece.size():
		ring.fill_indices.append_array(PackedInt32Array([hub, first + i, first + (i + 1) % piece.size()]))

## The ring of ground the owner's own golfer works, in world space. Empty when
## the owner has no ground yet.
func owner_area_polygon() -> PackedVector2Array:
	if terrain_grid == null:
		return PackedVector2Array()
	var manager = GameManager.player_golfer_manager
	if manager == null or manager.area_center.x < 0:
		return PackedVector2Array()
	return _projected_circle(Vector2(manager.area_center), manager.area_radius)

## Sample a grid-space circle and project each point to world space.
func _projected_circle(center_grid: Vector2, radius: float) -> PackedVector2Array:
	var segments := 32
	var points := PackedVector2Array()
	for i in segments:
		var a := (i / float(segments)) * TAU
		var gp := center_grid + Vector2(cos(a), sin(a)) * radius
		points.append(terrain_grid.grid_point_to_screen(gp))
	return points
