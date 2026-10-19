extends GameTest
## The World Map atlas carries the same pixel-art visual language as the
## title screen and Start New Game: Pixelify Sans for every word, the shared
## notched nine-patch frames on every card, button and field, PixelIcon
## sprites for the treasury coin, the location pennants and the legend pins,
## and a globe drawn in the chunky LandStyle.PIXEL mode.
##
## The screen is built from code, so a new builder could quietly leave a label
## on the engine's default font or wrap a card in a plain StyleBoxFlat; these
## walk the built tree and check what it actually draws.

const TITLE_FONT_PATH := "res://assets/fonts/PixelifySans-Bold.ttf"
const SUBTITLE_FONT_PATH := "res://assets/fonts/PixelifySans-SemiBold.ttf"
const BODY_FONT_PATH := "res://assets/fonts/PixelifySans-Regular.ttf"

func _screen() -> WorldMapScreen:
	var screen := autofree(WorldMapScreen.new()) as WorldMapScreen
	add_child(screen)
	return screen

func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found

func _texture_rects(root: Node) -> Array:
	var found: Array = []
	if root is TextureRect:
		found.append(root)
	for child in root.get_children():
		found.append_array(_texture_rects(child))
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
	assert_eq(unstyled, [], "every atlas label, button and search field uses Pixelify Sans")
	var title := screen.find_child("Title", true, false) as Label
	assert_not_null(title, "the screen keeps its World Map title")
	if title:
		assert_eq(title.get_theme_font("font").resource_path, TITLE_FONT_PATH, "the heading is bold")

func test_world_map_title_contains_only_the_icon_and_text() -> void:
	var screen := _screen()
	await process_frames(2)
	var title_block := screen.find_child("TitleBlock", true, false) as VBoxContainer
	assert_not_null(title_block, "the title block is built")
	if title_block == null:
		return

	var flag := screen.find_child("FlagMark", true, false)
	assert_true(flag is MenuFlagMark, "the golf icon sits beside the title block in the shared header")
	var title := screen.find_child("Title", true, false) as Label
	assert_not_null(title, "the title block holds the title text")
	if title:
		assert_eq(title.name, "Title", "the text item is the title")
		assert_eq(title.text, "World Map", "the title reads World Map")
		assert_eq(title_block.size_flags_horizontal, Control.SIZE_EXPAND_FILL,
			"the title block can use the space beside the icon")
		assert_gt(title.size.x, 0.0, "the title receives visible width")

func test_atlas_buttons_and_panels_use_shared_pixel_frames() -> void:
	var screen := _screen()
	var buttons := _nodes_of_class(screen, "Button")
	assert_gte(buttons.size(), 8, "back, the globe tools, filters and actions are built")
	for node in buttons:
		var button := node as Button
		var normal := button.get_theme_stylebox("normal") as StyleBoxTexture
		assert_not_null(normal, "%s has the same pixel frame as the title menu" % button.name)
		if normal:
			assert_eq(normal.texture_margin_left, float(PixelButtonStyle.MARGIN),
				"%s keeps its frame pixels 1:1" % button.name)
	var panels := _nodes_of_class(screen, "PanelContainer")
	assert_gte(panels.size(), 4, "globe, dossier, directory and treasury are framed panels")
	for node in panels:
		var panel := node as PanelContainer
		var style := panel.get_theme_stylebox("panel") as StyleBoxTexture
		assert_not_null(style, "%s uses a pixel panel frame" % panel.name)
		if style:
			assert_eq(style.texture_margin_left, float(PixelButtonStyle.MARGIN),
				"%s keeps its pixel border crisp" % panel.name)

func test_the_globe_is_the_pixel_art_planet() -> void:
	var screen := _screen()
	assert_eq(screen.globe.get_land_style(), GlobeMap.LandStyle.PIXEL,
		"the world map globe is the chunky pixel planet")
	assert_not_null(screen.find_child("LocationSearch", true, false), "the search field is built")

func test_screen_ornaments_are_pixel_sprites() -> void:
	var screen := _screen()
	var coin := screen.find_child("Coin", true, false) as TextureRect
	assert_not_null(coin, "the treasury card carries its coin sprite")
	if coin:
		assert_eq(coin.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "the coin stays pixel sharp")
		assert_eq(coin.texture.get_width() % PixelIcon.GRID, 0, "the coin stays on the sprite grid")
	var flags: Array = []
	for node in _texture_rects(screen):
		if (node as TextureRect).name == "StateFlag":
			flags.append(node)
	assert_gte(flags.size(), 20, "each location row carries a state pennant")
	for flag in flags:
		assert_eq((flag as TextureRect).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"the pennants stay pixel sharp")
	var legend := screen.find_child("MarkerLegend", true, false)
	var compact_layout := screen._layout_mode == MenuScreenKit.LayoutMode.PHONE_LANDSCAPE \
		or screen._layout_mode == MenuScreenKit.LayoutMode.PHONE_PORTRAIT
	if compact_layout:
		assert_null(legend, "compact layouts leave out the legend to preserve room")
	else:
		assert_not_null(legend, "the map footer keeps its pin legend")
		if legend:
			assert_gte(_texture_rects(legend).size(), 3, "the legend explains the pin colours")
	var mark := screen.find_child("FlagMark", true, false)
	assert_true(mark is MenuFlagMark, "the title lockup keeps its golf-flag mark")

func test_the_flag_mark_is_drawn_from_a_pixel_grid() -> void:
	assert_eq(MenuFlagMark.ART.size(), MenuFlagMark.GRID, "the mark has a full grid of rows")
	var joined := ""
	for row in MenuFlagMark.ART:
		assert_eq(str(row).length(), MenuFlagMark.GRID, "every mark row is the grid wide")
		joined += str(row)
	assert_true(joined.contains("X"), "the mark carries its ink and cup")
	assert_true(joined.contains("A"), "the mark's flag is gold")
	assert_true(joined.contains("G"), "the mark stands on its green")
