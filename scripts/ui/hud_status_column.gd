extends PanelContainer
class_name HUDStatusColumn
## HUDStatusColumn - Vertical status readout docked to the top-right corner.
##
## Replaces the old full-width top bar. Every stat that used to be spread
## across the top of the screen (money, date/season, reputation, course
## rating, weather, wind) is stacked as a compact column, freeing the whole
## top edge of the viewport for the course view.
##
## Each stat is its own card: a background, a border, an icon, the stat's
## name and its value. The cards are what separate one row from the next, so
## no dividers are drawn. The column itself is transparent - the cards float
## over the course, and only the cards that open a panel take the mouse.
##
## The game-mode row that used to head the column (`PLAYING` / `PAUSED`) is
## gone - the bottom dock already carries the pause, play and fast-forward
## controls - and so is the collapse handle, so the cards are always shown.
## The column sizes itself to its content.

signal money_clicked()
signal reputation_clicked()
signal rating_clicked()

## Side of a row icon, in screen pixels (PixelIcon scales in whole blocks).
const ICON_SIZE := 16
## Height of a status card; the icon plus the card's vertical padding.
const ROW_HEIGHT := 24
## Corner radius shared by the cards and their hover / focus rings.
const CARD_RADIUS := 4

# UI References
var _funds_row: PanelContainer
var _money_label: Label
var _money_trend: Label
var _date_row: PanelContainer
var _date_label: Label
var _season_row: PanelContainer
var _season_icon: TextureRect
var _time_label: Label
var _reputation_row: PanelContainer
var _reputation_icon: TextureRect
var _reputation_label: Label
var _rating_row: PanelContainer
var _rating_label: Label
var _weather_row: PanelContainer
var _weather_icon: TextureRect
var _weather_label: Label
var _wind_row: PanelContainer
var _wind_label: Label
## The weather and wind cards travel together: the block is hidden when both
## features are off, so neither card nor any leftover spacing stays behind.
var _environment_block: VBoxContainer

# State
## Change in the balance since the last money_changed signal, for the trend mark.
var _money_trend_value: int = 0

func _ready() -> void:
	add_to_group(UIConstants.HUD_COLUMN_GROUP)
	_apply_anchors()
	var eb := get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("load_completed"):
		eb.load_completed.connect(func(_success): _update_all())
	_build_ui()
	_connect_signals()
	_update_all()
	minimum_size_changed.connect(_refresh_height)
	_refresh_height()

## Column width for the current window: narrow windows (phones, small
## browser windows) get a compact column so the course keeps most of the
## screen.
func _column_width() -> float:
	if has_node("/root/Screen") and Screen.is_compact():
		return 150.0
	return UIConstants.HUD_COLUMN_WIDTH

func _is_compact() -> bool:
	return _column_width() < UIConstants.HUD_COLUMN_WIDTH

func _build_ui() -> void:
	custom_minimum_size = Vector2(_column_width(), 0)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# The column itself draws nothing: the cards are the only surface, so the
	# course shows through the gaps between them and clicks there fall through
	# to the course.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# --- Funds ---
	_funds_row = _create_row("FundsRow", "Funds", PixelIcon.Kind.COIN,
		UIConstants.COLOR_GOLD, _on_money_pressed, "Click to view financial details")
	_money_label = _funds_row.get_node("Content/Value") as Label
	_money_trend = Label.new()
	_money_trend.name = "Trend"
	_money_trend.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_money_trend.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# An empty trend takes no room, so the value keeps the space it needs.
	_money_trend.custom_minimum_size = Vector2(0, 0)
	_money_trend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_funds_row.get_node("Content").add_child(_money_trend)
	column.add_child(_funds_row)

	# Date / season (no intra-day clock — the course never closes). The Season
	# card is hidden while the Seasons feature is off.
	_date_row = _create_row("DateRow", "Date", PixelIcon.Kind.CALENDAR,
		UIConstants.COLOR_TEXT_DIM)
	_date_label = _date_row.get_node("Content/Value") as Label
	column.add_child(_date_row)

	_season_row = _create_row("SeasonRow", "Season", PixelIcon.Kind.LEAF,
		SeasonSystem.get_season_color(SeasonSystem.get_season(1)))
	_season_icon = _season_row.get_node("Content/Icon") as TextureRect
	_time_label = _season_row.get_node("Content/Value") as Label
	column.add_child(_season_row)

	# Reputation
	_reputation_row = _create_row("ReputationRow", "Reputation", PixelIcon.Kind.HEART,
		UIConstants.COLOR_DANGER_MUTED, _on_reputation_pressed,
		"Course reputation (click for rating details)")
	_reputation_icon = _reputation_row.get_node("Content/Icon") as TextureRect
	_reputation_label = _reputation_row.get_node("Content/Value") as Label
	column.add_child(_reputation_row)

	# Course rating
	_rating_row = _create_row("RatingRow", "Rating", PixelIcon.Kind.STAR,
		UIConstants.COLOR_GOLD, _on_rating_pressed, "Course rating (click for details)")
	_rating_label = _rating_row.get_node("Content/Value") as Label
	_rating_label.text = "-- (-.--)"
	_rating_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	column.add_child(_rating_row)

	# Weather and wind: one block, so the pair leaves the column together.
	_environment_block = VBoxContainer.new()
	_environment_block.name = "EnvironmentRows"
	_environment_block.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	_environment_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_environment_block)

	_weather_row = _create_row("WeatherRow", "Weather", PixelIcon.Kind.SUN,
		UIConstants.COLOR_GOLD)
	_weather_icon = _weather_row.get_node("Content/Icon") as TextureRect
	_weather_label = _weather_row.get_node("Content/Value") as Label
	_environment_block.add_child(_weather_row)

	_wind_row = _create_row("WindRow", "Wind", PixelIcon.Kind.WIND,
		UIConstants.COLOR_SUCCESS_MUTED)
	_wind_label = _wind_row.get_node("Content/Value") as Label
	_environment_block.add_child(_wind_row)

