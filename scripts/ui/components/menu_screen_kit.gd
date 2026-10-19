extends RefCounted
class_name MenuScreenKit
## MenuScreenKit - the shared chrome of the two fullscreen goal screens
## (Milestones and Achievements): the World Map's MenuBackdrop backdrop, the
## MenuStyle palette, Pixelify Sans faces, PixelButtonStyle's notched
## nine-patch frames and the small builders every panel on those screens is
## made of.
##
## Both screens compose for the shape of the window the way the World Map
## does - a wide desktop layout, a tablet layout and a phone layout - so the
## kit also owns the breakpoint maths and the sizing knobs each mode uses.

enum LayoutMode { DESKTOP, TABLET_LANDSCAPE, TABLET_PORTRAIT, PHONE_LANDSCAPE, PHONE_PORTRAIT }

## The three goal screens are peers: Course Milestones, World Milestones and
## Achievements. Each screen carries the same segmented switch, so players
## hop between the tracks without going back to the course first.
enum GoalTrack { COURSE, WORLD, ACHIEVEMENTS }

const DESKTOP_MIN_WIDTH := 1180.0
const DESKTOP_MIN_HEIGHT := 680.0
const TABLET_MIN_WIDTH := 680.0
const TABLET_MIN_HEIGHT := 620.0

## The atlas shares the title screen's chunky, readable Pixelify Sans
## lettering: Bold for headings and big numbers, SemiBold for names, kickers
## and buttons, Regular for captions and quiet lines.
const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_SURFACE_RAISED := MenuStyle.RAIL_BG
const COLOR_SURFACE_INSET := MenuStyle.INSET_BG
const COLOR_BORDER_SOFT := UIConstants.COLOR_BORDER
const COLOR_TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const COLOR_TEXT_SECONDARY := UIConstants.COLOR_TEXT_DIM
const COLOR_TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

## The composition each viewport shape calls for. Kept pure so every
## breakpoint can be checked without creating a window.
static func layout_mode_for(view: Vector2) -> int:
	if view.x >= DESKTOP_MIN_WIDTH and view.y >= DESKTOP_MIN_HEIGHT and view.x > view.y:
		return LayoutMode.DESKTOP
	if view.x >= TABLET_MIN_WIDTH and view.y >= TABLET_MIN_HEIGHT:
		return LayoutMode.TABLET_LANDSCAPE if view.x >= view.y else LayoutMode.TABLET_PORTRAIT
	if view.x > view.y and view.y < TABLET_MIN_HEIGHT:
		return LayoutMode.PHONE_LANDSCAPE
	return LayoutMode.PHONE_PORTRAIT

static func is_phone(mode: int) -> bool:
	return mode == LayoutMode.PHONE_LANDSCAPE or mode == LayoutMode.PHONE_PORTRAIT

static func is_desktop(mode: int) -> bool:
	return mode == LayoutMode.DESKTOP

static func outer_padding(mode: int, view: Vector2) -> int:
	match mode:
		LayoutMode.DESKTOP:
			return int(clampf(minf(view.x, view.y) * 0.025, 20.0, 36.0))
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return int(clampf(minf(view.x, view.y) * 0.022, 14.0, 26.0))
		LayoutMode.PHONE_LANDSCAPE:
			return 8
		_:
			return int(clampf(view.x * 0.028, 9.0, 14.0))

static func page_separation(mode: int) -> int:
	match mode:
		LayoutMode.DESKTOP:
			return 14
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return 11
		LayoutMode.PHONE_LANDSCAPE:
			return 7
		_:
			return 8

## ── Typography ───────────────────────────────────────────────────────────

static func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## The small gold caption above a section, like the setup screen's kickers.
static func make_kicker(text: String, font_size: int) -> Label:
	var kicker := make_label(text, font_size, COLOR_GOLD)
	kicker.add_theme_font_override("font", SUBTITLE_FONT)
	kicker.uppercase = true
	return kicker

## A heading in the bold weight: the screen title, a location's name, a
## big count.
static func make_title_label(text: String, font_size: int, color: Color = COLOR_TEXT_BRIGHT) -> Label:
	var title := make_label(text, font_size, color)
	title.add_theme_font_override("font", TITLE_FONT)
	return title

## A name or button-sized line in the semibold weight.
static func make_semibold_label(text: String, font_size: int, color: Color = COLOR_TEXT_BRIGHT) -> Label:
	var label := make_label(text, font_size, color)
	label.add_theme_font_override("font", SUBTITLE_FONT)
	return label

