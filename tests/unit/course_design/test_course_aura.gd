extends GameTest
## Course Aura: where golfers have spoken on the course, and how they felt.
##
## The aura is a rolling window of the newest comments, binned into square cells,
## so these cover the cell maths, the tallies, the window, the hotspot threshold
## and the plain-English trigger names the Course Map's Aura mode reads out.

const SLOW_PACE := FeedbackTriggers.TriggerType.SLOW_PACE
const GREAT_SHOT := FeedbackTriggers.TriggerType.GREAT_SHOT
const NICE_COURSE := FeedbackTriggers.TriggerType.NICE_COURSE
const COURSE_MESSY := FeedbackTriggers.TriggerType.COURSE_MESSY


func _aura() -> CourseAura:
	var aura := CourseAura.new()
	add_child_autofree(aura)
	return aura


func _course_with_holes() -> void:
	var course := GameManager.CourseData.new()
	course.add_hole(make_hole(1, Vector2i(10, 10), Vector2i(30, 10)))
	course.add_hole(make_hole(2, Vector2i(40, 20), Vector2i(70, 40)))
	GameManager.current_course = course


# ---------------------------------------------------------------------------
# Cells
# ---------------------------------------------------------------------------

func test_cells_are_four_tiles_a_side() -> void:
	assert_eq(CourseAura.cell_of(Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(CourseAura.cell_of(Vector2i(3, 3)), Vector2i(0, 0), "the last tile of the first cell")
	assert_eq(CourseAura.cell_of(Vector2i(4, 0)), Vector2i(1, 0), "the first tile of the next cell")
	assert_eq(CourseAura.cell_of(Vector2i(17, 9)), Vector2i(4, 2))


func test_cells_floor_towards_negative_tiles() -> void:
	# int() truncates towards zero, which would fold everything west and north
	# of the origin into cell 0 with the tiles beside it.
	assert_eq(CourseAura.cell_of(Vector2i(-1, -1)), Vector2i(-1, -1))
	assert_eq(CourseAura.cell_of(Vector2i(-4, -5)), Vector2i(-1, -2))


func test_a_cell_centre_is_the_middle_of_its_tiles() -> void:
	assert_eq(CourseAura.cell_center(Vector2i(0, 0)), Vector2(2.0, 2.0))
	assert_eq(CourseAura.cell_center(Vector2i(2, 1)), Vector2(10.0, 6.0))


func test_a_comment_lands_in_the_cell_it_was_made_in() -> void:
	var aura := _aura()
	aura.record_at(Vector2i(6, 2), GREAT_SHOT, "positive")
	assert_eq(aura.sample_count(), 1)
	var cells := aura.cell_counts()
	assert_true(cells.has(Vector2i(1, 0)), "tile 6,2 is in cell 1,0")
	assert_eq(int(cells[Vector2i(1, 0)]["positive"]), 1)
	assert_eq(int(cells[Vector2i(1, 0)]["total"]), 1)


func test_a_cell_with_nothing_said_in_it_is_neutral() -> void:
	var aura := _aura()
	assert_eq(aura.cell_counts(), {}, "nothing heard yet")
	assert_eq(aura.cell_score(Vector2i(0, 0)), 0.0)
	assert_eq(aura.totals()["total"], 0)


func test_a_cells_score_is_the_balance_of_feeling_in_it() -> void:
	var aura := _aura()
	for i in 3:
		aura.record_at(Vector2i(1, 1), NICE_COURSE, "positive")
	aura.record_at(Vector2i(2, 2), COURSE_MESSY, "negative")
	assert_almost_eq(aura.cell_score(Vector2i(0, 0)), 0.5, 0.001,
		"three happy to one complaint reads as +0.5")

	var level := _aura()
	level.record_at(Vector2i(0, 0), NICE_COURSE, "positive")
	level.record_at(Vector2i(0, 0), COURSE_MESSY, "negative")
	assert_almost_eq(level.cell_score(Vector2i(0, 0)), 0.0, 0.001, "one each way is level")


func test_neutral_comments_are_counted_but_do_not_move_the_score() -> void:
	var aura := _aura()
	aura.record_at(Vector2i(0, 0), NICE_COURSE, "positive")
	aura.record_at(Vector2i(0, 0), SLOW_PACE, "neutral")
	var counts: Dictionary = aura.cell_counts()[Vector2i(0, 0)]
	assert_eq(int(counts["neutral"]), 1)
	assert_eq(int(counts["total"]), 2)
	assert_eq(float(counts["score"]), 1.0, "a neutral comment is not a complaint")


func test_an_unknown_sentiment_counts_as_neutral() -> void:
	var aura := _aura()
	aura.record_at(Vector2i(0, 0), SLOW_PACE, "grumpy")
	assert_eq(int(aura.cell_counts()[Vector2i(0, 0)]["neutral"]), 1)


# ---------------------------------------------------------------------------
# The window
# ---------------------------------------------------------------------------

func test_the_aura_keeps_only_the_newest_comments() -> void:
	var aura := _aura()
	for i in CourseAura.MAX_SAMPLES + 25:
		# The first tile is only ever commented on at the start of the run.
		aura.record_at(Vector2i(0, 0) if i == 0 else Vector2i(64, 64), NICE_COURSE, "positive")
	assert_eq(aura.sample_count(), CourseAura.MAX_SAMPLES, "the window is capped")
	assert_false(aura.cell_counts().has(Vector2i(0, 0)),
		"the oldest comment fell out of the window with its cell")
	assert_true(aura.cell_counts().has(CourseAura.cell_of(Vector2i(64, 64))))


func test_clearing_the_aura_empties_the_window() -> void:
	var aura := _aura()
	aura.record_at(Vector2i(3, 3), GREAT_SHOT, "positive")
	aura.clear()
	assert_eq(aura.sample_count(), 0)
	assert_eq(aura.cell_counts(), {})


# ---------------------------------------------------------------------------
# Hotspots
# ---------------------------------------------------------------------------

func test_a_cell_needs_three_comments_before_it_is_a_hotspot() -> void:
	var aura := _aura()
	aura.record_at(Vector2i(1, 1), COURSE_MESSY, "negative")
	aura.record_at(Vector2i(2, 2), COURSE_MESSY, "negative")
	assert_eq(aura.hotspots("negative").size(), 0, "two complaints is not a hotspot yet")
	aura.record_at(Vector2i(3, 3), COURSE_MESSY, "negative")
	var spots := aura.hotspots("negative")
	assert_eq(spots.size(), 1, "the third tips it over")
	if spots.size() == 1:
		assert_eq(Vector2i(spots[0]["cell"]), Vector2i(0, 0))
		assert_eq(int(spots[0]["counts"]["negative"]), 3)
		assert_eq(int(spots[0]["hole"]), 0, "no hole was named, so no hole is reported")


func test_hotspots_are_ranked_by_the_feeling_being_looked_for() -> void:
	var aura := _aura()
	for i in 5:
		aura.record_at(Vector2i(20, 20), COURSE_MESSY, "negative")
	for i in 3:
		aura.record_at(Vector2i(60, 60), COURSE_MESSY, "negative")
	aura.record_at(Vector2i(61, 61), NICE_COURSE, "positive")
	var worst := aura.hotspots("negative", 2)
	assert_eq(worst.size(), 2)
	assert_eq(Vector2i(worst[0]["cell"]), Vector2i(5, 5), "the loudest complaint spot leads")
	assert_eq(Vector2i(worst[1]["cell"]), Vector2i(15, 15))

	var best := aura.hotspots("positive", 2)
	assert_eq(best.size(), 1, "only the mixed cell has a happy comment in a busy enough spot")
	assert_almost_eq(float(best[0]["score"]), -0.5, 0.001, "one happy to three complaints leans unhappy")


func test_a_hotspot_names_the_triggers_behind_it_in_plain_english() -> void:
	var aura := _aura()
	for i in 3:
		aura.record_at(Vector2i(8, 8), SLOW_PACE, "negative")
	aura.record_at(Vector2i(8, 8), COURSE_MESSY, "negative")
	aura.record_at(Vector2i(8, 8), COURSE_MESSY, "negative")
	var triggers := aura.top_triggers(Vector2i(2, 2), "negative", 2)
	assert_eq(triggers.size(), 2)
	assert_eq(str(triggers[0]["label"]), "Slow play", "the trigger heard most often leads")
	assert_eq(int(triggers[0]["count"]), 3)
	assert_eq(str(triggers[1]["label"]), "Weeds")
	assert_eq(int(triggers[1]["count"]), 2)
	assert_eq(triggers[0]["label"], CourseAura.trigger_label(SLOW_PACE),
		"the words come from the aura's own trigger table")


func test_the_trigger_behind_a_hole_is_the_one_heard_most_there() -> void:
	var aura := _aura()
	for i in 3:
		aura.record_at(Vector2i(12, 4), SLOW_PACE, "negative", 2)
	aura.record_at(Vector2i(14, 4), COURSE_MESSY, "negative", 2)
	aura.record_at(Vector2i(20, 9), SLOW_PACE, "negative", 3)
	var on_two := aura.top_triggers_for_hole(2, "negative", 2)
	assert_eq(on_two.size(), 2)
	assert_eq(str(on_two[0]["label"]), "Slow play")
	assert_eq(int(on_two[0]["count"]), 3)
	assert_eq(aura.top_triggers_for_hole(3, "negative", 1).size(), 1)
	assert_eq(aura.top_triggers_for_hole(9, "negative", 1).size(), 0, "nothing heard on hole 9")


func test_trigger_names_come_from_the_feedback_enum() -> void:
	assert_eq(CourseAura.trigger_name(SLOW_PACE), "SLOW_PACE")
	assert_eq(CourseAura.trigger_label(SLOW_PACE), "Slow play")
	assert_eq(CourseAura.trigger_label(COURSE_MESSY), "Weeds")
	assert_eq(CourseAura.trigger_label(9999), CourseAura.TRIGGER_FALLBACK,
		"a trigger this table has not met yet still reads as a word")


# ---------------------------------------------------------------------------
# Holes and words
# ---------------------------------------------------------------------------

func test_comments_are_tallied_per_hole() -> void:
	var aura := _aura()
	for i in 3:
		aura.record_at(Vector2i(4, 4), NICE_COURSE, "positive", 1)
	aura.record_at(Vector2i(4, 4), COURSE_MESSY, "negative", 2)
	var holes := aura.hole_counts()
	assert_eq(holes.size(), 2)
	assert_eq(int(holes[1]["positive"]), 3)
	assert_almost_eq(float(holes[1]["score"]), 1.0, 0.001)
	assert_almost_eq(float(holes[2]["score"]), -1.0, 0.001)
	assert_false(holes.has(3), "a hole nobody commented on is not listed")


func test_an_aura_cell_is_described_by_the_hole_landmark_it_is_nearest() -> void:
	_course_with_holes()
	var aura := _aura()
	aura.record_at(Vector2i(70, 40), GREAT_SHOT, "positive", 2)
	assert_eq(aura.describe(CourseAura.cell_of(Vector2i(70, 40))), "Hole 2 green")
	assert_eq(aura.describe(CourseAura.cell_of(Vector2i(11, 10))), "Hole 1 tee")
	assert_eq(aura.dominant_hole(CourseAura.cell_of(Vector2i(70, 40))), 2)


func test_without_a_course_a_cell_is_described_by_the_tiles_it_covers() -> void:
	GameManager.current_course = null
	var aura := _aura()
	assert_eq(aura.describe(Vector2i(1, 2)), "Tiles 4-7, 8-11")


func test_the_whole_course_mood_reads_as_a_balance() -> void:
	var aura := _aura()
	for i in 3:
		aura.record_at(Vector2i(4, 4), NICE_COURSE, "positive")
	aura.record_at(Vector2i(40, 40), COURSE_MESSY, "negative")
	aura.record_at(Vector2i(44, 44), SLOW_PACE, "neutral")
	var totals: Dictionary = aura.totals()
	assert_eq(int(totals["positive"]), 3)
	assert_eq(int(totals["negative"]), 1)
	assert_eq(int(totals["neutral"]), 1)
	assert_eq(int(totals["total"]), 5)
	assert_almost_eq(float(totals["score"]), 0.5, 0.001)


# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------

func test_the_aura_survives_a_save_and_load_round_trip() -> void:
	_course_with_holes()
	var aura := _aura()
	for i in 3:
		aura.record_at(Vector2i(6, 2), SLOW_PACE, "negative", 2, 7)
	aura.record_at(Vector2i(64, 64), NICE_COURSE, "positive", 1, 8)
	var saved := aura.serialize()

	var loaded := _aura()
	loaded.deserialize(saved)
	assert_eq(loaded.sample_count(), 4)
	assert_eq(loaded.cell_counts(), aura.cell_counts())
	assert_eq(loaded.hole_counts(), aura.hole_counts())
	assert_eq(int(loaded.samples[0]["day"]), 7, "the day a comment was made comes back too")
	assert_eq(loaded.top_triggers(Vector2i(1, 0), "negative", 1),
		aura.top_triggers(Vector2i(1, 0), "negative", 1))


func test_a_save_without_an_aura_starts_empty() -> void:
	var aura := _aura()
	aura.record_at(Vector2i(1, 1), NICE_COURSE, "positive")
	aura.deserialize({})
	assert_eq(aura.sample_count(), 0)
