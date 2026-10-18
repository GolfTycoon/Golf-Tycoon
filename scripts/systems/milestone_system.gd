extends RefCounted
class_name MilestoneSystem
## MilestoneSystem - Definitions for the game's three goal tracks.
##
## Goals are split into three tracks with different lifetimes:
##
##  * Course Location Milestones - one set per course location, unlocked
##    again in every save. They measure what has been built and enjoyed at
##    that site (holes, buildings, rounds, records, its star rating).
##  * World Milestones - one set for the whole company across all course
##    locations, unlocked again in every save. They measure the company's
##    portfolio, money, calendar, golfers and reputation.
##  * Achievements - career honours that stay unlocked between saves. They
##    are written to `user://settings.cfg` (see AchievementStore), so a new
##    company starts with the player's past glories still on the shelf.
##
## Definitions here are stateless; MilestoneManager owns the progress.

enum Track { LOCATION, WORLD, ACHIEVEMENT }

enum Category { COURSE, COMPANY, ECONOMY, GOLFERS, RECORDS, REPUTATION, MASTERY }

class Milestone:
	var id: String
	var title: String
	var description: String
	var category: int  # Category enum
	var track: int  # Track enum
	var reward_money: int = 0
	var reward_reputation: float = 0.0
	## Achievements only: the career counter behind this honour and the value
	## it unlocks at. Empty counter means a meta achievement (Hall of Fame).
	var counter: String = ""
	var goal: int = 1

	func _init(p_id: String, p_title: String, p_desc: String, p_cat: int, p_track: int,
			p_money: int = 0, p_rep: float = 0.0, p_counter: String = "", p_goal: int = 1) -> void:
		id = p_id
		title = p_title
		description = p_desc
		category = p_cat
		track = p_track
		reward_money = p_money
		reward_reputation = p_rep
		counter = p_counter
		goal = p_goal

## Every Course Location Milestone. The same list applies to each course
## location in the world; progress is kept per location and unlocked again
## with every new save.
static func get_location_milestones() -> Array:
	return [
		# Course design at this site
		Milestone.new("loc_first_hole", "First Tee", "Build your first hole at this location", Category.COURSE, Track.LOCATION, 300),
		Milestone.new("loc_three_holes", "Front Three", "Build 3 holes at this location", Category.COURSE, Track.LOCATION, 600),
		Milestone.new("loc_nine_holes", "The Front Nine", "Build 9 holes at this location", Category.COURSE, Track.LOCATION, 2000),
		Milestone.new("loc_eighteen_holes", "Full Course", "Build 18 holes at this location", Category.COURSE, Track.LOCATION, 4000),
		Milestone.new("loc_par_3", "Short Game Special", "Build a course here where every hole is a par 3", Category.COURSE, Track.LOCATION, 2000, 5.0),
		Milestone.new("loc_first_building", "Amenities", "Place your first building at this location", Category.COURSE, Track.LOCATION, 500, 1.0),
		Milestone.new("loc_five_buildings", "Full Service", "Place 5 buildings at this location", Category.COURSE, Track.LOCATION, 2000, 5.0),

		# Golfers at this site
		Milestone.new("loc_first_round", "Open for Business", "Have a golfer finish a round at this location", Category.GOLFERS, Track.LOCATION, 250),
		Milestone.new("loc_serve_25", "Local Favorite", "Serve 25 rounds at this location", Category.GOLFERS, Track.LOCATION, 2500, 5.0),
		Milestone.new("loc_full_house", "Tee Time Rush", "Fill this course to its golfer capacity", Category.GOLFERS, Track.LOCATION, 1000, 3.0),

		# Records set at this site
		Milestone.new("loc_first_hio", "Ace!", "Witness a hole-in-one at this location", Category.RECORDS, Track.LOCATION, 2000, 5.0),
		Milestone.new("loc_first_eagle", "Eagle Eye", "Witness an eagle at this location", Category.RECORDS, Track.LOCATION, 1000, 3.0),

		# This site's rating
		Milestone.new("loc_four_star", "Four Stars Here", "Earn a 4-star rating at this location", Category.REPUTATION, Track.LOCATION, 3000, 5.0),
		Milestone.new("loc_five_star", "Five Stars Here", "Earn a 5-star rating at this location", Category.REPUTATION, Track.LOCATION, 10000, 10.0),
	]

