extends Node2D
class_name Ball
## Ball - Represents a golf ball in flight or at rest

enum BallState {
	AT_REST,      # Ball is sitting still
	IN_FLIGHT,    # Ball is flying through the air
	ROLLING,      # Ball is rolling on ground after landing
	IN_WATER,     # Ball is in water hazard
	OUT_OF_BOUNDS # Ball is OB
}

## The one size a golf ball is drawn at, in screen pixels. Every state (at rest,
## in flight, in water, out of bounds) draws off this so the ball keeps a single
## silhouette — and the cup cut under the flag is sized from it too, so the hole
## in the ground is exactly as wide as the ball that drops into it
## (see CupOverlay.hole_radius()).
const BALL_RADIUS: float = 2.5
## Airborne the ball is drawn a touch larger so it stays visible against the sky;
## the flight depth scale multiplies this, never BALL_RADIUS.
const FLIGHT_RADIUS: float = 3.2
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
## Darkness of the contact shadow on the ground. It is a lighter touch than a
## prop's contact shadow because a ball is small and a full-strength blob would
## read as a second ball.
const SHADOW_ALPHA: float = 0.3
## In the air the shadow stays on the ground and tightens to this fraction of
## its resting size, and fades to this fraction of its resting darkness, at the
## top of the arc. Both settle back to 1 as the ball comes down.
const SHADOW_AIRBORNE_SCALE: float = 0.55
const SHADOW_AIRBORNE_ALPHA: float = 0.5

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
## How far the ball is lifted above its own ground track, in screen pixels. The
## flight arc moves the ball's node upward; its shadow ignores that offset so
## it stays on the ground the ball is flying over.
var _shadow_lift: float = 0.0

signal ball_landed(landing_pos: Vector2i)
signal ball_state_changed(old_state: BallState, new_state: BallState)
signal ball_landed_in_bunker(landing_pos: Vector2i)
signal ball_landed_in_water(landing_pos: Vector2i)

func _ready() -> void:
	z_index = 100  # Render above terrain and entities
	_update_visual()  # Builds the ground shadow first, then the ball
	# The Display page can switch contact shadows off, and the ball is already
	# on the course, so follow the setting rather than deciding once at birth.
	if not PerformanceSettings.profile_changed.is_connected(_on_graphics_settings_changed):
		PerformanceSettings.profile_changed.connect(_on_graphics_settings_changed)

func _exit_tree() -> void:
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

func set_position_in_grid(pos: Vector2i) -> void:
	grid_position = pos
	if terrain_grid:
		var world_pos = terrain_grid.grid_to_screen_center(pos)
		global_position = world_pos
	_update_visual()

## Configure rollout to play after the current flight lands.
## carry_screen is where the ball first hits ground (should match flight_end_pos).
## final_screen is where it comes to rest after rolling.
func set_rollout(final_screen: Vector2, duration: float) -> void:
	roll_end_pos = final_screen
	roll_duration = duration
	_has_pending_rollout = true

## Start a flight animation from one position to another
func start_flight(from_grid: Vector2i, to_grid: Vector2i, duration: float = 1.5, is_putt: bool = false, wind_offset: Vector2 = Vector2.ZERO) -> void:
	if not terrain_grid:
		return

	grid_position = from_grid
	flight_start_pos = terrain_grid.grid_to_screen_center(from_grid)
	flight_end_pos = terrain_grid.grid_to_screen_center(to_grid)
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

	_change_state(BallState.IN_FLIGHT)
	global_position = flight_start_pos

## Start a flight animation using precise screen coordinates (for sub-tile putting)
func start_flight_screen(from_screen: Vector2, to_screen: Vector2, duration: float = 1.5, is_putt: bool = false) -> void:
	flight_start_pos = from_screen
	flight_end_pos = to_screen
	flight_progress = 0.0
	flight_duration = duration

	if is_putt:
		flight_max_height = 0.0
		wind_visual_offset = Vector2.ZERO  # No wind drift on putts
	else:
		var distance = flight_start_pos.distance_to(flight_end_pos)
		flight_max_height = min(distance * 0.3, 150.0)

	_change_state(BallState.IN_FLIGHT)
	global_position = flight_start_pos

## Start a flight animation with arc using precise screen coordinates (for sub-tile shots)
func start_flight_screen_with_arc(from_screen: Vector2, to_screen: Vector2, duration: float = 1.5, wind_offset: Vector2 = Vector2.ZERO) -> void:
	flight_start_pos = from_screen
	flight_end_pos = to_screen
	flight_progress = 0.0
	flight_duration = duration

	var distance = flight_start_pos.distance_to(flight_end_pos)
	flight_max_height = min(distance * 0.3, 150.0)
	wind_visual_offset = wind_offset

	_change_state(BallState.IN_FLIGHT)
	global_position = flight_start_pos

