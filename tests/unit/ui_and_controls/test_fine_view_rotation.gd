extends GameTest
## Fine Rotation (Settings → Controls → Camera → Fine Rotation): the course
## turns in eighth turns — 45°, eight facings round the compass — instead of
## quarter turns, so the view can rest facing a diagonal as well as north, east,
## south and west. It is on out of the box, and turning it off puts the course
## back on the four cardinal facings.
##
## The projection is the part that has to keep its promises: whichever step the
## player chose, projected points must round-trip through the grid, the four
## cardinal facings must land exactly where they always did, and the art — one
## drawing per quarter turn — must be the drawing of the cardinal facing a
## diagonal sits nearest.

const QUARTER := GridProjection.ORIENTATION_COUNT
const EIGHTH := GridProjection.EIGHTH_TURN_COUNT

## SaveManager keeps its own handles on the course, so a test that saves or
## loads has to hand them over (and take them back afterwards: GameState does
## not snapshot SaveManager).
func after_each() -> void:
	SaveManager.set_references(null, null)
	super()


## The classic maths the projection replaced, kept here so the four cardinal
## facings can be held to the positions they have always had.
func _classic_rotate(offset: Vector2, steps: int) -> Vector2:
	match steps % QUARTER:
		1:
			return Vector2(-offset.y, offset.x)
		2:
			return Vector2(-offset.x, -offset.y)
		3:
			return Vector2(offset.y, -offset.x)
		_:
			return offset


func _classic_project(grid: TerrainGrid, point: Vector2, facing: int) -> Vector2:
	var center := Vector2(grid.grid_width * 0.5, grid.grid_height * 0.5)
	var span := center.x + center.y
	var bounds := Rect2(Vector2.ZERO,
		Vector2(span * grid.tile_width, span * grid.tile_height))
	var origin := bounds.get_center()
	var r := _classic_rotate(point - center, facing)
	return origin + Vector2((r.x - r.y) * grid.tile_width * 0.5,
		(r.x + r.y) * grid.tile_height * 0.5)


# ---------------------------------------------------------------------------
# The preference
# ---------------------------------------------------------------------------

func test_the_course_turns_in_eighth_turns_out_of_the_box() -> void:
	assert_true(GameManager.fine_view_rotation,
		"Fine rotation is the default: the compass has its diagonals")


func test_the_settings_file_stores_and_defaults_the_preference() -> void:
	var off := ConfigFile.new()
	off.set_value("camera", "fine_view_rotation", false)
	SaveManager._apply_camera_settings(off)
	assert_false(GameManager.fine_view_rotation, "a stored off preference is honoured")

	var on := ConfigFile.new()
	on.set_value("camera", "fine_view_rotation", true)
	SaveManager._apply_camera_settings(on)
	assert_true(GameManager.fine_view_rotation, "and so is a stored on one")

	var older := ConfigFile.new()
	older.set_value("camera", "min_zoom", 0.6)
	GameManager.set_fine_view_rotation(false)
	SaveManager._apply_camera_settings(older)
	assert_true(GameManager.fine_view_rotation,
		"a settings file from before the preference existed keeps the finer step")


func test_the_settings_toggle_writes_the_preference_with_the_camera() -> void:
	# The file is the player's own, so whatever it held is put back afterwards.
	var path := ProjectSettings.globalize_path(SaveManager.SETTINGS_PATH)
	var had_file := FileAccess.file_exists(path)
	var before := FileAccess.get_file_as_string(path) if had_file else ""

	var menu: SettingsMenu = add_child_autofree(SettingsMenu.new())
	menu._set_fine_view_rotation(false)
	var config := ConfigFile.new()
	config.load(SaveManager.SETTINGS_PATH)
	assert_false(bool(config.get_value("camera", "fine_view_rotation", true)),
		"the toggle writes the preference into the camera section")

	if had_file:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(before)
		restore.close()
	else:
		DirAccess.remove_absolute(path)
	GameManager.set_fine_view_rotation(true)


# ---------------------------------------------------------------------------
# The facings
# ---------------------------------------------------------------------------

func test_a_full_turn_holds_eight_facings_on_the_finer_step() -> void:
	var projection := GridProjection.new(Vector2i(16, 16), Vector2(64, 32))
	projection.set_steps_per_turn(EIGHTH)
	assert_eq(projection.steps_per_turn, EIGHTH)
	for facing in EIGHTH:
		projection.set_orientation(facing)
		assert_eq(projection.eighth_turns, facing, "facing %d is an eighth turn" % facing)
		assert_almost_eq(rad_to_deg(projection.angle_radians()), float(facing) * 45.0, 0.0001,
			"facing %d is %d degrees round from north" % [facing, facing * 45])


