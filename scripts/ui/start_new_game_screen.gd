extends Control
class_name StartNewGameScreen
const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")
## StartNewGameScreen - Company setup shown after "Start New Game".
##
## Collects the company name, difficulty, starting budget, how many holes the
## first course should start with, which game features are enabled and whether
## the tutorial walks the player through an empty first course. The features -
## and the section that lists them - come from mods: with nothing registered
## there, the section is not built at all. The Choose
## Location button hands those options to the World Map screen, where the
## player buys the location for their first course.
##
## The screen sits on the title screen's shared background image and uses its
## notched nine-patch pixel frames, Pixelify Sans lettering and hard-edged
## sprite icons. It is built in one of four arrangements picked from the
## window size (see layout_mode_for):
##
##  * WIDE - desktops and landscape tablets: the choices as a sheet of option
##    cards, and beside it a "your company" rail with a live plan of the course
##    that will be generated, a summary of every choice and the Choose Location
##    button. Nothing scrolls and nothing is a narrow strip in the middle.
##  * TABLET - portrait tablets: the same cards in one centred column, the
##    course plan next to the hole picker, Choose Location pinned in a footer.
##  * LANDSCAPE - rotated phones and squat windows: two compact columns of
##    segmented pickers with Choose Location always on screen, plus the
##    course plan once the window is tall enough for it.
##  * PHONE - one scrolling column of thumb-sized pickers over a pinned footer
##    with the Choose Location button.
##
## Every option shows what it does (difficulty effects, par, what a feature
## changes) instead of a bare label, and the course plan is drawn from the
## same layout table GeneratedCourse paints from. Choices live in plain fields,
## so rebuilding for a new window size never loses what the player picked.
##
## Wrapped text reserves the lines its longest possible text needs, so the
## content's height is known as soon as it is built: WIDE is then scaled to
## fill the window and LANDSCAPE to fit it, neither scrolling (_fit_to_window).

signal next_requested(options: Dictionary)
signal back_requested()

## -1 is GameManager.UNLIMITED_MONEY (kept literal so this file has no
## autoload dependency at parse time).
const MONEY_OPTIONS: Array[int] = [100000, 150000, 200000, -1]
const HOLE_OPTIONS: Array[int] = [0, 3, 6, 9, 18]

enum Layout { WIDE, TABLET, LANDSCAPE, PHONE }

## Breakpoints. WIDE needs a landscape window with room for the sheet beside
## the rail without scrolling; TABLET needs the height for one column of
## cards above a footer. Anything else wider than tall is LANDSCAPE, the rest
## PHONE.
const WIDE_MIN_WIDTH := 1000
const WIDE_MIN_HEIGHT := 640
const TABLET_MIN_WIDTH := 700
const TABLET_MIN_HEIGHT := 760
const LANDSCAPE_MIN_WIDTH := 600
## Same-arrangement resizes past this share of the window rebuild the tree at
## once so card heights and type are re-measured (see MainMenu)...
const REPROPORTION_STEP := 0.12
## ...and smaller ones rebuild once the window has stopped changing for this
## long, because the line budgets reserved for wrapped text (and the fitted
## scale) belong to the width they were measured at.
const SETTLE_DELAY := 0.2
## WIDE content is scaled to fill this share of the window height (it never
## scrolls, and a desktop has height to spare); LANDSCAPE only shrinks to fit.
const WIDE_FILL := 0.86
## WIDE type never grows past the window width / this, however tall the
## window: the cards' text has to fit across as well as down.
const WIDE_WIDTH_PER_SCALE := 1150.0
## Scale range per arrangement - type and spacing are clamped inside it.
const SCALE_RANGE := {
	Layout.WIDE: Vector2(0.74, 1.8),
	Layout.TABLET: Vector2(0.84, 1.3),
	Layout.LANDSCAPE: Vector2(0.72, 1.2),
	Layout.PHONE: Vector2(0.82, 1.2),
}

## Content never spreads wider than this; extra width becomes even margins.
const MAX_WIDTH := {
	Layout.WIDE: 1880.0,
	Layout.TABLET: 940.0,
	Layout.LANDSCAPE: 1400.0,
	Layout.PHONE: 520.0,
}
const TITLE_TEXT := "Start New Game"
const CTA_TEXT := "Choose Location"
const WORLD_MAP_STATE_SCRIPT := preload("res://scripts/autoload/world_map_state.gd")
const NEXT_TOOLTIP := "Choose the location for your first course"
const MONEY_TOOLTIP := "The company's opening balance. Location prices, land and buildings all come out of it."
const NAME_PLACEHOLDER := "Your golf company"
const TUTORIAL_TITLE := "Guided tutorial"
const TUTORIAL_TOOLTIP := "Step-by-step help on your first empty course: paint the course, open a hole, place a building and set your green fee. It only runs on an empty course, so it is not used when holes are generated."
## Under the switch where there is room for it (phones and tablets, which have
## no tooltips).
const TUTORIAL_CAPTION := "Step-by-step help on an empty first course. Not used when holes are generated."

## Accent per difficulty: green, gold, coral - easy to hard.
const DIFFICULTY_ACCENTS := {
	DifficultyPresets.Preset.EASY: Color("8fc79b"),
	DifficultyPresets.Preset.NORMAL: Color("e5c57c"),
	DifficultyPresets.Preset.HARD: Color("e38b70"),
}
const MONEY_ACCENT := Color("e5c57c")
const HOLES_ACCENT := Color("8fc79b")
const FEATURE_ACCENT := Color("8fc79b")

## The company setup shares the title screen's chunky, readable Pixelify Sans
## lettering: Bold for the heading and the next step, SemiBold for option
## titles and kickers, Regular for the explanatory copy and entered name.
const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

const MONEY_CAPTIONS := {
	100000: "A lean start",
	150000: "Room to grow",
	200000: "Deep pockets",
	-1: "No budget limit",
}

## The shipped feature ids and their wording: [key, title, short caption,
## tooltip, glyph]. A mod that registers one of these ids (the Weather, Wind
## and Seasons mods do) may supply only the id and gets this copy; an id that
## is not here must bring its own title.
const FEATURES := [
	["weather", "Weather", "Storms change turnout",
		"Storms and clouds change how often golfers come out and how they play.", SetupGlyph.Kind.WEATHER],
	["wind", "Wind", "Shots drift off line",
		"Wind pushes shots off line and changes how far they carry.", SetupGlyph.Kind.WIND],
	["seasons", "Seasons", "Demand follows the year",
		"Demand, upkeep and weather shift with the calendar year.", SetupGlyph.Kind.SEASONS],
]

## One selectable card: a toggle Button underneath (click, focus, keyboard,
## hover), its drawn content laid over it with mouse input passed through.
class ChoiceCard:
	var group := ""
	var value: Variant
	var accent := Color.WHITE
	var cell: MarginContainer
	var button: Button
	var content: MarginContainer
	var title: Label
	var check: SetupGlyph
	var glyph: SetupGlyph
	var switch: SetupGlyph

## Sizes for one build, measured from the window.
class Metrics:
	var view := Vector2.ZERO
	var u := 1.0
	var pad := 24
	var gap := 20
	var max_width := 1880.0
	var panel_pad := 20
	var section_gap := 18
	var item_gap := 10
	var kicker_font := 12
	var kicker_gap := 8
	var title_font := 32
	var body_font := 16
	var caption_font := 13
	var option_font := 18
	var number_font := 24
	var glyph := 24
	var card_pad := 14
	var radius := 12
	var input_height := 48
	var segment_height := 48
	var hole_height := 60
	var feature_height := 64
	var cta_height := 56
	var cta_font := 20
	var back_height := 44
	var back_font := 15
	var rail_width := 400.0
	var plan_min := 200.0
	var footer_height := 0.0
	## Short WIDE windows: difficulty cards drop their description (it stays
	## in the tooltip) and keep the title and the concrete effects.
	var dense := false
	## LANDSCAPE with height to spare: the course plan beside its caption and
	## money as captioned cards.
	var landscape_plan := false

# --- choices (survive rebuilds) ----------------------------------------------
var _company_name := ""
var _difficulty: int = DifficultyPresets.Preset.NORMAL
var _money: int = 100000
var _holes: int = 0
var _features: Dictionary = {"weather": false, "wind": false, "seasons": false}
## Starts as the company's choice would: on until the tutorial has been
## finished, as it always was.
var _tutorial_enabled: bool = true

