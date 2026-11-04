extends GameTest
## Unit tests for StartTournamentScreen:
##   1. Responsive layout breakpoints & Pixelify Sans typography.
##   2. Full Golfer Dossier rendering (Name, Skin + 5 Skin Colour chips,
##      Profession, Age, Gender, Marital Status, 5 Golfer Traits, 3 Golfer
##      Skills, and all 10 Golf Skills).
##   3. Format Type & Format Rules pickers (Stroke Play / Stableford / Modified
##      Stableford / Skins, Rounds, Field Size, Cut Rule, Playoff).
##   4. Community Mod Game Features section (Weather, Wind, Seasons, plus custom
##      mod features when enabled; hidden when all feature mods are disabled).

const SCRATCH_ROOT := "user://test_start_tournament_screen"
const SCRATCH_SAVES := SCRATCH_ROOT + "/saves/"
const SCRATCH_SETTINGS := SCRATCH_ROOT + "/settings.cfg"

var _saved_mod_states: Dictionary = {}

func before_each() -> void:
	super()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	PlayerDataStore.saves_dir = SCRATCH_SAVES
	PlayerDataStore.settings_path = SCRATCH_SETTINGS
	DirAccess.make_dir_recursive_absolute(SCRATCH_SAVES)
	_saved_mod_states.clear()
	for rec in ModManager.get_all_mod_infos():
		var mid := str((rec as Dictionary).get("id", ""))
		if not mid.is_empty():
			_saved_mod_states[mid] = ModManager.is_mod_enabled(mid)

func _erase_custom_feature(fid: String) -> void:
	for i in range(ModManager._start_features.size() - 1, -1, -1):
		if str(ModManager._start_features[i].get("id", "")) == fid:
			ModManager._start_features.remove_at(i)

func after_each() -> void:
	_erase_custom_feature("night_golf")
	var changed := false
	for mid in _saved_mod_states:
		var m_str := str(mid)
		if ModManager.is_mod_enabled(m_str) != bool(_saved_mod_states[mid]):
			ModManager.set_mod_enabled(m_str, bool(_saved_mod_states[mid]))
			changed = true
	if changed:
		ModManager.reload_mods()
	PlayerDataStore.restore_default_paths()
	PlayerDataStore._remove_tree(SCRATCH_ROOT)
	super()

static func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

func test_layout_breakpoints_cover_phone_landscape_tablet_and_desktop() -> void:
	assert_eq(StartTournamentScreen.layout_mode_for(Vector2(390, 844)), StartTournamentScreen.Layout.PHONE)
	assert_eq(StartTournamentScreen.layout_mode_for(Vector2(844, 390)), StartTournamentScreen.Layout.LANDSCAPE)
	assert_eq(StartTournamentScreen.layout_mode_for(Vector2(768, 1024)), StartTournamentScreen.Layout.TABLET)
	assert_eq(StartTournamentScreen.layout_mode_for(Vector2(1600, 1000)), StartTournamentScreen.Layout.WIDE)

func test_tournament_uses_the_shared_header_with_trophy_and_compact_action() -> void:
	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)
	for include_cta in [false, true]:
		var header := autofree(screen._make_header(include_cta)) as HBoxContainer
		assert_eq(header.name, "ScreenHeader")
		var title_box := header.get_node("TitleBlock") as VBoxContainer
		assert_eq(title_box.get_child_count(), 1, "the tournament header has no supporting subtitle")
		assert_eq((title_box.get_node("Title") as Label).text, "Start Tournament")
		var icon := header.get_node("ScreenIcon") as TextureRect
		var header_mode := MenuScreenKit.layout_mode_for(screen._window_size())
		assert_eq(icon.texture, PixelIcon.texture(PixelIcon.Kind.TROPHY,
			int(MenuScreenKit._header_metrics(header_mode)["mark"]), MenuScreenKit.COLOR_GOLD))
		assert_eq(header.get_node("BackButton"), screen._back_button)
		if include_cta:
			assert_eq(header.get_node("Trailing"), screen._start_button)
		else:
			assert_null(header.get_node_or_null("Trailing"))

