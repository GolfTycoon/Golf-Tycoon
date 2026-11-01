extends PixelCircleButton
class_name BulldozerButton
## The round Bulldozer action button in the Build shelf's header row.
##
## Demolition belongs beside the things it removes, so the Improvements and
## Buildings tabs show this button in the shared header row (see
## TerrainToolbar._build_header_row) instead of the Bulldozer living among the
## Course Terrain paint tiles. Pressing it toggles bulldozer mode (same
## `bulldozer_pressed` signal, hotkey X still works); it only ever demolishes
## Improvements and Buildings — course terrain tiles repaint with other tiles
## and ignore the bulldozer.
##
## Wears the same PixelCircleButton medallion style as InspectButton, with a
## pixel-art bulldozer glyph and the Build section's gold accent ring.

## Fixed diameter: matches InspectButton in the header row.
const BUTTON_DIAMETER := 46.0
## Distance kept from the page's bottom-left corner (kept for compatibility).
const CORNER_MARGIN := 10.0

func _init() -> void:
	diameter = BUTTON_DIAMETER
	glyph = "bulldozer"
	accent = TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.BUILD]
	accessibility_name = "Bulldozer"
	focus_mode = Control.FOCUS_ALL

func _ready() -> void:
	super()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func set_active(is_on: bool) -> void:
	active = is_on

func is_active() -> bool:
	return active

func _on_mouse_entered() -> void:
	if not has_node("/root/TooltipManager"):
		return
	var tm = get_node("/root/TooltipManager")
	tm.show_tooltip({
		"title": "Bulldozer",
		"description": accessibility_description,
		"cost": 0,
		"maintenance": 0,
		"shortcut": "X",
	}, self)

func _on_mouse_exited() -> void:
	if not has_node("/root/TooltipManager"):
		return
	var tm = get_node("/root/TooltipManager")
	tm.hide_tooltip()
