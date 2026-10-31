extends Button
class_name HoleCardButton
## One hole of the course as a pocket scorecard tile on the Holes tab.
##
## The tab's old hole buttons were plain text rows — "H1: P3 (420 yds)" — so a
## nine-hole register read as a wall of identical captions. This button draws
## each hole instead: a little pixel-art window onto the hole itself, framed
## in the same notched 16-bit window chrome the rest of the dock wears (see
## PixelButtonStyle). Left to right:
##
##   * the TEE MARKER plate — an inset dark tile carrying the hole number in
##     gold, the way the marker on a real tee names the hole;
##   * the COURSE WINDOW — a recessed strip of map with the hole's own
##     layout drawn on it: the tee box and its white markers, a mow-striped
##     fairway ribbon running to the green, the cup and its red flag, with
##     bunkers, water and pines scattered from the hole's own seed. Par
##     decides the silhouette family (a par 3 is a short straight pitch, a
##     par 4 doglegs once, a par 5 sweeps through a double bend), the real
##     tee-to-cup vector decides which way the window faces, and the hole
##     number seeds every scatter, so no two buttons ever share a layout;
##   * the READOUT — PAR and the yardage, stacked in the pixel font.
##
## Because every tile is generated from the hole's data, the register at a
## glance is the routing itself: short holes sit beside long ones, left
## doglegs beside right ones. A closed hole's window is generated in a grey
## palette and the flag drops, and main.gd dims the whole tile the way it
## dimmed the old text button.
##
## The frames are the tab's manage-green PixelButtonStyle frames, so hover
## lights the trim, press sinks the bevel (and nudges the art down a pixel)
## and keyboard focus floats the same notched ring the other dock buttons
## wear. The button still behaves exactly like the old one: it is a Button
## named HoleBtnN, carries hole_number metadata, keeps the rich tooltip, and
## pressing it opens the hole's detail view.
##
## All map art is pure Image work, generated once per hole configuration and
## cached, so the register costs nothing to repaint through hover and press
## states, and tests can read the art pixel by pixel headless.

const FONT = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

## Whole button footprint. Three to a column (HOLE_COLUMN_HEIGHT in
## TerrainToolbar) inside the 190px bottom bar, beside the Holes Map card.
const BUTTON_SIZE := Vector2(188, 46)

## The tee marker plate: inset square, left of the course window.
const PLATE_RECT := Rect2(9, 9, 26, 28)
## The map window's ink-bordered rectangle and the art rect inside it. The
## art is generated at half resolution (MAP_W x MAP_H pixels) and drawn at
## twice the size with nearest filtering, so every golf course pixel lands as
## a crisp 2x2 screen block — chunky enough to sit with the frame's own
## whole-pixel bands.
const WINDOW_RECT := Rect2(38, 10, 96, 26)
const MAP_ORIGIN := Vector2(42, 12)
const MAP_SCALE := 2
const MAP_W := 44
const MAP_H := 11
## X the readout column starts at.
const READOUT_X := 140

const NUMBER_FONT_SIZE := 20
const READOUT_FONT_SIZE := 13
const YARDS_FONT_SIZE := 10

## The house greens and anchors, from the course's own terrain palette.
const PAL_ROUGH := Color("41612f")
const PAL_ROUGH_SPECK := Color("36522a")
const PAL_TREE := Color("2c4a22")
const PAL_TREE_TIP := Color("46703a")
const PAL_FAIRWAY := Color("6f9c42")
const PAL_FAIRWAY_LIGHT := Color("83b354")
const PAL_TEE := Color("7fae4d")
const PAL_TEE_DARK := Color("6d9a41")
const PAL_GREEN := Color("93bb58")
const PAL_GREEN_LIGHT := Color("a8cf6a")
const PAL_CUP := Color("1c2a1a")
const PAL_FLAG := Color("e04040")
const PAL_FLAG_SHADE := Color("b32f2f")
const PAL_POLE := Color("f0ead2")
const PAL_MARKER := Color("f4f1e4")
const PAL_BUNKER := Color("eddeb0")
const PAL_BUNKER_SHADE := Color("d3c290")
const PAL_WATER := Color("3f7d78")
const PAL_WATER_LIGHT := Color("5aa3a6")

