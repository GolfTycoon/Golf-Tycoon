extends MainSceneTest
## The Course Map over a real course: opened from the Club tab and with Shift+M,
## and its four modes editing the live game - buying land, moving holes, reading
## the golfers' mood and posting staff.
##
## Quick Start is the course here because every mode has something to work with
## on it: nine real holes with painted tees and greens, land still for sale, and
## golfers out on the course while the map is up.

const MODE_LAND := CourseMapView.Mode.LAND
const MODE_ROUTING := CourseMapView.Mode.ROUTING
const MODE_AURA := CourseMapView.Mode.AURA
const MODE_STAFF := CourseMapView.Mode.STAFF


func before_all() -> void:
	await super()
	await quick_start("Course map test")


## A test that opens the map closes it again, so the next one starts on the
## course with the day running.
func after_each() -> void:
	if main != null and main.course_map_screen != null:
		main._on_course_map_back()
	await super()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Open the map the way the hotkey does, in `mode` when one is given.
func open_map(mode: int = -1) -> CourseMapScreen:
	main._toggle_course_map()
	await process_frames(2)
	var screen: CourseMapScreen = main.course_map_screen
	if mode >= 0:
		screen.set_mode(mode)
		await process_frames(1)
	return screen


## The dock row whose action is `tool_type`, from the tab that holds it.
func dock_row(tab: int, tool_type: String) -> Button:
	main.terrain_toolbar.select_tab(tab)
	await process_frames(2)
	var page: Control = main.terrain_toolbar.page_content(tab)
	for node in nodes_of_class(page, "Button"):
		if node.get("tool_type") == tool_type:
			return node
	return null


## The buttons in the Routing panel whose tooltip is `tooltip` — the move arrows,
## one per hole, in play order.
func routing_rows(tooltip: String) -> Array:
	var panel: Control = main.course_map_screen._routing_panel
	var found: Array = []
	for node in nodes_of_class(panel, "Button"):
		if (node as Button).tooltip_text == tooltip:
			found.append(node)
	return found


func course() -> GameManager.CourseData:
	return GameManager.current_course


## Everything a panel shows: the labels and the words on its buttons, which is
## where a picker keeps most of its text.
func panel_words(panel: Control) -> String:
	var text := labels_text(panel)
	for node in nodes_of_class(panel, "Button"):
		text += (node as Button).text + "\n"
	return text


# ---------------------------------------------------------------------------
# Opening and closing
# ---------------------------------------------------------------------------

func test_the_maps_tab_row_opens_the_map_and_back_hands_the_course_back() -> void:
	assert_false(main._course_map_is_open(), "the map starts closed")
	var row := await dock_row(TerrainToolbar.Tab.CLUB, "course_map")
	assert_not_null(row, "the Maps tab carries a Course Map row")
	assert_eq(str(row.get("hotkey")), "Shift+M", "and says which key opens it")
	await click(row)
	await process_frames(2)

	assert_true(main._course_map_is_open(), "the row opens the Course Map")
	var screen: CourseMapScreen = main.course_map_screen
	assert_true(screen.visible)
	assert_eq(screen.size, main.get_node("UI/HUD").size, "the map takes the whole window")
	assert_true(GameManager.is_paused, "and freezes the day while it is up")
	assert_false(main.bottom_bar.visible, "the gameplay HUD steps out of the way")
	assert_eq(screen.layout, CourseMapScreen.layout_mode_for(Vector2(get_window().size)))

	var back := screen.find_child("BackButton", true, false) as Button
	await click(back)
	await process_frames(2)
	assert_false(main._course_map_is_open(), "Back closes the map")
	assert_eq(main.course_map_screen, null)
	assert_false(GameManager.is_paused, "and the day the map froze resumes")
	assert_true(main.bottom_bar.visible, "the gameplay HUD comes back")


func test_the_hotkey_toggles_the_map_and_its_own_keys_do_not_reach_the_course() -> void:
	var screen := await open_map()
	assert_true(main._course_map_is_open())

	# 2 is Routing while the map is up; on the course it is a terrain brush.
	press_key(KEY_2)
	await process_frames(1)
	assert_eq(screen.mode, MODE_ROUTING, "the map's own keys reach it")

	press_key(KEY_ESCAPE)
	await process_frames(2)
	assert_false(main._course_map_is_open(), "Escape closes the map")
	assert_false(GameManager.is_paused, "and hands the day back")


