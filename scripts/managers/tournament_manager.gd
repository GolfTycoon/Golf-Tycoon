extends Node
class_name TournamentManager
## TournamentManager - Runs tournaments the moment they are hosted, and pays them out.
##
## Clicking "Host Tournament" starts the event straight away: the entry fee is
## taken, the field is generated and the first pair tees off on the current day.
## There is no scheduling lead time any more.
##
## Round 1 is played by live golfers on the course; every competitor beyond the
## ones that fit the fairways (and every round after the first) is settled by
## TournamentSimulator, shot by shot, headlessly.
##
## The field is built so the course carries two competitors on each open hole at
## the start of play, and the owner is always one of them: hosting an event puts
## *you* in the field, in the first pairing, with your own golfer on the tee.
##
## Multi-round events play the following number of rounds:
## - LOCAL: 1 round
## - REGIONAL: 2 rounds
## - NATIONAL: 4 rounds
## - CHAMPIONSHIP: 4 rounds
## The live first round ends when every on-course competitor has finished. Any
## additional rounds are then completed by the tournament simulator.

signal tournament_scheduled(tier: int, start_day: int)
signal tournament_started(tier: int)
signal tournament_completed(tier: int, results: Dictionary)

var current_tournament_tier: int = -1  # -1 = no tournament
var current_tournament_state: int = TournamentSystem.TournamentState.NONE
var tournament_start_day: int = 0
var tournament_results: Dictionary = {}

# Cooldown between tournaments (days on the fast calendar)
const TOURNAMENT_COOLDOWN: int = 45

var last_tournament_end_day: int = -100

# Multi-round & format state
var current_round: int = 0           # 1-based round number (0 = not started)
var total_rounds: int = 1            # Total rounds for this event
var current_format_type: int = TournamentLibrary.FormatType.STROKE_PLAY
var _is_standalone_event: bool = false
var _standalone_difficulty: int = TournamentLibrary.Difficulty.NORMAL
var _standalone_field_size: int = 12
var _standalone_cut_rule: String = "none"
var _standalone_playoff_enabled: bool = true
var _format_points: Dictionary = {}  # sim_id -> int (Stableford / Mod. Stableford / Skins)
var _playoff_winner_id: int = -999999
var _playoff_holes_played: int = 0

# Tournament field (persistent across rounds)
var _sim_field: Array = []           # Array of TournamentSimulator.SimulationGolfer
var _live_count: int = 0             # Field entries that play round 1 on the course
var _round_scores: Dictionary = {}   # golfer_id → Array of RoundResult
var _cumulative_scores: Dictionary = {} # golfer_id → {total_strokes, total_par}
var _cut_golfer_ids: Array = []      # IDs of golfers who made the cut (empty = no cut yet)
var _eliminated_ids: Array = []      # IDs of golfers who missed the cut
var _tournament_moments: Array = []  # TournamentMoment entries across all rounds

# Live play tracking (round 1 only)
var _tournament_golfer_ids: Array[int] = []
var _tournament_scores: Dictionary = {}  # golfer_id -> {name, total_strokes, total_par, holes_completed, is_finished, ability}
var _groups_spawned: int = 0
var _total_groups: int = 0
var _spawn_timer: float = 0.0
## The opening pairing waits for the event's first tick instead of spawning
## inside the host click: the press charges the entry fee and nothing else,
## while golfer arrivals - and the signals they carry, milestones among them -
## land on the frame after, where a day or a bonus cannot corrupt a click.
var _first_group_pending: bool = false
var _live_round_active: bool = false  # True when live golfers are playing round 1

## Field id reserved for the owner, who always plays their own tournament.
## Simulator golfers are numbered from -1 downwards, so 0 is always free.
const PLAYER_SIM_ID: int = 0

## Competitors that tee off together (and the size of a live group).
const GROUP_SIZE: int = TournamentSystem.GROUP_SIZE

# Stagger interval between pairings. Each pair goes to its own hole, so this is
# only the beat the field walks out to its tee on — the whole course is filled a
# few seconds after the click, not minutes.
const GROUP_SPAWN_INTERVAL: float = 0.5

# External references (set via setup())
var _golfer_manager: GolferManager = null
var _leaderboard: TournamentLeaderboard = null
var _pre_tournament_speed: int = -1
## Supplies the aiming HUD and shot input for the owner's live golfer, so they
## play their own shots during a tournament (set via set_aim_controller()). The
## manager still owns the round — spawning, scoring and results stay here.
var _aim_controller: PlayerRoundManager = null

# Rounds per tier
const ROUNDS_PER_TIER: Dictionary = {
	TournamentSystem.TournamentTier.LOCAL: 1,
	TournamentSystem.TournamentTier.REGIONAL: 2,
	TournamentSystem.TournamentTier.NATIONAL: 4,
	TournamentSystem.TournamentTier.CHAMPIONSHIP: 4,
}

# Cut line rules: {round_after_which_cut_applies: cut_rule}
# "top_50pct" = top 50% advance, "top_40_ties" = top 40 + ties advance
const CUT_RULES: Dictionary = {
	TournamentSystem.TournamentTier.NATIONAL: {"after_round": 2, "rule": "top_50pct"},
	TournamentSystem.TournamentTier.CHAMPIONSHIP: {"after_round": 2, "rule": "top_40_ties"},
}

func setup(golfer_manager: GolferManager, leaderboard: TournamentLeaderboard) -> void:
	_golfer_manager = golfer_manager
	_leaderboard = leaderboard

## Hand the owner's tournament shots to the PlayerRoundManager for aiming.
## Called once from main after both managers exist.
func set_aim_controller(controller: PlayerRoundManager) -> void:
	_aim_controller = controller

## Ask the aiming controller to stop, tolerating a missing/late controller.
func _release_aim() -> void:
	if is_instance_valid(_aim_controller):
		_aim_controller.end_tournament_aim()

func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.golfer_finished_hole.connect(_on_golfer_finished_hole)
	EventBus.golfer_finished_round.connect(_on_golfer_finished_round)

func _process(delta: float) -> void:
	# Safety fallback: a tournament restored from a save as SCHEDULED begins as
	# soon as its start day arrives (and the course is running).
	if current_tournament_state == TournamentSystem.TournamentState.SCHEDULED:
		if GameManager.current_day >= tournament_start_day and _golfer_manager != null \
				and GameManager.current_mode == GameManager.GameMode.SIMULATING:
			_start_tournament()
		return

	if current_tournament_state != TournamentSystem.TournamentState.IN_PROGRESS:
		return

	# Stagger group spawning for live round: the opening pairing tees off on
	# the first tick of the event, the rest one interval apart.
	if _live_round_active and _groups_spawned < _total_groups:
		if _first_group_pending:
			_first_group_pending = false
			_spawn_next_group()
		else:
			_spawn_timer += delta  # delta already scaled by Engine.time_scale
			if _spawn_timer >= GROUP_SPAWN_INTERVAL:
				_spawn_timer -= GROUP_SPAWN_INTERVAL
				_spawn_next_group()

func _on_day_changed(_new_day: int) -> void:
	# Keep compatibility with a saved tournament booking, but running events are
	# never ended by a calendar deadline. They finish when the field finishes.
	if current_tournament_state == TournamentSystem.TournamentState.SCHEDULED:
		_start_tournament()

