extends GameTest
## ChooseGolferScreen — the fullscreen golfer shelf the Start Tournament
## screen opens for its Golfer section.
##
##   1. The shelf lists every golfer on this device: the built-in defaults
##      badged DEFAULT, the Career-saved ones badged CAREER.
##   2. Each golfer is drawn as their own recoloured sprite portrait.
##   3. configure() pre-selects the golfer the setup screen has ready.
##   4. The dossier shows the highlighted golfer; the gold action emits
##      golfer_chosen with its id (and only then — Back changes nothing).
##   5. A saved golfer can be deleted from their own row, after a question;
##      the shelf falls back to a valid selection.
##   6. Esc leaves the screen without choosing anything.
##   7. Pixelify Sans covers every text control.

const SCRATCH_ROOT := "user://test_choose_golfer_screen"
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
	GameManager.player_profile = PlayerGolferProfile.new()
	super()

func _seed_saved_golfer(display_name := "Career Legend") -> void:
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = display_name
	profile.profession = "Masters Champion"
	profile.age = 37
	profile.gender = GolferAttributes.Gender.MALE
	profile.marital_status = GolferAttributes.MaritalStatus.MARRIED
	profile.traits = {"neat": true, "outgoing": true, "active": true, "playful": true, "nice": true}
	profile.golfer_skills = {"length": true, "accuracy": true, "imagination": true}
	profile.initialized = true
	profile.points = [20, 18, 14, 12, 16, 9, 8, 10, 11, 4]
	var result := TournamentLibrary.save_career_golfer(profile, "beginner")
	assert_true(bool(result.get("ok", false)))

func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

func _screen(selected_id: String = "") -> ChooseGolferScreen:
	var screen := ChooseGolferScreen.new()
	if not selected_id.is_empty():
		screen.configure(selected_id)
	add_child_autofree(screen)
	return screen

func _press(button: Button) -> void:
	if button != null:
		button.pressed.emit()

func test_the_shelf_lists_the_defaults_and_saved_golfers() -> void:
	_seed_saved_golfer()
	var screen := _screen()
	await process_frames(3)
	var count := screen.find_child("GolferCount", true, false) as Label
	assert_not_null(count)
	if count != null:
		assert_eq(count.text, "5 GOLFERS", "4 defaults plus the saved one")
	for default_id in ["claire_vance", "marcus_cole", "elena_sato", "arthur_pendleton"]:
		assert_not_null(screen.find_child("Golfer_default_%s" % default_id, true, false),
			"default golfer %s is on the shelf" % default_id)
	assert_not_null(screen.find_child("Golfer_saved_career_legend", true, false),
		"the saved golfer is on the shelf")
	assert_null(screen.find_child("DeleteSavedGolfer_claire_vance", true, false),
		"defaults carry no delete button")
	assert_not_null(screen.find_child("DeleteSavedGolfer_career_legend", true, false),
		"saved golfers carry their own delete button")

## Whether any pixel of `image` paints the golfer in `wanted` (within a couple
## of shades: a group's brightest pixel is scaled by its baked-in shading).
func _image_holds_colour(image: Image, wanted: Color, tolerance: float = 0.02) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.5:
				continue
			if absf(pixel.r - wanted.r) <= tolerance \
					and absf(pixel.g - wanted.g) <= tolerance \
					and absf(pixel.b - wanted.b) <= tolerance:
				return true
	return false