## The Holes tab's Holes Map card: the Course Map straight into Routing
## Holes, the mode that is the round the holes make.
func test_the_holes_tabs_map_card_opens_the_map_on_routing_holes() -> void:
	assert_false(main._course_map_is_open(), "the map starts closed")
	var card := await dock_row(TerrainToolbar.Tab.HOLES, "holes_map")
	assert_not_null(card, "the Holes tab carries a Holes Map card")
	assert_eq(str(card.get("tool_name")), "Holes Map", "and says what it is")

	await click(card)
	await process_frames(2)

	assert_true(main._course_map_is_open(), "the card opens the Course Map")
	assert_true(GameManager.is_paused, "and freezes the day like any entry")
	var screen: CourseMapScreen = main.course_map_screen
	assert_eq(screen.mode, MODE_ROUTING, "on Routing Holes")
	assert_eq(screen.map.mode, MODE_ROUTING, "and the map draws the route")
	assert_true(screen._routing_panel.visible, "with the Routing panel beside it")
	assert_eq(screen._routing_panel.get_parent(), screen._panel_scroll,
		"inside the panel frame")
	assert_string_contains(screen._strip_label.text, "Reorder the holes",
		"and the strip says what the mode is about")


## The Staff tab's Staff Map card: the Course Map straight into
## Staff, the mode that is the crew's ground.
func test_the_staff_tabs_map_card_opens_the_map_on_staff() -> void:
	assert_false(main._course_map_is_open(), "the map starts closed")
	var card := await dock_row(TerrainToolbar.Tab.STAFF, "staff_map")
	assert_not_null(card, "the Staff tab carries a Staff Map card")
	assert_eq(str(card.get("tool_name")), "Staff Map", "and says what it is")

	await click(card)
	await process_frames(2)

	assert_true(main._course_map_is_open(), "the card opens the Course Map")
	assert_true(GameManager.is_paused, "and freezes the day like any entry")
	var screen: CourseMapScreen = main.course_map_screen
	assert_eq(screen.mode, MODE_STAFF, "on Staff")
	assert_eq(screen.map.mode, MODE_STAFF, "and the map draws the crew's ground")
	assert_true(screen._staff_panel.visible, "with the Staff panel beside it")
	assert_eq(screen._staff_panel.get_parent(), screen._panel_scroll,
		"inside the panel frame")
	assert_string_contains(screen._strip_label.text, "Hire, fire",
		"and the strip says what the mode is about")


## Resizing the game window while the map is up (or turning a tablet) is the one
## thing the screen has to survive: the frames around the map are rebuilt, the
## map and the four panels are not, and the map keeps working afterwards.
func test_resizing_the_window_while_the_map_is_up_leaves_it_working() -> void:
	var screen := await open_map(MODE_LAND)
	var map := screen.map
	var panels: Array = screen._mode_panels()

	await set_window(Vector2i(768, 1024))
	assert_true(main._course_map_is_open(), "the map is still up after the resize")
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.TABLET_PORTRAIT, "reshaped for the new window")
	assert_eq(screen.map, map, "the same map control came through it, so the view is unchanged")
	await set_window(Vector2i(1600, 1000))
	assert_eq(screen.layout, MenuScreenKit.LayoutMode.DESKTOP, "and again on the way back")

	for i in panels.size():
		assert_true(is_instance_valid(panels[i]), "panel %d survived the reshape" % i)
		assert_eq(screen._mode_panels()[i], panels[i], "and it is the same panel, not a new one")
	for entry in CourseMapScreen.MODES:
		screen.set_mode(int(entry["mode"]))
		await process_frames(1)
		assert_eq(screen._panel_for_mode().get_parent(), screen._panel_scroll,
			"the %s panel is back in the frame" % str(entry["name"]))

	# The map is still live: its own keys reach it and it still backs out.
	screen.set_mode(MODE_LAND)
	press_key(KEY_3)
	await process_frames(1)
	assert_eq(screen.mode, MODE_AURA, "the map's own keys still reach it")
	press_key(KEY_ESCAPE)
	await process_frames(2)
	assert_false(main._course_map_is_open(), "and it still backs out")
	assert_false(GameManager.is_paused, "handing the day back")


