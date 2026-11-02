extends Control
class_name StartTournamentScreen
## StartTournamentScreen — Standalone Tournament Mode setup screen opened from
## the Main Menu.
##
## Lets the player configure:
##   1. Difficulty Level (selects the opposing golfer roster, with progressively
##      higher Golf Skills at each tier — independent of format, rounds, or mods)
##   2. Tournament Format Type (Stroke Play, Stableford, Modified Stableford, Skins)
##      and Format Rules (Rounds, Field Size, Cut Line, Sudden-Death Playoff)
##   3. Game Features from enabled community mods (Weather, Wind, Seasons, plus
##      any mod calling ModAPI.register_feature / register_feature_option)
##   4. Course (4 built-in Default Courses + Career-saved courses)
##   5. Golfer (4 built-in Default Golfers + Career-saved golfers, displaying
##      complete identity, Skin & Skin Colours, Golfer Traits, Golfer Skills,
##      and all 10 Golf Skills)

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

signal start_requested(options: Dictionary)
signal back_requested()

enum Layout { WIDE, TABLET, LANDSCAPE, PHONE }

const WIDE_MIN_WIDTH := 1020
const WIDE_MIN_HEIGHT := 600
const TABLET_MIN_WIDTH := 700
const TABLET_MIN_HEIGHT := 760
const LANDSCAPE_MIN_WIDTH := 600
const REPROPORTION_STEP := 0.12
const SETTLE_DELAY := 0.2

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

const COURSE_ACCENT := Color("8fc79b")
const GOLFER_ACCENT := Color("7fb8d8")
const FORMAT_ACCENT := Color("d9b468")
const FEATURE_ACCENT := Color("7ac7b8")
const CAREER_BADGE_COLOR := Color("e5c57c")
const DEFAULT_BADGE_COLOR := Color("8fa99a")

## Built-in presentation metadata for the three shipped feature mods; custom
## community mods fall back to the title/description they registered with ModAPI.
const BUILTIN_FEATURES: Dictionary = {
	"weather": {
		"title": "Weather",
		"subtitle": "Sun, clouds and rain shift roll and carry.",
		"accent": Color("6fb5e0"),
	},
	"wind": {
		"title": "Wind",
		"subtitle": "Breezes push shots off line and change club choice.",
		"accent": Color("7ed0c0"),
	},
	"seasons": {
		"title": "Seasons",
		"subtitle": "Spring through winter turf and seasonal course conditions.",
		"accent": Color("d9a55b"),
	},
}

## Crisp pixel golfer emblem showing cap, hair, face, shirt, and trousers in the
## golfer's own Skin Colours palette.
class GolferSwatch extends Control:
	var cap_color: Color = Color("f2f0e6")
	var hair_color: Color = Color("5c3a21")
	var skin_color: Color = Color("edc4a3")
	var shirt_color: Color = Color("2e7057")
	var pants_color: Color = Color("e0dbcc")

	func _init(entry: Dictionary = {}) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(28, 30)
		if not entry.is_empty():
			set_from_entry(entry)

	func set_from_entry(entry: Dictionary) -> void:
		cap_color = entry.get("cap_color", cap_color)
		hair_color = entry.get("hair_color", hair_color)
		skin_color = entry.get("skin_color", skin_color)
		shirt_color = entry.get("shirt_color", shirt_color)
		pants_color = entry.get("pants_color", pants_color)
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x / 13.0, size.y / 14.0)
		var ox := floorf((size.x - 13.0 * s) * 0.5)
		var oy := floorf((size.y - 14.0 * s) * 0.5)
		draw_rect(Rect2(ox, oy, 13.0 * s, 14.0 * s), Color(0.02, 0.05, 0.04, 0.80))
		# Cap crown + visor
		draw_rect(Rect2(ox + 3.0 * s, oy + 1.0 * s, 6.0 * s, 2.0 * s), cap_color)
		draw_rect(Rect2(ox + 3.0 * s, oy + 2.0 * s, 8.0 * s, 1.0 * s), cap_color.darkened(0.18))
		# Hair fringe + head
		draw_rect(Rect2(ox + 3.0 * s, oy + 3.0 * s, 1.5 * s, 2.5 * s), hair_color)
		draw_rect(Rect2(ox + 4.0 * s, oy + 3.0 * s, 5.0 * s, 3.0 * s), skin_color)
		# Shirt torso + collar
		draw_rect(Rect2(ox + 2.0 * s, oy + 6.0 * s, 9.0 * s, 5.0 * s), shirt_color)
		draw_rect(Rect2(ox + 5.0 * s, oy + 6.0 * s, 3.0 * s, 1.5 * s), cap_color.lightened(0.15))
		# Trousers
		draw_rect(Rect2(ox + 3.0 * s, oy + 11.0 * s, 3.0 * s, 2.5 * s), pants_color)
		draw_rect(Rect2(ox + 7.0 * s, oy + 11.0 * s, 3.0 * s, 2.5 * s), pants_color)

# ── Selection State ─────────────────────────────────────────────────────────
var _difficulty: int = TournamentLibrary.Difficulty.NORMAL
var _format_type: int = TournamentLibrary.FormatType.STROKE_PLAY
var _rounds: int = 2
var _field_size: int = 12
var _cut_rule: String = "top_50pct"
var _playoff_enabled: bool = true
var _features: Dictionary = {} # feature_id -> bool
var _available_features: Array[Dictionary] = []

var _course_id: String = "default:emerald_pines"
var _golfer_id: String = "default:claire_vance"

var _courses: Array[Dictionary] = []
var _golfers: Array[Dictionary] = []

# ── Live UI Nodes ───────────────────────────────────────────────────────────
var _layout_mode: int = Layout.WIDE
var _built_size: Vector2 = Vector2.ZERO
var _resize_serial: int = 0

var _back_button: Button = null
var _start_button: Button = null
var _difficulty_buttons: Dictionary = {} # diff_id -> Button
var _format_buttons: Dictionary = {}     # format_id -> Button
var _round_buttons: Dictionary = {}      # rounds -> Button
var _field_size_buttons: Dictionary = {} # field_size -> Button
var _cut_buttons: Dictionary = {}        # cut_id -> Button
var _playoff_button: Button = null
var _feature_buttons: Dictionary = {}    # feature_id -> Button
var _course_buttons: Dictionary = {}     # course_id -> Button
var _golfer_buttons: Dictionary = {}     # golfer_id -> Button

var _difficulty_desc_label: Label = null
var _difficulty_roster_label: Label = null
var _format_desc_label: Label = null
var _course_preview: TournamentCoursePreview = null
var _preview_title_label: Label = null
var _preview_meta_label: Label = null

var _golfer_summary_swatch: GolferSwatch = null
var _golfer_summary_name: Label = null
var _golfer_summary_role: Label = null
var _golfer_identity_label: Label = null
var _golfer_skin_label: Label = null
var _skin_color_chips: Dictionary = {}   # group_name -> ColorRect
var _trait_badges: Dictionary = {}       # trait_key -> Label
var _gskill_badges: Dictionary = {}      # skill_key -> Label
var _golf_skill_rows: Dictionary = {}    # int(GolfSkill) -> [PixelBar, Label]
var _dossier_diff_label: Label = null
var _footer_summary_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "StartTournamentScreen"
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_reload_catalogues()
	_build()
	if has_node("/root/InputManager"):
		InputManager.register_scope(self)

func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)

