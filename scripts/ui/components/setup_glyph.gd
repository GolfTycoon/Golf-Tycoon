extends Control
class_name SetupGlyph
## Icons for the Start New Game screen: difficulty bars, coin stacks, the
## three game features, the random-name die, the selection check, the on/off
## switch, the call-to-action arrow and the tutorial's open book.
##
## `make_pixel()` paints each symbol from an inspectable 16x16 character grid,
## to match the title screen's pixel-art frames, sprite and Pixelify Sans type.
## The original vector painter remains available through `make()` for callers
## that need its drawing contract. Both paths go through `_paint(canvas)`, so
## tests can hand in a recorder and the game can draw on the control itself.

enum Kind { DIFFICULTY, MONEY, WEATHER, WIND, SEASONS, DICE, CHECK, SWITCH, ARROW, TUTORIAL }

## MONEY level that draws the infinity sign (Unlimited) instead of coins.
const MONEY_UNLIMITED := 4

const CREAM := Color("e8e2cf")
const INK := Color("10241f")
const MUTED := Color("7e9184")
const SUN := Color("e5c57c")
const WIND_COLOR := Color("a9c9cf")
const LEAF := Color("d9893d")
const LEAF_VEIN := Color("8a4c1c")
const SWITCH_OFF := Color("1a2c25")

