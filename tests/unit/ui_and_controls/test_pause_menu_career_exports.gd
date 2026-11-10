extends GameTest
## The Career pause menu owns the Tournament Mode exports.
##
## Save Course and Save Golfer used to sit on the owner's round shelves; they
## now sit with the pause menu's save options and carry short captions.
## Pressing either card asks Main (via the menu's export signals) to open the
## Save Course / Save Golfer screen; Main hides the menu while that screen is
## open and brings it back when it closes. These tests cover the menu's own
## contract; the screens and the round-trip into Start Tournament are covered
## by their own tests and the integration flow.


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


func test_the_menu_has_no_inline_export_status_line() -> void:
	GameManager.is_tournament_mode = false
	var menu := _menu()
	await process_frames(3)
	# The outcome of a save is reported by the Save Course / Save Golfer screen
	# itself, above its own archive; the menu has no status line of its own.
	assert_null(menu.find_child("ExportStatus", true, false),
		"the menu does not carry a status line for the Tournament exports")
	assert_false(menu.has_method("show_export_feedback"),
		"and no feedback method remains for a caller to report through")


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
