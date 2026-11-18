extends RefCounted
class_name VisitorProfileRow
## Builds the whole Visiting Golfer profile as one horizontal row of cards:
## the guest-register tab, the identity card, then a card per profile section.
##
## TerrainToolbar owns when the row is shown and rebuilt; this class owns what
## the row is made of. Every card is `VisitorProfileStyle.CARD_HEIGHT` tall, so
## the row is exactly as tall as a full column of visitor plates and opening a
## profile cannot make the shelf any higher. Sections that need more room than
## one card continue in the next card to the right - the direction the shelf
## already scrolls - rather than growing the card downwards.
##
## Sections are ordered the way a reader wants them: who the golfer is, what
## the club means to them, the round in progress, then the record and the
## golfer's own account of the visit. Any section the profile data carries but
## this list does not know (a mod's) follows at the end, unchanged.


## Reading order of the profile's sections. Titles match main.gd's
## `_visitor_profile`; unknown titles keep their data order after these.
const SECTION_ORDER: Array[String] = [
	"Identity",
	"Club Membership",
	"Current Round",
	"Scorecard",
	"Golf Skills",
	"Golfer Traits",
	"Golfer Skills",
	"Golfer Statuses",
	"Golfer Comments",
	"Course Experience",
]


## The row's controls, in shelf order: [0] is always the way back, [1] always
## the identity card (whose `texture` is the shared skin snapshot).
static func build(visitor_name: String, data: Dictionary, active: bool,
		locate: Button = null, guest_count := 0) -> Array[Control]:
	var rim: Color = VisitorProfileStyle.ACTIVE_ACCENT if active else VisitorProfileStyle.PAST_ACCENT
	var controls: Array[Control] = []

	var back := VisitorRegisterTab.new()
	# The tab paints its own caption; an empty native label keeps Button from
	# adding the caption's width on top of the tab's footprint.
	back.text = ""
	back.count = guest_count
	back.tooltip_text = "Back to the guest register"
	controls.append(back)

	var identity := VisitorIdentityCard.new()
	identity.setup(visitor_name, data, active, locate)
	controls.append(identity)

	for section in _ordered_sections(data.get("profile", [])):
		for card in _section_cards(section, rim):
			controls.append(card)
	return controls


# ============================================================================
# SECTIONS
# ============================================================================

## The profile's sections in reading order, with any unknown section after the
## known ones. Duplicate titles (which the data never writes) are read once.
static func _ordered_sections(sections: Variant) -> Array:
	var ordered: Array = []
	if not sections is Array:
		return ordered
	var by_title: Dictionary = {}
	var data_order: Array[String] = []
	for section in sections:
		if not section is Dictionary:
			continue
		var title := str(section.get("title", "Profile"))
		if not by_title.has(title):
			data_order.append(title)
		by_title[title] = section
	for title in SECTION_ORDER:
		if by_title.has(title):
			ordered.append(by_title[title])
			by_title.erase(title)
	for title in data_order:
		if by_title.has(title):
			ordered.append(by_title[title])
	return ordered


## The card or cards one section needs, in order.
static func _section_cards(section: Dictionary, rim: Color) -> Array[Control]:
	var title := str(section.get("title", "Profile"))
	var tint := VisitorProfileStyle.section_color(title)
	var width := _section_width(title)
	var cards: Array[Control] = []

	if section.has("meters"):
		var meters: Dictionary = section.get("meters", {})
		var meter_rows: Array[Dictionary] = []
		var total := 0.0
		for meter_name in meters:
			var value := clampf(float(meters[meter_name]), 0.0, 1.0)
			meter_rows.append({"kind": "meter", "name": str(meter_name), "value": value,
				"height": VisitorProfileStyle.METER_ROW})
			total += value
		var meter_pages := _pack(meter_rows, VisitorProfileStyle.BODY_HEIGHT,
			VisitorProfileStyle.METERS_PER_CARD)
		for page_index in meter_pages.size():
			var card := _new_card(title, rim, tint, width, page_index, meter_pages.size())
			if total > 0.0:
				card.set_header_note("%d%%" % int(round(total / float(meters.size()) * 100.0)),
					VisitorProfileStyle.level_color(total / float(meters.size())))
			for row in meter_pages[page_index]:
				card.add_meter_row(str(row["name"]), float(row["value"]))
			cards.append(card)
		return cards

	if title.to_lower() == "golfer comments":
		return _comment_cards(title, rim, tint, width, section)

	var lines: Array = section.get("lines", [])
	if title.to_lower() == "scorecard":
		return _score_cards(title, rim, tint, width, lines)

	var rows := _line_rows(lines)
	var line_pages := _pack(rows, VisitorProfileStyle.BODY_HEIGHT,
		VisitorProfileStyle.LINES_PER_CARD)
	if line_pages.size() == 1 and line_pages[0].is_empty():
		line_pages[0].append({"kind": "note", "text": "Nothing recorded yet.",
			"height": VisitorProfileStyle.NOTE_ROW})
	for page_index in line_pages.size():
		var card := _new_card(title, rim, tint, width, page_index, line_pages.size())
		for row in line_pages[page_index]:
			match str(row.get("kind", "value")):
				"note":
					card.add_note_row(str(row.get("text", "")))
				"switch", "percent", "value":
					card.add_line_row(str(row.get("key", "")), str(row.get("value", "")),
						str(row.get("kind", "value")))
		cards.append(card)
	return cards