## 16x16 (or 16x8 for the switch) pixel grids. A dot is transparent; the
## remaining letters are indexed into _pixel_color(). They deliberately
## stay as character data so every source pixel is inspectable and the
## render path never interpolates a smooth vector icon.
const PIXEL_ART := {
	Kind.DIFFICULTY: [
		[
			"................",
			"................",
			"................",
			"..........XXXXXX",
			"..........XMMMMX",
			"..........XMMMMX",
			".....XXXXXXMMMMX",
			".....XMMMMXMMMMX",
			".....XMMMMXMMMMX",
			"XXXXXXMMMMXMMMMX",
			"XLLLDXMMMMXMMMMX",
			"XLAADXMMMMXMMMMX",
			"XLAADXMMMMXMMMMX",
			"XLDDDXMMMMXMMMMX",
			"XXXXXXXXXXXXXXXX",
			"................",
		],
		[
			"................",
			"................",
			"................",
			"..........XXXXXX",
			"..........XMMMMX",
			"..........XMMMMX",
			".....XXXXXXMMMMX",
			".....XLLLDXMMMMX",
			".....XLAADXMMMMX",
			"XXXXXXLAADXMMMMX",
			"XLLLDXLAADXMMMMX",
			"XLAADXLAADXMMMMX",
			"XLAADXLAADXMMMMX",
			"XLDDDXLDDDXMMMMX",
			"XXXXXXXXXXXXXXXX",
			"................",
		],
		[
			"................",
			"................",
			"................",
			"..........XXXXXX",
			"..........XLLLDX",
			"..........XLAADX",
			".....XXXXXXLAADX",
			".....XLLLDXLAADX",
			".....XLAADXLAADX",
			"XXXXXXLAADXLAADX",
			"XLLLDXLAADXLAADX",
			"XLAADXLAADXLAADX",
			"XLAADXLAADXLAADX",
			"XLDDDXLDDDXLDDDX",
			"XXXXXXXXXXXXXXXX",
			"................",
		],
	],
	Kind.MONEY: [
		[
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			".....XXXXXX.....",
			".....XXXXXX.....",
			".....XLLLDX.....",
			".....XLDDDX.....",
			".....XLDDDX.....",
			".....XLDDDX.....",
			"XXXXXXXXXXXXXXXX",
			"................",
		],
		[
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			".........XXXXXX.",
			".XXXXXX..XXXXXX.",
			".XXXXXX..XLLLDX.",
			".XLLLDX..XLDDDX.",
			".XLDDDX..XLDDDX.",
			".XLDDDX..XLDDDX.",
			"XXXXXXXXXXXXXXXX",
			"................",
		],
		[
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"..........XXXXXX",
			".....XXXXXXXXXXX",
			"XXXXXXXXXXXLLLDX",
			"XXXXXXLLLDXLDDDX",
			"XLLLDXLDDDXLDDDX",
			"XLDDDXLDDDXLDDDX",
			"XLDDDXLDDDXLDDDX",
			"XXXXXXXXXXXXXXXX",
			"................",
		],
		[
			"................",
			"................",
			"................",
			".XXXXXXXXXXXXXX.",
			"XXAAAAAXXAAAAAXX",
			"XAAAAAAAAAAAAAAX",
			"AAAXXXAAAAXXXAAA",
			"AAXX.XXAAXX.XXAA",
			"AAXX.XXAAXX.XXAA",
			"AAAXXXAAAAXXXAAA",
			"XAAAAAAAAAAAAAAX",
			"XXAAAAAXXAAAAAXX",
			".XXXXXXXXXXXXXX.",
			"................",
			"................",
			"................",
		],
	],
	Kind.WEATHER: [[
		".......XXXXSXXXX",
		".......XSXXXXXSX",
		".......XXSSSSXXX",
		"......XXXSSSSXXX",
		"......XSSSSSSSXS",
		"......XXXSSSSXXX",
		"......XXXSSSSX..",
		"...XXXXCXXXXXX..",
		"..XXCCCCCCXXX...",
		".XXCCCCCCCCCX...",
		".XCCCCCCCCCCXX..",
		".XXCCCCCCCCCCX..",
		"..XCCCCCCCCCCX..",
		"..XCCCCCCCCCCX..",
		"..XXXXXXXXXXXX..",
		"................",
	]],
	Kind.WIND: [[
		"......BB..B.....",
		"......B...B.....",
		"......B.........",
		".BBBBBBBB.......",
		".XXXXXXXX.BBB...",
		".........BB..B..",
		".........B...B..",
		".........B......",
		"...BBBBBBBBB....",
		"...XXXXXXXXX....",
		"................",
		"................",
		".BBBBBBB........",
		".XXXXXBB........",
		".....B..........",
		".....B...B......",
	]],
	Kind.SEASONS: [[
		"................",
		"................",
		"..........XXXX..",
		".......XXXXEEX..",
		".....XXXEEEVVX..",
		"....XXEEXXVVEX..",
		"...XXEEXXVVXEX..",
		"...XEEXXVVXEXX..",
		"...XEXXVVXXEX...",
		"..XXEXVVXXEEX...",
		"..XEEVVXXEEXX...",
		"..XEVVXEEEXX....",
		"..XVVEEEXXX.....",
		"..VXXXXXX.......",
		".V..............",
		"................",
	]],
	Kind.DICE: [[
		"................",
		".XXXXXXXXXXXXXX.",
		".XLLLLLLLLLLLMX.",
		".XLCCCCCCCCCCMX.",
		".XLCCCCCCCCCCMX.",
		".XLCCXXCCCXXCMX.",
		".XLCCXXCCCXXCMX.",
		".XLCCCCXXCCCCMX.",
		".XLCCCCXXXCCCMX.",
		".XLCCCCCXXCCCMX.",
		".XLCCXXCCCXXCMX.",
		".XLCCXXCCCXXCMX.",
		".XLCCCCCCCCCCMX.",
		".XMMMMMMMMMMMMX.",
		".XXXXXXXXXXXXXX.",
		"................",
	]],
	Kind.CHECK: [[
		"XXXXXXXXXXXXXXXX",
		"XLLLLLLLLLLLLLDX",
		"XLAAAAAAAAAAAADX",
		"XLAAAAAAAAAAAADX",
		"XLAAAAAAAAAAAADX",
		"XLAAAAAAAAAAXXDX",
		"XLAAAAAAAAAXXXDX",
		"XLAAAAAAAAXXXADX",
		"XLAAXXAAAXXXAADX",
		"XLAAXXXAXXXAAADX",
		"XLAAAXXXXXAAAADX",
		"XLAAAAXXXAAAAADX",
		"XLAAAAAAAAAAAADX",
		"XLAAAAAAAAAAAADX",
		"XDDDDDDDDDDDDDDX",
		"XXXXXXXXXXXXXXXX",
	]],
	Kind.SWITCH: [
		[
			".XXXXXXXXXXXXXX.",
			"XLLLLLLLLLLLLLLX",
			"XAAAAAAAAAWWWWAX",
			"XAAAAAAAAACCCCAX",
			"XAAAAAAAAACCCCAX",
			"XAAAAAAAAAMMMMAX",
			"XDDDDDDDDDDDDDDX",
			".XXXXXXXXXXXXXX.",
		],
		[
			".XXXXXXXXXXXXXX.",
			"XTTTTTTTTTTTTTTX",
			"XTWWWWTTTTTTTTTX",
			"XTCCCCTTTTTTTTTX",
			"XTCCCCTTTTTTTTTX",
			"XTMMMMTTTTTTTTTX",
			"XXXXXXXXXXXXXXXX",
			".XXXXXXXXXXXXXX.",
		],
	],
	Kind.ARROW: [[
		"................",
		".......XXX......",
		".......XAXX.....",
		".......XAAXX....",
		".......XAAAXX...",
		"XXXXXXXXAAAAXX..",
		"XALLLLLLAAAAAXX.",
		"XLAAAAAAAAAAAAXX",
		"XLAAAAAAAAAAAAAX",
		"XLAAAAAAAAAAAAXX",
		"XXDDDDDDAAAAAXX.",
		".XXXXXXXAAAAXX..",
		".......XAAAXX...",
		".......XAAXX....",
		".......XAXX.....",
		".......XXX......",
	]],
	Kind.TUTORIAL: [[
		"................",
		"................",
		"......XXXX..XXX.",
		".XXXXXXLLXXXXAX.",
		".XAAAAAXXAAAAXX.",
		".XAAAAAXXAAAAX..",
		".XALLLLXXLLLLX..",
		".XAAAAAXXAAAAX..",
		".XALLLLXXLLLLX..",
		".XAAAAAXXAAAAX..",
		".XALLLLXXLLLLX..",
		".XAAAAAXXAAAAX..",
		".XAAAAAXXAAAAX..",
		".XXXXXXXXXXXXX..",
		"......XXXX......",
		"................",
	]],
}