func test_every_mode_shows_its_own_read_of_the_course() -> void:
	var screen := await open_map(MODE_LAND)
	assert_eq(course().holes.size(), 9, "the Quick Start course has nine holes")
	for entry in CourseMapScreen.MODES:
		screen.set_mode(int(entry["mode"]))
		await process_frames(1)
		assert_eq(screen.map.mode, int(entry["mode"]), "the map follows the mode")
		var panel: Control = screen._panel_for_mode()
		assert_true(panel.visible, "the mode's panel is shown")
		assert_eq(panel.get_parent(), screen._panel_scroll, "inside the panel frame")
		assert_gte(screen.map.legend_entries().size(), 3, "each mode explains its colours")
		assert_string_contains(screen._strip_label.text, str(entry["blurb"]).substr(0, 10),
			"the strip says what the mode is about")

	screen.set_mode(MODE_ROUTING)
	assert_string_contains(screen._panel_summary(), "9 holes", "Routing counts the round")
	screen.set_mode(MODE_LAND)
	assert_string_contains(screen._panel_summary(), "parcels", "Land counts the property")
	screen.set_mode(MODE_STAFF)
	assert_string_contains(screen._panel_summary(), "crew", "Staff counts the payroll")
	assert_string_contains(panel_words(screen._staff_panel), "Hire staff",
		"and the panel carries the hire desk")


# ---------------------------------------------------------------------------
# Land
# ---------------------------------------------------------------------------

func test_a_parcel_is_bought_from_the_map_through_the_strip() -> void:
	var screen := await open_map(MODE_LAND)
	var land: LandManager = GameManager.land_manager
	GameManager.money = 500000
	var for_sale: Array = land.get_purchasable_parcels()
	assert_gt(for_sale.size(), 0, "there is land to buy next to the course")
	var owned_before: int = land.owned_parcels.size()
	var money_before: int = GameManager.money

	# A tap on a for-sale parcel offers it: the strip is where the money goes.
	var parcel: Vector2i = for_sale[0]
	var cost: int = land.get_parcel_cost(parcel)
	var tile: Vector2i = land.parcel_to_tile_rect(parcel).position + Vector2i(2, 2)
	screen._on_map_pressed(tile, {"kind": "parcel", "value": parcel})
	await process_frames(1)
	assert_eq(screen.offer.get("kind", ""), "buy", "the tap offers the parcel")
	assert_eq(Vector2i(screen.selection["value"]), parcel, "and picks it")
	assert_string_contains(screen._strip_label.text, "buy it for", "the strip asks the price")
	var buy_button := screen.find_child("StripBuy", true, false) as Button
	assert_not_null(buy_button, "the strip carries the buy button")
	await click(buy_button)
	await process_frames(2)

	assert_true(land.owned_parcels.has(parcel), "the parcel is bought")
	assert_eq(land.owned_parcels.size(), owned_before + 1)
	assert_eq(GameManager.money, money_before - cost, "the price came out of the company's cash")
	assert_true(screen.offer.is_empty(), "and the offer is settled")
	assert_true(land.get_parcel_tier(parcel) == LandManager.TIER_STANDARD \
		or land.has_features_generated(parcel),
		"a premium parcel arrives with its own terrain, generated behind the map")
	assert_string_contains(screen._panel_summary(), str(land.owned_parcels.size()),
		"the panel counts the new parcel among the company's land")


func test_a_parcel_that_is_not_for_sale_is_only_read() -> void:
	var screen := await open_map(MODE_LAND)
	var land: LandManager = GameManager.land_manager
	var owned: Vector2i = land.owned_parcels.keys()[0]
	var money_before: int = GameManager.money
	screen._on_map_pressed(land.parcel_to_tile_rect(owned).position, {"kind": "parcel", "value": owned})
	await process_frames(1)
	assert_true(screen.offer.is_empty(), "land the company owns is not for sale to it")
	assert_string_contains(screen._strip_label.text, "you own", "the strip reads the parcel out")
	assert_eq(GameManager.money, money_before)


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

func test_a_hole_is_moved_up_the_round_and_everything_follows_it() -> void:
	await open_map(MODE_ROUTING)
	var second = course().holes[1]
	var second_tee: Vector2i = second.tee_position
	var reordered: Array = []
	var watcher := func(order: Array): reordered.append(order)
	EventBus.holes_reordered.connect(watcher)

	var arrows := routing_rows("Play this hole earlier")
	assert_eq(arrows.size(), 9, "one move-up arrow per hole")
	await click(arrows[1])
	await process_frames(2)

	EventBus.holes_reordered.disconnect(watcher)
	assert_eq(course().holes[0], second, "hole 2 now leads the round")
	assert_eq(int(course().holes[0].hole_number), 1, "and is renumbered")
	assert_eq(int(course().holes[1].hole_number), 2, "the hole it displaced took its place")
	assert_eq(course().holes[0].tee_position, second_tee, "the hole itself stayed where it is painted")
	assert_eq(reordered.size(), 1, "the course announced the new order")
	assert_eq(reordered[0].size(), 9)
	assert_eq(int(reordered[0][0]), 1, "with the holes numbered in the new order")
	assert_eq(main.hole_manager.get_all_hole_visualizers().size(), 9, "every hole's marker was rebuilt")


