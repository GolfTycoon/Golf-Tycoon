extends PanelContainer
class_name HUDStatusColumn
## HUDStatusColumn - Vertical status readout docked to the top-right corner.
##
## Replaces the old full-width top bar. Every stat that used to be spread
## across the top of the screen (money, season, reputation, course rating,
## weather, wind) is stacked as a compact column, freeing the whole top edge
## of the viewport for the course view. The calendar date lives in the
## top-left CourseLocationBanner, not in this column.
##
## Each stat has a rounded value background and a separate right-hand icon
## circle. The cards are what separate one row from the next, so
## no dividers are drawn. The column itself is transparent - the cards float
## over the course, and only the cards that open a panel take the mouse.
##
## The game-mode row that used to head the column (`PLAYING` / `PAUSED`) is
## gone - the bottom dock already carries the pause and speed controls - and
## so is the collapse handle, so the cards are always shown.
## The column sizes itself to its content.

signal money_clicked()
signal reputation_clicked()
signal rating_clicked()

## Side of a row icon, in screen pixels (PixelIcon scales in whole blocks).
const ICON_SIZE := 32
## Scale the value text along with the doubled row height.
const VALUE_FONT_SIZE := UIConstants.FONT_SIZE_SM * 2
const COMPACT_VALUE_FONT_SIZE := UIConstants.FONT_SIZE_BASE
const MONEY_SUFFIXES: Array = [
	[1000000000000000000, "Qi"],
	[1000000000000000, "Q"],
	[1000000000000, "T"],
	[1000000000, "B"],
	[1000000, "M"],
	[1000, "K"],
]
## Height of a status card, leaving comfortable space around the icon and value.
const ROW_HEIGHT := 48
## Uniform height of each value pill inside its 48px row (leaving a 6px step under the medallion).
const VALUE_BACKGROUND_HEIGHT := 42
## Corner radius shared by the cards and their hover / focus rings.
const CARD_RADIUS := 18
const ICON_BACKGROUND_SIZE := 40
## Breathing room on each side of the value inside its pill.
const VALUE_HORIZONTAL_PADDING := 20
## Extend the value pill behind the icon without crowding its contents.
const VALUE_ICON_OVERLAP := 20

# UI References
var _funds_row: PanelContainer
var _money_label: Label
var _season_row: PanelContainer
var _season_icon: TextureRect
var _time_label: Label
var _reputation_row: PanelContainer
var _reputation_icon: TextureRect
var _reputation_label: Label
var _rating_row: PanelContainer
var _rating_stars: CourseRatingStars
var _portrait_rating_label: Label
var _weather_row: PanelContainer
var _weather_icon: TextureRect
var _weather_label: Label
var _wind_row: PanelContainer
var _wind_label: Label
## The weather and wind cards travel together: the block is hidden when both
## features are off, so neither card nor any leftover spacing stays behind.
var _environment_block: VBoxContainer
var _desktop_column: VBoxContainer
var _portrait_rows: VBoxContainer
var _portrait_primary: HBoxContainer
var _portrait_secondary: HBoxContainer
var _portrait_mode := false
var _custom_value_font_size: int = 0
var _applying_row_style := false

