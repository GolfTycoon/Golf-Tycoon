extends GameTest
## Terrain occlusion beyond the trees: a hill nearer the camera hides the walking
## trail, the buildings, the golfers, the golf balls, the tee markers, the cups
## and their pins, the designated-area rings and the decorations behind it,
## pixel by pixel, while whatever stands above the hill or in front of it stays
## drawn. The GPU does not run headless, so the shaders' depth test is checked
## through TerrainOcclusion, the CPU twin they share their formulas with; the
## materials are checked for the uniforms the shaders read, and the shaders for
## compiling.

const BASE := TerrainGrid.BASE_ELEVATION
const DECAL_SHADER := "res://shaders/terrain_decal_occlusion.gdshader"
const FOOTPRINT_SHADER := "res://shaders/terrain_footprint_occlusion.gdshader"
const OCCLUSION := PerformanceSettings.GraphicsSetting.TREE_OCCLUSION
const GOLFER_SCENE := preload("res://scenes/entities/golfer.tscn")
const ON_THE_TILE := Vector2(0.001, 0.001)

var grid: TerrainGrid
var entities: EntityLayer
var registry: Dictionary
var _previous_preset: int
var _previous_settings: Dictionary = {}


func before_each() -> void:
	super()
	# Auto resolves to the Performance preset on small machines, and that preset
	# turns occlusion off: pin a preset that has it on, and put the player's
	# graphics settings back afterwards.
	_previous_preset = PerformanceSettings.graphics_preset
	_previous_settings.clear()
	for setting in PerformanceSettings.GRAPHICS_SETTINGS:
		_previous_settings[setting] = PerformanceSettings.get_graphics_setting(setting)
	PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.HIGH)
	GameManager.land_manager = null
	grid = make_grid(16, 16)
	# Trails are laid on rough, not on the grass a new grid starts as.
	fill_grid(grid, TerrainTypes.Type.ROUGH)
	entities = make_entity_layer(grid)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities
	registry = ContentRegistry.get_buildings()
	entities.building_registry = registry
	await process_frames(1)


func after_each() -> void:
	if _previous_preset == PerformanceSettings.GraphicsPreset.CUSTOM:
		PerformanceSettings.set_graphics_preset(PerformanceSettings.GraphicsPreset.CUSTOM)
		for setting in PerformanceSettings.GRAPHICS_SETTINGS:
			PerformanceSettings.set_graphics_setting(setting, _previous_settings[setting])
	else:
		PerformanceSettings.set_graphics_preset(_previous_preset)
	await process_frames(1)
	super()


# ---------------------------------------------------------------------------
# Switching occlusion on and off
# ---------------------------------------------------------------------------

func test_occlusion_follows_relief_and_the_graphics_setting() -> void:
	watch_signals(grid)
	assert_false(grid.terrain_occlusion_enabled(), "a flat course has nothing to hide anything behind")
	grid.set_vertex_elevation(Vector2i(3, 3), BASE + 2)
	assert_true(grid.terrain_occlusion_enabled(), "the first sculpted vertex turns it on")
	assert_signal_emitted_with_parameters(grid, "terrain_occlusion_changed", [true])
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_false(grid.terrain_occlusion_enabled(), "the graphics setting turns it off")
	assert_signal_emitted_with_parameters(grid, "terrain_occlusion_changed", [false])
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	assert_true(grid.terrain_occlusion_enabled())
	grid.set_vertex_elevation(Vector2i(3, 3), BASE)
	assert_false(grid.terrain_occlusion_enabled(), "levelling the last vertex turns it off again")
	assert_signal_emit_count(grid, "terrain_occlusion_changed", 4)


func test_a_bulk_elevation_load_switches_occlusion() -> void:
	watch_signals(grid)
	grid.deserialize_elevation({"4,4": BASE + 3})
	assert_true(grid.terrain_occlusion_enabled(), "a loaded hill turns it on")
	assert_signal_emitted_with_parameters(grid, "terrain_occlusion_changed", [true])
	grid.deserialize_elevation({})
	assert_false(grid.terrain_occlusion_enabled(), "a flat load turns it off")
	assert_signal_emit_count(grid, "terrain_occlusion_changed", 2)


# ---------------------------------------------------------------------------
# The walking trail
# ---------------------------------------------------------------------------

## A hollow along vertex rows 5-6 and a full-height ridge along rows 7-8, nearer
## the camera (a larger x + y) in the default view.
func _raise_ridge() -> void:
	for x in range(grid.grid_width + 1):
		grid.set_vertex_elevation(Vector2i(x, 5), TerrainGrid.MIN_ELEVATION)
		grid.set_vertex_elevation(Vector2i(x, 6), TerrainGrid.MIN_ELEVATION)
		grid.set_vertex_elevation(Vector2i(x, 7), TerrainGrid.MAX_ELEVATION)
		grid.set_vertex_elevation(Vector2i(x, 8), TerrainGrid.MAX_ELEVATION)


func _trail() -> WalkingPathOverlay:
	return grid._walking_path_overlay


## Lay a straight trail along row `y` from `from_x` to `to_x` inclusive.
func _lay_row(y: int, from_x: int, to_x: int) -> void:
	for x in range(from_x, to_x + 1):
		assert_true(grid.set_walking_path(Vector2i(x, y), true), "trail laid at %d,%d" % [x, y])


func test_trail_wears_the_decal_occlusion_material_only_on_relief() -> void:
	_lay_row(5, 5, 5)
	var trail := _trail()
	assert_null(trail.material, "a flat course draws the trail with no shader at all")
	grid.set_vertex_elevation(Vector2i(9, 9), BASE + 3)
	var mat := trail.material as ShaderMaterial
	assert_not_null(mat, "the first sculpt clips the trail")
	assert_eq(mat.shader, WalkingPathOverlay.TERRAIN_DECAL_OCCLUSION)
	assert_same(mat.get_shader_parameter("vertex_elevation"), grid._course_surface._elevation_texture,
		"sculpts update the ground and the trail's mask together")
	assert_eq(mat.get_shader_parameter("grid_size"), Vector2(16, 16))
	assert_eq(mat.get_shader_parameter("vertex_grid_size"), Vector2(17, 17))
	assert_eq(mat.get_shader_parameter("elevation_step_y"), TerrainGrid.ELEVATION_STEP_Y)
	grid.set_view_orientation(1)
	assert_eq(mat.get_shader_parameter("grid_origin"), grid.projection.grid_origin(),
		"the mask turns with the view")
	assert_eq(mat.get_shader_parameter("grid_axis_x"), grid.projection.axis_x())
	assert_eq(mat.get_shader_parameter("grid_axis_y"), grid.projection.axis_y())
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_null(trail.material, "the graphics setting drops the shader")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	assert_same(trail.material, mat, "and turning it back on reuses the material")


func test_trail_commands_name_the_ground_under_their_paint() -> void:
	grid.set_vertex_elevation(Vector2i(6, 6), BASE + 3)
	grid.set_vertex_elevation(Vector2i(5, 6), BASE + 1)
	_lay_row(5, 4, 6)
	var trail := _trail()
	var kinds := {}
	var misplaced := 0
	for cmd in trail.tile_draw_commands(Vector2i(5, 5), false, true):
		kinds[cmd.kind] = true
		match cmd.kind:
			"polygon":
				assert_eq(cmd.ground.size(), cmd.points.size(), "one ground point per outline point")
				for i in cmd.points.size():
					if not _projects_to(cmd.ground[i], cmd.points[i]):
						misplaced += 1
			"line":
				assert_eq(cmd.ground.size(), 2, "one ground point per end")
				if not _projects_to(cmd.ground[0], cmd.a):
					misplaced += 1
				# A blade's tip stands on its foot's ground; a band's far end
				# lies on its own.
				if cmd.ground[1] != cmd.ground[0] and not _projects_to(cmd.ground[1], cmd.b):
					misplaced += 1
			"circle":
				assert_eq(cmd.ground.size(), 1, "the ground under the centre")
				if not _projects_to(cmd.ground[0], cmd.center):
					misplaced += 1
	assert_eq(misplaced, 0, "every painted point is drawn where its ground projects")
	assert_true(kinds.has("polygon") and kinds.has("line") and kinds.has("circle"),
		"a detailed tile exercises every kind of command")


func _projects_to(ground: Vector2, local_point: Vector2) -> bool:
	return grid.grid_point_to_screen(ground).distance_to(_trail().to_global(local_point)) < 0.01


func test_trail_mesh_is_one_triangle_list_with_a_ground_uv_per_vertex() -> void:
	grid.set_vertex_elevation(Vector2i(6, 6), BASE + 2)
	_lay_row(5, 4, 6)
	var trail := _trail()
	var commands := trail.tile_draw_commands(Vector2i(5, 5), false, true)
	var mesh := trail.build_tile_mesh(commands)
	assert_gt(mesh.indices.size(), 0)
	assert_eq(mesh.indices.size() % 3, 0, "a plain triangle list")
	assert_eq(mesh.colors.size(), mesh.points.size())
	assert_eq(mesh.uvs.size(), mesh.points.size())
	var out_of_range := 0
	for index in mesh.indices:
		if index < 0 or index >= mesh.points.size():
			out_of_range += 1
	assert_eq(out_of_range, 0)
	# The commands are laid in order, so the first outline's vertices lead the
	# mesh with their own ground as UV.
	var first: WalkingPathOverlay.DrawCommand = commands[0]
	assert_eq(first.kind, "polygon")
	for i in first.points.size():
		assert_eq(mesh.points[i], first.points[i])
		assert_eq(mesh.uvs[i], first.ground[i])
		assert_eq(mesh.colors[i], first.color)
	assert_same(trail._mesh_for(Vector2i(5, 5)), trail._mesh_for(Vector2i(5, 5)),
		"a pan does not rebuild a tile's mesh")
	grid.set_vertex_elevation(Vector2i(5, 5), BASE + 1)
	assert_true(trail._mesh_cache.is_empty(), "a sculpt drops the meshes with the commands")


func test_trail_lines_and_circles_become_triangles_on_their_ground() -> void:
	var trail := _trail()
	var line := WalkingPathOverlay.DrawCommand.new()
	line.kind = "line"
	line.a = Vector2(0.0, 0.0)
	line.b = Vector2(10.0, 0.0)
	line.width = 2.0
	line.color = Color.RED
	line.ground = PackedVector2Array([Vector2(1.0, 1.0), Vector2(2.0, 1.0)])
	var mesh := trail.build_tile_mesh([line])
	# The quad draw_line() fills: two pixels thick, each end on its ground.
	assert_eq(mesh.points.size(), 4)
	assert_eq(mesh.indices, PackedInt32Array([0, 1, 2, 0, 2, 3]))
	assert_eq(mesh.uvs, PackedVector2Array([Vector2(1.0, 1.0), Vector2(2.0, 1.0),
			Vector2(2.0, 1.0), Vector2(1.0, 1.0)]))
	for point in mesh.points:
		assert_true(point.x == 0.0 or point.x == 10.0)
		assert_almost_eq(absf(point.y), 1.0, 0.0001)
	assert_eq(mesh.colors, PackedColorArray([Color.RED, Color.RED, Color.RED, Color.RED]))

	var circle := WalkingPathOverlay.DrawCommand.new()
	circle.kind = "circle"
	circle.center = grid.grid_point_to_screen(Vector2(3.0, 3.0))
	circle.radius = 4.0
	circle.color = Color.BLUE
	circle.ground = PackedVector2Array([Vector2(3.0, 3.0)])
	mesh = trail.build_tile_mesh([circle])
	# A fan round on screen whose rim lies on the ground under it.
	assert_eq(mesh.points.size(), 9, "the centre and eight rim points")
	assert_eq(mesh.indices.size(), 24)
	assert_eq(mesh.uvs[0], Vector2(3.0, 3.0))
	for i in range(1, mesh.points.size()):
		assert_almost_eq(mesh.points[i].distance_to(circle.center), 4.0, 0.0001)
		assert_almost_eq(grid.grid_point_to_screen(mesh.uvs[i]).distance_to(mesh.points[i]), 0.0, 0.001,
			"rim point %d is drawn where its ground projects" % i)


