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
	"bulldozer": [".........", "....xxxx.", ".x..x..x.", ".x..xxxxx", ".xx.xxxxx", ".x..xxxxx", ".x.xxxxxx", "...xxxxxx", "........."],
	"brush_round": ["..xxxxx..", ".xx...xx.", "xx.....xx", "x.......x", "x.......x", "x.......x", "xx.....xx", ".xx...xx.", "..xxxxx.."],
	"brush_square": [".xxxxxxx.", ".xxxxxxx.", ".xx...xx.", ".xx...xx.", ".xx...xx.", ".xx...xx.", ".xx...xx.", ".xxxxxxx.", ".xxxxxxx."],
	"minus": [".........", ".........", ".........", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".........", ".........", "........."],
	"plus": [".........", "...xxx...", "...xxx...", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", "...xxx...", "...xxx...", "........."],
}
## Every icon casts an ink shadow this far below itself.
const ICON_SHADOW := 2.0
## Stacked wide faces (see stacked_caption) start the caption's capitals this
## far under the icon's shadow. A pressed or selected icon sits two pixels
## lower, so it still keeps two pixels of air above the caption.
const STACK_GAP := 4.0
## What a stacked caption keeps clear on each side of the face: the two-pixel
## border and two more pixels of air.
const STACK_SIDE_PAD := 4.0
## Pixelify Sans capitals stand seven tenths of the font size above the
## baseline. A stacked face centres its icon and the capitals as one block and
## lets descenders hang below it, the way the icon's shadow hangs below the icon.
const CAP_HEIGHT_RATIO := 0.7

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
## Portrait navigation can stretch into a full-width touch tab.
var wide_face := false:
	set(value):
		wide_face = value
		queue_redraw()
## A wide face sets its caption beside its icon, which suits the thumb rail's
## three roomy section tabs. A row that seats four tabs across a narrow phone
## has no room for that ("Elevation" beside its icon is wider than the tab), so
## those tabs stack the caption under the icon instead. Only a wide face with
## both an icon and a caption stacks (see is_stacked).
var stacked_caption := false:
	set(value):
		if stacked_caption != value:
			stacked_caption = value
			queue_redraw()
@export var caption := ""
@export var diameter := 32.0:
	set(value):
		diameter = value
		custom_minimum_size = Vector2.ONE * diameter
		if is_inside_tree():
			queue_redraw()
@export var accent := Color("a2ba85"):
	set(value):
		if accent != value:
			accent = value
			if is_inside_tree():
				queue_redraw()
## Toggle buttons that switch a mode on/off (Inspect, Pause, section/tab
## medallions) light their face while pressed; toggle buttons that cycle
## between two states (the round/square brush shape picker) swap their glyph
## instead of staying lit in only one of the two shapes.
@export var pressed_lights_face := true
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
	if wide_face:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5

## The side of one icon pixel on a face whose shorter side is `d`.
static func _icon_pixel(d: int) -> int:
	return 3 if d >= 74 else 2

## The caption's font size on a face whose shorter side is `d`.
static func _caption_font_size(d: int) -> int:
	return 12 if d < 74 else 14

## True while this face draws its caption under its icon.
func is_stacked() -> bool:
	return wide_face and stacked_caption and not caption.is_empty() and ICONS.has(glyph)

## Where a stacked face seats its icon, before the two-pixel nudge of a press:
## centred across the face, at the top of the block it forms with the caption.
func stacked_icon_rect() -> Rect2:
	var d := int(minf(size.x, size.y))
	var side := 9.0 * _icon_pixel(d)
	var block := side + ICON_SHADOW + STACK_GAP + ceilf(_caption_font_size(d) * CAP_HEIGHT_RATIO)
	return Rect2(floorf((size.x - side) * 0.5), floorf((size.y - block) * 0.5), side, side)

## Where a stacked face seats its caption: a box as wide as the text and as
## tall as its capitals, centred across the face, whose bottom edge is the
## baseline. A caption wider than the room between the side pads is held to
## that room, where it is trimmed rather than drawn over the border.
func stacked_caption_rect() -> Rect2:
	var font_size := _caption_font_size(int(minf(size.x, size.y)))
	var room := maxf(size.x - 2.0 * STACK_SIDE_PAD, 0.0)
	var width := minf(FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, room)
	return Rect2(STACK_SIDE_PAD + floorf((room - width) * 0.5),
			stacked_icon_rect().end.y + ICON_SHADOW + STACK_GAP,
			width, ceilf(font_size * CAP_HEIGHT_RATIO))

