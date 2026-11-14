extends Node2D
class_name AimGuide
## AimGuide - Draws the owner's shot guide while they line up a shot: the intended
## flight arc, the carry point where the ball lands, and the roll that follows it.
##
## The guide is fed by `Golfer.preview_shot_to_rest()`, which solves the real
## deterministic shot model backwards from the chosen resting point. That solve
## remains terrain-, wind- and elevation-aware. The displayed path is deliberately
## normalized by shot type, though, so a given type keeps the same arc and rollout
## proportions over different lies and slopes. It is an aiming aid, not a promise
## that the live, terrain-aware swing will trace every displayed point exactly.
##
## Flight keeps the familiar bell curve and wind/shape bend. Straight, fade and
## draw share the standard profile; Backspin gets a higher arc and short reverse
## roll; Punch gets a low arc and longer forward roll. The flight and rollout are
## drawn as one continuous thin white line over a black shadow, with a faint
## black shadow track on the ground beneath the flight arc and no circles, dots,
## diamonds or other shapes along the line.
##
## Those profile values are the guide's contract with the rest of the UI: the
## shot-type buttons' legends (`ShotShapeDiagram`) are built from the same roll
## ratios, arc multipliers and bend factor, so the picture on a button and the
## guide that shot draws on the course cannot drift apart.

const GUIDE_Z_INDEX := 10

## Arc height as a fraction of the displayed carry distance.
const ARC_HEIGHT_RATIO := 0.3
const MAX_ARC_HEIGHT := 150.0
## Fade/draw mid-flight bend, as a fraction of the displayed flight distance.
const BEND_FACTOR := 0.06
## Nominal rollout as a fraction of carry length. These are guide-only profile
## values; real rollout still uses terrain, slope and shot execution physics.
const STANDARD_ROLL_RATIO := 0.08
const BACKSPIN_ROLL_RATIO := -0.05
const PUNCH_ROLL_RATIO := 0.12
## Arc height multiplier per shot shape: backspin lofts the flight, punch
## flattens it. Matches the `arc_scale` `Golfer.preview_shot()` reports.
const BACKSPIN_ARC_SCALE := 1.4
const PUNCH_ARC_SCALE := 0.3
const MAX_BACKSPIN_ROLL_TILES := 1.5
const ROLL_SAMPLE_SPACING_TILES := 0.5

const SHOT_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const SHOT_LINE_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const SHOT_LINE_GLOW_COLOR := SHOT_LINE_SHADOW_COLOR
const GROUND_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const BACKSPIN_COLOR := Color(0.95, 0.72, 1.0, 0.95)
const BLOCKED_COLOR := Color(1.0, 0.42, 0.32, 0.95)
const OUT_OF_RANGE_COLOR := Color(1.0, 0.55, 0.45, 0.85)
const LABEL_SHADOW_COLOR := Color(0, 0, 0, 0.85)

const SHOT_LINE_WIDTH := 1.4
const SHOT_SHADOW_WIDTH := 2.8
const GROUND_LINE_WIDTH := 1.0

const ARC_STEPS := 28
const LABEL_FONT_SIZE := 13
const SMALL_FONT_SIZE := 12

## Latest `Golfer.preview_shot_to_rest()` payload; empty while no shot is being lined up.
var preview: Dictionary = {}

func _ready() -> void:
	z_index = GUIDE_Z_INDEX

## Show the guide for a preview payload. An empty payload clears it.
func show_preview(new_preview: Dictionary) -> void:
	if new_preview.is_empty():
		clear()
		return
	preview = new_preview
	queue_redraw()

func clear() -> void:
	if preview.is_empty():
		return
	preview = {}
	queue_redraw()

