extends CanvasLayer
class_name GeneratingCourseScreen
## GeneratingCourseScreen - The "Generating Course" loading screen.
##
## Shown while a new course is built (natural terrain, generated or Quick
## Start holes, the clubhouse, walking paths). The old screen was a flat dark
## overlay with a single "Generating course..." label; this one is dressed in
## the title screen's clothes:
##
##  * the shared MenuBackdrop artwork with a dark dim so the card pops;
##  * a gold-trimmed pixel-frame card (PixelButtonStyle) on MenuStyle colours;
##  * the MenuFlagMark emblem beside the course name and its theme line;
##  * a segmented pixel progress bar with a travelling shine band;
##  * a checklist of the build stages, each pip pending, active or done;
##  * a recessed tip box cycling gameplay tips (starting with the theme blurb).
##
## Generation runs synchronously on the main thread, so the screen only repaints
## between the awaits in main.gd - the bar's displayed fill eases towards its
## target every frame, which keeps it smooth across those coarse updates, and
## everything still reads perfectly as a static card mid-generation.
##
## The layout compacts itself for small windows (see is_compact / is_tiny):
## phones lose the tip box, and very short windows keep only the header, the
## bar and the status line, so nothing ever has to scroll mid-generation.
##
## Flow: main.gd builds the stage list with stages_for_job(), calls setup(),
## adds the screen, then calls set_stage_by_title() before each build phase
## (awaiting a frame so the new stage paints before the blocking work) and
## finish() once the course is ready.

## Build phases with a fixed title. The holes phase is worded per job by
## holes_stage_text() ("Laying out 6 holes", ...).
const STAGE_TERRAIN := "Shaping the land"
const STAGE_CLUBHOUSE := "Opening the clubhouse"
const STAGE_PATHS := "Laying walking paths"
const STAGE_OPENING := "Opening day"

## The title screen's chunky Pixelify Sans lettering: Bold for the course
## name, SemiBold for the status line, Regular for stages and tips.
const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

## Tips cycled through the tip box while the course builds. The theme
## description passed to setup() is shown first, then these.
const TIPS := [
	"Link tees and greens with paths - golfers walk faster on them.",
	"Raise the green fee as your star rating climbs.",
	"Trees shelter fairways from the wind - and punish wild drives.",
	"Water hazards raise the stakes - and the scenery.",
	"Host tournaments to boost your reputation.",
	"Demand rises and falls with the seasons - plan ahead.",
	"Every round starts at the clubhouse - build near the first tee.",
	"Happy golfers come back: keep conditions high and the pace quick.",
]
## Seconds each tip stays up before the next one is shown.
const TIP_INTERVAL := 5.0
## How far the window has to move (as a share of itself) before the card is
## measured again while staying in the same compactness.
const REPROPORTION_STEP := 0.12

var _course_name := "New Course"
var _subtitle := ""
var _stages: Array[String] = []
var _tips: Array[String] = []
var _stage_index := 0
var _finished := false
var _target_fraction := 0.0
var _display_fraction := 0.0
var _tip_index := 0
var _time := 0.0
var _tip_time := 0.0
var _built := false
var _compact := false
var _tiny := false
var _built_size := Vector2.ZERO

var _status_label: Label = null
var _percent_label: Label = null
var _bar: ProgressTrack = null
var _stage_rows: Array = []
var _tip_label: Label = null


## A segmented pixel progress bar: an ink-framed inset track filled with
## gold blocks (lit along the top edge) and a soft shine band that sweeps
## across while the bar is alive.
class ProgressTrack extends Control:
	const TRACK_BG := Color(0.012, 0.030, 0.023, 0.95)
	const INK := Color("08130f")
	const FILL := Color("e5c57c")
	const FILL_TOP := Color("f4e3b2")
	const BLOCK := 10.0
	const GAP := 4.0

	var fraction := 0.0
	var shimmer := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 24.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The shine band travels past both ends of the track; clip it.
		clip_contents = true

	func _draw() -> void:
		if size.x <= 4.0 or size.y <= 4.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), INK)
		var inner := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
		draw_rect(inner, TRACK_BG)
		var fill_width := inner.size.x * clampf(fraction, 0.0, 1.0)
		if fill_width > 0.5:
			var end := inner.position.x + fill_width
			var x := inner.position.x
			while x < end - 0.5:
				var width: float = minf(BLOCK, end - x)
				var block := Rect2(x, inner.position.y, width, inner.size.y)
				draw_rect(block, FILL)
				draw_rect(Rect2(block.position, Vector2(width, block.size.y * 0.38)), FILL_TOP)
				x += BLOCK + GAP
		# A soft diagonal shine sweeping across the whole track, filled or
		# not, so the bar reads as alive even before the first block lands.
		var band := 46.0
		var span := inner.size.x + band * 2.0
		var sx := inner.position.x - band + fmod(shimmer * 90.0, span)
		var top := inner.position.y
		var bottom := inner.position.y + inner.size.y
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx, bottom),
			Vector2(sx + 18.0, top),
			Vector2(sx + 18.0 + band, top),
			Vector2(sx + band, bottom),
		]), Color(1.0, 1.0, 1.0, 0.10))