# State
var _has_rating: bool = false
var _rating_value: float = 0.0

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
	if has_node("/root/Screen") and Screen.uses_portrait_hud():
		return maxf(240.0, Screen.window_size.x - Screen.safe_insets.x - Screen.safe_insets.z - 16.0)
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
	_desktop_column = column
	column.name = "Column"
	column.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# --- Funds ---
	_funds_row = _create_row("FundsRow", "Funds", PixelIcon.Kind.COIN,
		UIConstants.COLOR_GOLD, _on_money_pressed, "Click to view financial details")
	_money_label = _funds_row.get_node("Content/ValueBackground/ValueContent/Value") as Label
	column.add_child(_funds_row)

	# The calendar date lives in the top-left CourseLocationBanner; this column
	# keeps only the Season card, which is hidden while the Seasons feature is off.
	_season_row = _create_row("SeasonRow", "Season", PixelIcon.Kind.LEAF,
		SeasonSystem.get_season_color(SeasonSystem.get_season(1)))
	_season_icon = _season_row.get_node("Content/IconBackground/Icon") as TextureRect
	_time_label = _season_row.get_node("Content/ValueBackground/ValueContent/Value") as Label
	column.add_child(_season_row)

	# Reputation
	_reputation_row = _create_row("ReputationRow", "Reputation", PixelIcon.Kind.HEART,
		UIConstants.COLOR_DANGER_MUTED, _on_reputation_pressed,
		"Course reputation (click for rating details)")
	_reputation_icon = _reputation_row.get_node("Content/IconBackground/Icon") as TextureRect
	_reputation_label = _reputation_row.get_node("Content/ValueBackground/ValueContent/Value") as Label
	column.add_child(_reputation_row)

	# Course rating: five faceted star icons inside the value pill, with the
	# numeric rating surfaced in the hover tooltip.
	_rating_row = _create_row("RatingRow", "Rating", PixelIcon.Kind.STAR,
		UIConstants.COLOR_GOLD, _on_rating_pressed, format_rating_tooltip(0.0, false), false)
	_rating_stars = CourseRatingStars.new(_is_compact())
	_rating_stars.name = "Stars"
	_rating_stars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rating_row.get_node("Content/ValueBackground/ValueContent").add_child(_rating_stars)
	_portrait_rating_label = _create_value_label()
	_portrait_rating_label.name = "PortraitRating"
	_portrait_rating_label.visible = false
	_portrait_rating_label.theme_changed.connect(_on_value_label_theme_changed.bind(_rating_row, _portrait_rating_label))
	_rating_row.get_node("Content/ValueBackground/ValueContent").add_child(_portrait_rating_label)
	_refresh_rating_tooltip()
	column.add_child(_rating_row)

	# Weather and wind: one block, so the pair leaves the column together.
	_environment_block = VBoxContainer.new()
	_environment_block.name = "EnvironmentRows"
	_environment_block.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	_environment_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_environment_block)

	_weather_row = _create_row("WeatherRow", "Weather", PixelIcon.Kind.SUN,
		UIConstants.COLOR_GOLD)
	_weather_icon = _weather_row.get_node("Content/IconBackground/Icon") as TextureRect
	_weather_label = _weather_row.get_node("Content/ValueBackground/ValueContent/Value") as Label
	_environment_block.add_child(_weather_row)

	_wind_row = _create_row("WindRow", "Wind", PixelIcon.Kind.WIND,
		UIConstants.COLOR_SUCCESS_MUTED)
	_wind_label = _wind_row.get_node("Content/ValueBackground/ValueContent/Value") as Label
	_environment_block.add_child(_wind_row)
	_build_portrait_layout()
	for row in [_funds_row, _season_row, _reputation_row, _rating_row, _weather_row, _wind_row]:
		_style_portrait_row(row)
	if has_node("/root/Screen") and Screen.uses_portrait_hud():
		apply_screen()

## Build one status row: a rounded value background and a raised icon circle.
## A row with `on_pressed` is clickable and focusable as a whole.
func _create_row(row_name: String, title: String, icon_kind: int, icon_accent: Color,
		on_pressed: Callable = Callable(), tooltip: String = "",
		with_value_label: bool = true) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = row_name
	card.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_FILL
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.mouse_filter = Control.MOUSE_FILTER_STOP if on_pressed.is_valid() \
		else Control.MOUSE_FILTER_IGNORE

	card.set_meta("_icon_kind", icon_kind)
	card.set_meta("_icon_accent", icon_accent)
	card.set_meta("_font_size", VALUE_FONT_SIZE)
	card.set_meta("_applied_font_size", VALUE_FONT_SIZE)

	if on_pressed.is_valid():
		card.tooltip_text = tooltip
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
		# The panel fits the button over the whole row.
		card.add_child(action)

	var content := HBoxContainer.new()
	content.name = "Content"
	# The icon is drawn after the pill, so the negative gap tucks the pill
	# underneath the raised medallion rather than covering it.
	content.add_theme_constant_override("separation", -VALUE_ICON_OVERLAP)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var value_background := PanelContainer.new()
	value_background.name = "ValueBackground"
	value_background.custom_minimum_size = Vector2(0, VALUE_BACKGROUND_HEIGHT)
	value_background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_background.size_flags_vertical = Control.SIZE_SHRINK_END
	value_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_background.add_theme_stylebox_override("panel", _card_style(icon_accent))
	content.add_child(value_background)
	var value_content := HBoxContainer.new()
	value_content.name = "ValueContent"
	value_content.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	value_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_background.add_child(value_content)
	if with_value_label:
		var value_label := _create_value_label()
		value_label.theme_changed.connect(_on_value_label_theme_changed.bind(card, value_label))
		value_content.add_child(value_label)

	var icon_background := PanelContainer.new()
	icon_background.name = "IconBackground"
	icon_background.custom_minimum_size = Vector2(ICON_BACKGROUND_SIZE, ICON_BACKGROUND_SIZE)
	icon_background.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := _icon_style(icon_accent)
	icon_background.add_theme_stylebox_override("panel", icon_style)
	content.add_child(icon_background)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = PixelIcon.texture(icon_kind, ICON_SIZE, icon_accent)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_background.add_child(icon)

	# Paint interaction feedback above both backgrounds. Content ignores mouse input.
	if on_pressed.is_valid():
		card.move_child(card.get_node("Action"), -1)
	return card