func test_the_four_cardinal_facings_land_exactly_where_they_always_did() -> void:
	var grid := make_grid(12, 10)
	await process_frames(1)
	GameManager.set_fine_view_rotation(true)
	for facing in QUARTER:
		grid.set_view_eighths(facing * 2)
		for x in range(13):
			for y in range(11):
				var point := Vector2(x, y)
				assert_eq(grid.grid_point_to_screen(point),
					_classic_project(grid, point, facing),
					"the quarter turn to facing %d is unchanged at %s" % [facing, point])


func test_every_facing_round_trips_through_the_grid() -> void:
	var grid := make_grid(12, 10)
	await process_frames(1)
	for facing in EIGHTH:
		grid.set_view_eighths(facing)
		for x in range(12):
			for y in range(10):
				var point := Vector2(x, y) + Vector2(0.5, 0.5)
				var world := grid.grid_to_screen_precise(point)
				assert_almost_eq(grid.screen_to_grid_precise(world).x, point.x, 0.0001,
					"facing %d: %s comes back across" % [facing, point])
				assert_almost_eq(grid.screen_to_grid_precise(world).y, point.y, 0.0001,
					"facing %d: %s comes back down" % [facing, point])


func test_a_diagonal_wears_the_art_of_the_cardinal_facing_it_sits_nearest() -> void:
	var grid := make_grid(12, 12)
	await process_frames(1)
	var expected := {0: 0, 1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 0}
	for facing in EIGHTH:
		grid.set_view_eighths(facing)
		assert_eq(grid.get_view_facing(), expected[facing],
			"facing %d of eight draws the quarter-turn art of %d" % [facing, expected[facing]])


func test_changing_the_step_keeps_the_facing_the_course_is_on() -> void:
	var projection := GridProjection.new(Vector2i(16, 16), Vector2(64, 32))
	# Quarter turns are two eighth turns, so a cardinal facing survives both
	# ways round untouched.
	for facing in QUARTER:
		projection.set_steps_per_turn(QUARTER)
		projection.set_orientation(facing)
		projection.set_steps_per_turn(EIGHTH)
		assert_eq(projection.eighth_turns, facing * 2,
			"turning the finer step on leaves facing %d where it was" % facing)
		projection.set_steps_per_turn(QUARTER)
		assert_eq(projection.orientation, facing,
			"and turning it off brings the same facing back")


func test_a_diagonal_settles_on_its_nearest_cardinal_facing_when_the_step_goes_coarse() -> void:
	var projection := GridProjection.new(Vector2i(16, 16), Vector2(64, 32))
	projection.set_steps_per_turn(EIGHTH)
	var expected := {1: 1, 3: 2, 5: 3, 7: 0}
	for facing in expected:
		projection.set_steps_per_turn(EIGHTH)
		projection.set_orientation(facing)
		projection.set_steps_per_turn(QUARTER)
		assert_eq(projection.orientation, expected[facing],
			"the diagonal %d of eight falls back to the cardinal %d" % [facing, expected[facing]])


# ---------------------------------------------------------------------------
# The course
# ---------------------------------------------------------------------------

func test_a_fresh_course_has_eight_facings_to_turn_through() -> void:
	GameManager.set_fine_view_rotation(true)
	var grid := make_grid(12, 12)
	await process_frames(1)
	assert_eq(grid.get_view_step_count(), EIGHTH)
	assert_eq(grid.get_view_orientation(), 0, "and starts facing north")


func test_eight_steps_of_the_arrows_bring_the_course_back_to_north() -> void:
	GameManager.set_fine_view_rotation(true)
	var grid := make_grid(12, 12)
	await process_frames(1)
	for step in EIGHTH:
		grid.rotate_view_cw()
		assert_eq(grid.get_view_orientation(), wrapi(step + 1, 0, EIGHTH))
	assert_eq(grid.get_view_orientation(), 0, "a full turn of the compass returns north")


func test_the_setting_moves_a_live_course_onto_the_diagonals_and_back() -> void:
	var grid := make_grid(12, 12)
	await process_frames(1)
	GameManager.set_fine_view_rotation(true)
	assert_eq(grid.get_view_step_count(), EIGHTH, "the live course follows the setting on")
	grid.set_view_eighths(1)
	assert_eq(grid.get_view_orientation(), 1, "and can rest on north-east")

	GameManager.set_fine_view_rotation(false)
	assert_eq(grid.get_view_step_count(), QUARTER, "and back to quarter turns")
	assert_eq(grid.get_view_eighths(), 2,
		"with the diagonal it was on settled on its nearest cardinal facing")


func test_the_art_of_a_course_on_a_diagonal_is_a_cardinal_one() -> void:
	GameManager.set_fine_view_rotation(true)
	var grid := make_grid(12, 12)
	var entities := make_entity_layer(grid)
	GameManager.terrain_grid = grid
	GameManager.entity_layer = entities
	await process_frames(1)
	var registry: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	var clubhouse := entities.place_building("clubhouse", Vector2i(4, 4), registry)
	assert_not_null(clubhouse, "a clubhouse stands on the course")
	if clubhouse == null:
		return
	grid.set_view_eighths(5)  # south-west
	clubhouse.set_position_in_grid(clubhouse.grid_position)
	var architecture: CourseArchitecture = clubhouse.get_node("Visual/Architecture")
	assert_eq(grid.get_view_facing(), 3, "south-west wears the west drawing")
	assert_eq(architecture.facing, 3, "and the clubhouse is drawn with it")


