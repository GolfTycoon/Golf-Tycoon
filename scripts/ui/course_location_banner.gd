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
## The view controls live in the same corner, to the right of both columns: the
## two Rotate arrows that turn the course, and - in the details card's own
## top-right corner - the facing chip that names the direction the course faces
## and folds the arrows away again when the corner should stay quiet.
##
## The banner follows the active WorldMap location: buying a site or swapping
## between owned courses swaps the picture and name, and the date ticks with
## EventBus.day_changed. With no active location (a fresh world on the title
## screen) it hides itself, and it ignores the mouse like the status column so
## shots and course clicks pass straight through the corner.

## The corner changed the room it takes (a layout reflow, or the Rotate arrows
## folding in or out), so anything docked beneath it moves with it.
signal layout_changed

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

## Whole-pixel scale of the square source picture, per layout.
const PICTURE_SCALE_DESKTOP := 2
const PICTURE_SCALE_COMPACT := 1
## Fixed widths of the two columns per layout; the name ellipsises inside the
## detail card. They carry the room the facing chip takes out of the card's
## top-right corner, so the name and date lose none of the width they had
## before it arrived.
const WIDTH_DESKTOP := 320.0
const WIDTH_COMPACT := 232.0
## The narrowest the two columns may be squeezed to on a window too small for
## them and the Rotate arrows side by side.
const MIN_COLUMNS_WIDTH := 150.0
## Corner radius shared by the details card and the picture frame.
const CARD_RADIUS := 6
const FRAME_RADIUS := 4
## Reserve for the banner before its first layout pass: the square picture plus
## its frame (desktop 64+6, compact 32+6). The facing chip and the Rotate arrows
## can ask for a little more, and banner_height() takes whichever is tallest.
const HEIGHT_DESKTOP := 70.0
const HEIGHT_COMPACT := 38.0

## The view controls: gap between the details card and the Rotate arrows, and
## the arrows' face size on a desktop layout (touch layouts use the standard
## touch target instead).
const VIEW_CONTROLS_GAP := 6.0
const ROTATE_BUTTON_SIZE := 32.0

var _picture: TextureRect
var _picture_frame: PanelContainer
var _details_panel: PanelContainer
var _name_label: Label
var _date_label: Label
var _date_icon: TextureRect
var _accent_strip: PanelContainer

## The view controls, to the right of the two columns. `orientation_toggle` is
## the facing chip inside the details card; the two arrows stand beside it.
var rotate_controls: HBoxContainer
var rotate_ccw_btn: RotateViewButton
var rotate_cw_btn: RotateViewButton
var orientation_toggle: OrientationToggleButton
## Whether the two Rotate arrows are out beside the card (see
## set_rotate_controls_visible).
var _rotate_controls_shown := true

## The location currently shown, so only a real swap plays the entrance tween.
var _current_location_id: String = ""
var _tween: Tween = null
## The height last reported through layout_changed, so a re-anchor that moved
## nothing does not wake the HUD pieces below.
var _reported_height := -1.0


func _ready() -> void:
	add_to_group(UIConstants.COURSE_BANNER_GROUP)
	_build_ui()
	_connect_signals()
	_apply_anchors()
	# The details card can grow past the banner's reserve when the facing chip
	# arrives or a layout change resizes its rows; the corner takes the new
	# height at once rather than waiting for the next window resize.
	_details_panel.minimum_size_changed.connect(_apply_anchors)
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

	# The facing chip rides in the card's own top-right corner: the arrow and
	# the N / E / S / W letter, and the switch that folds the Rotate arrows
	# away. It is the one part of the card that takes the mouse.
	orientation_toggle = OrientationToggleButton.new()
	orientation_toggle.name = "OrientationToggleBtn"
	orientation_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	orientation_toggle.pressed.connect(_on_orientation_toggle_pressed)
	details_row.add_child(orientation_toggle)
	_sync_orientation_toggle()

	# The Rotate arrows stand to the right of both columns, on the same top-left
	# corner: the card names the course, the arrows turn it.
	rotate_controls = HBoxContainer.new()
	rotate_controls.name = "RotateViewControls"
	rotate_controls.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	rotate_controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rotate_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(rotate_controls)

	rotate_ccw_btn = RotateViewButton.new()
	rotate_ccw_btn.name = "RotateCCWBtn"
	rotate_ccw_btn.accessibility_name = "Rotate course counter-clockwise"
	rotate_controls.add_child(rotate_ccw_btn)

	rotate_cw_btn = RotateViewButton.new()
	rotate_cw_btn.name = "RotateCWBtn"
	rotate_cw_btn.clockwise = true
	rotate_cw_btn.accessibility_name = "Rotate course clockwise"
	rotate_controls.add_child(rotate_cw_btn)
	_refresh_rotate_tooltips()

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
	if has_node("/root/InputBindings"):
		InputBindings.bindings_changed.connect(_on_binding_changed)
		InputBindings.bindings_reset.connect(_on_bindings_reset)


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
# VIEW CONTROLS
# =============================================================================

## Point the facing chip's arrow and letter at the way the course faces.
func set_orientation(view_orientation: int) -> void:
	if orientation_toggle == null:
		return
	orientation_toggle.orientation = view_orientation
	_sync_orientation_toggle()


## Show or fold away the two Rotate arrows beside the details card. The facing
## chip stays either way, so the corner can always get them back; the card
## narrows back into the room they were using.
func set_rotate_controls_visible(shown: bool) -> void:
	if rotate_controls == null:
		return
	_rotate_controls_shown = shown
	rotate_controls.visible = shown
	_sync_orientation_toggle()
	_apply_layout_sizes()
	_apply_anchors()