## The Features section shows only what a mod has put there. Each shipped
## environment mod (Weather, Wind, Seasons) registers its option when it loads
## through ModAPI.register_feature_option, and any other mod can add its own;
## with no mod offering one, the section is not built at all.
func _has_features() -> bool:
	return not _available_features().is_empty()

## Every option a loaded mod has registered, in load order.
static func _registered_feature_options() -> Array:
	var options: Array = []
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		var manager: Node = (loop as SceneTree).root.get_node_or_null("ModManager")
		if manager != null and manager.has_method("get_feature_options"):
			options.append_array(manager.get_feature_options())
	return options

## The options to build, shipped features first in their catalogue order and
## then anything else in the order the mods registered it. Each is
## [key, title, caption, tooltip, glyph].
func _available_features() -> Array:
	var by_key: Dictionary = {}
	var order: Array = []
	for option in _registered_feature_options():
		var entry := feature_entry(option)
		if entry.is_empty() or by_key.has(str(entry[0])):
			continue
		by_key[str(entry[0])] = entry
		order.append(str(entry[0]))
	var result: Array = []
	for shipped in FEATURES:
		var key := str(shipped[0])
		if by_key.has(key):
			result.append(by_key[key])
			order.erase(key)
	for key in order:
		result.append(by_key[key])
	return result

## Normalise one registered option (a Dictionary or a [key, title, caption,
## tooltip, glyph] array) into that five-entry form, starting from the shipped
## copy for a known key and skipping anything without an id. A mod may supply
## only the id; the title, caption, tooltip and glyph then default.
static func feature_entry(option: Variant) -> Array:
	var key := ""
	if option is Dictionary:
		key = str(option.get("id", ""))
	elif option is Array and option.size() >= 2:
		key = str(option[0])
	key = key.strip_edges()
	if key.is_empty():
		return []
	var entry: Array = [key, "", "", "", SetupGlyph.Kind.WEATHER]
	for shipped in FEATURES:
		if str(shipped[0]) == key:
			entry = shipped.duplicate()
			break
	if option is Dictionary:
		for field in [["name", 1], ["title", 1], ["caption", 2], ["description", 3],
				["tooltip", 3], ["glyph", 4]]:
			if option.has(field[0]) and not str(option[field[0]]).strip_edges().is_empty():
				entry[field[1]] = option[field[0]]
	elif option is Array:
		for i in range(1, mini(option.size(), 5)):
			if not str(option[i]).strip_edges().is_empty():
				entry[i] = option[i]
	if str(entry[1]).strip_edges().is_empty():
		entry[1] = key.capitalize()
	return entry

## The title of one feature, as the mod that registered it spells it (or the
## shipped copy, or the key in title case when nothing registered it).
static func feature_title(key: String) -> String:
	for option in _registered_feature_options():
		var entry := feature_entry(option)
		if not entry.is_empty() and str(entry[0]) == key:
			return str(entry[1])
	for shipped in FEATURES:
		if str(shipped[0]) == key:
			return str(shipped[1])
	return key.capitalize()

# --- current build ---------------------------------------------------------
var _layout_mode: int = Layout.WIDE
var _built_size := Vector2.ZERO
var _resize_serial := 0
var _metrics_cache: Metrics
var _page: MarginContainer = null
## The arrangement's outer column - measured to fit WIDE and LANDSCAPE.
var _column: Control = null
var _company_input: LineEdit = null
var _difficulty_buttons: Array = []
var _money_buttons: Array = []
var _hole_buttons: Array = []
## Feature key -> its toggle Button (button_pressed = enabled).
var _feature_boxes: Dictionary = {}
## The tutorial switch (its card holds the Button).
var _tutorial_card: ChoiceCard = null
var _choices: Array = []
var _hole_hint: Label = null
var _difficulty_hint: Label = null
var _course_plan: CoursePlanPreview = null
var _plan_caption: Label = null
var _summary_company: Label = null
var _summary_values: Dictionary = {}
var _footer_summary: Label = null
var _next_button: Button = null
var _back_button: Button = null

func _init() -> void:
	_company_name = WorldLocations.random_company_name()
	_tutorial_enabled = WORLD_MAP_STATE_SCRIPT.default_tutorial_enabled()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "StartNewGameScreen"
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_build()

	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _on_screen_changed(new_size: Vector2, _world_scale: float) -> void:
	if _current_layout() != _layout_mode:
		_build()
		return
	# A ScrollContainer sizes its child to the child's minimum, so the page
	# has to be told about the new window even when nothing else changes.
	if _page != null:
		_page.custom_minimum_size = Vector2(new_size.x, new_size.y - _footer_height())
	if absf(new_size.x - _built_size.x) > _built_size.x * REPROPORTION_STEP \
			or absf(new_size.y - _built_size.y) > _built_size.y * REPROPORTION_STEP:
		_build()
		return
	if new_size != _built_size and is_inside_tree():
		_resize_serial += 1
		var serial := _resize_serial
		get_tree().create_timer(SETTLE_DELAY).timeout.connect(_on_resize_settled.bind(serial))

func _on_resize_settled(serial: int) -> void:
	if serial == _resize_serial and is_inside_tree() and _window_size() != _built_size:
		_build()

func _current_layout() -> int:
	return layout_mode_for(_window_size())

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

## Which of the four arrangements a window size gets. Pure, so the breakpoints
## can be unit-tested without a window.
static func layout_mode_for(window_size: Vector2) -> int:
	if window_size.x >= WIDE_MIN_WIDTH and window_size.y >= WIDE_MIN_HEIGHT and window_size.x > window_size.y:
		return Layout.WIDE
	if window_size.x >= TABLET_MIN_WIDTH and window_size.y >= TABLET_MIN_HEIGHT:
		return Layout.TABLET
	if window_size.x >= LANDSCAPE_MIN_WIDTH and window_size.x > window_size.y:
		return Layout.LANDSCAPE
	return Layout.PHONE

func _footer_height() -> float:
	return _metrics_cache.footer_height if _metrics_cache else 0.0

# =============================================================================
# METRICS
# =============================================================================

## Every size in a build comes from here: one scale factor `u` per
## arrangement, then clamped type and spacing derived from it.
func _measure(mode: int, view: Vector2, scale_override: float = -1.0, dense: bool = false) -> Metrics:
	var m := Metrics.new()
	m.view = view
	m.dense = dense
	m.max_width = MAX_WIDTH[mode]
	var u := 1.0
	match mode:
		Layout.WIDE:
			u = clampf(minf(view.y / 900.0, view.x / 1450.0), 0.74, 1.8)
			m.pad = int(clampf(minf(view.x, view.y) * 0.042, 18.0, 64.0))
			m.gap = int(clampf(view.x * 0.016, 16.0, 32.0))
		Layout.TABLET:
			u = clampf(minf(view.x / 820.0, view.y / 1120.0), 0.84, 1.3)
			m.pad = int(clampf(view.x * 0.035, 16.0, 40.0))
			m.gap = int(clampf(view.y * 0.014, 12.0, 22.0))
		Layout.LANDSCAPE:
			u = clampf(minf(view.y / 430.0, view.x / 900.0), 0.8, 1.2)
			m.pad = int(clampf(view.y * 0.028, 8.0, 20.0))
			m.gap = int(clampf(view.y * 0.024, 8.0, 16.0))
		_:
			u = clampf(view.x / 400.0, 0.82, 1.2)
			m.pad = int(clampf(view.x * 0.03, 10.0, 18.0))
			m.gap = int(clampf(view.x * 0.03, 10.0, 16.0))
	if scale_override > 0.0:
		u = scale_override
	m.u = u
	m.panel_pad = _px(20.0, u, 12, 36)
	m.section_gap = _px(20.0, u, 12, 36)
	m.item_gap = _px(10.0, u, 6, 18)
	m.kicker_font = _px(12.0, u, 11, 19)
	m.kicker_gap = _px(8.0, u, 5, 13)
	m.title_font = _px(32.0, u, 22, 56)
	m.body_font = _px(17.0, u, 14, 28)
	m.caption_font = _px(13.0, u, 12, 21)
	m.option_font = _px(19.0, u, 15, 31)
	m.number_font = _px(24.0, u, 18, 40)
	m.glyph = _px(24.0, u, 18, 40)
	m.card_pad = _px(14.0, u, 10, 24)
	m.radius = _px(12.0, u, 10, 18)
	m.input_height = _px(48.0, u, 44, 76)
	m.segment_height = _px(48.0, u, 44, 74)
	m.hole_height = _px(62.0, u, 52, 100)
	m.feature_height = _px(64.0, u, 52, 104)
	m.cta_height = _px(58.0, u, 48, 90)
	m.cta_font = _px(20.0, u, 16, 32)
	m.back_height = _px(44.0, u, 44, 66)
	m.back_font = _px(15.0, u, 14, 24)
	match mode:
		Layout.WIDE:
			var inner := minf(view.x, m.max_width) - float(m.pad) * 2.0
			m.rail_width = clampf(inner * 0.28, 300.0, 500.0)
			m.plan_min = clampf(view.y * 0.22, 150.0, 420.0)
		Layout.TABLET:
			m.plan_min = clampf(view.x * 0.24, 170.0, 260.0)
			m.footer_height = float(m.cta_height + m.panel_pad + int(m.panel_pad * 0.6))
		Layout.LANDSCAPE:
			m.section_gap = _px(12.0, u, 8, 18)
			m.panel_pad = _px(14.0, u, 10, 20)
			m.kicker_gap = _px(5.0, u, 4, 8)
			m.title_font = _px(22.0, u, 18, 28)
			m.hole_height = m.segment_height
			m.feature_height = m.segment_height
			m.cta_height = _px(50.0, u, 46, 58)
			m.input_height = m.segment_height
			m.landscape_plan = view.y >= 540.0
			m.plan_min = clampf(view.y * 0.3, 130.0, 220.0)
		_:
			m.section_gap = _px(18.0, u, 12, 22)
			m.panel_pad = _px(14.0, u, 10, 18)
			m.title_font = _px(24.0, u, 20, 30)
			m.plan_min = clampf(view.x * 0.42, 130.0, 210.0)
			m.feature_height = _px(92.0, u, 84, 104)
			m.cta_height = _px(52.0, u, 48, 58)
			m.footer_height = float(m.cta_height + m.pad * 2)
	return m