## Every vertex of one trail tile's mesh, as [ground, world] pairs: what the
## decal shader is given at each vertex.
func _trail_samples(pos: Vector2i) -> Array:
	var trail := _trail()
	var mesh := trail.build_tile_mesh(trail.tile_draw_commands(pos, false, true))
	var samples := []
	for i in mesh.points.size():
		samples.append([mesh.uvs[i], trail.to_global(mesh.points[i])])
	return samples


func _hidden_trail_samples(samples: Array) -> int:
	var hidden := 0
	for sample in samples:
		if TerrainOcclusion.hides_decal(grid, sample[0], sample[1]):
			hidden += 1
	return hidden


func test_flat_ground_hides_no_trail_paint() -> void:
	_lay_row(5, 3, 8)
	grid.set_vertex_elevation(Vector2i(15, 0), BASE + 4)
	var samples := _trail_samples(Vector2i(5, 5))
	assert_gt(samples.size(), 0)
	assert_eq(_hidden_trail_samples(samples), 0, "level ground hides none of the trail")


func test_a_ridge_in_front_hides_the_trail_behind_it_but_not_the_trail_on_or_before_it() -> void:
	# A trail in a hollow along y = 5, a full-height ridge along y = 7..8 nearer
	# the camera (a larger x + y), a trail along its top, and one in front of it.
	_lay_row(5, 2, 9)
	_lay_row(7, 2, 9)
	_lay_row(11, 2, 9)
	_raise_ridge()
	var behind := _trail_samples(Vector2i(5, 5))
	assert_gt(behind.size(), 0)
	assert_eq(_hidden_trail_samples(behind), behind.size(), "the ridge covers the trail behind it")
	assert_eq(_hidden_trail_samples(_trail_samples(Vector2i(5, 7))), 0, "the trail on the ridge stays drawn")
	assert_eq(_hidden_trail_samples(_trail_samples(Vector2i(5, 11))), 0,
		"the trail in front of the ridge stays drawn")


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------

func _architecture(building: Building) -> CanvasItem:
	return building.get_node("Visual/Architecture") as CanvasItem


func test_building_wears_the_footprint_occlusion_material_only_on_relief() -> void:
	var shop := entities.place_building("pro_shop", Vector2i(4, 4), registry)
	assert_not_null(shop)
	assert_null(_architecture(shop).material, "a flat course draws the art with no shader")
	grid.set_vertex_elevation(Vector2i(12, 12), BASE + 3)
	var mat := _architecture(shop).material as ShaderMaterial
	assert_not_null(mat, "the first sculpt clips the buildings already standing")
	assert_eq(mat.shader, Building.TERRAIN_FOOTPRINT_OCCLUSION)
	assert_same(mat.get_shader_parameter("vertex_elevation"), grid._course_surface._elevation_texture,
		"sculpts update the ground and the building's mask together")
	assert_eq(mat.get_shader_parameter("footprint_position"), Vector2(4, 4))
	assert_eq(mat.get_shader_parameter("footprint_size"), Vector2(2, 2))
	assert_eq(shop.get_footprint_rect(), Rect2(4, 4, 2, 2))
	assert_true(entities.move_building(shop, Vector2i(8, 3)))
	assert_eq(mat.get_shader_parameter("footprint_position"), Vector2(8, 3), "the mask moves with the building")
	grid.set_view_orientation(1)
	# Main repositions every placed entity on each view_rotated.
	shop.set_position_in_grid(shop.grid_position)
	assert_eq(mat.get_shader_parameter("grid_origin"), grid.projection.grid_origin(),
		"the mask turns with the view")
	assert_eq(mat.get_shader_parameter("grid_axis_x"), grid.projection.axis_x())
	# An upgrade or a restore rebuilds the art.
	shop._update_visuals()
	assert_same(_architecture(shop).material, mat, "rebuilt art is clipped the same way")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_null(_architecture(shop).material, "the graphics setting drops the shader")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	assert_same(_architecture(shop).material, mat)
	grid.set_vertex_elevation(Vector2i(12, 12), BASE)
	assert_null(_architecture(shop).material, "a course levelled flat again drops it")


func test_placement_previews_are_never_clipped() -> void:
	grid.set_vertex_elevation(Vector2i(12, 12), BASE + 3)
	var shop := entities.place_building("pro_shop", Vector2i(4, 4), registry)
	assert_not_null(_architecture(shop).material, "a building placed on a sculpted course is clipped")
	var preview := CourseArchitecture.new()
	add_child_autofree(preview)
	assert_null(preview.material, "only placed buildings carry the mask, not ghosts or catalogue art")


## Screen points across a footprint's column: every quarter-tile grid point of
## the footprint, from its foundation to well above any roof.
func _column_samples(footprint: Rect2) -> Array[Vector2]:
	var samples: Array[Vector2] = []
	for gx in range(int(footprint.size.x * 4.0) + 1):
		for gy in range(int(footprint.size.y * 4.0) + 1):
			var ground := grid.grid_point_to_screen(footprint.position + Vector2(gx, gy) * 0.25)
			for lift in [0.0, 8.0, 24.0, 60.0, 120.0]:
				samples.append(ground - Vector2(0.0, lift))
	return samples


func test_level_ground_hides_no_building_pixel() -> void:
	var shop := entities.place_building("pro_shop", Vector2i(4, 4), registry)
	grid.set_vertex_elevation(Vector2i(15, 1), BASE + 4)
	assert_eq(_hidden_column_samples(shop.get_footprint_rect()), 0,
		"the building's own level foundation never cuts into it")


func test_a_raised_foundation_is_not_cut_by_the_slope_around_it() -> void:
	# A building on a pad: its foundation is level and the ground falls away
	# from every edge, so nothing nearer the camera rises over any of its pixels.
	for x in range(4, 7):
		for y in range(4, 7):
			grid.set_vertex_elevation(Vector2i(x, y), BASE + 2)
	var shop := entities.place_building("pro_shop", Vector2i(4, 4), registry)
	assert_not_null(shop)
	var footprint := shop.get_footprint_rect()
	assert_eq(_hidden_column_samples(footprint), 0)


func test_a_hill_behind_a_building_hides_none_of_it() -> void:
	var shop := entities.place_building("pro_shop", Vector2i(4, 4), registry)
	# A full-height mound just behind the shop's back corner.
	for vertex in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]:
		grid.set_vertex_elevation(vertex, TerrainGrid.MAX_ELEVATION)
	assert_eq(_hidden_column_samples(shop.get_footprint_rect()), 0,
		"a building in front of a hill is drawn whole")


func _hidden_column_samples(footprint: Rect2) -> int:
	var hidden := 0
	for world in _column_samples(footprint):
		if TerrainOcclusion.hides_footprint(grid, footprint, world):
			hidden += 1
	return hidden


func test_a_hill_in_front_hides_the_low_wall_but_not_the_wall_above_it() -> void:
	var shop := entities.place_building("pro_shop", Vector2i(4, 4), registry)
	# A full-height mound just in front of the shop's front corner.
	for vertex in [Vector2i(7, 7), Vector2i(8, 7), Vector2i(7, 8), Vector2i(8, 8)]:
		grid.set_vertex_elevation(vertex, TerrainGrid.MAX_ELEVATION)
	var footprint := shop.get_footprint_rect()
	var front_corner := grid.grid_point_to_screen(footprint.end)
	assert_true(TerrainOcclusion.hides_footprint(grid, footprint, front_corner),
		"the mound covers the foot of the front corner")
	assert_true(TerrainOcclusion.hides_footprint(grid, footprint, front_corner - Vector2(0.0, 10.0)),
		"and the wall just above it")
	assert_false(TerrainOcclusion.hides_footprint(grid, footprint, front_corner - Vector2(0.0, 40.0)),
		"the wall above the mound's top stays drawn")
	assert_false(TerrainOcclusion.hides_footprint(grid, footprint, front_corner - Vector2(0.0, 120.0)),
		"and so does the roof")
	var left_corner := grid.grid_point_to_screen(Vector2(footprint.position.x, footprint.end.y))
	assert_false(TerrainOcclusion.hides_footprint(grid, footprint, left_corner),
		"a corner with no hill before it stays drawn down to the ground")
	# A click lands on what is drawn there.
	assert_true(shop.terrain_hides_point(front_corner), "a click on the mound does not select the shop")
	assert_false(shop.terrain_hides_point(front_corner - Vector2(0.0, 40.0)))
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_false(shop.terrain_hides_point(front_corner), "with occlusion off the whole shop answers clicks")


# ---------------------------------------------------------------------------
# Golfers
# ---------------------------------------------------------------------------

