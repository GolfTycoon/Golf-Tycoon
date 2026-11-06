extends PixelCircleButton
class_name MapCircleButton
## Circular map shortcut for the shelf: the Holes Map and Staff Map actions
## as medallions rather than rectangular tickets. No label is drawn inside
## the circle — the glyph alone names it, and the rich tooltip carries the
## description — so the button reads like every other circular tool in the
## game (Inspect, Bulldozer, the section medallions).
##
## Keeps the same public contract as DockActionButton/ToolButton (tool_type,
## tool_name, tool_description, hotkey, cost, maintenance and tool_pressed)
## so existing wiring and tests continue to find the button by its tool_type.

signal tool_pressed(tool_type)

@export var tool_type: Variant
@export var tool_name: String = ""
@export var tool_description: String = ""
@export var hotkey: String = ""
@export var cost: int = 0
@export var maintenance: int = 0

const BUTTON_DIAMETER := 64.0

func _init() -> void:
	diameter = BUTTON_DIAMETER
	# Manage green — same as the tab rail's MANAGE section — as a literal
	# so the class has no hard load-order dependency on TerrainToolbar.
	accent = Color("8dba9b")
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _ready() -> void:
	super()
	custom_minimum_size = Vector2.ONE * diameter
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Native Button pressed is bridged to the ToolButton-style tool_pressed
	# that TerrainToolbar expects.
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	if not tool_name.is_empty():
		accessibility_name = tool_name
		tooltip_text = tool_name
	if not tool_description.is_empty():
		accessibility_description = tool_description

func _on_pressed() -> void:
	tool_pressed.emit(tool_type)

func _on_mouse_entered() -> void:
	if not has_node("/root/TooltipManager"):
		return
	var tm = get_node("/root/TooltipManager")
	tm.show_tooltip({
		"title": tool_name,
		"description": tool_description,
		"cost": cost,
		"maintenance": maintenance,
		"shortcut": hotkey
	}, self)

func _on_mouse_exited() -> void:
	if not has_node("/root/TooltipManager"):
		return
	var tm = get_node("/root/TooltipManager")
	tm.hide_tooltip()

func configure(p_tool_type: Variant, p_name: String, p_glyph: String, p_description: String = "", p_hotkey: String = "") -> void:
	tool_type = p_tool_type
	tool_name = p_name
	glyph = p_glyph
	tool_description = p_description
	hotkey = p_hotkey
	accessibility_name = p_name
	accessibility_description = p_description
	tooltip_text = p_name
	queue_redraw()