func _on_golfer_finished_hole(golfer_id: int, hole: int, strokes: int, par: int) -> void:
	if not _live_round_active or golfer_id not in _tournament_golfer_ids:
		return

	if _tournament_scores.has(golfer_id):
		var entry = _tournament_scores[golfer_id]
		entry.total_strokes += strokes
		entry.total_par += par
		entry.holes_completed += 1
		var hole_index := _hole_index_for_number(hole)
		entry.current_hole = hole_index
		entry.holes_played[hole_index] = true
		entry.hole_strokes[hole_index] = strokes
		entry.hole_pars[hole_index] = par

	_recompute_format_points()
	if _leaderboard:
		_leaderboard.update_score(golfer_id, hole, strokes, par)
		_leaderboard.set_format_points(_format_points)

func _on_golfer_finished_round(golfer_id: int, total_strokes: int, _total_par: int) -> void:
	if not _live_round_active or golfer_id not in _tournament_golfer_ids:
		return

	if _tournament_scores.has(golfer_id):
		var entry = _tournament_scores[golfer_id]
		entry.is_finished = true
		entry.total_strokes = total_strokes

	if _leaderboard:
		_leaderboard.mark_finished(golfer_id, total_strokes)

	# Check if all live golfers finished
	_check_live_round_completion()

# ============================================================================
# HOSTING
# ============================================================================

func can_schedule_tournament(tier: int) -> Dictionary:
	var result = {"can_schedule": true, "reason": ""}

	if current_tournament_state != TournamentSystem.TournamentState.NONE:
		result.can_schedule = false
		result.reason = "Tournament already running"
		return result

	var days_since_last = GameManager.current_day - last_tournament_end_day
	if days_since_last < TOURNAMENT_COOLDOWN:
		result.can_schedule = false
		result.reason = "Must wait %d more days" % (TOURNAMENT_COOLDOWN - days_since_last)
		return result

	GameManager.update_course_rating()

	var qualification = TournamentSystem.check_qualification(
		tier, GameManager.current_course, GameManager.course_rating
	)
	if not qualification.qualified:
		result.can_schedule = false
		result.reason = qualification.missing[0] if not qualification.missing.is_empty() else "Course not qualified"
		return result

	var tier_data = TournamentSystem.get_tier_data(tier)
	if GameManager.money < tier_data.entry_cost:
		result.can_schedule = false
		result.reason = "Need $%d to host (have $%d)" % [tier_data.entry_cost, GameManager.money]
		return result

	# Live play needs somewhere to put the field: every competitor that plays on
	# the course needs an open hole to tee off on.
	if GameManager.get_open_hole_count() <= 0:
		result.can_schedule = false
		result.reason = "Open at least one hole before hosting a tournament"
		return result

	return result

## Host a tournament: it starts straight away. The entry fee is paid, the field
## is generated and round 1 begins on the current day with live golfers on the
## course — the player among them. Returns false (and charges nothing) when the
## course or the treasury does not allow it.
func host_tournament(tier: int) -> bool:
	var check = can_schedule_tournament(tier)
	if not check.can_schedule:
		# The shelf shows the same line as a tooltip, but hosting can be refused
		# from anywhere, and a click that does nothing needs a reason attached.
		EventBus.notify(str(check.reason), "warning")
		return false

	var tier_data = TournamentSystem.get_tier_data(tier)

	GameManager.modify_money(-tier_data.entry_cost)
	GameManager.daily_stats.tournament_entry_fee += tier_data.entry_cost
	EventBus.log_transaction("Tournament entry fee (%s)" % tier_data.name, -tier_data.entry_cost)

	_is_standalone_event = false
	current_format_type = TournamentLibrary.FormatType.STROKE_PLAY
	current_tournament_tier = tier
	total_rounds = ROUNDS_PER_TIER.get(tier, 1)
	current_round = 0
	tournament_start_day = GameManager.current_day

	# The event begins on the spot: no scheduled state, no lead-time wait.
	tournament_scheduled.emit(tier, tournament_start_day)
	EventBus.tournament_scheduled.emit(tier, tournament_start_day)
	_start_tournament()

	return true

## Launch a standalone Tournament Mode event directly without Career entry fees,
## course rating gates, or cooldowns. Accepts an options Dictionary (difficulty,
## format_type, rounds, field_size, cut_rule, playoff) or a legacy tier int.
func start_standalone_tournament(config: Variant) -> bool:
	if current_tournament_state != TournamentSystem.TournamentState.NONE:
		cancel_tournament()
	if GameManager.get_open_hole_count() <= 0:
		EventBus.notify("Course has no open holes for tournament play.", "warning")
		return false

	_is_standalone_event = true
	if config is Dictionary:
		var opts: Dictionary = config
		_standalone_difficulty = int(opts.get("difficulty", TournamentLibrary.Difficulty.NORMAL))
		var diff_info := TournamentLibrary.get_difficulty(_standalone_difficulty)
		current_tournament_tier = int(opts.get("tier", diff_info.get("tier", TournamentSystem.TournamentTier.REGIONAL)))
		current_format_type = int(opts.get("format_type", TournamentLibrary.FormatType.STROKE_PLAY))
		total_rounds = clampi(int(opts.get("rounds", 2)), 1, 4)
		var open_holes := GameManager.get_open_hole_count()
		if bool(opts.get("field_size_auto", false)) or int(opts.get("field_size", 12)) <= TournamentLibrary.FIELD_SIZE_AUTO:
			_standalone_field_size = TournamentLibrary.auto_field_size_for_holes(open_holes)
		else:
			_standalone_field_size = clampi(int(opts.get("field_size", 12)), 2, maxi(72, open_holes * 2))
		_standalone_cut_rule = str(opts.get("cut_rule", "none"))
		if total_rounds <= 1:
			_standalone_cut_rule = "none"
		_standalone_playoff_enabled = bool(opts.get("playoff", true))
	else:
		current_tournament_tier = int(config)
		_standalone_difficulty = clampi(current_tournament_tier, 0, 3)
		current_format_type = TournamentLibrary.FormatType.STROKE_PLAY
		total_rounds = ROUNDS_PER_TIER.get(current_tournament_tier, 1)
		_standalone_field_size = TournamentSystem.get_field_size(
			current_tournament_tier, GameManager.get_open_hole_count()
		)
		_standalone_cut_rule = str(CUT_RULES.get(current_tournament_tier, {}).get("rule", "none"))
		_standalone_playoff_enabled = true

	current_round = 0
	tournament_start_day = GameManager.current_day
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	tournament_scheduled.emit(current_tournament_tier, tournament_start_day)
	EventBus.tournament_scheduled.emit(current_tournament_tier, tournament_start_day)
	_start_tournament()
	GameManager.set_speed(GameManager.current_speed)
	return true

## Abort an active tournament cleanly (used when restarting or returning to
## Tournament Setup from standalone Tournament Mode).
func cancel_tournament() -> void:
	_release_aim()
	if _golfer_manager:
		_golfer_manager.remove_tournament_golfers()
	if _leaderboard:
		_leaderboard.hide()
	if _pre_tournament_speed >= 0:
		GameManager.set_speed(_pre_tournament_speed as GameManager.GameSpeed)
		_pre_tournament_speed = -1
	_is_standalone_event = false
	current_format_type = TournamentLibrary.FormatType.STROKE_PLAY
	current_tournament_tier = -1
	current_tournament_state = TournamentSystem.TournamentState.NONE
	current_round = 0
	total_rounds = 1
	_live_round_active = false
	_groups_spawned = 0
	_first_group_pending = false
	_tournament_golfer_ids.clear()
	_tournament_scores.clear()
	_sim_field.clear()
	_round_scores.clear()
	_cumulative_scores.clear()
	_format_points.clear()
	_playoff_winner_id = -999999
	_playoff_holes_played = 0
	_cut_golfer_ids.clear()
	_eliminated_ids.clear()
	_tournament_moments.clear()

