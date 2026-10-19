extends GameTest
## What SaveManager writes and reads back: the holes, the records, the books and
## the hole statistics; loading never replays construction rewards; elevation
## from older save versions migrates; and the save list the archive shows.

const SaveManagerScript := preload("res://scripts/autoload/save_manager.gd")
const SAVE_DIR_PATH := "user://saves/"
const TEST_SAVE := "unit_test_checkpoint"
## A pair of checkpoints for the ordering tests, named so that neither the
## directory order nor the name order agrees with the order they are written.
const TIE_SAVE_A := "unit_test_tie_aaa"
const TIE_SAVE_Z := "unit_test_tie_zzz"

func after_each() -> void:
	for save_name in [TEST_SAVE, "my.save.v2", TIE_SAVE_A, TIE_SAVE_Z]:
		var path: String = SAVE_DIR_PATH + save_name + ".save"
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	super()


# ---------------------------------------------------------------------------
# Holes
# ---------------------------------------------------------------------------

func test_hole_serialization_roundtrip() -> void:
	var first := make_hole(1, Vector2i(10, 20), Vector2i(30, 40), 3)
	first.distance_yards = 150
	first.difficulty_rating = 3.5
	var second := make_hole(2, Vector2i(50, 60), Vector2i(100, 120), 5)
	second.distance_yards = 520
	second.is_open = false
	second.difficulty_rating = 7.0

	var serialized: Array = JSON.parse_string(JSON.stringify(SaveManager._serialize_holes([first, second])))
	assert_eq(serialized.size(), 2, "Should serialize 2 holes")
	assert_eq(int(serialized[0].tee_position.x), 10)
	assert_eq(int(serialized[0].tee_position.y), 20)

	GameManager.current_course = GameManager.CourseData.new()
	SaveManager._deserialize_holes(serialized)
	var holes: Array = GameManager.current_course.holes
	assert_eq(holes.size(), 2)
	assert_eq(holes[0].hole_number, 1)
	assert_eq(holes[0].par, 3)
	assert_eq(holes[0].tee_position, Vector2i(10, 20))
	assert_eq(holes[0].green_position, Vector2i(30, 40))
	assert_eq(holes[0].hole_position, Vector2i(30, 40), "The cup is cut on the green tile")
	assert_eq(holes[0].distance_yards, 150)
	assert_true(holes[0].is_open)
	assert_almost_eq(holes[0].difficulty_rating, 3.5, 0.001)
	assert_eq(holes[1].par, 5)
	assert_false(holes[1].is_open)
	assert_eq(GameManager.current_course.total_par, 8, "The course's par is recounted")

func test_hole_serialization_defaults() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	SaveManager._deserialize_holes([{"hole_number": 1}])
	var hole = GameManager.current_course.holes[0]
	assert_eq(hole.hole_number, 1)
	assert_eq(hole.par, 4, "Default par should be 4")
	assert_true(hole.is_open, "Default should be open")
	assert_almost_eq(hole.difficulty_rating, 1.0, 0.001, "Default difficulty should be 1.0")
	assert_eq(hole.tee_position, Vector2i.ZERO, "A hole record without a tee falls back to the origin")

func test_hole_serialization_empty() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	SaveManager._deserialize_holes([])
	assert_eq(GameManager.current_course.holes.size(), 0)

func test_restoring_holes_does_not_emit_construction_rewards() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	watch_signals(EventBus)
	SaveManager._deserialize_holes([{"hole_number": 1, "par": 4}])
	assert_signal_not_emitted(EventBus, "hole_created", "Loading is not construction")


# ---------------------------------------------------------------------------
# Records, books and statistics
# ---------------------------------------------------------------------------

func test_records_json_roundtrip() -> void:
	var records = CourseRecords.create_empty_records()
	records.total_hole_in_ones = 2
	records.lowest_round = CourseRecords.RecordEntry.new("Tiger", 65, 10, -1)
	records.best_per_hole[3] = CourseRecords.RecordEntry.new("Phil", 2, 5, 3)

	var parsed = JSON.parse_string(JSON.stringify(CourseRecords.serialize_records(records)))
	var restored = CourseRecords.deserialize_records(parsed)

	assert_eq(restored.total_hole_in_ones, 2)
	assert_eq(restored.lowest_round.golfer_name, "Tiger")
	assert_eq(restored.lowest_round.value, 65)
	assert_eq(restored.best_per_hole[3].golfer_name, "Phil")