## Row dimensions derived from the value font size so shrinking the text
## shrinks the card, pill, medallion and icon in step.
static func metrics_for_font_size(font_size: int) -> Dictionary:
	var fs := clampi(font_size, 8, 40)
	if fs == VALUE_FONT_SIZE:
		return {
			"font_size": VALUE_FONT_SIZE,
			"row_height": ROW_HEIGHT,
			"value_background_height": VALUE_BACKGROUND_HEIGHT,
			"icon_background_size": ICON_BACKGROUND_SIZE,
			"icon_size": ICON_SIZE,
			"card_radius": CARD_RADIUS,
			"value_horizontal_padding": VALUE_HORIZONTAL_PADDING,
			"value_icon_overlap": VALUE_ICON_OVERLAP,
			"value_vertical_margin": 4,
		}
	var row_height := clampi(2 * roundi(float(fs) * 0.8 + 4.8), 22, 72)
	var step := 6 if fs >= 20 else 4
	var pill_height := maxi(row_height - step, 18)
	var icon_size := clampi(2 * roundi(float(fs) * 0.8 - 3.2), 10, 48)
	var icon_background_size := icon_size + 8
	var card_radius := clampi(roundi(float(CARD_RADIUS) * float(pill_height) / float(VALUE_BACKGROUND_HEIGHT)), 8, 24)
	var h_pad := clampi(2 * roundi(10.0 * float(row_height) / float(ROW_HEIGHT)), 8, 24)
	var overlap := int(roundi(float(icon_background_size) * 0.5))
	var v_margin := 4 if fs >= 22 else (3 if fs >= 18 else 2)
	return {
		"font_size": fs,
		"row_height": row_height,
		"value_background_height": pill_height,
		"icon_background_size": icon_background_size,
		"icon_size": icon_size,
		"card_radius": card_radius,
		"value_horizontal_padding": h_pad,
		"value_icon_overlap": overlap,
		"value_vertical_margin": v_margin,
	}

## Override the font size across the status column (pass <= 0 to restore
## responsive automatic sizing), scaling row heights and icons to match.
func set_value_font_size(font_size: int) -> void:
	_custom_value_font_size = clampi(font_size, 8, 40) if font_size > 0 else 0
	if not is_inside_tree() or _funds_row == null:
		return
	for row in [_funds_row, _season_row, _reputation_row, _rating_row, _weather_row, _wind_row]:
		_style_portrait_row(row)
	_update_all()
	_refresh_height()

## The value end of a card: centered horizontally and vertically inside the pill,
## capped so unusually long values still fit on narrow windows.
func _create_value_label() -> Label:
	var label := Label.new()
	label.name = "Value"
	label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _row_of_label(label: Label) -> PanelContainer:
	if label == null:
		return null
	var value_content := label.get_parent()
	if value_content == null:
		return null
	var value_background := value_content.get_parent()
	if value_background == null:
		return null
	var content := value_background.get_parent()
	if content == null:
		return null
	return content.get_parent() as PanelContainer

func _row_metrics(row: PanelContainer) -> Dictionary:
	var fs := VALUE_FONT_SIZE
	if row != null and row.has_meta("_font_size"):
		fs = int(row.get_meta("_font_size"))
	elif _custom_value_font_size > 0:
		fs = _custom_value_font_size
	elif _is_compact():
		fs = COMPACT_VALUE_FONT_SIZE
	return metrics_for_font_size(fs)

## Keep each card's label within its uniform row width, without letting
## exceptionally long values push the column beyond its responsive width.
func _set_value_text(label: Label, text: String) -> void:
	label.text = text
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var row := _row_of_label(label)
	var metrics := _row_metrics(row)
	var available := _column_width() - float(metrics["icon_background_size"]) - 2.0 * float(metrics["value_horizontal_padding"])
	if label == _money_label:
		available = _money_available_width()
	elif _portrait_mode:
		available = (_column_width() - 12.0) / 3.0 - 30.0
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size).x if font != null else available
	label.custom_minimum_size.x = minf(measured, available)

