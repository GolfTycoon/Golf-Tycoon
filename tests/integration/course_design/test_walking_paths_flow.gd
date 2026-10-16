extends MainSceneTest
## The Path improvement on a new course, through the real paint stamp:
## a trail leaves the ground under it alone and costs $8 a tile, is paved where
## it reaches the clubhouse, survives a save and load, is bulldozed for $5 and
## comes back with undo — and a golfer standing on it is drawn over it.

const SAVE_NAME := "integration_walking_paths"
## Tiles of trail the first test lays, the last of them against the clubhouse.
const TRAIL_LENGTH := 4

var grid: TerrainGrid
## The clubhouse's top-left footprint tile: where a new course puts it varies,
## so every tile the tests use is placed relative to it.
var origin: Vector2i


func before_all() -> void:
	await super()
	await new_game("Walking paths")
	grid = main.terrain_grid
	origin = CourseClubhouse.find(main.entity_layer).grid_position
	# Hold the clock so green fees and day rollovers cannot move the balance
	# between a purchase and the check of what it cost.
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)


## The tile `offset` away from the clubhouse's top-left footprint tile.
func _near_clubhouse(offset: Vector2i) -> Vector2i:
	return origin + offset


func after_all() -> void:
	SaveManager.delete_save(SAVE_NAME)
	super()


## Repaint a tile without a player's stroke (undo stays out of it).
func _prep(tile: Vector2i, terrain: int) -> void:
	main._suppress_tile_undo = true
	grid.set_tile(tile, terrain)
	main._suppress_tile_undo = false


func _overlay() -> WalkingPathOverlay:
	return grid.get_node("WalkingPathOverlay") as WalkingPathOverlay


## A straight run of ground leading to the clubhouse's wall: TRAIL_LENGTH tiles
## for the trail, nearest the wall last, and one more beyond them for the trail
## to be refused on. Where a new course puts its clubhouse varies — it can
## stand against the edge of the owned land, or have a tree standing where a
## trail would run — so the run is looked for on each side in turn rather than
## measured off the footprint and hoped for.
func _run_up_to_the_clubhouse() -> Array[Vector2i]:
	var clubhouse := CourseClubhouse.find(main.entity_layer)
	for row in range(clubhouse.height):
		for side in [Vector2i.LEFT, Vector2i.RIGHT]:
			var wall_x: int = 0 if side == Vector2i.LEFT else clubhouse.width - 1
			var wall: Vector2i = clubhouse.grid_position + Vector2i(wall_x, row)
			var run: Array[Vector2i] = []
			for step in range(TRAIL_LENGTH + 1, 0, -1):
				run.append(wall + side * step)
			if _is_buildable_ground(run):
				return run
	return [] as Array[Vector2i]


## True when every tile is owned ground with nothing standing on it, which is
## all _paint_walking_path_stamp() asks of a tile before it lays the trail.
func _is_buildable_ground(tiles: Array[Vector2i]) -> bool:
	for tile in tiles:
		if not grid.is_valid_position(tile):
			return false
		if not GameManager.land_manager.is_tile_owned(tile):
			return false
		if main.entity_layer.is_tile_occupied_by_building(tile) \
				or main.entity_layer.is_tile_occupied_by_decoration(tile):
			return false
	return true