func test_every_label_and_button_uses_pixelify_sans() -> void:
	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)
	var defaulting: Array = []
	for ctrl in _nodes_of_class(screen, "Button") + _nodes_of_class(screen, "Label"):
		var font := (ctrl as Control).get_theme_font("font")
		var path := font.resource_path if font != null else ""
		if not path.begins_with("res://assets/fonts/PixelifySans"):
			defaulting.append("%s -> %s" % [ctrl.name, path])
	assert_eq(defaulting, [], "every text control on StartTournamentScreen uses Pixelify Sans")

func test_golfer_dossier_renders_full_identity_skin_colors_traits_and_ten_golf_skills() -> void:
	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)
	screen.select_golfer("default:elena_sato")

	assert_eq(screen._golfer_summary_name.text, "Elena Sato")
	assert_string_contains(screen._golfer_summary_role.text, "Course Strategist")
	assert_string_contains(screen._golfer_identity_label.text, "Age 31")
	assert_string_contains(screen._golfer_identity_label.text, "Female")
	assert_string_contains(screen._golfer_identity_label.text, "Married")
	assert_string_contains(screen._golfer_skin_label.text, "Casual")

	for grp in ["Shirt", "Pants", "Cap", "Hair", "Skin"]:
		assert_not_null(screen.find_child("SkinColor_%s" % grp, true, false), "Skin colour swatch %s exists" % grp)
	for tk in ["neat", "outgoing", "active", "playful", "nice"]:
		assert_not_null(screen.find_child("TraitBadge_%s" % tk, true, false), "Trait badge %s exists" % tk)
	for gk in ["length", "accuracy", "imagination"]:
		assert_not_null(screen.find_child("GolferSkillBadge_%s" % gk, true, false), "Golfer skill badge %s exists" % gk)

	assert_eq(screen._golf_skill_rows.size(), 10, "all 10 Golf Skills have dedicated bars in the Golfer Dossier")

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

func test_golfer_rows_show_each_golfers_own_sprite_in_their_skin_colours() -> void:
	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)

	var textures: Array[Texture2D] = []
	for gid in ["default:claire_vance", "default:marcus_cole", "default:elena_sato", "default:arthur_pendleton"]:
		var entry := TournamentLibrary.get_golfer(gid)
		var portrait := screen.find_child("GolferPortrait_%s" % gid.replace(":", "_"), true, false) as GolferPortrait
		assert_not_null(portrait, "%s has a sprite portrait on its row" % gid)
		assert_not_null(portrait.sprite_texture, "%s's portrait draws the golfer's skin sprite" % gid)
		assert_true(portrait._source_rect.size.x < 48.0 and portrait._source_rect.size.y < 48.0,
			"%s's portrait trims the sprite's transparent canvas" % gid)
		assert_true(portrait.custom_minimum_size.y >= 66.0,
			"%s's row is tall enough to draw the sprite at twice its pixel size" % gid)
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

func test_golfer_dossier_portrait_follows_the_selected_golfer() -> void:
	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)

	var portrait := screen._golfer_summary_portrait
	assert_not_null(portrait, "the Golfer Dossier shows a portrait")
	assert_not_null(portrait.sprite_texture, "the dossier portrait draws the selected golfer's sprite")
	var claire_data := portrait.sprite_texture.get_image().get_data()

	screen.select_golfer("default:marcus_cole")
	assert_not_null(portrait.sprite_texture)
	assert_ne(portrait.sprite_texture.get_image().get_data(), claire_data,
		"selecting another golfer swaps the dossier portrait to that golfer's sprite")
	var marcus := TournamentLibrary.get_golfer("default:marcus_cole")
	var skin_tone := Color.from_string(str((marcus["skin_colors"] as Dictionary)["Skin"]), Color.WHITE)
	assert_true(_image_holds_colour(portrait.sprite_texture.get_image(), skin_tone),
		"the dossier portrait wears the selected golfer's Skin Colour")

