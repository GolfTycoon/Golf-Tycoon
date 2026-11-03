extends RefCounted
class_name TournamentLibrary
## TournamentLibrary - Catalogue, golfer rosters, format rules, and persistence
## for standalone Tournament Mode.
##
## Every playable golfer (built-in Default or Career-saved) and every opposing
## tournament competitor carries the full Golf Tycoon golfer schema:
##   - Name, Skin, Skin Colours
##   - Profession, Age, Gender, Marital Status
##   - Golfer Traits (Neat, Outgoing, Active, Playful, Nice)
##   - Golfer Skills (Length, Accuracy, Imagination)
##   - Golf Skills (Power Hitter, Long Driver, Accurate Driver, Accurate Irons,
##     Accurate Putter, Draw Shot, Fade Shot, High Backspin Shot,
##     Recovery Skills, Luck)
##
## Each Difficulty Level defines its own distinct roster of opposing golfers
## with progressively higher Golf Skills, decoupled from Tournament Format Type,
## Format Rules (rounds, field size, cut line, sudden-death playoff), and
## mod-contributed Game Features (Weather, Wind, Seasons, and community mods).

const COURSES_SUBDIR: String = "tournament_courses"
const COURSE_EXT: String = ".course"
const GOLFERS_SECTION: String = "tournament_golfers"
const FORMAT_VERSION: int = 2

enum Difficulty {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
	CHAMPIONSHIP = 3,
}

enum FormatType {
	STROKE_PLAY = 0,
	STABLEFORD = 1,
	MODIFIED_STABLEFORD = 2,
	SKINS = 3,
}

const ROUND_OPTIONS: Array[int] = [1, 2, 3, 4]
## The number of rounds a standalone Tournament Mode event plays when the player
## has not picked one: a single round, so the quickest event is one click away.
const DEFAULT_ROUNDS: int = 1
## Sentinel representing the Auto field size option (2x the selected course's hole count).
const FIELD_SIZE_AUTO: int = 0
const FIELD_SIZE_OPTIONS: Array[int] = [8, 12, 18, 24]

## Compute the Auto field size for a given hole count: double the number of holes
## on the course (at least 2 golfers so a 1-hole course still forms a pairing).
static func auto_field_size_for_holes(hole_count: int) -> int:
	return maxi(2, hole_count * 2)

## Compute the Auto field size for a course catalogue entry (2x hole_count).
static func auto_field_size_for_course(course_entry: Dictionary) -> int:
	var holes := int(course_entry.get("hole_count", 0))
	if holes <= 0 and course_entry.get("preview_holes") is Array:
		holes = (course_entry["preview_holes"] as Array).size()
	if holes <= 0:
		holes = 9
	return auto_field_size_for_holes(holes)

const GOLF_SKILL_SHORT_NAMES: Array[String] = [
	"Power Hitter",
	"Long Driver",
	"Accurate Driver",
	"Accurate Irons",
	"Accurate Putter",
	"Draw Shot",
	"Fade Shot",
	"High Backspin Shot",
	"Recovery Skills",
	"Luck",
]

const SKIN_GROUP_TO_PROFILE_KEY: Dictionary = {
	"Shirt": "shirt_color",
	"Pants": "pants_color",
	"Cap": "cap_color",
	"Hair": "hair_color",
	"Skin": "skin_tone",
}

const PROFILE_KEY_TO_SKIN_GROUP: Dictionary = {
	"shirt_color": "Shirt",
	"pants_color": "Pants",
	"cap_color": "Cap",
	"hair_color": "Hair",
	"skin_tone": "Skin",
}

const DEFAULT_COURSES: Array[Dictionary] = [
	{
		"id": "default:emerald_pines",
		"name": "Emerald Pines",
		"theme": CourseTheme.Type.PARKLAND,
		"layout": "quick_start",
		"seed": 7101,
		"hole_count": 9,
		"par": 36,
		"tagline": "Lush tree-lined Parkland routing with water carries and receptive greens.",
	},
	{
		"id": "default:dunbar_links",
		"name": "Dunbar Links",
		"theme": CourseTheme.Type.LINKS,
		"layout": "generated",
		"seed": 7303,
		"hole_count": 18,
		"par": 72,
		"tagline": "Full 18-hole championship coastal Links exposed to sea winds and pot bunkers.",
	},
	{
		"id": "default:red_mesa_canyon",
		"name": "Red Mesa Canyon",
		"theme": CourseTheme.Type.DESERT,
		"layout": "prebuilt:standard9",
		"seed": 7202,
		"hole_count": 9,
		"par": 36,
		"tagline": "Target-golf Desert nine framed by red rock arroyos, water hazards, and sand.",
	},
	{
		"id": "default:highland_ridge",
		"name": "Highland Ridge",
		"theme": CourseTheme.Type.MOUNTAIN,
		"layout": "generated",
		"seed": 7404,
		"hole_count": 6,
		"par": 24,
		"tagline": "Brisk 6-hole Alpine routing through pine-covered ridges for fast tournament play.",
	},
]

const DEFAULT_GOLFERS: Array[Dictionary] = [
	{
		"id": "default:claire_vance",
		"name": "Claire Vance",
		"archetype": "Tour All-Rounder",
		"skin_id": "casual",
		"skin_colors": {
			"Shirt": "2e7057",
			"Pants": "e0dbcc",
			"Cap": "f2f0e6",
			"Hair": "593822",
			"Skin": "edc4a3",
		},
		"profession": "Tour Professional",
		"age": 28,
		"gender": GolferAttributes.Gender.FEMALE,
		"marital_status": GolferAttributes.MaritalStatus.SINGLE,
		"tagline": "Balanced tee-to-green game with steady nerves and reliable putting.",
		# [Power, LongDrv, AccDrv, AccIrn, AccPut, Draw, Fade, Backspin, Recovery, Luck]
		"points": [8, 8, 10, 10, 10, 4, 4, 5, 8, 5],
		"traits": {"neat": true, "outgoing": true, "active": true, "playful": false, "nice": true},
		"golfer_skills": {"length": false, "accuracy": true, "imagination": false},
	},
	{
		"id": "default:marcus_cole",
		"name": "Marcus Cole",
		"archetype": "Power Bomber",
		"skin_id": "casual",
		"skin_colors": {
			"Shirt": "c23338",
			"Pants": "2e333d",
			"Cap": "292933",
			"Hair": "1f1a17",
			"Skin": "80573d",
		},
		"profession": "Long-Drive Champion",
		"age": 26,
		"gender": GolferAttributes.Gender.MALE,
		"marital_status": GolferAttributes.MaritalStatus.SINGLE,
		"tagline": "Towering drives and fearless par-5 attacks, trading accuracy for raw yardage.",
		"points": [18, 18, 4, 6, 6, 6, 3, 4, 10, 5],
		"traits": {"neat": false, "outgoing": true, "active": true, "playful": true, "nice": false},
		"golfer_skills": {"length": true, "accuracy": false, "imagination": false},
	},
	{
		"id": "default:elena_sato",
		"name": "Elena Sato",
		"archetype": "Precision Tactician",
		"skin_id": "casual",
		"skin_colors": {
			"Shirt": "386bad",
			"Pants": "ebebf0",
			"Cap": "335c99",
			"Hair": "1c1c24",
			"Skin": "ebccb0",
		},
		"profession": "Course Strategist",
		"age": 31,
		"gender": GolferAttributes.Gender.FEMALE,
		"marital_status": GolferAttributes.MaritalStatus.MARRIED,
		"tagline": "Laser-guided fairways, surgical irons, and elite shot shaping in tough winds.",
		"points": [5, 5, 16, 16, 11, 8, 8, 8, 7, 4],
		"traits": {"neat": true, "outgoing": false, "active": true, "playful": false, "nice": true},
		"golfer_skills": {"length": false, "accuracy": true, "imagination": true},
	},
	{
		"id": "default:arthur_pendleton",
		"name": "Arthur Pendleton",
		"archetype": "Short-Game Wizard",
		"skin_id": "beginner",
		"skin_colors": {
			"Shirt": "b88a3d",
			"Pants": "4d4238",
			"Cap": "6b5238",
			"Hair": "7a736b",
			"Skin": "deb394",
		},
		"profession": "Master Clubmaker",
		"age": 45,
		"gender": GolferAttributes.Gender.MALE,
		"marital_status": GolferAttributes.MaritalStatus.MARRIED,
		"tagline": "Crafty veteran who saves par from anywhere around the green and drains long putts.",
		"points": [3, 4, 10, 10, 18, 6, 6, 12, 18, 8],
		"traits": {"neat": true, "outgoing": true, "active": false, "playful": true, "nice": true},
		"golfer_skills": {"length": false, "accuracy": false, "imagination": true},
	},
]

