extends Node2D
class_name Ball
## Ball - Represents a golf ball in flight or at rest
##
## A hill nearer the camera hides the ball, pixel by pixel, as it hides a tree
## or a golfer (see refresh_terrain_occlusion()).

enum BallState {
	AT_REST,      # Ball is sitting still
	IN_FLIGHT,    # Ball is flying through the air
	ROLLING,      # Ball is rolling on ground after landing
	IN_WATER,     # Ball is in water hazard
	OUT_OF_BOUNDS # Ball is OB
}

## The ground-state golf ball radius, in screen pixels. The cup cut under the
## flag is sized from it too, so the hole is exactly as wide as the ball that
## drops into it (see CupOverlay.hole_radius()).
const BALL_RADIUS: float = 1.75
## Airborne the ball is drawn a touch larger so it stays visible against the sky;
## the flight depth scale multiplies this. Keep it proportional to the ground ball.
const FLIGHT_RADIUS: float = BALL_RADIUS * 1.28
## How many sides the ball's polygon gets. A dozen looked fine at the old size
## but reads as a chunky dodecagon once the ball is small.
const BALL_SEGMENTS: int = 16

## The soft contact shadow every ball lays on the ground, given as half-widths
## in ball radii: wider across the tile than up the screen, the way the
## isometric ground squashes a circle. It is drawn beneath the ball so the ball
## sits on the ground instead of hovering over it, and it is a shade wider than
## the ball so its rim stays visible around the ball's foot.
const SHADOW_RADII: Vector2 = Vector2(1.0, 0.5)
## Where the shadow's centre sits from the ball, in ball radii: at the ball's
## foot, a touch to the right, away from the sun, so the dark rim shows under
## the ball rather than hiding behind it.
const SHADOW_OFFSET: Vector2 = Vector2(0.2, 0.9)
## Darkness of the contact shadow on the ground. A darker blob would read as
## a second ball.
const SHADOW_ALPHA: float = 0.3
## In the air the shadow stays on the ground and tightens to this fraction of
## its resting size, and fades to this fraction of its resting darkness, at the
## top of the arc. Both settle back to 1 as the ball comes down.
const SHADOW_AIRBORNE_SCALE: float = 0.55
const SHADOW_AIRBORNE_ALPHA: float = 0.5
## Entity band shared with golfers, trees, buildings, decorations, and flags.
const ENTITY_Z_INDEX: int = 2
## Relative offset placing the ball's contact shadow into the ground band (z 1),
## over turf markings and beneath every standing sprite.
const SHADOW_Z_INDEX: int = -1

var golfer_id: int = -1
var grid_position: Vector2i = Vector2i.ZERO
var ball_state: BallState = BallState.AT_REST
var terrain_grid: TerrainGrid

# Flight animation properties
var flight_start_pos: Vector2 = Vector2.ZERO
var flight_end_pos: Vector2 = Vector2.ZERO
var flight_progress: float = 0.0
var flight_duration: float = 1.0
var flight_max_height: float = 100.0
var wind_visual_offset: Vector2 = Vector2.ZERO  # Visual wind drift during flight

# Rollout animation properties
var roll_start_pos: Vector2 = Vector2.ZERO
var roll_end_pos: Vector2 = Vector2.ZERO
var roll_progress: float = 0.0
var roll_duration: float = 0.0
var _has_pending_rollout: bool = false

## The soft ellipse painted on the ground under this ball. It is a child of the
## ball, added before the visual, so every state keeps exactly one shadow and
## the ball always paints over it.
var _ground_shadow: Polygon2D
var _visual: Node2D = null
## How far the ball is lifted above its own ground track, in screen pixels. The
## flight arc moves the ball's node upward; its shadow ignores that offset so
## it stays on the ground the ball is flying over.
var _shadow_lift: float = 0.0

## Clips the ball where nearer terrain covers it, as trees and golfers are
## clipped: a billboard over the grid point under the ball.
const TERRAIN_SPRITE_OCCLUSION: Shader = preload("res://shaders/terrain_sprite_occlusion.gdshader")
## How far under its ground point's screen position the ball's art reaches: the
## foot of its contact shadow. The occlusion test measures the ball from the
## ground drawn there (TerrainOcclusion.contact_reach()), so the lower half of a
## ball drawn centred on its ground point, and the shadow under it, are not taken
## to be underground, and cut by the ground just in front of the ball - even on a
## slope rising toward the camera.
const OCCLUSION_FOOT: float = (SHADOW_OFFSET.y + SHADOW_RADII.y) * BALL_RADIUS
## How close, in screen pixels, a grid point must project to a screen position
## to be taken as the ground there.
const GROUND_MATCH_PX: float = 0.5

## The ground under the ball, as grid points (tile centres at .5): the point it
## rests on, and the ends of the straight ground track a flight or a roll runs
## along. The screen positions above do not say which of the surfaces drawn at
## a spot - a hill, or the hollow behind it - the spot is on; these do. INVALID
## where not known.
var rest_ground := TerrainGrid.INVALID_GRID_POINT
var flight_start_ground := TerrainGrid.INVALID_GRID_POINT
var flight_end_ground := TerrainGrid.INVALID_GRID_POINT
var roll_start_ground := TerrainGrid.INVALID_GRID_POINT
var roll_end_ground := TerrainGrid.INVALID_GRID_POINT

## Multi-segment airborne deflection state (non-empty only on tree-impact shots).
var flight_start_height: float = 0.0
var flight_end_height: float = 0.0
var flight_phase_start: float = 0.0
var flight_phase_end: float = 1.0
var _flight_end_tree_hit: Dictionary = {}
var _queued_flight_segments: Array[Dictionary] = []

