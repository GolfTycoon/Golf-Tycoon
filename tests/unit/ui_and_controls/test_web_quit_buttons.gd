extends GameTest
## Application-exit controls are useful in native builds, but not in a browser:
## the tab or window already owns that action. Returning to the title screen is
## a different action and stays available on every platform.

const WEB_MAIN_ACTIONS := [
	"Start New Game", "Quick Start", "Tournament Mode", "Continue", "Load Game",
	"Achievements", "Golfer Skins", "Mods", "Settings",
]
const LAYOUT_SIZES := [
	[Vector2i(390, 844), MainMenu.Layout.PHONE],
	[Vector2i(844, 390), MainMenu.Layout.LANDSCAPE],
	[Vector2i(1024, 768), MainMenu.Layout.TABLET],
	[Vector2i(1600, 1000), MainMenu.Layout.WIDE],
]


func _main_menu(web: bool) -> MainMenu:
	var menu := autofree(MainMenu.new()) as MainMenu
	menu._is_web = web
	add_child(menu)
	return menu


func _pause_menu(web: bool) -> PauseMenu:
	var menu := autofree(PauseMenu.new()) as PauseMenu
	menu._is_web = web
	add_child(menu)
	return menu


func _button_labels(root: Node) -> Array:
	var labels: Array = []
	for button in find_buttons(root):
		labels.append(button.text)
	return labels


func test_web_main_menu_omits_quit_in_every_layout() -> void:
	var menu := _main_menu(true)
	for entry in LAYOUT_SIZES:
		var size: Vector2i = entry[0]
		await resize_window(size)
		assert_eq(menu._layout_mode, entry[1], "%s uses its expected layout" % size)
		var labels := _button_labels(menu)
		assert_false(labels.has("Quit"), "%s has no application Quit action on web" % size)
		assert_eq(labels.size(), WEB_MAIN_ACTIONS.size(), "%s only loses Quit" % size)
		for expected in WEB_MAIN_ACTIONS:
			assert_has(labels, expected, "%s keeps %s" % [size, expected])


func test_web_pause_menu_omits_only_quit_to_desktop() -> void:
	var menu := _pause_menu(true)
	var labels := _button_labels(menu)
	assert_false(labels.has("Quit to Desktop"), "web has no application Quit action")
	assert_has(labels, "Quit to Menu", "returning to the title screen remains available")
	for expected in ["Resume", "Save Game", "Load Game", "Settings"]:
		assert_has(labels, expected, "the web pause menu keeps %s" % expected)


func test_native_menus_keep_their_application_quit_actions() -> void:
	var main_menu := _main_menu(false)
	assert_has(_button_labels(main_menu), "Quit", "the native title screen keeps Quit")
	var pause_menu := _pause_menu(false)
	var labels := _button_labels(pause_menu)
	assert_has(labels, "Quit to Menu", "the native pause menu keeps Quit to Menu")
	assert_has(labels, "Quit to Desktop", "the native pause menu keeps Quit to Desktop")