## Build one status card: an icon, the stat's name and its value on a
## background with its own border. A row with `on_pressed` is clickable and
## focusable as a whole (the button sits under the content, so the labels
## never eat the click).
func _create_row(row_name: String, title: String, icon_kind: int, icon_accent: Color,
		on_pressed: Callable = Callable(), tooltip: String = "") -> PanelContainer:
	var card := PanelContainer.new()
	card.name = row_name
	card.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	card.add_theme_stylebox_override("panel", _card_style())
	card.mouse_filter = Control.MOUSE_FILTER_STOP if on_pressed.is_valid() \
		else Control.MOUSE_FILTER_IGNORE

	if on_pressed.is_valid():
		var action := Button.new()
		action.name = "Action"
		action.text = ""
		action.focus_mode = Control.FOCUS_ALL
		action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		action.tooltip_text = tooltip
		action.accessibility_name = title
		action.accessibility_description = tooltip
		_paint_row_button(action, icon_accent)
		action.pressed.connect(on_pressed)
		# Added first: the panel fits every child to its content rect, so the
		# button lies under the icon, name and value drawn after it.
		card.add_child(action)

	var content := HBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = PixelIcon.texture(icon_kind, ICON_SIZE, icon_accent)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)

	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	title_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_label)

	content.add_child(_create_value_label())
	return card

## The value end of a card: right-aligned, and shrinking with an ellipsis
## rather than widening the column on narrow windows.
func _create_value_label() -> Label:
	var label := Label.new()
	label.name = "Value"
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## The card every row wears: a dark fill with a hairline sage border, so each
## stat reads as its own tile over the course behind it.
func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIConstants.COLOR_BG_DARK, 0.82)
	style.set_border_width_all(1)
	style.border_color = Color(UIConstants.COLOR_BORDER, 0.62)
	style.set_corner_radius_all(CARD_RADIUS)
	style.content_margin_left = 6
	style.content_margin_top = 4
	style.content_margin_right = 7
	style.content_margin_bottom = 4
	return style

## A clickable card's states: no fill at rest (the card shows through), a wash
## of the row's accent under the pointer and while pressed, and a gold ring
## when it holds keyboard focus.
func _paint_row_button(button: Button, accent: Color) -> void:
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("disabled", empty)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(accent, 0.10)
	hover.set_corner_radius_all(CARD_RADIUS)
	button.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(accent, 0.20)
	pressed.set_corner_radius_all(CARD_RADIUS)
	button.add_theme_stylebox_override("pressed", pressed)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(1)
	focus.border_color = UIConstants.COLOR_GOLD
	focus.set_corner_radius_all(CARD_RADIUS)
	button.add_theme_stylebox_override("focus", focus)

## Swap a card's icon, keeping the 16x16 art crisp.
func _set_row_icon(icon: TextureRect, kind: int, accent: Color) -> void:
	if icon == null:
		return
	icon.texture = PixelIcon.texture(kind, ICON_SIZE, accent)

# =============================================================================
# LAYOUT
# =============================================================================

## Pin the column to the top-right corner of its parent.
func _apply_anchors() -> void:
	var width := _column_width()
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	offset_left = -(width + UIConstants.HUD_COLUMN_MARGIN)
	offset_right = -UIConstants.HUD_COLUMN_MARGIN
	offset_top = UIConstants.HUD_COLUMN_MARGIN
	_refresh_height()

