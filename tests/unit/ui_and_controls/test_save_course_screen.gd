extends GameTest
## SaveCourseScreen — the Pause Menu's "Save Course" screen, opened fullscreen
## while the career game is paused.
##
##   1. The chrome builds: the work card (workspace, name field, gold CTA,
##      live preview) on one side and the saved-course archive on the other.
##   2. The name field starts with the open course's name.
##   3. A blank name is refused with a warning; nothing is saved.
##   4. Saving round-trips into the Tournament Mode library and the screen
##      stays open with the outcome in its status line.
##   5. Saving over an existing name asks first; the library is only
##      overwritten once the question is answered with "Replace course".
##   6. A saved row selects itself back into the name field.
##   7. Delete removes the highlighted saved course, after the question.
##   8. Esc leaves the screen (closed() emitted, screen freed).

const SCRATCH_ROOT := "user://test_save_course_screen"
const SCRATCH_SAVES := SCRATCH_ROOT + "/saves/"
const SCRATCH_SETTINGS := SCRATCH_ROOT + "/settings.cfg"

func before_each() -> void:
	super()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	PlayerDataStore.saves_dir = SCRATCH_SAVES
	PlayerDataStore.settings_path = SCRATCH_SETTINGS
	DirAccess.make_dir_recursive_absolute(SCRATCH_SAVES)
	_make_open_course()

func after_each() -> void:
	PlayerDataStore.restore_default_paths()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	GameManager.current_course = null
	GameManager.player_profile = PlayerGolferProfile.new()
	super()

func _make_open_course() -> void:
	var course := GameManager.CourseData.new()
	for i in range(3):
		var hole := GameManager.HoleData.new()
		hole.hole_number = i + 1
		hole.par = 4
		hole.distance_yards = 350
		hole.is_open = true
		hole.tee_position = Vector2i(46, 46 + i * 4)
		hole.green_position = Vector2i(62, 46 + i * 4)
		hole.hole_position = Vector2i(62, 46 + i * 4)
		course.add_hole(hole)
	GameManager.current_course = course
	GameManager.course_name = "Royal Sydney Club"

func _screen() -> SaveCourseScreen:
	var screen := SaveCourseScreen.new()
	add_child_autofree(screen)
	return screen

func _save_cta(screen: SaveCourseScreen) -> Button:
	return screen.find_child("SaveCourseButton", true, false) as Button

func _confirmation(screen: SaveCourseScreen) -> ConfirmDialog:
	return screen.find_child("LibraryConfirmation", true, false) as ConfirmDialog

func _press(button: Button) -> void:
	if button != null:
		button.pressed.emit()

func test_the_archive_chrome_builds() -> void:
	var screen := _screen()
	await process_frames(3)
	assert_not_null(screen.find_child("SaveWorkspace", true, false), "the work card builds")
	assert_not_null(screen.find_child("LiveCoursePreview", true, false), "the live preview builds")
	assert_not_null(screen.find_child("CourseNameInput", true, false), "the name field builds")
	assert_not_null(screen.find_child("SaveStatus", true, false), "the status line builds")
	assert_not_null(_save_cta(screen), "the gold Save Course action builds")
	assert_not_null(screen.find_child("SavedCourseList", true, false), "the archive builds")
	assert_not_null(screen.find_child("SaveCount", true, false), "the count builds")
	assert_not_null(screen.find_child("DeleteSelectedButton", true, false), "the delete action builds")
	var header := screen.find_child("ScreenHeader", true, false) as HBoxContainer
	assert_not_null(header, "the shared header builds")
	if header != null:
		assert_eq((header.get_child(1) as TextureRect) != null, true, "the header carries a PixelIcon")
		var title_lbl := header.get_node("TitleBlock/Title") as Label
		assert_eq(title_lbl.text, "Save Course")

func test_the_name_field_starts_with_the_open_course_name() -> void:
	var screen := _screen()
	await process_frames(3)
	var input := screen.find_child("CourseNameInput", true, false) as LineEdit
	assert_not_null(input)
	if input != null:
		assert_eq(input.text, "Royal Sydney Club")

