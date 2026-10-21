extends Control
class_name CreateModDialog
## CreateModDialog - the "Create New Mod" form on the Mods screen.
##
## A modal over a dimmed backdrop, dressed in the shared pixel chrome
## (MenuScreenKit's panel and typography, PixelButtonStyle's field and card
## frames). It asks for the four things a mod's manifest needs - id, name,
## author and description - plus whether to add a starter script, validates
## the form as the player types, and hands the work to ModScaffold through
## ModManager.create_mod().
##
## Creating never enables: the new folder is discovered switched off, and
## the Mods screen's usual tick + Apply & Reload puts it into play. The
## dialog closes itself after creating; `created` carries the new mod id so
## the screen can select and describe it.

signal created(mod_id: String)
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

## The manager the form talks to. Null means the ModManager autoload; tests
## pass a throwaway manager over a temp folder instead.
var _manager: Node = null

var _id_field: LineEdit = null
var _name_field: LineEdit = null
var _author_field: LineEdit = null
var _description_field: LineEdit = null
var _script_check: CheckBox = null
var _feedback: Label = null
var _create_button: Button = null


func _init(manager: Node = null) -> void:
	_manager = manager
	name = "CreateModDialog"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	if has_node("/root/InputManager"):
		InputManager.register_scope(self)


func _resolved_manager() -> Node:
	return _manager if is_instance_valid(_manager) else ModManager


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
	panel.name = "CreateModPanel"
	panel.custom_minimum_size.x = clampf(view.x - 32.0, 288.0, 560.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	var pad: int = 20 if view.x >= 680.0 else 14
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, pad)
	panel.add_child(margin)

	# The form scrolls when a short window (phone landscape) cannot show it
	# whole, so the Create button is always reachable.
	var scroll := ScrollContainer.new()
	scroll.name = "CreateModScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size.y = clampf(view.y * 0.74, 200.0, 552.0)
	margin.add_child(scroll)

	var stack := VBoxContainer.new()
	stack.name = "CreateModForm"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	scroll.add_child(stack)

	var kicker := Kit.make_kicker("NEW MOD / scaffold", 11)
	stack.add_child(kicker)

	var title := Kit.make_title_label("Create New Mod", 26)
	stack.add_child(title)

	var blurb := Kit.make_label(
		"Builds a folder in your mods library. It stays switched off until you tick it and Apply & Reload.",
		13, COLOR_TEXT_SECONDARY)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(blurb)

	_id_field = _add_field(stack, "MOD ID", "yourname.my_mod",
		"Its folder name and the namespace for everything it adds. It must never change once players have saves.")
	_name_field = _add_field(stack, "NAME", "My Mod",
		"The title players see in this list.")
	_author_field = _add_field(stack, "AUTHOR", "Your name (optional)")
	_description_field = _add_field(stack, "DESCRIPTION", "What does it change? (optional)")

	_script_check = CheckBox.new()
	_script_check.name = "StarterScriptCheck"
	_script_check.text = "Add a starter script (mod_main.gd)"
	_script_check.button_pressed = true
	_script_check.tooltip_text = "Adds mod_main.gd and declares the \"script\" permission. Script mods run code; leave it unticked for a data-only mod."
	_script_check.add_theme_font_override("font", SUBTITLE_FONT)
	_script_check.add_theme_font_size_override("font_size", 13)
	_script_check.add_theme_color_override("font_color", COLOR_TEXT_BRIGHT)
	_script_check.add_theme_color_override("font_hover_color", COLOR_GOLD)
	_script_check.toggled.connect(func(_on: bool) -> void: _update_state())
	stack.add_child(_script_check)

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

	_create_button = _button("Create Mod", _on_create, true)
	_create_button.name = "CreateButton"
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_create_button)

	# The id is the field every other decision follows from, so it opens
	# focused for keyboard and gamepad players.
	_id_field.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	_update_state()


func _add_field(stack: VBoxContainer, caption: String, placeholder: String,
		hint: String = "") -> LineEdit:
	var label := Kit.make_kicker(caption, 10)
	stack.add_child(label)

	var field := LineEdit.new()
	field.name = caption.to_pascal_case().replace(" ", "") + "Field"
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 44.0
	field.add_theme_font_override("font", BODY_FONT)
	field.add_theme_font_size_override("font_size", 14)
	field.add_theme_color_override("font_color", COLOR_TEXT_BRIGHT)
	field.add_theme_color_override("font_placeholder_color", COLOR_TEXT_QUIET)
	field.add_theme_color_override("caret_color", COLOR_GOLD)
	field.add_theme_color_override("selection_color", MenuStyle.with_alpha(COLOR_GOLD, 0.35))
	PixelButtonStyle.paint_field(field, MenuStyle.with_alpha(COLOR_GOLD, 0.85),
		COLOR_SURFACE_INSET, 8)
	field.text_changed.connect(func(_text: String) -> void: _update_state())
	field.text_submitted.connect(func(_text: String) -> void: _on_submit())
	stack.add_child(field)

	if not hint.is_empty():
		var hint_label := _label(hint, 11, COLOR_TEXT_QUIET)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(hint_label)
	return field


# =============================================================================
# FORM STATE
# =============================================================================

func _fields() -> Dictionary:
	return {
		"id": _text_of(_id_field),
		"name": _text_of(_name_field),
		"author": _text_of(_author_field),
		"description": _text_of(_description_field),
		"script": is_instance_valid(_script_check) and _script_check.button_pressed,
	}


func _text_of(field: LineEdit) -> String:
	return field.text if is_instance_valid(field) else ""


func _errors() -> Array[String]:
	return ModScaffold.validate(_fields(), _resolved_manager().get_installed_mod_ids())


## Re-check the form on every keystroke: the button only lights when the
## manifest would be valid, and the line under the form says why not.
func _update_state() -> void:
	if not is_instance_valid(_create_button) or not is_instance_valid(_feedback):
		return
	var fields := _fields()
	var errors: Array[String] = _errors()
	_create_button.disabled = not errors.is_empty()
	if not errors.is_empty():
		_feedback.text = errors[0]
		_feedback.add_theme_color_override("font_color", UIConstants.COLOR_DANGER_MUTED)
		return
	var mod_id: String = str(fields.get("id", "")).strip_edges()
	var made: String = "mod.json, mod_main.gd and README.md" \
		if ModScaffold.has_script(fields) else "mod.json and README.md"
	_feedback.text = "Ready: mods/%s/ - %s." % [mod_id, made]
	_feedback.add_theme_color_override("font_color", COLOR_MINT)


func _on_submit() -> void:
	if is_instance_valid(_create_button) and not _create_button.disabled:
		_on_create()


func _on_create() -> void:
	var result: Dictionary = _resolved_manager().create_mod(_fields())
	if bool(result.get("ok", false)):
		created.emit(str(result.get("mod_id", "")))
		queue_free()
		return
	# Keep the manager's message: a folder that already exists on disk is not
	# something the live form check knows about, so don't overwrite it with
	# the "ready" line.
	var errors: Array = result.get("errors", ["The mod could not be created."])
	_feedback.text = "; ".join(errors)
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