func _draw() -> void:
	var selected := active or (button_pressed and pressed_lights_face)
	var lit := is_hovered() or has_focus()
	var d := int(minf(size.x, size.y))
	if d < 8:
		return
	var origin := ((size - Vector2.ONE * d) * 0.5).floor()
	var key := "%d:%s:%s:%s:%s:%s" % [d, accent, selected, lit, disabled, has_focus()]
	if wide_face:
		var face := StyleBoxFlat.new()
		face.bg_color = Color("284c3c") if selected else Color("192e26")
		if lit:
			face.bg_color = face.bg_color.lightened(0.12)
		face.border_color = accent if selected or lit else accent.darkened(0.38)
		face.set_border_width_all(2)
		face.set_corner_radius_all(6)
		face.anti_aliasing = false
		draw_style_box(face, Rect2(Vector2.ZERO, size))
	else:
		if not _faces.has(key):
			_faces[key] = _make_face(d, selected, lit)
		draw_texture_rect(_faces[key], Rect2(origin, Vector2.ONE * d), false)
	var stacked := is_stacked()
	if ICONS.has(glyph):
		var pixels: Array = ICONS[glyph]
		var pixel := _icon_pixel(d)
		var offset := origin + Vector2(floorf((d - 9 * pixel) * 0.5), floorf((d - 9 * pixel) * 0.5))
		if stacked:
			offset = stacked_icon_rect().position
		elif wide_face and not caption.is_empty():
			var text_width := FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			offset = Vector2(floorf((size.x - (9 * pixel + 4.0 + text_width)) * 0.5), floorf((size.y - 9 * pixel) * 0.5))
		elif not caption.is_empty():
			offset.y -= 6
		if is_pressed():
			offset.y += 2
		for y in pixels.size():
			for x in pixels[y].length():
				if pixels[y][x] == "x":
					var rect := Rect2(offset + Vector2(x, y) * pixel, Vector2.ONE * pixel)
					draw_rect(Rect2(rect.position + Vector2(0, ICON_SHADOW), rect.size), INK)
					draw_rect(rect, CREAM if not disabled else Color("748273"))
	if notification_count > 0:
		var badge_position := Vector2(size.x - 9, 4) if wide_face else origin + Vector2(d - 9, 2)
		draw_rect(Rect2(badge_position, Vector2(6, 6)), Color("e5bd66"))
	if stacked:
		# The caption keeps its place while a press nudges the icon, so a row of
		# tabs reads along one baseline whichever of them is selected.
		var caption_rect := stacked_caption_rect()
		draw_string(FONT, Vector2(caption_rect.position.x, caption_rect.end.y), caption,
				HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 2.0 * STACK_SIDE_PAD, 1.0),
				_caption_font_size(d), CREAM)
	elif not caption.is_empty():
		var font_size := _caption_font_size(d)
		var width := FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var text_position := origin + Vector2(floorf((d - width) * 0.5), d - 15)
		if wide_face and ICONS.has(glyph):
			var icon_size := 18.0 if d < 74 else 27.0
			text_position = Vector2(floorf((size.x - (icon_size + 4.0 + width)) * 0.5) + icon_size + 4.0, floorf((size.y - FONT.get_height(font_size)) * 0.5) + FONT.get_ascent(font_size))
		draw_string(FONT, text_position, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CREAM)

func _make_face(d: int, selected: bool, lit: bool) -> ImageTexture:
	return _build_face(d, accent, selected, lit, disabled, has_focus())

static func face_stylebox(d: int, btn_accent: Color) -> StyleBoxTexture:
	var key := "%d:%s:%s:%s:%s:%s" % [d, btn_accent, false, false, false, false]
	if not _faces.has(key):
		_faces[key] = _build_face(d, btn_accent, false, false, false, false)
	var box := StyleBoxTexture.new()
	box.texture = _faces[key]
	return box

static func _build_face(d: int, btn_accent: Color, selected: bool, lit: bool,
		muted: bool, focused: bool) -> ImageTexture:
	var side := maxi(4, int(d / 2.0))
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center := Vector2.ONE * (side - 1) * 0.5
	var radius := side * 0.5
	var trim := btn_accent if selected or lit else btn_accent.darkened(0.38)
	var fill := Color("284c3c") if selected else Color("192e26")
	if lit:
		fill = fill.lightened(0.12)
	if muted:
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
				color = CREAM if focused else trim
			elif distance > radius - 3.5:
				color = trim.lightened(0.3) if x + y < side else trim.darkened(0.5)
			elif y < side * 0.32:
				color = fill.lightened(0.06)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
