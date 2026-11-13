extends GolfTycoonMod
## Example: Hole-in-One Jackpot - a gameplay script mod.
##
## A complete tour of the script Mod API in one small system:
##
##   * it *listens* on the EventBus (golfer_finished_hole) like any core
##     system would,
##   * it *hooks* a game value (the golfer spawn rate) in load order,
##   * its numbers come from *config* - manifest defaults the player can
##     override in user://mods/config/example.jackpot.json,
##   * and it keeps state the save file carries for it
##     (_mod_save/_mod_restore), under its own mod id, so disabling the mod
##     can never corrupt the rest of the save.
##
## House rule it implements: a sponsor pays the course a bounty whenever a
## visitor aces a hole (publicity!), and the story brings a few extra
## golfers out for the next few days.

var _jackpots_paid: int = 0
var _last_jackpot_day: int = -1000


func _mod_load(mod_api: ModAPI) -> void:
	EventBus.golfer_finished_hole.connect(_on_golfer_finished_hole)
	mod_api.add_hook("golfer_spawn_rate", _buzz_hook)
	mod_api.log_info("Jackpot fund open: $%d per ace." % int(mod_api.get_config_value("payout", 500)))


func _mod_unload() -> void:
	if EventBus.golfer_finished_hole.is_connected(_on_golfer_finished_hole):
		EventBus.golfer_finished_hole.disconnect(_on_golfer_finished_hole)


func _mod_new_game() -> void:
	_jackpots_paid = 0
	_last_jackpot_day = -1000


func _on_golfer_finished_hole(_golfer_id: int, hole_number: int, strokes: int, _par: int) -> void:
	if strokes != 1:
		return
	var payout: int = int(api.get_config_value("payout", 500))
	_jackpots_paid += 1
	_last_jackpot_day = GameManager.current_day
	GameManager.modify_money(payout)
	EventBus.log_transaction("Hole-in-One Jackpot (hole %d)" % hole_number, payout)
	if bool(api.get_config_value("announce", true)):
		api.notify("Hole-in-one on hole %d! The jackpot fund pays the course $%d." % [hole_number, payout], "success")


## While the last ace is still neighbourhood news, a few extra golfers come
## out to try their luck. Hooks receive the running value and return the
## new one - leave it untouched when the story has gone cold.
func _buzz_hook(value: float, context: Dictionary) -> float:
	var day: int = int(context.get("day", GameManager.current_day))
	var buzz_days: int = int(api.get_config_value("buzz_days", 7))
	if day - _last_jackpot_day <= buzz_days and _jackpots_paid > 0:
		return value * float(api.get_config_value("buzz_multiplier", 1.05))
	return value


func _mod_save() -> Dictionary:
	return {"jackpots_paid": _jackpots_paid, "last_jackpot_day": _last_jackpot_day}


func _mod_restore(data: Dictionary) -> void:
	_jackpots_paid = int(data.get("jackpots_paid", 0))
	_last_jackpot_day = int(data.get("last_jackpot_day", -1000))
