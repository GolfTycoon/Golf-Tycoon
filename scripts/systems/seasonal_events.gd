extends RefCounted
class_name SeasonalEvents
## SeasonalEvents - Special events tied to the seasonal calendar.
##
## Each season has themed events that affect gameplay, revenue or golfer
## demand. Events trigger on specific days within each season.
##
## The calendar itself is a *registry*: which events exist is decided by the
## mods that are loaded. The bundled Seasons mod (`res://mods/golf_tycoon.seasons/`)
## registers the eight shipped events from its data file, and any other mod
## can add its own the same way (a `seasonal_events` content declaration, or
## SeasonalEvents.register_event() from a script mod via the Mod API). With
## no mod supplying events, the calendar is simply empty - the query methods
## below stay safe to call either way.

class SeasonEvent:
	var id: String
	var name: String
	var description: String
	var season: int  # SeasonSystem.Season enum
	var day_in_season: int  # Which day of the season (1-90, seasons are calendar quarters)
	var revenue_modifier: float = 1.0
	var spawn_modifier: float = 1.0
	var reputation_bonus: float = 0.0
	var duration_days: int = 1  # How many days the event lasts
	## The mod that registered the event ("core" would be the game itself,
	## which registers none). Shown in the Mods screen's conflict report.
	var source: String = ""

	func _init(p_id: String, p_name: String, p_desc: String, p_season: int,
			p_day: int, p_revenue: float = 1.0, p_spawn: float = 1.0,
			p_rep: float = 0.0, p_duration: int = 1) -> void:
		id = p_id
		name = p_name
		description = p_desc
		season = p_season
		day_in_season = p_day
		revenue_modifier = p_revenue
		spawn_modifier = p_spawn
		reputation_bonus = p_rep
		duration_days = p_duration

	func to_dictionary() -> Dictionary:
		return {
			"id": id, "name": name, "description": description, "season": season,
			"day_in_season": day_in_season, "revenue_modifier": revenue_modifier,
			"spawn_modifier": spawn_modifier, "reputation_bonus": reputation_bonus,
			"duration_days": duration_days, "source": source,
		}


static var _registered: Array = []

const SEASON_NAMES: Dictionary = {
	"spring": 0, "summer": 1, "fall": 2, "autumn": 2, "winter": 3,
}


## Register one event. An event whose id is already taken replaces the old
## one, which is how a mod later in the load order retunes an earlier mod's
## event.
static func register_event(event: SeasonEvent) -> void:
	for i in range(_registered.size()):
		if (_registered[i] as SeasonEvent).id == event.id:
			_registered[i] = event
			return
	_registered.append(event)


## Register an event described by mod data. `season` may be a name
## ("spring") or a SeasonSystem.Season number. Returns the event, or null
## when the data does not describe one.
static func register_event_from_data(data: Dictionary, source: String = "") -> SeasonEvent:
	var event_id: String = str(data.get("id", "")).strip_edges()
	var event_name: String = str(data.get("name", "")).strip_edges()
	if event_id.is_empty() or event_name.is_empty():
		return null
	var season_value: Variant = data.get("season", 1)
	var season: int = int(SEASON_NAMES.get(season_value, 1)) if season_value is String else int(season_value)
	var event := SeasonEvent.new(event_id, event_name, str(data.get("description", "")),
		clampi(season, 0, 3), maxi(1, int(data.get("day_in_season", 1))),
		float(data.get("revenue_modifier", 1.0)), float(data.get("spawn_modifier", 1.0)),
		float(data.get("reputation_bonus", 0.0)), maxi(1, int(data.get("duration_days", 1))))
	event.source = source
	register_event(event)
	return event


## Forget every registered event. The content registry calls this before it
## re-applies the loaded mods in load order.
static func clear_registered_events() -> void:
	_registered.clear()


static func registered_count() -> int:
	return _registered.size()


static func get_all_events() -> Array:
	return _registered.duplicate()


## Get the currently active event (if any) for the given game day
static func get_active_event(day: int) -> SeasonEvent:
	var season = SeasonSystem.get_season(day)
	var day_in_season = SeasonSystem.get_day_in_season(day)

	for event in get_all_events():
		if event.season == season:
			if day_in_season >= event.day_in_season and day_in_season < event.day_in_season + event.duration_days:
				return event
	return null

## Get upcoming events within the next N days
static func get_upcoming_events(current_day: int, look_ahead: int = 14) -> Array:
	var upcoming: Array = []
	for d in range(current_day + 1, current_day + look_ahead + 1):
		var event = get_active_event(d)
		if event and not _array_has_event(upcoming, event.id):
			upcoming.append({"event": event, "day": d, "days_until": d - current_day})
	return upcoming

static func _array_has_event(arr: Array, event_id: String) -> bool:
	for entry in arr:
		if entry.event.id == event_id:
			return true
	return false

## Get events for a specific season (for calendar display)
static func get_season_events(season: int) -> Array:
	var events: Array = []
	for event in get_all_events():
		if event.season == season:
			events.append(event)
	return events
