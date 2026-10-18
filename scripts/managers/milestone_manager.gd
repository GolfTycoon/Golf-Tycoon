extends Node
class_name MilestoneManager
## MilestoneManager - tracks and checks the game's three goal tracks.
##
##  * Course Location Milestones complete per course location (keyed on the
##    world map's location id) and are unlocked again with every new save.
##  * World Milestones complete once per save for the whole company across
##    all its course locations.
##  * Achievements stay unlocked between saves. Their flags and the career
##    counters behind them are written through AchievementStore to the
##    player's settings file whenever one moves.
##
## The manager listens to the game's events and checks the end-of-day
## picture as well. Completing a milestone pays its money and reputation
## rewards once; loading a save restores progress without paying again.

signal milestone_completed(milestone_id: String, title: String, description: String, track: int)
signal achievement_unlocked(achievement_id: String, title: String, description: String)

## Progress key used when no course location is active (tests and harnesses
## that start a course without the world map).
const LEGACY_LOCATION_KEY := "_legacy"

## Save payload version: v2 is { locations, world }. Anything older is the
## flat `{ completed: [...] }` list, migrated through
## MilestoneSystem.migrate_legacy_id().
const PROGRESS_VERSION := 2

## Stateless definitions (MilestoneSystem.Milestone).
var location_milestones: Array = []
var world_milestones: Array = []
var achievements: Array = []

## Per-save: location id -> { completed: { id: day }, rounds, hio, eagles }.
var location_progress: Dictionary = {}
## Per-save company state: { completed: { id: day }, hio, locations_bought,
## tournament_wins, holes_built }.
var world_progress: Dictionary = {}

## Persistent achievement state: { unlocked: { id: day }, counters: { key: value } }.
var achievement_state: Dictionary = {}

func _ready() -> void:
	_init_state()
	_connect_signals()

## Build the definition lists, the per-save progress and the career shelf.
## Separate from _ready so tests can build a quiet manager that listens to
## no game events and completes only the goals they mean to.
func _init_state() -> void:
	location_milestones = MilestoneSystem.get_location_milestones()
	world_milestones = MilestoneSystem.get_world_milestones()
	achievements = MilestoneSystem.get_achievements()
	location_progress = {}
	world_progress = _fresh_world_progress()
	achievement_state = AchievementStore.load_state()