func test_daily_accounts_survive_json_round_trip() -> void:
	GameManager.daily_stats = GameManager.DailyStatistics.new()
	GameManager.daily_stats.revenue = 540
	GameManager.daily_stats.operating_costs = 150
	GameManager.daily_stats.hired_staff_payroll = 40
	GameManager.daily_stats.marketing_cost = 20
	GameManager.daily_stats.golfers_arrived = 12
	GameManager.daily_stats.tier_counts[GolferTier.Tier.CASUAL] = 7
	SaveManager._restore_daily_stats(JSON.parse_string(JSON.stringify(SaveManager._serialize_daily_stats())))
	assert_eq(GameManager.daily_stats.get_profit(), 390)
	assert_eq(GameManager.daily_stats.golfers_arrived, 12)
	assert_eq(GameManager.daily_stats.hired_staff_payroll, 40)
	assert_eq(GameManager.daily_stats.marketing_cost, 20)
	assert_eq(GameManager.daily_stats.tier_counts[GolferTier.Tier.CASUAL], 7)
	SaveManager._restore_daily_stats({})
	assert_eq(GameManager.daily_stats.revenue, 0, "A save without books starts the day empty")

## Hole statistics are keyed by the public hole number (hole 1 is 1, not 0).
func test_hole_one_statistics_are_keyed_by_public_number() -> void:
	GameManager.hole_statistics = {}
	GameManager.daily_stats = GameManager.DailyStatistics.new()
	GameManager._on_golfer_finished_hole_for_stats(42, 1, 3, 4)
	assert_true(GameManager.hole_statistics.has(1))
	assert_false(GameManager.hole_statistics.has(2))
	assert_eq(GameManager.get_hole_statistics(1).get_average_score(), 3.0)
	var serialized = SaveManager._serialize_hole_statistics()
	SaveManager._restore_hole_statistics(JSON.parse_string(JSON.stringify(serialized)))
	assert_eq(GameManager.get_hole_statistics(1).total_rounds, 1)
	assert_eq(GameManager.get_hole_statistics(1).birdies, 1)
	SaveManager._restore_hole_statistics({})
	assert_true(GameManager.hole_statistics.is_empty(), "Older saves cannot inherit another course's scores")


# ---------------------------------------------------------------------------
# Elevation from older save versions (v3 signed -5..+5 -> v4 levels 0..10)
# ---------------------------------------------------------------------------

func test_pre_v4_elevation_heights_shift_into_the_new_range() -> void:
	# Pre-v4 saves stored signed heights with flat ground at 0. Shifting by
	# BASE_ELEVATION maps the old bottom (-5) to 0, flat (0) to 5, top (+5) to 10.
	var legacy := {"3,3": -5, "4,4": -3, "5,5": 0, "6,6": 2, "7,7": 5}
	var shifted: Dictionary = SaveManagerScript._shift_elevation_dict(legacy, TerrainGrid.BASE_ELEVATION)
	assert_eq(int(shifted["3,3"]), TerrainGrid.MIN_ELEVATION)
	assert_eq(int(shifted["4,4"]), TerrainGrid.BASE_ELEVATION - 3)
	assert_eq(int(shifted["5,5"]), TerrainGrid.BASE_ELEVATION, "old flat ground becomes the base level")
	assert_eq(int(shifted["6,6"]), TerrainGrid.BASE_ELEVATION + 2)
	assert_eq(int(shifted["7,7"]), TerrainGrid.MAX_ELEVATION)

func test_shift_elevation_dict_is_a_no_op_for_current_saves() -> void:
	var current := {"3,3": 0, "4,4": 7}
	assert_eq(SaveManagerScript._shift_elevation_dict(current, 0), current)

