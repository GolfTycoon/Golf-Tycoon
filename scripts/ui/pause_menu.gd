extends Control
class_name PauseMenu
## PauseMenu - Full-screen pause overlay with game options
##
## Triggered by Escape key. Career games provide Resume, Save Game, Load Game,
## Save Course and Save Golfer (the Tournament Mode exports), Settings and Quit
## to Menu, plus Quit to Desktop on native builds. Dims the game behind it.
##
## The World Map is not here: it lives on the Club tab, where the company's
## sites are managed.
##
## The menu is drawn in the title screen's own language, so pausing looks like
## the screen the game was opened from instead of a system dialogue: a pixel
## card (PixelButtonStyle's nine-patch frame) holding one column of action
## cards, each with its own accent trim and a PixelIcon sprite - a play
## triangle for Resume, a floppy and an archive for the save pair, a flag and a
## golfer shirt for the Tournament Mode exports, a cog for Settings, a map and
## a doorway for the two ways out. Resume is the gold call to action, the
## save/load pair is green, the export pair is blue, Settings is the quiet
## utility and the exits are the danger red, the same weighting the Main Menu
## gives them. The heading is the game's flag mark beside the title, over a
## gold rule. The two export cards open the Save Course and Save Golfer
## screens, where the keepsake is named, kept or replaced; the exports step
## aside in standalone Tournament Mode.
##
## The simulation is frozen while this menu is open, but the player can still
## look around the course: pointer events that land on the dimmed backdrop
## (not on the menu panel) are forwarded to the isometric camera, which runs
## on wall-clock time.
##
## The menu fits the window it opens in: on a short window (a phone held
## sideways, a small browser frame) the buttons scroll inside the panel instead
## of running off the bottom of the screen, where they could not be tapped.

signal resume_requested
signal save_requested
signal load_requested
signal save_course_requested
signal save_golfer_requested
signal restart_tournament_requested
signal tournament_setup_requested
signal settings_requested
signal quit_to_menu_requested
signal quit_to_desktop_requested

## Set by Main so camera controls work while the game is paused behind the
## menu. Null when the camera is unavailable (forwarding is then skipped).
var camera: IsometricCamera = null

var _bg: ColorRect = null
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null
var _info: Label = null
var _title: Label = null
var _spacer: Control = null
var _buttons: Array[Button] = []
var _compact := false
## Quit to Desktop is native-only: closing the browser tab is the equivalent
## action on web. Kept as a value so the web menu can be tested natively.
var _is_web := OS.has_feature("web")

## The heading: the small gold line above the title, the flag mark beside it,
## and the gold rule under it.
var _kicker: Label = null
var _mark: MenuFlagMark = null
## Each action's recipe (accent, sprite, label colour, and whether it is the
## one that takes focus), collected before the cards are painted because the
## frame, the sprite and the label are all drawn from the same values.
var _recipes: Array[Dictionary] = []

# =============================================================================
# PIXEL FURNITURE
# =============================================================================

## The scrim over the course: the frame's own ink rather than a flat black, so
## the game behind dims into the palette instead of into grey.
const SCRIM_COLOR := Color(0.016, 0.043, 0.035, 0.66)
## The card the menu sits in: the title screen's rail recipe - a notched
## nine-patch frame over the sheet colour, nearly opaque so the course behind
## it cannot run through the type.
const CARD_FILL := Color(0.031, 0.071, 0.059, 0.94)
const CARD_BORDER := Color(0.388, 0.435, 0.353, 0.60)

## Action cards: the title screen's tiles. One line of semibold Pixelify Sans,
## a sprite scaled from the label size (the sprites snap to whole multiples of
## their 16px grid, so 1.9x is a 32px sprite and 1.4x a 16px one), and the
## ink outline that keeps the letter legible over the glass.
const CARD_FONT := 16
const CARD_HEIGHT := 52.0
const CARD_HEIGHT_TOUCH := 44.0
const CARD_PAD := 10
const CARD_PAD_TOUCH := 8
const CARD_ICON_SCALE := 1.9
const CARD_ICON_SCALE_TOUCH := 1.4
## Between the cards: the desktop gap, and the tighter one a short window
## needs to keep the options as close to fitting as it can.
const CARD_GAP := 8
const CARD_GAP_SHORT := 5
## The Tournament Mode exports are a third family: blue cards with a flag and a
## golfer shirt, so they never read as another way to write a Career save slot.
const EXPORT_ACCENT := UIConstants.COLOR_INFO

