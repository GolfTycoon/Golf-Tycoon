extends PanelContainer
class_name CourseLocationBanner
## CourseLocationBanner - The top-left postcard for the course being played.
##
## Two columns, in the corner above every other gameplay readout:
##   1. A square pixel-art picture of the location - a different painted scene
##      for every course site (see CourseLocationPicture), sitting directly on
##      the course view inside a hairline photo frame with no background of its
##      own.
##   2. A dark card holding the location's name and the current in-game date.
##      This details card is the only part of the banner that paints a
##      background; the picture column stays transparent.
##
## The banner follows the active WorldMap location: buying a site or swapping
## between owned courses swaps the picture and name, and the date ticks with
## EventBus.day_changed. With no active location (a fresh world on the title
## screen) it hides itself, and it ignores the mouse like the status column so
## shots and course clicks pass straight through the corner.

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

## Whole-pixel scale of the square source picture, per layout.
const PICTURE_SCALE_DESKTOP := 2
const PICTURE_SCALE_COMPACT := 1
## Fixed banner widths per layout; the name ellipsises inside the detail card.
const WIDTH_DESKTOP := 276.0
const WIDTH_COMPACT := 208.0
## Corner radius shared by the details card and the picture frame.
const CARD_RADIUS := 6
const FRAME_RADIUS := 4
## Reserve for the banner before its first layout pass: the square picture plus
## its frame (desktop 64+6, compact 32+6). The details card is never taller.
const HEIGHT_DESKTOP := 70.0
const HEIGHT_COMPACT := 38.0

var _picture: TextureRect
var _picture_frame: PanelContainer
var _details_panel: PanelContainer
var _name_label: Label
var _date_label: Label
var _date_icon: TextureRect
var _accent_strip: PanelContainer

## The location currently shown, so only a real swap plays the entrance tween.
var _current_location_id: String = ""
var _tween: Tween = null


func _ready() -> void:
	add_to_group(UIConstants.COURSE_BANNER_GROUP)
	_build_ui()
	_connect_signals()
	_apply_anchors()
	refresh()


# =============================================================================
# BUILD
# =============================================================================

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# The root paints nothing: the picture column is transparent and only the
	# details card on the right carries a background.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", UIConstants.SEPARATION_LG)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(columns)

	# Column 1: the square location postcard in a border-only photo frame.
	_picture_frame = PanelContainer.new()
	_picture_frame.name = "PictureFrame"
	_picture_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_picture_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_frame.add_theme_stylebox_override("panel", _frame_style())
	columns.add_child(_picture_frame)

	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_frame.add_child(_picture)

	# Column 2: the only surface with a background - the name and date card.
	_details_panel = PanelContainer.new()
	_details_panel.name = "DetailsPanel"
	_details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_details_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_details_panel.add_theme_stylebox_override("panel", _card_style())
	columns.add_child(_details_panel)

	var details_row := HBoxContainer.new()
	details_row.name = "Details"
	details_row.add_theme_constant_override("separation", UIConstants.SEPARATION_MD)
	details_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_details_panel.add_child(details_row)

	# The gold spine belongs to the details card, down its left edge.
	_accent_strip = PanelContainer.new()
	_accent_strip.name = "AccentStrip"
	_accent_strip.custom_minimum_size = Vector2(3, 0)
	_accent_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_accent_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = UIConstants.COLOR_GOLD
	strip_style.set_corner_radius_all(2)
	_accent_strip.add_theme_stylebox_override("panel", strip_style)
	details_row.add_child(_accent_strip)

	var text_column := VBoxContainer.new()
	text_column.name = "Text"
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_column.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_row.add_child(text_column)

	_name_label = Label.new()
	_name_label.name = "LocationName"
	_name_label.add_theme_font_override("font", TITLE_FONT)
	_name_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_name_label)

	var date_row := HBoxContainer.new()
	date_row.name = "DateRow"
	date_row.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	date_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(date_row)

	_date_icon = TextureRect.new()
	_date_icon.name = "DateIcon"
	_date_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_date_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_date_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_date_icon.custom_minimum_size = Vector2(14, 14)
	_date_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_date_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_row.add_child(_date_icon)

	_date_label = Label.new()
	_date_label.name = "Date"
	_date_label.add_theme_font_override("font", BODY_FONT)
	_date_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A clipped label reports a near-zero minimum width; without EXPAND the
	# HBox would leave it at a single pixel and trim the whole date away.
	_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_label.clip_text = true
	_date_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_row.add_child(_date_label)

	_apply_layout_sizes()


## The dark details card: the banner's only background, with a hairline sage
## border and room for the gold spine and its two text rows.
func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIConstants.COLOR_BG_DARK, 0.88)
	style.set_border_width_all(1)
	style.border_color = Color(UIConstants.COLOR_BORDER, 0.75)
	style.set_corner_radius_all(CARD_RADIUS)
	style.content_margin_left = 8
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


## A border-only frame around the postcard: transparent fill so the course
## view shows right up to the picture's hairline edge.
func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(1)
	style.border_color = Color(UIConstants.COLOR_BORDER, 0.85)
	style.set_corner_radius_all(FRAME_RADIUS)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


