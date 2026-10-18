extends GameTest
## HoleCardButton: the Holes tab's hole cards. Each carries the hole number
## on a tee-marker plate beside a little pixel course window whose layout is
## generated from the hole's own data — its par shapes the route's bends, its
## number seeds every hazard, and the real tee-to-cup direction says which way
## the window faces. The map generator is pure Image work, so these tests read
## the art pixel by pixel, the same way the PixelButtonStyle tests read the
## frames.


## Count of pixels in `image` exactly matching `color`.
func _count(image: Image, color: Color) -> int:
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y) == color:
				total += 1
	return total


## Mean saturation over the whole image, for the open/closed ground check.
func _mean_saturation(image: Image) -> float:
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y).s
	return total / float(image.get_width() * image.get_height())


## The card is a Button that fits its three-to-a-column register: three cards
## and the grid's two gaps stay inside the desktop bottom bar under the page
## title, the same contract the old 26px text rows were measured against.
func test_the_card_is_a_button_sized_for_the_register() -> void:
	var card := HoleCardButton.new()
	add_child_autofree(card)
	assert_true(card is Button, "The hole card stays a Button, as the grid expects")
	assert_eq(card.custom_minimum_size, HoleCardButton.BUTTON_SIZE,
		"The card declares its own footprint")
	var register_height: float = HoleCardButton.BUTTON_SIZE.y * TerrainToolbar.HOLE_COLUMN_HEIGHT \
		+ 4.0 * float(TerrainToolbar.HOLE_COLUMN_HEIGHT - 1)
	var page_height := float(UIConstants.BOTTOM_BAR_HEIGHT) - TerrainToolbar.HEADER_HEIGHT
	assert_lte(register_height, page_height,
		"A full column of hole cards fits the tab page")


## The grid finds its buttons by name and sorts them by metadata; the card
## keeps both contracts and never grows child buttons of its own (the tab
## counts them: one detail button and one Locate button per hole row).
func test_the_card_carries_no_nested_buttons() -> void:
	var card := HoleCardButton.new()
	card.name = "HoleBtn7"
	card.set_meta("hole_number", 7)
	add_child_autofree(card)
	card.set_hole(7, 5, 540, true, Vector2i(4, 4), Vector2i(38, 2))
	assert_eq(card.find_children("*", "Button", true, false).size(), 0,
		"The card paints everything itself, no child buttons")
	assert_eq(card.accessibility_name, "Hole 7",
		"With no text, the card names itself to assistive tech")


## set_hole is the refresh entry main.gd drives from hole_updated: the same
## hole re-handed keeps its one cached map; a changed hole repaints.
func test_set_hole_caches_the_map_until_the_hole_changes() -> void:
	var card := HoleCardButton.new()
	add_child_autofree(card)
	card.set_hole(3, 4, 420, true, Vector2i.ZERO, Vector2i(30, 0))
	var first := card._map_texture
	assert_not_null(first, "The card generated its window art")
	card.set_hole(3, 4, 420, true, Vector2i.ZERO, Vector2i(30, 0))
	assert_same(first, card._map_texture, "Same hole keeps the same generated map")
	card.set_hole(3, 4, 420, false, Vector2i.ZERO, Vector2i(30, 0))
	assert_not_same(first, card._map_texture, "Closing the hole regenerates in the grey palette")


# ---------------------------------------------------------------------------
# THE COURSE WINDOW'S MAP
# ---------------------------------------------------------------------------

## One hole, one layout, every session: the generator depends only on values
## that follow the hole, so reloading the course redraws it exactly.
func test_the_map_is_deterministic() -> void:
	var a := HoleCardButton.generate_map(2, 4, true, false, 0)
	var b := HoleCardButton.generate_map(2, 4, true, false, 0)
	assert_eq(a.get_data(), b.get_data(), "Same hole, same layout, every time")


## The register at a glance is the routing itself: no two holes share a
## layout, and the par families draw different silhouettes.
func test_no_two_holes_share_a_layout() -> void:
	var seen := {}
	for hole in range(1, 10):
		var image := HoleCardButton.generate_map(hole, 3 + (hole - 1) % 3, true, false, 0)
		var key := image.get_data()
		for other in seen:
			assert_ne(key, seen[other], "Hole %d's window is its own, not hole %d's" % [hole, other])
		seen[hole] = key
	var par3 := HoleCardButton.generate_map(5, 3, true, false, 0)
	var par5 := HoleCardButton.generate_map(5, 5, true, false, 0)
	assert_ne(par3.get_data(), par5.get_data(), "Par decides the silhouette family")