## Multi-waypoint ground rollout state (used when rolling past/off a tree trunk).
var _roll_waypoints_ground: PackedVector2Array = PackedVector2Array()
var _roll_waypoints_screen: PackedVector2Array = PackedVector2Array()
var _roll_cum_dist: PackedFloat32Array = PackedFloat32Array()
var _roll_tree_events: Array[Dictionary] = []

## The course grid whose terrain-occlusion switch, sculpting and turns are followed.
var _occlusion_grid: TerrainGrid = null
## This ball's occlusion material: made the first time the course has relief,
## kept for the ball's life, and only worn while occlusion is on.
var _occlusion_material: ShaderMaterial = null
var _occlusion_active := false
## The grid point the shader stands the ball on, the lift it measures the ball
## from (its ground_offset.y), and the position they were found for.
var _occlusion_anchor := TerrainGrid.INVALID_GRID_POINT
var _occlusion_lift := 0.0
var _occlusion_position := Vector2(INF, INF)
var _occlusion_refresh_queued := false

signal ball_landed(landing_pos: Vector2i)
signal ball_state_changed(old_state: BallState, new_state: BallState)
signal ball_landed_in_bunker(landing_pos: Vector2i)
signal ball_landed_in_water(landing_pos: Vector2i)
signal ball_hit_tree(tree_tile: Vector2i, species: String, material_type: int, world_position: Vector2)

func _ready() -> void:
	z_index = ENTITY_Z_INDEX
	y_sort_enabled = true
	_update_visual()  # Builds the ground shadow first, then the ball
	# The Display page can switch contact shadows off, and the ball is already
	# on the course, so follow the setting rather than deciding once at birth.
	if not PerformanceSettings.profile_changed.is_connected(_on_graphics_settings_changed):
		PerformanceSettings.profile_changed.connect(_on_graphics_settings_changed)

func _enter_tree() -> void:
	# A ball moved from outside is followed as it is moved (see _notification()).
	set_notify_local_transform(true)
	_watch_terrain_occlusion(true)

func _exit_tree() -> void:
	_watch_terrain_occlusion(false)
	if PerformanceSettings.profile_changed.is_connected(_on_graphics_settings_changed):
		PerformanceSettings.profile_changed.disconnect(_on_graphics_settings_changed)

func _on_graphics_settings_changed(_terrain_fast: bool) -> void:
	_update_shadow()

func _process(delta: float) -> void:
	if ball_state == BallState.IN_FLIGHT:
		_process_flight(delta)
	elif ball_state == BallState.ROLLING:
		_process_rolling(delta)

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid
	_watch_terrain_occlusion(is_inside_tree())

func set_position_in_grid(pos: Vector2i) -> void:
	grid_position = pos
	rest_ground = Vector2(pos) + Vector2(0.5, 0.5)
	if terrain_grid:
		var world_pos = terrain_grid.grid_to_screen_center(pos)
		global_position = world_pos
	_update_visual()

func _clear_flight_tree_tracks() -> void:
	flight_start_height = 0.0
	flight_end_height = 0.0
	flight_phase_start = 0.0
	flight_phase_end = 1.0
	_flight_end_tree_hit.clear()
	_queued_flight_segments.clear()


func _clear_roll_waypoints() -> void:
	_roll_waypoints_ground.clear()
	_roll_waypoints_screen.clear()
	_roll_cum_dist.clear()
	_roll_tree_events.clear()


## Configure rollout to play after the current flight lands.
## carry_screen is where the ball first hits ground (should match flight_end_pos).
## final_screen is where it comes to rest after rolling; `final_ground` is the
## grid point there, when the caller knows it (see rest_ground).
func set_rollout(final_screen: Vector2, duration: float,
		final_ground: Vector2 = TerrainGrid.INVALID_GRID_POINT) -> void:
	_clear_roll_waypoints()
	roll_end_pos = final_screen
	roll_duration = duration
	roll_end_ground = final_ground
	_has_pending_rollout = true


## Configure a multi-waypoint rollout (used when rolling past/off tree trunks or brush).
func set_rollout_waypoints(waypoints_center: PackedVector2Array, duration: float,
		roll_hits: Array = []) -> void:
	_clear_roll_waypoints()
	if waypoints_center.size() < 2 or not is_instance_valid(terrain_grid):
		return
	var total_len := 0.0
	_roll_cum_dist.append(0.0)
	for i in range(waypoints_center.size()):
		var g_pt := waypoints_center[i] + Vector2(0.5, 0.5)
		var s_pt := terrain_grid.grid_point_to_screen(g_pt)
		_roll_waypoints_ground.append(g_pt)
		_roll_waypoints_screen.append(s_pt)
		if i > 0:
			total_len += _roll_waypoints_screen[i - 1].distance_to(s_pt)
			_roll_cum_dist.append(total_len)
	if total_len > 0.0001:
		for i in range(_roll_cum_dist.size()):
			_roll_cum_dist[i] /= total_len
	for hit in roll_hits:
		var wp_idx := clampi(int(hit.get("waypoint_index", 0)), 0, _roll_cum_dist.size() - 1)
		_roll_tree_events.append({
			"t": float(_roll_cum_dist[wp_idx]),
			"triggered": false,
			"tree_tile": hit.get("tree_tile", Vector2i(-1, -1)),
			"species": str(hit.get("species", "oak")),
			"material": int(hit.get("material", TreeCollisionProfile.MAT_WOOD)),
		})
	roll_end_pos = _roll_waypoints_screen[_roll_waypoints_screen.size() - 1]
	roll_end_ground = _roll_waypoints_ground[_roll_waypoints_ground.size() - 1]
	roll_duration = duration
	_has_pending_rollout = true


