extends Node
class_name GuiThemeApplier
## GuiThemeApplier - Dresses the live control tree in a GuiTheme.
##
## The built Theme (GuiTheme.build_theme) covers every control that takes
## its look from the Theme. What it cannot reach is the code-built layer:
## HUD cards, panels and popups whose StyleBoxFlat and font colours were
## assembled in GDScript from the stock palette (UIConstants, MenuStyle,
## hardcoded values copied from the stock theme). This applier walks the
## tree once at startup and re-maps those overrides role by role - a stock
## panel fill becomes the theme's panel, a stock border becomes the
## theme's border - and re-shapes mapped panel/button boxes to the
## theme's corner radii, so a design changes the interface's shapes, not
## only its hues.
##
## Panels, menus and toasts are created throughout the session, so the
## applier also listens for nodes entering the tree and dresses each new
## Control the same way. Overrides whose colours are not part of the
## stock palette (a score's gold, a warning's own red, art-tinted cards)
## are left exactly as their builders made them, and StyleBoxTexture
## frames are never touched here: PixelButtonStyle re-paints those at
## build time through GuiTheme.remap_color, before this walk runs.
##
## Created by Main only while a GUI theme mod is in force; with none, none
## of this exists and the game wears its stock look untouched.

## Stylebox slots any built-in control can carry. Each is only touched
## when the control actually overrides it (has_theme_stylebox_override),
## so enumerating generously can never invent a box a control never had.
const STYLEBOX_SLOTS: Array[StringName] = [
	&"panel", &"normal", &"hover", &"pressed", &"disabled", &"focus",
	&"hover_pressed", &"read_only", &"background", &"fill", &"scroll",
	&"grabber", &"grabber_highlight", &"grabber_pressed", &"separator",
	&"selected", &"selected_focus",
	&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_disabled", &"tab_focus",
]

## Colour slots likewise: only slots a control already overrides are
## re-mapped, everything else inherits from the built Theme.
const COLOR_SLOTS: Array[StringName] = [
	&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
	&"font_disabled_color", &"font_hover_pressed_color", &"font_placeholder_color",
	&"font_selected_color", &"font_unselected_color", &"font_hovered_color",
	&"caret_color", &"default_color", &"font_shadow_color",
]

## The stock medallion accent (PixelCircleButton's default face colour).
## Medallions painted in any other colour chose it on purpose and keep it.
const STOCK_MEDALLION_ACCENT := Color("a2ba85")

## The game's own typefaces, as the font overrides across the UI name
## them: body text in Regular, headings and buttons in the heavier
## weights. A theme font replaces the first family, its font_bold the
## second (see GuiTheme.font / font_bold).
const STOCK_FONT_BODY := "res://assets/fonts/PixelifySans-Regular.ttf"
const STOCK_FONT_DISPLAY: Array[String] = [
	"res://assets/fonts/PixelifySans-SemiBold.ttf",
	"res://assets/fonts/PixelifySans-Bold.ttf",
	"res://assets/fonts/PixelifySans-ExtraBold.ttf",
	"res://assets/fonts/PixelifySans-Black.ttf",
]

## Button stylebox slots a rule's background family maps onto, state by
## state (hover_pressed wears the hover colour, as the stock theme does).
const RULE_BUTTON_SLOTS: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"disabled", &"hover_pressed",
]

var _theme: GuiTheme = null
var _root: Node = null
var _built_theme: Theme = null
var _pending: Dictionary = {}  # Control -> true, awaiting its styling pass
var _flush_queued: bool = false


## Dress `root` (the main scene) and keep dressing what it grows. `hud` -
## the Control the scene file gave the stock game_theme.tres - is handed
## the built Theme in the stock one's place.
func setup(root: Node, theme: GuiTheme, hud: Control = null) -> void:
	_root = root
	_theme = theme
	_built_theme = theme.build_theme()
	if hud != null:
		hud.theme = _built_theme
	_style_recursive(root, false)
	if get_tree() != null and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


## Style one control in place. Public so tests - and a future screen that
## builds itself off-tree - can dress a control without the watcher.
func style_control(control: Control) -> void:
	if _theme == null or not is_instance_valid(control):
		return
	_style_styleboxes(control)
	_style_colors(control)
	if control.has_theme_font_size_override(&"font_size") \
			and control.get_theme_font_size(&"font_size") == GuiTheme.default_metrics()["font_size"] \
			and _theme.metric("font_size") != GuiTheme.default_metrics()["font_size"]:
		control.add_theme_font_size_override(&"font_size", _theme.metric("font_size"))
	if control is ColorRect:
		var rect := control as ColorRect
		if not _theme.role_for(rect.color).is_empty():
			rect.color = _theme.map_color(rect.color)
	if control is PixelCircleButton:
		var medallion := control as PixelCircleButton
		if GuiTheme._same_color(medallion.accent, STOCK_MEDALLION_ACCENT):
			medallion.accent = _theme.color("primary")
	_style_font(control)
	_style_rule(control)