@export var kind: Kind = Kind.DIFFICULTY:
	set(value):
		kind = value
		queue_redraw()
## DIFFICULTY: lit bars (1-3). MONEY: coin stacks (1-3) or MONEY_UNLIMITED.
@export var level := 1:
	set(value):
		level = value
		queue_redraw()
@export var accent := Color("e5c57c"):
	set(value):
		accent = value
		queue_redraw()
## SWITCH: knob right and track lit when on. Feature glyphs: full colour when
## on, muted when off.
@export var on := true:
	set(value):
		on = value
		queue_redraw()
## In the setup sheet the glyph is rendered from a hard-edged pixel grid.
## Kept as an opt-in so callers/tests that use the older vector recorder still
## get the original glyph drawing contract.
var pixel_art := false:
	set(value):
		pixel_art = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## A glyph of `kind` at a fixed square `side` (SWITCH is twice as wide).
static func make(glyph_kind: int, side: float, glyph_level: int = 1,
		glyph_accent: Color = Color("e5c57c")) -> SetupGlyph:
	var glyph := SetupGlyph.new()
	glyph.kind = glyph_kind as Kind
	glyph.level = glyph_level
	glyph.accent = glyph_accent
	var width := side * 1.75 if glyph_kind == Kind.SWITCH else side
	glyph.custom_minimum_size = Vector2(width, side)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return glyph

## Build one of the same symbols as hard-edged sprite art for the Start New
## Game screen, where its frame, type and glyphs all share the main menu's
## pixel-art treatment.
static func make_pixel(glyph_kind: int, side: float, glyph_level: int = 1,
		glyph_accent: Color = Color("e5c57c")) -> SetupGlyph:
	var glyph := make(glyph_kind, side, glyph_level, glyph_accent)
	glyph.pixel_art = true
	return glyph

func _draw() -> void:
	_paint(self)

func _paint(canvas) -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	if pixel_art:
		_paint_pixel(canvas)
		return
	if kind == Kind.SWITCH:
		_paint_switch(canvas)
		return
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	match kind:
		Kind.DIFFICULTY:
			_paint_difficulty(canvas, origin, side)
		Kind.MONEY:
			_paint_money(canvas, origin, side)
		Kind.WEATHER:
			_paint_weather(canvas, origin, side)
		Kind.WIND:
			_paint_wind(canvas, origin, side)
		Kind.SEASONS:
			_paint_seasons(canvas, origin, side)
		Kind.DICE:
			_paint_dice(canvas, origin, side)
		Kind.CHECK:
			_paint_check(canvas, origin, side)
		Kind.ARROW:
			_paint_arrow(canvas, origin, side)
		Kind.TUTORIAL:
			_paint_tutorial(canvas, origin, side)

