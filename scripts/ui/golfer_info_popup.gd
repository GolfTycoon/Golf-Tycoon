extends CenteredPanel
class_name GolferInfoPopup
## Popup panel showing golfer scorecard and stats when clicking a golfer.

signal close_requested

var _golfer: Golfer = null
var _content_vbox: VBoxContainer = null
var _title_label: Label = null
var _tier_label: Label = null

const TIER_COLORS := {
	0: UIConstants.COLOR_SUCCESS_MUTED,  # BEGINNER - light green
	1: UIConstants.COLOR_BLUE_SOFT,      # CASUAL - blue
	2: UIConstants.COLOR_GOLD_DIM,       # SERIOUS - gold
	3: UIConstants.COLOR_PURPLE,         # PRO - purple
}

func _build_ui() -> void:
	custom_minimum_size = Vector2(360, 560)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	_tier_label = Label.new()
	_tier_label.add_theme_font_size_override("font_size", 12)
	title_row.add_child(_tier_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func(): close_requested.emit())
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	# Scrollable content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 4)
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content_vbox)

func _ready() -> void:
	super._ready()
	EventBus.golfer_finished_hole.connect(_on_golfer_finished_hole)
	EventBus.golfer_left_course.connect(_on_golfer_left)

func _exit_tree() -> void:
	if EventBus.golfer_finished_hole.is_connected(_on_golfer_finished_hole):
		EventBus.golfer_finished_hole.disconnect(_on_golfer_finished_hole)
	if EventBus.golfer_left_course.is_connected(_on_golfer_left):
		EventBus.golfer_left_course.disconnect(_on_golfer_left)

func _on_golfer_finished_hole(golfer_id: int, _hole: int, _strokes: int, _par: int) -> void:
	if visible and _golfer and _golfer.golfer_id == golfer_id:
		_update_display()

func _on_golfer_left(golfer_id: int) -> void:
	if visible and _golfer and _golfer.golfer_id == golfer_id:
		_golfer = null
		hide()
		close_requested.emit()

func show_for_golfer(golfer: Golfer) -> void:
	_golfer = golfer
	_update_display()
	show_centered()

