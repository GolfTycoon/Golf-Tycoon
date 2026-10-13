extends GameTest
## The Generating Course screen's wording, progress mapping and breakpoints.
##
## GeneratingCourseScreen is built from code, so the parts worth pinning down
## without a window are the pure ones: which checklist a job gets, how the
## holes phase and the subtitle are worded, where the progress bar sits when
## each stage starts, and which windows get the compact and tiny layouts.

func test_quick_start_checklist_has_three_holes_and_paths() -> void:
	var holes := GeneratingCourseScreen.holes_stage_text(true, 0, false)
	var stages := GeneratingCourseScreen.stages_for_job(holes, true)
	assert_eq(stages, [
		GeneratingCourseScreen.STAGE_TERRAIN,
		"Laying out 3 holes",
		GeneratingCourseScreen.STAGE_CLUBHOUSE,
		GeneratingCourseScreen.STAGE_PATHS,
		GeneratingCourseScreen.STAGE_OPENING,
	], "quick start builds the full five-stage checklist")

func test_generated_holes_are_worded_with_their_count() -> void:
	assert_eq(GeneratingCourseScreen.holes_stage_text(false, 6, false),
		"Laying out 6 holes", "six requested holes")
	assert_eq(GeneratingCourseScreen.holes_stage_text(false, 18, false),
		"Laying out 18 holes", "eighteen requested holes")

func test_prebuilt_checklist_names_the_ready_made_course() -> void:
	var holes := GeneratingCourseScreen.holes_stage_text(false, 0, true)
	var stages := GeneratingCourseScreen.stages_for_job(holes, true)
	assert_has(stages, "Building the ready-made course", "the holes phase")
	assert_has(stages, GeneratingCourseScreen.STAGE_PATHS, "paths are laid for it")

func test_empty_lot_has_no_holes_or_paths_stage() -> void:
	var holes := GeneratingCourseScreen.holes_stage_text(false, 0, false)
	assert_eq(holes, "", "an empty lot has no holes phase")
	var stages := GeneratingCourseScreen.stages_for_job(holes, false)
	assert_eq(stages, [
		GeneratingCourseScreen.STAGE_TERRAIN,
		GeneratingCourseScreen.STAGE_CLUBHOUSE,
		GeneratingCourseScreen.STAGE_OPENING,
	], "an empty lot keeps only the three stages that run")

func test_checklist_always_starts_with_terrain_and_ends_with_opening_day() -> void:
	for holes in ["Laying out 3 holes", "Building the ready-made course", ""]:
		for with_paths in [true, false]:
			var stages := GeneratingCourseScreen.stages_for_job(holes, with_paths)
			assert_eq(stages[0], GeneratingCourseScreen.STAGE_TERRAIN,
				"first stage of %s" % [stages])
			assert_eq(stages[stages.size() - 1], GeneratingCourseScreen.STAGE_OPENING,
				"last stage of %s" % [stages])

func test_subtitle_names_the_theme_and_the_job() -> void:
	assert_eq(GeneratingCourseScreen.subtitle_for_job("Parkland", true, 0, false),
		"Parkland | 3 holes", "quick start")
	assert_eq(GeneratingCourseScreen.subtitle_for_job("Links", false, 18, false),
		"Links | 18 holes", "generated holes")
	assert_eq(GeneratingCourseScreen.subtitle_for_job("Desert", false, 0, true),
		"Desert | Ready-made course", "prebuilt package")
	assert_eq(GeneratingCourseScreen.subtitle_for_job("Mountain", false, 0, false),
		"Mountain | Empty lot", "empty lot")

func test_progress_bar_fills_one_stage_at_a_time() -> void:
	assert_eq(GeneratingCourseScreen.fraction_for_stage(0, 5), 0.1, "entering the first stage")
	assert_eq(GeneratingCourseScreen.fraction_for_stage(2, 5), 0.5, "entering the middle stage")
	assert_eq(GeneratingCourseScreen.fraction_for_stage(4, 5), 0.9, "entering the last stage")
	assert_eq(GeneratingCourseScreen.fraction_for_stage(0, 3), 0.5 / 3.0, "a shorter job's first stage")

func test_progress_mapping_is_clamped() -> void:
	assert_eq(GeneratingCourseScreen.fraction_for_stage(-1, 5), 0.0, "before the first stage")
	assert_eq(GeneratingCourseScreen.fraction_for_stage(9, 5), 1.0, "past the last stage")
	assert_eq(GeneratingCourseScreen.fraction_for_stage(0, 0), 0.0, "no stages at all")

func test_compact_layout_covers_phones_and_short_windows() -> void:
	assert_true(GeneratingCourseScreen.is_compact(Vector2(390, 844)), "phone portrait")
	assert_true(GeneratingCourseScreen.is_compact(Vector2(844, 390)), "rotated phone")
	assert_true(GeneratingCourseScreen.is_compact(Vector2(600, 500)), "narrow short window")
	assert_false(GeneratingCourseScreen.is_compact(Vector2(1600, 1000)), "desktop")
	assert_false(GeneratingCourseScreen.is_compact(Vector2(1024, 768)), "tablet landscape")