## ── Surfaces ─────────────────────────────────────────────────────────────

## Panels wear the same notched nine-patch pixel frame as the title and
## setup screens: straight edges, ink outline, accent trim.
static func make_panel(bg: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		PixelButtonStyle.panel_style(border, bg, 0, 0))
	return panel

static func make_inset_panel() -> PanelContainer:
	return make_panel(COLOR_SURFACE_INSET, MenuStyle.with_alpha(COLOR_BORDER_SOFT, 0.5))

## A padded panel: surface on the outside, margins around `inner`.
static func padded_panel(bg: Color, border: Color, pad: int, inner: Control) -> PanelContainer:
	var panel := make_panel(bg, border)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, pad)
	margin.add_child(inner)
	panel.add_child(margin)
	return panel

## Paint a small menu action (Back, switch screens, filter toggles): a pixel
## card with the semibold type.
static func paint_utility_button(button: Button, gold: bool) -> void:
	var accent := COLOR_GOLD if gold else MenuStyle.ACCENT_UTILITY
	PixelButtonStyle.paint_card(button, accent, 0.0, 8, UIConstants.COLOR_TEXT, COLOR_TEXT_BRIGHT)
	button.add_theme_font_override("font", SUBTITLE_FONT)
	button.add_theme_color_override("font_pressed_color", UIConstants.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)

## Paint a destructive action (Delete, Quit, Confirm delete): the same pixel
## card as the utility buttons, with the danger red as its trim.
static func paint_danger_button(button: Button) -> void:
	PixelButtonStyle.paint_card(button, UIConstants.COLOR_DANGER, 0.0, 8,
		UIConstants.COLOR_TEXT, COLOR_TEXT_BRIGHT)
	button.add_theme_font_override("font", SUBTITLE_FONT)
	button.add_theme_color_override("font_pressed_color", UIConstants.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)

## Paint a selectable toggle (segmented switch, filter chip, location chip):
## quiet until pressed, when the frame sinks and lights its trim.
static func paint_toggle(button: Button, accent: Color = COLOR_MINT) -> void:
	PixelButtonStyle.paint_choice(button, accent)
	button.add_theme_font_override("font", SUBTITLE_FONT)
	button.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_BRIGHT)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_BRIGHT)
	button.add_theme_color_override("font_hover_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## Paint a screen's action button. `primary` is the gold slab with dark ink
## type (the one call to action on a screen); otherwise a quiet green card.
static func paint_action(button: Button, primary: bool) -> void:
	if primary:
		PixelButtonStyle.paint_primary(button)
		button.add_theme_font_override("font", TITLE_FONT)
	else:
		PixelButtonStyle.paint_card(button, COLOR_MINT, 0.0, 7,
			COLOR_TEXT_BRIGHT, COLOR_TEXT_BRIGHT)
		button.add_theme_font_override("font", SUBTITLE_FONT)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_QUIET)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## A small filled chip (status stamps: Day 12, +$300, LOCKED).
static func make_chip(text: String, fill: Color, text_color: Color, font_size: int = 10) -> Label:
	var chip := make_label(text, font_size, text_color)
	chip.add_theme_font_override("font", SUBTITLE_FONT)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_theme_stylebox_override("normal", MenuStyle.flat(
		MenuStyle.with_alpha(fill, 0.30), MenuStyle.with_alpha(fill, 0.85), 1, 3, 7, 2, 2))
	return chip

## ── Sprites and bars ─────────────────────────────────────────────────────

## One of the menu sprites (PixelIcon), nearest-filtered so its pixels stay
## hard at whatever size the layout asks for.
static func make_sprite(kind: int, side: int, accent: Color, dimmed: bool = false) -> TextureRect:
	var grid_side := PixelIcon.snapped_side(side)
	var sprite := TextureRect.new()
	sprite.texture = PixelIcon.texture(kind, grid_side, accent, dimmed)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(grid_side, grid_side)
	sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sprite