func test_a_trail_is_painted_paved_saved_bulldozed_and_undone() -> void:
	# Four tiles leading to the clubhouse; the last one touches it. The fifth,
	# furthest out, is the ground the trail will be refused on.
	var run := _run_up_to_the_clubhouse()
	assert_eq(run.size(), TRAIL_LENGTH + 1,
		"A new course leaves a run of owned ground beside its clubhouse")
	if run.size() != TRAIL_LENGTH + 1:
		return
	var refusing := run[0]
	var trail: Array[Vector2i] = run.slice(1)
	var touching := trail[TRAIL_LENGTH - 1]
	var detached := [_near_clubhouse(Vector2i(6, -11)), _near_clubhouse(Vector2i(7, -11))]

	# Select the Path tool the way the toolbar does.
	main.terrain_toolbar._on_tool_button_pressed(TerrainTypes.WALKING_PATH_TOOL)
	await process_frames(2)
	assert_eq(main.current_tool, TerrainTypes.WALKING_PATH_TOOL, "The Path tool is selected")

	for tile in trail:
		_prep(tile, TerrainTypes.Type.ROUGH)
		assert_true(GameManager.land_manager.is_tile_owned(tile), "%s is owned land" % tile)
	await process_frames(2)

	# --- Painting: the trail sits on the ground, at $8 a tile.
	var money_before := GameManager.money
	main.undo_manager.begin_stroke()
	for tile in trail:
		main._paint_walking_path_stamp(tile)
	main.undo_manager.end_stroke()
	await process_frames(2)
	for tile in trail:
		assert_true(grid.has_walking_path(tile), "%s carries the trail" % tile)
		assert_eq(grid.get_tile(tile), TerrainTypes.Type.ROUGH, "%s is still rough underneath" % tile)
	assert_eq(GameManager.money, money_before - TRAIL_LENGTH * 8, "Four trail tiles cost $32")

	# Unhostable ground refuses the trail, and charges nothing.
	var money_now := GameManager.money
	_prep(refusing, TerrainTypes.Type.FAIRWAY)
	main._paint_walking_path_stamp(refusing)
	assert_false(grid.has_walking_path(refusing), "The fairway refuses the trail")
	assert_eq(GameManager.money, money_now, "A refused trail costs nothing")

	# --- Paving: the trail reaches the clubhouse, so all of it is paved; a
	# detached trail within the plot stays dirt.
	var overlay := _overlay()
	await process_frames(2)
	for tile in trail:
		assert_true(overlay._upgraded_tiles.has(tile), "%s is paved: the trail reaches the clubhouse" % tile)
	for tile in detached:
		_prep(tile, TerrainTypes.Type.ROUGH)
		grid.set_walking_path(tile, true)
	await process_frames(2)
	assert_false(overlay._upgraded_tiles.has(detached[0]), "A detached trail stays dirt")

	# --- Save, break, load: the trail and its paving survive.
	assert_true(SaveManager.save_game(SAVE_NAME), "The game saves")
	await process_frames(2)
	grid.set_walking_path(trail[1], false)
	assert_true(SaveManager.load_game(SAVE_NAME), "and loads back")
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	await process_frames(4)
	assert_true(grid.has_walking_path(trail[1]), "The broken trail tile is restored on load")
	assert_true(grid.has_walking_path(trail[0]))
	assert_eq(grid.get_tile(trail[1]), TerrainTypes.Type.ROUGH, "with its rough ground")
	overlay = _overlay()
	await process_frames(2)
	assert_true(overlay._upgraded_tiles.has(trail[1]), "and paved again")

	# --- Bulldozing a trail tile: $5, the ground stays, the tail goes back to dirt.
	main._on_bulldozer_pressed()
	await process_frames(2)
	var bulldoze_money := GameManager.money
	main._handle_bulldozer_click(trail[2])
	await process_frames(2)
	assert_false(grid.has_walking_path(trail[2]), "The bulldozer removed the trail tile")
	assert_eq(GameManager.money, bulldoze_money - 5, "for $5")
	assert_eq(grid.get_tile(trail[2]), TerrainTypes.Type.ROUGH, "and left the rough in place")
	assert_true(overlay._upgraded_tiles.has(touching), "The tile touching the clubhouse stays paved")
	assert_false(overlay._upgraded_tiles.has(trail[1]), "while the detached tail reverts to dirt")

	# --- Undo and redo the removal, then the whole paint stroke.
	main._perform_undo()
	await process_frames(2)
	assert_true(grid.has_walking_path(trail[2]), "Undo restores the bulldozed tile")
	assert_true(overlay._upgraded_tiles.has(trail[2]), "paved again")
	main._perform_redo()
	await process_frames(2)
	assert_false(grid.has_walking_path(trail[2]), "Redo removes it again")
	main._perform_undo()
	main._perform_undo()
	await process_frames(2)
	assert_false(grid.has_walking_path(trail[0]), "Undoing the paint stroke clears its tiles")
	assert_false(grid.has_walking_path(touching))
	main._perform_redo()
	await process_frames(2)
	assert_true(grid.has_walking_path(trail[0]), "and redo lays the trail again")
	main._cancel_bulldozer_mode()


func test_the_overlay_draws_dirt_and_paving_with_typed_commands() -> void:
	var tile := _near_clubhouse(Vector2i(-4, 5))
	_prep(tile, TerrainTypes.Type.ROUGH)
	grid.set_walking_path(tile, true)
	var overlay := _overlay()
	var dirt: Array = overlay.tile_draw_commands(tile, false, true)
	var paved: Array = overlay.tile_draw_commands(tile, true, true)
	assert_gte(dirt.size(), 2, "A dirt tile draws a patch and its detail")
	assert_gte(paved.size(), 2, "A paved tile draws its kerb and flagstones")
	for command in dirt + paved:
		assert_true(command is WalkingPathOverlay.DrawCommand, "Every draw command is a DrawCommand")


func test_a_golfer_on_the_trail_is_drawn_over_it() -> void:
	# The sprite belongs to the entity band (z 2), over the surface and every
	# overlay the grid paints on it; the shadow and rings ride that band.
	var tile := _near_clubhouse(Vector2i(-3, 5))
	_prep(tile, TerrainTypes.Type.ROUGH)
	grid.set_walking_path(tile, true)
	var golfer: Golfer = load("res://scenes/entities/golfer.tscn").instantiate()
	main.get_node("Entities/Golfers").add_child(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	golfer.global_position = grid.grid_to_screen_center(tile)
	await process_frames(2)

	var sprite := golfer.sprite_node() as CanvasItem
	if sprite == null:
		sprite = golfer.visual as CanvasItem
	var surface := grid.get_node("CourseSurface") as CanvasItem
	var sprite_z := _effective_z(sprite)
	var trail_z := _effective_z(_overlay())
	assert_gt(sprite_z, _effective_z(surface), "The golfer is drawn over the course surface")
	assert_gt(sprite_z, trail_z, "and over the walking trail")
	var shadow_z := _effective_z(golfer.visual.get_node("Shadow") as CanvasItem)
	assert_gte(shadow_z, trail_z, "The shadow lies on the trail, not under it")
	assert_gt(sprite_z, shadow_z, "and under the golfer who casts it")
	var buried: Array[String] = []
	for item in _canvas_items(golfer):
		if _effective_z(item) < _effective_z(surface):
			buried.append("%s (z %d)" % [item.name, _effective_z(item)])
	assert_eq(buried, [] as Array[String], "No part of the golfer is buried behind the surface")
	golfer.free()


## The z an item is actually drawn at: its own band, plus the bands of the
## relative parents above it, the way Godot resolves it.
func _effective_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		var canvas_item := node as CanvasItem
		if canvas_item.z_as_relative:
			z += canvas_item.z_index
		else:
			z = canvas_item.z_index
		node = canvas_item.get_parent()
	return z


## Every canvas item a node draws with, its own children first.
func _canvas_items(node: Node) -> Array[CanvasItem]:
	var items: Array[CanvasItem] = []
	for child in node.get_children():
		if child is CanvasItem:
			items.append(child)
		items.append_array(_canvas_items(child))
	return items