## Pre-populate selections (e.g. when returning from Tournament Setup) and rebuild.
func configure(initial_options: Dictionary = {}) -> void:
	if initial_options.has("difficulty"):
		_difficulty = clampi(int(initial_options["difficulty"]), 0, 3)
	if initial_options.has("format_type"):
		_format_type = clampi(int(initial_options["format_type"]), 0, 3)
	if initial_options.has("rounds"):
		_rounds = clampi(int(initial_options["rounds"]), 1, 4)
	if initial_options.has("field_size"):
		_field_size = clampi(int(initial_options["field_size"]), 2, 72)
	if initial_options.has("cut_rule"):
		_cut_rule = str(initial_options["cut_rule"])
	if initial_options.has("playoff"):
		_playoff_enabled = bool(initial_options["playoff"])
	if initial_options.get("features") is Dictionary:
		var incoming_features: Dictionary = initial_options["features"]
		for f_key in incoming_features:
			_features[str(f_key)] = bool(incoming_features[f_key])
	if initial_options.has("course_id"):
		_course_id = str(initial_options["course_id"])
	if initial_options.has("golfer_id"):
		_golfer_id = str(initial_options["golfer_id"])
	_reload_catalogues()
	if is_inside_tree():
		_build()

func refresh() -> void:
	_reload_catalogues()
	if is_inside_tree():
		_build()

func get_options() -> Dictionary:
	var diff := TournamentLibrary.get_difficulty(_difficulty)
	var fmt := TournamentLibrary.get_format_info(_format_type)
	var course := _selected_course()
	var golfer := _selected_golfer()
	var effective_cut := "none" if _rounds <= 1 else _cut_rule
	var active_features: Dictionary = {}
	for opt in _available_features:
		var fid := str(opt.get("id", ""))
		if not fid.is_empty():
			active_features[fid] = bool(_features.get(fid, opt.get("default", true)))
	return {
		"difficulty": _difficulty,
		"difficulty_name": str(diff.get("name", "Normal")),
		"difficulty_label": TournamentLibrary.get_difficulty_label(_difficulty),
		"opponent_avg_skill_pct": float(diff.get("avg_golf_skill_pct", 50.0)),
		"tier": int(diff.get("tier", TournamentSystem.TournamentTier.REGIONAL)),
		"format_type": _format_type,
		"format_name": str(fmt.get("name", "Stroke Play")),
		"rounds": _rounds,
		"field_size": _field_size,
		"cut_rule": effective_cut,
		"playoff": _playoff_enabled,
		"features": active_features,
		"course_id": str(course.get("id", "default:emerald_pines")),
		"course_name": str(course.get("name", "Emerald Pines")),
		"course_is_default": bool(course.get("is_default", true)),
		"golfer_id": str(golfer.get("id", "default:claire_vance")),
		"golfer_name": str(golfer.get("name", "Claire Vance")),
		"golfer_skin_id": str(golfer.get("skin_id", "casual")),
		"golfer_skin_colors": (golfer.get("skin_colors", {}) as Dictionary).duplicate(true),
	}

func has_feature_section() -> bool:
	return not _available_features.is_empty()

func get_feature_ids() -> Array[String]:
	var ids: Array[String] = []
	for opt in _available_features:
		var fid := str(opt.get("id", ""))
		if not fid.is_empty():
			ids.append(fid)
	return ids

func select_difficulty(diff_id: int) -> void:
	_difficulty = clampi(diff_id, 0, 3)
	_sync_selection_states()

func select_format_type(format_id: int) -> void:
	_format_type = clampi(format_id, 0, 3)
	_sync_selection_states()

func select_rounds(round_count: int) -> void:
	_rounds = clampi(round_count, 1, 4)
	_sync_selection_states()

func select_field_size(fsize: int) -> void:
	_field_size = clampi(fsize, 2, 72)
	_sync_selection_states()

func select_cut_rule(rule_id: String) -> void:
	if rule_id in ["none", "top_50pct", "top_10_ties"]:
		_cut_rule = rule_id
		_sync_selection_states()

func set_playoff_enabled(enabled: bool) -> void:
	_playoff_enabled = enabled
	_sync_selection_states()

func set_feature_enabled(feature_id: String, enabled: bool) -> void:
	if _features.has(feature_id):
		_features[feature_id] = enabled
		_sync_selection_states()

func select_course(course_id: String) -> void:
	for entry in _courses:
		if str(entry.get("id", "")) == course_id:
			_course_id = course_id
			_sync_selection_states()
			return

func select_golfer(golfer_id: String) -> void:
	for entry in _golfers:
		if str(entry.get("id", "")) == golfer_id:
			_golfer_id = golfer_id
			_sync_selection_states()
			return

static func layout_mode_for(window_size: Vector2) -> int:
	if window_size.x >= WIDE_MIN_WIDTH and window_size.y >= WIDE_MIN_HEIGHT and window_size.x > window_size.y:
		return Layout.WIDE
	if window_size.x >= TABLET_MIN_WIDTH and window_size.y >= TABLET_MIN_HEIGHT:
		return Layout.TABLET
	if window_size.x > window_size.y and window_size.x >= LANDSCAPE_MIN_WIDTH:
		return Layout.LANDSCAPE
	return Layout.PHONE

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

func _on_screen_changed(new_size: Vector2, _world_scale: float) -> void:
	if layout_mode_for(new_size) != _layout_mode:
		_build()
		return
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

func _reload_catalogues() -> void:
	_courses = TournamentLibrary.list_courses()
	_golfers = TournamentLibrary.list_golfers()
	var found_course := false
	for c in _courses:
		if str(c.get("id", "")) == _course_id:
			found_course = true
			break
	if not found_course and not _courses.is_empty():
		_course_id = str(_courses[0]["id"])

	var found_golfer := false
	for g in _golfers:
		if str(g.get("id", "")) == _golfer_id:
			found_golfer = true
			break
	if not found_golfer and not _golfers.is_empty():
		_golfer_id = str(_golfers[0]["id"])

	_available_features.clear()
	if ModManager != null:
		for raw_opt in ModManager.get_feature_options():
			if raw_opt is Dictionary:
				var opt_dict: Dictionary = (raw_opt as Dictionary).duplicate(true)
				var fid := str(opt_dict.get("id", "")).strip_edges()
				if fid.is_empty():
					continue
				_available_features.append(opt_dict)
				if not _features.has(fid):
					_features[fid] = bool(opt_dict.get("default", true))

func _selected_course() -> Dictionary:
	for c in _courses:
		if str(c.get("id", "")) == _course_id:
			return c
	return _courses[0] if not _courses.is_empty() else {}

func _selected_golfer() -> Dictionary:
	for g in _golfers:
		if str(g.get("id", "")) == _golfer_id:
			return g
	return _golfers[0] if not _golfers.is_empty() else {}

# ── UI Construction ─────────────────────────────────────────────────────────

func _clear_refs() -> void:
	_back_button = null
	_start_button = null
	_difficulty_buttons.clear()
	_format_buttons.clear()
	_round_buttons.clear()
	_field_size_buttons.clear()
	_cut_buttons.clear()
	_playoff_button = null
	_feature_buttons.clear()
	_course_buttons.clear()
	_golfer_buttons.clear()
	_difficulty_desc_label = null
	_difficulty_roster_label = null
	_format_desc_label = null
	_course_preview = null
	_preview_title_label = null
	_preview_meta_label = null
	_golfer_summary_swatch = null
	_golfer_summary_name = null
	_golfer_summary_role = null
	_golfer_identity_label = null
	_golfer_skin_label = null
	_skin_color_chips.clear()
	_trait_badges.clear()
	_gskill_badges.clear()
	_golf_skill_rows.clear()
	_dossier_diff_label = null
	_footer_summary_label = null

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_clear_refs()

	_built_size = _window_size()
	_layout_mode = layout_mode_for(_built_size)

	add_child(MenuBackdrop.new())

	match _layout_mode:
		Layout.WIDE:
			_build_wide()
		Layout.LANDSCAPE:
			_build_landscape()
		Layout.TABLET:
			_build_stacked(true)
		Layout.PHONE:
			_build_stacked(false)

	_sync_selection_states()