# ============================================================================
# TOURNAMENT START
# ============================================================================

func _start_tournament() -> void:
	current_tournament_state = TournamentSystem.TournamentState.IN_PROGRESS

	# The day must be running for live golfers to play, so hosting from the
	# design board opens the course first.
	if GameManager.current_mode != GameManager.GameMode.SIMULATING:
		GameManager.set_mode(GameManager.GameMode.SIMULATING)

	_pre_tournament_speed = GameManager.current_speed
	if GameManager.current_speed < GameManager.GameSpeed.FAST:
		GameManager.current_speed = GameManager.GameSpeed.FAST

	if _golfer_manager:
		_golfer_manager.clear_all_golfers()

	# Reset all tournament tracking
	_tournament_golfer_ids.clear()
	_tournament_scores.clear()
	_round_scores.clear()
	_cumulative_scores.clear()
	_format_points.clear()
	_playoff_winner_id = -999999
	_playoff_holes_played = 0
	_cut_golfer_ids.clear()
	_eliminated_ids.clear()
	_tournament_moments.clear()
	_groups_spawned = 0
	_spawn_timer = 0.0
	_first_group_pending = false
	_live_round_active = false

	var tier_data = TournamentSystem.get_tier_data(current_tournament_tier)
	var open_holes: int = GameManager.get_open_hole_count()

	var desired_field_size := _standalone_field_size if _is_standalone_event else TournamentSystem.get_field_size(current_tournament_tier, open_holes)
	_sim_field = _build_field(desired_field_size)

	# How many of them get a body on the course: two per open hole.
	_live_count = mini(TournamentSystem.get_live_field_size(open_holes), _sim_field.size())

	# Initialize cumulative scores
	for sg in _sim_field:
		_cumulative_scores[sg.id] = {"total_strokes": 0, "total_par": 0}
		_round_scores[sg.id] = []
		_format_points[sg.id] = 0

	# Show the whole field on the live board from the first tee shot, so the
	# owner can find themselves on it. Golfers who get a body on the course are
	# bound to their node below.
	if _leaderboard:
		var event_title := str(tier_data.name)
		if _is_standalone_event:
			event_title = TournamentLibrary.get_format_name(current_format_type)
		var round_text = "Round 1/%d" % total_rounds if total_rounds > 1 else ""
		_leaderboard.set_format_type(current_format_type)
		_leaderboard.show_for_tournament(event_title, _sim_field.size(), total_rounds, round_text)
		for sg in _sim_field:
			_leaderboard.register_golfer(sg.id, sg.name, sg.id, sg.id == PLAYER_SIM_ID)

	tournament_started.emit(current_tournament_tier)
	EventBus.tournament_started.emit(current_tournament_tier)

	# Play round 1 — live golfers on the course right now
	_play_round(1)

## Build the field: in standalone Tournament Mode, competitors come from the
## selected Difficulty Level's named golfer list (with higher Golf Skills at
## each higher difficulty). In Career Mode, generates the tier's field.
func _build_field(participant_count: int) -> Array:
	var player_sg := _make_player_sim_golfer()
	if _is_standalone_event:
		var tier_for_diff := GolferTier.Tier.CASUAL
		match _standalone_difficulty:
			TournamentLibrary.Difficulty.EASY:
				tier_for_diff = GolferTier.Tier.BEGINNER
			TournamentLibrary.Difficulty.NORMAL:
				tier_for_diff = GolferTier.Tier.CASUAL
			TournamentLibrary.Difficulty.HARD:
				tier_for_diff = GolferTier.Tier.SERIOUS
			TournamentLibrary.Difficulty.CHAMPIONSHIP:
				tier_for_diff = GolferTier.Tier.PRO
		var roster := TournamentLibrary.build_opponent_roster(
			_standalone_difficulty,
			maxi(0, participant_count - 1),
			player_sg.name
		)
		var standalone_field: Array = [player_sg]
		for idx in range(roster.size()):
			var sim_id := -(idx + 1)
			standalone_field.append(
				TournamentSimulator.SimulationGolfer.from_golfer_card(sim_id, roster[idx], tier_for_diff)
			)
		return standalone_field

	var field: Array = TournamentSimulator.generate_field(
		current_tournament_tier, maxi(0, participant_count - 1)
	)
	field.push_front(player_sg)
	return field

## The owner's entry in the field, built from the persistent player profile so
## the skills they allocated carry into tournament play.
func _make_player_sim_golfer() -> TournamentSimulator.SimulationGolfer:
	var profile: PlayerGolferProfile = GameManager.player_profile
	if _is_standalone_event and profile != null:
		var card := {
			"name": profile.golfer_name if not profile.golfer_name.is_empty() else "You",
			"skin_id": GameManager.player_skin_id,
			"skin_colors": GameManager.tournament_player_skin_colors.duplicate(true),
			"profession": profile.profession,
			"age": profile.age,
			"gender": profile.gender,
			"marital_status": profile.marital_status,
			"traits": profile.traits.duplicate(),
			"golfer_skills": profile.golfer_skills.duplicate(),
			"points": profile.points.duplicate(),
		}
		return TournamentSimulator.SimulationGolfer.from_golfer_card(PLAYER_SIM_ID, card, GolferTier.Tier.SERIOUS)

	var sg := TournamentSimulator.SimulationGolfer.new()
	sg.id = PLAYER_SIM_ID
	sg.name = profile.golfer_name if profile and profile.golfer_name != "" else "You"
	sg.tier = GolferTier.Tier.SERIOUS
	if profile:
		# Same ability mapping the owner's own rounds use.
		sg.driving_ability = profile.driving_ability()
		sg.accuracy_ability = profile.accuracy_ability()
		sg.putting_ability = profile.putting_ability()
		sg.recovery_ability = profile.recovery_ability()
	sg.miss_tendency = 0.0
	sg.aggression = 0.5
	sg.patience = 0.5
	return sg

## Is this field entry the owner?
func is_player_entry(sim_id: int) -> bool:
	return sim_id == PLAYER_SIM_ID

## Synchronize the owner's sim golfer abilities and active tournament score entry
## with GameManager.player_profile.
func sync_player_skills() -> void:
	var profile: PlayerGolferProfile = GameManager.player_profile
	if not profile:
		return
	var sg = _find_sim_golfer(PLAYER_SIM_ID)
	if sg:
		sg.driving_ability = profile.driving_ability()
		sg.accuracy_ability = profile.accuracy_ability()
		sg.putting_ability = profile.putting_ability()
		sg.recovery_ability = profile.recovery_ability()
		var avg_ability = (sg.driving_ability + sg.accuracy_ability + sg.putting_ability + sg.recovery_ability) / 4.0
		for golfer_id in _tournament_scores:
			if _tournament_scores[golfer_id].get("sim_id") == PLAYER_SIM_ID:
				_tournament_scores[golfer_id]["ability"] = avg_ability

# ============================================================================
# ROUND EXECUTION
# ============================================================================

## Play a specific round. Round 1 uses live golfers; rounds 2+ are simulated.
func _play_round(round_number: int) -> void:
	current_round = round_number

	var round_label = "Round %d/%d" % [round_number, total_rounds] if total_rounds > 1 else ""

	if _leaderboard:
		_leaderboard.update_round_info(round_number, total_rounds, round_label)

	# The "simulation started" notice is for the headless rounds: round 1 is live
	# golfers on the course, and the effects hung off that signal belong to them.
	if round_number > 1:
		EventBus.tournament_simulation_started.emit(current_tournament_tier, round_number)

	if round_number == 1:
		# Round 1: spawn live golfers
		_start_live_round()
	else:
		# Rounds 2+: simulate headlessly
		_simulate_round_headless(round_number)

