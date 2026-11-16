extends MainSceneTest
## The status column of the running game: Weather, Wind and Seasons each keep
## their row only while that feature is on for the course being played.
##
## The column is built into the real HUD, so this also checks the wiring that
## refreshes it: starting the course is what announces the features the Start
## New Game screen (or a quick start, which turns all three off) chose.

## All three rows read out a mod's system, so the official environment mods are
## installed and enabled before the scene is built, the way a player's Browse
## Mods session leaves the game: a course can only play with a feature whose
## mod is there to provide it.
func before_all() -> void:
	install_environment_mods()
	await super()


func after_all() -> void:
	uninstall_environment_mods()
	super()


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

func test_live_rows_share_uniform_size_centered_text_and_shorten_large_balances() -> void:
	main._on_main_menu_new_game("Uniform HUD test", CourseTheme.Type.PARKLAND, -1, {
		"terrain_seed": COURSE_SEED,
		"starting_money": GameManager.UNLIMITED_MONEY,
		"features": {"weather": true, "wind": true, "seasons": true},
	})
	await process_frames(NEW_COURSE_FRAMES)
	var column: HUDStatusColumn = main.hud_status_column
	var money_label := column.get("_money_label") as Label
	assert_eq(money_label.text, "$ 999.99M",
		"unlimited starting balance shortens to fit the live HUD money row")
	assert_null(column.get("_funds_row").get_node_or_null("Content/ValueBackground/ValueContent/Trend"),
		"funds row has no trend arrow")

	for field in ["_funds_row", "_season_row", "_reputation_row", "_rating_row", "_weather_row", "_wind_row"]:
		var row: Control = column.get(field)
		var pill: Control = row.get_node("Content/ValueBackground")
		assert_true(row.visible, "%s is visible in the live HUD" % field)
		assert_almost_eq(row.size.x, float(UIConstants.HUD_COLUMN_WIDTH), 0.5,
			"%s matches the uniform HUD column width" % field)
		assert_almost_eq(row.size.y, float(HUDStatusColumn.ROW_HEIGHT), 0.5,
			"%s matches the uniform HUD row height" % field)
		assert_almost_eq(pill.size.y, float(HUDStatusColumn.VALUE_BACKGROUND_HEIGHT), 0.5,
			"%s pill matches the uniform HUD pill height" % field)
		if field != "_rating_row":
			var value_label := pill.get_node("ValueContent/Value") as Label
			assert_eq(value_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER,
				"%s centers its text horizontally" % field)

	GameManager.money = 1500000
	EventBus.money_changed.emit(999999999, 1500000)
	await process_frames(2)
	assert_eq(money_label.text, "$ 1.5M", "1.5 million balance shortens with M suffix")
	assert_almost_eq((column.get("_funds_row") as Control).size.x, float(UIConstants.HUD_COLUMN_WIDTH), 0.5,
		"funds row width stays unchanged after shortening")

	GameManager.money = 2500000000000
	EventBus.money_changed.emit(1500000, 2500000000000)
	await process_frames(2)
	assert_eq(money_label.text, "$ 2.5T", "trillion balance shortens with T suffix")
	assert_almost_eq((column.get("_funds_row") as Control).size.x, float(UIConstants.HUD_COLUMN_WIDTH), 0.5,
		"funds row width stays unchanged at trillions")

	await set_window(Vector2i(844, 390))
	var compact_metrics := HUDStatusColumn.metrics_for_font_size(HUDStatusColumn.COMPACT_VALUE_FONT_SIZE)
	for field in ["_funds_row", "_season_row", "_reputation_row", "_rating_row", "_weather_row", "_wind_row"]:
		var row: Control = column.get(field)
		var pill: Control = row.get_node("Content/ValueBackground")
		var icon: Control = row.get_node("Content/IconBackground/Icon")
		assert_almost_eq(row.size.y, float(compact_metrics["row_height"]), 0.5,
			"%s shrinks height on compact layout" % field)
		assert_almost_eq(pill.size.y, float(compact_metrics["value_background_height"]), 0.5,
			"%s pill shrinks height on compact layout" % field)
		assert_almost_eq(icon.size.x, float(compact_metrics["icon_size"]), 0.5,
			"%s icon shrinks on compact layout" % field)

	await set_window(DESIGN_WINDOW)


