extends GameTest
## The Screen responsive-layout adapter: the UI and world scales a window size
## asks for, the compact and portrait flags, and the room left for panels.

const ScreenScript := preload("res://scripts/autoload/screen_manager.gd")

func _make_screen() -> Node:
	# A bare instance (not the autoload) so window_size can be set directly.
	return autofree(ScreenScript.new())

func test_compute_scale_is_limited_by_smaller_dimension() -> void:
	assert_almost_eq(ScreenScript.compute_scale(Vector2(1600, 1000)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_scale(Vector2(1366, 768)), 0.768, 0.0001)
	# A very wide window is limited by height; a very tall one by width.
	assert_almost_eq(ScreenScript.compute_scale(Vector2(3200, 1000)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_scale(Vector2(1600, 2000)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_scale(Vector2(100, 100)), 0.0625, 0.0001)

func test_world_scale_tracks_reference_view_on_large_windows() -> void:
	# Same course area per inch as the 1600x1000 reference design...
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1600, 1000)), 1.0, 0.0001)
	# ...and scaled up proportionally on bigger desktops.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1920, 1080)), 1.08, 0.001)
	# 1366x768 matches the old fixed-viewport stretch factor exactly.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1366, 768)), 0.768, 0.001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(2560, 1440)), 1.44, 0.001)

func test_world_scale_never_shrinks_tiles_below_design_size() -> void:
	# Phones and tablets keep 1:1 pixel scale so tiles stay tappable.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(390, 844)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(768, 1024)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(834, 1194)), 1.0, 0.0001)
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(1024, 768)), 0.879, 0.001)
	# Degenerate (test) sizes never go below 1.0.
	assert_almost_eq(ScreenScript.compute_world_scale(Vector2(64, 64)), 1.0, 0.0001)

func test_world_scale_is_scale_clamped_by_narrow_window_floor() -> void:
	# world_scale = max(scale, min(1, 900/width))
	for width in [500.0, 768.0, 900.0, 1200.0, 1600.0, 2560.0]:
		var size := Vector2(width, 1000.0)
		var expected: float = maxf(ScreenScript.compute_scale(size), minf(1.0, 900.0 / width))
		assert_almost_eq(ScreenScript.compute_world_scale(size), expected, 0.0001)

# ---------------------------------------------------------------------------
# Automatic UI scale
# ---------------------------------------------------------------------------

func test_system_display_scale_comes_from_the_platform_that_reports_it() -> void:
	# macOS Retina, phones and the web expose the backing scale / density.
	assert_almost_eq(ScreenScript.detect_system_ui_scale(2.0, 254, "macOS"), 2.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(2.0, 192, "Web"), 2.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(3.0, 288, "iOS"), 3.0, 0.001)
	# Android's screen scale is cropped for an 800x600 canvas; its densityDpi
	# is the dp scale (160 = 100%, 480 = 300%).
	assert_almost_eq(ScreenScript.detect_system_ui_scale(3.0, 480, "Android"), 3.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.35, 420, "Android"), 2.625, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.0, 0, "Android"), 1.0, 0.001)
	# Windows reports the monitor's effective DPI (and a flat 1.0 scale).
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.0, 96, "Windows"), 1.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.0, 120, "Windows"), 1.25, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.0, 144, "Windows"), 1.5, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.0, 192, "Windows"), 2.0, 0.001)
	# X11's DPI is the panel's physical resolution, not the desktop's chosen
	# text size, so only the toolkit's own scale counts there.
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.0, 157, "Linux", 1.0), 1.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.0, 96, "Linux", 2.0), 2.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(1.5, 96, "Linux", 1.0), 1.5, 0.001)
	# No useful report: the design's own 100%, never smaller.
	assert_almost_eq(ScreenScript.detect_system_ui_scale(0.0, 0, "Web"), 1.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(0.75, 96, "macOS"), 1.0, 0.001)
	assert_almost_eq(ScreenScript.detect_system_ui_scale(9.0, 96, "Web"), ScreenScript.MAX_UI_SCALE, 0.001)


