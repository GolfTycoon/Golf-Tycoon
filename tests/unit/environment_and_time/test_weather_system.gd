extends GameTest
## WeatherSystem: the day's weather and the spells it moves in — held until a
## spell runs its course, then moving to a neighbouring kind and easing in over
## two days — the clear skies the Weather feature leaves when it is off, and what
## each kind of weather does to the course: golfer numbers, shot accuracy, light,
## tint and the way it reads out.

const KINDS := [WeatherSystem.WeatherType.SUNNY, WeatherSystem.WeatherType.PARTLY_CLOUDY, WeatherSystem.WeatherType.CLOUDY, WeatherSystem.WeatherType.LIGHT_RAIN, WeatherSystem.WeatherType.RAIN, WeatherSystem.WeatherType.HEAVY_RAIN]

var weather: WeatherSystem


func before_each() -> void:
	super()
	seed(1234)
	GameManager.weather_enabled = true
	weather = WeatherSystem.new()
	add_child_autofree(weather)


## Settle the weather on `kind`, mid-spell.
func _settle(kind: WeatherSystem.WeatherType, spell_days: int = 100) -> void:
	weather.weather_type = kind
	weather._target_weather = kind
	weather.intensity = weather._get_base_intensity(kind)
	weather._transition_progress = 1.0
	weather._days_in_current_weather = 0
	weather._weather_duration_days = spell_days


# ---------------------------------------------------------------------------
# The day's weather
# ---------------------------------------------------------------------------

func test_a_new_day_rolls_a_kind_of_weather_and_a_spell_for_it() -> void:
	for i in range(20):
		watch_signals(EventBus)
		weather.generate_daily_weather()
		assert_has(KINDS, weather.weather_type, "The roll is a kind of weather")
		assert_eq(weather.intensity, weather._get_base_intensity(weather.weather_type),
			"at that kind's intensity")
		assert_between(weather._weather_duration_days, WeatherSystem.MIN_WEATHER_SPELL_DAYS,
			WeatherSystem.MAX_WEATHER_SPELL_DAYS, "The spell lasts days, not hours")
		assert_signal_emitted(EventBus, "weather_changed", "Everyone watching the weather hears about it")


func test_a_spell_holds_until_it_has_run_its_course() -> void:
	_settle(WeatherSystem.WeatherType.CLOUDY, 5)
	for day in range(4):
		weather.update_weather_daily()
		assert_eq(weather.weather_type, WeatherSystem.WeatherType.CLOUDY, "Day %d of a five-day spell keeps the weather" % (day + 1))
		assert_eq(weather._transition_progress, 1.0, "and starts no change")
	assert_eq(weather._days_in_current_weather, 4, "The spell counts its days")


func test_a_change_eases_in_over_two_days() -> void:
	_settle(WeatherSystem.WeatherType.SUNNY)
	weather._target_weather = WeatherSystem.WeatherType.RAIN
	weather._transition_progress = 0.0
	weather.update_weather_daily()
	assert_eq(weather.weather_type, WeatherSystem.WeatherType.SUNNY, "Halfway through a change the weather is still what it was")
	assert_almost_eq(weather.intensity, 0.3, 0.001, "but the rain is half on its way")
	weather.update_weather_daily()
	assert_eq(weather.weather_type, WeatherSystem.WeatherType.RAIN, "On the second day the rain has arrived")
	assert_almost_eq(weather.intensity, weather._get_base_intensity(WeatherSystem.WeatherType.RAIN), 0.001, "at its full intensity")


func test_weather_moves_to_a_neighbouring_kind() -> void:
	for kind in KINDS:
		for roll in range(40):
			_settle(kind)
			var next: int = weather._get_next_weather()
			assert_lte(absi(next - kind), 1, "%s moves at most one step, not to %s" % [
				weather.get_weather_text(), KINDS.find(next)])


func test_a_finished_spell_may_hold_or_move_on() -> void:
	var moved := 0
	var held := 0
	for roll in range(60):
		_settle(WeatherSystem.WeatherType.CLOUDY, 1)
		weather._days_in_current_weather = 1
		weather._maybe_change_weather()
		if weather._target_weather != WeatherSystem.WeatherType.CLOUDY:
			moved += 1
			assert_eq(weather._transition_progress, 0.0, "A change starts easing in")
			assert_eq(weather._days_in_current_weather, 0, "as a new spell")
		else:
			held += 1
			assert_eq(weather.weather_type, WeatherSystem.WeatherType.CLOUDY, "A spell that holds keeps its weather")
	assert_gt(moved, 0, "Some spells move on")
	assert_gt(held, 0, "and some hold")


func test_a_new_day_moves_the_weather_on() -> void:
	_settle(WeatherSystem.WeatherType.CLOUDY, 100)
	EventBus.day_changed.emit(GameManager.current_day + 1)
	assert_eq(weather._days_in_current_weather, 1, "The weather counts the new day")


# ---------------------------------------------------------------------------
# The Weather feature switched off
# ---------------------------------------------------------------------------

func test_with_the_feature_off_the_course_stays_clear() -> void:
	_settle(WeatherSystem.WeatherType.HEAVY_RAIN)
	GameManager.weather_enabled = false
	weather.update_weather_daily()
	assert_eq(weather.weather_type, WeatherSystem.WeatherType.SUNNY, "Switching weather off clears the sky on the next day")
	assert_eq(weather.intensity, 0.0, "to nothing at all")
	weather.generate_daily_weather()
	assert_eq(weather.weather_type, WeatherSystem.WeatherType.SUNNY, "and no new day brings any back")
	weather.weather_type = WeatherSystem.WeatherType.RAIN
	assert_eq(weather.get_spawn_rate_modifier(), 1.0, "Weather that is off keeps no golfer away")


# ---------------------------------------------------------------------------
# What weather does to the course
# ---------------------------------------------------------------------------

func test_worse_weather_keeps_golfers_away_and_spoils_their_shots() -> void:
	var previous := {"spawn": INF, "accuracy": INF, "light": INF, "tint": -INF}
	for kind in KINDS:
		_settle(kind)
		var weather_name := weather.get_weather_text()
		assert_lte(weather.get_spawn_rate_modifier(), previous.spawn, "%s keeps as many golfers away or more" % weather_name)
		assert_lte(weather.get_accuracy_modifier(), previous.accuracy, "%s makes shots no easier" % weather_name)
		assert_lte(weather.get_light_modifier(), previous.light, "%s is no brighter" % weather_name)
		assert_gte(weather.get_sky_tint().a, previous.tint, "%s tints the sky as much or more" % weather_name)
		assert_eq(weather.is_raining(), kind >= WeatherSystem.WeatherType.LIGHT_RAIN, "%s is rain or not" % weather_name)
		previous = {"spawn": weather.get_spawn_rate_modifier(), "accuracy": weather.get_accuracy_modifier(),
			"light": weather.get_light_modifier(), "tint": weather.get_sky_tint().a}
	assert_eq(previous.spawn, 0.3, "Heavy rain keeps seven golfers in ten away")
	assert_eq(previous.accuracy, 0.85, "and costs 15% of a shot's accuracy")


func test_every_kind_of_weather_has_a_name_and_an_icon() -> void:
	var names := {}
	var icons := {}
	for kind in KINDS:
		_settle(kind)
		names[weather.get_weather_text()] = true
		icons[weather.get_weather_icon()] = true
	assert_eq(names.size(), KINDS.size(), "Every kind of weather has a name of its own")
	assert_eq(icons.size(), KINDS.size(), "and an icon of its own")
	assert_false(names.has("Unknown"), "None of them is unknown")
