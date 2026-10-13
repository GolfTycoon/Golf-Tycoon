extends GameTest
## The title screen's type: every word on it is set in Pixelify Sans
## (assets/fonts/, SIL Open Font License 1.1) so the type matches the
## pixel-art cards, sprites and logo - the hero and Continue card titles in
## the bold weight, the compact utility tiles in the semibold one, and the
## captions, the rail kicker and the version line in the regular one. The
## heading itself is the logo image and carries no type (see
## tests/unit/ui_and_controls/test_main_menu_layout.gd).
##
## The screen is built from code, so a new builder could quietly leave a label
## on the engine's default font; these walk the built tree and resolve each
## text control's font the way the engine does when it draws it.

const TITLE_PATH := "res://assets/fonts/PixelifySans-Bold.ttf"
const SUBTITLE_PATH := "res://assets/fonts/PixelifySans-SemiBold.ttf"
const BODY_PATH := "res://assets/fonts/PixelifySans-Regular.ttf"
## The big cards, which carry the boldest weight; the compact utility tiles
## take the semibold one.
const HERO_CARDS := ["StartNewGameButton", "QuickStartButton", "ContinueButton"]


func _menu() -> MainMenu:
	var menu := autofree(MainMenu.new()) as MainMenu
	add_child(menu)
	return menu


## Every node of the engine class `type_name` under `root`, `root` included.
static func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found


## The font the engine would draw `control`'s text with: its own override,
## else the theme it inherits.
static func _drawn_font(control: Control) -> Font:
	return control.get_theme_font("font")


func test_the_action_titles_are_set_in_pixelify_sans_bold() -> void:
	var menu := _menu()
	var buttons := _nodes_of_class(menu, "Button")
	assert_eq(buttons.size(), 7, "the seven actions")
	for button in buttons:
		var expected := TITLE_PATH if button.name in HERO_CARDS else SUBTITLE_PATH
		assert_eq(_drawn_font(button).resource_path, expected,
			"the %s title carries its Pixelify Sans weight" % button.name)


func test_the_captions_and_quiet_lines_are_set_in_pixelify_sans_regular() -> void:
	var menu := _menu()
	var labels := _nodes_of_class(menu, "Label")
	assert_gte(labels.size(), 3, "captions, the kicker and the version line exist")
	for label in labels:
		assert_eq(_drawn_font(label).resource_path, BODY_PATH,
			"the %s line is Pixelify Sans regular" % (label as Label).name)


## Nothing on the screen keeps the engine's default face: a builder that
## forgets the override would show up here as an empty resource path.
func test_no_text_on_the_screen_keeps_the_default_font() -> void:
	var menu := _menu()
	var defaulting: Array = []
	for control in _nodes_of_class(menu, "Button") + _nodes_of_class(menu, "Label"):
		var path := _drawn_font(control).resource_path
		if not path.begins_with("res://assets/fonts/PixelifySans"):
			defaulting.append("%s -> %s" % [control.name, path])
	assert_eq(defaulting, [], "every text control draws a Pixelify Sans weight")
