extends GameTest
## SaveGolferScreen — the Pause Menu's "Save Golfer" screen, opened fullscreen
## while the career game is paused.
##
##   1. The chrome builds: the work card (portrait, ability bars, name field,
##      gold CTA) on one side and the saved-golfer archive on the other.
##   2. The name field starts with the golfer's own name.
##   3. A blank name is refused with a warning; nothing is saved.
##   4. Saving round-trips into the Tournament Mode library and the screen
##      stays open with the outcome in its status line.
##   5. Saving over an existing name asks first; the library is only
##      overwritten once the question is answered with "Replace golfer".
##   6. A saved row selects itself back into the name field.
##   7. Delete removes the highlighted saved golfer, after the question.
##   8. Esc leaves the screen (closed() emitted, screen freed).

const SCRATCH_ROOT := "user://test_save_golfer_screen"
const SCRATCH_SAVES := SCRATCH_ROOT + "/saves/"
const SCRATCH_SETTINGS := SCRATCH_ROOT + "/settings.cfg"

func before_each() -> void:
	super()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	PlayerDataStore.saves_dir = SCRATCH_SAVES
	PlayerDataStore.settings_path = SCRATCH_SETTINGS
	DirAccess.make_dir_recursive_absolute(SCRATCH_SAVES)
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = "Bennelong Star"
	profile.profession = "Tour Winner"
	profile.age = 34
	profile.gender = GolferAttributes.Gender.FEMALE
	profile.marital_status = GolferAttributes.MaritalStatus.MARRIED
	profile.traits = {"neat": true, "outgoing": true, "active": true, "playful": false, "nice": true}
	profile.golfer_skills = {"length": true, "accuracy": true, "imagination": true}
	profile.initialized = true
	profile.points = [15, 14, 17, 17, 19, 8, 7, 9, 12, 6]
	GameManager.player_profile = profile
	GameManager.player_skin_id = "casual"

func after_each() -> void:
	PlayerDataStore.restore_default_paths()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	GameManager.player_profile = PlayerGolferProfile.new()
	super()

func _screen() -> SaveGolferScreen:
	var screen := SaveGolferScreen.new()
	add_child_autofree(screen)
	return screen

func _save_cta(screen: SaveGolferScreen) -> Button:
	return screen.find_child("SaveGolferButton", true, false) as Button

func _confirmation(screen: SaveGolferScreen) -> ConfirmDialog:
	return screen.find_child("LibraryConfirmation", true, false) as ConfirmDialog

func _press(button: Button) -> void:
	if button != null:
		button.pressed.emit()

func test_the_archive_chrome_builds() -> void:
	var screen := _screen()
	await process_frames(3)
	assert_not_null(screen.find_child("SaveWorkspace", true, false), "the work card builds")
	assert_not_null(screen.find_child("LiveGolferPortrait", true, false), "the portrait builds")
	assert_not_null(screen.find_child("LiveGolferAbilities", true, false), "the ability bars build")
	assert_not_null(screen.find_child("GolferNameInput", true, false), "the name field builds")
	assert_not_null(screen.find_child("SaveStatus", true, false), "the status line builds")
	assert_not_null(_save_cta(screen), "the gold Save Golfer action builds")
	assert_not_null(screen.find_child("SavedGolferList", true, false), "the archive builds")
	assert_not_null(screen.find_child("SaveCount", true, false), "the count builds")
	assert_not_null(screen.find_child("DeleteSelectedButton", true, false), "the delete action builds")
	var header := screen.find_child("ScreenHeader", true, false) as HBoxContainer
	assert_not_null(header, "the shared header builds")
	if header != null:
		var title_lbl := header.get_node("TitleBlock/Title") as Label
		assert_eq(title_lbl.text, "Save Golfer")

func test_the_name_field_starts_with_the_golfers_name() -> void:
	var screen := _screen()
	await process_frames(3)
	var input := screen.find_child("GolferNameInput", true, false) as LineEdit
	assert_not_null(input)
	if input != null:
		assert_eq(input.text, "Bennelong Star")

func test_a_blank_name_is_refused_with_a_warning() -> void:
	var screen := _screen()
	await process_frames(3)
	var input := screen.find_child("GolferNameInput", true, false) as LineEdit
	assert_not_null(input)
	if input == null:
		return
	input.text = "   "
	_press(_save_cta(screen))
	await process_frames(1)
	var status := screen.find_child("SaveStatus", true, false) as Label
	assert_not_null(status)
	if status != null:
		assert_string_contains(status.text, "name")
	assert_eq(TournamentLibrary.saved_golfer_count(), 0, "nothing is written")

func test_saving_round_trips_into_the_tournament_library() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_golfer_count(), 1)
	assert_eq(TournamentLibrary.saved_course_count(), 0, "saving a golfer touches no course")
	var saved := TournamentLibrary.list_saved_golfers()
	assert_eq(saved.size(), 1)
	if not saved.is_empty():
		assert_eq(str(saved[0].get("name", "")), "Bennelong Star")
		assert_eq(int(saved[0].get("age", 0)), 34)
		assert_eq(str(saved[0].get("profession", "")), "Tour Winner")
	assert_true(screen.is_inside_tree(), "the screen stays open after saving")
	var status := screen.find_child("SaveStatus", true, false) as Label
	if status != null:
		assert_string_contains(status.text.to_lower(), "saved")
	assert_not_null(screen.find_child("SavedGolfer_bennelong_star", true, false),
		"the archive lists the fresh keepsake")

func test_saving_twice_asks_before_overwriting() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_golfer_count(), 1)

	_press(_save_cta(screen))
	await process_frames(2)
	var dialog := _confirmation(screen)
	assert_not_null(dialog, "the second save over the same name asks first")
	assert_eq(TournamentLibrary.saved_golfer_count(), 1, "the library is untouched until the answer")
	if dialog == null:
		return
	var confirm := dialog.find_child("ConfirmButton", true, false) as Button
	assert_not_null(confirm)
	if confirm != null:
		_press(confirm)
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_golfer_count(), 1, "overwriting replaces, it does not duplicate")
	assert_null(_confirmation(screen), "the dialogue clears once answered")

func test_selecting_a_saved_row_fills_the_name_field() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	var input := screen.find_child("GolferNameInput", true, false) as LineEdit
	if input == null:
		return
	input.text = "Somebody Else Entirely"
	var row := screen.find_child("SavedGolfer_bennelong_star", true, false) as Button
	assert_not_null(row, "the saved entry is on the shelf")
	if row == null:
		return
	_press(row)
	await process_frames(1)
	assert_eq(input.text, "Bennelong Star", "picking a saved row fills the name for an overwrite")
	assert_true(row.button_pressed, "the picked row shows it is picked")

func test_deleting_the_selected_saved_golfer_asks_then_removes_them() -> void:
	var screen := _screen()
	await process_frames(3)
	_press(_save_cta(screen))
	await process_frames(2)
	var row := screen.find_child("SavedGolfer_bennelong_star", true, false) as Button
	assert_not_null(row)
	if row == null:
		return
	_press(row)
	await process_frames(1)
	_press(screen.find_child("DeleteSelectedButton", true, false) as Button)
	await process_frames(2)
	var dialog := _confirmation(screen)
	assert_not_null(dialog, "deleting asks first")
	assert_eq(TournamentLibrary.saved_golfer_count(), 1, "nothing is deleted before the answer")
	if dialog == null:
		return
	_press(dialog.find_child("ConfirmButton", true, false) as Button)
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_golfer_count(), 0)
	assert_null(screen.find_child("SavedGolfer_bennelong_star", true, false),
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