func test_every_golfer_is_drawn_in_their_own_skin_colours() -> void:
	var screen := _screen()
	await process_frames(3)

	var textures: Array[Texture2D] = []
	for gid in ["default:claire_vance", "default:marcus_cole", "default:elena_sato", "default:arthur_pendleton"]:
		var entry := TournamentLibrary.get_golfer(gid)
		var portrait := screen.find_child("GolferPortrait_%s" % gid.replace(":", "_"), true, false) as GolferPortrait
		assert_not_null(portrait, "%s has a sprite portrait on its row" % gid)
		assert_not_null(portrait.sprite_texture, "%s's portrait draws the golfer's skin sprite" % gid)
		assert_true(portrait.custom_minimum_size.y >= 46.0,
			"%s's row is tall enough to draw the sprite" % gid)
		# Every shipped skin paints the Skin group, so it is the one colour each
		# entry is guaranteed to wear whichever skin it is dressed in.
		var skin_tone := Color.from_string(str((entry["skin_colors"] as Dictionary)["Skin"]), Color.WHITE)
		assert_true(_image_holds_colour(portrait.sprite_texture.get_image(), skin_tone),
			"%s's portrait is recoloured with the entry's Skin Colour (#%s)" % [gid, skin_tone.to_html(false)])
		textures.append(portrait.sprite_texture)

	# Claire and Marcus wear the same Casual skin, so their portraits only differ
	# because each one's Skin Colours were applied to the sprite.
	assert_ne(textures[0].get_image().get_data(), textures[1].get_image().get_data(),
		"two golfers sharing a skin still get portraits in their own colours")

func test_configure_preselects_the_golfer_the_setup_screen_has_ready() -> void:
	_seed_saved_golfer()
	var screen := _screen("saved:career_legend")
	await process_frames(3)
	assert_eq(screen._selected_id, "saved:career_legend")
	var cta := screen.find_child("ChooseGolferButton", true, false) as Button
	assert_not_null(cta, "the dossier carries its gold action")
	if cta != null:
		assert_string_contains(cta.tooltip_text, "Career Legend")
	var row := screen.find_child("Golfer_saved_career_legend", true, false) as Button
	assert_not_null(row)
	if row != null:
		assert_true(row.button_pressed, "the preselected row shows it is picked")

func test_the_gold_action_emits_golfer_chosen_with_the_highlight() -> void:
	_seed_saved_golfer()
	var screen := _screen("saved:career_legend")
	await process_frames(3)
	watch_signals(screen)
	_press(screen.find_child("ChooseGolferButton", true, false) as Button)
	assert_signal_emitted_with_parameters(screen, "golfer_chosen", ["saved:career_legend"])

func test_a_default_golfer_can_be_chosen_too() -> void:
	var screen := _screen()
	await process_frames(3)
	watch_signals(screen)
	var row := screen.find_child("Golfer_default_marcus_cole", true, false) as Button
	assert_not_null(row)
	if row == null:
		return
	row.toggled.emit(true)
	_press(screen.find_child("ChooseGolferButton", true, false) as Button)
	assert_signal_emitted_with_parameters(screen, "golfer_chosen", ["default:marcus_cole"])

func test_deleting_the_saved_golfer_asks_then_falls_back() -> void:
	_seed_saved_golfer()
	var screen := _screen("saved:career_legend")
	await process_frames(3)
	_press(screen.find_child("DeleteSavedGolfer_career_legend", true, false) as Button)
	await process_frames(2)
	var dialog := screen.find_child("LibraryConfirmation", true, false) as ConfirmDialog
	assert_not_null(dialog, "deleting asks first")
	assert_eq(TournamentLibrary.saved_golfer_count(), 1, "nothing is deleted before the answer")
	if dialog == null:
		return
	_press(dialog.find_child("ConfirmButton", true, false) as Button)
	await process_frames(2)
	assert_eq(TournamentLibrary.saved_golfer_count(), 0)
	assert_null(screen.find_child("Golfer_saved_career_legend", true, false),
		"the shelf drops the deleted golfer")
	assert_true(screen._selected_id.begins_with("default:"),
		"the highlight falls back to a default golfer")

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
	_seed_saved_golfer()
	var screen := _screen()
	await process_frames(3)
	var defaulting: Array = []
	for ctrl in _nodes_of_class(screen, "Button") + _nodes_of_class(screen, "Label"):
		var font := (ctrl as Control).get_theme_font("font")
		var path := font.resource_path if font != null else ""
		if not path.begins_with("res://assets/fonts/PixelifySans"):
			defaulting.append("%s -> %s" % [ctrl.name, path])
	assert_eq(defaulting, [], "every text control on ChooseGolferScreen uses Pixelify Sans")