## Width inside the sheet that holds the option cards.
func _sheet_content_width(m: Metrics) -> float:
	var frame := minf(m.view.x - float(m.pad) * 2.0, m.max_width)
	match _layout_mode:
		Layout.WIDE:
			return frame - m.rail_width - float(m.gap) - float(m.panel_pad) * 2.0
		Layout.LANDSCAPE:
			return (frame - float(m.gap)) * 0.5 - float(m.panel_pad) * 2.0
	return frame - float(m.panel_pad) * 2.0

static func _px(base: float, u: float, lo: int, hi: int) -> int:
	return int(clampf(roundf(base * u), float(lo), float(hi)))

# =============================================================================
# BUILD
# =============================================================================

## Tear the screen down and build it again for the current window. The
## choices live in fields, so only the controls are thrown away.
func _build() -> void:
	if _company_input != null and is_instance_valid(_company_input):
		_company_name = _company_input.text
	_layout_mode = _current_layout()
	_built_size = _window_size()
	var m := _measure(_layout_mode, _built_size)
	_populate(m)
	if _layout_mode == Layout.WIDE or _layout_mode == Layout.LANDSCAPE:
		_fit_to_window(m)
	_update_selection_styles()

## WIDE and LANDSCAPE promise a screen that never scrolls. Every wrapped label
## reserves a fixed number of lines, so the content's height is known straight
## after a build: measure it, and rebuild at the scale that fills WIDE_FILL of
## the window (WIDE) or just fits (LANDSCAPE). The height does not grow in
## step with the scale (type and targets are clamped), so it takes a couple of
## corrections; the largest scale that fitted wins.
func _fit_to_window(m: Metrics) -> void:
	_fit_scale(m)
	if _layout_mode == Layout.WIDE and not _metrics_cache.dense and _overflow() > 0.5:
		var dense := _measure(_layout_mode, m.view, -1.0, true)
		_populate(dense)
		_fit_scale(dense)

## How far the content runs past the window (0 when it fits).
func _overflow() -> float:
	var m := _metrics_cache
	return maxf(0.0, _column.get_combined_minimum_size().y - (m.view.y - m.footer_height - float(m.pad) * 2.0))

func _fit_scale(m: Metrics) -> void:
	var available := m.view.y - float(m.pad) * 2.0
	var range_u: Vector2 = SCALE_RANGE[_layout_mode]
	if _layout_mode == Layout.WIDE:
		range_u.y = maxf(range_u.x, minf(range_u.y, m.view.x / WIDE_WIDTH_PER_SCALE))
	var best_fit := -1.0
	for attempt in 4:
		var needed := _column.get_combined_minimum_size().y
		var fits := needed <= available + 0.5
		if fits:
			best_fit = maxf(best_fit, m.u)
		var target := available * WIDE_FILL if _layout_mode == Layout.WIDE else available
		if fits and (_layout_mode != Layout.WIDE or needed >= target * 0.96):
			return
		var u := clampf(m.u * target / maxf(needed, 1.0), range_u.x, range_u.y)
		if not fits:
			# Step under the estimate: the clamped parts shrink less.
			u = maxf(range_u.x, minf(u, m.u - 0.02))
		elif best_fit > 0.0 and u <= best_fit + 0.005:
			return
		if absf(u - m.u) < 0.01:
			break
		m = _measure(_layout_mode, m.view, u, m.dense)
		_populate(m)
	if _column.get_combined_minimum_size().y > available + 0.5 and best_fit > 0.0:
		_populate(_measure(_layout_mode, m.view, best_fit, m.dense))

## Throw away the current controls and build the arrangement for `m`.
func _populate(m: Metrics) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_reset_references()
	_metrics_cache = m

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	match _layout_mode:
		Layout.WIDE:
			_build_wide(m)
		Layout.TABLET:
			_build_tablet(m)
		Layout.LANDSCAPE:
			_build_landscape(m)
		_:
			_build_phone(m)

func _reset_references() -> void:
	_page = null
	_column = null
	_company_input = null
	_difficulty_buttons = []
	_money_buttons = []
	_hole_buttons = []
	_feature_boxes = {}
	_tutorial_card = null
	_choices = []
	_hole_hint = null
	_difficulty_hint = null
	_course_plan = null
	_plan_caption = null
	_summary_company = null
	_summary_values = {}
	_footer_summary = null
	_next_button = null
	_back_button = null

## Wide: header across the top; the option sheet and the company rail side by
## side below it.
func _build_wide(m: Metrics) -> void:
	var page := _make_page(m)
	var frame := _frame(page, m)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", m.gap)
	frame.add_child(column)
	_column = column
	column.add_child(_make_header(m, true))

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", m.gap)
	column.add_child(body)

	var form := _make_sheet(body, m, "Sheet")
	form.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_make_section("Company name", _make_company_row(m), m))
	form.add_child(_make_section("Difficulty", _make_difficulty_cards(m, _sheet_content_width(m)), m))
	form.add_child(_make_section("Starting money", _make_money_cards(m, 4, _sheet_content_width(m)), m))
	var width := _sheet_content_width(m)
	if not _has_features():
		form.add_child(_make_section("Generated holes", _make_holes_block(m, false, width), m))
	else:
		# Holes and features share a row when the sheet is wide enough for five
		# segments and three feature tiles side by side.
		var paired := width >= 900.0
		var pair_gap := m.section_gap + m.item_gap
		var holes_width := (width - float(pair_gap)) / 2.15 if paired else width
		var holes := _make_section("Generated holes", _make_holes_block(m, false, holes_width), m)
		var features := _make_section("Game features", _make_feature_tiles(m, "card" if paired else "row",
			width - float(pair_gap) - holes_width if paired else width), m)
		if paired:
			var pair := HBoxContainer.new()
			pair.name = "HolesAndFeatures"
			pair.add_theme_constant_override("separation", pair_gap)
			holes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holes.size_flags_stretch_ratio = 1.0
			features.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			features.size_flags_stretch_ratio = 1.15
			pair.add_child(holes)
			pair.add_child(features)
			form.add_child(pair)
		else:
			form.add_child(holes)
			form.add_child(features)

	var rail := _make_rail(m)
	rail.custom_minimum_size.x = m.rail_width
	body.add_child(rail)

