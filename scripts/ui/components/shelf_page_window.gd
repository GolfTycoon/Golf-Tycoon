extends Control
class_name ShelfPageWindow
## The curved window every bottom-right shelf page is cut to.
##
## The shelf's fairway is the dock's quarter-ellipse mirrored across the seam
## (see ShelfFanBackdrop): its rim leaves the shelf's left edge low down and
## rises to the top of the tab rail, so the turf beside the curved tab buttons
## is widest along the bottom and pinches out at the top. The pages used to
## start on a straight vertical edge beside the rail, which left all of that
## wedge as dead space. This control hands it back: a page now starts at the
## shelf's own left padding and its left side is cut along a curve parallel to
## the rim, so it reaches further left the lower it sits — sliding under the
## curved tabs and stopping a frame's width inside the rim.
##
## The window is a mask. It paints that silhouette and clips its children to it
## (`clip_children = CLIP_CHILDREN_ONLY`), so a scrolled page can never spill
## over the rim onto the course showing outside the shelf. The silhouette is one
## drawing of one polygon — no per-page work — so the whole shelf pays for a
## single mask pass. The same shape gates input (`clip_contents` with
## `has_point`, plus `has_touch_point` for TouchInput), so the cut-out left of
## the curve keeps passing clicks, hovers and gestures through to the course
## beneath it.

## How far inside the rim the pages start, in display pixels: the ink, trim,
## bevel and sheen bands the rim wears (DockArcBackdrop.BAND_SHEEN) plus a
## two-pixel breath, so the frame stays whole beside the scrolling content.
const EDGE_MARGIN := DockArcBackdrop.BAND_SHEEN + 2.0

## Horizontal radius of the mirrored quarter-ellipse, in display pixels, and
## the part of the dock's ellipse its own canvas clips (see ShelfFanBackdrop).
## Both are handed over by TerrainToolbar with the backdrop's own curve, so the
## cut window and the painted rim can never drift apart.
var curve_width := 0.0
var seam_inset := 0.0

func _init() -> void:
	name = "ShelfPageWindow"
	# Only its children answer clicks; the window itself shapes where they can.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The mask keeps pages off the course, and the rect clip lets `has_point`
	# shape the mouse and touch the pages' descendants receive.
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip_contents = true
	resized.connect(queue_redraw)

## Take the shelf's mirrored curve: the same width and seam inset the fairway
## is painted with (see TerrainToolbar._sync_backdrop).
func set_curve(width: float, inset: float) -> void:
	width = maxf(width, 0.0)
	inset = clampf(inset, 0.0, width)
	if not is_equal_approx(curve_width, width) or not is_equal_approx(seam_inset, inset):
		curve_width = width
		seam_inset = inset
		if is_inside_tree():
			queue_redraw()

## The page window's left edge at `y`: the rim, moved `margin` pixels into the
## shelf, so the frame keeps its width beside the content.
func content_left_at(y: float) -> float:
	return content_left(y, size, curve_width, seam_inset, EDGE_MARGIN)

## Whether a point of the shelf is inside the scrolling pages: below the rim
## and far enough right of it to clear the frame. Used for the mask, for mouse
## picking (through `has_point`) and for TouchInput.
func contains_content_point(point: Vector2) -> bool:
	return content_contains(point, size, curve_width, seam_inset, EDGE_MARGIN)

func has_touch_point(point: Vector2) -> bool:
	return contains_content_point(point)

func _has_point(point: Vector2) -> bool:
	return contains_content_point(point)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# The mask is this drawing's alpha: opaque inside the window, nothing above
	# the rim, so the children are cut to the curve. Before the rail has handed
	# over a curve (the first frame of a new shelf) the window is simply whole.
	if curve_width <= 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
		return
	draw_colored_polygon(content_polygon(size, curve_width, seam_inset, EDGE_MARGIN),
			Color.WHITE)

# ============================================================================
# THE CURVED EDGE
# ============================================================================

## The window's left edge at `y` for a shelf `canvas_size` wide and tall, with
## the fairway's mirrored curve (`width`, `inset`) and the page's `margin`
## inside the rim.
static func content_left(y: float, canvas_size: Vector2, width: float,
		inset: float = 0.0, margin: float = EDGE_MARGIN) -> float:
	if width <= 0.0:
		return 0.0
	return ShelfFanBackdrop.rim_x_at(y, canvas_size, width, inset) + margin

## Whether `point` is inside the window: on the shelf canvas and to the right
## of its curved left edge.
static func content_contains(point: Vector2, canvas_size: Vector2, width: float,
		inset: float = 0.0, margin: float = EDGE_MARGIN) -> bool:
	return Rect2(Vector2.ZERO, canvas_size).has_point(point) \
		and point.x >= content_left(point.y, canvas_size, width, inset, margin)

## The silhouette the pages are clipped to, wound from the curved left edge
## down the shelf and back along its square right side. The edge is sampled at
## the fairway's own two-pixel grain, so the cut steps with the pixel art.
static func content_polygon(canvas_size: Vector2, width: float,
		inset: float = 0.0, margin: float = EDGE_MARGIN) -> PackedVector2Array:
	var points := PackedVector2Array()
	var step := float(ShelfFanBackdrop.PIXEL)
	var last := maxf(canvas_size.y, step)
	var y := 0.0
	while y < last:
		points.append(Vector2(clampf(content_left(y, canvas_size, width, inset, margin),
				0.0, canvas_size.x), y))
		y += step
	points.append(Vector2(clampf(content_left(last, canvas_size, width, inset, margin),
			0.0, canvas_size.x), last))
	points.append(Vector2(canvas_size.x, last))
	points.append(Vector2(canvas_size.x, 0.0))
	return points
