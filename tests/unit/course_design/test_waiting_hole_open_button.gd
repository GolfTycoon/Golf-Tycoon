extends GameTest
## Unit tests for the inline "Open Hole" button on the waiting tee-to-cup route:
## button states, accessibility, tooltips, polyline midpoint geometry, plaque
## non-overlap and signal-driven visibility lifecycle.

var grid: TerrainGrid
var hud: Control
var preview: PlacementPreview
var button: WaitingHoleOpenButton

func before_each() -> void:
	super()
	GameManager.current_course = GameManager.CourseData.new()
	grid = make_grid(32, 32)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child_autofree(hud)
	preview = PlacementPreview.new()
	preview.set_terrain_grid(grid)
	add_child_autofree(preview)
	# Keep process off so every assertion proves synchronous, signal-driven state.
	preview.set_process(false)
	button = preview.attach_hud(hud)

func _paint_cup(tile: Vector2i) -> void:
	grid.set_tile(tile, TerrainTypes.Type.GREEN)
	grid.add_cup_tile(tile)

# ---------------------------------------------------------------------------
# Polyline geometry & plaque avoidance
# ---------------------------------------------------------------------------

func test_polyline_midpoint_splits_straight_and_bent_routes_by_arc_length() -> void:
	var straight := PackedVector2Array([Vector2(100, 200), Vector2(500, 300)])
	assert_almost_eq(PlacementPreview.polyline_point_at(straight, 0.5),
			Vector2(300, 250), Vector2(0.01, 0.01),
			"Straight par 3 midpoint sits halfway between tee and cup")

	# Dogleg: 300 px east then 100 px south = 400 px total; half is 200 px east.
	var dogleg := PackedVector2Array([
		Vector2(0, 0),
		Vector2(300, 0),
		Vector2(300, 100),
	])
	var mid := PlacementPreview.polyline_point_at(dogleg, 0.5)
	assert_almost_eq(mid, Vector2(200, 0), Vector2(0.01, 0.01),
			"Dogleg midpoint sits at half total path length, right on the line")
	assert_lt(PlacementPreview.distance_to_polyline(mid, dogleg), 0.01,
			"Dogleg midpoint lies directly on a route segment")

	# Two-landing par 5: 100 + 200 + 100 = 400 px; half sits in the middle of leg 2.
	var par5 := PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 200),
		Vector2(200, 200),
	])
	var par5_mid := PlacementPreview.polyline_point_at(par5, 0.5)
	assert_almost_eq(par5_mid, Vector2(100, 100), Vector2(0.01, 0.01),
			"Multi-waypoint par 5 midpoint sits halfway along total shot distance")
	assert_lt(PlacementPreview.distance_to_polyline(par5_mid, par5), 0.01)

func test_line_button_center_avoids_cup_plaque_while_staying_on_the_route() -> void:
	var btn_size := Vector2(104, 34)
	var route := PackedVector2Array([Vector2(100, 300), Vector2(420, 300)])

	# Plaque well away near the cup: seat is the exact midpoint.
	var far_plaque := Rect2(Vector2(360, 240), Vector2(140, 28))
	var normal := PlacementPreview.line_button_center(route, btn_size, far_plaque)
	assert_almost_eq(normal, Vector2(260, 300), Vector2(0.01, 0.01))
	assert_false(Rect2(normal - btn_size * 0.5, btn_size).intersects(far_plaque))

	# Plaque encroaches on the midpoint: slides along the line toward the tee.
	var near_plaque := Rect2(Vector2(240, 286), Vector2(150, 28))
	var slid := PlacementPreview.line_button_center(route, btn_size, near_plaque)
	assert_lt(slid.x, 260.0, "Button slides toward the tee to clear the plaque")
	assert_lt(PlacementPreview.distance_to_polyline(slid, route), 0.01,
			"Slid button still sits directly on the route line")
	assert_false(Rect2(slid - btn_size * 0.5, btn_size).intersects(near_plaque),
			"Slid button never overlaps the cup plaque")

	# Ultra-short line completely covered by the plaque: steps cleanly off it.
	var tiny_route := PackedVector2Array([Vector2(280, 300), Vector2(310, 300)])
	var covering_plaque := Rect2(Vector2(220, 284), Vector2(160, 30))
	var stepped := PlacementPreview.line_button_center(tiny_route, btn_size, covering_plaque)
	assert_false(Rect2(stepped - btn_size * 0.5, btn_size).intersects(covering_plaque),
			"Even on a tiny route the button leaves the cup plaque readable")

# ---------------------------------------------------------------------------
# Waiting-hole visibility lifecycle
# ---------------------------------------------------------------------------

