extends Control
class_name CreditsScreen
## CreditsScreen - the credits and about dialog.
##
## A small modal over a dimmed backdrop, dressed in the same shared chrome as
## every other menu: the notched pixel panel (MenuScreenKit.make_panel), the
## bold title face, gold kicker captions and the utility Close card.

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

signal close_requested

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _build_ui() -> void:
	# Semi-transparent overlay
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Panel
	var panel := Kit.make_panel(Kit.COLOR_SURFACE, Kit.COLOR_BORDER_SOFT)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Kit.make_title_label("Golf Tycoon", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Version
	var version := Kit.make_label("v0.4.9", 13, Kit.COLOR_TEXT_SECONDARY)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(version)
	vbox.add_child(HSeparator.new())

	# Credits entries
	_add_credit_section(vbox, "Engine", ["Godot 4.6 (MIT License)"])
	_add_credit_section(vbox, "License", ["GPL-3.0 - Open Source"])
	vbox.add_child(HSeparator.new())

	# Description
	var desc := Kit.make_label("Design courses, manage operations, and host tournaments.", 13, Kit.COLOR_TEXT_SECONDARY)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	# Close button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.add_theme_font_size_override("font_size", 15)
	Kit.paint_utility_button(close_btn, false)
	close_btn.pressed.connect(_on_close)

	var btn_center := CenterContainer.new()
	btn_center.add_child(close_btn)
	vbox.add_child(btn_center)

func _add_credit_section(parent: VBoxContainer, header_text: String, names: Array) -> void:
	var header := Kit.make_kicker(header_text, 12)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	for entry in names:
		var name_label := Kit.make_label(str(entry), 15, Kit.COLOR_TEXT_BRIGHT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parent.add_child(name_label)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		_on_close()
		get_viewport().set_input_as_handled()

func _on_close() -> void:
	close_requested.emit()
