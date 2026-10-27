extends MainSceneTest
## The potential hole path: while a tee box waits and the Green tool is about to
## cut the cup, hovering a tile previews the hole it would make — and the route
## drawn is the one the opened hole shows.
##
## The cursor is simulated through the camera's pointer, so the preview runs its
## real per-frame path: screen -> grid picking, HoleLayout.potential_hole() and
## the background route planner.

var grid: TerrainGrid
var preview: PlacementPreview


func before_all() -> void:
	await super()
	await new_game("Hole path preview")
	grid = main.terrain_grid
	preview = main.placement_preview
	# Routes ignore the wind anyway; this keeps them deterministic.
	GameManager.wind_system = null
	# A quiet stretch of owned grass, so no route is bent by scenery.
	main._suppress_tile_undo = true
	for x in range(48, 82):
		for y in range(54, 68):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	main._suppress_tile_undo = false


func after_each() -> void:
	await super()


## Put the simulated cursor over a tile's centre.
func _hover(tile: Vector2i) -> void:
	var camera = main.camera
	var motion := InputEventMouseMotion.new()
	motion.position = camera.get_canvas_transform() * grid.grid_to_screen_center(tile)
	motion.global_position = motion.position
	# A genuine mouse movement also takes control back from the gamepad
	# reticle; assigning the camera's private field bypasses that input path.
	motion.relative = Vector2(2, 0)
	get_viewport().push_input(motion, true)


## Wait for the background planner to deliver the hovered route.
func _await_route() -> void:
	await process_frames_until(func() -> bool: return not preview.potential_hole_route.is_empty(), 600)


func test_the_green_tool_previews_the_hole_and_opens_the_route_it_drew() -> void:
	# --- The Green tool with no tee box waiting: no path.
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	_hover(Vector2i(64, 60))
	await process_frames(3)
	assert_true(preview.potential_hole.is_empty(), "No path while no tee box waits")

	# --- Paint the tee; other tools never show the path.
	var tee := Vector2i(52, 60)
	paint(TerrainTypes.Type.TEE_BOX, tee)
	assert_eq(grid.get_tile(tee), TerrainTypes.Type.TEE_BOX, "The tee box is painted")
	_hover(Vector2i(64, 60))
	await process_frames(3)
	assert_true(preview.potential_hole.is_empty(), "The Tee Box tool shows no hole path")
	main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
	await process_frames(3)
	assert_true(preview.potential_hole.is_empty(), "The Fairway tool shows no hole path")

	# --- The Green tool with a waiting tee: a par 3 path follows the cursor.
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	var par3_cup := Vector2i(62, 60)
	_hover(par3_cup)
	await process_frames(3)
	var hole: Dictionary = preview.potential_hole
	assert_false(hole.is_empty(), "Hovering with the Green tool shows the potential hole")
	assert_eq(hole.get("tee"), tee, "The path starts at the waiting tee")
	assert_eq(hole.get("cup"), par3_cup, "The path ends at the hovered tile")
	assert_eq(hole.get("par"), 3, "Ten tiles is a par 3")
	assert_eq(hole.get("distance_yards"), 220, "of 220 yards")
	assert_eq(hole.get("hole_number"), 1, "It would be hole 1")
	assert_true(hole.get("ready", false), "A 220-yard pair on open, owned grass is ready: %s" % hole.get("reason"))
	assert_eq(preview.potential_hole_route, [tee, par3_cup], "A par 3 route is drawn tee to cup at once")

	# --- Too short: still drawn, but flagged.
	_hover(tee + Vector2i(2, 0))
	await process_frames(3)
	assert_false(preview.potential_hole.is_empty(), "The path follows the cursor even when too short")
	assert_false(preview.potential_hole.get("ready", true), "A 44-yard pair is flagged as too short")

	# --- Par 4: the route is planned in the background, then drawn.
	var par4_cup := Vector2i(70, 62)
	_hover(par4_cup)
	await process_frames(1)
	assert_eq(preview.potential_hole.get("par", 0), 4, "An 18-tile pair is a par 4")
	await _await_route()
	var previewed: Array = preview.potential_hole_route.duplicate()
	assert_eq(previewed.size(), 3, "The par 4 route has a landing zone: %s" % [previewed])
	if previewed.size() == 3:
		assert_eq(previewed[0], tee, "The par 4 route leaves the tee")
		assert_eq(previewed[-1], par4_cup, "and reaches the cup")

	# --- Other modes hide the path; coming back finds the cached route.
	main._on_bulldozer_pressed()
	await process_frames(3)
	assert_true(preview.potential_hole.is_empty(), "Bulldozer mode hides the path")
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	_hover(par4_cup)
	await process_frames(3)
	assert_false(preview.potential_hole.is_empty(), "Back on the Green tool, the path returns")
	assert_eq(preview.potential_hole_route, previewed, "The planned route was cached")
	main._cancel_action()  # Esc deselects the tool.
	await process_frames(3)
	assert_true(preview.potential_hole.is_empty(), "Deselecting the tool hides the path")

	# --- Cut the cup: the path stays anchored to the waiting pair.
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	_hover(par4_cup)
	await process_frames(3)
	stroke(par4_cup)
	assert_eq(grid.get_cup_tiles(), [par4_cup], "The cup was cut where the path ended")
	_hover(par4_cup + Vector2i(0, 3))
	await process_frames(3)
	assert_true(preview.potential_hole.is_empty(), "The hover path is hidden once a cup waits")
	assert_eq(preview.waiting_hole.get("cup"), par4_cup, "The painted cup keeps the hole path anchored")
	assert_eq(preview.waiting_hole.get("par"), 4, "The painted pair keeps its par")
	main._cancel_action()
	await process_frames(3)
	assert_eq(preview.waiting_hole.get("cup"), par4_cup, "The path persists without an active tool")

	# --- Open the hole: its route is the one that was previewed.
	main._on_open_hole_pressed()
	assert_eq(GameManager.current_course.holes.size(), 1, "Open Hole created the hole")
	var opened: GameManager.HoleData = GameManager.current_course.holes[-1]
	assert_eq(opened.par, 4, "The opened hole is the previewed par 4")
	assert_eq(ShotPathCalculator.calculate_waypoints(opened, grid), previewed,
		"The opened hole's route matches the preview")
	_hover(Vector2i(64, 64))
	await process_frames(3)
	assert_true(preview.potential_hole.is_empty(), "Every tee is claimed again: no hover path")
	assert_true(preview.waiting_hole.is_empty(), "Opening the hole clears the waiting path")