## A slim pixel progress bar: dark inset track, accent fill snapped to
## whole pixels, drawn (not themed) so it reads the same at every size.
class PixelBar extends Control:
	var fraction: float = 0.0
	var accent: Color = MenuStyle.ACCENT_PRIMARY
	var bar_height: float = 8.0

	func _init(p_fraction: float = 0.0, p_accent: Color = MenuStyle.ACCENT_PRIMARY,
			p_height: float = 8.0) -> void:
		fraction = p_fraction
		accent = p_accent
		bar_height = p_height
		custom_minimum_size = Vector2(40.0, bar_height)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func set_fraction(value: float) -> void:
		fraction = clampf(value, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := minf(size.y, bar_height)
		if w <= 2.0 or h <= 1.0:
			return
		var y := (size.y - h) * 0.5
		draw_rect(Rect2(0, y, w, h), MenuStyle.with_alpha(COLOR_SURFACE_INSET, 1.0))
		# Chunky two-pixel frame: ink outline with a lit top edge.
		draw_rect(Rect2(0, y, w, h), Color(0.02, 0.05, 0.04, 0.9), false, 1.0)
		var fill_w := floorf(w * fraction)
		if fill_w >= 1.0:
			draw_rect(Rect2(1, y + 1, maxf(fill_w - 2.0, 1.0), h - 2.0), accent)
			draw_rect(Rect2(1, y + 1, maxf(fill_w - 2.0, 1.0), 1.0),
				MenuStyle.with_alpha(accent.lightened(0.35), 0.9))

static func make_progress_bar(fraction: float, accent: Color, bar_height: float = 8.0) -> PixelBar:
	return PixelBar.new(clampf(fraction, 0.0, 1.0), accent, bar_height)

## ── Screen header (every fullscreen screen wears this one) ──────────────

## Layout predicates. Screens branch on these instead of comparing against
## their own copies of the breakpoint enum.
static func is_tablet(mode: int) -> bool:
	return mode == LayoutMode.TABLET_LANDSCAPE or mode == LayoutMode.TABLET_PORTRAIT

## Phones in either orientation: the compact layouts that drop subtitles and
## shorten captions.
static func is_compact(mode: int) -> bool:
	return is_phone(mode)

## The Back button every screen puts at the top left. One label, one size per
## layout mode, one semibold pixel card. Returns to the screen behind it.
static func make_back_button(mode: int, on_back: Callable) -> Button:
	var compact := is_compact(mode)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "‹  Back" if not compact else "‹ Back"
	back.tooltip_text = "Return to the previous screen (Esc)"
	back.custom_minimum_size = Vector2(94.0 if not compact else 74.0,
		40.0 if mode == LayoutMode.PHONE_LANDSCAPE else 44.0)
	back.add_theme_font_size_override("font_size", 15 if not compact else 14)
	paint_utility_button(back, false)
	if on_back.is_valid():
		back.pressed.connect(on_back)
	return back

## The flag mark that stands beside every screen title, sized for the layout.
static func make_flag_mark(mode: int) -> MenuFlagMark:
	var mark := MenuFlagMark.new()
	mark.name = "FlagMark"
	mark.mark_size = _header_metrics(mode)["mark"]
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return mark

## Sizes shared by every header: the bar height, the title and kicker type,
## and the flag mark. Phone landscape is the tightest, so it drops the
## subtitle and keeps the kicker.
static func _header_metrics(mode: int) -> Dictionary:
	match mode:
		LayoutMode.DESKTOP:
			return {"height": 62.0, "title": 26, "kicker": 11, "subtitle": 13, "mark": 29.0, "gap": 10}
		LayoutMode.TABLET_LANDSCAPE, LayoutMode.TABLET_PORTRAIT:
			return {"height": 56.0, "title": 23, "kicker": 10, "subtitle": 12, "mark": 26.0, "gap": 9}
		LayoutMode.PHONE_LANDSCAPE:
			return {"height": 42.0, "title": 18, "kicker": 9, "subtitle": 11, "mark": 20.0, "gap": 7}
		_:
			return {"height": 50.0, "title": 21, "kicker": 10, "subtitle": 11, "mark": 24.0, "gap": 8}

## The header bar: Back, the flag mark, a gold kicker over the bold title with
## an optional quiet subtitle, and an optional `trailing` control pinned to the
## right (a treasury chip, a switch, a tab row). Node names are fixed so tests
## and callers can find the parts: "ScreenHeader", "BackButton", "FlagMark",
## "TitleBlock", "Kicker", "Title", "Subtitle" and "Trailing".
static func make_screen_header(mode: int, title_text: String, kicker_text: String = "",
		subtitle_text: String = "", on_back: Callable = Callable(),
		trailing: Control = null) -> HBoxContainer:
	var metrics := _header_metrics(mode)
	var header := HBoxContainer.new()
	header.name = "ScreenHeader"
	header.add_theme_constant_override("separation", int(metrics["gap"]))
	header.custom_minimum_size.y = float(metrics["height"])
	header.add_child(make_back_button(mode, on_back))
	header.add_child(make_flag_mark(mode))

	var title_block := VBoxContainer.new()
	title_block.name = "TitleBlock"
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.alignment = BoxContainer.ALIGNMENT_CENTER
	title_block.add_theme_constant_override("separation", 0)
	if not kicker_text.is_empty():
		var kicker := make_kicker(kicker_text, int(metrics["kicker"]))
		kicker.name = "Kicker"
		kicker.clip_text = true
		title_block.add_child(kicker)
	var title := make_title_label(title_text, int(metrics["title"]))
	title.name = "Title"
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_block.add_child(title)
	# Phone landscape has no room for the subtitle, so it is only built where
	# it is shown: a label left out of the tree is never freed.
	if not subtitle_text.is_empty() and mode != LayoutMode.PHONE_LANDSCAPE:
		var subtitle := make_label(subtitle_text, int(metrics["subtitle"]), COLOR_TEXT_SECONDARY)
		subtitle.name = "Subtitle"
		subtitle.clip_text = true
		title_block.add_child(subtitle)
	header.add_child(title_block)

	if trailing != null:
		trailing.name = "Trailing"
		trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(trailing)
	return header

## ── Shared header pieces ─────────────────────────────────────────────────

static func window_size_of(control: Control) -> Vector2:
	if control.is_inside_tree() and control.get_viewport() != null:
		return control.get_viewport().get_visible_rect().size
	if control.has_node("/root/Screen"):
		return control.get_node("/root/Screen").window_size
	return Vector2(1600.0, 1000.0)

## "12 / 19" style count in the bold face, for the big stat numbers.
static func make_count_label(done: int, total: int, font_size: int, color: Color = COLOR_GOLD) -> Label:
	return make_title_label("%d / %d" % [done, total], font_size, color)

static func format_money(amount: int) -> String:
	var digits := str(absi(int(amount)))
	var out := "$" if amount >= 0 else "-$"
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out

static func format_money_compact(amount: int) -> String:
	if absi(amount) >= 1000000:
		return "$%.1fM" % (float(amount) / 1000000.0)
	if absi(amount) >= 1000:
		return "$%dK" % floori(float(amount) / 1000.0)
	return format_money(amount)

static func format_counter(counter: String, value: int) -> String:
	match counter:
		"revenue":
			return format_money_compact(value)
		_:
			return str(value)

## ── Goal track navigation ────────────────────────────────────────────────

## The short name a track switch segment wears.
static func track_label(track: int) -> String:
	match track:
		GoalTrack.COURSE:
			return "Course"
		GoalTrack.WORLD:
			return "World"
		_:
			return "Achievements"

## The full screen title behind that segment.
static func track_title(track: int) -> String:
	match track:
		GoalTrack.COURSE:
			return "Course Milestones"
		GoalTrack.WORLD:
			return "World Milestones"
		_:
			return "Achievements"

## The three-way switch shared by the goal screens: one tap to another
## track, with the current one held down. `on_select` receives the track
## number of the segment pressed (never the current one).
static func make_track_switch(current_track: int, on_select: Callable) -> Control:
	var switch := HBoxContainer.new()
	switch.name = "TrackSwitch"
	switch.add_theme_constant_override("separation", 6)
	switch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	for track in [GoalTrack.COURSE, GoalTrack.WORLD, GoalTrack.ACHIEVEMENTS]:
		var button := Button.new()
		button.name = "Track_%s" % track_label(track).to_lower()
		button.text = track_label(track)
		button.tooltip_text = track_title(track)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = track == current_track
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38.0
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		paint_toggle(button, COLOR_MINT if track != GoalTrack.ACHIEVEMENTS else COLOR_GOLD)
		button.pressed.connect(func():
			if track != current_track:
				on_select.call(track))
		switch.add_child(button)
	return switch

## ── Milestone groups and cards (shared by the two milestone screens) ─────

## Bucket defs into category groups in reading order. `completed` maps id ->
## completion day; each entry remembers whether it is done and when.
static func group_entries_by_category(defs: Array, completed: Dictionary) -> Array:
	var by_category: Dictionary = {}
	for m in defs:
		var entry := {
			"milestone": m,
			"done": completed.has(m.id),
			"day": int(completed.get(m.id, 0)),
		}
		if not by_category.has(m.category):
			by_category[m.category] = []
		by_category[m.category].append(entry)
	var categories: Array = by_category.keys()
	categories.sort_custom(func(a: int, b: int) -> bool:
		return MilestoneSystem.get_category_order(a) < MilestoneSystem.get_category_order(b))
	var groups: Array = []
	for category in categories:
		groups.append({"category": category, "entries": by_category[category]})
	return groups

## Lay category groups into `columns` vertical ledgers balanced by entry
## count, so no column runs away with the whole list. `card_factory` builds
## one card per entry (entry, accent colour, compact).
static func build_category_columns(groups: Array, columns: int, card_factory: Callable,
		empty_note: String = "") -> Control:
	var row := HBoxContainer.new()
	row.name = "LedgerColumns"
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column_boxes: Array = []
	var heights: Array = []
	for i in columns:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 12)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		column_boxes.append(column)
		heights.append(0)
	for group in groups:
		var lightest := 0
		for i in range(1, columns):
			if heights[i] < heights[lightest]:
				lightest = i
		(column_boxes[lightest] as VBoxContainer).add_child(
			_build_category_group(group, columns > 1, card_factory))
		heights[lightest] += 30 + (group["entries"] as Array).size() * 92
	if groups.is_empty():
		var note := make_label(empty_note, 12, COLOR_TEXT_QUIET)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(column_boxes[0] as VBoxContainer).add_child(note)
	return row

