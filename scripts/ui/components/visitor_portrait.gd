extends Control
class_name VisitorPortrait
## Snapshot of the same recoloured skin sprite used by the on-course golfer.
##
## The register's plate draws it small at 36x40; the profile's identity card
## gives it a much larger recessed well. `set_display_size` chooses the box,
## and the sprite is always fitted to it at whole-pixel scale, so the pixel art
## stays crisp at both sizes. With `show_backdrop` off the control is just the
## golfer on whatever frame its parent supplies, and `ground_shadow` lays a
## soft pixel pool under their feet.

## The box the sprite is fitted into. The default is the register plate's own
## footprint; the profile asks for a larger one.
var display_size := Vector2(36, 40)
## The dark card and ground line the small plate used to paint behind the
## golfer. The profile's inset well already supplies a surface, so it turns
## this off.
var show_backdrop := true
## A soft pixel shadow pooled under the golfer's feet.
var ground_shadow := false

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
	custom_minimum_size = display_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Re-box the sprite (call before the control enters the tree, or let _ready
## pick it up on the next layout).
func set_display_size(value: Vector2) -> void:
	display_size = value.max(Vector2(1, 1))
	custom_minimum_size = display_size
	if is_inside_tree():
		queue_redraw()

func _draw() -> void:
	if show_backdrop:
		draw_rect(Rect2(0, 0, 36, 40), Color("142c30"))
		draw_rect(Rect2(4, 34, 28, 3), Color("254a43"))
	if texture == null:
		return
	var source := texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var scale_factor := minf(display_size.x / source.x, display_size.y / source.y)
	# Use whole-pixel scaling wherever the source art fits at native size.
	if scale_factor >= 1.0:
		scale_factor = floorf(scale_factor)
	var drawn_size := source * scale_factor
	var drawn_origin := ((display_size - drawn_size) / 2.0).floor()
	if ground_shadow:
		_draw_ground_shadow(drawn_origin, drawn_size)
	draw_texture_rect(texture, Rect2(drawn_origin, drawn_size), false)

## A pixel pool of shadow just under the golfer: five flat rows, widest in the
## middle, in the same near-black green the dock's frames are inked with.
func _draw_ground_shadow(origin: Vector2, drawn: Vector2) -> void:
	var width := drawn.x * 0.72
	var centre := origin.x + drawn.x * 0.5
	var bottom := origin.y + drawn.y - 3.0
	var widths := [0.42, 0.76, 1.0, 0.72, 0.34]
	for row in widths.size():
		var row_width := width * float(widths[row])
		draw_rect(Rect2(floorf(centre - row_width * 0.5), bottom + float(row),
			ceilf(row_width), 1.0), Color(0.015, 0.06, 0.05, 0.55 - float(row) * 0.07))
