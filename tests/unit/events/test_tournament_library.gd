extends GameTest
## Unit tests for TournamentLibrary and PlayerDataStore integration:
##   1. Full golfer details across Default golfers, Career-saved golfers, and
##      AI tournament rosters (Name, Skin, Skin Colours, Profession, Age,
##      Gender, Marital Status, 5 Golfer Traits, 3 Golfer Skills, 10 Golf Skills).
##   2. Difficulty Levels strictly selecting distinct opposing golfer rosters
##      with progressively higher Golf Skills (decoupled from rounds/wind/weather).
##   3. Tournament format types (Stroke Play, Stableford, Modified Stableford,
##      Skins), format rules, and per-hole scoring formulas.
##   4. Career course/golfer persistence and PlayerDataStore erasure.

const SCRATCH_ROOT := "user://test_tournament_library"
const SCRATCH_SAVES := SCRATCH_ROOT + "/saves/"
const SCRATCH_SETTINGS := SCRATCH_ROOT + "/settings.cfg"

func before_each() -> void:
	super()
	_remove_scratch()
	PlayerDataStore.saves_dir = SCRATCH_SAVES
	PlayerDataStore.settings_path = SCRATCH_SETTINGS
	DirAccess.make_dir_recursive_absolute(SCRATCH_SAVES)

func after_each() -> void:
	GameManager.exit_tournament_mode()
	PlayerDataStore.restore_default_paths()
	_remove_scratch()
	super()

func _remove_scratch() -> void:
	PlayerDataStore._remove_tree(SCRATCH_ROOT)

func _assert_complete_golfer_schema(entry: Dictionary, context: String) -> void:
	assert_false(str(entry.get("name", "")).is_empty(), "%s: has name" % context)
	assert_has(["casual", "beginner"], str(entry.get("skin_id", "")), "%s: valid built-in skin_id" % context)
	assert_false(str(entry.get("skin_name", "")).is_empty(), "%s: has skin_name" % context)

	var sc: Dictionary = entry.get("skin_colors", {})
	for grp in ["Shirt", "Pants", "Cap", "Hair", "Skin"]:
		assert_true(sc.has(grp), "%s: skin_colors includes %s" % [context, grp])
		assert_eq(str(sc[grp]).length(), 6, "%s: %s hex colour is 6 chars" % [context, grp])

	assert_false(str(entry.get("profession", "")).is_empty(), "%s: has profession" % context)
	assert_gte(int(entry.get("age", 0)), 18, "%s: adult age" % context)
	assert_has([GolferAttributes.Gender.MALE, GolferAttributes.Gender.FEMALE], int(entry.get("gender", -1)), "%s: valid gender" % context)
	assert_has(["Male", "Female"], str(entry.get("gender_name", "")), "%s: valid gender_name" % context)
	assert_gte(int(entry.get("marital_status", -1)), 0, "%s: marital_status >= 0" % context)
	assert_lte(int(entry.get("marital_status", 99)), 3, "%s: marital_status <= 3" % context)
	assert_has(["Single", "Married", "Divorced", "Widowed"], str(entry.get("marital_status_name", "")), "%s: marital_status_name" % context)

	var traits: Dictionary = entry.get("traits", {})
	for tk in ["neat", "outgoing", "active", "playful", "nice"]:
		assert_true(traits.has(tk), "%s: traits has %s" % [context, tk])

	var gskills: Dictionary = entry.get("golfer_skills", {})
	for gk in ["length", "accuracy", "imagination"]:
		assert_true(gskills.has(gk), "%s: golfer_skills has %s" % [context, gk])

	var pts: Array = entry.get("points", [])
	assert_eq(pts.size(), 10, "%s: has all 10 Golf Skill point slots" % context)
	var gmap: Dictionary = entry.get("golf_skills", {})
	assert_eq(gmap.size(), 10, "%s: golf_skills dictionary names all 10 skills" % context)
	for sk_name in GolferAttributes.GOLF_SKILLS:
		assert_true(gmap.has(sk_name), "%s: golf_skills includes %s" % [context, sk_name])