## A golfer with their feet drawn on the grid point `ground` - placed by screen
## position, the way the game places one - and nothing walking them on. One
## whose skin is still to be chosen is drawn with the polygon body.
func _spawn_golfer(ground: Vector2, parent: Node = null, skin_to_come := false) -> Golfer:
	var golfer := GOLFER_SCENE.instantiate() as Golfer
	golfer.defer_skin_setup = skin_to_come
	if parent == null:
		add_child_autofree(golfer)
	else:
		parent.add_child(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	_place(golfer, ground)
	return golfer


func _place(golfer: Golfer, ground: Vector2) -> void:
	golfer.global_position = grid.grid_point_to_screen(ground)


func _golfer_material(golfer: Golfer) -> ShaderMaterial:
	return golfer.visual.material as ShaderMaterial


## Points of a golfer's figure, from the soles to the top of the cap and a
## shoulder's width to either side.
func _figure_samples(golfer: Golfer) -> Array[Vector2]:
	var samples: Array[Vector2] = []
	for height in [0.0, 6.0, 12.0, 20.0, 28.0, 36.0]:
		for side in [-6.0, 0.0, 6.0]:
			samples.append(golfer.global_position + Vector2(side, -height))
	return samples


func _name_tag_shown(golfer: Golfer) -> bool:
	return (golfer.get_node("InfoContainer") as CanvasItem).visible


func _hidden_figure_samples(golfer: Golfer) -> int:
	var hidden := 0
	for sample in _figure_samples(golfer):
		if golfer.terrain_hides_point(sample):
			hidden += 1
	return hidden


## Every part of the drawn golfer is clipped by the one material on Visual.
func _assert_parts_clipped(golfer: Golfer, what: String) -> void:
	var parts := golfer.visual.find_children("*", "CanvasItem", true, false)
	assert_gt(parts.size(), 0, what)
	for part in parts:
		assert_true((part as CanvasItem).use_parent_material, "%s: %s is clipped with the golfer" % [what, part.name])


func test_golfer_wears_the_sprite_occlusion_material_only_on_relief() -> void:
	var golfer := _spawn_golfer(Vector2(4.5, 4.5))
	var plain := _spawn_golfer(Vector2(8.5, 4.5), null, true)
	assert_null(plain.sprite_node(), "precondition: drawn with the polygon body")
	assert_null(golfer.visual.material, "a flat course draws the golfer with no shader")
	assert_eq(golfer.ground_point(), TerrainGrid.INVALID_GRID_POINT, "and tracks no ground under them")
	grid.set_vertex_elevation(Vector2i(12, 12), BASE + 3)
	var mat := _golfer_material(golfer)
	assert_not_null(mat, "the first sculpt clips the golfers already out on the course")
	if mat == null:
		return
	assert_eq(mat.shader, Golfer.TERRAIN_SPRITE_OCCLUSION, "the tree's per-pixel clip")
	assert_same(mat.get_shader_parameter("vertex_elevation"), grid._course_surface._elevation_texture,
		"sculpts update the ground and the golfer's mask together")
	assert_eq(mat.get_shader_parameter("occlusion_epsilon"), TerrainOcclusion.GOLFER_EPSILON)
	assert_eq(mat.get_shader_parameter("ground_offset"), Vector2.ZERO)
	assert_eq(mat.get_shader_parameter("ground_grid"), Vector2(4.5, 4.5), "anchored to the ground they stand on")
	assert_eq(golfer.ground_point(), Vector2(4.5, 4.5))
	_assert_parts_clipped(golfer, "the skin sprite")
	assert_same(golfer._expression.material, mat, "and so are the glints of a celebration")
	assert_not_null(plain.visual.material)
	_assert_parts_clipped(plain, "the polygon body")
	var trim := Polygon2D.new()
	golfer.visual.add_child(trim)
	assert_true(trim.use_parent_material, "a part dressed on later is clipped too")
	plain.finish_spawn_setup()
	assert_not_null(plain.sprite_node(), "precondition: the chosen skin's sprite is on")
	_assert_parts_clipped(plain, "the skin put on later")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_null(golfer.visual.material, "the graphics setting turns it off")
	assert_eq(golfer.ground_point(), TerrainGrid.INVALID_GRID_POINT)
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	assert_same(_golfer_material(golfer), mat, "turning it back on reuses the golfer's material")
	grid.set_vertex_elevation(Vector2i(12, 12), BASE)
	assert_null(golfer.visual.material, "levelling the course turns it off again")


func test_a_golfer_drawn_on_another_canvas_is_never_clipped() -> void:
	_raise_ridge()
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	var portrait := _spawn_golfer(Vector2(5.5, 5.5), viewport)
	assert_true(grid.terrain_occlusion_enabled())
	assert_null(portrait.visual.material, "the skin preview and the round screen's portrait are not on the course")
	assert_eq(portrait.ground_point(), TerrainGrid.INVALID_GRID_POINT)
	assert_false(portrait.terrain_hides_point(portrait.global_position))


func test_ray_crossings_lead_with_the_surface_the_pixel_shows() -> void:
	var probe := grid.grid_point_to_screen(Vector2(5.5, 5.5))
	assert_eq(TerrainOcclusion.ray_crossings(grid, probe).size(), 1, "level ground meets a pixel's ray once")
	_raise_ridge()
	probe = grid.grid_point_to_screen(Vector2(5.5, 5.5))
	var crossings := TerrainOcclusion.ray_crossings(grid, probe)
	assert_eq(crossings.size(), 3, "the ray through the hollow meets the ridge's two slopes and the hollow floor")
	for i in range(1, crossings.size()):
		assert_lt(crossings[i], crossings[i - 1], "the front-most first")
	assert_almost_eq(TerrainOcclusion.point_on_ray(grid, probe, crossings[0]), grid.screen_to_grid_point(probe),
		ON_THE_TILE, "the first is the surface the pixel shows")
	assert_almost_eq(TerrainOcclusion.point_on_ray(grid, probe, crossings[crossings.size() - 1]),
		Vector2(5.5, 5.5), ON_THE_TILE, "the last is the hollow floor behind the ridge")
	assert_eq(TerrainOcclusion.standing_point(grid, probe), Vector2(5.5, 5.5),
		"a figure placed on a tile stands on the tile, not on the ridge drawn over it")
	var off_course := Vector2(-5000.0, -5000.0)
	assert_eq(TerrainOcclusion.ray_crossings(grid, off_course).size(), 0, "a pixel off the course meets no ground")
	assert_eq(TerrainOcclusion.standing_point(grid, off_course), TerrainGrid.INVALID_GRID_POINT)


func test_a_ridge_in_front_hides_the_golfer_behind_it_but_not_one_on_or_before_it() -> void:
	_raise_ridge()
	var behind := _spawn_golfer(Vector2(5.5, 5.5))
	var on_top := _spawn_golfer(Vector2(9.5, 7.5))
	var before := _spawn_golfer(Vector2(5.5, 11.5))
	assert_eq(behind.ground_point(), Vector2(5.5, 5.5), "the golfer behind stands in the hollow")
	assert_gt(grid.screen_to_grid_point(behind.global_position).distance_to(Vector2(5.5, 5.5)), 1.0,
		"while the pixel under their feet shows the ridge")
	var samples := _figure_samples(behind).size()
	assert_eq(_hidden_figure_samples(behind), samples, "the ridge covers the golfer behind it, soles to cap")
	assert_false(_name_tag_shown(behind), "and their name tag with them, rather than leaving it on the hillside")
	assert_eq(_hidden_figure_samples(on_top), 0, "the golfer on the ridge stays drawn")
	assert_eq(_hidden_figure_samples(before), 0, "and so does the golfer in front of it")
	assert_true(_name_tag_shown(on_top) and _name_tag_shown(before), "name tags and all")
	assert_eq(_golfer_material(on_top).get_shader_parameter("ground_grid"), Vector2(9.5, 7.5))
	assert_eq(_golfer_material(before).get_shader_parameter("ground_grid"), Vector2(5.5, 11.5))
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_eq(_hidden_figure_samples(behind), 0, "with occlusion off the golfer is drawn over the ridge")
	assert_true(_name_tag_shown(behind), "name tag too")


func test_a_golfer_on_ground_rising_toward_the_camera_keeps_their_whole_name_tag() -> void:
	# A gentle ramp, one level a tile, rising toward the camera.
	for y in range(10, 15):
		for x in range(grid.grid_width + 1):
			grid.set_vertex_elevation(Vector2i(x, y), BASE + y - 10)
	var climber := _spawn_golfer(Vector2(5.5, 11.5))
	assert_eq(_hidden_figure_samples(climber), 0, "nothing stands between the golfer and the camera")
	# The tag hangs under the feet, where the ramp in front of them is drawn: a
	# tag clipped like the figure would lose its lower rows to the ramp.
	assert_true(TerrainOcclusion.hides_standing(grid, climber.ground_point(),
		climber.global_position + Vector2(0.0, 15.0)), "precondition: the ramp is drawn where the tag hangs")
	assert_true(_name_tag_shown(climber), "the tag is hidden only with the feet, and whole")


func test_a_golfer_walking_behind_the_ridge_stays_behind_it() -> void:
	_raise_ridge()
	var walker := _spawn_golfer(Vector2(2.5, 5.5))
	var mat := _golfer_material(walker)
	var worst_drift := 0.0
	var nearest_front := INF
	var hidden_steps := 0
	var tag_shown_steps := 0
	var steps := 50
	for step in range(1, steps + 1):
		var ground := Vector2(2.5 + step * 0.13, 5.5 + 0.2 * sin(step * 0.5))
		_place(walker, ground)
		await process_frames(1)
		# The frame's transform notification has found their footing again.
		var anchor: Vector2 = mat.get_shader_parameter("ground_grid")
		worst_drift = maxf(worst_drift, anchor.distance_to(ground))
		nearest_front = minf(nearest_front, grid.screen_to_grid_point(walker.global_position).distance_to(ground))
		if walker.terrain_hides_point(walker.global_position - Vector2(0.0, 12.0)):
			hidden_steps += 1
		if _name_tag_shown(walker):
			tag_shown_steps += 1
	assert_gt(nearest_front, 1.0, "every step of the walk is drawn over by the ridge")
	assert_lt(worst_drift, 0.001, "and the golfer is anchored to the hollow at every step, never to the ridge")
	assert_eq(hidden_steps, steps, "so the ridge hides them the whole way")
	assert_eq(tag_shown_steps, 0, "name tag and all")


func _click(golfer: Golfer, world: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = golfer.get_canvas_transform() * world
	golfer._on_click_area_input_event(golfer.get_viewport(), event, 0)


func test_a_click_on_the_ridge_does_not_select_the_golfer_behind_it() -> void:
	_raise_ridge()
	var behind := _spawn_golfer(Vector2(5.5, 5.5))
	var before := _spawn_golfer(Vector2(5.5, 11.5))
	watch_signals(behind)
	watch_signals(before)
	_click(behind, behind.global_position - Vector2(0.0, 12.0))
	assert_signal_not_emitted(behind, "golfer_selected", "the ridge drawn over the golfer takes the click")
	# A golfer in plain sight answers.
	_click(before, before.global_position - Vector2(0.0, 12.0))
	assert_signal_emitted_with_parameters(before, "golfer_selected", [before])
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	_click(behind, behind.global_position - Vector2(0.0, 12.0))
	assert_signal_emitted(behind, "golfer_selected", "with occlusion off the whole golfer answers clicks")


func test_the_anchor_follows_the_drawn_feet_the_sculpted_ground_and_the_view() -> void:
	grid.set_vertex_elevation(Vector2i(0, 15), BASE + 3)
	var golfer := _spawn_golfer(Vector2(10.5, 10.5))
	var mat := _golfer_material(golfer)
	# Golfers bunched together are drawn a little apart (see
	# GolferManager._update_visual_offsets()): the shader stands on the ground
	# under the drawn feet, the golfer on the ground where the game put them.
	golfer.visual_offset = Vector2(12.0, 0.0)
	await process_frames(1)
	var anchor: Vector2 = mat.get_shader_parameter("ground_grid")
	assert_almost_eq(grid.grid_point_to_screen(anchor), golfer.global_position + Vector2(12.0, 0.0),
		Vector2(0.01, 0.01), "the clip is anchored under the drawn feet")
	assert_eq(golfer.ground_point(), Vector2(10.5, 10.5), "the golfer still stands where they were put")
	golfer.visual_offset = Vector2.ZERO
	await process_frames(1)
	assert_eq(mat.get_shader_parameter("ground_grid"), Vector2(10.5, 10.5))
	# A sculpt lifts the ground under the golfer, who keeps their place on screen.
	for vertex in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11), Vector2i(11, 11)]:
		grid.set_vertex_elevation(vertex, BASE + 2)
	await process_frames(1)
	var ground := golfer.ground_point()
	assert_ne(ground, Vector2(10.5, 10.5), "the old footing is buried under the new ground")
	assert_almost_eq(grid.grid_point_to_screen(ground), golfer.global_position, Vector2(0.01, 0.01),
		"they stand on the ground now under their feet")
	assert_eq(mat.get_shader_parameter("ground_grid"), ground)
	# A turn re-projects the mask, and main.gd moves the golfer to where their
	# ground is drawn now.
	grid.set_view_orientation(1)
	assert_eq(mat.get_shader_parameter("grid_origin"), grid.projection.grid_origin(), "the mask turns with the view")
	assert_eq(mat.get_shader_parameter("grid_axis_x"), grid.projection.axis_x())
	assert_eq(mat.get_shader_parameter("grid_axis_y"), grid.projection.axis_y())
	_place(golfer, ground)
	await process_frames(1)
	assert_almost_eq(golfer.ground_point(), ground, ON_THE_TILE, "and they stand on the same ground in the new view")
	grid.set_view_orientation(0)


# ---------------------------------------------------------------------------
# Golf balls
# ---------------------------------------------------------------------------

## A ball on the course grid, as BallManager makes one, that nothing moves on
## but the test.
func _spawn_ball(parent: Node = null) -> Ball:
	var ball := Ball.new()
	ball.set_terrain_grid(grid)
	if parent == null:
		add_child_autofree(ball)
	else:
		parent.add_child(ball)
	ball.set_process(false)
	return ball


func _ball_material(ball: Ball) -> ShaderMaterial:
	return ball.material as ShaderMaterial


