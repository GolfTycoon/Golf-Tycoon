extends RefCounted
class_name PixelIcon
## Pixel-art action icons for the title screen's cards and tiles.
##
## Each of the seven actions carries a 16x16 sprite: a pennant on its mound
## for Start New Game, a lightning bolt for Quick Start, the play triangle for
## Continue, a floppy disk for Load Game, a polo shirt for the Golfer Skins
## studio, a cog for Settings and a doorway arrow for Quit. The World Map
## atlas reuses the same sprite kit for its own marks: a dollar coin for the
## company treasury and a teardrop map pin for the destinations and legend.
## The Benchmark Results screen adds four more: a chip for the CPU workload, a
## graphics card for the GPU fill test, a pulse trace for frame pacing and a
## memory stick for the run's footprint.
## They are sprites
## in the old sense - a grid of characters, one per pixel, painted from a
## palette derived from the card's own accent - so a gold card gets a gold
## pennant and the Quit tile gets its muted red arrow.
##
## The grids carry their own ink outline, a lit top edge and a shade side,
## matching the light direction of PixelButtonStyle's frames (light comes
## from above). Baked into an ImageTexture with the project's nearest
## filtering, they stay hard-edged at whatever size the layout asks for;
## each source pixel becomes a whole block of screen pixels.
##
## Icons are generated once per kind, size, accent and dim flag and cached,
## because the menu rebuilds itself whenever the window crosses a layout
## breakpoint.

enum Kind { FLAG, BOLT, PLAY, FLOPPY, SHIRT, GEAR, DOOR, COIN, PIN, TROPHY, STAR,
	CHIP, GPU, PULSE, MEMORY }

## Side of the sprite grid, in source pixels.
const GRID := 16

## Ink outline shared by every sprite: the frame's own ink, solid.
const INK := Color("0b1a14")
## Fixed greens for the pennant's mound, whatever the card's accent is.
const GRASS := Color("7fb08a")
const GRASS_DARK := Color("2c6739")

