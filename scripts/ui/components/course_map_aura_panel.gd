extends VBoxContainer
class_name CourseMapAuraPanel
## CourseMapAuraPanel - Course Aura + Course Review unified.
##
## The map paints every cell golfers have spoken in, green through amber to red.
## This panel is the reading of it: the balance of the whole course, the loudest
## happy and unhappy spots with the complaints behind them, and the holes that
## are pulling the mood down.
##
## It now also hosts the full Course Review content that previously lived in
## CourseRatingOverlay: overall star rating and category breakdown, visit
## experience summary, and evidence-based next steps (CourseAdvisor).
##
## The numbers come from CourseAura (rolling window) and CourseRatingSystem.

signal cell_selected(cell: Vector2i)
signal hole_selected(hole_number: int)
signal advice_selected(advice: Dictionary)
signal rating_updated(stars: float)

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

	# --- Course Review section (always shown) ---
	var rating := _current_rating()
	if not rating.is_empty():
		add_child(_rating_card(rating))
		# Emit for HUD status column etc.
		rating_updated.emit(float(rating.get("overall", 3.0)))
	else:
		add_child(CourseMapStyle.hint("No course data yet — start a course to see its rating."))

	add_child(_experience_card())
	add_child(_advice_card(rating))

	# --- Aura section ---
	var aura: CourseAura = GameManager.course_aura
	if aura == null or aura.samples.is_empty():
		add_child(CourseMapStyle.hint(
			"No aura comments yet. Golfers speak up as they play — run the day and the mood appears here."))
		# Still show hint about aura window if we have at least rating
		if aura != null:
			add_child(CourseMapStyle.hint(
				"Golfers only comment sometimes, so quiet ground is not the same as happy ground. "
				+ "The aura keeps the last %d comments." % CourseAura.MAX_SAMPLES))
		return

	add_child(_mood_card(aura))
	add_child(_hotspot_card(aura, "positive"))
	add_child(_hotspot_card(aura, "negative"))
	add_child(_holes_card(aura))
	add_child(CourseMapStyle.hint(
		"Golfers only comment sometimes, so quiet ground is not the same as happy ground. "
		+ "The aura keeps the last %d comments." % CourseAura.MAX_SAMPLES))

# --- Rating ------------------------------------------------------------------

func _current_rating() -> Dictionary:
	if not GameManager.current_course or not GameManager.terrain_grid:
		return {}
	return CourseRatingSystem.calculate_rating(
		GameManager.terrain_grid,
		GameManager.current_course,
		GameManager.daily_stats,
		GameManager.green_fee,
		GameManager.reputation,
		GameManager.entity_layer
	)

func _rating_card(rating: Dictionary) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.add_child(CourseMapStyle.kicker("Course review", 10))

	var stars: float = float(rating.get("overall", 3.0))
	var star_text := "%s (%.1f)" % [CourseRatingSystem.get_star_display(stars), stars]
	var overall_row := HBoxContainer.new()
	overall_row.add_theme_constant_override("separation", 6)
	var overall_label := CourseMapStyle.label("Overall:", 12, CourseMapStyle.TEXT_SECONDARY, CourseMapStyle.SUBTITLE_FONT)
	overall_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overall_row.add_child(overall_label)
	var overall_val := CourseMapStyle.label(star_text, 12, _star_color(stars), CourseMapStyle.SUBTITLE_FONT)
	overall_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	overall_row.add_child(overall_val)
	body.add_child(overall_row)

	body.add_child(_rating_row("Condition (25%):", "%.1f" % float(rating.get("condition", 0.0))))
	body.add_child(_rating_row("Design (15%):", "%.1f" % float(rating.get("design", 0.0))))
	body.add_child(_rating_row("Value (30%):", "%.1f" % float(rating.get("value", 0.0))))
	body.add_child(_rating_row("Pace (20%):", "%.1f" % float(rating.get("pace", 0.0))))
	body.add_child(_rating_row("Aesthetics (10%):", "%.1f" % float(rating.get("aesthetics", 0.0))))

	var diff: float = float(rating.get("difficulty", 5.0))
	var diff_text := "%s (%.1f)" % [CourseRatingSystem.get_difficulty_text(diff), diff]
	body.add_child(_rating_row("Difficulty:", diff_text))

	# Optional slope / course rating if present
	if rating.has("slope") or rating.has("course_rating"):
		var extra := ""
		if rating.has("slope"):
			extra += "Slope %d" % int(rating["slope"])
		if rating.has("course_rating"):
			if not extra.is_empty():
				extra += " · "
			extra += "Course rating %.1f" % float(rating["course_rating"])
		if not extra.is_empty():
			body.add_child(CourseMapStyle.label(extra, 10, CourseMapStyle.TEXT_QUIET))

	return CourseMapStyle.framed(body)

