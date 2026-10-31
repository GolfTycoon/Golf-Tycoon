extends GameTest
## Visiting golfer cards: the per-location pools in `data/visiting_golfers/`.
##
## Every card carries a unique name and a full attribute block - Profession,
## Marital Status, Age, Gender, Golfer Traits, Golfer Skills and Golf Skills -
## and that block is what the golfer spawns with.

const MARITAL_STATUS_NAMES: Array[String] = ["Single", "Married", "Divorced", "Widowed"]
const GENDER_NAMES: Array[String] = ["Male", "Female"]
const SWITCHES: Array[String] = ["traits", "golfer_skills"]


## Every visiting golfer card in the game, as {location: [card, ...]}.
func _pools() -> Dictionary:
	var pools := {}
	for location in WorldLocations.LOCATIONS:
		var id := str(location.get("id", ""))
		pools[id] = WorldLocations.get_visiting_golfers(id)
	return pools


# ---------------------------------------------------------------------------
# The data
# ---------------------------------------------------------------------------

func test_every_location_has_a_pool_of_visitors() -> void:
	var pools := _pools()
	assert_eq(pools.size(), WorldLocations.LOCATIONS.size(),
		"Every world map location has a visitor file")
	for id in pools:
		var pool: Array = pools[id]
		assert_false(pool.is_empty(), "%s has visitors" % id)

func test_every_card_carries_the_full_attribute_block() -> void:
	var pools := _pools()
	for id in pools:
		for card in pools[id]:
			var where := "%s / %s" % [id, card.get("name", "?")]
			for field in ["name", "skin_id", "tier", "profession", "marital_status",
					"age", "gender", "traits", "golfer_skills", "golf_skills",
					"group_colors"]:
				assert_true(card.has(field), "%s carries %s" % [where, field])
			assert_gt(str(card["name"]).length(), 0, "%s is named" % where)
			assert_gt(str(card["profession"]).strip_edges().length(), 0,
				"%s has a profession" % where)
			assert_true(str(card["marital_status"]) in MARITAL_STATUS_NAMES,
				"%s has a marital status the game knows" % where)
			assert_true(str(card["gender"]) in GENDER_NAMES,
				"%s has a gender the game knows" % where)
			assert_between(int(card["age"]), 18, 99, "%s is an adult age" % where)
			assert_between(int(card["tier"]), GolferTier.Tier.BEGINNER,
				GolferTier.Tier.PRO, "%s is a known tier" % where)
			for switch_key in SWITCHES:
				var switches = card[switch_key]
				assert_true(switches is Array, "%s lists %s" % [where, switch_key])
				for key in switches:
					assert_true(str(key) in _switch_keys(switch_key),
						"%s has a known %s entry (%s)" % [where, switch_key, key])

## The valid keys of a switch list, by the card field that carries it.
func _switch_keys(switch_key: String) -> Array:
	if switch_key == "traits":
		return GolferAttributes.TRAIT_KEYS.duplicate()
	return GolferAttributes.GOLFER_SKILL_KEYS.duplicate()

func test_every_card_lists_real_golf_skill_points() -> void:
	var pools := _pools()
	for id in pools:
		for card in pools[id]:
			var where := "%s / %s" % [id, card.get("name", "?")]
			var skills: Dictionary = card["golf_skills"]
			assert_false(skills.is_empty(), "%s has golf skills" % where)
			for skill_name in skills:
				assert_gte(GolferAttributes.golf_skill_index(str(skill_name)), 0,
					"%s names a real Golf Skill (%s)" % [where, skill_name])
				assert_between(int(skills[skill_name]), 1,
					GolferAttributes.POINTS_PER_GOLF_SKILL,
					"%s has points in %s" % [where, skill_name])

func test_visitor_names_are_unique() -> void:
	var seen := {}
	var pools := _pools()
	for id in pools:
		var at_location := {}
		for card in pools[id]:
			var visitor_name := str(card["name"])
			assert_false(at_location.has(visitor_name),
				"%s is unique at %s" % [visitor_name, id])
			at_location[visitor_name] = true
			assert_false(seen.has(visitor_name),
				"%s is unique across every location" % visitor_name)
			seen[visitor_name] = true
			var parts := visitor_name.split(" ")
			assert_eq(parts.size(), 2, "%s is a first and last name" % visitor_name)
			assert_ne(parts[0], parts[1], "%s is not a doubled name" % visitor_name)

