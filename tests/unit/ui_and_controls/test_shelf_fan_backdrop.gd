extends GameTest
## ShelfFanBackdrop: the right shelf mirrors the left dock's ellipse and its
## section-coloured rim, while retaining the same mown rings, tab sockets,
## flight dots and title rule. Test the generated pixels and live geometry.

## A medallion circle (centre, radius packed as Vector3).
func _circle(x: float, y: float, r: float) -> Vector3:
	return Vector3(x, y, r)

## The image pixel under a display-space point of the shelf.
func _at(image: Image, point: Vector2) -> Color:
	return image.get_pixel(
		clampi(int(point.x / ShelfFanBackdrop.PIXEL), 0, image.get_width() - 1),
		clampi(int(point.y / ShelfFanBackdrop.PIXEL), 0, image.get_height() - 1))

## Count of pixels in `image` exactly matching `color`.
func _count(image: Image, color: Color) -> int:
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y) == color:
				total += 1
	return total

# ---------------------------------------------------------------------------
# SHARED ARC
# ---------------------------------------------------------------------------

func test_the_fairway_is_painted_at_the_two_pixel_grain() -> void:
	var image := ShelfFanBackdrop.shelf_image(Vector2(300, 150), Vector2(-150, 150), [],
		TerrainToolbar.SECTION_COLORS[0])
	assert_eq(image.get_width(),
		int(ceil(300.0 / ShelfFanBackdrop.PIXEL)),
		"the fairway generates at half size, like the medallion faces")
	assert_eq(image.get_height(),
		int(ceil(150.0 / ShelfFanBackdrop.PIXEL)),
		"and half height, drawn back up with nearest filtering")

func test_the_shelf_rim_is_the_left_dock_curve_reflected() -> void:
	var outer: Array = []
	for i in BottomControlDock.SECTION_POSITIONS.size():
		var pos: Vector2 = BottomControlDock.SECTION_POSITIONS[i]
		var radius: float = BottomControlDock.SECTION_SIZES[i] * 0.5
		outer.append(Vector3(pos.x + radius, pos.y + radius, radius))
	var width := BottomControlDock.SECTION_POSITIONS[-1].x \
			+ BottomControlDock.SECTION_SIZES[-1] + DockArcBackdrop.RIM_SIDE_MARGIN
	for height in [UIConstants.BOTTOM_BAR_HEIGHT, UIConstants.TOUCH_BOTTOM_BAR_HEIGHT]:
		var canvas := Vector2(400, height)
		var left := DockArcBackdrop.rim_curve(outer, Vector2(0.0, height))
		for point in left:
			var reflected_x: float = width - point.x
			assert_almost_eq(ShelfFanBackdrop.rim_top_at(reflected_x, canvas, width),
					point.y, 0.01, "the shelf is the dock's reflected ellipse")
			if point.y >= 0.0:
				assert_almost_eq(ShelfFanBackdrop.rim_x_at(point.y, canvas, width),
						reflected_x, 0.01, "tab placement and painted rim use the same arc")

func test_the_reflected_rim_meets_the_dock_at_every_rail_width() -> void:
	var dock_radius := BottomControlDock.SECTION_POSITIONS[-1].x \
			+ BottomControlDock.SECTION_SIZES[-1] + DockArcBackdrop.RIM_SIDE_MARGIN
	for touch in [false, true]:
		var height := float(UIConstants.TOUCH_BOTTOM_BAR_HEIGHT if touch else UIConstants.BOTTOM_BAR_HEIGHT)
		var dock_width := BottomControlDock.TOUCH_WIDTH if touch else BottomControlDock.WIDTH
		var normalized := dock_width / dock_radius
		var dock_seam_y := height - (height + DockArcBackdrop.RIM_TOP_LIFT) \
				* sqrt(1.0 - normalized * normalized)
		for width in [224.0, 134.0, 66.0]:
			var inset := TerrainToolbar._shelf_seam_inset(width, touch)
			var canvas := Vector2(400, height)
			assert_almost_eq(ShelfFanBackdrop.rim_top_at(0.0, canvas, width, inset),
					dock_seam_y, 0.01, "the rims join at the same height")
			assert_almost_eq(ShelfFanBackdrop.rim_x_at(dock_seam_y, canvas, width, inset),
					0.0, 0.01, "the tab curve shares that join")
			var image := ShelfFanBackdrop.shelf_image(canvas, Vector2(-dock_width, height),
					[], Color.WHITE, Rect2(), width, inset)
			# On a narrow rail the curve is steep, so sample above the nearby
			# columns (and their 3px shadow), not just above x=0.
			var above := ShelfFanBackdrop.rim_top_at(4.0, canvas, width, inset) - 8.0
			assert_eq(_at(image, Vector2(1, above)).a, 0.0,
					"course remains visible above the join")
			assert_eq(_at(image, Vector2(1, dock_seam_y + 12)).a, 1.0,
					"the turf continues below it")

