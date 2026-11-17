extends RefCounted
class_name VisitorProfileStyle
## The shared look of the Visiting Golfer profile: its palette, its fixed card
## footprint and the small pixel instruments a dossier card is built from.
##
## The profile is a row of cards on the Golfers shelf, not a page that grows.
## Every card is exactly `CARD_HEIGHT` tall - the same 140px a full column of
## three visitor plates takes - so opening a visitor's profile never lifts the
## shelf above the register it replaces. What does not fit a card travels to
## the right, into the next card, where the shelf already scrolls.
##
## One palette serves the whole row: the dark green glass of the rest of the
## dock, a cream pixel caption, and a section colour used only on a card's
## mark, title and rule. The rim itself is the visitor's own green (on the
## course) or tan (past visitor), so the row reads as one set of files on one
## clubhouse desk.

const FONT := VisitorCardButton.FONT
const CREAM := VisitorCardButton.CREAM
const LIT := Color("ffffff")

## Quiet body text: a golfer's labels, captions and notes.
const MUTED := Color("93a89b")
const DIM := Color("b9c8b4")

## The row's two visitor accents, shared with the register's plates.
const ACTIVE_ACCENT := Color("83c9a4")
const PAST_ACCENT := Color("b5a477")

## Status and meter colours. They are deliberately soft, so a card of five
## meters still reads as one instrument rather than a warning panel.
const GREEN := Color("8fd6a5")
const GOLD := Color("e5c57c")
const SKY := Color("87b9cf")
const CORAL := Color("e39a78")
const APRICOT := Color("e0a878")
const ORCHID := Color("c9a6dd")
const SAGE := Color("a8c98f")
const TEAL := Color("8fb8a8")
const TAN := Color("d8bd8a")
const RED := Color("e2877a")

## Card footprint. `CARD_HEIGHT` is the register's own three-plate column:
## 3 x 44px plates and the two 4px gaps between them. `HEADER_HEIGHT` is the
## mark, title, rule and their gaps; `BODY_HEIGHT` is what is left for rows.
const CARD_HEIGHT := 140.0
const CARD_PAD := 7.0
const HEADER_HEIGHT := 22.0
const BODY_HEIGHT := 104.0

## Row rhythm inside a card. A line row (label + value) is 20px, a scorecard
## line is tighter at 16px, a wrapped comment gets two lines at 29px, and a
## meter row carries its caption and bar in 20px.
const LINE_ROW := 20.0
const SCORE_ROW := 16.0
const COMMENT_ROW := 29.0
const METER_ROW := 20.0
const NOTE_ROW := 29.0
const TILE_HEIGHT := 34.0

## How many rows of each kind one card holds before the section continues in
## the next card to its right.
const LINES_PER_CARD := 5
const SCORES_PER_CARD := 6
const COMMENTS_PER_CARD := 3
const METERS_PER_CARD := 5


## A pixel-font label with the quiet defaults every card shares: no pointer
## interception, a single clipped line unless the caller wraps it.
static func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## How wide a label's text is at `font_size`, plus a pixel of breathing room.
static func text_width(text: String, font_size: int) -> float:
	return ceilf(FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size).x) + 1.0


## A label that keeps its own width instead of collapsing to one pixel inside
## a container. `make_label` clips, and a clipped Label reports no minimum
## width, so anything that must sit beside an expanding label - a status, a
## membership plate, a card's counter - asks for its text width explicitly.
## `cap` keeps a long value from pushing a row wider than its card.
static func width_label(text: String, font_size: int, color: Color,
		cap := 0.0) -> Label:
	var label := make_label(text, font_size, color)
	var width := text_width(text, font_size)
	if cap > 0.0:
		width = minf(width, cap)
	label.custom_minimum_size.x = width
	return label


## A label that shrinks its type until `text` fits `room` pixels, then clips.
## Names and long values keep their whole silhouette instead of pushing a card
## wider than the row it belongs to.
static func fit_label(text: String, font_size: int, min_size: int, room: float,
		color: Color) -> Label:
	var label := make_label(text, font_size, color)
	while font_size > min_size and FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x > room:
		font_size -= 1
		label.add_theme_font_size_override("font_size", font_size)
	return label


## The colour a profile section wears on its mark, title and rule. Titles come
## from the profile data (main.gd), so unknown ones - a mod's extra section -
## fall back to the row's cream rather than an arbitrary colour.
static func section_color(title: String) -> Color:
	match title.to_lower():
		"identity":
			return ORCHID
		"club membership":
			return GOLD
		"current round":
			return GREEN
		"scorecard":
			return SKY
		"golf skills":
			return SAGE
		"golfer traits":
			return APRICOT
		"golfer skills":
			return TAN
		"golfer statuses":
			return CORAL
		"golfer comments":
			return ORCHID
		"course experience":
			return TEAL
	return DIM