## Heading type. The short-window title drops a step so the options still fit
## as closely as they can before the scroll area takes over.
const KICKER_FONT := 11
const TITLE_FONT_SIZE := 24
const TITLE_FONT_SIZE_SHORT := 18
const INFO_FONT := 12
## Side of the flag mark beside the title, and its size on a short window.
const MARK_SIZE := 34.0
const MARK_SIZE_SHORT := 22.0

## The label's ink edge and drop shadow, as on the title screen's cards.
const LABEL_OUTLINE_SIZE := 4
const LABEL_SHADOW_OFFSET := Vector2(0.0, 2.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("touch_camera_backdrop")
	_build_ui()
	_fit_to_view.call_deferred()
	# Re-fit when the window changes shape (rotation, a browser resize).
	resized.connect(_fit_to_view)
	if has_node("/root/Screen"):
		Screen.changed.connect(func(_size: Vector2, _scale: float) -> void: _fit_to_view())

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)


func _build_ui() -> void:
	# Semi-transparent dark overlay
	var bg = ColorRect.new()
	bg.name = "Scrim"
	bg.color = SCRIM_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = bg
	add_child(bg)

	# Center container for the menu panel
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Menu panel: the same notched pixel frame the title screen builds its
	# cards and rails from, so the pause overlay belongs to the same game.
	var panel = PanelContainer.new()
	panel.name = "PausePanel"
	var compact := has_node("/root/Screen") and Screen.uses_touch_layout()
	_compact = compact
	panel.add_theme_stylebox_override("panel",
		PixelButtonStyle.panel_style(CARD_BORDER, CARD_FILL, 16, 14))
	panel.custom_minimum_size = Vector2(_menu_width(), 0)
	_panel = panel
	center.add_child(panel)

	# The buttons live in a ScrollContainer: on a screen too short for the
	# whole menu it scrolls (touch drags scroll it, see TouchInput), so Quit to
	# Menu and Quit to Desktop never sit off the bottom where nothing can reach
	# them.
	var scroll = ScrollContainer.new()
	scroll.name = "PauseScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The project theme paints scroll containers an opaque green; the card
	# underneath is the surface here.
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_scroll = scroll
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", CARD_GAP)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox = vbox
	scroll.add_child(vbox)

	var in_tourney := GameManager.is_tournament_mode

	# ── Heading: the state, the title beside the game's mark, the course.
	vbox.add_child(_make_header(in_tourney))

	# Course info
	var info_label = MenuScreenKit.make_label(_info_text(in_tourney), INFO_FONT,
		UIConstants.COLOR_TEXT_DIM)
	info_label.name = "Info"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrapped, so a long course name never forces the panel wider than a phone.
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info = info_label
	vbox.add_child(info_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_spacer = spacer
	vbox.add_child(spacer)

	# ── Options. Each one is a card with the accent and the sprite of its
	# family, so the menu reads at a glance: gold to carry on, green to keep
	# a game, red to leave it.
	if in_tourney:
		_add_menu_button(vbox, "Resume", "Back to the round", _on_resume_pressed,
			MenuStyle.ACCENT_PRIMARY, PixelIcon.Kind.PLAY, UIConstants.COLOR_TEXT, true)
		_add_menu_button(vbox, "Restart Tournament", "Tee off in this tournament again",
			func() -> void: restart_tournament_requested.emit(),
			MenuStyle.ACCENT_SECONDARY, PixelIcon.Kind.FLAG)
		_add_menu_button(vbox, "Tournament Setup", "Choose a different difficulty, course or golfer",
			func() -> void: tournament_setup_requested.emit(),
			MenuStyle.ACCENT_SECONDARY, PixelIcon.Kind.TROPHY)
		_add_menu_button(vbox, "Settings", "Audio, display and gameplay options",
			_on_settings_pressed, MenuStyle.ACCENT_UTILITY, PixelIcon.Kind.GEAR)
		_add_menu_button(vbox, "Quit to Menu", "Leave the tournament for the title screen",
			_on_quit_to_menu_pressed, MenuStyle.ACCENT_QUIT, PixelIcon.Kind.MAP,
			UIConstants.COLOR_DANGER_MUTED)
		if not _is_web:
			_add_menu_button(vbox, "Quit to Desktop", "Close the game",
				_on_quit_to_desktop_pressed, UIConstants.COLOR_DANGER,
				PixelIcon.Kind.DOOR, UIConstants.COLOR_DANGER_MUTED)
	else:
		_add_menu_button(vbox, "Resume", "Back to the course", _on_resume_pressed,
			MenuStyle.ACCENT_PRIMARY, PixelIcon.Kind.PLAY, UIConstants.COLOR_TEXT, true)
		_add_menu_button(vbox, "Save Game", "Write your course to a save slot",
			_on_save_pressed, MenuStyle.ACCENT_SECONDARY, PixelIcon.Kind.FLOPPY)
		_add_menu_button(vbox, "Load Game", "Return to a saved course",
			_on_load_pressed, MenuStyle.ACCENT_SECONDARY, PixelIcon.Kind.BOOK)
		# Career -> Tournament Mode exports. Their short captions sit beside the
		# save pair; the tooltips spell out what is exported and where it can be
		# played, so the menu needs no extra heading for them.
		_add_menu_button(vbox, "Save Course",
			"Keep this course so you can pick it on the Start Tournament screen from the Main Menu.",
			_on_save_course_pressed, EXPORT_ACCENT, PixelIcon.Kind.FLAG)
		_add_menu_button(vbox, "Save Golfer",
			"Keep your golfer's skills, traits and appearance so you can play as them in Tournament Mode.",
			_on_save_golfer_pressed, EXPORT_ACCENT, PixelIcon.Kind.SHIRT)
		_add_menu_button(vbox, "Settings", "Audio, display and gameplay options",
			_on_settings_pressed, MenuStyle.ACCENT_UTILITY, PixelIcon.Kind.GEAR)
		_add_menu_button(vbox, "Quit to Menu", "Leave the course for the title screen",
			_on_quit_to_menu_pressed, MenuStyle.ACCENT_QUIT, PixelIcon.Kind.MAP,
			UIConstants.COLOR_DANGER_MUTED)
		if not _is_web:
			_add_menu_button(vbox, "Quit to Desktop", "Close the game",
				_on_quit_to_desktop_pressed, UIConstants.COLOR_DANGER,
				PixelIcon.Kind.DOOR, UIConstants.COLOR_DANGER_MUTED)

	_paint_buttons()


## The heading: a small gold line naming the mode, the title beside the game's
## flag mark, and a gold rule closing it off. The mark is drawn, not typed,
## like the title screen's sprites - the font carries no golf glyph.
func _make_header(in_tourney: bool) -> Control:
	var header := VBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 2)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_kicker = MenuScreenKit.make_kicker(
		"Tournament" if in_tourney else "Career", KICKER_FONT)
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_kicker)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_row.add_theme_constant_override("separation", 8)
	header.add_child(title_row)

	var mark := MenuFlagMark.new()
	mark.name = "Mark"
	mark.mark_size = MARK_SIZE
	_mark = mark
	title_row.add_child(mark)

	_title = MenuScreenKit.make_title_label(
		"Tournament Paused" if in_tourney else "Game Paused", TITLE_FONT_SIZE)
	_title.name = "PauseTitle"
	title_row.add_child(_title)

	# The gold rule that closes the heading off, as on the title screen.
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.55)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(rule)

	return header


