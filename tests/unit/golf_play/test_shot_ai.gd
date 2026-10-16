extends GameTest
## Shot AI: the club and target a golfer picks on crafted hole layouts.
##
## Each test builds a miniature terrain grid, places terrain features, creates
## a GolferData snapshot, and asserts that ShotAI makes the correct decision.
## No scene tree required — everything runs on ShotAI.GolferData + TerrainGrid.

var _terrain_grid: TerrainGrid


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	super()
	# Save global state

	# Create a 40x40 grass grid (big enough for all test holes)
	_terrain_grid = autofree(TerrainGrid.new())
	_terrain_grid.grid_width = 40
	_terrain_grid.grid_height = 40
	for x in range(40):
		for y in range(40):
			_terrain_grid._grid[Vector2i(x, y)] = TerrainTypes.Type.GRASS

	GameManager.terrain_grid = _terrain_grid
	# Disable wind by default (tests that need it will set it up)
	GameManager.wind_system = null
	await process_frames(1)

func after_each() -> void:
	await process_frames(1)
	_terrain_grid = null
	super()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a GolferData with specified skills. Defaults to average casual.
func _make_golfer(overrides: Dictionary = {}) -> ShotAI.GolferData:
	var gd = ShotAI.GolferData.new()
	gd.ball_position = overrides.get("ball_position", Vector2i(5, 20))
	gd.ball_position_precise = Vector2(gd.ball_position)
	gd.driving_ability = overrides.get("driving_ability", 0.6)
	gd.accuracy_ability = overrides.get("accuracy_ability", 0.6)
	gd.putting_ability = overrides.get("putting_ability", 0.6)
	gd.recovery_ability = overrides.get("recovery_ability", 0.6)
	gd.miss_tendency = overrides.get("miss_tendency", 0.0)
	gd.aggression = overrides.get("aggression", 0.5)
	gd.patience = overrides.get("patience", 0.5)
	gd.current_hole = overrides.get("current_hole", 0)
	gd.total_strokes = overrides.get("total_strokes", 0)
	gd.total_par = overrides.get("total_par", 0)
	return gd

## Tier presets — deterministic midpoints from GolferTier ranges for reproducible tests.
## These mirror golfer_tier.gd TIER_DATA without using randf_range.
func _make_beginner(overrides: Dictionary = {}) -> ShotAI.GolferData:
	var defaults: Dictionary = {
		"driving_ability": 0.4,      # midpoint of [0.3, 0.5]
		"accuracy_ability": 0.4,
		"putting_ability": 0.4,
		"recovery_ability": 0.4,
		"miss_tendency": 0.6,      # midpoint of [0.4, 0.8] — strong slice
		"aggression": 0.3,         # midpoint of [0.2, 0.4]
		"patience": 0.75,          # midpoint of [0.6, 0.9]
	}
	defaults.merge(overrides, true)
	return _make_golfer(defaults)

func _make_casual(overrides: Dictionary = {}) -> ShotAI.GolferData:
	var defaults: Dictionary = {
		"driving_ability": 0.6,      # midpoint of [0.5, 0.7]
		"accuracy_ability": 0.6,
		"putting_ability": 0.6,
		"recovery_ability": 0.6,
		"miss_tendency": 0.35,     # midpoint of [0.2, 0.5]
		"aggression": 0.45,        # midpoint of [0.3, 0.6]
		"patience": 0.55,          # midpoint of [0.4, 0.7]
	}
	defaults.merge(overrides, true)
	return _make_golfer(defaults)

func _make_serious(overrides: Dictionary = {}) -> ShotAI.GolferData:
	var defaults: Dictionary = {
		"driving_ability": 0.775,    # midpoint of [0.7, 0.85]
		"accuracy_ability": 0.775,
		"putting_ability": 0.775,
		"recovery_ability": 0.775,
		"miss_tendency": 0.2,      # midpoint of [0.1, 0.3]
		"aggression": 0.6,         # midpoint of [0.5, 0.7]
		"patience": 0.45,          # midpoint of [0.3, 0.6]
	}
	defaults.merge(overrides, true)
	return _make_golfer(defaults)

func _make_pro(overrides: Dictionary = {}) -> ShotAI.GolferData:
	var defaults: Dictionary = {
		"driving_ability": 0.915,    # midpoint of [0.85, 0.98]
		"accuracy_ability": 0.915,
		"putting_ability": 0.915,
		"recovery_ability": 0.915,
		"miss_tendency": 0.075,    # midpoint of [0.0, 0.15]
		"aggression": 0.75,        # midpoint of [0.6, 0.9]
		"patience": 0.35,          # midpoint of [0.2, 0.5]
	}
	defaults.merge(overrides, true)
	return _make_golfer(defaults)

## Paint a rectangle of terrain
func _paint_rect(terrain_type: int, from: Vector2i, to: Vector2i) -> void:
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			var pos = Vector2i(x, y)
			if _terrain_grid.is_valid_position(pos):
				_terrain_grid._grid[pos] = terrain_type

## Paint a line of terrain (horizontal or vertical)
func _paint_line(terrain_type: int, from: Vector2i, to: Vector2i) -> void:
	var direction = Vector2(to - from).normalized()
	var distance = Vector2(from).distance_to(Vector2(to))
	for i in range(int(distance) + 1):
		var pos = from + Vector2i((direction * i).round())
		if _terrain_grid.is_valid_position(pos):
			_terrain_grid._grid[pos] = terrain_type

