extends RefCounted
class_name GolferAttributes
## GolferAttributes - the golfer attribute model every golfer in Golf Tycoon uses.
##
## Every golfer - visiting, tournament, or the course owner - carries this
## attribute block:
##
##   Name           Text
##   Profession     Text
##   Marital Status Single, Married, Divorced, or Widowed
##   Age            Number
##   Gender         Male or Female
##
##   Golfer Traits  Neat, Outgoing, Active, Playful, Nice - each On or Off
##   Golfer Skills  Length, Accuracy, Imagination - each On or Off
##
##   Golf Skills    Ten skills, each bought with points. Every point adds 10%
##                  to that skill and each skill can reach 990% (99 points).
##
##   Golfer Statuses Fun, Attitude, Energy, Hunger, Thirst - every status
##                  starts the course at 50%.
##
##   Golfer Comments Positive, Neutral, or Negative remarks made while playing
##                  the course. They accumulate into the Fun status.
##
## The class also owns the per-round status simulation (decay on the course,
## restoration at amenities) that used to live in GolferNeeds, so the statuses
## above are the live values the game plays with, not a static record.
## Two internal course-flow trackers that are not golfer statuses - comfort and
## pace - stay here too: restrooms and marshals/traffic feed them, and they push
## Fun and Attitude around.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum MaritalStatus { SINGLE, MARRIED, DIVORCED, WIDOWED }
enum Gender { MALE, FEMALE }

const MARITAL_STATUS_NAMES := {
	MaritalStatus.SINGLE: "Single",
	MaritalStatus.MARRIED: "Married",
	MaritalStatus.DIVORCED: "Divorced",
	MaritalStatus.WIDOWED: "Widowed",
}

const GENDER_NAMES := {
	Gender.MALE: "Male",
	Gender.FEMALE: "Female",
}

# ---------------------------------------------------------------------------
# Attribute keys and constants
# ---------------------------------------------------------------------------

## Golfer Traits - each is either On or Off.
const TRAIT_KEYS: Array[String] = ["neat", "outgoing", "active", "playful", "nice"]

const TRAIT_NAMES := {
	"neat": "Neat",
	"outgoing": "Outgoing",
	"active": "Active",
	"playful": "Playful",
	"nice": "Nice",
}

## Golfer Skills - each is either On or Off.
const GOLFER_SKILL_KEYS: Array[String] = ["length", "accuracy", "imagination"]

const GOLFER_SKILL_NAMES := {
	"length": "Length",
	"accuracy": "Accuracy",
	"imagination": "Imagination",
}

## Golf Skills, in point order. Each point adds 10% and each skill caps at 99
## points (990%). Mirrors PlayerGolferProfile.SKILLS so the owner's allocation
## screen and every AI golfer speak the same language.
const GOLF_SKILLS: Array[String] = [
	"Power Hitter", "Long Driver", "Accurate Driver", "Accurate Irons",
	"Accurate Putter", "Draw Shot (R to L)", "Fade Shot (L to R)",
	"High Backspin Shot", "Recovery Skills", "Luck",
]

## Index helpers for GOLF_SKILLS.
enum GolfSkill {
	POWER_HITTER = 0,
	LONG_DRIVER = 1,
	ACCURATE_DRIVER = 2,
	ACCURATE_IRONS = 3,
	ACCURATE_PUTTER = 4,
	DRAW_SHOT = 5,
	FADE_SHOT = 6,
	HIGH_BACKSPIN = 7,
	RECOVERY = 8,
	LUCK = 9,
}

## Every point is worth +10% of the skill, up to 99 points = 990%.
const POINTS_PER_GOLF_SKILL: int = 99
const PERCENT_PER_POINT: int = 10

## Golfer Statuses - each starts the course at 50%.
const STATUS_START: float = 0.5

## Thresholds for status feedback and penalties.
const LOW_NEED_THRESHOLD: float = 0.3       # Below this, golfer may complain
const CRITICAL_NEED_THRESHOLD: float = 0.15 # Below this, attitude penalty applied

## Per-hole decay for the course statuses. Tuned against the 50% start: a
## golfer who never visits an amenity runs low around the middle of a full
## round and critical on the back nine.
const ENERGY_DECAY_PER_HOLE: float = 0.018  # Low after ~11 holes (casual)
const HUNGER_DECAY_PER_HOLE: float = 0.012  # Low after ~17 holes (casual)
const THIRST_DECAY_PER_HOLE: float = 0.015  # Low after ~13 holes (casual)
## Internal trackers (restrooms / traffic) keep their old rates.
const COMFORT_DECAY_PER_HOLE: float = 0.06
const PACE_DECAY_PER_WAIT_SECOND: float = 0.003
## Waiting around is no fun: waiting also drains Fun, softly.
const FUN_DECAY_PER_WAIT_SECOND: float = 0.0012
## Fun changes as comments accumulate.
const FUN_PER_POSITIVE_COMMENT: float = 0.02
const FUN_PER_NEUTRAL_COMMENT: float = 0.002
const FUN_PER_NEGATIVE_COMMENT: float = -0.02
## Attitude follows the fun a golfer is having at the resort.
const ATTITUDE_FOLLOW_RATE: float = 0.3

