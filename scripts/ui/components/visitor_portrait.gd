extends Control
class_name VisitorPortrait
## Snapshot of the same recoloured skin sprite used by the on-course golfer.
var texture: Texture2D

static func for_golfer(golfer: Golfer) -> Texture2D:
	var frames := GolferSkins.frames_for_golfer(golfer)
	if frames == null:
		return null
	var animation := &"idle_south"
	if not frames.has_animation(animation) or frames.get_frame_count(animation) == 0:
		for candidate in frames.get_animation_names():
			if frames.get_frame_count(candidate) > 0:
				return frames.get_frame_texture(candidate, 0)
		return null
	return frames.get_frame_texture(animation, 0)

func _ready() -> void:
	custom_minimum_size = Vector2(36, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	draw_rect(Rect2(0, 0, 36, 40), Color("142c30"))
	draw_rect(Rect2(4, 34, 28, 3), Color("254a43"))
	if texture == null:
		return
	var source := texture.get_size()
	var scale_factor := minf(32.0 / source.x, 36.0 / source.y)
	# Use whole-pixel scaling wherever the source art fits at native size.
	if scale_factor >= 1.0:
		scale_factor = floorf(scale_factor)
	var drawn_size := source * scale_factor
	draw_texture_rect(texture, Rect2(((Vector2(36, 40) - drawn_size) / 2.0).floor(), drawn_size), false)
