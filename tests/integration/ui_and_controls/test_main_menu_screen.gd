extends MainSceneTest
## The title screen at phone, rotated-phone, tablet and desktop window sizes:
## each of its four arrangements (see MainMenu.layout_mode_for) puts all seven
## actions on screen, apart and big enough to tap; the game's name is the logo
## image rather than a typed wordmark, with no tagline under it; and a drawn
## backdrop covers the window behind the menu.

const ACTIONS := ["Start New Game", "Quick Start", "Continue", "Load Game", "Golfer Skins", "Settings", "Quit"]


func _menu() -> Control:
	return main.main_menu


## Everything that has to hold for the seven actions at one window size.
func _assert_screen(tag: String, size: Vector2i, min_height: float) -> void:
	var menu := _menu()
	var buttons := nodes_of_class(menu, "Button")
	var labels: Array = []
	for button in buttons:
		labels.append(button.text)
	assert_eq(buttons.size(), ACTIONS.size(), "%s: seven actions" % tag)
	for expected in ACTIONS:
		assert_has(labels, expected, "%s: has a %s action" % [tag, expected])

	# Every word on the screen is set in Pixelify Sans, at every window size:
	# the action titles in the bold weight, the captions, kicker and version
	# line in the regular one (see test_main_menu_typography.gd).
	for button in buttons:
		var title_path := str((button as Button).get_theme_font("font").resource_path)
		assert_true(title_path.ends_with("PixelifySans-Bold.ttf")
				or title_path.ends_with("PixelifySans-SemiBold.ttf"),
			"%s: the %s title is set in a Pixelify Sans title weight" % [tag, (button as Button).text])
	for label in nodes_of_class(menu, "Label"):
		assert_true(str((label as Label).get_theme_font("font").resource_path)
				.ends_with("PixelifySans-Regular.ttf"),
			"%s: the %s line is set in Pixelify Sans" % [tag, (label as Label).name])

	var view := Rect2(Vector2.ZERO, Vector2(size))
	var too_small: Array = []
	var off_screen: Array = []
	var overlaps: Array = []
	for i in buttons.size():
		var rect: Rect2 = buttons[i].get_global_rect()
		if rect.size.y < min_height - 0.5 or rect.size.x < 60.0:
			too_small.append("%s %s" % [buttons[i].text, rect.size])
		if not rect_within(rect, view):
			off_screen.append("%s %s" % [buttons[i].text, rect])
		for j in range(i + 1, buttons.size()):
			if rect.intersects(buttons[j].get_global_rect(), false):
				overlaps.append("%s / %s" % [buttons[i].text, buttons[j].text])
	assert_eq(too_small, [], "%s: every action is a big enough target" % tag)
	assert_eq(off_screen, [], "%s: every action is on screen" % tag)
	assert_eq(overlaps, [], "%s: no two actions overlap" % tag)

	# The game's name is the logo, on screen, not a typed "Golf Tycoon" heading.
	var title := menu.find_child("Title", true, false) as TextureRect
	assert_not_null(title, "%s: the title is an image" % tag)
	if title:
		assert_true(title.texture != null and str(title.texture.resource_path).ends_with("logo.png"),
			"%s: the title is the logo" % tag)
		var title_rect := title.get_global_rect()
		assert_true(rect_within(title_rect, view) and title_rect.size.x > 48.0 and title_rect.size.y > 32.0,
			"%s: the logo is on screen, at a readable size: %s" % [tag, title_rect])
	assert_false("Golf Tycoon\n" in labels_text(menu), "%s: the game's name is not also typed out" % tag)
	_assert_icons(tag, size)
	var backdrop := menu.get_node_or_null("Backdrop") as Control
	assert_not_null(backdrop, "%s: a drawn backdrop sits behind the menu" % tag)
	if backdrop:
		assert_eq(backdrop.get_global_rect().size, Vector2(size), "%s: the backdrop covers the window" % tag)