## Points of a ball's art: the ball's top, sides, centre and bottom, and the
## foot of its contact shadow.
func _ball_samples(ball: Ball) -> Array[Vector2]:
	var centre := ball.global_position
	var r := Ball.BALL_RADIUS * 0.9
	var samples: Array[Vector2] = [centre + Vector2(0.0, -r), centre + Vector2(-r, 0.0), centre,
		centre + Vector2(r, 0.0), centre + Vector2(0.0, r)]
	samples.append(centre + Vector2(Ball.SHADOW_OFFSET.x, Ball.SHADOW_OFFSET.y + Ball.SHADOW_RADII.y * 0.9)
		* Ball.BALL_RADIUS)
	return samples


func _hidden_ball_samples(ball: Ball) -> int:
	var hidden := 0
	for sample in _ball_samples(ball):
		if ball.terrain_hides_point(sample):
			hidden += 1
	return hidden


func _assert_ball_parts_clipped(ball: Ball, what: String) -> void:
	var parts := ball.find_children("*", "CanvasItem", true, false)
	assert_gt(parts.size(), 2, what)
	for part in parts:
		assert_true((part as CanvasItem).use_parent_material, "%s: %s is clipped with the ball" % [what, part.name])


func test_ball_wears_the_sprite_occlusion_material_only_on_relief() -> void:
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(4, 4))
	assert_null(ball.material, "a flat course draws the ball with no shader")
	grid.set_vertex_elevation(Vector2i(12, 12), BASE + 3)
	var mat := _ball_material(ball)
	assert_not_null(mat, "the first sculpt clips the balls already out on the course")
	if mat == null:
		return
	assert_eq(mat.shader, Ball.TERRAIN_SPRITE_OCCLUSION, "the tree's per-pixel clip")
	assert_same(mat.get_shader_parameter("vertex_elevation"), grid._course_surface._elevation_texture,
		"sculpts update the ground and the ball's mask together")
	assert_eq(mat.get_shader_parameter("occlusion_epsilon"), TerrainOcclusion.BALL_EPSILON)
	assert_eq(mat.get_shader_parameter("ground_grid"), Vector2(4.5, 4.5), "stood on the ground it rests on")
	assert_almost_eq(mat.get_shader_parameter("ground_offset"), Vector2(0.0, Ball.OCCLUSION_FOOT),
		ON_THE_TILE, "and measured from the foot of its contact shadow")
	_assert_ball_parts_clipped(ball, "a ball at rest")
	# Every state draws the ball afresh.
	ball.start_flight(Vector2i(4, 4), Vector2i(8, 4), 1.0)
	_assert_ball_parts_clipped(ball, "a ball in flight")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_null(ball.material, "the graphics setting turns it off")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	assert_same(_ball_material(ball), mat, "turning it back on reuses the ball's material")
	grid.set_vertex_elevation(Vector2i(12, 12), BASE)
	assert_null(ball.material, "levelling the course turns it off again")


func test_the_balls_clip_follows_sculpts_and_view_turns() -> void:
	_raise_ridge()
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(5, 11))
	var mat := _ball_material(ball)
	assert_almost_eq(mat.get_shader_parameter("ground_offset"), Vector2(0.0, Ball.OCCLUSION_FOOT), ON_THE_TILE)
	# A sculpt raises the ground under the resting ball, which keeps its place on
	# screen: it is taken to be on the new ground, never buried in it.
	for vertex in [Vector2i(5, 11), Vector2i(6, 11), Vector2i(5, 12), Vector2i(6, 12)]:
		grid.set_vertex_elevation(vertex, BASE + 2)
	await process_frames(1)
	assert_almost_eq(mat.get_shader_parameter("ground_offset"), Vector2(0.0, Ball.OCCLUSION_FOOT + 20.0),
		ON_THE_TILE, "the clip is brought up to date before the frame is drawn")
	assert_eq(_hidden_ball_samples(ball), 0)
	# A turn re-projects the mask; main.gd then carries the ball to where its
	# ground is drawn now, and the clip follows each move as it is made.
	grid.set_view_orientation(1)
	assert_eq(mat.get_shader_parameter("grid_origin"), grid.projection.grid_origin(), "the mask turns with the view")
	assert_eq(mat.get_shader_parameter("grid_axis_x"), grid.projection.axis_x())
	assert_eq(mat.get_shader_parameter("grid_axis_y"), grid.projection.axis_y())
	var lie := grid.grid_point_to_screen(ball.rest_ground)
	ball.global_position = lie + Vector2(0.0, 30.0)
	assert_almost_eq(mat.get_shader_parameter("ground_offset"), Vector2(0.0, Ball.OCCLUSION_FOOT + 30.0),
		ON_THE_TILE, "a resting ball moved from outside is followed at once, and never taken to be underground")
	ball.global_position = lie
	assert_almost_eq(mat.get_shader_parameter("ground_offset"), Vector2(0.0, Ball.OCCLUSION_FOOT), ON_THE_TILE)
	assert_eq(mat.get_shader_parameter("ground_grid"), Vector2(5.5, 11.5), "it still lies on the same ground")
	assert_eq(_hidden_ball_samples(ball), 0)
	grid.set_view_orientation(0)


func test_a_ball_drawn_on_another_canvas_is_never_clipped() -> void:
	_raise_ridge()
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	var ball := _spawn_ball(viewport)
	ball.set_position_in_grid(Vector2i(5, 5))
	assert_null(ball.material)
	assert_false(ball.terrain_hides_point(ball.global_position))


func test_a_ridge_hides_a_resting_ball_behind_it_but_not_one_on_or_before_it() -> void:
	_raise_ridge()
	var behind := _spawn_ball()
	behind.set_position_in_grid(Vector2i(5, 5))
	var on_top := _spawn_ball()
	on_top.set_position_in_grid(Vector2i(9, 7))
	var before := _spawn_ball()
	before.set_position_in_grid(Vector2i(5, 11))
	assert_gt(grid.screen_to_grid_point(behind.global_position).distance_to(Vector2(5.5, 5.5)), 1.0,
		"precondition: the pixel the ball behind is drawn on shows the ridge")
	assert_eq(_hidden_ball_samples(behind), _ball_samples(behind).size(),
		"the ridge covers the ball behind it, contact shadow and all")
	assert_eq(_hidden_ball_samples(on_top), 0, "the ball on the ridge stays drawn")
	assert_eq(_hidden_ball_samples(before), 0, "and so does the ball in front of it")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_eq(_hidden_ball_samples(behind), 0, "with occlusion off the ball is drawn over the ridge")


func test_a_ball_flying_over_the_ridge_is_hidden_once_it_drops_behind_it() -> void:
	_raise_ridge()
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(5, 12))
	var struck := Vector2(5.5, 12.5)
	var carry := Vector2(5.5, 5.5)
	var carry_screen := grid.grid_point_to_screen(carry)
	assert_ne(grid.screen_to_grid(carry_screen), Vector2i(5, 5), "precondition: the carry's pixel shows the ridge")
	ball.start_flight_screen_with_arc(grid.grid_point_to_screen(struck), carry_screen, 1.0, Vector2.ZERO,
		struck, carry)
	ball.flight_max_height = 150.0
	var shown_on_the_way_up := 0
	var hidden_coming_down := 0
	for step in range(1, 20):
		ball._process_flight(0.05)
		var hidden := ball.terrain_hides_point(ball.global_position)
		if step <= 16 and not hidden:
			shown_on_the_way_up += 1
		elif step >= 18 and hidden:
			hidden_coming_down += 1
	assert_eq(shown_on_the_way_up, 16, "the ball is in view as it climbs and clears the ridge")
	assert_eq(hidden_coming_down, 2, "and hidden as it comes down behind it")
	# Come down low, like a chip, so no landing burst outlives the test.
	ball.flight_max_height = 0.0
	ball._process_flight(0.05)
	assert_eq(ball.ball_state, Ball.BallState.AT_REST)
	assert_eq(ball.rest_ground, carry, "it rests on the ground it came down on")
	assert_eq(ball.grid_position, Vector2i(5, 5), "in the hollow's tile, not the ridge's drawn over it")
	assert_eq(_hidden_ball_samples(ball), _ball_samples(ball).size(), "out of sight")


## A crown across the course along vertex row 8, two levels up, back to base at
## rows 6 and 10.
func _raise_crown() -> void:
	for x in range(grid.grid_width + 1):
		grid.set_vertex_elevation(Vector2i(x, 7), BASE + 1)
		grid.set_vertex_elevation(Vector2i(x, 8), BASE + 2)
		grid.set_vertex_elevation(Vector2i(x, 9), BASE + 1)


## Vertex rows from `first_row` on rising toward the camera (at the default
## facing) `levels` a tile from `from_level`, as far as the course's top level.
func _raise_ramp(first_row: int, levels: int, from_level: int = BASE) -> void:
	for y in range(first_row, grid.grid_height + 1):
		for x in range(grid.grid_width + 1):
			grid.set_vertex_elevation(Vector2i(x, y),
				mini(from_level + (y - first_row) * levels, TerrainGrid.MAX_ELEVATION))


func test_a_putt_over_a_crowned_green_rolls_over_the_crown_in_view() -> void:
	_raise_crown()
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(5, 11))
	var from := Vector2(5.5, 11.5)
	var to := Vector2(5.5, 4.5)
	var from_screen := grid.grid_point_to_screen(from)
	var to_screen := grid.grid_point_to_screen(to)
	assert_lt(grid.grid_point_to_screen(Vector2(5.5, 8.0)).y, from_screen.lerp(to_screen, 0.5).y - 10.0,
		"precondition: a straight line across the green runs under its crown")
	ball.start_flight_screen(from_screen, to_screen, 1.0, true, from, to)
	var hidden_steps := 0
	var worst_off_the_green := 0.0
	for step in range(1, 20):
		ball._process_flight(0.05)
		if ball.terrain_hides_point(ball.global_position):
			hidden_steps += 1
		worst_off_the_green = maxf(worst_off_the_green,
			ball.global_position.distance_to(grid.grid_point_to_screen(ball.ground_point())))
	assert_lt(worst_off_the_green, 0.01, "the putt rolls on the green, up and over the crown")
	assert_eq(hidden_steps, 0, "so it is in view the whole way")


func test_a_ball_rolling_out_over_the_crown_rolls_on_the_ground_in_view() -> void:
	_raise_crown()
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(5, 12))
	var struck := Vector2(5.5, 12.5)
	var carry := Vector2(5.5, 11.5)
	var rest := Vector2(5.5, 4.5)
	ball.set_rollout(grid.grid_point_to_screen(rest), 1.0, rest)
	ball.start_flight_screen_with_arc(grid.grid_point_to_screen(struck), grid.grid_point_to_screen(carry), 0.2,
		Vector2.ZERO, struck, carry)
	ball.flight_max_height = 8.0  # A chip: no landing burst to outlive the test.
	for step in range(4):
		ball._process_flight(0.05)
	assert_eq(ball.ball_state, Ball.BallState.ROLLING, "precondition: the chip has landed and rolls on")
	var hidden_steps := 0
	var worst_off_the_green := 0.0
	for step in range(1, 20):
		ball._process_rolling(0.05)
		if ball.terrain_hides_point(ball.global_position):
			hidden_steps += 1
		worst_off_the_green = maxf(worst_off_the_green,
			ball.global_position.distance_to(grid.grid_point_to_screen(ball.ground_point())))
	assert_lt(worst_off_the_green, 0.01, "the ball rolls on the ground, up and over the crown")
	assert_eq(hidden_steps, 0, "in view the whole way")