## The pip beside one checklist row: a hollow square while pending, a pulsing
## gold square while its stage runs, a green square with a cream check done.
class StagePip extends Control:
	const PENDING := 0
	const ACTIVE := 1
	const DONE := 2

	const SIDE := 14.0
	const GOLD := Color("e5c57c")
	const GOLD_TOP := Color("f7ead0")
	const GREEN := Color("3f7a4d")
	const GREEN_TOP := Color("7fb08a")
	const CREAM := Color("f4edd9")
	const HOLLOW_BG := Color(0.020, 0.051, 0.039, 0.9)
	const HOLLOW_EDGE := Color("63715a")

	var pip_state := PENDING
	var pulse := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(22.0, 22.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(value: int) -> void:
		pip_state = value
		queue_redraw()

	func _draw() -> void:
		var box := Rect2((size - Vector2(SIDE, SIDE)) * 0.5, Vector2(SIDE, SIDE))
		match pip_state:
			DONE:
				draw_rect(box, GREEN)
				draw_rect(Rect2(box.position, Vector2(SIDE, 3.0)), GREEN_TOP)
				var check_color := CREAM
				draw_line(box.position + Vector2(3.0, 7.5), box.position + Vector2(6.5, 11.0),
					check_color, 2.0)
				draw_line(box.position + Vector2(6.5, 11.0), box.position + Vector2(11.5, 3.5),
					check_color, 2.0)
			ACTIVE:
				var glow := 0.72 + 0.28 * sin(pulse * 5.0)
				var halo := Color(GOLD.r, GOLD.g, GOLD.b, 0.30 * glow)
				draw_rect(box.grow(1.5), halo)
				draw_rect(box, GOLD)
				draw_rect(Rect2(box.position, Vector2(SIDE, 3.0)), GOLD_TOP)
			_:
				draw_rect(box, HOLLOW_BG)
				draw_rect(box, HOLLOW_EDGE, false, 1.0)


func _init() -> void:
	# Above all other UI, like the overlay this screen replaces.
	layer = 100

## What the card says. Call before adding the screen to the tree.
## `theme_description` (CourseTheme.get_description) is shown as the first tip.
func setup(course_name: String, subtitle: String, stages: Array[String],
		theme_description: String = "") -> void:
	_course_name = course_name if not course_name.is_empty() else "New Course"
	_subtitle = subtitle
	_stages = stages.duplicate()
	_tips.clear()
	if not theme_description.is_empty():
		_tips.append(theme_description)
	_tips.append_array(TIPS)
	if _built:
		_build()

func _ready() -> void:
	_build()
	if get_tree() != null and get_tree().root != null:
		get_tree().root.size_changed.connect(_on_window_resized)

func _on_window_resized() -> void:
	var view := _window_size()
	if is_compact(view) != _compact or is_tiny(view) != _tiny:
		_build()
		return
	if absf(view.x - _built_size.x) > _built_size.x * REPROPORTION_STEP \
			or absf(view.y - _built_size.y) > _built_size.y * REPROPORTION_STEP:
		_build()

func _window_size() -> Vector2:
	if has_node("/root/Screen"):
		return Screen.window_size
	return get_viewport().get_visible_rect().size

## The bar's target when `index` becomes the active stage: stages complete in
## order, so entering stage i of n means i stages done and one in hand - the
## bar sits halfway through the active stage's share, never stuck at empty
## while the first (and longest) phase runs. Pure, so the mapping can be
## unit-tested without a window.
static func fraction_for_stage(index: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return clampf((float(index) + 0.5) / float(total), 0.0, 1.0)

## Compact windows (phones, squat browser windows) get smaller type and no
## tip box. Pure, so the breakpoint can be unit-tested without a window.
static func is_compact(window_size: Vector2) -> bool:
	return window_size.x < 700.0 or window_size.y < 560.0

## Very short windows (a rotated phone mid-generation) keep only the header,
## the bar and the status line. Pure, so the breakpoint can be unit-tested.
static func is_tiny(window_size: Vector2) -> bool:
	return window_size.y < 460.0

## The checklist for one generation job: shaping the land, the holes phase
## (worded by holes_stage_text(), absent for an empty lot), the clubhouse,
## walking paths when the course opens with holes, and opening day.
static func stages_for_job(holes_stage: String, with_paths: bool) -> Array[String]:
	var stages: Array[String] = [STAGE_TERRAIN]
	if not holes_stage.is_empty():
		stages.append(holes_stage)
	stages.append(STAGE_CLUBHOUSE)
	if with_paths:
		stages.append(STAGE_PATHS)
	stages.append(STAGE_OPENING)
	return stages

## How the holes phase reads on the checklist: Quick Start always builds 3,
## a generated first course its requested count, a prebuilt package its
## ready-made layout, and an empty lot has no holes phase at all.
static func holes_stage_text(is_quick_start: bool, holes_requested: int,
		is_prebuilt: bool) -> String:
	if is_quick_start:
		return "Laying out 3 holes"
	if holes_requested > 0:
		return "Laying out %d holes" % holes_requested
	if is_prebuilt:
		return "Building the ready-made course"
	return ""

## The card's subtitle: the theme and what is being built on it.
static func subtitle_for_job(theme_name: String, is_quick_start: bool,
		holes_requested: int, is_prebuilt: bool) -> String:
	var place := theme_name if not theme_name.is_empty() else "Parkland"
	if is_quick_start:
		return "%s | 3 holes" % place
	if holes_requested > 0:
		return "%s | %d holes" % [place, holes_requested]
	if is_prebuilt:
		return "%s | Ready-made course" % place
	return "%s | Empty lot" % place

## Make the stage with this title the active one; every stage above it reads
## as done. Unknown titles (a skipped phase) are ignored.
func set_stage_by_title(title: String) -> void:
	set_stage(_stages.find(title))

## Make stage `index` the active one. Out-of-range indices are ignored, so a
## skipped phase can simply never be activated and still reads as done once
## a later stage starts.
func set_stage(index: int) -> void:
	if index < 0 or index >= _stages.size():
		return
	_stage_index = index
	_finished = false
	_target_fraction = fraction_for_stage(index, _stages.size())
	_refresh_stages()

## The course is ready: every stage done, the bar full.
func finish() -> void:
	_finished = true
	_target_fraction = 1.0
	_display_fraction = 1.0
	_refresh_stages()

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	# The bar eases towards its target, so the coarse per-phase updates from
	# main.gd still sweep smoothly instead of jumping block to block.
	if _display_fraction < _target_fraction:
		_display_fraction = minf(_target_fraction, _display_fraction + delta * 0.9)
	if _bar != null:
		_bar.fraction = _display_fraction
		_bar.shimmer = _time
		_bar.queue_redraw()
	if _percent_label != null:
		_percent_label.text = "%d%%" % int(roundf(_display_fraction * 100.0))
	for row in _stage_rows:
		var pip: StagePip = row["pip"]
		if pip.pip_state == StagePip.ACTIVE:
			pip.pulse = _time
			pip.queue_redraw()
	if _status_label != null:
		var dots: String = ["", ".", "..", "..."][int(_time * 2.5) % 4]
		_status_label.text = _status_base() + dots
	# Tips turn over every few seconds; the card reserves two lines for them
	# so the swap never moves the layout.
	if _tips.size() > 1:
		_tip_time += delta
		if _tip_time >= TIP_INTERVAL:
			_tip_time = 0.0
			_tip_index = (_tip_index + 1) % _tips.size()
			if _tip_label != null:
				_tip_label.text = _tips[_tip_index]

func _status_base() -> String:
	if _finished:
		return "Course ready"
	if _stage_index >= 0 and _stage_index < _stages.size():
		return _stages[_stage_index]
	return "Working"

# =============================================================================
# BUILD
# =============================================================================

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stage_rows.clear()
	_status_label = null
	_percent_label = null
	_bar = null
	_tip_label = null
	var view := _window_size()
	_compact = is_compact(view)
	_tiny = is_tiny(view)
	_built_size = view

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Generation owns the screen: clicks must not fall through to the game.
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	# The artwork is bright daylight; dim it so the cream type pops.
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.008, 0.020, 0.016, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var pad_x := 26 if not _compact else 16
	var pad_y := 22 if not _compact else 14
	var card := PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
		MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.85),
		MenuStyle.SHEET_BG, pad_x, pad_y))
	center.add_child(card)

	# The column's minimum width sets the card's width; the labels inside it
	# all wrap, so long course names fold instead of stretching the card.
	var inner_width := minf(view.x - (48.0 if not _compact else 24.0) - float(pad_x) * 2.0, 600.0)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(maxf(inner_width, 200.0), 0.0)
	column.add_theme_constant_override("separation", 12 if not _compact else 8)
	card.add_child(column)

	column.add_child(_make_header())
	column.add_child(_make_rule())
	column.add_child(_make_status_row())
	_bar = ProgressTrack.new()
	_bar.name = "ProgressBar"
	_bar.fraction = _display_fraction
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_bar)
	if not _tiny and not _stages.is_empty():
		column.add_child(_make_stages())
	if not _compact and not _tips.is_empty():
		column.add_child(_make_tip_box())

	_refresh_stages()
	_built = true