## Project one preview into screen-space guide geometry. Arc and rollout lengths
## are derived from the selected shot type and the origin-to-rest distance, rather
## than the simulated carry/path. Elevation is applied to the flight chord, then
## removed from the rollout leg so the displayed roll remains a stable proportion.
## Pure and static so tests can assert the shape without a live mouse or draw pass.
## Returns {} when the preview (or the terrain grid) is unusable, or when the
## golfer's own tile is off the map.
static func build_geometry(grid: TerrainGrid, aim_preview: Dictionary,
		arc_steps: int = ARC_STEPS) -> Dictionary:
	if grid == null or aim_preview.is_empty():
		return {}
	var origin: Vector2 = aim_preview.get("origin", Vector2.ZERO)
	var actual_carry: Vector2 = aim_preview.get("carry", origin)
	var rest: Vector2 = aim_preview.get("rest", actual_carry)
	# Only the golfer's own tile has to be on the map. The drawn path comes from the
	# origin-to-rest chord, so a physical carry that came down past the rim (aiming at
	# a rim vertex, say) is no reason to draw nothing for an anchor the player picked.
	if not grid.is_valid_position(Vector2i(origin.round())):
		return {}

	var origin_screen := grid.grid_to_screen_precise(origin)
	var rest_screen := grid.grid_to_screen_precise(rest)
	var aim_screen := grid.grid_to_screen_precise(aim_preview.get("aim", origin))
	var target_screen := grid.grid_to_screen_precise(aim_preview.get("target", rest))
	var raw_target_screen := grid.grid_to_screen_precise(aim_preview.get("raw_target", rest))

	# Work out shot proportions in the flat projected plane. This makes the guide's
	# height and rollout independent of intervening terrain and elevation changes.
	var origin_plane := grid.projection.project(origin + Vector2(0.5, 0.5))
	var rest_plane := grid.projection.project(rest + Vector2(0.5, 0.5))
	var flat_delta := rest_plane - origin_plane
	var flat_distance := flat_delta.length()
	var grid_delta := rest - origin
	var grid_distance := grid_delta.length()
	if flat_distance <= 0.001 or grid_distance <= 0.001:
		return {}

	var shape := _shape_for_preview(aim_preview)
	var roll_ratio := roll_ratio_for_shape(shape)
	# `roll_ratio` is roll/carry. For backspin, the selected rest is behind the
	# carry point, so the nominal carry is placed just beyond the target anchor.
	var guide_roll_tiles := grid_distance * absf(roll_ratio) / (1.0 + roll_ratio)
	if roll_ratio < 0.0:
		guide_roll_tiles = minf(guide_roll_tiles, MAX_BACKSPIN_ROLL_TILES)
	var direction_grid := grid_delta / grid_distance
	var guide_carry_grid := rest - direction_grid * guide_roll_tiles
	if roll_ratio < 0.0:
		guide_carry_grid = rest + direction_grid * guide_roll_tiles

	var carry_plane := grid.projection.project(guide_carry_grid + Vector2(0.5, 0.5))
	var carry_distance := origin_plane.distance_to(carry_plane)
	# Apply the whole endpoint height change during flight. The rollout is then a
	# flat projected segment which still meets the actual elevated rest marker.
	var endpoint_height_delta := (rest_screen - origin_screen) - flat_delta
	var carry_screen := origin_screen + (carry_plane - origin_plane) + endpoint_height_delta

	var arc_scale := _arc_scale_for_shape(aim_preview, shape)
	var max_height := minf(carry_distance * ARC_HEIGHT_RATIO, MAX_ARC_HEIGHT) * arc_scale

	# Mid-flight shape bend. Convert only the flat grid offset, so terrain height
	# along the flight path cannot change the shot's apparent shape.
	var bend_screen := Vector2.ZERO
	var bend_deg: float = aim_preview.get("shape_bend_deg", 0.0)
	if absf(bend_deg) > 0.001:
		var flight_delta := guide_carry_grid - origin
		var bend_grid := Vector2(-flight_delta.y, flight_delta.x) * (-signf(bend_deg)) * BEND_FACTOR
		bend_screen = grid.projection.project(bend_grid) - grid.projection.project(Vector2.ZERO)

	var wind_drift := _wind_drift(grid, origin_plane, carry_plane)
	var arc := PackedVector2Array()
	var ground_track := PackedVector2Array()
	var steps := maxi(arc_steps, 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var swell := sin(t * PI)
		# Keep the ground reference smooth too: terrain under the shot must not
		# redraw the guide into a different shape from one tile to the next.
		ground_track.append(origin_screen.lerp(carry_screen, t) + bend_screen * swell)
		# Bend and wind swell through mid-flight and decay to the nominal carry.
		arc.append(origin_screen.lerp(carry_screen, t) + bend_screen * swell
			+ wind_drift * swell - Vector2(0.0, max_height * swell))

	var roll := PackedVector2Array()
	var roll_steps := maxi(1, ceili(guide_roll_tiles / ROLL_SAMPLE_SPACING_TILES))
	for i in range(roll_steps + 1):
		var t := float(i) / float(roll_steps)
		roll.append(carry_screen.lerp(rest_screen, t))

	# One continuous guide path, from the golfer, through flight and nominal roll.
	var trajectory := arc.duplicate()
	for i in range(1, roll.size()):
		trajectory.append(roll[i])

	return {
		"origin": origin_screen,
		"aim": aim_screen,
		"target": target_screen,
		"raw_target": raw_target_screen,
		"anchor_type": str(aim_preview.get("anchor_type", "center")),
		"carry": carry_screen,
		"physical_carry": grid.grid_to_screen_precise(actual_carry),
		"guide_carry_grid": guide_carry_grid,
		"rest": rest_screen,
		"arc": arc,
		"ground_track": ground_track,
		"roll": roll,
		"trajectory": trajectory,
		"apex_height": max_height,
		"carry_distance": carry_distance,
		"guide_roll_distance_tiles": guide_roll_tiles,
		"guide_carry_yards": grid.calculate_distance_yards_precise(origin, guide_carry_grid),
		"guide_roll_yards": grid.calculate_distance_yards_precise(guide_carry_grid, rest),
		"guide_backspin": shape == 3,
		"shape": shape,
	}

static func _shape_for_preview(aim_preview: Dictionary) -> int:
	if aim_preview.has("shape"):
		return int(aim_preview.get("shape", 0))
	if aim_preview.get("punch", false):
		return 4
	if aim_preview.get("is_backspin", false):
		return 3
	return 0

## The guide's rollout profile for a shot shape (0 straight, 1 fade, 2 draw,
## 3 high backspin, 4 low punch), as roll/carry: a short run forward, a longer
## run for the punch, and a reversal for backspin. Shared with the shot-type
## buttons' `ShotShapeDiagram`, so the legend on a button and the guide on the
## course always roll the same way.
static func roll_ratio_for_shape(shape: int) -> float:
	match shape:
		3:
			return BACKSPIN_ROLL_RATIO
		4:
			return PUNCH_ROLL_RATIO
		_:
			return STANDARD_ROLL_RATIO

## The guide's arc height multiplier for a shot shape: backspin lofts the
## flight, punch flattens it, everything else keeps the standard bell curve.
## Shared with `ShotShapeDiagram` for the same reason as the roll profile.
static func arc_scale_for_shape(shape: int) -> float:
	match shape:
		3:
			return BACKSPIN_ARC_SCALE
		4:
			return PUNCH_ARC_SCALE
		_:
			return 1.0

static func _arc_scale_for_shape(aim_preview: Dictionary, shape: int) -> float:
	if aim_preview.has("shape"):
		return arc_scale_for_shape(shape)
	# Older previews carry the multiplier instead of the shape.
	return float(aim_preview.get("arc_scale", 1.0))

## Cosmetic mid-flight wind drift on the guide's flat-plane path. Excluding
## elevation here keeps the same shot type's curve stable over sculpted terrain.
static func _wind_drift(grid: TerrainGrid, origin_screen: Vector2, carry_screen: Vector2) -> Vector2:
	if GameManager.wind_system == null:
		return Vector2.ZERO
	var shot_direction := (carry_screen - origin_screen).normalized()
	if shot_direction == Vector2.ZERO:
		return Vector2.ZERO
	var distance_tiles := origin_screen.distance_to(carry_screen) / grid.tile_width
	# The guide never runs for putters, so any non-zero wind sensitivity club gives
	# the same crosswind direction; Ball uses the club actually played.
	var displacement := GameManager.wind_system.get_wind_displacement(shot_direction, distance_tiles, Golfer.Club.FAIRWAY_WOOD)
	return displacement * grid.tile_width * 0.5

func _draw() -> void:
	_paint(self, GameManager.terrain_grid)

## Everything the guide draws on `canvas` (`self` in the game, a recorder in a
## test): black ground shadow first, then the aiming line's black shadow and
## thin white stroke through flight and rollout, with no shapes on the line.
func _paint(canvas, grid: TerrainGrid = GameManager.terrain_grid) -> void:
	if preview.is_empty():
		return
	var geometry := build_geometry(grid, preview)
	if geometry.is_empty():
		return

	var backspin: bool = geometry.get("guide_backspin", preview.get("is_backspin", false))
	var blocked: bool = preview.get("blocked", false)
	var status_color := BLOCKED_COLOR if blocked else (BACKSPIN_COLOR if backspin else SHOT_LINE_COLOR)

	# Black shadow on the ground beneath the flight arc, then the aiming line's
	# black shadow underlay and thin white stroke from take-off through rollout.
	# No circles, dots, diamonds or other shapes are drawn on the line.
	var ground_points := _to_local_many(geometry.ground_track)
	var trajectory_points := _to_local_many(geometry.trajectory)
	canvas.draw_polyline(ground_points, GROUND_COLOR, GROUND_LINE_WIDTH, true)
	canvas.draw_polyline(trajectory_points, SHOT_LINE_SHADOW_COLOR, SHOT_SHADOW_WIDTH, true)
	canvas.draw_polyline(trajectory_points, SHOT_LINE_COLOR, SHOT_LINE_WIDTH, true)

	if canvas == self:
		_draw_labels(geometry, status_color)

## Approximate guide distances above the ball, plus rollout at the rest point.
func _draw_labels(geometry: Dictionary, status_color: Color) -> void:
	var font := ThemeDB.fallback_font
	var club_name: String = preview.get("club_name", "Shot")
	var carry_yards: int = geometry.get("guide_carry_yards", preview.get("carry_yards", 0))
	var roll_yards: int = geometry.get("guide_roll_yards", preview.get("roll_yards", 0))
	var backspin: bool = geometry.get("guide_backspin", preview.get("is_backspin", false))
	var shape: int = int(geometry.get("shape", preview.get("shape", 0)))
	var head := "%s · ~%d yd carry" % [club_name, carry_yards]
	if shape == 4 or preview.get("punch", false):
		head += " · punch"
	var shape_bend: float = preview.get("shape_bend_deg", 0.0)
	if absf(shape_bend) > 0.001:
		head += " · fade" if shape_bend > 0.0 else " · draw"
	elif shape == 3:
		head += " · backspin"
	# Explain why the guide stops short of the requested resting anchor.
	if bool(preview.get("range_limited", preview.get("clamped", false))):
		head += " · out of range"
	elif bool(preview.get("clamped", false)):
		head += " · terrain limited"
	_draw_outlined_text(font, to_local(geometry.origin) + Vector2(-6.0, -18.0), head, Color(1, 1, 1, 0.92))

	# Roll captions stack under the resting point: nominal guide distance, then
	# any hazard the real preview predicts. Short rolls skip the caption.
	var rest := to_local(geometry.rest)
	var caption_lines: Array[Dictionary] = []
	if roll_yards >= 5:
		caption_lines.append({
			"text": "backspin ~%d yd" % roll_yards if backspin else "roll ~%d yd" % roll_yards,
			"color": status_color,
			"size": LABEL_FONT_SIZE,
		})
	if bool(preview.get("blocked", false)):
		caption_lines.append({
			"text": "%s!" % str(preview.get("blocked_terrain", "hazard")).to_lower(),
			"color": BLOCKED_COLOR,
			"size": SMALL_FONT_SIZE,
		})
	for i in caption_lines.size():
		var line: Dictionary = caption_lines[i]
		_draw_outlined_text(font, rest + Vector2(10.0, 18.0 + 17.0 * i), line.text, line.color, line.size)

func _draw_outlined_text(font: Font, pos: Vector2, text: String, color: Color,
		font_size: int = LABEL_FONT_SIZE) -> void:
	font.draw_string_outline(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, 4, LABEL_SHADOW_COLOR)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _to_local_many(points: PackedVector2Array) -> PackedVector2Array:
	var local_points := PackedVector2Array()
	for point in points:
		local_points.append(to_local(point))
	return local_points
