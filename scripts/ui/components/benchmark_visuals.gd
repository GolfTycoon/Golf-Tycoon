extends RefCounted
class_name BenchmarkVisuals
## BenchmarkVisuals - the drawn parts of the Benchmark Results screen.
##
## The results screen is a room full of little instruments: a frame-time
## oscilloscope, a bar chart of the runs kept on the shelf, segmented meters
## for each metric and a row of stars for the device rating. Every one of them
## is drawn rather than themed, in whole pixels, so they read as the same pixel
## art as the rest of the menus: no anti-aliasing, no gradients, hard edges
## everywhere, and the game's own palette (mint for "fine", gold for "worth a
## look", muted red for "missed the frame budget").
##
## Each control quantises its drawing to the pixel grid, so a chart is just as
## crisp at 390 px on a phone as it is at 2560 px on a desktop; the chart's
## columns simply get wider. The factories at the bottom hand out named
## controls the screen composes and the layout tests can find.

## Frame budget lines the frame chart marks: 60 FPS and the 33 ms stutter
## threshold the benchmark counts frames against.
const BUDGET_60_MS := 1000.0 / 60.0
const STUTTER_MS := 33.3

const COLOR_INK := Color("08130f")
const COLOR_INSET := MenuStyle.INSET_BG
const COLOR_GRID := Color(0.39, 0.44, 0.35, 0.22)
const COLOR_AXIS := Color(0.39, 0.44, 0.35, 0.55)
const COLOR_FINE := MenuStyle.ACCENT_SECONDARY
const COLOR_WARN := MenuStyle.ACCENT_PRIMARY
const COLOR_BAD := UIConstants.COLOR_DANGER_MUTED
const COLOR_TEXT := MenuStyle.TITLE_COLOR
const COLOR_TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED

const AXIS_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")
const VALUE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")

## The colour a 0-100 metric score wears: the same three-colour story the
## charts tell, so a red bar and a red grade mean the same thing.
static func score_color(score: float) -> Color:
	if score >= 70.0:
		return COLOR_FINE
	if score >= 40.0:
		return COLOR_WARN
	return COLOR_BAD

## The colour a five-star device rating wears.
static func tier_color(stars: int) -> Color:
	match stars:
		5: return COLOR_WARN
		4: return COLOR_FINE
		3: return MenuStyle.ACCENT_UTILITY
		_: return COLOR_TEXT_QUIET

# =============================================================================
# FRAME-TIME CHART
# =============================================================================

