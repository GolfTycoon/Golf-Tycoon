extends GameTest
## The shelf's tool buttons in the portrait HUD: the brush shape, the brush size
## stepper, the Bulldozer and Inspect. On a phone held upright they do not ride
## inside the tray. They float over the course just above the tray's top-right
## corner, level with the camera rail that holds the opposite corner, and they
## come and go with the tray. A whole brush (shape, size stepper, Inspect) is
## too wide to share that band with the rail on most phones, so its size
## stepper stands on a second row above the rest. Turning the phone on its side
## hands the one desktop row back to the shelf.
##
## The toolbar is built on its own here and placed where PortraitHUD places the
## tray; the real HUD, the real camera rail and real taps are covered by the
## portrait HUD integration tests.

const PHONES := [Vector2(320, 568), Vector2(360, 640), Vector2(375, 667),
	Vector2(390, 844), Vector2(412, 915), Vector2(430, 932), Vector2(540, 960)]
## A whole brush is 250px wide. Beside the 188px camera rail, 16px clear of it
## and 8px in from either side, that takes a tray of 470px.
const NARROW_PHONES := [Vector2(320, 568), Vector2(390, 844), Vector2(430, 932), Vector2(469, 900)]
const WIDE_PHONES := [Vector2(470, 900), Vector2(540, 960), Vector2(600, 1024)]
const BUILD_TABS: Array = TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.BUILD]
const BRUSH_TABS := [TerrainToolbar.Tab.TERRAIN, TerrainToolbar.Tab.ELEVATION]
const BULLDOZER_TABS := [TerrainToolbar.Tab.IMPROVEMENTS, TerrainToolbar.Tab.BUILDINGS]
const LIFT := TerrainToolbar.PORTRAIT_TOOLS_LIFT
const SIDE := TerrainToolbar.PORTRAIT_TOOLS_SIDE_MARGIN
const CELL := TerrainToolbar.BRUSH_DOCK_CELL

var toolbar: TerrainToolbar
var _window_size: Vector2 = Vector2(1600, 1000)
var _tools_open := false

## Pin the window size the way the toolbar tests do: the headless window is
## 64x64 and Screen's per-frame polling would put it back. The tray is open,
## as it is whenever the shelf is on show.
func before_each() -> void:
	super()
	_window_size = Screen.window_size
	_tools_open = Screen.portrait_tools_open
	Screen.set_process(false)
	Screen.apply_size(PHONES[0])
	Screen.set_portrait_tools_open(true)
	toolbar = TerrainToolbar.new()
	add_child_autofree(toolbar)

func after_each() -> void:
	# Switching tabs rebuilds tiles with queue_free(); let those frees land
	# before GUT counts orphans.
	await process_frames(1)
	Screen.set_portrait_tools_open(_tools_open)
	# Reads the display's own safe area back, undoing any cutouts a test set.
	Screen.apply_size(_window_size)
	Screen.set_process(true)
	super()

## Resize the phone and seat the shelf where PortraitHUD seats the tray: across
## the safe width, on top of the thumb rail. `cutouts` are the phone's safe
## area insets (left, top, right, bottom); resizing reads the display's own,
## which a desktop has none of, so they are set afterwards.
func _hold_phone(phone: Vector2, cutouts: Vector4 = Vector4.ZERO) -> void:
	Screen.apply_size(phone)
	if Screen.safe_insets != cutouts:
		Screen.safe_insets = cutouts
		Screen.changed.emit(Screen.window_size, Screen.world_scale)
	var tray_height := Screen.portrait_tray_height()
	toolbar.position = Vector2(Screen.safe_insets.x,
		phone.y - Screen.portrait_nav_height() - tray_height)
	toolbar.size = Vector2(phone.x - Screen.safe_insets.x - Screen.safe_insets.z, tray_height)
	await process_frames(2)

func _open(tab: int) -> void:
	toolbar.select_tab(tab)
	await process_frames(2)

## Where PortraitHUD seats the camera rail: the bottom-left corner of the
## course view.
func _camera_rail() -> Rect2:
	var course := Screen.portrait_course_rect()
	return Rect2(course.position.x, course.end.y - PortraitHUD.CAMERA_ACTION_SIZE,
		PortraitHUD.CAMERA_RAIL_WIDTH, PortraitHUD.CAMERA_ACTION_SIZE)

