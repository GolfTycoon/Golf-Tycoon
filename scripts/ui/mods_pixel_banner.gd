extends Control
## Resolution-independent pixel course vignette: deliberately hard-edged geometry.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("284d45"))
	# A tiled fairway, a tiny clubhouse, and a flag on the putting green.
	for x in range(0, int(size.x), 32):
		draw_rect(Rect2(x, 40, 32, 24), Color("38664b") if x % 64 == 0 else Color("325b43"))
	for x in range(12, int(size.x), 96):
		draw_rect(Rect2(x, 18, 12, 18), Color("193c35"))
		draw_rect(Rect2(x - 4, 22, 20, 8), Color("477b55"))
	draw_rect(Rect2(38, 26, 48, 28), Color("d3c894"))
	draw_rect(Rect2(30, 18, 64, 8), Color("b66e52"))
	draw_rect(Rect2(38, 10, 48, 8), Color("d98a5b"))
	draw_rect(Rect2(58, 36, 12, 18), Color("28413b"))
	var flag_x := floorf(size.x * 0.76 / 4.0) * 4.0
	draw_rect(Rect2(flag_x - 24, 44, 76, 12), Color("84b76b"))
	draw_rect(Rect2(flag_x, 10, 4, 38), Color("f3e9c5"))
	draw_rect(Rect2(flag_x + 4, 10, 24, 12), Color("edb65d"))
	draw_rect(Rect2(0, 60, size.x, 4), Color("a9e4b0"))