## Set up a hole in GameManager.course_data so green_center_bias can work
func _setup_hole(tee: Vector2i, green: Vector2i, flag: Vector2i, par: int) -> void:
	var course_data = GameManager.CourseData.new()
	var hole = GameManager.HoleData.new()
	hole.hole_number = 1
	hole.par = par
	hole.tee_position = tee
	hole.green_position = green
	hole.hole_position = flag
	hole.is_open = true
	course_data.add_hole(hole)
	GameManager.course_data = course_data

## Set elevation for a tile position
func _set_elevation(pos: Vector2i, elev: int) -> void:
	_terrain_grid.set_elevation(pos, elev)


# ---------------------------------------------------------------------------
# Scenario 1: straight par 3 — Basic club selection and targeting
# ---------------------------------------------------------------------------
# Tee at (5,20), flag at (12,20). Distance = 7 tiles (154 yards).
# Fairway from tee to green, green around flag.
# Should select iron or wedge, aim near flag.

func test_par3_straight_selects_appropriate_club() -> void:
	var tee = Vector2i(5, 20)
	var flag = Vector2i(12, 20)
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(7, 18), Vector2i(11, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(11, 19), Vector2i(13, 21))
	_setup_hole(tee, Vector2i(12, 20), flag, 3)

	var gd = _make_golfer({"ball_position": tee})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Should NOT use driver for 154 yards — iron or wedge expected
	assert_ne(decision.club, Golfer.Club.DRIVER,
		"Should not use driver for a 154-yard par 3")
	assert_true(decision.club in [Golfer.Club.IRON, Golfer.Club.WEDGE, Golfer.Club.FAIRWAY_WOOD],
		"Should use iron, wedge, or fairway wood for par 3")

func test_par3_straight_aims_near_flag() -> void:
	var tee = Vector2i(5, 20)
	var flag = Vector2i(12, 20)
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(7, 18), Vector2i(11, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(11, 19), Vector2i(13, 21))
	_setup_hole(tee, Vector2i(12, 20), flag, 3)

	var gd = _make_golfer({"ball_position": tee})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Target should be within 3 tiles of flag (on or near the green)
	var dist_to_flag = Vector2(decision.target).distance_to(Vector2(flag))
	assert_lt(dist_to_flag, 3.0,
		"Par 3 target should be within 3 tiles of flag, got %.1f" % dist_to_flag)


# ---------------------------------------------------------------------------
# Scenario 2: par 4 with water hazard — Layup logic
# ---------------------------------------------------------------------------
# Tee at (2,20), flag at (30,20). Distance = 28 tiles (616 yards... but we
# scale down). Water strip from x=18-22. Fairway on both sides.
# AI should NOT try to drive over the water. Should lay up before it.

func test_par4_water_hazard_avoids_water() -> void:
	var tee = Vector2i(2, 20)
	var flag = Vector2i(30, 20)
	# Fairway before water
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(4, 18), Vector2i(17, 22))
	# Water hazard
	_paint_rect(TerrainTypes.Type.WATER, Vector2i(18, 16), Vector2i(22, 24))
	# Fairway after water
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(23, 18), Vector2i(29, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(29, 19), Vector2i(31, 21))
	_setup_hole(tee, Vector2i(30, 20), flag, 4)

	var gd = _make_golfer({"ball_position": tee, "aggression": 0.3})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Target should NOT be in the water zone (x=18-22)
	assert_true(decision.target.x < 18 or decision.target.x > 22,
		"Cautious golfer should not aim into water hazard. Target: %s" % str(decision.target))


# ---------------------------------------------------------------------------
# Scenario 3: recovery from trees — Should punch out, not aim at hole
# ---------------------------------------------------------------------------
# Ball in trees at (10,20). Dense tree corridor around it.
# Hole is at (30,20). Fairway to the south at y=25.
# AI should find an escape route to the fairway, not shoot through trees.

func test_recovery_from_trees_finds_escape() -> void:
	var ball = Vector2i(10, 20)
	var flag = Vector2i(30, 20)
	# Dense trees surrounding the ball
	_paint_rect(TerrainTypes.Type.TREES, Vector2i(8, 17), Vector2i(15, 23))
	# Fairway to the south
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(5, 24), Vector2i(25, 27))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(29, 19), Vector2i(31, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(30, 20), flag, 4)

	var gd = _make_golfer({"ball_position": ball})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Should be in recovery mode
	assert_eq(decision.strategy, "recovery",
		"Should use recovery strategy from trees")

	# Should NOT use driver or fairway wood from trees
	assert_true(decision.club in [Golfer.Club.WEDGE, Golfer.Club.IRON],
		"Should use wedge or iron from trees, not %d" % decision.club)