## Frame ink and plate interior, in the family of the menu cards.
const PLATE_INK := PixelButtonStyle.INK
const PLATE_FILL := Color("0e1d16")
const PLATE_SHADOW := Color(0, 0, 0, 0.35)
const PLATE_LIP := Color(1, 1, 1, 0.07)
const PLATE_NUMBER := UIConstants.COLOR_GOLD
const PLATE_NUMBER_LIT := Color("ffe6a1")
const PLATE_NUMBER_CLOSED := Color("8f8a76")

const READOUT_PAR := UIConstants.COLOR_TEXT
const READOUT_PAR_CLOSED := Color("8f958b")
const READOUT_YARDS := UIConstants.COLOR_TEXT_DIM
const READOUT_YARDS_CLOSED := Color("79817a")

## The tab's section (Manage) colours the frame, exactly as the Holes Map
## card beside the register does.
const FRAME_ACCENT := TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.MANAGE]
const FRAME_FILL := Color("1d352b")
const FRAME_FILL_HOVER := Color("244134")

## How much the pointer lifts the art, and the press's one-pixel nudge.
const HOVER_LIFT := Color(1.14, 1.14, 1.08)
const PRESS_DIP := 1.0

## Generated map images, keyed on everything that shapes them: the hole, its
## par, whether it is open, and which way its tee-to-cup vector faces.
static var _map_cache: Dictionary = {}

var _hole_number := 1
var _par := 4
var _distance_yards := 0
var _is_open := true
## Which way the window faces: the true tee-to-cup vector collapsed to a
## flip (cup on the left when the real cup lies left of the tee) and a climb
## (cup high in the window when it lies up-course).
var _flip := false
var _climb := 0  # -1 cup sits high, +1 low, 0 level
var _map_texture: ImageTexture = null
var _map_key := ""
var _hovered := false


func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The card paints its own pixels; the rectangular chrome is the
	# PixelButtonStyle frame.
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("hover_pressed", empty)
	var fills := {
		"normal": FRAME_FILL,
		"hover": FRAME_FILL_HOVER,
		"pressed": FRAME_FILL.darkened(0.08),
		"hover_pressed": FRAME_FILL_HOVER.darkened(0.06),
		"disabled": FRAME_FILL,
	}
	var states := {
		"normal": PixelButtonStyle.State.NORMAL,
		"hover": PixelButtonStyle.State.HOVER,
		"pressed": PixelButtonStyle.State.PRESSED,
		"hover_pressed": PixelButtonStyle.State.HOVER,
		"disabled": PixelButtonStyle.State.NORMAL,
	}
	for state_name in states:
		add_theme_stylebox_override(state_name,
			PixelButtonStyle.texture_style(FRAME_ACCENT, states[state_name], fills[state_name]))
	# The shared focus overlay makes the navigated card stand out from hover
	# and from its own open/closed state.
	add_theme_stylebox_override("focus", PixelButtonStyle.focus_ring(FRAME_ACCENT))
	# The card draws its own caption, so the button's real text stays empty and
	# its colours never fight the art.
	for font_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color", "font_disabled_color",
			"font_outline_color"]:
		add_theme_color_override(font_state, Color.TRANSPARENT)
	for event in [mouse_entered, mouse_exited, button_down, button_up,
			focus_entered, focus_exited]:
		event.connect(queue_redraw)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


## Hand the card a hole. The number names it; the par and yardage fill its
## readout; the open flag and the real tee/cup cells shape the course window.
## The window's art regenerates only when something that shapes it changes.
func set_hole(hole_number: int, par: int, distance_yards: int, is_open: bool,
		tee_cell: Vector2i = Vector2i.ZERO, cup_cell: Vector2i = Vector2i.ZERO) -> void:
	_hole_number = hole_number
	_par = par
	_distance_yards = distance_yards
	_is_open = is_open
	_flip = cup_cell != tee_cell and cup_cell.x < tee_cell.x
	if cup_cell != tee_cell:
		var dy := cup_cell.y - tee_cell.y
		_climb = 0 if dy == 0 else (-1 if dy < 0 else 1)
	else:
		# No course cells to face along (a bare test button): the generator's
		# seeded nudge still keeps a column of fallback tiles from cloning.
		_climb = 0
	accessibility_name = "Hole %d" % hole_number
	accessibility_description = "Par %d, %d yards%s. Activate for hole details." % [
		par, distance_yards, "" if is_open else ", closed"]
	var key := "%d|%d|%d|%d|%d" % [_hole_number, _par, int(_is_open), int(_flip), _climb]
	if key != _map_key:
		_map_key = key
		_map_texture = ImageTexture.create_from_image(_map_image())
	queue_redraw()