## Start live round with on-course golfer nodes (round 1 only).
##
## Competitors play in pairs — two to a group, and no more pairs than the course
## has open holes, so the event starts with two competitors on every hole. The
## rest of the field plays out headlessly against the same scorecard.
func _start_live_round() -> void:
	_live_round_active = true
	_groups_spawned = 0
	_spawn_timer = 0.0
	_tournament_golfer_ids.clear()
	_tournament_scores.clear()

	# Determine how many groups to spawn for live play
	var live_field = _get_live_field()
	_total_groups = ceili(float(live_field.size()) / float(GROUP_SIZE))

	# The opening pairing tees off on the event's first tick (see
	# _first_group_pending), so hosting stays a light click.
	_first_group_pending = true

## Course index of the hole whose published number is `hole_number`. Live scoring
## reports hole numbers; the fill logic works in indices, and the two are not the
## same thing on a course whose holes were renumbered.
func _hole_index_for_number(hole_number: int) -> int:
	var course = GameManager.current_course
	if course:
		for i in range(course.holes.size()):
			if int(course.holes[i].hole_number) == hole_number:
				return i
	return clampi(hole_number - 1, 0, maxi((course.holes.size() if course else 1) - 1, 0))

## The first open hole this competitor has not carded, used as the start of the
## headless fill so their card ends up covering the circuit once each way.
func _first_open_hole_not_played(played: Dictionary) -> int:
	for i in _open_hole_indices():
		if not played.has(i):
			return i
	return 0

## Indices of the course's open holes, in play order.
func _open_hole_indices() -> Array:
	var indices: Array = []
	var course = GameManager.current_course
	if not course:
		return indices
	for i in range(course.holes.size()):
		if course.holes[i].is_open:
			indices.append(i)
	return indices

## The slice of the field that plays round 1 live on the course.
func _get_live_field() -> Array:
	var active_field = _get_active_field()
	if _live_count <= 0 or _live_count >= active_field.size():
		return active_field
	return active_field.slice(0, _live_count)

## First field index of a live group (groups are pairs, played consecutively
## through the field).
func _group_start_index(group_index: int) -> int:
	return group_index * GROUP_SIZE

func _spawn_next_group() -> void:
	if not _golfer_manager:
		return
	if _groups_spawned >= _total_groups:
		return

	var active_field = _get_live_field()
	var start_idx = _group_start_index(_groups_spawned)
	var end_idx = mini(start_idx + GROUP_SIZE, active_field.size())
	var group_size = end_idx - start_idx
	if group_size <= 0:
		_groups_spawned = _total_groups
		return

	var group_id = _golfer_manager.next_group_id
	_golfer_manager.next_group_id += 1

	# One pairing per open hole: the field spreads across the course as it starts
	# instead of queueing behind the first tee.
	var tee_holes = _open_hole_indices()
	var tee_hole: int = tee_holes[_groups_spawned % tee_holes.size()] if not tee_holes.is_empty() else 0

	for i in range(start_idx, end_idx):
		var sg: TournamentSimulator.SimulationGolfer = active_field[i]
		var tier = sg.tier
		var golfer = _golfer_manager.spawn_tournament_golfer(tier, group_id)
		if golfer:
			_golfer_manager.seat_golfer_at_hole(golfer, tee_hole)
			if not sg.golfer_card.is_empty():
				golfer.apply_golfer_card(sg.golfer_card)
			else:
				golfer.attributes.apply_abilities(sg.driving_ability, sg.accuracy_ability, sg.putting_ability, sg.recovery_ability)
				golfer.golfer_name = sg.name
			golfer.miss_tendency = sg.miss_tendency
			golfer.aggression = sg.aggression
			golfer.patience = sg.patience
			if sg.id == PLAYER_SIM_ID and GameManager.player_profile:
				golfer.apply_player_appearance(GameManager.player_profile)
				if is_instance_valid(_aim_controller):
					golfer.player_profile = GameManager.player_profile
					_aim_controller.begin_tournament_aim(golfer)
			_tournament_golfer_ids.append(golfer.golfer_id)
			var avg_ability = (sg.driving_ability + sg.accuracy_ability + sg.putting_ability + sg.recovery_ability) / 4.0
			_tournament_scores[golfer.golfer_id] = {
				"name": sg.name,
				"sim_id": sg.id,
				"total_strokes": 0,
				"total_par": 0,
				"holes_completed": 0,
				"is_finished": false,
				"ability": avg_ability,
				"current_hole": tee_hole,
				"holes_played": {},
				"hole_strokes": {},
				"hole_pars": {},
			}
			if _leaderboard:
				# Point the owner's/pre-pro's existing leaderboard row at the body
				# that is now playing, so live per-hole scores land on it.
				_leaderboard.bind_live_golfer(sg.id, golfer.golfer_id)

	_groups_spawned += 1
	print("Tournament group %d/%d spawned (%d golfers)%s" % [
		_groups_spawned, _total_groups, group_size,
		" — you are in the first pairing" if start_idx == 0 else ""
	])

## Simulate a round headlessly for all active golfers using real shot physics
func _simulate_round_headless(round_number: int) -> void:
	var active_field = _get_active_field()
	var round_moments: Array = []

	print("Simulating round %d for %d golfers..." % [round_number, active_field.size()])

	for sg in active_field:
		round_moments.append_array(_record_simulated_round(sg, round_number))

	_finish_round(round_moments, false)

## Play one round for one competitor with TournamentSimulator and file the result
## into the scorebook, the cumulative standings and the leaderboard. Returns the
## moments that round produced.
func _record_simulated_round(sg: TournamentSimulator.SimulationGolfer, round_number: int) -> Array:
	var result: TournamentSimulator.RoundResult = TournamentSimulator.simulate_round(sg, round_number)

	# Store round result
	if not _round_scores.has(sg.id):
		_round_scores[sg.id] = []
	_round_scores[sg.id].append(result)

	# Update cumulative scores
	if not _cumulative_scores.has(sg.id):
		_cumulative_scores[sg.id] = {"total_strokes": 0, "total_par": 0}
	_cumulative_scores[sg.id].total_strokes += result.total_strokes
	_cumulative_scores[sg.id].total_par += result.total_par
	_tournament_moments.append_array(result.moments)
	_recompute_format_points()

	# Update leaderboard
	if _leaderboard:
		if not _leaderboard.has_golfer(sg.id):
			_leaderboard.register_golfer(sg.id, sg.name, sg.id, sg.id == PLAYER_SIM_ID)
		_leaderboard.set_round_score(sg.id, round_number,
			result.total_strokes, result.total_par,
			_cumulative_scores[sg.id].total_strokes,
			_cumulative_scores[sg.id].total_par)
		_leaderboard.set_format_points(_format_points)

	return result.moments

