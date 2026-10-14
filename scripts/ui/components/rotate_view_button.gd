extends PixelCircleButton
class_name RotateViewButton
## Pixel arrows flank the heading letter. Drawn sprites never depend on the
## font having the Unicode rotation glyphs. The two sprites are mirrored.
const BUTTON_SIZE := Vector2(32, 32)

@export var clockwise := false:
	set(value):
		clockwise = value
		glyph = "rotate_cw" if clockwise else "rotate_ccw"
		queue_redraw()

func _init() -> void:
	custom_minimum_size = BUTTON_SIZE
	text = ""

func _ready() -> void:
	text = ""
	glyph = "rotate_cw" if clockwise else "rotate_ccw"
	if accessibility_name.is_empty():
		accessibility_name = tooltip_text
	super()