func test_a_hole_is_turned_around_and_the_round_played_backwards() -> void:
	var screen := await open_map(MODE_ROUTING)
	var grid: TerrainGrid = GameManager.terrain_grid
	var hole = course().holes[2]
	var old_tee: Vector2i = hole.tee_position
	var old_green: Vector2i = hole.green_position
	assert_eq(grid.get_tile(old_tee), TerrainTypes.Type.TEE_BOX)
	assert_eq(grid.get_tile(old_green), TerrainTypes.Type.GREEN)

	screen._on_hole_flip(int(hole.hole_number))
	await process_frames(2)
	assert_eq(hole.tee_position, old_green, "the green became the tee")
	assert_eq(hole.green_position, old_tee, "and the tee became the green")
	assert_eq(grid.get_tile(old_green), TerrainTypes.Type.TEE_BOX, "the tiles swapped with the hole")
	assert_eq(grid.get_tile(old_tee), TerrainTypes.Type.GREEN)
	assert_true(grid.get_cup_tiles().has(old_tee), "the cup was cut in the new green")
	assert_false(grid.get_cup_tiles().has(old_green), "and lifted out of the old one")
	assert_eq(Vector2(hole.tee_position).distance_to(Vector2(hole.green_position)),
		Vector2(old_tee).distance_to(Vector2(old_green)), "the hole is the same length, played the other way")

	var first = course().holes[0]
	var last = course().holes[8]
	screen._on_holes_reverse()
	await process_frames(2)
	assert_eq(course().holes[0], last, "the last hole now leads")
	assert_eq(course().holes[8], first)
	assert_eq(int(course().holes[0].hole_number), 1, "the round is renumbered")
	assert_eq(int(course().holes[8].hole_number), 9)


func test_the_par_of_a_hole_can_be_changed_from_the_panel() -> void:
	var screen := await open_map(MODE_ROUTING)
	var hole = course().holes[0]
	var par_before: int = hole.par
	screen._on_hole_par(int(hole.hole_number), par_before + 1)
	await process_frames(2)
	assert_eq(hole.par, par_before + 1, "the panel's P button sets the par by hand")
	assert_eq(hole.par_override, par_before + 1, "which the hole remembers as an override")
	var par_sum: int = 0
	for entry in course().holes:
		par_sum += int(entry.par)
	assert_eq(int(course().total_par), par_sum, "the course's par follows the holes")


func test_a_hole_is_closed_and_opened_again_from_the_panel() -> void:
	var screen := await open_map(MODE_ROUTING)
	var hole = course().holes[3]
	var was_open: bool = hole.is_open
	screen._on_hole_toggle(int(hole.hole_number))
	await process_frames(2)
	assert_eq(hole.is_open, not was_open, "the panel closes the hole")
	screen._on_hole_toggle(int(hole.hole_number))
	await process_frames(2)
	assert_eq(hole.is_open, was_open, "and opens it again")


# ---------------------------------------------------------------------------
# Course Aura
# ---------------------------------------------------------------------------

func test_the_aura_mode_reads_where_golfers_were_happy_and_unhappy() -> void:
	var aura: CourseAura = GameManager.course_aura
	assert_not_null(aura, "the course tracks its golfers' mood")
	# Whatever the golfers out on the course have said so far, this test says
	# where the good and the bad ground is.
	aura.clear()
	var happy_hole = course().holes[1]
	var unhappy_hole = course().holes[4]
	for i in 4:
		aura.record_at(happy_hole.tee_position, FeedbackTriggers.TriggerType.NICE_COURSE, "positive", 2)
		aura.record_at(unhappy_hole.green_position, FeedbackTriggers.TriggerType.SLOW_PACE, "negative", 5)
	var happy_spots: Array = aura.hotspots("positive")
	var trouble_spots: Array = aura.hotspots("negative")
	assert_eq(happy_spots.size(), 1, "the aura reports the happy spot")
	assert_eq(trouble_spots.size(), 1, "and the unhappy one")
	var happy_where := str(happy_spots[0]["where"])
	var trouble_where := str(trouble_spots[0]["where"])

	var screen := await open_map(MODE_AURA)
	var panel_text := panel_words(screen._aura_panel)
	assert_string_contains(panel_text, "Happiest spots", "the panel names the happy ground")
	assert_string_contains(panel_text, "Trouble spots", "and the unhappy ground")
	assert_string_contains(panel_text, happy_where, "in the words of the hole it is on")
	assert_string_contains(panel_text, trouble_where)
	assert_string_contains(panel_text, "Liked the course", "with the compliments behind it")
	assert_string_contains(panel_text, "Slow play", "and the complaints behind the other")

	# The map is the way back to the ground: a hotspot row sends the map there.
	var rows := screen._aura_panel.find_children("*", "Button", true, false)
	var picked := false
	for node in rows:
		if (node as Button).button_pressed:
			picked = true
	assert_false(picked, "nothing is picked to begin with")
	screen._select("aura", CourseAura.cell_of(unhappy_hole.green_position))
	await process_frames(1)
	assert_string_contains(screen._strip_label.text, trouble_where, "the strip reads the hotspot out")
	assert_string_contains(screen._strip_label.text, "unhappy", "with the mood of the ground on it")
	aura.clear()