func test_auto_scale_follows_the_device_and_keeps_desktop_size_elsewhere() -> void:
	# A 4K desktop at 200% system scaling lays out like a 1920x1080 one.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(3840, 2160), 1.0, 192, "Windows", false, 1.0, false), 2.0, 0.001)
	# A 1080p desktop at 100% keeps the 1600x1000 design's own size.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(1920, 1080), 1.0, 96, "Windows", false, 1.0, true), 1.0, 0.001)
	# A Retina Mac window is 2x its points.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(2880, 1800), 2.0, 254, "macOS", false, 1.0, true), 2.0, 0.001)
	# Phones lay out in density-independent pixels: density is the scale, and
	# the desktop room cap does not apply to them.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(1080, 2400), 3.0, 480, "Android", true, 1.0, true), 3.0, 0.001)
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(1080, 2400), 1.35, 420, "Android", true, 1.0, true), 2.65, 0.001)
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(1170, 2532), 3.0, 288, "Web", true, 1.0, true), 3.0, 0.001)
	# A desktop browser at devicePixelRatio 2 gets the same 2x.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(2880, 1800), 2.0, 192, "Web", false, 1.0, true), 2.0, 0.001)


func test_auto_scale_keeps_a_windowed_desktop_window_usable() -> void:
	# A large Retina window has room for the full display scale...
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(2560, 1600), 2.0, 254, "macOS", false, 1.0, true), 2.0, 0.001)
	# ...a small one is capped so the layout keeps 1180x680 logical pixels.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(1440, 900), 2.0, 254, "macOS", false, 1.0, true), 1.2, 0.001)
	# A maximised window is never capped.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(1440, 900), 2.0, 254, "macOS", false, 1.0, false), 2.0, 0.001)
	# The cap never shrinks the UI below the design's 100%.
	assert_almost_eq(ScreenScript.compute_auto_ui_scale(
		Vector2(640, 480), 2.0, 192, "Windows", false, 1.0, true), 1.0, 0.001)


func test_auto_scale_is_snapped_and_clamped() -> void:
	assert_almost_eq(ScreenScript.snap_ui_scale(1.37), 1.35, 0.001)
	assert_almost_eq(ScreenScript.snap_ui_scale(0.5), ScreenScript.MIN_UI_SCALE, 0.001)
	assert_almost_eq(ScreenScript.snap_ui_scale(9.0), ScreenScript.MAX_UI_SCALE, 0.001)
	assert_eq(ScreenScript.format_ui_scale(2.0), "200%")


func test_only_phone_platforms_lay_out_in_density_independent_pixels() -> void:
	assert_true(ScreenScript.is_mobile_platform("Android", false))
	assert_true(ScreenScript.is_mobile_platform("iOS", false))
	assert_true(ScreenScript.is_mobile_platform("Web", true))
	assert_false(ScreenScript.is_mobile_platform("Web", false))
	assert_false(ScreenScript.is_mobile_platform("Windows", true))
	assert_false(ScreenScript.is_mobile_platform("macOS", false))


func test_compact_flags() -> void:
	var s := _make_screen()
	s.window_size = Vector2(1600, 1000)
	assert_false(s.is_compact())
	assert_false(s.is_portrait())
	assert_true(s.is_landscape())

	s.window_size = Vector2(390, 844)  # Phone portrait
	assert_true(s.is_compact())
	assert_true(s.is_portrait())
	assert_false(s.is_landscape())

	s.window_size = Vector2(812, 375)  # Phone landscape: short window
	assert_true(s.is_compact())
	assert_true(s.is_landscape())

	s.window_size = Vector2(1024, 768)  # Tablet: wide enough, tall enough
	assert_false(s.is_compact())
	s.window_size = Vector2(1024, 600)  # but short windows stay compact
	assert_true(s.is_compact())

func test_apply_size_emits_changed_only_when_values_move() -> void:
	var s := _make_screen()
	var emissions: Array = []
	s.changed.connect(func(size: Vector2, ws: float): emissions.append([size, ws]))
	s.window_size = Vector2(1600, 1000)
	s.world_scale = 1.0
	s.apply_size(Vector2(1600, 1000))
	assert_eq(emissions.size(), 0, "same size + scale must not emit")
	s.apply_size(Vector2(390, 844))
	assert_eq(emissions.size(), 1)
	assert_eq(emissions[0][1], 1.0)
	s.apply_size(Vector2(1920, 1080))
	assert_eq(emissions.size(), 2)
	assert_almost_eq(emissions[1][1], 1.08, 0.001)

