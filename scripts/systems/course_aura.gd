extends Node
class_name CourseAura
## CourseAura - Where on the course golfers have spoken up, and how they felt.
##
## Every comment a golfer makes is announced on `EventBus.golfer_thought` with
## the golfer's id, the trigger that produced it and its sentiment. This tracker
## is the listener that also remembers *where* it happened: the course is cut
## into square cells (CELL_SIZE tiles a side) and each cell keeps a tally of the
## happy and the unhappy comments heard in it, plus the triggers behind them.
##
## The tally is a rolling window, not a lifetime total. Only the newest
## MAX_SAMPLES comments are kept, so the aura follows how the course is playing
## lately: a corner that used to be a walk in the park cools off once the weeds
## come in, and a stretch the staff now work warms back up.
##
## One screen reads it: the Course Map's **Course Aura** mode paints the cells
## green, amber or red and lists the hotspots with the complaints behind them. A
## cell is only called a hotspot once HOTSPOT_MIN_SAMPLES comments have landed in
## it, so one grumpy golfer cannot repaint the map.

## Tiles a side of one aura cell. Four keeps a cell big enough to read on the
## Course Map (a 128x128 course is a 32x32 aura) and small enough to point at a
## green, a tee or one stretch of fairway without blending the whole course.
const CELL_SIZE: int = 4
## Comments kept. The window is what makes the aura current: the oldest sample
## falls out as a new one arrives.
const MAX_SAMPLES: int = 600
## Comments a cell needs before it can be reported as a hotspot.
const HOTSPOT_MIN_SAMPLES: int = 3

## Short, plain names for the feedback triggers, for the hotspot list. Triggers
## missing from the table fall back to TRIGGER_FALLBACK - the list stays useful
## when FeedbackTriggers grows a trigger this table has not met yet.
const TRIGGER_LABELS: Dictionary = {
	"HOLE_IN_ONE": "Hole in one",
	"EAGLE": "Eagles",
	"BIRDIE": "Birdies",
	"BOGEY_PLUS": "Dropped shots",
	"OVERPRICED": "Green fees",
	"GOOD_VALUE": "Value for money",
	"SLOW_PACE": "Slow play",
	"NICE_COURSE": "Liked the course",
	"HAZARD_WATER": "Water trouble",
	"HAZARD_BUNKER": "Bunkers",
	"GREAT_SHOT": "Great shots",
	"BAD_LIE": "Bad lies",
	"TOO_FEW_HOLES": "Too few holes",
	"SHANK": "Shanks",
	"TIRED": "Long walks",
	"HUNGRY": "No food",
	"NEEDS_RESTROOM": "No restroom",
	"THIRSTY": "No drinks",
	"REFRESHED": "Drinks service",
	"CHEERED_UP": "Friendly staff",
	"PACED_UP": "Marshalling",
	"COURSE_TIDY": "Tidy course",
	"COURSE_MESSY": "Weeds",
}
const TRIGGER_FALLBACK: String = "Comment"

## Newest-last list of {
##   cell: Vector2i      - which aura cell the comment landed in
##   tile: Vector2i      - the exact tile the golfer stood on
##   sentiment: String   - "positive", "negative" or "neutral"
##   trigger: int        - FeedbackTriggers.TriggerType
##   hole: int           - hole being played (1-based, 0 when unknown)
##   day: int            - game day the comment was made
## }
var samples: Array = []

func _ready() -> void:
	if not EventBus.golfer_thought.is_connected(_on_golfer_thought):
		EventBus.golfer_thought.connect(_on_golfer_thought)
	if not EventBus.new_game_started.is_connected(_on_new_game):
		EventBus.new_game_started.connect(_on_new_game)

func _exit_tree() -> void:
	if EventBus.golfer_thought.is_connected(_on_golfer_thought):
		EventBus.golfer_thought.disconnect(_on_golfer_thought)
	if EventBus.new_game_started.is_connected(_on_new_game):
		EventBus.new_game_started.disconnect(_on_new_game)

# =============================================================================
# Recording
# =============================================================================

## A golfer just said something. Find where they are standing and keep it.
func _on_golfer_thought(golfer_id: int, trigger_type: int, sentiment: String) -> void:
	var golfer: Golfer = null
	var manager = GameManager.golfer_manager
	if manager:
		golfer = manager.get_golfer(golfer_id)
	if golfer == null:
		return
	var grid: TerrainGrid = GameManager.terrain_grid
	if grid == null:
		return
	var tile: Vector2i = grid.screen_to_grid(golfer.global_position)
	if not grid.is_valid_position(tile):
		return
	record_at(tile, trigger_type, sentiment, golfer.current_hole + 1)