## The emblem beside the kicker, the course name and its theme line.
func _make_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 14 if not _compact else 10)
	header.alignment = BoxContainer.ALIGNMENT_CENTER

	var mark := MenuFlagMark.new()
	mark.name = "Emblem"
	mark.mark_size = 64.0 if not _compact else 46.0
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mark)

	var title_block := VBoxContainer.new()
	title_block.name = "TitleBlock"
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_block.add_theme_constant_override("separation", 2)
	header.add_child(title_block)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.text = "PREPARING YOUR COURSE"
	kicker.add_theme_font_override("font", BODY_FONT)
	kicker.add_theme_font_size_override("font_size", 12 if not _compact else 11)
	kicker.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_block.add_child(kicker)

	var title := Label.new()
	title.name = "CourseName"
	title.text = _course_name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 30 if not _compact else 23)
	title.add_theme_color_override("font_color", MenuStyle.TITLE_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_block.add_child(title)

	if not _subtitle.is_empty():
		var subtitle := Label.new()
		subtitle.name = "Subtitle"
		subtitle.text = _subtitle
		subtitle.add_theme_font_override("font", SUBTITLE_FONT)
		subtitle.add_theme_font_size_override("font_size", 14 if not _compact else 12)
		subtitle.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
		subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_block.add_child(subtitle)
	return header

func _make_rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = MenuStyle.with_alpha(MenuStyle.ACCENT_PRIMARY, 0.5)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

## The current stage on the left, the percentage on the right.
func _make_status_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "StatusRow"
	row.add_theme_constant_override("separation", 12)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = _status_base()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.add_theme_font_override("font", SUBTITLE_FONT)
	_status_label.add_theme_font_size_override("font_size", 14 if not _compact else 13)
	_status_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_status_label)

	_percent_label = Label.new()
	_percent_label.name = "Percent"
	_percent_label.text = "%d%%" % int(roundf(_display_fraction * 100.0))
	_percent_label.add_theme_font_override("font", SUBTITLE_FONT)
	_percent_label.add_theme_font_size_override("font_size", 14 if not _compact else 13)
	_percent_label.add_theme_color_override("font_color", MenuStyle.ACCENT_PRIMARY)
	_percent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_percent_label)
	return row

