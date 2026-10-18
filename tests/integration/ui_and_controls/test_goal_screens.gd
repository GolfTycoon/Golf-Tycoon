extends MainSceneTest
## The goal screens over a live course and from the title screen: the Club
## tab's Course Milestones, World Milestones and Achievements buttons (and
## the G / Shift+G / Shift+T hotkeys) take the whole window on the World
## Map's backdrop, freeze the day while they are up, flip between the three
## tracks, and hand the course back on Back. The main menu's Achievements
## tile opens the same trophy room over the title screen and comes home to
## the menu.

func before_all() -> void:
	await super()
	await new_game("Goal screens")


func _goal_screen(named: String) -> Control:
	return main.get_node_or_null("UI/HUD/" + named) as Control


## The toolbar button that acts for `tool_type`, wherever it sits on its tab.
func _tool_button(node: Node, tool_type: String) -> Button:
	for child in node.get_children():
		if child is Button and str(child.get("tool_type")) == tool_type:
			return child
		var found := _tool_button(child, tool_type)
		if found:
			return found
	return null


func test_the_course_milestones_screen_takes_the_window_and_freezes_the_day() -> void:
	var was_paused := GameManager.is_paused
	main._toggle_course_milestones_screen()
	await process_frames(2)
	var screen := _goal_screen("CourseMilestonesScreen")
	assert_not_null(screen, "G takes the Course Milestones screen up")
	if screen:
		assert_true(screen.visible, "the goal book is on screen")
	assert_true(GameManager.is_paused, "the day freezes while the goals are up")

	main._toggle_course_milestones_screen()
	await process_frames(2)
	assert_null(_goal_screen("CourseMilestonesScreen"), "G again puts it away")
	assert_eq(GameManager.is_paused, was_paused, "and the day resumes as it was")


func test_the_world_milestones_screen_shares_the_same_hands_off_state() -> void:
	var was_paused := GameManager.is_paused
	main._toggle_world_milestones_screen()
	await process_frames(2)
	var screen := _goal_screen("WorldMilestonesScreen")
	assert_not_null(screen, "Shift+G takes the World Milestones screen up")
	if screen:
		assert_true(screen.visible)
	assert_true(GameManager.is_paused, "the day freezes here too")

	main._toggle_world_milestones_screen()
	await process_frames(2)
	assert_null(_goal_screen("WorldMilestonesScreen"))
	assert_eq(GameManager.is_paused, was_paused, "and the course is handed back")


func test_the_achievements_screen_keeps_career_honours_between_saves() -> void:
	var was_paused := GameManager.is_paused
	main._toggle_achievements_screen()
	await process_frames(2)
	var screen := _goal_screen("AchievementsScreen")
	assert_not_null(screen, "Shift+T takes the trophy room up")
	if screen:
		assert_true(screen.visible)
	assert_true(GameManager.is_paused, "and the day freezes while it is up")

	main._toggle_achievements_screen()
	await process_frames(2)
	assert_null(_goal_screen("AchievementsScreen"))
	assert_eq(GameManager.is_paused, was_paused, "Back hands the course back")


func test_the_three_screens_flip_between_each_other() -> void:
	main._toggle_course_milestones_screen()
	await process_frames(2)
	var world := _goal_screen("CourseMilestonesScreen").find_child("Track_world", true, false) as Button
	assert_not_null(world, "the goal book keeps the other tracks one tap away")
	if world:
		world.pressed.emit()
	await process_frames(2)
	assert_true(_goal_screen("WorldMilestonesScreen").visible, "one tap opens the world book")
	assert_false(_goal_screen("CourseMilestonesScreen").visible, "while the course book stands down")

	var honours := _goal_screen("WorldMilestonesScreen").find_child("Track_achievements", true, false) as Button
	assert_not_null(honours, "and the trophy room")
	if honours:
		honours.pressed.emit()
	await process_frames(2)
	assert_true(_goal_screen("AchievementsScreen").visible, "opens the same way")

	var back := _goal_screen("AchievementsScreen").find_child("BackButton", true, false) as Button
	if back:
		back.pressed.emit()
	await process_frames(2)
	assert_null(_goal_screen("AchievementsScreen"), "Back hands the course back")
	assert_null(_goal_screen("WorldMilestonesScreen"), "taking the other screens with it")


func test_the_club_tab_shelves_all_three_goal_screens() -> void:
	var course_button := _tool_button(main.terrain_toolbar, "course_milestones")
	assert_not_null(course_button, "the Club tab shelves Course Milestones")
	var world_button := _tool_button(main.terrain_toolbar, "world_milestones")
	assert_not_null(world_button, "World Milestones beside it")
	var honours_button := _tool_button(main.terrain_toolbar, "achievements")
	assert_not_null(honours_button, "and Achievements")
	if course_button:
		course_button.pressed.emit()
	await process_frames(2)
	assert_true(_goal_screen("CourseMilestonesScreen").visible, "the shelf opens the course book")
	main._toggle_course_milestones_screen()
	await process_frames(2)
	if world_button:
		world_button.pressed.emit()
	await process_frames(2)
	assert_true(_goal_screen("WorldMilestonesScreen").visible, "and the world book")
	main._toggle_world_milestones_screen()
	await process_frames(2)
	if honours_button:
		honours_button.pressed.emit()
	await process_frames(2)
	assert_true(_goal_screen("AchievementsScreen").visible, "and the trophy room")
	main._toggle_achievements_screen()
	await process_frames(2)


func test_the_main_menu_achievement_tile_opens_the_trophy_room_and_comes_home() -> void:
	# Back to the title screen first: the tile lives there.
	main._show_main_menu()
	await process_frames(2)
	assert_not_null(main.main_menu, "the title screen is up")
	var tile := main.main_menu.find_child("AchievementsButton", true, false) as Button
	assert_not_null(tile, "the title screen carries an Achievements tile")
	if tile:
		tile.pressed.emit()
	await process_frames(2)
	assert_null(main.main_menu, "the menu steps aside for the trophy room")
	var screen := _goal_screen("AchievementsScreen")
	assert_not_null(screen, "the trophy room opens")
	if screen:
		assert_true(screen.visible)

	var back := screen.find_child("BackButton", true, false) as Button
	if back:
		back.pressed.emit()
	await process_frames(2)
	assert_null(_goal_screen("AchievementsScreen"), "Back closes the trophy room")
	assert_not_null(main.main_menu, "and comes home to the main menu")