func _build_wide() -> void:
	var s := clampf(minf(_built_size.x / 1280.0, _built_size.y / 780.0), 0.78, 1.25)
	var pad_x := roundi(26.0 * s)
	var pad_y := roundi(16.0 * s)
	var gap := roundi(14.0 * s)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", pad_x)
	margin.add_theme_constant_override("margin_right", pad_x)
	margin.add_theme_constant_override("margin_top", pad_y)
	margin.add_theme_constant_override("margin_bottom", pad_y)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", gap)
	margin.add_child(outer)

	outer.add_child(_make_header(s, false))

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", gap)
	outer.add_child(body)

	# Left setup sheet (scrollable so Difficulty + Format/Rules + Mod Features + Course/Golfer never clip)
	var sheet := PanelContainer.new()
	sheet.name = "SetupSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.size_flags_stretch_ratio = 1.85
	sheet.add_theme_stylebox_override(
		"panel",
		MenuStyle.panel(MenuStyle.SHEET_BG, MenuStyle.with_alpha(MenuStyle.ACCENT_SECONDARY, 0.36),
			MenuStyle.CARD_RADIUS, roundi(16.0 * s), roundi(14.0 * s))
	)
	body.add_child(sheet)

	var sheet_scroll := ScrollContainer.new()
	sheet_scroll.name = "SetupSheetScroll"
	sheet_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_scroll.follow_focus = true
	sheet.add_child(sheet_scroll)

	var sheet_col := VBoxContainer.new()
	sheet_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_col.add_theme_constant_override("separation", roundi(12.0 * s))
	sheet_scroll.add_child(sheet_col)

	sheet_col.add_child(_make_difficulty_section(s, 4, false))
	sheet_col.add_child(_make_hairline())
	sheet_col.add_child(_make_format_section(s, 4, false))

	if not _available_features.is_empty():
		sheet_col.add_child(_make_hairline())
		sheet_col.add_child(_make_features_section(s, mini(3, maxi(1, _available_features.size())), false))

	sheet_col.add_child(_make_hairline())

	var pickers := HBoxContainer.new()
	pickers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pickers.add_theme_constant_override("separation", roundi(14.0 * s))
	sheet_col.add_child(pickers)

	pickers.add_child(_make_course_section(s, false, false))
	pickers.add_child(_make_golfer_section(s, false, false))

	if TournamentLibrary.saved_course_count() == 0 and TournamentLibrary.saved_golfer_count() == 0:
		var tip := _make_label(
			"Tip: Save your custom courses and golfers in Career Mode (Golfers -> Play Course / Edit Player) to compete with them here.",
			BODY_FONT, maxi(11, roundi(12.0 * s)), UIConstants.COLOR_TEXT_MUTED
		)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sheet_col.add_child(tip)

	# Right dossier rail: Course map preview + full Golfer Dossier + Start CTA
	body.add_child(_make_dossier_rail(s))

func _build_landscape() -> void:
	# Compact rotated-phone / short landscape layout (e.g. 844x390)
	var s := clampf(minf(_built_size.x / 844.0, _built_size.y / 420.0), 0.78, 1.05)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	outer.add_child(_make_header(s, true))

	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 8)
	outer.add_child(cols)

	var rules_col := VBoxContainer.new()
	rules_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_col.add_theme_constant_override("separation", 8)
	rules_col.add_child(_make_difficulty_section(s, 2, true))
	rules_col.add_child(_make_hairline())
	rules_col.add_child(_make_format_section(s, 2, true))
	if not _available_features.is_empty():
		rules_col.add_child(_make_hairline())
		rules_col.add_child(_make_features_section(s, 1, true))

	var rules_scroll := ScrollContainer.new()
	rules_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rules_scroll.follow_focus = true
	rules_scroll.add_child(rules_col)

	var diff_panel := _wrap_compact_card(rules_scroll)
	diff_panel.size_flags_stretch_ratio = 1.08
	cols.add_child(diff_panel)

	var course_panel := _wrap_compact_card(_make_course_section(s, true, true))
	course_panel.size_flags_stretch_ratio = 1.05
	cols.add_child(course_panel)

	var golfer_panel := _wrap_compact_card(_make_golfer_section(s, true, true))
	golfer_panel.size_flags_stretch_ratio = 1.08
	cols.add_child(golfer_panel)

func _build_stacked(is_tablet: bool) -> void:
	# Portrait tablet or portrait phone: clean scrolling column + pinned CTA footer
	var s := 0.96 if is_tablet else 0.88
	var pad := 20 if is_tablet else 12

	var root_col := VBoxContainer.new()
	root_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_col.add_theme_constant_override("separation", 0)
	add_child(root_col)

	var top_pad := MarginContainer.new()
	top_pad.add_theme_constant_override("margin_left", pad)
	top_pad.add_theme_constant_override("margin_right", pad)
	top_pad.add_theme_constant_override("margin_top", 12)
	top_pad.add_theme_constant_override("margin_bottom", 8)
	root_col.add_child(top_pad)
	top_pad.add_child(_make_header(s, false))

	var scroll := ScrollContainer.new()
	scroll.name = "SetupScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root_col.add_child(scroll)

	var scroll_pad := MarginContainer.new()
	scroll_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_pad.add_theme_constant_override("margin_left", pad)
	scroll_pad.add_theme_constant_override("margin_right", pad)
	scroll_pad.add_theme_constant_override("margin_top", 4)
	scroll_pad.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(scroll_pad)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll_pad.add_child(content)

	content.add_child(_wrap_sheet_card(_make_difficulty_section(s, 2, false), s))
	content.add_child(_wrap_sheet_card(_make_format_section(s, 2, false), s))
	if not _available_features.is_empty():
		content.add_child(_wrap_sheet_card(_make_features_section(s, 2 if is_tablet else 1, false), s))
	content.add_child(_wrap_sheet_card(_make_course_section(s, false, false), s))
	content.add_child(_make_inline_preview_card(s))
	content.add_child(_wrap_sheet_card(_make_golfer_section(s, false, false), s))
	content.add_child(_wrap_sheet_card(_make_golfer_dossier_content(s), s))

	# Pinned footer with summary + Start Tournament button
	var footer := PanelContainer.new()
	footer.name = "PinnedFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_stylebox_override(
		"panel",
		MenuStyle.panel(MenuStyle.SHEET_BG, MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.45),
			0, pad, 10)
	)
	root_col.add_child(footer)

	var footer_col := VBoxContainer.new()
	footer_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_col.add_theme_constant_override("separation", 6)
	footer.add_child(footer_col)

	_footer_summary_label = _make_label("", BODY_FONT, 12, UIConstants.COLOR_TEXT_DIM)
	_footer_summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer_col.add_child(_footer_summary_label)

	_start_button = _make_start_button(48.0, 18)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_col.add_child(_start_button)

# ── Section Builders ────────────────────────────────────────────────────────