## Tablet: one centred column of cards, Choose Location in a pinned footer.
func _build_tablet(m: Metrics) -> void:
	var page := _make_page(m)
	var frame := _frame(page, m)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", m.gap)
	frame.add_child(column)
	_column = column
	column.add_child(_make_header(m))

	var form := _make_sheet(column, m, "Sheet")
	form.add_child(_make_section("Company name", _make_company_row(m), m))
	var width := _sheet_content_width(m)
	form.add_child(_make_section("Difficulty", _make_difficulty_cards(m, width), m))
	form.add_child(_make_section("Starting money", _make_money_cards(m, 4, width), m))
	form.add_child(_make_section("Generated holes", _make_holes_block(m, true, width), m))
	if _has_features():
		form.add_child(_make_section("Game features", _make_feature_tiles(m, "card", width), m))
	form.add_child(_make_section("Tutorial", _make_tutorial_block(m, width), m))
	_make_footer(m, true)

## Landscape: two compact columns, everything (including Choose Location) on
## screen without scrolling on a rotated phone.
func _build_landscape(m: Metrics) -> void:
	var page := _make_page(m)
	var frame := _frame(page, m)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", m.gap)
	frame.add_child(column)
	_column = column
	column.add_child(_make_header(m, true))

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", m.gap)
	column.add_child(body)

	var left := _make_sheet(body, m, "LeftSheet")
	left.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var width := _sheet_content_width(m)
	left.add_child(_make_section("Company name", _make_company_row(m), m))
	var difficulty := _make_section("Difficulty", _make_difficulty_segments(m), m)
	_difficulty_hint = _make_hint(m, _difficulty_hint_texts(2), width, 2)
	difficulty.add_child(_difficulty_hint)
	left.add_child(difficulty)
	# Cards and segments are different Control subclasses; both branches are
	# widened to their shared base so the ternary's value types are compatible.
	var money_block := (_make_money_cards(m, 2) as Control) if m.landscape_plan \
			else (_make_money_segments(m) as Control)
	left.add_child(_make_section("Starting money", money_block, m))

	var right := _make_sheet(body, m, "RightSheet")
	right.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_make_section("Generated holes", _make_holes_block(m, m.landscape_plan, width), m))
	if _has_features():
		right.add_child(_make_section("Game features", _make_feature_tiles(m, "chip", width), m))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(_make_cta(m))

## Phone: one scrolling column, Choose Location pinned to the bottom edge.
func _build_phone(m: Metrics) -> void:
	var page := _make_page(m)
	var frame := _frame(page, m)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", m.gap)
	frame.add_child(column)
	_column = column
	column.add_child(_make_header(m))

	var form := _make_sheet(column, m, "Sheet")
	var width := _sheet_content_width(m)
	form.add_child(_make_section("Company name", _make_company_row(m), m))
	var difficulty := _make_section("Difficulty", _make_difficulty_segments(m), m)
	_difficulty_hint = _make_hint(m, _difficulty_hint_texts(4), width, 3)
	difficulty.add_child(_difficulty_hint)
	form.add_child(difficulty)
	form.add_child(_make_section("Starting money", _make_money_cards(m, 2), m))
	form.add_child(_make_section("Generated holes", _make_holes_block(m, true, width), m))
	if _has_features():
		form.add_child(_make_section("Game features", _make_feature_tiles(m, "stack", width), m))
	form.add_child(_make_section("Tutorial", _make_tutorial_block(m, width), m))
	_make_footer(m, false)

# =============================================================================
# PAGE STRUCTURE
# =============================================================================

## The scrollable page: full-rect (minus a pinned footer), vertical scroll
## only, content centred while it fits and reachable when it does not.
func _make_page(m: Metrics) -> MarginContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -m.footer_height
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED \
		if m.view.x >= 320.0 else ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	# The game theme gives ScrollContainer an opaque panel; the backdrop has
	# to show through.
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.name = "Page"
	margin.custom_minimum_size = Vector2(m.view.x, m.view.y - m.footer_height)
	_page = margin
	scroll.add_child(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, m.pad)
	return margin

## Keeps content from spreading past the arrangement's maximum width; the
## extra becomes an even margin either side.
func _frame(page: MarginContainer, m: Metrics) -> MarginContainer:
	var frame := MarginContainer.new()
	frame.name = "Frame"
	var side := int(maxf(0.0, (m.view.x - float(m.pad) * 2.0 - m.max_width) * 0.5))
	frame.add_theme_constant_override("margin_left", side)
	frame.add_theme_constant_override("margin_right", side)
	page.add_child(frame)
	return frame

## A translucent panel holding a column of sections. Returns the column.
func _make_sheet(parent: Control, m: Metrics, sheet_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = sheet_name
	panel.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.72), MenuStyle.SHEET_BG,
		m.panel_pad, m.panel_pad))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Sections"
	column.add_theme_constant_override("separation", m.section_gap)
	panel.add_child(column)
	return column

## A kicker over its content.
func _make_section(title: String, content: Control, m: Metrics) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = title.to_pascal_case()
	section.add_theme_constant_override("separation", m.kicker_gap)
	section.add_child(Kit.make_kicker(title, m.kicker_font))
	section.add_child(content)
	return section

func _make_header(m: Metrics, with_tutorial: bool = false) -> Control:
	# The header is the shared screen header, sized for the window's layout
	# mode like every other screen's bar; the tutorial switch sits on its right.
	var header := Kit.make_screen_header(Kit.layout_mode_for(_window_size()), TITLE_TEXT,
		"Company setup", "", func(): back_requested.emit())
	_back_button = header.get_node("BackButton") as Button
	if with_tutorial:
		_make_tutorial_chip(m, header)
	return header

# =============================================================================
# SECTIONS
# =============================================================================

## Name field plus the random-name die.
func _make_company_row(m: Metrics) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CompanyRow"
	row.add_theme_constant_override("separation", m.item_gap)

	_company_input = LineEdit.new()
	_company_input.name = "CompanyInput"
	_company_input.text = _company_name
	_company_input.placeholder_text = NAME_PLACEHOLDER
	_company_input.max_length = 40
	_company_input.accessibility_name = "Company name"
	_company_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_company_input.custom_minimum_size = Vector2(0, m.input_height)
	_company_input.add_theme_font_override("font", BODY_FONT)
	_company_input.add_theme_font_size_override("font_size", m.body_font)
	_company_input.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	_company_input.add_theme_color_override("font_placeholder_color", UIConstants.COLOR_TEXT_MUTED)
	_company_input.add_theme_color_override("caret_color", MenuStyle.ACCENT_PRIMARY)
	_company_input.add_theme_color_override("selection_color", MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.35))
	var field_pad := int(float(m.input_height) * 0.3)
	PixelButtonStyle.paint_field(_company_input, MenuStyle.ACCENT_PRIMARY,
		MenuStyle.INSET_BG, field_pad)
	_company_input.text_changed.connect(_on_company_name_changed)
	row.add_child(_company_input)

	var dice := _make_shell_button("RandomNameButton", MenuStyle.ACCENT_UTILITY)
	dice.tooltip_text = "Pick a random company name"
	dice.accessibility_name = "Random company name"
	dice.custom_minimum_size = Vector2(m.input_height, m.input_height)
	# A Button is not a container: a full-rect CenterContainer keeps the die
	# centred whatever size the row gives the button.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(SetupGlyph.make_pixel(SetupGlyph.Kind.DICE, float(m.input_height) * 0.62))
	dice.add_child(center)
	dice.pressed.connect(_on_random_name_pressed)
	row.add_child(dice)
	return row

