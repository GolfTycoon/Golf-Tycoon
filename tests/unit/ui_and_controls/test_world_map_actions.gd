extends GameTest
## World Map destination cards: every unowned site offers Buy & Play, which
## buys the land and asks to start that course in one press. The selected-site
## dossier also offers Buy, which purchases without leaving the map. Owned
## sites offer Play (or Playing for the course already under way).

const WorldMapStateScript := preload("res://scripts/autoload/world_map_state.gd")

func _screen() -> WorldMapScreen:
	var screen := autofree(WorldMapScreen.new()) as WorldMapScreen
	add_child(screen)
	return screen


func _row_action(screen: WorldMapScreen, location_id: String) -> Button:
	var row = screen._rows.get(location_id)
	if row == null:
		return null
	return row.find_child("LocationAction", true, false) as Button


func test_company_cash_is_visible_and_updates_in_the_treasury() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 90210)
	GameManager.money = 123456
	var screen := _screen()
	await process_frames(2)

	var cash := screen.find_child("Money", true, false) as Label
	assert_not_null(cash, "the treasury has a company-cash label")
	if cash == null:
		return
	var compact := (
		screen._layout_mode == MenuScreenKit.LayoutMode.PHONE_LANDSCAPE
		or screen._layout_mode == MenuScreenKit.LayoutMode.PHONE_PORTRAIT)
	assert_eq(cash.text, "$123K" if compact else "$123,456",
		"the World Map displays the current company balance")
	var text_width := cash.get_theme_font("font").get_string_size(
		cash.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cash.get_theme_font_size("font_size")).x
	assert_gte(cash.size.x, text_width,
		"the treasury allocates enough space for the balance instead of clipping it")

	GameManager.modify_money(1000)
	await process_frames(2)
	assert_eq(cash.text, "$124K" if compact else "$124,456",
		"the displayed balance changes when company cash changes")


func test_every_unowned_location_offers_buy_and_play() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 20261013)
	GameManager.money = 500000
	var screen := _screen()
	assert_eq(screen._rows.size(), WorldLocations.get_all().size(), "every destination has a card")
	for def in WorldLocations.get_all():
		var id := str(def["id"])
		var action := _row_action(screen, id)
		assert_not_null(action, "%s has a Buy & Play button" % id)
		if action == null:
			continue
		assert_eq(action.text, WorldMapScreen.BUY_AND_PLAY_LABEL, "%s is labelled Buy & Play" % id)
		assert_eq(action.disabled, not WorldMap.can_afford(id),
			"%s is disabled only when it is out of reach" % id)


func test_buy_and_play_buys_the_site_and_asks_to_start_it() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 4242)
	GameManager.money = 500000
	var screen := _screen()
	var site := "ireland"
	var price := WorldMap.get_price(site)
	var played: Array = []
	screen.play_location_requested.connect(func(id: String): played.append(id))
	var action := _row_action(screen, site)
	assert_not_null(action, "Ireland has a Buy & Play button")
	if action == null:
		return
	action.pressed.emit()
	await process_frames(2)
	assert_true(WorldMap.is_owned(site), "Buy & Play buys the site")
	assert_eq(GameManager.money, 500000 - price, "and deducts the asking price")
	assert_eq(played, [site], "and asks to start playing it")


func test_buy_and_play_does_nothing_when_the_site_is_out_of_reach() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 777)
	GameManager.money = 100
	GameManager.bankruptcy_threshold = -1000
	var screen := _screen()
	var site := "scotland"
	assert_false(WorldMap.can_afford(site), "Scotland costs more than $100")
	var played: Array = []
	screen.play_location_requested.connect(func(id: String): played.append(id))
	var action := _row_action(screen, site)
	assert_not_null(action)
	if action:
		assert_true(action.disabled, "Buy & Play is disabled when funds fall short")
		assert_eq(action.text, WorldMapScreen.BUY_AND_PLAY_LABEL)
	screen._on_buy_and_play_pressed(site)
	assert_false(WorldMap.is_owned(site), "an unaffordable site is not bought")
	assert_eq(played, [], "and play is not requested")