## Whether the two Rotate arrows are out beside the card.
func rotate_controls_visible() -> bool:
	return _rotate_controls_shown


## Flip the two Rotate arrows in or out, the way a press on the facing chip does.
func toggle_rotate_controls() -> void:
	set_rotate_controls_visible(not _rotate_controls_shown)


func _on_orientation_toggle_pressed() -> void:
	toggle_rotate_controls()


## The arrows' tooltips name the keys in force, so they never go stale after a
## player rebinds the view rotation in Settings.
func _refresh_rotate_tooltips() -> void:
	if is_instance_valid(rotate_ccw_btn):
		rotate_ccw_btn.tooltip_text = _rotate_tooltip("counter-clockwise", "rotate_camera")
	if is_instance_valid(rotate_cw_btn):
		rotate_cw_btn.tooltip_text = _rotate_tooltip("clockwise", "rotate_camera_cw")


func _rotate_tooltip(direction: String, action: String) -> String:
	var keys := InputBindings.binding_text(action)
	if keys.is_empty() or keys == "Unbound":
		return "Rotate course %s" % direction
	return "Rotate course %s (%s)" % [direction, keys]


func _on_binding_changed(action: String) -> void:
	if action == "rotate_camera" or action == "rotate_camera_cw":
		_refresh_rotate_tooltips()


func _on_bindings_reset() -> void:
	_refresh_rotate_tooltips()


## The chip reads as a switch as well as a compass: its rim and ink follow the
## arrows' state, and so does what it says it will do.
func _sync_orientation_toggle() -> void:
	if orientation_toggle == null:
		return
	orientation_toggle.controls_shown = _rotate_controls_shown
	var action := "hide" if _rotate_controls_shown else "show"
	var tip := "The course faces %s. Click to %s the rotate buttons" % [
		orientation_toggle.letter, action]
	orientation_toggle.tooltip_text = tip
	orientation_toggle.accessibility_name = "View direction and rotate buttons"
	orientation_toggle.accessibility_description = tip


# =============================================================================
# LAYOUT
# =============================================================================

func _is_compact() -> bool:
	return has_node("/root/Screen") and Screen.is_compact()


func _picture_scale() -> int:
	return PICTURE_SCALE_COMPACT if _is_compact() else PICTURE_SCALE_DESKTOP


## The two columns' own width, before the view controls beside them. A window
## too narrow for both gives up the card's width first, so the corner never
## runs off the screen with its arrows: they would be clipped and unreachable.
func _columns_width() -> float:
	var width := WIDTH_COMPACT if _is_compact() else WIDTH_DESKTOP
	if is_inside_tree():
		var usable: float = get_viewport_rect().size.x \
			- float(UIConstants.HUD_COLUMN_MARGIN) * 2.0 - _view_controls_width()
		width = minf(width, usable)
	return maxf(width, MIN_COLUMNS_WIDTH)


## Room the Rotate arrows take beside the card: nothing while they are folded
## away, so the whole banner narrows back into the corner.
func _view_controls_width() -> float:
	if rotate_controls == null or not rotate_controls.visible:
		return 0.0
	return rotate_controls.get_combined_minimum_size().x + VIEW_CONTROLS_GAP


func _banner_width() -> float:
	return _columns_width() + _view_controls_width()


## The banner's height for the current layout, used before the first layout
## pass (e.g. when the scores dock positions itself beneath the banner). The
## Rotate arrows and the facing chip can stand taller than a compact card, and
## when they do the banner grows with them rather than letting them hang over
## the course.
func banner_height() -> float:
	var base := HEIGHT_COMPACT if _is_compact() else HEIGHT_DESKTOP
	var arrows := 0.0
	if rotate_controls and rotate_controls.visible:
		arrows = rotate_controls.get_combined_minimum_size().y
	var card := 0.0
	if _details_panel:
		card = _details_panel.get_combined_minimum_size().y
	return maxf(base, maxf(arrows, card))


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
	var picture_scale := _picture_scale()
	# Square art: width and height come from the same grid side.
	var picture_side: int = CourseLocationPicture.GRID_W * picture_scale
	_picture.custom_minimum_size = Vector2(picture_side, picture_side)
	_name_label.add_theme_font_size_override(
		"font_size", UIConstants.FONT_SIZE_BASE if _is_compact() else UIConstants.FONT_SIZE_MD)
	_date_label.add_theme_font_size_override(
		"font_size", UIConstants.FONT_SIZE_XS if _is_compact() else UIConstants.FONT_SIZE_SM)
	_date_icon.custom_minimum_size = Vector2(12, 12) if _is_compact() else Vector2(14, 14)
	# The arrows take their layout's target before the width is read, so the
	# banner reserves exactly the room they need.
	_apply_view_control_sizes()
	custom_minimum_size = Vector2(_banner_width(), 0)


## Size the Rotate arrows and the facing chip for the current layout. Touch
## layouts grow the arrows to the standard touch target; desktop keeps the
## small medallion the dock used to carry.
func _apply_view_control_sizes() -> void:
	var touch := has_node("/root/Screen") and Screen.uses_touch_layout()
	var target := Vector2.ONE * (float(UIConstants.TOUCH_TARGET_SIZE) if touch \
		else ROTATE_BUTTON_SIZE)
	var arrows: Array[RotateViewButton] = [rotate_ccw_btn, rotate_cw_btn]
	for button in arrows:
		if button == null:
			continue
		button.diameter = target.x
		button.custom_minimum_size = target
		button.size = target
		button.queue_redraw()
	if orientation_toggle:
		orientation_toggle.apply_screen()


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
	var occupied := get_occupied_height()
	if not is_equal_approx(occupied, _reported_height):
		_reported_height = occupied
		layout_changed.emit()


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
