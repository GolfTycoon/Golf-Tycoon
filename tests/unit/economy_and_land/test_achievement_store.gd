extends GameTest
## AchievementStore: the career shelf in `user://settings.cfg` that makes
## achievements stay unlocked between saves. It reads and writes a scratch
## file here so no test can touch the player's real unlocks.

const STORE_PATH := "user://test_achievement_store_file.cfg"

var _old_store_path := ""

func before_each() -> void:
	super()
	_old_store_path = AchievementStore.settings_path
	AchievementStore.settings_path = STORE_PATH
	AchievementStore.clear()

func after_each() -> void:
	AchievementStore.clear()
	AchievementStore.settings_path = _old_store_path
	super()

func test_a_fresh_install_has_nothing_on_the_shelf() -> void:
	var state := AchievementStore.load_state()
	assert_true(state.unlocked.is_empty(), "No honours are unlocked")
	for key in MilestoneSystem.get_counter_defaults():
		assert_eq(int(state.counters.get(key, -1)), 0,
			"the %s counter starts at zero" % key)

func test_unlocks_and_counters_survive_a_round_trip() -> void:
	var state := AchievementStore.load_state()
	state.unlocked["ach_opening_day"] = 7
	state.counters["rounds"] = 42
	AchievementStore.save_state(state)

	var loaded := AchievementStore.load_state()
	assert_eq(int(loaded.unlocked.get("ach_opening_day", -1)), 7, "The unlock and its day are kept")
	assert_eq(int(loaded.counters.get("rounds", -1)), 42, "Career counters are kept")

func test_clearing_forgets_the_whole_career() -> void:
	var state := AchievementStore.load_state()
	state.unlocked["ach_opening_day"] = 7
	state.counters["rounds"] = 42
	AchievementStore.save_state(state)
	AchievementStore.clear()
	var loaded := AchievementStore.load_state()
	assert_true(loaded.unlocked.is_empty())
	assert_eq(int(loaded.counters.get("rounds", -1)), 0)

## The store lives in the same settings file the tutorial flag uses; if the
## paths ever drift apart, career unlocks would stop persisting.
func test_the_store_lives_in_the_games_settings_file() -> void:
	assert_eq(AchievementStore.DEFAULT_SETTINGS_PATH, SaveManager.SETTINGS_PATH,
		"AchievementStore keeps its career shelf in SaveManager's settings file")