func _update_display() -> void:
	if not _golfer:
		return

	_title_label.text = _golfer.golfer_name + (" (returning)" if _golfer.is_returning_guest else "")
	var tier_name = GolferTier.get_tier_name(_golfer.golfer_tier)
	_tier_label.text = tier_name
	var tier_color = TIER_COLORS.get(_golfer.golfer_tier, Color.WHITE)
	_tier_label.add_theme_color_override("font_color", tier_color)

	# Clear existing content
	for child in _content_vbox.get_children():
		child.queue_free()

	var attributes: GolferAttributes = _golfer.attributes

	# Identity: Profession, Age, Gender, Marital Status
	_content_vbox.add_child(_create_stat_row("Profession", attributes.profession, UIConstants.COLOR_TEXT))
	_content_vbox.add_child(_create_stat_row("Age / Gender",
		"%d · %s" % [attributes.age, attributes.gender_name()], UIConstants.COLOR_TEXT))
	_content_vbox.add_child(_create_stat_row("Marital Status", attributes.marital_status_name(), UIConstants.COLOR_TEXT))

	_content_vbox.add_child(HSeparator.new())

	# Golfer Traits (On/Off)
	_content_vbox.add_child(_create_section_label("Golfer Traits"))
	var traits_row := HFlowContainer.new()
	traits_row.add_theme_constant_override("h_separation", 4)
	for key in GolferAttributes.TRAIT_KEYS:
		traits_row.add_child(_create_chip(GolferAttributes.TRAIT_NAMES[key], attributes.trait_on(key)))
	_content_vbox.add_child(traits_row)

	# Golfer Skills (On/Off)
	_content_vbox.add_child(_create_section_label("Golfer Skills"))
	var golfer_skills_row := HFlowContainer.new()
	golfer_skills_row.add_theme_constant_override("h_separation", 4)
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		golfer_skills_row.add_child(_create_chip(GolferAttributes.GOLFER_SKILL_NAMES[key], attributes.skill_on(key)))
	_content_vbox.add_child(golfer_skills_row)

	_content_vbox.add_child(HSeparator.new())

	# Golf Skills (points; each point is +10%, up to 990%)
	_content_vbox.add_child(_create_section_label("Golf Skills"))
	for i in GolferAttributes.GOLF_SKILLS.size():
		_content_vbox.add_child(_create_stat_row(
			GolferAttributes.GOLF_SKILLS[i],
			"%d%%" % attributes.golf_skill_percent(i),
			_get_golf_skill_color(attributes.golf_skill_percent(i))))

	_content_vbox.add_child(HSeparator.new())

	# Golfer Statuses - each starts the course at 50%
	_content_vbox.add_child(_create_section_label("Golfer Statuses"))
	_content_vbox.add_child(_create_need_bar("Fun", attributes.fun))
	_content_vbox.add_child(_create_need_bar("Attitude", attributes.attitude))
	_content_vbox.add_child(_create_need_bar("Energy", attributes.energy))
	_content_vbox.add_child(_create_need_bar("Hunger", attributes.hunger))
	_content_vbox.add_child(_create_need_bar("Thirst", attributes.thirst))

	_content_vbox.add_child(HSeparator.new())

	# Golfer Comments (Positive, Neutral, Negative)
	var positive_comments: int = int(attributes.comment_counts.get("positive", 0))
	var neutral_comments: int = int(attributes.comment_counts.get("neutral", 0))
	var negative_comments: int = int(attributes.comment_counts.get("negative", 0))
	_content_vbox.add_child(_create_section_label("Golfer Comments"))
	var counts_label := Label.new()
	counts_label.text = "Positive %d · Neutral %d · Negative %d" % [
		positive_comments, neutral_comments, negative_comments]
	counts_label.add_theme_font_size_override("font_size", 11)
	_content_vbox.add_child(counts_label)
	for comment in attributes.recent_comments(5):
		_content_vbox.add_child(_create_comment_row(str(comment.get("text", "")),
			str(comment.get("sentiment", "neutral"))))

	_content_vbox.add_child(HSeparator.new())

	var experience := Label.new()
	experience.text = "%s\nTraffic wait: %.1f game minutes | Amenities used: %d\n%s" % [_golfer.activity_text,_golfer.traffic_wait_seconds * 60.0 / GameManager.SECONDS_PER_GAME_HOUR,_golfer.amenities_used,FeedbackManager.guest_incident_text(_golfer.golfer_id)]
	experience.custom_minimum_size.x = 280
	experience.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	experience.add_theme_font_size_override("font_size",12)
	_content_vbox.add_child(experience)
	# Skills section
	var skills_label := Label.new()
	skills_label.text = "Playing Skills"
	skills_label.add_theme_font_size_override("font_size", 13)
	_content_vbox.add_child(skills_label)

	_content_vbox.add_child(_create_skill_bar("Driving", _golfer.driving_skill))
	_content_vbox.add_child(_create_skill_bar("Accuracy", _golfer.accuracy_skill))
	_content_vbox.add_child(_create_skill_bar("Putting", _golfer.putting_skill))
	_content_vbox.add_child(_create_skill_bar("Recovery", _golfer.recovery_skill))

	_content_vbox.add_child(HSeparator.new())

	# Current round summary
	var score_vs_par = _golfer.total_strokes - _golfer.total_par
	var score_text = "%d (%s%d)" % [_golfer.total_strokes, "+" if score_vs_par > 0 else "", score_vs_par] if _golfer.total_par > 0 else "Not started"
	if score_vs_par == 0 and _golfer.total_par > 0:
		score_text = "%d (E)" % _golfer.total_strokes

	_content_vbox.add_child(_create_stat_row("Score", score_text, _get_score_color(score_vs_par)))
	_content_vbox.add_child(_create_stat_row("Hole", "%d" % (_golfer.current_hole + 1), UIConstants.COLOR_TEXT))
	_content_vbox.add_child(_create_stat_row("Mood", _get_mood_text(_golfer.current_mood), _get_mood_color(_golfer.current_mood)))

	_content_vbox.add_child(HSeparator.new())

	# Scorecard (hole-by-hole)
	if _golfer.hole_scores.size() > 0:
		var scorecard_label := Label.new()
		scorecard_label.text = "Scorecard"
		scorecard_label.add_theme_font_size_override("font_size", 13)
		_content_vbox.add_child(scorecard_label)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 2)
		_content_vbox.add_child(grid)

		for score_data in _golfer.hole_scores:
			var hole_label := Label.new()
			hole_label.text = "H%d" % (score_data.hole + 1)
			hole_label.add_theme_font_size_override("font_size", 11)
			hole_label.custom_minimum_size = Vector2(35, 0)
			grid.add_child(hole_label)

			var strokes_label := Label.new()
			var diff = score_data.strokes - score_data.par
			strokes_label.text = "%d" % score_data.strokes
			strokes_label.add_theme_font_size_override("font_size", 11)
			strokes_label.add_theme_color_override("font_color", _get_hole_score_color(diff))
			strokes_label.custom_minimum_size = Vector2(25, 0)
			grid.add_child(strokes_label)

			var name_label := Label.new()
			name_label.text = GolfRules.get_score_name(score_data.strokes, score_data.par)
			name_label.add_theme_font_size_override("font_size", 11)
			name_label.add_theme_color_override("font_color", _get_hole_score_color(diff))
			grid.add_child(name_label)

