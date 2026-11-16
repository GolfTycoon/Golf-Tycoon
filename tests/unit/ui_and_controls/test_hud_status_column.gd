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

func before_all() -> void:
	# Weather and Seasons come from mods now - install the official pair and
	# enable them the way a player's Browse Mods session leaves the game.
	install_environment_mods()

func after_all() -> void:
	uninstall_environment_mods()

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

		if field == "_rating_row":
			var stars := card.get_node_or_null("Content/ValueBackground/ValueContent/Stars") as CourseRatingStars
			assert_not_null(stars, "RatingRow carries star icons in its value background")
			assert_null(card.get_node_or_null("Content/ValueBackground/ValueContent/Value"),
				"RatingRow shows no text value label inside the pill")
		else:
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
	assert_null(funds.get_node_or_null("Trend"), "the funds row has no trend arrow")
	for field in ROW_FIELDS:
		if field == "_rating_row":
			continue
		var label := _row(column, field).get_node("Content/ValueBackground/ValueContent/Value") as Label
		assert_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER,
			"%s value text is horizontally centered" % field)
		assert_eq(label.vertical_alignment, VERTICAL_ALIGNMENT_CENTER,
			"%s value text is vertically centered" % field)

func test_value_pills_have_horizontal_padding_on_desktop_and_compact() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	for window_size in [Vector2i(1600, 1000), Vector2i(844, 390)]:
		get_window().size = window_size
		await process_frames(2)
		column.apply_screen()
		await process_frames(2)
		var font_size := HUDStatusColumn.COMPACT_VALUE_FONT_SIZE if window_size.x < 900 else HUDStatusColumn.VALUE_FONT_SIZE
		var metrics := HUDStatusColumn.metrics_for_font_size(font_size)
		var expected_pad := float(metrics["value_horizontal_padding"])
		var expected_overlap := float(metrics["value_icon_overlap"])
		for field in ROW_FIELDS:
			var card := _row(column, field)
			var pill := card.get_node("Content/ValueBackground") as PanelContainer
			var content := pill.get_node("ValueContent") as Control
			var icon := card.get_node("Content/IconBackground") as PanelContainer
			assert_almost_eq(content.position.x, expected_pad, 0.5,
				"%s has left padding" % field)
			assert_almost_eq(pill.position.x + pill.size.x - icon.position.x,
				expected_overlap, 0.5, "%s overlaps behind the icon" % field)
			assert_almost_eq(icon.position.x - (pill.position.x + content.position.x + content.size.x),
				expected_pad, 0.5, "%s keeps visible right padding" % field)
			assert_lt(pill.get_index(), icon.get_index(), "%s draws its icon above the pill" % field)
			assert_lte(card.size.x, column.custom_minimum_size.x, "%s fits the column" % field)

		# Long values still respect the responsive width.
		column._set_value_text(column._money_label, "$ 1,234,567,890")
		await process_frames(2)
		assert_lte(_row(column, "_funds_row").size.x, column.custom_minimum_size.x,
			"long funds values fit alongside the padding")

	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)

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
		assert_eq(icon.custom_minimum_size, Vector2(32, 32), "the icon is doubled")
		if field == "_rating_row":
			var stars := card.get_node("Content/ValueBackground/ValueContent/Stars") as CourseRatingStars
			assert_eq(stars.star_side(), CourseRatingStars.DESKTOP_SIDE,
				"desktop rating row uses the desktop star grid")
		else:
			var value := card.get_node("Content/ValueBackground/ValueContent/Value") as Label
			assert_eq(value.get_theme_font_size("font_size"), 24, "the value font is doubled")
		var icon_background := card.get_node("Content/IconBackground") as Control
		assert_almost_eq(icon.global_position.y + icon.size.y / 2.0,
			icon_background.global_position.y + icon_background.size.y / 2.0, 1.0,
			"%s keeps its icon centered in its circle" % field)