func test_available_panel_size_stays_clear_of_bottom_bar() -> void:
	var s := _make_screen()
	s.window_size = Vector2(1600, 1000)
	var desktop_bar := UIConstants.TOUCH_BOTTOM_BAR_HEIGHT if DisplayServer.is_touchscreen_available() else UIConstants.BOTTOM_BAR_HEIGHT
	assert_eq(s.available_panel_size(), Vector2(1568, 1000 - 24 - desktop_bar - 8))
	s.window_size = Vector2(390, 844)
	assert_eq(s.available_panel_size(), Vector2(358, 844 - 24 - 108 - 8),
		"Portrait popups clear the collapsed thumb rail and context button")
	s.set_portrait_tools_open(true)
	assert_eq(s.available_panel_size(), Vector2(358, 844 - 24 - 324 - 8),
		"An open tray reserves its full height")
	s.set_portrait_tools_open(false)
	# Tiny windows get a usable floor, not a negative size.
	s.window_size = Vector2(64, 64)
	assert_eq(s.available_panel_size(), Vector2(120, 120))

func test_touch_layout_uses_a_taller_bar_for_larger_targets() -> void:
	var s := _make_screen()
	s.window_size = Vector2(1600, 1000)
	var desktop_height: int = UIConstants.TOUCH_BOTTOM_BAR_HEIGHT if DisplayServer.is_touchscreen_available() else UIConstants.BOTTOM_BAR_HEIGHT
	assert_eq(s.bottom_bar_height(), float(desktop_height))

	s.window_size = Vector2(390, 844)
	assert_true(s.uses_touch_layout(), "Compact phone-sized windows use touch sizing")
	assert_eq(s.bottom_bar_height(), 108.0)
	assert_almost_eq(s.hud_bottom_clearance(), 116.0, 0.001)
	s.window_size = Vector2(844, 390)
	assert_eq(s.bottom_bar_height(), float(UIConstants.TOUCH_BOTTOM_BAR_HEIGHT),
		"Rotation keeps the existing landscape touch dock")


func test_portrait_hud_is_phone_width_only() -> void:
	var s := _make_screen()
	for size in [Vector2(320, 568), Vector2(390, 844), Vector2(699, 1000)]:
		s.window_size = size
		assert_true(s.uses_portrait_hud(), "%s uses the thumb layout" % size)
	for size in [Vector2(700, 1000), Vector2(768, 1024), Vector2(844, 390), Vector2(1600, 1000)]:
		s.window_size = size
		assert_false(s.uses_portrait_hud(), "%s keeps the wider composition" % size)

func test_portrait_state_emits_and_changes_only_the_affected_clearance() -> void:
	var s := _make_screen()
	s.window_size = Vector2(390, 844)
	var emissions: Array = []
	s.changed.connect(func(_size: Vector2, _scale: float): emissions.append(true))
	s.set_portrait_tools_open(false)
	s.set_portrait_map_open(false)
	assert_eq(emissions.size(), 0, "Unchanged state is quiet")
	s.set_portrait_tools_open(true)
	s.set_portrait_map_open(true)
	assert_eq(emissions.size(), 2)
	assert_eq(s.bottom_bar_height(), 324.0)
	var course: Rect2 = s.portrait_course_rect()
	assert_gte(course.position.y, s.portrait_header_height())
	assert_lte(course.end.y, 844.0 - s.bottom_bar_height())
	assert_gte(course.size.x, 300.0)

func test_safe_insets_are_clamped_to_a_fifth_of_each_axis() -> void:
	var clamped := ScreenScript.clamp_safe_insets(Vector4(-5, 44, 12, 900), Vector2(390, 844))
	assert_eq(clamped, Vector4(0, 44, 12, 168.8))
	var s := _make_screen()
	s.window_size = Vector2(390, 844)
	s.safe_insets = Vector4(12, 44, 12, 34)
	assert_eq(s.portrait_nav_height(), 98.0)
	var course: Rect2 = s.portrait_course_rect()
	assert_gte(course.position.x, 20.0)
	assert_lte(course.end.x, 378.0)
	assert_gte(course.position.y, s.portrait_header_height())