func test_a_blank_name_is_refused_with_a_warning() -> void:
	var screen := _screen()
	await process_frames(3)
	var input := screen.find_child("CourseNameInput", true, false) as LineEdit
	assert_not_null(input)
	if input == null:
		return
	await _blank_name_check(input, screen)

func _blank_name_check(input: LineEdit, screen: SaveCourseScreen) -> void:
	input.text = "   "
	_press(_save_cta(screen))
	await process_frames(1)
	var status := screen.find_child("SaveStatus", true, false) as Label
	assert_not_null(status)
	if status != null:
		assert_string_contains(status.text, "name")
	assert_eq(TournamentLibrary.saved_course_count(), 0, "nothing is written")

func test_saving_round_trips_into_the_tournament_library() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_course_count(), 1)
	assert_eq(TournamentLibrary.saved_golfer_count(), 0, "saving a course touches no golfer")
	var saved := TournamentLibrary.list_saved_courses()
	assert_eq(saved.size(), 1)
	if not saved.is_empty():
		assert_eq(str(saved[0].get("name", "")), "Royal Sydney Club")
		assert_eq(int(saved[0].get("hole_count", 0)), 3)
	assert_true(screen.is_inside_tree(), "the screen stays open after saving")
	var status := screen.find_child("SaveStatus", true, false) as Label
	if status != null:
		assert_string_contains(status.text.to_lower(), "saved")
	assert_not_null(screen.find_child("SavedCourse_royal_sydney_club", true, false),
		"the archive lists the fresh keepsake")

func test_saving_twice_asks_before_overwriting() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_course_count(), 1)

	_press(_save_cta(screen))
	await process_frames(2)
	var dialog := _confirmation(screen)
	assert_not_null(dialog, "the second save over the same name asks first")
	assert_eq(TournamentLibrary.saved_course_count(), 1, "the library is untouched until the answer")
	if dialog == null:
		return
	var confirm := dialog.find_child("ConfirmButton", true, false) as Button
	assert_not_null(confirm)
	if confirm != null:
		_press(confirm)
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_course_count(), 1, "overwriting replaces, it does not duplicate")
	assert_null(_confirmation(screen), "the dialogue clears once answered")

func test_selecting_a_saved_row_fills_the_name_field() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	var input := screen.find_child("CourseNameInput", true, false) as LineEdit
	if input == null:
		return
	input.text = "Something else entirely"
	var row := screen.find_child("SavedCourse_royal_sydney_club", true, false) as Button
	assert_not_null(row, "the saved entry is on the shelf")
	if row == null:
		return
	_press(row)
	await process_frames(1)
	assert_eq(input.text, "Royal Sydney Club", "picking a saved row fills the name for an overwrite")
	assert_true(row.button_pressed, "the picked row shows it is picked")

func test_deleting_the_selected_saved_course_asks_then_removes_it() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	var row := screen.find_child("SavedCourse_royal_sydney_club", true, false) as Button
	assert_not_null(row)
	if row == null:
		return
	_press(row)
	await process_frames(1)
	_press(screen.find_child("DeleteSelectedButton", true, false) as Button)
	await process_frames(2)
	var dialog := _confirmation(screen)
	assert_not_null(dialog, "deleting asks first")
	assert_eq(TournamentLibrary.saved_course_count(), 1, "nothing is deleted before the answer")
	if dialog == null:
		return
	_press(dialog.find_child("ConfirmButton", true, false) as Button)
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_course_count(), 0)
	assert_null(screen.find_child("SavedCourse_royal_sydney_club", true, false),
		"the shelf drops the deleted entry")

func test_escape_leaves_the_screen() -> void:
	var screen := _screen()
	await process_frames(3)
	var closed := [false]
	screen.closed.connect(func() -> void: closed[0] = true)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	screen._input(esc)
	await process_frames(2)
	assert_true(closed[0], "Esc closes the screen")
	assert_false(is_instance_valid(screen), "and the screen frees itself")