## Start a flight animation from one position to another
func start_flight(from_grid: Vector2i, to_grid: Vector2i, duration: float = 1.5, is_putt: bool = false, wind_offset: Vector2 = Vector2.ZERO) -> void:
	if not terrain_grid:
		return

	_clear_flight_tree_tracks()
	grid_position = from_grid
	flight_start_pos = terrain_grid.grid_to_screen_center(from_grid)
	flight_end_pos = terrain_grid.grid_to_screen_center(to_grid)
	flight_start_ground = Vector2(from_grid) + Vector2(0.5, 0.5)
	flight_end_ground = Vector2(to_grid) + Vector2(0.5, 0.5)
	flight_progress = 0.0
	flight_duration = duration

	# Putts roll along the ground; other shots fly in an arc
	if is_putt:
		flight_max_height = 0.0
		wind_visual_offset = Vector2.ZERO  # No wind on putts
	else:
		var distance = flight_start_pos.distance_to(flight_end_pos)
		flight_max_height = min(distance * 0.3, 150.0)
		wind_visual_offset = wind_offset

	_shadow_lift = 0.0
	scale = Vector2.ONE
	_change_state(BallState.IN_FLIGHT)
	global_position = flight_start_pos
	_update_shadow()

## Start a flight animation using precise screen coordinates (for sub-tile putting).
## `from_ground` and `to_ground` are the grid points under them, when the caller
## knows them (see rest_ground); otherwise the ball works them out.
func start_flight_screen(from_screen: Vector2, to_screen: Vector2, duration: float = 1.5, is_putt: bool = false,
		from_ground: Vector2 = TerrainGrid.INVALID_GRID_POINT,
		to_ground: Vector2 = TerrainGrid.INVALID_GRID_POINT) -> void:
	_clear_flight_tree_tracks()
	flight_start_pos = from_screen
	flight_end_pos = to_screen
	_set_flight_ground(from_ground, to_ground)
	flight_progress = 0.0
	flight_duration = duration

	if is_putt:
		flight_max_height = 0.0
		wind_visual_offset = Vector2.ZERO  # No wind drift on putts
	else:
		var distance = flight_start_pos.distance_to(flight_end_pos)
		flight_max_height = min(distance * 0.3, 150.0)

	_shadow_lift = 0.0
	scale = Vector2.ONE
	_change_state(BallState.IN_FLIGHT)
	global_position = flight_start_pos
	_update_shadow()

## Start a flight animation with arc using precise screen coordinates (for sub-tile shots).
## `from_ground` and `to_ground` are the grid points under them, when the caller
## knows them (see rest_ground); otherwise the ball works them out.
func start_flight_screen_with_arc(from_screen: Vector2, to_screen: Vector2, duration: float = 1.5,
		wind_offset: Vector2 = Vector2.ZERO,
		from_ground: Vector2 = TerrainGrid.INVALID_GRID_POINT,
		to_ground: Vector2 = TerrainGrid.INVALID_GRID_POINT) -> void:
	_clear_flight_tree_tracks()
	flight_start_pos = from_screen
	flight_end_pos = to_screen
	_set_flight_ground(from_ground, to_ground)
	flight_progress = 0.0
	flight_duration = duration

	var distance = flight_start_pos.distance_to(flight_end_pos)
	flight_max_height = min(distance * 0.3, 150.0)
	wind_visual_offset = wind_offset

	_shadow_lift = 0.0
	scale = Vector2.ONE
	_change_state(BallState.IN_FLIGHT)
	global_position = flight_start_pos
	_update_shadow()


## Start a chained multi-segment airborne flight produced by tree impacts.
func start_flight_tree_segments(segments: Array, total_duration: float) -> void:
	if segments.is_empty() or not is_instance_valid(terrain_grid):
		return
	_clear_flight_tree_tracks()

	var total_weight := 0.0
	for seg in segments:
		total_weight += maxf(float(seg.get("duration_weight", 1.0)), 1.0)

	var origin_proj := terrain_grid.projection.project(Vector2.ZERO)
	for seg in segments:
		var fg: Vector2 = Vector2(seg.get("from", Vector2.ZERO)) + Vector2(0.5, 0.5)
		var tg: Vector2 = Vector2(seg.get("to", Vector2.ZERO)) + Vector2(0.5, 0.5)
		var curve_g: Vector2 = seg.get("bend_grid", Vector2.ZERO) + seg.get("wind_grid", Vector2.ZERO)
		var wind_scr := terrain_grid.projection.project(curve_g) - origin_proj if curve_g != Vector2.ZERO else Vector2.ZERO
		var w := maxf(float(seg.get("duration_weight", 1.0)), 1.0)
		var seg_dur := maxf(total_duration * (w / total_weight), 0.06)
		var hit_info: Dictionary = {}
		if bool(seg.get("hit_at_end", false)):
			hit_info = {
				"tree_tile": seg.get("hit_tree_tile", Vector2i(-1, -1)),
				"species": str(seg.get("hit_species", "oak")),
				"material": int(seg.get("hit_material", TreeCollisionProfile.MAT_FOLIAGE)),
			}
		_queued_flight_segments.append({
			"from_ground": fg,
			"to_ground": tg,
			"from_pos": terrain_grid.grid_point_to_screen(fg),
			"to_pos": terrain_grid.grid_point_to_screen(tg),
			"start_h": float(seg.get("start_h", 0.0)),
			"end_h": float(seg.get("end_h", 0.0)),
			"pop_h": float(seg.get("pop_h", 0.0)),
			"phase_from": float(seg.get("phase_from", 0.0)),
			"phase_to": float(seg.get("phase_to", 1.0)),
			"curve_grid": curve_g,
			"wind_offset": wind_scr,
			"duration": seg_dur,
			"hit_info": hit_info,
		})

	_load_flight_segment(_queued_flight_segments.pop_front())
	_shadow_lift = 0.0
	scale = Vector2.ONE
	_change_state(BallState.IN_FLIGHT)
	place_on_track()