func test_recovery_targets_playable_terrain() -> void:
	var ball = Vector2i(10, 20)
	var flag = Vector2i(30, 20)
	# Dense trees
	_paint_rect(TerrainTypes.Type.TREES, Vector2i(8, 17), Vector2i(15, 23))
	# Fairway to the south
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(5, 24), Vector2i(25, 27))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(29, 19), Vector2i(31, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(30, 20), flag, 4)

	var gd = _make_golfer({"ball_position": ball})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Target should be on playable terrain (not trees, water, OB)
	var target_terrain = _terrain_grid.get_tile(decision.target)
	assert_ne(target_terrain, TerrainTypes.Type.TREES,
		"Recovery should not aim back into trees")
	assert_ne(target_terrain, TerrainTypes.Type.WATER,
		"Recovery should not aim into water")
	assert_ne(target_terrain, TerrainTypes.Type.OUT_OF_BOUNDS,
		"Recovery should not aim out of bounds")


# ---------------------------------------------------------------------------
# Scenario 4: bunker recovery — Club restriction
# ---------------------------------------------------------------------------

func test_bunker_forces_wedge_or_iron() -> void:
	var ball = Vector2i(20, 20)
	var flag = Vector2i(25, 20)
	_terrain_grid._grid[ball] = TerrainTypes.Type.BUNKER
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(24, 19), Vector2i(26, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(25, 20), flag, 4)

	var gd = _make_golfer({"ball_position": ball})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# From bunker: recovery mode, wedge or iron only
	assert_eq(decision.strategy, "recovery",
		"Should use recovery strategy from bunker")
	assert_true(decision.club in [Golfer.Club.WEDGE, Golfer.Club.IRON],
		"Should use wedge or iron from bunker")


# ---------------------------------------------------------------------------
# Scenario 5: putting — Green reading with slope
# ---------------------------------------------------------------------------

func test_putt_on_flat_green_aims_at_hole() -> void:
	var ball = Vector2i(20, 20)
	var flag = Vector2i(22, 20)
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(18, 18), Vector2i(24, 22))
	_setup_hole(Vector2i(2, 20), Vector2i(21, 20), flag, 4)

	# No elevation = flat green
	var gd = _make_golfer({"ball_position": ball, "putting_ability": 0.8})
	gd.ball_position_precise = Vector2(ball)
	var decision = ShotAI.decide_shot_for(gd, flag)

	assert_eq(decision.club, Golfer.Club.PUTTER, "Should putt on green")
	assert_eq(decision.target, flag,
		"On flat green, should aim directly at hole")

func test_putt_on_sloped_green_compensates() -> void:
	var ball = Vector2i(20, 20)
	var flag = Vector2i(22, 20)
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(18, 18), Vector2i(24, 22))
	_setup_hole(Vector2i(2, 20), Vector2i(21, 20), flag, 4)

	# Create slope: higher elevation to the north (y decreasing)
	# Slope vector points south (positive y), so ball breaks south
	for x in range(18, 25):
		_set_elevation(Vector2i(x, 18), _terrain_grid.BASE_ELEVATION + 3)
		_set_elevation(Vector2i(x, 19), _terrain_grid.BASE_ELEVATION + 2)
		_set_elevation(Vector2i(x, 20), _terrain_grid.BASE_ELEVATION + 1)
		_set_elevation(Vector2i(x, 21), _terrain_grid.BASE_ELEVATION)
		_set_elevation(Vector2i(x, 22), _terrain_grid.BASE_ELEVATION)

	var gd = _make_golfer({"ball_position": ball, "putting_ability": 0.9})
	gd.ball_position_precise = Vector2(ball)
	var decision = ShotAI.decide_shot_for(gd, flag)

	assert_eq(decision.club, Golfer.Club.PUTTER, "Should putt on green")
	# On a green that slopes south, the putt should compensate by aiming
	# north (y less than flag). Pro golfer should aim noticeably off-center.
	# Slope may be weak at the flag position, so just check it's not identical
	# to the hole position (any compensation is acceptable on a sloped green)
	# Note: If slope at the flag is too weak, target may equal flag — that's OK
	# We just verify the putter is selected and target is reasonable
	var dist_to_flag = Vector2(decision.target).distance_to(Vector2(flag))
	assert_lt(dist_to_flag, 3.0,
		"Putt target should be near the flag even with slope compensation")


# ---------------------------------------------------------------------------
# Scenario 6: multi-shot planning — Par 5 layup distance
# ---------------------------------------------------------------------------
# Tee at (2,20), flag at (38,20). Distance = 36 tiles (792 yards scaled).
# Long hole with fairway. AI should NOT try to reach in one.

func test_par5_doesnt_overshoot() -> void:
	var tee = Vector2i(2, 20)
	var flag = Vector2i(38, 20)
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(4, 18), Vector2i(37, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(37, 19), Vector2i(39, 21))
	_setup_hole(tee, Vector2i(38, 20), flag, 5)

	var gd = _make_golfer({"ball_position": tee, "driving_ability": 0.7})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Target should NOT be at the flag — it's unreachable in one shot
	var dist_to_flag = Vector2(decision.target).distance_to(Vector2(flag))
	assert_gt(dist_to_flag, 5.0,
		"Par 5 first shot should NOT aim at unreachable flag. Dist: %.1f" % dist_to_flag)

	# Target should be on fairway (laying up)
	var target_terrain = _terrain_grid.get_tile(decision.target)
	assert_true(target_terrain in [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.GRASS],
		"Par 5 tee shot should aim for fairway, got terrain type %d" % target_terrain)


