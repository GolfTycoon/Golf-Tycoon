extends ToolButton
class_name DockActionButton
## Compact management tickets with a pixel icon and a left-aligned label.
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
	PixelButtonStyle.paint_card(self, TerrainToolbar.SECTION_COLORS[accent_section], 0, 0,
		PixelCircleButton.CREAM, PixelCircleButton.CREAM)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)

func _update_button() -> void:
	super()
	text = tool_name # Keep the accessible native label, without a shortcut suffix.
	custom_minimum_size = Vector2(216, 54)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accessibility_name = tool_name
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

# Management tickets do not advertise shortcut text, including in tooltips.
# The bindings themselves remain registered independently by the game.
func _on_mouse_entered() -> void:
	if not has_node("/root/TooltipManager"):
		return
	var tm = get_node("/root/TooltipManager")
	tm.show_tooltip({"title": tool_name, "description": tool_description,
		"cost": cost, "maintenance": maintenance, "shortcut": ""}, self)

func _draw() -> void:
	# A recessed icon well makes each action read like a clubhouse wayfinding
	# ticket, while the shared frame supplies hover/focus.
	var well := Rect2(10, floorf((size.y - 34) * 0.5), 34, 34)
	draw_rect(well, Color("102c23"))
	var pixels: Array = PixelCircleButton.ICONS.get(glyph, PixelCircleButton.ICONS["maps"])
	var origin := well.position + Vector2(5, 4)
	for y in pixels.size():
		for x in pixels[y].length():
			if pixels[y][x] == "x":
				draw_rect(Rect2(origin + Vector2(x, y) * 3, Vector2(3, 3)), PixelCircleButton.CREAM)
	var font_size := 16
	var baseline := floorf((size.y - PixelCircleButton.FONT.get_height(font_size)) * 0.5) \
		+ PixelCircleButton.FONT.get_ascent(font_size)
	draw_string(PixelCircleButton.FONT, Vector2(52, baseline), tool_name,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 62, font_size, PixelCircleButton.CREAM)
	if notification_count > 0:
		var badge_text := str(notification_count) if notification_count <= 99 else "99+"
		var text_width := PixelCircleButton.FONT.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var badge := Rect2(size.x - text_width - 16, floorf((size.y - 16) * 0.5), text_width + 8, 16)
		draw_rect(badge, Color("e5bd66"))
		draw_string(PixelCircleButton.FONT, badge.position + Vector2(4, 13), badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelCircleButton.INK)
