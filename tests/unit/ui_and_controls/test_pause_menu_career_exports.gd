extends GameTest
## The Career pause menu owns the Tournament Mode exports.
##
## Save Course and Save Golfer used to sit on the owner's round shelves; they
## now sit with the pause menu's save options, carry short captions, and report
## their outcome in the menu instead of closing it. Main wires the requests to
## TournamentCareerExport; these tests cover the menu's own contract, while the
## round-trip into Start Tournament is covered by the integration flow.


func _menu() -> PauseMenu:
	var menu := autofree(PauseMenu.new()) as PauseMenu
	add_child(menu)
	return menu


func _button(menu: PauseMenu, node_name: String) -> Button:
	return menu.find_child(node_name, true, false) as Button


func test_career_menu_places_the_two_exports_between_load_and_settings() -> void:
	GameManager.is_tournament_mode = false
	var menu := _menu()
	await process_frames(3)
	var load_game := _button(menu, "LoadGameButton")
	var save_course := _button(menu, "SaveCourseButton")
	var save_golfer := _button(menu, "SaveGolferButton")
	var settings := _button(menu, "SettingsButton")
	assert_not_null(save_course, "Save Course is a career pause option")
	assert_not_null(save_golfer, "Save Golfer is a career pause option")
	if save_course == null or save_golfer == null:
		return
	assert_eq(save_course.text, "Save Course")
	assert_eq(save_golfer.text, "Save Golfer")
	assert_true("Tournament" in save_course.tooltip_text,
		"The course card says where the export can be played")
	assert_true("Tournament" in save_golfer.tooltip_text,
		"The golfer card says where the export can be played")
	assert_lt(load_game.get_index(), save_course.get_index())
	assert_lt(save_course.get_index(), save_golfer.get_index())
	assert_lt(save_golfer.get_index(), settings.get_index())


func test_the_export_cards_request_their_exports() -> void:
	GameManager.is_tournament_mode = false
	var menu := _menu()
	watch_signals(menu)
	await process_frames(3)
	var save_course := _button(menu, "SaveCourseButton")
	var save_golfer := _button(menu, "SaveGolferButton")
	assert_not_null(save_course)
	assert_not_null(save_golfer)
	if save_course == null or save_golfer == null:
		return
	save_course.pressed.emit()
	save_golfer.pressed.emit()
	assert_signal_emitted(menu, "save_course_requested",
		"Save Course asks Main to export the course")
	assert_signal_emitted(menu, "save_golfer_requested",
		"Save Golfer asks Main to export the golfer")


func test_an_export_reports_itself_above_the_options_without_leaving_the_menu() -> void:
	GameManager.is_tournament_mode = false
	var menu := _menu()
	await process_frames(3)
	assert_false(menu._export_status.visible, "No status is shown before an export")
	var message := "Saved golfer 'Bennelong Star' for Tournament Mode!"
	menu.show_export_feedback(message, true)
	await process_frames(3)
	assert_true(menu._export_status.visible, "The menu stays open and shows the result")
	assert_eq(menu._export_status.text, message)
	assert_eq(menu._export_status.get_theme_color("font_color"), UIConstants.COLOR_SUCCESS)
	var options := InputManager.collect_focusables(menu)
	assert_false(options.is_empty(), "The menu keeps its options")
	assert_lt(menu._export_status.get_global_rect().get_center().y,
		(options[0] as Control).get_global_rect().get_center().y,
		"The result stands above the options, not as a footnote under them")
	# A failed export is reported in the same place, in the warning colour.
	menu.show_export_feedback("No course is currently open.", false)
	await process_frames(2)
	assert_eq(menu._export_status.text, "No course is currently open.")
	assert_eq(menu._export_status.get_theme_color("font_color"), UIConstants.COLOR_WARNING)


func test_the_tournament_pause_menu_omits_the_career_exports() -> void:
	GameManager.is_tournament_mode = true
	var menu := _menu()
	await process_frames(3)
	assert_null(_button(menu, "SaveCourseButton"),
		"A standalone tournament has no Career course to export")
	assert_null(_button(menu, "SaveGolferButton"),
		"Nor a Career golfer")
	assert_not_null(_button(menu, "RestartTournamentButton"),
		"The tournament's own actions remain")
