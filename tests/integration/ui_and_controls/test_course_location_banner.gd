extends MainSceneTest
## The location postcard inside the real main scene: the banner builds with the
## HUD, shows the active world-map location with its own square picture, docks
## the scores cards underneath without overlap, and follows a location swap and
## the responsive window sizes.

func before_all() -> void:
	await super()
	await new_game()


func test_the_banner_is_in_the_hud_and_shows_the_active_location() -> void:
	var banner: CourseLocationBanner = main.course_location_banner
	assert_not_null(banner, "main.gd builds the CourseLocationBanner")
	assert_eq(banner.get_parent().name, "HUD", "it docks inside the gameplay HUD")
	assert_true(banner.visible, "a started course has an active location to show")
	var active: Dictionary = WorldLocations.get_definition(WorldMap.active_location_id)
	var name_label: Label = banner.get_node("Columns/DetailsPanel/Details/Text/LocationName")
	assert_eq(name_label.text, str(active["name"]), "the name is the active location's")
	var picture: TextureRect = banner.get_node("Columns/PictureFrame/Picture")
	assert_not_null(picture.texture, "the picture column carries the location art")
	assert_eq(picture.texture.get_width(), picture.texture.get_height(),
		"the location art is square")
	var date_label: Label = banner.get_node("Columns/DetailsPanel/Details/Text/DateRow/Date")
	assert_eq(date_label.text, GameCalendar.format_date(GameManager.current_day),
		"the date matches the running calendar")
	# Regression: the clipped date label must expand inside its row rather than
	# collapsing to a single invisible pixel.
	assert_gt(date_label.size.x, 40.0, "the date has real width in the running game")


func test_the_root_stays_transparent_and_only_the_details_card_has_a_background() -> void:
	var banner: CourseLocationBanner = main.course_location_banner
	assert_true(banner.get_theme_stylebox("panel") is StyleBoxEmpty,
		"the picture column floats over the course with no card behind it")
	var details: PanelContainer = banner.get_node("Columns/DetailsPanel")
	var style := details.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style, "the name/date column is its own card")
	assert_gt(style.bg_color.a, 0.0, "the details card paints the only background")


func test_every_location_paints_its_own_picture_into_the_banner() -> void:
	var banner: CourseLocationBanner = main.course_location_banner
	var first := WorldMap.active_location_id
	var first_texture: Texture2D = banner.get_node("Columns/PictureFrame/Picture").texture
	var other := ""
	for def in WorldLocations.get_all():
		if str(def["id"]) != first:
			other = str(def["id"])
			break
	WorldMap.set_active_location(other)
	await process_frames(2)
	var swapped: Texture2D = banner.get_node("Columns/PictureFrame/Picture").texture
	assert_ne(first_texture, swapped, "swapping course swaps the postcard picture")
	var name_label: Label = banner.get_node("Columns/DetailsPanel/Details/Text/LocationName")
	assert_eq(name_label.text, str(WorldLocations.get_definition(other)["name"]))
	WorldMap.set_active_location(first)
	await process_frames(2)


func test_the_scores_dock_stacks_underneath_the_banner_without_overlap() -> void:
	var banner: CourseLocationBanner = main.course_location_banner
	var dock: ScoresDock = main.scores_dock
	await process_frames(2)
	var banner_rect := banner.get_global_rect()
	var dock_rect := dock.get_global_rect()
	assert_gte(dock_rect.position.y, banner_rect.end.y,
		"the scores dock starts below the postcard")
	assert_eq(dock_rect.position.x, banner_rect.position.x,
		"both share the top-left corner margin")


func test_the_banner_stays_inside_the_screen_at_every_window_size() -> void:
	var banner: CourseLocationBanner = main.course_location_banner
	for window_size in [Vector2i(1600, 1000), Vector2i(1024, 768), Vector2i(390, 844), Vector2i(360, 800)]:
		await set_window(window_size)
		var screen := Rect2(Vector2.ZERO, Vector2(window_size))
		assert_true(rect_within(banner.get_global_rect(), screen),
			"the postcard stays on screen at %s" % window_size)
		var picture: TextureRect = banner.get_node("Columns/PictureFrame/Picture")
		assert_not_null(picture.texture, "the picture survives the responsive reflow")
		var date_label: Label = banner.get_node("Columns/DetailsPanel/Details/Text/DateRow/Date")
		assert_gt(date_label.size.x, 20.0, "the date stays visible in every layout")
	await set_window(DESIGN_WINDOW)


func test_the_banner_hides_with_the_rest_of_the_gameplay_hud() -> void:
	var banner: CourseLocationBanner = main.course_location_banner
	main._set_gameplay_ui_visible(false)
	assert_false(banner.visible, "menus hide the gameplay postcard with the other HUD pieces")
	main._set_gameplay_ui_visible(true)
	assert_true(banner.visible, "returning to the course shows it again")
