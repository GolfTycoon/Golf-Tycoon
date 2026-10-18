extends GameTest
## PixelIcon: the title screen's action sprites are 16x16 character grids
## painted from the card's accent, so the art itself can be checked as data -
## every row the same width, only palette characters, each sprite carrying
## its outline and its accent - and the baked textures can be checked for the
## property that makes them pixel art: whole blocks of identical pixels.

const KINDS := [
	PixelIcon.Kind.FLAG, PixelIcon.Kind.BOLT, PixelIcon.Kind.PLAY,
	PixelIcon.Kind.FLOPPY, PixelIcon.Kind.SHIRT, PixelIcon.Kind.GEAR,
	PixelIcon.Kind.DOOR, PixelIcon.Kind.COIN, PixelIcon.Kind.PIN,
	PixelIcon.Kind.TROPHY, PixelIcon.Kind.STAR,
]

const PALETTE_KEYS := ".XALDCMWGg"


func test_every_sprite_is_a_full_16_by_16_grid() -> void:
	for kind in KINDS:
		var rows: Array = PixelIcon.ART[kind]
		assert_eq(rows.size(), PixelIcon.GRID, "kind %d has 16 rows" % kind)
		for row in rows:
			assert_eq(str(row).length(), PixelIcon.GRID,
				"kind %d row \"%s\" is 16 pixels wide" % [kind, row])
			for ch in str(row):
				assert_true(PALETTE_KEYS.contains(ch),
					"kind %d uses only palette characters (saw \"%s\")" % [kind, ch])


func test_every_sprite_carries_its_accent_and_its_outline() -> void:
	for kind in KINDS:
		var rows: Array = PixelIcon.ART[kind]
		var joined := ""
		for row in rows:
			joined += str(row)
		# The floppy dresses its body in the accent's shade rather than the
		# accent itself; both count as wearing the card's colour.
		assert_true(joined.contains("A") or joined.contains("D"),
			"kind %d is painted in the accent" % kind)
		assert_true(joined.contains("X"), "kind %d carries its ink outline" % kind)
		assert_true(joined.contains("L"), "kind %d has a lit face" % kind)


func test_sprites_scale_in_whole_blocks() -> void:
	var img := PixelIcon.image(PixelIcon.Kind.FLAG, 30, UIConstants.COLOR_GOLD)
	# 30 snaps to 32: every source pixel is a 2x2 block of identical pixels.
	assert_eq(img.get_width(), 32, "the requested side snaps to a whole multiple")
	assert_eq(img.get_height(), 32, "square")
	for y in range(0, 32, 2):
		for x in range(0, 32, 2):
			var block := img.get_pixel(x, y)
			assert_eq(img.get_pixel(x + 1, y), block, "block (%d,%d) is even" % [x, y])
			assert_eq(img.get_pixel(x, y + 1), block, "block (%d,%d) is even" % [x, y])
			assert_eq(img.get_pixel(x + 1, y + 1), block, "block (%d,%d) is even" % [x, y])


func test_air_in_the_grid_stays_air_in_the_texture() -> void:
	var rows: Array = PixelIcon.ART[PixelIcon.Kind.FLAG]
	var img := PixelIcon.image(PixelIcon.Kind.FLAG, 16, UIConstants.COLOR_GOLD)
	for y in PixelIcon.GRID:
		for x in PixelIcon.GRID:
			var ch := str(rows[y])[x]
			assert_eq(img.get_pixel(x, y).a > 0.0, ch != ".",
				"pixel (%d,%d) matches the grid" % [x, y])


func test_the_accent_paints_the_sprite_and_dimming_greys_it() -> void:
	var gold := PixelIcon.image(PixelIcon.Kind.FLAG, 16, UIConstants.COLOR_GOLD)
	var green := PixelIcon.image(PixelIcon.Kind.FLAG, 16, MenuStyle.ACCENT_SECONDARY)
	# Row 3 of the pennant is accent across; the two accents differ there.
	assert_eq(gold.get_pixel(5, 3), UIConstants.COLOR_GOLD, "the pennant is gold")
	assert_eq(green.get_pixel(5, 3), MenuStyle.ACCENT_SECONDARY, "or green")
	var dim := PixelIcon.image(PixelIcon.Kind.FLAG, 16, UIConstants.COLOR_GOLD, true)
	assert_lt(dim.get_pixel(5, 3).s, gold.get_pixel(5, 3).s,
		"a disabled card's sprite is greyed")


func test_textures_are_cached_per_kind_size_and_accent() -> void:
	var a := PixelIcon.texture(PixelIcon.Kind.GEAR, 32, UIConstants.COLOR_GOLD)
	var b := PixelIcon.texture(PixelIcon.Kind.GEAR, 34, UIConstants.COLOR_GOLD)
	var c := PixelIcon.texture(PixelIcon.Kind.GEAR, 32, MenuStyle.ACCENT_UTILITY)
	assert_true(a == b, "34 snaps to the same 32px texture")
	assert_true(a != c, "another accent gets its own texture")
	assert_eq(a.get_width(), 32, "the texture is the snapped size")