## The scorecard's holes, six to a card. Each row is parsed from the line
## main.gd writes ("H3: 4 strokes / par 5 / Birdie").
static func _score_cards(title: String, rim: Color, tint: Color, width: float,
		lines: Array) -> Array[Control]:
	var rows: Array[Dictionary] = []
	for line in lines:
		rows.append({"kind": "score", "text": str(line), "height": VisitorProfileStyle.SCORE_ROW})
	if rows.is_empty():
		rows.append({"kind": "note", "text": "No completed holes yet.",
			"height": VisitorProfileStyle.NOTE_ROW})
	var pages := _pack(rows, VisitorProfileStyle.BODY_HEIGHT, VisitorProfileStyle.SCORES_PER_CARD)
	var cards: Array[Control] = []
	for page_index in pages.size():
		var card := _new_card(title, rim, tint, width, page_index, pages.size())
		if page_index == 0 and rows.size() > 0 and str(rows[0].get("kind", "")) == "score":
			card.set_header_note("%d HOLES" % rows.size(), VisitorProfileStyle.MUTED)
		for row in pages[page_index]:
			if str(row.get("kind", "")) == "note":
				card.add_note_row(str(row.get("text", "")), VisitorProfileStyle.MUTED)
			else:
				card.add_score_row(str(row.get("text", "")))
		cards.append(card)
	return cards


## The golfer's own words: the tally in each card's header, three quotes a card.
static func _comment_cards(title: String, rim: Color, tint: Color, width: float,
		section: Dictionary) -> Array[Control]:
	var rows: Array[Dictionary] = []
	var tally := {"positive": 0, "neutral": 0, "negative": 0}
	for line in section.get("lines", []):
		var text := str(line)
		var parsed := _parse_tally(text)
		if not parsed.is_empty():
			tally = parsed
			continue
		var sentiment := "neutral"
		var body := text
		var colon := text.find(":")
		if colon > 0:
			sentiment = text.substr(0, colon).strip_edges().to_lower()
			body = text.substr(colon + 1).strip_edges()
		rows.append({"kind": "comment", "sentiment": sentiment, "text": body,
			"height": VisitorProfileStyle.COMMENT_ROW})
	if rows.is_empty():
		rows.append({"kind": "note", "text": "No comments yet.", "height": VisitorProfileStyle.NOTE_ROW})

	var pages := _pack(rows, VisitorProfileStyle.BODY_HEIGHT, VisitorProfileStyle.COMMENTS_PER_CARD)
	var cards: Array[Control] = []
	for page_index in pages.size():
		var card := _new_card(title, rim, tint, width, page_index, pages.size())
		if page_index == 0:
			card.set_tally(int(tally["positive"]), int(tally["neutral"]),
				int(tally["negative"]))
		for row in pages[page_index]:
			if str(row.get("kind", "")) == "note":
				card.add_note_row(str(row.get("text", "")), VisitorProfileStyle.MUTED)
			else:
				card.add_comment_row(str(row.get("sentiment", "neutral")),
					str(row.get("text", "")))
		cards.append(card)
	return cards


static func _new_card(title: String, rim: Color, tint: Color, width: float,
		page_index: int, page_count: int) -> VisitorProfileCard:
	var card := VisitorProfileCard.new(title, rim, tint, width)
	card.set_page(page_index + 1, page_count)
	return card


# ============================================================================
# ROWS
# ============================================================================

## Turn a section's lines into row descriptors. "Key: Value" lines become a
## label/value row (with a switch for On/Off and a bar for a percentage);
## anything else is a wrapped note.
static func _line_rows(lines: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw in lines:
		var line := str(raw)
		var colon := line.find(":")
		if colon <= 0:
			rows.append({"kind": "note", "text": line, "height": VisitorProfileStyle.NOTE_ROW})
			continue
		var key := line.substr(0, colon).strip_edges()
		var value := line.substr(colon + 1).strip_edges()
		var kind := "value"
		if value.to_lower() == "on" or value.to_lower() == "off":
			kind = "switch"
		elif value.ends_with("%") and value.trim_suffix("%").strip_edges().is_valid_float():
			kind = "percent"
		rows.append({"kind": kind, "key": key, "value": value,
			"height": VisitorProfileStyle.LINE_ROW})
	return rows


## Split rows into card-sized pages: as many as fit `budget` pixels high, and
## never more than `max_rows` of them. Empty input still yields one page, so a
## section always has a card of its own.
static func _pack(rows: Array[Dictionary], budget: float, max_rows: int) -> Array:
	var pages: Array = []
	var page: Array[Dictionary] = []
	var height := 0.0
	for row in rows:
		var row_height := float(row.get("height", VisitorProfileStyle.LINE_ROW))
		if not page.is_empty() and (height + row_height > budget or page.size() >= max_rows):
			pages.append(page)
			page = []
			height = 0.0
		page.append(row)
		height += row_height
	if not page.is_empty():
		pages.append(page)
	if pages.is_empty():
		pages.append([])
	return pages


## "Positive 3 / Neutral 1 / Negative 0" - the comment tally main.gd writes as
## the section's first line. Returns an empty dictionary for any other line.
static func _parse_tally(text: String) -> Dictionary:
	if not text.begins_with("Positive "):
		return {}
	var numbers: Array[int] = []
	for part in text.replace("Positive", "").replace("Neutral", "").replace("Negative", "").split("/"):
		var digits := ""
		for character in part:
			if character.is_valid_int():
				digits += character
		numbers.append(int(digits) if not digits.is_empty() else 0)
	if numbers.size() < 3:
		return {}
	return {"positive": numbers[0], "neutral": numbers[1], "negative": numbers[2]}


## How wide a section's cards are, in pixels. Wide enough for the section's
## longest natural row, narrow enough that the row keeps moving to the right.
static func _section_width(title: String) -> float:
	match title.to_lower():
		"golfer comments":
			return 280.0
		"course experience":
			return 264.0
		"scorecard":
			return 252.0
		"golf skills":
			return 242.0
		"golfer statuses":
			return 236.0
		"current round":
			return 212.0
	return 232.0
