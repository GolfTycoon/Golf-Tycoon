extends Control
class_name TournamentLibraryScreen
## TournamentLibraryScreen — the shared chrome for the four Tournament Mode
## library screens.
##
## Save Course and Save Golfer are opened from the Pause Menu in a Career game;
## Choose Course and Choose Golfer are opened from the Start Tournament screen.
## None of them is a Career save slot: every one of them reads and writes the
## Tournament Mode library (the `tournament_courses` folder and the
## `tournament_golfers` section of settings.cfg), and handing a pick back to
## the screen that opened it is the caller's job — this screen only emits
## `closed` when its Back button (or Escape / controller B) is pressed.
##
## The four screens are peers, so they are built from one skeleton: the shared
## MenuBackdrop, the shared screen header (Back, the screen's PixelIcon
## sprite, a bold Pixelify Sans title), a split two-pane body on desktop and
## landscape windows (the work card on the left, the shelf on the right) and a
## stacked body on portrait windows, with the shelf scrolling on its own.
## Subclasses fill in the body; everything above it and every small furniture
## piece below it is built here once.

signal closed()

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY
const COLOR_QUIT := MenuStyle.ACCENT_QUIT
const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_RAISED := MenuStyle.RAIL_BG
const COLOR_INSET := MenuStyle.INSET_BG
const COLOR_TEXT := MenuStyle.TITLE_COLOR
const COLOR_MUTED := UIConstants.COLOR_TEXT_DIM
const COLOR_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_BORDER := UIConstants.COLOR_BORDER

var _layout_mode: int = Kit.LayoutMode.DESKTOP
var _built_size: Vector2 = Vector2.ZERO
## The open confirmation dialogue, if any. While one stands, this screen's own
## Escape handling steps aside: the dialogue answers Escape itself.
var _confirmation: ConfirmDialog = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if has_node("/root/Screen") and not Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.connect(_on_screen_changed)
	_build()
	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)

## Pure layout decision, kept public so the responsive breakpoints can be
## checked without constructing a window.
static func layout_mode_for(view: Vector2) -> int:
	return Kit.layout_mode_for(view)

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

func _on_screen_changed(window_size: Vector2, _world_scale: float) -> void:
	var new_layout := layout_mode_for(window_size)
	var remeasure := absf(window_size.x - _built_size.x) > maxf(120.0, _built_size.x * 0.16) \
		or absf(window_size.y - _built_size.y) > maxf(100.0, _built_size.y * 0.16)
	if new_layout != _layout_mode or remeasure:
		_capture_build_state()
		_build()

## Carry whatever the player half-typed across a rebuild. Subclasses override.
func _capture_build_state() -> void:
	pass

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_confirmation = null
	_layout_mode = layout_mode_for(_window_size())
	_built_size = _window_size()

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var frame := MarginContainer.new()
	frame.name = "LibraryFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var padding := Kit.outer_padding(_layout_mode, _built_size)
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, padding)
	add_child(frame)

	var page := VBoxContainer.new()
	page.name = "LibraryPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", Kit.page_separation(_layout_mode))
	frame.add_child(page)
	page.add_child(Kit.make_screen_header(_layout_mode, _screen_title(),
		_on_back_pressed, _header_trailing(), _screen_icon()))
	page.add_child(_build_body(_layout_mode, _built_size))
	_after_build()

## Override: the screen's name in the shared header.
func _screen_title() -> String:
	return "Tournament Library"

## Override: the PixelIcon sprite beside the title.
func _screen_icon() -> int:
	return PixelIcon.Kind.TROPHY

## Override: an optional control pinned to the header's right edge.
func _header_trailing() -> Control:
	return null

## Override: the split/stacked workspace below the header.
func _build_body(_mode: int, _view: Vector2) -> Control:
	return Control.new()

## Override: runs after every build (initial and resize rebuilds).
func _after_build() -> void:
	pass

## True when a side-by-side body fits the window: desktop, rotated phones and
## landscape tablets. Portrait layouts stack instead.
func _uses_split(mode: int, view: Vector2) -> bool:
	if mode == Kit.LayoutMode.DESKTOP or mode == Kit.LayoutMode.PHONE_LANDSCAPE:
		return true
	return Kit.is_tablet(mode) and view.x > view.y

func _set_margins(margin: MarginContainer, pad: int) -> void:
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)

func _make_hairline() -> ColorRect:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.color = MenuStyle.with_alpha(COLOR_BORDER, 0.5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

## One of the little value-over-caption stat tiles the archives use.
func _make_stat_tile(caption: String, value: String, mode: int) -> PanelContainer:
	var compact := Kit.is_phone(mode)
	var tile := Kit.make_panel(COLOR_RAISED, MenuStyle.with_alpha(COLOR_BORDER, 0.30))
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	var pad := (5 if mode == Kit.LayoutMode.PHONE_LANDSCAPE else 8) if compact else 10
	_set_margins(margin, pad)
	tile.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)
	var value_label := Kit.make_label(value, 13 if compact else 16, COLOR_GOLD)
	value_label.name = "Value"
	value_label.clip_text = true
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(value_label)
	var caption_label := Kit.make_label(caption.to_upper(), 8 if compact else 9, COLOR_QUIET)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption_label)
	return tile

## The "yyyy-mm-ddThh:mm:ss" stamp the library writes, as one quiet line.
static func format_saved_at(raw: String) -> String:
	var stamp := raw.strip_edges()
	if stamp.is_empty():
		return ""
	var parts := stamp.split("T", false)
	if parts.size() >= 2:
		var clock := str(parts[1]).split(":", false)
		var minutes := str(clock[1]) if clock.size() >= 2 else "00"
		return "%s  ·  %s:%s" % [str(parts[0]), str(clock[0]) if not clock.is_empty() else "00", minutes]
	return stamp

## A destructive action deserves a question first. Escape / controller B while
## the dialogue is up answers the dialogue, not the screen behind it.
func _show_confirmation(message: String, confirm_text: String, on_confirm: Callable,
		confirm_color: Color = UIConstants.COLOR_DANGER) -> void:
	_close_confirmation()
	var dialog := ConfirmDialog.new(message, confirm_text, "Cancel", confirm_color)
	dialog.name = "LibraryConfirmation"
	dialog.confirmed.connect(_on_confirmation_closed.bind(on_confirm))
	dialog.cancelled.connect(_on_confirmation_closed.bind(Callable()))
	_confirmation = dialog
	add_child(dialog)

func _on_confirmation_closed(on_confirm: Callable = Callable()) -> void:
	_confirmation = null
	if on_confirm.is_valid():
		on_confirm.call()

func _close_confirmation() -> void:
	if is_instance_valid(_confirmation):
		var dialog := _confirmation
		_confirmation = null
		dialog.queue_free()

func _on_back_pressed() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	# A dialogue that already answered this event (or any other node that
	# claimed it) leaves the screen alone.
	if get_viewport().is_input_handled():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not is_instance_valid(_confirmation):
			_on_back_pressed()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		if not is_instance_valid(_confirmation):
			_on_back_pressed()
			get_viewport().set_input_as_handled()