func _info_text(in_tourney: bool) -> String:
	if in_tourney:
		var diff_str := GameManager.tournament_difficulty_label if not GameManager.tournament_difficulty_label.is_empty() else "Tournament Mode"
		return "%s — %s" % [GameManager.course_name, diff_str]
	return "%s - Day %d" % [GameManager.course_name, GameManager.current_day]


## Keep the whole menu on screen: the panel is clamped to the space a modal may
## use and its content scrolls when it does not fit. Called after the first
## layout pass, and again whenever the window or the screen metrics change, so
## the menu is right in every window it can open in.
func _fit_to_view() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_vbox) or not is_instance_valid(_scroll):
		return
	var view := get_viewport().get_visible_rect().size
	var available := view - Vector2(24.0, 24.0)
	if has_node("/root/Screen"):
		available = Screen.modal_panel_rect().size
	available = available.max(Vector2(160.0, 120.0))

	var style := _panel.get_theme_stylebox("panel") as StyleBox
	var vertical_padding := 0.0
	var horizontal_padding := 0.0
	if style != null:
		vertical_padding = style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
		horizontal_padding = style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)

	# A short window (a phone held sideways) gets tighter spacing and drops the
	# heading's extras first: the options are what the player opened the menu
	# for. Eight career cards may still be taller than the window, in which case
	# the scroll area takes over and keeps every one of them reachable.
	var short_window := available.y < 420.0
	_vbox.add_theme_constant_override("separation",
		CARD_GAP_SHORT if short_window else CARD_GAP)
	# On a short window the course line and its spacer give way first: the
	# options themselves are what the player opened the menu for.
	if is_instance_valid(_info):
		_info.visible = not short_window
	if is_instance_valid(_spacer):
		_spacer.visible = not short_window
	if is_instance_valid(_kicker):
		_kicker.visible = not short_window
	if is_instance_valid(_title):
		_title.add_theme_font_size_override("font_size",
			TITLE_FONT_SIZE_SHORT if short_window else TITLE_FONT_SIZE)
	if is_instance_valid(_mark):
		_mark.mark_size = MARK_SIZE_SHORT if short_window else MARK_SIZE

	# Theme overrides land on the next sort, so ask for the new minimum sizes
	# before measuring: otherwise the panel is sized from the heading's old
	# type and every option sits a few pixels lower than it should.
	if is_instance_valid(_vbox):
		_vbox.update_minimum_size()

	var natural_size := _vbox.get_combined_minimum_size()
	var width := minf(maxf(_menu_width(), natural_size.x + horizontal_padding), available.x)
	var natural_height := natural_size.y + vertical_padding
	var height := minf(natural_height, available.y)
	var needs_scroll := natural_height > height + 1.0
	_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO if needs_scroll
		else ScrollContainer.SCROLL_MODE_DISABLED)
	_panel.custom_minimum_size = Vector2(width, height)