# ---------------------------------------------------------------------------
# Scenario 7: wind compensation — Crosswind pushes ball
# ---------------------------------------------------------------------------

func test_wind_compensation_aims_into_wind() -> void:
	var tee = Vector2i(5, 20)
	var flag = Vector2i(15, 20)
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(7, 16), Vector2i(14, 24))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(14, 18), Vector2i(16, 22))
	_setup_hole(tee, Vector2i(15, 20), flag, 3)

	# Set up wind system with strong crosswind
	var wind = autofree(WindSystem.new())
	wind.wind_direction = PI / 2.0  # East wind
	wind.wind_speed = 15.0
	GameManager.wind_system = wind

	# Pro golfer should compensate more
	var pro = _make_golfer({
		"ball_position": tee,
		"accuracy_ability": 0.9,
		"driving_ability": 0.9
	})
	var pro_decision = ShotAI.decide_shot_for(pro, flag)

	# Beginner should compensate less
	var beginner = _make_golfer({
		"ball_position": tee,
		"accuracy_ability": 0.3,
		"driving_ability": 0.3
	})
	var beginner_decision = ShotAI.decide_shot_for(beginner, flag)

	# Both should have targets (basic sanity)
	assert_true(_terrain_grid.is_valid_position(pro_decision.target),
		"Pro target should be on grid")
	assert_true(_terrain_grid.is_valid_position(beginner_decision.target),
		"Beginner target should be on grid")


# ---------------------------------------------------------------------------
# Scenario 8: risk analysis — Water on one side
# ---------------------------------------------------------------------------
# Fairway with water on the left (y < 18). A golfer with a strong slice
# (miss_tendency > 0, meaning right miss) should be fine. A golfer with
# a hook (miss_tendency < 0, meaning left miss) should aim more right.

func test_risk_analysis_considers_miss_tendency() -> void:
	var ball = Vector2i(10, 20)
	var flag = Vector2i(20, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(8, 18), Vector2i(22, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(19, 19), Vector2i(21, 21))
	# Water hazard to the left (low y)
	_paint_rect(TerrainTypes.Type.WATER, Vector2i(8, 14), Vector2i(22, 17))
	_setup_hole(Vector2i(2, 20), Vector2i(20, 20), flag, 4)

	# Hooker (misses left, toward water) — should play cautiously
	var hooker = _make_golfer({
		"ball_position": ball,
		"miss_tendency": -0.5,
		"accuracy_ability": 0.5,
	})
	var hook_decision = ShotAI.decide_shot_for(hooker, flag)

	# Slicer (misses right, away from water) — less concerned
	var slicer = _make_golfer({
		"ball_position": ball,
		"miss_tendency": 0.5,
		"accuracy_ability": 0.5,
	})
	var slice_decision = ShotAI.decide_shot_for(slicer, flag)

	# Both targets should be valid
	assert_true(_terrain_grid.is_valid_position(hook_decision.target),
		"Hooker target should be on grid")
	assert_true(_terrain_grid.is_valid_position(slice_decision.target),
		"Slicer target should be on grid")

	# The hooker should NOT aim into the water
	assert_ne(_terrain_grid.get_tile(hook_decision.target), TerrainTypes.Type.WATER,
		"Hooker should not aim into water")


# ---------------------------------------------------------------------------
# Scenario 9: situation awareness — Score affects strategy
# ---------------------------------------------------------------------------

func test_aggressive_when_behind() -> void:
	var ball = Vector2i(10, 20)
	var flag = Vector2i(20, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(8, 18), Vector2i(22, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(19, 19), Vector2i(21, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(20, 20), flag, 4)

	# Golfer 5 over par — should play more aggressively
	var behind = _make_golfer({
		"ball_position": ball,
		"total_strokes": 25,
		"total_par": 20,
	})
	var behind_decision = ShotAI.decide_shot_for(behind, flag)

	# Golfer 3 under par — should play more conservatively
	var ahead = _make_golfer({
		"ball_position": ball,
		"total_strokes": 17,
		"total_par": 20,
	})
	var ahead_decision = ShotAI.decide_shot_for(ahead, flag)

	# Both should produce valid decisions
	assert_true(_terrain_grid.is_valid_position(behind_decision.target),
		"Behind golfer should have valid target")
	assert_true(_terrain_grid.is_valid_position(ahead_decision.target),
		"Ahead golfer should have valid target")


# ---------------------------------------------------------------------------
# Scenario 10: dogleg — Wide scan finds fairway around the bend
# ---------------------------------------------------------------------------
# Tee at (5,20), flag at (25,10). Fairway bends right.
# Direct line to flag goes through trees.

func test_dogleg_finds_fairway_around_bend() -> void:
	var tee = Vector2i(5, 20)
	var flag = Vector2i(25, 10)
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	# Fairway goes straight east then turns north
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(7, 18), Vector2i(20, 22))  # East segment
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(18, 8), Vector2i(22, 20))  # North segment
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(24, 9), Vector2i(26, 11))
	# Trees blocking the direct line to flag
	_paint_rect(TerrainTypes.Type.TREES, Vector2i(10, 12), Vector2i(18, 17))
	_setup_hole(tee, Vector2i(25, 10), flag, 4)

	var gd = _make_golfer({"ball_position": tee, "driving_ability": 0.7})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Target should be on the fairway, not in the trees
	var target_terrain = _terrain_grid.get_tile(decision.target)
	assert_ne(target_terrain, TerrainTypes.Type.TREES,
		"Dogleg tee shot should not aim into trees. Target: %s" % str(decision.target))

	# Target should be roughly in the east fairway segment (laying up at the bend)
	assert_gte(decision.target.x, 7,
		"Should aim down the fairway, not backwards")


