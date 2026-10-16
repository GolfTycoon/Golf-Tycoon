extends RefCounted
class_name PlayerGolferProfile
## Persistent owner golfer. Percentages are bonuses, not AI's normalized skills.
const SKILLS = ["Power Hitter", "Long Driver", "Accurate Driver", "Accurate Irons",
	"Accurate Putter", "Draw Shot (R to L)", "Fade Shot (L to R)",
	"High Backspin Shot", "Recovery Skills", "Luck"]
const COLORS = ["shirt_color", "pants_color", "cap_color", "hair_color", "skin_tone"]
var golfer_name: String = "Course Owner"
var profession: String = "Professional"
var age: int = 30
var gender: int = GolferAttributes.Gender.MALE
var marital_status: int = GolferAttributes.MaritalStatus.SINGLE
var traits: Dictionary = {"neat": false, "outgoing": false, "active": false, "playful": false, "nice": false}
var golfer_skills: Dictionary = {"length": false, "accuracy": false, "imagination": false}
var appearance: Dictionary = {"shirt_color": "e65959", "pants_color": "404059",
	"cap_color": "3366b3", "hair_color": "4d331a", "skin_tone": "f2cca6"}
var points: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var initialized: bool = false

func remaining() -> int:
	var spent := 0
	for value in points:
		spent += value
	return maxi(0, 10 - spent)

func allocate(index: int, change: int, force: bool = false) -> bool:
	if (initialized and not force) or index < 0 or index >= points.size() or abs(change) != 1:
		return false
	if points[index] + change < 0 or points[index] + change > 99:
		return false
	if change > 0 and remaining() == 0:
		return false
	points[index] += change
	return true

func reallocate(index: int, change: int) -> bool:
	return allocate(index, change, true)

func bonus(index: int) -> float:
	return points[index] * 0.1

func normalized_skill(index: int) -> float:
	return 1.0 - 0.5 / (1.0 + bonus(index))

## Playing abilities (0.0-1.0) derived from the allocated Golf Skill points -
## the same curves every golfer uses (see GolferAttributes).
func driving_ability() -> float:
	return GolferAttributes.ability_from_bonus((bonus(0) + bonus(1)) * 0.5)

func accuracy_ability() -> float:
	return GolferAttributes.ability_from_bonus((bonus(2) + bonus(3)) * 0.5)

func putting_ability() -> float:
	return normalized_skill(4)

func recovery_ability() -> float:
	return normalized_skill(8)

func serialize() -> Dictionary:
	return {"name": golfer_name, "appearance": appearance.duplicate(),
		"points": points.duplicate(), "initialized": initialized,
		"profession": profession, "age": age, "gender": gender,
		"marital_status": marital_status, "traits": traits.duplicate(),
		"golfer_skills": golfer_skills.duplicate()}

static func from_data(data: Dictionary) -> PlayerGolferProfile:
	var profile := PlayerGolferProfile.new()
	profile.golfer_name = str(data.get("name", "Course Owner")).strip_edges().left(32)
	if profile.golfer_name.is_empty():
		profile.golfer_name = "Course Owner"
	var colors = data.get("appearance", {})
	if colors is Dictionary:
		for key in COLORS:
			profile.appearance[key] = Color.from_string(str(colors.get(key, profile.appearance[key])), Color(profile.appearance[key])).to_html(false)
	var saved = data.get("points", [])
	if saved is Array and saved.size() == SKILLS.size():
		for i in SKILLS.size():
			profile.points[i] = clampi(int(saved[i]), 0, 99)
	profile.initialized = bool(data.get("initialized", false))
	profile.profession = str(data.get("profession", "Professional")).strip_edges().left(48)
	profile.age = clampi(int(data.get("age", 30)), 18, 100)
	profile.gender = clampi(int(data.get("gender", 0)), 0, 1)
	profile.marital_status = clampi(int(data.get("marital_status", 0)), 0, 3)
	for key in GolferAttributes.TRAIT_KEYS:
		profile.traits[key] = bool(data.get("traits", {}).get(key, false))
	for key in GolferAttributes.GOLFER_SKILL_KEYS:
		profile.golfer_skills[key] = bool(data.get("golfer_skills", {}).get(key, false))
	if not profile.initialized:
		var budget := 10
		for i in profile.points.size():
			profile.points[i] = mini(profile.points[i], budget)
			budget -= profile.points[i]
	return profile