func test_all_rows_in_column_share_the_same_width_and_height() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	for window_size in [Vector2i(1600, 1000), Vector2i(844, 390)]:
		get_window().size = window_size
		await process_frames(2)
		column.apply_screen()
		await process_frames(2)

		var expected_width: float = column.custom_minimum_size.x
		var font_size := HUDStatusColumn.COMPACT_VALUE_FONT_SIZE if window_size.x < 900 else HUDStatusColumn.VALUE_FONT_SIZE
		var metrics := HUDStatusColumn.metrics_for_font_size(font_size)
		var expected_row_h := float(metrics["row_height"])
		var expected_pill_h := float(metrics["value_background_height"])
		var expected_box := float(metrics["icon_background_size"])
		var expected_icon := float(metrics["icon_size"])
		var first_row := _row(column, ROW_FIELDS[0])
		var first_pill := first_row.get_node("Content/ValueBackground") as Control
		var first_icon := first_row.get_node("Content/IconBackground") as Control

		for field in ROW_FIELDS:
			var card := _row(column, field)
			var parent := card.get_parent() as Control
			var pill := card.get_node("Content/ValueBackground") as Control
			var icon_box := card.get_node("Content/IconBackground") as Control
			var icon := icon_box.get_node("Icon") as TextureRect
			assert_almost_eq(card.size.x, expected_width, 0.5,
				"%s fills the column width at %s" % [field, window_size])
			assert_almost_eq(card.size.y, expected_row_h, 0.5,
				"%s matches the uniform card height at %s" % [field, window_size])
			assert_almost_eq(card.size.x, parent.size.x, 0.5,
				"%s matches its container width at %s" % [field, window_size])
			assert_almost_eq(card.global_position.x, first_row.global_position.x, 0.5,
				"%s aligns on the left with the other rows at %s" % [field, window_size])
			assert_almost_eq(card.position.x + card.size.x, parent.size.x, 0.5,
				"%s aligns on the right at %s" % [field, window_size])
			assert_almost_eq(pill.size.x, first_pill.size.x, 0.5,
				"%s value pill shares the uniform width at %s" % [field, window_size])
			assert_almost_eq(pill.size.y, expected_pill_h, 0.5,
				"%s value pill shares the uniform height at %s" % [field, window_size])
			assert_almost_eq(icon_box.size.x, expected_box, 0.5,
				"%s medallion scales with font size at %s" % [field, window_size])
			assert_almost_eq(icon.size.x, expected_icon, 0.5,
				"%s icon scales with font size at %s" % [field, window_size])
			assert_almost_eq(icon_box.global_position.x, first_icon.global_position.x, 0.5,
				"%s icon medallion aligns vertically at %s" % [field, window_size])
			if field != "_rating_row":
				var label := card.get_node("Content/ValueBackground/ValueContent/Value") as Label
				var value_content := pill.get_node("ValueContent") as Control
				assert_almost_eq(label.size.x, value_content.size.x, 0.5,
					"%s label spans ValueContent so text centers inside the pill at %s" % [field, window_size])

	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)

	var funds := _row(column, "_funds_row")
	var reference_row := _row(column, "_reputation_row")
	for amount in [1, 25000, 100000, 1234567, 999999999, 2500000000]:
		GameManager.money = amount
		EventBus.money_changed.emit(0, amount)
		await process_frames(2)
		assert_almost_eq(funds.size.x, reference_row.size.x, 0.5,
			"funds row keeps the same width as other rows for $%d" % amount)
		assert_almost_eq(funds.size.y, reference_row.size.y, 0.5,
			"funds row keeps the same height as other rows for $%d" % amount)