func _make_header(s: float, include_cta: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "HeaderBar"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", roundi(12.0 * s))

	var kit_mode := Kit.LayoutMode.DESKTOP
	if include_cta:
		kit_mode = Kit.LayoutMode.PHONE_LANDSCAPE
	elif _layout_mode == Layout.PHONE:
		kit_mode = Kit.LayoutMode.PHONE_PORTRAIT
	_back_button = Kit.make_back_button(kit_mode, func() -> void: back_requested.emit())
	_back_button.tooltip_text = "Return to the Main Menu (Esc)"
	row.add_child(_back_button)

	var trophy := Kit.make_sprite(
		PixelIcon.Kind.TROPHY,
		22 if (include_cta or _layout_mode == Layout.PHONE) else maxi(26, roundi(30.0 * s)),
		MenuStyle.ACCENT_PRIMARY
	)
	row.add_child(trophy)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_theme_constant_override("separation", 1)
	row.add_child(title_box)

	var title_lbl := _make_label(
		"Start Tournament",
		TITLE_FONT,
		18 if (include_cta or _layout_mode == Layout.PHONE) else maxi(22, roundi(28.0 * s)),
		MenuStyle.TITLE_COLOR
	)
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(title_lbl)

	if not include_cta and _layout_mode != Layout.PHONE:
		var sub_lbl := _make_label(
			"Configure your opponent roster, tournament format, rules, course, and golfer.",
			BODY_FONT,
			maxi(12, roundi(13.0 * s)),
			UIConstants.COLOR_TEXT_DIM
		)
		sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_box.add_child(sub_lbl)

	if include_cta:
		_start_button = _make_start_button(40.0, 15)
		_start_button.custom_minimum_size.x = 168.0
		row.add_child(_start_button)

	return row

func _make_difficulty_section(s: float, columns: int, compact: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "DifficultySection"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6 if compact else roundi(8.0 * s))

	box.add_child(_make_kicker("DIFFICULTY LEVEL (OPPONENT ROSTER)", s))

	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6 if compact else roundi(8.0 * s))
	grid.add_theme_constant_override("v_separation", 6 if compact else roundi(8.0 * s))
	box.add_child(grid)

	var min_h := 40.0 if compact else maxf(52.0, roundf(58.0 * s))
	for diff in TournamentLibrary.get_difficulties():
		var diff_id := int(diff["id"])
		var accent: Color = diff["accent"]
		var btn := Button.new()
		btn.name = "Difficulty_%s" % str(diff["key"])
		btn.toggle_mode = true
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(64.0, min_h)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = str(diff["description"])
		btn.add_theme_font_override("font", SUBTITLE_FONT)
		MenuStyle.paint_choice(btn, accent)
		btn.toggled.connect(_on_difficulty_toggled.bind(diff_id))

		var inner := MarginContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("margin_left", 8)
		inner.add_theme_constant_override("margin_right", 8)
		inner.add_theme_constant_override("margin_top", 4)
		inner.add_theme_constant_override("margin_bottom", 4)
		btn.add_child(inner)

		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 1)
		inner.add_child(v)

		var name_lbl := _make_label(
			str(diff["name"]),
			SUBTITLE_FONT,
			12 if compact else maxi(13, roundi(15.0 * s)),
			UIConstants.COLOR_TEXT
		)
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(name_lbl)

		var meta_lbl := _make_label(
			"%.0f%% Skill" % float(diff.get("avg_golf_skill_pct", 50.0)) if compact else str(diff["badge"]),
			BODY_FONT,
			10 if compact else maxi(10, roundi(11.0 * s)),
			accent.lightened(0.18)
		)
		meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(meta_lbl)

		grid.add_child(btn)
		_difficulty_buttons[diff_id] = btn

	if not compact:
		_difficulty_desc_label = _make_label("", BODY_FONT, maxi(11, roundi(12.0 * s)), UIConstants.COLOR_TEXT_DIM)
		_difficulty_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(_difficulty_desc_label)

		_difficulty_roster_label = _make_label("", BODY_FONT, maxi(10, roundi(11.0 * s)), UIConstants.COLOR_TEXT_MUTED)
		_difficulty_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(_difficulty_roster_label)

	return box

func _make_format_section(s: float, columns: int, compact: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "FormatSection"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6 if compact else roundi(8.0 * s))

	box.add_child(_make_kicker("TOURNAMENT FORMAT & RULES", s))

	var fmt_grid := GridContainer.new()
	fmt_grid.columns = columns
	fmt_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fmt_grid.add_theme_constant_override("h_separation", 6 if compact else roundi(8.0 * s))
	fmt_grid.add_theme_constant_override("v_separation", 6 if compact else roundi(8.0 * s))
	box.add_child(fmt_grid)

	var fmt_h := 36.0 if compact else maxf(46.0, roundf(50.0 * s))
	for fmt in TournamentLibrary.get_format_types():
		var fid := int(fmt["id"])
		var btn := Button.new()
		btn.name = "Format_%s" % str(fmt["key"])
		btn.toggle_mode = true
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(64.0, fmt_h)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = str(fmt["description"])
		btn.add_theme_font_override("font", SUBTITLE_FONT)
		MenuStyle.paint_choice(btn, FORMAT_ACCENT)
		btn.toggled.connect(_on_format_toggled.bind(fid))

		var inner := MarginContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("margin_left", 8)
		inner.add_theme_constant_override("margin_right", 8)
		inner.add_theme_constant_override("margin_top", 4)
		inner.add_theme_constant_override("margin_bottom", 4)
		btn.add_child(inner)

		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 1)
		inner.add_child(v)

		var n_lbl := _make_label(
			str(fmt["short_name"] if compact else fmt["name"]),
			SUBTITLE_FONT,
			11 if compact else maxi(12, roundi(14.0 * s)),
			UIConstants.COLOR_TEXT
		)
		n_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(n_lbl)

		if not compact:
			var sub := _make_label(
				str(fmt.get("unit_label", "Score")),
				BODY_FONT,
				10,
				FORMAT_ACCENT.lightened(0.18)
			)
			sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			v.add_child(sub)

		fmt_grid.add_child(btn)
		_format_buttons[fid] = btn

	if not compact:
		_format_desc_label = _make_label("", BODY_FONT, maxi(11, roundi(12.0 * s)), UIConstants.COLOR_TEXT_DIM)
		_format_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(_format_desc_label)

	# Format Rules: Rounds, Field Size, Cut Rule, Playoff
	var rules_grid := GridContainer.new()
	rules_grid.columns = 2 if columns >= 4 else 1
	rules_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_grid.add_theme_constant_override("h_separation", roundi(12.0 * s))
	rules_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(rules_grid)

	var chip_h := 32.0 if compact else 36.0

	# Rounds picker
	var rounds_group := VBoxContainer.new()
	rounds_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rounds_group.add_theme_constant_override("separation", 3)
	rounds_group.add_child(_make_label("Rounds", SUBTITLE_FONT, 11, UIConstants.COLOR_TEXT_DIM))
	var rounds_row := HBoxContainer.new()
	rounds_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rounds_row.add_theme_constant_override("separation", 4)
	for r_opt in TournamentLibrary.ROUND_OPTIONS:
		var r_val := int(r_opt)
		var r_btn := _make_rule_chip("Rounds_%d" % r_val, "%dR" % r_val, "Play %d %s" % [r_val, "round" if r_val == 1 else "rounds"], chip_h, FORMAT_ACCENT)
		r_btn.toggled.connect(_on_rounds_toggled.bind(r_val))
		rounds_row.add_child(r_btn)
		_round_buttons[r_val] = r_btn
	rounds_group.add_child(rounds_row)
	rules_grid.add_child(rounds_group)

	# Field Size picker
	var fsize_group := VBoxContainer.new()
	fsize_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fsize_group.add_theme_constant_override("separation", 3)
	fsize_group.add_child(_make_label("Field Size", SUBTITLE_FONT, 11, UIConstants.COLOR_TEXT_DIM))
	var fsize_row := HBoxContainer.new()
	fsize_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fsize_row.add_theme_constant_override("separation", 4)
	for fs_opt in TournamentLibrary.FIELD_SIZE_OPTIONS:
		var fs_val := int(fs_opt)
		var fs_btn := _make_rule_chip("FieldSize_%d" % fs_val, str(fs_val), "%d total golfers in the tournament field" % fs_val, chip_h, GOLFER_ACCENT)
		fs_btn.toggled.connect(_on_field_size_toggled.bind(fs_val))
		fsize_row.add_child(fs_btn)
		_field_size_buttons[fs_val] = fs_btn
	fsize_group.add_child(fsize_row)
	rules_grid.add_child(fsize_group)

	# Cut Line picker
	var cut_group := VBoxContainer.new()
	cut_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cut_group.add_theme_constant_override("separation", 3)
	cut_group.add_child(_make_label("Cut Rule", SUBTITLE_FONT, 11, UIConstants.COLOR_TEXT_DIM))
	var cut_row := HBoxContainer.new()
	cut_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cut_row.add_theme_constant_override("separation", 4)
	for c_opt in TournamentLibrary.get_cut_rules():
		var cid := str(c_opt["id"])
		var short_lbl := "No Cut"
		if cid == "top_50pct":
			short_lbl = "Top 50%"
		elif cid == "top_10_ties":
			short_lbl = "Top 10"
		var c_btn := _make_rule_chip("Cut_%s" % cid, short_lbl, str(c_opt["description"]), chip_h, COURSE_ACCENT)
		c_btn.toggled.connect(_on_cut_toggled.bind(cid))
		cut_row.add_child(c_btn)
		_cut_buttons[cid] = c_btn
	cut_group.add_child(cut_row)
	rules_grid.add_child(cut_group)

	# Sudden-Death Playoff toggle
	var po_group := VBoxContainer.new()
	po_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	po_group.add_theme_constant_override("separation", 3)
	po_group.add_child(_make_label("Tiebreaker", SUBTITLE_FONT, 11, UIConstants.COLOR_TEXT_DIM))
	_playoff_button = _make_rule_chip(
		"PlayoffToggle",
		"Playoff: ON",
		"Resolve 1st-place ties with a hole-by-hole Sudden-Death Playoff",
		chip_h,
		MenuStyle.ACCENT_PRIMARY
	)
	_playoff_button.toggled.connect(_on_playoff_toggled)
	po_group.add_child(_playoff_button)
	rules_grid.add_child(po_group)

	return box

