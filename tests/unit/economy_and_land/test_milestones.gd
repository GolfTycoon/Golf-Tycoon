extends GameTest
## The three goal tracks: Course Location Milestones complete per course
## location and unlock again with every new save, World Milestones complete
## once per save for the whole company, and Achievements stay unlocked
## between saves through the player's settings file.
##
## The manager is built quiet (not added to the tree, so it listens to no
## game events): each test completes the goals it means to.

const STORE_PATH := "user://test_achievements_store.cfg"

var manager: MilestoneManager
var _old_store_path := ""

func before_each() -> void:
	super()
	_old_store_path = AchievementStore.settings_path
	AchievementStore.settings_path = STORE_PATH
	AchievementStore.clear()
	manager = _make_manager()
	WorldMap.active_location_id = "monterey"

func after_each() -> void:
	AchievementStore.clear()
	AchievementStore.settings_path = _old_store_path
	SaveManager._is_loading = false
	manager = null
	super()

func _make_manager() -> MilestoneManager:
	var fresh: MilestoneManager = autofree(MilestoneManager.new())
	fresh._init_state()
	return fresh

func _location_milestone(id: String) -> MilestoneSystem.Milestone:
	for milestone in manager.location_milestones:
		if milestone.id == id:
			return milestone
	return null

func _world_milestone(id: String) -> MilestoneSystem.Milestone:
	for milestone in manager.world_milestones:
		if milestone.id == id:
			return milestone
	return null

func _achievement(id: String) -> MilestoneSystem.Milestone:
	for milestone in manager.achievements:
		if milestone.id == id:
			return milestone
	return null

# ---------------------------------------------------------------------------
# Course Location Milestones: one track per location
# ---------------------------------------------------------------------------

func test_a_location_milestone_pays_its_reward_once_at_that_location() -> void:
	var first_tee := _location_milestone("loc_first_hole")
	GameManager.money = 1000
	GameManager.current_day = 12
	watch_signals(manager)
	manager._complete_milestone(first_tee)
	assert_true(manager.is_location_completed("loc_first_hole", "monterey"))
	assert_eq(GameManager.money, 1000 + first_tee.reward_money, "The reward is paid")
	assert_signal_emitted_with_parameters(manager, "milestone_completed",
		[first_tee.id, first_tee.title, first_tee.description, MilestoneSystem.Track.LOCATION])
	manager._complete_milestone(first_tee)
	assert_eq(GameManager.money, 1000 + first_tee.reward_money, "...and only once")

func test_every_location_unlocks_its_own_milestones() -> void:
	var first_tee := _location_milestone("loc_first_hole")
	GameManager.money = 1000
	manager._complete_milestone(first_tee)
	assert_true(manager.is_location_completed("loc_first_hole", "monterey"))

	WorldMap.active_location_id = "florida"
	assert_false(manager.is_location_completed("loc_first_hole", "florida"),
		"The next site starts with its milestones locked again")
	manager._complete_milestone(first_tee)
	assert_true(manager.is_location_completed("loc_first_hole", "florida"))
	assert_eq(GameManager.money, 1000 + 2 * first_tee.reward_money,
		"Each location pays its own First Tee reward")
	assert_eq(manager.get_location_completion_count("monterey"), 1)
	assert_eq(manager.get_location_completion_count("florida"), 1)

func test_a_new_save_locks_the_milestones_again() -> void:
	manager._complete_milestone(_location_milestone("loc_first_hole"))
	manager._complete_milestone(_world_milestone("world_rep_25"))
	assert_eq(manager.get_location_completion_count(), 1)
	assert_eq(manager.get_world_completion_count(), 1)

	manager.reset_for_new_save()
	assert_eq(manager.get_location_completion_count(), 0, "Location milestones unlock again each save")
	assert_eq(manager.get_world_completion_count(), 0, "World milestones unlock again each save")

# ---------------------------------------------------------------------------
# World Milestones: one track per save, for every location
# ---------------------------------------------------------------------------

func test_a_world_milestone_completes_once_per_save() -> void:
	var noticed := _world_milestone("world_rep_25")
	GameManager.money = 500
	watch_signals(manager)
	manager._complete_milestone(noticed)
	assert_true(manager.is_world_completed("world_rep_25"))
	assert_signal_emitted_with_parameters(manager, "milestone_completed",
		[noticed.id, noticed.title, noticed.description, MilestoneSystem.Track.WORLD])
	manager._complete_milestone(noticed)
	assert_eq(manager.get_world_completion_count(), 1, "The company earns it once per save")

# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

