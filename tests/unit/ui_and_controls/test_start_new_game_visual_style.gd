extends GameTest
## Start New Game carries the same pixel-art visual language as the title
## screen: Pixelify Sans, the shared nine-patch frames, nearest-filtered flag
## sprite, and the new character-grid setup glyphs.

const ScreenScene := preload("res://scripts/ui/start_new_game_screen.gd")
const TITLE_FONT_PATH := "res://assets/fonts/PixelifySans-Bold.ttf"
const SUBTITLE_FONT_PATH := "res://assets/fonts/PixelifySans-SemiBold.ttf"
const BODY_FONT_PATH := "res://assets/fonts/PixelifySans-Regular.ttf"


func _screen() -> StartNewGameScreen:
	var screen := autofree(StartNewGameScreen.new()) as StartNewGameScreen
	add_child(screen)
	return screen


func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

func _setup_glyphs(root: Node) -> Array[SetupGlyph]:
	var found: Array[SetupGlyph] = []
	if root is SetupGlyph:
		found.append(root)
	for child in root.get_children():
		found.append_array(_setup_glyphs(child))
	return found


func test_every_visible_word_uses_the_title_screens_pixelify_faces() -> void:
	var screen := _screen()
	var allowed := [TITLE_FONT_PATH, SUBTITLE_FONT_PATH, BODY_FONT_PATH]
	var unstyled: Array[String] = []
	for label in _nodes_of_class(screen, "Label"):
		var path := (label as Label).get_theme_font("font").resource_path
		if not path in allowed:
			unstyled.append("%s -> %s" % [label.name, path])
	for input in _nodes_of_class(screen, "LineEdit"):
		var path := (input as LineEdit).get_theme_font("font").resource_path
		if not path in allowed:
			unstyled.append("%s -> %s" % [input.name, path])
	for button in _nodes_of_class(screen, "Button"):
		var control := button as Button
		if control.text.is_empty():
			continue
		var path := control.get_theme_font("font").resource_path
		if not path in allowed:
			unstyled.append("%s -> %s" % [control.name, path])
	assert_eq(unstyled, [], "every setup label, button and company field uses Pixelify Sans")
	var title := screen.find_child("Title", true, false) as Label
	assert_not_null(title, "the screen keeps its Start New Game title")
	if title:
		assert_eq(title.get_theme_font("font").resource_path, TITLE_FONT_PATH, "the heading is bold")


func test_setup_buttons_and_panels_use_shared_pixel_frames() -> void:
	var screen := _screen()
	var buttons := _nodes_of_class(screen, "Button")
	assert_gte(buttons.size(), 19, "the full setup menu is built")
	for node in buttons:
		var button := node as Button
		var normal := button.get_theme_stylebox("normal") as StyleBoxTexture
		assert_not_null(normal, "%s has the same pixel frame as the title menu" % button.name)
		if normal:
			assert_eq(normal.texture_margin_left, float(PixelButtonStyle.MARGIN),
				"%s keeps its frame pixels 1:1" % button.name)
	var panels := _nodes_of_class(screen, "PanelContainer")
	assert_gte(panels.size(), 3, "the sheet, plan and company rail are framed panels")
	for node in panels:
		var panel := node as PanelContainer
		var style := panel.get_theme_stylebox("panel") as StyleBoxTexture
		assert_not_null(style, "%s uses a pixel panel frame" % panel.name)
		if style:
			var edge_margin := style.texture_margin_top if panel.name == "Footer" else style.texture_margin_left
			assert_eq(edge_margin, float(PixelButtonStyle.MARGIN),
				"%s keeps its pixel border crisp" % panel.name)


func test_screen_ornaments_are_pixel_sprites_not_smooth_vector_marks() -> void:
	var screen := _screen()
	var mark := screen.find_child("FlagMark", true, false)
	assert_true(mark is MenuFlagMark, "the title lockup has its pixel-grid golf flag")
	var glyphs := _setup_glyphs(screen)
	assert_gt(glyphs.size(), 0, "choice cards carry their own icons")
	for glyph in glyphs:
		assert_true(glyph.pixel_art, "%s is drawn from its pixel grid" % glyph.name)
	assert_eq(CoursePlanPreview.PLAN_FONT.resource_path, BODY_FONT_PATH,
		"hole numbers in the live plan use the same pixel type")