func _make_features_section(s: float, columns: int, compact: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "GameFeaturesSection"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6 if compact else roundi(8.0 * s))

	box.add_child(_make_kicker("GAME FEATURES (MODS)", s))

	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6 if compact else roundi(8.0 * s))
	grid.add_theme_constant_override("v_separation", 6 if compact else roundi(8.0 * s))
	box.add_child(grid)

	var min_h := 38.0 if compact else maxf(48.0, roundf(54.0 * s))
	for opt in _available_features:
		var fid := str(opt.get("id", ""))
		var meta: Dictionary = BUILTIN_FEATURES.get(fid, {})
		var title := str(opt.get("title", "")).strip_edges()
		if title.is_empty():
			title = str(meta.get("title", fid.capitalize()))
		var desc := str(opt.get("description", "")).strip_edges()
		if desc.is_empty():
			desc = str(meta.get("subtitle", ""))
		var accent: Color = meta.get("accent", FEATURE_ACCENT)

		var btn := Button.new()
		btn.name = "Feature_%s" % fid
		btn.toggle_mode = true
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(64.0, min_h)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = desc if not desc.is_empty() else ("Enable %s during this tournament" % title)
		btn.add_theme_font_override("font", SUBTITLE_FONT)
		MenuStyle.paint_choice(btn, accent)
		btn.toggled.connect(_on_feature_toggled.bind(fid))

		var inner := MarginContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("margin_left", 8)
		inner.add_theme_constant_override("margin_right", 8)
		inner.add_theme_constant_override("margin_top", 4)
		inner.add_theme_constant_override("margin_bottom", 4)
		btn.add_child(inner)

		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 1)
		inner.add_child(v)

		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 6)
		v.add_child(top)

		var t_lbl := _make_label(title, SUBTITLE_FONT, 12 if compact else 13, UIConstants.COLOR_TEXT)
		t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(t_lbl)

		var state_lbl := _make_label("ON", SUBTITLE_FONT, 10, accent.lightened(0.2))
		state_lbl.name = "StateLabel"
		top.add_child(state_lbl)

		if not compact and not desc.is_empty():
			var d_lbl := _make_label(desc, BODY_FONT, 10, UIConstants.COLOR_TEXT_DIM)
			d_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			v.add_child(d_lbl)

		grid.add_child(btn)
		_feature_buttons[fid] = btn

	return box

func _make_rule_chip(btn_name: String, label_text: String, tip: String, min_h: float, accent: Color) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = label_text
	btn.toggle_mode = true
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(44.0, min_h)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = tip
	btn.add_theme_font_override("font", SUBTITLE_FONT)
	btn.add_theme_font_size_override("font_size", 11)
	MenuStyle.paint_choice(btn, accent)
	return btn

func _make_course_section(s: float, scrollable: bool, compact: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "CourseSection"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if scrollable:
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6 if compact else roundi(8.0 * s))

	var saved_cnt := TournamentLibrary.saved_course_count()
	var kicker_text := "CHOOSE COURSE" if saved_cnt <= 0 else "CHOOSE COURSE (%d SAVED)" % saved_cnt
	box.add_child(_make_kicker(kicker_text, s))

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)

	var min_h := 44.0 if compact else maxf(54.0, roundf(58.0 * s))
	for entry in _courses:
		list.add_child(_make_course_row(entry, s, min_h, compact))

	if scrollable:
		var scroll := ScrollContainer.new()
		scroll.name = "CourseScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.add_child(list)
		box.add_child(scroll)
	else:
		box.add_child(list)

	return box

func _make_course_row(entry: Dictionary, s: float, min_h: float, compact: bool) -> Control:
	var cid := str(entry["id"])
	var is_default := bool(entry.get("is_default", true))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.name = "Course_%s" % cid.replace(":", "_")
	btn.toggle_mode = true
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(100.0, min_h)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = str(entry.get("tagline", ""))
	btn.add_theme_font_override("font", SUBTITLE_FONT)
	MenuStyle.paint_choice(btn, COURSE_ACCENT if is_default else CAREER_BADGE_COLOR)
	btn.toggled.connect(_on_course_toggled.bind(cid))

	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 5)
	inner.add_theme_constant_override("margin_bottom", 5)
	btn.add_child(inner)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	inner.add_child(v)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)

	var name_lbl := _make_label(
		str(entry["name"]),
		SUBTITLE_FONT,
		13 if compact else maxi(14, roundi(15.0 * s)),
		UIConstants.COLOR_TEXT
	)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_lbl)

	var badge_col := DEFAULT_BADGE_COLOR if is_default else CAREER_BADGE_COLOR
	var badge_lbl := _make_label(
		str(entry.get("source_label", "DEFAULT")),
		SUBTITLE_FONT,
		10,
		badge_col
	)
	top.add_child(badge_lbl)

	var detail := "%s · %d Holes · Par %d" % [
		str(entry.get("theme_name", "Parkland")),
		int(entry.get("hole_count", 9)),
		int(entry.get("par", 36)),
	]
	var meta_lbl := _make_label(
		detail,
		BODY_FONT,
		10 if compact else maxi(11, roundi(12.0 * s)),
		UIConstants.COLOR_TEXT_DIM
	)
	meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(meta_lbl)

	row.add_child(btn)
	_course_buttons[cid] = btn

	if not is_default:
		var del_btn := _make_delete_button(
			"DeleteSavedCourse_%s" % cid.trim_prefix("saved:"),
			"Remove saved course '%s' from Tournament Mode" % str(entry["name"]),
			min_h
		)
		del_btn.pressed.connect(_on_delete_course_pressed.bind(cid))
		row.add_child(del_btn)

	return row

func _make_golfer_section(s: float, scrollable: bool, compact: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "GolferSection"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if scrollable:
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6 if compact else roundi(8.0 * s))

	var saved_cnt := TournamentLibrary.saved_golfer_count()
	var kicker_text := "CHOOSE GOLFER" if saved_cnt <= 0 else "CHOOSE GOLFER (%d SAVED)" % saved_cnt
	box.add_child(_make_kicker(kicker_text, s))

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)

	var min_h := 44.0 if compact else maxf(54.0, roundf(58.0 * s))
	for entry in _golfers:
		list.add_child(_make_golfer_row(entry, s, min_h, compact))

	if scrollable:
		var scroll := ScrollContainer.new()
		scroll.name = "GolferScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.add_child(list)
		box.add_child(scroll)
	else:
		box.add_child(list)

	return box