## The instrument colour of one golfer status meter.
static func meter_color(meter_name: String) -> Color:
	match meter_name.to_lower():
		"fun":
			return GOLD
		"attitude":
			return GREEN
		"energy":
			return SKY
		"hunger":
			return APRICOT
		"thirst":
			return CORAL
	return TEAL


## How a 0..1 reading is coloured: contented green, watchful gold, unhappy red.
static func level_color(value: float) -> Color:
	if value >= 0.66:
		return GREEN
	if value >= 0.33:
		return GOLD
	return RED


## The colour a comment's sentiment dot wears.
static func sentiment_color(sentiment: String) -> Color:
	match sentiment.to_lower():
		"positive":
			return GREEN
		"negative":
			return RED
	return GOLD


## The colour a score to par wears, from the same table the scorecard uses.
static func score_color(strokes: int, par: int) -> Color:
	return UIConstants.get_score_color(strokes - par)


# ============================================================================
# SMALL PIXEL INSTRUMENTS
# ============================================================================

## The little diamond that opens a card's header.
class Mark extends Control:
	var color := Color.WHITE

	func _init(mark_color: Color) -> void:
		color = mark_color
		custom_minimum_size = Vector2(6, 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		# A three-row pixel gem: one pixel, three, one.
		draw_rect(Rect2(2, 0, 2, 2), color)
		draw_rect(Rect2(0, 2, 6, 2), color.lightened(0.18))
		draw_rect(Rect2(2, 4, 2, 2), color.darkened(0.15))


## The status dot beside an identity card's "ON THE COURSE" line.
class StatusDot extends Control:
	var color := Color.WHITE

	func _init(dot_color: Color) -> void:
		color = dot_color
		custom_minimum_size = Vector2(7, 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		draw_rect(Rect2(2, 0, 3, 1), color)
		draw_rect(Rect2(0, 1, 7, 5), color)
		draw_rect(Rect2(2, 6, 3, 1), color)
		draw_rect(Rect2(2, 2, 3, 3), color.lightened(0.45))


## An ON/OFF light in a golfer trait or skill's row: an unlit trough for Off,
## the row's accent as a lit pill for On. Both are the same footprint, so a
## card's right edge never shifts as switches flip.
class Switch extends Control:
	var on := false
	var accent := Color.WHITE

	func _init(is_on: bool, lit: Color) -> void:
		on = is_on
		accent = lit
		custom_minimum_size = Vector2(38, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var body := Rect2(0, 2, 38, 10)
		draw_rect(body, Color(0.02, 0.06, 0.05, 0.85) if not on
			else Color(accent.r, accent.g, accent.b, 0.22))
		# A single pixel rim, lit along the top the way every card is.
		draw_rect(Rect2(0, 2, 38, 1), accent.darkened(0.25) if on else Color(0.25, 0.34, 0.29))
		draw_rect(Rect2(0, 11, 38, 1), accent.darkened(0.45) if on else Color(0.08, 0.13, 0.11))
		if on:
			draw_rect(Rect2(2, 4, 3, 6), accent)
		var text := "ON" if on else "OFF"
		var font_size := 9
		var width := VisitorProfileStyle.FONT.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := (14.0 + VisitorProfileStyle.FONT.get_ascent(font_size)
			- VisitorProfileStyle.FONT.get_descent(font_size)) * 0.5
		draw_string(VisitorProfileStyle.FONT,
			Vector2(38.0 - width - 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size, accent.lightened(0.35) if on else VisitorProfileStyle.MUTED)


## A segmented pixel bar: the same instrument the status meters and golf
## skills share, at two different widths.
class SegmentedBar extends Control:
	var value := 0.0
	var accent := Color.WHITE
	var segments := 10

	func _init(reading: float, bar_accent: Color, count := 10) -> void:
		value = clampf(reading, 0.0, 1.0)
		accent = bar_accent
		segments = maxi(count, 1)
		custom_minimum_size = Vector2(40, 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var gap := 2.0
		var segment_width := maxf((size.x - gap * float(segments - 1)) / float(segments), 1.0)
		var lit := int(round(value * float(segments)))
		for index in segments:
			var x := float(index) * (segment_width + gap)
			var rect := Rect2(floorf(x), 0.0, ceilf(segment_width), size.y)
			if index < lit:
				draw_rect(rect, accent)
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), accent.lightened(0.35))
			else:
				draw_rect(rect, Color(0.03, 0.08, 0.07, 0.9))
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Color(0.11, 0.18, 0.15))


## One golfer status as a card row: its name, its reading and a wide segmented
## bar. Drawn rather than assembled from a ProgressBar, so it keeps the dock's
## pixel grain instead of the engine theme's smooth trough.
class MeterRow extends Control:
	var meter_name := ""
	var reading := 0.0
	var accent := Color.WHITE

	func _init(name_text: String, value: float, meter_accent: Color) -> void:
		meter_name = name_text
		reading = clampf(value, 0.0, 1.0)
		accent = meter_accent
		custom_minimum_size = Vector2(0, VisitorProfileStyle.METER_ROW)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var font := VisitorProfileStyle.FONT
		var baseline := font.get_ascent(10)
		draw_string(font, Vector2(0, baseline), meter_name, HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 44.0, 10, VisitorProfileStyle.CREAM)
		var reading_text := "%d%%" % int(round(reading * 100.0))
		var width := font.get_string_size(reading_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(size.x - width, baseline), reading_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, VisitorProfileStyle.level_color(reading))
		var bar := Rect2(0, 14, size.x, 5)
		var gap := 2.0
		var segments := 16
		var segment_width := maxf((bar.size.x - gap * float(segments - 1)) / float(segments), 1.0)
		var lit := int(round(reading * float(segments)))
		for index in segments:
			var x := floorf(bar.position.x + float(index) * (segment_width + gap))
			var rect := Rect2(x, bar.position.y, ceilf(segment_width), bar.size.y)
			if index < lit:
				draw_rect(rect, accent)
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), accent.lightened(0.32))
			else:
				draw_rect(rect, Color(0.03, 0.08, 0.07, 0.9))
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Color(0.11, 0.18, 0.15))