func _money_available_width() -> float:
	var breathing := 6.0 if _portrait_mode else 8.0
	if _portrait_mode:
		var funds_width := (_column_width() - 12.0) * (1.18 / 3.18)
		return maxf(24.0, funds_width - 34.0 - breathing)
	var metrics := _row_metrics(_funds_row)
	var value_content_width := _column_width() - float(metrics["icon_background_size"]) - 2.0 * float(metrics["value_horizontal_padding"])
	return maxf(24.0, value_content_width - breathing)

## Shared dark fill and hairline sage border for the value and icon backgrounds.
func _card_style(accent: Color, metrics: Dictionary = {}) -> StyleBoxFlat:
	var m := metrics if not metrics.is_empty() else metrics_for_font_size(VALUE_FONT_SIZE)
	var h_pad := int(m["value_horizontal_padding"])
	var v_pad := int(m["value_vertical_margin"])
	var overlap := int(m["value_icon_overlap"])
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIConstants.COLOR_BG_DARK.lerp(accent, 0.08), 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(accent, 0.58)
	style.set_corner_radius_all(int(m["card_radius"]))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = h_pad
	style.content_margin_top = v_pad
	style.content_margin_right = h_pad + overlap
	style.content_margin_bottom = v_pad
	return style

func _card_style_for_row(accent: Color, row: PanelContainer = null) -> StyleBoxFlat:
	var m := _row_metrics(row)
	var style := _card_style(accent, m)
	if _portrait_mode:
		style.content_margin_left = 6
		style.content_margin_right = 12
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		style.corner_radius_top_left = 8
		style.corner_radius_bottom_left = 8
	return style

## The raised medallion takes a brighter accent rim and a deeper tinted fill,
## echoing the sprite while keeping the value pill quiet and legible.
func _icon_style(accent: Color, metrics: Dictionary = {}) -> StyleBoxFlat:
	var m := metrics if not metrics.is_empty() else metrics_for_font_size(VALUE_FONT_SIZE)
	var box_size := float(m["icon_background_size"])
	var icon_side := float(m["icon_size"])
	var style := _card_style(accent, m)
	style.bg_color = Color(UIConstants.COLOR_BG_DARK.lerp(accent, 0.18), 0.98)
	style.border_color = Color(accent, 0.9)
	style.set_corner_radius_all(int(box_size / 2.0))
	style.set_content_margin_all((box_size - icon_side) / 2.0)
	return style

func _icon_style_for_row(accent: Color, row: PanelContainer = null) -> StyleBoxFlat:
	var m := _row_metrics(row)
	var icon_style := _icon_style(accent, m)
	if _portrait_mode:
		icon_style.set_content_margin_all(4.0)
	return icon_style

## A clickable card's states: no fill at rest (the card shows through), a wash
## of the row's accent under the pointer and while pressed, and a gold ring
## when it holds keyboard focus.
func _paint_row_button(button: Button, accent: Color, radius: int = CARD_RADIUS) -> void:
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("disabled", empty)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(accent, 0.10)
	hover.set_corner_radius_all(radius)
	button.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(accent, 0.20)
	pressed.set_corner_radius_all(radius)
	button.add_theme_stylebox_override("pressed", pressed)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(1)
	focus.border_color = UIConstants.COLOR_GOLD
	focus.set_corner_radius_all(radius)
	button.add_theme_stylebox_override("focus", focus)

## Swap a card's icon, keeping the 16x16 art crisp.
func _set_row_icon(icon: TextureRect, kind: int, accent: Color) -> void:
	if icon == null:
		return
	var icon_background := icon.get_parent() as PanelContainer
	var content := icon_background.get_parent()
	var row := content.get_parent() as PanelContainer
	var value_background := content.get_node("ValueBackground") as PanelContainer
	if row != null:
		row.set_meta("_icon_kind", kind)
		row.set_meta("_icon_accent", accent)
	var m := _row_metrics(row)
	icon.texture = PixelIcon.texture(kind, int(m["icon_size"]), accent)
	# Season, weather and reputation change their palette as the game changes.
	icon_background.add_theme_stylebox_override("panel", _icon_style_for_row(accent, row))
	value_background.add_theme_stylebox_override("panel", _card_style_for_row(accent, row))

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
	if _portrait_mode:
		anchor_left = 0.0
		anchor_right = 0.0
		grow_horizontal = Control.GROW_DIRECTION_END
		offset_left = Screen.safe_insets.x + 8.0
		offset_right = offset_left + width
		offset_top = Screen.safe_insets.y + 56.0
	else:
		offset_left = -(width + UIConstants.HUD_COLUMN_MARGIN)
		offset_right = -UIConstants.HUD_COLUMN_MARGIN
		offset_top = UIConstants.HUD_COLUMN_MARGIN
	_refresh_height()