## The two size steppers, whichever row they stand in.
func _steppers() -> Array[Control]:
	return [toolbar._header_terrain_size, toolbar._header_elevation_size]

## The brush shape and size stepper of a brush tab.
func _brush(tab: int) -> Array[Control]:
	if tab == TerrainToolbar.Tab.TERRAIN:
		return [toolbar._header_terrain_shape, toolbar._header_terrain_size]
	return [toolbar._header_elevation_shape, toolbar._header_elevation_size]

## Every tool on show, cell by cell: a size stepper counts as its two step
## buttons and the readout between them.
func _shown_tools() -> Array[Control]:
	var tools: Array[Control] = []
	for row: Control in [toolbar._header_row, toolbar._header_upper_row]:
		if not row.is_visible_in_tree():
			continue
		for child: Control in row.get_children():
			if not child.visible:
				continue
			if child in _steppers():
				for cell: Control in child.get_children():
					tools.append(cell)
			else:
				tools.append(child)
	return tools

func _names(controls: Array) -> Array:
	return controls.map(func(control: Control) -> String: return str(control.name))


func test_the_tools_float_over_the_course_above_the_tray_on_every_phone() -> void:
	for phone: Vector2 in PHONES:
		await _hold_phone(phone)
		assert_true(Screen.uses_portrait_hud(), "%s is a phone held upright" % phone)
		var tray := toolbar.get_global_rect()
		var course := Screen.portrait_course_rect()
		var rail := _camera_rail()
		assert_almost_eq(tray.position.y - LIFT, course.end.y, 0.01,
			"%s: the course view ends one lift above the tray" % phone)
		for tab: int in BUILD_TABS:
			await _open(tab)
			var where := "%s, %s" % [phone, TerrainToolbar.TAB_TITLES[tab]]
			var tools := _shown_tools()
			assert_gte(tools.size(), 2, "%s shows its tools" % where)
			var cluster := tools[0].get_global_rect()
			for tool in tools:
				var rect := tool.get_global_rect()
				cluster = cluster.merge(rect)
				assert_false(rect.intersects(tray),
					"%s: %s %s is not inside the tray" % [where, tool.name, rect])
				assert_lte(rect.end.y, tray.position.y - LIFT + 0.01,
					"%s: %s stands above the tray" % [where, tool.name])
				assert_true(course.grow(0.01).encloses(rect),
					"%s: %s %s is over the course view %s" % [where, tool.name, rect, course])
				assert_false(rect.intersects(rail),
					"%s: %s %s leaves the camera rail %s alone" % [where, tool.name, rect, rail])
				if rect.end.y > rail.position.y:
					assert_gte(rect.position.x - rail.end.x,
						TerrainToolbar.PORTRAIT_TOOLS_RAIL_GAP - 0.01,
						"%s: %s keeps its distance from the rail it shares the band with" % [where, tool.name])
				assert_gte(rect.size.x, 44.0, "%s: %s is a touch target" % [where, tool.name])
				assert_gte(rect.size.y, 44.0, "%s: %s is a touch target" % [where, tool.name])
				assert_eq(rect.position, rect.position.round(),
					"%s: %s sits on whole pixels" % [where, tool.name])
			assert_almost_eq(cluster.end.y, tray.position.y - LIFT, 0.01,
				"%s: the tools stand one lift above the tray" % where)
			assert_almost_eq(cluster.end.y, rail.end.y, 0.01,
				"%s: on the line the camera rail stands on" % where)
			assert_almost_eq(cluster.end.x, tray.end.x - SIDE, 0.01,
				"%s: flush with the tray's right margin" % where)
			assert_almost_eq(cluster.end.x, course.end.x, 0.01,
				"%s: which is the course view's right edge" % where)
			assert_almost_eq(toolbar.inspect_button().get_global_rect().end, cluster.end,
				Vector2(0.01, 0.01), "%s: Inspect holds the corner" % where)