func test_row_heights_and_icons_shrink_when_font_size_shrinks() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	await process_frames(2)

	var funds := _row(column, "_funds_row")
	var funds_icon := funds.get_node("Content/IconBackground/Icon") as TextureRect
	var funds_box := funds.get_node("Content/IconBackground") as Control
	var desktop_h := funds.size.y
	var desktop_icon := funds_icon.size.x
	var desktop_box := funds_box.size.x

	# Compact landscape shrinks font size (24 -> 14): row height and icons follow.
	get_window().size = Vector2i(844, 390)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)
	assert_lt(funds.size.y, desktop_h, "compact row height shrinks with smaller compact font")
	assert_lt(funds_icon.size.x, desktop_icon, "compact icon shrinks with smaller compact font")
	assert_lt(funds_box.size.x, desktop_box, "compact medallion shrinks with smaller compact font")
	var weather_icon := _row(column, "_weather_row").get_node("Content/IconBackground/Icon") as TextureRect
	assert_eq(weather_icon.texture.get_width(), int(weather_icon.size.x),
		"compact icon uses crisp grid texture matching its smaller size")

	# Resizing back to desktop restores full 48px rows and 32px icons.
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)
	assert_almost_eq(funds.size.y, desktop_h, 0.5, "desktop resize restores row height")
	assert_almost_eq(funds_icon.size.x, desktop_icon, 0.5, "desktop resize restores icon size")

	# Portrait secondary conditions (12px font) use smaller row heights and icons than primary (14px font).
	get_window().size = Vector2i(390, 844)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)
	var season := _row(column, "_season_row")
	var season_icon := season.get_node("Content/IconBackground/Icon") as TextureRect
	var season_box := season.get_node("Content/IconBackground") as Control
	assert_lt(season.size.y, funds.size.y, "12px condition row is shorter than 14px primary row")
	assert_lt(season_icon.size.x, funds_icon.size.x, "12px condition icon is smaller than 14px primary icon")
	assert_lt(season_box.size.x, funds_box.size.x, "12px condition medallion is smaller than 14px primary medallion")

	# Direct font-size changes scale row height and icons monotonically across all rows.
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)
	var prev_h := 999.0
	var prev_icon := 999.0
	for fs in [24, 18, 14, 12, 10]:
		column.set_value_font_size(fs)
		await process_frames(2)
		var rating := _row(column, "_rating_row")
		assert_lt(funds.size.y, prev_h, "row height gets smaller at font size %d" % fs)
		assert_lt(funds_icon.size.x, prev_icon, "icon gets smaller at font size %d" % fs)
		assert_almost_eq(rating.size.y, funds.size.y, 0.5,
			"rating row stays the same height as text rows at font size %d" % fs)
		prev_h = funds.size.y
		prev_icon = funds_icon.size.x

	# External font-size overrides on a row's Value label also shrink that row and its icon.
	column.set_value_font_size(0)
	await process_frames(2)
	var money_label := column._money_label as Label
	money_label.add_theme_font_size_override("font_size", 12)
	await process_frames(2)
	assert_lt(funds.size.y, desktop_h, "overriding label font size shrinks row height")
	assert_lt(funds_icon.size.x, desktop_icon, "overriding label font size shrinks icon")

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
	assert_almost_eq(column.custom_minimum_size.x, 374.0, 0.5, "the portrait ledger spans the phone")
	assert_eq(column.get_node("PortraitLedger").visible, true, "the ledger arrangement is active")
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

# ---------------------------------------------------------------------------
# Course rating row: star icons in the value pill, numeric value in tooltip
# ---------------------------------------------------------------------------