## Compact roster specification rows per Difficulty Level:
## [name, gender, age, marital_status, profession, skin_id,
##  [Shirt, Pants, Cap, Hair, Skin], active_traits, active_golfer_skills, 10 golf_skill_points]
const _EASY_ROSTER_SPECS: Array = [
	["Toby Miller", GolferAttributes.Gender.MALE, 23, GolferAttributes.MaritalStatus.SINGLE, "Barista", "beginner", ["4d8b55", "4a433d", "5e6b54", "5c3c24", "f2cca6"], ["playful", "nice"], [], [2, 2, 2, 2, 3, 1, 1, 1, 2, 3]],
	["Hannah Brooks", GolferAttributes.Gender.FEMALE, 29, GolferAttributes.MaritalStatus.SINGLE, "Florist", "beginner", ["c96b84", "e3ded5", "d98ca0", "6e472b", "f0c7a8"], ["neat", "nice"], [], [1, 2, 3, 3, 3, 1, 1, 1, 2, 2]],
	["Owen Gallagher", GolferAttributes.Gender.MALE, 41, GolferAttributes.MaritalStatus.MARRIED, "Postal Carrier", "beginner", ["3f6d9c", "3d3f4a", "2f5073", "402b1d", "e8be9e"], ["active", "outgoing"], [], [3, 3, 2, 2, 2, 1, 1, 1, 3, 2]],
	["Priya Nair", GolferAttributes.Gender.FEMALE, 34, GolferAttributes.MaritalStatus.MARRIED, "Librarian", "casual", ["7b5ea7", "dedbe6", "63488c", "1f1924", "a87454"], ["neat", "nice"], ["accuracy"], [1, 1, 4, 3, 3, 1, 1, 2, 2, 2]],
	["Benjamin Hart", GolferAttributes.Gender.MALE, 52, GolferAttributes.MaritalStatus.MARRIED, "Hardware Clerk", "beginner", ["9c5a3c", "473a32", "6b4430", "736c66", "deb596"], ["nice"], [], [2, 2, 2, 3, 4, 1, 2, 1, 3, 2]],
	["Chloe Bennett", GolferAttributes.Gender.FEMALE, 25, GolferAttributes.MaritalStatus.SINGLE, "Graphic Designer", "casual", ["e08a44", "333942", "f0ede6", "3b2316", "f5d2b4"], ["outgoing", "playful"], [], [3, 2, 2, 2, 2, 2, 1, 1, 2, 3]],
	["Samir Khan", GolferAttributes.Gender.MALE, 37, GolferAttributes.MaritalStatus.MARRIED, "Pharmacist", "beginner", ["2f8078", "dcd8ce", "25635d", "1c1817", "b88462"], ["neat"], [], [2, 2, 3, 3, 3, 1, 1, 2, 2, 2]],
	["Megan O'Connor", GolferAttributes.Gender.FEMALE, 46, GolferAttributes.MaritalStatus.DIVORCED, "Bakery Owner", "beginner", ["b84b4b", "453d3b", "8f3838", "8a4b2a", "f2cab0"], ["outgoing", "nice"], [], [2, 3, 2, 2, 3, 1, 1, 1, 3, 3]],
	["Lucas Ferreira", GolferAttributes.Gender.MALE, 27, GolferAttributes.MaritalStatus.SINGLE, "Surf Instructor", "casual", ["3aa3a0", "e6e1d3", "2b7a78", "2e2118", "c99572"], ["active", "playful"], ["length"], [4, 4, 1, 2, 2, 1, 1, 1, 2, 3]],
	["Evelyn Cho", GolferAttributes.Gender.FEMALE, 31, GolferAttributes.MaritalStatus.SINGLE, "Violin Teacher", "casual", ["4c6996", "e8e6eb", "3a5175", "18161c", "edd0b7"], ["neat", "nice"], [], [1, 2, 3, 4, 4, 1, 1, 2, 2, 2]],
	["Derek Walsh", GolferAttributes.Gender.MALE, 58, GolferAttributes.MaritalStatus.WIDOWED, "Retired Fireman", "beginner", ["7d7244", "3b372f", "5c5432", "948f89", "e0b899"], ["active", "nice"], [], [3, 2, 2, 3, 3, 1, 2, 1, 3, 2]],
	["Nadia Novak", GolferAttributes.Gender.FEMALE, 22, GolferAttributes.MaritalStatus.SINGLE, "Film Student", "beginner", ["cc6e4e", "332f38", "a8563b", "4d3222", "f0cbb0"], ["playful", "outgoing"], [], [2, 3, 2, 2, 2, 2, 1, 1, 2, 4]],
	["Gavin Fletcher", GolferAttributes.Gender.MALE, 39, GolferAttributes.MaritalStatus.MARRIED, "Accountant", "beginner", ["527868", "d6d2c7", "3d594d", "36261b", "e6be9c"], ["neat"], [], [2, 2, 3, 3, 3, 1, 1, 1, 3, 2]],
	["Rosa Delgado", GolferAttributes.Gender.FEMALE, 44, GolferAttributes.MaritalStatus.MARRIED, "Pediatric Nurse", "casual", ["b5547a", "ebe6ea", "8f3f60", "241917", "c7926f"], ["outgoing", "nice", "active"], [], [2, 2, 3, 3, 4, 1, 1, 2, 3, 2]],
	["Trevor Bates", GolferAttributes.Gender.MALE, 33, GolferAttributes.MaritalStatus.SINGLE, "Auto Mechanic", "beginner", ["3d546e", "2b2e36", "2c3d52", "4a3525", "deb392"], ["active"], ["length"], [4, 3, 2, 2, 2, 1, 1, 1, 3, 2]],
	["Yuki Taniguchi", GolferAttributes.Gender.FEMALE, 26, GolferAttributes.MaritalStatus.SINGLE, " Pastry Chef", "casual", ["689c78", "edeae2", "4f7a5c", "1c1a20", "f0d0b8"], ["neat", "playful"], [], [2, 2, 3, 3, 3, 2, 1, 2, 2, 2]],
	["Colin MacLeod", GolferAttributes.Gender.MALE, 49, GolferAttributes.MaritalStatus.DIVORCED, "Ferry Captain", "beginner", ["356878", "40454a", "274d59", "6e655f", "e8bfa0"], ["outgoing"], [], [3, 3, 2, 2, 3, 1, 2, 1, 3, 3]],
	["Heidi Zimmerman", GolferAttributes.Gender.FEMALE, 36, GolferAttributes.MaritalStatus.MARRIED, "Botanist", "beginner", ["6c8c46", "dfd9cc", "536e35", "785634", "f2ccb0"], ["neat", "active", "nice"], [], [2, 2, 3, 3, 3, 1, 1, 2, 3, 2]],
]

const _NORMAL_ROSTER_SPECS: Array = [
	["Liam Henderson", GolferAttributes.Gender.MALE, 29, GolferAttributes.MaritalStatus.SINGLE, "Club Assistant Pro", "casual", ["286e58", "ded9cb", "1f5443", "3d281a", "ecc4a4"], ["neat", "active"], ["accuracy"], [8, 8, 9, 9, 9, 5, 5, 6, 8, 6]],
	["Maya Lin", GolferAttributes.Gender.FEMALE, 25, GolferAttributes.MaritalStatus.SINGLE, "Collegiate All-Star", "casual", ["3a6ea8", "eceef2", "2c5482", "1a1820", "f0cfb6"], ["neat", "active", "outgoing"], ["accuracy", "imagination"], [7, 7, 10, 10, 9, 7, 6, 7, 7, 5]],
	["Carlos Morales", GolferAttributes.Gender.MALE, 34, GolferAttributes.MaritalStatus.MARRIED, "Regional Champion", "casual", ["b83b3b", "2f333b", "8f2c2c", "211a16", "bd8967"], ["outgoing", "playful"], ["length"], [11, 10, 7, 8, 8, 6, 5, 6, 8, 6]],
	["Freya Lindholm", GolferAttributes.Gender.FEMALE, 30, GolferAttributes.MaritalStatus.SINGLE, "Sports Physiotherapist", "casual", ["4c8c9e", "e6eaed", "386978", "b8945e", "f5d5bc"], ["neat", "active", "nice"], ["accuracy"], [7, 8, 9, 10, 9, 6, 6, 6, 8, 5]],
	["Devon Brooks", GolferAttributes.Gender.MALE, 27, GolferAttributes.MaritalStatus.SINGLE, "Driving Range Pro", "casual", ["d17a32", "363840", "a65e24", "1c1715", "7a5239"], ["active", "outgoing"], ["length", "imagination"], [11, 11, 6, 7, 7, 7, 5, 6, 8, 6]],
	["Amelie Laurent", GolferAttributes.Gender.FEMALE, 32, GolferAttributes.MaritalStatus.MARRIED, "Wine Importer", "casual", ["784888", "ebe6ed", "5b3569", "3b241c", "edd0b6"], ["neat", "playful"], ["imagination"], [6, 6, 9, 9, 10, 8, 8, 7, 8, 5]],
	["Nathaniel Price", GolferAttributes.Gender.MALE, 42, GolferAttributes.MaritalStatus.MARRIED, "Civil Engineer", "casual", ["3b5c47", "d9d4c5", "2b4535", "544438", "e3ba9b"], ["neat", "nice"], ["accuracy"], [7, 7, 10, 9, 9, 5, 6, 6, 9, 5]],
	["Zara Al-Mansoor", GolferAttributes.Gender.FEMALE, 26, GolferAttributes.MaritalStatus.SINGLE, "Aviation Pilot", "casual", ["1f6e7a", "e8ebed", "18545e", "1c1616", "b5805e"], ["active", "neat"], ["length", "accuracy"], [9, 9, 9, 8, 8, 6, 6, 6, 7, 6]],
	["Patrick Byrne", GolferAttributes.Gender.MALE, 38, GolferAttributes.MaritalStatus.MARRIED, "Links Caddie Master", "beginner", ["6e5c3b", "453c33", "54462c", "6e4429", "edbfa2"], ["outgoing", "nice"], ["imagination"], [7, 7, 8, 8, 10, 7, 7, 8, 10, 7]],
	["Grace Kim", GolferAttributes.Gender.FEMALE, 24, GolferAttributes.MaritalStatus.SINGLE, "State Amateur Medalist", "casual", ["c44d6c", "edeef2", "993b54", "17161c", "f0d0b8"], ["neat", "active"], ["accuracy"], [7, 8, 10, 10, 10, 6, 6, 7, 7, 6]],
	["Matteo Conti", GolferAttributes.Gender.MALE, 35, GolferAttributes.MaritalStatus.SINGLE, "Architect", "casual", ["2f4f78", "e3e1da", "233b5c", "291f1a", "d9aa89"], ["outgoing", "playful", "neat"], ["imagination"], [8, 8, 8, 9, 9, 8, 7, 7, 8, 6]],
	["Keira Campbell", GolferAttributes.Gender.FEMALE, 29, GolferAttributes.MaritalStatus.MARRIED, "Marine Biologist", "casual", ["3a8770", "e0ddd4", "2a6654", "7d4828", "f2ccb0"], ["active", "nice"], ["length"], [9, 10, 8, 8, 8, 5, 6, 6, 8, 6]],
	["Julian Vance", GolferAttributes.Gender.MALE, 44, GolferAttributes.MaritalStatus.DIVORCED, "Financial Analyst", "casual", ["52576b", "d8dae0", "3d4152", "595552", "e5bc9e"], ["neat"], ["accuracy"], [7, 7, 10, 9, 9, 6, 6, 6, 8, 5]],
	["Sofia Herrera", GolferAttributes.Gender.FEMALE, 28, GolferAttributes.MaritalStatus.SINGLE, "Teaching Pro", "casual", ["b86b35", "ebe6dc", "8c5027", "261a14", "c99472"], ["outgoing", "active", "nice"], ["accuracy", "imagination"], [8, 8, 9, 9, 9, 7, 7, 7, 8, 6]],
	["Brett Callahan", GolferAttributes.Gender.MALE, 31, GolferAttributes.MaritalStatus.MARRIED, "Firefighter", "casual", ["9e3535", "343740", "782727", "3b2b1e", "e8be9e"], ["active", "outgoing"], ["length"], [10, 10, 7, 7, 8, 5, 5, 6, 9, 6]],
	["Hana Watanabe", GolferAttributes.Gender.FEMALE, 27, GolferAttributes.MaritalStatus.SINGLE, "Industrial Designer", "casual", ["4a7862", "eceae4", "375c4a", "19181e", "eed0b7"], ["neat", "nice"], ["accuracy"], [6, 7, 10, 10, 10, 6, 6, 7, 8, 5]],
	["Oliver Grant", GolferAttributes.Gender.MALE, 39, GolferAttributes.MaritalStatus.MARRIED, "Orthopedic Surgeon", "casual", ["385a7c", "dcdad2", "29435c", "453426", "e6be9f"], ["neat"], ["accuracy"], [8, 8, 9, 9, 9, 6, 6, 6, 8, 5]],
	["Tessa Van Dijk", GolferAttributes.Gender.FEMALE, 30, GolferAttributes.MaritalStatus.SINGLE, "Rowing Coach", "casual", ["d46a2e", "2e333d", "a85223", "a8834c", "f2cdb2"], ["active", "outgoing"], ["length"], [10, 10, 8, 8, 8, 6, 6, 6, 8, 6]],
]

