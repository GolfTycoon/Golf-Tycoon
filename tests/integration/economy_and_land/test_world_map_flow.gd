extends MainSceneTest
## The company's road from the main menu to its courses: Start New Game captures
## the company options and opens the world map, which lists every location;
## Buy & Play on a row buys that site and builds the generated first course
## there; the Club tab's World Map button freezes the course behind the globe
## and hands it back on Back or Esc; a second location can be bought and played
## and the first course is found as it was left; an 18-hole company builds and
## saves its championship course; and Quick Start buys and plays a location of
## its own.
##
## The tests follow one company through that road, in order.

const WorldMapStateScript := preload("res://scripts/autoload/world_map_state.gd")

const SAVE_NAME := "integration_world_map_flow"
const FIRST_SITE := "monterey"
const SECOND_SITE := "florida"
const CHAMPIONSHIP_SITE := "rocky_mountains"


func after_all() -> void:
	SaveManager.delete_save(SAVE_NAME)
	super()


func _world_map_screen() -> Node:
	return main.get_node_or_null("UI/HUD/WorldMapScreen")


## The toolbar button that acts for `tool_type`, wherever it sits on its tab.
func _tool_button(node: Node, tool_type: String) -> Button:
	for child in node.get_children():
		# Terrain tiles carry an int type and action buttons a String.
		if child is Button and str(child.get("tool_type")) == tool_type:
			return child
		var found := _tool_button(child, tool_type)
		if found:
			return found
	return null


## The Buy & Play / Play button in a location's row of the world map.
func _row_button(screen: Node, location_id: String) -> Button:
	var row = screen._rows.get(location_id)
	if row == null:
		return null
	var buttons := _buttons(row)
	return buttons[0] if not buttons.is_empty() else null


func _buttons(node: Node) -> Array:
	var found: Array = []
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_buttons(child))
	return found


func _labels_text(node: Node) -> String:
	var text := ""
	for child in node.get_children():
		if child is Label:
			text += child.text + "\n"
		text += _labels_text(child)
	return text


func _holes_on_unowned_land() -> int:
	var outside := 0
	for hole in GameManager.current_course.holes:
		if not GameManager.land_manager.is_tile_owned(hole.tee_position) \
				or not GameManager.land_manager.is_tile_owned(hole.green_position):
			outside += 1
	return outside


# ---------------------------------------------------------------------------
# Main menu and company setup
# ---------------------------------------------------------------------------

func test_the_main_menu_offers_the_agreed_actions() -> void:
	assert_not_null(main.main_menu, "The game opens on the main menu")
	var labels: Array = []
	for button in _buttons(main.main_menu):
		labels.append(button.text)
	for expected in ["Start New Game", "Quick Start", "Continue", "Load Game", "Achievements", "Settings", "Quit"]:
		assert_has(labels, expected, "The main menu has a %s button" % expected)
	for retired in ["New Game", "Credits", "Prebuilt Course"]:
		assert_does_not_have(labels, retired, "%s is no longer on the main menu" % retired)


func test_start_new_game_captures_the_company_and_opens_the_world_map() -> void:
	main._on_menu_start_new_game()
	await process_frames(3)
	var setup = main.get_node_or_null("UI/HUD/StartNewGameScreen")
	assert_not_null(setup, "Start New Game opens the company setup screen")
	assert_null(main.main_menu, "The title screen steps aside for it")
	if setup == null:
		return
	setup._company_input.text = "Summit Golf Group"
	setup._select_difficulty(DifficultyPresets.Preset.HARD)
	setup._select_money(200000)
	setup._select_holes(6)
	setup._feature_boxes["wind"].button_pressed = true
	var options: Dictionary = setup.get_options()
	assert_eq(options["company_name"], "Summit Golf Group", "The company name is captured")
	assert_eq(options["difficulty"], DifficultyPresets.Preset.HARD, "The difficulty is captured")
	assert_eq(options["starting_money"], 200000, "The starting money is captured")
	assert_eq(options["generated_holes"], 6, "The generated hole count is captured")
	assert_true(options["features"]["wind"], "The wind can be turned on")
	assert_false(options["features"]["weather"], "The weather stays off by default")

	setup._on_next_pressed()
	await process_frames(3)
	assert_not_null(_world_map_screen(), "Next goes on to the world map")
	assert_eq(WorldMap.company_name, "Summit Golf Group", "The world carries the company name")


