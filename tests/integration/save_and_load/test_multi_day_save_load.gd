extends MainSceneTest
## Several days on the Quick Start course, then a save: days roll over on their
## own and each one closed lands in the history; a save keeps the balance and the
## history exactly; loading the same save again pays nothing out twice; and the
## golfers arrive and play again after the load.

const SAVE_NAME := "integration_multi_day"
const DAYS := 3
## Frames a game day may take at Ultra speed before the test gives up.
const DAY_FRAMES := 1500

var days_closed: Array[int] = []
var holes_finished := 0


func before_all() -> void:
	await super()
	seed(74109)
	EventBus.end_of_day.connect(_on_end_of_day)
	EventBus.golfer_finished_hole.connect(_on_golfer_finished_hole)
	await quick_start("Multi-day")


func after_all() -> void:
	EventBus.end_of_day.disconnect(_on_end_of_day)
	EventBus.golfer_finished_hole.disconnect(_on_golfer_finished_hole)
	SaveManager.delete_save(SAVE_NAME)
	super()


func _on_end_of_day(day: int) -> void:
	days_closed.append(day)


func _on_golfer_finished_hole(_golfer_id: int, _hole: int, _strokes: int, _par: int) -> void:
	holes_finished += 1


func _simulate() -> void:
	if GameManager.current_mode != GameManager.GameMode.SIMULATING:
		main._on_mode_toggle_pressed()
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)


## A year-end summary pauses the game until it is dismissed.
func _dismiss_year_summary() -> void:
	var summary = main.get_node_or_null("UI/HUD/YearSummary")
	if summary:
		summary.continue_pressed.emit()


func test_days_roll_over_on_their_own_and_are_recorded() -> void:
	assert_eq(GameManager.current_course.holes.size(), 9, "Quick Start opens nine holes")
	var history := GameManager.daily_history.size()
	days_closed.clear()
	_simulate()
	for day in range(DAYS):
		# An overpriced middle day tries the demand trade-off on the way.
		GameManager.set_green_fee(20 if day == 1 else 5)
		var current := GameManager.current_day
		var rolled := await process_frames_until(func() -> bool:
			_dismiss_year_summary()
			return GameManager.current_day != current, DAY_FRAMES)
		assert_true(rolled, "Day %d finishes without intervention" % current)
	assert_eq(days_closed.size(), DAYS, "Every day that ended was closed once")
	assert_eq(GameManager.daily_history.size(), mini(history + DAYS, GameManager.MAX_DAILY_HISTORY),
		"and recorded in the history")


func test_a_save_keeps_the_balance_and_the_history() -> void:
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	var balance := GameManager.money
	var history: Array = GameManager.daily_history.duplicate(true)
	SaveManager._apply_save_data(SaveManager._build_save_data())
	assert_eq(GameManager.money, balance, "The balance survives the save")
	assert_eq(GameManager.daily_history.size(), history.size(), "and so does the history")
	if GameManager.daily_history.size() == history.size() and not history.is_empty():
		assert_eq(GameManager.daily_history[-1].get("day"), history[-1].get("day"), "down to its last day")


func test_loading_the_same_save_twice_pays_nothing_twice() -> void:
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	assert_true(SaveManager.save_game(SAVE_NAME), "The game saves")
	var saved := GameManager.money
	assert_true(SaveManager.load_game(SAVE_NAME), "and loads")
	main._on_main_menu_load_completed(true)
	assert_eq(GameManager.money, saved, "A load preserves the money exactly")
	assert_true(SaveManager.load_game(SAVE_NAME), "The same save loads again")
	assert_eq(GameManager.money, saved, "and replays no rewards")
	await process_frames(4)


func test_golfers_play_on_after_the_load() -> void:
	holes_finished = 0
	_simulate()
	# Golfers are not saved: the course fills again as groups arrive. Skip the
	# wait for the next tee time, which can run to weeks of game days.
	main.golfer_manager.time_since_last_spawn = 1.0e9
	assert_true(await process_frames_until(func() -> bool:
		_dismiss_year_summary()
		return holes_finished > 0, DAY_FRAMES * 3), "Golfers arrive and finish holes after the load")
