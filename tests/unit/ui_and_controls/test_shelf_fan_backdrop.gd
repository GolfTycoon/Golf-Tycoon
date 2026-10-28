extends GameTest
## ShelfFanBackdrop: the bottom-right shelf's fairway. The shelf is painted
## with the *same* mown rings the bottom-left dock's fan is cut from - both
## are centred on the screen's bottom-left hub and mowed at one rhythm - so
## the two read as one continuous putting surface. The tab rail's medallions
## sit in dark sockets on the turf and a dotted gold ball-flight arc joins
## them, and the page title wears a curved gold rule echoing the fan's rim.
## These tests read the generated images pixel by pixel, the same way the
## dock's fan tests do, using the shelf's own layout constants so a change
## that breaks the fairway breaks a test.

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

# ---------------------------------------------------------------------------
# THE TOOLBAR
# ---------------------------------------------------------------------------

func test_the_backdrop_covers_the_shelf_content() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	await get_tree().process_frame
	var backdrop := toolbar.get_node("ShelfFanBackdrop") as ShelfFanBackdrop
	var style := toolbar.get_theme_stylebox("panel")
	var panel_size := Vector2(style.content_margin_left + style.content_margin_right,
		style.content_margin_top + style.content_margin_bottom)
	assert_eq(backdrop.position, Vector2(style.content_margin_left, style.content_margin_top),
		"the fairway fills the panel's content rect")
	assert_eq(backdrop.size, toolbar.size - panel_size,
		"and every tab and tile sits on it")

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