## Every World Milestone: the company's goals across all its course
## locations, unlocked again with every new save.
static func get_world_milestones() -> Array:
	return [
		# The company's portfolio
		Milestone.new("world_own_2", "Second Site", "Own 2 course locations", Category.COMPANY, Track.WORLD, 2000),
		Milestone.new("world_own_3", "Chain Reaction", "Own 3 course locations", Category.COMPANY, Track.WORLD, 5000),
		Milestone.new("world_own_5", "Golf Empire", "Own 5 course locations", Category.COMPANY, Track.WORLD, 15000),
		Milestone.new("world_holes_18", "Company Course Card", "Build 18 holes across all your locations", Category.COMPANY, Track.WORLD, 3000),
		Milestone.new("world_holes_36", "A Company of Holes", "Build 36 holes across all your locations", Category.COMPANY, Track.WORLD, 8000),

		# The company's books
		Milestone.new("world_first_profit", "In the Black", "Finish a day with positive profit", Category.ECONOMY, Track.WORLD, 0, 2.0),
		Milestone.new("world_earn_10k", "Making Money", "Accumulate $10,000 total revenue in a year", Category.ECONOMY, Track.WORLD, 1000, 3.0),
		Milestone.new("world_earn_50k", "Big Business", "Accumulate $50,000 total revenue in a year", Category.ECONOMY, Track.WORLD, 5000, 5.0),
		Milestone.new("world_survive_year", "One-Year Milestone", "Keep the company running for a full year (365 days)", Category.ECONOMY, Track.WORLD, 3000, 5.0),
		Milestone.new("world_survive_five_years", "Seasoned Operator", "Keep the company running for five years (1,825 days)", Category.ECONOMY, Track.WORLD, 10000, 10.0),
		Milestone.new("world_no_debt", "Debt Free", "Reach $100,000 with no loans", Category.ECONOMY, Track.WORLD, 0, 5.0),

		# Golfers across the company
		Milestone.new("world_serve_50", "Getting Popular", "Serve 50 golfers in a single year", Category.GOLFERS, Track.WORLD, 2000, 5.0),
		Milestone.new("world_pro_visit", "Pro Tour Stop", "Attract a Pro-tier golfer", Category.GOLFERS, Track.WORLD, 3000, 8.0),

		# Records across the company
		Milestone.new("world_five_hio", "Ace Factory", "Witness 5 holes-in-one across the company", Category.RECORDS, Track.WORLD, 5000, 8.0),

		# The company's standing
		Milestone.new("world_rep_25", "Getting Noticed", "Reach 25 reputation", Category.REPUTATION, Track.WORLD, 0),
		Milestone.new("world_rep_50", "Established Course", "Reach 50 reputation", Category.REPUTATION, Track.WORLD, 2000),
		Milestone.new("world_rep_75", "Prestigious Club", "Reach 75 reputation", Category.REPUTATION, Track.WORLD, 5000),
		Milestone.new("world_rep_100", "Legendary Course", "Reach 100 reputation", Category.REPUTATION, Track.WORLD, 10000),
	]