## Paint the character grid directly as non-antialiased rectangles. Rounding
## each cell edge (rather than scaling a smooth CanvasItem shape) preserves the
## hard edges when the responsive layout gives an icon a non-integer size.
func _paint_pixel(canvas) -> void:
	var rows := _pixel_rows()
	if rows.is_empty():
		return
	var board_h := minf(size.x, size.y)
	var board_w := board_h
	if kind == Kind.SWITCH:
		board_w = minf(size.x, board_h * 1.75)
	var board := Vector2(board_w, board_h)
	var origin := (size - board) * 0.5
	var cell := Vector2(board.x / 16.0, board.y / float(rows.size()))
	for y in rows.size():
		var row: String = rows[y]
		for x in mini(row.length(), 16):
			var color := _pixel_color(row.substr(x, 1))
			if color.a <= 0.0:
				continue
			var left := roundf(origin.x + float(x) * cell.x)
			var top := roundf(origin.y + float(y) * cell.y)
			var right := roundf(origin.x + float(x + 1) * cell.x)
			var bottom := roundf(origin.y + float(y + 1) * cell.y)
			if right > left and bottom > top:
				canvas.draw_rect(Rect2(Vector2(left, top), Vector2(right - left, bottom - top)), color)

func _pixel_rows() -> Array:
	var variants: Array = PIXEL_ART.get(kind, [])
	if variants.is_empty():
		return []
	match kind:
		Kind.DIFFICULTY:
			return variants[clampi(level - 1, 0, variants.size() - 1)]
		Kind.MONEY:
			return variants[clampi(level - 1, 0, variants.size() - 1)]
		Kind.SWITCH:
			return variants[0 if on else 1]
	return variants[0]

func _pixel_color(key: String) -> Color:
	match key:
		"X":
			return INK
		"A":
			return accent if on else MUTED
		"L":
			return accent.lightened(0.42) if on else MUTED.lightened(0.25)
		"D":
			return accent.darkened(0.45) if on else MUTED.darkened(0.30)
		"C":
			return CREAM if on else MUTED.lightened(0.25)
		"M":
			return MUTED
		"W":
			return Color(0.98, 0.98, 0.96, 1.0) if on else MUTED.lightened(0.32)
		"S":
			return SUN if on else MUTED
		"B":
			return WIND_COLOR if on else MUTED
		"E":
			return LEAF if on else MUTED
		"V":
			return LEAF_VEIN if on else MUTED.darkened(0.25)
		"T":
			return SWITCH_OFF
	return Color(0, 0, 0, 0)

## Three ascending bars, `level` of them lit: the familiar strength meter.
func _paint_difficulty(canvas, o: Vector2, s: float) -> void:
	var bar := s * 0.2
	var gap := s * 0.1
	var heights := [0.40, 0.63, 0.86]
	for i in 3:
		var h: float = s * float(heights[i])
		var rect := Rect2(o.x + s * 0.1 + float(i) * (bar + gap), o.y + s * 0.92 - h, bar, h)
		var color := accent if i < level else Color(MUTED.r, MUTED.g, MUTED.b, 0.30)
		canvas.draw_colored_polygon(_rounded_rect(rect, bar * 0.28), color)

## Coin stacks - one, two or three, each taller than the last - or the
## infinity sign for an unlimited budget.
func _paint_money(canvas, o: Vector2, s: float) -> void:
	if level >= MONEY_UNLIMITED:
		var points := PackedVector2Array()
		var center := o + Vector2(s * 0.5, s * 0.52)
		var a := s * 0.40
		for i in 49:
			var t := TAU * float(i) / 48.0
			var d := 1.0 + sin(t) * sin(t)
			points.append(center + Vector2(a * cos(t) / d, a * sin(t) * cos(t) / d * 1.25))
		canvas.draw_polyline(points, accent, maxf(1.5, s * 0.10), true)
		return
	var stacks := clampi(level, 1, 3)
	var coin := Vector2(s * (0.17 if stacks > 1 else 0.22), s * 0.075)
	var spacing := coin.x * 2.25
	var first_x := o.x + s * 0.5 - spacing * float(stacks - 1) * 0.5
	var base_y := o.y + s * 0.84
	var dark := accent.darkened(0.42)
	for stack in stacks:
		var cx := first_x + spacing * float(stack)
		var coins := 2 + stack
		for c in coins:
			var cy := base_y - float(c) * coin.y * 1.55
			_ellipse(canvas, Vector2(cx, cy + coin.y * 0.55), coin, dark)
			_ellipse(canvas, Vector2(cx, cy), coin, accent)

