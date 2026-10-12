extends GameTest
## Which facilities each course theme may build (BuildingAvailability): the
## Buildings tab offers only what a location allows, and the catalogue data the
## tiles are built from is complete.

var registry: Dictionary = {}

func before_each() -> void:
	super()
	registry = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]


# ---------------------------------------------------------------------------
# Section 1: The catalogue matches the location design
# ---------------------------------------------------------------------------

func test_catalogue_lists_the_fifteen_location_facilities() -> void:
	var facilities := ["putting_green", "snack_bar", "pub", "pro_shop",
		"driving_range", "cart_garage", "tennis_court", "stable", "spa",
		"swim_club", "resort_hotel", "airstrip", "castle", "casino", "theme_park"]
	for type in facilities:
		assert_true(registry.has(type), "%s is a buildable facility" % type)
	# The clubhouse stays a required, non-placeable part of the course.
	assert_true(registry["clubhouse"].get("required", false),
		"The clubhouse is still required")


# ---------------------------------------------------------------------------
# Section 2: Facilities available at every location
# ---------------------------------------------------------------------------

func test_universal_facilities_are_available_on_every_theme() -> void:
	var universal := ["putting_green", "pro_shop", "driving_range",
		"cart_garage", "resort_hotel"]
	for theme in CourseTheme.get_all_types():
		for type in universal:
			assert_true(BuildingAvailability.is_available(registry[type], theme),
				"%s is available on %s" % [type, CourseTheme.to_string_name(theme)])


# ---------------------------------------------------------------------------
# Section 3: Theme-exclusive facilities
# ---------------------------------------------------------------------------

func test_snack_bar_is_everywhere_but_links() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme != CourseTheme.Type.LINKS
		assert_eq(BuildingAvailability.is_available(registry["snack_bar"], theme), expected,
			"Snack Bar availability on %s" % CourseTheme.to_string_name(theme))

func test_pub_is_links_only() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme == CourseTheme.Type.LINKS
		assert_eq(BuildingAvailability.is_available(registry["pub"], theme), expected,
			"Pub availability on %s" % CourseTheme.to_string_name(theme))

func test_stable_is_links_only() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme == CourseTheme.Type.LINKS
		assert_eq(BuildingAvailability.is_available(registry["stable"], theme), expected,
			"Stable availability on %s" % CourseTheme.to_string_name(theme))

func test_spa_is_desert_only() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme == CourseTheme.Type.DESERT
		assert_eq(BuildingAvailability.is_available(registry["spa"], theme), expected,
			"Spa availability on %s" % CourseTheme.to_string_name(theme))

func test_swim_club_is_tropical_only() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme == CourseTheme.Type.TROPICAL
		assert_eq(BuildingAvailability.is_available(registry["swim_club"], theme), expected,
			"Swim Club availability on %s" % CourseTheme.to_string_name(theme))

func test_tennis_court_skips_links_desert_and_tropical() -> void:
	var excluded := [CourseTheme.Type.LINKS, CourseTheme.Type.DESERT, CourseTheme.Type.TROPICAL]
	for theme in CourseTheme.get_all_types():
		var expected: bool = not excluded.has(theme)
		assert_eq(BuildingAvailability.is_available(registry["tennis_court"], theme), expected,
			"Tennis Court availability on %s" % CourseTheme.to_string_name(theme))

func test_airstrip_skips_links_desert_and_tropical() -> void:
	var excluded := [CourseTheme.Type.LINKS, CourseTheme.Type.DESERT, CourseTheme.Type.TROPICAL]
	for theme in CourseTheme.get_all_types():
		var expected: bool = not excluded.has(theme)
		assert_eq(BuildingAvailability.is_available(registry["airstrip"], theme), expected,
			"Airstrip availability on %s" % CourseTheme.to_string_name(theme))

func test_castle_is_links_only() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme == CourseTheme.Type.LINKS
		assert_eq(BuildingAvailability.is_available(registry["castle"], theme), expected,
			"Castle availability on %s" % CourseTheme.to_string_name(theme))

func test_casino_is_desert_only() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme == CourseTheme.Type.DESERT
		assert_eq(BuildingAvailability.is_available(registry["casino"], theme), expected,
			"Casino availability on %s" % CourseTheme.to_string_name(theme))

func test_theme_park_is_tropical_only() -> void:
	for theme in CourseTheme.get_all_types():
		var expected: bool = theme == CourseTheme.Type.TROPICAL
		assert_eq(BuildingAvailability.is_available(registry["theme_park"], theme), expected,
			"Theme Park availability on %s" % CourseTheme.to_string_name(theme))


# ---------------------------------------------------------------------------
# Section 4: Each theme's food, attitude and landmark line up
# ---------------------------------------------------------------------------