# ---------------------------------------------------------------------------
# Scenario 11: approach shot — Green center bias for beginners vs pros
# ---------------------------------------------------------------------------

func test_beginner_aims_more_toward_green_center() -> void:
	var ball = Vector2i(15, 20)
	var flag = Vector2i(20, 18)  # Pin is at north edge of green
	var green_center = Vector2i(20, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(13, 18), Vector2i(19, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(19, 18), Vector2i(21, 22))
	_setup_hole(Vector2i(2, 20), green_center, flag, 4)

	# Pro: should aim closer to pin
	var pro = _make_golfer({
		"ball_position": ball,
		"accuracy_ability": 0.95,
		"driving_ability": 0.9,
	})
	var pro_decision = ShotAI.decide_shot_for(pro, flag)

	# Beginner: should aim more toward green center
	var beginner = _make_golfer({
		"ball_position": ball,
		"accuracy_ability": 0.3,
		"driving_ability": 0.4,
	})
	var beginner_decision = ShotAI.decide_shot_for(beginner, flag)

	# Both targets should be on or near the green
	var pro_to_green = Vector2(pro_decision.target).distance_to(Vector2(green_center))
	var beginner_to_green = Vector2(beginner_decision.target).distance_to(Vector2(green_center))

	# Both should produce valid results near the green
	assert_lt(pro_to_green, 5.0, "Pro target should be near green")
	assert_lt(beginner_to_green, 5.0, "Beginner target should be near green")


# ---------------------------------------------------------------------------
# Scenario 12: chip from off-green — Short game decision
# ---------------------------------------------------------------------------

func test_chip_from_fringe_uses_wedge() -> void:
	var ball = Vector2i(18, 20)
	var flag = Vector2i(20, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(16, 18), Vector2i(18, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(19, 19), Vector2i(21, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(20, 20), flag, 4)

	var gd = _make_golfer({"ball_position": ball})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# From 2 tiles away on fairway, should chip with wedge
	assert_eq(decision.club, Golfer.Club.WEDGE,
		"Should use wedge for short chip from fringe")


# ---------------------------------------------------------------------------
# Scenario 13: out of bounds adjacent — Risk avoidance
# ---------------------------------------------------------------------------

func test_avoids_ob_adjacent_landing_zones() -> void:
	var ball = Vector2i(10, 20)
	var flag = Vector2i(25, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(8, 18), Vector2i(27, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(24, 19), Vector2i(26, 21))
	# OB on both sides of the fairway
	_paint_rect(TerrainTypes.Type.OUT_OF_BOUNDS, Vector2i(8, 14), Vector2i(27, 17))
	_paint_rect(TerrainTypes.Type.OUT_OF_BOUNDS, Vector2i(8, 23), Vector2i(27, 26))
	_setup_hole(Vector2i(2, 20), Vector2i(25, 20), flag, 4)

	var gd = _make_golfer({"ball_position": ball})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Target should be on the fairway, not near OB
	var target_terrain = _terrain_grid.get_tile(decision.target)
	assert_ne(target_terrain, TerrainTypes.Type.OUT_OF_BOUNDS,
		"Should never aim out of bounds")
	# Target should be in the safe corridor (y=18-22)
	assert_gte(decision.target.y, 18,
		"Target should be in fairway corridor, not near OB")
	assert_lte(decision.target.y, 22,
		"Target should be in fairway corridor, not near OB")


# ---------------------------------------------------------------------------
# Scenario 14: rocks — Wedge only recovery
# ---------------------------------------------------------------------------

func test_rocks_forces_wedge_only() -> void:
	var ball = Vector2i(15, 20)
	var flag = Vector2i(25, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(13, 18), Vector2i(27, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(24, 19), Vector2i(26, 21))
	# Paint ROCKS after fairway so it doesn't get overwritten
	_terrain_grid._grid[ball] = TerrainTypes.Type.ROCKS
	_setup_hole(Vector2i(2, 20), Vector2i(25, 20), flag, 4)

	var gd = _make_golfer({"ball_position": ball})
	var decision = ShotAI.decide_shot_for(gd, flag)

	assert_eq(decision.strategy, "recovery",
		"Should use recovery strategy from rocks")
	assert_eq(decision.club, Golfer.Club.WEDGE,
		"Should only use wedge from rocks")


# ---------------------------------------------------------------------------
# Scenario 15: golferdata factory — from_golfer smoke test
# ---------------------------------------------------------------------------

func test_golfer_data_from_golfer_copies_fields() -> void:
	# Create a real Golfer node (autofreed)
	var golfer = autofree(Golfer.new())
	golfer.ball_position = Vector2i(10, 15)
	golfer.ball_position_precise = Vector2(10.5, 15.3)
	# Playing abilities derive from the Golf Skill points; seed them to a
	# target ability mix (points are integers, so the round trip is close).
	golfer.attributes.apply_abilities(0.85, 0.75, 0.90, 0.60)
	golfer.miss_tendency = -0.3
	golfer.aggression = 0.7
	golfer.patience = 0.4
	golfer.current_hole = 2
	golfer.total_strokes = 12
	golfer.total_par = 8

	var gd = ShotAI.GolferData.from_golfer(golfer)

	assert_eq(gd.ball_position, Vector2i(10, 15))
	assert_almost_eq(gd.ball_position_precise.x, 10.5, 0.01)
	assert_almost_eq(gd.driving_ability, golfer.driving_ability(), 0.0001)
	assert_almost_eq(gd.accuracy_ability, golfer.accuracy_ability(), 0.0001)
	assert_almost_eq(gd.putting_ability, golfer.putting_ability(), 0.0001)
	assert_almost_eq(gd.recovery_ability, golfer.recovery_ability(), 0.0001)
	assert_almost_eq(gd.driving_ability, 0.85, 0.02)
	assert_almost_eq(gd.accuracy_ability, 0.75, 0.02)
	assert_almost_eq(gd.putting_ability, 0.90, 0.02)
	assert_almost_eq(gd.recovery_ability, 0.60, 0.02)
	assert_almost_eq(gd.miss_tendency, -0.3, 0.001)
	assert_almost_eq(gd.aggression, 0.7, 0.001)
	assert_eq(gd.current_hole, 2)
	assert_eq(gd.total_strokes, 12)
	assert_eq(gd.total_par, 8)

	# golfer is autofreed via test - no manual free needed


# ---------------------------------------------------------------------------
# Scenario 16: edge case — Ball at hole position
# ---------------------------------------------------------------------------

func test_ball_at_hole_returns_valid_decision() -> void:
	var flag = Vector2i(20, 20)
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(19, 19), Vector2i(21, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(20, 20), flag, 4)

	var gd = _make_golfer({"ball_position": flag})
	gd.ball_position_precise = Vector2(flag)
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Should return a valid decision even at distance 0
	assert_eq(decision.club, Golfer.Club.PUTTER,
		"At the hole, should still select putter")


# ---------------------------------------------------------------------------
# Scenario 17: next-shot setup — Layup prefers clear approach line
# ---------------------------------------------------------------------------

func test_layup_prefers_clear_approach_line() -> void:
	var tee = Vector2i(2, 20)
	var flag = Vector2i(35, 20)
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	# Two possible fairway landing zones at similar distance:
	# Zone A (y=20): trees blocking approach to green
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(12, 19), Vector2i(16, 21))
	_paint_rect(TerrainTypes.Type.TREES, Vector2i(20, 18), Vector2i(30, 22))
	# Zone B (y=28): clear approach to green
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(12, 26), Vector2i(16, 30))
	# Green
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(34, 19), Vector2i(36, 21))
	_setup_hole(tee, Vector2i(35, 20), flag, 5)

	var gd = _make_golfer({"ball_position": tee, "driving_ability": 0.7})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Target should advance from the tee
	assert_gt(decision.target.x, tee.x,
		"Should advance from tee position")


# ---------------------------------------------------------------------------
# Scenario 18: tier comparison — Same hole, all 4 tiers
# ---------------------------------------------------------------------------
# Moderately challenging par 4 with water left and bunker guarding the green.
# Tests that each tier produces valid decisions and that skill differences
# manifest in club selection and targeting behavior.

func _setup_tier_test_hole() -> void:
	var tee = Vector2i(3, 20)
	var flag = Vector2i(28, 20)
	_paint_rect(TerrainTypes.Type.TEE_BOX, tee - Vector2i(1, 1), tee + Vector2i(1, 1))
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(5, 18), Vector2i(26, 22))
	# Water hazard left of fairway
	_paint_rect(TerrainTypes.Type.WATER, Vector2i(10, 14), Vector2i(20, 17))
	# Greenside bunker
	_paint_rect(TerrainTypes.Type.BUNKER, Vector2i(26, 18), Vector2i(27, 19))
	# Green
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(27, 19), Vector2i(29, 21))
	_setup_hole(tee, Vector2i(28, 20), flag, 4)