## A sun half behind a cloud.
func _paint_weather(canvas, o: Vector2, s: float) -> void:
	var sun := SUN if on else MUTED
	var cloud := CREAM if on else Color(MUTED.r, MUTED.g, MUTED.b, 0.75)
	var sun_center := o + Vector2(s * 0.63, s * 0.36)
	var r := s * 0.16
	for i in 8:
		var angle := TAU * float(i) / 8.0 - PI / 8.0
		var dir := Vector2(cos(angle), sin(angle))
		canvas.draw_line(sun_center + dir * r * 1.40, sun_center + dir * r * 1.85, sun, maxf(1.2, s * 0.05), true)
	canvas.draw_circle(sun_center, r, sun)
	var base := o + Vector2(0.0, s * 0.68)
	canvas.draw_circle(base + Vector2(s * 0.33, 0.0), s * 0.15, cloud)
	canvas.draw_circle(base + Vector2(s * 0.50, -s * 0.08), s * 0.19, cloud)
	canvas.draw_circle(base + Vector2(s * 0.68, s * 0.01), s * 0.14, cloud)
	canvas.draw_colored_polygon(_rounded_rect(Rect2(o.x + s * 0.18, base.y - s * 0.02, s * 0.66, s * 0.15), s * 0.07), cloud)

## Three streamlines that curl at their ends.
func _paint_wind(canvas, o: Vector2, s: float) -> void:
	var color := WIND_COLOR if on else MUTED
	var width := maxf(1.4, s * 0.075)
	_streamline(canvas, o, s, 0.30, 0.10, 0.60, 0.10, -1.0, color, width)
	_streamline(canvas, o, s, 0.50, 0.10, 0.80, 0.12, -1.0, color, width)
	_streamline(canvas, o, s, 0.70, 0.22, 0.56, 0.09, 1.0, color, width)

