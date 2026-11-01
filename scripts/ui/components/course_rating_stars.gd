extends Control
class_name CourseRatingStars
## Five faceted pixel-art stars for the HUD status column's course rating pill.
##
## Each star is painted from an odd-width character grid (21x21 on desktop,
## 15x15 on compact windows) so its top spire lands on a single pixel and its
## central vertical ridge splits a half-star cleanly down the middle. Ten
## pinwheel bevel planes radiate from the star's centre — ivory crown highlight
## and champagne gold on the upper-left planes, rich gold across the core,
## warm amber and burnished bronze on the shaded lower-right planes — framed by
## a dark ink outline and a one-pixel drop shadow.
##
## Unlit stars (and the unearned side of a fractional star) sit in a recessed
## emerald-slate socket with a sunken top-left bevel and a muted sage catchlight
## along the bottom-right rim, so an unrated or low-rated course still reads as
## a five-star plaque at a glance.

const STAR_COUNT := 5

const DESKTOP_SIDE := 21
const COMPACT_SIDE := 15
const DESKTOP_GAP := 3
## Compact textures overlap by their two transparent edge columns. Their ink
## stays separate while the strip fits the phone pill's 20px side padding.
const COMPACT_GAP := -2
const DESKTOP_PAD_X := 3
## The HUD pill supplies the outer padding on compact windows.
const COMPACT_PAD_X := 0
const DESKTOP_HEIGHT := 28
const COMPACT_HEIGHT := 24

const DROP_SHADOW := Color(0.0, 0.0, 0.0, 0.42)
const GLOW_COLOR := Color("f5cc60")

## Cast-gold facets, lit from the upper left.
const LIT_PALETTE := {
	"X": Color8(8, 20, 15, 255),
	"H": Color8(255, 252, 230, 255),
	"L": Color8(253, 230, 142, 255),
	"G": Color8(242, 199, 92, 255),
	"A": Color8(219, 161, 58, 255),
	"D": Color8(176, 116, 35, 255),
	"R": Color8(140, 86, 23, 255),
}

## Engraved dark-emerald socket, shaded at the top-left and catching rim light
## along the lower-right bevel.
const UNLIT_PALETTE := {
	"X": Color8(8, 19, 15, 240),
	"H": Color8(22, 43, 36, 255),
	"L": Color8(26, 50, 42, 255),
	"G": Color8(33, 61, 51, 255),
	"A": Color8(40, 71, 59, 255),
	"D": Color8(52, 87, 72, 255),
	"R": Color8(66, 104, 86, 255),
}

## Desktop 21x21 five-pointed faceted star (row 20 reserved for the drop shadow).
const DESKTOP_ART: Array[String] = [
	"..........X..........",
	".........XHX.........",
	".........XHX.........",
	"........XLHGX........",
	"........XHHGX........",
	"........XHHGX........",
	"......XXHHLGGXX......",
	"..XXXXHHHHLGGGGXXXX..",
	".XALHHHHHHLGGGGGGGRX.",
	"..XAAAHHHHLLGGGRRRX..",
	"...XAAAAALHLRRRRRX...",
	"....XAAAAGHDRRRRX....",
	".....XGGGDDADDDX.....",
	".....XGGGDDADDDX.....",
	".....XGGDDDAADDX.....",
	"....XGGDDDXAAADDX....",
	"....XGDDDX.XAAADX....",
	"....XGDXX...XXADX....",
	"....XDX.......XAX....",
	".....X.........X.....",
	".....................",
]

## Compact 15x15 five-pointed faceted star for narrow / phone columns.
const COMPACT_ART: Array[String] = [
	".......X.......",
	"......XHX......",
	"......XHX......",
	".....XHHGX.....",
	"...XXXHHGXXX...",
	"..XHHHHLGGGGX..",
	".XAHHHHLLGGGRX.",
	"..XAAALHLRRRX..",
	"...XAGGHDDRX...",
	"...XGGDDADDX...",
	"...XGGDDADDX...",
	"...XGDDXAADX...",
	"...XDXX.XXAX...",
	"....X.....X....",
	"...............",
]

static var _image_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _glow_cache: Dictionary = {}

## Current rating on the 0..5 scale when `rated` is true.
var stars: float = 0.0
## False until the course pushes a rating: all five sockets stay unlit.
var rated: bool = false
## True on narrow windows where the status column uses its 150px compact width.
var compact: bool = false


func _init(is_compact: bool = false) -> void:
	compact = is_compact
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_refresh_minimum_size()
	resized.connect(queue_redraw)


## Display `value` (clamped to 0..5) across the five stars, including any
## fractional part on the boundary star.
func set_rating(value: float) -> void:
	var clamped := clampf(value, 0.0, float(STAR_COUNT))
	if rated and is_equal_approx(stars, clamped):
		return
	rated = true
	stars = clamped
	queue_redraw()


## Return all five stars to their unlit recessed sockets.
func set_unrated() -> void:
	if not rated and is_equal_approx(stars, 0.0):
		return
	rated = false
	stars = 0.0
	queue_redraw()


## Switch between the 21x21 desktop stars and the 15x15 compact stars.
func set_compact(is_compact: bool) -> void:
	if compact == is_compact:
		return
	compact = is_compact
	_refresh_minimum_size()
	queue_redraw()