func _map_image() -> Image:
	if not _map_cache.has(_map_key):
		_map_cache[_map_key] = HoleCardButton.generate_map(
			_hole_number, _par, _is_open, _flip, _climb)
	return _map_cache[_map_key]


## The register line the card carries — "P5 (420 yds)" — in plain text, for
## tests and for anything that asks the card what the hole is.
func readout_text() -> String:
	return "P%d (%d yds)" % [_par, _distance_yards]


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return  # Not laid out yet.
	var dip := PRESS_DIP if is_pressed() and not disabled else 0.0
	var lit := (_hovered or has_focus()) and not disabled
	_draw_plate(dip, lit)
	_draw_course_window(dip, lit)
	_draw_readout(dip, lit)


## The tee marker plate: an inset dark tile, ink-bordered and shadowed along
## its top, lit along its bottom lip, with the hole number centred in gold.
func _draw_plate(dip: float, lit: bool) -> void:
	var rect := PLATE_RECT
	rect.position.y += dip
	draw_rect(Rect2(rect.position, rect.size), PLATE_INK)
	var inner := Rect2(rect.position + Vector2.ONE, rect.size - Vector2(2, 2))
	draw_rect(inner, PLATE_FILL)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), PLATE_SHADOW)
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 1),
		Vector2(inner.size.x, 1)), PLATE_LIP)
	var digits := "%02d" % _hole_number
	var font_size := NUMBER_FONT_SIZE
	while font_size > 12 and FONT.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x > inner.size.x - 4.0:
		font_size -= 1
	var text_size := FONT.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := rect.position.y + (rect.size.y + FONT.get_ascent(font_size) \
		- FONT.get_descent(font_size)) * 0.5
	var color: Color = PLATE_NUMBER_CLOSED if not _is_open \
		else (PLATE_NUMBER_LIT if lit else PLATE_NUMBER)
	draw_string(FONT, rect.position + Vector2(floorf((rect.size.x - text_size.x) * 0.5),
		baseline - rect.position.y), digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## The course window: an ink-bordered recess holding the hole's own map, the
## art lifted a touch under the pointer.
func _draw_course_window(dip: float, lit: bool) -> void:
	var rect := WINDOW_RECT
	rect.position.y += dip
	draw_rect(Rect2(rect.position, rect.size), PLATE_INK)
	# The recess is lit from below and shadowed from above, the opposite of a
	# raised tile — a window the map sits in, not on. Its back wall stays the
	# same deep green in every state, so hover never brightens the recess.
	var inner := Rect2(rect.position + Vector2.ONE, rect.size - Vector2(2, 2))
	draw_rect(inner, PAL_CUP.darkened(0.2))
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)),
		Color(0, 0, 0, 0.3) if _is_open else Color(0, 0, 0, 0.45))
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 1),
		Vector2(inner.size.x, 1)), PLATE_LIP)
	if _map_texture:
		var origin := rect.position + (MAP_ORIGIN - WINDOW_RECT.position)
		var art_size := Vector2(MAP_W, MAP_H) * MAP_SCALE
		draw_texture_rect(_map_texture, Rect2(origin, art_size), false,
			HOVER_LIFT if lit and _is_open else Color.WHITE)


## PAR over the yardage, right of the window, the same register the old text
## button carried — now set in the pixel font like a scorecard entry.
func _draw_readout(dip: float, lit: bool) -> void:
	var par_text := "P%d" % _par
	var yards_text := "%dy" % _distance_yards
	var par_color: Color = READOUT_PAR_CLOSED if not _is_open \
		else (Color.WHITE if lit else READOUT_PAR)
	var yards_color: Color = READOUT_YARDS_CLOSED if not _is_open else READOUT_YARDS
	draw_string(FONT, Vector2(READOUT_X, 22 + dip), par_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE, par_color)
	draw_string(FONT, Vector2(READOUT_X, 34 + dip), yards_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, YARDS_FONT_SIZE, yards_color)