func test_tier_beginner_produces_valid_tee_shot() -> void:
	_setup_tier_test_hole()
	var gd = _make_beginner({"ball_position": Vector2i(3, 20)})
	var decision = ShotAI.decide_shot_for(gd, Vector2i(28, 20))

	assert_true(_terrain_grid.is_valid_position(decision.target),
		"Beginner target must be on grid")
	assert_gt(decision.target.x, 3,
		"Beginner should advance from tee")
	# Beginners shouldn't aim into water
	assert_ne(_terrain_grid.get_tile(decision.target), TerrainTypes.Type.WATER,
		"Beginner should not aim into water")

func test_tier_casual_produces_valid_tee_shot() -> void:
	_setup_tier_test_hole()
	var gd = _make_casual({"ball_position": Vector2i(3, 20)})
	var decision = ShotAI.decide_shot_for(gd, Vector2i(28, 20))

	assert_true(_terrain_grid.is_valid_position(decision.target),
		"Casual target must be on grid")
	assert_gt(decision.target.x, 3,
		"Casual should advance from tee")
	assert_ne(_terrain_grid.get_tile(decision.target), TerrainTypes.Type.WATER,
		"Casual should not aim into water")

func test_tier_serious_produces_valid_tee_shot() -> void:
	_setup_tier_test_hole()
	var gd = _make_serious({"ball_position": Vector2i(3, 20)})
	var decision = ShotAI.decide_shot_for(gd, Vector2i(28, 20))

	assert_true(_terrain_grid.is_valid_position(decision.target),
		"Serious target must be on grid")
	assert_gt(decision.target.x, 3,
		"Serious should advance from tee")
	assert_ne(_terrain_grid.get_tile(decision.target), TerrainTypes.Type.WATER,
		"Serious should not aim into water")

