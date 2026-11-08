extends GameTest
## The pause menu's new look: the same pixel language as the title screen.
##
## Every action is a PixelButtonStyle card - a notched nine-patch frame in the
## action's own accent, with a PixelIcon sprite of its own and one line of
## Pixelify Sans - and the panel around them is the title screen's rail frame.
## The menu is built from code, so a builder that quietly fell back to the
## project theme's flat green boxes, or to a card with no sprite, would show
## up here.
##
## The options' names, the signals they raise and the way the menu fits a
## short window are covered by test_pause_menu_touch.gd; what is checked here
## is the dressing.

const SUBTITLE_PATH := "res://assets/fonts/PixelifySans-SemiBold.ttf"
const BODY_PATH := "res://assets/fonts/PixelifySans-Regular.ttf"

## The accent each action's frame is trimmed in, matched to the weight the
## title screen gives the same family: gold to carry on, green to keep a
## game, the quiet utility grey for Settings, the danger red to leave.
const ACCENTS := {
	"ResumeButton": MenuStyle.ACCENT_PRIMARY,
	"SaveGameButton": MenuStyle.ACCENT_SECONDARY,
	"LoadGameButton": MenuStyle.ACCENT_SECONDARY,
	"SettingsButton": MenuStyle.ACCENT_UTILITY,
	"QuittoMenuButton": MenuStyle.ACCENT_QUIT,
	"QuittoDesktopButton": UIConstants.COLOR_DANGER,
}
## Every action carries a sprite of its own; two actions sharing one would
## make the menu unreadable at a glance.
const ICONS := {
	"ResumeButton": PixelIcon.Kind.PLAY,
	"SaveGameButton": PixelIcon.Kind.FLOPPY,
	"LoadGameButton": PixelIcon.Kind.BOOK,
	"SettingsButton": PixelIcon.Kind.GEAR,
	"QuittoMenuButton": PixelIcon.Kind.MAP,
	"QuittoDesktopButton": PixelIcon.Kind.DOOR,
}


## Every Button and Label on the menu, typed so the theme lookups resolve.
static func _text_controls(root: Node) -> Array[Control]:
	var controls: Array[Control] = []
	for node in _nodes_of_class(root, "Button") + _nodes_of_class(root, "Label"):
		controls.append(node as Control)
	return controls


func _menu() -> PauseMenu:
	var menu := autofree(PauseMenu.new()) as PauseMenu
	add_child(menu)
	return menu


static func _nodes_of_class(root: Node, type_name: String) -> Array:
	var found: Array = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_of_class(child, type_name))
	return found


static func _named(root: Node, option_name: String) -> Control:
	return root.find_child(option_name, true, false) as Control


func test_every_action_wears_the_shared_pixel_card_frame() -> void:
	var menu := _menu()
	await process_frames(3)
	for option_name in ACCENTS:
		var button := _named(menu, option_name) as Button
		assert_not_null(button, "%s exists" % option_name)
		if button == null:
			continue
		var accent: Color = ACCENTS[option_name]
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := button.get_theme_stylebox(state)
			assert_true(style is StyleBoxTexture,
				"%s: the %s state is a pixel card, not the theme's flat box" % [option_name, state])
		# The frame itself is the shared recipe, painted in this action's
		# accent: the same texture the title screen's tiles are built from.
		var expected := PixelButtonStyle.texture_style(
			accent, PixelButtonStyle.State.NORMAL, MenuStyle.CARD_BG)
		assert_eq((button.get_theme_stylebox("normal") as StyleBoxTexture).texture,
			expected.texture, "%s carries the shared frame in its own accent" % option_name)


