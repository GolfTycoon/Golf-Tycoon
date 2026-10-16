extends GameTest
## GolferAttributes: the golfer attribute model every golfer uses - identity,
## Golfer Traits, Golfer Skills, Golf Skills, Golfer Statuses and Comments -
## plus the status simulation (decay, amenities, fun/attitude) built on it.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make(overrides: Dictionary = {}) -> GolferAttributes:
	var a = GolferAttributes.new()
	a.setup(
		overrides.get("tier", 1),        # CASUAL by default
		overrides.get("patience", 0.5)
	)
	for key in ["fun", "attitude", "energy", "hunger", "thirst", "comfort", "pace"]:
		if overrides.has(key):
			a.set(key, overrides[key])
	return a


# ---------------------------------------------------------------------------
# Section 1: Attribute schema
# ---------------------------------------------------------------------------

func test_identity_fields_exist() -> void:
	var a = GolferAttributes.new()
	assert_true(a.name is String, "Name is text")
	assert_true(a.profession is String, "Profession is text")
	assert_true(a.age is int, "Age is a number")
	assert_true(GolferAttributes.MARITAL_STATUS_NAMES.size() == 4, "Four marital statuses")
	assert_true(GolferAttributes.GENDER_NAMES.size() == 2, "Two genders")

func test_marital_status_options() -> void:
	var a = GolferAttributes.new()
	var names: Array = []
	for status in [a.MaritalStatus.SINGLE, a.MaritalStatus.MARRIED,
			a.MaritalStatus.DIVORCED, a.MaritalStatus.WIDOWED]:
		a.marital_status = status
		names.append(a.marital_status_name())
	assert_eq(names, ["Single", "Married", "Divorced", "Widowed"],
		"Marital status is Single, Married, Divorced, or Widowed")

func test_gender_options() -> void:
	var a = GolferAttributes.new()
	a.gender = a.Gender.MALE
	assert_eq(a.gender_name(), "Male")
	a.gender = a.Gender.FEMALE
	assert_eq(a.gender_name(), "Female")

func test_golfer_traits_are_on_off() -> void:
	var a = GolferAttributes.new()
	assert_eq(GolferAttributes.TRAIT_KEYS, ["neat", "outgoing", "active", "playful", "nice"],
		"All five golfer traits exist")
	for key in GolferAttributes.TRAIT_KEYS:
		assert_true(a.trait_on(key) in [true, false], "%s is On or Off" % key)

func test_golfer_skills_are_on_off() -> void:
	var a = GolferAttributes.new()
	assert_eq(GolferAttributes.GOLFER_SKILL_KEYS, ["length", "accuracy", "imagination"],
		"All three golfer skills exist")
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		assert_true(a.skill_on(key) in [true, false], "%s is On or Off" % key)

func test_golf_skill_names() -> void:
	assert_eq(GolferAttributes.GOLF_SKILLS, [
		"Power Hitter", "Long Driver", "Accurate Driver", "Accurate Irons",
		"Accurate Putter", "Draw Shot (R to L)", "Fade Shot (L to R)",
		"High Backspin Shot", "Recovery Skills", "Luck",
	], "All ten golf skills exist")

func test_golf_skill_each_point_is_ten_percent() -> void:
	var a = GolferAttributes.new()
	a.set_golf_points(0, 0)
	assert_eq(a.golf_skill_percent(0), 0)
	assert_almost_eq(a.golf_bonus(0), 0.0, 0.001)
	a.set_golf_points(0, 1)
	assert_eq(a.golf_skill_percent(0), 10, "One point = +10%")
	a.set_golf_points(0, 12)
	assert_eq(a.golf_skill_percent(0), 120, "Twelve points = +120%")
	assert_almost_eq(a.golf_bonus(0), 1.2, 0.001, "Bonus scales 0.1 per point")

func test_golf_skill_caps_at_990_percent() -> void:
	var a = GolferAttributes.new()
	a.set_golf_points(3, 99)
	assert_eq(a.golf_skill_percent(3), 990, "A skill can go up to 990%")
	a.set_golf_points(3, 150)
	assert_eq(a.golf_skill_percent(3), 990, "It cannot go past 990%")