func test_elevation_roundtrip_keeps_base_level_sparse() -> void:
	var grid := make_grid(8, 8)
	grid.set_vertex_elevation(Vector2i(3, 3), grid.BASE_ELEVATION + 2)
	grid.set_vertex_elevation(Vector2i(4, 4), grid.MIN_ELEVATION)

	var serialized := grid.serialize_elevation()
	assert_eq(serialized.size(), 2, "only vertices off the base level are stored")
	assert_true(serialized.has("3,3"))
	assert_eq(int(serialized["4,4"]), 0, "level 0 is a stored height, not a missing entry")

	grid.set_vertex_elevation(Vector2i(3, 3), grid.MIN_ELEVATION)
	grid.deserialize_elevation(serialized)
	assert_eq(grid.get_vertex_elevation(Vector2i(3, 3)), grid.BASE_ELEVATION + 2)
	assert_eq(grid.get_vertex_elevation(Vector2i(4, 4)), grid.MIN_ELEVATION)
	assert_eq(grid.get_vertex_elevation(Vector2i(5, 5)), grid.BASE_ELEVATION,
			"missing entries read back as the flat base level")

func test_legacy_tile_elevation_migrates_around_the_base_level() -> void:
	# The pre-v3 save format stored one signed height per tile; shifted by
	# BASE_ELEVATION on load, tiles above the old flat 0 land above the base
	# level. The migration averages tiles onto shared corners, so a lone +2
	# tile becomes a gentle +1 bump — the same smoothing legacy saves always
	# got — and untouched ground keeps the base level exactly.
	var grid := make_grid(8, 8)
	var legacy_tiles := {"4,4": 2}
	grid.migrate_tile_elevation(
			SaveManagerScript._shift_elevation_dict(legacy_tiles, TerrainGrid.BASE_ELEVATION))
	assert_eq(grid.get_elevation(Vector2i(4, 4)), TerrainGrid.BASE_ELEVATION + 1,
			"a +2 legacy tile averages to one level above the base")
	assert_eq(grid.get_elevation(Vector2i(0, 0)), TerrainGrid.BASE_ELEVATION)
	for x in range(9):
		for y in range(9):
			var height: int = grid.get_vertex_elevation(Vector2i(x, y))
			assert_between(height, TerrainGrid.MIN_ELEVATION, TerrainGrid.MAX_ELEVATION)

func test_a_legacy_cart_path_save_loads_as_rough_carrying_a_trail() -> void:
	# Saves from before the cart path terrain was retired stored its gravel as tile
	# id 9. The id keeps its slot in the enum — no other id may move, and the
	# course surface's palette is indexed by id — but nothing is painted with it
	# any more, so loading one migrates each gravel tile to the rough it was laid
	# over and gives it the trail the Path improvement lays now.
	var grid := make_grid(8, 8)
	grid.deserialize({"3,3": TerrainTypes.Type.RETIRED_PATH,
			"4,3": TerrainTypes.Type.ROUGH, "6,6": TerrainTypes.Type.ROUGH})
	# SaveManager hands the trail layer to the grid once the terrain is in.
	grid.deserialize_walking_paths(["6,6"])

	assert_eq(grid.get_tile(Vector2i(3, 3)), TerrainTypes.Type.ROUGH,
			"The gravel becomes the rough it was laid over")
	assert_true(grid.has_walking_path(Vector2i(3, 3)), "and carries the walk it was")
	assert_false(grid.has_walking_path(Vector2i(4, 3)),
			"Ordinary rough the save carried keeps no trail")
	assert_true(grid.has_walking_path(Vector2i(6, 6)),
			"A trail the same save stored as a trail is still one")

	assert_eq(grid.serialize()["3,3"], TerrainTypes.Type.ROUGH,
			"Saving again writes rough: the retired id never goes back to disk")
	assert_true(grid.serialize_walking_paths().has("3,3"),
			"The migrated walk is saved as a walk")


# ---------------------------------------------------------------------------
# The save list
# ---------------------------------------------------------------------------