## The oscilloscope: one chunky column per sampled frame, mint under the 60 FPS
## budget, gold between there and 33 ms, muted red over it. The scale is chosen
## from the worst frame so a stutter always shows as a spike rather than
## flattening the rest of the run, and the two budget lines are drawn across it
## so the reader can see what "good" looked like without a legend.
class FrameChart extends Control:
	var values: Array[float] = []
	var average_ms: float = 0.0
	var one_percent_low_fps: float = 0.0
	var axis_font_size: int = 10
	var draw_axis: bool = true
	## Height reserved for the axis strip along the bottom.
	const AXIS_BAND := 12.0

	func _init(p_values: Array[float] = []) -> void:
		values = p_values
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(120.0, 64.0)
		resized.connect(queue_redraw)

	func set_series(p_values: Array[float], p_average_ms: float = 0.0,
			p_one_percent_low_fps: float = 0.0) -> void:
		values = p_values
		average_ms = p_average_ms
		one_percent_low_fps = p_one_percent_low_fps
		queue_redraw()

	## The chart's ceiling in milliseconds: the worst frame, lifted to a round
	## number so the axis labels land on something readable.
	func ceiling_ms() -> float:
		var worst := 0.0
		for sample in values:
			worst = maxf(worst, sample)
		worst = maxf(worst, STUTTER_MS * 1.25)
		var step := 10.0 if worst < 60.0 else (25.0 if worst < 160.0 else 50.0)
		return ceilf(worst / step) * step

	func _draw() -> void:
		var w := floorf(size.x)
		var h := floorf(size.y)
		if w < 8.0 or h < 8.0:
			return
		var plot_h := h - (AXIS_BAND if draw_axis else 0.0)
		_draw_background(w, h)
		if values.is_empty():
			_draw_empty(w, plot_h)
			return
		var ceiling := ceiling_ms()
		_draw_grid(w, plot_h, ceiling)
		_draw_columns(w, plot_h, ceiling)
		_draw_budget_lines(w, plot_h, ceiling)
		_draw_average_line(w, plot_h, ceiling)
		if draw_axis:
			_draw_axis(w, h, plot_h, ceiling)

	func _draw_background(w: float, h: float) -> void:
		draw_rect(Rect2(0, 0, w, h), Color(COLOR_INSET.r, COLOR_INSET.g, COLOR_INSET.b, 0.95))
		# Ink frame with a lit top edge, the way the menu's insets are cut.
		draw_rect(Rect2(0, 0, w, h), COLOR_INK, false, 1.0)
		draw_line(Vector2(1, 1), Vector2(w - 2, 1), Color(0.30, 0.38, 0.33, 0.35), 1.0)

	func _draw_empty(w: float, plot_h: float) -> void:
		draw_string(AXIS_FONT, Vector2(8, floorf(plot_h * 0.55)),
			"No frames sampled yet - run the test to draw the course of the run.",
			HORIZONTAL_ALIGNMENT_LEFT, int(w) - 12, axis_font_size + 1, COLOR_TEXT_QUIET)

	func _draw_grid(w: float, plot_h: float, ceiling: float) -> void:
		for step in range(1, 4):
			var y := floorf(plot_h * (1.0 - float(step) / 4.0))
			draw_line(Vector2(1, y), Vector2(w - 2, y), COLOR_GRID, 1.0)
		# Vertical ticks every eighth of the run, so the eye can count frames.
		var tick_count := 8
		for step in range(1, tick_count):
			var x := floorf(w * float(step) / float(tick_count))
			draw_line(Vector2(x, plot_h - 4), Vector2(x, plot_h - 1), COLOR_AXIS, 1.0)
		if ceiling <= 0.0:
			return

	func _draw_columns(w: float, plot_h: float, ceiling: float) -> void:
		var count := values.size()
		var usable := maxf(w - 2.0, 1.0)
		var slot := usable / float(count)
		var column := maxf(floorf(slot) - (1.0 if slot >= 2.0 else 0.0), 1.0)
		for index in range(count):
			var sample := maxf(values[index], 0.001)
			var height := clampf(sample / ceiling, 0.0, 1.0) * (plot_h - 2.0)
			var x := floorf(1.0 + float(index) * slot)
			var top := floorf(plot_h - height)
			var rect := Rect2(x, top, minf(column, usable - x + 1.0), maxf(plot_h - top - 1.0, 1.0))
			var color := COLOR_FINE
			if sample > STUTTER_MS:
				color = COLOR_BAD
			elif sample > BUDGET_60_MS:
				color = COLOR_WARN
			draw_rect(rect, color)
			# One lit pixel along the top of each column: the bevel that makes
			# the chart read as pixel art rather than a smooth plot.
			draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1.0),
				Color(color.r, color.g, color.b, 1.0).lightened(0.35))

	func _draw_budget_lines(w: float, plot_h: float, ceiling: float) -> void:
		if ceiling <= 0.0:
			return
		_draw_dashed_line(w, plot_h, ceiling, BUDGET_60_MS, Color(COLOR_FINE.r, COLOR_FINE.g,
			COLOR_FINE.b, 0.75))
		_draw_dashed_line(w, plot_h, ceiling, STUTTER_MS, Color(COLOR_BAD.r, COLOR_BAD.g,
			COLOR_BAD.b, 0.75))

	func _draw_dashed_line(w: float, plot_h: float, ceiling: float, ms: float,
			color: Color) -> void:
		if ms >= ceiling:
			return
		var y := floorf(plot_h * (1.0 - ms / ceiling))
		var x := 1.0
		while x < w - 3.0:
			draw_line(Vector2(x, y), Vector2(minf(x + 4.0, w - 2.0), y), color, 1.0)
			x += 7.0

	func _draw_average_line(w: float, plot_h: float, ceiling: float) -> void:
		if average_ms <= 0.0 or average_ms >= ceiling:
			return
		var y := floorf(plot_h * (1.0 - average_ms / ceiling))
		draw_line(Vector2(1, y), Vector2(w - 2, y), Color(COLOR_TEXT.r, COLOR_TEXT.g,
			COLOR_TEXT.b, 0.85), 1.0)
		if one_percent_low_fps <= 0.0:
			return
		var low_ms := 1000.0 / one_percent_low_fps
		if low_ms >= ceiling:
			return
		var low_y := floorf(plot_h * (1.0 - low_ms / ceiling))
		_draw_dashed_line(w, plot_h, ceiling, low_ms, Color(COLOR_WARN.r, COLOR_WARN.g,
			COLOR_WARN.b, 0.9))
		draw_line(Vector2(1, low_y), Vector2(1, low_y), COLOR_WARN, 1.0)

	func _draw_axis(w: float, h: float, plot_h: float, ceiling: float) -> void:
		draw_line(Vector2(1, plot_h), Vector2(w - 2, plot_h), COLOR_AXIS, 1.0)
		draw_string(AXIS_FONT, Vector2(3, h - 2), "0", HORIZONTAL_ALIGNMENT_LEFT, -1,
			axis_font_size, COLOR_TEXT_QUIET)
		draw_string(AXIS_FONT, Vector2(w - 34.0, h - 2), "%.0f ms" % ceiling,
			HORIZONTAL_ALIGNMENT_LEFT, -1, axis_font_size, COLOR_TEXT_QUIET)