const _HARD_ROSTER_SPECS: Array = [
	["Viktor Lindqvist", GolferAttributes.Gender.MALE, 28, GolferAttributes.MaritalStatus.SINGLE, "European Tour Pro", "casual", ["1f5482", "ebedf2", "173f63", "b38e56", "f2cfb5"], ["neat", "active"], ["length", "accuracy", "imagination"], [19, 19, 18, 19, 17, 15, 16, 16, 17, 12]],
	["Sora Takahashi", GolferAttributes.Gender.FEMALE, 24, GolferAttributes.MaritalStatus.SINGLE, "Touring Professional", "casual", ["236e57", "f0efe9", "1a5442", "17161c", "f0d1b8"], ["neat", "active", "nice"], ["accuracy", "imagination"], [15, 16, 22, 22, 20, 17, 17, 18, 17, 13]],
	["Mateo Reyes", GolferAttributes.Gender.MALE, 27, GolferAttributes.MaritalStatus.MARRIED, "Tour Shot-Maker", "casual", ["a82e36", "282c36", "802228", "1f1814", "c28d6b"], ["outgoing", "active", "playful"], ["length", "imagination"], [21, 20, 16, 18, 18, 20, 18, 19, 18, 14]],
	["Camille Beaumont", GolferAttributes.Gender.FEMALE, 29, GolferAttributes.MaritalStatus.SINGLE, "Touring Professional", "casual", ["4d3b78", "ece9f0", "392b59", "3d261a", "edd0b6"], ["neat", "outgoing"], ["accuracy", "imagination"], [15, 15, 20, 21, 21, 17, 18, 18, 17, 12]],
	["Declan Rory", GolferAttributes.Gender.MALE, 31, GolferAttributes.MaritalStatus.MARRIED, "Links Specialist", "casual", ["2d5e45", "dbd6c8", "214734", "6b3f24", "ecc5a8"], ["active", "outgoing", "nice"], ["length", "accuracy", "imagination"], [18, 19, 19, 19, 18, 18, 17, 17, 20, 13]],
	["Aisha Okafor", GolferAttributes.Gender.FEMALE, 26, GolferAttributes.MaritalStatus.SINGLE, "Power Tour Pro", "casual", ["c98428", "2b2e38", "99631e", "1a1514", "6e4830"], ["active", "outgoing"], ["length", "accuracy"], [23, 22, 17, 17, 17, 15, 15, 16, 17, 13]],
	["Henrik Solberg", GolferAttributes.Gender.MALE, 33, GolferAttributes.MaritalStatus.MARRIED, "Nordic Open Winner", "casual", ["2c6b78", "e6eaed", "204f59", "9e7c4c", "f2cfb4"], ["neat", "nice"], ["accuracy", "imagination"], [17, 17, 21, 20, 19, 16, 17, 17, 18, 12]],
	["Min-Ji Park", GolferAttributes.Gender.FEMALE, 23, GolferAttributes.MaritalStatus.SINGLE, "Tour Putting Leader", "casual", ["b54568", "f0eef2", "8a344f", "17161c", "f0d0b8"], ["neat", "active"], ["accuracy", "imagination"], [15, 15, 21, 22, 24, 16, 16, 18, 18, 14]],
	["Lucas Vance-Sterling", GolferAttributes.Gender.MALE, 30, GolferAttributes.MaritalStatus.SINGLE, "Invitational Champion", "casual", ["364559", "e0e2e8", "273240", "38281c", "e5bc9e"], ["neat", "active"], ["length", "accuracy"], [20, 19, 19, 19, 18, 15, 16, 16, 17, 12]],
	["Gabriela Silva", GolferAttributes.Gender.FEMALE, 28, GolferAttributes.MaritalStatus.MARRIED, "South American Tour Pro", "casual", ["2e8560", "ebe8df", "226347", "241914", "bd8968"], ["outgoing", "active", "playful"], ["length", "imagination"], [18, 18, 18, 19, 19, 18, 17, 18, 18, 14]],
	["Callum MacGregor", GolferAttributes.Gender.MALE, 36, GolferAttributes.MaritalStatus.MARRIED, "Scottish Tour Veteran", "casual", ["4a5438", "d6d0c2", "373f2a", "5c4533", "e8bfa0"], ["nice", "active"], ["accuracy", "imagination"], [16, 17, 19, 20, 19, 18, 18, 19, 21, 13]],
	["Elena Kovacs", GolferAttributes.Gender.FEMALE, 27, GolferAttributes.MaritalStatus.SINGLE, "Continental Tour Pro", "casual", ["8c3b52", "ebe6e8", "692c3d", "472e20", "f0cab0"], ["neat", "active"], ["length", "accuracy"], [18, 18, 20, 19, 18, 15, 16, 17, 17, 12]],
	["Jordan Mercer", GolferAttributes.Gender.MALE, 25, GolferAttributes.MaritalStatus.SINGLE, "Tour Long-Iron Specialist", "casual", ["29628a", "30343d", "1e4966", "241b16", "8c6044"], ["active", "outgoing"], ["length", "accuracy", "imagination"], [21, 21, 18, 20, 17, 17, 16, 18, 17, 13]],
	["Claire Dubois", GolferAttributes.Gender.FEMALE, 32, GolferAttributes.MaritalStatus.MARRIED, "Touring Professional", "casual", ["3d6e66", "ebeae4", "2d524c", "543824", "eed0b6"], ["neat", "nice"], ["accuracy", "imagination"], [15, 16, 21, 21, 20, 17, 17, 18, 18, 13]],
	["Rafael Mendoza", GolferAttributes.Gender.MALE, 34, GolferAttributes.MaritalStatus.MARRIED, "Desert Classic Champion", "casual", ["b85d2b", "e3ded3", "8a4520", "1f1815", "c79270"], ["outgoing", "playful"], ["imagination", "accuracy"], [17, 18, 19, 19, 20, 19, 18, 19, 20, 14]],
	["Ingrid Nystrom", GolferAttributes.Gender.FEMALE, 29, GolferAttributes.MaritalStatus.SINGLE, "Scandinavian Tour Pro", "casual", ["3b6b9c", "eceef2", "2c5075", "bfa068", "f5d5bc"], ["neat", "active"], ["length", "accuracy"], [19, 19, 20, 19, 18, 16, 16, 17, 17, 12]],
	["Shane Kulkarni", GolferAttributes.Gender.MALE, 28, GolferAttributes.MaritalStatus.SINGLE, "Asian Tour Contender", "casual", ["26735c", "2d313a", "1c5745", "1a1616", "a87554"], ["neat", "active", "nice"], ["accuracy", "imagination"], [17, 17, 20, 21, 19, 17, 17, 18, 18, 13]],
	["Bridget Holloway", GolferAttributes.Gender.FEMALE, 35, GolferAttributes.MaritalStatus.DIVORCED, "Touring Professional", "casual", ["734a85", "ebe8ee", "563763", "633d26", "f0cbb0"], ["outgoing", "active"], ["accuracy", "imagination"], [16, 16, 20, 20, 20, 17, 18, 18, 19, 13]],
]