## Close the live round after the active field has holed out, clearing the course
## and handing the completed cards to `_finish_round`.
func _finish_live_round() -> void:
	if not _live_round_active:
		return

	# The owner is done taking their own shots; drop the aiming HUD before the
	# live golfers (their golfer included) are cleared off the course.
	_release_aim()

	var round_moments: Array = []

	# Competitors whose tee time never came around — plus everyone the course
	# could not seat at two per hole — are settled headlessly against the same
	# scorecard.
	var live_field = _get_live_field()
	var full_field = _get_active_field()
	while _groups_spawned < _total_groups:
		var start_idx = _group_start_index(_groups_spawned)
		var end_idx = mini(start_idx + GROUP_SIZE, live_field.size())
		for i in range(start_idx, end_idx):
			round_moments.append_array(_record_simulated_round(live_field[i], current_round))
		_groups_spawned += 1
	for i in range(live_field.size(), full_field.size()):
		round_moments.append_array(_record_simulated_round(full_field[i], current_round))

	# Anyone still on the course when the round closes has their card completed
	# headlessly, for exactly the holes they did not reach. Filling a fixed number
	# of holes is what keeps the field comparable: everyone ends the round over the
	# same circuit, so "to par" means the same thing on every line of the board.
	var circuit_holes := _open_hole_indices().size()
	var simulated_results: Array = []
	for gid in _tournament_golfer_ids:
		if not _tournament_scores.has(gid):
			continue
		var entry = _tournament_scores[gid]
		if entry.is_finished:
			continue

		var sim_id = entry.get("sim_id", gid)
		var sg = _find_sim_golfer(sim_id)
		if not sg:
			# No entry in the simulated field (a save restored mid-round, say):
			# model them from the scorecard that does exist.
			sg = TournamentSimulator.SimulationGolfer.new()
			sg.id = sim_id
			sg.name = entry.name
			var entry_ability: float = entry.get("ability", entry.get("skill", 0.7))
			sg.driving_ability = entry_ability
			sg.accuracy_ability = entry_ability
			sg.putting_ability = entry_ability
			sg.recovery_ability = entry_ability

		var open_indices := _open_hole_indices()
		var played_map: Dictionary = entry.holes_played as Dictionary
		var next_slot := 0
		var cur_hole_idx := _first_open_hole_not_played(played_map)
		for s in open_indices.size():
			if int(open_indices[s]) >= cur_hole_idx:
				next_slot = s
				break
			next_slot = s + 1
		var unplayed_order: Array = []
		for offset in open_indices.size():
			var hi := int(open_indices[(next_slot + offset) % open_indices.size()])
			if not played_map.has(hi):
				unplayed_order.append(hi)

		var holes_left: int = maxi(circuit_holes - played_map.size(), 0)
		var result = TournamentSimulator.simulate_remaining(sg,
			cur_hole_idx,
			int(entry.total_strokes), int(entry.total_par), holes_left,
			played_map)

		for fill_i in range(mini(result.hole_scores.size(), unplayed_order.size())):
			var fill_hi := int(unplayed_order[fill_i])
			entry.hole_strokes[fill_hi] = int(result.hole_scores[fill_i])
			entry.hole_pars[fill_hi] = int(result.hole_pars[fill_i])
			entry.holes_played[fill_hi] = true

		entry.total_strokes = result.total_strokes
		entry.total_par = result.total_par
		entry.holes_completed = circuit_holes
		entry.is_finished = true

		simulated_results.append({
			"golfer_id": gid,
			"total_strokes": result.total_strokes,
			"total_par": result.total_par,
			"holes_completed": entry.holes_completed,
		})

		round_moments.append_array(result.moments)
		_tournament_moments.append_array(result.moments)

	# Update leaderboard
	if _leaderboard and not simulated_results.is_empty():
		_leaderboard.set_simulated_results(simulated_results)

	# Remove live golfers from course
	if _golfer_manager:
		_golfer_manager.remove_tournament_golfers()

	# Record this round's results into round_scores and cumulative_scores
	_record_live_round_results()

	_live_round_active = false

	_finish_round(round_moments, true)

## One round is over: announce its moments and standings, apply the cut, then
## either tee off the next round straight away or settle the tournament.
func _finish_round(round_moments: Array, was_live: bool) -> void:
	_emit_moments(round_moments)

	var standings = _get_standings()
	EventBus.tournament_round_completed.emit(current_tournament_tier, current_round, standings)
	if not was_live:
		EventBus.tournament_simulation_completed.emit(current_tournament_tier, current_round)

	print("Round %d complete. Leader: %s at %s" % [
		current_round,
		standings[0].name if not standings.is_empty() else "N/A",
		_format_score(standings[0]) if not standings.is_empty() else "N/A"
	])

	# Apply the cut line once the round it follows has been played
	if _is_standalone_event:
		var cut_after := maxi(1, int(float(total_rounds) * 0.5))
		if total_rounds >= 2 and _standalone_cut_rule != "none" and not _standalone_cut_rule.is_empty():
			if current_round == cut_after and _cut_golfer_ids.is_empty():
				_apply_cut_line(_standalone_cut_rule)
	elif CUT_RULES.has(current_tournament_tier):
		var cut_info = CUT_RULES[current_tournament_tier]
		if current_round == cut_info.after_round and _cut_golfer_ids.is_empty():
			_apply_cut_line(cut_info.rule)

	if current_round >= total_rounds:
		_complete_tournament()
		return

	if _leaderboard:
		_leaderboard.update_round_info(current_round, total_rounds,
			"Round %d/%d Complete" % [current_round, total_rounds])

	# The next round follows on straight away — a tournament plays through, it
	# does not sit in the diary waiting for a date.
	_play_round(current_round + 1)

func _check_live_round_completion() -> void:
	if _groups_spawned < _total_groups:
		return
	for gid in _tournament_golfer_ids:
		if _tournament_scores.has(gid) and not _tournament_scores[gid].is_finished:
			return
	_finish_live_round()

## Record live round results into the persistent round_scores/cumulative_scores
func _record_live_round_results() -> void:
	var open_indices := _open_hole_indices()
	for gid in _tournament_golfer_ids:
		if not _tournament_scores.has(gid):
			continue
		var entry = _tournament_scores[gid]
		var sim_id = entry.get("sim_id", gid)

		# Create a RoundResult from live play data (preserving per-hole scores in open-hole order)
		var rr = TournamentSimulator.RoundResult.new()
		rr.golfer_id = sim_id
		rr.golfer_name = entry.name
		rr.round_number = current_round
		rr.total_strokes = entry.total_strokes
		rr.total_par = entry.total_par
		var hs_map: Dictionary = entry.get("hole_strokes", {})
		var hp_map: Dictionary = entry.get("hole_pars", {})
		for hi in open_indices:
			if hs_map.has(hi):
				rr.hole_scores.append(int(hs_map[hi]))
				rr.hole_pars.append(int(hp_map.get(hi, 4)))

		if not _round_scores.has(sim_id):
			_round_scores[sim_id] = []
		_round_scores[sim_id].append(rr)

		# Update cumulative
		if _cumulative_scores.has(sim_id):
			_cumulative_scores[sim_id].total_strokes += entry.total_strokes
			_cumulative_scores[sim_id].total_par += entry.total_par
		else:
			_cumulative_scores[sim_id] = {
				"total_strokes": entry.total_strokes,
				"total_par": entry.total_par,
			}

		# Update leaderboard with cumulative scores
		if _leaderboard:
			_leaderboard.set_round_score(sim_id, current_round,
				entry.total_strokes, entry.total_par,
				_cumulative_scores[sim_id].total_strokes,
				_cumulative_scores[sim_id].total_par)

	_recompute_format_points()
	if _leaderboard:
		_leaderboard.set_format_points(_format_points)

# ============================================================================
# CUT LINE
# ============================================================================

