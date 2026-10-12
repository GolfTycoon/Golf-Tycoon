extends GameTest
## Course records: the record entries and their save format, and the records
## GameManager keeps as golfers hole out and finish their rounds.

# ---------------------------------------------------------------------------
# Empty Records
# ---------------------------------------------------------------------------

func test_create_empty_records() -> void:
	var records = CourseRecords.create_empty_records()
	assert_eq(records.total_hole_in_ones, 0)
	assert_eq(records.lowest_round, null)
	assert_eq(records.hole_in_ones.size(), 0)
	assert_eq(records.best_per_hole.size(), 0)


# ---------------------------------------------------------------------------
# RecordEntry
# ---------------------------------------------------------------------------

func test_record_entry_creation() -> void:
	var entry = CourseRecords.RecordEntry.new("Tiger", 68, 5, 1)
	assert_eq(entry.golfer_name, "Tiger")
	assert_eq(entry.value, 68)
	assert_eq(entry.date_day, 5)
	assert_eq(entry.hole_number, 1)

func test_record_entry_defaults() -> void:
	var entry = CourseRecords.RecordEntry.new()
	assert_eq(entry.golfer_name, "")
	assert_eq(entry.value, 0)
	assert_eq(entry.date_day, 0)
	assert_eq(entry.hole_number, -1)

func test_record_entry_to_dict() -> void:
	var entry = CourseRecords.RecordEntry.new("Alice", 3, 10, 5)
	var d = entry.to_dict()
	assert_eq(d.golfer_name, "Alice")
	assert_eq(d.value, 3)
	assert_eq(d.date_day, 10)
	assert_eq(d.hole_number, 5)

func test_record_entry_from_dict() -> void:
	var d = {"golfer_name": "Bob", "value": 72, "date_day": 3, "hole_number": -1}
	var entry = CourseRecords.RecordEntry.from_dict(d)
	assert_eq(entry.golfer_name, "Bob")
	assert_eq(entry.value, 72)
	assert_eq(entry.date_day, 3)
	assert_eq(entry.hole_number, -1)

func test_record_entry_from_dict_defaults() -> void:
	var entry = CourseRecords.RecordEntry.from_dict({})
	assert_eq(entry.golfer_name, "")
	assert_eq(entry.value, 0)


# ---------------------------------------------------------------------------
# Serialization Round-trip
# ---------------------------------------------------------------------------

func test_serialize_empty_records() -> void:
	var records = CourseRecords.create_empty_records()
	var serialized = CourseRecords.serialize_records(records)
	assert_eq(serialized.total_hole_in_ones, 0)
	assert_eq(serialized.lowest_round, null)
	assert_eq(serialized.hole_in_ones.size(), 0)
	assert_eq(serialized.best_per_hole.size(), 0)

func test_serialize_deserialize_roundtrip() -> void:
	var records = CourseRecords.create_empty_records()
	records.total_hole_in_ones = 3
	records.lowest_round = CourseRecords.RecordEntry.new("Tiger", 65, 10, -1)
	records.hole_in_ones.append(CourseRecords.RecordEntry.new("Tiger", 1, 5, 3))
	records.hole_in_ones.append(CourseRecords.RecordEntry.new("Phil", 1, 7, 1))
	records.best_per_hole[1] = CourseRecords.RecordEntry.new("Alice", 2, 3, 1)
	records.best_per_hole[5] = CourseRecords.RecordEntry.new("Bob", 3, 8, 5)

	var serialized = CourseRecords.serialize_records(records)
	var deserialized = CourseRecords.deserialize_records(serialized)

	assert_eq(deserialized.total_hole_in_ones, 3)
	assert_eq(deserialized.lowest_round.golfer_name, "Tiger")
	assert_eq(deserialized.lowest_round.value, 65)
	assert_eq(deserialized.hole_in_ones.size(), 2)
	assert_eq(deserialized.hole_in_ones[0].golfer_name, "Tiger")
	assert_eq(deserialized.hole_in_ones[1].golfer_name, "Phil")
	assert_eq(deserialized.best_per_hole[1].golfer_name, "Alice")
	assert_eq(deserialized.best_per_hole[5].golfer_name, "Bob")

