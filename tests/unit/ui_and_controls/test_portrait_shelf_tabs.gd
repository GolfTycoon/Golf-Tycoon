extends GameTest
## The shelf's page tabs in the portrait tray: Terrain, Improvements, Buildings
## and Elevations under Build; Club, Holes and Staff under Manage; the four
## Golfers pages. On a phone held upright they are full-width touch tabs, not
## 48px medallions with empty tray either side of them: the tabs on show share
## the whole row between the same 8px margins, and with the same 4px gap, as the
## section buttons of the thumb rail under the tray, and each wears its caption
## under its icon. Turning the phone on its side hands the medallions back.
##
## The toolbar is built on its own here, sized as the tray sizes it; the real
## HUD, real taps and the safe-area insets are covered by the portrait HUD
## integration tests.

const PHONES := [Vector2(320, 568), Vector2(360, 640), Vector2(375, 667),
	Vector2(390, 844), Vector2(412, 915), Vector2(430, 932), Vector2(540, 960)]

var toolbar: TerrainToolbar
var _window_size: Vector2 = Vector2(1600, 1000)

## Pin the window size the way the toolbar tests do: the headless window is
## 64x64 and Screen's per-frame polling would put it back.
func before_each() -> void:
	super()
	_window_size = Screen.window_size
	Screen.set_process(false)
	Screen.apply_size(PHONES[0])
	toolbar = TerrainToolbar.new()
	add_child_autofree(toolbar)

func after_each() -> void:
	# Switching tabs rebuilds tiles with queue_free(); let those frees land
	# before GUT counts orphans.
	await process_frames(1)
	Screen.apply_size(_window_size)
	Screen.set_process(true)
	super()

## Resize the phone and hand the shelf the tray's size, as PortraitHUD does.
func _hold_phone(phone: Vector2) -> void:
	Screen.apply_size(phone)
	toolbar.size = Vector2(phone.x, Screen.portrait_tray_height())
	await process_frames(2)

func _open(section: int) -> void:
	toolbar.select_section(section)
	await process_frames(2)

## The tabs the open section shows, left to right.
func _shown_tabs() -> Array[PixelCircleButton]:
	var tabs: Array[PixelCircleButton] = []
	for tab in TerrainToolbar.SECTION_TABS[toolbar.current_section]:
		var button: PixelCircleButton = toolbar._tab_buttons[tab]
		if button.visible:
			tabs.append(button)
	return tabs

## A tab's rectangle in the shelf's own coordinates.
func _in_shelf(tab: Control) -> Rect2:
	return Rect2(tab.get_global_rect().position - toolbar.get_global_position(), tab.size)

## The row of `tabs` fills the shelf: flush to both side margins, one gap
## between neighbours, equal shares, every tab a full-height wide face.
func _assert_row_fills_the_shelf(tabs: Array[PixelCircleButton], where: String) -> void:
	var margin := TerrainToolbar.PORTRAIT_TAB_SIDE_MARGIN
	assert_almost_eq(_in_shelf(tabs[0]).position.x, margin, 0.01,
		"%s: the first tab starts at the side margin" % where)
	assert_almost_eq(_in_shelf(tabs[-1]).end.x, toolbar.size.x - margin, 0.01,
		"%s: the last tab ends at the other side margin" % where)
	var widest := 0.0
	var narrowest := INF
	for i in tabs.size():
		var tab := tabs[i]
		var rect := _in_shelf(tab)
		widest = maxf(widest, rect.size.x)
		narrowest = minf(narrowest, rect.size.x)
		assert_true(tab.wide_face, "%s: %s is a full-width tab" % [where, tab.caption])
		assert_almost_eq(rect.size.y, TerrainToolbar.PORTRAIT_TAB_FACE_HEIGHT, 0.01,
			"%s: %s keeps the tab height" % [where, tab.caption])
		assert_almost_eq(rect.position.y, TerrainToolbar.PORTRAIT_TAB_TOP, 0.01,
			"%s: %s sits in the one row at the top of the tray" % [where, tab.caption])
		assert_gt(rect.size.x, rect.size.y, "%s: %s is wider than it is tall" % [where, tab.caption])
		assert_eq(rect.position.x, roundf(rect.position.x),
			"%s: %s starts on a whole pixel" % [where, tab.caption])
		assert_eq(rect.size.x, roundf(rect.size.x),
			"%s: %s is a whole number of pixels wide" % [where, tab.caption])
		assert_true(tab._has_point(Vector2(1, 1)) and tab._has_point(rect.size - Vector2.ONE),
			"%s: all of %s is a touch target, corners included" % [where, tab.caption])
		if i > 0:
			assert_almost_eq(rect.position.x - _in_shelf(tabs[i - 1]).end.x,
				TerrainToolbar.PORTRAIT_TAB_GAP, 0.01,
				"%s: one gap separates %s from the tab before it" % [where, tab.caption])
	assert_lte(widest - narrowest, 1.0,
		"%s: the tabs share the row equally, to the pixel" % where)


