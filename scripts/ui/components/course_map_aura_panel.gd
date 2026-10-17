extends VBoxContainer
class_name CourseMapAuraPanel
## CourseMapAuraPanel - Course Aura: where golfers are happy and where they are not.
##
## The map paints every cell golfers have spoken in, green through amber to red.
## This panel is the reading of it: the balance of the whole course, the loudest
## happy and unhappy spots with the complaints behind them, and the holes that
## are pulling the mood down.
##
## The numbers come from CourseAura, which keeps the last CourseAura.MAX_SAMPLES
## comments a golfer made - so this is how the course is playing lately, not a
## lifetime average.

signal cell_selected(cell: Vector2i)
signal hole_selected(hole_number: int)

const HOTSPOTS := 3

var compact: bool = false
var _selected: Vector2i = Vector2i(-2, -2)

func _ready() -> void:
	refresh()

func set_selected(cell: Vector2i) -> void:
	if cell == _selected:
		return
	_selected = cell
	refresh()

func set_compact(value: bool) -> void:
	if compact == value:
		return
	compact = value
	refresh()

func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 8 if not compact else 6)
	add_child(CourseMapStyle.kicker("Course aura", 10))
	add_child(CourseMapStyle.title("How the course feels", 19 if not compact else 17))

	var aura: CourseAura = GameManager.course_aura
	if aura == null or aura.samples.is_empty():
		add_child(CourseMapStyle.hint(
			"No comments yet. Golfers speak up as they play — run the day and the mood appears here."))
		return

	add_child(_mood_card(aura))
	add_child(_hotspot_card(aura, "positive"))
	add_child(_hotspot_card(aura, "negative"))
	add_child(_holes_card(aura))
	add_child(CourseMapStyle.hint(
		"Golfers only comment sometimes, so quiet ground is not the same as happy ground. "
		+ "The aura keeps the last %d comments." % CourseAura.MAX_SAMPLES))

# --- Cards -------------------------------------------------------------------

func _mood_card(aura: CourseAura) -> Control:
	var totals := aura.totals()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	var judgement: int = int(totals["positive"]) + int(totals["negative"])
	body.add_child(CourseMapStyle.label(
		"%d comments kept · %s of them happy" % [int(totals["total"]),
			CourseMapStyle.percent(float(totals["positive"]) / float(maxi(1, judgement)))],
		12 if not compact else 11, CourseMapStyle.TEXT_BRIGHT, CourseMapStyle.SUBTITLE_FONT))
	body.add_child(CourseMapStyle.chip_row([
		{"text": "%d happy" % int(totals["positive"]), "color": CourseMapView.AURA_HAPPY},
		{"text": "%d unhappy" % int(totals["negative"]), "color": CourseMapView.AURA_UNHAPPY},
		{"text": "%d neutral" % int(totals["neutral"]), "color": CourseMapStyle.TEXT_SECONDARY},
	]))
	body.add_child(CourseMapStyle.label(
		"Course mood: %s" % _mood_name(float(totals["score"])), 11, _mood_color(float(totals["score"])),
		CourseMapStyle.SUBTITLE_FONT))
	return CourseMapStyle.framed(body)

func _hotspot_card(aura: CourseAura, sentiment: String) -> Control:
	var happy := sentiment == "positive"
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.add_child(CourseMapStyle.kicker("Happiest spots" if happy else "Trouble spots", 10))
	var spots := aura.hotspots(sentiment, HOTSPOTS)
	if spots.is_empty():
		body.add_child(CourseMapStyle.hint(
			"Nothing stands out yet — a spot needs %d comments to count." % CourseAura.HOTSPOT_MIN_SAMPLES))
		return CourseMapStyle.framed(body)
	for spot in spots:
		body.add_child(_spot_row(spot, happy))
	return CourseMapStyle.framed(body)

