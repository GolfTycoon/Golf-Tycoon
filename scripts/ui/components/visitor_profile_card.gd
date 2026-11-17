extends PanelContainer
class_name VisitorProfileCard
## One card of the Visiting Golfer profile: a titled panel of fixed height that
## holds as many rows as fit, with the rest continuing in the next card.
##
## The card is the dock's own glass frame (PixelButtonStyle) with the visitor's
## green or tan rim, a slim section-coloured spine, a pixel gem, an uppercase
## pixel title and a hairline rule. Its body sits in a clipped, fixed-height
## holder, so no amount of profile data can make the card taller than
## `VisitorProfileStyle.CARD_HEIGHT` - and therefore no profile can make the
## shelf taller than the register it opens over.
##
## The body is assembled row by row by TerrainToolbar: label/value rows (with a
## lit switch for On/Off and a segmented bar for a percentage), status meters,
## scorecard lines and wrapped comments. This class owns how a row looks, not
## which rows a section has.

const HEIGHT := VisitorProfileStyle.CARD_HEIGHT
const BODY_HEIGHT := VisitorProfileStyle.BODY_HEIGHT

## The section title as the profile data writes it ("Golf Skills"), before the
## card uppercases it for display. Kept readable for tests and callers.
var title_text := ""
var accent := VisitorProfileStyle.ACTIVE_ACCENT
var tint := VisitorProfileStyle.SKY

var _body: VBoxContainer
var _meta: HBoxContainer


func _init(title: String, rim: Color, section_tint: Color, width: float) -> void:
	name = "VisitorProfileCard"
	title_text = title
	accent = rim
	accessibility_name = title
	tint = section_tint
	# Decorative: the shelf's scroll and the course behind it keep the pointer.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(width, HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(rim,
		MenuStyle.CARD_BG.lerp(rim, 0.05), 0, 0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(VisitorProfileStyle.CARD_PAD))
	margin.add_theme_constant_override("margin_right", int(VisitorProfileStyle.CARD_PAD))
	margin.add_theme_constant_override("margin_top", int(VisitorProfileStyle.CARD_PAD))
	margin.add_theme_constant_override("margin_bottom", int(VisitorProfileStyle.CARD_PAD))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	# The section's index stripe, inset inside the rim so the frame stays whole.
	var spine := ColorRect.new()
	spine.color = Color(tint.r, tint.g, tint.b, 0.8)
	spine.custom_minimum_size = Vector2(2, 0)
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spine)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	header.custom_minimum_size = Vector2(0, 14)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)
	header.add_child(VisitorProfileStyle.Mark.new(tint))
	var title_label := VisitorProfileStyle.make_label(title.to_upper(), 10,
		tint.lightened(0.22))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.tooltip_text = title
	header.add_child(title_label)
	_meta = HBoxContainer.new()
	_meta.add_theme_constant_override("separation", 4)
	_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_meta)

	# Air, the rule, then air again: `HEADER_HEIGHT` in total.
	var top_gap := Control.new()
	top_gap.custom_minimum_size.y = 2
	top_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(top_gap)
	var rule := ColorRect.new()
	rule.color = Color(tint.r, tint.g, tint.b, 0.42)
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rule)
	var bottom_gap := Control.new()
	bottom_gap.custom_minimum_size.y = 5
	bottom_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bottom_gap)

	# A plain Control does not pass its children's minimum height on, and it
	# clips: the card is exactly `HEIGHT` tall whatever the rows ask for.
	var holder := Control.new()
	holder.custom_minimum_size.y = BODY_HEIGHT
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(holder)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A short section (Current Round is two rows) sits in the middle of its
	# card rather than clinging to the header, so every card reads as filled.
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_body)
	_body.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)


## Mark this card as the `page`-th of `total` cards the section needed, so a
## reader knows there is more to the right rather than assuming a cut-off.
func set_page(page: int, total: int) -> void:
	if total <= 1:
		return
	_meta.add_child(VisitorProfileStyle.width_label("%d / %d" % [page, total], 9,
		VisitorProfileStyle.MUTED))


