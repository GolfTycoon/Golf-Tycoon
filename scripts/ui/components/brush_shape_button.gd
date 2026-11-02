extends PixelCircleButton
class_name BrushShapeButton
## The Terrain and Elevation Brush Shape toggles, each showing the brush itself.
##
## A fixed square or circle glyph only said which shape was picked. These
## medallions instead wear a miniature of the brush: the exact tile footprint
## the brush will paint with at its current size and shape, drawn as a little
## grid of tiles. A 1-tile brush is one chunky tile, a 5-tile round brush is a
## 5x5 block with clipped corners. The footprint is read from
## TerrainBrush.offsets, the same geometry the two tools paint with (the
## Elevation tool's tile_offsets is a thin wrapper over it), so the example can
## never drift from the brush.
##
## The tiles scale to fill the medallion for every size — a 9x9 footprint gets
## small tiles, a 1x1 footprint one large tile — so the grid count, not the
## absolute pixel size, says how wide the brush is. Tiles are cream on ink
## shadows, like the pixel glyphs they replace, and grey while the brush is
## locked by a single-tile tool.

## What the preview keeps clear of the medallion's ink rim, trim, bevel and
## sheen bands. They leave a fill circle of about 0.85 of the diameter, and a
## square inscribed in that circle is about 0.7 of the diameter across, so an
## inset of a fifth of the diameter per side keeps every corner cell inside.
const PREVIEW_INSET_RATIO := 0.2
## The gap between two tile cells, so the footprint reads as a grid of tiles
## rather than one solid block.
const TILE_GAP := 1.0
## The widest a tile cell may draw: a single-tile brush stays a readable block
## in the middle of the plate instead of filling the medallion. Narrower plates
## simply get smaller cells — the layout never draws outside its area.
const MAX_TILE := 11.0

## The brush these tiles are drawn for. Both setters repaint, so the medallion
## follows the size stepper next door and the shape toggle as they change.
var brush_size := 3:
	set(value):
		var clamped := maxi(1, value)
		if brush_size != clamped:
			brush_size = clamped
			if is_inside_tree():
				queue_redraw()
var brush_square := true:
	set(value):
		if brush_square != value:
			brush_square = value
			if is_inside_tree():
				queue_redraw()

## Point the preview at a brush. Callers pass what the brush will really paint
## with — the size plate's capped size on the Terrain shelf — so the example and
## the number beside it always agree.
func set_brush(size_in_tiles: int, square_shape: bool) -> void:
	brush_size = size_in_tiles
	brush_square = square_shape

## The tiles the brush covers, relative to its anchor. Delegates to the painting
## geometry so the preview is the brush's own footprint.
func footprint() -> Array[Vector2i]:
	return TerrainBrush.offsets(brush_size, not brush_square)

## Where each tile's cell sits inside `area`, in drawing coordinates. Pure, so
## the layout can be checked headlessly: cells are TILE_GAP apart while the area
## has room for the gaps, and the whole footprint is centred in the area.
static func preview_rects(size_in_tiles: int, square_shape: bool, area: Rect2) -> Array[Rect2]:
	var offsets := TerrainBrush.offsets(maxi(1, size_in_tiles), not square_shape)
	var rects: Array[Rect2] = []
	if offsets.is_empty():
		return rects
	var low := offsets[0]
	var high := offsets[0]
	for offset in offsets:
		low = Vector2i(mini(low.x, offset.x), mini(low.y, offset.y))
		high = Vector2i(maxi(high.x, offset.x), maxi(high.y, offset.y))
	var span := Vector2i(high.x - low.x + 1, high.y - low.y + 1)
	var across := float(maxi(span.x, span.y))
	var box := minf(area.size.x, area.size.y)
	# The gap is a luxury: a plate too small for a one-pixel cell plus gaps
	# packs its tiles edge to edge rather than spilling out of the medallion.
	var gap := TILE_GAP if box >= across + TILE_GAP * (across - 1.0) else 0.0
	var cell := clampf(floorf((box - gap * (across - 1.0)) / across), 1.0, MAX_TILE)
	var grid := Vector2(span) * cell + Vector2.ONE * (gap * (across - 1.0))
	var top_left := area.position + ((area.size - grid) * 0.5).floor()
	var step := cell + gap
	for offset in offsets:
		var at := top_left + Vector2(float(offset.x - low.x), float(offset.y - low.y)) * step
		rects.append(Rect2(at, Vector2.ONE * cell))
	return rects

## The area the footprint is drawn in, given the medallion's diameter and its
## top-left origin on the control.
static func preview_area(diameter_px: int, origin: Vector2) -> Rect2:
	var inset := ceili(float(diameter_px) * PREVIEW_INSET_RATIO)
	var side := maxf(0.0, float(diameter_px) - 2.0 * inset)
	return Rect2(origin + Vector2.ONE * inset, Vector2.ONE * side)

func _draw() -> void:
	super()
	var d := int(minf(size.x, size.y))
	if d < 8:
		return
	var origin := ((size - Vector2.ONE * d) * 0.5).floor()
	# The toggle is held down while the round shape is picked, so the preview
	# stays put instead of nudging: the brush, not the pressed state, is what
	# the plate shows.
	var tile_color := Color("748273") if disabled else CREAM
	for rect in preview_rects(brush_size, brush_square, preview_area(d, origin)):
		draw_rect(Rect2(rect.position + Vector2(0, 2), rect.size), INK)
		draw_rect(rect, tile_color)