func test_deserialize_missing_fields() -> void:
	var deserialized = CourseRecords.deserialize_records({})
	assert_eq(deserialized.total_hole_in_ones, 0)
	assert_eq(deserialized.lowest_round, null)
	assert_eq(deserialized.hole_in_ones.size(), 0)

func test_serialize_best_per_hole_uses_string_keys() -> void:
	# JSON keys must be strings, so hole numbers get stringified
	var records = CourseRecords.create_empty_records()
	records.best_per_hole[3] = CourseRecords.RecordEntry.new("Test", 2, 1, 3)
	var serialized = CourseRecords.serialize_records(records)
	assert_true(serialized.best_per_hole.has("3"), "Serialized keys should be strings")

func test_deserialize_converts_string_keys_to_int() -> void:
	var data = {
		"total_hole_in_ones": 0,
		"lowest_round": null,
		"hole_in_ones": [],
		"best_per_hole": {
			"3": {"golfer_name": "Test", "value": 2, "date_day": 1, "hole_number": 3}
		}
	}
	var records = CourseRecords.deserialize_records(data)
	assert_true(records.best_per_hole.has(3), "Deserialized keys should be ints")
	assert_eq(records.best_per_hole[3].golfer_name, "Test")


# ---------------------------------------------------------------------------
# Records broken in play (GameManager)
# ---------------------------------------------------------------------------

func test_check_hole_records_hole_in_one() -> void:
	GameManager.reset_course_records()
	GameManager.current_day = 5
	var records = GameManager.check_hole_records("Tiger", 1, 1)
	assert_eq(records.size(), 1, "Should have one record")
	assert_eq(records[0].type, "hole_in_one", "Record type should be hole_in_one")
	assert_eq(GameManager.course_records.total_hole_in_ones, 1, "Should track hole-in-one count")

func test_check_hole_records_best_score_new() -> void:
	GameManager.reset_course_records()
	GameManager.current_day = 1
	# The first score sets the record; only beating an existing one announces it.
	GameManager.check_hole_records("Alice", 1, 3)
	assert_true(GameManager.course_records.best_per_hole.has(1), "Should have best for hole 1")
	assert_eq(GameManager.course_records.best_per_hole[1].value, 3, "Best score should be 3")

func test_check_hole_records_best_score_broken() -> void:
	GameManager.reset_course_records()
	GameManager.current_day = 1
	GameManager.check_hole_records("Alice", 1, 4)
	var records = GameManager.check_hole_records("Bob", 1, 3)
	var has_hole_record = false
	for record in records:
		if record.type == "hole_record":
			has_hole_record = true
	assert_true(has_hole_record, "Should announce broken hole record")
	assert_eq(GameManager.course_records.best_per_hole[1].golfer_name, "Bob", "Bob should hold record")

func test_check_round_record_first_round() -> void:
	GameManager.reset_course_records()
	GameManager.current_day = 1
	var is_record = GameManager.check_round_record("Alice", 72)
	assert_true(is_record, "First round should always be a course record")
	assert_eq(GameManager.course_records.lowest_round.value, 72)

func test_check_round_record_beaten() -> void:
	GameManager.reset_course_records()
	GameManager.current_day = 1
	GameManager.check_round_record("Alice", 72)
	var is_record = GameManager.check_round_record("Bob", 70)
	assert_true(is_record, "Lower score should beat the record")
	assert_eq(GameManager.course_records.lowest_round.golfer_name, "Bob")

func test_check_round_record_not_beaten() -> void:
	GameManager.reset_course_records()
	GameManager.current_day = 1
	GameManager.check_round_record("Alice", 70)
	var is_record = GameManager.check_round_record("Bob", 72)
	assert_false(is_record, "Higher score should not beat the record")
	assert_eq(GameManager.course_records.lowest_round.golfer_name, "Alice")