func _load_flight_segment(seg: Dictionary) -> void:
	flight_start_ground = seg.from_ground
	flight_end_ground = seg.to_ground
	flight_start_pos = seg.from_pos
	flight_end_pos = seg.to_pos
	flight_start_height = float(seg.start_h)
	flight_end_height = float(seg.end_h)
	flight_max_height = float(seg.pop_h)
	flight_phase_start = float(seg.phase_from)
	flight_phase_end = float(seg.phase_to)
	wind_visual_offset = seg.wind_offset
	flight_duration = float(seg.duration)
	flight_progress = 0.0
	_flight_end_tree_hit = seg.hit_info


func _current_flight_phase() -> float:
	return lerpf(flight_phase_start, flight_phase_end, flight_progress)


func _current_arc_height() -> float:
	var phase := _current_flight_phase()
	var base_h := lerpf(flight_start_height, flight_end_height, flight_progress)
	return base_h + sin(phase * PI) * flight_max_height


## Recompute queued bounce segments and rollout waypoints after a camera view rotation.
func reproject_extra_tracks(grid: TerrainGrid) -> void:
	if not is_instance_valid(grid):
		return
	var origin_proj := grid.projection.project(Vector2.ZERO)
	for seg in _queued_flight_segments:
		seg["from_pos"] = grid.grid_point_to_screen(seg.from_ground)
		seg["to_pos"] = grid.grid_point_to_screen(seg.to_ground)
		var cg: Vector2 = seg.get("curve_grid", Vector2.ZERO)
		seg["wind_offset"] = grid.projection.project(cg) - origin_proj if cg != Vector2.ZERO else Vector2.ZERO
	if not _roll_waypoints_ground.is_empty():
		_roll_waypoints_screen.resize(_roll_waypoints_ground.size())
		for i in range(_roll_waypoints_ground.size()):
			_roll_waypoints_screen[i] = grid.grid_point_to_screen(_roll_waypoints_ground[i])
		if _roll_waypoints_screen.size() > 0:
			roll_start_pos = _roll_waypoints_screen[0]
			roll_end_pos = _roll_waypoints_screen[_roll_waypoints_screen.size() - 1]


func _process_flight(delta: float) -> void:
	flight_progress += delta / maxf(flight_duration, 0.001)

	if flight_progress >= 1.0:
		flight_progress = 1.0
		place_on_track()

		if not _flight_end_tree_hit.is_empty():
			ball_hit_tree.emit(
				_flight_end_tree_hit.get("tree_tile", Vector2i(-1, -1)),
				str(_flight_end_tree_hit.get("species", "oak")),
				int(_flight_end_tree_hit.get("material", TreeCollisionProfile.MAT_FOLIAGE)),
				global_position
			)
			_flight_end_tree_hit.clear()

		if not _queued_flight_segments.is_empty():
			_load_flight_segment(_queued_flight_segments.pop_front())
			place_on_track()
			return

		# All airborne segments finished - ball hits the ground
		global_position = flight_end_pos
		if terrain_grid:
			grid_position = _tile_under(flight_end_ground, flight_end_pos)

		scale = Vector2.ONE  # Reset scale from flight
		_shadow_lift = 0.0   # Back on the ground, under the ball again
		_update_shadow()

		# Spawn impact effect at the carry spot (where ball first hits ground)
		_spawn_landing_impact()

		# Check if rollout was configured — if so, start rolling instead of landing
		var has_roll_dist := _roll_waypoints_ground.size() >= 2 or roll_end_pos.distance_to(flight_end_pos) > 1.0
		if _has_pending_rollout and has_roll_dist:
			_has_pending_rollout = false
			_start_rollout()
		else:
			_has_pending_rollout = false
			rest_ground = flight_end_ground
			_land_ball()
		return

	# Update visual scale for depth perception (skip for putts rolling on ground)
	var arc_height := _current_arc_height()
	if flight_max_height > 0.0 or flight_start_height > 0.0:
		var is_standard_arc := flight_start_height == 0.0 and flight_phase_start == 0.0 and flight_phase_end == 1.0
		var ref_h := flight_max_height if is_standard_arc else maxf(flight_max_height, maxf(flight_start_height, 60.0))
		var scale_factor := 1.0 + clampf(arc_height / maxf(ref_h, 1.0), 0.0, 1.0) * 0.5
		scale = Vector2(scale_factor, scale_factor)

	place_on_track()