func test_a_locations_surnames_are_not_all_the_same() -> void:
	var pools := _pools()
	for id in pools:
		var surnames := {}
		for card in pools[id]:
			surnames[str(card["name"]).split(" ")[1]] = true
		assert_gt(surnames.size(), 10,
			"%s's visitors do not all share one last name" % id)


# ---------------------------------------------------------------------------
# Applying a card
# ---------------------------------------------------------------------------

## A golfer carrying a card: the rolled block, then the card over the top.
func _golfer_with_card(card: Dictionary) -> Golfer:
	var golfer: Golfer = autofree(Golfer.new())
	golfer.attributes = GolferAttributes.new()
	golfer.attributes.generate_for_tier(int(card.get("tier", GolferTier.Tier.CASUAL)))
	golfer.attributes.apply_visitor_card(card)
	return golfer

func test_a_card_lands_the_whole_block_on_the_golfer() -> void:
	var pools := _pools()
	for id in pools:
		for card in pools[id]:
			var golfer := _golfer_with_card(card)
			var who := golfer.attributes
			assert_eq(who.name, str(card["name"]), "Name comes from the card")
			assert_eq(who.profession, str(card["profession"]),
				"Profession comes from the card")
			assert_eq(who.marital_status_name(), str(card["marital_status"]),
				"Marital Status comes from the card")
			assert_eq(who.age, int(card["age"]), "Age comes from the card")
			assert_eq(who.gender_name(), str(card["gender"]),
				"Gender comes from the card")
			for key in GolferAttributes.TRAIT_KEYS:
				assert_eq(who.trait_on(key), key in card["traits"],
					"%s trait %s follows the card" % [who.name, key])
			for key in GolferAttributes.GOLFER_SKILL_KEYS:
				assert_eq(who.skill_on(key), key in card["golfer_skills"],
					"%s golfer skill %s follows the card" % [who.name, key])
			for skill_name in card["golf_skills"]:
				var index := GolferAttributes.golf_skill_index(str(skill_name))
				assert_eq(who.golf_points[index], int(card["golf_skills"][skill_name]),
					"%s golf skill %s follows the card" % [who.name, skill_name])

func test_a_card_replaces_the_rolled_golf_skills_it_does_not_list() -> void:
	var card := {
		"name": "Test Visitor", "profession": "Baker", "marital_status": "Single",
		"age": 30, "gender": "Female", "traits": [], "golfer_skills": [],
		"golf_skills": {"Luck": 7},
	}
	var golfer := _golfer_with_card(card)
	assert_eq(golfer.attributes.golf_points[GolferAttributes.GolfSkill.LUCK], 7)
	assert_eq(golfer.attributes.golf_points[GolferAttributes.GolfSkill.POWER_HITTER], 0,
		"A skill the card does not list has no points")
	for key in GolferAttributes.TRAIT_KEYS:
		assert_false(golfer.attributes.trait_on(key),
			"An empty trait list is a golfer with no traits on")

func test_a_partial_card_keeps_the_rolled_block() -> void:
	var attributes := GolferAttributes.new()
	attributes.generate_for_tier(GolferTier.Tier.CASUAL)
	var rolled_traits := attributes.traits.duplicate()
	var rolled_skills := attributes.golfer_skills.duplicate()
	var rolled_points := attributes.golf_points.duplicate()
	var rolled_profession := attributes.profession
	attributes.apply_visitor_card({"name": "Only A Name"})
	assert_eq(attributes.name, "Only A Name")
	assert_eq(attributes.profession, rolled_profession,
		"A profession the card leaves out is kept")
	assert_eq(attributes.traits, rolled_traits, "Traits the card leaves out are kept")
	assert_eq(attributes.golfer_skills, rolled_skills,
		"Golfer skills the card leaves out are kept")
	assert_eq(attributes.golf_points, rolled_points,
		"Golf skills the card leaves out are kept")