## Re-derive size-sensitive layout after a responsive window change
## (rotation, resize across the compact threshold).
func apply_screen() -> void:
	if not is_inside_tree() or _funds_row == null:
		return
	var portrait := has_node("/root/Screen") and Screen.uses_portrait_hud()
	var arrangement_changed := portrait != _portrait_mode
	_portrait_mode = portrait
	# Move the live cards only when the arrangement actually changes; tray
	# toggles also emit Screen.changed and must not churn focus/ownership.
	var expected_parent: Container
	if portrait:
		expected_parent = _portrait_primary
	else:
		expected_parent = _desktop_column
	if arrangement_changed or _funds_row.get_parent() != expected_parent:
		_arrange_rows()
		_update_feature_rows()
	else:
		for row in [_funds_row, _season_row, _reputation_row, _rating_row, _weather_row, _wind_row]:
			_style_portrait_row(row)
	custom_minimum_size.x = _column_width()
	# Refit values to the new width, including the season leaf, name and stars.
	_update_all()
	_apply_anchors()

## The portrait ledger keeps the three actionable stats on one reachable row,
## with the course conditions below. Reparent the live cards (never duplicate
## their signals) so money/rating clicks and every live update stay identical.
func _build_portrait_layout() -> void:
	_portrait_rows = VBoxContainer.new()
	_portrait_rows.name = "PortraitLedger"
	_portrait_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_rows.add_theme_constant_override("separation", 4)
	add_child(_portrait_rows)
	_portrait_primary = HBoxContainer.new()
	_portrait_primary.name = "PrimaryStats"
	_portrait_primary.add_theme_constant_override("separation", 6)
	_portrait_rows.add_child(_portrait_primary)
	_portrait_secondary = HBoxContainer.new()
	_portrait_secondary.name = "CourseConditions"
	_portrait_secondary.add_theme_constant_override("separation", 6)
	_portrait_rows.add_child(_portrait_secondary)
	_portrait_rows.visible = false

func _arrange_rows() -> void:
	var rows := [_funds_row, _season_row, _reputation_row, _rating_row, _weather_row, _wind_row]
	for row in rows:
		if row.get_parent():
			row.get_parent().remove_child(row)
	if _portrait_mode:
		_desktop_column.visible = false
		_portrait_rows.visible = true
		for row in [_funds_row, _rating_row, _reputation_row]:
			_portrait_primary.add_child(row)
		for row in [_season_row, _weather_row, _wind_row]:
			_portrait_secondary.add_child(row)
	else:
		_desktop_column.visible = true
		_portrait_rows.visible = false
		for row in [_funds_row, _season_row, _reputation_row, _rating_row]:
			_desktop_column.add_child(row)
		_environment_block.add_child(_weather_row)
		_environment_block.add_child(_wind_row)
	for row in rows:
		_style_portrait_row(row)

func _target_font_size_for_row(row: PanelContainer) -> int:
	if _custom_value_font_size > 0:
		if _portrait_mode and row.get_parent() != _portrait_primary:
			return clampi(_custom_value_font_size - 2, 8, 40)
		return _custom_value_font_size
	if _portrait_mode:
		return 14 if row.get_parent() == _portrait_primary else 12
	if _is_compact():
		return COMPACT_VALUE_FONT_SIZE
	return VALUE_FONT_SIZE

func _style_portrait_row(row: PanelContainer) -> void:
	_apply_row_metrics(row, _target_font_size_for_row(row), true)