## Put the ball where its flight or roll has got to, and its contact shadow on
## the ground under it.
##
## A flight follows a parabolic arc over the straight track between the screen
## positions of its ends, drifted by the wind. A putt or a roll rolls on the
## ground itself where the ground under it is known (ground_point()): over a
## crowned green, not through it - on flat ground the two are the same line.
## main.gd calls this after a view turn has moved the ends.
func place_on_track() -> void:
	var ground := ground_point()
	var knows_ground := ground != TerrainGrid.INVALID_GRID_POINT and is_instance_valid(terrain_grid)
	match ball_state:
		BallState.IN_FLIGHT:
			var phase := _current_flight_phase()
			var arc_height := _current_arc_height()
			# Apply wind visual drift as a bell curve: peaks at mid-flight,
			# smoothly returns to zero at landing so the ball arrives at the
			# correct position.
			var track := flight_start_pos.lerp(flight_end_pos, flight_progress) \
					+ wind_visual_offset * sin(phase * PI)
			var under := terrain_grid.grid_point_to_screen(ground) if knows_ground else track
			if flight_max_height <= 0.0 and flight_start_height <= 0.0 and knows_ground:
				global_position = under
			else:
				global_position = track - Vector2(0.0, arc_height)
			# The ball's node has climbed with the arc; the shadow is pushed
			# back down onto the ground the ball is flying over.
			_shadow_lift = maxf(under.y - global_position.y, 0.0)
		BallState.ROLLING:
			var u := _roll_eased()
			if knows_ground:
				global_position = terrain_grid.grid_point_to_screen(ground)
			elif _roll_waypoints_screen.size() >= 2:
				global_position = _sample_roll_array(_roll_waypoints_screen, u)
			else:
				global_position = roll_start_pos.lerp(roll_end_pos, u)
			_trigger_pending_roll_tree_events(u)
			_shadow_lift = 0.0
		_:
			return
	_update_shadow()


func _sample_roll_array(arr: PackedVector2Array, u: float) -> Vector2:
	var n := arr.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1 or u <= 0.0:
		return arr[0]
	if u >= 1.0:
		return arr[n - 1]
	for i in range(1, n):
		if u <= _roll_cum_dist[i]:
			var seg_len := _roll_cum_dist[i] - _roll_cum_dist[i - 1]
			var seg_t := (u - _roll_cum_dist[i - 1]) / seg_len if seg_len > 0.00001 else 0.0
			return arr[i - 1].lerp(arr[i], seg_t)
	return arr[n - 1]


func _trigger_pending_roll_tree_events(u: float) -> void:
	for ev in _roll_tree_events:
		if not bool(ev.triggered) and u >= float(ev.t):
			ev.triggered = true
			ball_hit_tree.emit(
				ev.tree_tile,
				str(ev.species),
				int(ev.material),
				global_position
			)

## How far along its roll the ball has got: eased out, so it slows as it rolls.
func _roll_eased() -> float:
	return 1.0 - pow(1.0 - roll_progress, 2.0)

## Begin rollout animation from current position to roll_end_pos
func _start_rollout() -> void:
	roll_start_pos = global_position
	roll_start_ground = flight_end_ground
	if roll_end_ground == TerrainGrid.INVALID_GRID_POINT:
		roll_end_ground = _resolve_ground(roll_end_pos, roll_start_ground)
	roll_progress = 0.0
	_change_state(BallState.ROLLING)

func _process_rolling(delta: float) -> void:
	if roll_duration <= 0.0:
		_finish_rollout()
		return

	roll_progress += delta / roll_duration

	if roll_progress >= 1.0:
		roll_progress = 1.0
		global_position = roll_end_pos
		_finish_rollout()
		return

	# Ease-out deceleration: ball slows down as it rolls (see _roll_eased())
	place_on_track()

func _finish_rollout() -> void:
	global_position = roll_end_pos
	rest_ground = roll_end_ground
	if terrain_grid:
		grid_position = _tile_under(roll_end_ground, roll_end_pos)
	_land_ball()

## Spawn landing impact effect at the carry spot (where ball first hits ground)
func _spawn_landing_impact() -> void:
	if not terrain_grid:
		return
	# Skip putts and short chips
	if flight_max_height <= 10.0:
		return

	var carry_terrain = terrain_grid.get_tile(grid_position)
	var impact_terrain = "default"
	match carry_terrain:
		TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY, TerrainTypes.Type.TEE_BOX:
			impact_terrain = "fairway"
		TerrainTypes.Type.GRASS, TerrainTypes.Type.ROUGH, TerrainTypes.Type.HEAVY_ROUGH, \
				TerrainTypes.Type.DEEP_ROUGH, TerrainTypes.Type.BRUSH:
			impact_terrain = "grass"
		TerrainTypes.Type.BUNKER, TerrainTypes.Type.POT_BUNKER, TerrainTypes.Type.WASTE_BUNKER:
			impact_terrain = "bunker"
		TerrainTypes.Type.WATER, TerrainTypes.Type.STREAM:
			impact_terrain = "water"
		TerrainTypes.Type.GREEN:
			impact_terrain = "fairway"
	LandingImpactEffect.create_at(get_parent(), global_position, impact_terrain)

func _land_ball() -> void:
	if not terrain_grid:
		_change_state(BallState.AT_REST)
		ball_landed.emit(grid_position)
		scale = Vector2.ONE
		return

	# Check terrain type at final resting position
	var terrain_type = terrain_grid.get_tile(grid_position)

	match terrain_type:
		TerrainTypes.Type.WATER, TerrainTypes.Type.STREAM:
			_change_state(BallState.IN_WATER)
			ball_landed_in_water.emit(grid_position)
		TerrainTypes.Type.OUT_OF_BOUNDS:
			_change_state(BallState.OUT_OF_BOUNDS)
		TerrainTypes.Type.BUNKER, TerrainTypes.Type.POT_BUNKER:
			_change_state(BallState.AT_REST)
			ball_landed_in_bunker.emit(grid_position)
		_:
			_change_state(BallState.AT_REST)

	ball_landed.emit(grid_position)
	scale = Vector2.ONE  # Reset scale