func test_the_world_map_lists_every_location_with_its_details() -> void:
	var screen := _world_map_screen()
	assert_not_null(screen, "The world map is up")
	if screen == null:
		return
	assert_eq(screen._rows.size(), WorldLocations.get_all().size(), "The world map lists every location")
	var ids: Array = []
	for definition in WorldLocations.get_all():
		ids.append(definition["id"])
	for expected in ["monterey", "san_diego", "rocky_mountains", "las_vegas", "phoenix", "hawaii", "oahu",
			"nova_scotia", "northeast", "carolina", "ireland", "scotland", "wales", "spain", "florida", "jamaica"]:
		assert_has(ids, expected, "The catalogue includes %s" % expected)
	for id in ids:
		var definition: Dictionary = WorldLocations.get_definition(id)
		assert_ne(CourseTheme.get_theme_name(int(definition["theme"])), "Unknown", "%s has a real theme" % id)
		assert_gt(WorldMap.get_price(id), 0, "%s has a price" % id)
		assert_gte(WorldMap.get_unlocked_parcels(id).size(), 4, "%s starts with its central land unlocked" % id)
		assert_gt(WorldMap.get_total_parcels(id), 0, "%s has land" % id)

	# Each row shows the name, theme, size and cost.
	var listed := _labels_text(screen)
	var monterey: Dictionary = WorldLocations.get_definition("monterey")
	assert_string_contains(listed, "Monterey", "The list shows the Monterey row")
	assert_string_contains(listed, WorldLocations.get_size_name(int(monterey["size"])), "with its size")
	assert_string_contains(listed, CourseTheme.get_theme_name(int(monterey["theme"])), "and its theme")
	assert_string_contains(listed, "$", "The list shows costs")

	# Reset World rolls a new world: a new seed, valid prices, and new costs
	# (any one location may happen to keep its price).
	var seed_before := WorldMap.world_seed
	var prices_before: Dictionary = {}
	for id in ids:
		prices_before[id] = WorldMap.get_price(id)
	WorldMap.reset_world()
	assert_ne(WorldMap.world_seed, seed_before, "Reset World rolls a new world")
	var changed := 0
	for id in ids:
		assert_gt(WorldMap.get_price(id), 0, "%s still has a valid price after the reset" % id)
		if WorldMap.get_price(id) != prices_before[id]:
			changed += 1
	assert_gt(changed, 0, "Reset World changes location costs")


# ---------------------------------------------------------------------------
# The first course
# ---------------------------------------------------------------------------

func test_buying_and_playing_a_location_builds_its_first_course() -> void:
	# Drive the real row button: what the player clicks has to buy and play.
	var screen := _world_map_screen()
	assert_false(WorldMap.is_owned(FIRST_SITE), "Monterey starts unowned")
	var price := WorldMap.get_price(FIRST_SITE)
	var buy_and_play := _row_button(screen, FIRST_SITE)
	assert_not_null(buy_and_play, "The Monterey row has an action button")
	if buy_and_play == null:
		return
	assert_eq(buy_and_play.text, "Buy & Play", "The unowned row offers Buy & Play")
	buy_and_play.pressed.emit()
	await process_frames(12)
	assert_true(WorldMap.is_owned(FIRST_SITE), "Pressing Buy & Play buys Monterey")
	assert_between(GameManager.money, 200000 - price, 200000 - price + 5000,
		"Buying deducts the price; opening the course may add a little from fees and milestones")
	assert_null(_world_map_screen(), "Pressing Buy & Play closes the world map")
	assert_eq(GameManager.company_name, "Summit Golf Group", "The company name reaches the game")
	assert_eq(GameManager.current_difficulty, DifficultyPresets.Preset.HARD, "and the difficulty")
	assert_true(GameManager.wind_enabled, "The wind chosen on the setup screen is on in the new game")
	assert_true(SeasonSystem.disabled, "Seasons stay off by default")
	assert_eq(GameManager.current_course.holes.size(), 6, "The first course starts with its 6 generated holes")
	assert_true(GameManager.course_name.begins_with("Monterey"), "The course is named for its location")
	assert_eq(GameManager.current_theme, int(WorldLocations.get_definition(FIRST_SITE)["theme"]),
		"The course uses the location's theme")
	var land: LandManager = GameManager.land_manager
	for parcel in WorldMap.get_unlocked_parcels(FIRST_SITE):
		assert_true(land.owned_parcels.has(parcel), "The pre-cleared parcel %s is owned" % parcel)
	for parcel in WorldMap.get_location_parcels(FIRST_SITE):
		assert_true(parcel in land.location_parcels or land.location_parcels.is_empty(),
			"Parcel %s belongs to the location" % parcel)
	assert_eq(_holes_on_unowned_land(), 0, "Every generated hole sits on owned land")