const _CHAMPIONSHIP_ROSTER_SPECS: Array = [
	["Alistair Sterling", GolferAttributes.Gender.MALE, 32, GolferAttributes.MaritalStatus.MARRIED, "4x Major Champion", "casual", ["1a4d3a", "f0ede4", "d4af37", "38261a", "ecc4a6"], ["neat", "active", "nice"], ["length", "accuracy", "imagination"], [38, 38, 40, 42, 40, 34, 34, 36, 38, 28]],
	["Jin-Ae Seo", GolferAttributes.Gender.FEMALE, 27, GolferAttributes.MaritalStatus.SINGLE, "World #1 Ranked Pro", "casual", ["1e3f6e", "f2f3f7", "d9b648", "16151c", "f2d3ba"], ["neat", "active", "nice"], ["length", "accuracy", "imagination"], [34, 35, 44, 45, 44, 36, 36, 38, 38, 30]],
	["Dante Castellano", GolferAttributes.Gender.MALE, 29, GolferAttributes.MaritalStatus.SINGLE, "Grand Slam Contender", "casual", ["8f1d28", "23262e", "c9a438", "1c1614", "c79270"], ["outgoing", "active", "playful"], ["length", "accuracy", "imagination"], [44, 43, 35, 38, 36, 38, 36, 38, 37, 29]],
	["Freja Lindstrom", GolferAttributes.Gender.FEMALE, 30, GolferAttributes.MaritalStatus.MARRIED, "3x Open Champion", "casual", ["256378", "eef1f5", "204f5e", "c2a26b", "f5d6be"], ["neat", "active", "nice"], ["length", "accuracy", "imagination"], [36, 36, 42, 41, 40, 35, 36, 37, 39, 27]],
	["Rory Kavanagh", GolferAttributes.Gender.MALE, 34, GolferAttributes.MaritalStatus.MARRIED, "Links Major Legend", "casual", ["245c43", "ded9cb", "1b4532", "5e3820", "ebc3a4"], ["outgoing", "active", "nice"], ["length", "accuracy", "imagination"], [40, 41, 38, 39, 38, 37, 37, 36, 41, 28]],
	["Valentina Cruz", GolferAttributes.Gender.FEMALE, 26, GolferAttributes.MaritalStatus.SINGLE, "Players Champion", "casual", ["a83858", "f2eff2", "7d2941", "211714", "c48f6d"], ["outgoing", "active", "playful"], ["length", "accuracy", "imagination"], [37, 36, 39, 40, 41, 36, 35, 38, 37, 29]],
	["Kazuki Morimoto", GolferAttributes.Gender.MALE, 28, GolferAttributes.MaritalStatus.SINGLE, "Masters Medalist", "casual", ["26384f", "eceef2", "1c2a3b", "17161c", "edd0b6"], ["neat", "active"], ["length", "accuracy", "imagination"], [35, 36, 43, 44, 39, 36, 37, 40, 38, 27]],
	["Niamh Fitzgerald", GolferAttributes.Gender.FEMALE, 31, GolferAttributes.MaritalStatus.MARRIED, "2x Women's Open Winner", "casual", ["2e6e53", "edeae0", "22523d", "7d4425", "f2ccb2"], ["neat", "outgoing", "nice"], ["length", "accuracy", "imagination"], [33, 34, 41, 41, 42, 35, 35, 37, 40, 28]],
	["Marcus Thorne", GolferAttributes.Gender.MALE, 27, GolferAttributes.MaritalStatus.SINGLE, "World Long-Ball Icon", "casual", ["b86b23", "282b33", "8a501a", "1c1715", "785038"], ["active", "outgoing", "playful"], ["length", "accuracy", "imagination"], [45, 45, 33, 35, 34, 34, 32, 35, 36, 28]],
	["Celeste Moreau", GolferAttributes.Gender.FEMALE, 29, GolferAttributes.MaritalStatus.SINGLE, "Continental Order Winner", "casual", ["4c3a75", "f0edf5", "382b57", "42291c", "f0ceb6"], ["neat", "active"], ["length", "accuracy", "imagination"], [32, 33, 42, 43, 43, 37, 37, 38, 37, 27]],
	["Sebastian Adler", GolferAttributes.Gender.MALE, 35, GolferAttributes.MaritalStatus.MARRIED, "Tour Money-List Leader", "casual", ["384a5e", "e3e5eb", "293747", "4d3b2b", "e8bfa0"], ["neat", "active"], ["length", "accuracy", "imagination"], [37, 38, 40, 40, 39, 34, 35, 36, 38, 26]],
	["Ananya Deshmukh", GolferAttributes.Gender.FEMALE, 25, GolferAttributes.MaritalStatus.SINGLE, "Championship Prodigy", "casual", ["1f7068", "eef2f0", "17544e", "1a1618", "a87454"], ["neat", "active", "nice"], ["length", "accuracy", "imagination"], [35, 35, 41, 42, 41, 35, 35, 37, 36, 29]],
	["Gideon Botha", GolferAttributes.Gender.MALE, 37, GolferAttributes.MaritalStatus.MARRIED, "3x Invitational Legend", "casual", ["596638", "dedad0", "424d29", "574432", "e6be9e"], ["active", "nice"], ["length", "accuracy", "imagination"], [39, 39, 38, 39, 38, 36, 36, 37, 42, 28]],
	["Mei-Ling Zhou", GolferAttributes.Gender.FEMALE, 28, GolferAttributes.MaritalStatus.SINGLE, "Olympic Gold Medalist", "casual", ["ad2b3c", "f2f0f2", "82202d", "17161c", "f0d0b8"], ["neat", "active"], ["length", "accuracy", "imagination"], [34, 35, 43, 43, 42, 36, 36, 38, 37, 28]],
	["Lachlan Fraser", GolferAttributes.Gender.MALE, 31, GolferAttributes.MaritalStatus.SINGLE, "Pacific Masters Winner", "casual", ["235978", "2d323b", "1a4359", "4a3424", "e5bc9e"], ["outgoing", "active", "playful"], ["length", "accuracy", "imagination"], [40, 40, 37, 38, 37, 35, 35, 36, 39, 28]],
	["Astrid Holm", GolferAttributes.Gender.FEMALE, 33, GolferAttributes.MaritalStatus.MARRIED, "2x Major Champion", "casual", ["3b638c", "edf0f5", "2c4a69", "b89862", "f5d5bc"], ["neat", "nice", "active"], ["length", "accuracy", "imagination"], [35, 36, 41, 41, 40, 35, 36, 36, 38, 27]],
	["Emilio Navarro", GolferAttributes.Gender.MALE, 30, GolferAttributes.MaritalStatus.MARRIED, "World Match & Stroke Star", "casual", ["9e4d24", "e6e1d6", "783a1b", "211915", "c7926f"], ["outgoing", "playful", "active"], ["length", "accuracy", "imagination"], [38, 37, 38, 40, 41, 39, 38, 39, 41, 30]],
	["Victoria Kensington", GolferAttributes.Gender.FEMALE, 34, GolferAttributes.MaritalStatus.SINGLE, "Grand Slam Veteran", "casual", ["2b5248", "ebe8df", "d4af37", "523624", "f0cab0"], ["neat", "active", "nice"], ["length", "accuracy", "imagination"], [34, 35, 41, 42, 42, 36, 36, 38, 39, 28]],
]

# ── Difficulty Levels (Opposing Golfer Rosters) ─────────────────────────────

static func get_difficulties() -> Array[Dictionary]:
	var specs := [
		[
			Difficulty.EASY, "easy", "Easy", "Amateur Flight",
			TournamentSystem.TournamentTier.LOCAL, Color("6ebd68"),
			"Casual local club golfers with modest Golf Skills (+10% to +40%)."
		],
		[
			Difficulty.NORMAL, "normal", "Normal", "Club Circuit",
			TournamentSystem.TournamentTier.REGIONAL, Color("6bb0e0"),
			"Regional scratch contenders with trained Golf Skills (+50% to +110%)."
		],
		[
			Difficulty.HARD, "hard", "Hard", "Pro Tour",
			TournamentSystem.TournamentTier.NATIONAL, Color("e0a94f"),
			"Seasoned touring pros with sharp Golf Skills (+120% to +240%)."
		],
		[
			Difficulty.CHAMPIONSHIP, "championship", "Championship", "World Masters",
			TournamentSystem.TournamentTier.CHAMPIONSHIP, Color("e0c252"),
			"World-class major legends with elite Golf Skills (+260% to +450%)."
		],
	]
	var result: Array[Dictionary] = []
	for item in specs:
		var diff_id := int(item[0])
		var roster := get_difficulty_roster(diff_id)
		var total_skill_pct := 0
		var min_pct := 99999
		var max_pct := 0
		var featured_names: Array[String] = []
		for idx in range(roster.size()):
			var g := roster[idx]
			var avg_pct := int(g.get("avg_golf_skill_pct", 0))
			total_skill_pct += avg_pct
			min_pct = mini(min_pct, avg_pct)
			max_pct = maxi(max_pct, avg_pct)
			if idx < 3:
				featured_names.append(str(g["name"]))
		var mean_pct := roundi(float(total_skill_pct) / float(maxi(roster.size(), 1)))
		result.append({
			"id": diff_id,
			"key": str(item[1]),
			"name": str(item[2]),
			"subtitle": str(item[3]),
			"tier": int(item[4]),
			"accent": item[5] as Color,
			"roster_size": roster.size(),
			"avg_golf_skill_pct": mean_pct,
			"min_golf_skill_pct": min_pct,
			"max_golf_skill_pct": max_pct,
			"featured_golfers": featured_names,
			"badge": "AVG +%d%% GOLF SKILLS" % mean_pct,
			"summary": "%d-golfer %s list · Avg +%d%% Golf Skills · %s" % [
				roster.size(), str(item[3]), mean_pct, ", ".join(featured_names)
			],
			"description": str(item[6]),
		})
	return result

