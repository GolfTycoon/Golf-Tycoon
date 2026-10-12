extends GameTest
## The HUD status column (pinned to the top-right corner) reads out one row per
## game feature. Weather, Wind and Seasons are optional, so their rows are
## hidden while the feature is off: a course playing without them has no rows
## left reading "Off" or "Year-round", and the column stays that much shorter.

const FEATURE_ROWS: Array[String] = ["_weather_row", "_wind_row", "_season_row"]

func before_each() -> void:
	super()
	# The column picks its compact width and starts collapsed on narrow
	# windows; pin a desktop window so the rows are laid out normally.
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)

## A column in the tree, freed after the test.
func _make_column() -> HUDStatusColumn:
	var column: HUDStatusColumn = autofree(HUDStatusColumn.new())
	add_child(column)
	return column

## Turn the three optional features on or off the way a new game does.
func _set_features(weather: bool, wind: bool, seasons: bool) -> void:
	GameManager.set_weather_enabled(weather)
	GameManager.set_wind_enabled(wind)
	GameManager.set_seasons_enabled(seasons)

func _row(column: HUDStatusColumn, field: String) -> Control:
	var row: Control = column.get(field)
	assert_not_null(row, "%s exists" % field)
	return row

func _row_visible(column: HUDStatusColumn, field: String) -> bool:
	return _row(column, field).visible

# ---------------------------------------------------------------------------
# Building the column
# ---------------------------------------------------------------------------

func test_every_feature_row_is_shown_while_its_feature_is_on() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	for field in FEATURE_ROWS:
		assert_true(_row_visible(column, field), "%s is shown while its feature is on" % field)

func test_every_feature_row_is_hidden_while_its_feature_is_off() -> void:
	_set_features(false, false, false)
	var column := _make_column()
	for field in FEATURE_ROWS:
		assert_false(_row_visible(column, field), "%s is hidden while its feature is off" % field)

func test_each_feature_row_hides_on_its_own() -> void:
	# One feature off at a time: only its row goes, its neighbours stay.
	for off in range(FEATURE_ROWS.size()):
		var features := [true, true, true]
		features[off] = false
		_set_features(features[0], features[1], features[2])
		var column := _make_column()
		for i in range(FEATURE_ROWS.size()):
			assert_eq(_row_visible(column, FEATURE_ROWS[i]), features[i],
				"%s follows its feature" % FEATURE_ROWS[i])
		column.queue_free()
		await process_frames(1)

func test_the_date_row_stays_whatever_the_features_do() -> void:
	# The calendar keeps ticking with all three features off, so the Date row
	# outlives them.
	_set_features(false, false, false)
	var column := _make_column()
	var date_label: Label = column.get("_date_label")
	assert_not_null(date_label)
	assert_true(date_label.get_parent().visible, "the Date row stays visible")

# ---------------------------------------------------------------------------
# The divider and the column height
# ---------------------------------------------------------------------------

func test_the_divider_before_weather_and_wind_goes_with_them() -> void:
	_set_features(false, false, true)
	var column := _make_column()
	var separator: HSeparator = column.get("_environment_separator")
	assert_not_null(separator)
	assert_false(separator.visible, "no divider is left dangling above nothing")

	# Either of the two rows keeps the divider it introduces.
	GameManager.set_wind_enabled(true)
	EventBus.new_game_started.emit()
	assert_true(separator.visible, "the divider stays while Wind is shown")

	GameManager.set_wind_enabled(false)
	GameManager.set_weather_enabled(true)
	EventBus.new_game_started.emit()
	assert_true(separator.visible, "the divider stays while Weather is shown")

func test_hiding_rows_shortens_the_column() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	var full_height: float = column.get_occupied_height()

	_set_features(false, false, false)
	EventBus.new_game_started.emit()
	await process_frames(2)
	assert_lt(column.get_occupied_height(), full_height,
		"a course with no weather, wind or seasons needs a shorter column")

# ---------------------------------------------------------------------------
# Starting a new game
# ---------------------------------------------------------------------------

func test_a_new_game_refreshes_the_rows() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	for field in FEATURE_ROWS:
		assert_true(_row_visible(column, field), "%s starts shown" % field)

	# A new game applies the Start New Game options (none of them on here) and
	# announces itself; no feature signal carries the change.
	_set_features(false, false, false)
	EventBus.new_game_started.emit()
	for field in FEATURE_ROWS:
		assert_false(_row_visible(column, field), "%s hides for the new course" % field)

	# ...and back the other way when the player turns them on again.
	_set_features(true, true, true)
	EventBus.new_game_started.emit()
	for field in FEATURE_ROWS:
		assert_true(_row_visible(column, field), "%s returns with its feature" % field)
