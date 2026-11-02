extends GameTest
## BrushShapeButton: the Terrain and Elevation Brush Shape toggles wear a
## miniature of the brush they will paint — the real tile footprint at the
## current size and shape — instead of a fixed square or circle glyph. The
## footprint comes from TerrainBrush.offsets, the same geometry the paint brush
## and the Elevation tool use, and the preview lays its cells out inside the
## medallion's clear middle. These tests check both halves: the footprint is the
## brush's own, and every size and shape fits the plate without spilling over
## the rim.

const DIAMETER := int(InspectButton.BUTTON_DIAMETER)
const AREA := Rect2(Vector2(8, 8), Vector2(30, 30))


func test_the_footprint_is_the_brushs_own_geometry() -> void:
	var button := BrushShapeButton.new()
	add_child_autofree(button)
	for size in TerrainToolbar.BRUSH_SIZES:
		for square in [true, false]:
			button.set_brush(size, square)
			assert_eq(button.footprint(), TerrainBrush.offsets(size, not square),
				"The %s %s preview is the tiles that brush paints" % [
					size, "square" if square else "round"])


func test_a_single_tile_reads_as_one_block() -> void:
	var rects := BrushShapeButton.preview_rects(1, true, AREA)
	assert_eq(rects.size(), 1, "A one-tile brush draws one tile")
	assert_eq(rects[0].size, Vector2.ONE * BrushShapeButton.MAX_TILE,
		"the single tile is chunky rather than a dot")
	var offset := rects[0].get_center() - AREA.get_center()
	assert_lte(offset.length(), 1.0,
		"and it sits in the middle of the plate, snapped to whole pixels")


func test_the_cells_form_a_centred_grid_inside_the_area() -> void:
	for size in TerrainToolbar.BRUSH_SIZES:
		var rects := BrushShapeButton.preview_rects(size, true, AREA)
		assert_eq(rects.size(), size * size,
			"A %dx%d square preview covers %d cells" % [size, size, size * size])
		var bounds := Rect2(rects[0].position, rects[0].size)
		for rect in rects:
			bounds = bounds.merge(rect)
			assert_eq(rect.size, rects[0].size, "every cell is the same size")
		assert_true(AREA.encloses(bounds), "a %dx%d preview fits the plate" % [size, size])
		assert_true(absf(bounds.get_center().x - AREA.get_center().x) <= 1.0
			and absf(bounds.get_center().y - AREA.get_center().y) <= 1.0,
			"a %dx%d preview is centred" % [size, size])
		# Cells are one-pixel apart in both axes: a grid, not a solid block.
		var step := rects[0].size.x + BrushShapeButton.TILE_GAP
		for rect in rects:
			var offset := (rect.position - bounds.position) / step
			assert_true(is_equal_approx(offset.x, roundf(offset.x))
				and is_equal_approx(offset.y, roundf(offset.y)),
				"cells line up on the tile grid")


func test_the_round_shape_clips_the_corners_away() -> void:
	for size in TerrainToolbar.BRUSH_SIZES:
		var square_cells := BrushShapeButton.preview_rects(size, true, AREA)
		var round_cells := BrushShapeButton.preview_rects(size, false, AREA)
		assert_lte(round_cells.size(), square_cells.size(),
			"a %dx%d round preview never covers more tiles" % [size, size])
		if size >= 3:
			assert_lt(round_cells.size(), square_cells.size(),
				"a %dx%d round preview clips the square's corners" % [size, size])


func test_the_wide_brush_keeps_every_cell_inside_the_plate() -> void:
	var rects := BrushShapeButton.preview_rects(9, true, AREA)
	var bounds := Rect2(rects[0].position, rects[0].size)
	for rect in rects:
		bounds = bounds.merge(rect)
	assert_eq(rects.size(), 81, "A 9x9 preview keeps all 81 cells")
	assert_gte(rects[0].size.x, 2.0,
		"cells stay at least two pixels so the grid reads")
	assert_true(AREA.encloses(bounds), "and the 9x9 block still fits inside the plate")


func test_a_small_plate_packs_its_tiles_instead_of_spilling_out() -> void:
	var small := Rect2(Vector2.ZERO, Vector2(12, 12))
	for size in TerrainToolbar.BRUSH_SIZES:
		for square in [true, false]:
			var rects := BrushShapeButton.preview_rects(size, square, small)
			var bounds := Rect2(rects[0].position, rects[0].size)
			for rect in rects:
				bounds = bounds.merge(rect)
			assert_true(small.encloses(bounds),
				"a %dx%d %s preview still fits the small plate" % [
					size, size, "square" if square else "round"])


func test_the_preview_keeps_clear_of_the_medallion_rim() -> void:
	var area := BrushShapeButton.preview_area(DIAMETER, Vector2.ZERO)
	var inset := area.position.x
	assert_gt(inset, 0.0, "the preview starts inside the face")
	# A square inscribed in the face's fill circle is about 0.7 of its
	# diameter across; the preview must not reach out into the ring bands.
	assert_lte(area.size.x, float(DIAMETER) * 0.7,
		"the preview's box stays inside the trim and bevel rings")
	# Corner cells must stay inside the face: their corners sit on the box's
	# corners, which is exactly the inscribed square.
	var radius := float(DIAMETER) * 0.5
	var corner := area.end - Vector2.ONE * 0.5
	assert_lte(corner.distance_to(Vector2.ONE * radius), radius - 2.0,
		"no cell spills over the medallion's rings")


func test_set_brush_repaints_both_shape_and_size() -> void:
	var button := BrushShapeButton.new()
	add_child_autofree(button)
	button.set_brush(5, false)
	assert_eq(button.brush_size, 5)
	assert_false(button.brush_square)
	assert_eq(button.footprint().size(), 13, "a 5x5 round brush keeps 13 tiles")
	button.set_brush(5, true)
	assert_true(button.brush_square)
	assert_eq(button.footprint().size(), 25, "a 5x5 square brush keeps 25 tiles")


func test_the_size_is_clamped_to_at_least_one_tile() -> void:
	var button := BrushShapeButton.new()
	add_child_autofree(button)
	button.brush_size = 0
	assert_eq(button.brush_size, 1, "a brush is never narrower than one tile")
	assert_eq(button.footprint().size(), 1)