func test_button_appears_only_when_both_a_waiting_tee_and_waiting_cup_exist() -> void:
	assert_eq(button.get_index(), 0, "Inline button sits at child index 0 of the HUD")
	assert_eq(button.text, "Open Hole")
	assert_eq(button.focus_mode, Control.FOCUS_NONE,
			"Course-space pill does not steal D-pad or keyboard dock focus")
	assert_false(button.visible, "Hidden on an empty course")

	# Only a waiting tee: no connecting line yet, so no button.
	grid.set_tile(Vector2i(8, 12), TerrainTypes.Type.TEE_BOX)
	assert_false(button.visible, "Hidden with only a waiting tee")

	# Add a waiting cup at legal hole distance: line and button appear together.
	_paint_cup(Vector2i(16, 12))
	assert_true(button.visible, "Shown as soon as tee and cup both wait")
	assert_false(button.disabled, "Enabled for a legal tee-to-cup pair")
	assert_eq(button.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND)

	var screen_points := preview.waiting_hole_screen_points()
	var btn_center := button.position + button.size * 0.5
	assert_lt(PlacementPreview.distance_to_polyline(btn_center, screen_points), 1.0,
			"Button centre sits right on the connecting tee-to-cup line")
	assert_false(Rect2(button.position, button.size).intersects(preview.waiting_hole_plaque_rect()),
			"Button does not cover the cup plaque")

	# Erase the cup: pair dissolves and button hides immediately.
	grid.set_tile(Vector2i(16, 12), TerrainTypes.Type.GRASS)
	assert_false(button.visible, "Hidden the moment the waiting cup is cleared")

	# Only a waiting cup without a tee: still hidden.
	grid.set_tile(Vector2i(8, 12), TerrainTypes.Type.GRASS)
	_paint_cup(Vector2i(16, 12))
	assert_false(button.visible, "Hidden with only a waiting cup")

	# Two unused tees make pairing ambiguous: waiting_hole is empty, button hides.
	grid.set_tile(Vector2i(8, 12), TerrainTypes.Type.TEE_BOX)
	assert_true(button.visible)
	grid.set_tile(Vector2i(8, 15), TerrainTypes.Type.TEE_BOX)
	assert_false(button.visible, "Hidden when more than one unused tee makes pairing ambiguous")

func test_too_short_pair_shows_disabled_button_with_reason_and_clears_tooltip_on_hide() -> void:
	grid.set_tile(Vector2i(10, 10), TerrainTypes.Type.TEE_BOX)
	_paint_cup(Vector2i(12, 10))  # 2 tiles < MIN_HOLE_TILES (5)

	assert_true(button.visible, "Too-short pair still shows its connecting line and button")
	assert_true(button.disabled, "Too-short pair disables Open Hole")
	assert_eq(button.mouse_default_cursor_shape, Control.CURSOR_ARROW)
	assert_string_contains(button.description_text(), "Too short",
			"Disabled description tells the player why the pair cannot open yet")
	assert_string_contains(button.accessibility_description, "Too short")

	# Hovering starts a tooltip; hiding the button clears it immediately.
	button._on_mouse_entered()
	assert_false(TooltipManager._pending_data.is_empty(), "Hover schedules a tooltip")
	preview.set_hud_visible(false)
	assert_false(button.visible)
	assert_true(TooltipManager._pending_data.is_empty(),
			"Hiding the button cancels any pending or visible tooltip immediately")

	# Restoring HUD visibility when the pair is gone must never reveal the button.
	grid.set_tile(Vector2i(12, 10), TerrainTypes.Type.GRASS)
	preview.set_hud_visible(true)
	assert_false(button.visible, "Restoring HUD visibility stays hidden without a waiting pair")

func test_clicking_emits_open_hole_pressed_and_move_or_passthrough_gates_apply() -> void:
	grid.set_tile(Vector2i(6, 10), TerrainTypes.Type.TEE_BOX)
	_paint_cup(Vector2i(15, 10))
	assert_true(button.visible)
	assert_string_contains(button.description_text(), "Hole 1")
	assert_string_contains(button.description_text(), "Par 3")
	assert_eq(button.shortcut_text(), InputBindings.binding_text("tool_open_hole"))

	var fired := [0]
	preview.open_hole_pressed.connect(func() -> void: fired[0] += 1)
	button.pressed.emit()
	assert_eq(fired[0], 1, "Pressing the inline pill emits open_hole_pressed")

	# Moving a hole endpoint hides the button until the move finishes.
	preview.set_hole_move_mode(1)
	assert_false(button.visible, "Hidden during hole move mode")
	preview.set_hole_move_mode(0)
	assert_true(button.visible, "Restored once hole move mode ends")

	# Carrying a building hides the button until dropped or cancelled.
	var dummy_building: Building = autofree(Building.new())
	preview.set_building_move_target(dummy_building)
	assert_false(button.visible, "Hidden while carrying a building")
	preview.set_building_move_target(null)
	assert_true(button.visible, "Restored once the carried building is released")

	# Passthrough lets active strokes sweep right across the button.
	var painting := [false]
	preview.passthrough_input_provider = func() -> bool: return painting[0]
	preview.refresh_input_filter()
	assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)
	painting[0] = true
	preview.refresh_input_filter()
	assert_eq(button.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	painting[0] = false
	preview.refresh_input_filter()
	assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)

	# Opening the hole claims both tee and cup and hides the button immediately.
	GameManager.terrain_grid = grid
	var tool: HoleCreationTool = autofree(HoleCreationTool.new())
	assert_not_null(tool.open_hole(Vector2i(6, 10), Vector2i(15, 10)))
	assert_false(button.visible, "Hidden immediately once the hole opens")
