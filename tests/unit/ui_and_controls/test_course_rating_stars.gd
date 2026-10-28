extends GameTest
## CourseRatingStars: the five faceted pixel-art stars inside HUDStatusColumn's
## rating value pill. Verifies grid geometry, mirror symmetry, 3D facet palette,
## recessed unlit sockets, central-ridge half-star splits and texture caching.

const VALID_KEYS := ".XHLGADR"


func test_desktop_and_compact_grids_are_square_and_mirror_symmetric() -> void:
	for pair in [
		[false, CourseRatingStars.DESKTOP_SIDE],
		[true, CourseRatingStars.COMPACT_SIDE],
	]:
		var is_compact: bool = pair[0]
		var expected_side: int = pair[1]
		var rows := CourseRatingStars.grid_for(is_compact)
		assert_eq(rows.size(), expected_side, "grid height matches side")
		for y in rows.size():
			var row: String = rows[y]
			assert_eq(row.length(), expected_side, "row %d width matches side" % y)
			for x in expected_side:
				var ch := row[x]
				assert_true(VALID_KEYS.contains(ch),
					"only facet palette keys appear (saw \"%s\")" % ch)
				assert_eq(ch == ".", row[expected_side - 1 - x] == ".",
					"row %d silhouette is mirror-symmetric at column %d" % [y, x])


func test_lit_star_carries_crown_highlight_gold_facets_shadow_and_ink() -> void:
	for is_compact in [false, true]:
		var rows := CourseRatingStars.grid_for(is_compact)
		var joined := ""
		for row in rows:
			joined += row
		for key in ["X", "H", "L", "G", "A", "D", "R"]:
			assert_true(joined.contains(key),
				"%s star uses facet tone %s" % ["compact" if is_compact else "desktop", key])

		var full_img := CourseRatingStars.star_image(1.0, is_compact)
		var unlit_img := CourseRatingStars.star_image(0.0, is_compact)
		var mid := int(rows.size() / 2.0)
		assert_gt(full_img.get_pixel(mid, mid).r, unlit_img.get_pixel(mid, mid).r,
			"lit star core is brighter gold than the recessed unlit socket")
		assert_gt(unlit_img.get_pixel(mid, mid).a, 0.9,
			"unlit star renders an opaque recessed socket rather than disappearing")


func test_half_star_splits_cleanly_along_the_central_vertical_ridge() -> void:
	var half_desktop := CourseRatingStars.star_image(0.5, false)
	var full_desktop := CourseRatingStars.star_image(1.0, false)
	var unlit_desktop := CourseRatingStars.star_image(0.0, false)

	# Row 8 spans the full horizontal arms (columns 1..19, centre ridge at x = 10).
	assert_eq(half_desktop.get_pixel(4, 8), full_desktop.get_pixel(4, 8),
		"left arm of a 0.5 star is lit gold")
	assert_eq(half_desktop.get_pixel(10, 8), full_desktop.get_pixel(10, 8),
		"central ridge of a 0.5 star stays lit")
	assert_eq(half_desktop.get_pixel(16, 8), unlit_desktop.get_pixel(16, 8),
		"right arm of a 0.5 star is the recessed unlit socket")


func test_star_textures_are_cached_by_quantized_fill_and_layout() -> void:
	var a := CourseRatingStars.star_texture(1.0, false)
	var b := CourseRatingStars.star_texture(1.0, false)
	var c := CourseRatingStars.star_texture(1.0, true)
	var d := CourseRatingStars.star_texture(0.5, false)
	assert_true(a == b, "identical fill reuses cached texture")
	assert_true(a != c, "compact layout has its own 15x15 texture")
	assert_true(a != d, "half star has its own baked texture")
