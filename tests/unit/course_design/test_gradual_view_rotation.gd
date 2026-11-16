extends GameTest
## Gradual View Rotation — fractional GridProjection math, TerrainGrid tweened
## 15-degree steps, unwrapped north wrap-around, option-off settling, and
## SaveManager view.angle / camera.gradual_view_rotation persistence.

var grid: TerrainGrid = null


func before_each() -> void:
	super()
	GameManager.set_gradual_view_rotation(true)
	grid = TerrainGrid.new()
	grid.grid_width = 32
	grid.grid_height = 24
	add_child_autofree(grid)


# ---------------------------------------------------------------------------
# GridProjection fractional angles
# ---------------------------------------------------------------------------

func test_whole_turns_keep_exact_classic_projection_and_bounds() -> void:
	var size := Vector2i(32, 24)
	var tile := Vector2(64, 32)
	var span := float(size.x + size.y) * 0.5
	var expected_bounds := Rect2(Vector2.ZERO, Vector2(span * tile.x, span * tile.y))
	for facing in range(4):
		var proj := GridProjection.new(size, tile, float(facing))
		assert_eq(proj.world_bounds(), expected_bounds,
			"whole turn %d keeps exact classic world_bounds" % facing)
		assert_eq(proj.nearest_orientation(), facing)
		var sample := Vector2(7.25, 13.75)
		var world := proj.project(sample)
		var back := proj.unproject(world)
		assert_almost_eq(back.x, sample.x, 0.0001)
		assert_almost_eq(back.y, sample.y, 0.0001)


func test_fractional_angles_round_trip_and_enclose_all_grid_corners() -> void:
	var size := Vector2i(40, 28)
	var tile := Vector2(64, 32)
	for step in range(24):
		var angle := float(step) * TerrainGrid.GRADUAL_TURN_STEP
		var proj := GridProjection.new(size, tile, angle)
		var bounds := proj.world_bounds()
		for corner in [
			Vector2.ZERO,
			Vector2(size.x, 0),
			Vector2(size.x, size.y),
			Vector2(0, size.y),
		]:
			var world := proj.project(corner)
			assert_true(bounds.grow(0.01).has_point(world),
				"world_bounds encloses corner %s at step %d" % [corner, step])
		var probe := Vector2(18.4, 9.6)
		var round_trip := proj.unproject(proj.project(probe))
		assert_almost_eq(round_trip.x, probe.x, 0.0005)
		assert_almost_eq(round_trip.y, probe.y, 0.0005)


func test_nearest_orientation_picks_the_closest_compass_quarter_turn() -> void:
	var proj := GridProjection.new(Vector2i(16, 16), Vector2(64, 32), 0.0)
	for pair in [
		[0.0, 0], [0.49, 0], [0.51, 1], [1.49, 1],
		[1.51, 2], [2.49, 2], [2.51, 3], [3.49, 3], [3.51, 0], [3.99, 0],
	]:
		proj.set_orientation(float(pair[0]))
		assert_eq(proj.nearest_orientation(), int(pair[1]),
			"angle %.2f maps to quarter turn %d" % [float(pair[0]), int(pair[1])])


# ---------------------------------------------------------------------------
# TerrainGrid tweened stepping & unwrapped wrap-around
# ---------------------------------------------------------------------------

func test_one_gradual_step_turns_15_degrees_over_tween_and_six_steps_make_a_quarter_turn() -> void:
	grid.set_view_angle(0.0)
	grid.rotate_view_cw()
	assert_true(grid.is_view_turning(), "gradual rotation runs a tween")
	await wait_for_signal(grid.view_rotation_settled, 1.0)
	assert_false(grid.is_view_turning(), "the tween stops after settling")
	assert_almost_eq(grid.get_view_angle(), 1.0 / 6.0, 0.001,
		"one step is 15 degrees (1/6 of a quarter turn)")
	assert_eq(grid.get_view_orientation(), 0,
		"nearest 4-way orientation stays north under 45 degrees")

	for _i in range(5):
		grid.rotate_view_cw()
	await wait_for_signal(grid.view_rotation_settled, 1.0)
	assert_almost_eq(grid.get_view_angle(), 1.0, 0.001,
		"six 15-degree steps add up to one exact quarter turn")
	assert_eq(grid.get_view_orientation(), 1)