func _make_golfer_row(entry: Dictionary, s: float, min_h: float, compact: bool) -> Control:
	var gid := str(entry["id"])
	var is_default := bool(entry.get("is_default", true))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.name = "Golfer_%s" % gid.replace(":", "_")
	btn.toggle_mode = true
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(100.0, min_h)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "%s · %s · Age %d · %s · Skin: %s" % [
		str(entry.get("profession", "Golfer")),
		str(entry.get("gender_name", "Male")),
		int(entry.get("age", 30)),
		str(entry.get("marital_status_name", "Single")),
		str(entry.get("skin_name", "Casual")),
	]
	btn.add_theme_font_override("font", SUBTITLE_FONT)
	MenuStyle.paint_choice(btn, GOLFER_ACCENT if is_default else CAREER_BADGE_COLOR)
	btn.toggled.connect(_on_golfer_toggled.bind(gid))

	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", 8)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 5)
	inner.add_theme_constant_override("margin_bottom", 5)
	btn.add_child(inner)

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	inner.add_child(h)

	var swatch := GolferSwatch.new(entry)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(swatch)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)

	var name_lbl := _make_label(
		str(entry["name"]),
		SUBTITLE_FONT,
		13 if compact else maxi(14, roundi(15.0 * s)),
		UIConstants.COLOR_TEXT
	)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_lbl)

	var badge_col := DEFAULT_BADGE_COLOR if is_default else CAREER_BADGE_COLOR
	var badge_lbl := _make_label(
		str(entry.get("source_label", "DEFAULT")),
		SUBTITLE_FONT,
		10,
		badge_col
	)
	top.add_child(badge_lbl)

	var stats_line := "%s · Age %d · %s · %.0f%% Skill" % [
		str(entry.get("profession", "Golfer")),
		int(entry.get("age", 30)),
		str(entry.get("skin_name", "Casual")),
		float(entry.get("avg_golf_skill_pct", 50.0)),
	]
	var meta_lbl := _make_label(
		stats_line,
		BODY_FONT,
		10 if compact else maxi(11, roundi(12.0 * s)),
		UIConstants.COLOR_TEXT_DIM
	)
	meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(meta_lbl)

	row.add_child(btn)
	_golfer_buttons[gid] = btn

	if not is_default:
		var del_btn := _make_delete_button(
			"DeleteSavedGolfer_%s" % gid.trim_prefix("saved:"),
			"Remove saved golfer '%s' from Tournament Mode" % str(entry["name"]),
			min_h
		)
		del_btn.pressed.connect(_on_delete_golfer_pressed.bind(gid))
		row.add_child(del_btn)

	return row

func _make_dossier_rail(s: float) -> Control:
	var rail := PanelContainer.new()
	rail.name = "TournamentDossier"
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.size_flags_stretch_ratio = 1.05
	rail.custom_minimum_size.x = maxf(300.0, roundf(325.0 * s))
	rail.add_theme_stylebox_override(
		"panel",
		MenuStyle.panel(MenuStyle.RAIL_BG, MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.42),
			MenuStyle.CARD_RADIUS, roundi(16.0 * s), roundi(14.0 * s))
	)

	var outer_col := VBoxContainer.new()
	outer_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_col.add_theme_constant_override("separation", roundi(8.0 * s))
	rail.add_child(outer_col)

	var dossier_scroll := ScrollContainer.new()
	dossier_scroll.name = "DossierScroll"
	dossier_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dossier_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dossier_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dossier_scroll.follow_focus = true
	outer_col.add_child(dossier_scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", roundi(8.0 * s))
	dossier_scroll.add_child(col)

	col.add_child(_make_kicker("TOURNAMENT CARD", s))

	_course_preview = TournamentCoursePreview.new()
	_course_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_course_preview.custom_minimum_size = Vector2(220.0, maxf(104.0, roundf(120.0 * s)))
	col.add_child(_course_preview)

	_preview_title_label = _make_label("", TITLE_FONT, maxi(15, roundi(17.0 * s)), MenuStyle.TITLE_COLOR)
	_preview_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_preview_title_label)

	_preview_meta_label = _make_label("", BODY_FONT, maxi(11, roundi(12.0 * s)), UIConstants.COLOR_TEXT_DIM)
	_preview_meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_preview_meta_label)

	col.add_child(_make_hairline())
	col.add_child(_make_golfer_dossier_content(s))
	col.add_child(_make_hairline())

	_dossier_diff_label = _make_label("", BODY_FONT, maxi(11, roundi(12.0 * s)), MenuStyle.ACCENT_PRIMARY)
	_dossier_diff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer_col.add_child(_dossier_diff_label)

	_start_button = _make_start_button(maxf(48.0, roundf(54.0 * s)), maxi(17, roundi(20.0 * s)))
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_col.add_child(_start_button)

	return rail