## Keep one comment made at `tile`. Split out from the signal handler so the
## rules (cell size, window, tallies) can be exercised without a golfer.
func record_at(tile: Vector2i, trigger_type: int, sentiment: String,
		hole: int = 0, day: int = GameManager.current_day) -> void:
	samples.append({
		"cell": cell_of(tile),
		"tile": tile,
		"sentiment": sentiment if sentiment in ["positive", "negative", "neutral"] else "neutral",
		"trigger": trigger_type,
		"hole": hole,
		"day": day,
	})
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()

func _on_new_game() -> void:
	clear()

func clear() -> void:
	samples.clear()

func sample_count() -> int:
	return samples.size()

# =============================================================================
# Cells
# =============================================================================

## Which aura cell a tile belongs to. floori, not int: int() truncates towards
## zero, which would fold the tiles just west/north of the origin into cell 0.
static func cell_of(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / float(CELL_SIZE)), floori(float(tile.y) / float(CELL_SIZE)))

## Centre of a cell, in tiles.
static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5

## Every cell that has heard a comment: cell -> {positive, negative, neutral,
## total, score}. `score` is the balance of feeling in [-1, 1]: +1 is an
## all-compliments cell, -1 an all-complaints one.
func cell_counts() -> Dictionary:
	var cells: Dictionary = {}
	for sample in samples:
		var cell: Vector2i = sample.cell
		if not cells.has(cell):
			cells[cell] = {"positive": 0, "negative": 0, "neutral": 0, "total": 0, "score": 0.0}
		cells[cell][sample.sentiment] += 1
		cells[cell]["total"] += 1
	for cell in cells:
		var counts: Dictionary = cells[cell]
		var judgement: int = int(counts["positive"]) + int(counts["negative"])
		counts["score"] = 0.0 if judgement == 0 \
			else float(int(counts["positive"]) - int(counts["negative"])) / float(judgement)
	return cells

## The balance of feeling in one cell (-1..1), or 0.0 when nothing has been said
## there yet.
func cell_score(cell: Vector2i) -> float:
	return float(cell_counts().get(cell, {}).get("score", 0.0))

## The cells worth sending the player to, most of one feeling first. `sentiment`
## is "positive" or "negative"; the result carries the cell, its counts, its
## score and the trigger heard most often in it.
func hotspots(sentiment: String, limit: int = 3) -> Array:
	var sought: String = sentiment if sentiment in ["positive", "negative"] else "negative"
	var cells := cell_counts()
	var picked: Array = []
	for cell in cells:
		var counts: Dictionary = cells[cell]
		if int(counts["total"]) < HOTSPOT_MIN_SAMPLES:
			continue
		var weight: int = int(counts[sought])
		if weight <= 0:
			continue
		picked.append({
			"cell": cell,
			"counts": counts,
			"score": float(counts["score"]),
			"weight": weight,
		})
	picked.sort_custom(func(a, b):
		if int(a["weight"]) != int(b["weight"]):
			return int(a["weight"]) > int(b["weight"])
		# A tie goes to the cell that leans harder the way we are looking.
		return float(a["score"]) < float(b["score"]) if sought == "negative" \
			else float(a["score"]) > float(b["score"]))
	var result: Array = []
	for entry in picked.slice(0, maxi(0, limit)):
		var cell: Vector2i = entry["cell"]
		var triggers := top_triggers(cell, sought, 2)
		entry["triggers"] = triggers
		entry["where"] = describe(cell)
		entry["hole"] = dominant_hole(cell)
		result.append(entry)
	return result

## The triggers heard most often in a cell, most frequent first.
## Returns an array of {"trigger": int, "label": String, "count": int}.
func top_triggers(cell: Vector2i, sentiment: String, limit: int = 2) -> Array:
	var tally: Dictionary = {}
	for sample in samples:
		if sample.cell != cell:
			continue
		if sentiment in ["positive", "negative"] and sample.sentiment != sentiment:
			continue
		tally[sample.trigger] = int(tally.get(sample.trigger, 0)) + 1
	var ranked: Array = []
	for trigger in tally:
		ranked.append({"trigger": int(trigger), "label": trigger_label(int(trigger)), "count": int(tally[trigger])})
	ranked.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	return ranked.slice(0, maxi(0, limit))

## The triggers heard most often on one hole, most frequent first. Same shape as
## top_triggers(): {"trigger", "label", "count"} entries.
func top_triggers_for_hole(hole: int, sentiment: String, limit: int = 2) -> Array:
	var tally: Dictionary = {}
	for sample in samples:
		if int(sample.hole) != hole:
			continue
		if sentiment in ["positive", "negative"] and sample.sentiment != sentiment:
			continue
		tally[sample.trigger] = int(tally.get(sample.trigger, 0)) + 1
	var ranked: Array = []
	for trigger in tally:
		ranked.append({"trigger": int(trigger), "label": trigger_label(int(trigger)), "count": int(tally[trigger])})
	ranked.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	return ranked.slice(0, maxi(0, limit))

