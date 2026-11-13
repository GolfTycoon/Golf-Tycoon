extends Control
class_name AddRepositoryDialog
## AddRepositoryDialog - the "Add a mod repository feed" form on the
## Browse Mods screen.
##
## A modal over a dimmed backdrop, dressed in the shared pixel chrome, with
## one field: the http(s) address of a feed's JSON document. Anybody can
## host a feed - any web server that can serve a JSON file and some mod
## zips will do - so the box takes a plain URL and nothing else; the
## address is checked as the player types and handed to the screen through
## `added` when it is accepted.
##
## Adding is not fetching: the screen refreshes the new feed straight away
## anyway, so a bad address surfaces as that feed's own error line rather
## than as a rejected form.

signal added(url: String)
signal cancelled

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_SURFACE_INSET := MenuStyle.INSET_BG
const COLOR_TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const COLOR_TEXT_SECONDARY := UIConstants.COLOR_TEXT_DIM
const COLOR_TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

## The store the form checks the typed address against. Null means the
## default construction; tests pass a throwaway store.
var _store: ModRepositoryStore = null

var _url_field: LineEdit = null
var _feedback: Label = null
var _add_button: Button = null


func _init(store: ModRepositoryStore = null) -> void:
	_store = store
	name = "AddRepositoryDialog"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	if has_node("/root/InputManager"):
		InputManager.register_scope(self)


func _resolved_store() -> ModRepositoryStore:
	return _store if is_instance_valid(_store) else null


# =============================================================================
# BUILDING
# =============================================================================

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Dim"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.62)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var view := Kit.window_size_of(self)
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(COLOR_GOLD, 0.55))
	panel.name = "AddRepositoryPanel"
	panel.custom_minimum_size.x = clampf(view.x - 32.0, 288.0, 560.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	var pad: int = 20 if view.x >= 680.0 else 14
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, pad)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.name = "AddRepositoryForm"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	var kicker := Kit.make_kicker("MOD REPOSITORY / feed address", 11)
	stack.add_child(kicker)

	var title := Kit.make_title_label("Add a Repository Feed", 26)
	stack.add_child(title)

	var blurb := Kit.make_label(
		"Any web host can serve a mod repository: the address is a JSON file that lists mods and their zips. The Official Repository is already in the list.",
		13, COLOR_TEXT_SECONDARY)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(blurb)

	var caption := Kit.make_kicker("FEED URL", 10)
	stack.add_child(caption)

	_url_field = LineEdit.new()
	_url_field.name = "UrlField"
	_url_field.placeholder_text = ModRepositoryStore.add_prompt()
	_url_field.custom_minimum_size.y = 44.0
	_url_field.add_theme_font_override("font", BODY_FONT)
	_url_field.add_theme_font_size_override("font_size", 14)
	_url_field.add_theme_color_override("font_color", COLOR_TEXT_BRIGHT)
	_url_field.add_theme_color_override("font_placeholder_color", COLOR_TEXT_QUIET)
	_url_field.add_theme_color_override("caret_color", COLOR_GOLD)
	_url_field.add_theme_color_override("selection_color", MenuStyle.with_alpha(COLOR_GOLD, 0.35))
	PixelButtonStyle.paint_field(_url_field, MenuStyle.with_alpha(COLOR_GOLD, 0.85),
		COLOR_SURFACE_INSET, 8)
	_url_field.text_changed.connect(func(_text: String) -> void: _update_state())
	_url_field.text_submitted.connect(func(_text: String) -> void: _on_submit())
	stack.add_child(_url_field)

	var hint := _label("A self-hosted feed stays yours: nothing is sent anywhere, and you can remove it from the list at any time.",
		11, COLOR_TEXT_QUIET)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)

	_feedback = _label("", 12, COLOR_TEXT_QUIET)
	_feedback.name = "Feedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.y = 32.0
	stack.add_child(_feedback)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 10)
	stack.add_child(buttons)

	var cancel_button := _button("Cancel", _on_cancel, false)
	cancel_button.name = "CancelButton"
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(cancel_button)

	_add_button = _button("Add Feed", _on_add, true)
	_add_button.name = "AddButton"
	_add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_add_button)

	# The address is what everything follows, so it opens focused for
	# keyboard and gamepad players.
	_url_field.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	_update_state()


# =============================================================================
# FORM STATE
# =============================================================================

func typed_url() -> String:
	return _url_field.text if is_instance_valid(_url_field) else ""


## The form's own live check: shape of the address only. Whether the feed
## answers, and whether it has already been added, are the store's and the
## network's answers, shown after the fact.
static func address_problem(url: String) -> String:
	var candidate := ModRepositoryStore.normalize_url(url)
	if candidate.is_empty():
		return "Type or paste the address of a mod repository feed (an http(s) URL to its JSON)."
	if not ModRepositoryFeed.is_fetchable_url(candidate):
		return "'%s' is not an http(s) URL. Feed addresses point at a JSON file on the web." % candidate
	return ""


## Re-check the form on every keystroke: the button only lights when the
## address could be a feed, and the line under it says why not.
func _update_state() -> void:
	if not is_instance_valid(_add_button) or not is_instance_valid(_feedback):
		return
	var problem := address_problem(typed_url())
	_add_button.disabled = not problem.is_empty()
	if not problem.is_empty():
		_feedback.text = problem
		_feedback.add_theme_color_override("font_color", UIConstants.COLOR_DANGER_MUTED)
		return
	_feedback.text = "Ready to add. The feed is fetched as soon as the list refreshes."
	_feedback.add_theme_color_override("font_color", COLOR_MINT)


func _on_submit() -> void:
	if is_instance_valid(_add_button) and not _add_button.disabled:
		_on_add()


func _on_add() -> void:
	var store := _resolved_store()
	if store == null:
		# No store to ask: refuse rather than guess. (The screen always
		# passes one; this guards the dialog opened bare in a test.)
		_feedback.text = "No repository list is connected to this form."
		_feedback.add_theme_color_override("font_color", UIConstants.COLOR_DANGER_MUTED)
		return
	var result: Dictionary = store.add_repository(typed_url())
	if bool(result.get("ok", false)):
		added.emit(str(result.get("url", "")))
		queue_free()
		return
	_feedback.text = "; ".join(result.get("errors", ["The feed could not be added."]))
	_feedback.add_theme_color_override("font_color", UIConstants.COLOR_DANGER_MUTED)


# =============================================================================
# LOOK AND FEEL
# =============================================================================

func _label(text: String, font_size: int = 13,
		color: Color = COLOR_TEXT_BRIGHT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44.0
	if accent:
		Kit.paint_action(button, true)
	else:
		Kit.paint_utility_button(button, false)
	button.pressed.connect(action)
	return button


# =============================================================================
# INPUT
# =============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()