func test_golfer_portrait_trims_the_empty_sprite_canvas() -> void:
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(5, 7, 10, 20), Color.WHITE)
	var used := GolferPortrait._used_rect(ImageTexture.create_from_image(image))
	assert_eq(used, Rect2(5, 7, 10, 20), "the portrait only draws the part of the sprite that holds the golfer")
	assert_eq(GolferPortrait._used_rect(null), Rect2(), "a golfer with no art reports no sprite to crop")

func test_golfer_portrait_falls_back_to_the_pixel_emblem_when_the_skin_is_gone() -> void:
	var entry := {
		"skin_id": "skin_that_was_deleted",
		"skin_colors": {"Shirt": "c23338", "Pants": "2e333d", "Cap": "292933", "Hair": "1f1a17", "Skin": "80573d"},
	}
	var portrait := autofree(GolferPortrait.new(entry)) as GolferPortrait
	add_child(portrait)
	assert_null(portrait.sprite_texture, "a missing skin has no sprite to draw")
	assert_eq((portrait._emblem_colors["shirt"] as Color).to_html(false), "c23338",
		"the emblem fallback still paints the entry's Skin Colours")
	portrait.set_from_entry(entry)
	assert_eq(portrait._entry_key, GolferPortrait.entry_key(entry))

func test_the_screen_opens_on_a_one_round_event() -> void:
	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)

	assert_eq(TournamentLibrary.DEFAULT_ROUNDS, 1, "1 round is the shipped default")
	assert_eq(int(screen.get_options()["rounds"]), 1, "the screen opens ready to play a single round")
	assert_eq(int(screen._rounds), TournamentLibrary.DEFAULT_ROUNDS)

	var one_btn := screen.find_child("Rounds_1", true, false) as Button
	var two_btn := screen.find_child("Rounds_2", true, false) as Button
	assert_not_null(one_btn, "the 1R chip exists")
	assert_not_null(two_btn, "the 2R chip exists")
	assert_true(one_btn.button_pressed, "the 1R chip starts pressed")
	assert_false(two_btn.button_pressed, "no other round chip starts pressed")

	# A single round has no halfway cut, so the cut picker reads No Cut and the
	# multi-round rules are visibly unavailable until the player asks for more.
	assert_eq(str(screen.get_options()["cut_rule"]), "none", "1 round reports no cut")
	var cut_none_btn := screen.find_child("Cut_none", true, false) as Button
	var cut_50_btn := screen.find_child("Cut_top_50pct", true, false) as Button
	assert_true(cut_none_btn.button_pressed, "No Cut is the selected cut rule")
	assert_true(cut_50_btn.disabled, "a 1-round event disables the halfway-cut rules")
	if screen._dossier_diff_label != null:
		assert_string_contains(screen._dossier_diff_label.text, "1 Round")
	if screen._footer_summary_label != null:
		assert_string_contains(screen._footer_summary_label.text, "1R")

	# The default survives the repopulation the screen does on every resize and
	# when it is configured again from another screen's options.
	screen.refresh()
	assert_eq(int(screen.get_options()["rounds"]), 1, "a rebuild keeps the 1-round default")
	one_btn = screen.find_child("Rounds_1", true, false) as Button
	two_btn = screen.find_child("Rounds_2", true, false) as Button
	cut_50_btn = screen.find_child("Cut_top_50pct", true, false) as Button
	assert_true(one_btn.button_pressed, "the rebuilt 1R chip is pressed")

	var restored := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	restored.configure(screen.get_options())
	add_child(restored)
	assert_eq(int(restored.get_options()["rounds"]), 1, "configure() round-trips the 1-round default")
	assert_true((restored.find_child("Rounds_1", true, false) as Button).button_pressed)

	# Picking 2 rounds turns the halfway cut back on, and 1 round turns it off again.
	two_btn.toggled.emit(true)
	assert_eq(int(screen.get_options()["rounds"]), 2, "2R is still one click away")
	assert_eq(str(screen.get_options()["cut_rule"]), "top_50pct", "2 rounds brings the halfway cut back")
	assert_false(cut_50_btn.disabled, "and its chip is selectable again")
	assert_true(cut_50_btn.button_pressed)
	one_btn.toggled.emit(true)
	assert_eq(int(screen.get_options()["rounds"]), 1, "and 1R takes it away again")
	assert_true(cut_50_btn.disabled)

	# An explicit round choice still wins over the default.
	var picked := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	picked.configure({"rounds": 3})
	add_child(picked)
	assert_eq(int(picked.get_options()["rounds"]), 3, "configure() honours a caller's rounds")
	assert_true((picked.find_child("Rounds_3", true, false) as Button).button_pressed)
	assert_false((picked.find_child("Rounds_1", true, false) as Button).button_pressed)