func test_the_club_tab_opens_the_world_map_over_a_frozen_course() -> void:
	# The World Map lives on the Club tab, not in the pause menu.
	var money := GameManager.money
	main._show_pause_menu()
	await process_frames(2)
	assert_not_null(main.pause_menu, "The pause menu opens in game")
	if main.pause_menu:
		assert_false("World Map" in _labels_text(main.pause_menu), "The pause menu no longer offers the World Map")
	main._on_pause_resume()
	await process_frames(2)

	var map_button := _tool_button(main.terrain_toolbar, "world_map")
	assert_not_null(map_button, "The Club tab has the World Map button")
	if map_button == null:
		return
	map_button.pressed.emit()
	await process_frames(3)
	assert_not_null(_world_map_screen(), "The Club tab opens the world map")
	assert_eq(main.terrain_toolbar.current_tab, TerrainToolbar.Tab.CLUB, "The Club tab stays open behind it")
	assert_eq(GameManager.money, money, "Opening the world map does not change the money")
	assert_true(GameManager.is_paused, "The course freezes behind the world map")
	assert_false(main.bottom_bar.is_visible_in_tree(), "The gameplay UI steps aside for the world map")

	# Esc belongs to the map while it is up: the course behind it must not
	# answer it by opening the pause menu over the globe.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main.get_viewport().push_input(escape)
	await process_frames(3)
	assert_null(main.pause_menu, "Esc over the world map opens no pause menu")
	assert_null(_world_map_screen(), "Esc closes the world map like Back does")
	assert_false(GameManager.is_paused, "Esc hands the running course back")
	assert_true(main.bottom_bar.is_visible_in_tree(), "The gameplay UI comes back after Esc")

	# Back takes the same way out.
	map_button.pressed.emit()
	await process_frames(3)
	var screen := _world_map_screen()
	assert_not_null(screen, "The Club tab reopens the world map")
	if screen:
		screen.back_requested.emit()
	await process_frames(3)
	assert_null(_world_map_screen(), "Back closes the world map")
	assert_false(GameManager.is_paused, "Back resumes the course that was running")
	assert_true(main.bottom_bar.is_visible_in_tree(), "The gameplay UI comes back after Back")


func test_the_globe_turns_when_the_map_opens_from_the_club_tab() -> void:
	# The Club tab freezes the course behind the map, and a frozen simulation
	# (Engine.time_scale 0) used to stop the globe mid-flight and write its
	# frozen centre over every frame of a drag: the atlas looked stuck.
	_tool_button(main.terrain_toolbar, "world_map").pressed.emit()
	await process_frames(3)
	var screen := _world_map_screen()
	assert_not_null(screen, "The Club tab opens the world map")
	if screen == null:
		return
	assert_true(GameManager.is_paused, "The course behind the map is frozen")
	var globe: GlobeMap = screen.globe
	var before := globe.get_view_state()
	await drag(globe, Vector2(90.0, 30.0))
	var after := globe.get_view_state()
	assert_true(absf(float(after["center_lon"]) - float(before["center_lon"])) > 5.0,
		"Dragging turns the globe over a frozen course")
	assert_gt(float(after["center_lat"]), float(before["center_lat"]),
		"and tilts it the way the pointer moved")

	# The zoom buttons answer over a frozen course too.
	var radius: float = globe.get_view_state()["radius_scale"]
	var zoom_in := screen.find_child("ZoomIn", true, false) as Button
	assert_not_null(zoom_in, "The map has a zoom-in button")
	if zoom_in:
		zoom_in.pressed.emit()
	await process_frames(8)
	assert_gt(globe.get_view_state()["radius_scale"], radius, "Zooming in eases the globe closer")

	# ...and so does choosing a destination, which flies the globe round to it.
	var centre: float = globe.get_view_state()["center_lon"]
	globe.location_clicked.emit("japan")
	await process_frames(8)
	assert_true(absf(globe.get_view_state()["center_lon"] - centre) > 0.01,
		"Choosing a destination flies the globe towards it")

	screen.back_requested.emit()
	await process_frames(3)
	assert_null(_world_map_screen(), "Back closes the world map")
	assert_false(GameManager.is_paused, "Back hands the running course back")


