extends GameTest
## Milestones: completing one pays its reward once, a load restores exactly the
## milestones the save had (and never pays for them again), and nothing completes
## while a save is being loaded.

var manager: MilestoneManager

func before_each() -> void:
	super()
	# Not added to the tree, so it does not listen to the game's events: each
	# test completes the milestones it means to.
	manager = autofree(MilestoneManager.new())
	manager.milestones = MilestoneSystem.get_all_milestones()

func after_each() -> void:
	SaveManager._is_loading = false
	super()

func _milestone(id: String) -> MilestoneSystem.Milestone:
	for milestone in manager.milestones:
		if milestone.id == id:
			return milestone
	return null

func test_completing_a_milestone_pays_its_reward_once() -> void:
	var first_tee := _milestone("first_hole")
	GameManager.money = 1000
	GameManager.current_day = 12
	watch_signals(manager)
	manager._complete_milestone(first_tee)
	assert_true(first_tee.is_completed)
	assert_eq(first_tee.completion_day, 12, "The day it was reached is kept")
	assert_eq(GameManager.money, 1000 + first_tee.reward_money, "The reward is paid")
	assert_signal_emitted(manager, "milestone_completed")
	manager._complete_milestone(first_tee)
	assert_eq(GameManager.money, 1000 + first_tee.reward_money, "...and only once")
	assert_eq(manager.get_completion_count(), 1)

func test_completed_milestones_survive_a_save_round_trip() -> void:
	GameManager.current_day = 3
	manager._complete_milestone(_milestone("first_hole"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(manager.serialize()))

	var loaded: MilestoneManager = autofree(MilestoneManager.new())
	loaded.milestones = MilestoneSystem.get_all_milestones()
	var money := GameManager.money
	loaded.deserialize(saved)
	assert_eq(loaded.get_completion_count(), 1)
	assert_true(loaded._is_done("first_hole"))
	assert_eq(GameManager.money, money, "Loading a milestone does not pay it again")

## Loading used to add the save's milestones to the flags of the course played
## before it instead of replacing them.
func test_milestone_deserialize_resets_previous_course_flags() -> void:
	var first = manager.milestones[0]
	first.is_completed = true
	first.completion_day = 3
	manager.deserialize({})
	assert_false(first.is_completed)
	assert_eq(first.completion_day, 0)

func test_loading_blocks_rewards_even_when_event_is_received() -> void:
	var money := GameManager.money
	SaveManager._is_loading = true
	manager._complete_milestone(manager.milestones[0])
	assert_eq(manager.get_completion_count(), 0)
	assert_true(manager.serialize().completed.is_empty())
	SaveManager._is_loading = false
	assert_eq(GameManager.money, money)
	assert_false(manager.milestones[0].is_completed)