func _make_golfer_dossier_content(s: float) -> Control:
	var box := VBoxContainer.new()
	box.name = "GolferDossierContent"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)

	box.add_child(_make_kicker("GOLFER DOSSIER", s))

	var g_head := HBoxContainer.new()
	g_head.add_theme_constant_override("separation", 8)
	box.add_child(g_head)

	_golfer_summary_swatch = GolferSwatch.new()
	g_head.add_child(_golfer_summary_swatch)

	var g_titles := VBoxContainer.new()
	g_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g_titles.add_theme_constant_override("separation", 1)
	g_head.add_child(g_titles)

	_golfer_summary_name = _make_label("", SUBTITLE_FONT, maxi(14, roundi(16.0 * s)), UIConstants.COLOR_TEXT)
	_golfer_summary_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	g_titles.add_child(_golfer_summary_name)

	_golfer_summary_role = _make_label("", BODY_FONT, 11, GOLFER_ACCENT.lightened(0.15))
	_golfer_summary_role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	g_titles.add_child(_golfer_summary_role)

	# Full Identity: Profession, Age, Gender, Marital Status
	_golfer_identity_label = _make_label("", BODY_FONT, 11, UIConstants.COLOR_TEXT_DIM)
	_golfer_identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_golfer_identity_label)

	# Skin & Skin Colours row
	var skin_row := HBoxContainer.new()
	skin_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_row.add_theme_constant_override("separation", 5)
	box.add_child(skin_row)

	_golfer_skin_label = _make_label("", BODY_FONT, 11, UIConstants.COLOR_TEXT_DIM)
	_golfer_skin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_golfer_skin_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	skin_row.add_child(_golfer_skin_label)

	for grp_name in ["Shirt", "Pants", "Cap", "Hair", "Skin"]:
		var chip := ColorRect.new()
		chip.name = "SkinColor_%s" % grp_name
		chip.custom_minimum_size = Vector2(12, 12)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.tooltip_text = "%s colour" % grp_name
		skin_row.add_child(chip)
		_skin_color_chips[grp_name] = chip

	# Golfer Traits (Neat, Outgoing, Active, Playful, Nice)
	var traits_hdr := _make_label("Golfer Traits", SUBTITLE_FONT, 11, UIConstants.COLOR_TEXT_MUTED)
	box.add_child(traits_hdr)

	var traits_flow := HFlowContainer.new()
	traits_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	traits_flow.add_theme_constant_override("h_separation", 6)
	traits_flow.add_theme_constant_override("v_separation", 3)
	box.add_child(traits_flow)

	for t_key in GolferAttributes.TRAIT_KEYS:
		var t_lbl := _make_label(
			str(GolferAttributes.TRAIT_NAMES.get(t_key, t_key.capitalize())),
			SUBTITLE_FONT,
			10,
			UIConstants.COLOR_TEXT_MUTED
		)
		t_lbl.name = "TraitBadge_%s" % str(t_key)
		traits_flow.add_child(t_lbl)
		_trait_badges[str(t_key)] = t_lbl

	# Golfer Skills (Length, Accuracy, Imagination)
	var gskills_hdr := _make_label("Golfer Skills", SUBTITLE_FONT, 11, UIConstants.COLOR_TEXT_MUTED)
	box.add_child(gskills_hdr)

	var gskills_flow := HFlowContainer.new()
	gskills_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gskills_flow.add_theme_constant_override("h_separation", 8)
	gskills_flow.add_theme_constant_override("v_separation", 3)
	box.add_child(gskills_flow)

	for gs_key in GolferAttributes.GOLFER_SKILL_KEYS:
		var gs_lbl := _make_label(
			str(GolferAttributes.GOLFER_SKILL_NAMES.get(gs_key, gs_key.capitalize())),
			SUBTITLE_FONT,
			10,
			UIConstants.COLOR_TEXT_MUTED
		)
		gs_lbl.name = "GolferSkillBadge_%s" % str(gs_key)
		gskills_flow.add_child(gs_lbl)
		_gskill_badges[str(gs_key)] = gs_lbl

	# All 10 Golf Skills
	var golf_hdr := _make_label("Golf Skills (10)", SUBTITLE_FONT, 11, UIConstants.COLOR_TEXT_MUTED)
	box.add_child(golf_hdr)

	var golf_grid := VBoxContainer.new()
	golf_grid.name = "GolfSkillsList"
	golf_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	golf_grid.add_theme_constant_override("separation", 3)
	box.add_child(golf_grid)

	var skill_colors := [
		Color("e09b52"), Color("d9824c"), Color("6dc48c"), Color("5eb89b"), Color("6fb5e0"),
		Color("a78be0"), Color("c785cf"), Color("d6ba5c"), Color("8fc77a"), Color("e3c567"),
	]
	for sk_idx in range(GolferAttributes.GOLF_SKILLS.size()):
		var sk_title: String = TournamentLibrary.GOLF_SKILL_SHORT_NAMES[sk_idx] if sk_idx < TournamentLibrary.GOLF_SKILL_SHORT_NAMES.size() else GolferAttributes.GOLF_SKILLS[sk_idx]
		var s_row := HBoxContainer.new()
		s_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s_row.add_theme_constant_override("separation", 6)

		var s_name := _make_label(sk_title, BODY_FONT, 10, UIConstants.COLOR_TEXT_DIM)
		s_name.custom_minimum_size.x = 108.0
		s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		s_row.add_child(s_name)

		var bar := Kit.PixelBar.new(0.25, skill_colors[sk_idx % skill_colors.size()])
		bar.custom_minimum_size = Vector2(56.0, 8.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s_row.add_child(bar)

		var val_lbl := _make_label("0 (+0%)", SUBTITLE_FONT, 10, UIConstants.COLOR_TEXT)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.custom_minimum_size.x = 58.0
		s_row.add_child(val_lbl)

		golf_grid.add_child(s_row)
		_golf_skill_rows[sk_idx] = [bar, val_lbl]

	return box

func _make_inline_preview_card(s: float) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		MenuStyle.panel(MenuStyle.RAIL_BG, MenuStyle.with_alpha(COURSE_ACCENT, 0.36),
			MenuStyle.CARD_RADIUS, 12, 10)
	)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	_course_preview = TournamentCoursePreview.new()
	_course_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_course_preview.custom_minimum_size = Vector2(180.0, roundf(116.0 * s))
	col.add_child(_course_preview)

	_preview_title_label = _make_label("", SUBTITLE_FONT, 15, MenuStyle.TITLE_COLOR)
	_preview_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_preview_title_label)

	_preview_meta_label = _make_label("", BODY_FONT, 12, UIConstants.COLOR_TEXT_DIM)
	_preview_meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_preview_meta_label)
	return card

func _make_start_button(min_h: float, font_sz: int) -> Button:
	var btn := Button.new()
	btn.name = "StartTournamentButton"
	btn.text = "Start Tournament"
	btn.custom_minimum_size = Vector2(160.0, min_h)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "Tee off in Round 1 with the selected roster, format, rules, course, and golfer"
	btn.add_theme_font_override("font", TITLE_FONT)
	btn.add_theme_font_size_override("font_size", font_sz)
	MenuStyle.paint_primary(btn)
	btn.pressed.connect(_on_start_pressed)
	return btn

func _make_delete_button(btn_name: String, tip: String, min_h: float) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = "Del"
	btn.tooltip_text = tip
	btn.custom_minimum_size = Vector2(56.0, min_h)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", SUBTITLE_FONT)
	btn.add_theme_font_size_override("font_size", 11)
	PixelButtonStyle.paint_card(
		btn,
		MenuStyle.ACCENT_QUIT,
		0.0,
		6,
		Color(0.96, 0.72, 0.68),
		Color.WHITE
	)
	return btn

func _wrap_sheet_card(inner: Control, s: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		MenuStyle.panel(MenuStyle.SHEET_BG, MenuStyle.with_alpha(MenuStyle.ACCENT_SECONDARY, 0.34),
			MenuStyle.CARD_RADIUS, roundi(14.0 * s), roundi(12.0 * s))
	)
	card.add_child(inner)
	return card

func _wrap_compact_card(inner: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		MenuStyle.panel(MenuStyle.SHEET_BG, MenuStyle.with_alpha(MenuStyle.ACCENT_SECONDARY, 0.34),
			MenuStyle.CARD_RADIUS, 8, 8)
	)
	card.add_child(inner)
	return card

func _make_hairline() -> ColorRect:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.color = MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

func _make_kicker(text: String, s: float) -> Label:
	var lbl := _make_label(text, SUBTITLE_FONT, maxi(11, roundi(12.0 * s)), MenuStyle.ACCENT_SECONDARY)
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return lbl