func test_the_page_tabs_share_the_whole_tray_width_on_every_phone() -> void:
	for phone: Vector2 in PHONES:
		await _hold_phone(phone)
		assert_true(Screen.uses_portrait_hud(), "%s is a phone held upright" % phone)
		assert_almost_eq(toolbar.size.x, phone.x, 0.01, "The tray is as wide as the phone")
		for section in TerrainToolbar.SECTION_TABS:
			await _open(section)
			var tabs := _shown_tabs()
			assert_eq(tabs.size(), TerrainToolbar.SECTION_TABS[section].size(),
				"%s shows all of its tabs" % TerrainToolbar.SECTION_TITLES[section])
			_assert_row_fills_the_shelf(tabs,
				"%s, %s" % [phone, TerrainToolbar.SECTION_TITLES[section]])


func test_the_row_is_as_wide_as_the_thumb_rail_under_the_tray() -> void:
	# Three page tabs take exactly the cells BottomControlDock gives the three
	# section buttons: the same margins, the same gap, the same share.
	for phone: Vector2 in PHONES:
		await _hold_phone(phone)
		await _open(TerrainToolbar.Section.MANAGE)
		var tabs := _shown_tabs()
		var cell := (phone.x - 16.0 - 2.0 * 4.0) / 3.0
		for i in tabs.size():
			var rect := _in_shelf(tabs[i])
			assert_almost_eq(rect.position.x, 8.0 + i * (cell + 4.0), 0.5,
				"%s: %s starts where its section button's column starts" % [phone, tabs[i].caption])
			assert_almost_eq(rect.end.x, 8.0 + i * (cell + 4.0) + cell, 0.5,
				"%s: %s ends where that column ends" % [phone, tabs[i].caption])