static func get_difficulty(difficulty_id: int) -> Dictionary:
	var all := get_difficulties()
	for entry in all:
		if int(entry["id"]) == difficulty_id:
			return entry
	return all[Difficulty.NORMAL]

static func get_difficulty_label(difficulty_id: int) -> String:
	var entry := get_difficulty(difficulty_id)
	return "%s (%s)" % [str(entry["name"]), str(entry["subtitle"])]

## Return the full 18-golfer opposing competitor list for `difficulty_id`.
## Every golfer carries full identity, skin, skin_colors, traits, golfer_skills,
## and all 10 golf_skills — with higher Golf Skills at each higher difficulty.
static func get_difficulty_roster(difficulty_id: int) -> Array[Dictionary]:
	var raw_specs: Array = _NORMAL_ROSTER_SPECS
	var diff_key := "normal"
	match difficulty_id:
		Difficulty.EASY:
			raw_specs = _EASY_ROSTER_SPECS
			diff_key = "easy"
		Difficulty.NORMAL:
			raw_specs = _NORMAL_ROSTER_SPECS
			diff_key = "normal"
		Difficulty.HARD:
			raw_specs = _HARD_ROSTER_SPECS
			diff_key = "hard"
		Difficulty.CHAMPIONSHIP:
			raw_specs = _CHAMPIONSHIP_ROSTER_SPECS
			diff_key = "championship"
	var roster: Array[Dictionary] = []
	for spec in raw_specs:
		roster.append(_entry_from_roster_spec(diff_key, spec))
	return roster

## Build `opponent_count` opposing tournament golfers for `difficulty_id`,
## excluding any competitor with the same name as the player's golfer.
static func build_opponent_roster(
	difficulty_id: int,
	opponent_count: int,
	exclude_name: String = ""
) -> Array[Dictionary]:
	var target := maxi(0, opponent_count)
	var base := get_difficulty_roster(difficulty_id)
	var filtered: Array[Dictionary] = []
	var clean_exclude := exclude_name.strip_edges().to_lower()
	for entry in base:
		if not clean_exclude.is_empty() and str(entry.get("name", "")).to_lower() == clean_exclude:
			continue
		filtered.append(entry)
	var selected: Array[Dictionary] = []
	for i in range(mini(target, filtered.size())):
		selected.append(filtered[i])
	# Deterministic overflow in the same Golf Skill band when field_size > 19
	var roman_suffixes: Array[String] = ["II", "III", "IV", "V", "VI"]
	var extra_idx := 0
	while selected.size() < target and not filtered.is_empty():
		var template: Dictionary = filtered[extra_idx % filtered.size()].duplicate(true)
		var cycle := int(float(extra_idx) / float(filtered.size()))
		extra_idx += 1
		var suffix: String = roman_suffixes[cycle] if cycle < roman_suffixes.size() else str(cycle + 2)
		template["id"] = "%s_alt_%d" % [str(template["id"]), extra_idx]
		template["name"] = "%s %s" % [str(template["name"]), suffix]
		selected.append(template)
	return selected

static func _entry_from_roster_spec(diff_key: String, spec: Array) -> Dictionary:
	var g_name := str(spec[0]).strip_edges()
	var gender_val := int(spec[1])
	var age_val := int(spec[2])
	var marital_val := int(spec[3])
	var prof_val := str(spec[4]).strip_edges()
	var skin_val := str(spec[5]).strip_edges()
	var pal: Array = spec[6]
	var skin_colors := {
		"Shirt": str(pal[0]),
		"Pants": str(pal[1]),
		"Cap": str(pal[2]),
		"Hair": str(pal[3]),
		"Skin": str(pal[4]),
	}
	var traits_dict := {}
	for key in GolferAttributes.TRAIT_KEYS:
		traits_dict[key] = key in (spec[7] as Array)
	var gskills_dict := {}
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		gskills_dict[key] = key in (spec[8] as Array)
	var pts: Array[int] = []
	for p in (spec[9] as Array):
		pts.append(clampi(int(p), 0, 99))
	while pts.size() < PlayerGolferProfile.SKILLS.size():
		pts.append(0)
	var slug := sanitize_slug(g_name, "competitor")
	var data := {
		"name": g_name,
		"profession": prof_val,
		"age": age_val,
		"gender": gender_val,
		"marital_status": marital_val,
		"initialized": true,
		"appearance": appearance_from_skin_colors(skin_colors),
		"points": pts,
		"traits": traits_dict,
		"golfer_skills": gskills_dict,
	}
	var profile := PlayerGolferProfile.from_data(data)
	return _build_golfer_entry(
		"field:%s:%s" % [diff_key, slug],
		profile,
		true,
		prof_val,
		"%s · Age %d" % [prof_val, age_val],
		skin_val,
		skin_colors,
		""
	)

# ── Tournament Format Types & Format Rules ──────────────────────────────────

static func get_format_types() -> Array[Dictionary]:
	return [
		{
			"id": FormatType.STROKE_PLAY,
			"key": "stroke_play",
			"name": "Stroke Play",
			"short_name": "Stroke Play",
			"summary": "Every stroke counts; lowest score vs par wins.",
			"description": "Traditional championship medal play: total strokes across all rounds relative to par. Lowest score wins.",
			"higher_is_better": false,
		},
		{
			"id": FormatType.STABLEFORD,
			"key": "stableford",
			"name": "Stableford",
			"short_name": "Stableford",
			"summary": "Hole points (Par 2, Birdie 3, Eagle 4, Bogey 1); highest points wins.",
			"description": "Points per hole against par: Albatross 5, Eagle 4, Birdie 3, Par 2, Bogey 1, Double Bogey or worse 0. Highest total wins.",
			"higher_is_better": true,
		},
		{
			"id": FormatType.MODIFIED_STABLEFORD,
			"key": "modified_stableford",
			"name": "Modified Stableford",
			"short_name": "Mod. Stableford",
			"summary": "Aggressive points (+8/+5/+2/0/-1/-3); rewards attacking pins.",
			"description": "Tour birdie-fest scoring: Albatross +8, Eagle +5, Birdie +2, Par 0, Bogey -1, Double Bogey or worse -3. Highest total wins.",
			"higher_is_better": true,
		},
		{
			"id": FormatType.SKINS,
			"key": "skins",
			"name": "Skins",
			"short_name": "Skins",
			"summary": "Outright lowest score on a hole wins its skin; ties carry over!",
			"description": "Each hole is worth 1 skin. Only a single outright low score claims the hole; any tie carries the skin forward to build the pot!",
			"higher_is_better": true,
		},
	]

static func get_format_info(format_type: int) -> Dictionary:
	for fmt in get_format_types():
		if int(fmt["id"]) == format_type:
			return fmt
	return get_format_types()[0]

static func get_format_name(format_type: int) -> String:
	return str(get_format_info(format_type).get("name", "Stroke Play"))

static func get_cut_rules() -> Array[Dictionary]:
	return [
		{
			"id": "none",
			"name": "No Cut",
			"summary": "Full field plays every round",
			"description": "Every golfer in the field competes through the final round.",
		},
		{
			"id": "top_50pct",
			"name": "Top 50% + Ties",
			"summary": "Halfway cut trims to top half + ties",
			"description": "After the midpoint round (2+ round events), only the top 50% of the field and ties advance.",
		},
		{
			"id": "top_10_ties",
			"name": "Top 10 + Ties",
			"summary": "Halfway cut trims to top 10 + ties",
			"description": "After the midpoint round (2+ round events), only the top 10 contenders and ties advance.",
		},
	]

static func get_cut_rule_label(cut_rule: String, rounds: int = 2) -> String:
	if rounds <= 1 or cut_rule == "none" or cut_rule.is_empty():
		return "No Cut"
	for item in get_cut_rules():
		if str(item["id"]) == cut_rule:
			return str(item["name"])
	return "No Cut"

static func higher_points_is_better(format_type: int) -> bool:
	return format_type in [FormatType.STABLEFORD, FormatType.MODIFIED_STABLEFORD, FormatType.SKINS]

## Compute points earned on a single hole for Stableford / Modified Stableford.
static func hole_points_for_format(format_type: int, strokes: int, par: int) -> int:
	if strokes <= 0 or par <= 0:
		return 0
	var diff := strokes - par
	match format_type:
		FormatType.STABLEFORD:
			if diff <= -3:
				return 5
			elif diff == -2:
				return 4
			elif diff == -1:
				return 3
			elif diff == 0:
				return 2
			elif diff == 1:
				return 1
			return 0
		FormatType.MODIFIED_STABLEFORD:
			if diff <= -3:
				return 8
			elif diff == -2:
				return 5
			elif diff == -1:
				return 2
			elif diff == 0:
				return 0
			elif diff == 1:
				return -1
			return -3
	return 0

