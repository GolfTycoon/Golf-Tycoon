extends Button
class_name SkinGroupColorButton
## One Re-color Group of the owner's Golfer Skin as a pocket name plate on the
## Edit Player Golfer shelf, in the Visiting Golfers visual language.
##
## The plate carries exactly two things: the group's colour as a swatch on the
## left, and the group's name beside it - the same arrangement, pixel font and
## shared PixelButtonStyle card the visiting golfer plates wear (see
## VisitorCardButton), so the colours read as part of the same register.
##
## Pressing the plate opens the engine's own ColorPicker in a popup and every
## colour it hands back is emitted as `color_changed`, which is what writes the
## group. A native ColorPickerButton cannot wear this frame: it paints its colour
## over the whole face, corners included, which would cover the card's rim. So
## the plate draws the swatch itself and hosts the picker separately.
##
## The native `text` stays the group's name - tests and assistive tech read it -
## but the plate paints its own caption, so every font colour is transparent.

const FONT := PixelCircleButton.FONT
const CREAM := PixelCircleButton.CREAM
const NAME_LIT := Color("ffffff")
## The visiting green the on-course golfer plates wear.
const ACCENT := Color("83c9a4")

## Whole plate footprint. Five stack in one column of the Edit Player shelf
## (5 x 26 + 4 x 3 = 142), so the standard Shirt/Pants/Cap/Hair/Skin set reads as
## a single column beside the sprite. The portrait tray is the tightest shelf it
## has to fit (146px above the scrollbar); see
## test_the_group_colour_column_fits_the_portrait_tray.
const BUTTON_SIZE := Vector2(150, 26)

## The swatch's drawing area, and where the caption starts.
const SWATCH_AREA := Rect2(4, 3, 20, 20)
const TEXT_X := 30.0

const NAME_FONT_SIZE := 13
const NAME_FONT_MIN := 9

## Emitted for every colour the picker hands back, so the group is written as
## the player drags - the same contract as the ColorPickerButton this replaces.
signal color_changed(new_color: Color)

## The group's colour, drawn as the swatch. Setting it repaints the plate.
var color := Color.WHITE:
	set(value):
		if color != value:
			color = value
			queue_redraw()

var _hovered := false
## The picker and its popup are built on the first press, the way the engine's
## own ColorPickerButton defers them: opening the shelf never pays for a picker
## nobody asked for.
var _popup: PopupPanel = null
var _picker: ColorPicker = null
## The colour the plate carried when the popup opened, so Esc puts it back.
var _opened_color := Color.WHITE


func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	# The caption is drawn to fit (see _draw_name), so the native text must not
	# drive the plate's minimum size: a long group name would otherwise widen the
	# whole column past the sprite it stands beside.
	clip_text = true
	PixelButtonStyle.paint_card(self, ACCENT, 0, 0, Color("e4e7d5"), Color.WHITE)
	# The plate draws its own caption, so the native text never fights the art.
	for font_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color", "font_disabled_color",
			"font_outline_color"]:
		add_theme_color_override(font_state, Color.TRANSPARENT)
	if accessibility_name.is_empty():
		accessibility_name = text
	accessibility_description = "Re-color Group colour. Activate to choose a colour."
	for event_signal in [mouse_entered, mouse_exited, button_down, button_up,
			focus_entered, focus_exited]:
		event_signal.connect(queue_redraw)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	pressed.connect(_open_picker)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return  # Not laid out yet.
	var dip := 1.0 if is_pressed() and not disabled else 0.0
	var lit := (_hovered or has_focus()) and not disabled
	_draw_swatch(dip)
	_draw_name(dip, lit)


## The group's colour as a crisp chip, with an ink border so a pale colour still
## reads against the card.
func _draw_swatch(dip: float) -> void:
	var area := Rect2(SWATCH_AREA.position + Vector2(0.0, dip), SWATCH_AREA.size)
	draw_rect(area, PixelCircleButton.INK)
	draw_rect(area.grow(-2.0), color)


## The group's name, fitted to the room between the swatch and the frame: shrunk
## a step at a time for long names, clipped at the frame's edge if it still does
## not fit - the same fallback the visiting golfer plates use.
func _draw_name(dip: float, lit: bool) -> void:
	var available := size.x - TEXT_X - 6.0
	var font_size := NAME_FONT_SIZE
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while font_size > NAME_FONT_MIN and width > available:
		font_size -= 1
		width = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := dip + (size.y + FONT.get_ascent(font_size) - FONT.get_descent(font_size)) * 0.5
	var caption_color := NAME_LIT if lit else CREAM
	if disabled:
		caption_color = UIConstants.COLOR_TEXT_MUTED
	draw_string(FONT, Vector2(TEXT_X, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, available, font_size, caption_color)


# ── The colour picker ─────────────────────────────────────────────────────

## Build the picker on first use. It hangs off the plate, so it is freed with it
## when the shelf is rebuilt for another skin.
func _ensure_picker() -> void:
	if _popup != null and is_instance_valid(_popup):
		return
	_popup = PopupPanel.new()
	_popup.name = "ColorPopup"
	_popup.wrap_controls = true
	add_child(_popup)
	_picker = ColorPicker.new()
	_picker.name = "ColorPicker"
	_picker.edit_alpha = false
	_picker.color = color
	_popup.add_child(_picker)
	_picker.color_changed.connect(_on_picker_color_changed)
	_popup.popup_hide.connect(_on_popup_hidden)
	# The picker is part of the Golfer Skin controls, which stay reachable while
	# a round runs (see PlayerRoundManager.start_round). Tag its controls so that
	# lock passes over them instead of disabling the picker mid-round.
	_popup.set_meta("editable_while_playing", true)
	for control in _popup.find_children("*", "Control", true, false):
		control.set_meta("editable_while_playing", true)


## Open the picker over the plate, above it when the shelf sits in the bottom
## half of the window - which is where this shelf lives.
func _open_picker() -> void:
	if disabled:
		return
	_ensure_picker()
	if _popup.visible:
		_popup.hide()
		return
	_opened_color = color
	_picker.color = color
	_popup.reset_size()
	var wanted := _popup.get_contents_minimum_size()
	var viewport_height := get_viewport_rect().size.y
	var show_above := global_position.y + size.y + wanted.y > viewport_height \
		and global_position.y * 2.0 + size.y > viewport_height
	var offset := Vector2((size.x - wanted.x) * 0.5, -wanted.y if show_above else size.y)
	_popup.position = Vector2i(get_screen_position() + offset)
	_popup.popup()


func _on_picker_color_changed(picked: Color) -> void:
	color = picked
	color_changed.emit(picked)


## Esc abandons the pick, the way the engine's own picker button does.
func _on_popup_hidden() -> void:
	if Input.is_action_just_pressed("ui_cancel") and color != _opened_color:
		color = _opened_color
		color_changed.emit(_opened_color)
