extends CenteredPanel
class_name HotkeyPanel
## HotkeyPanel - Shows all keyboard shortcuts grouped by category

## Keycap labels for rebindable actions, keyed by InputBindings action id.
var _binding_labels: Dictionary = {}

## Escape, controller B or a right-click closes the help sheet. It is opened by
## F1 from any screen, so it has no owner to hand a close_requested to.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		hide()


func _build_ui() -> void:
	_binding_labels.clear()
	custom_minimum_size = Vector2(520, 540)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "Controls & Shortcuts"
	title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Every screen works with a mouse, keyboard, controller or touch. Rebind the course controls in Settings → Controls; F1 toggles this panel."
	subtitle.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	subtitle.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(subtitle)

	main_vbox.add_child(HSeparator.new())

	# Scrollable content
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Every rebindable action, grouped exactly as Settings groups them. The
	# labels are kept so a rebind refreshes them without rebuilding the panel.
	if not InputBindings.bindings_changed.is_connected(_on_binding_changed):
		InputBindings.bindings_changed.connect(_on_binding_changed)
	if not InputBindings.bindings_reset.is_connected(_on_bindings_reset):
		InputBindings.bindings_reset.connect(_on_bindings_reset)
	for group in InputBindings.groups():
		_add_binding_section(vbox, str(group.get("id", "")), str(group.get("title", "")))

	# Controls that are part of the input language rather than a course action:
	# menus, the pointer, touch and the Course Map's own keys.
	_add_section(vbox, "Fixed - Menus & Navigation", [
		["Arrows / D-pad", "Move focus (arrows enter the HUD on the course)"],
		["Shift+Arrows", "Move the course pointer when the HUD is unfocused"],
		["Enter / A", "Select the focused control"],
		["Esc / B", "Back, cancel or close"],
		["Tab / LB, RB", "Next or previous control"],
		["Right stick", "Move the pointer on a screen"],
		["Left stick", "Focus navigation, or pan the course"],
	])

	_add_section(vbox, "Fixed - Mouse & Touch", [
		["Left click", "Select, paint or place"],
		["Right click", "Cancel, or raise terrain"],
		["Middle drag", "Pan the camera"],
		["Wheel / pinch", "Zoom in and out"],
		["Tap", "Select or place"],
		["One-finger drag", "Pan, paint or scroll"],
		["Two-finger drag", "Pan and pinch to zoom"],
		["Two-finger tap", "Cancel or close"],
	])

	_add_section(vbox, "Fixed - Course Map", [
		["1 to 4", "Land, Routing, Aura and Staff modes"],
		["F", "Frame the whole course"],
		["+ / -", "Zoom the map"],
		["Esc", "Back out one step"],
	])

	_add_section(vbox, "Fixed - On the Course", [
		["Tab", "Toggle the minimap"],
		["Ctrl + click drag", "Measure a distance"],
		["Right / left click", "Raise / lower terrain with an elevation tool"],
	])

	var note = Label.new()
	note.text = "Keycaps show the binding you have now. Change them in Settings → Controls; the game's menu keys stay fixed."
	note.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	note.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)

	# Close button
	main_vbox.add_child(HSeparator.new())
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 35)
	close_btn.pressed.connect(func(): hide())
	main_vbox.add_child(close_btn)

## The current keycap text for one action, in the panel.
func _binding_label(action: String) -> String:
	return InputBindings.binding_text(action)

func _add_binding_section(parent: VBoxContainer, group_id: String, group_title: String) -> void:
	var actions := InputBindings.actions_in_group(group_id)
	if actions.is_empty():
		return
	var rows: Array = []
	for action in actions:
		rows.append([_binding_label(action), InputBindings.action_label(action), action])
	_add_section(parent, group_title, rows, true)

func _on_binding_changed(action: String) -> void:
	var label := _binding_labels.get(action) as Label
	if is_instance_valid(label):
		label.text = _binding_label(action)

func _on_bindings_reset() -> void:
	for action in _binding_labels:
		var label := _binding_labels[action] as Label
		if is_instance_valid(label):
			label.text = _binding_label(str(action))

func _add_section(parent: VBoxContainer, section_name: String, shortcuts: Array,
		bindable: bool = false) -> void:
	var header = Label.new()
	header.text = section_name
	header.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	header.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	parent.add_child(header)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)

	for shortcut in shortcuts:
		var key_label = Label.new()
		key_label.text = shortcut[0]
		key_label.custom_minimum_size = Vector2(150 if bindable else 125, 0)
		key_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM if bindable else UIConstants.FONT_SIZE_BASE)
		key_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
		key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(key_label)
		if bindable and shortcut.size() > 2:
			_binding_labels[str(shortcut[2])] = key_label

		var desc_label = Label.new()
		desc_label.text = shortcut[1]
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
		desc_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(desc_label)

	# Small spacer after section
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	parent.add_child(spacer)
