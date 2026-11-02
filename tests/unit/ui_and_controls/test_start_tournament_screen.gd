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
