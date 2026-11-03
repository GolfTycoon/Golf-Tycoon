extends Control
class_name GolferPortrait
## The portrait of one Tournament Mode golfer: the golfer's own sprite, seen
## from the front, standing on a plinth.
##
## The art is the same recoloured animation frame the golfer is drawn with on
## the course (see GolferSkins), so a golfer's Skin and Skin Colours show on
## the Start Tournament screen exactly as they do when the tournament tees off.
## The frame is cropped to the pixels the golfer actually covers - the sprite
## canvas is mostly empty - and scaled in whole pixels, which keeps the art
## crisp at any panel size.
##
## A golfer whose Skin is missing (a deleted or never-shipped skin folder)
## still gets a portrait: the painted pixel emblem falls back to the Skin
## Colours the entry carries.

## The frame the portrait is drawn from: a front-facing idle pose, the same
## one a golfer standing still on the course plays.
const SPRITE_KEY: String = "idle/south/frame_000"
## Breathing room between the art and the portrait's frame, in pixels.
const FRAME_PADDING: float = 2.0
## What a portrait asks for when the caller does not size it: room for the
## 12x33 golfer sprite to be drawn at twice its pixel size.
const DEFAULT_MIN_SIZE: Vector2 = Vector2(32, 72)

## The recoloured sprite, null when the golfer's skin has no art to draw.
var sprite_texture: Texture2D = null
## Frame and plinth colour; callers tint it to match the card it sits on.
var accent_color: Color = MenuStyle.ACCENT_SECONDARY

## What the portrait is currently showing, so re-setting the same entry (which
## the screen does on every selection change) costs nothing. A sentinel, so the
## first entry - even an empty one - is always drawn.
var _entry_key: String = "<unset>"
## The part of the sprite that is the golfer rather than empty canvas.
var _source_rect: Rect2 = Rect2()
## Skin Colours for the emblem fallback: cap, hair, skin, shirt, pants.
var _emblem_colors: Dictionary = {}


func _init(entry: Dictionary = {}) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DEFAULT_MIN_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	if not entry.is_empty():
		set_from_entry(entry)


## Draw the golfer `entry` describes (a Tournament Library golfer entry, with
## `skin_id` and `skin_colors`).
func set_from_entry(entry: Dictionary) -> void:
	var key := entry_key(entry)
	if key == _entry_key:
		return
	_entry_key = key
	_emblem_colors = _emblem_colors_from(entry)
	sprite_texture = _texture_for(entry)
	_source_rect = _used_rect(sprite_texture)
	queue_redraw()


## Everything about an entry that changes how its portrait is drawn.
static func entry_key(entry: Dictionary) -> String:
	var parts := PackedStringArray([str(entry.get("skin_id", ""))])
	var raw: Variant = entry.get("skin_colors", {})
	if raw is Dictionary:
		var colors: Dictionary = raw
		var names := colors.keys()
		names.sort()
		for group_name in names:
			parts.append("%s=%s" % [str(group_name), str(colors[group_name])])
	return "|".join(parts)


## The entry's Skin in the colours it carries, or null when the skin is gone.
func _texture_for(entry: Dictionary) -> Texture2D:
	if GolferSkins == null or GolferSkins.library == null:
		return null
	var skin := GolferSkins.library.get_skin(str(entry.get("skin_id", "")))
	if skin == null:
		return null
	var overrides := TournamentLibrary.skin_color_overrides_from_entry(entry)
	var texture := GolferSkins.library.recolor_texture(skin, SPRITE_KEY, overrides)
	if texture == null:
		texture = GolferSkins.library.edited_texture(skin, SPRITE_KEY)
	return texture


