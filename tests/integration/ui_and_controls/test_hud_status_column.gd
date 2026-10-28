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

func test_live_course_populates_rating_stars_and_hover_tooltip() -> void:
	var column: HUDStatusColumn = await _start_with_features({
		"weather": false, "wind": false, "seasons": false,
	})
	var rating_row: Control = column.get("_rating_row")
	var stars := rating_row.get_node_or_null("Content/ValueBackground/ValueContent/Stars") as CourseRatingStars
	var action := rating_row.get_node_or_null("Action") as Button
	assert_not_null(stars, "live HUD rating row carries CourseRatingStars")
	assert_true(stars.rated, "starting a course populates the star icons")
	assert_gte(stars.stars, 1.0, "live course rating is within the 1..5 star range")
	assert_true(action.tooltip_text.contains("%.1f" % stars.stars),
		"hover tooltip shows the live numeric rating (got: %s)" % action.tooltip_text)