# =============================================================================
# THE COURSE WINDOW'S MAP
# =============================================================================
#
# The map is a MAP_W x MAP_H image of the hole seen from above: rough on the
# ground, pines round the edges, the striped fairway running from the tee box
# to the green and its red flag. Everything is placed by a seeded generator,
# so the same hole always draws the same layout and two holes never share
# one. The route's shape follows the par — par 3s barely bend, par 4s dogleg
# once, par 5s sweep through two bends — and the whole thing can mirror
# horizontally and tilt vertically to face the way the real hole plays.

## A minimal deterministic generator: an LCG seeded from the hole's own
## numbers, so layouts are stable across sessions and platforms without a
## RandomNumberGenerator's seeding dance.
class _Rng:
	var _state: int
	func _init(from_seed: int) -> void:
		_state = (from_seed * 1103515245 + 12345) & 0x7fffffff
	func next() -> int:
		_state = (_state * 1103515245 + 12345) & 0x7fffffff
		return _state
	func range_i(low: int, high: int) -> int:  # inclusive both ends
		return low + next() % (high - low + 1)
	func chance(percent: int) -> bool:
		return next() % 100 < percent


## The palette a map is painted in: the course's own colours while the hole
## is open, a greyed ground (and a dropped flag) while it is closed.
static func _palette(is_open: bool) -> Dictionary:
	if is_open:
		return {
			"rough": PAL_ROUGH, "speck": PAL_ROUGH_SPECK,
			"tree": PAL_TREE, "tree_tip": PAL_TREE_TIP,
			"fairway": PAL_FAIRWAY, "fairway_light": PAL_FAIRWAY_LIGHT,
			"tee": PAL_TEE, "tee_dark": PAL_TEE_DARK,
			"green": PAL_GREEN, "green_light": PAL_GREEN_LIGHT,
			"cup": PAL_CUP, "flag": PAL_FLAG, "flag_shade": PAL_FLAG_SHADE,
			"pole": PAL_POLE, "marker": PAL_MARKER,
			"bunker": PAL_BUNKER, "bunker_shade": PAL_BUNKER_SHADE,
			"water": PAL_WATER, "water_light": PAL_WATER_LIGHT,
		}
	var grey := {}
	for key in _palette(true):
		var color: Color = _palette(true)[key]
		var lum := color.get_luminance() * 0.82
		# Keep a little of the hue so the closed map reads as faded turf
		# rather than a photocopy.
		grey[key] = color.lerp(Color(lum, lum, lum), 0.72).darkened(0.08)
	return grey


