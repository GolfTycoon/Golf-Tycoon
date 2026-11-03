extends Control
class_name TournamentCoursePreview
## TournamentCoursePreview — Top-down map of a tournament course (default or
## Career-saved), drawn in theme colours with tee markers, fairways, greens,
## water hazards, and numbered flags.

const FONT_BOLD := preload("res://assets/fonts/PixelifySans-Bold.ttf")

var _holes: Array[Dictionary] = []
var _theme_type: int = CourseTheme.Type.PARKLAND

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(180.0, 96.0)

func set_course_entry(entry: Dictionary) -> void:
	_theme_type = int(entry.get("theme", CourseTheme.Type.PARKLAND))
	_holes.clear()
	var raw_holes: Variant = entry.get("preview_holes", [])
	if raw_holes is Array:
		for item in raw_holes:
			if item is Dictionary:
				_holes.append(item as Dictionary)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 24.0 or h < 24.0:
		return

	var colors: Dictionary = CourseTheme.get_terrain_colors(_theme_type)
	var grass: Color = colors.get("grass", Color("3d6e2e"))
	var rough: Color = colors.get("rough", grass.darkened(0.14))
	var fairway: Color = colors.get("fairway", Color("5fb44b"))
	var green_col: Color = colors.get("green", Color("7fe066"))
	var tee_col: Color = colors.get("tee_box", Color("6bc256"))
	var water_col: Color = colors.get("water", Color("3377b8"))

	# Recessed map bed & turf canvas
	draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.INSET_BG)
	var turf := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	draw_rect(turf, grass.darkened(0.26))
	draw_rect(turf.grow(-3.0), rough.darkened(0.16))

	# Subtle surveyor grid lines
	var grid_col := Color(1.0, 1.0, 1.0, 0.04)
	for gx in range(1, 5):
		var px := turf.position.x + turf.size.x * (float(gx) / 5.0)
		draw_line(Vector2(px, turf.position.y), Vector2(px, turf.end.y), grid_col, 1.0)
	for gy in range(1, 4):
		var py := turf.position.y + turf.size.y * (float(gy) / 4.0)
		draw_line(Vector2(turf.position.x, py), Vector2(turf.end.x, py), grid_col, 1.0)

	if _holes.is_empty():
		_draw_border()
		return

	# Compute bounding box of all tees, greens, and water hazards
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for hole in _holes:
		var tee := Vector2(hole.get("tee", Vector2i(64, 64)))
		var grn := Vector2(hole.get("green", Vector2i(68, 64)))
		min_pt.x = minf(min_pt.x, minf(tee.x, grn.x))
		min_pt.y = minf(min_pt.y, minf(tee.y, grn.y))
		max_pt.x = maxf(max_pt.x, maxf(tee.x, grn.x))
		max_pt.y = maxf(max_pt.y, maxf(tee.y, grn.y))
		var water: Vector2i = hole.get("water", Vector2i(-1, -1))
		if water.x >= 0:
			min_pt.x = minf(min_pt.x, float(water.x) - 2.0)
			min_pt.y = minf(min_pt.y, float(water.y) - 2.0)
			max_pt.x = maxf(max_pt.x, float(water.x) + 2.0)
			max_pt.y = maxf(max_pt.y, float(water.y) + 2.0)

	var span := (max_pt - min_pt).max(Vector2(12.0, 12.0))
	var pad := Vector2(12.0, 10.0)
	var inner := size - pad * 2.0
	var scale_px := minf(inner.x / (span.x + 6.0), inner.y / (span.y + 6.0))
	var world_mid := (min_pt + max_pt) * 0.5
	var center_px := size * 0.5

	# Pass 1: Water hazards
	for hole in _holes:
		var water: Vector2i = hole.get("water", Vector2i(-1, -1))
		if water.x >= 0:
			var wp := center_px + (Vector2(water) - world_mid) * scale_px
			var wr := maxf(3.0, 2.2 * scale_px)
			draw_circle(wp, wr + 1.0, water_col.darkened(0.32))
			draw_circle(wp, wr, water_col)

	# Pass 2: Fairway corridors
	for hole in _holes:
		var p_tee := center_px + (Vector2(hole.get("tee", Vector2i(64, 64))) - world_mid) * scale_px
		var p_grn := center_px + (Vector2(hole.get("green", Vector2i(68, 64))) - world_mid) * scale_px
		var par := int(hole.get("par", 4))
		var fw_w := clampf((3.2 if par == 3 else 4.8) * scale_px * 0.45, 2.5, 8.5)
		draw_line(p_tee, p_grn, fairway.darkened(0.28), fw_w + 2.0)
		draw_line(p_tee, p_grn, fairway, fw_w)

	# Pass 3: Greens, tees, flags, and hole numbers
	var show_numbers := _holes.size() <= 9 and h >= 84.0
	for idx in range(_holes.size()):
		var hole := _holes[idx]
		var p_tee := center_px + (Vector2(hole.get("tee", Vector2i(64, 64))) - world_mid) * scale_px
		var p_grn := center_px + (Vector2(hole.get("green", Vector2i(68, 64))) - world_mid) * scale_px

		var grn_r := clampf(2.2 * scale_px * 0.55, 2.8, 6.0)
		draw_circle(p_grn, grn_r + 1.0, fairway.darkened(0.32))
		draw_circle(p_grn, grn_r, green_col)

		var tee_sz := Vector2(3.0, 3.0)
		draw_rect(Rect2((p_tee - tee_sz * 0.5).round(), tee_sz), tee_col.lightened(0.18))

		var pole_base := p_grn.round()
		var pole_top := pole_base + Vector2(0.0, -6.0)
		draw_line(pole_base, pole_top, Color(0.95, 0.94, 0.88), 1.0)
		var flag_col := Color("e45a4f") if idx == 0 or idx == _holes.size() - 1 else Color("f0cf62")
		draw_rect(Rect2(pole_top, Vector2(4.0, 3.0)), flag_col)

		if show_numbers:
			draw_string(
				FONT_BOLD,
				pole_base + Vector2(3.0, 3.0),
				str(idx + 1),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				Color(1.0, 0.97, 0.88, 0.90)
			)

	_draw_border()

func _draw_border() -> void:
	var w := size.x
	var h := size.y
	var border_dark := Color(0.0, 0.0, 0.0, 0.55)
	var border_light := MenuStyle.with_alpha(MenuStyle.ACCENT_UTILITY, 0.38)
	draw_rect(Rect2(0.0, 0.0, w, 1.0), border_dark)
	draw_rect(Rect2(0.0, h - 1.0, w, 1.0), border_light)
	draw_rect(Rect2(0.0, 0.0, 1.0, h), border_dark)
	draw_rect(Rect2(w - 1.0, 0.0, 1.0, h), border_light)
