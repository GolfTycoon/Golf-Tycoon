extends Control
class_name ShotShapeDiagram
## The picture on a shot-type button: that shot's flight arc, the carry point
## where it lands, and the roll that follows it — the aim guide's own profile,
## shrunk into the button.
##
## The five buttons sit side by side, so the legend's job is comparison. Every
## shot type is drawn from one shared heading at one shared scale, from the
## guide's own numbers (`AimGuide.roll_ratio_for_shape()`,
## `AimGuide.arc_scale_for_shape()`, `AimGuide.ARC_HEIGHT_RATIO` and
## `AimGuide.BEND_FACTOR`, with the bend in `Golfer.shape_bend_degrees()`), and
## the projection is the course's own 2:1 isometric mapping. Backspin therefore
## really does climb highest and roll back toward the ball, punch really does
## stay flat and run on, and fade and draw really are mirror images of the
## straight flight — the button cannot drift away from the shot it names.
##
## Two gains are legend-only, because a 44px button is not a 400px guide: the
## rollout and the 8° bend are multiplied up so both read at button size. The
## ratios *between* shot types are untouched, so the row still compares. The
## guide's absolute arc cap (`AimGuide.MAX_ARC_HEIGHT`) does not apply here: the
## legend scales itself to the slot it is given instead.
##
## `build_geometry()` is pure and drawing goes through `_paint(canvas)`, like
## `SetupGlyph` and `CoursePlanPreview`, so a test can assert the shape of a
## legend — or hand in a recorder — without a live button or a draw pass.

## The shot types the legend knows, in `Golfer.player_shape` order.
const SHOT_COUNT := 5
## Grid heading the legend flies: up and to the right across the course view,
## the way a ball struck toward grid (1, -4) runs on screen. One heading for all
## five buttons, so the only thing that differs between them is the shot.
const LEGEND_HEADING := Vector2(1, -4)
## The slot a button reserves for its legend. The profile is fitted into it at
## the shared scale, so a wider slot only centres the drawing.
const DIAGRAM_WIDTH := 44.0
const DIAGRAM_HEIGHT := 26.0
const DIAGRAM_SIZE := Vector2(DIAGRAM_WIDTH, DIAGRAM_HEIGHT)
## Legend-only gains (see the header): the guide's rollout is 8% of a shot and
## its bend 6% of the flight, which read across a course and vanish on a button.
const ROLL_GAIN := 2.5
const BEND_GAIN := 3.0
## Sampling of the flight, and the dots that mark the rollout after it.
const ARC_STEPS := 20
const ROLL_DOTS := 3
## Stroke weights and marker radii, in slot pixels.
const ARC_WIDTH := 1.6
const ROLL_WIDTH := 1.4
const GROUND_WIDTH := 1.0
const DOT_RADIUS := 1.1
const BALL_RADIUS := 1.4
const CARRY_RING_RADIUS := 2.4
const CARRY_RING_SEGMENTS := 12
## Longest back arrowhead, and the share of a short roll one may take.
const ARROW_HEAD := 3.2
const ARROW_SHARE := 0.7
const ARROW_SPREAD := 0.62
## The guide's ground reference at 20% alpha reads across a course; on a dark
## button face it needs a little more to be seen at all.
const GROUND_ALPHA := 0.34
const MUTED_ALPHA := 0.8

## Shot type this legend pictures (0 straight … 4 low punch).
var shape := 0:
	set(value):
		var next := clampi(value, 0, SHOT_COUNT - 1)
		if shape == next:
			return
		shape = next
		queue_redraw()

## False draws the legend in the row's muted grey: the shot is one the current
## lie forbids, or the owner is waiting for their turn. The picture stays — a
## greyed shot still teaches what it would have flown.
var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		queue_redraw()

func _init() -> void:
	size = DIAGRAM_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ============================================================================
# PROFILE (pure; projected units, one unit of flight = one tile of rest)
# ============================================================================

## The course's own 2:1 isometric mapping (see `GridProjection.project()`), so
## the legend tilts and bends the way the same shot does across the course view.
static func project(grid_offset: Vector2) -> Vector2:
	return Vector2(grid_offset.x - grid_offset.y, (grid_offset.x + grid_offset.y) * 0.5)

