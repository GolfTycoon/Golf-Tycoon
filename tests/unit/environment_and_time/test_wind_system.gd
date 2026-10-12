extends GameTest
## WindSystem: the day's breeze and its gentle drift from day to day, the dead
## calm the Wind feature leaves when it is off, how a crosswind pushes a shot
## aside and a head- or tailwind changes its length — less for the lofted clubs,
## not at all for the putter — and how the wind reads out.

## The wind blows towards +x, from the west (see WindSystem.wind_direction).
const FROM_THE_WEST := PI * 1.5
## The wind blows towards +y (down the screen), from the north.
const FROM_THE_NORTH := 0.0
const NORTHWARD := Vector2(0, -1)
const SOUTHWARD := Vector2(0, 1)
const EASTWARD := Vector2(1, 0)

var wind: WindSystem


func before_each() -> void:
	super()
	seed(4321)
	GameManager.wind_enabled = true
	wind = WindSystem.new()
	add_child_autofree(wind)


func _blow(direction: float, speed: float) -> void:
	wind.wind_direction = direction
	wind.wind_speed = speed


# ---------------------------------------------------------------------------
# The day's wind
# ---------------------------------------------------------------------------

func test_a_new_day_brings_a_breeze() -> void:
	for i in range(20):
		wind.generate_daily_wind()
		assert_between(wind.wind_speed, 2.0, 20.0, "A new wind blows between 2 and 20 mph")
		assert_between(wind.wind_direction, 0.0, TAU, "from any direction")


func test_the_wind_drifts_a_little_from_day_to_day() -> void:
	var drifted := 0
	for day in range(200):
		var direction := wind.wind_direction
		var speed := wind.wind_speed
		wind.update_wind_daily()
		assert_between(wind.wind_speed, 0.0, 30.0, "The wind stays between calm and 30 mph")
		var turned := absf(angle_difference(direction, wind.wind_direction))
		if turned <= 0.35 + 0.0001 and absf(wind.wind_speed - speed) <= 1.5 + 0.0001:
			drifted += 1
	# A rare front reshuffles the wind; every other day only nudges it.
	assert_gt(drifted, 160, "Most days the wind only drifts")
	assert_lt(drifted, 200, "and now and then a front changes it altogether")


func test_a_new_day_moves_the_wind_on() -> void:
	watch_signals(EventBus)
	EventBus.day_changed.emit(GameManager.current_day + 1)
	assert_signal_emitted(EventBus, "wind_changed", "The wind changes with the day")


func test_with_the_feature_off_the_air_is_calm() -> void:
	_blow(FROM_THE_WEST, 18.0)
	GameManager.wind_enabled = false
	wind.update_wind_daily()
	assert_eq(wind.wind_speed, 0.0, "Switching the wind off calms it on the next day")
	wind.generate_daily_wind()
	assert_eq(wind.wind_speed, 0.0, "and no new day brings it back")
	wind.wind_speed = 18.0
	assert_eq(wind.get_wind_displacement(NORTHWARD, 20.0, Golfer.Club.DRIVER), Vector2.ZERO,
		"Wind that is off pushes no shot aside")
	assert_eq(wind.get_distance_modifier(SOUTHWARD, Golfer.Club.DRIVER), 1.0, "nor changes its length")


# ---------------------------------------------------------------------------
# Wind on a shot
# ---------------------------------------------------------------------------

func test_a_crosswind_pushes_the_shot_downwind() -> void:
	_blow(FROM_THE_WEST, 20.0)
	var drive := wind.get_wind_displacement(NORTHWARD, 20.0, Golfer.Club.DRIVER)
	assert_gt(drive.x, 0.0, "A west wind pushes a northbound drive east")
	assert_almost_eq(drive.y, 0.0, 0.0001, "and neither longer nor shorter")
	var half := wind.get_wind_displacement(NORTHWARD, 10.0, Golfer.Club.DRIVER)
	assert_almost_eq(half.x, drive.x / 2.0, 0.0001, "Half the distance, half the push")
	var wedge := wind.get_wind_displacement(NORTHWARD, 20.0, Golfer.Club.WEDGE)
	assert_lt(wedge.x, drive.x, "A wedge is pushed less than a driver")
	assert_eq(wind.get_wind_displacement(NORTHWARD, 20.0, Golfer.Club.PUTTER), Vector2.ZERO,
		"and a putt not at all")
	assert_almost_eq(wind.get_wind_displacement(EASTWARD, 20.0, Golfer.Club.DRIVER).length(), 0.0, 0.0001,
		"A shot with the wind behind it is not pushed aside")


func test_a_headwind_shortens_and_a_tailwind_lengthens_the_shot() -> void:
	_blow(FROM_THE_NORTH, 20.0)
	var with_it := wind.get_distance_modifier(SOUTHWARD, Golfer.Club.DRIVER)
	var into_it := wind.get_distance_modifier(NORTHWARD, Golfer.Club.DRIVER)
	assert_gt(with_it, 1.0, "A tailwind carries the ball further")
	assert_lt(into_it, 1.0, "A headwind holds it up")
	assert_lt(1.0 - into_it, 0.15, "by up to 15%")
	assert_almost_eq(wind.get_distance_modifier(EASTWARD, Golfer.Club.DRIVER), 1.0, 0.0001,
		"A crosswind leaves the length alone")
	assert_eq(wind.get_distance_modifier(NORTHWARD, Golfer.Club.PUTTER), 1.0, "and so does any wind on a putt")
	_blow(FROM_THE_NORTH, 1000.0)
	assert_between(wind.get_distance_modifier(SOUTHWARD, Golfer.Club.DRIVER), 0.75, 1.15, "Even a gale is capped")
	assert_between(wind.get_distance_modifier(NORTHWARD, Golfer.Club.DRIVER), 0.75, 1.15, "both ways")


# ---------------------------------------------------------------------------
# Reading it out
# ---------------------------------------------------------------------------

func test_the_wind_reads_out_as_a_compass_point_and_a_strength() -> void:
	var points := {0.0: "N", PI / 4.0: "NE", PI / 2.0: "E", PI: "S", PI * 1.5: "W", PI * 1.75: "NW"}
	for direction in points:
		_blow(direction, 10.0)
		assert_eq(wind.get_direction_text(), points[direction], "%.2f rad reads %s" % [direction, points[direction]])
	var strengths := {3.0: "Calm", 7.0: "Light", 12.0: "Moderate", 17.0: "Strong", 25.0: "Very Strong"}
	for speed in strengths:
		_blow(0.0, speed)
		assert_eq(wind.get_strength_text(), strengths[speed], "%d mph reads %s" % [speed, strengths[speed]])