func test_difficulty_levels_select_distinct_rosters_with_progressively_higher_golf_skills() -> void:
	var diffs := TournamentLibrary.get_difficulties()
	assert_eq(diffs.size(), 4, "four difficulty levels are offered")

	var prev_avg := -1.0
	var seen_names: Dictionary = {}
	for diff in diffs:
		var diff_id := int(diff["id"])
		# Difficulty must NOT hardcode round count, cut rules, wind, or weather
		assert_false(diff.has("rounds"), "difficulty %s is decoupled from round count" % str(diff["name"]))
		assert_false(diff.has("has_cut"), "difficulty %s is decoupled from cut rules" % str(diff["name"]))
		assert_false(diff.has("wind_speed"), "difficulty %s is decoupled from wind" % str(diff["name"]))
		assert_false(diff.has("weather"), "difficulty %s is decoupled from weather" % str(diff["name"]))

		var roster := TournamentLibrary.get_difficulty_roster(diff_id)
		assert_eq(roster.size(), 18, "%s provides an 18-golfer opponent roster" % str(diff["name"]))
		var avg_pct := float(diff["avg_golf_skill_pct"])
		assert_gt(avg_pct, prev_avg, "%s opponents have higher Golf Skills than previous difficulty" % str(diff["name"]))
		prev_avg = avg_pct

		for g in roster:
			var g_name := str(g["name"])
			assert_false(seen_names.has(g_name), "opponent '%s' is unique to its difficulty roster" % g_name)
			seen_names[g_name] = true
			_assert_complete_golfer_schema(g, "%s:%s" % [str(diff["name"]), g_name])

	# Verify build_opponent_roster excludes player name collisions and scales to 24-golfer fields (23 opponents)
	var easy_first_name := str(TournamentLibrary.get_difficulty_roster(TournamentLibrary.Difficulty.EASY)[0]["name"])
	var built := TournamentLibrary.build_opponent_roster(TournamentLibrary.Difficulty.EASY, 23, easy_first_name)
	assert_eq(built.size(), 23)
	for opp in built:
		assert_ne(str(opp["name"]), easy_first_name, "player's own name excluded from opponent list")

func test_default_courses_and_golfers_are_present_with_complete_details() -> void:
	var courses := TournamentLibrary.list_courses()
	assert_eq(courses.size(), 4, "four default courses ship out of the box")
	for c in courses:
		assert_true(bool(c["is_default"]), "%s is marked default" % str(c["name"]))
		assert_gt(int(c["hole_count"]), 0, "%s has playable holes" % str(c["name"]))
		assert_gt((c["preview_holes"] as Array).size(), 0, "%s provides map preview holes" % str(c["name"]))

	var golfers := TournamentLibrary.list_golfers()
	assert_eq(golfers.size(), 4, "four default golfers ship out of the box")
	var names: Array[String] = []
	for g in golfers:
		assert_true(bool(g["is_default"]), "%s is marked default" % str(g["name"]))
		names.append(str(g["name"]))
		_assert_complete_golfer_schema(g, "Default:%s" % str(g["name"]))
		var profile := TournamentLibrary.make_golfer_profile(g)
		assert_eq(profile.golfer_name, str(g["name"]))
		assert_eq(profile.profession, str(g["profession"]))
		assert_eq(profile.age, int(g["age"]))
		assert_eq(profile.gender, int(g["gender"]))
		assert_eq(profile.marital_status, int(g["marital_status"]))
		assert_true(profile.initialized, "default golfer skill profile is initialized")

		var attrs := TournamentLibrary.make_golfer_attributes(g)
		assert_eq(attrs.name, str(g["name"]))
		assert_eq(attrs.profession, str(g["profession"]))
		assert_eq(attrs.age, int(g["age"]))
		assert_eq(attrs.golf_points, g["points"])
		var overrides := TournamentLibrary.skin_color_overrides_from_entry(g)
		assert_eq(overrides.size(), 5, "all 5 skin colour groups produce Color overrides")

	assert_has(names, "Claire Vance")
	assert_has(names, "Marcus Cole")
	assert_has(names, "Elena Sato")
	assert_has(names, "Arthur Pendleton")

