extends Node2D
class_name MenuFocusRing
## The focus ring of one menu pill, drawn as its own layer around it.
##
## PixelButtonStyle's frames are pills inset a couple of pixels inside their
## nine-patch texture, so the ring that marks keyboard and controller focus
## reaches a little past the button's own edge. Nothing that lives on a button
## can draw there: a stylebox is clipped to its control, and a stylebox's
## expand margin is decoration the pointer ignores only because the engine
## knows about it. So the ring is a separate node, laid over the button.
##
## It is a Node2D on purpose, not a Control:
##
##  * a Control child would join the button's minimum size, and its reach plus
##    padding would make every painted card a few pixels taller - which a dense
##    screen with a fixed row height cannot afford;
##  * a Control rectangle is what the engine's mouse-hit test sees, so a ring
##    drawn around a card would swallow that card's clicks.
##
## A Node2D does neither. It is drawn in the button's own coordinate space,
## sized and positioned from the button's rect every frame, and it draws only
## the ring's bands (the stylebox has draw_center off), so the card's label and
## body are never covered. PixelButtonStyle routes every painted control
## through `attach`, so a screen cannot forget to ask for one.

## How far past the button's edge the ring is drawn, in screen pixels.
const RING_REACH := 4
## Transparent rows kept around the button inside this node's drawing area, so
## the ring's ink edge is never clipped by its own bounds.
const TEXTURE_PADDING := 3

## The control this ring belongs to.
var owner_button: Control = null
## The ring stylebox, shared with the button's "focus" state.
var ring_style: StyleBoxTexture = null


## Wrap `control`'s focus highlight in its own ring layer. Safe to call on any
## control painted with PixelButtonStyle; a null ring is a no-op.
static func attach(control: Control, ring: StyleBoxTexture) -> MenuFocusRing:
	if ring == null or control == null:
		return null
	var wrapper := MenuFocusRing.new()
	wrapper.name = "FocusRing"
	wrapper.owner_button = control
	wrapper.ring_style = ring if not ring.draw_center else _bands_only(ring)
	control.add_child(wrapper)
	control.focus_entered.connect(wrapper._refresh)
	control.focus_exited.connect(wrapper._refresh)
	control.resized.connect(wrapper._refresh)
	wrapper._refresh()
	return wrapper


## A copy of `ring` that draws its bands and nothing in the middle, so a ring
## can be laid over a card without covering what is inside it.
static func _bands_only(ring: StyleBoxTexture) -> StyleBoxTexture:
	var bands := ring.duplicate() as StyleBoxTexture
	bands.draw_center = false
	return bands


func _ready() -> void:
	# A Node2D never takes part in the button's layout, so its offset can be
	# set once: everything that matters is measured from the card's own rect.
	position = Vector2(-_pad(), -_pad())
	visible = false
	_refresh()


## Transparent rows kept between the layer's own bounds and the ring's ink.
func _pad() -> float:
	return float(RING_REACH + TEXTURE_PADDING)


func _refresh() -> void:
	_follow()
	queue_redraw()


## Show the ring only while its button has focus. The ring needs no other
## upkeep: as a child of the button it already moves wherever the button moves,
## including inside a docked bar or a scrolling column, and its own offset from
## the card never changes.
func _follow() -> void:
	if owner_button == null or not is_instance_valid(owner_button):
		return
	var focused: bool = owner_button.has_focus()
	if visible != focused:
		visible = focused
		queue_redraw()


func _draw() -> void:
	if ring_style == null or owner_button == null or not is_instance_valid(owner_button):
		return
	var box := ring_box()
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	draw_style_box(ring_style, box)


## Where the ring is drawn, in its own coordinates: the box handed to the
## stylebox. Exposed so tests and tools can check it lines up with the pill.
func ring_box() -> Rect2:
	if ring_style == null or owner_button == null:
		return Rect2()
	# The stylebox's own expand margin puts the ring's outer edge exactly on
	# the pill's ink outline, RING_REACH outside the card's rect.
	var reach := ring_style.get_expand_margin(SIDE_LEFT)
	return Rect2(Vector2(_pad() - reach, _pad() - reach),
		owner_button.size + Vector2(reach, reach) * 2.0)