## Every action wears its pixel sprite where the layout has room: the three
## way-into-the-game cards always, and the utility tiles wherever they keep
## their caption - the squat and phone layouts drop captions to save width,
## and a tile too narrow for a sentence is too narrow for an emblem.
func _assert_icons(tag: String, size: Vector2i) -> void:
	var cards := ["Start New Game", "Quick Start", "Continue"]
	var mode := MainMenu.layout_mode_for(Vector2(size))
	var roomy := mode == MainMenu.Layout.WIDE or mode == MainMenu.Layout.TABLET
	for button in nodes_of_class(_menu(), "Button"):
		var expected := cards.has(button.text) or roomy
		assert_eq(button.icon != null, expected,
			"%s: the %s card %s" % [tag, button.text,
			"carries its sprite" if expected else "drops its sprite with its caption"])


## Continue carries the newest save's course name when there is one; with no
## saves it is disabled and says why.
func _assert_continue(tag: String) -> void:
	var button: Button = _menu()._continue_button
	assert_not_null(button, "%s: the Continue card exists" % tag)
	if button == null:
		return
	var saves: Array = SaveManager.get_save_list()
	if saves.is_empty():
		assert_true(button.disabled, "%s: Continue is disabled with no saves" % tag)
		assert_string_contains(button.tooltip_text, "No saved", "%s: and explains why" % tag)
	else:
		assert_false(button.disabled, "%s: Continue is live with a save on file" % tag)
		var caption := button.find_child("Caption", true, false) as Label
		assert_true(caption != null and str(saves[0].get("course_name", "")) in caption.text,
			"%s: Continue names the newest course" % tag)


func test_a_phone_gets_one_scrollable_column_of_big_targets() -> void:
	await set_window(Vector2i(390, 844))
	assert_not_null(_menu(), "The game opens on the title screen")
	assert_eq(_menu()._layout_mode, MainMenu.Layout.PHONE, "390x844 uses the phone layout")
	_assert_screen("phone portrait", Vector2i(390, 844), 44.0)
	_assert_continue("phone portrait")


func test_a_rotated_phone_fits_without_scrolling() -> void:
	await set_window(Vector2i(844, 390))
	assert_eq(_menu()._layout_mode, MainMenu.Layout.LANDSCAPE, "844x390 uses the landscape layout")
	_assert_screen("rotated phone", Vector2i(844, 390), 40.0)
	assert_false(scrolls(_menu()), "A rotated phone fits without scrolling")


func test_a_tablet_gets_a_centred_column() -> void:
	await set_window(Vector2i(768, 1024))
	assert_eq(_menu()._layout_mode, MainMenu.Layout.TABLET, "768x1024 uses the tablet layout")
	_assert_screen("tablet portrait", Vector2i(768, 1024), 44.0)
	await set_window(Vector2i(1024, 768))
	assert_eq(_menu()._layout_mode, MainMenu.Layout.TABLET, "1024x768 uses the tablet layout")
	_assert_screen("tablet", Vector2i(1024, 768), 44.0)
	assert_false(scrolls(_menu()), "A 1024x768 tablet fits without scrolling")


func test_a_desktop_spreads_the_menu_across_the_window() -> void:
	await set_window(Vector2i(1600, 1000))
	assert_eq(_menu()._layout_mode, MainMenu.Layout.WIDE, "1600x1000 uses the wide layout")
	_assert_screen("desktop", Vector2i(1600, 1000), 44.0)
	assert_false(scrolls(_menu()), "A desktop fits without scrolling")
	# Not a narrow centre strip: the outermost actions are far apart.
	var left := INF
	var right := -INF
	for button in nodes_of_class(_menu(), "Button"):
		left = minf(left, button.get_global_rect().position.x)
		right = maxf(right, button.get_global_rect().end.x)
	assert_gte(right - left, 1600.0 * 0.6, "The desktop layout spreads across the window")
	_assert_continue("desktop")
	await set_window(Vector2i(2560, 1440))
	assert_eq(_menu()._layout_mode, MainMenu.Layout.WIDE, "2560x1440 uses the wide layout")
	_assert_screen("large desktop", Vector2i(2560, 1440), 44.0)


func test_the_phone_layout_comes_back_without_a_tagline() -> void:
	await set_window(Vector2i(390, 844))
	assert_eq(_menu()._layout_mode, MainMenu.Layout.PHONE, "The phone layout returns when the window shrinks back")
	_assert_screen("phone portrait again", Vector2i(390, 844), 44.0)
	assert_false("Design. Build. Manage." in labels_text(_menu()), "No tagline sits under the title any more")