## Hand the control the theme's typeface when the one it wears is the
## game's own: body faces become the theme font, display faces its bold
## companion (or the theme font when the palette names only one). A face
## a screen chose from anywhere else is its own and stays.
func _style_font(control: Control) -> void:
	if _theme.font == null and _theme.font_bold == null:
		return
	if not control.has_theme_font_override(&"font"):
		return
	var current := control.get_theme_font(&"font")
	if current == null:
		return
	var replacement: Font = null
	if current.resource_path == STOCK_FONT_BODY:
		replacement = _theme.font
	elif STOCK_FONT_DISPLAY.has(current.resource_path):
		replacement = _theme.font_bold if _theme.font_bold != null else _theme.font
	if replacement != null and replacement != current:
		control.add_theme_font_override(&"font", replacement)


## Apply whatever the theme's targeted rules ask of this one control -
## its own corner of the interface, dressed as no global role could.
## Rules run after the global passes, so what they say wins.
func _style_rule(control: Control) -> void:
	var style := _theme.style_for(String(control.name),
		_type_names(control), _ancestor_names(control))
	if style.is_empty():
		return
	if control is PixelCircleButton and style.has("background"):
		(control as PixelCircleButton).accent = style["background"]
	if control is PixelCircleButton and style.has("glyph"):
		(control as PixelCircleButton).glyph = str(style["glyph"])
	if control is ColorRect and style.has("background"):
		var rect_color: Color = style["background"]
		if style.has("opacity"):
			rect_color.a *= float(style["opacity"])
		(control as ColorRect).color = rect_color
	_apply_rule_boxes(control, style)
	if style.has("text"):
		for slot in [&"font_color", &"font_hover_color", &"font_pressed_color",
				&"font_focus_color", &"font_hover_pressed_color"]:
			control.add_theme_color_override(slot, style["text"])
	if style.has("font_size"):
		control.add_theme_font_size_override(&"font_size", int(style["font_size"]))
	if style.has("font"):
		control.add_theme_font_override(&"font", style["font"])
	if control is Button and style.has("icon"):
		(control as Button).icon = style["icon"]


## The stylebox half of a rule: backgrounds (with their derived states),
## corner radius, border, shadow and solidity, translated onto the flats
## the control wears. Painted StyleBoxTexture frames are never touched -
## their art is generated, not flat - so a rule's colours land on flat
## boxes and its text, font, size and icon land everywhere.
func _apply_rule_boxes(control: Control, style: Dictionary) -> void:
	var slots: Dictionary = {}
	if control is BaseButton and not control is PixelCircleButton:
		if style.has("background"):
			var states := GuiTheme.derived_button_states(style["background"])
			slots[&"normal"] = style["background"]
			slots[&"hover"] = style.get("background_hover", states["button_hover"])
			slots[&"hover_pressed"] = slots[&"hover"]
			slots[&"pressed"] = style.get("background_pressed", states["button_pressed"])
			slots[&"disabled"] = style.get("background_disabled", states["button_disabled"])
		else:
			if style.has("background_hover"):
				slots[&"hover"] = style["background_hover"]
				slots[&"hover_pressed"] = style["background_hover"]
			if style.has("background_pressed"):
				slots[&"pressed"] = style["background_pressed"]
			if style.has("background_disabled"):
				slots[&"disabled"] = style["background_disabled"]
	if (control is Panel or control is PanelContainer or control is TabContainer) \
			and style.has("background"):
		slots[&"panel"] = style["background"]
	var shape_slots: Array = slots.keys()
	if not style.has("background"):
		# Shapes or solidity alone still land on the standard boxes.
		if control is BaseButton and not control is PixelCircleButton:
			shape_slots = RULE_BUTTON_SLOTS.duplicate()
		elif control is Panel or control is PanelContainer or control is TabContainer:
			shape_slots = [&"panel"]
	for slot in shape_slots:
		var box := _rule_box(control, slot)
		if box == null:
			continue
		if slots.has(slot):
			var bg: Color = slots[slot]
			if style.has("opacity"):
				bg.a *= float(style["opacity"])
			box.bg_color = bg
		elif style.has("opacity"):
			box.bg_color.a *= float(style["opacity"])
		if style.has("radius"):
			box.set_corner_radius_all(int(style["radius"]))
		if style.has("border_width"):
			box.set_border_width_all(int(style["border_width"]))
		if style.has("border"):
			box.border_color = style["border"]
			if box.get_border_width_min() == 0 and not style.has("border_width"):
				box.set_border_width_all(1)
		if style.has("shadow_size"):
			box.shadow_size = int(style["shadow_size"])
		control.add_theme_stylebox_override(slot, box)


## The flat a rule may repaint for one slot: the control's own box (its
## override, or its Theme's, duplicated so the shared resource is never
## written through), or null when the slot wears painted art.
func _rule_box(control: Control, slot: StringName) -> StyleBoxFlat:
	var existing := control.get_theme_stylebox(slot)
	if existing == null:
		return StyleBoxFlat.new()
	if existing is StyleBoxFlat:
		return (existing as StyleBoxFlat).duplicate() as StyleBoxFlat
	return null