# =============================================================================
# COMPARISON BARS
# =============================================================================

## The shelf's bar chart: one bar per run kept in the history, the newest in
## gold and the rest in mint, each with its value above it and its time below.
## A single run reads as one bar with room to grow; an empty shelf says so.
class BarChart extends Control:
	var values: Array[float] = []
	var labels: Array[String] = []
	var unit: String = ""
	var highlight_last: bool = true
	var value_font_size: int = 10
	var label_font_size: int = 9
	const LABEL_BAND := 13.0

	func _init(p_values: Array[float] = [], p_labels: Array[String] = []) -> void:
		values = p_values
		labels = p_labels
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(140.0, 72.0)
		resized.connect(queue_redraw)

	func set_series(p_values: Array[float], p_labels: Array[String], p_unit: String = "") -> void:
		values = p_values
		labels = p_labels
		unit = p_unit
		queue_redraw()

	func _draw() -> void:
		var w := floorf(size.x)
		var h := floorf(size.y)
		if w < 8.0 or h < 8.0:
			return
		draw_rect(Rect2(0, 0, w, h), Color(COLOR_INSET.r, COLOR_INSET.g, COLOR_INSET.b, 0.95))
		draw_rect(Rect2(0, 0, w, h), COLOR_INK, false, 1.0)
		if values.is_empty():
			draw_string(AXIS_FONT, Vector2(8, floorf(h * 0.55)),
				"No past runs yet - finished runs are kept here to compare.",
				HORIZONTAL_ALIGNMENT_LEFT, int(w) - 12, label_font_size + 1, COLOR_TEXT_QUIET)
			return
		var plot_h := h - LABEL_BAND - float(value_font_size) - 4.0
		var peak := 0.0
		for value in values:
			peak = maxf(peak, value)
		peak = maxf(peak, 1.0)
		for step in range(1, 4):
			var y := floorf(float(value_font_size) + 2.0 + plot_h * (1.0 - float(step) / 4.0))
			draw_line(Vector2(1, y), Vector2(w - 2, y), COLOR_GRID, 1.0)
		var count := values.size()
		var slot := (w - 4.0) / float(count)
		var bar_width := clampf(floorf(slot) - 6.0, 4.0, 46.0)
		var baseline := floorf(float(value_font_size) + 2.0 + plot_h)
		draw_line(Vector2(1, baseline), Vector2(w - 2, baseline), COLOR_AXIS, 1.0)
		for index in range(count):
			var value := maxf(values[index], 0.0)
			var height := clampf(value / peak, 0.0, 1.0) * plot_h
			var x := floorf(3.0 + float(index) * slot + (slot - bar_width) * 0.5)
			var top := floorf(baseline - height)
			var is_last := highlight_last and index == count - 1
			var color := COLOR_WARN if is_last else COLOR_FINE
			draw_rect(Rect2(x, top, bar_width, maxf(baseline - top, 1.0)), color)
			draw_rect(Rect2(x, top, bar_width, 1.0), color.lightened(0.35))
			draw_rect(Rect2(x, top, bar_width, maxf(baseline - top, 1.0)),
				Color(0.02, 0.05, 0.04, 0.85), false, 1.0)
			var caption := "%.0f%s" % [value, unit]
			draw_string(VALUE_FONT, Vector2(x - 4.0, top - 3.0), caption,
				HORIZONTAL_ALIGNMENT_CENTER, int(bar_width) + 8, value_font_size,
				COLOR_WARN if is_last else COLOR_TEXT)
			if index < labels.size():
				draw_string(AXIS_FONT, Vector2(x - 6.0, h - 3.0), labels[index],
					HORIZONTAL_ALIGNMENT_CENTER, int(bar_width) + 12, label_font_size,
					COLOR_TEXT_QUIET)