func _change_state(new_state: BallState) -> void:
	if ball_state == new_state:
		return

	var old_state = ball_state
	ball_state = new_state
	if new_state != BallState.IN_FLIGHT:
		_shadow_lift = 0.0
		scale = Vector2.ONE
	ball_state_changed.emit(old_state, new_state)
	_update_visual()

func _update_visual() -> void:
	# The shadow is created once and kept first, beneath the visual, so it is
	# never rebuilt with the ball's shape and never paints over it.
	_ensure_ground_shadow()

	# Remove existing visual immediately so the new node keeps the "Visual" name
	# without leaving detached nodes pending deletion at end-of-frame.
	if _visual != null and is_instance_valid(_visual):
		if _visual.get_parent() == self:
			remove_child(_visual)
		_visual.free()
	elif has_node("Visual"):
		var previous := get_node("Visual")
		remove_child(previous)
		previous.free()

	var visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)
	_visual = visual

	# Draw ball based on state
	match ball_state:
		BallState.AT_REST, BallState.ROLLING:
			_draw_ball_at_rest(visual)
		BallState.IN_FLIGHT:
			_draw_ball_in_flight(visual)
		BallState.IN_WATER:
			_draw_ball_in_water(visual)
		BallState.OUT_OF_BOUNDS:
			_draw_ball_out_of_bounds(visual)

	_apply_occlusion_material()
	_update_shadow()

## Build the ball's one contact shadow, toggled on the Display page.
func _ensure_ground_shadow() -> void:
	if _ground_shadow != null and is_instance_valid(_ground_shadow):
		return

	_ground_shadow = Polygon2D.new()
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.z_index = SHADOW_Z_INDEX
	_ground_shadow.polygon = ellipse_polygon(SHADOW_RADII * BALL_RADIUS)
	_ground_shadow.color = Color(0, 0, 0, SHADOW_ALPHA)
	_ground_shadow.visible = PerformanceSettings.contact_shadows_enabled()
	add_child(_ground_shadow)
	move_child(_ground_shadow, 0)

## Anchor the ball's Visual node on the ground track directly beneath the ball
## while shifting its polygons back up by the same amount, so world Y-sorting
## orders an airborne ball by its true ground position without moving the drawn
## arc or changing `global_position`.
func _sync_visual_sort_anchor() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	var depth := maxf(scale.x, 0.001)
	var ground_anchor := Vector2(0.0, _shadow_lift / depth)
	_visual.position = ground_anchor
	for child in _visual.get_children():
		if child is Polygon2D:
			(child as Polygon2D).offset = -ground_anchor

## Place the contact shadow on the ground under the ball.
##
## At rest it is a soft ellipse at the ball's foot. In flight the ball's node
## climbs with the arc and grows with the depth scale, so the shadow is pushed
## back down by the arc height and divided through by that scale: it stays on
## the ground beneath the ball's flight path at its normal size, tightening and
## fading as the ball rises instead of flying away with it.
func _update_shadow() -> void:
	_sync_visual_sort_anchor()
	# Every step of a flight or a roll, and every new state, passes through
	# here; other moves are followed as they are made (_notification()).
	_refresh_occlusion()
	if _ground_shadow == null or not is_instance_valid(_ground_shadow):
		return

	_ground_shadow.visible = PerformanceSettings.contact_shadows_enabled()
	if not _ground_shadow.visible:
		return

	var lift_ratio := 0.0
	if ball_state == BallState.IN_FLIGHT:
		var max_h := maxf(flight_max_height, flight_start_height)
		if max_h > 0.0:
			lift_ratio = clampf(_shadow_lift / max_h, 0.0, 1.0)

	# The flight depth scale enlarges the ball, and everything under it. Undo it
	# so the shadow keeps its resting footprint rather than growing with height.
	var depth := maxf(scale.x, 0.001)
	var footprint := lerpf(1.0, SHADOW_AIRBORNE_SCALE, lift_ratio) / depth
	_ground_shadow.scale = Vector2(footprint, footprint)
	_ground_shadow.position = (SHADOW_OFFSET * BALL_RADIUS + Vector2(0, _shadow_lift)) / depth
	_ground_shadow.color = Color(0, 0, 0,
			lerpf(SHADOW_ALPHA, SHADOW_ALPHA * SHADOW_AIRBORNE_ALPHA, lift_ratio))

## Round polygon of the given screen radius, centred on the node's origin.
## Shared by every ball state so one constant decides how big a ball is.
static func ball_polygon(radius: float, segments: int = BALL_SEGMENTS) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

## Flat ellipse (a round shape seen in the isometric view), given as half-widths.
static func ellipse_polygon(radii: Vector2, segments: int = 8) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points

func _draw_ball_at_rest(visual: Node2D) -> void:
	# White golf ball. Its contact shadow is the Ball's own GroundShadow child,
	# painted before the visual so the ball sits on top of it.
	var ball = Polygon2D.new()
	ball.color = Color.WHITE
	ball.polygon = ball_polygon(BALL_RADIUS)
	visual.add_child(ball)

func _draw_ball_in_flight(visual: Node2D) -> void:
	# Slightly larger for visibility
	var ball = Polygon2D.new()
	ball.color = Color.WHITE
	ball.polygon = ball_polygon(FLIGHT_RADIUS)
	visual.add_child(ball)

	# Add motion blur effect
	var blur = Polygon2D.new()
	blur.color = Color(1, 1, 1, 0.3)
	blur.position = Vector2(-FLIGHT_RADIUS * 0.6, FLIGHT_RADIUS * 0.2)
	blur.polygon = ball_polygon(FLIGHT_RADIUS * 0.8)
	visual.add_child(blur)

