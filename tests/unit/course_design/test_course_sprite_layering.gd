extends GameTest
## Draw-order and Y-sort invariants for the four course-play elements that share
## the world with standing pixel-art sprites:
##   1. White tee aim arrow and red tee-marker balls (`TeeAimOverlay`)
##   2. The cup hole cut in the green (`CupOverlay`)
##   3. Pin flags (`WindFlag` under `WindFlagOverlay` and waiting pins in `CupOverlay`)
##   4. Golf balls (`Ball` under `Entities/Balls`, at rest, rolling, putting, and airborne)
## against golfers, trees, buildings, decorations, and flower beds.

const GOLFER_SCENE := preload("res://scenes/entities/golfer.tscn")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")

const SURFACE_BAND := 0
const GROUND_BAND := 1
const ENTITY_BAND := 2

var world: Node2D
var grid: TerrainGrid
var entity_layer: EntityLayer
var entities: Node2D
var golfers_container: Node2D
var balls_container: Node2D
var ball_manager: BallManager
var decoration_registry: Dictionary


func before_each() -> void:
	super()
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child_autofree(world)

	grid = TerrainGrid.new()
	grid.name = "TerrainGrid"
	grid.grid_width = 24
	grid.grid_height = 24
	world.add_child(grid)
	fill_grid(grid, TerrainTypes.Type.GRASS)
	GameManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()

	entity_layer = EntityLayer.new()
	entity_layer.name = "EntityLayer"
	entity_layer.map_seed = 1234
	world.add_child(entity_layer)
	entity_layer.set_terrain_grid(grid)

	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	world.add_child(entities)

	golfers_container = Node2D.new()
	golfers_container.name = "Golfers"
	golfers_container.y_sort_enabled = true
	entities.add_child(golfers_container)

	balls_container = Node2D.new()
	balls_container.name = "Balls"
	balls_container.y_sort_enabled = true
	entities.add_child(balls_container)

	ball_manager = BallManager.new()
	ball_manager.name = "BallManager"
	world.add_child(ball_manager)
	ball_manager.set_terrain_grid(grid)

	decoration_registry = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/decorations.json"))["decorations"]


func _effective_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		var canvas_item := node as CanvasItem
		if canvas_item.z_as_relative:
			z += canvas_item.z_index
		else:
			z = canvas_item.z_index
			break
		node = canvas_item.get_parent()
	return z


## True when every CanvasItem ancestor between `root` and `item` (exclusive of
## `item` itself) enables `y_sort_enabled`, allowing Godot's canvas cull to
## flatten `item` into `root`'s shared Y-sort list.
func _has_ysort_chain(root: CanvasItem, item: CanvasItem) -> bool:
	if root == null or item == null or not root.y_sort_enabled:
		return false
	var parent := item.get_parent()
	while parent != null and parent != root:
		if not (parent is CanvasItem) or not (parent as CanvasItem).y_sort_enabled:
			return false
		parent = parent.get_parent()
	return parent == root


