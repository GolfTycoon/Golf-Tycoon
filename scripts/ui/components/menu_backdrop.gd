extends Control
class_name MenuBackdrop
## The shared background of the fullscreen menu screens: the title screen,
## Start New Game, the World Map, Save / Load, Settings and the other menus
## all sit on the same backdrop, painted from whichever background style and
## overlay the player chose (Settings > Display > Background).
##
## The picture is drawn "cover": scaled up just enough that both dimensions of
## the window are filled and centred, so a portrait phone and a 2560px desktop
## both see the whole scene without letterbox bars - the longer dimension is
## simply cropped. A style's `tint` is multiplied over the picture, which is how
## a mod can restyle a shipped image without repainting it.
##
## The menus put cream text and dark translucent cards over this, and the
## artwork is bright daylight, so a dark scrim along the top and bottom edges
## keeps the heading and the version line readable wherever the window is a
## different shape (the style's `scrim` sets how deep it is). The cards carry
## their own opacity.
##
## The overlay is painted after the picture and before the scrim, by
## MenuBackdropOverlay, from the entry the player chose (or Auto resolved).
##
## Both are resolved when the backdrop is built and re-resolved when
## Backdrops.backdrop_changed fires (the player changed the setting on the
## Settings page behind this screen). No node has to know about styles.

## The style and overlay currently worn - the dictionaries Backdrops resolved.
var background: Dictionary = {}
var overlay: Dictionary = {}

var _texture: Texture2D = null
## Bands used for the edge scrims.
const SCRIM_BANDS := 14
const EDGE_COLOR := Color(0.0, 0.02, 0.01)
## Alpha of the scrim at the very top / bottom edge when a style asks for none.
const DEFAULT_SCRIM_ALPHA := 0.45
## The parts of the resolved style drawing needs, kept as plain values so a
## repaint never walks the catalogue again. (The picture itself is cached by
## the Backdrops autoload.)
var _tint: Color = Color.WHITE
var _scrim_alpha: float = DEFAULT_SCRIM_ALPHA


func _init() -> void:
	# The menu sits on top of the backdrop: never swallow a click.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	_apply_style()


func _ready() -> void:
	if is_instance_valid(Backdrops) and not Backdrops.backdrop_changed.is_connected(_on_backdrop_changed):
		Backdrops.backdrop_changed.connect(_on_backdrop_changed)
	_apply_style()


func _exit_tree() -> void:
	if is_instance_valid(Backdrops) and Backdrops.backdrop_changed.is_connected(_on_backdrop_changed):
		Backdrops.backdrop_changed.disconnect(_on_backdrop_changed)


## Re-read what the menus should wear now (the player changed a setting, or the
## resolved style fell back to something else) and repaint.
func refresh_style() -> void:
	_apply_style()
	queue_redraw()


func _on_backdrop_changed() -> void:
	refresh_style()


## Ask Backdrops what this opening should wear and remember the parts drawing
## needs. Cheap lives on the resolved dictionaries; the texture comes from the
## autoload's cache.
func _apply_style() -> void:
	if not is_instance_valid(Backdrops):
		background = {}
		overlay = {}
		_texture = null
		_tint = Color.WHITE
		_scrim_alpha = DEFAULT_SCRIM_ALPHA
		return
	background = Backdrops.resolve_background()
	overlay = Backdrops.resolve_overlay()
	_texture = background.get("texture", null) as Texture2D
	_tint = background.get("tint", Color.WHITE) as Color
	_scrim_alpha = float(background.get("scrim", DEFAULT_SCRIM_ALPHA))


func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	_draw_background(s)
	_draw_overlay(s)
	_draw_edge_scrim(s)


## The artwork, scaled to cover the whole control and centred so the overflow
## crops evenly on both sides (or top and bottom on a portrait window).
func _draw_background(s: Vector2) -> void:
	if _texture == null:
		# No picture to decode (a mod removed, a file hand-deleted): the deep
		# clubhouse green the boot splash clears to, so the menus stay readable
		# instead of sitting on a black hole.
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.043, 0.098, 0.078))
		return
	var tex_size := _texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var cover_scale := maxf(s.x / tex_size.x, s.y / tex_size.y)
	var drawn := tex_size * cover_scale
	draw_texture_rect(_texture, Rect2((s - drawn) * 0.5, drawn), false, _tint)


## The chosen overlay, painted over the picture: a pattern in the style's own
## ink and strength (see MenuBackdropOverlay for the painters).
func _draw_overlay(s: Vector2) -> void:
	if overlay.is_empty():
		return
	var pattern: String = str(overlay.get("pattern", "none"))
	if pattern == "none":
		return
	var color: Variant = overlay.get("color", Color("06110c"))
	var ink: Color = color if color is Color else Color("06110c")
	var strength := clampf(float(overlay.get("strength", 0.2)), 0.0, 1.0)
	if strength <= 0.0:
		return
	ink.a = strength
	var settings: Variant = overlay.get("settings", {})
	MenuBackdropOverlay.draw(self, pattern, Rect2(Vector2.ZERO, s), ink,
		float(overlay.get("scale", 1.0)),
		settings if settings is Dictionary else {})


## Darken the top and bottom edges so the title text and the version line have
## something to sit on wherever the window is a different shape, and so a
## mod-supplied picture cannot wash out the heading. The style's `scrim` sets
## how deep the shading goes.
func _draw_edge_scrim(s: Vector2) -> void:
	if _scrim_alpha <= 0.0:
		return
	var band_h := s.y * 0.12 / float(SCRIM_BANDS)
	for i in SCRIM_BANDS:
		var t := 1.0 - float(i) / float(SCRIM_BANDS)
		var alpha := _scrim_alpha * t * t
		draw_rect(Rect2(0.0, band_h * float(i), s.x, band_h + 1.0),
			Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, alpha))
		draw_rect(Rect2(0.0, s.y - band_h * float(i + 1), s.x, band_h + 1.0),
			Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, alpha))