## Every open hole's window shows the round's players: a tee box with its
## white markers on striped fairway running to a green with a cup and its red
## flag. Trouble (bunkers and water) comes and goes with the seed, but these
## staples never do.
func test_the_window_shows_tee_fairway_green_and_flag() -> void:
	for hole in range(1, 10):
		for par in [3, 4, 5]:
			var image := HoleCardButton.generate_map(hole, par, true, false, 0)
			assert_gt(_count(image, HoleCardButton.PAL_FAIRWAY), 20,
				"Hole %d par %d has its fairway ribbon" % [hole, par])
			assert_gt(_count(image, HoleCardButton.PAL_FAIRWAY_LIGHT), 4,
				"the ribbon carries its mow stripe" )
			assert_gt(_count(image, HoleCardButton.PAL_TEE), 3,
				"the tee box is mown in" )
			assert_gt(_count(image, HoleCardButton.PAL_MARKER), 0,
				"white markers name the tee" )
			assert_gt(_count(image, HoleCardButton.PAL_GREEN), 8,
				"the green holds up its end" )
			assert_eq(_count(image, HoleCardButton.PAL_CUP), 1,
				"exactly one cup is cut" )
			assert_gte(_count(image, HoleCardButton.PAL_FLAG), 2,
				"the red flag flies" )
			assert_gt(_count(image, HoleCardButton.PAL_TREE), 2,
				"pines stand round the edges" )


## Par shapes the route: par 3s stay shallow (a pitch), par 4s and 5s swing
## deeper bends. Measured as the fairway's widest vertical sweep.
func _fairway_sweep(image: Image) -> int:
	var top := image.get_height()
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			var px := image.get_pixel(x, y)
			if px == HoleCardButton.PAL_FAIRWAY or px == HoleCardButton.PAL_FAIRWAY_LIGHT:
				top = mini(top, y)
				bottom = maxi(bottom, y)
	return bottom - top


func test_par_decides_how_deep_the_route_bends() -> void:
	var par5_sweep := _fairway_sweep(HoleCardButton.generate_map(7, 5, true, false, 0))
	var par3_sweep := _fairway_sweep(HoleCardButton.generate_map(3, 3, true, false, 0))
	assert_gt(par5_sweep, par3_sweep,
		"Hole 7's par 5 sweeps deeper than hole 3's par 3 pitch")


## The window faces the way the real hole plays: a cup that lies left of the
## tee mirrors the layout, so the tee box and the green swap ends.
func test_the_layout_mirrors_to_face_the_real_hole() -> void:
	var east := HoleCardButton.generate_map(4, 4, true, false, 0)
	var west := HoleCardButton.generate_map(4, 4, true, true, 0)
	var half_w := int(HoleCardButton.MAP_W / 2.0)
	var left_half := Rect2i(0, 0, half_w, HoleCardButton.MAP_H)
	var right_half := Rect2i(half_w, 0, HoleCardButton.MAP_W - half_w, HoleCardButton.MAP_H)
	var east_teepad := _count(east.get_region(left_half), HoleCardButton.PAL_TEE)
	var east_greenend := _count(east.get_region(right_half), HoleCardButton.PAL_GREEN)
	var west_teepad := _count(west.get_region(left_half), HoleCardButton.PAL_TEE)
	var west_greenend := _count(west.get_region(right_half), HoleCardButton.PAL_GREEN)
	assert_gt(east_teepad, 0, "The card's tee anchors the left edge…")
	assert_gt(east_greenend, 0, "…with the green finishing right")
	assert_eq(west_teepad, 0, "A mirrored hole tees off from the right…")
	assert_eq(west_greenend, 0, "…and holes out on the left")


## The climb tilts the picture: a cup lying up-course sits high in the
## window; one lying down-course hangs low.
func test_the_layout_tilts_with_the_real_hole() -> void:
	var high := HoleCardButton.generate_map(6, 4, true, false, -1)
	var low := HoleCardButton.generate_map(6, 4, true, false, 1)
	var green_y := func(image: Image) -> float:
		var total := 0.0
		var count := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y) in [HoleCardButton.PAL_GREEN, HoleCardButton.PAL_GREEN_LIGHT]:
					total += y
					count += 1
		return total / float(maxi(count, 1))
	assert_lt(green_y.call(high), green_y.call(low),
		"The up-course cup hangs high, the down-course one low")


## A closed hole's window is the same routing drawn in faded turf, with the
## flag pulled: the register reads "not playing" without a word.
func test_a_closed_hole_fades_its_window_and_drops_its_flag() -> void:
	var open := HoleCardButton.generate_map(2, 4, true, false, 0)
	var closed := HoleCardButton.generate_map(2, 4, false, false, 0)
	assert_gt(_mean_saturation(open), _mean_saturation(closed) * 1.5,
		"The closed window is ground gone grey")
	assert_eq(_count(closed, HoleCardButton.PAL_FLAG), 0,
		"The closed window carries no red flag")
	assert_eq(_count(closed, _palette_flag_closed()), 0,
		"and the grey palette has no flag standing either")


## The closed palette's flag shade, for the assertion above.
func _palette_flag_closed() -> Color:
	var color: Color = HoleCardButton.PAL_FLAG
	var lum := color.get_luminance() * 0.82
	return color.lerp(Color(lum, lum, lum), 0.72).darkened(0.08)