func _spawn_golfer(pos: Vector2i) -> Golfer:
	var golfer := GOLFER_SCENE.instantiate() as Golfer
	golfers_container.add_child(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	golfer.global_position = grid.grid_to_screen_center(pos)
	return golfer


# ---------------------------------------------------------------------------
# Scene tree Y-sort chain
# ---------------------------------------------------------------------------

func test_main_scene_enables_ysort_on_balls_alongside_golfers_and_terrain() -> void:
	var packed_state := MAIN_SCENE.get_state()
	var y_sorted_paths: Dictionary = {}
	for idx in range(packed_state.get_node_count()):
		var path := str(packed_state.get_node_path(idx))
		var y_sort := false
		for prop_idx in range(packed_state.get_node_property_count(idx)):
			if packed_state.get_node_property_name(idx, prop_idx) == "y_sort_enabled":
				y_sort = bool(packed_state.get_node_property_value(idx, prop_idx))
		y_sorted_paths[path] = y_sort

	assert_true(y_sorted_paths.get(".", false), "Main enables y_sort_enabled")
	assert_true(y_sorted_paths.get("./TerrainGrid", false), "TerrainGrid enables y_sort_enabled")
	assert_true(y_sorted_paths.get("./Entities", false), "Entities enables y_sort_enabled")
	assert_true(y_sorted_paths.get("./Entities/Golfers", false), "Entities/Golfers enables y_sort_enabled")
	assert_true(y_sorted_paths.get("./Entities/Balls", false), "Entities/Balls enables y_sort_enabled")


# ---------------------------------------------------------------------------
# Ground band: tee white arrow & red balls (`TeeAimOverlay`) and hole (`CupOverlay`)
# ---------------------------------------------------------------------------

func test_tee_arrow_red_balls_and_cup_hole_paint_in_ground_band_under_all_sprites() -> void:
	var tee_pos := Vector2i(6, 10)
	var cup_pos := Vector2i(14, 10)
	grid.set_tile(tee_pos, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(cup_pos, TerrainTypes.Type.GREEN)
	var hole := make_hole(1, tee_pos, cup_pos, 4)
	GameManager.course_data.add_hole(hole)

	var surface := grid.get_node("CourseSurface") as CanvasItem
	var tee_overlay := grid.get_node("TeeAimOverlay") as TeeAimOverlay
	var cup_overlay := grid.get_node("CupOverlay") as CupOverlay
	var flowers := grid.get_node("FlowerOverlay") as FlowerOverlay
	var walk := grid.get_node("WalkingPathOverlay") as WalkingPathOverlay
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	tee_overlay.rebuild()
	grid._wind_flag_overlay._rebuild_all_flags()

	# Both overlays sit in the ground band: above the surface, ranked under flowers/paths/trees.
	assert_eq(_effective_z(surface), SURFACE_BAND)
	assert_eq(_effective_z(tee_overlay), GROUND_BAND,
			"Tee white arrow and red tee balls belong in the ground band")
	assert_eq(_effective_z(cup_overlay), GROUND_BAND,
			"The hole cut in the green belongs in the ground band")
	assert_lt(cup_overlay.get_index(), flowers.get_index(),
			"Cup hole paints before adjacent flower sprites")
	assert_lt(tee_overlay.get_index(), flowers.get_index(),
			"Tee markings paint before adjacent flower sprites")
	assert_lt(tee_overlay.get_index(), walk.get_index())
	assert_lt(tee_overlay.get_index(), trees.get_index())

	# Spawn every kind of standing sprite on the course and verify all of them draw above z 1.
	grid.set_tile(Vector2i(7, 11), TerrainTypes.Type.OAK)
	trees._sync_visuals()
	var tree_node := trees._visuals[Vector2i(7, 11)] as CanvasItem

	var clubhouse := entity_layer.place_building("snack_bar", Vector2i(9, 12),
			ContentRegistry.get_buildings())
	var statue := entity_layer.place_decoration("golfer_statue", Vector2i(8, 11), decoration_registry)
	var golfer := _spawn_golfer(tee_pos)
	await process_frames(1)
	var golfer_sprite := (golfer.sprite_node() if golfer.sprite_node() != null else golfer.visual) as CanvasItem
	var flag := grid._wind_flag_overlay._flags[0] as CanvasItem
	ball_manager.place_ball_at_rest(1, tee_pos)
	var ball := ball_manager.get_ball(1)
	var ball_visual := ball.get_node("Visual") as CanvasItem

	for sprite_item in [golfer_sprite, tree_node, clubhouse.get_node("Visual") as CanvasItem,
			statue.get_node("Visual") as CanvasItem, flag, ball_visual]:
		assert_eq(_effective_z(sprite_item), ENTITY_BAND,
				"%s resolves to the entity band (z %d)" % [sprite_item.name, ENTITY_BAND])
		assert_gt(_effective_z(sprite_item), _effective_z(tee_overlay),
				"%s draws over the tee's white arrow and red balls" % sprite_item.name)
		assert_gt(_effective_z(sprite_item), _effective_z(cup_overlay),
				"%s draws over the cup hole in the green" % sprite_item.name)


# ---------------------------------------------------------------------------
# Pin flags (`WindFlagOverlay` and waiting gold pins in `CupOverlay`)
# ---------------------------------------------------------------------------

func test_open_hole_and_waiting_flags_ysort_with_sprites_in_entity_band() -> void:
	var open_tee := Vector2i(4, 10)
	var open_cup := Vector2i(10, 10)
	var waiting_cup := Vector2i(14, 10)
	grid.set_tile(open_tee, TerrainTypes.Type.TEE_BOX)
	grid.set_tile(open_cup, TerrainTypes.Type.GREEN)
	grid.set_tile(waiting_cup, TerrainTypes.Type.GREEN)
	assert_true(grid.add_cup_tile(waiting_cup))
	GameManager.course_data.add_hole(make_hole(1, open_tee, open_cup, 3))
	grid._wind_flag_overlay._rebuild_all_flags()

	assert_eq(grid._wind_flag_overlay._flags.size(), 1)
	assert_eq(grid._cup_overlay._pins.size(), 1)
	var open_flag := grid._wind_flag_overlay._flags[0]
	var waiting_pin := grid._cup_overlay._pins[0]

	assert_eq(_effective_z(open_flag), ENTITY_BAND,
			"Open-hole red flag resolves to entity band z 2")
	assert_eq(_effective_z(waiting_pin), ENTITY_BAND,
			"Waiting gold pin resolves to entity band z 2 (not stacked on CupOverlay)")
	assert_gt(_effective_z(open_flag), _effective_z(grid._cup_overlay),
			"Open-hole flag stands over the black hole cut beneath it")
	assert_gt(_effective_z(waiting_pin), _effective_z(grid._cup_overlay),
			"Waiting gold pin stands over the black hole cut beneath it")
	assert_true(_has_ysort_chain(world, open_flag),
			"Open-hole flag has an unbroken y_sort_enabled chain from World")
	assert_true(_has_ysort_chain(world, waiting_pin),
			"Waiting gold pin has an unbroken y_sort_enabled chain from World")

	# Place a tree north (behind) and a golfer south (in front) of the open-hole flag.
	var north_tile := open_cup + Vector2i(-1, -1)
	var south_tile := open_cup + Vector2i(1, 1)
	grid.set_tile(north_tile, TerrainTypes.Type.PINE)
	grid._tree_overlay._sync_visuals()
	var back_tree := grid._tree_overlay._visuals[north_tile] as Node2D
	var front_golfer := _spawn_golfer(south_tile)
	await process_frames(1)

	assert_lt(back_tree.global_position.y, open_flag.global_position.y,
			"Northern tree anchors behind the flag")
	assert_gt(front_golfer.global_position.y, open_flag.global_position.y,
			"Southern golfer anchors in front of the flag")
	assert_true(_has_ysort_chain(world, back_tree))
	assert_true(_has_ysort_chain(world, front_golfer))


# ---------------------------------------------------------------------------
# Golf balls (`Ball`): resting, rolling, putting, and airborne arc
# ---------------------------------------------------------------------------

func test_resting_and_rolling_balls_ysort_with_sprites_and_keep_shadow_on_ground() -> void:
	var ball_tile := Vector2i(10, 10)
	var front_tree_tile := Vector2i(11, 11)
	var back_tree_tile := Vector2i(9, 9)
	grid.set_tile(front_tree_tile, TerrainTypes.Type.OAK)
	grid.set_tile(back_tree_tile, TerrainTypes.Type.OAK)
	grid._tree_overlay._sync_visuals()

	ball_manager.place_ball_at_rest(7, ball_tile)
	var ball := ball_manager.get_ball(7)
	var shadow := ball.get_node("GroundShadow") as Polygon2D
	var visual := ball.get_node("Visual") as Node2D

	assert_eq(_effective_z(ball), ENTITY_BAND, "Ball resolves to entity band z 2")
	assert_eq(_effective_z(visual), ENTITY_BAND, "Ball visual resolves to entity band z 2")
	assert_eq(_effective_z(shadow), GROUND_BAND,
			"Ball contact shadow resolves to ground band z 1 beneath all standing sprites")
	assert_true(_has_ysort_chain(world, visual),
			"Ball visual has an unbroken y_sort_enabled chain from World")

	var back_tree := grid._tree_overlay._visuals[back_tree_tile] as Node2D
	var front_tree := grid._tree_overlay._visuals[front_tree_tile] as Node2D
	assert_lt(back_tree.global_position.y, visual.global_position.y,
			"Ball sorts in front of a tree behind it")
	assert_lt(visual.global_position.y, front_tree.global_position.y,
			"Ball sorts behind a tree canopy in front of it")

	# At address on the same tile, Golfers precedes Balls under Entities so the ball stays visible.
	var golfer := _spawn_golfer(ball_tile)
	await process_frames(1)
	assert_almost_eq(golfer.global_position.y, visual.global_position.y, 0.001)
	assert_lt(golfers_container.get_index(), balls_container.get_index(),
			"Golfers draws before Balls on an exact Y tie so a ball at address stays visible")


func test_airborne_ball_sorts_by_ground_track_while_drawing_at_lifted_arc_position() -> void:
	var tree_tile := Vector2i(10, 10)
	grid.set_tile(tree_tile, TerrainTypes.Type.OAK)
	grid._tree_overlay._sync_visuals()
	var tree := grid._tree_overlay._visuals[tree_tile] as Node2D
	var tree_pos := tree.global_position

	ball_manager.place_ball_at_rest(3, Vector2i(4, 4))
	var ball := ball_manager.get_ball(3)
	# Fly from south of the tree to north of the tree; at mid-flight (t = 0.25) the
	# ground track is still south of the tree (`ground_y > tree_pos.y`), while the
	# arc lifts `ball.global_position.y` above `tree_pos.y`.
	var start_screen := tree_pos + Vector2(0.0, 60.0)
	var end_screen := tree_pos - Vector2(0.0, 20.0)
	ball.start_flight_screen_with_arc(start_screen, end_screen, 1.0)
	ball.flight_max_height = 120.0
	ball._process_flight(0.25)

	var visual := ball.get_node("Visual") as Node2D
	var shadow := ball.get_node("GroundShadow") as Polygon2D
	var drawn_poly := visual.get_child(0) as Polygon2D
	var expected_ground := start_screen.lerp(end_screen, 0.25)

	# Without ground-track anchoring, ball.global_position.y (< tree_pos.y) would
	# mistakenly sort behind the tree even while flying high over its crown!
	assert_lt(ball.global_position.y, tree_pos.y,
			"Lifted airborne position is higher on screen (smaller Y) than the tree base")
	assert_gt(visual.global_position.y, tree_pos.y,
			"Visual sort anchor stays on the ground track south of the tree so the shot flies over it")
	assert_almost_eq(visual.global_position.y, expected_ground.y, 0.05,
			"Visual sort anchor tracks the ground directly under the airborne ball")

	# Meanwhile the rendered polygon vertex center still lands at the lifted airborne coordinates.
	var rendered_center := drawn_poly.global_transform * drawn_poly.offset
	assert_almost_eq(rendered_center.x, ball.global_position.x, 0.05)
	assert_almost_eq(rendered_center.y, ball.global_position.y, 0.05,
			"Offsetting Visual to the ground track keeps the drawn ball at its arc height")
	assert_eq(_effective_z(shadow), GROUND_BAND,
			"Shadow stays in ground band z 1 under the tree canopy during flight")

	# Completing flight resets the ground-anchor offset cleanly for rollout/rest.
	ball.set_terrain_grid(null)  # Avoid spawning a timed LandingImpactEffect tween
	ball._process_flight(0.75)
	visual = ball.get_node("Visual") as Node2D
	drawn_poly = visual.get_child(0) as Polygon2D
	assert_almost_eq(visual.position.y, 0.0, 0.001)
	assert_almost_eq(drawn_poly.offset.y, 0.0, 0.001)
	assert_almost_eq(visual.global_position.y, end_screen.y, 0.05)


func test_path_offset_decorations_ysort_at_their_shifted_visual_foot() -> void:
	for x in range(6, 12):
		grid.set_tile(Vector2i(x, 10), TerrainTypes.Type.ROUGH)
		grid.set_walking_path(Vector2i(x, 10), true)
	var bench := entity_layer.place_decoration("park_bench", Vector2i(8, 10), decoration_registry)
	var visual := bench.get_node("Visual") as Node2D
	assert_ne(visual.position.y, 0.0, "Bench shifts off the centre of the walking path")
	assert_true(_has_ysort_chain(world, visual),
			"Decoration enables y_sort_enabled so its shifted Visual sorts at its actual foot")