func _apply_row_metrics(row: PanelContainer, value_font_size: int, apply_font_override: bool = true) -> void:
	var fs := clampi(value_font_size, 8, 40)
	row.set_meta("_font_size", fs)
	row.set_meta("_applied_font_size", fs)
	var m := metrics_for_font_size(fs)
	var content := row.get_node("Content") as HBoxContainer
	var value := row.get_node("Content/ValueBackground") as PanelContainer
	var icon_box := row.get_node("Content/IconBackground") as PanelContainer
	var icon := icon_box.get_node("Icon") as TextureRect
	var default_accent := UIConstants.COLOR_GOLD
	if row == _reputation_row:
		default_accent = UIConstants.COLOR_DANGER_MUTED
	elif row == _wind_row:
		default_accent = UIConstants.COLOR_SUCCESS_MUTED
	var accent: Color = row.get_meta("_icon_accent", default_accent)
	var icon_kind: int = int(row.get_meta("_icon_kind", PixelIcon.Kind.COIN))
	var is_primary := row in [_funds_row, _rating_row, _reputation_row]

	var target_row_h := float(m["row_height"])
	var target_pill_h := float(m["value_background_height"])
	if _portrait_mode and is_primary:
		# Keep primary portrait cards at least 44px tall for phone touch targets.
		target_row_h = maxf(float(UIConstants.TOUCH_TARGET_SIZE), target_row_h)
		target_pill_h = target_row_h - 6.0

	row.custom_minimum_size.y = target_row_h
	value.custom_minimum_size.y = target_pill_h
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _portrait_mode else Control.SIZE_FILL
	row.size_flags_stretch_ratio = (1.18 if row == _funds_row else 1.0) if _portrait_mode else 1.0
	content.add_theme_constant_override("separation", -8 if _portrait_mode else -int(m["value_icon_overlap"]))
	value.add_theme_stylebox_override("panel", _card_style_for_row(accent, row))

	var box_side := float(m["icon_background_size"])
	var icon_side := float(m["icon_size"])
	icon_box.custom_minimum_size = Vector2.ONE * box_side
	icon.custom_minimum_size = Vector2.ONE * icon_side
	icon.texture = PixelIcon.texture(icon_kind, int(icon_side), accent)
	icon_box.add_theme_stylebox_override("panel", _icon_style_for_row(accent, row))
	var action := row.get_node_or_null("Action") as Button
	if action:
		_paint_row_button(action, accent, 8 if _portrait_mode else int(m["card_radius"]))

	# Portrait swaps the five-star strip for a number plus the existing medallion.
	icon_box.visible = true
	if row == _rating_row:
		_rating_stars.visible = not _portrait_mode
		_portrait_rating_label.visible = _portrait_mode
		if not _portrait_mode:
			_rating_stars.set_compact(_is_compact() or fs < 20)
			var inner_h := target_pill_h - float(m["value_vertical_margin"]) * 2.0
			_rating_stars.custom_minimum_size.y = clampf(inner_h, float(_rating_stars.star_side()), float(_rating_stars._strip_height()))

	if apply_font_override:
		_applying_row_style = true
		for child in row.get_node("Content/ValueBackground/ValueContent").get_children():
			if child is Label:
				child.add_theme_font_size_override("font_size", fs)
		_applying_row_style = false

func _on_value_label_theme_changed(row: PanelContainer, label: Label) -> void:
	if _applying_row_style or row == null or label == null:
		return
	if label == _portrait_rating_label and not _portrait_mode:
		return
	var fs := label.get_theme_font_size("font_size")
	if fs <= 0 or fs == int(row.get_meta("_applied_font_size", -1)):
		return
	_apply_row_metrics(row, fs, false)
	if label == _money_label:
		_update_money()
	elif not label.text.is_empty():
		_set_value_text(label, label.text)
	_sync_rating_row_to_siblings()
	_refresh_height()

func _sync_rating_row_to_siblings() -> void:
	if _portrait_mode or _rating_row == null:
		return
	var text_rows: Array[PanelContainer] = [_funds_row, _season_row, _reputation_row, _weather_row, _wind_row]
	var uniform_fs := -1
	for sibling in text_rows:
		if sibling == null or not sibling.visible:
			continue
		var lbl := sibling.get_node_or_null("Content/ValueBackground/ValueContent/Value") as Label
		if lbl == null:
			continue
		var sibling_fs := lbl.get_theme_font_size("font_size")
		if uniform_fs == -1:
			uniform_fs = sibling_fs
		elif uniform_fs != sibling_fs:
			return
	if uniform_fs > 0 and uniform_fs != int(_rating_row.get_meta("_applied_font_size", -1)):
		_apply_row_metrics(_rating_row, uniform_fs, false)

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
		if eb.has_signal("course_rating_changed"):
			eb.course_rating_changed.connect(_on_course_rating_changed)

func _update_all() -> void:
	_update_money()
	_update_season()
	_update_reputation()
	_update_rating_from_game()
	_update_weather()
	_update_wind()
	_update_feature_rows()

## Show only the cards of the features this course plays with. A feature that
## is off has no row at all rather than one reading "Off": leaving Weather,
## Wind or Seasons out of the column says the same thing in less space.
func _update_feature_rows() -> void:
	if _season_row == null or _weather_row == null or _wind_row == null:
		return
	var in_tourney := has_node("/root/GameManager") and GameManager.is_tournament_mode
	var seasons_on := _is_feature_on("seasons")
	var weather_on := _is_feature_on("weather")
	var wind_on := _is_feature_on("wind")
	if _funds_row != null:
		_funds_row.visible = not in_tourney
	if _reputation_row != null:
		_reputation_row.visible = not in_tourney
	if _rating_row != null:
		_rating_row.visible = not in_tourney
	_season_row.visible = seasons_on
	_weather_row.visible = weather_on
	_wind_row.visible = wind_on
	if _environment_block:
		# The block introduces the weather/wind pair; with both off it goes too.
		_environment_block.visible = weather_on or wind_on
	if _portrait_mode:
		if _portrait_primary:
			_portrait_primary.visible = not in_tourney
		_portrait_secondary.visible = seasons_on or weather_on or wind_on
	_refresh_height()