## One shot type's profile, in units where the ball travels one unit from where
## it lies to where it comes to rest:
##   carry_length  the flight, roll included
##   roll_length   the run after landing, as a share of that one unit
##   arc_scale     the guide's height multiplier for the shape
##   bend_deg      the shape's bend (±8° for fade and draw, 0 for the rest)
##   reversed      true when the roll runs back toward the ball
static func profile(shot: int) -> Dictionary:
	var roll_ratio := AimGuide.roll_ratio_for_shape(shot)
	var roll_length := absf(roll_ratio) / (1.0 + roll_ratio) * ROLL_GAIN
	# The roll is measured back from the rest point, so a forward roll lands
	# short of it and a reversed one lands past it — the way AimGuide places the
	# carry ring it hands its rollout over to.
	var carry_length := 1.0 + roll_length if roll_ratio < 0.0 else 1.0 - roll_length
	return {
		"shape": shot,
		"roll_ratio": roll_ratio,
		"arc_scale": AimGuide.arc_scale_for_shape(shot),
		"bend_deg": Golfer.shape_bend_degrees(shot),
		"carry_length": carry_length,
		"roll_length": roll_length,
		"reversed": roll_ratio < 0.0,
	}

## The legend's path for one shot type, in projected units: the faint ground
## reference, the climbing arc, the carry point and the roll that follows it.
static func unit_path(shot: int) -> Dictionary:
	var data := profile(shot)
	var heading := LEGEND_HEADING.normalized()
	var across := Vector2(-heading.y, heading.x)
	var carry_length := float(data["carry_length"])
	var carry_point := project(heading * carry_length)
	var apex := AimGuide.ARC_HEIGHT_RATIO * carry_point.length() * float(data["arc_scale"])
	# The bend is taken across the flight and projected, exactly as AimGuide
	# takes it across `flight_delta`: a fade bows one way off the ground line, a
	# draw the same distance the other.
	var bend := project(across) * (-signf(float(data["bend_deg"]))) * AimGuide.BEND_FACTOR \
		* carry_length * BEND_GAIN
	var arc := PackedVector2Array()
	var ground := PackedVector2Array()
	for i in ARC_STEPS + 1:
		var t := float(i) / float(ARC_STEPS)
		var swell := sin(t * PI)
		var along := carry_point * t + bend * swell
		ground.append(along)
		# The climb is straight up the screen, as it is on the course: the guide
		# lifts its arc vertically out of the projected ground track.
		arc.append(along - Vector2(0.0, apex * swell))
	return {
		"origin": Vector2.ZERO,
		"carry": carry_point,
		"rest": project(heading),
		"arc": arc,
		"ground": ground,
		"roll": PackedVector2Array([carry_point, project(heading)]),
		"apex_height": apex,
		"bend": bend,
		"reversed": bool(data["reversed"]),
	}

## The frame every shot type shares: the union of all five profiles. One scale
## for all of them is what makes the row comparable — backspin climbs higher
## than punch because it does, not because its legend fills its slot better.
static func profile_bounds() -> Rect2:
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for shot in SHOT_COUNT:
		var path := unit_path(shot)
		for key in ["arc", "ground", "roll"]:
			var points: PackedVector2Array = path[key]
			for point in points:
				bounds = bounds.expand(point)
	return bounds

## How the shared frame maps into `box`: one uniform scale, centred. A wider box
## only centres the drawing, a narrower one shrinks it whole, so a legend never
## distorts and never spills out of its button. Empty when there is no area.
static func fit_transform(box: Rect2) -> Dictionary:
	var bounds := profile_bounds()
	if box.size.x <= 0.0 or box.size.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {}
	var fit_scale := minf(box.size.x / bounds.size.x, box.size.y / bounds.size.y)
	if fit_scale <= 0.0:
		return {}
	return {
		"scale": fit_scale,
		"offset": box.position + (box.size - bounds.size * fit_scale) * 0.5 - bounds.position * fit_scale,
	}

## The legend for `shot` fitted into `box`, in box-local pixels:
##   origin, carry, rest  the ball, the landing and where it comes to rest
##   ground, arc, roll    the faint reference, the flight and the rollout
##   roll_dots, arrow     the rollout's dots, and backspin's arrow back to it
##   apex_height, roll_length, bend, reversed, scale  the drawn proportions
## Returns {} when `box` has no area to draw in.
static func build_geometry(shot: int, box: Rect2) -> Dictionary:
	var clamped := clampi(shot, 0, SHOT_COUNT - 1)
	var fit := fit_transform(box)
	if fit.is_empty():
		return {}
	var fit_scale := float(fit["scale"])
	var offset: Vector2 = fit["offset"]
	var path := unit_path(clamped)
	var roll := _fit_points(path["roll"], fit_scale, offset)
	var dots := PackedVector2Array()
	for i in ROLL_DOTS:
		dots.append(roll[0].lerp(roll[1], float(i + 1) / float(ROLL_DOTS)))
	return {
		"shape": clamped,
		"origin": offset,
		"carry": roll[0],
		"rest": roll[1],
		"arc": _fit_points(path["arc"], fit_scale, offset),
		"ground": _fit_points(path["ground"], fit_scale, offset),
		"roll": roll,
		"roll_dots": dots,
		"arrow": _arrow(roll[0], roll[1], bool(path["reversed"])),
		"apex_height": float(path["apex_height"]) * fit_scale,
		"carry_length": Vector2(path["carry"]).length() * fit_scale,
		"roll_length": roll[0].distance_to(roll[1]),
		"bend": Vector2(path["bend"]) * fit_scale,
		"reversed": bool(path["reversed"]),
		"scale": fit_scale,
	}

