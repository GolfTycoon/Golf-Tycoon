extends Control
class_name GameOverPanel
## GameOverPanel - Shown when the player goes bankrupt (money < -$1000)
##
## Displays game statistics celebrating what the player achieved,
## with options to retry (new game) or load a save.
##
## Like the pause menu and the confirmation dialogue, it fits the window it
## opens in: on a small or short window the legacy scrolls and the three
## options stay pinned at the bottom, so Quit to Menu is always reachable.

signal retry_requested
signal load_requested
signal quit_to_menu_requested

const PANEL_WIDTH := 450.0
const COMPACT_PANEL_WIDTH := 300.0
const BUTTON_HEIGHT := 40.0
const TOUCH_BUTTON_HEIGHT := 44.0

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null
var _stats_box: VBoxContainer = null
var _buttons: VBoxContainer = null
var _compact := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_fit_to_view.call_deferred()
	resized.connect(_fit_to_view)
	if has_node("/root/Screen"):
		Screen.changed.connect(func(_size: Vector2, _scale: float) -> void: _fit_to_view())

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _build_ui() -> void:
	# Dark overlay
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.0, 0.0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var compact := has_node("/root/Screen") and Screen.uses_touch_layout()
	_compact = compact
	var margin := 16 if compact else 30

	var panel = PanelContainer.new()
	panel.name = "GameOverCard"
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.08, 0.95)
	style.border_color = UIConstants.COLOR_DANGER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = 20 if compact else 24
	style.content_margin_bottom = 20 if compact else 24
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(_panel_width(), 0)
	_panel = panel
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox = vbox
	panel.add_child(vbox)

	# The legacy scrolls when the window is too short for it; the options below
	# keep their place at the bottom of the card, always on screen.
	var scroll = ScrollContainer.new()
	scroll.name = "LegacyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = scroll
	vbox.add_child(scroll)

	var stats_box = VBoxContainer.new()
	stats_box.name = "Legacy"
	stats_box.add_theme_constant_override("separation", 10)
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_box = stats_box
	scroll.add_child(stats_box)

	# Title
	var title = Label.new()
	title.text = "Course Closed"
	title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XL)
	title.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_box.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Your course has gone bankrupt."
	subtitle.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	subtitle.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.add_child(subtitle)

	stats_box.add_child(HSeparator.new())

	# Stats section - celebrate what the player achieved
	var stats_label = Label.new()
	stats_label.text = "Your Legacy"
	stats_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	stats_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_box.add_child(stats_label)

	# Gather stats
	var days = GameManager.current_day
	var holes = GameManager.current_course.holes.size() if GameManager.current_course else 0
	var rating = GameManager.course_rating.get("stars", 0)
	var total_hio = GameManager.course_records.get("total_hole_in_ones", 0)
	var best_round = GameManager.course_records.get("lowest_round")

	var years := GameCalendar.get_year(days) - GameCalendar.START_YEAR + 1
	_add_stat_row(stats_box, "Days Survived", "%d (%d year%s)" % [days, years, "s" if years != 1 else ""])
	_add_stat_row(stats_box, "Holes Built", str(holes))
	_add_stat_row(stats_box, "Best Course Rating", "%d star%s" % [rating, "s" if rating != 1 else ""])

	if total_hio > 0:
		_add_stat_row(stats_box, "Holes-in-One Witnessed", str(total_hio))

	if best_round and best_round is CourseRecords.RecordEntry:
		_add_stat_row(stats_box, "Course Record", "%d strokes by %s" % [best_round.value, best_round.golfer_name])

	var season_name = SeasonSystem.get_season_name(SeasonSystem.get_season(days))
	_add_stat_row(stats_box, "Final Date", "%s (%s)" % [GameCalendar.format_date_short(days), season_name])

	stats_box.add_child(HSeparator.new())

	# Buttons, pinned below the scrolling legacy so they never leave the screen.
	var btn_box = VBoxContainer.new()
	btn_box.name = "GameOverActions"
	btn_box.add_theme_constant_override("separation", 8)
	btn_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons = btn_box
	vbox.add_child(btn_box)

	var retry_btn = _make_button("Start New Game", UIConstants.FONT_SIZE_MD)
	retry_btn.pressed.connect(func(): retry_requested.emit())
	btn_box.add_child(retry_btn)

	var load_btn = _make_button("Load Saved Game", UIConstants.FONT_SIZE_MD)
	load_btn.pressed.connect(func(): load_requested.emit())
	btn_box.add_child(load_btn)

	var quit_btn = _make_button("Quit to Menu", UIConstants.FONT_SIZE_BASE)
	quit_btn.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	quit_btn.pressed.connect(func(): quit_to_menu_requested.emit())
	btn_box.add_child(quit_btn)

## A comfortable target at every window shape: full width on a touch layout,
## a fixed 300px otherwise.
func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	if _compact:
		button.custom_minimum_size = Vector2(0, TOUCH_BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		button.custom_minimum_size = Vector2(300, BUTTON_HEIGHT)
	return button

func _panel_width() -> float:
	return COMPACT_PANEL_WIDTH if has_node("/root/Screen") and Screen.uses_touch_layout() else PANEL_WIDTH

## Clamp the card to the space a modal may use, keeping the three options on
## screen: only the legacy above them scrolls.
func _fit_to_view() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_vbox) \
			or not is_instance_valid(_scroll) or not is_instance_valid(_stats_box) \
			or not is_instance_valid(_buttons):
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

	var buttons_height := _buttons.get_combined_minimum_size().y
	var separation := float(_vbox.get_theme_constant("separation"))
	var stats_size := _stats_box.get_combined_minimum_size()
	var natural_size := Vector2(
		maxf(stats_size.x, _buttons.get_combined_minimum_size().x),
		stats_size.y + separation + buttons_height)
	var width := minf(maxf(_panel_width(), natural_size.x + horizontal_padding), available.x)
	var natural_height := natural_size.y + vertical_padding

	var height := minf(natural_height, available.y)
	var stats_height := clampf(height - vertical_padding - separation - buttons_height, 0.0, stats_size.y)
	var needs_scroll := stats_size.y > stats_height + 1.0
	_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO if needs_scroll
		else ScrollContainer.SCROLL_MODE_DISABLED)
	_scroll.custom_minimum_size = Vector2(0.0, stats_height)
	_panel.custom_minimum_size = Vector2(width, height)

func _add_stat_row(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	value.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	parent.add_child(row)