## Write a save file straight to the saves folder.
func _write_save(save_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR_PATH)
	var file := FileAccess.open(SAVE_DIR_PATH + save_name + ".save", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

## The listed entry for `save_name`, or an empty dictionary.
func _listed(save_name: String) -> Dictionary:
	for entry in SaveManager.get_save_list():
		if entry.get("name", "") == save_name:
			return entry
	return {}

## The archive shows money, holes and difficulty on each card, so the listing
## has to carry them even though the save itself stores them elsewhere.
func test_save_list_carries_the_archive_details() -> void:
	_write_save(TEST_SAVE, {
		"timestamp": "2026-10-01T09:30:00",
		"game_state": {
			"course_name": "Layout Test Links",
			"current_day": 42,
			"money": 250000,
			"reputation": 61.5,
			"difficulty": "hard",
			"theme": "links",
		},
		"holes": [{"hole_number": 1}, {"hole_number": 2}, {"hole_number": 3}],
	})
	var found := _listed(TEST_SAVE)
	assert_false(found.is_empty(), "the written save is listed")
	assert_eq(found.get("course_name", ""), "Layout Test Links")
	assert_eq(int(found.get("day", 0)), 42)
	assert_eq(int(found.get("money", 0)), 250000)
	assert_eq(int(found.get("hole_count", 0)), 3)
	assert_almost_eq(float(found.get("reputation", 0.0)), 61.5, 0.001)
	assert_eq(found.get("difficulty", ""), "hard")
	assert_eq(found.get("theme", ""), "links")

func test_save_list_tolerates_missing_fields() -> void:
	_write_save(TEST_SAVE, {"holes": null, "game_state": {"money": "not a number"}})
	var found := _listed(TEST_SAVE)
	assert_false(found.is_empty(), "a sparse save is still listed")
	assert_eq(int(found.get("money", -1)), 0, "a non-numeric balance reads as zero")
	assert_eq(int(found.get("hole_count", -1)), 0, "missing holes read as none")
	assert_eq(found.get("course_name", ""), "Unknown", "a missing course name keeps the old fallback")

## get_save_list used to strip every ".save" from a name, not just the extension.
func test_save_list_keeps_dots_inside_the_save_name() -> void:
	_write_save("my.save.v2", {"timestamp": "2000-01-01T00:00:00",
		"game_state": {"course_name": "X", "current_day": 1}})
	assert_false(_listed("my.save.v2").is_empty(), "The name keeps its inner '.save' text")

## The title screen's Continue card plays whichever save is first in the list,
## so the newest has to be the same save on every read. A stamp is only good
## to the second, and two checkpoints written inside one second — a year-end
## autosave landing beside a manual save — leave it nothing to sort by, so
## the top of the list used to be whichever the directory listed first.
func test_save_list_keeps_the_newest_save_the_same_between_reads() -> void:
	var same_second := "2026-10-01T09:30:00"
	_write_save(TIE_SAVE_A, {"timestamp": same_second,
		"game_state": {"course_name": "Written First", "current_day": 1}})
	_write_save(TIE_SAVE_Z, {"timestamp": same_second,
		"game_state": {"course_name": "Written Over It", "current_day": 2}})

	var expected: Array = [TIE_SAVE_Z, TIE_SAVE_A]
	var readings: Array = []
	for read in range(5):
		var order: Array = []
		for entry in SaveManager.get_save_list():
			var save_name := str(entry.get("name", ""))
			if save_name.begins_with("unit_test_tie_"):
				order.append(save_name)
		readings.append(order)
		assert_eq(order, expected, "read %d lists the same two, newest first" % read)
	assert_eq(readings[0], readings[4], "and the newest is the same save on the last read as the first")
	assert_ne(int(_listed(TIE_SAVE_Z).get("modified_time", 0)), 0,
		"each entry carries the file's own modified time to break the tie with")

## The tie-break only breaks ties: a save stamped a day earlier is the older of
## the two however the names happen to sort, so the card never resumes it over
## the one actually played last.
func test_save_list_puts_the_newer_stamp_first_whatever_the_names_say() -> void:
	# The alphabetically-first name carries the newer stamp, so a name sort
	# would put the older save on top.
	_write_save(TIE_SAVE_A, {"timestamp": "2026-10-02T09:30:00",
		"game_state": {"course_name": "Played Last", "current_day": 9}})
	_write_save(TIE_SAVE_Z, {"timestamp": "2026-10-01T09:30:00",
		"game_state": {"course_name": "Played First", "current_day": 8}})
	var order: Array = []
	for entry in SaveManager.get_save_list():
		var save_name := str(entry.get("name", ""))
		if save_name.begins_with("unit_test_tie_"):
			order.append(save_name)
	assert_eq(order, [TIE_SAVE_A, TIE_SAVE_Z], "the newer stamp leads, name second")