## The hole most of a cell's comments were made on, or 0 when none of them
## belong to a hole.
func dominant_hole(cell: Vector2i) -> int:
	var tally: Dictionary = {}
	for sample in samples:
		if sample.cell == cell and int(sample.hole) > 0:
			tally[int(sample.hole)] = int(tally.get(int(sample.hole), 0)) + 1
	var best: int = 0
	var best_count: int = 0
	for hole in tally:
		if int(tally[hole]) > best_count:
			best = int(hole)
			best_count = int(tally[hole])
	return best

## What a cell is on, in plain words: the nearest hole landmark, e.g.
## "Hole 7 green". Falls back to the tiles it covers when the course has no
## holes yet.
func describe(cell: Vector2i) -> String:
	var centre := cell_center(cell)
	var course = GameManager.current_course
	var best := ""
	var best_distance: float = INF
	if course:
		for hole in course.holes:
			for landmark in [["tee", hole.tee_position], ["green", hole.green_position]]:
				var distance := centre.distance_to(Vector2(landmark[1]))
				if distance < best_distance:
					best_distance = distance
					best = "Hole %d %s" % [hole.hole_number, landmark[0]]
	if best.is_empty():
		return "Tiles %d-%d, %d-%d" % [
			cell.x * CELL_SIZE, cell.x * CELL_SIZE + CELL_SIZE - 1,
			cell.y * CELL_SIZE, cell.y * CELL_SIZE + CELL_SIZE - 1]
	return best

## How many comments were made on each hole: hole -> {positive, negative,
## neutral, total, score}. Holes nobody commented on are absent.
func hole_counts() -> Dictionary:
	var holes: Dictionary = {}
	for sample in samples:
		var hole: int = int(sample.hole)
		if hole <= 0:
			continue
		if not holes.has(hole):
			holes[hole] = {"positive": 0, "negative": 0, "neutral": 0, "total": 0, "score": 0.0}
		holes[hole][sample.sentiment] += 1
		holes[hole]["total"] += 1
	for hole in holes:
		var counts: Dictionary = holes[hole]
		var judgement: int = int(counts["positive"]) + int(counts["negative"])
		counts["score"] = 0.0 if judgement == 0 \
			else float(int(counts["positive"]) - int(counts["negative"])) / float(judgement)
	return holes

## Totals for the whole course, for the aura panel's headline.
func totals() -> Dictionary:
	var out := {"positive": 0, "negative": 0, "neutral": 0, "total": 0, "score": 0.0}
	for sample in samples:
		out[sample.sentiment] += 1
		out["total"] += 1
	var judgement: int = int(out["positive"]) + int(out["negative"])
	out["score"] = 0.0 if judgement == 0 \
		else float(int(out["positive"]) - int(out["negative"])) / float(judgement)
	return out

## Plain name of a feedback trigger, for the hotspot list.
static func trigger_label(trigger_type: int) -> String:
	var key := trigger_name(trigger_type)
	return TRIGGER_LABELS.get(key, TRIGGER_FALLBACK)

## The FeedbackTriggers enum key for a trigger value ("SLOW_PACE"), or "" when
## nothing carries that value.
static func trigger_name(trigger_type: int) -> String:
	for key in FeedbackTriggers.TriggerType:
		if int(FeedbackTriggers.TriggerType[key]) == trigger_type:
			return key
	return ""

# =============================================================================
# Saving
# =============================================================================

func serialize() -> Dictionary:
	var kept: Array = []
	for sample in samples:
		kept.append({
			"cell_x": sample.cell.x, "cell_y": sample.cell.y,
			"tile_x": sample.tile.x, "tile_y": sample.tile.y,
			"sentiment": sample.sentiment,
			"trigger": int(sample.trigger),
			"hole": int(sample.hole),
			"day": int(sample.day),
		})
	return {"samples": kept}

## Put the aura back. Data from a save written before this system existed is
## simply absent, and the aura starts empty.
func deserialize(data: Dictionary) -> void:
	samples.clear()
	for entry in data.get("samples", []):
		samples.append({
			"cell": Vector2i(int(entry.get("cell_x", 0)), int(entry.get("cell_y", 0))),
			"tile": Vector2i(int(entry.get("tile_x", 0)), int(entry.get("tile_y", 0))),
			"sentiment": str(entry.get("sentiment", "neutral")),
			"trigger": int(entry.get("trigger", -1)),
			"hole": int(entry.get("hole", 0)),
			"day": int(entry.get("day", 0)),
		})
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()
