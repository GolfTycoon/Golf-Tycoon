extends GameTest
## CreateModDialog: the Mods screen's New Mod form. It validates as the
## player types, previews what will be written, and creates through the
## manager it is handed - so these tests never touch the real library.
## (scripts/ui/create_mod_dialog.gd)

const ManagerScript := preload("res://scripts/modding/mod_manager.gd")
const RegistryScript := preload("res://scripts/modding/mod_content_registry.gd")
const ROOT := "user://ut_create_mod_dialog"

var _manager: Node = null
var _window_before := Vector2i.ZERO


func before_each() -> void:
	super()
	_window_before = get_window().size
	ModPackage.remove_directory_recursive(ROOT)
	_manager = ManagerScript.new()
	_manager.bundled_root = ROOT.path_join("no_bundled")
	_manager.user_root = ROOT
	_manager.use_steam = false
	var registry: Node = RegistryScript.new()
	add_child_autofree(registry)
	_manager.set_content_registry(registry)
	add_child_autofree(_manager)
	_manager.discover()


func after_each() -> void:
	get_window().size = _window_before
	ModPackage.remove_directory_recursive(ROOT)
	super()


func _open_dialog() -> CreateModDialog:
	var dialog := CreateModDialog.new(_manager)
	add_child_autofree(dialog)
	await process_frames(1)
	return dialog


func _fill(dialog: CreateModDialog, mod_id: String, display_name: String,
		script: bool = true) -> void:
	dialog._id_field.text = mod_id
	dialog._name_field.text = display_name
	dialog._script_check.button_pressed = script
	dialog._update_state()


# ── the form ─────────────────────────────────────────────────────────────

func test_the_form_opens_with_the_fields_the_manifest_needs() -> void:
	var dialog := await _open_dialog()
	assert_not_null(dialog._id_field)
	assert_not_null(dialog._name_field)
	assert_not_null(dialog._author_field)
	assert_not_null(dialog._description_field)
	assert_not_null(dialog._script_check)
	assert_true(dialog._script_check.button_pressed,
		"a starter script is the friendliest default, like mods/_template")
	assert_true(dialog._create_button.disabled, "an empty form cannot create anything")
	assert_true(dialog._feedback.text.to_lower().contains("id"),
		"the form says what is missing instead of only disabling the button")


func test_a_valid_form_enables_create_and_previews_the_folder() -> void:
	var dialog := await _open_dialog()
	_fill(dialog, "tester.typed", "Typed Mod")
	assert_false(dialog._create_button.disabled)
	assert_true(dialog._feedback.text.contains("mods/tester.typed/"),
		"the player sees where the mod will land")
	assert_true(dialog._feedback.text.contains("mod_main.gd"))
	dialog._script_check.button_pressed = false
	dialog._update_state()
	assert_true(dialog._feedback.text.contains("mod.json and README.md"),
		"a data mod previews only the files it writes")


func test_an_unusable_id_keeps_create_disabled_and_explains_it() -> void:
	var dialog := await _open_dialog()
	_fill(dialog, "Not A Mod Id", "Whatever")
	assert_true(dialog._create_button.disabled)
	assert_true(dialog._feedback.text.contains("not usable"))


func test_an_id_already_in_the_library_keeps_create_disabled() -> void:
	var existing: Dictionary = _manager.create_mod({
		"id": "tester.existing", "name": "Existing", "script": false,
	})
	assert_true(bool(existing.get("ok", false)))
	var dialog := await _open_dialog()
	_fill(dialog, "tester.existing", "A Second One")
	assert_true(dialog._create_button.disabled)
	assert_true(dialog._feedback.text.contains("already installed"))


# ── creating ─────────────────────────────────────────────────────────────

func test_creating_writes_the_mod_and_reports_its_id() -> void:
	var dialog := await _open_dialog()
	var made: Array[String] = []
	dialog.created.connect(func(mod_id: String) -> void: made.append(mod_id))
	_fill(dialog, "tester.made_here", "Made Here")
	assert_false(dialog._create_button.disabled)
	dialog._create_button.emit_signal("pressed")
	await process_frames(2)
	assert_eq(made, ["tester.made_here"])
	assert_false(is_instance_valid(dialog), "the form closes itself on success")
	var info: Dictionary = _manager.get_mod_info("tester.made_here")
	assert_eq(info.get("name", ""), "Made Here")
	assert_false(bool(info.get("enabled", true)), "it arrives switched off")
	assert_true(FileAccess.file_exists(ROOT.path_join("tester.made_here/mod.json")))
	assert_true(FileAccess.file_exists(ROOT.path_join("tester.made_here/README.md")))


func test_a_folder_already_on_disk_keeps_the_form_open_with_the_reason() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("tester.on_disk"))
	var dialog := await _open_dialog()
	_fill(dialog, "tester.on_disk", "On Disk")
	assert_false(dialog._create_button.disabled,
		"the live check cannot see a folder the library has not discovered")
	dialog._create_button.emit_signal("pressed")
	await process_frames(1)
	assert_true(is_instance_valid(dialog), "a failed create leaves the form open to fix it")
	assert_true(dialog._feedback.text.contains("already in your mods folder"),
		"and keeps the manager's explanation instead of the ready line")
	assert_false(FileAccess.file_exists(ROOT.path_join("tester.on_disk/mod.json")))


func test_cancel_writes_nothing_and_reports_it() -> void:
	var dialog := await _open_dialog()
	var cancelled: Array[bool] = []
	dialog.cancelled.connect(func() -> void: cancelled.append(true))
	_fill(dialog, "tester.never", "Never Made")
	dialog.find_child("CancelButton", true, false).emit_signal("pressed")
	await process_frames(2)
	assert_eq(cancelled, [true])
	assert_false(is_instance_valid(dialog))
	assert_false(DirAccess.dir_exists_absolute(ROOT.path_join("tester.never")))
	assert_eq(_manager.get_installed_mod_ids(), [])


func test_escape_cancels_the_form() -> void:
	var dialog := await _open_dialog()
	var cancelled: Array[bool] = []
	dialog.cancelled.connect(func() -> void: cancelled.append(true))
	_fill(dialog, "tester.escape_me", "Escape Me")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	dialog._input(esc)
	await process_frames(2)
	assert_eq(cancelled, [true])
	assert_false(is_instance_valid(dialog))
	assert_false(DirAccess.dir_exists_absolute(ROOT.path_join("tester.escape_me")))


# ── shapes ───────────────────────────────────────────────────────────────

func test_the_form_fits_phones_and_short_landscape_windows() -> void:
	for size in [Vector2i(320, 480), Vector2i(720, 390), Vector2i(1600, 1000)]:
		get_window().size = size
		await process_frames(2)
		var dialog := await _open_dialog()
		assert_lte(dialog.get_combined_minimum_size().x, float(size.x),
			"the form does not overflow %dx%d" % [size.x, size.y])
		assert_true(dialog.find_child("CreateModScroll", true, false) is ScrollContainer,
			"short windows can scroll the form")
		dialog.queue_free()
		await process_frames(1)