func _create_section_label(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 13)
	return label

## An On/Off chip for a Golfer Trait or Golfer Skill.
func _create_chip(chip_name: String, is_on: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UIConstants.COLOR_SUCCESS_MUTED if is_on else UIConstants.COLOR_BG_BUTTON
	style.set_corner_radius_all(8)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = "%s: %s" % [chip_name, "On" if is_on else "Off"]
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color",
		Color(0.1, 0.25, 0.12) if is_on else UIConstants.COLOR_TEXT_DIM)
	panel.add_child(label)
	return panel

## One comment line, coloured by its sentiment (Positive, Neutral, Negative).
func _create_comment_row(text: String, sentiment: String) -> Label:
	var label := Label.new()
	label.text = "• %s" % text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 280
	label.add_theme_font_size_override("font_size", 11)
	match sentiment:
		"positive":
			label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS_MUTED)
		"negative":
			label.add_theme_color_override("font_color", UIConstants.COLOR_MOOD_UNHAPPY)
		_:
			label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	return label

## Colour for a Golf Skill percentage: brighter as the skill grows.
func _get_golf_skill_color(percent: int) -> Color:
	if percent >= 300:
		return UIConstants.COLOR_SUCCESS_MUTED
	if percent >= 100:
		return UIConstants.COLOR_BLUE_SOFT
	return UIConstants.COLOR_TEXT

func _create_skill_bar(skill_name: String, value: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = skill_name
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size = Vector2(65, 0)
	row.add_child(label)

	# Background bar
	var bg := ColorRect.new()
	bg.color = UIConstants.COLOR_BG_BUTTON
	bg.custom_minimum_size = Vector2(140, 12)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bg)

	# Fill bar (added as child of bg)
	var fill := ColorRect.new()
	var bar_color = UIConstants.COLOR_SCORE_BIRDIE.lerp(UIConstants.COLOR_SCORE_DOUBLE, 1.0 - value)
	fill.color = bar_color
	fill.custom_minimum_size = Vector2(140.0 * value, 12)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bg.add_child(fill)

	var val_label := Label.new()
	val_label.text = "%d" % int(value * 100)
	val_label.add_theme_font_size_override("font_size", 11)
	val_label.custom_minimum_size = Vector2(30, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_label)

	return row

func _create_need_bar(need_name: String, value: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = need_name
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size = Vector2(65, 0)
	row.add_child(label)

	var bg := ColorRect.new()
	bg.color = UIConstants.COLOR_BG_BUTTON
	bg.custom_minimum_size = Vector2(140, 12)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bg)

	var fill := ColorRect.new()
	if value > 0.5:
		fill.color = UIConstants.COLOR_MOOD_HAPPY
	elif value > 0.3:
		fill.color = UIConstants.COLOR_MOOD_NEUTRAL
	else:
		fill.color = UIConstants.COLOR_MOOD_UNHAPPY
	fill.custom_minimum_size = Vector2(140.0 * value, 12)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bg.add_child(fill)

	var val_label := Label.new()
	val_label.text = "%d%%" % int(value * 100)
	val_label.add_theme_font_size_override("font_size", 11)
	val_label.custom_minimum_size = Vector2(35, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_label)

	return row

func _create_stat_row(label_text: String, value_text: String, value_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", value_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	return row

func _get_score_color(diff: int) -> Color:
	return UIConstants.get_score_color(diff)

func _get_hole_score_color(diff: int) -> Color:
	return UIConstants.get_score_color(diff)

func _get_mood_text(mood: float) -> String:
	if mood >= 0.8: return "Happy"
	if mood >= 0.6: return "Content"
	if mood >= 0.4: return "Neutral"
	if mood >= 0.2: return "Unhappy"
	return "Frustrated"

func _get_mood_color(mood: float) -> Color:
	if mood >= 0.6: return UIConstants.COLOR_MOOD_HAPPY
	if mood >= 0.4: return UIConstants.COLOR_MOOD_NEUTRAL
	return UIConstants.COLOR_MOOD_UNHAPPY