func test_turning_past_north_keeps_going_in_the_direction_turned() -> void:
	grid.set_view_angle(0.0)
	var observed: Array[float] = []
	grid.view_rotated.connect(func(_o: int, _iso: bool): observed.append(grid.get_view_angle()))

	grid.rotate_view_ccw()
	await wait_for_signal(grid.view_rotation_settled, 1.0)
	assert_almost_eq(grid.get_view_angle(), 3.0 + 5.0 / 6.0, 0.001,
		"CCW from north lands at 345 degrees (23/6)")
	for angle in observed:
		assert_gt(angle, 3.0, "every intermediate frame stays on the CCW arc past north (got %.3f)" % angle)

	observed.clear()
	grid.rotate_view_cw()
	await wait_for_signal(grid.view_rotation_settled, 1.0)
	assert_almost_eq(grid.get_view_angle(), 0.0, 0.001,
		"CW from 345 degrees returns cleanly to 0")
	for angle in observed:
		assert_true(angle >= 3.8 or is_equal_approx(angle, 0.0),
			"CW past north does not jump backward through south (got %.3f)" % angle)


func test_turning_gradual_off_settles_to_nearest_quarter_turn_and_restores_instant_turns() -> void:
	grid.set_view_angle(2.0 / 6.0) # 30 degrees -> nearest 0
	var settled := [0]
	grid.view_rotation_settled.connect(func(): settled[0] += 1)
	GameManager.set_gradual_view_rotation(false)
	assert_almost_eq(grid.get_view_angle(), 0.0, 0.001,
		"turning the option off at 30 degrees settles back to north")
	assert_eq(settled[0], 1, "settling notifies view_rotation_settled")

	grid.rotate_view_cw()
	assert_false(grid.is_view_turning(), "classic mode turns immediately without a tween")
	assert_almost_eq(grid.get_view_angle(), 1.0, 0.001)
	assert_eq(grid.get_view_orientation(), 1)

	GameManager.set_gradual_view_rotation(true)
	grid.set_view_angle(1.0 + 4.0 / 6.0) # 150 degrees -> nearest 2 (south)
	GameManager.set_gradual_view_rotation(false)
	assert_almost_eq(grid.get_view_angle(), 2.0, 0.001,
		"turning the option off past the midpoint settles forward to south")


func test_gradual_rotation_works_while_simulation_is_paused() -> void:
	var previous_scale := Engine.time_scale
	Engine.time_scale = 0.0
	grid.set_view_angle(0.0)
	grid.rotate_view_cw()
	await wait_for_signal(grid.view_rotation_settled, 1.0)
	Engine.time_scale = previous_scale
	assert_almost_eq(grid.get_view_angle(), 1.0 / 6.0, 0.001,
		"the 0.18s tween still runs on wall-clock time while paused")


# ---------------------------------------------------------------------------
# SaveManager persistence (settings.cfg + course save view.angle)
# ---------------------------------------------------------------------------

func test_settings_file_persists_and_defaults_gradual_view_rotation() -> void:
	var off := ConfigFile.new()
	off.set_value("camera", "gradual_view_rotation", false)
	SaveManager._apply_camera_settings(off)
	assert_false(GameManager.gradual_view_rotation)

	var on := ConfigFile.new()
	on.set_value("camera", "gradual_view_rotation", true)
	SaveManager._apply_camera_settings(on)
	assert_true(GameManager.gradual_view_rotation)

	var older := ConfigFile.new()
	older.set_value("camera", "min_zoom", 0.5)
	GameManager.set_gradual_view_rotation(false)
	SaveManager._apply_camera_settings(older)
	assert_true(GameManager.gradual_view_rotation,
		"older settings files without the key default to gradual view rotation on")


func test_save_data_round_trips_exact_view_angle_and_supports_legacy_orientation() -> void:
	var saved_grid := SaveManager.terrain_grid
	SaveManager.terrain_grid = grid
	grid.set_view_angle(1.5) # 135 degrees (nearest quarter turn = 2)

	var data := SaveManager._build_save_data()
	var view_block: Dictionary = data.get("view", {})
	assert_almost_eq(float(view_block.get("angle", -1.0)), 1.5, 0.001,
		"saves store the exact fractional view.angle")
	assert_eq(int(view_block.get("orientation", -1)), 2,
		"and keep whole-turn view.orientation for backward compatibility")

	grid.set_view_angle(0.0)
	GameManager.set_gradual_view_rotation(true)
	SaveManager._apply_save_data(data)
	assert_almost_eq(grid.get_view_angle(), 1.5, 0.001,
		"loading restores the exact saved angle when gradual rotation is on")

	grid.set_view_angle(0.0)
	GameManager.set_gradual_view_rotation(false)
	SaveManager._apply_save_data(data)
	assert_almost_eq(grid.get_view_angle(), 2.0, 0.001,
		"loading snaps a saved fractional angle to the nearest quarter turn when gradual is off")

	var legacy := data.duplicate(true)
	(legacy["view"] as Dictionary).erase("angle")
	(legacy["view"] as Dictionary)["orientation"] = 3
	GameManager.set_gradual_view_rotation(true)
	SaveManager._apply_save_data(legacy)
	assert_almost_eq(grid.get_view_angle(), 3.0, 0.001,
		"older saves without view.angle load cleanly from view.orientation")

	SaveManager.terrain_grid = saved_grid
