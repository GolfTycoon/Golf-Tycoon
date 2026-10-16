extends GameTest
## The guest experience FeedbackManager keeps: patience lost to traffic, the
## incidents guests report and where they happen, the review a visit earns and
## whether the guest comes back, and how bookings limit crowding.

var _saved_experience: Dictionary

func before_each() -> void:
	super()
	_saved_experience = FeedbackManager.serialize_experience()
	FeedbackManager.restore_experience({})
	GameManager.daily_stats = GameManager.DailyStatistics.new()

func after_each() -> void:
	FeedbackManager.restore_experience(_saved_experience)
	super()

## A visiting golfer that is not in the scene, freed after the test.
func _visitor(golfer_name: String = "Visitor") -> Golfer:
	var golfer: Golfer = autofree(Golfer.new())
	golfer.golfer_name = golfer_name
	golfer.attributes = GolferAttributes.new()
	return golfer

func test_normal_play_recovers_patience_but_traffic_reduces_it() -> void:
	var needs := GolferAttributes.new()
	needs.setup(1, 0.5)
	needs.on_waiting(100)
	assert_lt(needs.pace, 0.5)
	var before := needs.pace
	needs.on_playing(100)
	assert_gt(needs.pace, before)
	needs.on_playing(-100)
	assert_gte(needs.pace, before)

func test_incidents_are_located_deduplicated_and_survive_json() -> void:
	var golfer := _visitor()
	golfer.golfer_id = 400
	golfer.current_hole = 3
	FeedbackManager.record_incident(golfer, FeedbackTriggers.TriggerType.HUNGRY)
	FeedbackManager.record_incident(golfer, FeedbackTriggers.TriggerType.HUNGRY)
	assert_eq(FeedbackManager.incidents.size(), 1)
	assert_eq(FeedbackManager.get_hotspots()[0].hole, 4)
	assert_true(FeedbackManager.guest_incident_text(400).contains("Needs food"))
	FeedbackManager.restore_experience(JSON.parse_string(JSON.stringify(FeedbackManager.serialize_experience())))
	assert_eq(FeedbackManager.get_hotspots()[0].count, 1)
	golfer.current_hole = 0
	FeedbackManager.record_incident(golfer, FeedbackTriggers.TriggerType.SHANK)
	golfer.golfer_id = 401
	FeedbackManager.record_incident(golfer, FeedbackTriggers.TriggerType.SHANK)
	FeedbackManager.restore_experience(JSON.parse_string(JSON.stringify(FeedbackManager.serialize_experience())))
	assert_eq(int(FeedbackManager.get_hotspots()[0].trigger), FeedbackTriggers.TriggerType.HUNGRY,
		"Loaded actionable needs outrank mishits")

func test_service_and_value_improvements_raise_visit_score_and_return_intent() -> void:
	var golfer := _visitor()
	golfer.guest_key = "test"
	golfer._round_total_holes = 9
	golfer.paid_round_fee = 500
	golfer.attitude = 0.4
	golfer.needs.energy = 0.1
	golfer.needs.hunger = 0.1
	golfer.needs.comfort = 0.1
	FeedbackManager.record_visit(golfer)
	var poor: Dictionary = FeedbackManager.visits[0].duplicate()
	FeedbackManager.visits.clear()
	golfer.needs.apply_building_effect("bench")
	golfer.needs.apply_building_effect("pub")
	golfer.needs.apply_building_effect("clubhouse")
	golfer.paid_round_fee = 10
	FeedbackManager.record_visit(golfer)
	assert_gt(FeedbackManager.visits[0].score, poor.score)
	assert_gt(FeedbackManager.visits[0].return_intent, poor.return_intent)
	assert_eq(FeedbackManager.customers.size(), 1, "Returning profile updates rather than duplicating")
	FeedbackManager.record_visit(golfer)
	assert_eq(FeedbackManager.visits.size(), 1, "One review per completed visit")

func test_recent_customers_cannot_return_twice_on_the_same_day() -> void:
	FeedbackManager.customers = [{"key": "one", "last_day": GameManager.current_day, "intent": 1.0}]
	for i in range(20):
		assert_true(FeedbackManager.take_returning_guest().is_empty())
	assert_eq(FeedbackManager.returning_today, 0)

func test_new_day_keeps_customers_but_clears_daily_experience() -> void:
	FeedbackManager.customers = [{"key": "one", "last_day": 1, "intent": 0.8}]
	FeedbackManager.service_visits = 4
	FeedbackManager.service_revenue = 20
	FeedbackManager.reset_daily_stats()
	assert_eq(FeedbackManager.customers.size(), 1)
	assert_eq(FeedbackManager.service_visits, 0)
	assert_eq(FeedbackManager.service_revenue, 0)

func test_guest_identity_sequence_survives_save_and_is_not_reused() -> void:
	var first := FeedbackManager.next_guest_key()
	FeedbackManager.restore_experience(JSON.parse_string(JSON.stringify(FeedbackManager.serialize_experience())))
	assert_ne(FeedbackManager.next_guest_key(), first)

func test_recent_satisfaction_is_weighted_by_reviews_and_profit_excludes_rewards() -> void:
	GameManager.daily_history = [
		{"profit": 100, "guest_experience": {"reviews": 1, "satisfaction": 1.0}},
		{"profit": -50, "guest_experience": {"reviews": 3, "satisfaction": 0.0}},
	]
	var recent := FeedbackManager.recent_experience()
	assert_eq(recent.reviews, 4)
	assert_eq(recent.satisfaction, 0.25)
	assert_eq(recent.profit, 25.0)

func test_relaxed_bookings_limit_on_course_crowding() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	for i in range(9):
		GameManager.current_course.add_hole(make_hole(i + 1, Vector2i(i, 0), Vector2i(i, 10)))
	var manager: GolferManager = autofree(GolferManager.new())
	GameManager.tee_booking_interval = 90
	assert_eq(manager.get_max_concurrent_golfers(), 36)
	GameManager.tee_booking_interval = 180
	assert_eq(manager.get_max_concurrent_golfers(), 18)
