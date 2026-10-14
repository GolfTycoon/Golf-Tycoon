extends Control
class_name MenuFlagMark
## The menu screens' mark: a gold pennant on its flagstick, standing in the
## cup on a green with a ball beside it.
##
## It is drawn, not typed, for the same reason as the Rotate buttons' arrows
## and the compass needle — the game's font carries no golf glyph, and a
## Unicode flag would render as a blank box on some builds. And it is drawn
## as a 16x16 pixel-art sprite, like the title screen's PixelIcon actions and
## the Start New Game setup glyphs: the screens share one hard-edged visual
## language, so a smooth vector mark would stick out beside them. Drawn
## rectangles scale to whatever `mark_size` the layout asks for.

const DEFAULT_SIZE := 64.0

## Side of the sprite grid, in source pixels.
const GRID := 16

const GREEN_COLOR := Color("2c6739")
const FRINGE_COLOR := Color("22502d")
const GREEN_RIM := Color("7fb08a")
const POLE_COLOR := Color("e8e2cf")
const FLAG_COLOR := Color("e5c57c")
const CUP_COLOR := Color("0d2119")
const BALL_COLOR := Color("f4edd9")
const BALL_SHADE := Color("c9c2ad")

## The sprite, one 16-character row per pixel row. Characters are palette
## keys: '.' air, 'X' ink (and the cup), 'A' the flag's gold, 'L' its lit top
## edge, 'C' the cream flagstick, 'W'/'S' the ball and its shade, 'G' the
## putting green, 'R' its lit top rim and 'g' the dark fringe.
const ART := [
	"................",
	".....CXXXXXX....",
	".....CXLLLLLX...",
	".....CXAAAAAX...",
	".....CXAAAAAXX..",
	".....CXAAAAAAX..",
	".....CXXXXXXXX..",
	".....C..........",
	".....C..........",
	"..RRRCRRR.WWW...",
	".GGGXXGGGWSGGg..",
	".gGGGGGGGGGGGG..",
	"..gGGGGGGGGGGg..",
	"...gGGGGGGGGg...",
	"................",
	"................",
]

## Side length of the mark in layout pixels. Setting it resizes the control.
@export var mark_size := DEFAULT_SIZE:
	set(value):
		mark_size = maxf(12.0, value)
		custom_minimum_size = Vector2(mark_size, mark_size)
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(DEFAULT_SIZE, DEFAULT_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Paint the character grid directly as non-antialiased rectangles. Rounding
## each cell edge (rather than scaling a smooth CanvasItem shape) preserves
## the hard edges when the responsive layout gives the mark a non-integer
## size — the same render path SetupGlyph uses for the setup screen's glyphs.
func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 1.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	var cell := side / float(GRID)
	for y in GRID:
		var row: String = ART[y]
		for x in GRID:
			var color := _cell_color(row[x])
			if color.a <= 0.0:
				continue
			var left := roundf(origin.x + float(x) * cell)
			var top := roundf(origin.y + float(y) * cell)
			var right := roundf(origin.x + float(x + 1) * cell)
			var bottom := roundf(origin.y + float(y + 1) * cell)
			if right > left and bottom > top:
				draw_rect(Rect2(Vector2(left, top), Vector2(right - left, bottom - top)), color)

static func _cell_color(key: String) -> Color:
	match key:
		"X":
			return CUP_COLOR
		"A":
			return FLAG_COLOR
		"L":
			return FLAG_COLOR.lightened(0.38)
		"C":
			return POLE_COLOR
		"W":
			return BALL_COLOR
		"S":
			return BALL_SHADE
		"G":
			return GREEN_COLOR
		"R":
			return GREEN_RIM
		"g":
			return FRINGE_COLOR
	return Color(0, 0, 0, 0)