func _apply_cut_line(rule: String) -> void:
	var standings = _get_standings()
	var cut_count: int = 0

	if rule == "top_50pct":
		cut_count = ceili(standings.size() / 2.0)
	elif rule == "top_10_ties":
		cut_count = 10
	elif rule == "top_40_ties":
		cut_count = 40

	if cut_count <= 0 or cut_count >= standings.size():
		return

	var target_entry: Dictionary = standings[mini(cut_count - 1, standings.size() - 1)]
	var use_points := TournamentLibrary.higher_points_is_better(current_format_type)
	var cut_score := int(target_entry.get("score_to_par", 0))
	var cut_points := int(target_entry.get("format_points", 0))

	_cut_golfer_ids.clear()
	_eliminated_ids.clear()

	for entry in standings:
		var advances := false
		if use_points:
			advances = int(entry.get("format_points", 0)) >= cut_points
		else:
			advances = int(entry.get("score_to_par", 0)) <= cut_score
		if advances:
			_cut_golfer_ids.append(entry.id)
		else:
			_eliminated_ids.append(entry.id)

	# Notify
	EventBus.tournament_cut_applied.emit(current_tournament_tier, _cut_golfer_ids, _eliminated_ids)

	if _leaderboard:
		_leaderboard.apply_cut_line(_cut_golfer_ids, _eliminated_ids)

	var cut_score_text := TournamentLibrary.format_score_for_format(
		current_format_type, cut_score, cut_points, true
	)
	EventBus.notify("Cut line at %s — %d golfers advance, %d eliminated" % [
		cut_score_text, _cut_golfer_ids.size(), _eliminated_ids.size()
	], "info")

	print("Cut applied: %d advance at %s, %d eliminated" % [
		_cut_golfer_ids.size(), cut_score_text, _eliminated_ids.size()
	])

# ============================================================================
# TOURNAMENT COMPLETION
# ============================================================================

func _complete_tournament() -> void:
	var tier_data = TournamentSystem.get_tier_data(current_tournament_tier)

	# Belt-and-braces: no aiming HUD should outlive the event, even if the live
	# round was settled by a path that skipped _finish_live_round().
	_release_aim()

	_recompute_format_points()
	var standings = _get_standings()
	if _is_standalone_event and _standalone_playoff_enabled and standings.size() >= 2:
		_run_sudden_death_playoff(standings)
		standings = _get_standings()

	var winner_name = standings[0].name if not standings.is_empty() else "Unknown"
	var winning_score = standings[0].total_strokes if not standings.is_empty() else 0
	var winning_points := int(standings[0].get("format_points", 0)) if not standings.is_empty() else 0
	var winner_is_player: bool = not standings.is_empty() and standings[0].id == PLAYER_SIM_ID
	var course_par = TournamentSystem._get_course_par(GameManager.current_course)

	# Build all_entries array for results popup
	var all_entries: Array = []
	for s in standings:
		all_entries.append({
			"name": s.name,
			"is_player": s.id == PLAYER_SIM_ID,
			"total_strokes": s.total_strokes,
			"total_par": s.total_par,
			"score_to_par": s.score_to_par,
			"format_points": int(s.get("format_points", 0)),
			"won_playoff": s.id == _playoff_winner_id,
			"missed_cut": s.id in _eliminated_ids,
			"round_scores": _get_round_score_diffs(s.id),
			"round_points": _get_round_format_points(s.id),
		})

	# Calculate drama multiplier for spectator revenue
	var drama_multiplier = _calculate_drama_multiplier()

	var completed_format := current_format_type
	var completed_playoff_holes := _playoff_holes_played

	tournament_results = {
		"winner_name": winner_name,
		"winner_is_player": winner_is_player,
		"winning_score": winning_score,
		"winning_points": winning_points,
		"format_type": completed_format,
		"format_name": TournamentLibrary.get_format_name(completed_format),
		"cut_rule": _standalone_cut_rule if _is_standalone_event else str(CUT_RULES.get(current_tournament_tier, {}).get("rule", "none")),
		"playoff_enabled": _standalone_playoff_enabled if _is_standalone_event else false,
		"playoff_holes": completed_playoff_holes,
		"par": course_par,
		"scores": standings.map(func(s): return s.total_strokes),
		"participant_count": _sim_field.size(),
		"prize_pool": tier_data.prize_pool,
		"all_entries": all_entries,
		"rounds_played": current_round,
		"total_rounds": total_rounds,
		"moments": _tournament_moments.duplicate(),
		"cut_golfers": _cut_golfer_ids.size(),
		"eliminated_golfers": _eliminated_ids.size(),
	}

	# Prize pool payout & Career economics apply only to hosted Career events
	var prize_cost = tier_data.prize_pool
	var spectator_rev = int(tier_data.get("spectator_revenue", 0) * drama_multiplier)
	var sponsor_rev = tier_data.get("sponsorship_revenue", 0)
	var total_revenue = spectator_rev + sponsor_rev
	var prestige = SeasonSystem.get_tournament_prestige(GameManager.current_day, GameManager.current_theme)
	var adjusted_rep = int(float(tier_data.reputation_reward) * prestige)

	if not GameManager.is_tournament_mode:
		if prize_cost > 0:
			GameManager.modify_money(-prize_cost)
			EventBus.log_transaction("Tournament prize pool payout", -prize_cost)
		if total_revenue > 0:
			GameManager.modify_money(total_revenue)
			GameManager.daily_stats.tournament_revenue += total_revenue
			EventBus.log_transaction("Tournament revenue (spectators + sponsors)", total_revenue)
		GameManager.modify_reputation(adjusted_rep)

	tournament_results["spectator_revenue"] = spectator_rev
	tournament_results["sponsorship_revenue"] = sponsor_rev
	tournament_results["total_revenue"] = total_revenue
	tournament_results["drama_multiplier"] = drama_multiplier
	tournament_results["prestige_multiplier"] = prestige

	if _leaderboard:
		_leaderboard.set_format_points(_format_points, _playoff_winner_id)
		_leaderboard.show_final_results()

	last_tournament_end_day = GameManager.current_day
	var completed_tier = current_tournament_tier

	if _pre_tournament_speed >= 0:
		GameManager.current_speed = _pre_tournament_speed as GameManager.GameSpeed
		_pre_tournament_speed = -1

	# The event is over: nobody stays on the course because of it.
	if _golfer_manager:
		_golfer_manager.remove_tournament_golfers()

	# Reset state
	_is_standalone_event = false
	current_format_type = TournamentLibrary.FormatType.STROKE_PLAY
	current_tournament_tier = -1
	current_tournament_state = TournamentSystem.TournamentState.NONE
	current_round = 0
	total_rounds = 1
	_tournament_golfer_ids.clear()
	_tournament_scores.clear()
	_sim_field.clear()
	_round_scores.clear()
	_cumulative_scores.clear()
	_format_points.clear()
	_playoff_winner_id = -999999
	_playoff_holes_played = 0
	_cut_golfer_ids.clear()
	_eliminated_ids.clear()
	_tournament_moments.clear()
	_live_count = 0
	_total_groups = 0
	_groups_spawned = 0
	_spawn_timer = 0.0
	_first_group_pending = false
	_live_round_active = false

	var score_diff = standings[0].score_to_par if not standings.is_empty() else 0
	var score_text := TournamentLibrary.format_score_for_format(
		completed_format, score_diff, winning_points, true
	)
	if completed_playoff_holes > 0:
		score_text += " (Playoff)"

	tournament_completed.emit(completed_tier, tournament_results)
	EventBus.tournament_completed.emit(completed_tier, tournament_results)
	EventBus.notify("Tournament complete! Winner: %s (%s)" % [winner_name, score_text], "success")