## Re-derive size-sensitive layout after a responsive window change
## (rotation, resize across the compact threshold).
func apply_screen() -> void:
	if not is_inside_tree():
		return
	custom_minimum_size.x = _column_width()
	# The date loses its weekday on the narrow column so the value still fits
	# beside its icon and label.
	_update_day_time()
	_apply_anchors()

## Keep the panel exactly as tall as its content (anchored controls need an
## explicit bottom offset).
func _refresh_height() -> void:
	offset_bottom = offset_top + get_combined_minimum_size().y

## Height the column currently occupies, including its top margin. Other HUD
## elements use this to avoid overlapping it.
func get_occupied_height() -> float:
	return offset_bottom

func _connect_signals() -> void:
	# Connect to EventBus signals
	if has_node("/root/EventBus"):
		var eb := get_node("/root/EventBus")
		# A new game can switch Weather, Wind and Seasons on or off (Start New
		# Game options, or the location that was just bought), so re-read the
		# whole column: no feature signal carries that change.
		eb.new_game_started.connect(_update_all)
		eb.money_changed.connect(_on_money_changed)
		eb.day_changed.connect(_on_day_changed)
		eb.reputation_changed.connect(_on_reputation_changed)
		eb.weather_changed.connect(_on_weather_changed)
		eb.wind_changed.connect(_on_wind_changed)

func _update_all() -> void:
	_update_money()
	_update_day_time()
	_update_reputation()
	_update_weather()
	_update_wind()
	_update_feature_rows()

## Show only the cards of the features this course plays with. A feature that
## is off has no row at all rather than one reading "Off": leaving Weather,
## Wind or Seasons out of the column says the same thing in less space.
func _update_feature_rows() -> void:
	if _season_row == null or _weather_row == null or _wind_row == null:
		return
	var seasons_on := _is_feature_on("seasons")
	var weather_on := _is_feature_on("weather")
	var wind_on := _is_feature_on("wind")
	_season_row.visible = seasons_on
	_weather_row.visible = weather_on
	_wind_row.visible = wind_on
	if _environment_block:
		# The block introduces the weather/wind pair; with both off it goes too.
		_environment_block.visible = weather_on or wind_on
	_refresh_height()

## Whether the course plays with a feature. Without a GameManager — a column
## built on its own, as the layout tests do — every row is kept.
func _is_feature_on(feature: String) -> bool:
	if not has_node("/root/GameManager"):
		return true
	return GameManager.is_feature_enabled(feature)

func _update_money() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm = get_node("/root/GameManager")
	var money = gm.get("money")
	if money == null:
		money = GameManager.DEFAULT_STARTING_MONEY

	_money_label.text = "$ %s" % _format_number(money)

	# Color based on balance
	if money < 0:
		_money_label.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	elif money < 5000:
		_money_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_money_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)

	# Trend indicator
	if _money_trend_value > 0:
		_money_trend.text = "^"
		_money_trend.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	elif _money_trend_value < 0:
		_money_trend.text = "v"
		_money_trend.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	else:
		_money_trend.text = ""

func _update_day_time() -> void:
	if not has_node("/root/GameManager") or _date_label == null or _time_label == null:
		return
	var gm = get_node("/root/GameManager")
	var day = gm.get("current_day")
	if day == null:
		day = 1

	# Wide column: the full date with its weekday. Narrow: the weekday goes so
	# the value still fits on one line beside the icon and its label.
	_date_label.text = GameCalendar.format_date_short(day) if _is_compact() \
		else GameCalendar.format_date(day)
	# With the Seasons feature off the calendar still ticks, but the course
	# plays as one year-round season, so _update_feature_rows hides the row.
	var season = SeasonSystem.get_season(day)
	var season_color := SeasonSystem.get_season_color(season)
	_time_label.text = SeasonSystem.get_season_name(season)
	_time_label.add_theme_color_override("font_color", season_color)
	# The leaf wears the season too: green shoots, summer gold, fall orange,
	# winter blue.
	_set_row_icon(_season_icon, PixelIcon.Kind.LEAF, season_color)

func _update_reputation() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm = get_node("/root/GameManager")
	var rep = gm.get("reputation")
	if rep == null:
		rep = 50.0

	_reputation_label.text = "%d%%" % int(rep)

	# Color based on reputation; the heart wears the same reading as the value.
	var color := UIConstants.COLOR_DANGER
	if rep >= 75:
		color = UIConstants.COLOR_SUCCESS
	elif rep >= 40:
		color = UIConstants.COLOR_WARNING
	_reputation_label.add_theme_color_override("font_color", color)
	_set_row_icon(_reputation_icon, PixelIcon.Kind.HEART, color)