func test_a_whole_brush_shares_the_band_with_the_camera_rail_where_it_fits() -> void:
	for phone: Vector2 in WIDE_PHONES:
		await _hold_phone(phone)
		var rail := _camera_rail()
		for tab: int in BRUSH_TABS:
			await _open(tab)
			var where := "%s, %s" % [phone, TerrainToolbar.TAB_TITLES[tab]]
			var shape := _brush(tab)[0]
			var stepper := _brush(tab)[1]
			var inspect := toolbar.inspect_button()
			assert_eq(stepper.get_parent(), toolbar._header_row,
				"%s: the size stepper rides in the one row" % where)
			assert_false(toolbar._header_upper_row.visible, "%s: there is no second row" % where)
			var row := toolbar._header_row.get_global_rect()
			assert_almost_eq(row.size, Vector2(3.0 * CELL + stepper.size.x - CELL
				+ 2.0 * TerrainToolbar.HEADER_ROW_GAP, CELL), Vector2(0.01, 0.01),
				"%s: the row is the brush, the stepper and Inspect, a gap apart" % where)
			assert_almost_eq(row.end.y, rail.end.y, 0.01, "%s: the row stands level with the rail" % where)
			assert_gte(row.position.x - rail.end.x, TerrainToolbar.PORTRAIT_TOOLS_RAIL_GAP - 0.01,
				"%s: and clear of it" % where)
			# Left to right: shape, stepper, Inspect, as on the desktop shelf.
			assert_almost_eq(stepper.get_global_rect().position.x - shape.get_global_rect().end.x,
				TerrainToolbar.HEADER_ROW_GAP, 0.01, "%s: the stepper follows the shape" % where)
			assert_almost_eq(inspect.get_global_rect().position.x - stepper.get_global_rect().end.x,
				TerrainToolbar.HEADER_ROW_GAP, 0.01, "%s: Inspect follows the stepper" % where)
	# The narrowest tray a brush fits is a tight fit: exactly the rail's gap.
	await _hold_phone(WIDE_PHONES[0])
	await _open(TerrainToolbar.Tab.TERRAIN)
	assert_almost_eq(toolbar._header_row.get_global_rect().position.x - _camera_rail().end.x,
		TerrainToolbar.PORTRAIT_TOOLS_RAIL_GAP, 0.01,
		"At %s the brush has the rail's gap and nothing to spare" % WIDE_PHONES[0])


func test_on_a_narrow_phone_the_size_stepper_stands_above_the_brush() -> void:
	for phone: Vector2 in NARROW_PHONES:
		await _hold_phone(phone)
		var rail := _camera_rail()
		var inspect := toolbar.inspect_button()
		var corner: Rect2
		var beside: Rect2
		for tab: int in BRUSH_TABS:
			await _open(tab)
			var where := "%s, %s" % [phone, TerrainToolbar.TAB_TITLES[tab]]
			var shape := _brush(tab)[0]
			var stepper := _brush(tab)[1]
			assert_eq(stepper.get_parent(), toolbar._header_upper_row,
				"%s: the size stepper moves to the upper row" % where)
			assert_true(toolbar._header_upper_row.visible, "%s: which is on show" % where)
			var lower := toolbar._header_row.get_global_rect()
			var upper := toolbar._header_upper_row.get_global_rect()
			assert_eq(_shown_tools().size(), 5, "%s: shape, Inspect and the stepper's three cells" % where)
			assert_almost_eq(upper.size, stepper.size, Vector2(0.01, 0.01),
				"%s: the upper row is the stepper and nothing more" % where)
			assert_almost_eq(upper.end.y, lower.position.y - TerrainToolbar.BRUSH_DOCK_GAP, 0.01,
				"%s: the stepper stands on the lower row, one cell gap above it" % where)
			assert_almost_eq(upper.end.x, lower.end.x, 0.01,
				"%s: the rows share the right margin" % where)
			assert_lte(upper.end.y, rail.position.y, "%s: the stepper stands clear above the rail" % where)
			# One grid: the shape sits under the readout, Inspect under the plus.
			var cells := stepper.get_children()
			assert_eq(cells.size(), 3, "%s: a stepper is smaller, the size, bigger" % where)
			assert_almost_eq(shape.get_global_rect().position.x,
				(cells[1] as Control).get_global_rect().position.x, 0.01,
				"%s: the brush shape stands under the size readout" % where)
			assert_almost_eq(inspect.get_global_rect().position.x,
				(cells[2] as Control).get_global_rect().position.x, 0.01,
				"%s: Inspect stands under the bigger-brush button" % where)
			assert_almost_eq(lower.size, Vector2(2.0 * CELL + TerrainToolbar.BRUSH_DOCK_GAP, CELL),
				Vector2(0.01, 0.01), "%s: the lower row is the shape and Inspect" % where)
			if tab == BRUSH_TABS[0]:
				corner = inspect.get_global_rect()
				beside = shape.get_global_rect()
			else:
				assert_eq(inspect.get_global_rect(), corner, "%s: Inspect keeps its corner" % where)
				assert_eq(shape.get_global_rect(), beside, "%s: the shape keeps its place" % where)
		# The Bulldozer pages have no stepper: one row, in the same two seats.
		for tab: int in BULLDOZER_TABS:
			await _open(tab)
			var where := "%s, %s" % [phone, TerrainToolbar.TAB_TITLES[tab]]
			assert_false(toolbar._header_upper_row.visible, "%s: no stepper, no upper row" % where)
			assert_eq(_shown_tools().size(), 2, "%s: the Bulldozer and Inspect" % where)
			assert_eq(inspect.get_global_rect(), corner, "%s: Inspect keeps its corner" % where)
			assert_eq(toolbar._bulldozer_button.get_global_rect(), beside,
				"%s: the Bulldozer takes the brush shape's seat" % where)