## Interaction chance thresholds - determines if a golfer stops at a building.
const INTERACT_CHANCE_HIGH_NEED: float = 0.20   # 20% chance when status is above 0.7
const INTERACT_CHANCE_MID_NEED: float = 0.50    # 50% when status is 0.3-0.7
const INTERACT_CHANCE_LOW_NEED: float = 1.0     # 100% when status is below 0.3
const INTERACT_CHANCE_BASE: float = 0.30        # Fallback for unmapped buildings

## Satisfaction amounts from buildings. A bench feeds Energy, a Snack Bar feeds
## Hunger (and takes the edge off Thirst), and the clubhouse tops up everything
## at the end of the round.
const BENCH_ENERGY_RESTORE: float = 0.20
const SNACK_BAR_HUNGER_RESTORE: float = 0.30
const PUB_HUNGER_RESTORE: float = 0.50
const SNACK_BAR_THIRST_RESTORE: float = 0.20
const PUB_THIRST_RESTORE: float = 0.25
const CLUBHOUSE_ALL_RESTORE: float = 0.15
## Practice facilities and carts are entertainment: they lift Fun.
const PRACTICE_FUN_BOOST: float = 0.03
const CART_GARAGE_FUN_BOOST: float = 0.02

## Comment history kept on the golfer (and shown in the golfer panel).
const MAX_COMMENTS: int = 40

## How many golf-skill points each tier gets, before Golfer Skills adjust them.
const TIER_POINT_RANGE := {
	0: [0, 3],    # Beginner
	1: [1, 6],    # Casual
	2: [3, 10],   # Serious
	3: [6, 16],   # Pro
}

## Odds that a given Golfer Skill is On, by tier.
const TIER_GOLFER_SKILL_ODDS := {
	0: {"length": 0.25, "accuracy": 0.20, "imagination": 0.30},
	1: {"length": 0.40, "accuracy": 0.35, "imagination": 0.40},
	2: {"length": 0.55, "accuracy": 0.55, "imagination": 0.50},
	3: {"length": 0.75, "accuracy": 0.70, "imagination": 0.65},
}

## Age ranges by tier: pros are in their prime, beginners and casuals span life.
const TIER_AGE_RANGE := {
	0: [18, 80],
	1: [21, 75],
	2: [22, 62],
	3: [20, 40],
}

const PROFESSIONS: Array[String] = [
	"Accountant", "Architect", "Artist", "Baker", "Barber", "Carpenter",
	"Chef", "Chemist", "Consultant", "Dentist", "Doctor", "Driver",
	"Editor", "Electrician", "Engineer", "Farmer", "Firefighter", "Florist",
	"Graphic Designer", "Hotel Manager", "Insurance Agent", "Journalist",
	"Judge", "Lawyer", "Librarian", "Mechanic", "Musician", "Nurse",
	"Pharmacist", "Photographer", "Pilot", "Plumber", "Professor",
	"Real Estate Agent", "Retired", "Scientist", "Software Developer",
	"Teacher", "Tour Guide", "Veterinarian", "Waiter", "Writer",
]

const FEMALE_FIRST_NAMES: Array[String] = [
	"Amelia", "Ava", "Beatrice", "Bianca", "Camila", "Carla", "Chloe",
	"Daisy", "Elena", "Emily", "Fiona", "Grace", "Hannah", "Harper",
	"Isla", "Jasmine", "Jenna", "Kaya", "Layla", "Lucia", "Maya",
	"Mia", "Naomi", "Nora", "Olivia", "Priya", "Rosa", "Ruby",
	"Sofia", "Stella", "Tessa", "Valeria", "Vera", "Zoe",
]

const MALE_FIRST_NAMES: Array[String] = [
	"Adam", "Adrian", "Andre", "Benjamin", "Caleb", "Carlos", "Cedric",
	"Daniel", "Darius", "Diego", "Elias", "Emmett", "Felix", "Gabriel",
	"Hugo", "Isaac", "Jamal", "Javier", "Jonah", "Julian", "Kai",
	"Leo", "Liam", "Malik", "Marco", "Mateo", "Miles", "Nathan",
	"Omar", "Oscar", "Rafael", "Reid", "Simon", "Theo", "Victor", "Yusuf",
]