## WIDE / TABLET: three description cards.
func _make_difficulty_cards(m: Metrics, width: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "DifficultyCards"
	row.add_theme_constant_override("separation", m.item_gap)
	var group := ButtonGroup.new()
	# Every card reserves the lines the longest description needs, so the
	# three stay level and none cuts its description short.
	var text_width := (width - float(m.item_gap) * 2.0) / 3.0 - float(m.card_pad) * 2.0
	var descriptions := []
	for preset in DifficultyPresets.get_all_presets():
		descriptions.append(str(DifficultyPresets.get_modifiers(preset).get("description", "")))
	for preset in DifficultyPresets.get_all_presets():
		var accent: Color = DIFFICULTY_ACCENTS.get(preset, MONEY_ACCENT)
		var mods := DifficultyPresets.get_modifiers(preset)
		var card := _make_choice("difficulty", preset, accent, difficulty_tooltip(preset),
			str(mods.get("name", "")), m, group)
		var stack := _content_column(card, int(4.0 * m.u))
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", m.item_gap)
		card.glyph = SetupGlyph.make_pixel(SetupGlyph.Kind.DIFFICULTY, float(m.glyph), preset + 1, accent)
		top.add_child(card.glyph)
		card.title = _make_option_label(str(mods.get("name", "")), m.option_font, UIConstants.COLOR_TEXT)
		card.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(card.title)
		card.check = SetupGlyph.make_pixel(SetupGlyph.Kind.CHECK, float(m.glyph) * 0.8, 1, accent)
		top.add_child(card.check)
		stack.add_child(top)
		if not m.dense:
			var caption := _make_label(str(mods.get("description", "")), m.caption_font, UIConstants.COLOR_TEXT_DIM)
			_reserve_lines(caption, descriptions, text_width, 4)
			stack.add_child(caption)
		var effects := _make_label(difficulty_effects_line(preset), m.caption_font, accent)
		effects.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		stack.add_child(effects)
		_finish_choice(card, row)
		_difficulty_buttons.append(card.button)
	return row

## LANDSCAPE / PHONE: a three-way segmented picker (the hint below it carries
## the description).
func _make_difficulty_segments(m: Metrics) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "DifficultySegments"
	row.add_theme_constant_override("separation", int(m.item_gap * 0.8))
	var group := ButtonGroup.new()
	for preset in DifficultyPresets.get_all_presets():
		var accent: Color = DIFFICULTY_ACCENTS.get(preset, MONEY_ACCENT)
		var mods := DifficultyPresets.get_modifiers(preset)
		var card := _make_choice("difficulty", preset, accent, difficulty_tooltip(preset),
			str(mods.get("name", "")), m, group, Vector2(0, m.segment_height), int(m.card_pad * 0.6))
		var line := _content_row(card, int(m.item_gap * 0.8))
		card.glyph = SetupGlyph.make_pixel(SetupGlyph.Kind.DIFFICULTY, float(m.glyph) * 0.75, preset + 1, accent)
		line.add_child(card.glyph)
		card.title = _make_option_label(str(mods.get("name", "")), m.option_font - 2, UIConstants.COLOR_TEXT)
		line.add_child(card.title)
		_finish_choice(card, row)
		_difficulty_buttons.append(card.button)
	return row

## Money as cards with a coin glyph and caption, in `columns` columns.
func _make_money_cards(m: Metrics, columns: int, width: float = 0.0) -> GridContainer:
	# Four across need room for the glyph, the amount and the check badge;
	# without it the badge goes (the gold frame still marks the pick), and
	# failing that the cards go two by two.
	var with_check := columns >= 4
	if columns >= 4 and width > 0.0:
		var font := SUBTITLE_FONT
		var widest := 0.0
		for option in MONEY_OPTIONS:
			widest = maxf(widest, font.get_string_size(_money_label(option), HORIZONTAL_ALIGNMENT_LEFT, -1,
				m.option_font).x)
		var card_width := (width - float(m.item_gap) * float(columns - 1)) / float(columns)
		var bare := widest + float(m.glyph + m.card_pad * 2) + m.item_gap * 0.8 + 6.0
		with_check = card_width >= bare + float(m.glyph) * 0.8 + m.item_gap * 0.8
		if card_width < bare:
			columns = 2
	var grid := GridContainer.new()
	grid.name = "MoneyCards"
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", m.item_gap)
	grid.add_theme_constant_override("v_separation", m.item_gap)
	var group := ButtonGroup.new()
	var compact := columns < 4
	for i in MONEY_OPTIONS.size():
		var option: int = MONEY_OPTIONS[i]
		var card := _make_choice("money", option, MONEY_ACCENT, "%s\n%s" % [MONEY_TOOLTIP, MONEY_CAPTIONS[option]],
			_money_label(option), m, group)
		var stack := _content_column(card, int(3.0 * m.u))
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", int(m.item_gap * 0.8))
		var level := SetupGlyph.MONEY_UNLIMITED if option == -1 else i + 1
		card.glyph = SetupGlyph.make_pixel(SetupGlyph.Kind.MONEY, float(m.glyph) * (0.8 if compact else 1.0), level, MONEY_ACCENT)
		top.add_child(card.glyph)
		card.title = _make_option_label(_money_label(option), m.option_font - (1 if compact else 0), UIConstants.COLOR_TEXT)
		card.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(card.title)
		if with_check:
			card.check = SetupGlyph.make_pixel(SetupGlyph.Kind.CHECK, float(m.glyph) * 0.8, 1, MONEY_ACCENT)
			top.add_child(card.check)
		stack.add_child(top)
		var caption := _make_label(MONEY_CAPTIONS[option], m.caption_font, UIConstants.COLOR_TEXT_DIM)
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		stack.add_child(caption)
		_finish_choice(card, grid)
		_money_buttons.append(card.button)
	return grid

## LANDSCAPE: a four-way segmented picker with short labels.
func _make_money_segments(m: Metrics) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MoneySegments"
	row.add_theme_constant_override("separation", int(m.item_gap * 0.8))
	var group := ButtonGroup.new()
	for option in MONEY_OPTIONS:
		var card := _make_choice("money", option, MONEY_ACCENT, "%s\n%s" % [MONEY_TOOLTIP, MONEY_CAPTIONS[option]],
			_money_label(option), m, group, Vector2(0, m.segment_height), 4)
		var line := _content_row(card, 4)
		card.title = _make_option_label(_money_short_label(option), m.option_font - 3, UIConstants.COLOR_TEXT)
		line.add_child(card.title)
		_finish_choice(card, row)
		_money_buttons.append(card.button)
	return row

## The hole-count segments with their hint, plus the course plan when
## `with_plan`: TABLET puts the plan beside the picker, PHONE puts it beside
## the hint under the picker. WIDE shows the plan in the rail instead, and
## LANDSCAPE has no room for it.
func _make_holes_block(m: Metrics, with_plan: bool, width: float) -> Control:
	var block := VBoxContainer.new()
	block.name = "HolesBlock"
	block.add_theme_constant_override("separation", int(m.item_gap * 0.8))
	var row := HBoxContainer.new()
	row.name = "HoleSegments"
	row.add_theme_constant_override("separation", int(m.item_gap * 0.7))
	var group := ButtonGroup.new()
	var show_par := m.hole_height >= 52
	for count in HOLE_OPTIONS:
		var card := _make_choice("holes", count, HOLES_ACCENT, _holes_tooltip(count),
			"%d holes" % count, m, group, Vector2(0, m.hole_height), 2)
		var stack := _content_column(card, 0)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		card.title = _make_option_label(str(count), m.number_font if show_par else m.option_font, UIConstants.COLOR_TEXT)
		card.title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(card.title)
		if show_par:
			var caption := _make_label("Empty" if count == 0 else "Par %d" % GeneratedCourse.get_par_for_count(count),
				m.caption_font - 1, UIConstants.COLOR_TEXT_DIM)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stack.add_child(caption)
		_finish_choice(card, row)
		_hole_buttons.append(card.button)
	block.add_child(row)

	if not with_plan:
		_hole_hint = _make_hint(m, _hole_hint_texts(), width, 1 if _layout_mode == Layout.LANDSCAPE else 3)
		block.add_child(_hole_hint)
		return block

	var split := HBoxContainer.new()
	split.name = "PlanSplit"
	split.add_theme_constant_override("separation", m.section_gap if _layout_mode == Layout.TABLET else m.item_gap + 2)
	var words := VBoxContainer.new()
	words.name = "PlanWords"
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", int(m.item_gap * 0.6))
	_plan_caption = _make_plan_caption(m)
	words.add_child(_plan_caption)
	var gap := float(m.section_gap if _layout_mode == Layout.TABLET else m.item_gap + 2)
	_hole_hint = _make_hint(m, _hole_hint_texts(), width - m.plan_min - gap, 6)
	words.add_child(_hole_hint)
	var plan := _make_plan_frame(Vector2(m.plan_min, m.plan_min))
	if _layout_mode == Layout.TABLET:
		# Picker over the words on the left, the plan square on the right.
		block.remove_child(row)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", m.item_gap + 4)
		left.add_child(row)
		left.add_child(words)
		split.add_child(left)
		split.add_child(plan)
	else:
		split.add_child(plan)
		split.add_child(words)
	block.add_child(split)
	return block

## Feature toggles in one of four shapes:
##   card  - glyph and switch over the name and a wrapped caption (WIDE, TABLET)
##   row   - glyph, name (+ caption when it fits), switch in one line
##   stack - glyph over name over switch, for narrow phone columns
##   chip  - glyph and name only; the lit border and colours carry on/off
##           (LANDSCAPE, where the height is too short for a switch row)
func _make_feature_tiles(m: Metrics, variant: String, width: float) -> GridContainer:
	var features := _available_features()
	var grid := GridContainer.new()
	grid.name = "FeatureTiles"
	grid.columns = maxi(1, features.size())
	grid.add_theme_constant_override("h_separation", int(m.item_gap * 0.8))
	grid.add_theme_constant_override("v_separation", int(m.item_gap * 0.8))
	var font := get_theme_default_font()
	var tile_width := width - float(int(m.card_pad * 0.85)) * 2.0
	if features.size() >= 3:
		tile_width = (width - float(int(m.item_gap * 0.8)) * 2.0) / 3.0
	elif features.size() == 2:
		tile_width = (width - float(int(m.item_gap * 0.8))) / 2.0
	elif features.size() == 1:
		tile_width = width - float(int(m.card_pad * 0.85)) * 2.0
	var caption_font := m.caption_font - 1
	var captions := []
	var widest_caption := 0.0
	for feature in features:
		captions.append(str(feature[2]))
		widest_caption = maxf(widest_caption,
			font.get_string_size(str(feature[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, caption_font).x)
	# One-line rows show their captions only if all three fit.
	var row_captions := tile_width - float(m.glyph + int(m.card_pad * 0.85) * 2 + int(m.item_gap * 0.8) * 2) \
		- float(m.glyph) * 0.62 * 1.75 >= widest_caption
	for feature in features:
		var key: String = feature[0]
		var height := m.segment_height if variant == "chip" else (m.feature_height if variant != "card" else 0)
		var card := _make_choice("feature", key, FEATURE_ACCENT, str(feature[3]), str(feature[1]), m, null,
			Vector2(0, height), int(m.card_pad * (0.6 if variant == "chip" else 0.85)))
		card.glyph = SetupGlyph.make_pixel(feature[4], float(m.glyph) * (0.8 if variant == "chip" else 1.0), 1, FEATURE_ACCENT)
		card.title = _make_option_label(str(feature[1]), m.option_font - (2 if variant == "chip" or variant == "stack" else 1),
			UIConstants.COLOR_TEXT)
		if variant != "chip":
			# (A chip's name sits in a centred row: trimmed, it would shrink to
			# nothing but the ellipsis.)
			card.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			card.switch = SetupGlyph.make_pixel(SetupGlyph.Kind.SWITCH, float(m.glyph) * 0.62, 1, FEATURE_ACCENT)
		match variant:
			"card":
				var stack := _content_column(card, int(4.0 * m.u))
				var top := HBoxContainer.new()
				top.add_child(card.glyph)
				var spacer := Control.new()
				spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				top.add_child(spacer)
				top.add_child(card.switch)
				stack.add_child(top)
				stack.add_child(card.title)
				var caption := _make_label(str(feature[2]), caption_font, UIConstants.COLOR_TEXT_DIM)
				_reserve_lines(caption, captions, tile_width - float(int(m.card_pad * 0.85)) * 2.0, 3)
				stack.add_child(caption)
			"stack":
				var stack := _content_column(card, int(4.0 * m.u))
				stack.alignment = BoxContainer.ALIGNMENT_CENTER
				stack.add_child(card.glyph)
				card.title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				stack.add_child(card.title)
				stack.add_child(card.switch)
			"chip":
				var line := _content_row(card, int(m.item_gap * 0.6))
				line.add_child(card.glyph)
				line.add_child(card.title)
			_:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", int(m.item_gap * 0.8))
				card.content.add_child(line)
				line.add_child(card.glyph)
				var words := VBoxContainer.new()
				words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				words.alignment = BoxContainer.ALIGNMENT_CENTER
				words.add_theme_constant_override("separation", 0)
				words.add_child(card.title)
				if row_captions:
					words.add_child(_make_label(str(feature[2]), caption_font, UIConstants.COLOR_TEXT_DIM))
				line.add_child(words)
				line.add_child(card.switch)
		card.button.button_pressed = bool(_features.get(key, false))
		card.button.toggled.connect(_on_feature_toggled.bind(key))
		_finish_choice(card, grid)
		_feature_boxes[key] = card.button
	return grid

## The tutorial switch as a card: glyph, name and the switch. `compact` is the
## title-bar chip of the wide arrangements; otherwise it is a full-width row.
func _make_tutorial_card(m: Metrics, compact: bool) -> ChoiceCard:
	var card := _make_choice("tutorial", "tutorial", FEATURE_ACCENT, TUTORIAL_TOOLTIP, TUTORIAL_TITLE, m, null,
		Vector2(0, m.back_height) if compact else Vector2(0, m.feature_height),
		int(m.card_pad * 0.6) if compact else int(m.card_pad * 0.85))
	if compact:
		card.cell.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.glyph = SetupGlyph.make_pixel(SetupGlyph.Kind.TUTORIAL, float(m.glyph) * (0.8 if compact else 1.0), 1, FEATURE_ACCENT)
	card.switch = SetupGlyph.make_pixel(SetupGlyph.Kind.SWITCH, float(m.glyph) * 0.62, 1, FEATURE_ACCENT)
	var line := _content_row(card, int(m.item_gap * 0.6))
	line.add_child(card.glyph)
	card.title = _make_option_label(TUTORIAL_TITLE, m.option_font - (3 if compact else 2), UIConstants.COLOR_TEXT)
	# The chip sizes to its words; the full-width row may trim them if it must.
	if not compact:
		card.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(card.title)
	line.add_child(card.switch)
	card.button.toggled.connect(_on_tutorial_toggled)
	return card

## The tutorial's place on the narrow arrangements: its switch with a caption
## under it, inside the section.
func _make_tutorial_block(m: Metrics, width: float) -> Control:
	var block := VBoxContainer.new()
	block.name = "TutorialBlock"
	block.add_theme_constant_override("separation", int(m.item_gap * 0.8))
	var card := _make_tutorial_card(m, false)
	_tutorial_card = card
	_finish_choice(card, block)
	var caption := _make_label("", m.caption_font, UIConstants.COLOR_TEXT_DIM)
	caption.name = "TutorialCaption"
	_reserve_lines(caption, [TUTORIAL_CAPTION], width, 3)
	block.add_child(caption)
	return block

## The tutorial switch as it sits in the title bar on the wide arrangements.
func _make_tutorial_chip(m: Metrics, title_bar: Control) -> void:
	var card := _make_tutorial_card(m, true)
	_tutorial_card = card
	_finish_choice(card, title_bar)

## WIDE: the company rail - name, course plan, summary, Choose Location.
func _make_rail(m: Metrics) -> PanelContainer:
	var rail := PanelContainer.new()
	rail.name = "Rail"
	rail.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.68), MenuStyle.SHEET_BG,
		m.panel_pad, m.panel_pad))
	var column := VBoxContainer.new()
	column.name = "RailColumn"
	column.add_theme_constant_override("separation", int(m.item_gap * 1.1))
	rail.add_child(column)
	column.add_child(Kit.make_kicker("Your company", m.kicker_font))
	_summary_company = _make_option_label(_company_display_name(), m.option_font + 5, MenuStyle.TITLE_COLOR)
	_summary_company.name = "CompanyName"
	_summary_company.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_summary_company)
	var frame := _make_plan_frame(Vector2(0, m.plan_min))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(frame)
	_plan_caption = _make_plan_caption(m)
	column.add_child(_plan_caption)
	column.add_child(_make_rule())
	var summary_rows: Array = [["difficulty", "Difficulty"], ["money", "Budget"]]
	if _has_features():
		summary_rows.append(["features", "Features"])
	summary_rows.append(["tutorial", "Tutorial"])
	for row in summary_rows:
		column.add_child(_make_summary_row(row[0], row[1], m))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, m.item_gap * 0.5)
	column.add_child(gap)
	column.add_child(_make_cta(m))
	var note := _make_label("Next: buy a site on the world map.", m.caption_font,
		UIConstants.COLOR_TEXT_MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reserve_lines(note, [note.text], m.rail_width - float(m.panel_pad) * 2.0, 2)
	column.add_child(note)
	return rail

## TABLET / PHONE: Choose Location in a bar pinned to the bottom edge (with a
## one-line summary on tablets).
func _make_footer(m: Metrics, with_summary: bool) -> void:
	var bar := PanelContainer.new()
	bar.name = "Footer"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -m.footer_height
	bar.add_theme_stylebox_override("panel", PixelButtonStyle.bar_style(
		MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.68), Color(0.024, 0.055, 0.045, 0.94)))
	add_child(bar)
	var margin := MarginContainer.new()
	var side := int(maxf(float(m.pad), (m.view.x - m.max_width) * 0.5))
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	var vertical := int((m.footer_height - float(m.cta_height)) * 0.5)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	bar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", m.gap)
	margin.add_child(row)
	var cta := _make_cta(m)
	if with_summary:
		_footer_summary = _make_label("", m.caption_font + 1, UIConstants.COLOR_TEXT_DIM)
		_footer_summary.name = "FooterSummary"
		_footer_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_footer_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_footer_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_footer_summary.max_lines_visible = 2
		_footer_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(_footer_summary)
		cta.custom_minimum_size.x = clampf(m.view.x * 0.34, 240.0, 340.0)
	else:
		cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cta)