## Fill fraction (0..1) of star `index` (0..4).
func star_fill(index: int) -> float:
	if not rated or index < 0 or index >= STAR_COUNT:
		return 0.0
	return clampf(stars - float(index), 0.0, 1.0)


func star_side() -> int:
	return COMPACT_SIDE if compact else DESKTOP_SIDE


## Gap between texture bounds; compact overlaps only transparent edge columns.
func star_gap() -> int:
	return COMPACT_GAP if compact else DESKTOP_GAP


func _pad_x() -> int:
	return COMPACT_PAD_X if compact else DESKTOP_PAD_X


func _strip_height() -> int:
	return COMPACT_HEIGHT if compact else DESKTOP_HEIGHT


func _refresh_minimum_size() -> void:
	var side := star_side()
	var gap := star_gap()
	var pad := _pad_x()
	var total_w := pad * 2 + side * STAR_COUNT + gap * (STAR_COUNT - 1)
	custom_minimum_size = Vector2(float(total_w), float(_strip_height()))


func _draw() -> void:
	var side := star_side()
	var gap := star_gap()
	var strip_w := float(side * STAR_COUNT + gap * (STAR_COUNT - 1))
	var start_x := floorf((size.x - strip_w) * 0.5)
	var start_y := floorf((size.y - float(side)) * 0.5)
	var glow_diameter := int(roundf(float(side) * 1.4))
	var glow_tex := glow_texture(glow_diameter)
	var prestige_boost := 1.28 if (rated and stars >= 4.5) else 1.0

	for index in STAR_COUNT:
		var fill := star_fill(index)
		var x := start_x + float(index * (side + gap))
		if fill > 0.0:
			var glow_offset := floorf(float(glow_diameter - side) * 0.5)
			var glow_alpha := clampf(0.18 * minf(1.0, fill * 1.2) * prestige_boost, 0.0, 0.30)
			draw_texture_rect(
				glow_tex,
				Rect2(x - glow_offset, start_y - glow_offset, float(glow_diameter), float(glow_diameter)),
				false,
				Color(1.0, 1.0, 1.0, glow_alpha)
			)
		var tex := star_texture(fill, compact)
		draw_texture_rect(tex, Rect2(x, start_y, float(side), float(side)), false)


## The character grid for either layout mode.
static func grid_for(is_compact: bool) -> Array[String]:
	return COMPACT_ART if is_compact else DESKTOP_ART


## Horizontal interior bounds (first and last non-outline columns) of the star.
static func interior_bounds(is_compact: bool) -> Vector2i:
	var side := COMPACT_SIDE if is_compact else DESKTOP_SIDE
	return Vector2i(1, side - 2)


## Number of lit interior pixel columns for `fill` (0..1). At 0.5 on an
## odd-width star this lands directly on the central vertical ridge.
static func quantized_lit_columns(fill: float, is_compact: bool = false) -> int:
	var bounds := interior_bounds(is_compact)
	var span := bounds.y - bounds.x + 1
	return clampi(roundi(clampf(fill, 0.0, 1.0) * float(span)), 0, span)


## Bake one star (lit, unlit, or partially filled) into an RGBA8 Image.
static func star_image(fill: float, is_compact: bool = false) -> Image:
	var lit_cols := quantized_lit_columns(fill, is_compact)
	var key := "%d|%d" % [1 if is_compact else 0, lit_cols]
	if _image_cache.has(key):
		return _image_cache[key]

	var rows := grid_for(is_compact)
	var side := rows.size()
	var bounds := interior_bounds(is_compact)
	var cutoff_x := bounds.x + lit_cols
	var out := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)

	# 1px drop shadow directly below the star's bottom ink contour.
	for y in side:
		var row: String = rows[y]
		for x in side:
			if row[x] != "." and (y + 1 >= side or rows[y + 1][x] == "."):
				if y + 1 < side:
					out.set_pixel(x, y + 1, DROP_SHADOW)

	for y in side:
		var row: String = rows[y]
		for x in side:
			var ch := row[x]
			if ch == ".":
				continue
			var is_lit_side := lit_cols > 0 and x < cutoff_x
			if ch == "X":
				var ink: Color = LIT_PALETTE["X"] if (lit_cols > 0 and x <= cutoff_x) else UNLIT_PALETTE["X"]
				out.set_pixel(x, y, ink)
			else:
				var color: Color = LIT_PALETTE[ch] if is_lit_side else UNLIT_PALETTE[ch]
				out.set_pixel(x, y, color)

	_image_cache[key] = out
	return out


## Cached ImageTexture for `star_image(fill, is_compact)`.
static func star_texture(fill: float, is_compact: bool = false) -> ImageTexture:
	var lit_cols := quantized_lit_columns(fill, is_compact)
	var key := "%d|%d" % [1 if is_compact else 0, lit_cols]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var tex := ImageTexture.create_from_image(star_image(fill, is_compact))
	_texture_cache[key] = tex
	return tex


## Soft radial golden aura drawn behind lit stars inside the dark value pill.
static func glow_texture(diameter: int) -> ImageTexture:
	var d := maxi(4, diameter)
	if _glow_cache.has(d):
		return _glow_cache[d]
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	var center := (float(d) - 1.0) * 0.5
	var max_r := float(d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) - center, float(y) - center).length()
			if dist < max_r:
				var falloff := 1.0 - dist / max_r
				img.set_pixel(x, y, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, falloff * falloff))
	var tex := ImageTexture.create_from_image(img)
	_glow_cache[d] = tex
	return tex
