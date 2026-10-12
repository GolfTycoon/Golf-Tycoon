extends MainSceneTest
## The three elevation selector tools (Vertex, Flat Square, Gradual Square) on
## a new course, through the real main.gd input path: the toolbar
## selects the tool, right click raises, left click lowers, right click never
## cancels the tool, Esc does, and undo puts the ground back.
##
## The Square Selectors' brush is measured in tiles: it reshapes the tiles it
## covers, so a 3x3 brush holds 16 vertices (4 per side).

## The widest brush the tests use.
const AREA_SIZE := 9

var grid: TerrainGrid
## An owned, unoccupied tile in the middle of the course: every corner of it,
## and of the brushes centred on it, can be reshaped.
var anchor: Vector2i


func before_all() -> void:
	await super()
	await new_game("Elevation tools")
	grid = main.terrain_grid
	anchor = _pick_tile()
	# Plain rough under every brush: a generated lot can put water there, which
	# the tools refuse to reshape.
	main._suppress_tile_undo = true
	for x in range(anchor.x - AREA_SIZE, anchor.x + AREA_SIZE + 1):
		for y in range(anchor.y - AREA_SIZE, anchor.y + AREA_SIZE + 1):
			if not main.entity_layer.is_tile_occupied_by_building(Vector2i(x, y)):
				grid.set_tile(Vector2i(x, y), TerrainTypes.Type.ROUGH)
	main._suppress_tile_undo = false


func after_each() -> void:
	main._stop_elevation_painting()
	main._cancel_elevation_mode()
	await super()


