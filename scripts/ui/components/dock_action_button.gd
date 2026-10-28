extends ToolButton
class_name DockActionButton
## Management shortcuts use the same pixel frame as the title-screen cards.
var glyph := "maps"
## The section whose colour frames the card. Every dock action now lives in
## the Manage section, so all of them wear its green.
var accent_section: int = TerrainToolbar.Section.MANAGE
## Unread count shown as a gold badge in the card's top-right corner. Only
## the Club tab's Feed card carries one; every other card leaves it at zero.
var notification_count := 0:
	set(value):
		if notification_count != value:
			notification_count = value
			queue_redraw()

func _create_styles() -> void:
	pass

func _apply_styles() -> void:
	PixelButtonStyle.paint_primary(self, TerrainToolbar.SECTION_COLORS[accent_section])
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)

func _update_button() -> void:
	super()
	custom_minimum_size = Vector2(150, 116)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accessibility_name = tool_name
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _draw() -> void:
	var pixels: Array = PixelCircleButton.ICONS.get(glyph, PixelCircleButton.ICONS["maps"])
	var origin := Vector2(floorf((size.x - 27) * 0.5), 20)
	for y in pixels.size():
		for x in pixels[y].length():
			if pixels[y][x] == "x":
				draw_rect(Rect2(origin + Vector2(x, y) * 3, Vector2(3, 3)), PixelCircleButton.CREAM)
	var lines := tool_name.replace("Financial Overview", "Financial\nOverview").split("\n")
	for i in lines.size():
		var width := PixelCircleButton.FONT.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(PixelCircleButton.FONT, Vector2(floorf((size.x - width) * 0.5), 73 + i * 17), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PixelCircleButton.CREAM)
	if not hotkey.is_empty():
		draw_string(PixelCircleButton.FONT, Vector2(size.x - 22, size.y - 12), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9da987"))
	if notification_count > 0:
		var badge_text := str(notification_count) if notification_count <= 99 else "99+"
		var text_width := PixelCircleButton.FONT.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var badge := Rect2(size.x - text_width - 16, 8, text_width + 8, 16)
		draw_rect(badge, Color("e5bd66"))
		draw_string(PixelCircleButton.FONT, badge.position + Vector2(4, 13), badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelCircleButton.INK)