## Called when the player chooses Play It Out during a live tournament.
func simulate_remaining_and_complete() -> void:
	if current_tournament_state == TournamentSystem.TournamentState.SCHEDULED:
		_start_tournament()
		return
	if current_tournament_state != TournamentSystem.TournamentState.IN_PROGRESS:
		return

	# End the live round and chain through remaining rounds, so one call settles
	# the whole event.
	if _live_round_active:
		_finish_live_round()

	# Safety net: a round still pending for any other reason plays out now.
	var guard := 0
	while current_tournament_state == TournamentSystem.TournamentState.IN_PROGRESS \
			and current_round < total_rounds and guard < 8:
		guard += 1
		_play_round(current_round + 1)

	if current_tournament_state == TournamentSystem.TournamentState.IN_PROGRESS:
		_complete_tournament()

# ============================================================================
# STANDINGS & HELPERS
# ============================================================================

## Get active field (golfers who haven't been cut)
func _get_active_field() -> Array:
	if _cut_golfer_ids.is_empty():
		return _sim_field  # No cut yet, everyone plays
	return _sim_field.filter(func(sg): return sg.id in _cut_golfer_ids)

## Recompute cumulative format points (Stableford / Modified Stableford / Skins)
## across completed rounds plus any live Round 1 holes currently in progress.
func _recompute_format_points() -> void:
	_format_points.clear()
	for sg in _sim_field:
		_format_points[sg.id] = 0
	if current_format_type == TournamentLibrary.FormatType.STROKE_PLAY:
		return

	if current_format_type in [
		TournamentLibrary.FormatType.STABLEFORD,
		TournamentLibrary.FormatType.MODIFIED_STABLEFORD
	]:
		for sg in _sim_field:
			var pts := 0
			if _round_scores.has(sg.id):
				for rr in _round_scores[sg.id]:
					for hi in range(mini(rr.hole_scores.size(), rr.hole_pars.size())):
						pts += TournamentLibrary.hole_points_for_format(
							current_format_type, int(rr.hole_scores[hi]), int(rr.hole_pars[hi])
						)
			if _live_round_active and (_round_scores.get(sg.id, []) as Array).is_empty():
				for entry in _tournament_scores.values():
					if int(entry.get("sim_id", -999999)) == sg.id:
						var hs: Dictionary = entry.get("hole_strokes", {})
						var hp: Dictionary = entry.get("hole_pars", {})
						for h_key in hs:
							pts += TournamentLibrary.hole_points_for_format(
								current_format_type, int(hs[h_key]), int(hp.get(h_key, 4))
							)
						break
			_format_points[sg.id] = pts
		return

	if current_format_type == TournamentLibrary.FormatType.SKINS:
		var carryover := 0
		var max_r := current_round
		for r in range(1, max_r + 1):
			var hole_cards: Dictionary = {}  # sim_id -> Array[int] (strokes in open-hole order)
			var hole_count := 0
			for sg in _sim_field:
				var rrs: Array = _round_scores.get(sg.id, [])
				for rr in rrs:
					if rr.round_number == r and not rr.hole_scores.is_empty():
						hole_cards[sg.id] = rr.hole_scores
						hole_count = maxi(hole_count, rr.hole_scores.size())
						break
			# Live round partial cards when Round 1 is still active
			if r == 1 and _live_round_active and hole_cards.is_empty():
				var open_indices := _open_hole_indices()
				hole_count = open_indices.size()
				for h_ord in range(hole_count):
					var hi := int(open_indices[h_ord])
					var scores_on_hole: Dictionary = {}
					var active_total := _tournament_scores.size()
					for entry in _tournament_scores.values():
						var hs: Dictionary = entry.get("hole_strokes", {})
						if hs.has(hi):
							scores_on_hole[int(entry.get("sim_id", -999999))] = int(hs[hi])
					if active_total >= 2 and scores_on_hole.size() == active_total:
						var low := 999999
						var low_ids: Array[int] = []
						for sid in scores_on_hole:
							var sc := int(scores_on_hole[sid])
							if sc < low:
								low = sc
								low_ids = [int(sid)]
							elif sc == low:
								low_ids.append(int(sid))
						if low_ids.size() == 1:
							_format_points[low_ids[0]] = int(_format_points.get(low_ids[0], 0)) + 1 + carryover
							carryover = 0
						else:
							carryover += 1
				continue

			for h_ord in range(hole_count):
				var low := 999999
				var low_ids: Array[int] = []
				for sid in hole_cards:
					var arr: Array = hole_cards[sid]
					if h_ord >= arr.size():
						continue
					var sc := int(arr[h_ord])
					if sc < low:
						low = sc
						low_ids = [int(sid)]
					elif sc == low:
						low_ids.append(int(sid))
				if low_ids.is_empty():
					continue
				if low_ids.size() == 1:
					_format_points[low_ids[0]] = int(_format_points.get(low_ids[0], 0)) + 1 + carryover
					carryover = 0
				else:
					carryover += 1

## Play hole-by-hole Sudden-Death Playoff among competitors tied for 1st place.
func _run_sudden_death_playoff(standings: Array) -> void:
	if standings.size() < 2:
		return
	var use_points := TournamentLibrary.higher_points_is_better(current_format_type)
	var lead_stp := int(standings[0].get("score_to_par", 0))
	var lead_pts := int(standings[0].get("format_points", 0))
	var contenders: Array = []
	for s in standings:
		if int(s.id) in _eliminated_ids:
			continue
		var tied := (int(s.get("format_points", 0)) == lead_pts) if use_points else (int(s.get("score_to_par", 0)) == lead_stp)
		if tied:
			var sg := _find_sim_golfer(int(s.id))
			if sg != null:
				contenders.append(sg)
	if contenders.size() < 2:
		return

	var open_indices := _open_hole_indices()
	if open_indices.is_empty():
		return

	var holes_played := 0
	var winning_hole_num := 1
	var winning_strokes := 4
	var winning_par := 4
	while contenders.size() > 1 and holes_played < 18:
		var hi := int(open_indices[holes_played % open_indices.size()])
		holes_played += 1
		var best_val := -999999 if (current_format_type in [TournamentLibrary.FormatType.STABLEFORD, TournamentLibrary.FormatType.MODIFIED_STABLEFORD]) else 999999
		var survivors: Array = []
		for sg in contenders:
			var out := TournamentSimulator.simulate_single_hole(sg, hi)
			var st := int(out.get("strokes", 4))
			var pa := int(out.get("par", 4))
			winning_hole_num = int(out.get("hole_number", hi + 1))
			winning_par = pa
			if current_format_type in [TournamentLibrary.FormatType.STABLEFORD, TournamentLibrary.FormatType.MODIFIED_STABLEFORD]:
				var pts := TournamentLibrary.hole_points_for_format(current_format_type, st, pa)
				if pts > best_val:
					best_val = pts
					winning_strokes = st
					survivors = [sg]
				elif pts == best_val:
					survivors.append(sg)
			else:
				if st < best_val:
					best_val = st
					winning_strokes = st
					survivors = [sg]
				elif st == best_val:
					survivors.append(sg)
		if not survivors.is_empty():
			contenders = survivors

	var champ: TournamentSimulator.SimulationGolfer = contenders[0]
	_playoff_winner_id = champ.id
	_playoff_holes_played = holes_played
	var pm := TournamentSimulator.TournamentMoment.new()
	pm.type = "playoff"
	pm.round_number = total_rounds
	pm.hole = winning_hole_num
	pm.golfer_name = champ.name
	pm.detail = "Sudden-Death Playoff (Hole %d, %d extra %s): %s won with %s (%d)!" % [
		winning_hole_num,
		holes_played,
		"hole" if holes_played == 1 else "holes",
		champ.name,
		GolfRules.get_score_name(winning_strokes, winning_par),
		winning_strokes,
	]
	pm.importance = 3
	_tournament_moments.append(pm)
	_emit_moments([pm])