func _process_flight(delta: float) -> void:
	flight_progress += delta / flight_duration

	if flight_progress >= 1.0:
		# Flight complete - ball hits the ground
		flight_progress = 1.0
		global_position = flight_end_pos

		# Update grid position to carry spot
		if terrain_grid:
			grid_position = terrain_grid.screen_to_grid(flight_end_pos)

		scale = Vector2.ONE  # Reset scale from flight
		_shadow_lift = 0.0   # Back on the ground, under the ball again

		# Spawn impact effect at the carry spot (where ball first hits ground)
		_spawn_landing_impact()

		# Check if rollout was configured — if so, start rolling instead of landing
		if _has_pending_rollout and roll_end_pos.distance_to(flight_end_pos) > 1.0:
			_has_pending_rollout = false
			_start_rollout()
		else:
			_has_pending_rollout = false
			_land_ball()
		return

	# Parabolic arc animation
	var linear_pos = flight_start_pos.lerp(flight_end_pos, flight_progress)
	var arc_height = sin(flight_progress * PI) * flight_max_height

	# Apply wind visual drift as a bell curve: peaks at mid-flight, smoothly
	# returns to zero at landing so the ball arrives at the correct position
	var wind_drift = wind_visual_offset * sin(flight_progress * PI)

	global_position = linear_pos - Vector2(0, arc_height) + wind_drift

	# Update visual scale for depth perception (skip for putts rolling on ground)
	if flight_max_height > 0.0:
		var scale_factor = 1.0 + (arc_height / flight_max_height) * 0.5
		scale = Vector2(scale_factor, scale_factor)

	# The ball's node has climbed with the arc; the shadow is pushed back down
	# by the same amount so it stays on the ground the ball is flying over.
	_shadow_lift = arc_height
	_update_shadow()

## Begin rollout animation from current position to roll_end_pos
func _start_rollout() -> void:
	roll_start_pos = global_position
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

	# Ease-out deceleration: ball slows down as it rolls
	var eased_t = 1.0 - pow(1.0 - roll_progress, 2.0)
	global_position = roll_start_pos.lerp(roll_end_pos, eased_t)

func _finish_rollout() -> void:
	global_position = roll_end_pos
	if terrain_grid:
		grid_position = terrain_grid.screen_to_grid(roll_end_pos)
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
	ball_state_changed.emit(old_state, new_state)
	_update_visual()

func _update_visual() -> void:
	# The shadow is created once and kept first, beneath the visual, so it is
	# never rebuilt with the ball's shape and never paints over it.
	_ensure_ground_shadow()

	# Remove existing visual if it exists
	if has_node("Visual"):
		get_node("Visual").queue_free()

	var visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)

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

	_update_shadow()

## Build the ball's one contact shadow. It is the same kind of ground contact
## the props get, and it goes with them when shadows are switched off on the
## Display page.
func _ensure_ground_shadow() -> void:
	if _ground_shadow != null and is_instance_valid(_ground_shadow):
		return

	_ground_shadow = Polygon2D.new()
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.polygon = ellipse_polygon(SHADOW_RADII * BALL_RADIUS)
	_ground_shadow.color = Color(0, 0, 0, SHADOW_ALPHA)
	_ground_shadow.visible = PerformanceSettings.contact_shadows_enabled()
	add_child(_ground_shadow)
	move_child(_ground_shadow, 0)

## Place the contact shadow on the ground under the ball.
##
## At rest it is a soft ellipse at the ball's foot. In flight the ball's node
## climbs with the arc and grows with the depth scale, so the shadow is pushed
## back down by the arc height and divided through by that scale: it stays on
## the ground beneath the ball's flight path at its normal size, tightening and
## fading as the ball rises instead of flying away with it.
func _update_shadow() -> void:
	if _ground_shadow == null or not is_instance_valid(_ground_shadow):
		return

	_ground_shadow.visible = PerformanceSettings.contact_shadows_enabled()
	if not _ground_shadow.visible:
		return

	var lift_ratio := 0.0
	if ball_state == BallState.IN_FLIGHT and flight_max_height > 0.0:
		lift_ratio = clampf(_shadow_lift / flight_max_height, 0.0, 1.0)

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

func get_ball_info() -> Dictionary:
	return {
		"golfer_id": golfer_id,
		"position": grid_position,
		"state": ball_state,
		"world_position": global_position
	}

func destroy() -> void:
	queue_free()