func test_unknown_names_in_a_card_are_ignored() -> void:
	var a := GolferAttributes.new()
	a.generate_for_tier(GolferTier.Tier.CASUAL)
	var rolled_marital_status := a.marital_status
	var rolled_gender := a.gender
	a.apply_visitor_card({
		"name": "Odd Card", "profession": "Falconer", "marital_status": "Betrothed",
		"age": 500, "gender": "Robot", "traits": ["neat", "punctual"],
		"golfer_skills": ["luck"], "golf_skills": {"Luck": 500, "Wizardry": 3},
	})
	assert_eq(a.marital_status, rolled_marital_status,
		"An unknown marital status leaves the rolled one")
	assert_eq(a.age, 99, "Age is clamped to the game's range")
	assert_eq(a.gender, rolled_gender, "An unknown gender leaves the rolled one")
	assert_true(a.trait_on("neat"), "A known trait still lands")
	for key in GolferAttributes.TRAIT_KEYS:
		if key != "neat":
			assert_false(a.trait_on(key), "The card's unknown trait is ignored")
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		assert_false(a.skill_on(key), "An unknown golfer skill is ignored")
	assert_eq(a.golf_points[GolferAttributes.GolfSkill.LUCK],
		GolferAttributes.POINTS_PER_GOLF_SKILL, "Golf skill points are clamped")
	assert_eq(a.golf_points[GolferAttributes.GolfSkill.POWER_HITTER], 0,
		"An unknown Golf Skill is ignored")


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

func test_a_spawned_visitor_is_the_person_on_their_card() -> void:
	var golfer_manager := make_golfer_manager()
	WorldMap.active_location_id = "scotland"
	var golfer := golfer_manager.spawn_visiting_golfer(1)
	assert_not_null(golfer, "A visitor from the pool spawns")
	if golfer == null:
		return
	# The card the golfer walked in on, found by the name they spawned under.
	var card := {}
	for entry in WorldLocations.get_visiting_golfers("scotland"):
		if str(entry["name"]) == golfer.golfer_name:
			card = entry
	assert_false(card.is_empty(), "The spawned visitor is one of Scotland's cards")
	assert_eq(golfer.attributes.name, str(card["name"]))
	assert_eq(golfer.attributes.profession, str(card["profession"]),
		"The golfer works the card's profession")
	assert_eq(golfer.attributes.age, int(card["age"]))
	assert_eq(golfer.attributes.gender_name(), str(card["gender"]))
	assert_eq(golfer.golfer_tier, int(card["tier"]), "The card's tier is the golfer's")
	assert_eq(golfer.skin_id, str(card["skin_id"]), "The card's skin is the golfer's")
	assert_not_null(golfer.sprite_node(), "The visitor is drawn after their final skin is applied")
	assert_eq(golfer.skin().id, str(card["skin_id"]),
		"The spawn builds frames for the visitor's chosen skin")
	for key in GolferAttributes.TRAIT_KEYS:
		assert_eq(golfer.attributes.trait_on(key), key in card["traits"],
			"Trait %s follows the card" % key)
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		assert_eq(golfer.attributes.skill_on(key), key in card["golfer_skills"],
			"Golfer skill %s follows the card" % key)
	for skill_name in card["golf_skills"]:
		var index := GolferAttributes.golf_skill_index(str(skill_name))
		assert_eq(golfer.attributes.golf_points[index],
			int(card["golf_skills"][skill_name]), "Golf skill %s follows the card" % skill_name)
	assert_almost_eq(golfer.walk_speed,
		100.0 * golfer.attributes.walk_speed_multiplier(), 0.001,
		"Walk speed follows the card's Active trait")

func test_the_same_visitor_is_not_spawned_twice() -> void:
	var golfer_manager := make_golfer_manager()
	WorldMap.active_location_id = "wales"
	var cards := WorldLocations.get_visiting_golfers("wales")
	for i in cards.size():
		var golfer := golfer_manager.spawn_visiting_golfer(1)
		assert_not_null(golfer, "Visitor %d of the pool spawns" % (i + 1))
		if golfer == null:
			return
	assert_null(golfer_manager.spawn_visiting_golfer(1),
		"A pool with every visitor on the course has nobody left to send")