func test_the_curve_reveals_the_course_and_anchors_the_shelf() -> void:
	var canvas := Vector2(400, 190)
	var image := ShelfFanBackdrop.shelf_image(canvas, Vector2(-220, 190), [],
			TerrainToolbar.SECTION_COLORS[0], Rect2(), 134.0)
	assert_eq(_at(image, Vector2(8, 8)).a, 0.0, "the upper-left cutout is transparent")
	assert_eq(_at(image, Vector2(32, 32)).a, 0.0, "the curve clears space above the rim")
	assert_eq(_at(image, Vector2(32, 170)).a, 1.0, "turf fills below the rim")
	assert_eq(_at(image, Vector2(200, 40)).a, 1.0, "the scrolling pages remain backed")
	assert_eq(_at(image, Vector2(4, 188)).a, 1.0, "the shelf meets the dock at the bottom")
	assert_false(ShelfFanBackdrop.contains_point(Vector2(8, 8), canvas, 134.0))
	assert_true(ShelfFanBackdrop.contains_point(Vector2(32, 170), canvas, 134.0))

func test_the_mirrored_rim_uses_the_open_sections_trim() -> void:
	var canvas := Vector2(400, 190)
	var build := TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.BUILD]
	var golfers := TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.GOLFERS]
	var first := ShelfFanBackdrop.shelf_image(canvas, Vector2(-220, 190), [], build, Rect2(), 134.0)
	var second := ShelfFanBackdrop.shelf_image(canvas, Vector2(-220, 190), [], golfers, Rect2(), 134.0)
	assert_gt(_count(first, DockArcBackdrop.INK), 40, "the same ink band outlines the rim")
	assert_gt(_count(first, build), 20, "the rim wears the Build colour")
	assert_gt(_count(second, golfers), 20, "changing section recolours the rim")
	assert_eq(_count(second, build), 0, "the previous section's trim is gone")

func test_the_shelf_mows_at_the_dock_fans_one_rhythm() -> void:
	# The shelf's rings are the dock fan's rings continued: same ring width,
	# same chequer sector, same two turf tones, so the fairway is one grass.
	assert_eq(ShelfFanBackdrop.RING_WIDTH, DockArcBackdrop.RING_WIDTH,
		"both fairways mow at the same ring width")
	assert_eq(ShelfFanBackdrop.SECTOR_DEGREES, DockArcBackdrop.SECTOR_DEGREES,
		"and the same chequer sector")
	assert_eq(ShelfFanBackdrop.TURF_DARK, DockArcBackdrop.TURF_DARK,
		"and the same deep turf")
	assert_eq(ShelfFanBackdrop.TURF_LIGHT, DockArcBackdrop.TURF_LIGHT,
		"and the same lit turf")

func test_the_rings_sweep_on_from_the_hub() -> void:
	var hub := Vector2(-150.0, 150.0)
	var image := ShelfFanBackdrop.shelf_image(Vector2(300, 150), hub, [],
		TerrainToolbar.SECTION_COLORS[0])
	# Two points on one ray out of the hub, in neighbouring rings.
	var near := _at(image, Vector2(0.0, 150.0))
	var far := _at(image, Vector2(15.0, 150.0))
	assert_ne(near, far, "neighbouring rings mow to different tones")
	for tone in [near, far]:
		assert_eq(tone.a, 1.0, "the rings are solid turf")
		assert_gt(tone.g, tone.r, "and the turf stays a deep green")
		assert_lt(tone.get_luminance(), 0.25,
			"dark enough that the medallion faces stand proud of it")

# ---------------------------------------------------------------------------
# MEDALLIONS
# ---------------------------------------------------------------------------

func test_a_medallion_sits_in_a_dark_socket() -> void:
	var circles := [_circle(40.0, 40.0, 16.0)]
	var image := ShelfFanBackdrop.shelf_image(Vector2(100, 100), Vector2(-100, 100),
		circles, Color.WHITE)
	# Just outside the medallion's edge the turf darkens to its socket.
	assert_eq(_at(image, Vector2(40.0 + 16.0 + 3.0, 40.0)),
		ShelfFanBackdrop.SOCKET, "the circle wears a dark socket")

func test_a_dotted_gold_flight_arc_joins_the_medallions() -> void:
	var circles := [_circle(20.0, 20.0, 16.0), _circle(20.0, 60.0, 16.0)]
	var image := ShelfFanBackdrop.shelf_image(Vector2(80, 100), Vector2(-80, 100),
		circles, Color.WHITE)
	assert_gt(_count(image, ShelfFanBackdrop.FLIGHT_GOLD), 4,
		"a dotted gold arc runs through the gap between the medallions")