## Whether the course plays with a feature. Without a GameManager — a column
## built on its own, as the layout tests do — every row is kept.
func _is_feature_on(feature: String) -> bool:
	if not has_node("/root/GameManager"):
		return true
	return GameManager.is_feature_enabled(feature)

func _update_money() -> void:
	if not has_node("/root/GameManager") or _money_label == null:
		return
	var gm = get_node("/root/GameManager")
	var money = gm.get("money")
	if money == null:
		money = GameManager.DEFAULT_STARTING_MONEY

	var money_int := int(money)
	var formatted := format_money_to_fit(
		money_int,
		_money_available_width(),
		_money_label.get_theme_font("font"),
		_money_label.get_theme_font_size("font_size")
	)
	_set_value_text(_money_label, formatted)
	_refresh_money_tooltip(money_int, formatted)

	# Color based on balance
	if money_int < 0:
		_money_label.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	elif money_int < 5000:
		_money_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_money_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)

func _refresh_money_tooltip(amount: int, displayed_text: String) -> void:
	if _funds_row == null:
		return
	var full_text := _format_money_full(amount)
	var tip := "%s — Click to view financial details" % full_text if displayed_text != full_text \
		else "Click to view financial details"
	_funds_row.tooltip_text = tip
	var action := _funds_row.get_node_or_null("Action") as Button
	if action:
		action.tooltip_text = tip
		action.accessibility_description = tip

## The Season card follows the calendar (the full date itself reads out in the
## top-left CourseLocationBanner). With the Seasons feature off the calendar
## still ticks, but the course plays as one year-round season and
## _update_feature_rows hides the row.
func _update_season() -> void:
	if not has_node("/root/GameManager") or _time_label == null:
		return
	var gm = get_node("/root/GameManager")
	var day = gm.get("current_day")
	if day == null:
		day = 1

	var season = SeasonSystem.get_season(day)
	var season_color := SeasonSystem.get_season_color(season)
	_set_value_text(_time_label, SeasonSystem.get_season_name(season))
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

	_set_value_text(_reputation_label, "%d%%" % int(rep))

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
		_set_value_text(_weather_label, "Sunny")
		_set_row_icon(_weather_icon, PixelIcon.Kind.SUN, UIConstants.COLOR_GOLD)
		return

	# The Weather feature can be turned off at setup: _update_feature_rows
	# then hides the row, so there is nothing to show here.
	if not GameManager.weather_enabled:
		return
	var weather_system = GameManager.get("weather_system")
	if weather_system == null:
		_set_value_text(_weather_label, "Sunny")
		_set_row_icon(_weather_icon, PixelIcon.Kind.SUN, UIConstants.COLOR_GOLD)
		return

	var weather_type = weather_system.get("weather_type")
	if weather_type == null:
		weather_type = 0

	var weather_name: String = UIConstants.get_weather_name(weather_type)
	_weather_row.tooltip_text = weather_name
	if _portrait_mode:
		weather_name = ["Sunny", "Cloudy", "Overcast", "Light rain", "Rain", "Storm"][clampi(weather_type, 0, 5)]
	_set_value_text(_weather_label, weather_name)

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
		_set_value_text(_wind_label, "0 mph")
		return

	# The Wind feature can be turned off at setup: the air is dead calm and
	# _update_feature_rows hides the row.
	if not GameManager.wind_enabled:
		return
	var wind_system = GameManager.get("wind_system")
	if wind_system == null:
		_set_value_text(_wind_label, "0 mph")
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
	_wind_row.tooltip_text = "%s wind, %d mph" % [dir_name, int(speed)]
	_set_value_text(_wind_label, ("%s %d" if _portrait_mode else "%s %d mph") % [dir_name, int(speed)])

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

static func _safe_abs_int(value: int) -> int:
	if value >= 0:
		return value
	if value < -9223372036854775807:
		return 9223372036854775807
	return -value