func test_every_tab_wears_its_caption_under_its_icon_and_the_caption_fits() -> void:
	# The narrowest phone is the hard case: four tabs of 73px each, and
	# "Elevation" beside an icon would need 78px.
	await _hold_phone(PHONES[0])
	for section in TerrainToolbar.SECTION_TABS:
		await _open(section)
		for tab in TerrainToolbar.SECTION_TABS[section]:
			var button: PixelCircleButton = toolbar._tab_buttons[tab]
			var caption: String = TerrainToolbar.PORTRAIT_TAB_CAPTIONS[tab]
			assert_eq(button.caption, caption, "%s is captioned" % TerrainToolbar.TAB_TITLES[tab])
			assert_true(button.is_stacked(), "%s stacks its caption under its icon" % caption)
			var face := Rect2(Vector2.ZERO, button.size).grow(-2.0)
			var text := button.stacked_caption_rect()
			assert_true(face.encloses(button.stacked_icon_rect()), "%s: the icon fits the tab" % caption)
			assert_true(face.encloses(text), "%s: the caption fits the tab" % caption)
			assert_almost_eq(text.size.x, PixelCircleButton.FONT.get_string_size(
				caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 0.01,
				"%s is drawn whole, not trimmed" % caption)
			assert_eq(button.tooltip_text, TerrainToolbar.TAB_TITLES[tab],
				"%s still carries its full title for assistive tech" % caption)
			assert_eq(button.accessibility_name, TerrainToolbar.TAB_TITLES[tab])


func test_only_the_tabs_on_show_share_the_row() -> void:
	# Tournament Mode has no golfer to edit or train: the two Golfers tabs it
	# leaves take half the tray each instead of two cells out of four.
	await _hold_phone(Vector2(390, 844))
	GameManager.is_tournament_mode = true
	toolbar.select_tab(TerrainToolbar.Tab.PLAYER)
	await process_frames(2)
	var tabs := _shown_tabs()
	assert_eq(tabs.size(), 2, "Tournament Mode hides Edit and Skills")
	assert_eq(tabs[0], toolbar._tab_buttons[TerrainToolbar.Tab.GOLFERS])
	assert_eq(tabs[1], toolbar._tab_buttons[TerrainToolbar.Tab.PLAYER])
	_assert_row_fills_the_shelf(tabs, "Tournament Mode")
	assert_almost_eq(tabs[0].size.x, (390.0 - 16.0 - 4.0) * 0.5, 0.5,
		"Each of the two tabs takes half the row")
	# Back in a career, all four return and share the row again.
	GameManager.is_tournament_mode = false
	toolbar.select_tab(TerrainToolbar.Tab.PLAYER)
	await process_frames(2)
	tabs = _shown_tabs()
	assert_eq(tabs.size(), 4, "A career shows all four Golfers tabs")
	_assert_row_fills_the_shelf(tabs, "Back in a career")


func test_the_row_follows_the_tray_when_the_phone_changes_width() -> void:
	await _hold_phone(Vector2(540, 960))
	await _open(TerrainToolbar.Section.BUILD)
	var wide := _shown_tabs()[0].size.x
	await _hold_phone(Vector2(320, 568))
	var tabs := _shown_tabs()
	assert_lt(tabs[0].size.x, wide, "A narrower phone gets narrower tabs")
	_assert_row_fills_the_shelf(tabs, "After narrowing")
	await _hold_phone(Vector2(540, 960))
	tabs = _shown_tabs()
	assert_almost_eq(tabs[0].size.x, wide, 0.01, "and widening it gives the width back")
	_assert_row_fills_the_shelf(tabs, "After widening")


func test_switching_tabs_never_shrinks_a_tab_back_to_a_square() -> void:
	# Every selection re-applies the portrait dress. It must leave the widths
	# the layout gave the tabs alone, or the row would flash as 48px squares
	# until the next layout pass.
	await _hold_phone(Vector2(390, 844))
	await _open(TerrainToolbar.Section.BUILD)
	var before: Array[Rect2] = []
	for tab in _shown_tabs():
		before.append(_in_shelf(tab))
	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	var tabs := _shown_tabs()
	for i in tabs.size():
		assert_eq(_in_shelf(tabs[i]), before[i],
			"%s keeps its place and width the moment a tab is chosen" % tabs[i].caption)


func test_the_skill_point_badge_rides_the_skills_tabs_corner_clear_of_its_face() -> void:
	# The badge straddles the tab's top-right corner, as it does on the round
	# medallion. On the narrowest tab it must still miss the icon and the
	# caption, and stay inside the tray.
	await _hold_phone(PHONES[0])
	await _open(TerrainToolbar.Section.GOLFERS)
	var skills: PixelCircleButton = toolbar._tab_buttons[TerrainToolbar.Tab.PLAYER_SKILLS]
	var badge: Label = toolbar.player_tab.skill_badge
	assert_eq(badge.get_parent(), skills, "The badge rides on the Skills tab")
	for points in [3, 12]:
		toolbar.player_tab.set_unused_skill_points(points)
		await process_frames(1)
		assert_true(badge.visible, "%d points to spend show the badge" % points)
		var on_tab := Rect2(badge.position, badge.size)
		assert_almost_eq(on_tab.end.x, skills.size.x + 4.0, 0.01,
			"%d: the badge hangs off the tab's right edge" % points)
		assert_almost_eq(on_tab.position.y, -2.0, 0.01, "%d: and just over its top" % points)
		# Grown by the icon's shadow and the nudge of a selected tab.
		assert_false(on_tab.intersects(skills.stacked_icon_rect().grow(4.0)),
			"%d: the badge leaves the icon alone" % points)
		assert_false(on_tab.intersects(skills.stacked_caption_rect()),
			"%d: and the caption" % points)
		var in_shelf := Rect2(badge.get_global_rect().position - toolbar.get_global_position(),
			badge.size)
		assert_true(Rect2(Vector2.ZERO, toolbar.size).encloses(in_shelf),
			"%d: the badge %s stays inside the tray" % [points, in_shelf])


func test_turning_the_phone_on_its_side_hands_the_medallions_back() -> void:
	await _hold_phone(Vector2(390, 844))
	await _open(TerrainToolbar.Section.MANAGE)
	assert_true(_shown_tabs()[0].wide_face, "Upright, the tabs are wide")
	# Landscape and desktop both wear the curved rail of round medallions.
	for window: Vector2 in [Vector2(844, 390), Vector2(1600, 1000)]:
		Screen.apply_size(window)
		await process_frames(2)
		assert_false(Screen.uses_portrait_hud(), "%s is not the portrait HUD" % window)
		for tab in toolbar._tab_buttons:
			var button: PixelCircleButton = toolbar._tab_buttons[tab]
			var title: String = TerrainToolbar.TAB_TITLES[tab]
			assert_false(button.wide_face, "%s: %s is a medallion again" % [window, title])
			assert_false(button.is_stacked(), "%s: %s stacks nothing" % [window, title])
			assert_eq(button.caption, "", "%s: %s drops its caption" % [window, title])
			assert_eq(button.size, Vector2.ONE * TerrainToolbar.TAB_DIAMETER,
				"%s: %s is round and the rail's one diameter" % [window, title])
			assert_false(button._has_point(Vector2(1, 1)),
				"%s: %s answers only inside its circle" % [window, title])
		# And upright again they stretch back out.
		await _hold_phone(Vector2(390, 844))
		_assert_row_fills_the_shelf(_shown_tabs(), "Upright again after %s" % window)