## The sprites, one 16-character row per pixel row. Characters are palette
## keys: '.' air, 'X' ink outline, 'A' the accent, 'L' its lit face, 'D' its
## shade, 'C' cream, 'M' muted, 'W' white, 'G'/'g' the mound's greens.
const ART := {
	Kind.FLAG: [
		"................",
		"...CXXXXXXXXX...",
		"...CXLLLLLLX....",
		"...CXAAAAAX.....",
		"...CXAAAAAX.....",
		"...CXAAAAAAX....",
		"...CXXXXXXXXX...",
		"...C............",
		"...C............",
		"...C.....WW.....",
		"...C.....WW.....",
		"...CXXXXXGX.....",
		"...XGGGGGGGX....",
		"..XGGGGGGGGGX...",
		".XXXXXXXXXXXXX..",
		"................",
	],
	Kind.BOLT: [
		"................",
		"........XXXXXX..",
		".......XLLLLX...",
		"......XLAAAX....",
		"......XAAAX.....",
		"...XXXLAAAAXXX..",
		"...XLLAAAAALLX..",
		"...XAAAAAAAAAX..",
		"...XXAAAAAAAXX..",
		".....XAAAAAX....",
		"....XLAAAAX.....",
		"...XLAAAXX......",
		"....XAAX........",
		"....XAX.........",
		".....X..........",
		"................",
	],
	Kind.PLAY: [
		"................",
		"................",
		"....X...........",
		"....XX..........",
		"....XLXX........",
		"....XALLXX......",
		"....XAAALLXX....",
		"....XAAAAALLX...",
		"....XAAAAAAAX...",
		"....XAAAAAXX....",
		"....XAAAXX......",
		"....XAXX........",
		"....XX..........",
		"....X...........",
		"................",
		"................",
	],
	Kind.FLOPPY: [
		"................",
		"....XXXXXXXXXX..",
		"...XLCCCCCLLLX..",
		"..XLDCXXCCDDDX..",
		"..XDDCXXCCDDDX..",
		"..XDDCXXCCDDDX..",
		"..XDDCCCCCDDDX..",
		"..XDDDDDDDDDDX..",
		"..XDCCCCCCCCDX..",
		"..XDCMMMMMMCDX..",
		"..XDCCCCCCCCDX..",
		"..XDCMMMMMMCDX..",
		"..XDCCCCCCCCDX..",
		"..XDCCCCCCCCDX..",
		"..XXXXXXXXXXXX..",
		"................",
	],
	Kind.SHIRT: [
		"................",
		"................",
		".....XXXXXX.....",
		"....XLCLLLCX....",
		"...XLACCACCLX...",
		"..XLAAAACAAALX..",
		"..XAAAAADAAAAX..",
		"..XXXAAADAAXXX..",
		".....XAAAAX.....",
		".....XAAAAX.....",
		".....XAAAAX.....",
		".....XAAAAX.....",
		".....XAAAAX.....",
		".....XXXXXX.....",
		"................",
		"................",
	],
	Kind.GEAR: [
		"......XXX.......",
		"...X..XLX..X....",
		"..XLXXLAAXXLX...",
		".XLALLAAALLALX..",
		"..XAAAAAAAAAX...",
		"..XAAA...AAAX...",
		"XXLAA.....AAAXX.",
		"XLAAA.....AAALX.",
		"XXAAA.....AAAXX.",
		"..XAAA...AAAX...",
		"..XAAAAAAAAAX...",
		".XLAAAAAAAAAAX..",
		"..XAXXAAAXXAX...",
		"...X..XAX..X....",
		"......XXX.......",
		"................",
	],
	Kind.DOOR: [
		"................",
		"................",
		"..CCCCCC........",
		"..CCCCCC........",
		"..CC.....X......",
		"..CC.....XXX....",
		"..CC.XXXXLLLX...",
		"..CC.XLLLAAALXX.",
		"..CC.XAAAAAAX...",
		"..CC.XXXXAXX....",
		"..CC.....X......",
		"..CC............",
		"..CCCCCC........",
		"..CCCCCC........",
		"................",
		"................",
	],
	Kind.COIN: [
		"................",
		"................",
		"......XXXX......",
		"....XXLLLLXX....",
		"...XLLLLLLAAX...",
		"...XLLACCCAAX...",
		"..XLLLLCAAAADX..",
		"..XLLLACCCAADDX.",
		"..XLLAAAACDDDX..",
		"..XLAAAACCCDDDX.",
		"...XAAAAADCDDX..",
		"...XAAADDDDDX...",
		"....XXDDDDXX....",
		"......XXXX......",
		"................",
		"................",
	],
	Kind.PIN: [
		"................",
		"................",
		"......XXXX......",
		".....XLLAAX.....",
		"....XLLLAADX....",
		"....XLLAAADX....",
		"...XLAA..ADDX...",
		"...XLAA..ADDX...",
		"....XAAAADDX....",
		".....XAADDX.....",
		".....XAAADX.....",
		"......XADX......",
		".......XX.......",
		"................",
		"................",
		"................",
	],
	Kind.TROPHY: [
		"................",
		"...XXXXXXXXXX...",
		"...XLLLLLLLAX...",
		"X..XLAAAAAAAX..X",
		"XX.XLAAAAAAAX.XX",
		"XX.XLAAAAAAAX.XX",
		".XXXLAAAAAAAXXX.",
		"...XDAAAAAADX...",
		"....XAAAAAAX....",
		"....XDAAAAAX....",
		".....XAAAAX.....",
		".....XAAAAX.....",
		"...XXXXXXXXXX...",
		"..XXXXXXXXXXXX..",
		"................",
		"................",
	],
	Kind.STAR: [
		"................",
		".......XX.......",
		"......XLLX......",
		"......XLLX......",
		".....XLLLLX.....",
		"X....XLAAAX....X",
		"XX...XLAAAX...XX",
		"XXXX.XLAAAX.XXXX",
		"XXXX.XDAAAX.XXXX",
		"XX...XDAAAX...XX",
		"X....XDAAAX....X",
		".....XDDDDX.....",
		"......XDDX......",
		"......XDDX......",
		".......XX.......",
		"................",
	],
	Kind.CHIP: [
		"................",
		"....X..X..X.....",
		"....X..X..X.....",
		"..XXXXXXXXXXXX..",
		"..XLLLLLLLLLLX..",
		"XXLAAAAAAAAAAXXX",
		"XXLAACCCCCAAAXXX",
		"..LAACCCCCAADA..",
		"..LAACCCCCAADA..",
		"XXLAACCCCCAAAXXX",
		"XXLAAAAAAAAAAXXX",
		"..XDAAAAAAAAAX..",
		"..XDDDDDDDDDDX..",
		"....X..X..X.....",
		"....X..X..X.....",
		"................",
	],
	Kind.GPU: [
		"................",
		"X...............",
		"XXXXXXXXXXXXXXXX",
		"XLLLLLLLLLLLLLLX",
		"XLA....CC....AAX",
		"XLAA..CWWMWC.AAX",
		"XLA..CWMMMMWC.AX",
		"XLAA.CMMXXMMC.AX",
		"XLA..CWMMMMWC.AX",
		"XLAA..CWWMWC.AAX",
		"XLA....CC....AAX",
		"XDAAAAAAAAAAAAAX",
		"XDDDDDDDDDDDDDDX",
		".XX.XX.XX.XX.XX.",
		"................",
		"................",
	],
	Kind.PULSE: [
		"................",
		"..XXXXXXXXXXXX..",
		"..XLLLLLLLLLLX..",
		"..XAAAAWAAAAAX..",
		"..XAAAAWAAAAAX..",
		"..XAAAWWAAAAAX..",
		"..XAAAWAWAAAAX..",
		"..XWAAWAWWWWWX..",
		"..XWWWAAWAAAAX..",
		"..XAAAAAWAAAAX..",
		"..XDDDDDDDDDDX..",
		"..XXXXXXXXXXXX..",
		"......XXXX......",
		"......XXXX......",
		".....XXXXXX.....",
		"................",
	],
	Kind.MEMORY: [
		"................",
		"................",
		"................",
		"..XXXXXXXXXXXX..",
		"..XLLLLLLLLLLX..",
		"..XACMACMACMAX..",
		"..XAMMAMMAMMAX..",
		"..XAMMAMMAMMAX..",
		"..XAMMAMMAMMAX..",
		"..XDDDDDDDDDDX..",
		"..XDDDDDDDDDDX..",
		"..XXXXXXXXXXXX..",
		"...X..X..X..X...",
		"................",
		"................",
		"................",
	],
}