func test_statuses_start_at_fifty_percent() -> void:
	var a = GolferAttributes.new()
	var statuses: Dictionary = a.statuses()
	assert_eq(statuses.fun, 0.5, "Fun starts at 50%")
	assert_eq(statuses.attitude, 0.5, "Attitude starts at 50%")
	assert_eq(statuses.energy, 0.5, "Energy starts at 50%")
	assert_eq(statuses.hunger, 0.5, "Hunger starts at 50%")
	assert_eq(statuses.thirst, 0.5, "Thirst starts at 50%")

func test_setup_resets_statuses_to_fifty_percent() -> void:
	var a = _make({"fun": 0.1, "attitude": 0.9, "energy": 0.2, "hunger": 0.3, "thirst": 0.4})
	a.setup(1, 0.5)
	assert_eq(a.fun, 0.5, "Fun resets to 50%")
	assert_eq(a.attitude, 0.5, "Attitude resets to 50%")
	assert_eq(a.energy, 0.5, "Energy resets to 50%")
	assert_eq(a.hunger, 0.5, "Hunger resets to 50%")
	assert_eq(a.thirst, 0.5, "Thirst resets to 50%")

func test_comments_start_empty() -> void:
	var a = GolferAttributes.new()
	assert_eq(a.comments.size(), 0)
	assert_eq(a.comment_counts.positive, 0)
	assert_eq(a.comment_counts.neutral, 0)
	assert_eq(a.comment_counts.negative, 0)


# ---------------------------------------------------------------------------
# Section 2: Generation
# ---------------------------------------------------------------------------

func test_generate_for_tier_fills_everything() -> void:
	var a = GolferAttributes.new()
	a.generate_for_tier(2)
	assert_false(a.name.is_empty(), "Name is generated")
	assert_false(a.profession.is_empty(), "Profession is generated")
	assert_between(a.age, 18, 99, "Age is a plausible number")
	assert_true(a.gender in [GolferAttributes.Gender.MALE, GolferAttributes.Gender.FEMALE],
		"Gender is Male or Female")
	assert_true(a.marital_status in [
		GolferAttributes.MaritalStatus.SINGLE, GolferAttributes.MaritalStatus.MARRIED,
		GolferAttributes.MaritalStatus.DIVORCED, GolferAttributes.MaritalStatus.WIDOWED],
		"Marital status is one of the four")

func test_golf_points_respect_bounds() -> void:
	for tier in [0, 1, 2, 3]:
		var a = GolferAttributes.new()
		a.generate_for_tier(tier)
		for i in a.golf_points.size():
			assert_between(a.golf_points[i], 0, GolferAttributes.POINTS_PER_GOLF_SKILL,
				"Golf skill %d stays in 0..99 points (tier %d)" % [i, tier])

func test_golfer_traits_stay_on_off_after_generation() -> void:
	var a = GolferAttributes.new()
	a.generate_for_tier(1)
	for key in GolferAttributes.TRAIT_KEYS:
		assert_true(a.trait_on(key) in [true, false], "%s is On or Off" % key)

func test_shape_skills_halved_without_imagination() -> void:
	# Draw/Fade/Backspin points are halved when Imagination is Off - such a
	# golfer cannot control the ball's behaviour around hazards.
	var without := GolferAttributes.new()
	without.golfer_skills["imagination"] = false
	without.randomize_golf_points(3)
	for index in [GolferAttributes.GolfSkill.DRAW_SHOT,
			GolferAttributes.GolfSkill.FADE_SHOT,
			GolferAttributes.GolfSkill.HIGH_BACKSPIN]:
		assert_lte(without.golf_points[index], 16,
			"Shape skills stay modest without Imagination")

func test_shape_skill_gate() -> void:
	var a = GolferAttributes.new()
	a.set_golfer_skill("imagination", false)
	assert_false(a.can_shape_shots(), "Without Imagination a golfer cannot shape shots")
	assert_eq(a.shape_bend_multiplier(GolferAttributes.GolfSkill.DRAW_SHOT), 0.0,
		"No shape comes off the club without Imagination")
	a.set_golfer_skill("imagination", true)
	assert_true(a.can_shape_shots())
	assert_gt(a.shape_bend_multiplier(GolferAttributes.GolfSkill.DRAW_SHOT), 0.0)


