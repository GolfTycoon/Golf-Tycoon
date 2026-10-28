extends GameTest
## The HUD status column (pinned to the top-right corner) reads out one card
## per stat. Every card carries its own background, border, value and
## right-hand icon; there is no game-mode (PLAYING / PAUSED) row at the top any more,
## the column itself has no background, and it can no longer be collapsed.
## Weather, Wind and Seasons are optional, so their cards are hidden while the
## feature is off: a course playing without them has no rows left reading
## "Off" or "Year-round", and the column stays that much shorter.

const FEATURE_ROWS: Array[String] = ["_weather_row", "_wind_row", "_season_row"]
const ROW_FIELDS: Array[String] = ["_funds_row", "_season_row",
	"_reputation_row", "_rating_row", "_weather_row", "_wind_row"]

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

func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

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

func test_the_date_row_is_gone_the_calendar_lives_in_the_location_banner() -> void:
	# The date moved to the top-left CourseLocationBanner, so the status column
	# carries no Date card even with every feature switched on.
	_set_features(true, true, true)
	var column := _make_column()
	assert_null(column.get("_date_row"), "there is no Date card in the column")
	assert_null(column.get("_date_label"), "and no date label behind it")
	for label in _nodes_of_class(column, "Label"):
		var text: String = (label as Label).text
		assert_false(GameCalendar.format_date(GameManager.current_day) == text,
			"no row prints the calendar date (saw %s)" % text)

# ---------------------------------------------------------------------------
# Row design: no game-mode row, and every stat is its own card
# ---------------------------------------------------------------------------

func test_the_play_pause_row_is_gone() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	assert_null(column.get("_game_mode_label"), "there is no PLAYING / PAUSED label")
	assert_null(column.get("_game_mode_icon"), "and no game-mode icon")
	for label in _nodes_of_class(column, "Label"):
		var text: String = (label as Label).text
		assert_false(text.contains("PLAYING"),
			"no row reports the running state (saw %s)" % text)
		assert_false(text.contains("PAUSED"),
			"no row reports the paused state (saw %s)" % text)