func _draw_ball_in_water(visual: Node2D) -> void:
	# Semi-transparent ball in water
	var ball = Polygon2D.new()
	ball.color = Color(1, 1, 1, 0.5)
	ball.polygon = ball_polygon(BALL_RADIUS)
	visual.add_child(ball)

	# Water splash effect, drawn in ball radii so it shrinks with the ball
	var splash = Polygon2D.new()
	splash.color = Color(0.3, 0.5, 0.8, 0.6)
	var splash_points = PackedVector2Array()
	for point in [
		Vector2(-1.5, 0.0), Vector2(-0.75, -1.0), Vector2(0.0, -0.5),
		Vector2(0.75, -1.0), Vector2(1.5, 0.0), Vector2(0.75, 0.5),
		Vector2(0.0, 1.0), Vector2(-0.75, 0.5),
	]:
		splash_points.append(point * BALL_RADIUS)
	splash.polygon = splash_points
	visual.add_child(splash)

func _draw_ball_out_of_bounds(visual: Node2D) -> void:
	# Red X over ball
	var ball = Polygon2D.new()
	ball.color = Color.GRAY
	ball.polygon = ball_polygon(BALL_RADIUS)
	visual.add_child(ball)

# =============================================================================
# HILLS IN FRONT OF THE BALL
# =============================================================================

## The grid point directly under the ball: where it rests, or how far along its
## straight ground track a flight or a roll has got (the track's ends lerped, as
## the screen positions are, with a flight's wind drift taken as a drift over
## the ground); INVALID where the ground is not known.
func ground_point() -> Vector2:
	match ball_state:
		BallState.IN_FLIGHT:
			if flight_start_ground == TerrainGrid.INVALID_GRID_POINT \
					or flight_end_ground == TerrainGrid.INVALID_GRID_POINT:
				return TerrainGrid.INVALID_GRID_POINT
			var ground := flight_start_ground.lerp(flight_end_ground, flight_progress)
			if wind_visual_offset != Vector2.ZERO and is_instance_valid(terrain_grid):
				var drift := wind_visual_offset * sin(_current_flight_phase() * PI)
				ground += terrain_grid.projection.unproject(drift) \
						- terrain_grid.projection.unproject(Vector2.ZERO)
			return ground
		BallState.ROLLING:
			if _roll_waypoints_ground.size() >= 2:
				return _sample_roll_array(_roll_waypoints_ground, _roll_eased())
			if roll_start_ground == TerrainGrid.INVALID_GRID_POINT \
					or roll_end_ground == TerrainGrid.INVALID_GRID_POINT:
				return TerrainGrid.INVALID_GRID_POINT
			return roll_start_ground.lerp(roll_end_ground, _roll_eased())
		_:
			return rest_ground

## A new flight's ground track: the grid points the caller gave, or else the
## ground under the screen positions - the ball's own resting point for where
## it is struck from.
func _set_flight_ground(from_ground: Vector2, to_ground: Vector2) -> void:
	flight_start_ground = from_ground if from_ground != TerrainGrid.INVALID_GRID_POINT \
			else _resolve_ground(flight_start_pos, rest_ground)
	flight_end_ground = to_ground if to_ground != TerrainGrid.INVALID_GRID_POINT \
			else _resolve_ground(flight_end_pos, TerrainGrid.INVALID_GRID_POINT)

## The grid point under a screen position the caller gave no ground for: `hint`
## where it projects there, else the surface crossing nearest `hint`, a tile
## centre, or the surface the pixel shows (TerrainOcclusion.standing_point()).
func _resolve_ground(screen: Vector2, hint: Vector2) -> Vector2:
	if not is_instance_valid(terrain_grid):
		return TerrainGrid.INVALID_GRID_POINT
	if hint != TerrainGrid.INVALID_GRID_POINT \
			and terrain_grid.grid_point_to_screen(hint).distance_to(screen) <= GROUND_MATCH_PX:
		return hint
	return TerrainOcclusion.standing_point(terrain_grid, screen, hint, false)

## The tile a landing spot is on: the one under its ground point, where known -
## the front-most surface on its pixel can be a hill the ball came down behind.
func _tile_under(ground: Vector2, screen: Vector2) -> Vector2i:
	if ground != TerrainGrid.INVALID_GRID_POINT:
		return Vector2i(floori(ground.x), floori(ground.y))
	return terrain_grid.screen_to_grid(screen)

## Follow a move no flight or roll of the ball's own is making - main.gd
## carrying a resting ball across a view turn, a placement - as it is made, so
## the clip never waits for the next shot to catch up. Every step of a flight or
## a roll refreshes it already (_update_shadow()).
func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and _occlusion_active \
			and ball_state != BallState.IN_FLIGHT and ball_state != BallState.ROLLING \
			and global_position != _occlusion_position:
		_refresh_occlusion()

## Whether the shader is clipping this ball, against a grid that still exists.
func _occlusion_tracking() -> bool:
	return _occlusion_active and _occlusion_material != null and is_instance_valid(_occlusion_grid)