# ---------------------------------------------------------------------------
# Section 3: Comments -> Fun -> Attitude
# ---------------------------------------------------------------------------

func test_positive_comment_raises_fun() -> void:
	var a = _make()
	a.record_comment("Great shot!", "positive")
	assert_gt(a.fun, 0.5, "Positive comments add to Fun")
	assert_gt(a.attitude, 0.5, "Attitude follows the fun")

func test_negative_comment_lowers_fun() -> void:
	var a = _make()
	a.record_comment("Bunker!", "negative")
	assert_lt(a.fun, 0.5, "Negative comments drain Fun")
	assert_lt(a.attitude, 0.5, "Attitude follows the fun")

func test_neutral_comment_is_nearly_flat() -> void:
	var a = _make()
	a.record_comment("Hmm...", "neutral")
	assert_almost_eq(a.fun, 0.5, 0.01, "Neutral comments barely move Fun")

func test_comments_accumulate_by_sentiment() -> void:
	var a = _make()
	a.record_comment("Birdie!", "positive")
	a.record_comment("Nice!", "positive")
	a.record_comment("Bunker!", "negative")
	assert_eq(a.comments.size(), 3)
	assert_eq(a.comment_counts.positive, 2)
	assert_eq(a.comment_counts.negative, 1)
	assert_eq(a.comment_counts.neutral, 0)

func test_comment_text_and_sentiment_are_kept() -> void:
	var a = _make()
	a.record_comment("HOLE IN ONE!", "positive", 3)
	var recent: Array = a.recent_comments(5)
	assert_eq(recent.size(), 1)
	assert_eq(recent[0].text, "HOLE IN ONE!")
	assert_eq(recent[0].sentiment, "positive")
	assert_eq(recent[0].hole, 3)

func test_comments_are_capped() -> void:
	var a = _make()
	for i in GolferAttributes.MAX_COMMENTS + 10:
		a.record_comment("Comment %d" % i, "neutral")
	assert_eq(a.comments.size(), GolferAttributes.MAX_COMMENTS,
		"Only recent comments are kept")

func test_playful_trait_amplifies_fun_gains() -> void:
	var plain = _make()
	plain.record_comment("Birdie!", "positive")
	var playful = _make()
	playful.set_trait("playful", true)
	playful.record_comment("Birdie!", "positive")
	assert_gt(playful.fun, plain.fun, "Playful golfers enjoy the good moments more")

func test_nice_trait_softens_fun_losses() -> void:
	var plain = _make()
	plain.record_comment("Ugh!", "negative")
	var nice = _make()
	nice.set_trait("nice", true)
	nice.record_comment("Ugh!", "negative")
	assert_gt(nice.fun, plain.fun, "Nice golfers shrug off the bad moments")

func test_attitude_settles_toward_fun() -> void:
	var a = _make({"fun": 1.0, "attitude": 0.0})
	a.update_attitude()
	assert_gt(a.attitude, 0.0, "Attitude rises toward the fun being had")
	assert_lt(a.attitude, 1.0, "Attitude moves toward Fun, not instantly to it")


# ---------------------------------------------------------------------------
# Section 4: Status decay and amenity restoration
# ---------------------------------------------------------------------------

func test_on_hole_completed_decays_energy_hunger_thirst() -> void:
	var a = _make()
	a.on_hole_completed()
	assert_lt(a.energy, 0.5, "Energy goes down while the golfer is on the course")
	assert_lt(a.hunger, 0.5, "Hunger goes down while the golfer is on the course")
	assert_lt(a.thirst, 0.5, "Thirst goes down while the golfer is on the course")

func test_casual_exact_decay_per_hole() -> void:
	var a = _make({"tier": 1})
	a.on_hole_completed()
	assert_almost_eq(a.energy, 0.5 - GolferAttributes.ENERGY_DECAY_PER_HOLE, 0.001)
	assert_almost_eq(a.hunger, 0.5 - GolferAttributes.HUNGER_DECAY_PER_HOLE, 0.001)
	assert_almost_eq(a.thirst, 0.5 - GolferAttributes.THIRST_DECAY_PER_HOLE, 0.001)