func test_a_par_five_opens_with_the_route_it_previewed() -> void:
	var next_number := GameManager.current_course.holes.size() + 1
	var tee := Vector2i(52, 66)
	paint(TerrainTypes.Type.TEE_BOX, tee)
	main._on_tool_selected(TerrainTypes.Type.GREEN)
	var cup := Vector2i(78, 64)
	_hover(cup)
	await process_frames(1)
	var hole: Dictionary = preview.potential_hole
	assert_eq(hole.get("hole_number", 0), next_number, "The preview numbers the next hole")
	assert_eq(hole.get("par", 0), 5, "A 26-tile pair is a par 5")
	assert_false(hole.has("extra_tees"), "One tee per hole: the preview paints no extras")
	await _await_route()
	var previewed: Array = preview.potential_hole_route.duplicate()
	# Two landings usually; one when a lay-up already reaches a green nearby.
	assert_gte(previewed.size(), 3, "The par 5 route lands at least once: %s" % [previewed])
	if previewed.size() >= 3:
		assert_eq(previewed[0], tee, "The par 5 route leaves the tee")
		assert_eq(previewed[-1], cup, "and reaches the cup")

	stroke(cup)
	main._on_open_hole_pressed()
	assert_eq(GameManager.current_course.holes.size(), next_number, "Open Hole created the par 5")
	var opened: GameManager.HoleData = GameManager.current_course.holes[-1]
	assert_eq(opened.tee_position, tee, "The hole's tee is the tile that was painted")
	assert_eq(ShotPathCalculator.calculate_waypoints(opened, grid), previewed,
		"The opened par 5's route matches the preview")