func _connect_signals() -> void:
	EventBus.end_of_day.connect(_on_end_of_day)
	EventBus.hole_created.connect(_on_hole_created)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.golfer_completed_round.connect(_on_golfer_finished_round)
	EventBus.golfer_spawned.connect(_on_golfer_spawned)
	EventBus.record_broken.connect(_on_record_broken)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.course_rating_changed.connect(_on_course_rating_changed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.tournament_completed.connect(_on_tournament_completed)
	WorldMap.location_purchased.connect(_on_location_purchased)
	WorldMap.company_started.connect(reset_for_new_save)

func _exit_tree() -> void:
	for pair: Array in [
		[EventBus.end_of_day, _on_end_of_day],
		[EventBus.hole_created, _on_hole_created],
		[EventBus.building_placed, _on_building_placed],
		[EventBus.golfer_completed_round, _on_golfer_finished_round],
		[EventBus.golfer_spawned, _on_golfer_spawned],
		[EventBus.record_broken, _on_record_broken],
		[EventBus.reputation_changed, _on_reputation_changed],
		[EventBus.course_rating_changed, _on_course_rating_changed],
		[EventBus.money_changed, _on_money_changed],
		[EventBus.tournament_completed, _on_tournament_completed],
	]:
		var signal_: Signal = pair[0]
		var callable_: Callable = pair[1]
		if signal_.is_connected(callable_):
			signal_.disconnect(callable_)
	if WorldMap.location_purchased.is_connected(_on_location_purchased):
		WorldMap.location_purchased.disconnect(_on_location_purchased)
	if WorldMap.company_started.is_connected(reset_for_new_save):
		WorldMap.company_started.disconnect(reset_for_new_save)

func _fresh_world_progress() -> Dictionary:
	return {
		"completed": {},
		"hio": 0,
		"locations_bought": 0,
		"tournament_wins": 0,
		"holes_built": 0,
	}

## A brand-new company (a brand-new save): every Course Location Milestone
## and World Milestone locks again. Achievements are deliberately untouched.
func reset_for_new_save() -> void:
	location_progress = {}
	world_progress = _fresh_world_progress()

## Re-read the career shelf. Called when the Achievements screen opens so a
## long-running session sees unlocks another window wrote.
func refresh_achievements() -> void:
	achievement_state = AchievementStore.load_state()

## ── Progress queries ─────────────────────────────────────────────────────

func _current_location_id() -> String:
	var id := WorldMap.active_location_id
	return id if not id.is_empty() else LEGACY_LOCATION_KEY

func _location_entry(location_id: String = "") -> Dictionary:
	var id := location_id if not location_id.is_empty() else _current_location_id()
	if not location_progress.has(id):
		location_progress[id] = {"completed": {}, "rounds": 0, "hio": 0, "eagles": 0}
	return location_progress[id]

## Completed ids -> day, for one course location (or the active one).
func get_location_completed(location_id: String = "") -> Dictionary:
	return _location_entry(location_id).get("completed", {})

func is_location_completed(milestone_id: String, location_id: String = "") -> bool:
	return get_location_completed(location_id).has(milestone_id)

func get_world_completed() -> Dictionary:
	return world_progress.get("completed", {})

func is_world_completed(milestone_id: String) -> bool:
	return get_world_completed().has(milestone_id)

func is_achievement_unlocked(achievement_id: String) -> bool:
	return achievement_state.get("unlocked", {}).has(achievement_id)

func get_achievement_day(achievement_id: String) -> int:
	return int(achievement_state.get("unlocked", {}).get(achievement_id, 0))

func get_counter(counter: String) -> int:
	return int(achievement_state.get("counters", {}).get(counter, 0))

## How far along a counter-driven achievement is, clamped to its goal.
func get_achievement_progress(a: MilestoneSystem.Milestone) -> int:
	if a.counter.is_empty():
		return 1 if is_achievement_unlocked(a.id) else 0
	return mini(get_counter(a.counter), a.goal)

func get_location_completion_count(location_id: String = "") -> int:
	return get_location_completed(location_id).size()

func get_location_total_count() -> int:
	return location_milestones.size()

func get_world_completion_count() -> int:
	return get_world_completed().size()

func get_world_total_count() -> int:
	return world_milestones.size()

func get_achievement_count() -> int:
	return achievement_state.get("unlocked", {}).size()

func get_achievement_total_count() -> int:
	return achievements.size()

## Read one of the per-location counters the screens summarise (rounds
## served, holes-in-one, eagles).
func get_location_stat(location_id: String, key: String) -> int:
	return int(_location_entry(location_id).get(key, 0))

## Every hole the company owns, across all its course locations.
func get_company_hole_count() -> int:
	return _company_hole_count()

## How many course locations the company owns right now.
func get_owned_location_count() -> int:
	return _owned_location_count()

# Kept for callers that ask for "the milestones" as one set: the two
# per-save tracks side by side.
func get_completion_count() -> int:
	return get_world_completion_count() + get_location_completion_count()

func get_total_count() -> int:
	return get_world_total_count() + get_location_total_count()

## ── Completing goals ─────────────────────────────────────────────────────

func _complete_milestone(m: MilestoneSystem.Milestone, location_id: String = "") -> void:
	if SaveManager._is_loading:
		return
	match m.track:
		MilestoneSystem.Track.LOCATION:
			var entry := _location_entry(location_id)
			if entry.completed.has(m.id):
				return
			entry.completed[m.id] = GameManager.current_day
		MilestoneSystem.Track.WORLD:
			if get_world_completed().has(m.id):
				return
			world_progress.completed[m.id] = GameManager.current_day
		_:
			return

	# Award rewards
	if m.reward_money > 0:
		GameManager.modify_money(m.reward_money)
		EventBus.log_transaction("Milestone: %s" % m.title, m.reward_money)
	if m.reward_reputation > 0.0:
		GameManager.modify_reputation(m.reward_reputation)

	# Notify
	var reward_text := ""
	if m.reward_money > 0:
		reward_text += "+$%d" % m.reward_money
	if m.reward_reputation > 0.0:
		if reward_text != "":
			reward_text += ", "
		reward_text += "+%.0f rep" % m.reward_reputation

	var msg := "Milestone: %s" % m.title
	if reward_text != "":
		msg += " (%s)" % reward_text
	EventBus.notify(msg, "success")
	milestone_completed.emit(m.id, m.title, m.description, m.track)

func _find_milestone(defs: Array, milestone_id: String) -> MilestoneSystem.Milestone:
	for m in defs:
		if m.id == milestone_id:
			return m
	return null

func _check_location(milestone_id: String, condition: bool) -> void:
	if not condition or SaveManager._is_loading:
		return
	var m := _find_milestone(location_milestones, milestone_id)
	if m:
		_complete_milestone(m)

func _check_world(milestone_id: String, condition: bool) -> void:
	if not condition or SaveManager._is_loading:
		return
	var m := _find_milestone(world_milestones, milestone_id)
	if m:
		_complete_milestone(m)

## Unlock an achievement for good. Progress is written through
## AchievementStore immediately, so the honour survives even if the player
## never saves this company.
func _unlock_achievement(achievement_id: String) -> void:
	var unlocked: Dictionary = achievement_state.get("unlocked", {})
	if unlocked.has(achievement_id):
		return
	var m := _find_milestone(achievements, achievement_id)
	if m == null:
		return
	unlocked[achievement_id] = GameManager.current_day
	achievement_state["unlocked"] = unlocked
	AchievementStore.save_state(achievement_state)

	var msg := "Achievement unlocked: %s" % m.title
	EventBus.notify(msg, "success")
	achievement_unlocked.emit(m.id, m.title, m.description)
	# The meta honour follows the last regular one.
	_check_hall_of_fame()

func _check_hall_of_fame() -> void:
	for a in achievements:
		if a.id == "ach_hall_of_fame":
			continue
		if not is_achievement_unlocked(a.id):
			return
	_unlock_achievement("ach_hall_of_fame")

## Move a career counter and unlock whatever it reaches. `mode` is "sum",
## "max" (the counter keeps the highest value seen) or "flag" (0/1).
func _bump_counter(counter: String, value: int, mode: String = "sum") -> void:
	if SaveManager._is_loading:
		return
	var counters: Dictionary = achievement_state.get("counters", {})
	var current := int(counters.get(counter, 0))
	var next := current
	match mode:
		"max":
			next = maxi(current, value)
		"flag":
			next = 1 if value != 0 else current
		_:
			next = current + value
	if next == current:
		return
	counters[counter] = next
	achievement_state["counters"] = counters
	# Counters are career state: keep them on disk as they move, so a crash
	# (or a second window) never loses ground toward an honour.
	AchievementStore.save_state(achievement_state)
	for a in achievements:
		if a.counter != counter:
			continue
		if next >= a.goal:
			_unlock_achievement(a.id)

# ── Signal handlers ───────────────────────────────────────────────────────

func _on_end_of_day(_day: int) -> void:
	# Location picture: eagles land on the course the day was played on.
	var entry := _location_entry()
	var daily_eagles := int(GameManager.daily_stats.eagles)
	if daily_eagles > 0:
		entry.eagles = int(entry.get("eagles", 0)) + daily_eagles
	_check_location("loc_first_eagle", int(entry.get("eagles", 0)) > 0)

	# Par 3 course at this location.
	if GameManager.current_course:
		var all_par3 := true
		var holes = GameManager.current_course.holes
		if holes.size() >= 3:
			for hole in holes:
				if hole.par != 3:
					all_par3 = false
					break
			_check_location("loc_par_3", all_par3)

	# World picture — measured against the real calendar.
	_check_world("world_survive_year", GameManager.current_day >= 365)
	_check_world("world_survive_five_years", GameManager.current_day >= 1825)

	# Yearly revenue milestones: today's revenue is accumulated at rollover,
	# so count YTD + today for the true picture.
	var yearly_revenue: int = GameManager.yearly_stats.get_total_revenue() \
		+ GameManager.daily_stats.get_total_revenue()
	_check_world("world_earn_10k", yearly_revenue >= 10000)
	_check_world("world_earn_50k", yearly_revenue >= 50000)

	# Profit milestone
	_check_world("world_first_profit", GameManager.daily_stats.get_profit() > 0)

	# Yearly golfer count
	_check_world("world_serve_50",
		GameManager.yearly_stats.golfers_served + GameManager.daily_stats.golfers_served >= 50)

	# Debt free with $100k
	_check_world("world_no_debt", GameManager.money >= 100000 and GameManager.loan_balance <= 0)

	# Career counters: a day lived and the day's takings, remembered forever.
	_bump_counter("days", GameManager.current_day, "max")
	_bump_counter("revenue", GameManager.daily_stats.get_total_revenue())
	_bump_counter("eagles", daily_eagles)
	AchievementStore.save_state(achievement_state)

func _on_hole_created(_hole_number: int, _par: int, _distance: int) -> void:
	if not GameManager.current_course:
		return
	var count: int = GameManager.current_course.holes.size()
	_check_location("loc_first_hole", count >= 1)
	_check_location("loc_three_holes", count >= 3)
	_check_location("loc_nine_holes", count >= 9)
	_check_location("loc_eighteen_holes", count >= 18)
	_check_world("world_holes_18", _company_hole_count() >= 18)
	_check_world("world_holes_36", _company_hole_count() >= 36)
	_bump_counter("holes_built", 1)

## Every hole the company owns: the live course plus every course left
## behind at another location.
func _company_hole_count() -> int:
	var total: int = GameManager.current_course.holes.size() if GameManager.current_course else 0
	for id in WorldMap.location_snapshots:
		if id == WorldMap.active_location_id:
			continue
		var snapshot = WorldMap.location_snapshots[id]
		if snapshot is Dictionary:
			total += (snapshot.get("holes", []) as Array).size()
	return total

func _on_building_placed(_type: String, _pos: Vector2i) -> void:
	if not GameManager.entity_layer:
		return
	var building_count: int = GameManager.entity_layer.get_building_count() \
		if GameManager.entity_layer.has_method("get_building_count") else 1
	_check_location("loc_first_building", building_count >= 1)
	_check_location("loc_five_buildings", building_count >= 5)

func _on_golfer_finished_round(_golfer_id: int, _total_strokes: int, _total_par: int) -> void:
	var entry := _location_entry()
	entry.rounds = int(entry.get("rounds", 0)) + 1
	_check_location("loc_first_round", true)
	_check_location("loc_serve_25", int(entry.rounds) >= 25)
	_bump_counter("rounds", 1)
	# A finished round puts the course's standing on the board: reputation
	# and star milestones only count from here on.
	_on_reputation_changed(GameManager.reputation, GameManager.reputation)
	_on_course_rating_changed(GameManager.course_rating)

func _on_golfer_spawned(_golfer_id: int, _golfer_name: String) -> void:
	# Check for pro visit - GolferTier.get_name_prefix(PRO) returns "Pro"
	if _golfer_name.begins_with("Pro "):
		_check_world("world_pro_visit", true)

func _on_record_broken(record_type: String, _golfer_name: String, _value: int, _hole_number: int) -> void:
	if record_type != "hole_in_one":
		return
	var entry := _location_entry()
	entry.hio = int(entry.get("hio", 0)) + 1
	world_progress["hio"] = int(world_progress.get("hio", 0)) + 1
	_check_location("loc_first_hio", true)
	_check_world("world_five_hio", int(world_progress.get("hio", 0)) >= 5)
	_bump_counter("hole_in_ones", 1)

func _on_reputation_changed(_old_rep: float, new_rep: float) -> void:
	# Starting reputation and construction are not an operating track record.
	if not _has_completed_round():
		return
	_check_world("world_rep_25", new_rep >= 25.0)
	_check_world("world_rep_50", new_rep >= 50.0)
	_check_world("world_rep_75", new_rep >= 75.0)
	_check_world("world_rep_100", new_rep >= 100.0)
	_bump_counter("reputation", int(new_rep), "max")

func _on_course_rating_changed(rating: Dictionary) -> void:
	if not _has_completed_round():
		return
	var stars: int = int(rating.get("stars", 0))
	_check_location("loc_four_star", stars >= 4)
	_check_location("loc_five_star", stars >= 5)
	if stars >= 5:
		_bump_counter("five_star", 1, "flag")

func _on_money_changed(_old: int, _new: int) -> void:
	_check_world("world_no_debt", GameManager.money >= 100000 and GameManager.loan_balance <= 0)

func _on_tournament_completed(_tier: int, results: Dictionary) -> void:
	if bool(results.get("winner_is_player", false)):
		world_progress["tournament_wins"] = int(world_progress.get("tournament_wins", 0)) + 1
		_bump_counter("tournament_wins", 1)

func _on_location_purchased(_location_id: String) -> void:
	world_progress["locations_bought"] = int(world_progress.get("locations_bought", 0)) + 1
	_check_world("world_own_2", _owned_location_count() >= 2)
	_check_world("world_own_3", _owned_location_count() >= 3)
	_check_world("world_own_5", _owned_location_count() >= 5)
	_bump_counter("locations_bought", 1)

func _owned_location_count() -> int:
	var count := 0
	for id in WorldMap.locations:
		if WorldMap.is_owned(id):
			count += 1
	return count

## Check if a pro golfer has been spawned (called from GolferManager)
func check_pro_visit(tier: int) -> void:
	if tier == GolferTier.Tier.PRO:
		_check_world("world_pro_visit", true)

## Check concurrent golfer count (called from GolferManager)
func check_full_house(current_count: int, max_count: int) -> void:
	if max_count > 0 and current_count >= max_count:
		_check_location("loc_full_house", true)

func _has_completed_round() -> bool:
	return GameManager.course_records.get("lowest_round") != null

## ── Save / load ──────────────────────────────────────────────────────────

## Per-save progress only. Achievements live in AchievementStore, never in a
## save file, so they stay unlocked between saves.
func serialize() -> Dictionary:
	return {
		"version": PROGRESS_VERSION,
		"locations": location_progress.duplicate(true),
		"world": world_progress.duplicate(true),
	}

## Restore per-save progress, replacing whatever the previous course had
## earned. Restored milestones never pay their rewards again.
func deserialize(data: Dictionary) -> void:
	location_progress = {}
	world_progress = _fresh_world_progress()
	if data.is_empty():
		return
	if data.has("completed") and not data.has("locations"):
		_migrate_legacy(data)
		return
	for location_id in data.get("locations", {}):
		var saved = data["locations"][location_id]
		if not (saved is Dictionary):
			continue
		var completed: Dictionary = {}
		for id in saved.get("completed", {}):
			completed[str(id)] = int(saved.completed[id])
		location_progress[str(location_id)] = {
			"completed": completed,
			"rounds": int(saved.get("rounds", 0)),
			"hio": int(saved.get("hio", 0)),
			"eagles": int(saved.get("eagles", 0)),
		}
	var saved_world = data.get("world", {})
	if saved_world is Dictionary:
		world_progress = _fresh_world_progress()
		for id in saved_world.get("completed", {}):
			world_progress.completed[str(id)] = int(saved_world.completed[id])
		for key in ["hio", "locations_bought", "tournament_wins", "holes_built"]:
			world_progress[key] = int(saved_world.get(key, 0))

## The pre-tracks save format: one flat completed list. Its ids land on the
## new tracks through MilestoneSystem's migration table.
func _migrate_legacy(data: Dictionary) -> void:
	var legacy_location := _current_location_id()
	for entry in data.get("completed", []):
		if not (entry is Dictionary):
			continue
		var mapped := MilestoneSystem.migrate_legacy_id(str(entry.get("id", "")))
		if mapped.is_empty():
			continue
		var day := int(entry.get("day", 0))
		if int(mapped["track"]) == MilestoneSystem.Track.LOCATION:
			_location_entry(legacy_location).completed[str(mapped["id"])] = day
		else:
			world_progress.completed[str(mapped["id"])] = day

## Career state is saved on every unlock and at every end of day; saving a
## game flushes it once more so a session that unlocks and quits to the menu
## is never behind.
func persist_achievements() -> void:
	AchievementStore.save_state(achievement_state)