func test_owned_locations_offer_play_instead() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 5150)
	GameManager.money = 1000000
	assert_true(WorldMap.buy_location("monterey"))
	WorldMap.set_active_location("monterey")
	assert_true(WorldMap.buy_location("florida"))
	var screen := _screen()
	var playing := _row_action(screen, "monterey")
	assert_not_null(playing)
	if playing:
		assert_eq(playing.text, "Playing", "the current course shows Playing")
		assert_true(playing.disabled, "and cannot be pressed again")
	var play := _row_action(screen, "florida")
	assert_not_null(play)
	if play:
		assert_eq(play.text, "Play", "another owned site offers Play")
		assert_false(play.disabled)
	var unowned := _row_action(screen, "hawaii")
	assert_not_null(unowned)
	if unowned:
		assert_eq(unowned.text, WorldMapScreen.BUY_AND_PLAY_LABEL, "unowned sites still offer Buy & Play")


func test_the_selected_site_dossier_offers_buy_and_buy_and_play() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 2468)
	GameManager.money = 500000
	var screen := _screen()
	screen.select_location("hawaii")
	var buy := screen._featured_buy
	var play := screen._featured_action
	assert_not_null(buy, "the dossier has a Buy button")
	assert_not_null(play, "and a Buy & Play button")
	if buy == null or play == null:
		return
	assert_true(buy.visible, "Buy is shown for an unowned site")
	assert_true(
		buy.text == WorldMapScreen.BUY_LABEL or buy.text.begins_with("BUY"),
		"Buy is labelled Buy (%s)" % buy.text)
	assert_true(
		play.text == WorldMapScreen.BUY_AND_PLAY_LABEL
		or play.text.begins_with("BUY & PLAY"),
		"the selected unowned site offers Buy & Play (%s)" % play.text)
	assert_false(buy.disabled)
	assert_false(play.disabled)
	var played: Array = []
	screen.play_location_requested.connect(func(id: String): played.append(id))
	play.pressed.emit()
	await process_frames(2)
	assert_true(WorldMap.is_owned("hawaii"), "Buy & Play buys the site")
	assert_eq(played, ["hawaii"], "and asks to start playing it")


func test_the_dossier_buy_button_purchases_without_starting() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 1357)
	GameManager.money = 500000
	var screen := _screen()
	screen.select_location("wales")
	var price := WorldMap.get_price("wales")
	var played: Array = []
	screen.play_location_requested.connect(func(id: String): played.append(id))
	var buy := screen._featured_buy
	assert_not_null(buy, "the dossier has a Buy button")
	if buy == null:
		return
	buy.pressed.emit()
	await process_frames(2)
	assert_true(WorldMap.is_owned("wales"), "Buy purchases the site")
	assert_eq(GameManager.money, 500000 - price, "and deducts the asking price")
	assert_eq(played, [], "but does not start playing it")
	assert_true(screen.visible, "the map stays open so more sites can be browsed")
	assert_false(screen._featured_buy.visible, "Buy hides once the site is owned")
	assert_true(
		screen._featured_action.text == "Play"
		or screen._featured_action.text == "PLAY THIS COURSE",
		"the dossier then offers Play (%s)" % screen._featured_action.text)


func test_an_owned_site_dossier_offers_play_only() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 888)
	GameManager.money = 1000000
	assert_true(WorldMap.buy_location("monterey"))
	WorldMap.set_active_location("monterey")
	assert_true(WorldMap.buy_location("florida"))
	var screen := _screen()
	screen.select_location("monterey")
	assert_false(screen._featured_buy.visible, "Buy is hidden on the current course")
	assert_true(
		screen._featured_action.text == "Playing now"
		or screen._featured_action.text == "CURRENT COURSE")
	assert_true(screen._featured_action.disabled)
	screen.select_location("florida")
	assert_false(screen._featured_buy.visible, "Buy is hidden on an owned site")
	assert_true(
		screen._featured_action.text == "Play"
		or screen._featured_action.text == "PLAY THIS COURSE",
		"an owned site offers Play")
	assert_false(screen._featured_action.disabled)