func test_a_low_chip_over_the_crown_flies_over_it_in_view() -> void:
	_raise_crown()
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(5, 11))
	var struck := Vector2(5.5, 11.5)
	var carry := Vector2(5.5, 4.5)
	ball.start_flight_screen_with_arc(grid.grid_point_to_screen(struck), grid.grid_point_to_screen(carry), 1.0,
		Vector2.ZERO, struck, carry)
	ball.flight_max_height = 8.0
	var hidden_steps := 0
	for step in range(1, 20):
		ball._process_flight(0.05)
		if ball.terrain_hides_point(ball.global_position):
			hidden_steps += 1
		if step == 10:
			assert_gt(ball.global_position.y, grid.grid_point_to_screen(ball.ground_point()).y + 10.0,
				"precondition: the arc is drawn over a straight track, lower than the crown it crosses")
	assert_eq(hidden_steps, 0, "the ball is taken to clear the crown, not to bore through it")


func test_a_ball_on_a_slope_facing_the_camera_keeps_its_contact_shadow() -> void:
	# Two levels a tile, then the steepest whole-level slope that still faces
	# the camera: three, from the lowest level so the ball's shadow lies on it.
	for levels in [2, 3]:
		_raise_ramp(10, levels, BASE if levels == 2 else TerrainGrid.MIN_ELEVATION)
		var ball := _spawn_ball()
		ball.set_position_in_grid(Vector2i(5, 11))
		var shadow_foot: Vector2 = _ball_samples(ball).back()
		assert_true(TerrainOcclusion.hides_ball(grid, ball.rest_ground, Ball.OCCLUSION_FOOT, shadow_foot),
			"precondition: measured as if on level ground, the slope in front would cut the shadow (%d)" % levels)
		assert_eq(_hidden_ball_samples(ball), 0, "the ball and its shadow on the slope stay whole (%d)" % levels)
		assert_true(ball.terrain_hides_point(ball.global_position + Vector2(0.0, 12.0)),
			"while the slope drawn further down the screen is still in front of it (%d)" % levels)
		ball.free()


func test_contact_reach_finds_the_ground_under_the_shadows_foot() -> void:
	var foot := Ball.OCCLUSION_FOOT
	assert_almost_eq(TerrainOcclusion.contact_reach(grid, Vector2(5.5, 11.5), foot), foot, 0.0001,
		"on level ground the shadow's foot is just under the ball")
	# One level a tile rises 10 px over the 32 px of a tile's diagonal.
	_raise_ramp(10, 1)
	assert_almost_eq(TerrainOcclusion.contact_reach(grid, Vector2(5.5, 11.5), foot), foot / (1.0 - 10.0 / 32.0),
		0.001, "a slope rising toward the camera carries it out to ground nearer the viewer")
	grid.set_view_orientation(2)
	assert_almost_eq(TerrainOcclusion.contact_reach(grid, Vector2(5.5, 11.5), foot), foot, 0.0001,
		"the same slope falling away toward the camera does not")
	grid.set_view_orientation(0)
	_raise_ramp(10, 3, TerrainGrid.MIN_ELEVATION)
	assert_almost_eq(TerrainOcclusion.contact_reach(grid, Vector2(5.5, 11.5), foot), foot / (1.0 - 30.0 / 32.0),
		0.001, "however steep the slope, while it faces the camera")
	# Four levels a tile turns the slope's face away from the camera: the ground
	# in front folds over a ball on it.
	_raise_ramp(10, 4)
	assert_eq(TerrainOcclusion.contact_reach(grid, Vector2(5.5, 10.5), foot), foot)
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(5, 10))
	assert_eq(_hidden_ball_samples(ball), _ball_samples(ball).size(),
		"so the ball on that face is hidden by the ground above it")


func test_a_ball_rolling_out_behind_the_ridge_stays_behind_it() -> void:
	_raise_ridge()
	var ball := _spawn_ball()
	ball.set_position_in_grid(Vector2i(2, 5))
	var struck := Vector2(2.5, 5.5)
	var carry := Vector2(3.5, 5.5)
	var rest := Vector2(8.5, 5.25)
	ball.set_rollout(grid.grid_point_to_screen(rest), 1.0, rest)
	ball.start_flight_screen_with_arc(grid.grid_point_to_screen(struck), grid.grid_point_to_screen(carry), 0.2,
		Vector2.ZERO, struck, carry)
	ball.flight_max_height = 8.0  # A chip: no landing burst to outlive the test.
	for step in range(4):
		ball._process_flight(0.05)
	assert_eq(ball.ball_state, Ball.BallState.ROLLING, "precondition: the chip has landed and rolls on")
	var hidden_steps := 0
	var worst_off_the_hollow := 0.0
	for step in range(1, 20):
		ball._process_rolling(0.05)
		if _hidden_ball_samples(ball) == _ball_samples(ball).size():
			hidden_steps += 1
		worst_off_the_hollow = maxf(worst_off_the_hollow, absf(ball.ground_point().y - 5.5) - 0.25)
	assert_lt(worst_off_the_hollow, 0.001, "the ball rolls along the hollow")
	assert_eq(hidden_steps, 19, "behind the ridge the whole way")
	ball._process_rolling(0.05)
	assert_eq(ball.rest_ground, rest, "and comes to rest on the ground the roll was played to")
	assert_eq(ball.grid_position, Vector2i(8, 5))


func test_a_shots_ball_comes_down_on_the_ground_the_shot_landed_on() -> void:
	_raise_ridge()
	var golfers := make_golfer_manager()
	var balls := BallManager.new()
	golfers.get_parent().add_child(balls)
	balls.set_terrain_grid(grid)
	var golfer := GOLFER_SCENE.instantiate() as Golfer
	golfer.golfer_id = 77
	golfers.get_parent().get_node("Entities/Golfers").add_child(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	golfers.join_course(golfer)
	# Struck in front of the ridge, carried into the hollow behind it, rolled on.
	var struck := Vector2(5.5, 12.5)
	var carry := Vector2(5.2, 5.6)
	var rest := Vector2(6.1, 5.4)
	var carry_screen := grid.grid_point_to_screen(carry)
	assert_gt(grid.screen_to_grid_point(carry_screen).distance_to(carry), 1.0,
		"precondition: the carry's pixel shows the ridge")
	golfer._record_shot_ground(struck - Vector2(0.5, 0.5), carry - Vector2(0.5, 0.5), rest - Vector2(0.5, 0.5))
	balls._on_ball_shot_precise(77, grid.grid_point_to_screen(struck), grid.grid_point_to_screen(rest), 120,
		carry_screen)
	var ball := balls.get_ball(77)
	assert_eq(ball.flight_start_ground, struck)
	assert_eq(ball.flight_end_ground, carry, "the ball comes down in the hollow the shot landed in")
	assert_eq(ball.roll_end_ground, rest, "and rolls on to where it came to rest")
	# Without a record the ball has only the screen to go by, and takes the
	# surface the pixel shows - as every ball did before.
	balls._on_ball_shot_precise(78, grid.grid_point_to_screen(struck), grid.grid_point_to_screen(rest), 120,
		carry_screen)
	assert_almost_eq(balls.get_ball(78).flight_end_ground, grid.screen_to_grid_point(carry_screen), ON_THE_TILE)


# ---------------------------------------------------------------------------
# Ground paint (GroundDecal)
# ---------------------------------------------------------------------------

func test_a_ground_decal_line_is_shaped_as_the_engine_draws_one() -> void:
	var line := GroundDecal.new()
	line.add_polyline(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), Color.RED, 2.0, false,
			PackedVector2Array([Vector2(1, 1), Vector2(2, 1)]))
	# The quad draw_polyline() fills: two pixels thick, each end on its ground.
	assert_eq(line.points.size(), 4)
	assert_eq(line.indices.size(), 6, "two triangles")
	for i in line.points.size():
		assert_almost_eq(absf(line.points[i].y), 1.0, 0.0001)
		assert_eq(line.uvs[i], Vector2(1, 1) if line.points[i].x == 0.0 else Vector2(2, 1))
	# Antialiased, it fades out over the engine's feather along both edges and
	# past both ends.
	var soft := GroundDecal.new()
	soft.add_polyline(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), Color.RED, 2.0, true)
	var extent := Rect2(soft.points[0], Vector2.ZERO)
	var faded := 0
	for i in soft.points.size():
		extent = extent.expand(soft.points[i])
		if soft.colors[i].a == 0.0:
			faded += 1
		elif absf(soft.points[i].y) > 1.0001 or soft.points[i].x < 0.0 or soft.points[i].x > 10.0:
			fail_test("only the line itself is drawn opaque, at %s" % soft.points[i])
	assert_almost_eq(extent.position, Vector2(-GroundDecal.FEATHER, -1.0 - GroundDecal.FEATHER), Vector2.ONE * 0.0001)
	assert_almost_eq(extent.end, Vector2(10.0 + GroundDecal.FEATHER, 1.0 + GroundDecal.FEATHER), Vector2.ONE * 0.0001)
	assert_eq(faded, 12, "the fade along both edges and the four corners of both ends")
	# A right-angle turn keeps the line's width through the corner.
	var corner := GroundDecal.new()
	corner.add_polyline(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), Color.RED, 2.0)
	assert_almost_eq(corner.points[2], Vector2(11, -1), Vector2.ONE * 0.0001, "the outer edges meet at the mitre")
	assert_almost_eq(corner.points[3], Vector2(9, 1), Vector2.ONE * 0.0001, "and so do the inner ones")
	# A line whose last point repeats its first is closed: no ends to fade.
	var loop := GroundDecal.new()
	loop.add_polyline(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10),
			Vector2(0, 0)]), Color.RED, 2.0, true)
	assert_eq(loop.points.size(), 20, "four vertices a point and none past its ends")
	assert_eq(loop.indices.size(), 4 * 3 * 6, "every side a quad and its two fades")
	assert_almost_eq(loop.points[1], loop.points[17], Vector2.ONE * 0.0001, "the loop closes on its first joint")


func test_a_ground_decal_circle_stands_on_its_ground_or_lies_on_its_plane() -> void:
	var standing := GroundDecal.new()
	standing.add_circle(Vector2(5, 5), 2.0, Color.RED, Vector2(3, 3), GroundDecal.ON_THE_POINT, 8)
	assert_eq(standing.points.size(), 9, "the centre and eight rim points")
	assert_eq(standing.indices.size(), 24)
	for i in standing.points.size():
		assert_eq(standing.uvs[i], Vector2(3, 3), "a ball stands wholly on the ground under it")
		if i > 0:
			assert_almost_eq(standing.points[i].distance_to(Vector2(5, 5)), 2.0, 0.0001, "round on screen")
	var lying := GroundDecal.new()
	lying.add_circle(Vector2(5, 5), 2.0, Color.RED, Vector2(3, 3), Transform2D(Vector2(0.5, 0), Vector2(0, 0.25), Vector2.ZERO), 8)
	assert_almost_eq(lying.uvs[1], Vector2(4, 3), Vector2.ONE * 0.0001, "a rim point on the plane through its ground")


## Points of the course with every kind of slope: a crown in the middle of the
## grid rising four levels.
func _raise_hill() -> void:
	for x in range(grid.grid_width + 1):
		for y in range(grid.grid_height + 1):
			var level := BASE + 4 - int(Vector2(x, y).distance_to(Vector2(8, 8)))
			grid.set_vertex_elevation(Vector2i(x, y), clampi(level, BASE, TerrainGrid.MAX_ELEVATION))


func test_ground_under_finds_the_ground_drawn_at_a_point() -> void:
	_raise_hill()
	for ground in [Vector2(6.3, 7.1), Vector2(8.0, 8.0), Vector2(9.7, 10.2), Vector2(11.4, 6.6)]:
		var world := grid.grid_point_to_screen(ground)
		var found := GroundDecal.ground_under(grid, world, ground + Vector2(0.4, -0.3))
		assert_almost_eq(grid.grid_point_to_screen(found).distance_to(world), 0.0, 0.01,
			"the point found is drawn where %s is" % ground)
		assert_almost_eq(found, ground, Vector2.ONE * 0.01, "and it is %s itself" % ground)