const LAST_NAMES: Array[String] = [
	"Abbott", "Alvarez", "Bennett", "Brennan", "Calloway", "Carrington",
	"Castillo", "Chen", "Clarke", "Cortez", "Dalton", "Delgado",
	"Donovan", "Ellison", "Farrow", "Fitzgerald", "Fleming", "Fontaine",
	"Gallagher", "Garcia", "Grant", "Hargrove", "Hayes", "Henderson",
	"Ibrahim", "Jennings", "Kaur", "Keller", "Kim", "Kowalski",
	"Langley", "Lawson", "Lindqvist", "Macklin", "Marino", "McAllister",
	"Mercer", "Montgomery", "Nakamura", "Navarro", "Okafor", "Petrov",
	"Quinn", "Ramirez", "Redgrave", "Richter", "Sandoval", "Sinclair",
	"Sullivan", "Thatcher", "Torres", "Vasquez", "Whitfield", "Zamora",
]

# ---------------------------------------------------------------------------
# Identity (Name, Profession, Marital Status, Age, Gender)
# ---------------------------------------------------------------------------

## The golfer's name. Golfer.golfer_name keeps the live display name in step;
## this field is the attribute copy that serializes with the rest.
var name: String = "Golfer"
var profession: String = "Professional"
var marital_status: int = MaritalStatus.SINGLE
var age: int = 30
var gender: int = Gender.MALE

# ---------------------------------------------------------------------------
# Golfer Traits (On / Off)
# ---------------------------------------------------------------------------

var traits: Dictionary = {
	"neat": false, "outgoing": false, "active": false, "playful": false, "nice": false,
}

# ---------------------------------------------------------------------------
# Golfer Skills (On / Off)
# ---------------------------------------------------------------------------

var golfer_skills: Dictionary = {
	"length": false, "accuracy": false, "imagination": false,
}

# ---------------------------------------------------------------------------
# Golf Skills (points, +10% each, up to 990%)
# ---------------------------------------------------------------------------

var golf_points: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]

# ---------------------------------------------------------------------------
# Golfer Statuses (start at 50%)
# ---------------------------------------------------------------------------

var fun: float = STATUS_START
var attitude: float = STATUS_START
var energy: float = STATUS_START
var hunger: float = STATUS_START
var thirst: float = STATUS_START

## Internal course-flow trackers (not golfer statuses): comfort is the need for
## a restroom, pace is how stuck the golfer feels in traffic. Both feed Fun.
var comfort: float = 1.0
var pace: float = 1.0

# ---------------------------------------------------------------------------
# Golfer Comments
# ---------------------------------------------------------------------------

## Comments made while playing: [{text, sentiment, hole, day}, ...].
## Sentiment is "positive", "neutral", or "negative".
var comments: Array = []
var comment_counts: Dictionary = {"positive": 0, "neutral": 0, "negative": 0}

# ---------------------------------------------------------------------------
# Personality and round context (used by the simulation)
# ---------------------------------------------------------------------------

## Patience (0.0 impatient - 1.0 patient) shapes how fast traffic drains pace.
var patience: float = 0.5
## GolferTier.Tier value - higher tiers are more demanding.
var golfer_tier: int = 1
## The Resort Hotel sends golfers out rested (1.0 = normal fatigue).
var energy_decay_modifier: float = 1.0

## Feedback flags (prevent spam / stacking).
var _triggered_low_energy: bool = false
var _triggered_low_comfort: bool = false
var _triggered_low_hunger: bool = false
var _triggered_low_thirst: bool = false
var _triggered_low_pace: bool = false
var _applied_critical_energy: bool = false
var _applied_critical_comfort: bool = false
var _applied_critical_hunger: bool = false
var _applied_critical_thirst: bool = false
var _applied_critical_pace: bool = false

# ===========================================================================
# Generation
# ===========================================================================

## Roll up a full random golfer: identity, traits, golfer skills and golf
## skills for the given tier. Statuses stay at their 50% start.
func generate_for_tier(tier: int) -> void:
	randomize_identity(tier)
	randomize_traits()
	randomize_golfer_skills(tier)
	randomize_golf_points(tier)

## Roll identity: gender, age, profession, marital status and a matching name.
func randomize_identity(tier: int = GolferTier.Tier.CASUAL) -> void:
	gender = Gender.MALE if randf() < 0.5 else Gender.FEMALE
	var age_range: Array = TIER_AGE_RANGE.get(tier, [18, 80])
	age = randi_range(age_range[0], age_range[1])
	profession = PROFESSIONS[randi() % PROFESSIONS.size()]
	marital_status = _roll_marital_status(age)
	name = random_full_name(gender)

## Each Golfer Trait is On or Off - independent coin flips.
func randomize_traits() -> void:
	for key in TRAIT_KEYS:
		traits[key] = randf() < 0.5

## Each Golfer Skill is On or Off; odds improve with tier. Length feeds distance,
## Accuracy feeds precision, and Imagination unlocks shaped shots.
func randomize_golfer_skills(tier: int = GolferTier.Tier.CASUAL) -> void:
	var odds: Dictionary = TIER_GOLFER_SKILL_ODDS.get(tier, TIER_GOLFER_SKILL_ODDS[1])
	for key in GOLFER_SKILL_KEYS:
		golfer_skills[key] = randf() < float(odds.get(key, 0.4))