static func _build_category_group(group: Dictionary, compact: bool,
		card_factory: Callable) -> Control:
	var box := VBoxContainer.new()
	box.name = "Category_%s" % str(group["category"])
	box.add_theme_constant_override("separation", 7)
	var color := MilestoneSystem.get_category_color(int(group["category"]))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var heading := make_kicker(MilestoneSystem.get_category_name(int(group["category"])), 11)
	heading.add_theme_color_override("font_color", color)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var entries: Array = group["entries"]
	var done_count := 0
	for entry in entries:
		if entry["done"]:
			done_count += 1
	head.add_child(make_label("%d/%d" % [done_count, entries.size()], 11, COLOR_TEXT_QUIET))
	box.add_child(head)
	for entry in entries:
		box.add_child(card_factory.call(entry, color, compact))
	return box

## One milestone card: status stamp, title, what it takes, and its reward.
## Gold-framed with its completion day when done; accent-framed and "In
## progress" when not.
static func make_milestone_card(entry: Dictionary, accent: Color, compact: bool) -> Control:
	var m: MilestoneSystem.Milestone = entry["milestone"]
	var done := bool(entry["done"])
	var card := make_panel(
		COLOR_SURFACE_RAISED if not done else MenuStyle.with_alpha(COLOR_GOLD, 0.16),
		MenuStyle.with_alpha(COLOR_GOLD if done else accent, 0.85 if done else 0.45))
	card.name = "Milestone_%s" % m.id
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var icon := make_sprite(
		PixelIcon.Kind.TROPHY if done else PixelIcon.Kind.STAR,
		18 if compact else 22,
		COLOR_GOLD if done else MenuStyle.ACCENT_UTILITY, not done)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(icon)
	var title := make_semibold_label(m.title, 13 if compact else 14,
		COLOR_TEXT_BRIGHT if done else COLOR_TEXT_SECONDARY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	top.add_child(title)
	var stamp := make_chip(("Day %d" % int(entry["day"])) if done else "In progress",
		COLOR_GOLD if done else accent,
		UIConstants.COLOR_TEXT if done else COLOR_TEXT_QUIET, 10)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(stamp)
	stack.add_child(top)

	var desc := make_label(m.description, 11, COLOR_TEXT_QUIET)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(desc)

	var reward_text := milestone_reward_text(m)
	if not reward_text.is_empty():
		stack.add_child(make_label(reward_text, 10,
			COLOR_MINT if done else COLOR_TEXT_QUIET))
	return card

static func milestone_reward_text(m: MilestoneSystem.Milestone) -> String:
	var parts: Array = []
	if m.reward_money > 0:
		parts.append("Reward: %s" % format_money(m.reward_money))
	if m.reward_reputation > 0.0:
		parts.append("+%.0f reputation" % m.reward_reputation)
	return "   ".join(parts)
