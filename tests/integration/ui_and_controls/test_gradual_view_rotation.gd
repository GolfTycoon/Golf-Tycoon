extends MainSceneTest
## Gradual View Rotation in the running game: the Settings → Controls → Camera
## switch that turns the course in small, animated steps, and the live view
## controls that follow it. The classic mode keeps its instant quarter turns.

const STEP := TerrainGrid.GRADUAL_VIEW_STEP_QUARTER_TURNS


func before_all() -> void:
	await super()
	await new_game()


func after_each() -> void:
	# These tests flip the player's live preference; put the classic view back.
	Input.action_release("rotate_camera")
	Input.action_release("rotate_camera_cw")
	GameManager.set_gradual_view_rotation(false)
	if is_instance_valid(main) and is_instance_valid(main.terrain_grid):
		main.terrain_grid.set_gradual_view_rotation(false)
		main.terrain_grid.set_view_orientation(0.0)
	await process_frames(1)
	super()


func _grid() -> TerrainGrid:
	return main.terrain_grid


func _settle() -> void:
	await process_frames_until(func() -> bool: return not _grid().is_view_turning(), 180)


func _set_gradual(enabled: bool) -> void:
	GameManager.set_gradual_view_rotation(enabled)
	await process_frames(1)


# ---------------------------------------------------------------------------
# The live view
# ---------------------------------------------------------------------------

func test_the_setting_reaches_the_live_course_at_once() -> void:
	await _set_gradual(true)
	assert_true(_grid().is_gradual_view_rotation_enabled(),
		"Turning the preference on changes how the course turns")
	await _set_gradual(false)
	assert_false(_grid().is_gradual_view_rotation_enabled(),
		"and turning it off changes it straight back")


func test_a_rotate_arrow_turns_a_small_step_instead_of_a_quarter_turn() -> void:
	var grid := _grid()
	grid.set_view_orientation(0.0)
	await process_frames(1)
	await _set_gradual(true)

	await click(main.rotate_cw_btn)
	await _settle()
	assert_almost_eq(grid.get_view_angle(), STEP, 0.0001,
		"One press turns 15°, not a quarter turn")
	assert_eq(grid.get_view_orientation(), 0,
		"15° has not reached the next of the four directions")
	assert_eq(main.course_location_banner.orientation_toggle.letter, "N",
		"so the compass still reads north")

	# Six steps make the quarter turn the classic mode does in one.
	for i in range(5):
		await click(main.rotate_cw_btn)
		await _settle()
	assert_almost_eq(grid.get_view_angle(), 1.0, 0.0001, "Six steps are 90°")
	assert_eq(grid.get_view_orientation(), 1)
	assert_eq(main.course_location_banner.orientation_toggle.letter, "E",
		"and the compass follows at the quarter turn")


func test_q_and_e_turn_in_gradual_steps_too() -> void:
	var grid := _grid()
	grid.set_view_orientation(0.0)
	await process_frames(1)
	await _set_gradual(true)

	press_key(KEY_E)
	await _settle()
	assert_almost_eq(grid.get_view_angle(), STEP, 0.0001,
		"E takes one gradual step clockwise")
	press_key(KEY_Q)
	await _settle()
	assert_almost_eq(grid.get_view_angle(), 0.0, 0.0001,
		"Q takes it back")


func test_holding_a_rotate_key_keeps_the_view_turning() -> void:
	var grid := _grid()
	grid.set_view_orientation(0.0)
	await process_frames(1)
	await _set_gradual(true)

	# No key press event: only the key staying down, which is what a player who
	# keeps Q or E pressed does after the first step.
	Input.action_press("rotate_camera_cw")
	await get_tree().create_timer(
		(main.VIEW_ROTATE_HOLD_DELAY_MSEC + 150) / 1000.0).timeout
	Input.action_release("rotate_camera_cw")
	await _settle()

	assert_gt(grid.get_view_angle(), 0.0,
		"A held rotate key keeps taking small steps")
	assert_lt(grid.get_view_angle(), 1.0,
		"without spinning all the way round in an instant")


func test_turning_the_setting_off_settles_on_the_nearest_direction() -> void:
	var grid := _grid()
	grid.set_view_orientation(0.0)
	await _set_gradual(true)
	# Land between north and east, where the classic view cannot sit.
	grid.set_view_orientation(0.4)
	assert_almost_eq(grid.get_view_angle(), 0.4, 0.0001)

	await _set_gradual(false)
	assert_almost_eq(grid.get_view_angle(), 0.0, 0.0001,
		"The course settles back on the nearest of the four directions")


func test_the_classic_mode_keeps_its_instant_quarter_turn() -> void:
	var grid := _grid()
	grid.set_view_orientation(0.0)
	await process_frames(1)
	assert_false(grid.is_gradual_view_rotation_enabled())

	await click(main.rotate_cw_btn)
	assert_false(grid.is_view_turning(), "No animation in the classic mode")
	assert_eq(grid.get_view_orientation(), 1, "The click is a quarter turn at once")
	assert_almost_eq(grid.get_view_angle(), 1.0, 0.0001)


# ---------------------------------------------------------------------------
# The Settings control
# ---------------------------------------------------------------------------