func test_format_type_rules_difficulty_course_and_golfer_emit_start_options() -> void:
	var custom := PlayerGolferProfile.new()
	custom.golfer_name = "Career Legend"
	custom.profession = "Masters Champion"
	custom.age = 37
	custom.gender = GolferAttributes.Gender.MALE
	custom.marital_status = GolferAttributes.MaritalStatus.MARRIED
	custom.initialized = true
	TournamentLibrary.save_career_golfer(custom, "beginner")

	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)

	screen.select_difficulty(TournamentLibrary.Difficulty.CHAMPIONSHIP)
	screen.select_format_type(TournamentLibrary.FormatType.MODIFIED_STABLEFORD)
	screen.select_rounds(4)
	screen.select_field_size(18)
	screen.select_cut_rule("top_10_ties")
	screen.set_playoff_enabled(false)
	screen.select_course("default:dunbar_links")
	screen.select_golfer("saved:career_legend")

	var captured: Array = []
	screen.start_requested.connect(func(emitted: Dictionary) -> void: captured.append(emitted))
	var start_btn := screen.find_child("StartTournamentButton", true, false) as Button
	assert_not_null(start_btn, "Start Tournament CTA exists")
	start_btn.pressed.emit()

	assert_eq(captured.size(), 1)
	var opts: Dictionary = captured[0]
	assert_eq(int(opts["difficulty"]), TournamentLibrary.Difficulty.CHAMPIONSHIP)
	assert_eq(int(opts["format_type"]), TournamentLibrary.FormatType.MODIFIED_STABLEFORD)
	assert_eq(str(opts["format_name"]), "Modified Stableford")
	assert_eq(int(opts["rounds"]), 4)
	assert_eq(int(opts["field_size"]), 18)
	assert_eq(str(opts["cut_rule"]), "top_10_ties")
	assert_false(bool(opts["playoff"]))
	assert_eq(str(opts["course_id"]), "default:dunbar_links")
	assert_eq(str(opts["golfer_id"]), "saved:career_legend")
	assert_eq(str(opts["golfer_name"]), "Career Legend")
	assert_eq(str(opts["golfer_skin_id"]), "beginner")

	# Selecting 1 round automatically disables cut-line rules and reports cut_rule = "none"
	screen.select_rounds(1)
	var cut_50_btn := screen.find_child("Cut_top_50pct", true, false) as Button
	assert_not_null(cut_50_btn)
	assert_true(cut_50_btn.disabled, "1-round events disable multi-round cut options")
	assert_eq(str(screen.get_options()["cut_rule"]), "none")

	# Delete the Career-saved golfer via its Delete button and confirm fallback to default
	var del_btn := screen.find_child("DeleteSavedGolfer_career_legend", true, false) as Button
	assert_not_null(del_btn, "Career-saved golfer exposes a delete button")
	del_btn.pressed.emit()
	await wait_frames(2)
	assert_eq(TournamentLibrary.saved_golfer_count(), 0)
	assert_true(str(screen.get_options()["golfer_id"]).begins_with("default:"),
		"selection falls back cleanly to a default golfer after deletion")

