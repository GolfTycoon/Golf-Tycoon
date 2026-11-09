extends RefCounted
class_name TournamentCareerExport
## Career Mode exports for standalone Tournament Mode.
##
## The Pause Menu's Save Course and Save Golfer cards are the only entry points
## for these exports. They used to live on the owner's round shelves, which
## meant the open course and the player's golfer could only be exported while a
## shelf happened to be built. The exports read GameManager's live state here,
## so they work from the pause menu at any time, including mid-round.
##
## TournamentLibrary owns the file format; this helper captures whatever the
## library needs from the live game, reports the outcome through EventBus and
## returns the same result plus a `message` the menu can show in place.

const COURSE_ERROR := "Could not save course for Tournament Mode."
const GOLFER_ERROR := "Could not save golfer for Tournament Mode."


## Snapshot the open Career course so Start Tournament can offer it.
static func save_course() -> Dictionary:
	var result := TournamentLibrary.save_career_course()
	var ok := bool(result.get("ok", false))
	var message := course_message(result)
	EventBus.notify(message, "success" if ok else "warning")
	return _with_message(result, message, ok)


## Snapshot the owner's golfer - skills, traits, appearance and the colours of
## the skin they wear - so Start Tournament can offer them as a playable golfer.
## Profile edits persist as they are made, so GameManager holds the live record;
## there is no round-shelf draft to flush first.
static func save_golfer() -> Dictionary:
	var worn_skin: GolferSkin = null
	if GolferSkins != null:
		worn_skin = GolferSkins.player_skin()
	var skin_id := GameManager.player_skin_id
	if worn_skin != null:
		skin_id = worn_skin.id
	var skin_colors := TournamentLibrary.capture_skin_colors(GameManager.player_profile, skin_id)
	var result := TournamentLibrary.save_career_golfer(
		GameManager.player_profile, skin_id, skin_colors)
	var ok := bool(result.get("ok", false))
	var message := golfer_message(result)
	EventBus.notify(message, "success" if ok else "warning")
	return _with_message(result, message, ok)


static func course_message(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return "Saved '%s' (%d holes, Par %d) for Tournament Mode!" % [
			str(result.get("name", "Course")),
			int(result.get("hole_count", 0)),
			int(result.get("par", 0)),
		]
	return str(result.get("error", COURSE_ERROR))


static func golfer_message(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return "Saved golfer '%s' for Tournament Mode!" % str(result.get("name", "Golfer"))
	return str(result.get("error", GOLFER_ERROR))


static func _with_message(result: Dictionary, message: String, ok: bool) -> Dictionary:
	var feedback := result.duplicate()
	feedback["ok"] = ok
	feedback["message"] = message
	return feedback