func test_completed_goals_survive_a_save_round_trip() -> void:
	GameManager.current_day = 3
	manager._complete_milestone(_location_milestone("loc_first_hole"))
	manager._complete_milestone(_world_milestone("world_rep_25"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(manager.serialize()))

	var loaded := _make_manager()
	var money := GameManager.money
	loaded.deserialize(saved)
	assert_eq(loaded.get_location_completion_count("monterey"), 1)
	assert_eq(loaded.get_world_completion_count(), 1)
	assert_true(loaded.is_location_completed("loc_first_hole", "monterey"))
	assert_true(loaded.is_world_completed("world_rep_25"))
	assert_eq(GameManager.money, money, "Loading a milestone does not pay it again")

## Loading used to add the save's goals to the flags of the course played
## before it instead of replacing them.
func test_deserialize_replaces_previous_progress() -> void:
	var first = manager.location_milestones[0]
	manager._location_entry("monterey").completed[first.id] = 3
	manager.deserialize({})
	assert_eq(manager.get_location_completion_count("monterey"), 0)
	assert_false(manager.is_world_completed(manager.world_milestones[0].id))

func test_loading_blocks_rewards_even_when_the_goal_completes() -> void:
	var money := GameManager.money
	SaveManager._is_loading = true
	manager._complete_milestone(_location_milestone("loc_first_hole"))
	assert_eq(manager.get_location_completion_count(), 0)
	assert_true(manager.get_location_completed().is_empty())
	SaveManager._is_loading = false
	assert_eq(GameManager.money, money)
	assert_false(manager.is_location_completed("loc_first_hole"))

## Saves from before the three tracks kept one flat completed list. Its ids
## migrate to the closest new home instead of being dropped.
func test_deserialize_migrates_the_old_flat_list() -> void:
	GameManager.current_day = 40
	var legacy := {
		"completed": [
			{"id": "first_hole", "day": 12},
			{"id": "nine_holes", "day": 20},
			{"id": "rep_50", "day": 35},
			{"id": "not_a_real_id", "day": 1},
		],
	}
	manager.deserialize(legacy)
	assert_true(manager.is_location_completed("loc_first_hole", "monterey"),
		"Old course milestones land on the active location")
	assert_true(manager.is_location_completed("loc_nine_holes", "monterey"))
	assert_true(manager.is_world_completed("world_rep_50"),
		"Old company milestones become world milestones")
	assert_eq(manager.get_world_completion_count(), 1, "Unknown ids are dropped")

# ---------------------------------------------------------------------------
# Achievements: unlocked for good, whatever happens to the saves
# ---------------------------------------------------------------------------

func test_an_achievement_unlocks_once_and_stays_unlocked_between_managers() -> void:
	var opening := _achievement("ach_opening_day")
	watch_signals(manager)
	manager._bump_counter("rounds", 1)
	assert_true(manager.is_achievement_unlocked("ach_opening_day"))
	assert_signal_emitted_with_parameters(manager, "achievement_unlocked",
		[opening.id, opening.title, opening.description])
	manager._bump_counter("rounds", 0)
	assert_eq(manager.get_achievement_count(), 1, "It unlocks only once")

	# A new manager is a new session over the same career shelf.
	var later := _make_manager()
	assert_true(later.is_achievement_unlocked("ach_opening_day"),
		"Achievements stay unlocked between saves")

func test_a_new_save_keeps_achievements_while_milestones_lock_again() -> void:
	manager._bump_counter("rounds", 1)
	manager._complete_milestone(_location_milestone("loc_first_hole"))
	manager.reset_for_new_save()
	assert_true(manager.is_achievement_unlocked("ach_opening_day"),
		"Achievements outlive the save that earned them")
	assert_eq(manager.get_location_completion_count(), 0,
		"Milestones unlock again with the new save")

func test_counters_accumulate_toward_their_goals() -> void:
	var club_classic := _achievement("ach_club_classic")
	assert_eq(manager.get_achievement_progress(club_classic), 0)
	manager._bump_counter("rounds", 40)
	assert_eq(manager.get_achievement_progress(club_classic), 40, "Progress is kept")
	assert_false(manager.is_achievement_unlocked("ach_club_classic"))
	manager._bump_counter("rounds", 60)
	assert_true(manager.is_achievement_unlocked("ach_club_classic"))
	assert_eq(manager.get_achievement_progress(club_classic), 100, "Progress clamps at the goal")

func test_revenue_and_reputation_counters_use_their_modes() -> void:
	manager._bump_counter("revenue", 250000)
	manager._bump_counter("revenue", 300000)
	assert_eq(manager.get_counter("revenue"), 550000, "Revenue adds up")
	manager._bump_counter("reputation", 25, "max")
	manager._bump_counter("reputation", 100, "max")
	manager._bump_counter("reputation", 25, "max")
	assert_eq(manager.get_counter("reputation"), 100, "A max counter keeps the high-water mark")
	manager._bump_counter("days", 200, "max")
	manager._bump_counter("days", 120, "max")
	assert_eq(manager.get_counter("days"), 200, "and so does the longest company")
	manager._bump_counter("five_star", 1, "flag")
	manager._bump_counter("five_star", 0, "flag")
	assert_eq(manager.get_counter("five_star"), 1, "A flag counter sticks at one")

func test_the_hall_of_fame_follows_the_last_achievement() -> void:
	for a in manager.achievements:
		if a.id in ["ach_hall_of_fame", "ach_champion"]:
			continue
		manager._unlock_achievement(a.id)
	assert_false(manager.is_achievement_unlocked("ach_hall_of_fame"),
		"The meta honour waits for every other one")
	manager._unlock_achievement("ach_champion")
	assert_true(manager.is_achievement_unlocked("ach_hall_of_fame"),
		"and lands with the last achievement")