func test_the_steppers_move_with_the_tray_width_and_never_with_the_tab() -> void:
	# Reparenting on every tab change would churn focus and layout. Both
	# steppers go up or come down together, whichever page is open.
	for phone: Vector2 in [NARROW_PHONES[0], WIDE_PHONES[1], NARROW_PHONES[1], WIDE_PHONES[0]]:
		await _hold_phone(phone)
		var home: Control = toolbar._header_upper_row if phone in NARROW_PHONES else toolbar._header_row
		for section in TerrainToolbar.SECTION_TABS:
			for tab: int in TerrainToolbar.SECTION_TABS[section]:
				await _open(tab)
				for stepper in _steppers():
					assert_eq(stepper.get_parent(), home, "%s, %s: both steppers stay in %s" % [
						phone, TerrainToolbar.TAB_TITLES[tab], home.name])
		assert_eq(toolbar._header_row.get_child_count() + toolbar._header_upper_row.get_child_count(), 6,
			"%s: the six tools are moved, never copied" % phone)
		if home == toolbar._header_row:
			assert_eq(toolbar._header_row.get_children(), [toolbar._header_terrain_shape,
				toolbar._header_terrain_size, toolbar._bulldozer_button, toolbar._header_elevation_shape,
				toolbar._header_elevation_size, toolbar.inspect_button()],
				"%s: each stepper is back straight after its brush shape: %s" % [
					phone, _names(toolbar._header_row.get_children())])


func test_a_moved_stepper_still_drives_its_brush() -> void:
	await _hold_phone(NARROW_PHONES[0])
	await _open(TerrainToolbar.Tab.TERRAIN)
	watch_signals(toolbar)
	toolbar.set_brush_size(3)
	var terrain := toolbar._header_terrain_size
	assert_eq(terrain.get_parent(), toolbar._header_upper_row, "The terrain stepper is stacked")
	var readout := terrain.get_child(1) as Label
	assert_eq(readout.text, "3", "The stacked readout follows the brush")
	(terrain.get_child(2) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "brush_size_changed", [4])
	assert_eq(readout.text, "4", "Bigger steps the brush up")
	(terrain.get_child(0) as Button).pressed.emit()
	assert_eq(toolbar.get_brush_size(), 3, "Smaller steps it back down")
	# A single-tile tool still locks the stacked stepper with the shape.
	toolbar.set_brush_limit(1)
	assert_true((terrain.get_child(2) as Button).disabled, "A one-tile tool locks the stacked stepper")
	assert_true(toolbar._header_terrain_shape.disabled, "and the shape under it")
	toolbar.set_brush_limit(HoleLayout.UNLIMITED_BRUSH)
	toolbar.set_brush_size(1)

	await _open(TerrainToolbar.Tab.ELEVATION)
	var elevation := toolbar._header_elevation_size
	assert_eq(elevation.get_parent(), toolbar._header_upper_row, "The elevation stepper is stacked")
	var before := toolbar._elevation_size
	(elevation.get_child(2) as Button).pressed.emit()
	assert_signal_emitted(toolbar, "elevation_brush_size_changed")
	assert_gt(toolbar._elevation_size, before, "Bigger steps the elevation brush up")
	assert_eq((elevation.get_child(1) as Label).text, str(toolbar._elevation_size),
		"and its stacked readout follows")
	(elevation.get_child(0) as Button).pressed.emit()
	assert_eq(toolbar._elevation_size, before, "Smaller steps it back down")