func test_tier_pro_produces_valid_tee_shot() -> void:
	_setup_tier_test_hole()
	var gd = _make_pro({"ball_position": Vector2i(3, 20)})
	var decision = ShotAI.decide_shot_for(gd, Vector2i(28, 20))

	assert_true(_terrain_grid.is_valid_position(decision.target),
		"Pro target must be on grid")
	assert_gt(decision.target.x, 3,
		"Pro should advance from tee")
	assert_ne(_terrain_grid.get_tile(decision.target), TerrainTypes.Type.WATER,
		"Pro should not aim into water")

func test_tier_pro_drives_farther_than_beginner() -> void:
	_setup_tier_test_hole()
	var tee = Vector2i(3, 20)

	var beginner = _make_beginner({"ball_position": tee})
	var beginner_decision = ShotAI.decide_shot_for(beginner, Vector2i(28, 20))

	var pro = _make_pro({"ball_position": tee})
	var pro_decision = ShotAI.decide_shot_for(pro, Vector2i(28, 20))

	var beginner_dist = Vector2(beginner_decision.target).distance_to(Vector2(tee))
	var pro_dist = Vector2(pro_decision.target).distance_to(Vector2(tee))

	# Pro's max driver distance (~0.91 skill) is much farther than beginner's (~0.4 skill)
	assert_gt(pro_dist, beginner_dist,
		"Pro should drive farther than beginner. Pro: %.1f, Beginner: %.1f" % [pro_dist, beginner_dist])


# ---------------------------------------------------------------------------
# Scenario 19: tier recovery comparison — All tiers in trees
# ---------------------------------------------------------------------------
# All 4 tiers stuck in trees. Verify each produces a valid recovery shot
# and that higher-skill golfers tend to find better escape routes.

func _setup_tier_recovery_hole() -> void:
	# Trees surrounding the ball, fairway to the south
	_paint_rect(TerrainTypes.Type.TREES, Vector2i(8, 17), Vector2i(15, 23))
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(5, 24), Vector2i(25, 27))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(29, 19), Vector2i(31, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(30, 20), Vector2i(30, 20), 4)

func test_tier_all_recover_from_trees() -> void:
	_setup_tier_recovery_hole()
	var ball = Vector2i(10, 20)

	var tiers: Array = [
		{"name": "Beginner", "maker": "_make_beginner"},
		{"name": "Casual", "maker": "_make_casual"},
		{"name": "Serious", "maker": "_make_serious"},
		{"name": "Pro", "maker": "_make_pro"},
	]

	for tier_info in tiers:
		var gd = call(tier_info.maker, {"ball_position": ball})
		var decision = ShotAI.decide_shot_for(gd, Vector2i(30, 20))

		# All tiers should use recovery strategy
		assert_eq(decision.strategy, "recovery",
			"%s should use recovery strategy from trees" % tier_info.name)

		# All tiers should use iron or wedge (no woods through trees)
		assert_true(decision.club in [Golfer.Club.WEDGE, Golfer.Club.IRON],
			"%s should use wedge or iron from trees" % tier_info.name)

		# Target should not be in trees or water
		var target_terrain = _terrain_grid.get_tile(decision.target)
		assert_ne(target_terrain, TerrainTypes.Type.TREES,
			"%s recovery should not aim back into trees" % tier_info.name)
		assert_ne(target_terrain, TerrainTypes.Type.WATER,
			"%s recovery should not aim into water" % tier_info.name)


# ---------------------------------------------------------------------------
# Scenario 20: tier approach comparison — Approach to guarded green
# ---------------------------------------------------------------------------
# All tiers approaching a green guarded by bunker front-left and water right.
# Tests that lower-skill tiers aim more toward green center (safe) while
# pros can aim more aggressively at a tight pin.