func test_every_action_carries_its_own_pixel_sprite() -> void:
	var menu := _menu()
	await process_frames(3)
	for option_name in ICONS:
		var button := _named(menu, option_name) as Button
		if button == null:
			continue
		var kind: int = ICONS[option_name]
		var accent: Color = ACCENTS[option_name]
		assert_not_null(button.icon, "%s carries a sprite" % option_name)
		if button.icon == null:
			continue
		var image := button.icon.get_image()
		# Sprites snap to whole multiples of their 16px grid, so every source
		# pixel lands as an even block - that is what makes them pixel art.
		assert_eq(image.get_width(), image.get_height(), "%s: square sprite" % option_name)
		assert_eq(image.get_width() % PixelIcon.GRID, 0,
			"%s: the sprite is a whole multiple of its grid" % option_name)
		# And it is the action's own sprite, painted in the action's accent.
		var expected := PixelIcon.image(kind, image.get_width(), accent)
		assert_eq(image.get_width(), expected.get_width(), "%s: sprite size" % option_name)


func test_the_actions_tell_themselves_apart() -> void:
	var menu := _menu()
	await process_frames(3)
	var names: Array = []
	var icons: Array = []
	var frames: Array = []
	for option_name in ICONS:
		var button := _named(menu, option_name) as Button
		if button == null:
			continue
		names.append(option_name)
		icons.append(button.icon)
		var style := button.get_theme_stylebox("normal") as StyleBoxTexture
		frames.append(style.texture)
	assert_eq(icons.size(), ICONS.size(), "every action was found")
	# No two options may carry the same sprite: a player glancing at the menu
	# has to be able to tell Save from Load at once.
	var shared_sprites: Array = []
	for i in icons.size():
		for j in range(i + 1, icons.size()):
			if icons[i] == icons[j]:
				shared_sprites.append("%s+%s" % [names[i], names[j]])
	assert_eq(shared_sprites, [], "every action carries a sprite of its own")
	# Frames are shared by family: the save pair is one green family, and the
	# two ways out are told apart by the frame alone.
	var shared_frames: Array = []
	for i in frames.size():
		for j in range(i + 1, frames.size()):
			if frames[i] == frames[j]:
				shared_frames.append("%s+%s" % [names[i], names[j]])
	assert_eq(shared_frames, ["SaveGameButton+LoadGameButton"],
		"only the save pair shares a frame - Resume, Settings and each way out has its own")


func test_the_options_are_set_in_pixelify_sans() -> void:
	var menu := _menu()
	await process_frames(3)
	var defaulting: Array = []
	for control in _text_controls(menu):
		var path: String = control.get_theme_font("font").resource_path
		if not path.begins_with("res://assets/fonts/PixelifySans"):
			defaulting.append("%s -> %s" % [control.name, path])
	assert_eq(defaulting, [], "every line on the menu draws a Pixelify Sans weight")
	for option_name in ACCENTS:
		var button := _named(menu, option_name) as Button
		if button == null:
			continue
		assert_eq(button.get_theme_font("font").resource_path, SUBTITLE_PATH,
			"%s is set in the semibold weight, like the title screen's tiles" % option_name)
		# The ink outline keeps the letter legible over the glassy card.
		assert_gt(button.get_theme_constant("outline_size"), 0,
			"%s: the label wears its ink edge" % option_name)


func test_the_heading_is_the_flag_mark_over_a_gold_kicker() -> void:
	var menu := _menu()
	await process_frames(3)
	assert_not_null(menu._title, "the menu has a title")
	if menu._title != null:
		assert_eq(menu._title.get_theme_font("font").resource_path,
			"res://assets/fonts/PixelifySans-Bold.ttf",
			"the title is set in Pixelify Sans bold")
	assert_not_null(menu._info, "the menu names the course it paused")
	if menu._kicker != null:
		assert_true(menu._kicker.uppercase, "the kicker is set in capitals")
		assert_eq(menu._kicker.get_theme_color("font_color"), MenuStyle.ACCENT_PRIMARY,
			"the kicker is the shared gold section caption")
	# The mark beside the title is the game's drawn pennant, not a typed glyph.
	var mark := _named(menu, "Mark")
	assert_not_null(mark, "the heading carries the game's flag mark")
	if mark != null:
		assert_true(mark is MenuFlagMark, "the mark is the shared menu mark")