# =============================================================================
# BUILDING BLOCKS
# =============================================================================

## A choice card shell. Fill `card.content`, then call _finish_choice.
func _make_choice(group: String, value: Variant, accent: Color, tooltip: String, a11y_name: String,
		m: Metrics, button_group: ButtonGroup, min_size: Vector2 = Vector2.ZERO, pad: int = -1) -> ChoiceCard:
	var card := ChoiceCard.new()
	card.group = group
	card.value = value
	card.accent = accent
	card.cell = MarginContainer.new()
	card.cell.name = "%s_%s" % [group.capitalize().replace(" ", ""), str(value).replace("-", "minus")]
	card.cell.custom_minimum_size = min_size
	card.cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.button = Button.new()
	card.button.name = "Button"
	card.button.toggle_mode = true
	card.button.button_group = button_group
	card.button.focus_mode = Control.FOCUS_ALL
	card.button.tooltip_text = tooltip
	card.button.accessibility_name = a11y_name
	card.button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.button.set_meta("value", value)
	PixelButtonStyle.paint_choice(card.button, accent)
	card.cell.add_child(card.button)
	card.content = MarginContainer.new()
	card.content.name = "Content"
	var inner := m.card_pad if pad < 0 else pad
	for side in ["left", "right"]:
		card.content.add_theme_constant_override("margin_" + side, inner)
	for side in ["top", "bottom"]:
		card.content.add_theme_constant_override("margin_" + side, int(float(inner) * 0.85))
	card.cell.add_child(card.content)
	if not _is_toggle_group(group):
		card.button.pressed.connect(_on_choice_pressed.bind(card))
	return card