func _rating_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := CourseMapStyle.label(label_text, 11, CourseMapStyle.TEXT_SECONDARY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var val := CourseMapStyle.label(value_text, 11, CourseMapStyle.TEXT_BRIGHT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return row

func _star_color(stars: float) -> Color:
	if stars >= 4.0:
		return CourseMapStyle.GOLD
	elif stars >= 3.0:
		return CourseMapStyle.SUCCESS
	elif stars >= 2.0:
		return CourseMapStyle.WARNING
	return CourseMapStyle.DANGER

# --- Experience --------------------------------------------------------------

func _experience_card() -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.add_child(CourseMapStyle.kicker("Guest experience", 10))

	var experience_data := FeedbackManager.visit_summary()
	var satisfaction_text := ("%d%%" % int(experience_data.satisfaction * 100)) if experience_data.reviews > 0 else "awaiting rounds"
	var intent_text := ("%d%%" % int(experience_data.return_intent * 100)) if experience_data.reviews > 0 else "awaiting rounds"
	var line := "%d completed-visit reviews | %d returning guests\nVisit satisfaction: %s | Return intent: %s\n%d amenity visits | $%d service income" % [
		experience_data.reviews, experience_data.returning, satisfaction_text, intent_text, experience_data.service_visits, experience_data.service_revenue
	]
	var recent := FeedbackManager.recent_experience()
	if recent.days > 0:
		var recent_sat := ("%d%%" % int(recent.satisfaction * 100)) if recent.reviews > 0 else "unrated"
		line += "\nPrevious %d days: %s satisfaction | $%d/day operating profit" % [
			recent.days, recent_sat, int(recent.profit)
		]
	var lbl := CourseMapStyle.label(line, 11, CourseMapStyle.TEXT_SECONDARY)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.tooltip_text = "Visit satisfaction combines needs, attitude and value at the end of the round. Return intent is a forecast, not a guaranteed booking."
	body.add_child(lbl)

	if experience_data.complaints > 0:
		body.add_child(CourseMapStyle.label("%d complaints recorded today" % experience_data.complaints, 10, CourseMapStyle.TEXT_QUIET))

	return CourseMapStyle.framed(body)

# --- Advice ------------------------------------------------------------------

func _advice_card(rating: Dictionary) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.add_child(CourseMapStyle.kicker("What to improve next", 10))

	if not GameManager.terrain_grid or not GameManager.current_course:
		body.add_child(CourseMapStyle.hint("Start a course to get tailored next steps."))
		return CourseMapStyle.framed(body)

	var advice_list: Array = CourseAdvisor.review(
		GameManager.terrain_grid,
		GameManager.current_course,
		GameManager.entity_layer,
		rating,
		GameManager.daily_stats
	)

	if advice_list.is_empty():
		body.add_child(CourseMapStyle.hint("All basic checks look good. Watch a round before expanding."))
		return CourseMapStyle.framed(body)

	for advice in advice_list:
		var btn := CourseMapStyle.choice(str(advice.get("title", "Advice")) + _advice_suffix(advice), 11)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var captured: Dictionary = advice.duplicate(true)
		btn.pressed.connect(func(): advice_selected.emit(captured))
		# Tooltip from detail
		btn.tooltip_text = str(advice.get("detail", ""))
		body.add_child(btn)

		var detail := CourseMapStyle.label(str(advice.get("detail", "")), 11, CourseMapStyle.TEXT_QUIET)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(detail)

	return CourseMapStyle.framed(body)

func _advice_suffix(advice: Dictionary) -> String:
	var action := str(advice.get("action", ""))
	if action == "locate":
		return "  - Locate"
	if action in ["finance", "garden", "build", "observe"]:
		return "  - Open"
	return ""

# --- Aura Cards (original) ---------------------------------------------------

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
