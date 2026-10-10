extends Control
class_name MenuBackdrop
## The shared background of the out-of-game menu screens: the title screen,
## Start New Game, the World Map and the Golfer Skin studio all sit on the
## same artwork, `assets/ui/background.jpeg`.
##
## The image is drawn "cover": scaled up just enough that both dimensions of
## the window are filled and centred, so a portrait phone and a 2560px desktop
## both see the whole scene without letterbox bars - the longer dimension is
## simply cropped.
##
## The menus put cream text and dark translucent cards over this (see
## MenuStyle), and the artwork is bright daylight. A dark scrim along the top
## and bottom edges keeps the heading and the version line readable wherever
## the window is a different shape; the cards carry their own opacity.

const BACKGROUND_TEXTURE: Texture2D = preload("res://assets/ui/background.jpeg")

## Bands used for the edge scrims.
const SCRIM_BANDS := 14
const EDGE_COLOR := Color(0.0, 0.02, 0.01)
## Alpha of the scrim at the very top / bottom edge.
const EDGE_ALPHA := 0.45

func _init() -> void:
	# The menu sits on top of the backdrop: never swallow a click.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	_draw_background(s)
	_draw_edge_scrim(s)

## The artwork, scaled to cover the whole control and centred so the overflow
## crops evenly on both sides (or top and bottom on a portrait window).
func _draw_background(s: Vector2) -> void:
	var tex_size := BACKGROUND_TEXTURE.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var cover_scale := maxf(s.x / tex_size.x, s.y / tex_size.y)
	var drawn := tex_size * cover_scale
	draw_texture_rect(BACKGROUND_TEXTURE, Rect2((s - drawn) * 0.5, drawn), false)

## Darken the top and bottom edges so the title text and the version line have
## something to sit on wherever the window is a different shape.
func _draw_edge_scrim(s: Vector2) -> void:
	var band_h := s.y * 0.12 / float(SCRIM_BANDS)
	for i in SCRIM_BANDS:
		var t := 1.0 - float(i) / float(SCRIM_BANDS)
		var alpha := EDGE_ALPHA * t * t
		draw_rect(Rect2(0.0, band_h * float(i), s.x, band_h + 1.0),
			Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, alpha))
		draw_rect(Rect2(0.0, s.y - band_h * float(i + 1), s.x, band_h + 1.0),
			Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, alpha))