## A straight run from x0 to x1 at height y, finished with a curl of radius r
## that turns up (dir -1) or down (dir 1).
func _streamline(canvas, o: Vector2, s: float, y: float, x0: float, x1: float, r: float,
		dir: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	points.append(o + Vector2(s * x0, s * y))
	var center := o + Vector2(s * x1, s * (y + dir * r))
	for i in 15:
		var t := float(i) / 14.0
		# Start pointing along the line, sweep about 300 degrees round the centre.
		var angle := (PI * 0.5 if dir < 0.0 else -PI * 0.5) - dir * t * PI * 1.65
		points.append(center + Vector2(cos(angle), sin(angle)) * s * r * (1.0 - 0.25 * t))
	canvas.draw_polyline(points, color, width, true)

## A leaf with its midrib and stem: the turning year.
func _paint_seasons(canvas, o: Vector2, s: float) -> void:
	var fill := LEAF if on else MUTED
	var vein := LEAF_VEIN if on else Color(0.2, 0.25, 0.22)
	var base := o + Vector2(s * 0.24, s * 0.80)
	var tip := o + Vector2(s * 0.82, s * 0.18)
	var axis := tip - base
	var normal := Vector2(-axis.y, axis.x).normalized()
	var outline := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var t := float(i) / float(steps)
		outline.append(base + axis * t + normal * s * 0.24 * sin(PI * t) * (1.0 - 0.25 * t))
	for i in range(steps - 1, 0, -1):
		var t := float(i) / float(steps)
		outline.append(base + axis * t - normal * s * 0.24 * sin(PI * t) * (1.0 - 0.25 * t))
	canvas.draw_colored_polygon(outline, fill)
	canvas.draw_line(base - axis * 0.16, base + axis * 0.82, vein, maxf(1.0, s * 0.045), true)

## A die showing five, for "pick a random name".
func _paint_dice(canvas, o: Vector2, s: float) -> void:
	var face := Rect2(o + Vector2(s * 0.14, s * 0.14), Vector2(s * 0.72, s * 0.72))
	canvas.draw_colored_polygon(_rounded_rect(face, s * 0.14), CREAM)
	var pip := s * 0.068
	var c := face.get_center()
	var d := s * 0.19
	for offset in [Vector2(-d, -d), Vector2(d, -d), Vector2.ZERO, Vector2(-d, d), Vector2(d, d)]:
		canvas.draw_circle(c + offset, pip, INK)

## The badge on a selected card: an accent disc with a dark tick.
func _paint_check(canvas, o: Vector2, s: float) -> void:
	canvas.draw_circle(o + Vector2(s * 0.5, s * 0.5), s * 0.48, accent)
	canvas.draw_polyline(PackedVector2Array([
		o + Vector2(s * 0.27, s * 0.52),
		o + Vector2(s * 0.43, s * 0.67),
		o + Vector2(s * 0.73, s * 0.35),
	]), INK, maxf(1.5, s * 0.12), true)

## A right-pointing arrow (the font has no arrow glyph).
func _paint_arrow(canvas, o: Vector2, s: float) -> void:
	var width := maxf(1.6, s * 0.12)
	canvas.draw_line(o + Vector2(s * 0.16, s * 0.5), o + Vector2(s * 0.76, s * 0.5), accent, width, true)
	canvas.draw_polyline(PackedVector2Array([
		o + Vector2(s * 0.52, s * 0.26),
		o + Vector2(s * 0.80, s * 0.5),
		o + Vector2(s * 0.52, s * 0.74),
	]), accent, width, true)

## An open book: two pages either side of a spine, the lessons of the tutorial.
func _paint_tutorial(canvas, o: Vector2, s: float) -> void:
	var page := accent if on else MUTED
	var left := PackedVector2Array([
		o + Vector2(s * 0.06, s * 0.24),
		o + Vector2(s * 0.47, s * 0.32),
		o + Vector2(s * 0.47, s * 0.84),
		o + Vector2(s * 0.06, s * 0.74),
	])
	var right := PackedVector2Array([
		o + Vector2(s * 0.94, s * 0.24),
		o + Vector2(s * 0.53, s * 0.32),
		o + Vector2(s * 0.53, s * 0.84),
		o + Vector2(s * 0.94, s * 0.74),
	])
	canvas.draw_colored_polygon(left, page)
	canvas.draw_colored_polygon(right, page)
	canvas.draw_line(o + Vector2(s * 0.5, s * 0.30), o + Vector2(s * 0.5, s * 0.86), INK, maxf(1.2, s * 0.06), true)

## A pill switch: lit track and knob on the right when on.
func _paint_switch(canvas) -> void:
	var h := minf(size.y, size.x / 1.75)
	var w := h * 1.75
	var rect := Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)
	var track := accent if on else SWITCH_OFF
	canvas.draw_colored_polygon(_rounded_rect(rect, h * 0.5), track)
	if not on:
		canvas.draw_polyline(_closed(_rounded_rect(rect.grow(-0.5), h * 0.5 - 0.5)),
			Color(MUTED.r, MUTED.g, MUTED.b, 0.7), 1.0, true)
	var knob_x := rect.end.x - h * 0.5 if on else rect.position.x + h * 0.5
	canvas.draw_circle(Vector2(knob_x, rect.get_center().y), h * 0.36, CREAM if on else MUTED.lightened(0.15))

# =============================================================================
# SHAPE HELPERS
# =============================================================================

## Outline of a rounded rectangle as a polygon (CanvasItem has no rounded
## rect primitive outside a StyleBox).
static func _rounded_rect(rect: Rect2, radius: float, segments: int = 5) -> PackedVector2Array:
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var points := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
		[rect.end - Vector2(r, r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
		[rect.position + Vector2(r, r), PI],
	]
	for corner in corners:
		var center: Vector2 = corner[0]
		var start: float = corner[1]
		for i in segments + 1:
			var angle := start + PI * 0.5 * float(i) / float(segments)
			var point := center + Vector2(cos(angle), sin(angle)) * r
			# A pill (radius = half the height) has zero-length straight sides,
			# so neighbouring arcs share an end point; a repeated vertex makes
			# the polygon fail to triangulate.
			if points.is_empty() or not points[points.size() - 1].is_equal_approx(point):
				points.append(point)
	if points.size() > 1 and points[0].is_equal_approx(points[points.size() - 1]):
		points.remove_at(points.size() - 1)
	return points

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out

func _ellipse(canvas, center: Vector2, radii: Vector2, color: Color, segments: int = 24) -> void:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	canvas.draw_colored_polygon(points, color)