## Format a golfer's tournament score according to `format_type`.
static func format_score_for_format(
	format_type: int,
	score_to_par: int,
	format_points: int,
	has_played: bool = true
) -> String:
	if not has_played:
		return "-"
	match format_type:
		FormatType.STABLEFORD:
			return "%d pts" % format_points
		FormatType.MODIFIED_STABLEFORD:
			return ("+%d pts" % format_points) if format_points > 0 else ("%d pts" % format_points)
		FormatType.SKINS:
			return "1 Skin" if format_points == 1 else ("%d Skins" % format_points)
		_:
			if score_to_par == 0:
				return "E"
			elif score_to_par > 0:
				return "+%d" % score_to_par
			return "%d" % score_to_par

# ── Storage Paths ───────────────────────────────────────────────────────────

static func courses_dir() -> String:
	return PlayerDataStore.saves_dir.trim_suffix("/").path_join(COURSES_SUBDIR)

static func _ensure_courses_dir() -> bool:
	var dir_path := courses_dir()
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK

static func sanitize_slug(raw_name: String, fallback: String = "custom") -> String:
	var cleaned := SaveLoadPanel.sanitize_save_name(raw_name).to_lower().replace(" ", "_")
	var safe := ""
	for i in range(cleaned.length()):
		var ch := cleaned.substr(i, 1)
		var code := ch.unicode_at(0)
		var is_alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if is_alnum or ch == "_" or ch == "-":
			safe += ch
	while safe.contains("__"):
		safe = safe.replace("__", "_")
	safe = safe.trim_prefix("_").trim_suffix("_")
	return fallback if safe.is_empty() else safe

# ── Courses: List, Save, Load, Delete, Build ────────────────────────────────

static func list_courses() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for def in DEFAULT_COURSES:
		entries.append(_default_course_entry(def))
	for saved in list_saved_courses():
		entries.append(saved)
	return entries

static func list_saved_courses() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	var dir_path := courses_dir()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return saved
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(COURSE_EXT):
			var full_path := dir_path.path_join(file_name)
			var entry := _read_saved_course_entry(full_path, file_name.trim_suffix(COURSE_EXT))
			if not entry.is_empty():
				saved.append(entry)
		file_name = dir.get_next()
	dir.list_dir_end()
	saved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("saved_at", "")) > str(b.get("saved_at", ""))
	)
	return saved

static func saved_course_count() -> int:
	return list_saved_courses().size()

static func get_course(course_id: String) -> Dictionary:
	for entry in list_courses():
		if str(entry.get("id", "")) == course_id:
			return entry
	var all := list_courses()
	return all[0] if not all.is_empty() else {}

## Export the currently open Career course for standalone Tournament Mode.
static func save_career_course(custom_name: String = "") -> Dictionary:
	if GameManager.current_course == null:
		return {"ok": false, "error": "No course is currently open."}
	var open_holes := 0
	var open_par := 0
	for hole in GameManager.current_course.holes:
		if hole.is_open:
			open_holes += 1
			open_par += int(hole.par)
	if open_holes <= 0:
		return {"ok": false, "error": "Build and open at least 1 hole before saving for Tournament Mode."}
	if not _ensure_courses_dir():
		return {"ok": false, "error": "Could not create the tournament courses folder."}

	var display_name := custom_name.strip_edges()
	if display_name.is_empty():
		display_name = GameManager.course_name.strip_edges()
	if display_name.is_empty():
		display_name = "Career Course"

	var slug := sanitize_slug(display_name, "career_course")
	var snapshot := SaveManager.build_location_snapshot()
	if snapshot.is_empty():
		return {"ok": false, "error": "Could not capture the current course snapshot."}

	var payload := {
		"format_version": FORMAT_VERSION,
		"slug": slug,
		"name": display_name,
		"saved_at": Time.get_datetime_string_from_system(),
		"theme": int(GameManager.current_theme),
		"hole_count": open_holes,
		"par": open_par,
		"course_rating": float(GameManager.course_rating.get("overall", 3.5)),
		"snapshot": snapshot,
	}
	var file_path := courses_dir().path_join(slug + COURSE_EXT)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Failed to write tournament course file."}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return {
		"ok": true,
		"id": "saved:" + slug,
		"slug": slug,
		"name": display_name,
		"hole_count": open_holes,
		"par": open_par,
	}

static func delete_saved_course(course_id: String) -> bool:
	if not course_id.begins_with("saved:"):
		return false
	var slug := course_id.trim_prefix("saved:")
	var file_path := courses_dir().path_join(slug + COURSE_EXT)
	if not FileAccess.file_exists(file_path):
		return false
	return DirAccess.remove_absolute(file_path) == OK

static func load_saved_course_payload(course_id: String) -> Dictionary:
	if not course_id.begins_with("saved:"):
		return {}
	var slug := course_id.trim_prefix("saved:")
	var file_path := courses_dir().path_join(slug + COURSE_EXT)
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return json.data as Dictionary

## Build one of the 4 built-in Default Courses onto the active TerrainGrid.
static func build_default_course(
	course_id: String,
	terrain_grid: TerrainGrid,
	entity_layer: EntityLayer,
	hole_tool: HoleCreationTool
) -> bool:
	var def: Dictionary = {}
	for candidate in DEFAULT_COURSES:
		if str(candidate["id"]) == course_id:
			def = candidate
			break
	if def.is_empty() or terrain_grid == null or entity_layer == null or hole_tool == null:
		return false

	var theme := int(def.get("theme", CourseTheme.Type.PARKLAND))
	var holes := int(def.get("hole_count", 9))
	var seed_value := int(def.get("seed", 7101))
	var layout := str(def.get("layout", "generated"))

	GameManager.current_course = GameManager.CourseData.new()
	GameManager.course_name = str(def.get("name", "Tournament Course"))
	GameManager.current_theme = theme
	var colors := ColorblindMode.remap_colors(
		CourseTheme.get_terrain_colors(theme), GameManager.colorblind_mode)
	TerrainPalette.set_theme_colors(colors)
	EventBus.theme_changed.emit(theme)

	hole_tool.current_hole_number = 1
	if GameManager.land_manager != null:
		GameManager.land_manager.grant_parcels(WorldLocations.get_required_parcels(holes))

	terrain_grid.begin_batch()
	NaturalTerrainGenerator.generate(terrain_grid, entity_layer, seed_value)
	terrain_grid.end_batch_quiet()
	terrain_grid.refresh_all_overlays()

	var preferred := CourseClubhouse.arrival_corner()
	if layout == "quick_start":
		terrain_grid.begin_batch()
		QuickStartCourse.build(terrain_grid, entity_layer, hole_tool)
		terrain_grid.end_batch_quiet()
		terrain_grid.refresh_all_overlays()
		preferred = QuickStartCourse.CLUBHOUSE_TILE
	elif layout.begins_with("prebuilt:"):
		PrebuiltCourseGenerator.build(layout.trim_prefix("prebuilt:"), terrain_grid, hole_tool)
	else:
		terrain_grid.begin_batch()
		GeneratedCourse.generate(holes, terrain_grid, entity_layer, hole_tool)
		terrain_grid.end_batch_quiet()
		terrain_grid.refresh_all_overlays()
		preferred = GeneratedCourse.get_anchor(holes) + GeneratedCourse.CLUBHOUSE_OFFSET

	CourseClubhouse.ensure(terrain_grid, entity_layer, preferred)
	StrokeIndexCalculator.recalculate_for_course()
	GameManager.update_course_rating()
	return GameManager.current_course != null and not GameManager.current_course.holes.is_empty()

static func _default_course_entry(def: Dictionary) -> Dictionary:
	var theme := int(def.get("theme", CourseTheme.Type.PARKLAND))
	var holes := int(def.get("hole_count", 9))
	var par := int(def.get("par", 36))
	var layout := str(def.get("layout", "generated"))
	return {
		"id": str(def["id"]),
		"name": str(def["name"]),
		"is_default": true,
		"source_label": "DEFAULT",
		"theme": theme,
		"theme_name": CourseTheme.get_theme_name(theme),
		"hole_count": holes,
		"par": par,
		"tagline": str(def.get("tagline", "")),
		"layout": layout,
		"preview_holes": _preview_holes_for_default(layout, holes),
	}

static func _read_saved_course_entry(full_path: String, slug: String) -> Dictionary:
	var file := FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	var data: Dictionary = json.data
	var snapshot: Dictionary = data.get("snapshot", {}) if data.get("snapshot") is Dictionary else {}
	var theme := int(data.get("theme", snapshot.get("theme", CourseTheme.Type.PARKLAND)))
	var preview_holes := _preview_holes_from_snapshot(snapshot)
	var hole_count := int(data.get("hole_count", preview_holes.size()))
	var par := int(data.get("par", hole_count * 4))
	return {
		"id": "saved:" + slug,
		"slug": slug,
		"name": str(data.get("name", slug.capitalize())),
		"is_default": false,
		"source_label": "CAREER",
		"saved_at": str(data.get("saved_at", "")),
		"theme": theme,
		"theme_name": CourseTheme.get_theme_name(theme),
		"hole_count": hole_count,
		"par": par,
		"tagline": "Saved from Career Mode · %s · %d holes (Par %d)" % [
			CourseTheme.get_theme_name(theme), hole_count, par
		],
		"preview_holes": preview_holes,
	}

