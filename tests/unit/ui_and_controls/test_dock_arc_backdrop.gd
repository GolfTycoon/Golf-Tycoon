extends GameTest
## DockArcBackdrop: the bottom-left corner's fan-shaped backdrop. The art
## is a generated pixel image shaped around the dock medallions' arc, so
## the pixels themselves are the contract - turf below the rim, air above
## it, the rim banded ink/trim/bevel/sheen in the section's colour. These
## tests read the generated images pixel by pixel, the same way the
## PixelButtonStyle tests read the frames, using the dock's own layout
## constants so a layout change that breaks the fan breaks a test.


## Medallion circles (centre, radius packed as Vector3) from the dock's
## layout constants, for one row of buttons.
func _row(positions: Array, size_of: Callable) -> Array:
	var row: Array = []
	for i in positions.size():
		var d: float = size_of.call(i)
		var p: Vector2 = positions[i]
		row.append(Vector3(p.x + d * 0.5, p.y + d * 0.5, d * 0.5))
	return row


func _outer() -> Array:
	return _row(BottomControlDock.SECTION_POSITIONS,
			func(i: int) -> float: return BottomControlDock.SECTION_SIZES[i])


func _inner(touch: bool) -> Array:
	var base := BottomControlDock.TOUCH_UTILITY_SIZE if touch \
			else BottomControlDock.DESKTOP_UTILITY_SIZE
	return _row(BottomControlDock.TOUCH_UTILITY_POSITIONS if touch
			else BottomControlDock.DESKTOP_UTILITY_POSITIONS,
			func(i: int) -> float: return base - i * BottomControlDock.UTILITY_SIZE_STEP)


func _fan(touch: bool, trim: Color) -> Image:
	var canvas := Vector2(
			BottomControlDock.TOUCH_WIDTH if touch else BottomControlDock.WIDTH,
			float(UIConstants.TOUCH_BOTTOM_BAR_HEIGHT if touch
					else UIConstants.BOTTOM_BAR_HEIGHT))
	return DockArcBackdrop.arc_image(canvas, _outer(), _inner(touch), trim)


## The image pixel under a display-space point of the dock.
func _at(image: Image, point: Vector2) -> Color:
	return image.get_pixel(
			clampi(int(point.x / DockArcBackdrop.PIXEL), 0, image.get_width() - 1),
			clampi(int(point.y / DockArcBackdrop.PIXEL), 0, image.get_height() - 1))


## Count of pixels in `image` exactly matching `color`.
func _count(image: Image, color: Color) -> int:
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y) == color:
				total += 1
	return total


# ---------------------------------------------------------------------------
# SILHOUETTE
# ---------------------------------------------------------------------------

func test_the_fan_is_painted_at_the_medallions_two_pixel_grain() -> void:
	var image := _fan(false, TerrainToolbar.SECTION_COLORS[0])
	assert_eq(image.get_width(),
			int(ceil(BottomControlDock.WIDTH / DockArcBackdrop.PIXEL)),
			"the fan generates at half size, like the medallion faces")
	assert_eq(image.get_height(),
			int(ceil(float(UIConstants.BOTTOM_BAR_HEIGHT) / DockArcBackdrop.PIXEL)),
			"and half height, drawn back up with nearest filtering")


func test_the_rim_is_a_single_smooth_quarter_ellipse() -> void:
	for height in [UIConstants.BOTTOM_BAR_HEIGHT, UIConstants.TOUCH_BOTTOM_BAR_HEIGHT]:
		var hub := Vector2(0.0, float(height))
		var curve := DockArcBackdrop.rim_curve(_outer(), hub)
		assert_gt(curve.size(), 40, "the rim is densely sampled")
		var radius_x := 0.0
		for circle: Vector3 in _outer():
			radius_x = maxf(radius_x, circle.x + circle.z)
		radius_x += DockArcBackdrop.RIM_SIDE_MARGIN
		var radius_y := hub.y + DockArcBackdrop.RIM_TOP_LIFT
		for i in curve.size():
			var p := curve[i] - hub
			assert_almost_eq(pow(p.x / radius_x, 2) + pow(p.y / radius_y, 2),
					1.0, 0.001, "every point lies on the same ellipse")
			if i > 0:
				assert_gte(curve[i].x, curve[i - 1].x, "the rim never doubles back")
				assert_gte(curve[i].y, curve[i - 1].y, "the rim descends smoothly")
				assert_lt(curve[i].distance_to(curve[i - 1]), 3.0,
						"samples stay close even on the steep end")