# ---------------------------------------------------------------------------
# The compass chip
# ---------------------------------------------------------------------------

func test_the_chip_names_every_point_of_the_compass() -> void:
	assert_eq(OrientationToggleButton.letter_for(0, QUARTER), "N")
	assert_eq(OrientationToggleButton.letter_for(1, QUARTER), "E")
	assert_eq(OrientationToggleButton.letter_for(2, QUARTER), "S")
	assert_eq(OrientationToggleButton.letter_for(3, QUARTER), "W")
	var eighths := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for facing in EIGHTH:
		assert_eq(OrientationToggleButton.letter_for(facing, EIGHTH), eighths[facing],
			"facing %d of eight reads %s" % [facing, eighths[facing]])
	# The cardinal facings keep their letters whichever step is in force.
	for facing in QUARTER:
		assert_eq(OrientationToggleButton.letter_for(facing * 2, EIGHTH),
			OrientationToggleButton.letter_for(facing, QUARTER))


func test_the_diagonal_arrows_point_at_their_corner() -> void:
	# Each arrow's tip is the corner pixel it points at: the eighth-turn arrows
	# are the four cardinal ones with a diagonal between each pair.
	var tips := {
		1: Vector2i(8, 0),   # north-east: the top-right corner
		3: Vector2i(8, 8),   # south-east
		5: Vector2i(0, 8),   # south-west
		7: Vector2i(0, 0),   # north-west
	}
	for facing in tips:
		var rows: Array = OrientationToggleButton.arrow_rows(facing, EIGHTH)
		var tip: Vector2i = tips[facing]
		assert_eq(String(rows[tip.y])[tip.x], "x",
			"the arrow for facing %d reaches its corner" % facing)
	# The cardinal arrows are the ones the coarse chip has always drawn.
	for facing in QUARTER:
		assert_eq(OrientationToggleButton.arrow_rows(facing * 2, EIGHTH),
			OrientationToggleButton.arrow_rows(facing, QUARTER),
			"facing %d keeps its arrow" % facing)


func test_the_chip_follows_the_step_the_course_turns_in() -> void:
	var chip := OrientationToggleButton.new()
	add_child_autofree(chip)
	var one_letter: float = chip.custom_minimum_size.x
	chip.facings = EIGHTH
	chip.orientation = 1
	assert_eq(chip.letter, "NE", "the chip points at the diagonal")
	assert_gt(chip.custom_minimum_size.x, one_letter,
		"and widens by the room its second letter needs")
	chip.orientation = 2
	assert_eq(chip.letter, "E", "east is the next step round")
	assert_almost_eq(chip.custom_minimum_size.x, one_letter, 0.5,
		"and a one-letter facing takes the chip back to its usual footprint")


func test_the_banner_hands_the_number_of_facings_to_the_chip() -> void:
	WorldMap.active_location_id = "monterey"
	var banner: CourseLocationBanner = add_child_autofree(CourseLocationBanner.new())
	banner.set_orientation(1, EIGHTH)
	assert_eq(banner.orientation_toggle.facings, EIGHTH)
	assert_eq(banner.orientation_toggle.letter, "NE")
	banner.set_orientation(1, QUARTER)
	assert_eq(banner.orientation_toggle.facings, QUARTER)
	assert_eq(banner.orientation_toggle.letter, "E",
		"one step of four is east, one step of eight is north-east")


# ---------------------------------------------------------------------------
# The save file
# ---------------------------------------------------------------------------

func test_a_diagonal_facing_survives_a_save() -> void:
	GameManager.set_fine_view_rotation(true)
	var grid := make_grid(12, 12)
	GameManager.terrain_grid = grid
	SaveManager.set_references(grid, null)
	await process_frames(1)
	grid.set_view_eighths(3)  # south-east
	var data := SaveManager._build_save_data()
	assert_eq(int(data["view"]["facing_eighths"]), 3,
		"the facing is written in eighth turns, whichever step is in force")

	SaveManager._apply_save_data({"view": {"facing_eighths": 5}})
	assert_eq(grid.get_view_eighths(), 5, "and comes back as the facing it was")


func test_a_save_from_before_the_diagonals_opens_facing_the_same_way() -> void:
	var grid := make_grid(12, 12)
	GameManager.terrain_grid = grid
	SaveManager.set_references(grid, null)
	await process_frames(1)
	# Older saves name a quarter turn; every quarter turn is two eighth turns.
	for quarter in QUARTER:
		SaveManager._apply_save_data({"view": {"orientation": quarter}})
		assert_eq(grid.get_view_eighths(), quarter * 2,
			"a saved quarter turn %d still faces %d" % [quarter, quarter * 2])