## Roll the ten Golf Skills as points. Every point is +10% of that skill and
## each skill can reach 99 points (990%). Tier sets the point range; the golfer
## skills a golfer owns raise the matching golf skills, while shot-shape skills
## are capped without Imagination (they cannot perform the shots at all).
func randomize_golf_points(tier: int = GolferTier.Tier.CASUAL) -> void:
	var range_pair: Array = TIER_POINT_RANGE.get(tier, [1, 6])
	var low: int = int(range_pair[0])
	var high: int = int(range_pair[1])
	for i in GOLF_SKILLS.size():
		var points := randi_range(low, high)
		if _golf_skill_matches_enabled_golfer_skill(i):
			points += randi_range(1, 4)
		if i in [GolfSkill.DRAW_SHOT, GolfSkill.FADE_SHOT, GolfSkill.HIGH_BACKSPIN] \
				and not golfer_skills["imagination"]:
			points = int(points * 0.5)
		golf_points[i] = clampi(points, 0, POINTS_PER_GOLF_SKILL)

## Whether a golf skill's natural home (a Golfer Skill) is switched on.
func _golf_skill_matches_enabled_golfer_skill(index: int) -> bool:
	match index:
		GolfSkill.POWER_HITTER, GolfSkill.LONG_DRIVER:
			return golfer_skills["length"]
		GolfSkill.ACCURATE_DRIVER, GolfSkill.ACCURATE_IRONS, GolfSkill.ACCURATE_PUTTER:
			return golfer_skills["accuracy"]
		GolfSkill.DRAW_SHOT, GolfSkill.FADE_SHOT, GolfSkill.HIGH_BACKSPIN, GolfSkill.RECOVERY:
			return golfer_skills["imagination"]
		_:
			return false  # Luck belongs to no golfer skill

## A random full name for this gender.
static func random_full_name(gender_value: int) -> String:
	var pool := MALE_FIRST_NAMES if gender_value == Gender.MALE else FEMALE_FIRST_NAMES
	return "%s %s" % [pool[randi() % pool.size()], LAST_NAMES[randi() % LAST_NAMES.size()]]

## Marital status odds shift with age.
static func _roll_marital_status(age_value: int) -> int:
	var roll := randf()
	if age_value < 26:
		if roll < 0.70: return MaritalStatus.SINGLE
		if roll < 0.98: return MaritalStatus.MARRIED
		return MaritalStatus.DIVORCED
	if age_value < 46:
		if roll < 0.25: return MaritalStatus.SINGLE
		if roll < 0.85: return MaritalStatus.MARRIED
		if roll < 0.99: return MaritalStatus.DIVORCED
		return MaritalStatus.WIDOWED
	if age_value < 66:
		if roll < 0.10: return MaritalStatus.SINGLE
		if roll < 0.70: return MaritalStatus.MARRIED
		if roll < 0.92: return MaritalStatus.DIVORCED
		return MaritalStatus.WIDOWED
	if roll < 0.08: return MaritalStatus.SINGLE
	if roll < 0.58: return MaritalStatus.MARRIED
	if roll < 0.73: return MaritalStatus.DIVORCED
	return MaritalStatus.WIDOWED

## Reset everything a fresh round needs - the five statuses go back to 50%.
## Identity, traits, skills and golf points survive: the golfer is the same
## person stepping onto the course again.
func setup(tier: int, patience_trait: float) -> void:
	golfer_tier = tier
	patience = patience_trait
	fun = STATUS_START
	attitude = STATUS_START
	energy = STATUS_START
	hunger = STATUS_START
	thirst = STATUS_START
	comfort = 1.0
	pace = 1.0
	_triggered_low_energy = false
	_triggered_low_comfort = false
	_triggered_low_hunger = false
	_triggered_low_thirst = false
	_triggered_low_pace = false
	_applied_critical_energy = false
	_applied_critical_comfort = false
	_applied_critical_hunger = false
	_applied_critical_thirst = false
	_applied_critical_pace = false

# ===========================================================================
# Accessors
# ===========================================================================

func trait_on(key: String) -> bool:
	return bool(traits.get(key, false))

func set_trait(key: String, value: bool) -> void:
	if traits.has(key):
		traits[key] = value

func skill_on(key: String) -> bool:
	return bool(golfer_skills.get(key, false))

func set_golfer_skill(key: String, value: bool) -> void:
	if golfer_skills.has(key):
		golfer_skills[key] = value

## The golf skill as a multiplier bonus: every point is +10%, so 12 points is
## +120% (a 2.2x skill). Caps at +990%.
func golf_bonus(index: int) -> float:
	if index < 0 or index >= golf_points.size():
		return 0.0
	return golf_points[index] * 0.1