func _update_weather() -> void:
	if _weather_label == null:
		return
	if not has_node("/root/GameManager"):
		_weather_label.text = "Sunny"
		_set_row_icon(_weather_icon, PixelIcon.Kind.SUN, UIConstants.COLOR_GOLD)
		return

	# The Weather feature can be turned off at setup: _update_feature_rows
	# then hides the row, so there is nothing to show here.
	if not GameManager.weather_enabled:
		return
	var weather_system = GameManager.get("weather_system")
	if weather_system == null:
		_weather_label.text = "Sunny"
		_set_row_icon(_weather_icon, PixelIcon.Kind.SUN, UIConstants.COLOR_GOLD)
		return

	var weather_type = weather_system.get("weather_type")
	if weather_type == null:
		weather_type = 0

	_weather_label.text = UIConstants.get_weather_name(weather_type)

	# The card's sky sprite follows the conditions, painted in the same family
	# of colours the conditions use elsewhere in the HUD.
	var icon_kind := PixelIcon.Kind.SUN
	var icon_color := UIConstants.COLOR_GOLD
	match weather_type:
		0:  # SUNNY
			icon_kind = PixelIcon.Kind.SUN
			icon_color = UIConstants.COLOR_GOLD
		1:  # PARTLY_CLOUDY
			icon_kind = PixelIcon.Kind.PARTLY_CLOUDY
			icon_color = UIConstants.COLOR_TEXT_DIM
		2:  # OVERCAST
			icon_kind = PixelIcon.Kind.OVERCAST
			icon_color = UIConstants.COLOR_TEXT_DIM
		3:  # LIGHT_RAIN
			icon_kind = PixelIcon.Kind.LIGHT_RAIN
			icon_color = UIConstants.COLOR_INFO
		4:  # RAIN
			icon_kind = PixelIcon.Kind.RAIN
			icon_color = UIConstants.COLOR_INFO
		5:  # HEAVY_RAIN
			icon_kind = PixelIcon.Kind.HEAVY_RAIN
			icon_color = UIConstants.COLOR_INFO
		_:
			icon_kind = PixelIcon.Kind.OVERCAST
			icon_color = UIConstants.COLOR_TEXT_MUTED
	_set_row_icon(_weather_icon, icon_kind, icon_color)

func _update_wind() -> void:
	if not has_node("/root/GameManager") or _wind_label == null:
		_wind_label.text = "0 mph"
		return

	# The Wind feature can be turned off at setup: the air is dead calm and
	# _update_feature_rows hides the row.
	if not GameManager.wind_enabled:
		return
	var wind_system = GameManager.get("wind_system")
	if wind_system == null:
		_wind_label.text = "0 mph"
		return

	var speed = wind_system.get("wind_speed")
	var direction = wind_system.get("wind_direction")
	if speed == null:
		speed = 0.0
	if direction == null:
		direction = 0.0

	# Convert radians to degrees for direction name
	var degrees = fmod(rad_to_deg(direction) + 360.0, 360.0)
	var dir_name = _get_direction_name(degrees)
	_wind_label.text = "%s %d mph" % [dir_name, int(speed)]

	# Color based on wind speed
	if speed < 5:
		_wind_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	elif speed < 15:
		_wind_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_wind_label.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)

func _get_direction_name(degrees: float) -> String:
	var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var index = int(round(degrees / 45.0)) % 8
	return dirs[index]

func _format_number(num: int) -> String:
	var str_num = str(abs(num))
	var result = ""
	var count = 0
	for i in range(str_num.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_num[i] + result
		count += 1
	if num < 0:
		result = "-" + result
	return result

# Signal handlers
func _on_money_pressed() -> void:
	money_clicked.emit()

func _on_reputation_pressed() -> void:
	reputation_clicked.emit()

func _on_rating_pressed() -> void:
	rating_clicked.emit()

func update_rating(stars: float) -> void:
	if _rating_label == null:
		return
	var display := CourseRatingSystem.get_star_display(stars)
	_rating_label.text = "%s (%.1f)" % [display, stars]
	if stars >= 4.0:
		_rating_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	elif stars >= 3.0:
		_rating_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	elif stars >= 2.0:
		_rating_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_rating_label.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)

func _on_money_changed(old_amount: int, new_amount: int) -> void:
	_money_trend_value = new_amount - old_amount
	_update_money()

func _on_day_changed(_new_day: int) -> void:
	_update_day_time()

func _on_reputation_changed(_old_rep: float, _new_rep: float) -> void:
	_update_reputation()

func _on_weather_changed(_weather_type: int, _intensity: float) -> void:
	_update_weather()

func _on_wind_changed(_direction: float, _speed: float) -> void:
	_update_wind()