func _mouse_button(pressed: bool, button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	return event


## The tile nearest the middle of the lot whose widest brush reaches only owned
## ground clear of buildings.
func _pick_tile() -> Vector2i:
	for radius in range(0, 20):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := Vector2i(64, 64) + Vector2i(dx, dy)
				if grid.is_valid_position(tile) and _brush_is_editable(tile):
					return tile
	return Vector2i(64, 64)


func _brush_is_editable(tile: Vector2i) -> bool:
	for vertex in ElevationTool.brush_vertices(grid, tile, AREA_SIZE, true):
		if not grid.is_vertex_editable(vertex, main.entity_layer, true):
			return false
	return true


## Flatten every vertex of the brush centred on the anchor so assertions are exact.
func _flatten(size: int) -> void:
	for vertex in ElevationTool.brush_vertices(grid, anchor, size, true):
		grid.set_vertex_elevation(vertex, grid.BASE_ELEVATION)


func test_the_toolbar_arms_the_tool_and_the_mouse_buttons_raise_and_lower() -> void:
	assert_true(_brush_is_editable(anchor), "Every brush around %s reaches editable owned land" % anchor)
	main.terrain_toolbar._on_tool_button_pressed("flat")
	await process_frames(2)
	assert_eq(main.elevation_tool.tool, ElevationTool.Tool.FLAT, "Flat Square is selected from the toolbar")
	assert_true(main.elevation_tool.is_active(), "The elevation tool is active")
	assert_true(main.placement_preview.elevation_mode_active, "The preview shows the elevation brush")
	assert_eq(main.placement_preview.elevation_tool_type, ElevationTool.Tool.FLAT,
		"and mirrors the selected tool")

	# Headless, the pointer sits at the course corner, so this checks the input
	# wiring and the mode; the ground itself is checked on a chosen tile below.
	main._unhandled_input(_mouse_button(true, MOUSE_BUTTON_RIGHT))
	await process_frames(1)
	assert_true(main.elevation_tool.is_raising(), "Right click starts a raising stroke")
	main._unhandled_input(_mouse_button(false, MOUSE_BUTTON_RIGHT))
	await process_frames(1)
	assert_true(main.elevation_tool.is_active(), "Releasing right click does not cancel the tool")
	assert_eq(main.elevation_tool.elevation_mode, ElevationTool.ElevationMode.NONE,
		"but ends the stroke")
	main._unhandled_input(_mouse_button(true, MOUSE_BUTTON_LEFT))
	await process_frames(1)
	assert_true(main.elevation_tool.is_lowering(), "Left click starts a lowering stroke")
	main._unhandled_input(_mouse_button(false, MOUSE_BUTTON_LEFT))
	await process_frames(1)
	assert_true(main.elevation_tool.is_active(), "Releasing left click does not cancel the tool")


func test_flat_square_raises_the_lowest_and_lowers_the_highest_vertices() -> void:
	_flatten(AREA_SIZE)
	main.terrain_toolbar._on_tool_button_pressed("flat")
	await process_frames(1)

	# Raising lifts only the lowest vertices one level.
	main._start_elevation_painting(true)
	var area := ElevationTool.brush_vertices(grid, anchor, 3, true)
	assert_eq(area.size(), 16, "A 3x3 Flat brush selects 16 vertices")
	for i in area.size():
		grid.set_vertex_elevation(area[i], grid.BASE_ELEVATION + i % 3)  # +0/+1/+2 mixture
	main.undo_manager.record_elevation_stroke(main.elevation_tool.paint_at_tile(anchor, grid, main.entity_layer))
	main._stop_elevation_painting()
	await process_frames(2)
	for i in area.size():
		var expected: int = grid.BASE_ELEVATION + 1 if i % 3 == 0 else grid.BASE_ELEVATION + i % 3
		assert_eq(grid.get_vertex_elevation(area[i]), expected,
			"Vertex %s %s" % [area[i], "rises one level" if i % 3 == 0 else "is higher and stays put"])
	assert_eq(grid.get_vertex_elevation(anchor + Vector2i(-2, 0)), grid.BASE_ELEVATION,
		"Outside the brush is untouched")

	# Lowering even ground steps it down as one slab.
	main._start_elevation_painting(false)
	for vertex in area:
		grid.set_vertex_elevation(vertex, grid.BASE_ELEVATION + 3)
	main.undo_manager.record_elevation_stroke(main.elevation_tool.paint_at_tile(anchor, grid, main.entity_layer))
	main._stop_elevation_painting()
	await process_frames(2)
	for vertex in area:
		assert_eq(grid.get_vertex_elevation(vertex), grid.BASE_ELEVATION + 2,
			"Vertex %s stays even and steps down one level" % vertex)


func test_gradual_square_builds_a_one_step_pyramid() -> void:
	_flatten(AREA_SIZE)
	main._on_elevation_tool_pressed(ElevationTool.TOOL_GRADUAL)
	await process_frames(2)
	assert_eq(main.elevation_tool.tool, ElevationTool.Tool.GRADUAL, "Gradual Square is selected")
	# Widen the Elevation Brush to 7x7 the way the tab's stepper does.
	main._on_elevation_brush_size_changed(7)
	await process_frames(1)
	assert_eq(main.elevation_tool.brush_size, 7, "The elevation brush widens to 7x7")
	for i in range(3):
		main._start_elevation_painting(true)
		main.undo_manager.record_elevation_stroke(main.elevation_tool.paint_at_tile(anchor, grid, main.entity_layer))
		main._stop_elevation_painting()
	await process_frames(2)
	assert_eq(grid.get_vertex_elevation(anchor), grid.BASE_ELEVATION + 3, "The middle rises three levels")
	for vertex in ElevationTool.brush_vertices(grid, anchor, 7, true):
		var expected: int = grid.BASE_ELEVATION + 3 - ElevationTool.distance_to_middle(vertex, 7, anchor)
		assert_eq(grid.get_vertex_elevation(vertex), expected, "Vertex %s holds the one-step pyramid" % vertex)
	assert_eq(ElevationTool.middle_vertices(7, anchor).size(), 4,
		"A 7x7 gradual brush lifts the anchor tile's four corners")


func test_the_vertex_tool_moves_one_vertex_and_undo_puts_it_back() -> void:
	main._on_elevation_tool_pressed(ElevationTool.TOOL_VERTEX)
	await process_frames(2)
	assert_eq(main.elevation_tool.tool, ElevationTool.Tool.VERTEX, "The Vertex tool is selected")
	_flatten(5)
	main._start_elevation_painting(true)
	main.undo_manager.record_elevation_stroke(main.elevation_tool.paint_at_vertex(anchor, grid, main.entity_layer))
	main._stop_elevation_painting()
	await process_frames(2)
	assert_eq(grid.get_vertex_elevation(anchor), grid.BASE_ELEVATION + 1, "The vertex rises one level")
	var neighbours_moved := 0
	for vertex in ElevationTool.brush_vertices(grid, anchor, 5, true):
		if vertex != anchor and grid.get_vertex_elevation(vertex) != grid.BASE_ELEVATION:
			neighbours_moved += 1
	assert_eq(neighbours_moved, 0, "No other vertex moves")
	main._perform_undo()
	await process_frames(2)
	assert_eq(grid.get_vertex_elevation(anchor), grid.BASE_ELEVATION, "Undo restores the stroke")


func test_escape_cancels_the_tool() -> void:
	main._on_elevation_tool_pressed(ElevationTool.TOOL_VERTEX)
	await process_frames(1)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._unhandled_input(escape)
	await process_frames(2)
	assert_false(main.elevation_tool.is_active(), "Esc cancels the elevation tool")
	assert_false(main.placement_preview.elevation_mode_active, "and hides its preview")