func test_rating_row_shows_star_icons_without_text_and_puts_numeric_value_in_tooltip() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	var rating_row := _row(column, "_rating_row")
	var action := rating_row.get_node("Action") as Button
	var stars := rating_row.get_node("Content/ValueBackground/ValueContent/Stars") as CourseRatingStars

	assert_not_null(stars, "RatingRow renders CourseRatingStars inside ValueBackground")
	var visible_labels := _nodes_of_class(rating_row, "Label").filter(func(label: Label): return label.is_visible_in_tree())
	assert_eq(visible_labels.size(), 0,
		"Desktop RatingRow contains no visible text Label")

	# Before a rating arrives, all five star sockets are unlit and the tooltip says Unrated.
	assert_false(stars.rated, "starts unrated until a course pushes a rating")
	for i in CourseRatingStars.STAR_COUNT:
		assert_almost_eq(stars.star_fill(i), 0.0, 0.001, "star %d starts unlit" % i)
	assert_true(action.tooltip_text.contains("Unrated"),
		"unrated tooltip reports Unrated (got: %s)" % action.tooltip_text)

	# Updating the rating lights the stars (including fractional fill) and writes
	# the formatted number into the hover tooltip.
	column.update_rating(3.5)
	assert_true(stars.rated, "rating is now active")
	assert_almost_eq(stars.star_fill(0), 1.0, 0.001)
	assert_almost_eq(stars.star_fill(1), 1.0, 0.001)
	assert_almost_eq(stars.star_fill(2), 1.0, 0.001)
	assert_almost_eq(stars.star_fill(3), 0.5, 0.001, "fourth star is half filled at 3.5")
	assert_almost_eq(stars.star_fill(4), 0.0, 0.001, "fifth star stays unlit at 3.5")
	assert_true(action.tooltip_text.contains("3.5"),
		"hover tooltip shows the numeric rating 3.5 (got: %s)" % action.tooltip_text)
	assert_true(action.tooltip_text.contains("5.0"),
		"hover tooltip shows the 5.0 scale (got: %s)" % action.tooltip_text)
	assert_eq(rating_row.tooltip_text, action.tooltip_text,
		"row tooltip stays in sync with its hover button")
	assert_eq(action.accessibility_description, action.tooltip_text,
		"accessibility description stays in sync with the hover tooltip")

	# EventBus.course_rating_changed updates both the star strip and tooltip live.
	EventBus.course_rating_changed.emit({"overall": 4.7})
	assert_almost_eq(stars.stars, 4.7, 0.001)
	assert_almost_eq(stars.star_fill(4), 0.7, 0.001)
	assert_true(action.tooltip_text.contains("4.7"),
		"hover tooltip updates when course_rating_changed fires (got: %s)" % action.tooltip_text)
	assert_true(action.tooltip_text.contains("Excellent"),
		"hover tooltip includes the tier description (got: %s)" % action.tooltip_text)

func test_rating_row_stars_fit_both_desktop_and_compact_columns() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	column.update_rating(4.5)
	await process_frames(2)

	var rating_row := _row(column, "_rating_row")
	var stars := rating_row.get_node("Content/ValueBackground/ValueContent/Stars") as CourseRatingStars
	var value_content := rating_row.get_node("Content/ValueBackground/ValueContent") as Control
	assert_false(stars.compact, "desktop window uses desktop star strip")
	assert_almost_eq(rating_row.size.x, column.custom_minimum_size.x, 0.5,
		"desktop rating row matches the 210px column width")
	assert_lte(stars.custom_minimum_size.x, value_content.size.x,
		"desktop stars fit comfortably inside the rating value pill")

	get_window().size = Vector2i(844, 390)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)

	assert_true(stars.compact, "compact landscape switches to compact 15x15 stars")
	assert_almost_eq(rating_row.size.x, column.custom_minimum_size.x, 0.5,
		"compact rating row matches the 150px landscape column width")
	assert_lte(stars.custom_minimum_size.x, value_content.size.x,
		"compact stars fit comfortably inside the rating value pill")
	assert_almost_eq(stars.stars, 4.5, 0.001, "resizing preserves the active star rating")
	assert_true((rating_row.get_node("Action") as Button).tooltip_text.contains("4.5"),
		"resizing preserves the numeric tooltip")

	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	column.apply_screen()

# ---------------------------------------------------------------------------
# Money shortening to fit the row
# ---------------------------------------------------------------------------

