extends MainSceneTest
## The status column of the running game: Weather, Wind and Seasons each keep
## their row only while that feature is on for the course being played.
##
## The column is built into the real HUD, so this also checks the wiring that
## refreshes it: starting the course is what announces the features the Start
## New Game screen (or a quick start, which turns all three off) chose.

## Start a course the way the Start New Game screen does, with `features` as
## the player left the Weather, Wind and Seasons options.
func _start_with_features(features: Dictionary) -> HUDStatusColumn:
	main._on_main_menu_new_game("Feature test", CourseTheme.Type.PARKLAND, -1, {
		"terrain_seed": COURSE_SEED,
		"features": features,
	})
	await process_frames(NEW_COURSE_FRAMES)
	return main.hud_status_column

func _row_visible(column: HUDStatusColumn, field: String) -> bool:
	var row: Control = column.get(field)
	assert_not_null(row, "%s exists" % field)
	return row != null and row.visible

func test_a_new_course_shows_a_row_per_feature_it_plays_with() -> void:
	var column: HUDStatusColumn = await _start_with_features({
		"weather": false, "wind": true, "seasons": false,
	})
	assert_false(_row_visible(column, "_weather_row"), "Weather is off: no Weather row")
	assert_true(_row_visible(column, "_wind_row"), "Wind is on: the Wind row stays")
	assert_false(_row_visible(column, "_season_row"), "Seasons are off: no Season row")
	assert_null(column.get("_date_row"), "The calendar date lives in the location banner, not the status column")

func test_a_course_with_every_feature_shows_every_row() -> void:
	var column: HUDStatusColumn = await _start_with_features({
		"weather": true, "wind": true, "seasons": true,
	})
	for field in ["_weather_row", "_wind_row", "_season_row"]:
		assert_true(_row_visible(column, field), "%s is shown for a course playing with it" % field)