func test_every_theme_gets_exactly_one_food_stop_choice() -> void:
	for theme in CourseTheme.get_all_types():
		var food := []
		for type in ["snack_bar", "pub"]:
			if BuildingAvailability.is_available(registry[type], theme):
				food.append(type)
		assert_eq(food.size(), 1,
			"%s offers exactly one of Snack Bar or Pub" % CourseTheme.to_string_name(theme))

func test_every_theme_gets_exactly_one_attitude_facility() -> void:
	for theme in CourseTheme.get_all_types():
		var attitude := []
		for type in ["tennis_court", "stable", "spa", "swim_club"]:
			if BuildingAvailability.is_available(registry[type], theme):
				attitude.append(type)
		assert_eq(attitude.size(), 1,
			"%s offers exactly one attitude facility" % CourseTheme.to_string_name(theme))

func test_every_theme_gets_exactly_one_landmark() -> void:
	for theme in CourseTheme.get_all_types():
		var landmark := []
		for type in ["airstrip", "castle", "casino", "theme_park"]:
			if BuildingAvailability.is_available(registry[type], theme):
				landmark.append(type)
		assert_eq(landmark.size(), 1,
			"%s offers exactly one green-fee landmark" % CourseTheme.to_string_name(theme))


# ---------------------------------------------------------------------------
# Section 5: available_types and the Buildings tab
# ---------------------------------------------------------------------------

func test_available_types_excludes_foreign_facilities() -> void:
	var parkland := BuildingAvailability.available_types(registry, CourseTheme.Type.PARKLAND)
	assert_false(parkland.has("pub"), "Parkland has no Pub")
	assert_true(parkland.has("snack_bar"), "Parkland has the Snack Bar")
	assert_true(parkland.has("clubhouse"),
		"The clubhouse is available everywhere; the tab, not this rule, hides it")

func test_links_catalogue_swaps_snack_bar_for_pub() -> void:
	var links := BuildingAvailability.available_types(registry, CourseTheme.Type.LINKS)
	assert_true(links.has("pub"), "A Links course is offered the Pub")
	assert_false(links.has("snack_bar"), "A Links course is not offered the Snack Bar")
	assert_true(links.has("stable"), "A Links course is offered the Stable")
	assert_true(links.has("castle"), "A Links course is offered the Castle")

func test_building_tab_shows_only_the_theme_catalogue() -> void:
	var toolbar := TerrainToolbar.new()
	add_child_autofree(toolbar)
	toolbar.set_building_registry(registry)
	# The tab hides required buildings (the clubhouse) on top of applying the
	# location rules, so drop them from the expected list.
	var expected: Array = []
	for type in BuildingAvailability.available_types(registry, GameManager.current_theme):
		if not registry[type].get("required", false):
			expected.append(type)
	var shelf_count := 0
	for child in toolbar._building_shelf.get_children():
		if child is BuildingTileButton:
			shelf_count += 1
	assert_eq(shelf_count, expected.size(),
		"The Buildings tab lists exactly the facilities this location allows")


# ---------------------------------------------------------------------------
# Section 6: The availability note mirrors the catalogue blurb
# ---------------------------------------------------------------------------

func test_availability_note_describes_the_rule() -> void:
	assert_eq(BuildingAvailability.availability_note(registry["pro_shop"]),
		"Available on all locations.")
	assert_eq(BuildingAvailability.availability_note(registry["snack_bar"]),
		"Available on all locations unless it uses the Links Course Theme.")
	assert_eq(BuildingAvailability.availability_note(registry["pub"]),
		"Available on all locations that use the Links Course Theme.")
	assert_eq(BuildingAvailability.availability_note(registry["tennis_court"]),
		"Available on all locations unless it uses the Links, Desert, or Tropical Course Themes.")


# ---------------------------------------------------------------------------
# Section 7: The catalogue data files
# ---------------------------------------------------------------------------

func test_catalog_has_valid_services_and_artwork() -> void:
	var decorations: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/decorations.json")).decorations
	assert_eq(registry.size(), 16)
	# The Buildings tab keeps the clubhouse plus the fifteen location facilities.
	for type in ["clubhouse", "putting_green", "snack_bar", "pub", "pro_shop",
			"driving_range", "cart_garage", "tennis_court", "stable", "spa",
			"swim_club", "resort_hotel", "airstrip", "castle", "casino", "theme_park"]:
		assert_true(registry.has(type), "%s is in the catalogue" % type)
	# The Improvements tab keeps the path, the ball washer, the park bench, the
	# fountain, the golfer statue and the sundial.
	assert_eq(decorations.size(), 5)
	for type in ["ball_washer", "park_bench", "fountain", "golfer_statue", "sundial"]:
		assert_true(decorations.has(type), type)
		assert_true(DecorationTileArt.has_art(type), "%s has catalogue artwork" % type)
	for type in registry:
		var item: Dictionary = registry[type]
		assert_true(item.has("description"), "%s describes itself on its tile" % type)
		if item.has("needs_service"):
			assert_true(item.needs_service in ["snack_bar", "pub", "bench", "clubhouse", "pro_shop"], type)