## One hole of the scorecard: the hole, its par, its strokes in a small chip
## and the score's name in the colour the rest of the game gives it.
class ScoreRow extends Control:
	var hole_text := ""
	var par := 0
	var strokes := 0
	var score_name := ""
	var parsed := false

	func _init(line: String) -> void:
		custom_minimum_size = Vector2(0, VisitorProfileStyle.SCORE_ROW)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parsed = _parse(line)
		if not parsed:
			hole_text = line

	## "H3: 4 strokes / par 5 / Birdie" - the shape main.gd writes. Anything
	## else is shown as a quiet note instead of a broken row.
	func _parse(line: String) -> bool:
		var colon := line.find(":")
		if colon <= 0:
			return false
		var pieces := line.substr(colon + 1).split("/")
		if pieces.size() < 3:
			return false
		var stroke_words := pieces[0].strip_edges().split(" ")
		var par_words := pieces[1].strip_edges().split(" ")
		if stroke_words.is_empty() or par_words.size() < 2:
			return false
		hole_text = line.substr(0, colon).strip_edges()
		strokes = int(stroke_words[0])
		par = int(par_words[1])
		score_name = pieces[2].strip_edges()
		return true

	func _draw() -> void:
		var font := VisitorProfileStyle.FONT
		var baseline := (VisitorProfileStyle.SCORE_ROW + font.get_ascent(10)
			- font.get_descent(10)) * 0.5
		if not parsed:
			draw_string(font, Vector2(0, baseline), hole_text, HORIZONTAL_ALIGNMENT_LEFT,
				size.x, 10, VisitorProfileStyle.MUTED)
			return
		var color := VisitorProfileStyle.score_color(strokes, par)
		draw_string(font, Vector2(0, baseline), hole_text, HORIZONTAL_ALIGNMENT_LEFT,
			24.0, 10, VisitorProfileStyle.MUTED)
		draw_string(font, Vector2(30, baseline), "PAR %d" % par,
			HORIZONTAL_ALIGNMENT_LEFT, 38.0, 9, VisitorProfileStyle.MUTED)
		# The strokes chip: a recessed pixel well with the number on it.
		var chip := Rect2(70, 2, 18, 12)
		draw_rect(chip, Color(color.r, color.g, color.b, 0.16))
		draw_rect(Rect2(chip.position, Vector2(chip.size.x, 1)),
			Color(color.r, color.g, color.b, 0.7))
		draw_rect(Rect2(chip.position + Vector2(0, chip.size.y - 1), Vector2(chip.size.x, 1)),
			Color(color.r, color.g, color.b, 0.35))
		var strokes_text := str(strokes)
		var strokes_width := font.get_string_size(strokes_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 10).x
		draw_string(font, Vector2(chip.position.x + (chip.size.x - strokes_width) * 0.5, baseline),
			strokes_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
		var name_width := font.get_string_size(score_name, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 9).x
		draw_string(font, Vector2(size.x - name_width, baseline), score_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color.lightened(0.12))