## Feature and tutorial cards are switches: they report their state through
## `toggled` and are drawn lit or muted, rather than picked from a group.
static func _is_toggle_group(group: String) -> bool:
	return group == "feature" or group == "tutorial"

## Mouse input goes through the drawn content to the button underneath.
func _finish_choice(card: ChoiceCard, parent: Control) -> void:
	_ignore_mouse(card.content)
	parent.add_child(card.cell)
	_choices.append(card)

func _content_column(card: ChoiceCard, separation: int) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", separation)
	card.content.add_child(stack)
	return stack

func _content_row(card: ChoiceCard, separation: int) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", separation)
	card.content.add_child(line)
	return line

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

## A button that only provides the surface (its content is drawn on top).
func _make_shell_button(button_name: String, accent: Color) -> Button:
	var button := Button.new()
	button.name = button_name
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	PixelButtonStyle.paint_choice(button, accent)
	return button

## The gold Choose Location button: label and drawn arrow over a gold fill.
func _make_cta(m: Metrics) -> MarginContainer:
	var cell := MarginContainer.new()
	cell.name = "NextCell"
	cell.custom_minimum_size = Vector2(0, m.cta_height)
	_next_button = Button.new()
	_next_button.name = "NextButton"
	_next_button.tooltip_text = NEXT_TOOLTIP
	_next_button.accessibility_name = CTA_TEXT
	_next_button.focus_mode = Control.FOCUS_ALL
	# Choosing the location is the action a keyboard/controller player needs.
	_next_button.set_meta(InputManager.DEFAULT_FOCUS_META, true)
	_next_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	PixelButtonStyle.paint_primary(_next_button, MenuStyle.ACCENT_PRIMARY)
	_next_button.pressed.connect(_on_next_pressed)
	cell.add_child(_next_button)
	var center := CenterContainer.new()
	cell.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(float(m.cta_font) * 0.45))
	center.add_child(row)
	var label := _make_label(CTA_TEXT, m.cta_font, MenuStyle.INK)
	label.add_theme_font_override("font", TITLE_FONT)
	row.add_child(label)
	row.add_child(SetupGlyph.make_pixel(SetupGlyph.Kind.ARROW, float(m.cta_font) * 1.1, 1, MenuStyle.INK))
	_ignore_mouse(center)
	return cell

## The course plan in a recessed frame.
func _make_plan_frame(min_size: Vector2) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "PlanFrame"
	frame.custom_minimum_size = min_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", PixelButtonStyle.inset_style(
		MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.62), MenuStyle.INSET_BG, 4))
	_course_plan = CoursePlanPreview.new()
	_course_plan.name = "CoursePlan"
	_course_plan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_course_plan.set_hole_count(_holes, false)
	_course_plan.tooltip_text = ""
	frame.add_child(_course_plan)
	return frame

func _make_plan_caption(m: Metrics) -> Label:
	var label := _make_option_label("", m.kicker_font + 1, MenuStyle.ACCENT_PRIMARY)
	label.name = "PlanCaption"
	label.uppercase = true
	return label

func _make_summary_row(key: String, title: String, m: Metrics) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Summary%s" % title
	row.add_theme_constant_override("separation", m.item_gap)
	row.add_child(_make_label(title, m.caption_font + 1, UIConstants.COLOR_TEXT_MUTED))
	var value := _make_label("", m.caption_font + 2, UIConstants.COLOR_TEXT)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value)
	_summary_values[key] = value
	return row

## A wrapped hint whose height fits the longest text it can show at `width`.
func _make_hint(m: Metrics, texts: Array, width: float, max_lines: int) -> Label:
	var label := _make_label("", m.caption_font, UIConstants.COLOR_TEXT_DIM)
	label.name = "Hint"
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_reserve_lines(label, texts, width, max_lines)
	return label

## Make `label` a wrapped block tall enough for the longest of `texts` at
## `width` (at most `max_lines`), so it keeps one height whichever text it
## shows and the layout's height is known before the first layout pass.
func _reserve_lines(label: Label, texts: Array, width: float, max_lines: int) -> int:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var lines := 1
	for text in texts:
		lines = maxi(lines, MenuStyle.wrapped_lines(str(text), font, font_size, width))
	lines = mini(lines, max_lines)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.custom_minimum_size.y = ceilf(MenuStyle.text_block(font, font_size, lines))
	return lines

func _hole_hint_texts() -> Array:
	var texts := []
	for count in HOLE_OPTIONS:
		texts.append(hole_hint(count) if _uses_long_hole_hint() else hole_hint_short(count))
	return texts

## Every arrangement but a short LANDSCAPE has room for the full hole hint.
func _uses_long_hole_hint() -> bool:
	return _layout_mode != Layout.LANDSCAPE or (_metrics_cache != null and _metrics_cache.landscape_plan)

func _difficulty_hint_texts(limit: int) -> Array:
	var texts := []
	for preset in DifficultyPresets.get_all_presets():
		texts.append(difficulty_effects_line(preset, limit))
	return texts

func _make_rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.45)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

func _make_option_label(text: String, font_size: int, color: Color) -> Label:
	var label := _make_label(text, font_size, color)
	label.add_theme_font_override("font", SUBTITLE_FONT)
	return label

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# =============================================================================
# SELECTION
# =============================================================================

func _on_choice_pressed(card: ChoiceCard) -> void:
	match card.group:
		"difficulty":
			_select_difficulty(int(card.value))
		"money":
			_select_money(int(card.value))
		"holes":
			_select_holes(int(card.value))

func _select_difficulty(preset: int) -> void:
	_difficulty = preset
	_update_selection_styles()

func _select_money(option: int) -> void:
	_money = option
	_update_selection_styles()

func _select_holes(count: int) -> void:
	_holes = count
	if _course_plan:
		_course_plan.set_hole_count(count)
	_update_selection_styles()

func _on_feature_toggled(enabled: bool, key: String) -> void:
	_features[key] = enabled
	_update_selection_styles()

func _on_tutorial_toggled(enabled: bool) -> void:
	_tutorial_enabled = enabled
	_update_selection_styles()

func _on_company_name_changed(text: String) -> void:
	_company_name = text
	_refresh_summary()