# ---------------------------------------------------------------------------
# Staff
# ---------------------------------------------------------------------------

func test_staff_are_hired_posted_moved_and_let_go_from_the_map() -> void:
	var screen := await open_map(MODE_STAFF)
	var manager: StaffManager = GameManager.staff_manager
	assert_eq(manager.hired_staff.size(), 0, "the crew starts empty")
	GameManager.money = 100000

	# Hiring is two steps: pick a job in the panel, then tap the course.
	screen._on_staff_hire_armed(StaffManager.StaffType.GROUNDSKEEPER)
	await process_frames(1)
	assert_eq(screen.pending.get("kind", ""), "hire_staff", "the panel arms the map")
	assert_string_contains(screen._strip_label.text, "Tap the map", "and the strip says what to do")
	assert_eq(screen.map.pending.get("value", -1), StaffManager.StaffType.GROUNDSKEEPER,
		"the map is waiting for the same hire")

	var first_tile := Vector2i(30, 30)
	screen._on_map_pressed(first_tile, {})
	await process_frames(2)
	assert_eq(manager.hired_staff.size(), 1, "the tap hired the groundskeeper")
	assert_true(screen.pending.is_empty(), "and put the instruction away")
	assert_eq(Vector2i(manager.hired_staff[0].area_center), first_tile, "based where the map was tapped")
	assert_eq(int(screen.selection["value"]), 0, "and picked, so the strip reads them out")
	assert_string_contains(screen._strip_label.text, "Groundskeeper")

	# Move: the same two steps, on the employee already hired.
	screen._on_staff_move_requested(0)
	await process_frames(1)
	assert_eq(screen.pending.get("kind", ""), "move_staff")
	var second_tile := Vector2i(60, 44)
	screen._on_map_pressed(second_tile, {})
	await process_frames(2)
	assert_eq(Vector2i(manager.hired_staff[0].area_center), second_tile, "the area moved")
	assert_eq(manager.get_staff_area(0), second_tile)

	# Firing asks first.
	screen._on_staff_fire_requested(0)
	await process_frames(2)
	var dialog := screen.find_children("*", "PanelContainer", true, false)
	assert_gt(dialog.size(), 0, "firing opens a confirmation")
	var fire_button: Button = null
	for node in nodes_of_class(screen, "Button"):
		if (node as Button).text == "Fire":
			fire_button = node
	assert_not_null(fire_button, "with a Fire button on it")
	await click(fire_button)
	await process_frames(2)
	assert_eq(manager.hired_staff.size(), 0, "the Fire button lets them go")
	assert_string_contains(screen._panel_summary(), "0 on the crew")


func test_a_hire_that_is_armed_twice_is_put_away() -> void:
	var screen := await open_map(MODE_STAFF)
	GameManager.money = 100000
	screen._on_staff_hire_armed(StaffManager.StaffType.CLUB_PRO)
	await process_frames(1)
	assert_false(screen.pending.is_empty(), "the first tap arms the hire")
	screen._on_staff_hire_armed(StaffManager.StaffType.CLUB_PRO)
	await process_frames(1)
	assert_true(screen.pending.is_empty(), "tapping the same job again puts it away")
	assert_eq(GameManager.staff_manager.hired_staff.size(), 0, "and nobody was hired")


func test_a_hire_the_company_cannot_afford_is_refused_before_the_map_is_armed() -> void:
	var screen := await open_map(MODE_STAFF)
	GameManager.unlimited_money = false
	# Already at the bankruptcy floor: a day of a premium wage would take the
	# company under it, so the hire is refused before it is armed.
	GameManager.money = GameManager.bankruptcy_threshold
	screen._on_staff_hire_armed(StaffManager.StaffType.CELEBRITY)
	await process_frames(1)
	assert_true(screen.pending.is_empty(), "nothing is armed for a hire that cannot be paid for")
	assert_eq(GameManager.staff_manager.hired_staff.size(), 0)