func _make_label(text: String, font: Font, font_sz: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", color)
	return lbl

# ── Selection Sync & Callbacks ──────────────────────────────────────────────

func _sync_selection_states() -> void:
	for diff_id in _difficulty_buttons:
		var btn: Button = _difficulty_buttons[diff_id]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(int(diff_id) == _difficulty)

	for fid in _format_buttons:
		var btn: Button = _format_buttons[fid]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(int(fid) == _format_type)

	for r_val in _round_buttons:
		var btn: Button = _round_buttons[r_val]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(int(r_val) == _rounds)

	for fs_val in _field_size_buttons:
		var btn: Button = _field_size_buttons[fs_val]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(int(fs_val) == _field_size)

	var single_round := _rounds <= 1
	var shown_cut := "none" if single_round else _cut_rule
	for cid_rule in _cut_buttons:
		var btn: Button = _cut_buttons[cid_rule]
		if is_instance_valid(btn):
			var rule_str := str(cid_rule)
			btn.disabled = single_round and rule_str != "none"
			btn.set_pressed_no_signal(rule_str == shown_cut)

	if _playoff_button != null and is_instance_valid(_playoff_button):
		_playoff_button.set_pressed_no_signal(_playoff_enabled)
		_playoff_button.text = "Playoff: ON" if _playoff_enabled else "Playoff: OFF"

	for feat_id in _feature_buttons:
		var btn: Button = _feature_buttons[feat_id]
		if is_instance_valid(btn):
			var on := bool(_features.get(str(feat_id), true))
			btn.set_pressed_no_signal(on)
			var st_lbl := btn.find_child("StateLabel", true, false) as Label
			if st_lbl != null:
				st_lbl.text = "ON" if on else "OFF"
				st_lbl.add_theme_color_override(
					"font_color",
					UIConstants.COLOR_SUCCESS if on else UIConstants.COLOR_TEXT_MUTED
				)

	for cid in _course_buttons:
		var btn: Button = _course_buttons[cid]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(str(cid) == _course_id)

	for gid in _golfer_buttons:
		var btn: Button = _golfer_buttons[gid]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(str(gid) == _golfer_id)

	var diff := TournamentLibrary.get_difficulty(_difficulty)
	var fmt := TournamentLibrary.get_format_info(_format_type)
	var course := _selected_course()
	var golfer := _selected_golfer()

	if _difficulty_desc_label != null:
		_difficulty_desc_label.text = str(diff.get("description", ""))
	if _difficulty_roster_label != null:
		var featured: Array = diff.get("featured_golfers", [])
		_difficulty_roster_label.text = "Featured Opponents (%d in pool): %s" % [
			int(diff.get("roster_size", 18)),
			", ".join(PackedStringArray(featured)),
		]
	if _format_desc_label != null:
		_format_desc_label.text = str(fmt.get("description", ""))

	if _course_preview != null:
		_course_preview.set_course_entry(course)
	if _preview_title_label != null:
		_preview_title_label.text = str(course.get("name", "Course"))
	if _preview_meta_label != null:
		_preview_meta_label.text = "%s · %d Holes · Par %d · %s" % [
			str(course.get("theme_name", "Parkland")),
			int(course.get("hole_count", 9)),
			int(course.get("par", 36)),
			"Built-in Course" if bool(course.get("is_default", true)) else "Saved Career Course",
		]

	if _golfer_summary_swatch != null:
		_golfer_summary_swatch.set_from_entry(golfer)
	if _golfer_summary_name != null:
		_golfer_summary_name.text = str(golfer.get("name", "Golfer"))
	if _golfer_summary_role != null:
		_golfer_summary_role.text = "%s · %.0f%% Avg Golf Skill (%d pts)" % [
			str(golfer.get("profession", "Golfer")),
			float(golfer.get("avg_golf_skill_pct", 50.0)),
			int(golfer.get("total_golf_points", 0)),
		]
	if _golfer_identity_label != null:
		_golfer_identity_label.text = "Age %d · %s · %s" % [
			int(golfer.get("age", 30)),
			str(golfer.get("gender_name", "Male")),
			str(golfer.get("marital_status_name", "Single")),
		]
	if _golfer_skin_label != null:
		_golfer_skin_label.text = "Skin: %s" % str(golfer.get("skin_name", "Casual"))

	var sc_dict: Dictionary = golfer.get("skin_colors", {}) if golfer.get("skin_colors") is Dictionary else {}
	for grp_name in _skin_color_chips:
		var chip: ColorRect = _skin_color_chips[grp_name]
		var hex := str(sc_dict.get(grp_name, "cccccc"))
		chip.color = Color.from_string(hex, Color.WHITE)
		chip.tooltip_text = "%s: #%s" % [grp_name, hex]

	var traits_dict: Dictionary = golfer.get("traits", {}) if golfer.get("traits") is Dictionary else {}
	for t_key in _trait_badges:
		var lbl: Label = _trait_badges[t_key]
		var on := bool(traits_dict.get(t_key, false))
		var t_name := str(GolferAttributes.TRAIT_NAMES.get(t_key, t_key.capitalize()))
		lbl.text = "[+] %s" % t_name if on else "[ ] %s" % t_name
		lbl.add_theme_color_override("font_color", COURSE_ACCENT if on else UIConstants.COLOR_TEXT_MUTED)

	var gskills_dict: Dictionary = golfer.get("golfer_skills", {}) if golfer.get("golfer_skills") is Dictionary else {}
	for gs_key in _gskill_badges:
		var lbl: Label = _gskill_badges[gs_key]
		var on := bool(gskills_dict.get(gs_key, false))
		var gs_name := str(GolferAttributes.GOLFER_SKILL_NAMES.get(gs_key, gs_key.capitalize()))
		lbl.text = "[+] %s" % gs_name if on else "[ ] %s" % gs_name
		lbl.add_theme_color_override("font_color", FORMAT_ACCENT if on else UIConstants.COLOR_TEXT_MUTED)

	var pts_arr: Array = golfer.get("points", []) if golfer.get("points") is Array else []
	for sk_idx in _golf_skill_rows:
		var pair: Array = _golf_skill_rows[sk_idx]
		var bar: Kit.PixelBar = pair[0]
		var val_lbl: Label = pair[1]
		var pts := int(pts_arr[sk_idx]) if int(sk_idx) < pts_arr.size() else 0
		var bonus_pct := pts * 10
		# Normalise bar against tour-elite 24 pts (240% bonus) so all tiers read clearly
		bar.set_fraction(clampf(float(pts) / 24.0, 0.04 if pts > 0 else 0.0, 1.0))
		val_lbl.text = "%d (+%d%%)" % [pts, bonus_pct]

	if _dossier_diff_label != null:
		_dossier_diff_label.text = "%s · %s · %d %s · %d Golfers · %s%s" % [
			TournamentLibrary.get_difficulty_label(_difficulty),
			str(fmt.get("name", "Stroke Play")),
			_rounds,
			"Round" if _rounds == 1 else "Rounds",
			_field_size,
			TournamentLibrary.get_cut_rule_label(shown_cut, _rounds),
			" · Playoff" if _playoff_enabled else "",
		]

	if _footer_summary_label != null:
		_footer_summary_label.text = "%s · %s (%dR, %dP) · %s · %s" % [
			str(diff.get("name", "Normal")),
			str(fmt.get("short_name", "Stroke Play")),
			_rounds,
			_field_size,
			str(course.get("name", "Course")),
			str(golfer.get("name", "Golfer")),
		]

func _on_difficulty_toggled(pressed: bool, diff_id: int) -> void:
	if not pressed:
		if diff_id == _difficulty and _difficulty_buttons.has(diff_id):
			(_difficulty_buttons[diff_id] as Button).set_pressed_no_signal(true)
		return
	select_difficulty(diff_id)

func _on_format_toggled(pressed: bool, format_id: int) -> void:
	if not pressed:
		if format_id == _format_type and _format_buttons.has(format_id):
			(_format_buttons[format_id] as Button).set_pressed_no_signal(true)
		return
	select_format_type(format_id)

func _on_rounds_toggled(pressed: bool, round_count: int) -> void:
	if not pressed:
		if round_count == _rounds and _round_buttons.has(round_count):
			(_round_buttons[round_count] as Button).set_pressed_no_signal(true)
		return
	select_rounds(round_count)

func _on_field_size_toggled(pressed: bool, fsize: int) -> void:
	if not pressed:
		if fsize == _field_size and _field_size_buttons.has(fsize):
			(_field_size_buttons[fsize] as Button).set_pressed_no_signal(true)
		return
	select_field_size(fsize)

func _on_cut_toggled(pressed: bool, rule_id: String) -> void:
	if not pressed:
		var shown_cut := "none" if _rounds <= 1 else _cut_rule
		if rule_id == shown_cut and _cut_buttons.has(rule_id):
			(_cut_buttons[rule_id] as Button).set_pressed_no_signal(true)
		return
	select_cut_rule(rule_id)

func _on_playoff_toggled(pressed: bool) -> void:
	set_playoff_enabled(pressed)

func _on_feature_toggled(pressed: bool, feature_id: String) -> void:
	set_feature_enabled(feature_id, pressed)

func _on_course_toggled(pressed: bool, course_id: String) -> void:
	if not pressed:
		if course_id == _course_id and _course_buttons.has(course_id):
			(_course_buttons[course_id] as Button).set_pressed_no_signal(true)
		return
	select_course(course_id)

func _on_golfer_toggled(pressed: bool, golfer_id: String) -> void:
	if not pressed:
		if golfer_id == _golfer_id and _golfer_buttons.has(golfer_id):
			(_golfer_buttons[golfer_id] as Button).set_pressed_no_signal(true)
		return
	select_golfer(golfer_id)

func _on_delete_course_pressed(course_id: String) -> void:
	if TournamentLibrary.delete_saved_course(course_id):
		EventBus.notify("Removed saved tournament course.", "info")
		refresh()

func _on_delete_golfer_pressed(golfer_id: String) -> void:
	if TournamentLibrary.delete_saved_golfer(golfer_id):
		EventBus.notify("Removed saved tournament golfer.", "info")
		refresh()

func _on_start_pressed() -> void:
	start_requested.emit(get_options())

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