## The checklist: one pip-and-label row per build stage.
func _make_stages() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.name = "Stages"
	list.add_theme_constant_override("separation", 5 if not _compact else 3)
	for stage in _stages:
		var row := HBoxContainer.new()
		row.name = "StageRow"
		row.add_theme_constant_override("separation", 10)
		var pip := StagePip.new()
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
		var label := Label.new()
		label.text = stage
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_override("font", BODY_FONT)
		label.add_theme_font_size_override("font_size", 14 if not _compact else 13)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		list.add_child(row)
		_stage_rows.append({"pip": pip, "label": label})
	return list

## The recessed tip box: a kicker over two reserved lines of tips.
func _make_tip_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "TipBox"
	box.add_theme_stylebox_override("panel", PixelButtonStyle.inset_style(
		MenuStyle.ACCENT_SECONDARY, MenuStyle.INSET_BG, 12))
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 2)
	box.add_child(content)
	var kicker := Label.new()
	kicker.name = "TipKicker"
	kicker.text = "COURSE TIP"
	kicker.add_theme_font_override("font", BODY_FONT)
	kicker.add_theme_font_size_override("font_size", 11)
	kicker.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(kicker)
	_tip_label = Label.new()
	_tip_label.name = "Tip"
	_tip_label.text = _tips[_tip_index] if not _tips.is_empty() else ""
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.max_lines_visible = 2
	_tip_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tip_label.add_theme_font_override("font", BODY_FONT)
	_tip_label.add_theme_font_size_override("font_size", 13)
	_tip_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Reserve two lines so a turning tip never moves the card.
	_tip_label.custom_minimum_size = Vector2(0.0, BODY_FONT.get_height(13) * 2.0 + 4.0)
	content.add_child(_tip_label)
	return box

## Repaint the checklist for the current stage: stages above it done, the
## stage itself active, everything below pending - or all done once finished.
func _refresh_stages() -> void:
	for i in _stage_rows.size():
		var row: Dictionary = _stage_rows[i]
		var pip: StagePip = row["pip"]
		var label: Label = row["label"]
		if _finished or i < _stage_index:
			pip.set_state(StagePip.DONE)
			label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
		elif i == _stage_index:
			pip.set_state(StagePip.ACTIVE)
			label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
		else:
			pip.set_state(StagePip.PENDING)
			label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	if _status_label != null:
		_status_label.text = _status_base()
	if _percent_label != null:
		_percent_label.text = "%d%%" % int(roundf(_display_fraction * 100.0))
