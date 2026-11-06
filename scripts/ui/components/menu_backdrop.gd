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
## The menus put cream text and dark translucent cards over this. The cards
## carry their own opacity; the picture itself gets nothing extra here. The
## dark bands the headings and the version line used to sit on are the
## **Edge Scrim** overlay, so they are a choice like any other pattern - a
## player who wants the bare art picks None.
##
## The overlay is painted over the picture, by MenuBackdropOverlay, from the
## entry the player chose (or Auto resolved). It is the only layer between the
## art and the menu's own cards.
##
## Both are resolved when the backdrop is built and re-resolved when
## Backdrops.backdrop_changed fires (the player changed the setting on the
## Settings page behind this screen). No node has to know about styles.

## The style and overlay currently worn - the dictionaries Backdrops resolved.
var background: Dictionary = {}
var overlay: Dictionary = {}

var _texture: Texture2D = null
## The parts of the resolved style drawing needs, kept as plain values so a
## repaint never walks the catalogue again. (The picture itself is cached by
## the Backdrops autoload.)
var _tint: Color = Color.WHITE


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
		return
	background = Backdrops.resolve_background()
	overlay = Backdrops.resolve_overlay()
	_texture = background.get("texture", null) as Texture2D
	_tint = background.get("tint", Color.WHITE) as Color


func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	_draw_background(s)
	_draw_overlay(s)


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