## The golf skill the way the player sees it: 0% to 990%.
func golf_skill_percent(index: int) -> int:
	if index < 0 or index >= golf_points.size():
		return 0
	return golf_points[index] * PERCENT_PER_POINT

func set_golf_points(index: int, points: int) -> void:
	if index >= 0 and index < golf_points.size():
		golf_points[index] = clampi(points, 0, POINTS_PER_GOLF_SKILL)

func marital_status_name() -> String:
	return MARITAL_STATUS_NAMES.get(marital_status, "Single")

func gender_name() -> String:
	return GENDER_NAMES.get(gender, "Male")

## The five golfer statuses as a dictionary (fun, attitude, energy, hunger,
## thirst). Every one starts the course at 50%.
func statuses() -> Dictionary:
	return {
		"fun": fun,
		"attitude": attitude,
		"energy": energy,
		"hunger": hunger,
		"thirst": thirst,
	}

# ===========================================================================
# Status simulation
# ===========================================================================

## Called after each hole is completed - energy, hunger and thirst decline as
## the golfer walks the course, and attitude settles toward the fun they are
## having.
func on_hole_completed() -> void:
	var tier_modifier = _get_tier_decay_modifier()
	energy = maxf(energy - ENERGY_DECAY_PER_HOLE * tier_modifier
		* energy_decay_modifier * trait_energy_decay_multiplier(), 0.0)
	hunger = maxf(hunger - HUNGER_DECAY_PER_HOLE * tier_modifier, 0.0)
	thirst = maxf(thirst - THIRST_DECAY_PER_HOLE * tier_modifier, 0.0)
	comfort = maxf(comfort - COMFORT_DECAY_PER_HOLE * tier_modifier, 0.0)
	update_attitude()

## Waiting (not their turn) drains pace satisfaction - impatient golfers faster -
## and waiting around is no fun either.
func on_waiting(wait_seconds: float) -> void:
	if wait_seconds <= 0.0:
		return
	var patience_modifier = 1.0 + (1.0 - patience) * 1.5  # 1.0 (patient) - 2.5 (impatient)
	pace = maxf(pace - wait_seconds * PACE_DECAY_PER_WAIT_SECOND * patience_modifier, 0.0)
	fun = maxf(fun - wait_seconds * FUN_DECAY_PER_WAIT_SECOND * wait_fun_multiplier(), 0.0)
	if pace >= LOW_NEED_THRESHOLD:
		_triggered_low_pace = false
	if pace >= CRITICAL_NEED_THRESHOLD:
		_applied_critical_pace = false
	update_attitude()

## Normal play restores pace; only traffic delays drain it.
func on_playing(seconds: float) -> void:
	pace = minf(1.0, pace + maxf(seconds, 0.0) * .0008)
	if pace >= LOW_NEED_THRESHOLD: _triggered_low_pace = false
	if pace >= CRITICAL_NEED_THRESHOLD: _applied_critical_pace = false

## Move attitude toward the amount of fun this golfer is having at the resort.
func update_attitude() -> void:
	attitude = clampf(attitude + (fun - attitude) * ATTITUDE_FOLLOW_RATE, 0.0, 1.0)

## Adjust Fun directly (good golf, a nice amenity, a long wait) and let
## Attitude follow.
func adjust_fun(amount: float) -> void:
	fun = clampf(fun + amount, 0.0, 1.0)
	update_attitude()

## Adjust Attitude directly (service shocks: a greeting, a drink, a marshal).
func adjust_attitude(amount: float) -> void:
	attitude = clampf(attitude + amount, 0.0, 1.0)

## Record a golfer comment (Positive, Neutral, or Negative). Comments made while
## playing the course accumulate into the Fun status.
func record_comment(text: String, sentiment: String, hole: int = 0, day: int = 0) -> void:
	var bucket := sentiment if sentiment in ["positive", "neutral", "negative"] else "neutral"
	comments.append({
		"text": text,
		"sentiment": bucket,
		"hole": hole,
		"day": day,
	})
	if comments.size() > MAX_COMMENTS:
		comments.pop_front()
	comment_counts[bucket] = int(comment_counts.get(bucket, 0)) + 1
	match bucket:
		"positive":
			fun = clampf(fun + FUN_PER_POSITIVE_COMMENT * fun_gain_multiplier(), 0.0, 1.0)
		"negative":
			fun = clampf(fun + FUN_PER_NEGATIVE_COMMENT * fun_loss_multiplier(), 0.0, 1.0)
		_:
			fun = clampf(fun + FUN_PER_NEUTRAL_COMMENT, 0.0, 1.0)
	update_attitude()

## Comments made today, most recent last, for the golfer panel.
func recent_comments(count: int = 5) -> Array:
	return comments.slice(maxi(0, comments.size() - count))