## Generated icon textures, keyed on kind, size, accent and dim flag.
static var _cache: Dictionary = {}

## The palette one sprite is painted with: the card's accent and its lit and
## shaded faces, plus the neutrals. `dimmed` greys the accent family for a
## disabled card (no saves to Continue or Load).
static func palette_for(accent: Color, dimmed: bool) -> Dictionary:
	if dimmed:
		var grey := Color(0.44, 0.47, 0.45, 1.0)
		return {
			"X": INK,
			"A": grey,
			"L": grey.lightened(0.22),
			"D": grey.darkened(0.30),
			"C": Color(0.62, 0.64, 0.60, 1.0),
			"M": Color(0.40, 0.43, 0.41, 1.0),
			"W": Color(0.66, 0.68, 0.65, 1.0),
			"G": GRASS.darkened(0.35),
			"g": GRASS_DARK.darkened(0.35),
		}
	return {
		"X": INK,
		"A": accent,
		"L": accent.lightened(0.42),
		"D": accent.darkened(0.45),
		"C": UIConstants.COLOR_TEXT,
		"M": UIConstants.COLOR_TEXT_MUTED,
		"W": Color(0.98, 0.98, 0.96, 1.0),
		"G": GRASS,
		"g": GRASS_DARK,
	}

## The sprite at `side` screen pixels: the 16x16 art nearest-scaled, so every
## source pixel lands as a whole block of `side / GRID`-ish pixels and the
## edges stay hard.
static func image(kind: int, side: int, accent: Color, dimmed: bool = false) -> Image:
	var out_side := snapped_side(side)
	var key := "%d|%d|%s|%d" % [kind, out_side, accent.to_html(), 1 if dimmed else 0]
	if _cache.has(key + "|img"):
		return _cache[key + "|img"]
	var palette := palette_for(accent, dimmed)
	var rows: Array = ART[kind]
	var out := Image.create_empty(out_side, out_side, false, Image.FORMAT_RGBA8)
	var clear := Color(0, 0, 0, 0)
	var scale := float(out_side) / float(GRID)
	for y in out_side:
		var row: String = rows[int(float(y) / scale)]
		for x in out_side:
			var ch := row[int(float(x) / scale)]
			out.set_pixel(x, y, palette[ch] if ch != "." else clear)
	_cache[key + "|img"] = out
	return out

## Icons scale in whole multiples of the sprite grid, so every source pixel
## becomes an even block of screen pixels - no ragged cells at 2.3x.
static func snapped_side(side: int) -> int:
	var factor := clampi(int(roundf(float(side) / float(GRID))), 1, 3)
	return factor * GRID

## The sprite as a texture, ready for `button.icon` or a TextureRect.
static func texture(kind: int, side: int, accent: Color, dimmed: bool = false) -> ImageTexture:
	var out_side := snapped_side(side)
	var key := "%d|%d|%s|%d" % [kind, out_side, accent.to_html(), 1 if dimmed else 0]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(image(kind, side, accent, dimmed))
	_cache[key] = tex
	return tex