## Follow the course's terrain-occlusion switch, its sculpting and its view
## turns while in the scene tree.
func _watch_terrain_occlusion(watch: bool) -> void:
	var grid: TerrainGrid = null
	if watch and is_instance_valid(terrain_grid):
		grid = terrain_grid
	if not is_instance_valid(_occlusion_grid):
		_occlusion_grid = null  # Freed: its connections went with it.
	if grid != _occlusion_grid:
		if _occlusion_grid != null:
			if _occlusion_grid.terrain_occlusion_changed.is_connected(_on_terrain_occlusion_changed):
				_occlusion_grid.terrain_occlusion_changed.disconnect(_on_terrain_occlusion_changed)
			if _occlusion_grid.vertex_elevation_changed.is_connected(_on_vertex_elevation_changed):
				_occlusion_grid.vertex_elevation_changed.disconnect(_on_vertex_elevation_changed)
		_occlusion_grid = grid
		if grid != null:
			grid.terrain_occlusion_changed.connect(_on_terrain_occlusion_changed)
			grid.vertex_elevation_changed.connect(_on_vertex_elevation_changed)
	var rotating := EventBus.view_rotated.is_connected(_on_view_rotated_for_occlusion)
	if grid != null and not rotating:
		EventBus.view_rotated.connect(_on_view_rotated_for_occlusion)
	elif grid == null and rotating:
		EventBus.view_rotated.disconnect(_on_view_rotated_for_occlusion)
	refresh_terrain_occlusion()

## Clip the ball wherever a nearer hill covers it, as trees and golfers are
## clipped, while the course has relief and the graphics setting allows it (see
## TerrainGrid.terrain_occlusion_enabled()). Only a ball on the course's own
## canvas is clipped.
func refresh_terrain_occlusion() -> void:
	if not is_instance_valid(_occlusion_grid):
		_occlusion_grid = null
	var grid := _occlusion_grid
	_occlusion_active = is_inside_tree() and grid != null and grid.is_inside_tree() \
			and grid._course_surface != null and grid.terrain_occlusion_enabled() \
			and get_canvas() == grid.get_canvas()
	if _occlusion_active:
		if _occlusion_material == null:
			_occlusion_material = ShaderMaterial.new()
			_occlusion_material.shader = TERRAIN_SPRITE_OCCLUSION
			_occlusion_material.set_shader_parameter("occlusion_epsilon", TerrainOcclusion.BALL_EPSILON)
		grid._course_surface.configure_terrain_occlusion(_occlusion_material)
		_refresh_occlusion()
	_apply_occlusion_material()

## Wear the occlusion material on the whole ball: its polygons, a flight's
## motion blur, a splash, and the contact shadow on the ground under it.
func _apply_occlusion_material() -> void:
	material = _occlusion_material if _occlusion_active else null
	_use_parent_material_below(self)

static func _use_parent_material_below(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			(child as CanvasItem).use_parent_material = true
			_use_parent_material_below(child)

func _on_terrain_occlusion_changed(_enabled: bool) -> void:
	refresh_terrain_occlusion()

## A sculpt can raise the ground under a straight track (see _refresh_occlusion()).
func _on_vertex_elevation_changed(_vertex: Vector2i, _old: int, _new: int) -> void:
	if _occlusion_tracking() and not _occlusion_refresh_queued:
		_occlusion_refresh_queued = true
		call_deferred("_refresh_occlusion")

## A turn changes the projection, not the ground under the ball; main.gd moves
## the ball to where that ground is drawn now (_notification()).
func _on_view_rotated_for_occlusion(_orientation: int, _isometric: bool) -> void:
	if _occlusion_tracking():
		_occlusion_grid._course_surface.configure_terrain_occlusion(_occlusion_material)
		_refresh_occlusion()

## Stand the shader's ball on the grid point under it (ground_point()),
## measured from the ground under its contact shadow's foot (OCCLUSION_FOOT). A
## flight's arc is drawn over a straight track between its ends, and the
## ground can rise above that track in between, so the ball is measured from
## the higher of the two: it flies over a hill, never through it. (A roll is
## drawn on the ground already - see place_on_track().)
func _refresh_occlusion() -> void:
	_occlusion_refresh_queued = false
	_occlusion_position = global_position
	if not _occlusion_tracking():
		return
	var grid := _occlusion_grid
	var anchor := ground_point()
	var lift := 0.0
	if anchor == TerrainGrid.INVALID_GRID_POINT:
		# No known ground: nothing is taken to be in front of the ball.
		anchor = TerrainOcclusion.point_on_ray(grid, global_position, TerrainOcclusion.UNHIDDEN_T)
	else:
		lift = TerrainOcclusion.contact_reach(grid, anchor, OCCLUSION_FOOT)
		var arc := _current_arc_height() if ball_state == BallState.IN_FLIGHT else 0.0
		var track_t := grid.projection.project(anchor).y - (global_position.y + arc)
		lift += maxf(0.0, TerrainOcclusion.ground_t(grid, anchor) - track_t)
	_occlusion_anchor = anchor
	_occlusion_lift = lift
	_occlusion_material.set_shader_parameter("ground_grid", anchor)
	_occlusion_material.set_shader_parameter("ground_offset", Vector2(0.0, lift))

## Whether the terrain covers this ball's art at a world point: the test its
## occlusion shader runs.
func terrain_hides_point(world: Vector2) -> bool:
	if not _occlusion_tracking():
		return false
	if _occlusion_refresh_queued or global_position != _occlusion_position:
		_refresh_occlusion()
	return TerrainOcclusion.hides_ball(_occlusion_grid, _occlusion_anchor, _occlusion_lift, world)

func get_ball_info() -> Dictionary:
	return {
		"golfer_id": golfer_id,
		"position": grid_position,
		"state": ball_state,
		"world_position": global_position
	}

func destroy() -> void:
	queue_free()
