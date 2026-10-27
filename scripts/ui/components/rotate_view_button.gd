extends PixelCircleButton
class_name RotateViewButton
## The pair of arrows that turn the course a quarter turn each way. They stand
## side by side at the top-left corner, on the right of the location banner's
## details card, and the facing chip in that card's top-right corner folds them
## away (see OrientationToggleButton).
##
## Drawn sprites never depend on the font having the Unicode rotation glyphs,
## and the two sweep arrows are mirror images of one another.
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