func test_only_the_build_pages_show_tools_and_every_page_keeps_its_heading() -> void:
	for phone: Vector2 in [NARROW_PHONES[0], WIDE_PHONES[1]]:
		await _hold_phone(phone)
		var tray := toolbar.get_global_rect()
		for section in TerrainToolbar.SECTION_TABS:
			for tab: int in TerrainToolbar.SECTION_TABS[section]:
				await _open(tab)
				var where := "%s, %s" % [phone, TerrainToolbar.TAB_TITLES[tab]]
				if section == TerrainToolbar.Section.BUILD:
					assert_true(toolbar._header_row.visible, "%s shows tools" % where)
					assert_true(toolbar.inspect_button().is_visible_in_tree(), "%s: Inspect among them" % where)
				else:
					assert_false(toolbar._header_row.visible, "%s shows no tool row" % where)
					assert_false(toolbar._header_upper_row.visible, "%s: nor a stepper row" % where)
					assert_eq(_shown_tools().size(), 0, "%s has no tools over the course" % where)
				# With the tools out of the tray, the row under the tabs is
				# the heading's on every page.
				var title := toolbar._page_title
				assert_true(title.is_visible_in_tree(), "%s keeps its heading" % where)
				assert_string_contains(title.text, TerrainToolbar.TAB_TITLES[tab])
				var heading := title.get_global_rect()
				assert_true(tray.encloses(heading), "%s: the heading %s is inside the tray" % [where, heading])
				assert_gte(heading.position.y, toolbar._tab_buttons[tab].get_global_rect().end.y,
					"%s: under the page tabs" % where)
				assert_lt(heading.get_center().y, toolbar._pages_container.get_global_rect().position.y,
					"%s: over the page" % where)
				assert_almost_eq(heading.size.x, tray.size.x - 24.0, 0.01,
					"%s: across the tray, no longer cut short by a tool row" % where)


func test_the_tools_come_and_go_with_the_tray() -> void:
	await _hold_phone(NARROW_PHONES[0])
	await _open(TerrainToolbar.Tab.TERRAIN)
	var inspect := toolbar.inspect_button().get_global_rect()
	assert_eq(_shown_tools().size(), 5, "An open tray shows the brush tools")
	toolbar.collapse_section()
	await process_frames(2)
	assert_false(toolbar._header_row.is_visible_in_tree(), "Putting the tray away takes the tool row with it")
	assert_false(toolbar._header_upper_row.is_visible_in_tree(), "and the stepper row")
	assert_eq(_shown_tools().size(), 0, "No tool is left floating over the course")
	toolbar.expand_section()
	await process_frames(2)
	assert_eq(_shown_tools().size(), 5, "Opening the tray brings them back")
	assert_eq(toolbar.inspect_button().get_global_rect(), inspect, "where they were")


func test_the_tools_respect_the_side_cutouts() -> void:
	for phone: Vector2 in [Vector2(390, 844), Vector2(540, 960)]:
		await _hold_phone(phone, Vector4(12, 44, 20, 34))
		assert_almost_eq(toolbar.size.x, phone.x - 32.0, 0.01, "%s: the tray spans the safe width" % phone)
		var course := Screen.portrait_course_rect()
		var rail := _camera_rail()
		for tab: int in BUILD_TABS:
			await _open(tab)
			var where := "%s with cutouts, %s" % [phone, TerrainToolbar.TAB_TITLES[tab]]
			for tool in _shown_tools():
				var rect := tool.get_global_rect()
				assert_lte(rect.end.x, phone.x - 20.0 - SIDE + 0.01, "%s: %s clears the right cutout" % [where, tool.name])
				assert_true(course.grow(0.01).encloses(rect), "%s: %s stays over the course view" % [where, tool.name])
				assert_false(rect.intersects(rail), "%s: %s leaves the inset camera rail alone" % [where, tool.name])
			assert_almost_eq(toolbar.inspect_button().get_global_rect().end.x, phone.x - 20.0 - SIDE, 0.01,
				"%s: Inspect sits at the safe right margin" % where)