## The rectangle of a sprite that holds the golfer, with the empty canvas
## around the art trimmed off.
static func _used_rect(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2(Vector2.ZERO, texture.get_size())
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2(Vector2.ZERO, texture.get_size())
	return Rect2(used)


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, MenuStyle.INSET_BG)
	draw_rect(box, MenuStyle.with_alpha(accent_color, 0.55), false, 1.0)
	# The plinth the golfer stands on.
	var ground_y := floorf(size.y - 3.0)
	draw_rect(Rect2(2.0, ground_y, maxf(size.x - 4.0, 1.0), 1.0),
		MenuStyle.with_alpha(accent_color, 0.38))

	if sprite_texture == null or _source_rect.size.x < 1.0 or _source_rect.size.y < 1.0:
		_draw_emblem()
		return

	# Whole-pixel scaling only: half-pixel steps would blur the pixel art. Art
	# larger than the portrait (a custom skin's) is instead shrunk to fit.
	var fit_width := maxf(size.x - 2.0 * FRAME_PADDING, 1.0)
	var fit_height := maxf(ground_y - FRAME_PADDING, 1.0)
	var fit_ratio := minf(fit_width / _source_rect.size.x, fit_height / _source_rect.size.y)
	var pixel_scale := fit_ratio if fit_ratio < 1.0 else floorf(fit_ratio)
	var drawn_size := _source_rect.size * pixel_scale
	var origin := Vector2(
		floorf((size.x - drawn_size.x) * 0.5),
		ground_y - drawn_size.y
	)
	draw_texture_rect_region(sprite_texture, Rect2(origin, drawn_size), _source_rect)


## A tiny golfer painted from the entry's Skin Colours, shown when the skin's
## sprite art cannot be read.
func _draw_emblem() -> void:
	var cap := _emblem_colors.get("cap", Color("f2f0e6")) as Color
	var hair := _emblem_colors.get("hair", Color("5c3a21")) as Color
	var skin := _emblem_colors.get("skin", Color("edc4a3")) as Color
	var shirt := _emblem_colors.get("shirt", Color("2e7057")) as Color
	var pants := _emblem_colors.get("pants", Color("e0dbcc")) as Color
	var ground_y := floorf(size.y - 3.0)
	var s := maxf(floorf(minf((size.x - 2.0 * FRAME_PADDING) / 13.0,
		(ground_y - FRAME_PADDING) / 14.0)), 1.0)
	var ox := floorf((size.x - 13.0 * s) * 0.5)
	var oy := ground_y - 14.0 * s
	# Cap crown + visor
	draw_rect(Rect2(ox + 3.0 * s, oy + 1.0 * s, 6.0 * s, 2.0 * s), cap)
	draw_rect(Rect2(ox + 3.0 * s, oy + 2.0 * s, 8.0 * s, 1.0 * s), cap.darkened(0.18))
	# Hair fringe + head
	draw_rect(Rect2(ox + 3.0 * s, oy + 3.0 * s, 1.5 * s, 2.5 * s), hair)
	draw_rect(Rect2(ox + 4.0 * s, oy + 3.0 * s, 5.0 * s, 3.0 * s), skin)
	# Shirt torso + collar
	draw_rect(Rect2(ox + 2.0 * s, oy + 6.0 * s, 9.0 * s, 5.0 * s), shirt)
	draw_rect(Rect2(ox + 5.0 * s, oy + 6.0 * s, 3.0 * s, 1.5 * s), cap.lightened(0.15))
	# Trousers
	draw_rect(Rect2(ox + 3.0 * s, oy + 11.0 * s, 3.0 * s, 2.5 * s), pants)
	draw_rect(Rect2(ox + 7.0 * s, oy + 11.0 * s, 3.0 * s, 2.5 * s), pants)


## The Skin Colours an entry carries, keyed the way the emblem draws them.
static func _emblem_colors_from(entry: Dictionary) -> Dictionary:
	var raw: Variant = entry.get("skin_colors", {})
	var colors: Dictionary = raw if raw is Dictionary else {}
	return {
		"cap": _color_of(colors, "Cap", Color("f2f0e6")),
		"hair": _color_of(colors, "Hair", Color("5c3a21")),
		"skin": _color_of(colors, "Skin", Color("edc4a3")),
		"shirt": _color_of(colors, "Shirt", Color("2e7057")),
		"pants": _color_of(colors, "Pants", Color("e0dbcc")),
	}


static func _color_of(colors: Dictionary, group_name: String, fallback: Color) -> Color:
	return Color.from_string(str(colors.get(group_name, "")), fallback)
