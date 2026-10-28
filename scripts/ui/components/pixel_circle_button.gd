extends Button
class_name PixelCircleButton
## Crisp, two-pixel medallions shared by dock navigation and utility controls.
## Native Button input, focus, tooltips and accessibility stay intact. Icons are
## bitmaps rather than font glyphs, so they also work with the pixel font.

const FONT = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const INK := Color("081812")
const CREAM := Color("f4ecd0")
const ICONS := {
	"menu": [".........", ".xxxxxxx.", ".xxxxxxx.", ".........", ".xxxxxxx.", ".xxxxxxx.", ".........", ".xxxxxxx.", ".xxxxxxx."],
	"feed": [".xxxxxxx.", ".x.....x.", ".x.xxx.x.", ".x.....x.", ".x.xxx.x.", ".x.....x.", ".xxxxxxx.", "...xx....", "..xx....."],
	"inspect": ["..xxxx...", ".x....x..", "x......x.", "x......x.", "x......x.", ".x....x..", "..xxxx...", "......xx.", ".......xx"],
	"build": ["...xxxx..", "..xxxxxx.", ".xx.xx.xx", "....xx...", "....xx...", "....xx...", "....xx...", "....xx...", "....xx..."],
	"manage": ["..xxxxx..", "..x...x..", "xxxxxxxxx", "x.......x", "xxxx.xxxx", "...xxx...", "x.......x", "x.......x", "xxxxxxxxx"],
	"golfers": ["...xxx...", "..xxxxx..", "...xxx...", ".........", "..xxxxx..", ".xxxxxxx.", ".x.xxx.x.", "...x.x...", "...x.x..."],
	"terrain": ["....x....", "...xxx...", "..xxxxx..", ".xxxxxxx.", "xxxxxxxxx", "...xxx...", "....x....", "....x....", "..xxxxx.."],
	"improvements": ["...xxx...", "..xxxxx..", "...xxx...", ".x..x..x.", "..xxxxx..", "....x....", "..xxxxx..", "..xxxxx..", "...xxx..."],
	"buildings": ["....x....", "...xxx...", "..xxxxx..", ".xxxxxxx.", "xxxxxxxxx", ".x.....x.", ".x.xx..x.", ".x.xx..x.", ".xxxxxxx."],
	"elevation": ["....x....", "...x.x...", "..x...x..", ".x.....x.", "xxxxxxxxx", ".........", "..xxxxx..", ".........", "xxxxxxxxx"],
	"holes": ["..xxxxxx.", "..xxxxxx.", "..xxxxx..", "..x......", "..x......", "..x......", "..x......", ".xxxxx...", "xxxxxxxx."],
	"flag": ["....x....", "....xx...", "....xxx..", "....xxxx.", "....x....", "....x....", "....x....", "....x....", "..xxxxx.."],
	"maps": ["xxx...xxx", "x..xxx..x", "x..x.x..x", "x..x.x..x", "x..x.x..x", "x..x.x..x", "x..x.x..x", "x..xxx..x", "xxx...xxx"],
	"club": [".........", "...xxx...", "..x...x..", "xxxxxxxxx", "x.......x", "x.......x", "x.......x", "xxxxxxxxx", "........."],
	"review": ["..xxxxx..", ".xx...xx.", ".x.x.x.x.", ".x..x..x.", ".x.x.x.x.", ".xx...xx.", "..xxxxx..", "..xx.xx..", "..x...x.."],
	"milestone": ["..xxxxx..", "xxx...xxx", "x.x...x.x", "xxx...xxx", "..xxxxx..", "...xxx...", "....x....", "...xxx...", "..xxxxx.."],
	"world": ["..xxxxx..", ".x.....x.", "x..xxx..x", "x.x...x.x", "x..xxx..x", "x.x...x.x", "x..xxx..x", ".x.....x.", "..xxxxx.."],
	"achievement": ["..xxxxx..", ".xxxxxxx.", "xx.xxx.xx", "xx.xxx.xx", ".xxxxxxx.", "..xxxxx..", "...xxx...", "...xxx...", "..xxxxx.."],
	"marketing": ["......xx.", "....xxxx.", "xxxxxxxx.", "xxxxxxxx.", "xxxxxxxx.", "....xxxx.", "..xx..xx.", "..xx.....", "...xx...."],
	"staff": ["...xxx...", "..xxxxx..", "...xxx...", ".........", "..xxxxx..", ".xxx.xxx.", ".xxx.xxx.", ".xxxxxxx.", "..xxxxx.."],
	"edit": ["......xx.", ".....xxxx", "....xxxx.", "...xxxx..", "..xxxx...", ".xxxx....", ".xxx.....", ".xx......", "xxxxxxxxx"],
	"skills": ["....x....", "....x....", "...xxx...", "xxxxxxxxx", ".xxxxxxx.", "..xxxxx..", "..xxxxx..", ".xxx.xxx.", ".x.....x."],
	"pause": [".........", "..xx.xx..", "..xx.xx..", "..xx.xx..", "..xx.xx..", "..xx.xx..", "..xx.xx..", "..xx.xx..", "........."],
	"play": [".........", "..xx.....", "..xxx....", "..xxxx...", "..xxxxx..", "..xxxx...", "..xxx....", "..xx.....", "........."],
	"fast": [".........", "xx..xx...", "xxx.xxx..", "xxxxxxxx.", "xxxxxxxxx", "xxxxxxxx.", "xxx.xxx..", "xx..xx...", "........."],
	"ultra": [".........", "x..x..x..", "xx.xx.xx.", "xxxxxxxx.", "xxxxxxxxx", "xxxxxxxx.", "xx.xx.xx.", "x..x..x..", "........."],
	"rotate_ccw": ["...xxxx..", "..xx..xx.", ".xx....xx", "xxxx...xx", "xxx....xx", ".......xx", "..x...xx.", "..xxxxx..", "...xxx..."],
	"rotate_cw": ["..xxxx...", ".xx..xx..", "xx....xx.", "xx...xxxx", "xx....xxx", "xx.......", ".xx...x..", "..xxxxx..", "...xxx..."],
	"finance": ["....x....", "..xxxxx..", ".xx.x....", "..xxx....", "....xxx..", "....x.xx.", "..xxxxx..", "....x....", "........."],
}