func test_the_rows_are_solid_touch_targets_only_over_the_course() -> void:
	# Over the course a tap between two buttons, or on the size readout, must
	# land on the row and not on the tile behind it. On the desktop shelf the
	# row lets those through to the page and the course, as it always has.
	await _hold_phone(NARROW_PHONES[0])
	await _open(TerrainToolbar.Tab.TERRAIN)
	assert_eq(toolbar._header_row.mouse_filter, Control.MOUSE_FILTER_STOP, "Upright, the tool row stops the pointer")
	assert_eq(toolbar._header_upper_row.mouse_filter, Control.MOUSE_FILTER_STOP, "and so does the stepper row")
	var readout := toolbar._header_terrain_size.get_child(1) as Control
	assert_eq(readout.mouse_filter, Control.MOUSE_FILTER_IGNORE, "The size readout itself takes no input")
	assert_true(toolbar._header_upper_row.get_global_rect().encloses(readout.get_global_rect()),
		"so the row behind it is what a tap on it lands on")
	await _hold_phone(WIDE_PHONES[1])
	assert_eq(toolbar._header_row.mouse_filter, Control.MOUSE_FILTER_STOP, "A wide phone's one row stops the pointer too")
	Screen.apply_size(Vector2(1600, 1000))
	await process_frames(2)
	assert_eq(toolbar._header_row.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"On the desktop shelf the row passes the pointer through again")


func test_turning_the_phone_on_its_side_hands_the_shelf_its_one_row_back() -> void:
	var desktop_order: Array = [toolbar._header_terrain_shape, toolbar._header_terrain_size,
		toolbar._bulldozer_button, toolbar._header_elevation_shape,
		toolbar._header_elevation_size, toolbar.inspect_button()]
	await _hold_phone(NARROW_PHONES[1])
	await _open(TerrainToolbar.Tab.TERRAIN)
	assert_eq(toolbar._header_terrain_size.get_parent(), toolbar._header_upper_row, "Upright, the stepper is stacked")
	# Landscape and desktop both wear the shelf with its single header row.
	for window: Vector2 in [Vector2(844, 390), Vector2(1600, 1000)]:
		Screen.apply_size(window)
		toolbar.position = Vector2(0.0, 400.0)
		toolbar.size = Vector2(700.0, Screen.bottom_bar_height())
		await process_frames(2)
		assert_false(Screen.uses_portrait_hud(), "%s is not the portrait HUD" % window)
		assert_eq(toolbar._header_row.get_children(), desktop_order,
			"%s: the row holds all six tools in their desktop order: %s" % [
				window, _names(toolbar._header_row.get_children())])
		assert_eq(toolbar._header_upper_row.get_child_count(), 0, "%s: the upper row is empty" % window)
		assert_false(toolbar._header_upper_row.visible, "%s: and hidden" % window)
		assert_eq(toolbar._header_row.get_theme_constant("separation"), int(TerrainToolbar.HEADER_ROW_GAP),
			"%s: the row spaces its tools as the desktop does" % window)
		var shelf := toolbar.get_global_rect()
		var row := toolbar._header_row.get_global_rect()
		assert_true(toolbar._header_row.visible, "%s: the row is on show" % window)
		assert_almost_eq(row.end.x - shelf.end.x, -TerrainToolbar.SHELF_PAD_X, 0.01,
			"%s: the row hugs the shelf's right padding" % window)
		assert_almost_eq(row.position.y - shelf.position.y, TerrainToolbar.HEADER_ROW_TOP_OFFSET, 0.01,
			"%s: and straddles the shelf's top border" % window)
		var shape := toolbar._header_terrain_shape.get_global_rect()
		var stepper := toolbar._header_terrain_size.get_global_rect()
		var inspect := toolbar.inspect_button().get_global_rect()
		assert_almost_eq(stepper.position, shape.position + Vector2(CELL + TerrainToolbar.HEADER_ROW_GAP, 0.0),
			Vector2(0.01, 0.01), "%s: the stepper sits beside the shape again" % window)
		assert_almost_eq(inspect.position.x, stepper.end.x + TerrainToolbar.HEADER_ROW_GAP, 0.01,
			"%s: and Inspect beside the stepper" % window)
		# And upright again the stepper goes back up.
		await _hold_phone(NARROW_PHONES[1])
		assert_eq(toolbar._header_terrain_size.get_parent(), toolbar._header_upper_row,
			"Upright again after %s, the stepper is stacked" % window)
		assert_eq(toolbar._header_row.get_theme_constant("separation"), int(TerrainToolbar.BRUSH_DOCK_GAP),
			"and the lower row closes up under it")