func test_tiny_layout_keeps_only_short_windows() -> void:
	assert_true(GeneratingCourseScreen.is_tiny(Vector2(844, 390)), "rotated phone")
	assert_true(GeneratingCourseScreen.is_tiny(Vector2(1920, 400)), "short and very wide")
	assert_false(GeneratingCourseScreen.is_tiny(Vector2(390, 844)), "phone portrait keeps its checklist")
	assert_false(GeneratingCourseScreen.is_tiny(Vector2(1600, 1000)), "desktop")

func test_tips_are_all_short_single_sentences() -> void:
	assert_gt(GeneratingCourseScreen.TIPS.size(), 0, "there are tips to show")
	for tip in GeneratingCourseScreen.TIPS:
		assert_false(str(tip).is_empty(), "no blank tip")
		assert_lte(str(tip).length(), 120, "tip fits two lines: %s" % tip)

## The card measures itself from Screen.window_size, which is whatever the
## headless test window happens to be - the build tests set the size they
## need, and it is put back after each test.
var _previous_window_size := Vector2(1600, 1000)

func before_each() -> void:
	super()
	_previous_window_size = Screen.window_size

func after_each() -> void:
	Screen.window_size = _previous_window_size
	super()

func _screen(course_name: String = "Pebble Bay Golf Club",
		window_size: Vector2 = Vector2(1600, 1000)) -> GeneratingCourseScreen:
	Screen.window_size = window_size
	var screen := autofree(GeneratingCourseScreen.new()) as GeneratingCourseScreen
	var holes := GeneratingCourseScreen.holes_stage_text(true, 0, false)
	screen.setup(course_name, "Links | 3 holes",
		GeneratingCourseScreen.stages_for_job(holes, true),
		"Coastal links course with golden fescue rough.")
	add_child(screen)
	return screen

## Pip states down the built checklist, in stage order.
func _pip_states(screen: GeneratingCourseScreen) -> Array:
	var states: Array = []
	var list := screen.get_node_or_null("Root/Center/Card/Column/Stages")
	if list == null:
		return states
	for row in list.get_children():
		states.append(row.get_child(0).get("pip_state"))
	return states

func test_builds_the_card_with_the_course_name_and_checklist() -> void:
	var screen := _screen()
	assert_not_null(screen.get_node_or_null("Root/Center/Card"), "the card")
	var title := screen.get_node_or_null("Root/Center/Card/Column/Header/TitleBlock/CourseName")
	assert_not_null(title, "the course name label")
	assert_eq(title.text, "Pebble Bay Golf Club", "the course name")
	assert_eq(_pip_states(screen).size(), 5, "the five quick-start stages")
	var tip := screen.get_node_or_null("Root/Center/Card/Column/TipBox/Content/Tip")
	assert_not_null(tip, "the tip box")
	assert_eq(tip.text, "Coastal links course with golden fescue rough.",
		"the theme description is the first tip")

func test_stages_complete_in_order_as_they_start() -> void:
	var screen := _screen()
	screen.set_stage_by_title(GeneratingCourseScreen.STAGE_TERRAIN)
	assert_eq(_pip_states(screen), [1, 0, 0, 0, 0], "terrain running, the rest pending")
	screen.set_stage_by_title(GeneratingCourseScreen.STAGE_PATHS)
	assert_eq(_pip_states(screen), [2, 2, 2, 1, 0], "paths running, earlier stages done")
	screen.set_stage_by_title("A phase that was skipped")
	assert_eq(_pip_states(screen), [2, 2, 2, 1, 0], "unknown titles are ignored")
	screen.finish()
	assert_eq(_pip_states(screen), [2, 2, 2, 2, 2], "everything done")
	assert_eq(screen.get("_display_fraction"), 1.0, "the bar is full")

func test_empty_jobs_build_without_a_checklist() -> void:
	var screen := autofree(GeneratingCourseScreen.new()) as GeneratingCourseScreen
	screen.setup("New Course", "", [], "")
	add_child(screen)
	assert_not_null(screen.get_node_or_null("Root/Center/Card"), "the card still builds")
	assert_null(screen.get_node_or_null("Root/Center/Card/Column/Stages"), "no checklist")
	screen.set_stage(0)
	screen.finish()

func test_compact_and_tiny_windows_build_smaller_cards() -> void:
	var phone := _screen("Phone Course", Vector2(390, 844))
	assert_null(phone.get_node_or_null("Root/Center/Card/Column/TipBox"),
		"phones lose the tip box")
	assert_eq(_pip_states(phone).size(), 5, "phones keep the checklist")
	var rotated := _screen("Rotated Course", Vector2(844, 390))
	assert_null(rotated.get_node_or_null("Root/Center/Card/Column/TipBox"),
		"short windows lose the tip box")
	assert_null(rotated.get_node_or_null("Root/Center/Card/Column/Stages"),
		"short windows lose the checklist too")

func test_the_card_animates_without_errors() -> void:
	var screen := _screen()
	screen.set_stage_by_title(GeneratingCourseScreen.STAGE_TERRAIN)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(screen.get("_display_fraction"), 0.0, "the bar eases towards its target")
	assert_not_null(screen.get_node_or_null("Root/Center/Card"), "the card survives its own animation")
