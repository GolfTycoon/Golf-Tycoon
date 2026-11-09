extends Control
class_name CourseMapThumbnail
## A non-interactive, whole-course map for the Save/Load dossier. It reads the
## live terrain grid while saving and the selected save's serialized terrain
## while loading, using the same terrain palette as the in-game course map.

const INK := Color("10241f")
const EDGE := Color("8fc79b")
const ROUTE := Color(0.93, 0.91, 0.75, 0.78)
const TEE := Color("e5c57c")
const GREEN := Color("82d890")
const LABEL_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")
const GRID_WIDTH := 128
const GRID_HEIGHT := 128

var _grid: TerrainGrid
var _terrain: Dictionary = {}
var _paths: Array = []
var _holes: Array = []
var _has_course := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	queue_redraw()

func show_live_course(grid: TerrainGrid, holes: Array = []) -> void:
	_grid = grid
	_terrain.clear()
	_paths = grid.get_walking_paths() if grid != null else []
	_holes = holes.duplicate(true)
	_has_course = grid != null
	queue_redraw()

func show_saved_course(save_data: Dictionary) -> void:
	_grid = null
	_terrain = save_data.get("terrain", {}).duplicate() if save_data.get("terrain", {}) is Dictionary else {}
	_paths = _parse_positions(save_data.get("walking_paths", []))
	_holes = save_data.get("holes", []).duplicate(true) if save_data.get("holes", []) is Array else []
	_has_course = not save_data.is_empty()
	queue_redraw()

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size).grow(-2.0)
	if bounds.size.x < 12.0 or bounds.size.y < 12.0:
		return
	draw_rect(bounds, Color(0.012, 0.035, 0.027, 0.95))
	var center := bounds.get_center()
	var unit := minf(bounds.size.x * 2.0 / float(GRID_WIDTH + GRID_HEIGHT),
		bounds.size.y * 4.0 / float(GRID_WIDTH + GRID_HEIGHT))
	var tile_half := Vector2(unit * 0.25, unit * 0.125)
	var diamond := PackedVector2Array([
		center + Vector2(0, -unit * float(GRID_WIDTH + GRID_HEIGHT) / 8.0),
		center + Vector2(unit * float(GRID_WIDTH + GRID_HEIGHT) / 4.0, 0),
		center + Vector2(0, unit * float(GRID_WIDTH + GRID_HEIGHT) / 8.0),
		center + Vector2(-unit * float(GRID_WIDTH + GRID_HEIGHT) / 4.0, 0),
	])
	draw_colored_polygon(diamond, Color("315f3f"))
	if not _has_course:
		_draw_edge(diamond)
		draw_string(LABEL_FONT, Vector2(bounds.position.x + 8.0, center.y + 4.0),
			"Select a save to preview its course", HORIZONTAL_ALIGNMENT_CENTER,
			bounds.size.x - 16.0, 11, Color(0.84, 0.89, 0.79, 0.9))
		return

	# Most of the 128x128 plot is plain grass; the diamond is that base layer.
	# Draw only changed tiles, which keeps the little dossier map inexpensive.
	for y in GRID_HEIGHT:
		for x in GRID_WIDTH:
			var terrain_type := _tile_type(Vector2i(x, y))
			if terrain_type == TerrainTypes.Type.GRASS:
				continue
			var p := _tile_center(x, y, center, unit)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -tile_half.y), p + Vector2(tile_half.x, 0),
				p + Vector2(0, tile_half.y), p + Vector2(-tile_half.x, 0),
			]), CourseSurface.map_color(terrain_type))

	for path in _paths:
		var pos := _as_grid_position(path)
		if pos.x >= 0:
			draw_circle(_tile_center(pos.x, pos.y, center, unit), maxf(unit * 0.055, 0.7), Color("d4c79a"))
	for hole in _holes:
		if not hole is Dictionary:
			continue
		var tee := _hole_point(hole, "tee_position")
		var green := _hole_point(hole, "green_position")
		if tee.x < 0 or green.x < 0:
			continue
		var from := _tile_center(int(tee.x), int(tee.y), center, unit)
		var to := _tile_center(int(green.x), int(green.y), center, unit)
		draw_line(from, to, ROUTE, maxf(1.0, unit * 0.07), true)
		draw_circle(from, maxf(2.0, unit * 0.16), TEE)
		draw_circle(to, maxf(2.0, unit * 0.17), GREEN)
	_draw_edge(diamond)

func _draw_edge(diamond: PackedVector2Array) -> void:
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]),
		Color(EDGE, 0.76), 1.2, true)

func _tile_center(x: int, y: int, center: Vector2, unit: float) -> Vector2:
	return center + Vector2(float(x - y) * unit * 0.5,
		(float(x + y) - float(GRID_WIDTH + GRID_HEIGHT - 2) * 0.5) * unit * 0.25)

func _tile_type(pos: Vector2i) -> int:
	if _grid != null:
		return _grid.get_tile(pos)
	return int(_terrain.get("%d,%d" % [pos.x, pos.y], TerrainTypes.Type.GRASS))

func _parse_positions(values: Array) -> Array:
	var result: Array = []
	for value in values:
		var parts := str(value).split(",")
		if parts.size() == 2:
			result.append(Vector2i(int(parts[0]), int(parts[1])))
	return result

func _as_grid_position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Dictionary:
		return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))
	return Vector2i(-1, -1)

func _hole_point(hole: Dictionary, key: String) -> Vector2i:
	return _as_grid_position(hole.get(key, {}))