func test_tier_modifies_decay() -> void:
	var beginner = _make({"tier": 0})
	var pro = _make({"tier": 3})
	beginner.on_hole_completed()
	pro.on_hole_completed()
	assert_gt(beginner.energy, pro.energy, "Beginners tire more slowly than pros")

func test_statuses_clamp_at_zero() -> void:
	var a = _make({"energy": 0.01, "hunger": 0.01, "thirst": 0.01})
	for i in 20:
		a.on_hole_completed()
	assert_eq(a.energy, 0.0, "Energy is clamped at zero")
	assert_eq(a.hunger, 0.0)
	assert_eq(a.thirst, 0.0)

func test_bench_restores_energy() -> void:
	var a = _make({"energy": 0.35})
	a.apply_building_effect("bench")
	assert_almost_eq(a.energy, 0.55, 0.001,
		"Energy goes up when using a bench")

func test_snack_bar_restores_hunger() -> void:
	var a = _make({"hunger": 0.25})
	a.apply_building_effect("snack_bar")
	assert_almost_eq(a.hunger, 0.55, 0.001,
		"Hunger goes up when using a Snack Bar")

func test_snack_bar_takes_edge_off_thirst_too() -> void:
	var a = _make({"thirst": 0.4})
	a.apply_building_effect("snack_bar")
	assert_gt(a.thirst, 0.4, "A snack bar also serves drinks")

func test_drink_vendor_restores_thirst() -> void:
	var a = _make({"thirst": 0.3})
	var boost = a.restore_thirst(0.25)
	assert_almost_eq(a.thirst, 0.55, 0.001,
		"Thirst goes up when using a Drink Vendor")
	assert_gt(boost, 0.0, "The service also lifts attitude")

func test_restores_clamp_at_one() -> void:
	var a = _make({"energy": 0.95, "hunger": 0.95, "thirst": 0.95})
	a.apply_building_effect("bench")
	a.apply_building_effect("snack_bar")
	a.restore_thirst(0.5)
	assert_eq(a.energy, 1.0)
	assert_eq(a.hunger, 1.0)
	assert_eq(a.thirst, 1.0)

func test_clubhouse_tops_up_everything() -> void:
	var a = _make({"energy": 0.4, "hunger": 0.4, "thirst": 0.4, "comfort": 0.4})
	a.apply_building_effect("clubhouse")
	assert_gt(a.energy, 0.4)
	assert_gt(a.hunger, 0.4)
	assert_gt(a.thirst, 0.4)
	assert_gt(a.comfort, 0.4)


# ---------------------------------------------------------------------------
# Section 5: Waiting, fun and satisfaction
# ---------------------------------------------------------------------------

func test_waiting_drains_pace_and_fun() -> void:
	var a = _make()
	a.on_waiting(100)
	assert_lt(a.pace, 1.0, "Waiting drains pace satisfaction")
	assert_lt(a.fun, 0.5, "Waiting around is no fun")

func test_playing_restores_pace() -> void:
	var a = _make({"pace": 0.4})
	a.on_playing(100)
	assert_gt(a.pace, 0.4, "Normal play restores pace")

func test_active_trait_tires_less_and_walks_faster() -> void:
	var plain = _make({"tier": 1})
	var active = _make({"tier": 1})
	active.set_trait("active", true)
	plain.on_hole_completed()
	active.on_hole_completed()
	assert_gt(active.energy, plain.energy, "Active golfers tire more slowly")
	assert_gt(active.walk_speed_multiplier(), plain.walk_speed_multiplier(),
		"Active golfers walk faster")

func test_length_golfer_skill_drives_further() -> void:
	var plain = GolferAttributes.new()
	plain.set_golfer_skill("length", false)
	var long_hitter = GolferAttributes.new()
	long_hitter.set_golfer_skill("length", true)
	assert_gt(long_hitter.distance_multiplier(), plain.distance_multiplier(),
		"Length: how far a golfer is able to drive the ball")

func test_accuracy_golfer_skill_tightens_dispersion() -> void:
	var plain = GolferAttributes.new()
	plain.set_golfer_skill("accuracy", false)
	var precise = GolferAttributes.new()
	precise.set_golfer_skill("accuracy", true)
	assert_lt(precise.dispersion_multiplier(), plain.dispersion_multiplier(),
		"Accuracy: control of how and where the ball lands")