# =============================================================================
# STATE
# =============================================================================

func _connect_signals() -> void:
	if has_node("/root/WorldMap"):
		WorldMap.active_location_changed.connect(_on_active_location_changed)
		WorldMap.world_reset.connect(_on_world_reset)
	if has_node("/root/EventBus"):
		EventBus.day_changed.connect(_on_day_changed)
		EventBus.load_completed.connect(_on_load_completed)
		EventBus.new_game_started.connect(refresh)


## Re-read the active location and the calendar. Safe to call any time; the
## banner hides itself while no location is active.
func refresh() -> void:
	var location_id := ""
	if has_node("/root/WorldMap"):
		location_id = WorldMap.active_location_id
	if location_id.is_empty():
		_current_location_id = ""
		visible = false
		return
	visible = true
	var definition := WorldLocations.get_definition(location_id)
	var location_name: String = str(definition.get("name", location_id))
	var location_theme: int = int(definition.get("theme", CourseTheme.Type.PARKLAND))
	_name_label.text = location_name
	_picture.texture = CourseLocationPicture.texture_for_location(
		location_id, location_theme, _picture_scale())
	_update_date()
	if _current_location_id != location_id and not _current_location_id.is_empty():
		_play_swap_animation()
	_current_location_id = location_id


func _update_date() -> void:
	if _date_label == null:
		return
	var day := 1
	if has_node("/root/GameManager"):
		var current = GameManager.get("current_day")
		if current != null:
			day = int(current)
	# Wide card: weekday and date. Narrow card: the compact stamp.
	_date_label.text = GameCalendar.format_date_short(day) if _is_compact() \
		else GameCalendar.format_date(day)
	if _date_icon:
		_date_icon.texture = PixelIcon.texture(
			PixelIcon.Kind.CALENDAR, 14, Color(UIConstants.COLOR_GOLD, 0.85))


# =============================================================================
# LAYOUT
# =============================================================================

func _is_compact() -> bool:
	return has_node("/root/Screen") and Screen.is_compact()


func _picture_scale() -> int:
	return PICTURE_SCALE_COMPACT if _is_compact() else PICTURE_SCALE_DESKTOP


func _banner_width() -> float:
	return WIDTH_COMPACT if _is_compact() else WIDTH_DESKTOP


## The banner's height for the current layout, used before the first layout
## pass (e.g. when the scores dock positions itself beneath the banner).
func banner_height() -> float:
	return HEIGHT_COMPACT if _is_compact() else HEIGHT_DESKTOP


## Re-derive every size-sensitive piece after a responsive window change.
func apply_screen() -> void:
	if not is_inside_tree():
		return
	_apply_layout_sizes()
	_apply_anchors()
	# The picture's pixel scale and the date format follow the layout.
	if not _current_location_id.is_empty():
		var definition := WorldLocations.get_definition(_current_location_id)
		_picture.texture = CourseLocationPicture.texture_for_location(
			_current_location_id,
			int(definition.get("theme", CourseTheme.Type.PARKLAND)),
			_picture_scale())
	_update_date()


func _apply_layout_sizes() -> void:
	custom_minimum_size = Vector2(_banner_width(), 0)
	var picture_scale := _picture_scale()
	# Square art: width and height come from the same grid side.
	var picture_side: int = CourseLocationPicture.GRID_W * picture_scale
	_picture.custom_minimum_size = Vector2(picture_side, picture_side)
	_name_label.add_theme_font_size_override(
		"font_size", UIConstants.FONT_SIZE_BASE if _is_compact() else UIConstants.FONT_SIZE_MD)
	_date_label.add_theme_font_size_override(
		"font_size", UIConstants.FONT_SIZE_XS if _is_compact() else UIConstants.FONT_SIZE_SM)
	_date_icon.custom_minimum_size = Vector2(12, 12) if _is_compact() else Vector2(14, 14)


## Pin the banner to the top-left corner, growing right and down with its content.
func _apply_anchors() -> void:
	var margin: float = UIConstants.HUD_COLUMN_MARGIN
	set_anchor(SIDE_LEFT, 0.0)
	set_anchor(SIDE_TOP, 0.0)
	set_anchor(SIDE_RIGHT, 0.0)
	set_anchor(SIDE_BOTTOM, 0.0)
	offset_left = margin
	offset_top = margin
	offset_right = margin + _banner_width()
	offset_bottom = margin + banner_height()
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END


## Vertical space the banner occupies from the top of the screen, including
## its margin. Other top-left HUD elements dock below this.
func get_occupied_height() -> float:
	return offset_top + maxf(get_combined_minimum_size().y, banner_height())


# =============================================================================
# SIGNALS AND ANIMATION
# =============================================================================

func _on_active_location_changed(_location_id: String) -> void:
	refresh()


func _on_world_reset() -> void:
	# A new world clears the active location until its first site is bought.
	refresh()


func _on_day_changed(_new_day: int) -> void:
	_update_date()


func _on_load_completed(_success: bool) -> void:
	refresh()


## A quick fade-in when the postcard swaps to another course.
func _play_swap_animation() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.3
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.28)
