extends MainSceneTest
## The title screen's Continue card: it resumes the newest checkpoint and
## hands the player the course they left.
##
## Continue is the shortcut past the archive — the Load Game tile opens the
## Save / Load panel and lets the player pick, while Continue plays the newest
## checkpoint straight away. Both have to end in the same place, because the
## title screen is the last thing standing between the player and the game:
## the menu gone, the world map gone and the course's own HUD back on screen.
##
## It is also the one way into the game that can fail without the player
## doing anything wrong (a checkpoint written by an older version, a file
## another program truncated), so a refused load has to leave the title
## screen standing rather than dropping the player into an empty course.

## The slot these tests play. Deleted before and after, so a leftover from an
## interrupted run cannot make one of them pass on someone else's file.
const SLOT := "integration_continue_slot"
## A second, older slot, so "newest" has something to be newest against, and
## something to be left alone when the newest one is refused.
const OLDER_SLOT := "integration_continue_older"

## The recognisable state each checkpoint carries. Course name is the marker
## these tests read back: it is the one field the running day cannot move.
const SLOT_COURSE := "Continue Links"
const OLDER_COURSE := "Older Grounds"


func before_all() -> void:
	await super()
	_clean_slots()


func after_all() -> void:
	_clean_slots()
	super()


func _clean_slots() -> void:
	for slot in [SLOT, OLDER_SLOT]:
		SaveManager.delete_save(slot)


## A checkpoint on disk, written by the real save path and named `course`, so a
## test can tell from the loaded course name which slot came back.
func _write_slot(slot: String, course: String) -> void:
	GameManager.course_name = course
	assert_true(SaveManager.save_game(slot), "the %s checkpoint is written" % slot)


## The newest save's Continue card, pressed the way a player presses it.
func _press_continue() -> void:
	var button: Button = main.main_menu._continue_button
	assert_not_null(button, "the title screen has a Continue card")
	if button != null:
		button.pressed.emit()
		await process_frames(6)


func test_continue_resumes_the_newest_save_and_hands_the_course_back() -> void:
	await set_window(DESIGN_WINDOW)
	await new_game("Throwaway lot")
	# An older checkpoint first, then a newer one: Continue must pick the
	# newer of the two, not whichever the directory happens to list first.
	_write_slot(OLDER_SLOT, OLDER_COURSE)
	_write_slot(SLOT, SLOT_COURSE)

	main._show_main_menu()
	await process_frames(4)
	assert_not_null(main.main_menu, "the game is back on the title screen")
	var card: Button = main.main_menu._continue_button
	assert_not_null(card, "the title screen has a Continue card")
	if card == null:
		return
	assert_false(card.disabled, "and Continue is live with checkpoints on file")

	await _press_continue()

	# The newest checkpoint is the one that came back, not the older slot.
	assert_eq(GameManager.course_name, SLOT_COURSE, "Continue resumed the newest checkpoint")
	assert_eq(SaveManager.current_save_name, SLOT, "and that slot is now the current one")

	# ...and the player is looking at the course, not at the menu that sent
	# them there. This is what makes Continue worth a card of its own.
	await process_frames(2)
	assert_null(main.main_menu, "the title screen is dismissed")
	assert_false(is_instance_valid(main.world_map_screen), "with no world map left over the course")
	assert_not_null(main.terrain_toolbar, "the course HUD exists to be shown")
	if main.terrain_toolbar:
		assert_true(main.terrain_toolbar.is_visible_in_tree(), "and the toolbar is back on screen")
	if main.hud_status_column:
		assert_true(main.hud_status_column.is_visible_in_tree(), "and so is the status column")


func test_a_refused_continue_leaves_the_title_screen_standing() -> void:
	await set_window(DESIGN_WINDOW)
	await new_game("Throwaway lot")
	# The newest entry on the shelf is one that is gone by the time the card
	# is pressed — the archive's own Delete, or another session's cleanup.
	_write_slot(OLDER_SLOT, OLDER_COURSE)
	_write_slot(SLOT, SLOT_COURSE)

	main._show_main_menu()
	await process_frames(4)
	var card: Button = main.main_menu._continue_button
	assert_not_null(card, "the title screen has a Continue card")
	if card == null:
		return
	assert_false(card.disabled, "Continue is live while a checkpoint is on file")

	SaveManager.delete_save(SLOT)
	# Writing the checkpoints above moved the game's own course name with
	# them, so this is the state a refused load has to leave exactly as it is.
	var before := GameManager.course_name
	await _press_continue()

	assert_not_null(main.main_menu, "a refused load leaves the title screen up")
	assert_eq(GameManager.course_name, before,
		"and the game in progress is untouched by the failed attempt")
	if main.terrain_toolbar:
		assert_false(main.terrain_toolbar.is_visible_in_tree(),
			"the course HUD stays hidden behind the menu that is still up")


## The card is disabled when there is nothing to resume (see
## test_main_menu_screen.gd, which covers both branches at every window size),
## so a player cannot press it. A press with no slot behind it — a stale
## signal, a save deleted while the menu was up — has to be just as harmless.
func test_a_continue_with_no_slot_behind_it_goes_nowhere() -> void:
	await set_window(DESIGN_WINDOW)
	_clean_slots()
	await new_game("Throwaway lot")
	main._show_main_menu()
	await process_frames(4)
	var before := GameManager.course_name
	main._on_menu_continue("")
	await process_frames(3)
	assert_not_null(main.main_menu, "an empty slot leaves the title screen up")
	assert_eq(GameManager.course_name, before, "and changes nothing about the game")
