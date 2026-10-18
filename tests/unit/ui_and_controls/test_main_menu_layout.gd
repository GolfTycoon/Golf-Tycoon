extends GameTest
## The title screen's layout: its breakpoints and card metrics.
##
## MainMenu is built from code, so the parts worth pinning down without a
## window are the pure ones: which arrangement a window size asks for, and how
## much room a two-line caption needs inside a card. The arrangement is
## checked end to end (all eight actions on screen, no overlaps) by
## tests/harness/main_menu_layout_harness.gd.

func _mode(size: Vector2) -> int:
	return MainMenu.layout_mode_for(size)

func test_phone_sizes_use_the_single_column_layout() -> void:
	assert_eq(_mode(Vector2(390, 844)), MainMenu.Layout.PHONE, "phone portrait")
	assert_eq(_mode(Vector2(320, 568)), MainMenu.Layout.PHONE, "small phone")
	assert_eq(_mode(Vector2(600, 900)), MainMenu.Layout.PHONE, "narrow browser window")
	# Portrait is the phone layout even when the window is tall and roomy.
	assert_eq(_mode(Vector2(680, 1000)), MainMenu.Layout.PHONE, "narrow and tall")

func test_wide_short_windows_use_the_two_column_compact_layout() -> void:
	assert_eq(_mode(Vector2(844, 390)), MainMenu.Layout.LANDSCAPE, "rotated phone")
	assert_eq(_mode(Vector2(1180, 500)), MainMenu.Layout.LANDSCAPE, "squat browser window")
	# A short window is not offered the tall arrangements even when wide.
	assert_eq(_mode(Vector2(1920, 400)), MainMenu.Layout.LANDSCAPE, "short and very wide")

func test_tablet_sizes_use_the_centred_column() -> void:
	assert_eq(_mode(Vector2(768, 1024)), MainMenu.Layout.TABLET, "tablet portrait")
	assert_eq(_mode(Vector2(1024, 768)), MainMenu.Layout.TABLET, "tablet landscape")
	assert_eq(_mode(Vector2(MainMenu.TABLET_MIN_WIDTH, MainMenu.TALL_MIN_HEIGHT)),
		MainMenu.Layout.TABLET, "the smallest tablet window")

func test_desktop_sizes_use_the_split_layout() -> void:
	assert_eq(_mode(Vector2(1600, 1000)), MainMenu.Layout.WIDE, "the reference window")
	assert_eq(_mode(Vector2(1280, 800)), MainMenu.Layout.WIDE, "small laptop")
	assert_eq(_mode(Vector2(2560, 1440)), MainMenu.Layout.WIDE, "large desktop")
	assert_eq(_mode(Vector2(MainMenu.WIDE_MIN_WIDTH, MainMenu.TALL_MIN_HEIGHT)),
		MainMenu.Layout.WIDE, "the smallest wide window")

## Every size gets exactly one arrangement, and the split ones only start at
## their documented width - a regression here would leave a desktop window
## with the phone layout or two panels crammed into a phone's width.
func test_breakpoints_are_ordered() -> void:
	var sizes := [
		Vector2(360, 640), Vector2(390, 844), Vector2(844, 390), Vector2(1024, 768),
		Vector2(1120, 619), Vector2(1120, 620), Vector2(1600, 1000),
	]
	for size in sizes:
		var mode := _mode(size)
		if mode == MainMenu.Layout.WIDE or mode == MainMenu.Layout.TABLET:
			assert_gte(size.x, MainMenu.TABLET_MIN_WIDTH, "%s is wide enough for a two-panel mode" % size)
			assert_gte(size.y, MainMenu.TALL_MIN_HEIGHT, "%s is tall enough for a two-panel mode" % size)
		if mode == MainMenu.Layout.WIDE:
			assert_gte(size.x, MainMenu.WIDE_MIN_WIDTH, "%s is wide enough to split" % size)

func test_short_window_drops_out_of_the_wide_layout() -> void:
	# 1120x620 is the corner of the wide arrangement; one pixel less height and
	# the window is treated as short (the compact two-panel layout).
	assert_eq(_mode(Vector2(1120, 620)), MainMenu.Layout.WIDE)
	assert_eq(_mode(Vector2(1120, 619)), MainMenu.Layout.LANDSCAPE)

## The logo replaces the typed game name. These caps are the spare room measured
## around the action stack, so a taller lockup here would push a button off
## screen on the tight windows the layout harness drives.
func test_logo_heading_fits_the_tight_windows() -> void:
	var aspect := 1.91
	var small_phone := MainMenu.logo_display_size(Vector2(320, 568), 292.0, aspect)
	assert_lte(small_phone.x, 292.0, "small phone logo fits its column")
	assert_lte(small_phone.y, 104.0, "small phone logo leaves room for the action stack")
	assert_gte(small_phone.y, 64.0, "small phone logo is still a heading")

	var rotated := MainMenu.logo_display_size(Vector2(844, 390), 304.0, aspect)
	assert_lte(rotated.y, 128.0, "rotated phone logo stays short")
	assert_lte(rotated.x, 304.0, "rotated phone logo fits the brand column")

	var squat := MainMenu.logo_display_size(Vector2(1920, 400), 691.0, aspect)
	assert_lte(squat.y, 128.0, "a squat window does not grow a tall logo")

	var wide_corner := MainMenu.logo_display_size(Vector2(1120, 620), 0.0, aspect)
	assert_lte(wide_corner.y, 180.0, "the shortest wide window can still carry the logo")
	assert_gte(wide_corner.x, 240.0, "the wide logo still reads as a heading")

	var desktop := MainMenu.logo_display_size(Vector2(1600, 1000), 0.0, aspect)
	assert_gt(desktop.x, wide_corner.x, "a larger window gets a larger logo")
	assert_almost_eq(desktop.x / desktop.y, aspect, 0.02, "the logo keeps its aspect")
	assert_lte(desktop.y, 300.0, "the desktop logo does not become a banner")

func test_card_caption_reserves_room_for_its_lines() -> void:
	assert_eq(MainMenu._caption_block(0, 2), 0.0, "no font, no caption strip")
	assert_eq(MainMenu._caption_block(14, 0), 0.0, "no lines, no caption strip")
	assert_almost_eq(MainMenu._caption_block(10, 1), 14.0, 0.001)
	# Two lines need exactly twice one line, so cards scale with their text.
	assert_almost_eq(MainMenu._caption_block(10, 2), 28.0, 0.001)
	assert_almost_eq(MainMenu._caption_block(12, 2), MainMenu._caption_block(12, 1) * 2.0, 0.001)
