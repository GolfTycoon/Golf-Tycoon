extends Button
class_name WaitingHoleOpenButton
## Inline "Open Hole" call to action carried on the waiting tee-to-cup route.
##
## Once the player has painted a waiting tee box and cut a waiting cup,
## PlacementPreview keeps the dashed hole route anchored between them regardless
## of which build tool is selected. Seating this button directly on that line
## puts the commit action where the player is already looking, without requiring
## a trip back to the Course Terrain tab or memorizing the H shortcut.
##
## The control lives in the gameplay HUD (behind the dock, shelf, status cards
## and overlay screens) so it renders at a crisp, constant size at every camera
## zoom level, intercepts clicks and taps cleanly before course painting runs,
## and wears the same gold glass-pill treatment as the game's other primary
## calls to action.

const LABEL := "Open Hole"
const ACTION_NAME := "tool_open_hole"
const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")

const FONT_SIZE := 13
const PAD_X := 14
const PAD_Y := 5
const DESKTOP_MIN_HEIGHT := 34.0
const TOUCH_MIN_HEIGHT := float(UIConstants.TOUCH_TARGET_SIZE)

const READY_DESCRIPTION := "Pair the waiting tee box and cup to open Hole %d (Par %d, %d yds)."
const FALLBACK_READY_DESCRIPTION := "Pair the waiting tee box with the waiting green with a hole."
const FALLBACK_BLOCKED_DESCRIPTION := "This tee box and cup cannot be opened as a hole yet."

var _hole_number: int = 0
var _par: int = 0
var _distance_yards: int = 0
var _reason: String = ""
var _hovered: bool = false
var _touch_sized: bool = false

func _init() -> void:
	text = LABEL
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Course-space pointer target: keyboard and D-pad focus stays inside the
	# dock and panels, and GamepadCursor stays active across press + release.
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = LABEL

func _ready() -> void:
	apply_visual_style()
	update_layout_metrics(true)
	_sync_accessibility()
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if has_node("/root/InputBindings"):
		if not InputBindings.bindings_changed.is_connected(_on_bindings_changed):
			InputBindings.bindings_changed.connect(_on_bindings_changed)
		if not InputBindings.bindings_reset.is_connected(_sync_accessibility):
			InputBindings.bindings_reset.connect(_sync_accessibility)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_dismiss_tooltip(true)

func _exit_tree() -> void:
	_dismiss_tooltip(true)
	if has_node("/root/InputBindings"):
		if InputBindings.bindings_changed.is_connected(_on_bindings_changed):
			InputBindings.bindings_changed.disconnect(_on_bindings_changed)
		if InputBindings.bindings_reset.is_connected(_sync_accessibility):
			InputBindings.bindings_reset.disconnect(_sync_accessibility)

func _on_bindings_changed(action: String) -> void:
	if action == ACTION_NAME:
		_sync_accessibility()

## Dress the pill in the shared primary gold glass frame, with an opaque dark
## disabled card so an unready (too-short) pair stays legible over bright turf.
func apply_visual_style() -> void:
	PixelButtonStyle.paint_primary(self, MenuStyle.ACCENT_PRIMARY)
	add_theme_font_override("font", TITLE_FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_stylebox_override("disabled", PixelButtonStyle.card_style(
		MenuStyle.ACCENT_PRIMARY, PixelButtonStyle.State.DISABLED, MenuStyle.CARD_BG,
		PAD_X, PAD_Y, PAD_Y))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		if not has_theme_stylebox_override(state):
			continue
		var style := get_theme_stylebox(state)
		if style == null:
			continue
		var copy := style.duplicate()
		copy.content_margin_left = float(PAD_X)
		copy.content_margin_right = float(PAD_X)
		copy.content_margin_top = float(PAD_Y)
		copy.content_margin_bottom = float(PAD_Y)
		add_theme_stylebox_override(state, copy)
	add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)

## Keep a comfortable 44 px thumb target on touch and compact windows and a
## trim pill on desktop layouts. Returns true when the button's size changed.
func update_layout_metrics(force: bool = false) -> bool:
	var use_touch := has_node("/root/Screen") and Screen.uses_touch_layout()
	var target_height := TOUCH_MIN_HEIGHT if use_touch else DESKTOP_MIN_HEIGHT
	var changed := force or use_touch != _touch_sized \
			or not is_equal_approx(custom_minimum_size.y, target_height)
	_touch_sized = use_touch
	custom_minimum_size = Vector2(0.0, target_height)
	var min_size := get_combined_minimum_size()
	if not size.is_equal_approx(min_size):
		size = min_size
		changed = true
	return changed

## Sync enabled state, cursor and description from HoleLayout.waiting_hole().
func set_waiting_hole(hole: Dictionary) -> void:
	var hole_ready := bool(hole.get("ready", false))
	var next_number := int(hole.get("hole_number", 0))
	var next_par := int(hole.get("par", 0))
	var next_yards := int(hole.get("distance_yards", 0))
	var next_reason := str(hole.get("reason", ""))
	if disabled == (not hole_ready) and _hole_number == next_number \
			and _par == next_par and _distance_yards == next_yards \
			and _reason == next_reason:
		return
	disabled = not hole_ready
	_hole_number = next_number
	_par = next_par
	_distance_yards = next_yards
	_reason = next_reason
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled \
			else Control.CURSOR_POINTING_HAND
	_sync_accessibility()
	if _hovered:
		_show_tooltip()
	queue_redraw()

## Human-readable explanation shown in the hover tooltip and screen reader text.
func description_text() -> String:
	if disabled:
		return _reason if not _reason.is_empty() else FALLBACK_BLOCKED_DESCRIPTION
	if _hole_number > 0 and _par > 0 and _distance_yards > 0:
		return READY_DESCRIPTION % [_hole_number, _par, _distance_yards]
	return FALLBACK_READY_DESCRIPTION

## Current shortcut label (follows custom bindings in Settings -> Controls).
func shortcut_text() -> String:
	if has_node("/root/InputBindings"):
		return InputBindings.binding_text(ACTION_NAME)
	return "H"

func _sync_accessibility() -> void:
	var key := shortcut_text()
	var desc := description_text()
	if key.is_empty():
		accessibility_description = desc
	else:
		accessibility_description = "%s Shortcut %s." % [desc, key]

func _on_mouse_entered() -> void:
	_hovered = true
	_show_tooltip()

func _on_mouse_exited() -> void:
	_dismiss_tooltip()

func _show_tooltip() -> void:
	if not has_node("/root/TooltipManager"):
		return
	TooltipManager.show_tooltip({
		"title": LABEL,
		"description": description_text(),
		"shortcut": shortcut_text(),
	}, self)

func _dismiss_tooltip(immediate: bool = false) -> void:
	if not _hovered:
		return
	_hovered = false
	if not has_node("/root/TooltipManager"):
		return
	if immediate:
		TooltipManager.hide_tooltip_immediate()
	else:
		TooltipManager.hide_tooltip()