# ---------------------------------------------------------------------------
# TITLE RULE
# ---------------------------------------------------------------------------

func test_the_title_wears_a_curved_gold_rule() -> void:
	var rule := Rect2(44.0, 2.0, 200.0, 22.0)
	var image := ShelfFanBackdrop.shelf_image(Vector2(300, 100), Vector2(-300, 100),
		[], Color.WHITE, rule)
	assert_gt(_count(image, ShelfFanBackdrop.FLIGHT_GOLD), 20,
		"a curved gold rule sits along the title's bottom edge")

func test_without_a_title_there_is_no_rule() -> void:
	var image := ShelfFanBackdrop.shelf_image(Vector2(300, 100), Vector2(-300, 100),
		[], Color.WHITE, Rect2())
	assert_eq(_count(image, ShelfFanBackdrop.FLIGHT_GOLD), 0,
		"no title, no rule")

func test_the_title_rule_never_paints_in_the_transparent_cutout() -> void:
	var rule := Rect2(0, 0, 120, 20)
	var image := ShelfFanBackdrop.shelf_image(Vector2(300, 150), Vector2(-220, 150),
			[], Color.WHITE, rule, 134.0)
	assert_eq(_at(image, Vector2(10, 18)).a, 0.0,
			"a rule extending outside the fairway cannot fill the cutout")

func test_resize_artwork_caches_are_bounded() -> void:
	for i in ShelfFanBackdrop.CACHE_LIMIT + 4:
		var canvas := Vector2(40 + i, 30)
		ShelfFanBackdrop.texture_for(canvas, Vector2(-100, 30), [], Color.WHITE,
				Rect2(), 20.0 + i)
	assert_lte(ShelfFanBackdrop._image_cache.size(), ShelfFanBackdrop.CACHE_LIMIT,
			"old images do not accumulate during live resizes")
	assert_lte(ShelfFanBackdrop._texture_cache.size(), ShelfFanBackdrop.CACHE_LIMIT,
			"old textures do not accumulate either")

# ---------------------------------------------------------------------------
# THE TOOLBAR
# ---------------------------------------------------------------------------

func test_the_backdrop_covers_the_shelf_content() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	await get_tree().process_frame
	var backdrop := toolbar.get_node("ShelfFanBackdrop") as ShelfFanBackdrop
	assert_true(toolbar.get_theme_stylebox("panel") is StyleBoxEmpty,
		"no rectangular panel frame fills the transparent corner")
	assert_eq(backdrop.position, Vector2.ZERO, "the fairway starts at the shelf edge")
	assert_eq(backdrop.size, toolbar.size, "the backdrop fills the entire shelf canvas")

func test_the_sockets_hug_the_rails_live_medallions() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	await get_tree().process_frame
	var backdrop := toolbar.get_node("ShelfFanBackdrop") as ShelfFanBackdrop
	assert_gt(backdrop.circles.size(), 0,
		"the rail's medallions sit on the fairway")
	for circle in backdrop.circles:
		# A socket is drawn just outside the circle's edge, so the circle and
		# its socket must stay inside the shelf's canvas.
		assert_lt(circle.x + circle.z, backdrop.size.x + 1.0,
			"a socket stays inside the shelf")
		assert_lt(circle.y + circle.z, backdrop.size.y + 1.0,
			"a socket stays inside the shelf")

# ---------------------------------------------------------------------------
# THE CONTROL
# ---------------------------------------------------------------------------

func test_the_backdrop_never_swallows_a_click() -> void:
	var backdrop := ShelfFanBackdrop.new()
	add_child_autofree(backdrop)
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"clicks pass through the fairway to the shelf's controls")
	assert_eq(backdrop.accent, ShelfFanBackdrop.FALLBACK_ACCENT,
		"a fresh backdrop trims in sage until the toolbar syncs a section")

func test_the_toolbar_seats_the_backdrop_behind_every_tab() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	var backdrop := toolbar.get_node_or_null("ShelfFanBackdrop") as ShelfFanBackdrop
	assert_not_null(backdrop, "the shelf paints its fairway with the backdrop")
	assert_eq(backdrop.get_index(), 0, "as its first child, behind every circle and tile")

func test_the_shelf_wears_the_open_sections_colour() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	var backdrop := toolbar.get_node("ShelfFanBackdrop") as ShelfFanBackdrop
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	assert_eq(backdrop.accent, TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.GOLFERS],
		"switching section re-trims the shelf's fairway")
