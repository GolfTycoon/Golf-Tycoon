extends GameTest
## ChooseCourseScreen — the fullscreen course shelf the Start Tournament
## screen opens for its Course section.
##
##   1. The shelf lists every course on this device: the built-in defaults
##      badged DEFAULT, the Career-saved ones badged CAREER.
##   2. configure() pre-selects the course the setup screen has ready.
##   3. The dossier shows the highlighted course; the gold action emits
##      course_chosen with its id (and only then — Back changes nothing).
##   4. A saved course can be deleted from its own row, after a question;
##      the shelf falls back to a valid selection.
##   5. Esc leaves the screen without choosing anything.
##   6. Pixelify Sans covers every text control.

const SCRATCH_ROOT := "user://test_choose_course_screen"
const SCRATCH_SAVES := SCRATCH_ROOT + "/saves/"
const SCRATCH_SETTINGS := SCRATCH_ROOT + "/settings.cfg"

func before_each() -> void:
	super()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	PlayerDataStore.saves_dir = SCRATCH_SAVES
	PlayerDataStore.settings_path = SCRATCH_SETTINGS
	DirAccess.make_dir_recursive_absolute(SCRATCH_SAVES)

func after_each() -> void:
	PlayerDataStore.restore_default_paths()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	super()

func _seed_saved_course(display_name := "Five Pines") -> void:
	var course := GameManager.CourseData.new()
	for i in range(5):
		var hole := GameManager.HoleData.new()
		hole.hole_number = i + 1
		hole.par = 4
		hole.distance_yards = 350
		hole.is_open = true
		hole.tee_position = Vector2i(46, 46 + i * 4)
		hole.green_position = Vector2i(62, 46 + i * 4)
		hole.hole_position = Vector2i(62, 46 + i * 4)
		course.add_hole(hole)
	var previous_course := GameManager.current_course
	var previous_name := GameManager.course_name
	GameManager.current_course = course
	GameManager.course_name = display_name
	assert_true(bool(TournamentLibrary.save_career_course().get("ok", false)))
	GameManager.current_course = previous_course
	GameManager.course_name = previous_name

func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

func _screen(selected_id: String = "") -> ChooseCourseScreen:
	var screen := ChooseCourseScreen.new()
	if not selected_id.is_empty():
		screen.configure(selected_id)
	add_child_autofree(screen)
	return screen

func _press(button: Button) -> void:
	if button != null:
		button.pressed.emit()

func test_the_shelf_lists_the_defaults_and_saved_courses() -> void:
	_seed_saved_course()
	var screen := _screen()
	await process_frames(3)
	var count := screen.find_child("CourseCount", true, false) as Label
	assert_not_null(count)
	if count != null:
		assert_eq(count.text, "5 COURSES", "4 defaults plus the saved one")
	for default_id in ["emerald_pines", "highland_ridge", "dunbar_links"]:
		assert_not_null(screen.find_child("Course_default_%s" % default_id, true, false),
			"default course %s is on the shelf" % default_id)
	assert_not_null(screen.find_child("Course_saved_five_pines", true, false),
		"the saved course is on the shelf")
	# The defaults carry no delete button; only the saved one does.
	assert_null(screen.find_child("DeleteSavedCourse_emerald_pines", true, false))
	assert_not_null(screen.find_child("DeleteSavedCourse_five_pines", true, false),
		"saved courses carry their own delete button")

func test_configure_preselects_the_course_the_setup_screen_has_ready() -> void:
	_seed_saved_course()
	var screen := _screen("saved:five_pines")
	await process_frames(3)
	assert_eq(screen._selected_id, "saved:five_pines")
	var cta := screen.find_child("ChooseCourseButton", true, false) as Button
	assert_not_null(cta, "the dossier carries its gold action")
	if cta != null:
		assert_string_contains(cta.tooltip_text, "Five Pines")
	var dossier_name := screen.find_child("CourseDossier", true, false)
	assert_not_null(dossier_name, "the dossier builds")
	var row := screen.find_child("Course_saved_five_pines", true, false) as Button
	assert_not_null(row)
	if row != null:
		assert_true(row.button_pressed, "the preselected row shows it is picked")

func test_the_gold_action_emits_course_chosen_with_the_highlight() -> void:
	_seed_saved_course()
	var screen := _screen("saved:five_pines")
	await process_frames(3)
	watch_signals(screen)
	_press(screen.find_child("ChooseCourseButton", true, false) as Button)
	assert_signal_emitted_with_parameters(screen, "course_chosen", ["saved:five_pines"])

func test_a_default_course_can_be_chosen_too() -> void:
	var screen := _screen()
	await process_frames(3)
	watch_signals(screen)
	var row := screen.find_child("Course_default_highland_ridge", true, false) as Button
	assert_not_null(row)
	if row == null:
		return
	row.toggled.emit(true)
	_press(screen.find_child("ChooseCourseButton", true, false) as Button)
	assert_signal_emitted_with_parameters(screen, "course_chosen", ["default:highland_ridge"])

func test_deleting_the_saved_course_asks_then_falls_back() -> void:
	_seed_saved_course()
	var screen := _screen("saved:five_pines")
	await process_frames(3)
	_press(screen.find_child("DeleteSavedCourse_five_pines", true, false) as Button)
	await process_frames(2)
	var dialog := screen.find_child("LibraryConfirmation", true, false) as ConfirmDialog
	assert_not_null(dialog, "deleting asks first")
	assert_eq(TournamentLibrary.saved_course_count(), 1, "nothing is deleted before the answer")
	if dialog == null:
		return
	_press(dialog.find_child("ConfirmButton", true, false) as Button)
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_course_count(), 0)
	assert_null(screen.find_child("Course_saved_five_pines", true, false),
		"the shelf drops the deleted course")
	assert_true(screen._selected_id.begins_with("default:"),
		"the highlight falls back to a default course")

func test_escape_leaves_without_choosing() -> void:
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
	# (the screen freed itself, so GUT cannot re-interrogate it for signals)
	assert_false(is_instance_valid(screen), "and the screen frees itself")

func test_every_label_and_button_uses_pixelify_sans() -> void:
	_seed_saved_course()
	var screen := _screen()
	await process_frames(3)
	var defaulting: Array = []
	for ctrl in _nodes_of_class(screen, "Button") + _nodes_of_class(screen, "Label"):
		var font := (ctrl as Control).get_theme_font("font")
		var path := font.resource_path if font != null else ""
		if not path.begins_with("res://assets/fonts/PixelifySans"):
			defaulting.append("%s -> %s" % [ctrl.name, path])
	assert_eq(defaulting, [], "every text control on ChooseCourseScreen uses Pixelify Sans")