## Get current standings sorted by the active tournament format's primary metric.
func _get_standings() -> Array:
	var standings: Array = []
	var use_points := TournamentLibrary.higher_points_is_better(current_format_type)
	for sg in _sim_field:
		if not _cumulative_scores.has(sg.id):
			continue
		var cum = _cumulative_scores[sg.id]
		standings.append({
			"id": sg.id,
			"name": sg.name,
			"is_player": sg.id == PLAYER_SIM_ID,
			"total_strokes": cum.total_strokes,
			"total_par": cum.total_par,
			"score_to_par": cum.total_strokes - cum.total_par,
			"format_points": int(_format_points.get(sg.id, 0)),
			"won_playoff": sg.id == _playoff_winner_id,
		})

	standings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cut := int(a.id) in _eliminated_ids
		var b_cut := int(b.id) in _eliminated_ids
		if a_cut != b_cut:
			return not a_cut
		if bool(a.get("won_playoff", false)) != bool(b.get("won_playoff", false)):
			return bool(a.get("won_playoff", false))
		if use_points:
			var ap := int(a.get("format_points", 0))
			var bp := int(b.get("format_points", 0))
			if ap != bp:
				return ap > bp
		return int(a.score_to_par) < int(b.score_to_par)
	)
	return standings

## Get per-round score-to-par diffs for a golfer
func _get_round_score_diffs(sim_id: int) -> Array:
	var diffs: Array = []
	if _round_scores.has(sim_id):
		for rr in _round_scores[sim_id]:
			diffs.append(rr.total_strokes - rr.total_par)
	return diffs

## Get per-round format points for Stableford / Modified Stableford
func _get_round_format_points(sim_id: int) -> Array:
	var pts_arr: Array = []
	if current_format_type not in [
		TournamentLibrary.FormatType.STABLEFORD,
		TournamentLibrary.FormatType.MODIFIED_STABLEFORD
	]:
		return pts_arr
	if _round_scores.has(sim_id):
		for rr in _round_scores[sim_id]:
			var r_pts := 0
			for hi in range(mini(rr.hole_scores.size(), rr.hole_pars.size())):
				r_pts += TournamentLibrary.hole_points_for_format(
					current_format_type, int(rr.hole_scores[hi]), int(rr.hole_pars[hi])
				)
			pts_arr.append(r_pts)
	return pts_arr

## Find the simulated competitor a live golfer is being modelled on.
func _find_sim_golfer(sim_id: int) -> TournamentSimulator.SimulationGolfer:
	for sg in _sim_field:
		if sg.id == sim_id:
			return sg
	return null

## Calculate drama multiplier based on tournament moments
func _calculate_drama_multiplier() -> float:
	var multiplier = 1.0
	for moment in _tournament_moments:
		match moment.type:
			"eagle":
				multiplier += 0.05
			"hole_in_one":
				multiplier += 0.10
			"albatross":
				multiplier += 0.15
	return minf(multiplier, 1.5)

## Emit notifications for dramatic moments
func _emit_moments(moments: Array) -> void:
	for moment in moments:
		if moment.importance >= 2:
			EventBus.notify(moment.detail, "success")
		EventBus.tournament_moment.emit({
			"type": moment.type,
			"round": moment.round_number,
			"hole": moment.hole,
			"golfer_name": moment.golfer_name,
			"detail": moment.detail,
			"importance": moment.importance,
		})

## Format score-to-par difference
func _format_score_diff(diff: int) -> String:
	if diff == 0:
		return "E"
	elif diff > 0:
		return "+%d" % diff
	else:
		return "%d" % diff

## Format a standings entry
func _format_score(entry: Dictionary) -> String:
	return TournamentLibrary.format_score_for_format(
		current_format_type,
		int(entry.get("score_to_par", 0)),
		int(entry.get("format_points", 0)),
		true
	)

# ============================================================================
# PUBLIC QUERY METHODS
# ============================================================================

func get_tournament_info() -> Dictionary:
	if current_tournament_state == TournamentSystem.TournamentState.NONE:
		return {}

	var tier_data = TournamentSystem.get_tier_data(current_tournament_tier)
	var event_name := str(tier_data.name)
	if _is_standalone_event:
		event_name = TournamentLibrary.get_format_name(current_format_type)
	return {
		"tier": current_tournament_tier,
		"name": event_name,
		"format_type": current_format_type,
		"format_name": TournamentLibrary.get_format_name(current_format_type),
		"cut_rule": _standalone_cut_rule if _is_standalone_event else str(CUT_RULES.get(current_tournament_tier, {}).get("rule", "none")),
		"playoff": _standalone_playoff_enabled if _is_standalone_event else false,
		"field_size": _sim_field.size(),
		"state": current_tournament_state,
		"current_round": current_round,
		"total_rounds": total_rounds,
	}

func get_cooldown_remaining() -> int:
	var days_since = GameManager.current_day - last_tournament_end_day
	return max(0, TOURNAMENT_COOLDOWN - days_since)

func is_tournament_in_progress() -> bool:
	return current_tournament_state == TournamentSystem.TournamentState.IN_PROGRESS

## The owner's own standing in the running event — score to par / format points,
## position in the field and how many holes they have played.
func get_player_standing() -> Dictionary:
	if current_tournament_state == TournamentSystem.TournamentState.NONE:
		return {}

	var standings = _get_standings()
	var use_points := TournamentLibrary.higher_points_is_better(current_format_type)
	for i in range(standings.size()):
		if standings[i].id != PLAYER_SIM_ID:
			continue
		var holes: int = 0
		for entry in _tournament_scores.values():
			if entry.get("sim_id", -1) == PLAYER_SIM_ID:
				holes = int(entry.holes_completed)
				break
		var ahead := 0
		for j in range(standings.size()):
			if use_points:
				if int(standings[j].get("format_points", 0)) > int(standings[i].get("format_points", 0)):
					ahead += 1
			elif int(standings[j].score_to_par) < int(standings[i].score_to_par):
				ahead += 1
		return {
			"name": standings[i].name,
			"rank": ahead + 1,
			"field_size": standings.size(),
			"score_to_par": standings[i].score_to_par,
			"format_points": int(standings[i].get("format_points", 0)),
			"format_type": current_format_type,
			"total_strokes": standings[i].total_strokes,
			"holes_completed": holes,
			"round": current_round,
			"missed_cut": standings[i].id in _eliminated_ids,
		}
	return {}

func get_save_data() -> Dictionary:
	return {
		"current_tier": current_tournament_tier,
		"state": current_tournament_state,
		"start_day": tournament_start_day,
		"last_end_day": last_tournament_end_day,
	}

func load_save_data(data: Dictionary) -> void:
	current_tournament_tier = data.get("current_tier", -1)
	var loaded_state = data.get("state", TournamentSystem.TournamentState.NONE)
	if loaded_state == TournamentSystem.TournamentState.IN_PROGRESS:
		current_tournament_state = TournamentSystem.TournamentState.NONE
		current_tournament_tier = -1
	else:
		current_tournament_state = loaded_state
	tournament_start_day = data.get("start_day", 0)
	last_tournament_end_day = data.get("last_end_day", -100)
