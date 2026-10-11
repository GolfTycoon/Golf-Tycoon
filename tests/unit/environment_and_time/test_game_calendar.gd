extends GameTest
## The game calendar: day 1 is Saturday 1 January 2000, and GameManager shows the
## current day as a date and rolls it over into the next one.

func test_day_one_is_saturday_first_january_2000() -> void:
	var date := GameCalendar.get_date(1)
	assert_eq(int(date["year"]), 2000)
	assert_eq(int(date["month"]), 1)
	assert_eq(int(date["day"]), 1)
	assert_eq(GameCalendar.get_weekday(1), 6, "1 Jan 2000 was a Saturday")
	assert_eq(GameCalendar.format_date(1), "Sat 1 Jan 2000")

func test_february_first_is_day_32() -> void:
	assert_eq(GameCalendar.format_date(32), "Tue 1 Feb 2000")
	assert_eq(GameCalendar.get_month(32), 2)
	assert_eq(GameCalendar.get_day_of_month(32), 1)

func test_leap_day_2000() -> void:
	assert_eq(GameCalendar.format_date(60), "Tue 29 Feb 2000")
	assert_true(GameCalendar.is_leap_year(2000))
	assert_eq(GameCalendar.get_days_in_year(2000), 366)

func test_year_2001_starts_on_day_367() -> void:
	assert_eq(GameCalendar.format_date(366), "Sun 31 Dec 2000")
	assert_eq(GameCalendar.get_year(366), 2000)
	assert_eq(GameCalendar.format_date(367), "Mon 1 Jan 2001")
	assert_eq(GameCalendar.get_year(367), 2001)
	assert_false(GameCalendar.is_leap_year(2001))

func test_get_date_clamps_pre_epoch_days() -> void:
	var clamped := GameCalendar.get_date(-30)
	assert_eq(int(clamped["year"]), 2000)
	assert_eq(int(clamped["month"]), 1)
	assert_eq(int(clamped["day"]), 1)

func test_get_date_raw_keeps_pre_epoch_winter() -> void:
	# Winter containing day 1 starts on 1 Dec 1999 = game day -30.
	var raw := GameCalendar.get_date_raw(-30)
	assert_eq(int(raw["year"]), 1999)
	assert_eq(int(raw["month"]), 12)
	assert_eq(int(raw["day"]), 1)


# ---------------------------------------------------------------------------
# The date GameManager shows
# ---------------------------------------------------------------------------

func test_legacy_hour_scale_is_available_for_round_duration_ui() -> void:
	assert_eq(GameManager.SECONDS_PER_GAME_HOUR, 120.0,
		"Round UI should be able to convert simulation seconds to game minutes")
	assert_eq(GameManager.LEGACY_DAY_SECONDS, 14.0 * GameManager.SECONDS_PER_GAME_HOUR,
		"The legacy day scale should stay consistent with its hourly scale")

func test_new_game_starts_on_january_first_2000() -> void:
	GameManager.new_game("Test Course")
	assert_eq(GameManager.current_day, 1, "New games start on day 1")
	assert_eq(GameManager.get_date_string(), "Sat 1 Jan 2000", "Day 1 is Saturday 1 January 2000")

func test_day_rollover_advances_calendar_date() -> void:
	GameManager.new_game("Test Course")
	# Day 1 = 1 Jan 2000, so day 32 = 1 Feb 2000 (2000 is a leap year).
	GameManager.current_day = 32
	assert_eq(GameManager.get_date_string(), "Tue 1 Feb 2000")

func test_day_rollover_crosses_year_boundary() -> void:
	GameManager.new_game("Test Course")
	# 2000 has 366 days, so day 367 = 1 Jan 2001.
	GameManager.current_day = 367
	assert_eq(GameManager.get_date_string(), "Mon 1 Jan 2001")
	assert_eq(GameManager.get_current_year(), 2001)

func test_get_date_string_formats_weekday() -> void:
	GameManager.new_game("Test Course")
	GameManager.current_day = 7  # Friday 7 Jan 2000
	assert_eq(GameCalendar.get_weekday(7), 5, "Jan 7 2000 was a Friday")
	assert_eq(GameManager.get_date_string(), "Fri 7 Jan 2000")