## The width the menu wants when there is room for it: a little narrower in the
## touch layout, where it may share the window with a small phone's edges.
func _menu_width() -> float:
	return 280.0 if has_node("/root/Screen") and Screen.uses_touch_layout() else 320.0


## Paint every action card: the shared frame recipe in this action's accent and
## its own sprite — including the shared focus treatment (the cream ring drawn
## outside the card and the warm wash over it). Cards are
## sized once, from the layout the menu opened in - a touch window gets the
## compact 44 px target with a small sprite, a desktop window the roomier card
## with a full-size one.
func _paint_buttons() -> void:
	var compact := _compact
	var height := CARD_HEIGHT_TOUCH if compact else CARD_HEIGHT
	var pad := CARD_PAD_TOUCH if compact else CARD_PAD
	var icon_side := int(roundf(float(CARD_FONT) * (CARD_ICON_SCALE_TOUCH if compact else CARD_ICON_SCALE)))
	for recipe in _recipes:
		var button: Button = recipe["button"]
		if not is_instance_valid(button):
			continue
		var accent: Color = recipe["accent"]
		var text_color: Color = recipe["text"]
		var hover_color := Color.WHITE if text_color == UIConstants.COLOR_TEXT else text_color.lightened(0.25)
		PixelButtonStyle.paint_card(button, accent, 0.0, pad, text_color, hover_color)
		button.custom_minimum_size = Vector2(0, height)
		button.icon = PixelIcon.texture(recipe["icon"], icon_side, accent)
		button.add_theme_constant_override("h_separation", 8 if compact else 10)
		if recipe["default"]:
			button.set_meta(InputManager.DEFAULT_FOCUS_META, true)