## Get the chance (0.0-1.0) that a golfer interacts with a nearby building.
## Lower status = higher chance. Golfers don't seek buildings out, but when they
## walk within range, needier golfers are more likely to stop.
func get_interaction_chance(building_type: String) -> float:
	var relevant_need: float = -1.0

	match building_type:
		"bench":
			relevant_need = energy
		"snack_bar":
			relevant_need = hunger
		"pub":
			relevant_need = hunger
		_:
			return INTERACT_CHANCE_BASE

	if relevant_need < LOW_NEED_THRESHOLD:
		return INTERACT_CHANCE_LOW_NEED      # Desperate - always stop
	elif relevant_need < 0.7:
		return INTERACT_CHANCE_MID_NEED      # Could use it - coin flip
	else:
		return INTERACT_CHANCE_HIGH_NEED     # Doing fine - usually walk past

## Apply an amenity visit: benches feed Energy, snack bars feed Hunger (and a
## little Thirst), the clubhouse tops everything up at the end of the round.
## Practice facilities and carts are entertainment: they lift Fun.
## Returns the attitude boost applied (0.0 when nothing changed).
func apply_building_effect(building_type: String) -> float:
	var attitude_boost: float = 0.0

	match building_type:
		"bench":
			var old_energy = energy
			energy = minf(energy + BENCH_ENERGY_RESTORE, 1.0)
			if energy > old_energy:
				attitude_boost = 0.02
				adjust_fun(0.01)  # A little rest is a little fun
			_reset_energy_flags_if_recovered()
		"snack_bar":
			var old_hunger = hunger
			hunger = minf(hunger + SNACK_BAR_HUNGER_RESTORE, 1.0)
			if hunger > old_hunger:
				attitude_boost = 0.03
			_reset_hunger_flags_if_recovered()
			thirst = minf(thirst + SNACK_BAR_THIRST_RESTORE, 1.0)
			_reset_thirst_flags_if_recovered()
		"pub":
			var old_hunger = hunger
			hunger = minf(hunger + PUB_HUNGER_RESTORE, 1.0)
			if hunger > old_hunger:
				attitude_boost = 0.05
				adjust_fun(0.02)
			_reset_hunger_flags_if_recovered()
			thirst = minf(thirst + PUB_THIRST_RESTORE, 1.0)
			_reset_thirst_flags_if_recovered()
		"putting_green", "pro_shop", "driving_range":
			attitude_boost = PRACTICE_FUN_BOOST
			adjust_fun(PRACTICE_FUN_BOOST)
		"cart_garage":
			attitude_boost = CART_GARAGE_FUN_BOOST
			adjust_fun(CART_GARAGE_FUN_BOOST)
		"clubhouse":
			energy = minf(energy + CLUBHOUSE_ALL_RESTORE, 1.0)
			hunger = minf(hunger + CLUBHOUSE_ALL_RESTORE, 1.0)
			thirst = minf(thirst + CLUBHOUSE_ALL_RESTORE, 1.0)
			comfort = minf(comfort + CLUBHOUSE_ALL_RESTORE, 1.0)
			attitude_boost = 0.03
			adjust_fun(0.02)
			_reset_energy_flags_if_recovered()
			_reset_comfort_flags_if_recovered()
			_reset_hunger_flags_if_recovered()
			_reset_thirst_flags_if_recovered()

	return attitude_boost

## A drinks vendor served this golfer. Restores Thirst and returns the attitude
## boost applied (0.0 when they were already fully quenched).
func restore_thirst(amount: float) -> float:
	var old_thirst = thirst
	thirst = clampf(thirst + amount, 0.0, 1.0)
	_reset_thirst_flags_if_recovered()
	if thirst <= old_thirst:
		return 0.0
	return 0.04

## A marshal got this group moving again. Restores pace and returns the attitude
## boost applied (0.0 when pace was already full).
func restore_pace(amount: float) -> float:
	var old_pace = pace
	pace = clampf(pace + amount, 0.0, 1.0)
	if pace >= LOW_NEED_THRESHOLD:
		_triggered_low_pace = false
	if pace >= CRITICAL_NEED_THRESHOLD:
		_applied_critical_pace = false
	if pace <= old_pace:
		return 0.0
	adjust_fun(0.01)
	return 0.03

## Overall picture of how this golfer is doing (0.0-1.0). Fun and Attitude lead -
## they are what the golfer's visit is judged by - with the physical statuses
## behind them.
func get_overall_satisfaction() -> float:
	return clampf(
		fun * 0.25 +
		attitude * 0.25 +
		energy * 0.20 +
		hunger * 0.15 +
		thirst * 0.15,
		0.0, 1.0)