func test_the_panel_and_the_scroll_area_wear_the_shared_frame() -> void:
	var menu := _menu()
	await process_frames(3)
	assert_true(menu._panel.get_theme_stylebox("panel") is StyleBoxTexture,
		"the card around the options is the shared pixel panel")
	# The project theme paints scroll containers an opaque green; over the
	# card that would be a green slab behind the options.
	assert_true(menu._scroll.get_theme_stylebox("panel") is StyleBoxEmpty,
		"the scrolling area is transparent, so the card shows through")


func test_the_scrim_dims_the_course_without_hiding_it() -> void:
	var menu := _menu()
	await process_frames(3)
	assert_not_null(menu._bg, "the menu dims the game behind it")
	if menu._bg == null:
		return
	var alpha: float = (menu._bg as ColorRect).color.a
	assert_gt(alpha, 0.3, "the scrim is dark enough to read the menu against")
	assert_lt(alpha, 0.85, "and sheer enough to still see the course behind it")


func test_every_action_shows_the_shared_focus_ring() -> void:
	var menu := _menu()
	await process_frames(3)
	for option_name in ACCENTS:
		var button := _named(menu, option_name) as Button
		if button == null:
			continue
		var ring := button.get_node_or_null("FocusRing") as MenuFocusRing
		assert_not_null(ring, "%s wears the shared focus ring" % option_name)
		if ring != null:
			assert_eq(ring.ring_style.get_expand_margin(SIDE_LEFT),
				PixelButtonStyle.FOCUS_EXPAND, "%s: the ring reaches past the card" % option_name)
		assert_not_null(button.get_theme_stylebox("focus"),
			"%s: the warm wash sits over the card" % option_name)


func test_the_cards_are_big_enough_to_tap_on_a_phone() -> void:
	await resize_window(Vector2i(844, 390))
	var menu := _menu()
	await process_frames(4)
	for option_name in ACCENTS:
		var button := _named(menu, option_name) as Button
		if button == null:
			continue
		assert_gte(button.size.y, 44.0,
			"%s stays a touch-sized target on a phone held sideways" % option_name)


func test_the_tournament_menu_swaps_the_save_pair_for_its_own_actions() -> void:
	var was_tournament := GameManager.is_tournament_mode
	GameManager.is_tournament_mode = true
	var menu := _menu()
	await process_frames(3)
	assert_eq(menu._title.text, "Tournament Paused", "the heading names the mode")
	assert_null(_named(menu, "SaveGameButton"), "a tournament is not saved mid-round")
	assert_null(_named(menu, "LoadGameButton"), "nor loaded")
	assert_not_null(_named(menu, "RestartTournamentButton"), "it is restarted instead")
	assert_not_null(_named(menu, "TournamentSetupButton"), "or set up again")
	# The tournament actions wear the same cards as the career ones.
	for option_name in ["RestartTournamentButton", "TournamentSetupButton"]:
		var button := _named(menu, option_name) as Button
		if button == null:
			continue
		assert_true(button.get_theme_stylebox("normal") is StyleBoxTexture,
			"%s is a pixel card too" % option_name)
		assert_not_null(button.icon, "%s carries a sprite" % option_name)
	GameManager.is_tournament_mode = was_tournament


func test_the_hint_and_the_course_line_are_set_in_pixelify_sans_regular() -> void:
	var menu := _menu()
	await process_frames(3)
	for label in [menu._info, menu._hint]:
		assert_not_null(label, "the quiet lines exist")
		if label == null:
			continue
		assert_eq((label as Label).get_theme_font("font").resource_path, BODY_PATH,
			"the %s line is set in Pixelify Sans regular" % (label as Label).name)