func test_every_row_is_a_card_with_a_background_a_border_an_icon_and_a_value() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	for field in ROW_FIELDS:
		var card: Control = _row(column, field)
		assert_true(card is PanelContainer, "%s is a panel card" % field)
		var style := (card.get_node("Content/ValueBackground") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		assert_not_null(style, "%s has its own background style" % field)
		assert_gt(style.bg_color.a, 0.0, "%s paints a background" % field)
		var borders := style.border_width_left + style.border_width_top \
			+ style.border_width_right + style.border_width_bottom
		assert_gt(borders, 0, "%s paints a border" % field)
		assert_true(style.corner_radius_top_left > 0, "%s has rounded card corners" % field)

		var icon := card.get_node_or_null("Content/IconBackground/Icon") as TextureRect
		assert_not_null(icon, "%s carries an icon" % field)
		if icon:
			assert_not_null(icon.texture, "%s's icon is painted" % field)
			assert_eq(icon.custom_minimum_size, Vector2(HUDStatusColumn.ICON_SIZE,
				HUDStatusColumn.ICON_SIZE), "%s's icon uses the enlarged pixel grid" % field)

		var value := card.get_node_or_null("Content/ValueBackground/ValueContent/Value") as Label
		assert_not_null(value, "%s carries a value" % field)
		if value:
			assert_ne(value.text, "", "%s shows its value" % field)

func test_rows_show_values_before_right_hand_icons_without_titles() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	await process_frames(2)
	for field in ROW_FIELDS:
		var card := _row(column, field)
		var content := card.get_node("Content") as HBoxContainer
		var value_background := content.get_node("ValueBackground") as PanelContainer
		var icon_background := content.get_node("IconBackground") as PanelContainer
		assert_null(content.get_node_or_null("Title"), "%s has no title" % field)
		assert_lt(value_background.get_index(), icon_background.get_index(), "%s places its value before the icon" % field)
		assert_gt(icon_background.position.x, value_background.position.x, "%s places its icon on the right" % field)
		assert_lt(icon_background.position.y, value_background.position.y, "%s raises its icon background" % field)
		assert_eq(icon_background.size, Vector2(40, 40), "%s has a circular icon background" % field)
		var icon_style := icon_background.get_theme_stylebox("panel") as StyleBoxFlat
		assert_eq(icon_style.corner_radius_top_left, 20, "%s has fully rounded icon corners" % field)
		var value_style := value_background.get_theme_stylebox("panel") as StyleBoxFlat
		assert_gt(value_style.corner_radius_top_left, 4, "%s has more rounded value corners" % field)
	var funds := _row(column, "_funds_row").get_node("Content/ValueBackground/ValueContent")
	assert_gt(funds.get_node("Trend").get_index(), funds.get_node("Value").get_index(),
		"the funds trend follows the value")

func test_dynamic_icons_update_their_accented_medallion_and_value_pill() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	var card := _row(column, "_weather_row")
	var icon := card.get_node("Content/IconBackground/Icon") as TextureRect
	var icon_background := icon.get_parent() as PanelContainer
	var value_background := card.get_node("Content/ValueBackground") as PanelContainer
	var accent := Color(0.2, 0.6, 0.9)
	column._set_row_icon(icon, PixelIcon.Kind.RAIN, accent)
	var icon_style := icon_background.get_theme_stylebox("panel") as StyleBoxFlat
	var value_style := value_background.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(icon_style.border_color, Color(accent, 0.9), "medallion follows its icon")
	assert_eq(value_style.border_color, Color(accent, 0.58), "value pill matches the medallion")
	assert_gt(icon_style.bg_color.b, value_style.bg_color.b, "the medallion is more richly tinted")
	assert_gt(value_style.shadow_size, 0, "the pill has depth over the course")

func test_cards_are_double_height() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	await process_frames(2)
	for field in ROW_FIELDS:
		var card := _row(column, field)
		assert_almost_eq(card.size.y, 48.0, 0.5, "%s is 48 pixels tall" % field)
		var icon := card.get_node("Content/IconBackground/Icon") as TextureRect
		var value := card.get_node("Content/ValueBackground/ValueContent/Value") as Label
		assert_eq(icon.custom_minimum_size, Vector2(32, 32), "the icon is doubled")
		assert_eq(value.get_theme_font_size("font_size"), 24, "the value font is doubled")
		var icon_background := card.get_node("Content/IconBackground") as Control
		assert_almost_eq(icon.global_position.y + icon.size.y / 2.0,
			icon_background.global_position.y + icon_background.size.y / 2.0, 1.0,
			"%s keeps its icon centered in its circle" % field)

func test_card_backgrounds_fit_their_values_and_remain_right_aligned() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	await process_frames(3)
	for field in ROW_FIELDS:
		var card := _row(column, field)
		var parent := card.get_parent() as Control
		assert_lt(card.size.x, parent.size.x, "%s does not fill the column" % field)
		assert_almost_eq(card.position.x + card.size.x, parent.size.x, 1.0,
			"%s is aligned to the right" % field)
	var funds := _row(column, "_funds_row")
	column._set_value_text(column._money_label, "$ 1")
	await process_frames(2)
	var short_width := funds.size.x
	column._set_value_text(column._money_label, "$ 1,234,567")
	await process_frames(2)
	assert_gt(funds.size.x, short_width, "the background grows with the value")
	column._set_value_text(column._money_label, "$ 1")
	await process_frames(2)
	assert_almost_eq(funds.size.x, short_width, 1.0, "the background shrinks again")

func test_the_rows_are_separate_cards_not_a_shared_bar() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	var cards: Array = []
	for field in ROW_FIELDS:
		var card: Control = _row(column, field)
		assert_false(cards.has(card), "%s is its own card" % field)
		cards.append(card)
	# No divider is needed between cards, and none is left in the column.
	for node in _nodes_of_class(column, "HSeparator"):
		fail_test("the column still carries a divider: %s" % node)

func test_the_money_reputation_and_rating_cards_stay_clickable() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	var clicks := {"money": 0, "reputation": 0, "rating": 0}
	column.money_clicked.connect(func(): clicks["money"] += 1)
	column.reputation_clicked.connect(func(): clicks["reputation"] += 1)
	column.rating_clicked.connect(func(): clicks["rating"] += 1)
	for pair in [["_funds_row", "money"], ["_reputation_row", "reputation"], ["_rating_row", "rating"]]:
		var action := _row(column, pair[0]).get_node_or_null("Action") as Button
		assert_not_null(action, "%s has a click target" % pair[0])
		action.pressed.emit()
		assert_eq(clicks[pair[1]], 1, "clicking %s emits its signal" % pair[0])

func test_the_column_has_no_background_of_its_own() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	# The cards are the column's only surface: the panel behind them draws
	# nothing, so the course shows through between them.
	var style := column.get_theme_stylebox("panel")
	assert_true(style is StyleBoxEmpty,
		"the column panel draws no background or border (got %s)" % style.get_class())

func test_the_column_has_no_collapse_row() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	assert_null(column.get("_collapse_button"), "there is no collapse control")
	for button in _nodes_of_class(column, "Button"):
		assert_false((button as Button).name == "CollapseButton",
			"no collapse button is left in the column")
	# Every card is shown, on every window size: nothing can hide them now.
	for field in ROW_FIELDS:
		assert_true(_row(column, field).is_visible_in_tree(), "%s is shown" % field)

func test_the_cards_stay_shown_on_a_compact_window() -> void:
	# The column narrows on a phone, but the old auto-collapse went with the
	# collapse handle, so every card is still there.
	get_window().size = Vector2i(390, 844)
	await process_frames(2)
	_set_features(true, true, true)
	var column := _make_column()
	for field in ROW_FIELDS:
		assert_true(_row(column, field).is_visible_in_tree(),
			"%s stays on screen on a compact window" % field)
	assert_almost_eq(column.custom_minimum_size.x, 150.0, 0.5, "the column is the compact width")
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)

# ---------------------------------------------------------------------------
# The block that introduces Weather and Wind
# ---------------------------------------------------------------------------

func test_the_environment_block_goes_with_weather_and_wind() -> void:
	_set_features(false, false, true)
	var column := _make_column()
	var block: Control = column.get("_environment_block")
	assert_not_null(block)
	assert_false(block.visible, "no weather/wind block is left dangling above nothing")

	# Either of the two cards keeps the block it lives in.
	GameManager.set_wind_enabled(true)
	EventBus.new_game_started.emit()
	assert_true(block.visible, "the block stays while Wind is shown")

	GameManager.set_wind_enabled(false)
	GameManager.set_weather_enabled(true)
	EventBus.new_game_started.emit()
	assert_true(block.visible, "the block stays while Weather is shown")

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