func test_community_mod_features_appear_when_enabled_and_hide_when_disabled() -> void:
	# Ensure built-in Weather, Wind, and Seasons mods are enabled, plus a custom mod feature
	ModManager.set_mod_enabled("golf_tycoon.weather", true)
	ModManager.set_mod_enabled("golf_tycoon.wind", true)
	ModManager.set_mod_enabled("golf_tycoon.seasons", true)
	ModManager.reload_mods()
	ModManager.register_feature_option("test.night", {
		"id": "night_golf",
		"title": "Night Golf",
		"description": "Floodlit fairways and glowing golf balls.",
		"default": false,
	})

	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)

	assert_true(screen.has_feature_section(), "Game Features section is shown when feature mods are enabled")
	assert_not_null(screen.find_child("GameFeaturesSection", true, false))
	assert_not_null(screen.find_child("Feature_weather", true, false))
	assert_not_null(screen.find_child("Feature_wind", true, false))
	assert_not_null(screen.find_child("Feature_seasons", true, false))
	assert_not_null(screen.find_child("Feature_night_golf", true, false))

	var initial_feats: Dictionary = screen.get_options()["features"]
	assert_true(bool(initial_feats["weather"]))
	assert_false(bool(initial_feats["night_golf"]), "custom mod feature honours its registered default=false")

	screen.set_feature_enabled("weather", false)
	screen.set_feature_enabled("night_golf", true)
	var updated_feats: Dictionary = screen.get_options()["features"]
	assert_false(bool(updated_feats["weather"]))
	assert_true(bool(updated_feats["night_golf"]))

	# Disable all feature mods and unregister custom feature -> section disappears completely
	ModManager.set_mod_enabled("golf_tycoon.weather", false)
	ModManager.set_mod_enabled("golf_tycoon.wind", false)
	ModManager.set_mod_enabled("golf_tycoon.seasons", false)
	ModManager.reload_mods()
	_erase_custom_feature("night_golf")
	screen.refresh()
	await wait_frames(1)

	assert_false(screen.has_feature_section(), "Game Features section hides when no feature mods are enabled")
	assert_null(screen.find_child("GameFeaturesSection", true, false))
	assert_eq((screen.get_options()["features"] as Dictionary).size(), 0)