## Every Achievement: career honours that stay unlocked between saves. Each
## one (except the meta honour) reads a career counter AchievementStore keeps
## across every company the player has ever run.
static func get_achievements() -> Array:
	return [
		# Building
		Milestone.new("ach_first_steps", "First Steps", "Break ground on your first hole", Category.COURSE, Track.ACHIEVEMENT, 0, 0.0, "holes_built", 1),
		Milestone.new("ach_master_builder", "Master Builder", "Build 100 holes across all your courses", Category.COURSE, Track.ACHIEVEMENT, 0, 0.0, "holes_built", 100),

		# Golfers
		Milestone.new("ach_opening_day", "Opening Day", "Complete your first round of golf", Category.GOLFERS, Track.ACHIEVEMENT, 0, 0.0, "rounds", 1),
		Milestone.new("ach_club_classic", "Club Classic", "Complete 100 rounds of golf", Category.GOLFERS, Track.ACHIEVEMENT, 0, 0.0, "rounds", 100),
		Milestone.new("ach_grand_tour", "Grand Tour", "Complete 500 rounds of golf", Category.GOLFERS, Track.ACHIEVEMENT, 0, 0.0, "rounds", 500),

		# Records
		Milestone.new("ach_ace", "Ace!", "Witness your first hole-in-one", Category.RECORDS, Track.ACHIEVEMENT, 0, 0.0, "hole_in_ones", 1),
		Milestone.new("ach_ace_hunter", "Ace Hunter", "Witness 10 holes-in-one", Category.RECORDS, Track.ACHIEVEMENT, 0, 0.0, "hole_in_ones", 10),
		Milestone.new("ach_eagle_eye", "Eagle Eye", "Witness your first eagle", Category.RECORDS, Track.ACHIEVEMENT, 0, 0.0, "eagles", 1),
		Milestone.new("ach_sky_high", "Sky High", "Witness 50 eagles", Category.RECORDS, Track.ACHIEVEMENT, 0, 0.0, "eagles", 50),

		# Business
		Milestone.new("ach_tycoon", "Tycoon", "Earn $1,000,000 in total revenue", Category.ECONOMY, Track.ACHIEVEMENT, 0, 0.0, "revenue", 1000000),
		Milestone.new("ach_mogul", "Mogul", "Earn $10,000,000 in total revenue", Category.ECONOMY, Track.ACHIEVEMENT, 0, 0.0, "revenue", 10000000),

		# The company's reach
		Milestone.new("ach_globetrotter", "Globetrotter", "Buy 5 course locations across your career", Category.COMPANY, Track.ACHIEVEMENT, 0, 0.0, "locations_bought", 5),
		Milestone.new("ach_atlas_complete", "Atlas Complete", "Buy 10 course locations across your career", Category.COMPANY, Track.ACHIEVEMENT, 0, 0.0, "locations_bought", 10),

		# Standing and longevity
		Milestone.new("ach_one_year_on", "One Year On", "Run a company for a full year (365 days)", Category.REPUTATION, Track.ACHIEVEMENT, 0, 0.0, "days", 365),
		Milestone.new("ach_five_year_plan", "Five Year Plan", "Run a company for five years (1,825 days)", Category.REPUTATION, Track.ACHIEVEMENT, 0, 0.0, "days", 1825),
		Milestone.new("ach_reputation_100", "Living Legend", "Reach 100 reputation", Category.REPUTATION, Track.ACHIEVEMENT, 0, 0.0, "reputation", 100),
		Milestone.new("ach_five_star", "Five Star Club", "Earn a five-star course rating", Category.REPUTATION, Track.ACHIEVEMENT, 0, 0.0, "five_star", 1),
		Milestone.new("ach_champion", "Champion", "Win a tournament", Category.REPUTATION, Track.ACHIEVEMENT, 0, 0.0, "tournament_wins", 1),

		# The shelf above the shelf
		Milestone.new("ach_hall_of_fame", "Hall of Fame", "Unlock every other achievement", Category.MASTERY, Track.ACHIEVEMENT),
	]

## Every career counter AchievementStore remembers, with the value a fresh
## install starts at.
static func get_counter_defaults() -> Dictionary:
	return {
		"holes_built": 0,
		"rounds": 0,
		"hole_in_ones": 0,
		"eagles": 0,
		"revenue": 0,
		"locations_bought": 0,
		"days": 0,
		"reputation": 0,
		"five_star": 0,
		"tournament_wins": 0,
	}