static func _format_number(num: int) -> String:
	var str_num := str(_safe_abs_int(num))
	var result := ""
	var count := 0
	for i in range(str_num.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_num[i] + result
		count += 1
	if num < 0:
		result = "-" + result
	return result

static func _format_money_full(amount: int) -> String:
	var prefix := "-$ " if amount < 0 else "$ "
	return "%s%s" % [prefix, _format_number(_safe_abs_int(amount))]

static func format_money_to_fit(amount: int, max_width: float, font: Font = null,
		font_size: int = VALUE_FONT_SIZE) -> String:
	var full_text := _format_money_full(amount)
	if _string_fits_width(full_text, max_width, font, font_size):
		return full_text

	var abs_amount := _safe_abs_int(amount)
	if abs_amount < 1000:
		return full_text

	var prefix := "-$ " if amount < 0 else "$ "
	for tier in MONEY_SUFFIXES:
		var divisor: int = tier[0]
		if abs_amount < divisor:
			continue
		var suffix: String = tier[1]
		for decimals in [2, 1, 0]:
			var candidate := "%s%s" % [prefix, _format_scaled_number(abs_amount, divisor, suffix, decimals)]
			if decimals == 0 or _string_fits_width(candidate, max_width, font, font_size):
				return candidate
	return full_text

static func _string_fits_width(text: String, max_width: float, font: Font, font_size: int) -> bool:
	if max_width <= 0.0:
		return false
	if font != null:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width
	var estimated_char_width := maxf(1.0, float(font_size) * 0.55)
	return float(text.length()) * estimated_char_width <= max_width

static func _format_scaled_number(abs_amount: int, divisor: int, suffix: String, decimals: int) -> String:
	@warning_ignore_start("integer_division")
	if decimals <= 0:
		return "%d%s" % [abs_amount / divisor, suffix]
	var decimal_factor := 1
	for _i in decimals:
		decimal_factor *= 10
	var step := divisor / decimal_factor
	var scaled := abs_amount / step
	var whole := scaled / decimal_factor
	var frac := scaled % decimal_factor
	@warning_ignore_restore("integer_division")
	if frac == 0:
		return "%d%s" % [whole, suffix]
	var frac_str := ("%0" + str(decimals) + "d") % frac
	while frac_str.ends_with("0"):
		frac_str = frac_str.left(frac_str.length() - 1)
	return "%d.%s%s" % [whole, frac_str, suffix]

# Signal handlers
func _on_money_pressed() -> void:
	money_clicked.emit()

func _on_reputation_pressed() -> void:
	reputation_clicked.emit()

func _on_rating_pressed() -> void:
	rating_clicked.emit()

func update_rating(stars: float) -> void:
	if _rating_stars == null:
		return
	if stars <= 0.0:
		_has_rating = false
		_rating_value = 0.0
		_rating_stars.set_unrated()
	else:
		_has_rating = true
		_rating_value = clampf(stars, 0.0, float(CourseRatingStars.STAR_COUNT))
		_rating_stars.set_rating(_rating_value)
	if _portrait_rating_label:
		_portrait_rating_label.text = ("%.1f" % _rating_value) if _has_rating else "—"
		_portrait_rating_label.custom_minimum_size.x = 30.0
	_refresh_rating_tooltip()

static func format_rating_tooltip(stars: float, rated: bool = true) -> String:
	if not rated or stars <= 0.0:
		return "Course rating: Unrated (click for details)"
	var clamped := clampf(stars, 0.0, float(CourseRatingStars.STAR_COUNT))
	var tier := CourseRatingSystem.get_rating_text(clampi(roundi(clamped), 1, 5))
	return "Course rating: %.1f / 5.0 (%s) — click for details" % [clamped, tier]

func _refresh_rating_tooltip() -> void:
	if _rating_row == null:
		return
	var tip := format_rating_tooltip(_rating_value, _has_rating)
	_rating_row.tooltip_text = tip
	var action := _rating_row.get_node_or_null("Action") as Button
	if action:
		action.tooltip_text = tip
		action.accessibility_description = tip

func _update_rating_from_game() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm := get_node("/root/GameManager")
	if gm.get("current_course") == null:
		return
	var rating = gm.get("course_rating")
	if rating is Dictionary and rating.has("overall"):
		update_rating(float(rating["overall"]))

func _on_course_rating_changed(rating: Dictionary) -> void:
	update_rating(float(rating.get("overall", 3.0)))

func _on_money_changed(_old_amount: int, _new_amount: int) -> void:
	_update_money()

func _on_day_changed(_new_day: int) -> void:
	_update_season()

func _on_reputation_changed(_old_rep: float, _new_rep: float) -> void:
	_update_reputation()

func _on_weather_changed(_weather_type: int, _intensity: float) -> void:
	_update_weather()

func _on_wind_changed(_direction: float, _speed: float) -> void:
	_update_wind()