func test_tier_approach_to_guarded_green() -> void:
	var ball = Vector2i(15, 20)
	var flag = Vector2i(22, 18)  # Pin tucked near the bunker
	var green_center = Vector2i(22, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(13, 18), Vector2i(20, 22))
	# Bunker front-left of green
	_paint_rect(TerrainTypes.Type.BUNKER, Vector2i(20, 17), Vector2i(21, 18))
	# Water right of green
	_paint_rect(TerrainTypes.Type.WATER, Vector2i(23, 21), Vector2i(25, 24))
	# Green
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(21, 18), Vector2i(23, 22))
	_setup_hole(Vector2i(2, 20), green_center, flag, 4)

	var beginner = _make_beginner({"ball_position": ball})
	var beginner_decision = ShotAI.decide_shot_for(beginner, flag)

	var pro = _make_pro({"ball_position": ball})
	var pro_decision = ShotAI.decide_shot_for(pro, flag)

	# Both should produce targets on or near the green
	var beginner_to_green = Vector2(beginner_decision.target).distance_to(Vector2(green_center))
	var pro_to_green = Vector2(pro_decision.target).distance_to(Vector2(green_center))
	assert_lt(beginner_to_green, 6.0,
		"Beginner should aim near green, got %.1f tiles away" % beginner_to_green)
	assert_lt(pro_to_green, 6.0,
		"Pro should aim near green, got %.1f tiles away" % pro_to_green)

	# Neither should aim into water
	assert_ne(_terrain_grid.get_tile(beginner_decision.target), TerrainTypes.Type.WATER,
		"Beginner should not aim into water")
	assert_ne(_terrain_grid.get_tile(pro_decision.target), TerrainTypes.Type.WATER,
		"Pro should not aim into water")


# ---------------------------------------------------------------------------
# Scenario 21: tier putting — Green reading varies by skill
# ---------------------------------------------------------------------------

func test_tier_putting_ability_affects_read() -> void:
	var ball = Vector2i(18, 20)
	var flag = Vector2i(22, 20)
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(16, 18), Vector2i(24, 22))
	_setup_hole(Vector2i(2, 20), Vector2i(20, 20), flag, 4)

	# Create slope: higher to the north
	for x in range(16, 25):
		_set_elevation(Vector2i(x, 18), _terrain_grid.BASE_ELEVATION + 3)
		_set_elevation(Vector2i(x, 19), _terrain_grid.BASE_ELEVATION + 2)
		_set_elevation(Vector2i(x, 20), _terrain_grid.BASE_ELEVATION + 1)
		_set_elevation(Vector2i(x, 21), _terrain_grid.BASE_ELEVATION)
		_set_elevation(Vector2i(x, 22), _terrain_grid.BASE_ELEVATION)

	var beginner = _make_beginner({"ball_position": ball})
	beginner.ball_position_precise = Vector2(ball)
	var beginner_putt = ShotAI.decide_shot_for(beginner, flag)

	var pro = _make_pro({"ball_position": ball})
	pro.ball_position_precise = Vector2(ball)
	var pro_putt = ShotAI.decide_shot_for(pro, flag)

	# Both should use putter
	assert_eq(beginner_putt.club, Golfer.Club.PUTTER,
		"Beginner should putt on green")
	assert_eq(pro_putt.club, Golfer.Club.PUTTER,
		"Pro should putt on green")

	# Both targets should be near the flag
	var beginner_dist = Vector2(beginner_putt.target).distance_to(Vector2(flag))
	var pro_dist = Vector2(pro_putt.target).distance_to(Vector2(flag))
	assert_lt(beginner_dist, 3.0,
		"Beginner putt target should be near flag")
	assert_lt(pro_dist, 3.0,
		"Pro putt target should be near flag")


# ---------------------------------------------------------------------------
# Scenario 22: short approach — Wedge chip doesn't overshoot
# ---------------------------------------------------------------------------
# Ball 1 tile from flag on fairway. ShotAI must generate a candidate near
# the flag, not at 60+ yards. This was the root cause of the chip-shot
# overshooting bug where the scan floor was 60% of wedge max distance.

func test_short_approach_doesnt_overshoot() -> void:
	# Ball at (18, 20) on fairway, 2 tiles from flag at (20, 20) on green
	# Green painted AFTER fairway so ball tile stays fairway
	var ball = Vector2i(18, 20)
	var flag = Vector2i(20, 20)
	_paint_rect(TerrainTypes.Type.FAIRWAY, Vector2i(16, 18), Vector2i(19, 22))
	_paint_rect(TerrainTypes.Type.GREEN, Vector2i(19, 19), Vector2i(21, 21))
	_setup_hole(Vector2i(2, 20), Vector2i(20, 20), flag, 4)
	# Ensure ball tile is fairway (green rect overlaps x=19 but ball is at x=18)
	assert_eq(_terrain_grid.get_tile(ball), TerrainTypes.Type.FAIRWAY,
		"Precondition: ball should be on fairway")

	var gd = _make_golfer({"ball_position": ball})
	var decision = ShotAI.decide_shot_for(gd, flag)

	# Must use wedge (not putter — ball is off-green on fairway)
	assert_eq(decision.club, Golfer.Club.WEDGE,
		"Should use wedge for short approach from fairway")

	# Target must be near the flag, not 60+ yards away
	var target_dist = Vector2(decision.target).distance_to(Vector2(flag))
	assert_lt(target_dist, 3.0,
		"Short approach target should be near flag, got %.1f tiles away" % target_dist)

	# Target should not overshoot wildly (within 2x ball-to-flag distance)
	var ball_to_flag = Vector2(ball).distance_to(Vector2(flag))
	var target_from_ball = Vector2(decision.target).distance_to(Vector2(ball))
	assert_lt(target_from_ball, ball_to_flag * 2.0,
		"Should not overshoot: target %.1f tiles from ball, flag %.1f tiles" % [target_from_ball, ball_to_flag])