func test_a_standing_mark_is_measured_as_a_sprite_on_its_anchor() -> void:
	_raise_hill()
	var anchor := Vector2(6.5, 6.5)
	var mark := GroundDecal.new()
	var foot := grid.grid_point_to_screen(anchor)
	mark.add_convex(PackedVector2Array([foot + Vector2(-8, -12), foot + Vector2(8, -12), foot + Vector2(8, 6),
			foot + Vector2(-8, 6)]), Color.WHITE)
	mark.stand_on(grid, anchor, Transform2D.IDENTITY)
	# Measured from its lowest pixel, six pixels under the anchor: the ground the
	# pixel's ray reaches there (on this slope, further than six pixels).
	var reach := TerrainOcclusion.contact_reach(grid, anchor, 6.0)
	assert_gt(reach, 6.0, "precondition: the ground rises toward the camera, up the crown")
	var depth_y := grid.projection.project(anchor).y + reach
	for i in mark.points.size():
		assert_almost_eq(TerrainOcclusion.point_t_above(grid, mark.uvs[i], mark.points[i]), depth_y - mark.points[i].y,
			0.001, "vertex %d is as deep as a sprite's pixel there" % i)
		assert_false(TerrainOcclusion.hides_decal(grid, mark.uvs[i], mark.points[i]), "and the ground it stands on never hides it")


# ---------------------------------------------------------------------------
# Tee markers, cups and pins
# ---------------------------------------------------------------------------