## Generate one hole's window art. flip mirrors the route (the true cup lies
## left of the tee), climb tilts it (the cup sits high or low in the strip).
## Pure Image work: stable, cacheable and testable headless.
static func generate_map(hole_number: int, par: int, is_open: bool,
		flip: bool, climb: int) -> Image:
	var pal := _palette(is_open)
	# The seed carries everything that shapes the layout but nothing that
	# changes by the day: one hole, one layout, every session.
	var rng := _Rng.new(hole_number * 7919 + par * 104729 + (337 if flip else 0) + (climb + 1) * 61)
	var image := Image.create(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	image.fill(pal["rough"])

	# Mottled rough.
	for y in MAP_H:
		for x in MAP_W:
			if rng.next() % 100 < 9:
				image.set_pixel(x, y, pal["speck"])

	# The route from the tee to the cup. The tee anchors the short edge the
	# real tee faces; bend depth follows the par. The climb tilts the whole
	# picture: the cup sits high in the window when the real cup lies
	# up-course, and the tee drops the other way.
	var tee := Vector2i(3 if not flip else MAP_W - 4, _anchor_y(-climb, rng))
	var cup := Vector2i(MAP_W - 4 if not flip else 3, _anchor_y(climb, rng))
	var route := _route(tee, cup, par, rng, flip)
	_paint_fairway(image, pal, route)
	_paint_tee_box(image, pal, route)
	var green_center := _paint_green(image, pal, route)
	_paint_hazards(image, pal, route, green_center, par, rng)
	# The pines come last among the terrain: they stand on whatever rough is
	# left along the window's edges so a bold dogleg never mows them down.
	_paint_pines(image, pal, rng)
	_paint_flag(image, pal, green_center, route, is_open)
	return image


## Where along the window's height an end sits: the tilt shifts it twice as
## far as the seeded nudge can scatter it, so an up-course cup always hangs
## above a down-course one and level holes still vary.
static func _anchor_y(tilt: int, rng: _Rng) -> int:
	return clampi(int(MAP_H / 2.0) + tilt * 2 + rng.range_i(-1, 1), 2, MAP_H - 3)


## The waypoints the fairway follows: the tee, the par's bends and the cup.
static func _route(tee: Vector2i, cup: Vector2i, par: int, rng: _Rng, flip: bool) -> Array:
	var direction := 1.0 if not flip else -1.0
	var span := float(cup.x - tee.x) * direction  # always positive
	# Dogleg handedness comes from the seed: real routings mix left and right.
	var hand := 1 if rng.chance(50) else -1
	var points: Array = [Vector2(tee)]
	var bend := 0.0
	var ledge := 0.0
	var floor_y := 2.0
	var ceil_y := MAP_H - 3.0
	match par:
		3:
			# A short straight pitch; the tiny wobble is terrain, not routing.
			var wobble := Vector2(tee).lerp(Vector2(cup), 0.5) + Vector2(0, hand * rng.range_i(0, 1))
			wobble.y = clampf(wobble.y, floor_y, ceil_y)
			points.append(wobble)
		4:
			# One honest dogleg, knee somewhere past halfway.
			bend = hand * rng.range_i(4, 6)
			var knee := Vector2(tee) + Vector2(span * (0.50 + rng.next() % 11 / 100.0) * direction, bend)
			knee.y = clampf(knee.y, floor_y, ceil_y)
			points.append(knee)
		_:
			# Par 5, or a freakishly long 4 / short 3: the sweeping S.
			bend = hand * rng.range_i(3, 4)
			ledge = -bend * rng.range_i(50, 100) / 100.0
			var hip := Vector2(tee) + Vector2(span * 0.34 * direction, bend)
			var shoulder := Vector2(tee) + Vector2(span * 0.68 * direction, ledge)
			hip.y = clampf(hip.y, floor_y, ceil_y)
			shoulder.y = clampf(shoulder.y, floor_y, ceil_y)
			points.append(hip)
			points.append(shoulder)
	points.append(Vector2(cup))
	return points


## March a polyline, calling `plot` at every half pixel along it.
static func _walk(points: Array, plot: Callable) -> void:
	for i in range(1, points.size()):
		var from: Vector2 = points[i - 1]
		var to: Vector2 = points[i]
		var steps := int(from.distance_to(to) * 2.0) + 1
		for s in range(steps + 1):
			plot.call(from.lerp(to, float(s) / float(steps)))


## The striped ribbon: three pixels deep, mown in sweeping diagonal bands.
## The stripes land on every fairway pixel afterwards, so water and rough
## crossings stay cuts, not stripes.
static func _paint_fairway(image: Image, pal: Dictionary, route: Array) -> void:
	var set_px := func(x: int, y: int, color: Color) -> void:
		if x >= 0 and y >= 0 and x < MAP_W and y < MAP_H:
			image.set_pixel(x, y, color)
	_walk(route, func(p: Vector2) -> void:
		var cx := int(round(p.x))
		var cy := int(round(p.y))
		set_px.call(cx, cy, pal["fairway"])
		set_px.call(cx, cy + 1, pal["fairway"])
		set_px.call(cx, cy - 1, pal["fairway"]))
	# The mow: sweeping diagonal bands, two on then two off.
	for y in MAP_H:
		for x in MAP_W:
			if image.get_pixel(x, y) == pal["fairway"] and (x + y) % 4 < 2:
				image.set_pixel(x, y, pal["fairway_light"])


## The tee box sits astride the route's first step: a block of mown tee with
## its darker edge and the two white markers that name the hole's start.
static func _paint_tee_box(image: Image, pal: Dictionary, route: Array) -> void:
	var tee: Vector2 = route[0]
	var out: Vector2 = (Vector2(route[1]) - tee).normalized()
	var side := Vector2(-out.y, out.x)
	var center := Vector2(tee) + out * 1.0
	for a_i in [-1, 0, 1]:
		var a := float(a_i)
		for b_i in [-1, 1]:
			var p: Vector2 = center + side * a + out * (float(b_i) * 0.5)
			_plot(image, int(round(p.x)), int(round(p.y)), pal["tee"])
		var shade_p := center + side * a + out * 1.5
		_plot(image, int(round(shade_p.x)), int(round(shade_p.y)), pal["tee_dark"])
	# The markers stand off the box's back corners.
	for a_i in [-2, 2]:
		var p: Vector2 = center + side * float(a_i) - out * 0.5
		_plot(image, int(round(p.x)), int(round(p.y)), pal["marker"])


## The green is a small putting-surface blob at the route's end; returns the
## cup cell (the blob's middle) for the flag to stand on.
static func _paint_green(image: Image, pal: Dictionary, route: Array) -> Vector2i:
	var cup := Vector2i(int(round((route.back() as Vector2).x)), int(round((route.back() as Vector2).y)))
	# A 5x4 ellipse reads as a green at this scale; the top edge catches light.
	var rows := [3, 5, 5, 3]
	for r in range(rows.size()):
		var row_y := cup.y - 2 + r
		var width: int = rows[r]
		for c in range(width):
			var px := cup.x - (width >> 1) + c
			_plot(image, px, row_y, pal["green"])
	_plot(image, cup.x - 1, cup.y - 1, pal["green_light"])
	_plot(image, cup.x, cup.y - 1, pal["green_light"])
	_plot(image, cup.x + 1, cup.y - 2, pal["green_light"])
	return cup


## Seeded trouble: bunkers tucked near the route's bends, and sometimes a
## water carry cutting the ribbon before the green. Nothing may land on the
## tee, the green, or the two cells of fairway either side of the cup.
static func _paint_hazards(image: Image, pal: Dictionary, route: Array,
		green_center: Vector2i, par: int, rng: _Rng) -> void:
	var bunker_count := rng.range_i(1, 2) if par <= 3 else (rng.range_i(2, 3) if par == 4 else 3)
	var placed_cells: Array = []
	for _attempt in range(32):
		if placed_cells.size() >= bunker_count:
			break
		var t := (25 + rng.next() % 60) / 100.0
		var p := _point_along(route, t)
		var offset_side := 2 + rng.next() % 3
		var tangent := _tangent_along(route, t)
		var side := Vector2(-tangent.y, tangent.x) * (float(offset_side) * (1 if rng.chance(50) else -1))
		var cell := Vector2i(int(round(p.x + side.x)), int(round(p.y + side.y)))
		if _is_reserved(image, pal, cell, route, green_center):
			continue
		# Real bunkers keep their distance from one another on the hole.
		var too_close := false
		for other in placed_cells:
			if (cell - Vector2i(other)).length() < 4.0:
				too_close = true
				break
		if too_close:
			continue
		# A neat round of sand with a shaded lip on its low side.
		_plot(image, cell.x, cell.y, pal["bunker"])
		_plot(image, cell.x + 1, cell.y, pal["bunker"])
		_plot(image, cell.x, cell.y + 1, pal["bunker"])
		_plot(image, cell.x + 1, cell.y + 1, pal["bunker_shade"])
		placed_cells.append(cell)
	# The water carry: cut the ribbon an approach-shot's width before the
	# green, and sparkle the far bank. Par 3s stay dry (their drama is bunkers),
	# longer holes carry water from the seed about a third of the time. The
	# channel only floods turf — it never swallows the green, the tee or a pine.
	var water_odds := 0 if par <= 3 else (30 if par == 4 else 40)
	if rng.chance(water_odds):
		var t := 0.70 + (rng.next() % 12) / 100.0
		var center := _point_along(route, t)
		var tangent := _tangent_along(route, t)
		var side := Vector2(-tangent.y, tangent.x)
		var turf: Array = [pal["rough"], pal["speck"], pal["fairway"], pal["fairway_light"]]
		for s in range(-3, 4):
			var p := center + side * float(s)
			var cell := Vector2i(int(round(p.x)), int(round(p.y)))
			if cell.x < 0 or cell.y < 0 or cell.x >= MAP_W or cell.y >= MAP_H:
				continue
			if cell.distance_to(Vector2(green_center)) < 2.5:
				continue
			if image.get_pixel(cell.x, cell.y) not in turf:
				continue
			_plot(image, cell.x, cell.y, pal["water_light"] if s % 3 == 0 else pal["water"])


## The cup and its flag: pole standing off the incoming fairway, pennant
## flying toward the window's open end — or a bare cup with the flag dropped
## while the hole is closed.
static func _paint_flag(image: Image, pal: Dictionary, cup: Vector2i, route: Array,
		is_open: bool) -> void:
	_plot(image, cup.x, cup.y, pal["cup"])
	if not is_open:
		return
	# The flag stands on the far side of the cup from the route it arrived on.
	var incoming: Vector2 = ((route.back() as Vector2) - (route[-2] as Vector2)) \
		if route.size() > 1 else Vector2.RIGHT
	var lean := -1 if incoming.y > 0.15 else 1
	# If the green hugs that edge there is no sky for the pole: stand the
	# other way instead.
	if cup.y + 3 * lean < 1 or cup.y + 3 * lean > MAP_H - 2:
		lean = -lean
	var pole_x := cup.x
	for i in range(1, 4):
		var py: int = cup.y + i * lean
		if py >= 0 and py < MAP_H:
			image.set_pixel(pole_x, py, pal["pole"])
	# The pennant flies toward whichever end of the window has the room: two
	# pixels on the pole's tip row and its shaded heel one row toward the cup,
	# so it reads as one little flag, not scattered dust.
	var top_y: int = cup.y + 3 * lean
	var pennant_side := 1 if cup.x < int(MAP_W / 2.0) else -1
	if top_y >= 0 and top_y < MAP_H:
		_plot(image, pole_x + pennant_side, top_y, pal["flag"])
		_plot(image, pole_x + pennant_side * 2, top_y, pal["flag"])
		var heel_y := top_y - lean
		if heel_y >= 0 and heel_y < MAP_H:
			_plot(image, pole_x + pennant_side, heel_y, pal["flag_shade"])


## Pines stand along the window's long edges, planted only on open rough so
## the route, hazards and green never behead them — a whiffed spot just stays
## grass.
static func _paint_pines(image: Image, pal: Dictionary, rng: _Rng) -> void:
	var count := rng.range_i(4, 7)
	var open := [pal["rough"], pal["speck"]]
	for _i in range(count):
		var x := rng.range_i(1, MAP_W - 3)
		var top := rng.chance(50)
		var y := rng.range_i(0, 1) if top else rng.range_i(MAP_H - 2, MAP_H - 1)
		var dx := 1 if rng.chance(50) else -1
		if image.get_pixel(x, y) not in open or image.get_pixel(x + dx, y) not in open:
			continue
		_plot(image, x, y, pal["tree"])
		_plot(image, x + dx, y, pal["tree"])
		_plot(image, x, y + (1 if top else -1), pal["tree_tip"])


## March the route handsomely: `t` (0..1) along its total arc length.
static func _point_along(route: Array, t: float) -> Vector2:
	var total := 0.0
	for i in range(1, route.size()):
		total += (route[i] as Vector2).distance_to(route[i - 1])
	var want := total * clampf(t, 0.0, 1.0)
	for i in range(1, route.size()):
		var seg := (route[i] as Vector2).distance_to(route[i - 1])
		if want <= seg:
			return (route[i - 1] as Vector2).lerp(route[i], want / seg if seg > 0.0 else 0.0)
		want -= seg
	return route.back()


## Local direction of the route around `t`, from the segments either side.
static func _tangent_along(route: Array, t: float) -> Vector2:
	var before := _point_along(route, maxf(0.0, t - 0.03))
	var after := _point_along(route, minf(1.0, t + 0.03))
	var delta := after - before
	return delta.normalized() if delta.length() > 0.001 else Vector2.RIGHT


## True where hazards must not walk: on the route's own ribbon, next to the
## tee or the green, or off the map.
static func _is_reserved(image: Image, pal: Dictionary, cell: Vector2i,
		route: Array, green: Vector2i) -> bool:
	if cell.x < 1 or cell.y < 0 or cell.x >= MAP_W - 1 or cell.y >= MAP_H:
		return true
	if cell.distance_to(Vector2(route[0])) < 3.5 or cell.distance_to(Vector2(green)) < 3.5:
		return true
	# A bunker may not straddle the ribbon; water is painted outright.
	return image.get_pixel(cell.x, cell.y) in [pal["fairway"], pal["fairway_light"]]


static func _plot(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < MAP_W and y < MAP_H:
		image.set_pixel(x, y, color)