func test_large_money_values_shorten_with_suffixes_to_fit_row() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	await process_frames(2)

	var label := column._money_label as Label
	var funds := _row(column, "_funds_row")
	var action := funds.get_node("Action") as Button

	var cases := [
		[25000, "$ 25,000", false],
		[100000, "$ 100,000", false],
		[999999, "$ 999,999", false],
		[1000000, "$ 1M", true],
		[1500000, "$ 1.5M", true],
		[1250000, "$ 1.25M", true],
		[999999999, "$ 999.99M", true],
		[-999999999, "-$ 999.9M", true],
		[-1500000, "-$ 1.5M", true],
		[2500000000, "$ 2.5B", true],
		[3500000000000, "$ 3.5T", true],
		[1500000000000000, "$ 1.5Q", true],
		[9200000000000000000, "$ 9.2Qi", true],
	]

	for case in cases:
		var amount: int = case[0]
		var expected: String = case[1]
		var expects_shortened: bool = case[2]
		GameManager.money = amount
		EventBus.money_changed.emit(0, amount)
		await process_frames(2)

		assert_eq(label.text, expected, "formats %d as %s" % [amount, expected])
		assert_almost_eq(funds.size.x, column.custom_minimum_size.x, 0.5,
			"funds row stays at uniform column width for %d" % amount)

		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var rendered_width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		assert_lte(rendered_width, label.size.x + 0.5,
			"shortened money %s (%s) fits in label width %.1f without clipping" % [
				label.text, str(rendered_width), label.size.x
			])
		assert_true(action.tooltip_text.contains("Click to view financial details"),
			"funds tooltip retains action hint")
		if expects_shortened:
			assert_true(action.tooltip_text.contains(HUDStatusColumn._format_number(absi(amount))),
				"shortened funds tooltip keeps exact balance for %d" % amount)

func test_money_shortens_across_desktop_compact_and_portrait_widths() -> void:
	_set_features(true, true, true)
	var column := _make_column()
	var label := column._money_label as Label
	var funds := _row(column, "_funds_row")

	GameManager.money = 25000
	EventBus.money_changed.emit(0, 25000)
	await process_frames(2)
	assert_eq(label.text, "$ 25,000", "desktop fits starting $ 25,000 in full")

	get_window().size = Vector2i(844, 390)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)
	assert_eq(label.text, "$ 25,000", "compact 150px column fits $ 25,000 alongside the smaller compact icon")
	assert_almost_eq(funds.size.x, 150.0, 0.5, "compact funds row stays 150px wide")

	GameManager.money = 100000000
	EventBus.money_changed.emit(25000, 100000000)
	await process_frames(2)
	assert_eq(label.text, "$ 100M", "compact 150px column shortens $ 100,000,000 to fit")

	for amount in [150000, 999999999, 2500000000, 3500000000000]:
		GameManager.money = amount
		EventBus.money_changed.emit(0, amount)
		await process_frames(2)
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		assert_lte(width, label.size.x + 0.5,
			"compact %s fits inside 150px column label" % label.text)
		assert_almost_eq(funds.size.x, 150.0, 0.5,
			"compact funds row width remains uniform at 150px for %d" % amount)

	for portrait_size in [Vector2i(390, 844), Vector2i(320, 568)]:
		get_window().size = portrait_size
		await process_frames(2)
		column.apply_screen()
		await process_frames(2)
		for amount in [25000, 999999999, 3500000000000]:
			GameManager.money = amount
			EventBus.money_changed.emit(0, amount)
			await process_frames(2)
			var font := label.get_theme_font("font")
			var font_size := label.get_theme_font_size("font_size")
			var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			assert_lte(width, label.size.x + 0.5,
				"portrait %s fits %s without clipping" % [portrait_size, label.text])

	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	column.apply_screen()
	await process_frames(2)
	assert_eq(label.text, "$ 3.5T", "resizing back to desktop keeps T suffix")
	GameManager.money = 25000
	EventBus.money_changed.emit(0, 25000)
	await process_frames(2)
	assert_eq(label.text, "$ 25,000", "resizing back to desktop restores exact $ 25,000")