func test_turf_fills_the_corner_and_the_course_shows_above_the_rim() -> void:
	for touch in [false, true]:
		var image := _fan(touch, TerrainToolbar.SECTION_COLORS[0])
		var canvas := Vector2(image.get_width(), image.get_height()) * DockArcBackdrop.PIXEL
		# Every medallion of both rows is centred on turf...
		for circle: Vector3 in _outer() + _inner(touch):
			assert_eq(_at(image, Vector2(circle.x, circle.y)).a, 1.0,
					"the medallion at %s sits on the fan (touch=%s)" % [str(circle), touch])
		# The course is visible outside the curved edge.
		assert_eq(_at(image, Vector2(canvas.x - 8.0, 30.0)).a, 0.0,
				"the space beyond the arc remains open (touch=%s)" % touch)
		# The fan anchors to the screen's corner and bottom edge.
		assert_eq(image.get_pixel(0, image.get_height() - 1).a, 1.0,
				"the bottom-left corner is turf")
		assert_eq(image.get_pixel(image.get_width() - 1, image.get_height() - 1).a, 1.0,
				"the fan meets the shelf along the bottom edge")
		# The rectangle's dead top-right is air now: course shows there.
		assert_eq(image.get_pixel(image.get_width() - 1, 0).a, 0.0,
				"the dock's top-right corner is open to the course")
		assert_eq(_at(image, Vector2(canvas.x - 18.0, 30.0)).a, 0.0,
				"above the rim between Manage and Golfers is course, not bar")


func test_without_medallions_the_fan_falls_back_to_plain_turf() -> void:
	var image := DockArcBackdrop.arc_image(Vector2(64, 48), [], [], Color.WHITE)
	assert_eq(image.get_pixel(0, 0), DockArcBackdrop.TURF_DARK,
			"before the dock lays out, the corner is flat turf as the bar was")
	assert_eq(image.get_pixel(image.get_width() - 1, image.get_height() - 1).a, 1.0)


# ---------------------------------------------------------------------------
# PAINT
# ---------------------------------------------------------------------------

func test_the_rim_wears_ink_and_the_open_sections_trim() -> void:
	var build := TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.BUILD]
	var image := _fan(false, build)
	assert_gt(_count(image, DockArcBackdrop.INK), 40,
			"an ink band runs the length of the rim")
	assert_gt(_count(image, build), 20,
			"the trim band inside it carries the section colour exactly")
	var golfers := TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.GOLFERS]
	var other := _fan(false, golfers)
	assert_gt(_count(other, golfers), 20, "switching section re-trims the rim")
	assert_eq(_count(other, build), 0, "and leaves no trace of the last section's trim")


func test_a_collapsed_section_drops_the_trim_to_the_bars_sage() -> void:
	var image := _fan(false, DockArcBackdrop.FALLBACK_ACCENT)
	assert_gt(_count(image, DockArcBackdrop.FALLBACK_ACCENT), 20,
			"the collapsed fan trims in sage")
	assert_eq(_count(image, TerrainToolbar.SECTION_COLORS[0]), 0,
			"with no section open, no section colour shows")


func test_the_turf_is_mown_in_rings_around_the_corner() -> void:
	var image := _fan(false, TerrainToolbar.SECTION_COLORS[0])
	var hub := Vector2(0.0, float(UIConstants.BOTTOM_BAR_HEIGHT))
	# Two points on one ray out of the hub, in neighbouring rings but the
	# same chequer sector, in the empty pocket below Menu.
	var ray := Vector2.from_angle(deg_to_rad(-30.0))
	var near := _at(image, hub + ray * 40.0)
	var far := _at(image, hub + ray * 55.0)
	assert_ne(near, far, "neighbouring rings mow to different tones")
	for tone in [near, far]:
		assert_eq(tone.a, 1.0, "the rings are solid turf")
		assert_gt(tone.g, tone.r, "and the turf stays a deep green")
		assert_lt(tone.get_luminance(), 0.25,
				"dark enough that the medallion faces stand proud of it")


func test_the_corner_pocket_carries_a_flag() -> void:
	var image := _fan(false, TerrainToolbar.SECTION_COLORS[0])
	assert_gt(_count(image, DockArcBackdrop.FLAG_RED), 8,
			"a red flag stands in the corner pocket below Menu")


# ---------------------------------------------------------------------------
# THE CONTROL
# ---------------------------------------------------------------------------

func test_the_backdrop_never_swallows_a_click() -> void:
	var backdrop := DockArcBackdrop.new()
	add_child_autofree(backdrop)
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"clicks above the rim reach the course, below it the medallions")
	assert_eq(backdrop.accent, DockArcBackdrop.FALLBACK_ACCENT,
			"a fresh backdrop trims in sage until the dock syncs a section")


func test_the_dock_seats_the_backdrop_behind_every_circle() -> void:
	var dock := BottomControlDock.new()
	add_child_autofree(dock)
	var backdrop := dock.get_node_or_null("ArcBackdrop") as DockArcBackdrop
	assert_not_null(backdrop, "the dock paints its corner with the arc backdrop")
	assert_eq(backdrop.get_index(), 0, "as its first child, behind every medallion")