func test_clicking_a_list_row_centres_the_globe_on_that_location() -> void:
	WorldMap.new_world(WorldMapStateScript.default_options(), 1357)
	GameManager.money = 500000
	var screen := _screen()
	await process_frames(2)
	var site := "wales"
	var def := WorldLocations.get_definition(site)
	var row = screen._rows.get(site)
	assert_not_null(row, "Wales has a list row")
	if row == null:
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._on_row_input(click, site)
	assert_eq(screen._selected_id, site, "the row click selects the site")
	assert_true(screen.globe._animating, "and starts the globe flying towards it")
	assert_almost_eq(screen.globe._anim_to_lat, float(def["lat"]), 0.001, "aimed at the site's latitude")
	assert_almost_eq(screen.globe._anim_to_lon, float(def["lon"]), 0.001, "aimed at the site's longitude")


# ---------------------------------------------------------------------------
# Reset World: the confirmation sits on top of the globe
# ---------------------------------------------------------------------------
#
# The globe reads raw touches itself, so before the dialogue learned to look at
# what is drawn over it, every tap inside the globe's rectangle went to the
# globe — including taps on the Reset World confirmation's buttons, which made
# them impossible to answer on a touchscreen.

func _open_reset_confirmation(screen: WorldMapScreen) -> ConfirmDialog:
	var reset := screen.find_child("ResetWorldButton", true, false) as Button
	assert_not_null(reset, "the World Map offers Reset World")
	if reset == null:
		return null
	reset.pressed.emit()
	await process_frames(3)
	for child in screen.get_children():
		if child is ConfirmDialog:
			return child
	return null


func test_reset_world_confirmation_answers_a_touch_confirm() -> void:
	await resize_window(Vector2i(1600, 1000))
	WorldMap.new_world(WorldMapStateScript.default_options(), 90210)
	GameManager.money = 500000
	var screen := _screen()
	await process_frames(3)
	var dialog := await _open_reset_confirmation(screen)
	assert_not_null(dialog, "the confirmation opens")
	if dialog == null:
		return
	var confirmed: Array = []
	dialog.confirmed.connect(func() -> void: confirmed.append(true))
	var confirm_btn := dialog.find_child("ConfirmButton", true, false) as Button
	assert_not_null(confirm_btn, "the confirmation has its Reset World answer")
	assert_false(TouchInput._has_native_touch_target(confirm_btn.get_global_rect().get_center()),
		"the dialogue on top owns the touch, not the globe underneath it")
	await touch_tap(confirm_btn.get_global_rect().get_center())
	assert_eq(confirmed.size(), 1, "a tap on Reset World confirms")
	assert_false(is_instance_valid(dialog), "and the confirmation closes")


func test_reset_world_confirmation_answers_a_touch_cancel() -> void:
	await resize_window(Vector2i(1280, 800))
	WorldMap.new_world(WorldMapStateScript.default_options(), 90210)
	GameManager.money = 500000
	var screen := _screen()
	await process_frames(3)
	var dialog := await _open_reset_confirmation(screen)
	assert_not_null(dialog, "the confirmation opens")
	if dialog == null:
		return
	var cancelled: Array = []
	dialog.cancelled.connect(func() -> void: cancelled.append(true))
	var keep_btn := dialog.find_child("CancelButton", true, false) as Button
	assert_not_null(keep_btn, "the confirmation has its Keep World answer")
	await touch_tap(keep_btn.get_global_rect().get_center())
	assert_eq(cancelled.size(), 1, "a tap on Keep World cancels")
	assert_false(is_instance_valid(dialog), "and the confirmation closes")