func test_saving_career_golfer_persists_full_details_skin_colors_traits_and_skills() -> void:
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = "Sydney Ace"
	profile.profession = "Tour Champion"
	profile.age = 33
	profile.gender = GolferAttributes.Gender.FEMALE
	profile.marital_status = GolferAttributes.MaritalStatus.MARRIED
	profile.initialized = true
	profile.points = [14, 12, 16, 15, 18, 7, 8, 9, 10, 6]
	profile.traits = {
		"neat": true, "outgoing": false, "active": true, "playful": true, "nice": false,
	}
	profile.golfer_skills = {
		"length": true, "accuracy": true, "imagination": false,
	}
	var custom_skin_colors := {
		"Shirt": "1188aa",
		"Pants": "eeece4",
		"Cap": "0d6b87",
		"Hair": "3d2314",
		"Skin": "e8be9e",
	}

	var res := TournamentLibrary.save_career_golfer(profile, "beginner", custom_skin_colors)
	assert_true(bool(res.get("ok", false)), "Career golfer exports cleanly")
	assert_eq(str(res.get("id", "")), "saved:sydney_ace")
	assert_eq(TournamentLibrary.saved_golfer_count(), 1)

	var loaded_entry := TournamentLibrary.get_golfer("saved:sydney_ace")
	assert_false(bool(loaded_entry["is_default"]))
	_assert_complete_golfer_schema(loaded_entry, "Saved:Sydney Ace")
	assert_eq(str(loaded_entry["skin_id"]), "beginner")
	assert_eq(str((loaded_entry["skin_colors"] as Dictionary)["Shirt"]), "1188aa")
	assert_eq(str((loaded_entry["skin_colors"] as Dictionary)["Hair"]), "3d2314")
	assert_eq(str(loaded_entry["profession"]), "Tour Champion")
	assert_eq(int(loaded_entry["age"]), 33)
	assert_eq(int(loaded_entry["gender"]), GolferAttributes.Gender.FEMALE)
	assert_eq(str(loaded_entry["gender_name"]), "Female")
	assert_eq(int(loaded_entry["marital_status"]), GolferAttributes.MaritalStatus.MARRIED)
	assert_eq(str(loaded_entry["marital_status_name"]), "Married")

	var restored := TournamentLibrary.make_golfer_profile(loaded_entry)
	assert_eq(restored.golfer_name, "Sydney Ace")
	assert_eq(restored.profession, "Tour Champion")
	assert_eq(restored.age, 33)
	assert_eq(restored.gender, GolferAttributes.Gender.FEMALE)
	assert_eq(restored.marital_status, GolferAttributes.MaritalStatus.MARRIED)
	assert_true(bool(restored.traits["neat"]))
	assert_true(bool(restored.traits["active"]))
	assert_false(bool(restored.traits["outgoing"]))
	assert_true(bool(restored.golfer_skills["length"]))
	assert_true(bool(restored.golfer_skills["accuracy"]))
	assert_false(bool(restored.golfer_skills["imagination"]))
	assert_eq(restored.points, [14, 12, 16, 15, 18, 7, 8, 9, 10, 6])
	assert_eq(str(restored.appearance["shirt_color"]), "1188aa")

	var career_usage := PlayerDataStore.usage(PlayerDataStore.CAREER)
	assert_true(bool(career_usage["present"]), "PlayerDataStore reports the saved tournament golfer")
	assert_string_contains(str(career_usage["label"]), "1 tournament golfer")

	PlayerDataStore.erase(PlayerDataStore.CAREER)
	assert_eq(TournamentLibrary.saved_golfer_count(), 0, "erasing Career records clears tournament golfers")