func test_auto_field_size_option_doubles_selected_course_holes_and_roundtrips() -> void:
	# Export a 5-hole Career course and a 1-hole Career course to test custom hole counts too
	GameManager.current_course = GameManager.CourseData.new()
	for i in range(5):
		var h := GameManager.HoleData.new()
		h.hole_number = i + 1
		h.par = 4
		h.distance_yards = 350
		h.is_open = true
		h.tee_position = Vector2i(46, 46 + i * 4)
		h.green_position = Vector2i(62, 46 + i * 4)
		h.hole_position = Vector2i(62, 46 + i * 4)
		GameManager.current_course.add_hole(h)
	GameManager.course_name = "Five Pines"
	assert_true(bool(TournamentLibrary.save_career_course().get("ok", false)))

	GameManager.current_course = GameManager.CourseData.new()
	var h_one := GameManager.HoleData.new()
	h_one.hole_number = 1
	h_one.par = 3
	h_one.distance_yards = 165
	h_one.is_open = true
	h_one.tee_position = Vector2i(50, 50)
	h_one.green_position = Vector2i(60, 50)
	h_one.hole_position = Vector2i(60, 50)
	GameManager.current_course.add_hole(h_one)
	GameManager.course_name = "Solo Green"
	assert_true(bool(TournamentLibrary.save_career_course().get("ok", false)))

	var screen := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	add_child(screen)

	var auto_btn := screen.find_child("FieldSize_Auto", true, false) as Button
	var fs12_btn := screen.find_child("FieldSize_12", true, false) as Button
	var fs18_btn := screen.find_child("FieldSize_18", true, false) as Button
	assert_not_null(auto_btn, "FieldSize_Auto chip exists on StartTournamentScreen")
	assert_not_null(fs12_btn)
	assert_not_null(fs18_btn)

	# Default selection is Auto on Emerald Pines (9 holes -> 18 golfers)
	assert_true(screen.is_field_size_auto(), "Auto field size is selected by default")
	assert_true(auto_btn.button_pressed, "Auto button starts pressed")
	assert_false(fs18_btn.button_pressed, "Fixed 18 button is not simultaneously pressed when Auto=18")
	assert_eq(auto_btn.text, "Auto (18)")
	assert_eq(int(screen.get_options()["field_size"]), 18, "9-hole Emerald Pines -> Auto field size 18")
	assert_true(bool(screen.get_options()["field_size_auto"]))
	if screen._dossier_diff_label != null:
		assert_string_contains(screen._dossier_diff_label.text, "18 Golfers (Auto)")
	if screen._footer_summary_label != null:
		assert_string_contains(screen._footer_summary_label.text, "Auto 18P")

	# Selecting 18-hole Dunbar Links doubles to 36 golfers
	screen.select_course("default:dunbar_links")
	assert_eq(auto_btn.text, "Auto (36)")
	assert_eq(int(screen.get_options()["field_size"]), 36, "18-hole Dunbar Links -> Auto field size 36")
	if screen._dossier_diff_label != null:
		assert_string_contains(screen._dossier_diff_label.text, "36 Golfers (Auto)")
	if screen._footer_summary_label != null:
		assert_string_contains(screen._footer_summary_label.text, "Auto 36P")

	# Selecting 6-hole Highland Ridge doubles to 12 golfers (without highlighting fixed 12)
	screen.select_course("default:highland_ridge")
	assert_eq(auto_btn.text, "Auto (12)")
	assert_eq(int(screen.get_options()["field_size"]), 12, "6-hole Highland Ridge -> Auto field size 12")
	assert_true(auto_btn.button_pressed)
	assert_false(fs12_btn.button_pressed)

	# Selecting 5-hole and 1-hole saved Career courses doubles to 10 and 2 golfers
	screen.select_course("saved:five_pines")
	assert_eq(auto_btn.text, "Auto (10)")
	assert_eq(int(screen.get_options()["field_size"]), 10, "5-hole saved course -> Auto field size 10")

	screen.select_course("saved:solo_green")
	assert_eq(auto_btn.text, "Auto (2)")
	assert_eq(int(screen.get_options()["field_size"]), 2, "1-hole saved course -> Auto field size 2")

	# Toggling a fixed field size disables Auto and keeps the fixed size across course changes
	fs18_btn.toggled.emit(true)
	assert_false(screen.is_field_size_auto())
	assert_false(auto_btn.button_pressed)
	assert_true(fs18_btn.button_pressed)
	screen.select_course("default:dunbar_links")
	assert_eq(int(screen.get_options()["field_size"]), 18, "fixed 18 stays 18 on 18-hole Dunbar Links")
	assert_false(bool(screen.get_options()["field_size_auto"]))
	assert_eq(auto_btn.text, "Auto (36)", "Auto chip still previews 2x holes for the selected course")

	# Clicking Auto button re-enables Auto (36 on Dunbar Links), and clicking it again keeps it pressed
	auto_btn.toggled.emit(true)
	assert_true(screen.is_field_size_auto())
	assert_true(auto_btn.button_pressed)
	assert_false(fs18_btn.button_pressed)
	assert_eq(int(screen.get_options()["field_size"]), 36)
	auto_btn.toggled.emit(false)
	assert_true(auto_btn.button_pressed, "re-clicking active Auto radio chip keeps it pressed")

	# Roundtrip via configure() preserves both Auto and fixed field size choices
	var auto_opts := screen.get_options()
	var restored_auto := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	restored_auto.configure(auto_opts)
	add_child(restored_auto)
	assert_true(restored_auto.is_field_size_auto(), "configure() preserves field_size_auto=true")
	assert_eq(int(restored_auto.get_options()["field_size"]), 36)

	restored_auto.select_field_size(24)
	var fixed_opts := restored_auto.get_options()
	var restored_fixed := autofree(StartTournamentScreen.new()) as StartTournamentScreen
	restored_fixed.configure(fixed_opts)
	add_child(restored_fixed)
	assert_false(restored_fixed.is_field_size_auto(), "configure() preserves field_size_auto=false")
	assert_eq(int(restored_fixed.get_options()["field_size"]), 24)