func test_the_controls_page_offers_gradual_rotation_and_saves_it() -> void:
	await _set_gradual(false)
	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	await process_frames(6)
	menu._select_category(SettingsMenu.Category.CONTROLS)
	await process_frames(3)

	var toggle := menu.find_child("Toggle_gradual_view_rotation", true, false) as CheckButton
	assert_not_null(toggle, "Gradual View Rotation is on the Controls page")
	if toggle == null:
		return
	assert_false(toggle.button_pressed, "It starts off, matching the live preference")

	toggle.button_pressed = true
	await process_frames(2)
	assert_true(GameManager.gradual_view_rotation, "Flipping it changes the preference")
	assert_true(_grid().is_gradual_view_rotation_enabled(), "and the live course follows it")
	var saved := ConfigFile.new()
	assert_eq(saved.load(SaveManager.SETTINGS_PATH), OK, "The choice saves to settings.cfg")
	assert_true(bool(saved.get_value("camera", "gradual_view_rotation", false)),
		"with gradual_view_rotation stored under [camera]")

	toggle.button_pressed = false
	await process_frames(2)
	assert_false(GameManager.gradual_view_rotation, "Flipping it back restores the classic view")
	assert_false(_grid().is_gradual_view_rotation_enabled())
	# Put the real preference back on disk, as the other settings tests do.
	menu._save_camera_settings()


# ---------------------------------------------------------------------------
# Saving the angle
# ---------------------------------------------------------------------------

func test_a_saved_course_remembers_an_angle_between_directions() -> void:
	var grid := _grid()
	await _set_gradual(true)
	grid.set_view_orientation(0.75)

	var snapshot := SaveManager.capture_course_snapshot()
	var view: Dictionary = snapshot.get("view", {})
	assert_almost_eq(float(view.get("angle", -1.0)), 0.75, 0.0001,
		"The exact angle rides along with the save")
	assert_eq(int(view.get("orientation", -1)), 1,
		"and the compass direction it is nearest is stored beside it")

	grid.set_view_orientation(0.0)
	assert_true(SaveManager.restore_course_snapshot(snapshot), "The snapshot loads")
	await process_frames(3)
	assert_almost_eq(grid.get_view_angle(), 0.75, 0.0001,
		"The loaded course is left at the angle it was saved at")
	assert_eq(grid.get_view_orientation(), 1,
		"and the four-way art reads the nearest direction")


# ---------------------------------------------------------------------------
# Buildings between the four drawings
# ---------------------------------------------------------------------------

func _clubhouse() -> Building:
	for building in main.entity_layer.get_all_buildings():
		if is_instance_valid(building) and building.is_clubhouse():
			return building
	return null


func test_a_building_shears_its_base_on_to_the_angled_tiles() -> void:
	var grid := _grid()
	var clubhouse := _clubhouse()
	assert_not_null(clubhouse, "The clubhouse is on the course")
	if clubhouse == null:
		return
	var drawing := clubhouse.get_node("Visual/Architecture") as CourseArchitecture
	assert_not_null(drawing)

	grid.set_view_orientation(0.0)
	await process_frames(1)
	assert_almost_eq(drawing.angle_offset, 0.0, 0.0001,
		"Facing north, the drawing is the untouched picture")

	await _set_gradual(true)
	await click(main.rotate_cw_btn)
	await _settle()
	assert_eq(drawing.facing, 0, "15° still uses the north picture")
	assert_almost_eq(drawing.angle_offset, STEP, 0.0001,
		"and shears it on to the angled tiles")

	# The click silhouette is carried with the picture, from its
	# quarter-turn shape rather than the last frame's shear.
	var footprint := Vector2(clubhouse.width * 64.0, clubhouse.height * 32.0)
	var base: PackedVector2Array = BuildingSprites.click_polygons(
		clubhouse.building_type, clubhouse.upgrade_level, 0, footprint)[0]
	var clicked: PackedVector2Array = clubhouse.get_click_polygons()[0]
	assert_almost_eq(clicked[0].x,
		CourseArchitecture.warp_point(base[0], footprint, 0, STEP).x, 0.01,
		"The clickable outline follows the sheared drawing")
	assert_almost_eq(clicked[0].y,
		CourseArchitecture.warp_point(base[0], footprint, 0, STEP).y, 0.01)

	# Six steps bring the course to east, where the next picture is untouched.
	for i in range(5):
		await click(main.rotate_cw_btn)
		await _settle()
	assert_eq(drawing.facing, 1, "A quarter turn swaps to the east picture")
	assert_almost_eq(drawing.angle_offset, 0.0, 0.0001,
		"which needs no shear")


func test_the_placement_ghost_shears_with_the_course() -> void:
	await _set_gradual(true)
	_grid().set_view_orientation(STEP)
	await process_frames(1)
	main.placement_preview._draw_building_ghost_shape(
		Vector2i(10, 10), "resort_hotel", Vector2i(4, 4), Color(0.3, 0.9, 0.3, 0.6))
	assert_almost_eq(main.placement_preview._building_ghost.angle_offset, STEP, 0.0001,
		"The ghost under the cursor is sheared like the building it will drop")


func test_every_step_of_a_full_turn_keeps_the_drawing_on_its_tiles() -> void:
	var clubhouse := _clubhouse()
	assert_not_null(clubhouse)
	if clubhouse == null:
		return
	var drawing := clubhouse.get_node("Visual/Architecture") as CourseArchitecture
	await _set_gradual(true)
	for step in range(24):
		var angle := float(step) / 6.0
		_grid().set_view_orientation(angle)
		await process_frames(2)
		assert_eq(drawing.facing, wrapi(roundi(angle), 0, 4),
			"Step %d draws the nearest of the four pictures" % step)
		var expected := fposmod(angle - float(drawing.facing) + 0.5, 1.0) - 0.5
		assert_almost_eq(drawing.angle_offset, expected, 0.0001,
			"Step %d carries the angle between the two pictures" % step)