func test_format_types_rules_and_hole_scoring_formulas() -> void:
	var formats := TournamentLibrary.get_format_types()
	assert_eq(formats.size(), 4, "Stroke Play, Stableford, Modified Stableford, and Skins are offered")
	assert_eq(TournamentLibrary.ROUND_OPTIONS, [1, 2, 3, 4])
	assert_eq(TournamentLibrary.FIELD_SIZE_OPTIONS, [8, 12, 18, 24])
	assert_eq(TournamentLibrary.get_cut_rules().size(), 3)

	# Traditional Stableford: Albatross 5, Eagle 4, Birdie 3, Par 2, Bogey 1, Double+ 0
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.STABLEFORD, 2, 5), 5)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.STABLEFORD, 2, 4), 4)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.STABLEFORD, 3, 4), 3)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.STABLEFORD, 4, 4), 2)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.STABLEFORD, 5, 4), 1)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.STABLEFORD, 6, 4), 0)

	# Modified Stableford: Albatross +8, Eagle +5, Birdie +2, Par 0, Bogey -1, Double+ -3
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.MODIFIED_STABLEFORD, 2, 5), 8)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.MODIFIED_STABLEFORD, 2, 4), 5)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.MODIFIED_STABLEFORD, 3, 4), 2)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.MODIFIED_STABLEFORD, 4, 4), 0)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.MODIFIED_STABLEFORD, 5, 4), -1)
	assert_eq(TournamentLibrary.hole_points_for_format(TournamentLibrary.FormatType.MODIFIED_STABLEFORD, 6, 4), -3)

	assert_eq(TournamentLibrary.format_score_for_format(TournamentLibrary.FormatType.STROKE_PLAY, -3, 0), "-3")
	assert_eq(TournamentLibrary.format_score_for_format(TournamentLibrary.FormatType.STABLEFORD, 0, 34), "34 pts")
	assert_eq(TournamentLibrary.format_score_for_format(TournamentLibrary.FormatType.SKINS, 0, 1), "1 Skin")
	assert_eq(TournamentLibrary.format_score_for_format(TournamentLibrary.FormatType.SKINS, 0, 4), "4 Skins")

func test_saving_career_course_validates_open_holes_and_supports_deletion() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.course_name = "Unfinished Links"
	var empty_res := TournamentLibrary.save_career_course()
	assert_false(bool(empty_res.get("ok", true)), "cannot export a course with 0 open holes")

	var h1 := GameManager.HoleData.new()
	h1.hole_number = 1
	h1.par = 4
	h1.distance_yards = 365
	h1.is_open = true
	h1.tee_position = Vector2i(50, 50)
	h1.green_position = Vector2i(66, 50)
	h1.hole_position = Vector2i(66, 50)
	GameManager.current_course.add_hole(h1)
	GameManager.course_name = "Harbour Royal"
	GameManager.current_theme = CourseTheme.Type.LINKS

	var ok_res := TournamentLibrary.save_career_course()
	assert_true(bool(ok_res.get("ok", false)), "course with an open hole exports cleanly")
	assert_eq(str(ok_res.get("id", "")), "saved:harbour_royal")
	assert_eq(int(ok_res.get("hole_count", 0)), 1)
	assert_eq(int(ok_res.get("par", 0)), 4)
	assert_eq(TournamentLibrary.saved_course_count(), 1)

	var course_usage := PlayerDataStore.usage(PlayerDataStore.SAVED_COURSES)
	assert_true(bool(course_usage["present"]))
	assert_string_contains(str(course_usage["label"]), "1 tournament course")

	assert_true(TournamentLibrary.delete_saved_course("saved:harbour_royal"))
	assert_eq(TournamentLibrary.saved_course_count(), 0)