# =============================================================================
# SEGMENTED METER
# =============================================================================

## A metric's meter: a row of chunky segments, lit up to the score, in the
## colour that score earns. The segment count keeps it honest - a meter that
## cannot show 73.4% does not pretend to.
class SegmentMeter extends Control:
	var fraction: float = 0.0
	var accent: Color = COLOR_FINE
	var segments: int = 14

	func _init(p_fraction: float = 0.0, p_accent: Color = COLOR_FINE, p_segments: int = 14) -> void:
		fraction = clampf(p_fraction, 0.0, 1.0)
		accent = p_accent
		segments = maxi(p_segments, 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(80.0, 12.0)
		resized.connect(queue_redraw)

	func set_fraction(value: float, p_accent: Color = accent) -> void:
		fraction = clampf(value, 0.0, 1.0)
		accent = p_accent
		queue_redraw()

	## How many segments are lit - what the tests read back.
	func lit_segments() -> int:
		return int(roundf(fraction * float(segments)))

	func _draw() -> void:
		var w := floorf(size.x)
		var h := floorf(size.y)
		if w < 8.0 or h < 4.0:
			return
		var gap := 2.0
		var slot := w / float(segments)
		var block := maxf(floorf(slot) - gap, 1.0)
		var lit := lit_segments()
		for index in range(segments):
			var x := floorf(float(index) * slot)
			var rect := Rect2(x, 0.0, minf(block, w - x), h)
			if index < lit:
				draw_rect(rect, accent)
				draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1.0),
					accent.lightened(0.4))
				draw_rect(Rect2(rect.position.x, rect.end.y - 1.0, rect.size.x, 1.0),
					accent.darkened(0.3))
			else:
				draw_rect(rect, Color(COLOR_INSET.r, COLOR_INSET.g, COLOR_INSET.b, 1.0))
				draw_rect(rect, Color(0.02, 0.05, 0.04, 0.9), false, 1.0)

# =============================================================================
# STAR ROW
# =============================================================================

## The device's five-star rating, drawn with the game's own star sprite: gold
## and lit for the stars it earned, greyed for the ones it did not.
class StarRow extends Control:
	var stars: int = 0
	var star_side: int = 16
	var total: int = 5

	func _init(p_stars: int = 0, p_side: int = 16) -> void:
		stars = clampi(p_stars, 0, 5)
		star_side = PixelIcon.snapped_side(p_side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_refresh_minimum()
		resized.connect(queue_redraw)

	func set_stars(value: int) -> void:
		stars = clampi(value, 0, 5)
		queue_redraw()

	func _refresh_minimum() -> void:
		custom_minimum_size = Vector2(float(star_side) * float(total) + 4.0 * float(total - 1),
			float(star_side))

	func _draw() -> void:
		var gap := 4.0
		var lit := PixelIcon.texture(PixelIcon.Kind.STAR, star_side, COLOR_WARN, false)
		var unlit := PixelIcon.texture(PixelIcon.Kind.STAR, star_side, MenuStyle.ACCENT_UTILITY, true)
		for index in range(total):
			var x := floorf(float(index) * (float(star_side) + gap))
			var texture := lit if index < stars else unlit
			draw_texture_rect(texture, Rect2(x, 0.0, float(star_side), float(star_side)), false)

static func make_frame_chart(values: Array[float], average_ms: float, one_percent_low_fps: float,
		chart_name: String = "FrameChart") -> FrameChart:
	var chart := FrameChart.new(values)
	chart.name = chart_name
	chart.average_ms = average_ms
	chart.one_percent_low_fps = one_percent_low_fps
	return chart

static func make_bar_chart(values: Array[float], labels: Array[String], unit: String = "",
		chart_name: String = "HistoryChart") -> BarChart:
	var chart := BarChart.new(values, labels)
	chart.name = chart_name
	chart.unit = unit
	return chart

static func make_meter(fraction: float, accent: Color, meter_name: String = "Meter",
		segments: int = 14) -> SegmentMeter:
	var meter := SegmentMeter.new(clampf(fraction, 0.0, 1.0), accent, segments)
	meter.name = meter_name
	return meter

static func make_star_row(stars: int, side: int = 16, row_name: String = "StarRow") -> StarRow:
	var row := StarRow.new(stars, side)
	row.name = row_name
	return row
