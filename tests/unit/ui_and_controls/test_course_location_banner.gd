extends GameTest
## CourseLocationBanner and the CourseLocationPicture generator behind it.
##
## The banner is the top-left postcard: a square per-location pixel-art picture
## in one column (no background behind it) and, in the other, the only card
## with a background - the location name and the date. These tests cover the
## picture generator (every shipped location paints, each one differently, and
## repaints identically), the banner's two-column build, its WorldMap /
## EventBus wiring, the visible date, and its responsive compact layout.


func before_each() -> void:
	super()
	# Desktop window so the banner starts in its wide layout.
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	CourseLocationPicture.clear_cache()


func after_each() -> void:
	get_window().size = Vector2i(1600, 1000)
	await process_frames(1)
	super()


## A banner in the tree, freed after the test.
func _make_banner() -> CourseLocationBanner:
	var banner: CourseLocationBanner = autofree(CourseLocationBanner.new())
	add_child(banner)
	return banner


func _picture(banner: CourseLocationBanner) -> TextureRect:
	var node := banner.get_node_or_null("Columns/PictureFrame/Picture")
	assert_not_null(node, "the picture column holds a TextureRect")
	return node as TextureRect


func _name_label(banner: CourseLocationBanner) -> Label:
	var node := banner.get_node_or_null("Columns/DetailsPanel/Details/Text/LocationName")
	assert_not_null(node, "the details card holds the location name")
	return node as Label


func _date_label(banner: CourseLocationBanner) -> Label:
	var node := banner.get_node_or_null("Columns/DetailsPanel/Details/Text/DateRow/Date")
	assert_not_null(node, "the details card holds the date")
	return node as Label


# ---------------------------------------------------------------------------
# CourseLocationPicture generator
# ---------------------------------------------------------------------------

func test_every_shipped_location_paints_a_square_grid_with_many_colors() -> void:
	for def in WorldLocations.get_all():
		var id := str(def["id"])
		var image := CourseLocationPicture.image_for_location(id, int(def["theme"]))
		assert_eq(image.get_width(), CourseLocationPicture.GRID_W, "%s paints the full width" % id)
		assert_eq(image.get_height(), CourseLocationPicture.GRID_H, "%s paints the full height" % id)
		assert_eq(image.get_width(), image.get_height(), "%s is a square 1:1 picture" % id)
		var colors := {}
		for y in image.get_height():
			for x in image.get_width():
				colors[image.get_pixel(x, y).to_html()] = true
		assert_gt(colors.size(), 12, "%s paints a multi-colour scene (saw %d)" % [id, colors.size()])


func test_every_location_gets_a_different_picture() -> void:
	var seen := {}
	for def in WorldLocations.get_all():
		var id := str(def["id"])
		var image := CourseLocationPicture.image_for_location(id, int(def["theme"]))
		var fingerprint := image.get_data()
		assert_false(seen.has(fingerprint),
			"%s has its own picture, not another location's" % id)
		seen[fingerprint] = id
	assert_eq(seen.size(), WorldLocations.get_all().size(), "one unique picture per location")


func test_a_location_repaints_identically_and_returns_a_cached_texture() -> void:
	var first := CourseLocationPicture.image_for_location("hawaii", CourseTheme.Type.TROPICAL)
	var second := CourseLocationPicture.image_for_location("hawaii", CourseTheme.Type.TROPICAL)
	assert_eq(first.get_data(), second.get_data(), "the same id repaints the same scene")
	var tex_a := CourseLocationPicture.texture_for_location("hawaii", CourseTheme.Type.TROPICAL, 2)
	var tex_b := CourseLocationPicture.texture_for_location("hawaii", CourseTheme.Type.TROPICAL, 2)
	assert_true(tex_a == tex_b, "textures are cached per location and scale")
	assert_eq(tex_a.get_width(), CourseLocationPicture.GRID_W * 2, "scale 2 doubles the width")
	assert_eq(tex_a.get_height(), CourseLocationPicture.GRID_H * 2, "and the height - the art stays square")


func test_locations_of_one_theme_still_differ() -> void:
	# Several shipped LINKS courses share a palette and landmarks; their seeded
	# placements must still keep their postcards apart.
	var links_ids: Array[String] = []
	for def in WorldLocations.get_all():
		if int(def["theme"]) == CourseTheme.Type.LINKS:
			links_ids.append(str(def["id"]))
	assert_gte(links_ids.size(), 3, "the catalog has several links courses")
	var fingerprints := {}
	for id in links_ids:
		fingerprints[CourseLocationPicture.image_for_location(id, CourseTheme.Type.LINKS).get_data()] = id
	assert_eq(fingerprints.size(), links_ids.size(), "every links location looks different")


func test_unknown_themes_and_ids_paint_without_error() -> void:
	var image := CourseLocationPicture.image_for_location("modders_dream_course", 999)
	assert_eq(image.get_size(), Vector2i(CourseLocationPicture.GRID_W, CourseLocationPicture.GRID_H),
		"an unknown theme falls back to the parkland scene")


# ---------------------------------------------------------------------------
# Banner build: two columns, background only on the details card
# ---------------------------------------------------------------------------