## Attitude penalty from critically low statuses (negative value to subtract).
## Each penalty fires once per critical episode.
func get_mood_penalty() -> float:
	var penalty: float = 0.0
	if energy < CRITICAL_NEED_THRESHOLD and not _applied_critical_energy:
		penalty -= 0.05
		_applied_critical_energy = true
	if comfort < CRITICAL_NEED_THRESHOLD and not _applied_critical_comfort:
		penalty -= 0.05
		_applied_critical_comfort = true
	if hunger < CRITICAL_NEED_THRESHOLD and not _applied_critical_hunger:
		penalty -= 0.03
		_applied_critical_hunger = true
	if thirst < CRITICAL_NEED_THRESHOLD and not _applied_critical_thirst:
		penalty -= 0.04
		_applied_critical_thirst = true
	if pace < CRITICAL_NEED_THRESHOLD and not _applied_critical_pace:
		penalty -= 0.08  # Frustration from traffic is the strongest penalty
		_applied_critical_pace = true
	return penalty

## Which low statuses should trigger a comment right now.
## Returns an array of FeedbackTriggers.TriggerType values.
func check_need_triggers() -> Array:
	var triggers: Array = []

	if energy < LOW_NEED_THRESHOLD and not _triggered_low_energy:
		triggers.append(FeedbackTriggers.TriggerType.TIRED)
		_triggered_low_energy = true

	if comfort < LOW_NEED_THRESHOLD and not _triggered_low_comfort:
		triggers.append(FeedbackTriggers.TriggerType.NEEDS_RESTROOM)
		_triggered_low_comfort = true

	if hunger < LOW_NEED_THRESHOLD and not _triggered_low_hunger:
		triggers.append(FeedbackTriggers.TriggerType.HUNGRY)
		_triggered_low_hunger = true

	if thirst < LOW_NEED_THRESHOLD and not _triggered_low_thirst:
		triggers.append(FeedbackTriggers.TriggerType.THIRSTY)
		_triggered_low_thirst = true

	if pace < LOW_NEED_THRESHOLD and not _triggered_low_pace:
		triggers.append(FeedbackTriggers.TriggerType.SLOW_PACE)
		_triggered_low_pace = true

	return triggers

## Higher tiers have faster status decay (more demanding golfers).
func _get_tier_decay_modifier() -> float:
	match golfer_tier:
		0:  # BEGINNER
			return 0.8
		1:  # CASUAL
			return 1.0
		2:  # SERIOUS
			return 1.1
		3:  # PRO
			return 1.3
	return 1.0

func _reset_energy_flags_if_recovered() -> void:
	if energy >= LOW_NEED_THRESHOLD:
		_triggered_low_energy = false
	if energy >= CRITICAL_NEED_THRESHOLD:
		_applied_critical_energy = false

func _reset_comfort_flags_if_recovered() -> void:
	if comfort >= LOW_NEED_THRESHOLD:
		_triggered_low_comfort = false
	if comfort >= CRITICAL_NEED_THRESHOLD:
		_applied_critical_comfort = false

func _reset_hunger_flags_if_recovered() -> void:
	if hunger >= LOW_NEED_THRESHOLD:
		_triggered_low_hunger = false
	if hunger >= CRITICAL_NEED_THRESHOLD:
		_applied_critical_hunger = false

func _reset_thirst_flags_if_recovered() -> void:
	if thirst >= LOW_NEED_THRESHOLD:
		_triggered_low_thirst = false
	if thirst >= CRITICAL_NEED_THRESHOLD:
		_applied_critical_thirst = false

## Serialize statuses for debug/display and guest reviews.
func to_dict() -> Dictionary:
	return {
		"fun": snappedf(fun, 0.01),
		"attitude": snappedf(attitude, 0.01),
		"energy": snappedf(energy, 0.01),
		"hunger": snappedf(hunger, 0.01),
		"thirst": snappedf(thirst, 0.01),
		"comfort": snappedf(comfort, 0.01),
		"pace": snappedf(pace, 0.01),
		"overall": snappedf(get_overall_satisfaction(), 0.01),
	}

# ===========================================================================
# Trait effects
# ===========================================================================

## Active golfers walk faster and tire more slowly.
func walk_speed_multiplier() -> float:
	return 1.15 if trait_on("active") else 1.0

func trait_energy_decay_multiplier() -> float:
	return 0.8 if trait_on("active") else 1.0

## Outgoing golfers speak up more often and enjoy greetings more.
func comment_probability_multiplier() -> float:
	return 1.5 if trait_on("outgoing") else 1.0

func greeting_boost_multiplier() -> float:
	return 1.5 if trait_on("outgoing") else 1.0

## Playful golfers enjoy the good moments more; nice golfers shrug off the bad
## ones and don't complain as hard.
func fun_gain_multiplier() -> float:
	return 1.5 if trait_on("playful") else 1.0

func fun_loss_multiplier() -> float:
	return 0.7 if trait_on("nice") else 1.0

func wait_fun_multiplier() -> float:
	return 0.75 if trait_on("nice") else 1.0