static func _preview_holes_for_default(layout: String, hole_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if layout == "quick_start" or layout == "prebuilt:standard9":
		var raw_std: Array = [
			[Vector2i(46, 46), Vector2i(62, 48), 4, Vector2i(-1, -1)],
			[Vector2i(65, 46), Vector2i(74, 46), 3, Vector2i(-1, -1)],
			[Vector2i(76, 48), Vector2i(80, 72), 5, Vector2i(78, 60)],
			[Vector2i(78, 75), Vector2i(62, 80), 4, Vector2i(-1, -1)],
			[Vector2i(59, 80), Vector2i(46, 70), 4, Vector2i(-1, -1)],
			[Vector2i(46, 67), Vector2i(48, 52), 4, Vector2i(-1, -1)],
			[Vector2i(50, 50), Vector2i(72, 56), 5, Vector2i(62, 56)],
			[Vector2i(74, 58), Vector2i(78, 66), 3, Vector2i(76, 62)],
			[Vector2i(76, 68), Vector2i(62, 64), 4, Vector2i(-1, -1)],
		]
		for item in raw_std:
			result.append({
				"tee": item[0],
				"green": item[1],
				"par": int(item[2]),
				"water": item[3],
			})
		return result

	var anchor := GeneratedCourse.get_anchor(hole_count)
	for h in GeneratedCourse.layout_for(hole_count):
		var tee := anchor + Vector2i(h[0])
		var green := anchor + Vector2i(h[1])
		var water := Vector2i(-1, -1)
		if h.size() > 3 and h[3] != null:
			water = anchor + Vector2i(h[3])
		var tiles := Vector2(tee).distance_to(Vector2(green))
		var par := 3 if tiles < 11.5 else (5 if tiles > 20.5 else 4)
		result.append({
			"tee": tee,
			"green": green,
			"par": par,
			"water": water,
		})
	return result

static func _preview_holes_from_snapshot(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var holes_var: Variant = snapshot.get("holes", [])
	if not (holes_var is Array):
		return result
	for h in holes_var:
		if not (h is Dictionary):
			continue
		if not bool(h.get("is_open", true)):
			continue
		var tee_d: Dictionary = h.get("tee_position", {}) if h.get("tee_position") is Dictionary else {}
		var green_d: Dictionary = h.get("green_position", {}) if h.get("green_position") is Dictionary else {}
		result.append({
			"tee": Vector2i(int(tee_d.get("x", 64)), int(tee_d.get("y", 64))),
			"green": Vector2i(int(green_d.get("x", 68)), int(green_d.get("y", 64))),
			"par": int(h.get("par", 4)),
			"water": Vector2i(-1, -1),
		})
	return result

# ── Golfers: List, Save, Load, Delete, Instantiate ──────────────────────────

static func list_golfers() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for def in DEFAULT_GOLFERS:
		entries.append(_default_golfer_entry(def))
	for saved in list_saved_golfers():
		entries.append(saved)
	return entries

static func list_saved_golfers() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	var cfg := ConfigFile.new()
	if cfg.load(PlayerDataStore.settings_path) != OK:
		return saved
	if not cfg.has_section(GOLFERS_SECTION):
		return saved
	for slug in cfg.get_section_keys(GOLFERS_SECTION):
		var raw: Variant = cfg.get_value(GOLFERS_SECTION, slug, {})
		if not (raw is Dictionary):
			continue
		var entry := _saved_golfer_entry_from_record(str(slug), raw as Dictionary)
		if not entry.is_empty():
			saved.append(entry)
	saved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("saved_at", "")) > str(b.get("saved_at", ""))
	)
	return saved

static func saved_golfer_count() -> int:
	return list_saved_golfers().size()

static func get_golfer(golfer_id: String) -> Dictionary:
	for entry in list_golfers():
		if str(entry.get("id", "")) == golfer_id:
			return entry
	var all := list_golfers()
	return all[0] if not all.is_empty() else {}

## Capture the currently worn Career skin & group colours for `profile`.
static func capture_skin_colors(profile: PlayerGolferProfile, skin_id: String = "") -> Dictionary:
	var colors: Dictionary = {}
	var chosen_id := skin_id
	if chosen_id.is_empty() and GameManager != null:
		chosen_id = GameManager.player_skin_id
	if GolferSkins != null and GolferSkins.library != null:
		var skin: GolferSkin = GolferSkins.library.get_skin(chosen_id) if not chosen_id.is_empty() else GolferSkins.player_skin()
		if skin != null:
			for grp in skin.group_list():
				var grp_name := str(grp.get("name", "")).strip_edges()
				if not grp_name.is_empty():
					var c: Color = grp.get("color", Color.WHITE)
					colors[grp_name] = c.to_html(false)
	if profile != null:
		for p_key in PROFILE_KEY_TO_SKIN_GROUP:
			var grp_name := str(PROFILE_KEY_TO_SKIN_GROUP[p_key])
			if profile.appearance.has(p_key):
				var hex := Color.from_string(str(profile.appearance[p_key]), Color.WHITE).to_html(false)
				colors[grp_name] = hex
	return colors

static func appearance_from_skin_colors(skin_colors: Dictionary, fallback: Dictionary = {}) -> Dictionary:
	var app := {
		"shirt_color": "2e7057",
		"pants_color": "2e333d",
		"cap_color": "f2f0e6",
		"hair_color": "4d331a",
		"skin_tone": "edc4a3",
	}
	for k in fallback:
		if app.has(str(k)):
			app[str(k)] = Color.from_string(str(fallback[k]), Color(app[str(k)])).to_html(false)
	for grp_name in skin_colors:
		var p_key := str(SKIN_GROUP_TO_PROFILE_KEY.get(str(grp_name), ""))
		if not p_key.is_empty():
			app[p_key] = Color.from_string(str(skin_colors[grp_name]), Color(app[p_key])).to_html(false)
	return app

## Convert a golfer entry's `skin_colors` hex dictionary into `Golfer.group_color_overrides` (`String -> Color`).
static func skin_color_overrides_from_entry(golfer_entry: Dictionary) -> Dictionary:
	var overrides: Dictionary = {}
	var raw: Variant = golfer_entry.get("skin_colors", {})
	if raw is Dictionary:
		for grp_name in raw:
			overrides[str(grp_name)] = Color.from_string(str(raw[grp_name]), Color.WHITE)
	return overrides

## Export a Career golfer with full details (Name, Skin, Skin Colours,
## Profession, Age, Gender, Marital Status, Golfer Traits, Golfer Skills,
## and all 10 Golf Skills) for standalone Tournament Mode.
static func save_career_golfer(
	profile: PlayerGolferProfile = null,
	skin_id: String = "",
	explicit_skin_colors: Dictionary = {}
) -> Dictionary:
	var active_profile := profile if profile != null else GameManager.player_profile
	if active_profile == null:
		return {"ok": false, "error": "No golfer profile is available to save."}

	var display_name := active_profile.golfer_name.strip_edges()
	if display_name.is_empty():
		display_name = "Club Pro"
	var slug := sanitize_slug(display_name, "career_golfer")

	var chosen_skin := skin_id.strip_edges()
	if chosen_skin.is_empty():
		chosen_skin = GameManager.player_skin_id.strip_edges()
	if chosen_skin.is_empty() and GolferSkins != null and GolferSkins.player_skin() != null:
		chosen_skin = GolferSkins.player_skin().id
	if chosen_skin.is_empty():
		chosen_skin = "casual"

	var skin_colors := capture_skin_colors(active_profile, chosen_skin)
	for grp_name in explicit_skin_colors:
		skin_colors[str(grp_name)] = Color.from_string(str(explicit_skin_colors[grp_name]), Color.WHITE).to_html(false)

	var golf_skills_map := {}
	for i in range(mini(active_profile.points.size(), GolferAttributes.GOLF_SKILLS.size())):
		golf_skills_map[GolferAttributes.GOLF_SKILLS[i]] = int(active_profile.points[i])

	var cfg := ConfigFile.new()
	cfg.load(PlayerDataStore.settings_path)
	var record := {
		"format_version": FORMAT_VERSION,
		"slug": slug,
		"name": display_name,
		"saved_at": Time.get_datetime_string_from_system(),
		"skin_id": chosen_skin,
		"skin_colors": skin_colors,
		"profession": active_profile.profession,
		"age": active_profile.age,
		"gender": active_profile.gender,
		"marital_status": active_profile.marital_status,
		"traits": active_profile.traits.duplicate(),
		"golfer_skills": active_profile.golfer_skills.duplicate(),
		"golf_skills": golf_skills_map,
		"points": active_profile.points.duplicate(),
		"profile": active_profile.serialize(),
	}
	cfg.set_value(GOLFERS_SECTION, slug, record)
	if cfg.save(PlayerDataStore.settings_path) != OK:
		return {"ok": false, "error": "Failed to write tournament golfer data."}
	return {
		"ok": true,
		"id": "saved:" + slug,
		"slug": slug,
		"name": display_name,
		"skin_id": chosen_skin,
		"skin_colors": skin_colors,
	}

static func delete_saved_golfer(golfer_id: String) -> bool:
	if not golfer_id.begins_with("saved:"):
		return false
	var slug := golfer_id.trim_prefix("saved:")
	var cfg := ConfigFile.new()
	if cfg.load(PlayerDataStore.settings_path) != OK:
		return false
	if not cfg.has_section_key(GOLFERS_SECTION, slug):
		return false
	cfg.erase_section_key(GOLFERS_SECTION, slug)
	return cfg.save(PlayerDataStore.settings_path) == OK