func test_the_banner_builds_two_columns_with_picture_name_and_date() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	banner.refresh()
	assert_true(banner.visible, "the banner shows with an active location")

	var picture := _picture(banner)
	assert_not_null(picture.texture, "the first column carries the location picture")
	assert_eq(picture.custom_minimum_size.x, picture.custom_minimum_size.y,
		"the picture slot is square")
	assert_eq(picture.texture.get_width(), CourseLocationPicture.GRID_W * 2,
		"the desktop picture is nearest-scaled 2x")
	assert_eq(picture.texture.get_width(), picture.texture.get_height(),
		"the baked texture keeps the 1:1 ratio")

	var name_label := _name_label(banner)
	assert_eq(name_label.text, "Monterey", "the second column names the location")
	var date_label := _date_label(banner)
	assert_ne(date_label.text, "", "the second column carries the date")
	assert_eq(date_label.text, GameCalendar.format_date(GameManager.current_day),
		"the date matches the game calendar")


func test_only_the_details_card_paints_a_background() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	# The root and the picture column are transparent; the details card alone
	# carries the dark surface.
	assert_true(banner.get_theme_stylebox("panel") is StyleBoxEmpty,
		"the banner root paints no background of its own")
	var frame: PanelContainer = banner.get_node("Columns/PictureFrame")
	var frame_style := frame.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(frame_style, "the picture keeps a hairline frame")
	assert_eq(frame_style.bg_color.a, 0.0, "the picture frame has no fill")
	var details: PanelContainer = banner.get_node("Columns/DetailsPanel")
	var details_style := details.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(details_style, "the details column is a card")
	assert_gt(details_style.bg_color.a, 0.0, "the details card paints the only background")


func test_the_banner_hides_without_an_active_location() -> void:
	WorldMap.active_location_id = ""
	var banner := _make_banner()
	banner.refresh()
	assert_false(banner.visible, "no postcard shows before the first course is bought")


func test_the_banner_tracks_the_active_location_signal() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	assert_eq(_name_label(banner).text, "Monterey")

	# Swapping the active location through WorldMap refreshes the card itself.
	WorldMap.set_active_location("hawaii")
	assert_eq(_name_label(banner).text, "Hawaii", "the name follows the active location")
	var picture := _picture(banner)
	var expected := CourseLocationPicture.texture_for_location(
		"hawaii", CourseTheme.Type.TROPICAL, banner._picture_scale())
	assert_true(picture.texture == expected, "the picture swaps with the location")


func test_the_date_ticks_with_the_calendar_and_keeps_enough_room_to_show() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	GameManager.current_day = 18
	EventBus.day_changed.emit(18)
	var date_label := _date_label(banner)
	assert_eq(date_label.text, GameCalendar.format_date(18),
		"the date refreshes when the day rolls over")
	# Regression: a clipped Label without SIZE_EXPAND collapsed to 1px and the
	# date was invisible. After a layout pass it must hold real width.
	await process_frames(2)
	assert_gt(date_label.size.x, 40.0,
		"the date label keeps enough width to show the full date (was 1px)")
	assert_true(date_label.is_visible_in_tree(), "the date row is on screen")


func test_a_world_reset_hides_the_banner_until_a_site_is_bought() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	assert_true(banner.visible)
	WorldMap.active_location_id = ""
	WorldMap.world_reset.emit()
	assert_false(banner.visible, "a fresh world has no active location to postcard")


func test_the_banner_ignores_the_mouse_so_shots_pass_through() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	assert_eq(banner.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the card never eats course clicks")


func test_the_picture_swaps_between_two_real_locations() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	var monterey_tex := _picture(banner).texture
	WorldMap.set_active_location("las_vegas")
	var vegas_tex := _picture(banner).texture
	assert_ne(monterey_tex, vegas_tex, "each course location shows a different image")


# ---------------------------------------------------------------------------
# Responsive layout
# ---------------------------------------------------------------------------

func test_the_compact_layout_shrinks_the_square_picture_and_the_card() -> void:
	WorldMap.active_location_id = "rocky_mountains"
	var banner := _make_banner()
	var desktop_width := banner.custom_minimum_size.x
	var desktop_picture := _picture(banner).custom_minimum_size
	assert_eq(desktop_picture, Vector2(CourseLocationPicture.GRID_W * 2,
		CourseLocationPicture.GRID_H * 2), "desktop shows the 2x square picture")

	get_window().size = Vector2i(390, 844)
	await process_frames(2)
	banner.apply_screen()
	assert_lt(banner.custom_minimum_size.x, desktop_width, "the card narrows on a phone")
	assert_eq(_picture(banner).custom_minimum_size,
		Vector2(CourseLocationPicture.GRID_W, CourseLocationPicture.GRID_H),
		"compact shows the 1x square picture")
	assert_eq(_date_label(banner).text, GameCalendar.format_date_short(GameManager.current_day),
		"compact uses the short date")


func test_the_occupied_height_covers_the_card_and_its_margin() -> void:
	WorldMap.active_location_id = "monterey"
	var banner := _make_banner()
	assert_gt(banner.get_occupied_height(), CourseLocationBanner.HEIGHT_DESKTOP,
		"the clearance includes the corner margin")