## Class names a rule's `type` matches: the engine class, plus the script
## class when the control carries one (Button, PixelCircleButton, ...).
func _type_names(control: Control) -> Array:
	var names: Array = [control.get_class()]
	var script := control.get_script() as Script
	if script != null and not script.get_global_name().is_empty():
		names.append(script.get_global_name())
	return names


## The control's own name and every ancestor's, nearest first - the chain
## a rule's `screen` selector matches against (MainMenu, ModsScreen, HUD).
func _ancestor_names(control: Control) -> Array:
	var names: Array = []
	var node: Node = control
	while node != null:
		names.append(String(node.name))
		node = node.get_parent()
	return names


func _style_styleboxes(control: Control) -> void:
	for slot in STYLEBOX_SLOTS:
		if not control.has_theme_stylebox_override(slot):
			continue
		var box: StyleBox = control.get_theme_stylebox(slot)
		if box is StyleBoxFlat:
			control.add_theme_stylebox_override(slot, _remapped_flat(box as StyleBoxFlat))
		elif box is StyleBoxLine:
			var line := (box as StyleBoxLine).duplicate() as StyleBoxLine
			if not _theme.role_for(line.color).is_empty():
				line.color = _theme.map_color(line.color)
			control.add_theme_stylebox_override(slot, line)


func _remapped_flat(source: StyleBoxFlat) -> StyleBoxFlat:
	var style := source.duplicate() as StyleBoxFlat
	var bg_role := _theme.role_for(style.bg_color)
	if not bg_role.is_empty():
		style.bg_color = _theme.map_color(style.bg_color)
		match bg_role:
			"panel":
				style.bg_color = GuiTheme._with_opacity(style.bg_color,
					_theme.metricf("panel_opacity"))
			"button", "button_hover", "button_pressed", "button_disabled", \
			"primary", "primary_hover":
				style.bg_color = GuiTheme._with_opacity(style.bg_color,
					_theme.metricf("button_opacity"))
		match bg_role:
			"panel", "tooltip", "inset":
				style.set_corner_radius_all(_theme.metric("panel_radius"))
			"button", "button_hover", "button_pressed", "button_disabled", \
			"primary", "primary_hover":
				style.set_corner_radius_all(_theme.metric("button_radius"))
		if style.get_border_width_min() > 0:
			style.set_border_width_all(_theme.metric("border_width"))
		if style.shadow_size > 0:
			style.shadow_size = _theme.metric("shadow_size")
	if not _theme.role_for(style.border_color).is_empty():
		style.border_color = _theme.map_color(style.border_color)
	if style.shadow_size > 0 and _is_stock_shadow(style.shadow_color):
		var shadow := _theme.color("deep")
		shadow.a = style.shadow_color.a
		style.shadow_color = shadow
	return style


## The stock shadows all share one near-black green RGB, tinted per box by
## alpha alone - recognisable even though their alphas differ.
func _is_stock_shadow(candidate: Color) -> bool:
	return absf(candidate.r - 0.008) < 0.02 and absf(candidate.g - 0.043) < 0.02 \
		and absf(candidate.b - 0.031) < 0.02


func _style_colors(control: Control) -> void:
	for slot in COLOR_SLOTS:
		if not control.has_theme_color_override(slot):
			continue
		var current: Color = control.get_theme_color(slot)
		if not _theme.role_for(current).is_empty():
			control.add_theme_color_override(slot, _theme.map_color(current))


func _style_recursive(node: Node, ancestor_themed: bool) -> void:
	var themed := ancestor_themed
	if node is Control:
		var control := node as Control
		# A top-level Control with no themed ancestor (a CanvasLayer's
		# children: the FPS counter, the notice layer) gets the built Theme
		# of its own, since nothing above it can hand one down.
		if not themed and control.theme == null and not (control.get_parent() is Control):
			control.theme = _built_theme
		if control.theme != null:
			themed = true
		style_control(control)
	for child in node.get_children():
		_style_recursive(child, themed)


func _on_node_added(node: Node) -> void:
	if _theme == null or _root == null or not is_instance_valid(_root):
		return
	if node is Control and (node == _root or _root.is_ancestor_of(node)):
		_pending[node] = true
		if not _flush_queued:
			_flush_queued = true
			call_deferred("_flush_pending")


func _flush_pending() -> void:
	_flush_queued = false
	var controls: Array = _pending.keys()
	_pending.clear()
	for entry in controls:
		var control := entry as Control
		if control == null or not is_instance_valid(control) or not control.is_inside_tree():
			continue
		if not _has_themed_ancestor(control) and control.theme == null \
				and not (control.get_parent() is Control):
			control.theme = _built_theme
		style_control(control)


func _has_themed_ancestor(control: Control) -> bool:
	var parent := control.get_parent()
	while parent != null:
		if parent is Control and (parent as Control).theme != null:
			return true
		parent = parent.get_parent()
	return false