## An open hole from `tee` to `cup`, with its tee's marker and its pin made.
func _open_hole(number: int, tee: Vector2i, cup: Vector2i) -> void:
	if GameManager.current_course == null:
		GameManager.current_course = GameManager.CourseData.new()
	grid.set_tile(tee, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(cup, TerrainTypes.Type.GREEN)
	GameManager.course_data.add_hole(make_hole(number, tee, cup, 3))
	grid._tee_aim_overlay.rebuild()
	grid._wind_flag_overlay._rebuild_all_flags()


## Every vertex of a GroundDecal drawn by `item`, as [ground, world] pairs.
func _decal_samples(item: CanvasItem, decal: GroundDecal) -> Array:
	var samples := []
	for i in decal.points.size():
		samples.append([decal.uvs[i], item.to_global(decal.points[i])])
	return samples


func _marker_samples(tee: Vector2i) -> Array:
	var tees := grid._tee_aim_overlay
	return _decal_samples(tees, tees.mesh_for(tee))


func _hole_samples(cup: Vector2i) -> Array:
	var cups := grid._cup_overlay
	return _decal_samples(cups, cups.decal_for(cup))


## Points up a pin's pole from its foot, and the pennant at its top.
func _pin_samples(pin: WindFlag) -> Array[Vector2]:
	var samples: Array[Vector2] = []
	for height in [0.5, 6.0, 12.0, 20.0, 28.0, pin._pole_height - 1.0]:
		samples.append(pin.global_position + Vector2(0.0, -height))
	samples.append(pin.global_position + Vector2(6.0, -pin._pole_height + 1.0))
	return samples


func _hidden_pin_samples(pin: WindFlag) -> int:
	var hidden := 0
	for sample in _pin_samples(pin):
		if pin.terrain_hides_point(sample):
			hidden += 1
	return hidden


func test_tee_markers_cups_and_area_rings_wear_the_decal_occlusion_material_only_on_relief() -> void:
	_open_hole(1, Vector2i(4, 4), Vector2i(10, 4))
	var overlays: Array[CanvasItem] = [grid._tee_aim_overlay, grid._cup_overlay, _area_overlay([[Vector2i(8, 8), 3.0]])]
	for overlay in overlays:
		assert_null(overlay.material, "a flat course draws the %s with no shader at all" % overlay.name)
	grid.set_vertex_elevation(Vector2i(14, 14), BASE + 3)
	var materials: Array[ShaderMaterial] = []
	for overlay in overlays:
		var mat := overlay.material as ShaderMaterial
		assert_not_null(mat, "the first sculpt clips the %s" % overlay.name)
		if mat == null:
			return
		assert_eq(mat.shader.resource_path, DECAL_SHADER, "the trail's per-pixel clip")
		assert_same(mat.get_shader_parameter("vertex_elevation"), grid._course_surface._elevation_texture,
			"sculpts update the ground and the %s's mask together" % overlay.name)
		materials.append(mat)
	grid.set_view_orientation(1)
	for mat in materials:
		assert_eq(mat.get_shader_parameter("grid_origin"), grid.projection.grid_origin(), "the mask turns with the view")
		assert_eq(mat.get_shader_parameter("grid_axis_x"), grid.projection.axis_x())
	grid.set_view_orientation(0)
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	for overlay in overlays:
		assert_null(overlay.material, "the graphics setting drops the shader")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	for i in overlays.size():
		assert_same(overlays[i].material, materials[i], "and turning it back on reuses the material")


func test_a_ridge_hides_the_tee_marker_cup_and_pin_behind_it_but_not_those_on_or_before_it() -> void:
	# Holes in the hollow at row 5, along the ridge top at row 7, and in front at
	# row 11 (see _raise_ridge()).
	var rows := [5, 7, 11]
	for i in rows.size():
		_open_hole(i + 1, Vector2i(2, rows[i]), Vector2i(10, rows[i]))
	_raise_ridge()
	assert_eq(grid._tee_aim_overlay.aimed_tees().size(), 3, "precondition: every tee carries its marker")
	for i in rows.size():
		var row: int = rows[i]
		var marker := _marker_samples(Vector2i(2, row))
		var hole := _hole_samples(Vector2i(10, row))
		var pin: WindFlag = grid._wind_flag_overlay._flags[i]
		assert_gt(marker.size(), 0)
		assert_gt(hole.size(), 0)
		if row == 5:
			assert_eq(_hidden_trail_samples(marker), marker.size(), "the ridge covers the tee marker behind it")
			assert_eq(_hidden_trail_samples(hole), hole.size(), "and the cup")
			assert_eq(_hidden_pin_samples(pin), _pin_samples(pin).size(), "and the whole pin, pennant and all")
		else:
			var where := "on the ridge" if row == 7 else "in front of it"
			assert_eq(_hidden_trail_samples(marker), 0, "the tee marker %s stays drawn" % where)
			assert_eq(_hidden_trail_samples(hole), 0, "and the cup")
			assert_eq(_hidden_pin_samples(pin), 0, "and its pin")


func test_a_hill_in_front_hides_the_foot_of_a_pin_before_its_pennant() -> void:
	# The green lies in a dip two levels deep at row 5, the ridge stands at rows
	# 7-8: it covers the foot of the pole and not the pennant flying above it.
	for x in range(grid.grid_width + 1):
		grid.set_vertex_elevation(Vector2i(x, 5), BASE - 2)
		grid.set_vertex_elevation(Vector2i(x, 6), BASE - 2)
		grid.set_vertex_elevation(Vector2i(x, 7), TerrainGrid.MAX_ELEVATION)
		grid.set_vertex_elevation(Vector2i(x, 8), TerrainGrid.MAX_ELEVATION)
	_open_hole(1, Vector2i(2, 12), Vector2i(8, 5))
	var pin: WindFlag = grid._wind_flag_overlay._flags[0]
	assert_true(pin.terrain_hides_point(pin.global_position + Vector2(0.0, -1.0)), "the foot of the pole is behind the ridge")
	assert_false(pin.terrain_hides_point(pin.global_position + Vector2(0.0, -pin._pole_height + 1.0)),
		"the top of the pole stands above it")


func test_pins_wear_the_sprite_occlusion_material_standing_in_their_cups() -> void:
	_open_hole(1, Vector2i(3, 3), Vector2i(10, 4))
	var waiting := Vector2i(12, 10)
	grid.set_tile(waiting, TerrainTypes.Type.GREEN)
	assert_true(grid.add_cup_tile(waiting))
	var pins: Array = [[grid._wind_flag_overlay._flags[0], Vector2i(10, 4)], [grid._cup_overlay._pins[0], waiting]]
	for entry in pins:
		assert_null((entry[0] as WindFlag).material, "a flat course draws the pin with no shader")
	grid.set_vertex_elevation(Vector2i(15, 15), BASE + 3)
	var materials: Array[ShaderMaterial] = []
	for entry in pins:
		var pin: WindFlag = entry[0]
		var cup: Vector2i = entry[1]
		var mat := pin.material as ShaderMaterial
		assert_not_null(mat, "the first sculpt clips the pins already standing")
		if mat == null:
			return
		assert_eq(mat.shader, WindFlag.TERRAIN_SPRITE_OCCLUSION, "the tree's per-pixel clip")
		assert_same(mat.get_shader_parameter("vertex_elevation"), grid._course_surface._elevation_texture)
		assert_eq(mat.get_shader_parameter("ground_grid"), Vector2(cup) + Vector2(0.5, 0.5), "standing in its cup")
		assert_eq(mat.get_shader_parameter("ground_offset"), Vector2.ZERO, "measured from the foot of its pole")
		assert_eq(mat.get_shader_parameter("occlusion_epsilon"), TerrainOcclusion.PROP_EPSILON)
		materials.append(mat)
	# A sculpt under a cup lifts its pin onto the new ground, and a turn of the
	# view carries it, and its mask, to where that ground is drawn now.
	for vertex in [Vector2i(10, 4), Vector2i(11, 4), Vector2i(10, 5), Vector2i(11, 5)]:
		grid.set_vertex_elevation(vertex, BASE + 2)
	grid.set_view_orientation(2)
	for i in pins.size():
		var pin: WindFlag = pins[i][0]
		assert_eq(pin.global_position, grid.grid_to_screen_center(pins[i][1]), "%s stands in its cup" % pin.name)
		assert_eq(materials[i].get_shader_parameter("grid_origin"), grid.projection.grid_origin(), "the mask turns with the view")
		assert_eq(_hidden_pin_samples(pin), 0, "and nothing hides a pin on open ground")
	grid.set_view_orientation(0)
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	for entry in pins:
		assert_null((entry[0] as WindFlag).material, "the graphics setting turns it off")
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	for i in pins.size():
		assert_same((pins[i][0] as WindFlag).material, materials[i], "turning it back on reuses the pin's material")
	# A pin put up on a course that already has its hills is clipped at once.
	grid._wind_flag_overlay._rebuild_all_flags()
	var fresh: WindFlag = grid._wind_flag_overlay._flags[0]
	assert_not_same(fresh, pins[0][0], "precondition: a new pin")
	assert_not_null(fresh.material, "a new pin on a sculpted course is clipped")
	if fresh.material != null:
		assert_eq((fresh.material as ShaderMaterial).get_shader_parameter("ground_grid"), Vector2(10.5, 4.5))


func test_a_tee_marker_and_a_cup_are_never_hidden_by_the_ground_they_are_on() -> void:
	# The tee and the green on a ramp rising toward the camera, as steep as three
	# levels a tile: a fixed-size marker overhangs a tile squeezed that thin, and
	# the ground under its overhang is the same ramp - not a hill in front.
	_open_hole(1, Vector2i(6, 6), Vector2i(10, 9))
	_raise_ramp(0, 0, TerrainGrid.MIN_ELEVATION)
	var checked := 0
	for levels in [1, 2, 3]:
		_raise_ramp(5, levels, TerrainGrid.MIN_ELEVATION)
		for angle in [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
			grid.set_view_angle(angle)
			for entry in [[Vector2i(6, 6), _marker_samples(Vector2i(6, 6))], [Vector2i(10, 9), _hole_samples(Vector2i(10, 9))]]:
				var tile: Vector2i = entry[0]
				var centre := Vector2(tile) + Vector2(0.5, 0.5)
				assert_almost_eq(grid.screen_to_grid_point(grid.grid_point_to_screen(centre)), centre, Vector2.ONE * 0.001,
					"precondition: the tile at %s faces the view at %s" % [tile, angle])
				assert_eq(_hidden_trail_samples(entry[1]), 0,
					"nothing hides the mark on %s on a ramp of %d levels at view %s" % [tile, levels, angle])
				checked += 1
	grid.set_view_angle(0.0)
	assert_eq(checked, 42)


func test_marker_and_hole_meshes_are_reused_until_the_ground_or_the_view_changes() -> void:
	_open_hole(1, Vector2i(4, 4), Vector2i(10, 4))
	grid.set_vertex_elevation(Vector2i(14, 14), BASE + 2)
	var tees := grid._tee_aim_overlay
	var cups := grid._cup_overlay
	var marker := tees.mesh_for(Vector2i(4, 4))
	var hole := cups.decal_for(Vector2i(10, 4))
	assert_same(tees.mesh_for(Vector2i(4, 4)), marker, "a camera pan repaints the marker it laid out")
	assert_same(cups.decal_for(Vector2i(10, 4)), hole, "and the hole")
	grid.set_vertex_elevation(Vector2i(5, 5), BASE + 2)
	var lifted := tees.mesh_for(Vector2i(4, 4))
	assert_not_same(lifted, marker, "a sculpt lays the marker out again")
	assert_not_same(cups.decal_for(Vector2i(10, 4)), hole, "and the hole")
	assert_lt(_mean_y(lifted.points), _mean_y(marker.points), "on the raised ground")
	grid.set_view_orientation(1)
	var turned := tees.mesh_for(Vector2i(4, 4))
	assert_not_same(turned, lifted, "and so does a turn of the view")
	assert_eq(_hidden_trail_samples(_decal_samples(tees, turned)), 0)
	grid.set_view_orientation(0)


func _mean_y(points: PackedVector2Array) -> float:
	var total := 0.0
	for point in points:
		total += point.y
	return total / maxf(1.0, float(points.size()))


# ---------------------------------------------------------------------------
# Designated areas
# ---------------------------------------------------------------------------

## The designated-area overlay as main.gd seats it, drawing one ring for each
## [area centre, radius] in `areas`.
func _area_overlay(areas: Array = []) -> StaffAreaOverlay:
	var staff := StaffManager.new()
	add_child_autofree(staff)
	for area in areas:
		staff.hired_staff.append({"staff_id": staff.hired_staff.size() + 1, "type": 0, "salary": 80,
			"name": "Keeper", "area_center": area[0], "area_radius": area[1]})
	GameManager.staff_manager = staff
	var overlay := StaffAreaOverlay.new()
	overlay.name = "StaffAreaOverlay"
	overlay.set_terrain_grid(grid)
	grid.add_child(overlay)
	return overlay


func _triangle_area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return absf((b - a).cross(c - a)) * 0.5


func test_an_area_ring_is_a_mesh_of_its_tiles_in_grid_space() -> void:
	for radius in [1.0, 2.5, 6.0, 13.0]:
		var ring := StaffAreaOverlay.build_ring(Vector2(8, 8), radius)
		var count := ring.rim_grounds.size() - 1
		assert_eq(ring.rim_grounds[count], ring.rim_grounds[0], "the rim closes")
		assert_eq(count, clampi(ceili(TAU * radius / StaffAreaOverlay.RIM_SPACING),
			StaffAreaOverlay.MIN_RIM_POINTS, StaffAreaOverlay.MAX_RIM_POINTS), "a point every half tile")
		assert_gt(ring.fill_indices.size(), 0)
		assert_eq(ring.fill_indices.size() % 3, 0, "a plain triangle list")
		var area := 0.0
		var astray := 0
		for i in range(0, ring.fill_indices.size(), 3):
			var corners: Array[Vector2] = []
			for j in 3:
				var index := ring.fill_indices[i + j]
				if index < 0 or index >= ring.fill_grounds.size():
					fail_test("index %d is out of range" % index)
					return
				corners.append(ring.fill_grounds[index])
			area += _triangle_area(corners[0], corners[1], corners[2])
			# No triangle crosses a tile edge, where the ground bends.
			var tile := ((corners[0] + corners[1] + corners[2]) / 3.0).floor()
			for corner in corners:
				if corner.x < tile.x - 0.0001 or corner.x > tile.x + 1.0001 \
						or corner.y < tile.y - 0.0001 or corner.y > tile.y + 1.0001:
					astray += 1
		var rim_area: float = 0.5 * count * radius * radius * sin(TAU / count)
		assert_almost_eq(area, rim_area, rim_area * 0.0001, "radius %s: the disc is covered once, rim to rim" % radius)
		assert_eq(astray, 0, "radius %s: every triangle lies in one tile" % radius)
	for radius in [0.0, -1.0, NAN]:
		var empty := StaffAreaOverlay.build_ring(Vector2(8, 8), radius)
		assert_true(empty.fill_indices.is_empty() and empty.rim_grounds.is_empty(),
			"an area of radius %s has nothing to draw" % radius)


func test_a_ring_on_ground_folded_over_itself_is_drawn_without_the_engine_triangulating_it() -> void:
	# A cliff along the diagonal through the area's centre, rising toward the
	# camera: on screen the ground behind its foot is folded under the ground in
	# front, and so is a ring drawn around both - a polygon the engine cannot fill
	# ("Invalid polygon data, triangulation failed" at staff_area_overlay.gd:59).
	for x in range(grid.grid_width + 1):
		for y in range(grid.grid_height + 1):
			var side := x + y - 16
			var level := TerrainGrid.MAX_ELEVATION if side >= 1 else (TerrainGrid.MIN_ELEVATION if side <= -1 else BASE)
			grid.set_vertex_elevation(Vector2i(x, y), level)
	var rings := _area_overlay([[Vector2i(8, 8), 6.0]])
	assert_true(Geometry2D.triangulate_polygon(rings._projected_circle(Vector2(8, 8), 6.0)).is_empty(),
		"precondition: the ring's projected outline folds over itself")
	var geometry := rings.ring_geometry(Vector2(8, 8), 6.0)
	var points: PackedVector2Array = geometry.fill_points
	var grounds: PackedVector2Array = geometry.fill_grounds
	var indices: PackedInt32Array = geometry.fill_indices
	assert_gt(indices.size(), 0, "the disc is drawn all the same")
	var misplaced := 0
	for i in points.size():
		if grid.grid_point_to_screen(grounds[i]).distance_to(rings.to_global(points[i])) > 0.01:
			misplaced += 1
	assert_eq(misplaced, 0, "every vertex is drawn where its ground is")
	# The owner's gold ring is drawn the same way. An engine error while drawing
	# them fails the run.
	var owner_manager := PlayerGolferManager.new()
	add_child_autofree(owner_manager)
	GameManager.player_golfer_manager = owner_manager
	assert_true(owner_manager.set_area_center(Vector2i(8, 8)))
	rings.refresh()
	await process_frames(2)
	assert_eq(rings._rings.size(), 2, "both rings were drawn")


func test_a_ridge_hides_the_ring_behind_it_but_not_the_ring_on_or_before_it() -> void:
	# The area reaches from the hollow over the ridge and well in front of it,
	# and keeps three tiles clear of the course's far edge: the ridge only hides
	# the hollow where it stands on the course between the hollow and the camera.
	_raise_ridge()
	var rings := _area_overlay([[Vector2i(6, 8), 6.0]])
	var geometry := rings.ring_geometry(Vector2(6, 8), 6.0, Color.WHITE, 2.5)
	var rim: GroundDecal = geometry.rim
	var samples := []
	var points: PackedVector2Array = geometry.fill_points
	var grounds: PackedVector2Array = geometry.fill_grounds
	for i in points.size():
		samples.append([grounds[i], rings.to_global(points[i])])
	samples.append_array(_decal_samples(rings, rim))
	var counts := {"hollow": 0, "ridge": 0, "front": 0}
	for sample in samples:
		var ground: Vector2 = sample[0]
		var hidden := TerrainOcclusion.hides_decal(grid, ground, sample[1])
		if ground.y >= 5.0 and ground.y <= 6.0:
			counts.hollow += 1
			if not hidden:
				fail_test("the ring in the hollow at %s is drawn over the ridge" % ground)
		elif ground.y >= 7.0 and ground.y <= 8.0:
			counts.ridge += 1
			if hidden:
				fail_test("the ring along the ridge at %s is hidden" % ground)
		elif ground.y >= 9.0:
			counts.front += 1
			if hidden:
				fail_test("the ring in front of the ridge at %s is hidden" % ground)
	for where in counts:
		assert_gt(counts[where], 10, "the ring crosses the %s" % where)


func test_a_ring_lies_on_the_ground_it_crosses() -> void:
	# On a ramp rising toward the camera as steep as three levels a tile, the
	# rim's thin line stays on the ground under it: its lower edge, a pixel down
	# the screen, lies on ground much further up such a slope.
	var rings := _area_overlay([[Vector2i(7, 7), 3.0]])
	_raise_ramp(0, 0, TerrainGrid.MIN_ELEVATION)
	for levels in [1, 2, 3]:
		_raise_ramp(5, levels, TerrainGrid.MIN_ELEVATION)
		for orientation in 4:
			grid.set_view_orientation(orientation)
			var geometry := rings.ring_geometry(Vector2(7, 7), 3.0, Color.WHITE, 2.5)
			var rim: GroundDecal = geometry.rim
			var samples := _decal_samples(rings, rim)
			var points: PackedVector2Array = geometry.fill_points
			var grounds: PackedVector2Array = geometry.fill_grounds
			for i in points.size():
				samples.append([grounds[i], rings.to_global(points[i])])
			assert_eq(_hidden_trail_samples(samples), 0,
				"nothing hides the ring on a ramp of %d levels in view %d" % [levels, orientation])
	grid.set_view_orientation(0)


func test_rings_follow_sculpts_and_view_turns_and_are_reused_between_them() -> void:
	var rings := _area_overlay([[Vector2i(8, 8), 3.0]])
	grid.set_vertex_elevation(Vector2i(15, 15), BASE + 1)
	var key := Vector3(8, 8, 3.0)
	var before := rings.ring_geometry(Vector2(8, 8), 3.0)
	var ring: StaffAreaOverlay.AreaRing = rings._rings[key]
	rings.ring_geometry(Vector2(8, 8), 3.0)
	assert_same(rings._rings[key], ring, "a redraw reuses the area's mesh")
	grid.set_vertex_elevation(Vector2i(8, 8), BASE + 2)
	var after := rings.ring_geometry(Vector2(8, 8), 3.0)
	var centre := (before.fill_grounds as PackedVector2Array).find(Vector2(8, 8))
	assert_gt(centre, -1, "precondition: the area's centre is a corner of its mesh")
	assert_almost_eq((after.fill_points as PackedVector2Array)[centre].y,
		(before.fill_points as PackedVector2Array)[centre].y - 2.0 * TerrainGrid.ELEVATION_STEP_Y, 0.001,
		"a sculpt lifts the ring with the ground")
	grid.set_view_orientation(1)
	var turned := rings.ring_geometry(Vector2(8, 8), 3.0)
	var misplaced := 0
	for i in (turned.fill_points as PackedVector2Array).size():
		if grid.grid_point_to_screen(turned.fill_grounds[i]).distance_to(rings.to_global(turned.fill_points[i])) > 0.01:
			misplaced += 1
	assert_eq(misplaced, 0, "a turn re-projects every vertex onto its ground")
	assert_same(rings._rings[key], ring, "from the same mesh")
	assert_eq((rings.material as ShaderMaterial).get_shader_parameter("grid_origin"), grid.projection.grid_origin(),
		"and turns the mask with the view")
	grid.set_view_orientation(0)


# ---------------------------------------------------------------------------
# Decorations
# ---------------------------------------------------------------------------

func _place_decoration(type: String, pos: Vector2i) -> Decoration:
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/decorations.json"))["decorations"]
	var decoration := entities.place_decoration(type, pos, catalogue)
	assert_not_null(decoration, "%s placed at %s" % [type, pos])
	return decoration


func _decoration_visual(decoration: Decoration) -> Node2D:
	return decoration.get_node("Visual") as Node2D


## Points of a decoration's art, from its foot up to the top of a statue and to
## either side of it.
func _art_samples(decoration: Decoration) -> Array[Vector2]:
	var foot := decoration.to_global(_decoration_visual(decoration).position)
	var samples: Array[Vector2] = []
	for height in [0.5, 4.0, 10.0, 18.0, 26.0]:
		for side in [-6.0, 0.0, 6.0]:
			samples.append(foot + Vector2(side, -height))
	return samples


func _hidden_art_samples(decoration: Decoration) -> int:
	var hidden := 0
	for sample in _art_samples(decoration):
		if decoration.terrain_hides_point(sample):
			hidden += 1
	return hidden


func _shadow_samples(decoration: Decoration) -> Array:
	var samples := []
	for shadow in decoration._shadow_polygons():
		for i in shadow.polygon.size():
			samples.append([shadow.uv[i] if i < shadow.uv.size() else Vector2.ZERO, shadow.to_global(shadow.polygon[i])])
	return samples


func test_decorations_wear_occlusion_materials_only_on_relief() -> void:
	var fountain := _place_decoration("fountain", Vector2i(4, 4))
	var bench := _place_decoration("park_bench", Vector2i(8, 4))
	var visual := _decoration_visual(fountain)
	var shadows := []
	shadows.append_array(fountain._shadow_polygons())
	assert_eq(shadows.size(), 2, "precondition: the contact shadow and the sun's")
	assert_null(visual.material, "a flat course draws the prop with no shader")
	for shadow in shadows:
		assert_null(shadow.material)
		assert_null(shadow.texture, "and its shadows as plain polygons")
	grid.set_vertex_elevation(Vector2i(12, 12), BASE + 3)
	var art := visual.material as ShaderMaterial
	assert_not_null(art, "the first sculpt clips the props already standing")
	if art == null:
		return
	assert_eq(art.shader, Decoration.TERRAIN_SPRITE_OCCLUSION, "the art: the tree's per-pixel clip")
	assert_same(art.get_shader_parameter("vertex_elevation"), grid._course_surface._elevation_texture)
	assert_eq(art.get_shader_parameter("ground_grid"), Vector2(4.5, 4.5), "standing on its tile")
	assert_eq(art.get_shader_parameter("occlusion_epsilon"), TerrainOcclusion.PROP_EPSILON)
	for part in visual.find_children("*", "CanvasItem", true, false):
		assert_eq((part as CanvasItem).use_parent_material, not shadows.has(part),
			"%s wears the art's clip" % part.name if not shadows.has(part) else "%s wears its own" % part.name)
	for shadow in shadows:
		var mat := shadow.material as ShaderMaterial
		assert_not_null(mat, "%s is clipped as paint on the ground" % shadow.name)
		if mat == null:
			return
		assert_eq(mat.shader, Decoration.TERRAIN_DECAL_OCCLUSION)
		assert_eq(mat.get_shader_parameter("occlusion_epsilon"), TerrainOcclusion.SHADOW_EPSILON)
		assert_same(shadow.texture, GroundDecal.uv_carrier(), "carrying its grounds as UVs")
		assert_eq(shadow.uv.size(), shadow.polygon.size())
	var misplaced := 0
	for sample in _shadow_samples(fountain):
		if grid.grid_point_to_screen(sample[0]).distance_to(sample[1]) > Decoration.SHADOW_GROUND_MISS:
			misplaced += 1
	assert_eq(misplaced, 0, "every point of a shadow names the ground drawn under it")
	assert_not_null(_decoration_visual(bench).material, "path furniture is clipped too")
	# A sculpt beside the prop moves the ground under its shadow, not the prop.
	var grounds := []
	for sample in _shadow_samples(fountain):
		grounds.append(sample[0])
	grid.set_vertex_elevation(Vector2i(6, 5), BASE + 2)
	await process_frames(1)
	var moved := 0
	misplaced = 0
	var samples := _shadow_samples(fountain)
	for i in samples.size():
		if samples[i][0] != grounds[i]:
			moved += 1
		if grid.grid_point_to_screen(samples[i][0]).distance_to(samples[i][1]) > Decoration.SHADOW_GROUND_MISS:
			misplaced += 1
	assert_gt(moved, 0, "precondition: the sculpt reaches ground under the shadow")
	assert_eq(misplaced, 0, "the shadow names the ground drawn under it after a sculpt beside the prop")
	# A turn of the view comes through set_position_in_grid() (main.gd).
	grid.set_view_orientation(3)
	fountain.set_position_in_grid(fountain.grid_position)
	assert_eq(art.get_shader_parameter("grid_origin"), grid.projection.grid_origin(), "the mask turns with the view")
	misplaced = 0
	for sample in _shadow_samples(fountain):
		if grid.grid_point_to_screen(sample[0]).distance_to(sample[1]) > Decoration.SHADOW_GROUND_MISS:
			misplaced += 1
	assert_eq(misplaced, 0, "and the shadows name the ground drawn under them now")
	grid.set_view_orientation(0)
	fountain.set_position_in_grid(fountain.grid_position)
	PerformanceSettings.set_graphics_setting(OCCLUSION, 0)
	assert_null(visual.material, "the graphics setting turns it off")
	for shadow in shadows:
		assert_null(shadow.material)
		assert_null(shadow.texture)
	PerformanceSettings.set_graphics_setting(OCCLUSION, 1)
	assert_same(visual.material, art, "turning it back on reuses the prop's material")


func test_a_ridge_hides_decorations_behind_it_but_not_those_on_or_before_it() -> void:
	var rows := {5: "in the hollow", 7: "on the ridge", 11: "in front of it"}
	var placed := []
	var x := 1
	for type in ["fountain", "golfer_statue", "park_bench"]:
		for row in rows:
			placed.append([row, _place_decoration(type, Vector2i(x, row))])
		x += 4
	_raise_ridge()
	await process_frames(2)
	for entry in placed:
		var row: int = entry[0]
		var decoration: Decoration = entry[1]
		var art := _art_samples(decoration)
		var shadows := _shadow_samples(decoration)
		var what := "%s %s" % [decoration.decoration_type, rows[row]]
		if row == 5:
			assert_eq(_hidden_art_samples(decoration), art.size(), "the ridge covers the %s" % what)
			if not shadows.is_empty():
				assert_gt(_hidden_trail_samples(shadows) * 10, shadows.size() * 9, "and its shadow on the ground behind it")
		else:
			assert_eq(_hidden_art_samples(decoration), 0, "the %s stays drawn" % what)
			assert_eq(_hidden_trail_samples(shadows), 0, "and so does its shadow")


func test_a_decoration_is_measured_from_the_lowest_pixel_of_its_art() -> void:
	# A bench on a two-tile-wide walk sits out at the walk's edge, drawn ten
	# pixels down its tile; a sundial's sprite is cut so its lowest pixel is
	# its foot.
	_lay_row(5, 3, 9)
	_lay_row(6, 3, 9)
	var bench := _place_decoration("park_bench", Vector2i(5, 6))
	var sundial := _place_decoration("sundial", Vector2i(8, 11))
	grid.set_vertex_elevation(Vector2i(15, 0), BASE + 4)
	var visual := _decoration_visual(bench)
	var furniture := bench.get_node("Visual/PathFurniture") as PathFurniture
	assert_eq(visual.position, Vector2(0.0, 10.0), "precondition: the bench stands at the walk's edge")
	var below := visual.position.y + PathFurniture.ground_reach("park_bench", furniture.facing) * absf(visual.scale.y)
	var art := visual.material as ShaderMaterial
	assert_eq(art.get_shader_parameter("ground_grid"), Vector2(5.5, 6.5), "standing on its tile")
	assert_almost_eq((art.get_shader_parameter("ground_offset") as Vector2).y, below, 0.001,
		"measured from its front feet, under its tile's centre")
	assert_almost_eq((_decoration_visual(sundial).material as ShaderMaterial).get_shader_parameter("ground_offset").y,
		0.0, 0.001, "a sprite is measured from its foot")
	# The ground rising toward the camera in front of the bench: the ground under
	# its feet lies further along their rays, and never cuts into them.
	_raise_ramp(6, 2)
	await process_frames(1)
	visual = _decoration_visual(bench)
	art = visual.material as ShaderMaterial
	assert_gt((art.get_shader_parameter("ground_offset") as Vector2).y, below + 1.0, "the reach follows the ramp")
	var lowest := bench.to_global(visual.position) + Vector2(0.0, below - visual.position.y - 0.5)
	for height in [0.0, 2.0, 6.0, 12.0, 20.0]:
		assert_false(bench.terrain_hides_point(lowest + Vector2(0.0, -height)), "%s px up from its feet the bench is drawn" % height)


# ---------------------------------------------------------------------------
# Shaders
# ---------------------------------------------------------------------------

func test_occlusion_shaders_compile_and_share_the_heightfield_depth_test() -> void:
	for path in [DECAL_SHADER, FOOTPRINT_SHADER, "res://shaders/terrain_sprite_occlusion.gdshader",
			"res://shaders/course_surface.gdshader"]:
		var shader := load(path) as Shader
		assert_not_null(shader, path)
		if shader:
			assert_gt(shader.get_shader_uniform_list().size(), 0, "%s compiles" % path)
	for path in [DECAL_SHADER, FOOTPRINT_SHADER]:
		var source := FileAccess.get_file_as_string(path)
		assert_true(source.contains("#include \"res://shaders/terrain_heightfield.gdshaderinc\""),
			"%s intersects the same heightfield as the ground" % path)
		assert_true(source.contains("terrain_hides("), path)
		assert_true(source.contains("discard;"), "%s clips covered pixels instead of darkening them" % path)
	var common := FileAccess.get_file_as_string("res://shaders/terrain_heightfield.gdshaderinc")
	assert_true(common.contains("bool terrain_hides(vec2 world, float point_t)"))
	# The CPU twin answers for the shaders, so their slack must agree.
	assert_true(FileAccess.get_file_as_string(DECAL_SHADER).contains(
		"uniform float occlusion_epsilon = %s;" % TerrainOcclusion.DECAL_EPSILON))
	assert_true(FileAccess.get_file_as_string(FOOTPRINT_SHADER).contains(
		"uniform float occlusion_epsilon = %s;" % TerrainOcclusion.FOOTPRINT_EPSILON))


func test_occlusion_shaders_clip_pixels_without_recolouring_them() -> void:
	# Godot 4 multiplies the texture into COLOR before a canvas fragment() runs.
	# Sampling TEXTURE again squares every channel and darkens the art, so these
	# shaders only decide whether a pixel is drawn.
	var resample := RegEx.create_from_string("\\bTEXTURE\\b")
	var recolour := RegEx.create_from_string("\\bCOLOR\\s*[-+*/]?=(?!=)")
	for path in [DECAL_SHADER, FOOTPRINT_SHADER, "res://shaders/terrain_sprite_occlusion.gdshader"]:
		var code := _shader_code(path)
		assert_gt(code.length(), 0, path)
		assert_null(resample.search(code), "%s does not sample the art a second time" % path)
		assert_null(recolour.search(code), "%s leaves the drawn colour as it is" % path)


## A shader's source without its `//` comments.
func _shader_code(path: String) -> String:
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var comment := line.find("//")
		lines.append(line if comment < 0 else line.substr(0, comment))
	return "\n".join(lines)