## Instantiate a ready-to-play `PlayerGolferProfile` from any golfer entry.
static func make_golfer_profile(golfer_entry: Dictionary) -> PlayerGolferProfile:
	var profile_data: Variant = golfer_entry.get("profile_data", {})
	if profile_data is Dictionary and not (profile_data as Dictionary).is_empty():
		var p_data := (profile_data as Dictionary).duplicate(true)
		p_data["initialized"] = true
		return PlayerGolferProfile.from_data(p_data)
	var fallback := PlayerGolferProfile.new()
	fallback.golfer_name = str(golfer_entry.get("name", "Tournament Player"))
	fallback.initialized = true
	return fallback

## Instantiate a complete `GolferAttributes` block from any golfer entry.
static func make_golfer_attributes(golfer_entry: Dictionary, tier: int = GolferTier.Tier.SERIOUS) -> GolferAttributes:
	var attrs := GolferAttributes.new()
	attrs.golfer_tier = tier
	attrs.name = str(golfer_entry.get("name", "Golfer"))
	attrs.profession = str(golfer_entry.get("profession", "Tour Professional"))
	attrs.age = clampi(int(golfer_entry.get("age", 30)), 18, 99)
	attrs.gender = GolferAttributes.Gender.FEMALE if int(golfer_entry.get("gender", 0)) == GolferAttributes.Gender.FEMALE else GolferAttributes.Gender.MALE
	attrs.marital_status = clampi(int(golfer_entry.get("marital_status", 0)), 0, 3)
	var traits_var: Variant = golfer_entry.get("traits", {})
	if traits_var is Dictionary:
		for key in GolferAttributes.TRAIT_KEYS:
			attrs.traits[key] = bool((traits_var as Dictionary).get(key, false))
	var gskills_var: Variant = golfer_entry.get("golfer_skills", {})
	if gskills_var is Dictionary:
		for key in GolferAttributes.GOLFER_SKILL_KEYS:
			attrs.golfer_skills[key] = bool((gskills_var as Dictionary).get(key, false))
	var pts_var: Variant = golfer_entry.get("points", [])
	if pts_var is Array:
		for i in range(mini((pts_var as Array).size(), attrs.golf_points.size())):
			attrs.golf_points[i] = clampi(int((pts_var as Array)[i]), 0, GolferAttributes.POINTS_PER_GOLF_SKILL)
	return attrs

static func _default_golfer_entry(def: Dictionary) -> Dictionary:
	var skin_colors: Dictionary = (def.get("skin_colors", {}) as Dictionary).duplicate()
	var data := {
		"name": str(def.get("name", "Golfer")),
		"profession": str(def.get("profession", "Tour Professional")),
		"age": int(def.get("age", 30)),
		"gender": int(def.get("gender", GolferAttributes.Gender.MALE)),
		"marital_status": int(def.get("marital_status", GolferAttributes.MaritalStatus.SINGLE)),
		"initialized": true,
		"appearance": appearance_from_skin_colors(skin_colors, def.get("appearance", {})),
		"points": def.get("points", [5, 5, 5, 5, 5, 2, 2, 2, 5, 2]),
		"traits": def.get("traits", {}),
		"golfer_skills": def.get("golfer_skills", {}),
	}
	var p := PlayerGolferProfile.from_data(data)
	return _build_golfer_entry(
		str(def["id"]),
		p,
		true,
		str(def.get("archetype", p.profession)),
		str(def.get("tagline", "")),
		str(def.get("skin_id", "casual")),
		skin_colors,
		""
	)

static func _saved_golfer_entry_from_record(slug: String, record: Dictionary) -> Dictionary:
	var profile_dict: Dictionary = {}
	if record.get("profile") is Dictionary:
		profile_dict = (record.get("profile") as Dictionary).duplicate(true)
	# Overlay top-level golfer detail fields when present
	for field in ["name", "profession", "age", "gender", "marital_status", "traits", "golfer_skills", "points"]:
		if record.has(field):
			profile_dict[field] = record[field]
	profile_dict["initialized"] = true
	var skin_colors: Dictionary = {}
	if record.get("skin_colors") is Dictionary:
		for k in record["skin_colors"]:
			skin_colors[str(k)] = Color.from_string(str(record["skin_colors"][k]), Color.WHITE).to_html(false)
	profile_dict["appearance"] = appearance_from_skin_colors(
		skin_colors,
		profile_dict.get("appearance", {}) if profile_dict.get("appearance") is Dictionary else {}
	)
	var p := PlayerGolferProfile.from_data(profile_dict)
	if skin_colors.is_empty():
		skin_colors = capture_skin_colors(p, str(record.get("skin_id", "casual")))
	var display_name := str(record.get("name", p.golfer_name)).strip_edges()
	if not display_name.is_empty():
		p.golfer_name = display_name
	var chosen_skin := str(record.get("skin_id", "casual")).strip_edges()
	if chosen_skin.is_empty():
		chosen_skin = "casual"
	var subtitle := "%s · Career Golfer" % p.profession
	var tagline := "Saved from Career Mode · %s · Age %d · %s" % [
		p.profession,
		p.age,
		GolferAttributes.GENDER_NAMES.get(p.gender, "Male"),
	]
	return _build_golfer_entry(
		"saved:" + slug,
		p,
		false,
		subtitle,
		tagline,
		chosen_skin,
		skin_colors,
		str(record.get("saved_at", ""))
	)

static func _skin_display_name(skin_id: String) -> String:
	if skin_id.is_empty():
		return "Casual"
	if GolferSkins != null and GolferSkins.library != null:
		var skin := GolferSkins.library.get_skin(skin_id)
		if skin != null and not skin.display_name.is_empty():
			return skin.display_name
	return skin_id.replace("_", " ").capitalize()

static func _build_golfer_entry(
	entry_id: String,
	p: PlayerGolferProfile,
	is_default: bool,
	archetype: String,
	tagline: String,
	skin_id: String,
	skin_colors_in: Dictionary,
	saved_at: String
) -> Dictionary:
	var chosen_skin := skin_id.strip_edges()
	if chosen_skin.is_empty():
		chosen_skin = "casual"
	var skin_colors := skin_colors_in.duplicate()
	for p_key in PROFILE_KEY_TO_SKIN_GROUP:
		var grp_name := str(PROFILE_KEY_TO_SKIN_GROUP[p_key])
		if not skin_colors.has(grp_name) and p.appearance.has(p_key):
			skin_colors[grp_name] = Color.from_string(str(p.appearance[p_key]), Color.WHITE).to_html(false)

	var shirt := Color.from_string(str(skin_colors.get("Shirt", p.appearance.get("shirt_color", "2e7057"))), Color("2e7057"))
	var cap := Color.from_string(str(skin_colors.get("Cap", p.appearance.get("cap_color", "f2f0e6"))), Color("f2f0e6"))
	var skin_col := Color.from_string(str(skin_colors.get("Skin", p.appearance.get("skin_tone", "edc4a3"))), Color("edc4a3"))
	var pants := Color.from_string(str(skin_colors.get("Pants", p.appearance.get("pants_color", "2e333d"))), Color("2e333d"))
	var hair := Color.from_string(str(skin_colors.get("Hair", p.appearance.get("hair_color", "4d331a"))), Color("4d331a"))

	var active_traits: Array[String] = []
	for key in GolferAttributes.TRAIT_KEYS:
		if bool(p.traits.get(key, false)):
			active_traits.append(str(GolferAttributes.TRAIT_NAMES.get(key, key.capitalize())))

	var active_gskills: Array[String] = []
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		if bool(p.golfer_skills.get(key, false)):
			active_gskills.append(str(GolferAttributes.GOLFER_SKILL_NAMES.get(key, key.capitalize())))

	var total_pts := 0
	var golf_skills_dict := {}
	for i in range(mini(p.points.size(), GolferAttributes.GOLF_SKILLS.size())):
		var pts := int(p.points[i])
		total_pts += pts
		golf_skills_dict[GolferAttributes.GOLF_SKILLS[i]] = pts
	var avg_skill_pct := roundi(float(total_pts * GolferAttributes.PERCENT_PER_POINT) / float(maxi(p.points.size(), 1)))

	var gender_str := str(GolferAttributes.GENDER_NAMES.get(p.gender, "Male"))
	var marital_str := str(GolferAttributes.MARITAL_STATUS_NAMES.get(p.marital_status, "Single"))

	return {
		"id": entry_id,
		"name": p.golfer_name,
		"is_default": is_default,
		"source_label": "DEFAULT" if is_default else "CAREER",
		"archetype": archetype,
		"tagline": tagline,
		"skin_id": chosen_skin,
		"skin_name": _skin_display_name(chosen_skin),
		"skin_colors": skin_colors,
		"profession": p.profession,
		"age": p.age,
		"gender": p.gender,
		"gender_name": gender_str,
		"marital_status": p.marital_status,
		"marital_status_name": marital_str,
		"traits": p.traits.duplicate(),
		"active_traits": active_traits,
		"golfer_skills": p.golfer_skills.duplicate(),
		"active_golfer_skills": active_gskills,
		"points": p.points.duplicate(),
		"golf_skills": golf_skills_dict,
		"total_golf_points": total_pts,
		"avg_golf_skill_pct": avg_skill_pct,
		"saved_at": saved_at,
		"profile_data": p.serialize(),
		"driving_pct": clampf(p.driving_ability() * 100.0, 0.0, 100.0),
		"accuracy_pct": clampf(p.accuracy_ability() * 100.0, 0.0, 100.0),
		"putting_pct": clampf(p.putting_ability() * 100.0, 0.0, 100.0),
		"recovery_pct": clampf(p.recovery_ability() * 100.0, 0.0, 100.0),
		"shirt_color": shirt,
		"cap_color": cap,
		"skin_color": skin_col,
		"pants_color": pants,
		"hair_color": hair,
	}