## The icon can change while the button is on screen (the speed toggle wears
## one, two or three triangles as the tier changes), so a new glyph repaints.
## The guard covers glyphs set before the button enters the tree (scene files,
## BottomControlDock.setup) — those are drawn on entry anyway.
@export var glyph := "":
	set(value):
		if glyph != value:
			glyph = value
			if is_inside_tree():
				queue_redraw()
@export var caption := ""
@export var diameter := 32.0
@export var accent := Color("a2ba85")
var notification_count := 0:
	set(value):
		if notification_count != value:
			notification_count = value
			queue_redraw()
var active := false:
	set(value):
		if active != value:
			active = value
			queue_redraw()
static var _faces: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2.ONE * diameter
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up, toggled]:
		# toggled carries a bool; queue_redraw takes no arguments.
		if event == toggled:
			event.connect(func(_pressed: bool): queue_redraw())
		else:
			event.connect(queue_redraw)

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5

func _draw() -> void:
	var selected := active or button_pressed
	var lit := is_hovered() or has_focus()
	var d := int(minf(size.x, size.y))
	if d < 8:
		return
	var origin := ((size - Vector2.ONE * d) * 0.5).floor()
	var key := "%d:%s:%s:%s:%s:%s" % [d, accent, selected, lit, disabled, has_focus()]
	if not _faces.has(key):
		_faces[key] = _make_face(d, selected, lit)
	draw_texture_rect(_faces[key], Rect2(origin, Vector2.ONE * d), false)
	if ICONS.has(glyph):
		var pixels: Array = ICONS[glyph]
		var pixel := 3 if d >= 74 else 2
		var offset := origin + Vector2(floorf((d - 9 * pixel) * 0.5), floorf((d - 9 * pixel) * 0.5))
		if not caption.is_empty():
			offset.y -= 6
		if is_pressed():
			offset.y += 2
		for y in pixels.size():
			for x in pixels[y].length():
				if pixels[y][x] == "x":
					var rect := Rect2(offset + Vector2(x, y) * pixel, Vector2.ONE * pixel)
					draw_rect(Rect2(rect.position + Vector2(0, 2), rect.size), INK)
					draw_rect(rect, CREAM if not disabled else Color("748273"))
	if notification_count > 0:
		draw_rect(Rect2(origin + Vector2(d - 9, 2), Vector2(6, 6)), Color("e5bd66"))
	if not caption.is_empty():
		var font_size := 12 if d < 74 else 14
		var width := FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(FONT, origin + Vector2(floorf((d - width) * 0.5), d - 15), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CREAM)

func _make_face(d: int, selected: bool, lit: bool) -> ImageTexture:
	var side := maxi(4, int(d / 2.0))
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center := Vector2.ONE * (side - 1) * 0.5
	var radius := side * 0.5
	var trim := accent if selected or lit else accent.darkened(0.38)
	var fill := Color("284c3c") if selected else Color("192e26")
	if lit:
		fill = fill.lightened(0.12)
	if disabled:
		trim = Color("59665d")
	for y in side:
		for x in side:
			var distance := Vector2(x, y).distance_to(center)
			if distance > radius - 0.5:
				continue
			var color := fill
			if distance > radius - 1.5:
				color = INK
			elif distance > radius - 2.5:
				color = CREAM if has_focus() else trim
			elif distance > radius - 3.5:
				color = trim.lightened(0.3) if x + y < side else trim.darkened(0.5)
			elif y < side * 0.32:
				color = fill.lightened(0.06)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