# ===========================================================================
# Golfer Skill effects
# ===========================================================================

## Length: how far a golfer is able to drive the ball.
func distance_multiplier() -> float:
	return 1.1 if skill_on("length") else 1.0

## Accuracy: the ability to control how and where the ball lands.
func dispersion_multiplier() -> float:
	return 1.0 / 1.35 if skill_on("accuracy") else 1.0

## Imagination: control of the ball's behaviour to overcome obstacles or
## hazards. Without it a golfer cannot play draw, fade or high backspin shots.
func can_shape_shots() -> bool:
	return skill_on("imagination")

## Bend multiplier for a shaped shot (1 = fade L→R, 2 = draw R→L, 3 = backspin).
## The matching Golf Skill scales how much of the shape the golfer can actually
## produce - every point is +10% of the skill.
func shape_bend_multiplier(index: int) -> float:
	if not can_shape_shots():
		return 0.0
	return 0.4 + minf(1.2, 0.12 * golf_bonus(index))

# ===========================================================================
# Serialization
# ===========================================================================

func serialize() -> Dictionary:
	return {
		"name": name,
		"profession": profession,
		"marital_status": marital_status,
		"age": age,
		"gender": gender,
		"traits": traits.duplicate(),
		"golfer_skills": golfer_skills.duplicate(),
		"golf_points": golf_points.duplicate(),
		"fun": fun,
		"attitude": attitude,
		"energy": energy,
		"hunger": hunger,
		"thirst": thirst,
		"comfort": comfort,
		"pace": pace,
		"comments": comments.duplicate(true),
		"comment_counts": comment_counts.duplicate(),
		"patience": patience,
		"golfer_tier": golfer_tier,
		"energy_decay_modifier": energy_decay_modifier,
	}

static func from_data(data: Dictionary) -> GolferAttributes:
	var attributes := GolferAttributes.new()
	attributes.name = str(data.get("name", "Golfer")).strip_edges().left(32)
	if attributes.name.is_empty():
		attributes.name = "Golfer"
	attributes.profession = str(data.get("profession", "Professional")).strip_edges().left(48)
	if attributes.profession.is_empty():
		attributes.profession = "Professional"
	attributes.marital_status = clampi(int(data.get("marital_status", MaritalStatus.SINGLE)),
		MaritalStatus.SINGLE, MaritalStatus.WIDOWED)
	attributes.age = clampi(int(data.get("age", 30)), 18, 99)
	attributes.gender = Gender.FEMALE if int(data.get("gender", Gender.MALE)) == Gender.FEMALE else Gender.MALE
	var saved_traits = data.get("traits", {})
	if saved_traits is Dictionary:
		for key in TRAIT_KEYS:
			attributes.traits[key] = bool(saved_traits.get(key, false))
	var saved_skills = data.get("golfer_skills", {})
	if saved_skills is Dictionary:
		for key in GOLFER_SKILL_KEYS:
			attributes.golfer_skills[key] = bool(saved_skills.get(key, false))
	var saved_points = data.get("golf_points", [])
	if saved_points is Array:
		for i in mini(saved_points.size(), attributes.golf_points.size()):
			attributes.golf_points[i] = clampi(int(saved_points[i]), 0, POINTS_PER_GOLF_SKILL)
	attributes.fun = clampf(float(data.get("fun", STATUS_START)), 0.0, 1.0)
	attributes.attitude = clampf(float(data.get("attitude", STATUS_START)), 0.0, 1.0)
	attributes.energy = clampf(float(data.get("energy", STATUS_START)), 0.0, 1.0)
	attributes.hunger = clampf(float(data.get("hunger", STATUS_START)), 0.0, 1.0)
	attributes.thirst = clampf(float(data.get("thirst", STATUS_START)), 0.0, 1.0)
	attributes.comfort = clampf(float(data.get("comfort", 1.0)), 0.0, 1.0)
	attributes.pace = clampf(float(data.get("pace", 1.0)), 0.0, 1.0)
	var saved_comments = data.get("comments", [])
	if saved_comments is Array:
		for comment in saved_comments:
			if comment is Dictionary:
				attributes.comments.append(comment.duplicate(true))
		if attributes.comments.size() > MAX_COMMENTS:
			attributes.comments = attributes.comments.slice(attributes.comments.size() - MAX_COMMENTS)
	var saved_counts = data.get("comment_counts", {})
	if saved_counts is Dictionary:
		for sentiment in ["positive", "neutral", "negative"]:
			attributes.comment_counts[sentiment] = int(saved_counts.get(sentiment, 0))
	attributes.patience = clampf(float(data.get("patience", 0.5)), 0.0, 1.0)
	attributes.golfer_tier = int(data.get("golfer_tier", 1))
	attributes.energy_decay_modifier = clampf(float(data.get("energy_decay_modifier", 1.0)), 0.1, 1.0)
	return attributes
