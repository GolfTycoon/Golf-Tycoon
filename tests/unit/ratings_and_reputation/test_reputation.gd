extends GameTest
## The company's reputation: kept between 0 and 100, worn down a little every
## night (faster on a poorly rated course and on a harder difficulty), and worn
## down further when the course stops growing. See docs/systems/ratings-and-
## reputation/reputation.md.

const START := 60.0

func test_modify_reputation_clamps_to_max() -> void:
	GameManager.reputation = 95.0
	GameManager.modify_reputation(10.0)
	assert_eq(GameManager.reputation, 100.0, "Should clamp to 100")

func test_modify_reputation_clamps_to_min() -> void:
	GameManager.reputation = 5.0
	GameManager.modify_reputation(-10.0)
	assert_eq(GameManager.reputation, 0.0, "Should clamp to 0")

func test_modify_reputation_normal_range() -> void:
	GameManager.reputation = 50.0
	GameManager.modify_reputation(10.0)
	assert_eq(GameManager.reputation, 60.0, "Should increase normally")

func test_modify_reputation_announces_the_change() -> void:
	GameManager.reputation = 50.0
	watch_signals(EventBus)
	GameManager.modify_reputation(-5.0)
	assert_signal_emitted_with_parameters(EventBus, "reputation_changed", [50.0, 45.0])


# ---------------------------------------------------------------------------
# Daily decay
# ---------------------------------------------------------------------------

## How much reputation one night costs a course of `stars` stars that has kept
## the same holes for `days_unchanged` days.
func _overnight_loss(stars: int, difficulty: int = DifficultyPresets.Preset.NORMAL,
		days_unchanged: int = 0) -> float:
	GameManager.current_day = 100
	GameManager.current_difficulty = difficulty
	GameManager.course_rating = {"stars": stars}
	GameManager.current_course = GameManager.CourseData.new()
	GameManager._stagnation_hole_count = 0
	GameManager._stagnation_day_started = GameManager.current_day - days_unchanged
	GameManager.daily_stats = GameManager.DailyStatistics.new()
	GameManager.yearly_stats = GameManager.DailyStatistics.new()
	GameManager.reputation = START
	GameManager.advance_to_next_day()
	return START - GameManager.reputation

func test_a_poorly_rated_course_loses_reputation_fastest() -> void:
	var scale := GameManager.DAILY_RATE_SCALE
	assert_almost_eq(_overnight_loss(1), 1.0 * scale, 0.00001, "One star")
	assert_almost_eq(_overnight_loss(2), 1.0 * scale, 0.00001, "Two stars")
	assert_almost_eq(_overnight_loss(3), 0.5 * scale, 0.00001, "Three stars")
	assert_almost_eq(_overnight_loss(4), 0.25 * scale, 0.00001, "Four stars")
	assert_almost_eq(_overnight_loss(5), 0.1 * scale, 0.00001, "Five stars")

func test_difficulty_scales_the_nightly_loss() -> void:
	var normal := _overnight_loss(3)
	assert_almost_eq(_overnight_loss(3, DifficultyPresets.Preset.EASY), normal * 0.5, 0.00001,
		"Easy halves the decay")
	assert_almost_eq(_overnight_loss(3, DifficultyPresets.Preset.HARD), normal * 2.0, 0.00001,
		"Hard doubles it")

func test_a_course_that_stops_growing_loses_more() -> void:
	var growing := _overnight_loss(3, DifficultyPresets.Preset.NORMAL, 0)
	var stale := _overnight_loss(3, DifficultyPresets.Preset.NORMAL,
		GameManager.STAGNATION_DAYS_THRESHOLD + 1)
	assert_almost_eq(stale - growing,
		GameManager.STAGNATION_DECAY_PENALTY * GameManager.DAILY_RATE_SCALE, 0.00001,
		"The stagnation penalty is added once the threshold has passed")

func test_stagnation_spares_a_reputation_already_at_its_floor() -> void:
	GameManager.current_day = 100
	GameManager.current_difficulty = DifficultyPresets.Preset.NORMAL
	GameManager.course_rating = {"stars": 5}
	GameManager.current_course = GameManager.CourseData.new()
	GameManager._stagnation_hole_count = 0
	GameManager._stagnation_day_started = 0
	GameManager.daily_stats = GameManager.DailyStatistics.new()
	GameManager.yearly_stats = GameManager.DailyStatistics.new()
	GameManager.reputation = GameManager.STAGNATION_REPUTATION_FLOOR
	GameManager.advance_to_next_day()
	assert_almost_eq(GameManager.reputation,
		GameManager.STAGNATION_REPUTATION_FLOOR - 0.1 * GameManager.DAILY_RATE_SCALE, 0.00001,
		"Only the ordinary five-star decay applies at the floor")