## Backspin's arrow back toward the ball, as three points (barb, tip, barb) for
## one polyline — the guide's own back arrow, at legend size. Empty for a roll
## that runs forward, where the dots alone say which way the ball travelled.
static func _arrow(carry: Vector2, rest: Vector2, reversed: bool) -> PackedVector2Array:
	if not reversed:
		return PackedVector2Array()
	var back := rest - carry
	if back.length_squared() <= 0.000001:
		return PackedVector2Array()
	var direction := back.normalized()
	var head := minf(ARROW_HEAD, back.length() * ARROW_SHARE)
	var across := Vector2(-direction.y, direction.x) * head * ARROW_SPREAD
	return PackedVector2Array([rest - direction * head + across, rest, rest - direction * head - across])

static func _fit_points(points: PackedVector2Array, fit_scale: float, offset: Vector2) -> PackedVector2Array:
	var fitted := PackedVector2Array()
	fitted.resize(points.size())
	for i in points.size():
		fitted[i] = offset + points[i] * fit_scale
	return fitted

# ============================================================================
# COLOURS
# ============================================================================

## The guide's own hues: gold for the flight, violet for the backspin reversal
## (see `AimGuide`). A shot the lie forbids — or a row waiting for its turn —
## draws the same picture in the UI's muted grey.
static func line_color(shot: int, is_enabled: bool) -> Color:
	if not is_enabled:
		return Color(UIConstants.COLOR_TEXT_MUTED, MUTED_ALPHA)
	return AimGuide.BACKSPIN_COLOR if shot == 3 else AimGuide.SHOT_LINE_COLOR

## The faint ground reference under the flight, in the same hue.
static func ground_color(is_enabled: bool) -> Color:
	var base: Color = UIConstants.COLOR_TEXT_MUTED if not is_enabled else AimGuide.SHOT_LINE_COLOR
	return Color(base.r, base.g, base.b, GROUND_ALPHA)

static func ball_color(is_enabled: bool) -> Color:
	return UIConstants.COLOR_TEXT if is_enabled else UIConstants.COLOR_TEXT_MUTED

# ============================================================================
# DRAWING
# ============================================================================

func _draw() -> void:
	_paint(self)

## Everything the legend draws, on `canvas` — the control itself in the game, a
## recorder in a test. Ground reference first, then flight, rollout and markers,
## the order and the hues the guide uses on the course.
func _paint(canvas) -> void:
	var geometry := build_geometry(shape, Rect2(Vector2.ZERO, size))
	if geometry.is_empty():
		return
	var line := line_color(shape, enabled)
	var ground: PackedVector2Array = geometry["ground"]
	var arc: PackedVector2Array = geometry["arc"]
	var roll: PackedVector2Array = geometry["roll"]
	var dots: PackedVector2Array = geometry["roll_dots"]
	var arrow: PackedVector2Array = geometry["arrow"]
	var carry: Vector2 = geometry["carry"]
	var origin: Vector2 = geometry["origin"]
	canvas.draw_polyline(ground, ground_color(enabled), GROUND_WIDTH, true)
	canvas.draw_polyline(arc, line, ARC_WIDTH, true)
	canvas.draw_polyline(roll, line, ROLL_WIDTH, true)
	for dot in dots:
		canvas.draw_circle(dot, DOT_RADIUS, line)
	if arrow.size() >= 3:
		canvas.draw_polyline(arrow, line, ROLL_WIDTH, true)
	canvas.draw_arc(carry, CARRY_RING_RADIUS, 0.0, TAU, CARRY_RING_SEGMENTS, line, ROLL_WIDTH, true)
	canvas.draw_circle(origin, BALL_RADIUS, ball_color(enabled))
