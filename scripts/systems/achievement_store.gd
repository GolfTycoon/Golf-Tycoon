extends RefCounted
class_name AchievementStore
## AchievementStore - the career shelf that outlives every save.
##
## Achievements stay unlocked between saves, so their unlock flags and the
## career counters behind them live in the player's settings file (the same
## `user://settings.cfg` the tutorial completion flag uses) instead of any
## save slot. A new company begins with every milestone locked again while
## the trophy case on the Achievements screen still shows the past unlocks.
##
## State shape: { "unlocked": { id: day }, "counters": { key: value } }.

const SECTION := "achievements"
const UNLOCKED_KEY := "unlocked"
const COUNTERS_KEY := "counters"

## Mirrors SaveManager.SETTINGS_PATH. Kept literal so the store can be unit
## tested on a scratch file without the autoloads; a test asserts the two
## paths match. Tests point `settings_path` at a scratch file instead.
const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
static var settings_path: String = DEFAULT_SETTINGS_PATH

static func empty_state() -> Dictionary:
	return {
		UNLOCKED_KEY: {},
		COUNTERS_KEY: MilestoneSystem.get_counter_defaults(),
	}

## The stored unlocks and counters. Missing pieces (a fresh install, or a
## file from before a counter existed) fall back to empty / zero.
static func load_state() -> Dictionary:
	var state := empty_state()
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return state
	var unlocked = config.get_value(SECTION, UNLOCKED_KEY, {})
	if unlocked is Dictionary:
		for id in unlocked:
			state[UNLOCKED_KEY][str(id)] = int(unlocked[id])
	var counters = config.get_value(SECTION, COUNTERS_KEY, {})
	if counters is Dictionary:
		for key in counters:
			state[COUNTERS_KEY][str(key)] = int(counters[key])
	return state

## Write the state back, keeping every other section of the settings file
## (key bindings, the tutorial flag) intact.
static func save_state(state: Dictionary) -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(SECTION, UNLOCKED_KEY, state.get(UNLOCKED_KEY, {}))
	config.set_value(SECTION, COUNTERS_KEY, state.get(COUNTERS_KEY, {}))
	config.save(settings_path)

## Forget every unlock and counter (tests, and the "wipe career" escape hatch).
static func clear() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK and config.has_section(SECTION):
		config.erase_section(SECTION)
		config.save(settings_path)