static func get_track_name(track: int) -> String:
	match track:
		Track.LOCATION: return "Course Location Milestones"
		Track.WORLD: return "World Milestones"
		Track.ACHIEVEMENT: return "Achievements"
	return "Goals"

static func get_category_name(category: int) -> String:
	match category:
		Category.COURSE: return "Course Design"
		Category.COMPANY: return "The Company"
		Category.ECONOMY: return "Economy"
		Category.GOLFERS: return "Golfers"
		Category.RECORDS: return "Records"
		Category.REPUTATION: return "Reputation"
		Category.MASTERY: return "Mastery"
	return "Other"

static func get_category_color(category: int) -> Color:
	match category:
		Category.COURSE: return Color(0.4, 0.8, 0.4)
		Category.COMPANY: return Color(0.45, 0.75, 0.95)
		Category.ECONOMY: return Color(0.9, 0.85, 0.3)
		Category.GOLFERS: return Color(0.4, 0.7, 1.0)
		Category.RECORDS: return Color(1.0, 0.6, 0.2)
		Category.REPUTATION: return Color(0.9, 0.3, 0.9)
		Category.MASTERY: return Color(1.0, 0.78, 0.25)
	return Color.WHITE

## Where a milestone of `category` sits in the reading order of the screens.
static func get_category_order(category: int) -> int:
	match category:
		Category.COURSE: return 0
		Category.COMPANY: return 1
		Category.ECONOMY: return 2
		Category.GOLFERS: return 3
		Category.RECORDS: return 4
		Category.REPUTATION: return 5
		_: return 6

## The old save format kept one flat list of completed ids, keyed on the ids
## this system used before the three tracks existed. Map each to its closest
## new home so loading an old save keeps what the player had earned. Location
## ids land on the active course location.
static func migrate_legacy_id(legacy_id: String) -> Dictionary:
	var mapping := {
		"first_hole": ["loc_first_hole", Track.LOCATION],
		"three_holes": ["loc_three_holes", Track.LOCATION],
		"nine_holes": ["loc_nine_holes", Track.LOCATION],
		"eighteen_holes": ["loc_eighteen_holes", Track.LOCATION],
		"par_3_course": ["loc_par_3", Track.LOCATION],
		"first_building": ["loc_first_building", Track.LOCATION],
		"five_buildings": ["loc_five_buildings", Track.LOCATION],
		"first_golfer": ["loc_first_round", Track.LOCATION],
		"full_house": ["loc_full_house", Track.LOCATION],
		"first_hio": ["loc_first_hio", Track.LOCATION],
		"first_eagle": ["loc_first_eagle", Track.LOCATION],
		"four_star": ["loc_four_star", Track.LOCATION],
		"five_star": ["loc_five_star", Track.LOCATION],
		"five_hio": ["world_five_hio", Track.WORLD],
		"earn_10k": ["world_earn_10k", Track.WORLD],
		"earn_50k": ["world_earn_50k", Track.WORLD],
		"survive_30_days": ["world_survive_year", Track.WORLD],
		"survive_100_days": ["world_survive_five_years", Track.WORLD],
		"no_debt": ["world_no_debt", Track.WORLD],
		"serve_50": ["world_serve_50", Track.WORLD],
		"pro_visit": ["world_pro_visit", Track.WORLD],
		"rep_25": ["world_rep_25", Track.WORLD],
		"rep_50": ["world_rep_50", Track.WORLD],
		"rep_75": ["world_rep_75", Track.WORLD],
		"rep_100": ["world_rep_100", Track.WORLD],
	}
	if not mapping.has(legacy_id):
		return {}
	var entry: Array = mapping[legacy_id]
	return {"id": entry[0], "track": entry[1]}