func _add_menu_button(parent: VBoxContainer, text: String, tooltip: String,
		callback: Callable, accent: Color, icon_kind: int,
		text_color: Color = UIConstants.COLOR_TEXT, default: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.name = text.replace(" ", "") + "Button"
	btn.tooltip_text = tooltip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", MenuScreenKit.SUBTITLE_FONT)
	btn.add_theme_font_size_override("font_size", CARD_FONT)
	# An outlined letter reads over the glassy card and over the course behind
	# it, exactly as it does on the title screen's cards.
	btn.add_theme_constant_override("outline_size", LABEL_OUTLINE_SIZE)
	btn.add_theme_color_override("font_outline_color", PixelButtonStyle.INK)
	btn.add_theme_color_override("font_shadow_color", Color(
		PixelButtonStyle.INK.r, PixelButtonStyle.INK.g, PixelButtonStyle.INK.b, 0.55))
	btn.add_theme_constant_override("shadow_offset_x", int(LABEL_SHADOW_OFFSET.x))
	btn.add_theme_constant_override("shadow_offset_y", int(LABEL_SHADOW_OFFSET.y))
	_buttons.append(btn)
	_recipes.append({
		"button": btn,
		"accent": accent,
		"text": text_color,
		"icon": icon_kind,
		"default": default,
	})
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_resume_pressed()
			get_viewport().set_input_as_handled()
		return
	# Controller B (the cancel action) resumes, like Escape.
	if event is InputEventJoypadButton and event.is_action_pressed("cancel"):
		_on_resume_pressed()
		get_viewport().set_input_as_handled()
		return

	# The game is paused behind this menu, but the player should still be
	# able to look around the course. This overlay is full-screen with
	# MOUSE_FILTER_STOP, so pointer events never reach the camera's
	# _unhandled_input — forward the ones that are over the dimmed backdrop
	# (not over the menu panel) to the camera instead.
	if camera != null and _is_camera_event(event):
		camera.handle_input_event(event, true)

## True when a pointer event should be forwarded to the camera: the pointer
## is over the dimmed backdrop rather than an interactive part of the menu,
## or the camera is already mid-drag (so the drag keeps flowing — including
## the release — even if the pointer moves over the panel).
func _is_camera_event(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		return _hover_is_backdrop()
	if event is InputEventMouseMotion:
		return camera.is_dragging() or _hover_is_backdrop()
	if event is InputEventMouseButton:
		if camera.is_dragging():
			return true
		if not _hover_is_backdrop():
			return false
		return event.button_index == MOUSE_BUTTON_MIDDLE \
			or event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	return false

func _hover_is_backdrop() -> bool:
	var hovered := _get_hovered_control()
	if hovered == null:
		return false
	return not _is_inside_panel(hovered)

## The control under the pointer. Split out so tests can simulate hover
## state (headless runs have no real mouse, so the viewport never reports a
## hovered control).
func _get_hovered_control() -> Control:
	return get_viewport().gui_get_hovered_control()

func _is_inside_panel(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		if node == _panel:
			return true
		node = node.get_parent()
	return false

## The pause overlay blocks normal GUI input across the screen, but its dimmed
## backdrop still allows camera gestures. TouchInput checks this before it
## decides whether a drag belongs to the UI.
func allows_touch_camera_gesture(screen_pos: Vector2) -> bool:
	if camera == null or not is_visible_in_tree():
		return false
	if _panel == null:
		return true
	var local_pos := _panel.get_global_transform_with_canvas().affine_inverse() * screen_pos
	return not Rect2(Vector2.ZERO, _panel.size).has_point(local_pos)

func _on_resume_pressed() -> void:
	resume_requested.emit()

func _on_save_pressed() -> void:
	save_requested.emit()

func _on_load_pressed() -> void:
	load_requested.emit()

func _on_save_course_pressed() -> void:
	save_course_requested.emit()

func _on_save_golfer_pressed() -> void:
	save_golfer_requested.emit()

func _on_settings_pressed() -> void:
	settings_requested.emit()

func _on_quit_to_menu_pressed() -> void:
	quit_to_menu_requested.emit()

func _on_quit_to_desktop_pressed() -> void:
	quit_to_desktop_requested.emit()