func _spot_row(spot: Dictionary, happy: bool) -> Control:
	var cell: Vector2i = spot["cell"]
	var counts: Dictionary = spot["counts"]
	var color := CourseMapView.AURA_HAPPY if happy else CourseMapView.AURA_UNHAPPY
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var pick := CourseMapStyle.choice("%s" % str(spot["where"]), 11)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.button_pressed = cell == _selected
	pick.tooltip_text = "Show this ground on the map"
	pick.pressed.connect(func(): cell_selected.emit(cell))
	row.add_child(pick)

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 1)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(CourseMapStyle.label(
		"%d happy · %d unhappy" % [int(counts["positive"]), int(counts["negative"])],
		11, color, CourseMapStyle.SUBTITLE_FONT))
	var triggers: Array = spot.get("triggers", [])
	if not triggers.is_empty():
		var words: Array = []
		for trigger in triggers:
			words.append("%s ×%d" % [str(trigger["label"]), int(trigger["count"])])
		detail.add_child(CourseMapStyle.label("mostly " + ", ".join(words), 10, CourseMapStyle.TEXT_QUIET))
	row.add_child(detail)
	return row

## The holes pulling the mood down (and the ones carrying it), worst first.
func _holes_card(aura: CourseAura) -> Control:
	var counts := aura.hole_counts()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.add_child(CourseMapStyle.kicker("By hole", 10))
	if counts.is_empty():
		body.add_child(CourseMapStyle.hint("No comments on any hole yet."))
		return CourseMapStyle.framed(body)

	var holes: Array = []
	for hole in counts:
		holes.append({"hole": int(hole), "counts": counts[hole]})
	holes.sort_custom(func(a, b): return float(a["counts"]["score"]) < float(b["counts"]["score"]))
	var shown: int = holes.size() if not compact else mini(4, holes.size())
	for i in shown:
		body.add_child(_hole_row(holes[i]))
	if holes.size() > shown:
		body.add_child(CourseMapStyle.label("%d more holes with comments" % (holes.size() - shown), 10,
			CourseMapStyle.TEXT_QUIET))
	return CourseMapStyle.framed(body)

func _hole_row(entry: Dictionary) -> Control:
	var hole: int = entry["hole"]
	var counts: Dictionary = entry["counts"]
	var score := float(counts["score"])
	var color := CourseMapView.aura_color(score)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var pick := CourseMapStyle.choice("Hole %d" % hole, 11)
	pick.custom_minimum_size.x = 74.0
	pick.tooltip_text = "Show hole %d on the map" % hole
	pick.pressed.connect(func(): hole_selected.emit(hole))
	row.add_child(pick)

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 1)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(CourseMapStyle.label(
		"%d happy · %d unhappy" % [int(counts["positive"]), int(counts["negative"])],
		11, color, CourseMapStyle.SUBTITLE_FONT))
	var note := _trigger_note(hole, score)
	if not note.is_empty():
		detail.add_child(CourseMapStyle.label(note, 10, CourseMapStyle.TEXT_QUIET))
	row.add_child(detail)
	return row

## What they are saying on this hole: the complaints when the hole reads badly,
## the compliments when it reads well.
func _trigger_note(hole: int, score: float) -> String:
	var aura: CourseAura = GameManager.course_aura
	if aura == null:
		return ""
	var sentiment := "negative" if score < 0.0 else "positive"
	var triggers := aura.top_triggers_for_hole(hole, sentiment, 2)
	if triggers.is_empty():
		return ""
	var words: Array = []
	for trigger in triggers:
		words.append("%s ×%d" % [str(trigger["label"]), int(trigger["count"])])
	return ("mostly " if score < 0.0 else "thanks to ") + ", ".join(words)

# --- Helpers -----------------------------------------------------------------

static func _mood_name(score: float) -> String:
	if score >= 0.5:
		return "delighted"
	if score >= 0.15:
		return "happy"
	if score > -0.15:
		return "mixed"
	if score > -0.5:
		return "grumbling"
	return "unhappy"

static func _mood_color(score: float) -> Color:
	return CourseMapView.aura_color(score)