func test_switching_locations_keeps_each_course_and_the_company_money() -> void:
	_tool_button(main.terrain_toolbar, "world_map").pressed.emit()
	await process_frames(3)
	var screen := _world_map_screen()
	assert_not_null(screen, "The world map is up")
	if screen == null:
		return
	assert_true(WorldMap.buy_location(SECOND_SITE), "A second location can be bought")
	# Mark the first course, so the switch back can be checked.
	var marker: GameManager.HoleData = GameManager.current_course.holes[0]
	marker.par_override = 5
	marker.total_revenue = 1234
	var first_holes := GameManager.current_course.holes.size()
	var first_cash := GameManager.money

	# The switch is synchronous, so the balance is compared exactly: money
	# belongs to the company, not to the site.
	screen.refresh()
	var play := _row_button(screen, SECOND_SITE)
	assert_eq(play.text if play else "", "Play", "The second location offers Play once it is owned")
	if play:
		play.pressed.emit()
	var cash_after_switch := GameManager.money
	assert_eq(WorldMap.active_location_id, SECOND_SITE, "The company plays the second location now")
	assert_eq(GameManager.current_theme, int(WorldLocations.get_definition(SECOND_SITE)["theme"]),
		"with its own theme")
	assert_eq(cash_after_switch, first_cash, "Switching locations keeps the company's money")
	await process_frames(12)
	assert_eq(GameManager.current_course.holes.size(), 0,
		"Generated holes are only laid on the first location bought")

	main._on_world_map_play_location(FIRST_SITE)
	var cash_after_return := GameManager.money
	# Read back before the course plays again: green fees add to the revenue.
	var revenue_after_return: int = GameManager.current_course.holes[0].total_revenue
	await process_frames(12)
	assert_eq(WorldMap.active_location_id, FIRST_SITE, "The company is back on the first location")
	assert_eq(GameManager.current_course.holes.size(), first_holes, "The first course kept its holes")
	assert_eq(GameManager.current_course.holes[0].par_override, 5, "and the par edited before leaving")
	assert_eq(revenue_after_return, 1234, "and the revenue edited before leaving")
	assert_lt(absi(cash_after_return - cash_after_switch), 20000, "Switching back keeps the company's money")


# ---------------------------------------------------------------------------
# A championship company, and Quick Start
# ---------------------------------------------------------------------------

func test_an_eighteen_hole_company_builds_and_saves_its_championship_course() -> void:
	main._on_menu_start_new_game()
	await process_frames(2)
	var setup = main.get_node("UI/HUD/StartNewGameScreen")
	setup._company_input.text = "Championship Holdings"
	setup._select_money(200000)
	setup._select_holes(18)
	setup._on_next_pressed()
	await process_frames(3)
	assert_true(WorldMap.buy_location(CHAMPIONSHIP_SITE), "A championship-sized location can be bought")
	main._on_world_map_play_location(CHAMPIONSHIP_SITE)
	assert_gt(GameManager.money, 0, "The purchase leaves the company solvent")
	await process_frames(14)
	assert_eq(WorldMap.active_location_id, CHAMPIONSHIP_SITE, "The company plays the championship site")
	assert_eq(GameManager.current_course.holes.size(), 18, "It gets all 18 generated holes")
	assert_eq(GameManager.current_course.total_par, 72, "The 18 holes play to par 72")
	assert_eq(_holes_on_unowned_land(), 0, "Every tee and green is on owned land")
	assert_gt(main.entity_layer.get_all_buildings().size(), 0, "The course comes with its clubhouse cluster")

	# A save keeps the locations the company owns, the one it plays and its money.
	var money := GameManager.money
	assert_true(SaveManager.save_game(SAVE_NAME), "The company world saves")
	assert_true(SaveManager.load_game(SAVE_NAME), "and loads")
	await process_frames(4)
	assert_true(WorldMap.is_owned(CHAMPIONSHIP_SITE), "A bought location survives the save")
	assert_eq(WorldMap.active_location_id, CHAMPIONSHIP_SITE, "The location being played is restored")
	assert_lt(absi(GameManager.money - money), 1000, "The company keeps its money")
	assert_eq(GameManager.current_course.holes.size(), 18, "The 18-hole course is restored")


func test_quick_start_buys_and_plays_a_location_of_its_own() -> void:
	main._on_menu_quick_start()
	await process_frames(3)
	assert_ne(WorldMap.active_location_id, "", "Quick Start plays a location")
	assert_true(WorldMap.is_owned(WorldMap.active_location_id), "that it bought")
	assert_eq(GameManager.current_course.holes.size(), 3, "Its course starts with 3 generated holes")
	assert_eq(WorldMap.difficulty, DifficultyPresets.Preset.NORMAL, "Quick Start plays on Normal")
	assert_eq(WorldMap.starting_money_option, 100000, "with $100,000")
	assert_eq(WorldMap.generated_holes, 3, "and a 3-hole course")
	for feature in WorldMapStateScript.quick_start_options()["features"]:
		assert_false(bool(WorldMap.features[feature]), "Quick Start leaves %s off" % feature)
	assert_gt(WorldMap.company_name.length(), 0, "Quick Start picks a company name")