func test_overall_satisfaction_reflects_statuses() -> void:
	var happy = _make({"fun": 1.0, "attitude": 1.0, "energy": 1.0, "hunger": 1.0, "thirst": 1.0})
	var miserable = _make({"fun": 0.0, "attitude": 0.0, "energy": 0.0, "hunger": 0.0, "thirst": 0.0})
	assert_almost_eq(happy.get_overall_satisfaction(), 1.0, 0.001)
	assert_almost_eq(miserable.get_overall_satisfaction(), 0.0, 0.001)

func test_mood_penalty_fires_once_per_critical_episode() -> void:
	var a = _make({"energy": 0.1})
	var first = a.get_mood_penalty()
	assert_lt(first, 0.0, "Critical statuses cost attitude")
	assert_eq(a.get_mood_penalty(), 0.0, "The penalty does not stack")
	a.apply_building_effect("bench")
	a.energy = 0.1
	assert_lt(a.get_mood_penalty(), 0.0, "It fires again after recovery")

func test_need_triggers_fire_once_per_episode() -> void:
	var a = _make({"energy": 0.2, "thirst": 0.2})
	var first = a.check_need_triggers()
	assert_eq(first.size(), 2, "TIRED and THIRSTY fire")
	assert_eq(a.check_need_triggers().size(), 0, "They fire once per episode")

func test_interaction_chance_follows_need() -> void:
	var desperate = _make({"energy": 0.2})
	assert_eq(desperate.get_interaction_chance("bench"),
		GolferAttributes.INTERACT_CHANCE_LOW_NEED, "Desperate golfers always stop")
	var fine = _make({"energy": 0.8})
	assert_eq(fine.get_interaction_chance("bench"),
		GolferAttributes.INTERACT_CHANCE_HIGH_NEED, "Content golfers stroll past")
	assert_eq(fine.get_interaction_chance("pro_shop"),
		GolferAttributes.INTERACT_CHANCE_BASE, "Unmapped buildings use the base chance")


# ---------------------------------------------------------------------------
# Section 6: Serialization
# ---------------------------------------------------------------------------

func test_serialize_round_trip() -> void:
	var a = GolferAttributes.new()
	a.generate_for_tier(2)
	a.name = "Rae Crocodile"
	a.profession = "Architect"
	a.age = 41
	a.gender = GolferAttributes.Gender.FEMALE
	a.marital_status = GolferAttributes.MaritalStatus.MARRIED
	a.record_comment("Nice course!", "positive", 2)
	a.record_comment("Slow play...", "negative", 3)
	a.energy = 0.4

	var restored = GolferAttributes.from_data(JSON.parse_string(JSON.stringify(a.serialize())))
	assert_eq(restored.name, "Rae Crocodile")
	assert_eq(restored.profession, "Architect")
	assert_eq(restored.age, 41)
	assert_eq(restored.gender, GolferAttributes.Gender.FEMALE)
	assert_eq(restored.marital_status, GolferAttributes.MaritalStatus.MARRIED)
	assert_eq(restored.traits, a.traits, "Traits survive the round trip")
	assert_eq(restored.golfer_skills, a.golfer_skills, "Golfer skills survive")
	assert_eq(restored.golf_points, a.golf_points, "Golf skill points survive")
	assert_almost_eq(restored.fun, a.fun, 0.01)
	assert_almost_eq(restored.attitude, a.attitude, 0.01)
	assert_almost_eq(restored.energy, 0.4, 0.01)
	assert_eq(restored.comments.size(), 2, "Comments survive")
	assert_eq(restored.comment_counts.positive, 1)
	assert_eq(restored.comment_counts.negative, 1)

func test_from_data_defaults_are_safe() -> void:
	var restored = GolferAttributes.from_data({})
	assert_false(restored.name.is_empty())
	assert_false(restored.profession.is_empty())
	assert_between(restored.age, 18, 99)
	for i in restored.golf_points.size():
		assert_between(restored.golf_points[i], 0, GolferAttributes.POINTS_PER_GOLF_SKILL)
	assert_eq(restored.statuses().energy, GolferAttributes.STATUS_START)