func _on_random_name_pressed() -> void:
	if _company_input:
		_company_input.text = WorldLocations.random_company_name()
		_company_name = _company_input.text
	_refresh_summary()

## Bring every card in line with the current choices, then the summaries.
func _update_selection_styles() -> void:
	for card: ChoiceCard in _choices:
		var selected := _is_selected(card)
		card.button.set_pressed_no_signal(selected)
		if card.title:
			var lit := card.accent.lerp(Color.WHITE, 0.45)
			if _is_toggle_group(card.group):
				card.title.add_theme_color_override("font_color",
					UIConstants.COLOR_TEXT if selected else UIConstants.COLOR_TEXT_MUTED)
			else:
				card.title.add_theme_color_override("font_color", lit if selected else UIConstants.COLOR_TEXT)
		if card.check:
			card.check.modulate.a = 1.0 if selected else 0.0
		if card.switch:
			card.switch.on = selected
		if card.glyph and _is_toggle_group(card.group):
			card.glyph.on = selected
	_sync_tutorial_availability()
	_refresh_summary()

## The tutorial only starts on an empty course. With holes generated its switch
## keeps the company's choice but cannot be changed, and is drawn faded.
func _sync_tutorial_availability() -> void:
	if _tutorial_card == null:
		return
	var applies := tutorial_applies(_holes)
	_tutorial_card.button.disabled = not applies
	_tutorial_card.cell.modulate.a = 1.0 if applies else 0.5

func _is_selected(card: ChoiceCard) -> bool:
	match card.group:
		"difficulty":
			return int(card.value) == _difficulty
		"money":
			return int(card.value) == _money
		"holes":
			return int(card.value) == _holes
		"feature":
			return bool(_features.get(str(card.value), false))
		"tutorial":
			return _tutorial_enabled
	return false

func _refresh_summary() -> void:
	var difficulty_name := str(DifficultyPresets.get_modifiers(_difficulty).get("name", ""))
	if _summary_company:
		_summary_company.text = _company_display_name()
	if _summary_values.has("difficulty"):
		_summary_values["difficulty"].text = difficulty_name
	if _summary_values.has("money"):
		_summary_values["money"].text = _money_label(_money)
	if _summary_values.has("features"):
		_summary_values["features"].text = features_summary(_features)
	if _summary_values.has("tutorial"):
		_summary_values["tutorial"].text = tutorial_summary(_tutorial_enabled, _holes)
	if _plan_caption:
		_plan_caption.text = plan_caption(_holes)
	if _hole_hint:
		_hole_hint.text = hole_hint(_holes) if _uses_long_hole_hint() else hole_hint_short(_holes)
	if _difficulty_hint:
		# Phones have no tooltips, so the hint spells out every effect.
		_difficulty_hint.text = difficulty_effects_line(_difficulty, 2 if _layout_mode == Layout.LANDSCAPE else 4)
	if _footer_summary:
		_footer_summary.text = footer_summary(difficulty_name, _money, _holes, _features)

func _company_display_name() -> String:
	var text := _company_input.text if _company_input else _company_name
	text = text.strip_edges()
	return text if not text.is_empty() else NAME_PLACEHOLDER

# =============================================================================
# OPTIONS
# =============================================================================

func get_options() -> Dictionary:
	var company := _company_input.text.strip_edges() if _company_input else _company_name.strip_edges()
	if company.is_empty():
		company = WorldLocations.random_company_name()
	var features: Dictionary = {}
	for feature in _available_features():
		var key: String = feature[0]
		features[key] = bool(_features.get(key, false))
	# Keep a choice already made for a feature that is not offered right now
	# (its mod was switched off while this screen was open) rather than
	# silently dropping it.
	for key in _features:
		if not features.has(key):
			features[key] = bool(_features[key])
	return {
		"company_name": company,
		"difficulty": _difficulty,
		"starting_money": _money,
		"generated_holes": _holes,
		"features": features,
		"tutorial": _tutorial_enabled,
	}

func _on_next_pressed() -> void:
	next_requested.emit(get_options())

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

# =============================================================================
# COPY (pure, unit-tested)
# =============================================================================

static func _money_label(option: int) -> String:
	if option == -1:
		return "Unlimited"
	return "$%s" % _group_digits(option)

## "$100K" - for pickers too narrow for the full amount.
static func _money_short_label(option: int) -> String:
	if option == -1:
		return "Unlimited"
	if option >= 1000 and option % 1000 == 0:
		return "$%dK" % int(option / 1000.0)
	return _money_label(option)

static func _holes_tooltip(count: int) -> String:
	if count == 0:
		return "Start with an empty plot and build every hole yourself."
	return "%d holes are generated on the first location you buy (Par %d). Additional locations start empty." % [
		count, GeneratedCourse.get_par_for_count(count)]

static func _group_digits(amount: int) -> String:
	var s := str(absi(amount))
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

## The line under the hole picker.
static func hole_hint(count: int) -> String:
	if count == 0:
		return "Build every hole yourself. The tutorial can guide you through the first one."
	return "%d holes (%d par) are laid out on the first location you buy. Later sites start empty so you build them yourself." % [
		count, GeneratedCourse.get_par_for_count(count)]

## The one-line form of hole_hint, for the landscape picker.
static func hole_hint_short(count: int) -> String:
	if count == 0:
		return "An empty plot: you build every hole."
	return "%d holes (par %d) on the first site you buy." % [count, GeneratedCourse.get_par_for_count(count)]

## The tutorial only runs on an empty first course, so it applies only when no
## holes are generated.
static func tutorial_applies(holes: int) -> bool:
	return holes == 0

## The rail's line for the tutorial: "On", "Off", or "Not used" when the
## course has generated holes (whatever the switch says).
static func tutorial_summary(enabled: bool, holes: int) -> String:
	if not tutorial_applies(holes):
		return "Not used"
	return "On" if enabled else "Off"

## The caption under the course plan: "9 holes · par 36" / "Empty plot".
static func plan_caption(count: int) -> String:
	if count == 0:
		return "Empty plot · build every hole"
	return "%d holes · par %d" % [count, GeneratedCourse.get_par_for_count(count)]

## A difficulty's headline effects against Normal: "Upkeep −20%". Normal has
## none - it is the baseline.
static func difficulty_effects(preset: int) -> Array[String]:
	var mods := DifficultyPresets.get_modifiers(preset)
	var effects: Array[String] = []
	for entry in [["Upkeep", "maintenance_multiplier"], ["Golfers", "spawn_rate_multiplier"],
			["Building costs", "building_cost_multiplier"], ["Reputation decay", "reputation_decay_multiplier"]]:
		var delta := roundi((float(mods.get(entry[1], 1.0)) - 1.0) * 100.0)
		if delta != 0:
			effects.append("%s %s%d%%" % [entry[0], "+" if delta > 0 else "−", absi(delta)])
	return effects

## Up to `limit` effects on one line, or the baseline note for Normal.
static func difficulty_effects_line(preset: int, limit: int = 2) -> String:
	var effects := difficulty_effects(preset)
	if effects.is_empty():
		return "Standard costs and demand" if limit <= 2 else "Standard costs, demand and reputation decay"
	return " · ".join(effects.slice(0, limit))

static func difficulty_tooltip(preset: int) -> String:
	var mods := DifficultyPresets.get_modifiers(preset)
	var lines: Array[String] = [str(mods.get("description", ""))]
	var effects := difficulty_effects(preset)
	if not effects.is_empty():
		lines.append(", ".join(effects))
	var threshold := int(mods.get("bankruptcy_threshold", 0))
	lines.append("Bankruptcy below %s$%s" % ["−" if threshold < 0 else "", _group_digits(threshold)])
	return "\n".join(lines)

## "Weather · Wind · Seasons", "Wind", or "None" - named the way the mod that
## registered each feature spells it.
static func features_summary(features: Dictionary, separator: String = " · ") -> String:
	var names: Array[String] = []
	for key in features:
		if bool(features[key]):
			names.append(feature_title(str(key)))
	return "None" if names.is_empty() else separator.join(names)

## The tablet footer's one-line recap of every choice.
static func footer_summary(difficulty_name: String, money: int, holes: int, features: Dictionary) -> String:
	var course := "Empty plot" if holes == 0 else "%d holes (par %d)" % [holes, GeneratedCourse.get_par_for_count(holes)]
	var enabled := features_summary(features, ", ")
	return "%s  ·  %s  ·  %s  ·  %s" % [difficulty_name, _money_label(money), course,
		"No features" if enabled == "None" else enabled]