## The comment tally in a comments card's header: three soft counters in the
## sentiment colours. Compact enough to sit beside the title.
func set_tally(positive: int, neutral: int, negative: int) -> void:
	for entry in [[positive, VisitorProfileStyle.GREEN, "+%d"], [neutral, VisitorProfileStyle.GOLD, "=%d"],
			[negative, VisitorProfileStyle.RED, "-%d"]]:
		if int(entry[0]) <= 0:
			continue
		_meta.add_child(VisitorProfileStyle.width_label(str(entry[2]) % int(entry[0]),
			9, entry[1]))


## A quiet right-hand note in the header, e.g. a meter card's average.
func set_header_note(text: String, color: Color = VisitorProfileStyle.MUTED) -> void:
	_meta.add_child(VisitorProfileStyle.width_label(text, 9, color))


## One label/value row. `kind` is "value" (quiet), "switch" (an On/Off light)
## or "percent" (a segmented bar and its reading).
func add_line_row(key_text: String, value_text: String, kind := "value") -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = VisitorProfileStyle.LINE_ROW
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(row)

	var key := VisitorProfileStyle.make_label(key_text, 10, VisitorProfileStyle.DIM)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)

	match kind:
		"switch":
			row.add_child(VisitorProfileStyle.Switch.new(value_text.to_lower() == "on", tint))
		"percent":
			var percent := clampf(value_text.trim_suffix("%").strip_edges().to_float()
				/ 100.0, 0.0, 1.0)
			var bar := VisitorProfileStyle.SegmentedBar.new(percent, tint, 10)
			row.add_child(bar)
			var reading := VisitorProfileStyle.width_label(value_text, 10,
				tint.lightened(0.18), 40)
			reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			reading.custom_minimum_size.x = maxf(reading.custom_minimum_size.x, 32)
			_show_full_text_on_hover(reading, value_text)
			row.add_child(reading)
		_:
			var value := VisitorProfileStyle.width_label(value_text, 10,
				VisitorProfileStyle.CREAM, 140)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value.size_flags_horizontal = Control.SIZE_SHRINK_END
			value.custom_minimum_size.x = maxf(value.custom_minimum_size.x, 40)
			_show_full_text_on_hover(value, value_text)
			row.add_child(value)


## When a value had to be capped to its card, hovering it still gives the
## whole text; an uncapped value needs no tooltip.
func _show_full_text_on_hover(label: Label, text: String) -> void:
	if VisitorProfileStyle.text_width(text, 10) <= label.custom_minimum_size.x:
		return
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS


## A wrapped note: an unparsed line, a long activity description or a comment.
func add_note_row(text: String, color: Color = VisitorProfileStyle.DIM) -> void:
	var label := VisitorProfileStyle.make_label(text, 10, color)
	# A clipped Label reports a one-pixel minimum; a wrapped note has to be
	# allowed to ask for its two lines, so clipping is off here.
	label.clip_text = false
	label.custom_minimum_size.y = VisitorProfileStyle.NOTE_ROW
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text
	# PASS rather than IGNORE, so the full line can be read on hover while
	# unhandled wheel events still travel up to the shelf's scroll.
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_child(label)


## One golfer status: its name, its reading and a wide segmented bar.
func add_meter_row(meter_name: String, value: float) -> void:
	_body.add_child(VisitorProfileStyle.MeterRow.new(meter_name, value,
		VisitorProfileStyle.meter_color(meter_name)))


## One scorecard line, parsed into hole, par, strokes and score name.
func add_score_row(line: String) -> void:
	_body.add_child(VisitorProfileStyle.ScoreRow.new(line))


## One comment: a sentiment dot and up to two lines of what the golfer said.
func add_comment_row(sentiment: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = VisitorProfileStyle.COMMENT_ROW
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(row)
	var dot := VisitorProfileStyle.Mark.new(VisitorProfileStyle.sentiment_color(sentiment))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var label := VisitorProfileStyle.make_label("\u201c%s\u201d" % text, 10,
		VisitorProfileStyle.CREAM)
	label.clip_text = false
	label.custom_minimum_size.y = VisitorProfileStyle.COMMENT_ROW
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
