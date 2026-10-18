extends GameTest
## The terrain toolbar along the bottom of the screen: its tabs and their shelves
## of course tiles — Course Terrain, Improvements, Buildings, Holes, Golfers,
## Staff and Elevation — and the controls nestled among them.

var toolbar: TerrainToolbar

## The headless test window is 64x64, which Screen reads as a compact — and so
## touch-sized — layout: 40px tab buttons measured against the 232px touch
## bottom bar. Every height budget below is the desktop one (BOTTOM_BAR_HEIGHT
## and a 32px rail), so each test pins the reference window size and pauses the
## per-frame polling that would put the tiny test window back, then restores
## both. The touch layout has its own coverage in the bottom dock tests.
var _window_size: Vector2 = Vector2(1600, 1000)

func before_each() -> void:
	super()
	_window_size = Screen.window_size
	Screen.set_process(false)
	Screen.apply_size(Screen.BASE_SIZE)
	toolbar = TerrainToolbar.new()
	add_child_autofree(toolbar)

func after_each() -> void:
	# Switching tabs rebuilds tiles with queue_free(); let those frees land
	# before GUT counts orphans.
	await process_frames(1)
	Screen.apply_size(_window_size)
	Screen.set_process(true)
	super()

## The desktop layout the whole file measures against: a toolbar that fits the
## bottom bar with a 32px tab rail, not the compact one the test window implies.
func test_the_toolbar_is_measured_in_the_desktop_layout() -> void:
	assert_false(Screen.uses_touch_layout(), "The tests run the desktop layout")
	assert_eq(Screen.bottom_bar_height(), float(UIConstants.BOTTOM_BAR_HEIGHT),
		"so the bottom bar is the desktop one")
	for button in toolbar._tab_buttons.values():
		assert_eq((button as PixelCircleButton).diameter, 32.0,
			"and the tab rail wears its desktop diameter")

func test_bottom_bar_fits_two_rows_of_course_tiles() -> void:
	assert_eq(UIConstants.BOTTOM_BAR_HEIGHT, 190, "Bottom bar should be tall enough for two tile rows")
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT),
		"Toolbar content must fit inside the bottom bar")

## The Course Terrain tiles in reading order: the top row runs from the tee to
## out of bounds, the bottom row pairs each playing surface with its trouble
## tiles, ending with the two boulder grounds.
const TOP_ROW := [TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.GREEN,
	TerrainTypes.Type.BUNKER, TerrainTypes.Type.ROUGH, TerrainTypes.Type.POT_BUNKER,
	TerrainTypes.Type.STREAM, TerrainTypes.Type.WATER, TerrainTypes.Type.OUT_OF_BOUNDS]

const BOTTOM_ROW := [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY,
	TerrainTypes.Type.DEEP_ROUGH, TerrainTypes.Type.WASTE_BUNKER, TerrainTypes.Type.BRUSH,
	TerrainTypes.Type.ROCKS, TerrainTypes.Type.SMALL_BOULDERS,
	TerrainTypes.Type.LARGE_BOULDERS]

func test_course_tiles_share_one_group_in_top_and_bottom_rows() -> void:
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent()
	var landscape_count := 1 + CourseTheme.get_tree_types(GameManager.current_theme).size()
	assert_eq(grid.columns, TOP_ROW.size() + ceili(float(landscape_count) / 2.0))
	assert_eq(grid.flow_children().size(),
		TOP_ROW.size() + BOTTOM_ROW.size() + landscape_count,
		"All course and landscape tiles share exactly two rows")
	for tool_type in TOP_ROW + BOTTOM_ROW:
		assert_eq(toolbar._tool_buttons[tool_type].get_parent(), grid,
			"Course tiles should live in the same group")

	# Reading order: the tiles take slots in the order they are children. The
	# nestled Open Hole button is not a tile, so it holds no slot (see
	# test_open_hole_nests_into_the_notch_between_the_tee_and_green_tiles).
	var tiles: Array[Control] = grid.flow_children()
	for slot in TOP_ROW.size():
		assert_eq(tiles.find(toolbar._tool_buttons[TOP_ROW[slot]]), slot,
			"%s is tile %d of the top row" % [TerrainTypes.get_type_name(TOP_ROW[slot]), slot])
	for slot in BOTTOM_ROW.size():
		assert_eq(tiles.find(toolbar._tool_buttons[BOTTOM_ROW[slot]]), grid.columns + slot,
			"%s is tile %d of the bottom row" % [TerrainTypes.get_type_name(BOTTOM_ROW[slot]), slot])

	# The rows are drawn staggered: the bottom row sits half a tile below the top.
	await _settle_layout()
	var top_y: float = toolbar._tool_buttons[TOP_ROW[0]].position.y
	for tool_type in TOP_ROW:
		assert_almost_eq(toolbar._tool_buttons[tool_type].position.y, top_y, 0.01,
			"%s sits on the top row" % TerrainTypes.get_type_name(tool_type))
	for tool_type in BOTTOM_ROW:
		assert_almost_eq(toolbar._tool_buttons[tool_type].position.y,
			top_y + grid.tile_size.y * 0.5 + grid.v_separation, 0.01,
			"%s sits on the bottom row" % TerrainTypes.get_type_name(tool_type))

func test_bottom_row_is_shifted_right_into_the_notches_of_the_top_row() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent()
	var pitch := grid.tile_size.x + grid.h_separation
	var tiles: Array[Control] = grid.flow_children()
	var bottom_count := tiles.size() - grid.columns

	for i in bottom_count:
		var below: Control = tiles[grid.columns + i]
		var above_left: Control = tiles[i]

		# Half a tile to the right of the tile above: the row is staggered.
		assert_almost_eq(below.position.x - above_left.position.x, pitch * 0.5, 0.01,
			"Bottom row tile %d should be shifted half a tile to the right" % i)
		if i + 1 < grid.columns:
			# Centred on the gap between the two tiles above it.
			var above_right: Control = tiles[i + 1]
			assert_almost_eq(below.position.x,
				(above_left.position.x + above_right.position.x) * 0.5, 0.01,
				"Bottom row tile %d should sit in the notch between two top row tiles" % i)

		# Half a tile down: tucked into the row above instead of stacked below
		# it, while staying clear of the breathing room above the first row.
		assert_almost_eq(below.position.y,
			grid.v_padding + grid.tile_size.y * 0.5 + grid.v_separation, 0.01,
			"Bottom row tile %d should tuck up into the notches of the top row" % i)
		assert_lt(below.position.y, grid.v_padding + grid.tile_size.y,
			"Bottom row tile %d should rise into the row above, not sit below it" % i)

func test_interlocking_rows_never_overlap_each_others_diamonds() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent()
	var tile := grid.tile_size

	# A bottom row tile's top vertex must stay outside every diamond above it,
	# including the last tile, which overhangs the end of the top row.
	var tiles: Array[Control] = grid.flow_children()
	for i in tiles.size() - grid.columns:
		var below: Control = tiles[grid.columns + i]
		var vertex := below.position + Vector2(tile.x * 0.5, 0.0)
		for above in tiles.slice(0, grid.columns):
			assert_false(TerrainTileButton.point_on_tile(vertex - above.position),
				"Bottom row tile %d should not cover the diamond of top row tile %d"
					% [i, above.get_index()])

func test_tile_buttons_only_answer_inside_the_diamond() -> void:
	var tile := TerrainTileButton.TILE_SIZE
	assert_true(TerrainTileButton.point_on_tile(tile * 0.5), "The middle of the tile is clickable")
	assert_true(TerrainTileButton.point_on_tile(Vector2(tile.x * 0.5, 2.0)), "So is the top vertex")
	assert_false(TerrainTileButton.point_on_tile(Vector2.ZERO),
		"The empty corner of the bounding box is not")
	assert_false(TerrainTileButton.point_on_tile(Vector2(tile.x, tile.y)),
		"Nor is the opposite corner")

func test_building_tiles_always_fill_two_rows() -> void:
	for count in [1, 2, 7, 16, 17]:
		var registry := {}
		for i in count:
			registry["b%d" % i] = {"name": "B%d" % i, "size": [1, 1], "cost": 100, "operating_cost": 0}
		toolbar.set_building_registry(registry)
		var columns: int = toolbar._building_shelf.columns
		var rows := ceili(float(count) / columns)
		assert_eq(rows, mini(count, TerrainToolbar.TILE_ROWS),
			"%d buildings should be laid out in two rows" % count)

func test_two_rows_of_big_tiles_fill_the_toolbar_page_height() -> void:
	var tile := TerrainTileButton.BUTTON_SIZE
	# Two interlocking rows: 1.5 tiles, the gap where row 2 tucks into row 1,
	# and the breathing room above and below the rows.
	var two_rows := tile.y * 1.5 + TerrainToolbar.TILE_V_SEPARATION \
			+ 2.0 * TerrainToolbar.TILE_V_PADDING
	assert_gt(tile.y, 42.0, "Tiles should be bigger than the old 84x42 cells")

	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	toolbar.set_building_registry(registry)
	await _settle_layout()
	var course_grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent()
	assert_almost_eq(course_grid.get_combined_minimum_size().y, two_rows, 0.01)
	assert_almost_eq(toolbar._building_shelf.get_combined_minimum_size().y, two_rows, 0.01)
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT))

	# The page the tiles sit on: the bottom bar less the tab bar, the panel
	# margins and the horizontal scrollbar shown when a page overflows.
	var page_height: float = toolbar._pages[TerrainToolbar.Tab.TERRAIN].size.y
	assert_lte(two_rows + 2.0, page_height, "Two rows (plus drop shadow) fit the page")
	assert_gte(two_rows, page_height - 8.0, "Two rows should fill the page height")

func test_tile_rows_keep_space_above_below_and_between_them() -> void:
	var padding: int = TerrainToolbar.TILE_V_PADDING
	var gap: int = TerrainToolbar.TILE_V_SEPARATION
	assert_gt(padding, 0, "Rows should not touch the top of the page")
	assert_gt(gap, 8, "The interlocking rows should have more room between them")

	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	toolbar.set_building_registry(registry)
	await _settle_layout()

	for grid in [toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent(),
			toolbar._building_shelf]:
		var tiles: TileHoneycomb = grid
		assert_eq(tiles.v_padding, padding, "Both tabs keep the same breathing room")
		assert_eq(tiles.v_separation, gap, "Both tabs keep the same inter-row gap")

		# Space above the first row and below the last row.
		var first_tile: Control = tiles.get_child(0)
		assert_almost_eq(first_tile.position.y, float(padding), 0.01,
			"The first row starts below the breathing room")
		var last_row_bottom: float = 0.0
		for child in tiles.get_children():
			var tile: Control = child
			last_row_bottom = maxf(last_row_bottom, tile.position.y + tiles.tile_size.y)
		assert_almost_eq(tiles.get_combined_minimum_size().y - last_row_bottom,
			float(padding), 0.01, "The last row ends above the breathing room")

		# Space between the two rows: row 2 sits a full half tile plus the gap
		# below row 1, so the diamonds never touch.
		var row_two: Control = tiles.get_child(tiles.columns)
		assert_almost_eq(row_two.position.y - first_tile.position.y,
			tiles.tile_size.y * 0.5 + float(gap), 0.01,
			"Row 2 is tucked a half tile plus the gap below row 1")
		assert_gt(row_two.position.y - first_tile.position.y, tiles.tile_size.y * 0.5,
			"Row 2 must not touch the row above it")

## Containers lay their children out over the next frame.
func _settle_layout() -> void:
	await process_frames(2)

## The diamond's four vertices plus the midpoints of its edges: enough points to
## show a nestled button is clear of the tiles either side of it.
func _diamond_samples(box: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for corner in OpenHoleNotchButton.diamond_corners(box):
		points.append(corner)
	points.append(box * Vector2(0.25, 0.25))
	points.append(box * Vector2(0.75, 0.25))
	points.append(box * Vector2(0.75, 0.75))
	points.append(box * Vector2(0.25, 0.75))
	return points

## The improvement shelf's decoration tiles, in shelf order: the leading path
## tile is a painting tool rather than a catalogue entry, so catalogue
## assertions skip it.
func _catalogue_tiles() -> Array:
	return toolbar._decoration_shelf.get_children().filter(
		func(tile): return tile != toolbar._path_tile)

func test_toolbar_has_eleven_tabs_in_three_sections() -> void:
	assert_eq(toolbar._tab_buttons.size(), 11)
	assert_eq(toolbar._pages.size(), 11)
	assert_eq(TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.BUILD].size(), 4)
	assert_eq(TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.MANAGE].size(), 3)
	assert_eq(TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.GOLFERS].size(), 4)
	assert_false(TerrainToolbar.Tab.HOLES in TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.BUILD],
		"Holes moved out of the Build section")
	assert_true(TerrainToolbar.Tab.HOLES in TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.MANAGE],
		"and into Manage")
	for index in TerrainToolbar.TAB_TITLES:
		assert_eq(toolbar._tab_buttons[index].accessibility_name, TerrainToolbar.TAB_TITLES[index])
		assert_true(PixelCircleButton.ICONS.has(toolbar._tab_buttons[index].glyph))

func test_all_pages_scroll_horizontally_behind_fixed_chrome() -> void:
	for i in toolbar._pages.size():
		var page = toolbar._pages[i]
		assert_not_null(page, "Page %d should not be null" % i)
		var scroll: ScrollContainer = toolbar.page_scroll(i)
		assert_not_null(scroll, "Page %d should hold a scroll container" % i)
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO,
			"Page %d should have horizontal scroll mode AUTO" % i)
		assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
			"Page %d should have vertical scroll mode DISABLED" % i)
		assert_gt(scroll.get_child_count(), 0, "Page %d should have content child" % i)
		var content = scroll.get_child(0)
		assert_true(content is HBoxContainer, "Page %d content container should be HBoxContainer" % i)

func test_tab_selection_toggles_visibility() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	assert_true(toolbar._pages[TerrainToolbar.Tab.TERRAIN].visible)
	assert_false(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible)

	toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	assert_false(toolbar._pages[TerrainToolbar.Tab.TERRAIN].visible)
	assert_true(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible)

	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	assert_false(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible)
	assert_true(toolbar._pages[TerrainToolbar.Tab.BUILDINGS].visible)

func test_bulldozer_pins_to_the_removal_tabs_bottom_left_corners() -> void:
	assert_eq(toolbar._bulldozer_buttons.size(), 2,
		"One pinned Bulldozer per tab whose tiles it can remove")
	for tab in [TerrainToolbar.Tab.IMPROVEMENTS, TerrainToolbar.Tab.BUILDINGS]:
		var page: Control = toolbar._pages[tab]
		var found := page.find_children("*", "BulldozerButton", false, false)
		assert_eq(found.size(), 1, "%s page pins exactly one Bulldozer" % TerrainToolbar.TAB_TITLES[tab])
		var btn: BulldozerButton = found[0]
		# Anchored to the page's bottom-left corner, clear of the page edges.
		assert_almost_eq(btn.anchor_left, 0.0, 0.001, "Anchored to the left edge")
		assert_almost_eq(btn.anchor_top, 1.0, 0.001, "Anchored to the bottom edge")
		assert_almost_eq(btn.anchor_right, 0.0, 0.001, "Anchored to the left edge")
		assert_almost_eq(btn.anchor_bottom, 1.0, 0.001, "Anchored to the bottom edge")
		assert_almost_eq(btn.offset_left, BulldozerButton.CORNER_MARGIN, 0.01)
		assert_almost_eq(btn.offset_bottom, -BulldozerButton.CORNER_MARGIN, 0.01)
		# A round button: square bounds of the fixed diameter, circular hit face.
		assert_eq(btn.custom_minimum_size,
			Vector2(BulldozerButton.BUTTON_DIAMETER, BulldozerButton.BUTTON_DIAMETER))
		assert_true(btn._has_point(btn.size * 0.5), "The circle face is clickable")
		assert_false(btn._has_point(Vector2(1, 1)),
			"The bounding box corners fall through to the tiles underneath")
		assert_string_contains(btn.accessibility_description, "Course Terrain tiles are not affected",
			"The tooltip explains the Bulldozer's scope")
	# The Course Terrain page pins nothing: ground tiles are never bulldozed.
	assert_eq(toolbar._pages[TerrainToolbar.Tab.TERRAIN].find_children(
		"*", "BulldozerButton", true, false).size(), 0,
		"Course Terrain has no Bulldozer button")

func test_bulldozer_buttons_trigger_and_share_the_mode_state() -> void:
	watch_signals(toolbar)
	var buttons: Array = toolbar._bulldozer_buttons

	# Pressing a pinned button stays on its own tab and starts bulldozer mode.
	toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	buttons[0].pressed.emit()
	assert_signal_emitted(toolbar, "bulldozer_pressed")
	assert_true(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible,
		"Pressing the pinned Bulldozer keeps its tab open")

	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	buttons[1].pressed.emit()
	assert_signal_emitted(toolbar, "bulldozer_pressed")
	assert_true(toolbar._pages[TerrainToolbar.Tab.BUILDINGS].visible,
		"Pressing the pinned Bulldozer keeps its tab open")

	# Both circles report the mode: gold ring while it runs, quiet when it ends.
	toolbar.set_bulldozer_active(true)
	for btn in buttons:
		assert_true(btn.is_active(), "The pinned Bulldozer shows the mode is on")
	toolbar.set_bulldozer_active(false)
	for btn in buttons:
		assert_false(btn.is_active(), "The pinned Bulldozer shows the mode is off")

func test_tool_selection_and_signals() -> void:
	watch_signals(toolbar)

	toolbar._on_tool_button_pressed(TerrainTypes.Type.FAIRWAY)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.FAIRWAY])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.FAIRWAY)
	assert_true(toolbar.has_selection())

	toolbar._on_tool_button_pressed(TerrainTypes.Type.GREEN)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.GREEN])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.GREEN)

	toolbar.clear_selection()
	assert_eq(toolbar.get_current_tool(), -1)
	assert_false(toolbar.has_selection())

func test_terrain_paint_tools_are_isometric_course_tiles() -> void:
	# The walking path paints the course as much as any of these, so it is drawn
	# as a tile too — it just lives in the Improvements honeycomb.
	var paint_tools := [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.ROUGH,
		TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.BUNKER,
		TerrainTypes.Type.WATER, TerrainTypes.Type.OUT_OF_BOUNDS, TerrainTypes.WALKING_PATH_TOOL]
	for tool_type in paint_tools:
		var button: ToolButton = toolbar._tool_buttons[tool_type]
		assert_true(button is TerrainTileButton, "%s should be a tile button" % button.tool_name)
		assert_null(button.icon, "Terrain swatches should not use the old square sprite icons")
		assert_eq(button.text, "", "The name is drawn on the tile, not as button text")
		var labels := button.get_children().filter(func(child): return child is Label)
		assert_eq(labels.size(), 1, "The name is the only caption on the tile")
		assert_eq(button._name_label.text, button.tool_name)
		assert_false(button._name_label.text.contains(button.hotkey),
			"The shortcut number is no longer drawn on the tile")
		assert_eq(button._name_label.size, TerrainTileButton.BUTTON_SIZE,
			"The name spans the tile so its text centres on the diamond")
		assert_eq(button._name_label.position, Vector2.ZERO)
		assert_true(button._name_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"Clicking a label should still select the tool")
		assert_false(button.accessibility_description.is_empty(),
			"The shortcut still reaches assistive tech")
		assert_eq(button.cost, TerrainTypes.get_placement_cost(tool_type))

	# Non-painting actions retain their familiar ToolButtons. The Bulldozer is
	# no longer a Course Terrain tool at all — it is pinned to the Improvements
	# and Buildings tabs, whose tiles it can remove.
	assert_false(toolbar._tool_buttons.has("bulldozer"), "The Bulldozer is not a Course Terrain tool")
	assert_false(toolbar._open_hole_buttons[0] is TerrainTileButton)

func test_building_choices_use_the_course_tile_design_without_required_clubhouse() -> void:
	var registry := {
		"clubhouse": {"name": "Clubhouse", "size": [4, 4], "cost": 10000,
			"operating_cost": 100, "required": true},
		"bench": {"name": "Bench", "size": [1, 1], "cost": 200, "operating_cost": 0},
	}
	toolbar.set_building_registry(registry)

	assert_true(toolbar._building_shelf is TileHoneycomb)
	assert_true(toolbar._building_registry.has("clubhouse"),
		"The required clubhouse stays registered for course and building logic")
	assert_eq(toolbar._building_shelf.columns, TerrainToolbar.tile_columns(1))
	assert_eq(toolbar._building_shelf.get_child_count(), 1,
		"The required clubhouse is supplied with the course, not offered as a placement button")
	for button in toolbar._building_shelf.get_children():
		assert_true(button is BuildingTileButton, "Building choices should use isometric tile buttons")
		assert_true(button is TerrainTileButton, "Building tiles should share the Course/Hazards button base")
		assert_eq(button.custom_minimum_size, TerrainTileButton.BUTTON_SIZE)
		assert_eq(button.text, "", "Building names should be drawn on the tile")
		assert_eq(button._name_label.size, TerrainTileButton.BUTTON_SIZE)
		assert_not_null(button._building_art)
		assert_ne(button.tool_type, "clubhouse", "The clubhouse should not appear in the Buildings shelf")

	var bench: BuildingTileButton = toolbar._building_shelf.get_child(0)
	assert_eq(bench.tool_name, "Bench")
	assert_eq(bench.cost, 200)
	assert_eq(bench.maintenance, 0)
	assert_eq(bench.tooltip_text, "", "Only the rich TooltipManager popup should appear on hover")

	watch_signals(toolbar)
	bench.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "building_selected", ["bench"])

func test_buildings_tab_has_no_heading_or_info_section() -> void:
	var page: Control = toolbar._pages[TerrainToolbar.Tab.BUILDINGS]
	var texts: Array[String] = []
	for label in page.find_children("*", "Label", true, false):
		if label.get_parent() is TerrainTileButton:
			continue  # Building names drawn on the tiles themselves
		texts.append(label.text)
	assert_false(texts.has("FACILITIES"), "Buildings tab should not show a FACILITIES heading")
	assert_false(texts.has("INFO"), "Buildings tab should not show an INFO section")
	assert_eq(page.find_children("*", "VSeparator", true, false).size(), 0,
		"Buildings tab should not keep a separator for the removed INFO section")

func test_tile_previews_use_course_shader_and_neighboring_grass() -> void:
	var corners := TerrainTileButton.tile_corners()
	assert_eq(corners.size(), 4)
	assert_eq(corners[1].x - corners[3].x, TerrainTileButton.TILE_SIZE.x)
	assert_eq(corners[2].y - corners[0].y, TerrainTileButton.TILE_SIZE.y)
	assert_eq(TerrainTileButton.TILE_SIZE.x, TerrainTileButton.TILE_SIZE.y * 2,
		"The swatch has the same 2:1 footprint as a projected grid cell")

	for tool_type in [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.GREEN,
			TerrainTypes.Type.BUNKER, TerrainTypes.Type.WATER, TerrainTypes.Type.OUT_OF_BOUNDS]:
		var button: TerrainTileButton = toolbar._tool_buttons[tool_type]
		var tile: Polygon2D = button.get_child(1)
		assert_eq(tile.polygon, corners)
		assert_eq(tile.texture.get_size(), Vector2(1, 1))
		assert_eq(tile.uv[0], Vector2(0.5, 0))
		assert_eq(tile.uv[1], Vector2(1, 0.5))
		var mat := button._surface_material
		assert_eq(mat.shader, preload("res://shaders/course_surface.gdshader"))
		assert_eq(mat.get_shader_parameter("grid_size"), Vector2(3, 3))
		assert_eq(mat.get_shader_parameter("grid_axis_x"), Vector2(32, 16))
		assert_eq(mat.get_shader_parameter("grid_axis_y"), Vector2(-32, 16))
		var image: Image = mat.get_shader_parameter("terrain_data").get_image()
		assert_eq(image.get_size(), Vector2i(3, 3))
		assert_eq(roundi(image.get_pixel(1, 1).r * 255.0), tool_type)
		assert_eq(roundi(image.get_pixel(0, 1).r * 255.0), TerrainTypes.Type.GRASS)
		assert_eq(roundi(image.get_pixel(2, 1).r * 255.0), TerrainTypes.Type.GRASS)

func test_terrain_tile_highlight_and_click_still_select_the_tool() -> void:
	watch_signals(toolbar)
	var button: TerrainTileButton = toolbar._tool_buttons[TerrainTypes.Type.WATER]
	button.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.WATER])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.WATER)
	assert_true(button.is_selected())
	assert_eq(button._outline.default_color, UIConstants.COLOR_GOLD)
	assert_eq(button._name_label.get_theme_color("font_color"), UIConstants.COLOR_GOLD,
		"The selected tile's name is picked out in gold")

	toolbar.clear_selection()
	assert_false(button.is_selected())
	assert_eq(button._outline.default_color, UIConstants.COLOR_BORDER)

func test_tile_previews_follow_course_theme_colors() -> void:
	var button: TerrainTileButton = toolbar._tool_buttons[TerrainTypes.Type.WATER]
	var original_colors := TerrainPalette._active_colors.duplicate()
	var recolored := original_colors.duplicate()
	recolored["water"] = Color("d0478c")
	recolored["fringe"] = Color("808044")
	TerrainPalette.set_theme_colors(recolored)
	EventBus.theme_changed.emit(0)

	var palette: Image = button._surface_material.get_shader_parameter("palette").get_image()
	assert_eq(palette.get_pixel(TerrainTypes.Type.WATER, 0).to_html(false),
		Color("d0478c").to_html(false))
	assert_eq(button._surface_material.get_shader_parameter("fringe_color"), Color("808044"))

	TerrainPalette.set_theme_colors(original_colors)
	EventBus.theme_changed.emit(0)

func test_brush_size_controls() -> void:
	watch_signals(toolbar)
	assert_eq(TerrainToolbar.BRUSH_SIZES, ElevationTool.BRUSH_SIZES,
			"Terrain paint steps 1×1 through 9×9, matching the Elevation Brush")

	toolbar.set_brush_size(1)
	assert_eq(toolbar.get_brush_size(), 1)

	toolbar._on_brush_increase()
	assert_eq(toolbar.get_brush_size(), 2)
	assert_signal_emitted_with_parameters(toolbar, "brush_size_changed", [2])

	toolbar._on_brush_increase()
	assert_eq(toolbar.get_brush_size(), 3)

	toolbar._on_brush_decrease()
	assert_eq(toolbar.get_brush_size(), 2)
	assert_signal_emitted_with_parameters(toolbar, "brush_size_changed", [2])

	toolbar.set_brush_size(9)
	toolbar._on_brush_increase()
	assert_eq(toolbar.get_brush_size(), 9, "9×9 is the largest terrain brush")

func test_standard_bunker_tool_is_described_as_shallow() -> void:
	var button: TerrainTileButton = toolbar._tool_buttons[TerrainTypes.Type.BUNKER]
	assert_string_contains(button.tool_description, "Shallow sand-trap hazard")

func test_green_tile_flag_tracks_the_next_green_type() -> void:
	var button: TerrainTileButton = toolbar._tool_buttons[TerrainTypes.Type.GREEN]
	assert_true(toolbar.green_will_place_cup(), "A new course's first green carries a cup")
	assert_true(button.shows_green_with_hole_flag(), "Green With Hole is marked with a flag")
	assert_true(button._cup_flag.visible)
	assert_string_contains(button.tool_description, "Green With Hole")

	toolbar.set_green_placement_state(false)
	assert_false(toolbar.green_will_place_cup())
	assert_false(button.shows_green_with_hole_flag(), "Green Without Hole has no flag")
	assert_false(button._cup_flag.visible)
	assert_string_contains(button.tool_description, "Green Without Hole")
	assert_string_contains(button.accessibility_description, "selected brush")

func test_every_course_terrain_tile_says_it_replaces_the_others() -> void:
	var sentence := TerrainTypes.REPLACES_ANY_COURSE_TILE
	for tool_type in TOP_ROW + BOTTOM_ROW + [TerrainTypes.Type.FLOWER_BED]:
		var button: TerrainTileButton = toolbar._tool_buttons[tool_type]
		assert_string_contains(button.tool_description, sentence,
			"%s tells the player it replaces any other Course Terrain tile" % button.tool_name)
	for tree_type in CourseTheme.get_tree_types(GameManager.current_theme):
		assert_string_contains(toolbar._tool_buttons[tree_type].tool_description, sentence,
			"%s replaces any other Course Terrain tile" % TerrainTypes.get_type_name(tree_type))
	# The Path tool is an improvement laid over ground, not a Course Terrain tile.
	assert_false(toolbar._tool_buttons[TerrainTypes.WALKING_PATH_TOOL].tool_description.contains(sentence),
		"The walking path does not replace course terrain")
	toolbar.set_green_placement_state(false)
	assert_string_contains(toolbar._tool_buttons[TerrainTypes.Type.GREEN].tool_description, sentence,
		"Switching the green between with-hole and without keeps the replacement note")

func test_course_terrain_tab_has_no_green_size_presets() -> void:
	var terrain_content: HBoxContainer = toolbar.page_content(TerrainToolbar.Tab.TERRAIN)
	assert_eq(terrain_content.get_child_count(), 1,
		"The scrolling terrain tab is just the unified tile grid — the brush is pinned to the page, and there is no extra separator or preset group")

## Open Hole pairs the tee box and the green, so the Course Terrain tab nestles
## the action into the notch between those two tiles instead of leaving it in the
## tools column at the far edge of the tab.
func test_open_hole_nests_into_the_notch_between_the_tee_and_green_tiles() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._course_tiles
	var tee: Control = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]
	var green: Control = toolbar._tool_buttons[TerrainTypes.Type.GREEN]
	var open_hole: OpenHoleNotchButton = toolbar._open_hole_buttons[0]

	assert_true(open_hole is OpenHoleNotchButton, "Open Hole is drawn as a notch cell, not a wide button")
	assert_eq(open_hole.get_parent(), grid, "Open Hole lives on the Course Terrain honeycomb")
	assert_true(grid.is_notch_child(open_hole), "The action fills a notch instead of a tile slot")
	assert_false(grid.flow_children().has(open_hole),
		"A nestled child takes no slot, so the tiles keep their rows")
	assert_eq(open_hole.tool_name, "Open Hole")
	assert_eq(open_hole.hotkey, "H")
	assert_eq(open_hole.caption(), "[H]",
		"A notch cell is too small for the name: it carries the hotkey chip")
	assert_string_contains(open_hole.tool_description, "tee box",
		"The hover tooltip still explains what the action does")

	# Tucked between the two tiles' facing edges, its bottom point on the point
	# where those edges meet and its top point level with the top of the row.
	var tee_centre := tee.position + tee.size * 0.5
	var green_centre := green.position + green.size * 0.5
	var centre := open_hole.position + open_hole.size * 0.5
	# Where the two tiles meet: the tee box's right vertex and the green's left
	# vertex face each other across the honeycomb's gap.
	var meet := (tee.position + Vector2(tee.size.x, tee.size.y * 0.5)
		+ green.position + Vector2(0.0, green.size.y * 0.5)) * 0.5
	assert_almost_eq(centre.x, (tee_centre.x + green_centre.x) * 0.5, 0.01,
		"The diamond is centred between the tee box and the green")
	assert_almost_eq(centre.x, meet.x, 0.01, "Centred on the point where the two tiles meet")
	assert_almost_eq(centre.y + open_hole.size.y * 0.5, meet.y, 0.01,
		"Its bottom point sits on the point where the tee box and the green meet")
	assert_almost_eq(centre.y - open_hole.size.y * 0.5, tee.position.y, 0.01,
		"Its top point is level with the top of the tiles' row")
	# Half a course cell: an isometric diamond narrower than the notch cell, so
	# it keeps daylight from the tiles, and exactly as tall, so its points line
	# up with the grid it drops into.
	assert_almost_eq(open_hole.size.x, open_hole.size.y * 2.0, 0.01,
		"The notch cell is an isometric diamond, like the tiles")
	var notch := grid.notch_cell_size()
	assert_lt(open_hole.size.x, notch.x, "Narrower than the notch, so it clears the tiles")
	assert_almost_eq(open_hole.size.y, notch.y, 0.01, "As tall as the notch: its points meet the grid")
	assert_almost_eq((grid.notch_centre(0) - centre).length(), 0.0, 0.01,
		"The honeycomb centres the action in the tee/green notch")
	for tile in [tee, green]:
		for point in _diamond_samples(open_hole.size):
			assert_false(TerrainTileButton.point_on_tile(open_hole.position + point - tile.position),
				"The Open Hole diamond stays clear of the %s tile" % tile.tool_name)

	# Only the diamond answers to the mouse.
	assert_true(open_hole._has_point(open_hole.size * 0.5), "The middle of the diamond is clickable")
	assert_false(open_hole._has_point(Vector2(1, 1)),
		"The empty corner of its bounding box falls through to the tiles underneath")

	# Pressing it still opens the hole.
	watch_signals(toolbar)
	open_hole.pressed.emit()
	assert_signal_emitted(toolbar, "open_hole_pressed")

func test_open_hole_notch_does_not_shift_the_course_tiles() -> void:
	await _settle_layout()
	var tiles: Array[Control] = toolbar._course_tiles.flow_children()
	assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]), 0,
		"The tee box still opens the top row")
	assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.GREEN]), 1,
		"The green still follows it, with nothing wedged between them")
	assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.BUNKER]), 2,
		"The rest of the top row is untouched")
	for slot in BOTTOM_ROW.size():
		assert_eq(tiles.find(toolbar._tool_buttons[BOTTOM_ROW[slot]]),
			toolbar._course_tiles.columns + slot,
			"%s keeps its bottom row slot" % TerrainTypes.get_type_name(BOTTOM_ROW[slot]))

## The nestled diamond reports the action's availability in its own ring: gold
## while a tee box and a cup are waiting to be paired, grey while they are not.
func test_open_hole_notch_ring_tracks_whether_a_hole_can_be_opened() -> void:
	var open_hole: OpenHoleNotchButton = toolbar._open_hole_buttons[0]

	toolbar.set_open_hole_state(false, "Paint a tee box to go with the waiting green.")
	assert_true(open_hole.disabled)
	assert_eq(open_hole._ring_color(), OpenHoleNotchButton.COLOR_RING_DISABLED,
		"The ring is grey while no hole can be opened")
	assert_string_contains(open_hole.tool_description, "Paint a tee box")

	toolbar.set_open_hole_state(true, "")
	assert_false(open_hole.disabled)
	assert_eq(open_hole._ring_color(), UIConstants.COLOR_GOLD,
		"The ring turns gold the moment the pair is ready")
	assert_string_contains(open_hole.tool_description, "waiting tee box")

## Switching themes rebuilds the landscape catalogue around the nestled action:
## the tile flow is reshuffled, and the Open Hole button must not be moved into
## a row with it.
func test_theme_changes_keep_the_open_hole_between_the_tee_and_green() -> void:
	var original_theme: int = GameManager.current_theme
	var open_hole: OpenHoleNotchButton = toolbar._open_hole_buttons[0]
	for theme in [CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND,
			CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND]:
		GameManager.current_theme = theme
		EventBus.theme_changed.emit(theme)
		await _settle_layout()

		var grid: TileHoneycomb = toolbar._course_tiles
		assert_true(grid.is_notch_child(open_hole), "The action stays nestled, never a tile")
		assert_almost_eq(
			(open_hole.position + open_hole.size * 0.5).distance_to(grid.notch_centre(0)), 0.0, 0.01,
			"A rebuilt catalogue leaves the action in the tee/green notch")
		var tiles: Array[Control] = grid.flow_children()
		assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]), 0)
		assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.GREEN]), 1)
		assert_false(tiles.has(open_hole), "The catalogue rebuild never turns it into a tile")
	GameManager.current_theme = original_theme
	EventBus.theme_changed.emit(original_theme)

## The Course Terrain brush controls no longer lead the scrolling shelf: they
## are pinned to the page's bottom-left corner so they stay above the tiles.
func test_brush_controls_pin_to_the_terrain_tabs_bottom_left_corner() -> void:
	var page: Control = toolbar._pages[TerrainToolbar.Tab.TERRAIN]
	var dock: PanelContainer = toolbar._brush_dock
	assert_not_null(dock, "The Course Terrain tab pins a brush dock")
	assert_eq(dock.name, "BrushDock")
	assert_eq(dock.get_parent(), page, "Pinned to the page, not to the scrolling shelf")
	assert_false(toolbar.page_scroll(TerrainToolbar.Tab.TERRAIN).is_ancestor_of(dock),
		"The brush stays fixed while the tiles scroll beneath it")
	assert_eq(page.find_children("*", "TerrainToolsColumn", true, false).size(), 0,
		"The old tools column is gone")

	# Anchored to the page's bottom-left corner, clear of the page edges.
	assert_almost_eq(dock.anchor_left, 0.0, 0.001, "Anchored to the left edge")
	assert_almost_eq(dock.anchor_top, 1.0, 0.001, "Anchored to the bottom edge")
	assert_almost_eq(dock.anchor_right, 0.0, 0.001, "Anchored to the left edge")
	assert_almost_eq(dock.anchor_bottom, 1.0, 0.001, "Anchored to the bottom edge")
	assert_almost_eq(dock.offset_left, TerrainToolbar.BRUSH_DOCK_MARGIN, 0.01)
	assert_almost_eq(dock.offset_bottom, -TerrainToolbar.BRUSH_DOCK_MARGIN, 0.01)

	await _settle_layout()
	var side := TerrainToolbar.brush_dock_side()
	assert_eq(dock.size, Vector2(side, side), "A square plate of four cells")
	assert_eq(dock.position, Vector2(TerrainToolbar.BRUSH_DOCK_MARGIN,
		page.size.y - TerrainToolbar.BRUSH_DOCK_MARGIN - side),
		"Held in the bottom-left corner of the tab")
	assert_true(Rect2(Vector2.ZERO, page.size).encloses(Rect2(dock.position, dock.size)),
		"The plate stays inside the tab")

## "Fixed" means fixed: scrolling the catalogue moves the tiles, and the brush
## stays where it was pinned.
func test_pinned_brush_stays_put_while_the_tiles_scroll() -> void:
	var scroll: ScrollContainer = toolbar.page_scroll(TerrainToolbar.Tab.TERRAIN)
	var dock: PanelContainer = toolbar._brush_dock
	await _settle_layout()
	var dock_before: Vector2 = dock.get_global_transform_with_canvas().origin
	var tee: Control = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]
	var tee_before: Vector2 = tee.get_global_transform_with_canvas().origin

	scroll.scroll_horizontal = 200
	await _settle_layout()
	assert_gt(scroll.scroll_horizontal, 0, "The shelf scrolled")
	assert_eq(dock.get_global_transform_with_canvas().origin, dock_before,
		"The brush stays fixed in the corner of the tab")
	assert_ne(tee.get_global_transform_with_canvas().origin, tee_before,
		"The tiles scroll beneath it")

	scroll.scroll_horizontal = 0
	await _settle_layout()
	assert_eq(dock.get_global_transform_with_canvas().origin, dock_before)

## The pinned plate carries the whole brush — shape, the size it paints with,
## and the two steps — and drives exactly the brush it used to.
func test_pinned_brush_dock_carries_the_whole_brush() -> void:
	var dock: PanelContainer = toolbar._brush_dock
	var cell := Vector2(TerrainToolbar.BRUSH_DOCK_CELL, TerrainToolbar.BRUSH_DOCK_CELL)

	var shapes: Array = dock.find_children("*", "Button", true, false).filter(
		func(button): return button in toolbar._brush_shape_buttons)
	assert_eq(shapes.size(), 1, "One round/square picker")
	var shape: Button = shapes[0]
	assert_true(shape.toggle_mode)
	assert_eq(shape.custom_minimum_size, cell)

	var chips := dock.find_children("BrushSizeChip", "Label", true, false)
	assert_eq(chips.size(), 1, "One size readout")
	var chip: Label = chips[0]
	assert_has(toolbar._brush_labels, chip, "The toolbar writes the size into the chip")
	assert_eq(chip.custom_minimum_size, cell)

	var steps: Array = dock.find_children("*", "Button", true, false).filter(
		func(button): return button in toolbar._brush_buttons)
	assert_eq(steps.size(), 2, "Smaller and bigger")
	for step in steps:
		assert_eq(step.custom_minimum_size, cell)

	# The dock is the terrain tab's brush: stepping it changes the real brush,
	# and the chip reads back the size the selected tool paints with.
	watch_signals(toolbar)
	toolbar.set_brush_size(5)
	assert_eq(chip.text, "5x5")
	for step in steps:
		if step.text == "+":
			step.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "brush_size_changed", [6])
	assert_eq(toolbar.get_brush_size(), 6)
	assert_eq(chip.text, "6x6")

	# A tool capped at a single tile locks the dock, like every other brush UI.
	toolbar.set_brush_limit(1)
	assert_eq(chip.text, "1x1", "The chip shows the capped size")
	assert_true(shape.disabled, "The shape picker is locked")
	for step in steps:
		assert_true(step.disabled, "The stepper is locked")
	toolbar.set_brush_limit(HoleLayout.UNLIMITED_BRUSH)
	assert_false(shape.disabled)
	toolbar.set_brush_size(1)

## The plate floats above the shelf in the corner the staggered rows leave
## empty, so no tile loses a pixel of its clickable diamond to it.
func test_pinned_brush_dock_leaves_every_tile_diamond_clear() -> void:
	await _settle_layout()
	var dock: PanelContainer = toolbar._brush_dock
	var dock_origin: Vector2 = dock.get_global_transform_with_canvas().origin
	var dock_rect := Rect2(dock_origin, dock.size)
	assert_gt(dock_rect.size.x, 0.0, "The dock is laid out")

	var checked := 0
	for tile in toolbar._course_tiles.flow_children() + [toolbar._open_hole_buttons[0]]:
		var covered := false
		for offset_y in range(0, int(dock_rect.size.y) + 1, 2):
			for offset_x in range(0, int(dock_rect.size.x) + 1, 2):
				var local: Vector2 = dock_rect.position + Vector2(offset_x, offset_y) \
						- tile.get_global_transform_with_canvas().origin
				if TerrainTileButton.point_on_tile(local):
					covered = true
		assert_false(covered,
			"%s keeps its diamond clear of the pinned brush" % (tile as ToolButton).tool_name)
		checked += 1
	assert_eq(checked, toolbar._course_tiles.flow_children().size() + 1,
		"Every tile on the tab, plus the nestled Open Hole action, was checked")

func test_holes_tab_has_hole_grid_without_duplicate_action_or_heading() -> void:
	assert_not_null(toolbar.hole_grid, "hole_grid should exist")
	assert_true(toolbar.hole_grid is GridContainer, "hole_grid should be a GridContainer")
	assert_not_null(toolbar._hole_register, "The Holes tab builds a hole register")
	assert_not_null(toolbar._hole_detail, "and a hole detail view beside it")

	var page_content := toolbar.page_content(TerrainToolbar.Tab.HOLES)
	assert_eq(page_content.get_child_count(), 3,
		"The Holes tab holds the hole register, the hole detail view and the course scorecard")
	assert_same(page_content.get_child(0), toolbar._hole_register,
		"The hole register leads the tab")
	assert_same(page_content.get_child(1), toolbar._hole_detail,
		"with the hole detail view beside it")
	assert_same(page_content.get_child(2), toolbar._hole_scorecard,
		"and the course scorecard after it")
	assert_true(toolbar._hole_register.visible, "The register is up while no hole is picked")
	assert_false(toolbar._hole_detail.visible, "and the detail view steps aside")
	assert_false(toolbar._hole_scorecard.visible, "and so does the scorecard")
	assert_eq(toolbar._hole_register.get_child_count(), 3,
		"The hole register holds the Holes Map card, the Scorecard card and the hole grid")
	var map_card := _holes_map_card()
	assert_not_null(map_card, "The Holes Map card is the register's other content")
	assert_same(toolbar._hole_register.get_child(0), map_card,
		"The Holes Map card leads the register on the left")
	assert_same(toolbar._hole_register.get_child(1), _scorecard_card(),
		"the Scorecard card follows it")
	assert_same(toolbar._hole_register.get_child(2), toolbar.hole_grid,
		"and the hole buttons come after both cards")
	var page: Control = toolbar._pages[TerrainToolbar.Tab.HOLES]
	var open_hole_cards := page.find_children("*", "ToolButton", true, false)\
		.filter(func(button): return (button as ToolButton).get("tool_type") == "open_hole")
	assert_eq(open_hole_cards.size(), 0,
		"The Open Hole action is not duplicated on the Holes tab")
	assert_false(page.find_children("*", "Label", true, false)
		.any(func(label): return label.text == "COURSE HOLES"),
		"The redundant COURSE HOLES heading is removed")

	# Add a sample hole button and verify containment: the button is the whole
	# of a hole's per-hole UI in the register, with no toggle or delete button beside it.
	_add_hole_button(1)
	assert_true(toolbar.hole_grid.has_node("HoleBtn1"))
	assert_eq(toolbar.hole_grid.get_child_count(), 1, "One hole is one button")
	assert_eq(toolbar.hole_grid.columns, 1, "One hole fills one column")

## A hole button the way main.gd makes it: named for its hole and carrying its
## number as metadata, which is what the column layout sorts on.
func _add_hole_button(hole_number: int) -> Button:
	var hole_btn := Button.new()
	hole_btn.name = "HoleBtn%d" % hole_number
	hole_btn.set_meta("hole_number", hole_number)
	toolbar.hole_grid.add_child(hole_btn)
	toolbar.layout_hole_buttons()
	return hole_btn

## The Holes tab's map card, the way the tab builds it.
func _holes_map_card() -> DockActionButton:
	for child in toolbar._hole_register.get_children():
		if child is DockActionButton and str(child.get("tool_type")) == "holes_map":
			return child
	return null

## The Holes Map card opens the Course Map on Routing Holes: pressing it
## asks main.gd for exactly that.
func test_the_holes_map_card_asks_for_the_course_map_on_routing() -> void:
	var card := _holes_map_card()
	assert_not_null(card, "The Holes tab carries a Holes Map card")
	assert_eq(str(card.tool_name), "Holes Map", "and says what it is")
	assert_eq(str(card.hotkey), "", "claiming no hotkey of its own")
	assert_string_contains(card.tool_description, "Routing Holes",
		"and its tooltip says which mode it opens")

	watch_signals(toolbar)
	card.pressed.emit()
	assert_signal_emitted(toolbar, "holes_map_pressed",
		"Pressing the card emits holes_map_pressed")
	assert_eq(toolbar.current_section, TerrainToolbar.Section.MANAGE,
		"The Holes tab answers from the Manage section now")

## The Staff tab's map card, the way the tab builds it.
func _staff_map_card() -> DockActionButton:
	for child in toolbar.page_content(TerrainToolbar.Tab.STAFF).get_children():
		if child is DockActionButton and str(child.get("tool_type")) == "staff_map":
			return child
	return null

## The Staff Map card opens the Course Map on Staff: pressing it
## asks main.gd for exactly that.
func test_the_staff_map_card_asks_for_the_course_map_on_staff() -> void:
	var card := _staff_map_card()
	assert_not_null(card, "The Staff tab carries a Staff Map card")
	assert_eq(str(card.tool_name), "Staff Map", "and says what it is")
	assert_eq(str(card.hotkey), "", "claiming no hotkey of its own")
	assert_string_contains(card.tool_description, "Staff",
		"and its tooltip says which mode it opens")

	watch_signals(toolbar)
	card.pressed.emit()
	assert_signal_emitted(toolbar, "staff_map_pressed",
		"Pressing the card emits staff_map_pressed")

## The Holes tab's Scorecard card, the way the tab builds it.
func _scorecard_card() -> DockActionButton:
	for child in toolbar._hole_register.get_children():
		if child is DockActionButton and str(child.get("tool_type")) == "scorecard":
			return child
	return null

## The course scorecard used to be a Club tab popup. It is the Holes tab's now,
## opened by a card beside the Holes Map card, and the K shortcut still reaches it.
func test_the_scorecard_moved_from_the_club_tab_to_the_holes_tab() -> void:
	assert_eq(TerrainToolbar.TOOL_TAB_MAP.get("scorecard"), TerrainToolbar.Tab.HOLES,
		"The scorecard belongs to the Holes tab")
	for card in _club_cards():
		assert_ne(card.tool_type, "scorecard", "The Club tab no longer carries a Scorecard card")
	var card := _scorecard_card()
	assert_not_null(card, "The Holes tab carries a Scorecard card")
	assert_eq(str(card.tool_name), "Scorecard", "and says what it is")
	assert_eq(str(card.hotkey), "K", "The card shows the K shortcut that still opens it")
	assert_string_contains(card.tool_description, "stroke index",
		"and its tooltip says what the scorecard shows")

## Pressing the Scorecard card swaps the hole register for the scorecard on the
## Holes tab, and its back button puts the register back up.
func test_the_scorecard_card_opens_the_scorecard_over_the_register() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	_scorecard_card().pressed.emit()
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.HOLES, "The card opens the Holes tab")
	assert_eq(toolbar.current_section, TerrainToolbar.Section.MANAGE, "in the Manage section")
	assert_true(toolbar.is_course_scorecard_showing(), "The scorecard is up")
	assert_true(toolbar._hole_scorecard.visible, "and takes the shelf")
	assert_false(toolbar._hole_register.visible, "in place of the hole register")
	assert_false(toolbar._hole_detail.visible, "and the hole detail stays shut")

	var back := toolbar._hole_scorecard.find_child("BackButton", false, false) as Button
	assert_not_null(back, "The scorecard has a way back to the holes")
	back.pressed.emit()
	assert_false(toolbar.is_course_scorecard_showing(), "Back closes the scorecard")
	assert_true(toolbar._hole_register.visible, "and the hole register is up again")
	assert_false(toolbar._hole_scorecard.visible, "with the scorecard put away")

## K opens the scorecard, or puts the register back when it is already up, the
## same toggle the popup had. Picking a hole takes the scorecard away for it.
func test_the_scorecard_toggles_and_a_hole_pick_replaces_it() -> void:
	toolbar.show_course_scorecard()
	assert_true(toolbar.is_course_scorecard_showing(), "The scorecard opens")
	toolbar.close_course_scorecard()
	assert_false(toolbar.is_course_scorecard_showing(), "and closes again")

	_add_hole_button(1)
	toolbar.show_course_scorecard()
	toolbar.show_hole_detail(1)
	assert_false(toolbar.is_course_scorecard_showing(), "Picking a hole replaces the scorecard")
	assert_false(toolbar._hole_scorecard.visible, "The scorecard steps aside")
	assert_true(toolbar._hole_detail.visible, "and the hole's detail takes the shelf")

## Leaving for another tab and coming back keeps the scorecard where it was, as
## a hole's detail view is kept.
func test_the_scorecard_stays_open_across_tabs() -> void:
	toolbar.show_course_scorecard()
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	assert_false(toolbar.is_course_scorecard_showing(), "Off the Holes tab it is not on screen")
	toolbar.select_tab(TerrainToolbar.Tab.HOLES)
	assert_true(toolbar.is_course_scorecard_showing(), "and it is still open when the tab returns")

## A full course of holes, with a record on every hole, still fits inside the
## bottom bar with the scorecard open: the records scroll rather than grow it.
func test_a_full_course_scorecard_stays_inside_the_bottom_bar() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	for hole_number in range(1, 19):
		var hole := GameManager.HoleData.new()
		hole.hole_number = hole_number
		hole.par = 4
		hole.distance_yards = 350
		hole.stroke_index = hole_number
		GameManager.current_course.add_hole(hole)
		GameManager.course_records["best_per_hole"][hole_number] = CourseRecords.RecordEntry.new(
			"Visitor %d" % hole_number, 4, 1, hole_number)

	toolbar.show_course_scorecard()
	await _settle_layout()
	assert_true(toolbar._hole_scorecard.visible, "The scorecard is up")
	var content := toolbar.page_content(TerrainToolbar.Tab.HOLES)
	var available := float(UIConstants.BOTTOM_BAR_HEIGHT) - TerrainToolbar.HEADER_HEIGHT
	assert_gt(content.get_combined_minimum_size().y, 0.0, "The scorecard is measured")
	assert_lte(content.get_combined_minimum_size().y, available,
		"The nines and the records fit under the tab bar")

## Holes stack three deep and the columns run off to the right, so a course
## grows along the axis the page already scrolls on.
func test_hole_buttons_stack_three_to_a_column() -> void:
	for hole_number in 8:
		_add_hole_button(hole_number + 1)

	var grid := toolbar.hole_grid
	assert_eq(grid.columns, 3, "Eight holes fill two columns of three and start a third")

	# The grid fills row-major, so reading down the first column gives holes
	# 1-3, down the second 4-6, and down the third 7-8.
	var reading_order := [1, 4, 7, 2, 5, 8, 3, 6]
	for slot in reading_order.size():
		assert_eq(int(grid.get_child(slot).get_meta("hole_number")), reading_order[slot],
			"Slot %d reads down the columns in hole order" % slot)

	toolbar.select_tab(TerrainToolbar.Tab.HOLES)
	await _settle_layout()
	var rows: Array[float] = []
	for child in grid.get_children():
		if not rows.has(child.position.y):
			rows.append(child.position.y)
	assert_eq(rows.size(), TerrainToolbar.HOLE_COLUMN_HEIGHT,
		"Holes sit in exactly three rows")

func test_a_full_course_of_holes_stays_inside_the_bottom_bar() -> void:
	for hole_number in 18:
		_add_hole_button(hole_number + 1)
	var grid := toolbar.hole_grid
	assert_eq(grid.columns, 6, "Eighteen holes fill six columns of three")

	toolbar.select_tab(TerrainToolbar.Tab.HOLES)
	await _settle_layout()
	assert_gt(grid.get_combined_minimum_size().y, 0.0, "The hole buttons are measured")
	var available := float(UIConstants.BOTTOM_BAR_HEIGHT) \
			- TerrainToolbar.HEADER_HEIGHT
	var content := toolbar.page_content(TerrainToolbar.Tab.HOLES)
	assert_lte(content.get_combined_minimum_size().y, available,
		"Three rows of hole buttons fit under the tab bar")

	toolbar.show_hole_detail(1)
	await _settle_layout()
	assert_true(toolbar._hole_detail.visible, "The hole detail view opened")
	assert_lte(content.get_combined_minimum_size().y, available,
		"An open hole detail view fits under the tab bar too")

## A hole button opens that hole's detail view in place of the hole register,
## and the way back puts the register up again.
func test_a_hole_button_opens_the_hole_detail_over_the_register() -> void:
	var hole_btn := _add_hole_button(1)
	toolbar.select_tab(TerrainToolbar.Tab.HOLES)
	assert_true(toolbar._hole_register.visible, "The hole register leads the tab")
	assert_false(toolbar._hole_detail.visible, "with no hole detail over it")

	watch_signals(toolbar)
	hole_btn.pressed.emit()
	assert_eq(toolbar._selected_hole, 1, "The button names the hole it opens")
	assert_true(toolbar._hole_detail.visible, "The hole detail takes the page")
	assert_false(toolbar._hole_register.visible, "and the hole register steps aside")
	assert_signal_emitted_with_parameters(toolbar, "hole_detail_changed", [1])

	(toolbar._hole_detail.get_child(0) as Button).pressed.emit()
	assert_eq(toolbar._selected_hole, 0, "The way back closes the hole detail")
	assert_true(toolbar._hole_register.visible, "and the hole register is up again")
	assert_false(toolbar._hole_detail.visible, "with the detail view cleared away")

## All content from the hole context menu and hole statistics panel lives on the
## Holes tab detail view: header, orphan warning, actions, hole info, scoring
## statistics and score distribution.
func test_hole_detail_shows_actions_info_and_statistics_and_emits_signals() -> void:
	var grid := TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	toolbar.terrain_grid = grid

	GameManager.current_course = GameManager.CourseData.new()
	var hole := GameManager.HoleData.new()
	hole.hole_number = 2
	hole.par = 4
	hole.distance_yards = 380
	hole.difficulty_rating = 4.5
	hole.stroke_index = 3
	hole.total_revenue = 1250
	hole.tee_position = Vector2i(2, 2)
	hole.green_position = Vector2i(10, 10)
	hole.hole_position = Vector2i(10, 10)
	grid.set_tile(hole.green_position, TerrainTypes.Type.GREEN)
	# Leave tee_position as grass so the orphan warning and Place Tee show up.
	GameManager.current_course.add_hole(hole)

	var stats := GameManager.HoleStatistics.new(2)
	stats.record_score(1, 4)
	stats.record_score(2, 4)
	stats.record_score(3, 4)
	stats.record_score(4, 4)
	stats.record_score(5, 4)
	stats.record_score(6, 4)
	GameManager.hole_statistics[2] = stats

	_add_hole_button(2)
	toolbar.show_hole_detail(2)

	var detail_text := ""
	for node in toolbar._hole_detail.find_children("*", "Label", true, false):
		detail_text += (node as Label).text + "\n"
	assert_string_contains(detail_text, "Hole 2 — Par 4")
	assert_string_contains(detail_text, "OPEN")
	assert_string_contains(detail_text, "380 yards  •  Diff: 4.5")
	assert_string_contains(detail_text, "Warning: Missing tee")
	assert_string_contains(detail_text, "Hole Information")
	assert_string_contains(detail_text, "Rating: 4.5")
	assert_string_contains(detail_text, "Difficulty: 4.5 / 10")
	assert_string_contains(detail_text, "Revenue: $1,250")
	assert_string_contains(detail_text, "Stroke Index: 3")
	assert_string_contains(detail_text, "Scoring Statistics")
	assert_string_contains(detail_text, "Rounds Played: 6")
	assert_string_contains(detail_text, "Best Score: 1")
	assert_string_contains(detail_text, "Score Distribution")
	assert_string_contains(detail_text, "Holes-in-One: 1")
	assert_string_contains(detail_text, "Eagles: 2")
	assert_string_contains(detail_text, "Birdies: 1")
	assert_string_contains(detail_text, "Pars: 1")
	assert_string_contains(detail_text, "Bogeys: 1")
	assert_string_contains(detail_text, "Double+: 1")

	var locate_btn := toolbar._hole_detail.find_child("LocateHoleButton", true, false) as Button
	var tee_btn := toolbar._hole_detail.find_child("MoveTeeButton", true, false) as Button
	var green_btn := toolbar._hole_detail.find_child("MoveGreenButton", true, false) as Button
	var par_btn := toolbar._hole_detail.find_child("CycleParButton", true, false) as Button
	var toggle_btn := toolbar._hole_detail.find_child("ToggleHoleButton", true, false) as Button
	var delete_btn := toolbar._hole_detail.find_child("DeleteHoleButton", true, false) as Button
	assert_not_null(locate_btn)
	assert_not_null(tee_btn)
	assert_eq(tee_btn.text, "Place Tee", "An orphaned tee asks to Place Tee")
	assert_not_null(green_btn)
	assert_eq(green_btn.text, "Move Green", "A painted green offers Move Green")
	assert_not_null(par_btn)
	assert_string_contains(par_btn.text, "Cycle Par  [Par 4 (auto)]")
	assert_not_null(toggle_btn)
	assert_eq(toggle_btn.text, "Close Hole")
	assert_not_null(delete_btn)
	assert_eq(delete_btn.text, "Delete Hole")

	watch_signals(toolbar)
	locate_btn.pressed.emit()
	tee_btn.pressed.emit()
	green_btn.pressed.emit()
	par_btn.pressed.emit()
	toggle_btn.pressed.emit()
	delete_btn.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "hole_locate_requested", [2])
	assert_signal_emitted_with_parameters(toolbar, "hole_move_tee_requested", [2])
	assert_signal_emitted_with_parameters(toolbar, "hole_move_green_requested", [2])
	assert_signal_emitted_with_parameters(toolbar, "hole_par_override_requested", [2, 5])
	assert_signal_emitted_with_parameters(toolbar, "hole_toggle_requested", [2])
	assert_signal_emitted_with_parameters(toolbar, "hole_delete_requested", [2])

## A hole that goes takes its button with it and the rest re-seat, which is the
## rebuild main.gd runs whenever the holes are renumbered.
func test_hole_buttons_reseat_when_a_hole_goes() -> void:
	for hole_number in 6:
		_add_hole_button(hole_number + 1)
	var gone: Button = toolbar.hole_grid.get_node("HoleBtn4")
	toolbar.hole_grid.remove_child(gone)
	gone.queue_free()
	toolbar.layout_hole_buttons()

	var grid := toolbar.hole_grid
	assert_eq(grid.get_child_count(), 5, "The hole that went took its button with it")
	assert_eq(grid.columns, 2, "Five holes fill one column of three and one of two")
	# Reading down the columns: 1,2,3 then 5,6.
	var reading_order := [1, 5, 2, 6, 3]
	for slot in reading_order.size():
		assert_eq(int(grid.get_child(slot).get_meta("hole_number")), reading_order[slot],
			"Slot %d reads down the columns after hole 4 went" % slot)

## The Golfers tab is one guest register: a shelf of columns that stack three
## visitors deep — the golfers on the course first, the past visitors after
## them — with the columns running off to the right where the page already
## scrolls, the same rhythm the Holes tab keeps.
func test_the_guest_register_is_a_shelf_of_columns_and_populates() -> void:
	assert_not_null(toolbar._visitor_shelf, "The Golfers tab builds a register shelf")
	assert_true(toolbar._visitor_shelf is HBoxContainer,
		"The shelf runs sideways, so every child of it is a column")
	assert_eq(toolbar._visitor_shelf.get_parent(), toolbar._visitor_register,
		"The shelf is the guest register's own list")

	toolbar.golfer_data_provider = func() -> Array:
		return [
			{"id": 1, "name": "Alice Green", "tier": 1, "hole": 2, "strokes": 3, "attitude": 0.8},
			{"id": 2, "name": "Bob Fairway", "tier": 2, "hole": 5, "strokes": 4, "attitude": 0.5},
		]
	toolbar.record_completed_round({
		"name": "Cara Bunker", "strokes": 72, "par": 72, "day": 1, "tier": 1, "owner": false,
	})
	toolbar._refresh_golfer_lists()

	var shelf := toolbar._visitor_shelf
	assert_eq(shelf.get_child_count(), 1,
		"Two golfers and one past visitor fill a single column of three")
	var column := shelf.get_child(0) as VBoxContainer
	assert_not_null(column, "A column stacks its cards vertically")
	_assert_column_holds(column, ["Alice Green", "Bob Fairway", "Cara Bunker"])
	assert_eq(column.get_child(0).get_child_count(), 3,
		"A golfer on the course carries a portrait, a profile button and Locate")
	assert_eq(column.get_child(2).get_child_count(), 2,
		"A past visitor has no Locate button: there is nobody left to centre on")

## Visitors named Golfer1, Golfer2 ... are on the course, so the column layout
## can be read back off the cards the tab builds.
func _provide_golfers(count: int) -> void:
	toolbar.golfer_data_provider = func() -> Array:
		var rows: Array = []
		for number in count:
			rows.append({"id": number + 1, "name": "Golfer%d" % (number + 1), "tier": 1,
				"hole": number + 1, "strokes": number, "attitude": 0.5})
		return rows

## The visitors in one column, top to bottom. A card reads its name on the
## first line of its profile button, with the status line under it.
func _visitors_in_column(column: Control) -> Array[String]:
	var names: Array[String] = []
	for card in column.get_children():
		var profile_button := card.get_child(1) as Button
		if profile_button != null:
			names.append(profile_button.text.get_slice("\n", 0))
	return names

func _assert_column_holds(column: Control, expected: Array[String]) -> void:
	var found := _visitors_in_column(column)
	assert_eq(found.size(), expected.size(),
		"The column holds %d visitors" % expected.size())
	for slot in mini(found.size(), expected.size()):
		assert_eq(found[slot], expected[slot],
			"Visitor %d of the column reads %s" % [slot + 1, expected[slot]])

## Golfers on the course stack three deep and the columns run off to the right,
## so a busy course grows along the axis the page already scrolls on.
func test_visitors_stack_three_to_a_column() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	_provide_golfers(5)
	toolbar._refresh_golfer_lists()

	var shelf := toolbar._visitor_shelf
	assert_eq(shelf.get_child_count(), 2,
		"Five visitors fill one column of three and spill into a second")
	_assert_column_holds(shelf.get_child(0), ["Golfer1", "Golfer2", "Golfer3"])
	_assert_column_holds(shelf.get_child(1), ["Golfer4", "Golfer5"])

	await _settle_layout()
	var first := shelf.get_child(0) as Control
	var second := shelf.get_child(1) as Control
	var rows: Array[float] = []
	for card in first.get_children():
		var row_y := (card as Control).position.y
		if not rows.has(row_y):
			rows.append(row_y)
	assert_eq(rows.size(), TerrainToolbar.GOLFER_COLUMN_HEIGHT,
		"The first column runs exactly three deep")
	assert_gt(second.position.x, first.position.x,
		"The second column sits to the right of the first, not under it")
	assert_almost_eq(second.get_child(0).global_position.y,
		first.get_child(0).global_position.y, 0.01,
		"The short second column starts level with the top of the first")

## A course at full tilt keeps stacking three to a column for as long as
## golfers keep arriving: the columns run off to the right, where the page
## scrolls.
func test_a_busy_course_fills_one_column_of_three_after_another() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	_provide_golfers(7)
	toolbar._refresh_golfer_lists()

	var shelf := toolbar._visitor_shelf
	assert_eq(shelf.get_child_count(), 3, "Seven visitors fill two columns and start a third")
	_assert_column_holds(shelf.get_child(0), ["Golfer1", "Golfer2", "Golfer3"])
	_assert_column_holds(shelf.get_child(1), ["Golfer4", "Golfer5", "Golfer6"])
	_assert_column_holds(shelf.get_child(2), ["Golfer7"])

## One register holds both kinds of visitor: whoever is on the course reads
## first, the rounds already played follow, and a golfer who finished a round
## while still out there is listed once — as a golfer on the course.
func test_golfers_on_the_course_lead_the_past_visitors() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	_provide_golfers(2)
	# Recorded oldest first, so the register reads R1 then R2 after the golfers.
	for round_name in ["R1", "R2"]:
		toolbar.record_completed_round({
			"name": round_name, "strokes": 71, "par": 72, "day": 1, "tier": 1, "owner": false,
		})
	# Golfer2 holed out but is still on the course, so the round updates their
	# card instead of adding a second one for the same person.
	toolbar.record_completed_round({
		"name": "Golfer2", "strokes": 68, "par": 72, "day": 1, "tier": 1, "owner": false,
	})
	toolbar._refresh_golfer_lists()

	var shelf := toolbar._visitor_shelf
	assert_eq(shelf.get_child_count(), 2, "Four visitors fill a column of three and a second")
	_assert_column_holds(shelf.get_child(0), ["Golfer1", "Golfer2", "R1"])
	_assert_column_holds(shelf.get_child(1), ["R2"])
	var playing := (shelf.get_child(0).get_child(1).get_child(1) as Button).text
	assert_string_contains(playing, "PLAYING",
		"A golfer still on the course keeps their on-course card")

## The Golfers tab has no vertical scroll, so a full column of cards — and the
## profile a card opens — has to fit under the tab bar inside the bottom bar.
func test_the_guest_register_stays_inside_the_bottom_bar() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	_provide_golfers(7)
	for round_number in 5:
		toolbar.record_completed_round({
			"name": "R%d" % (round_number + 1), "strokes": 70 + round_number,
			"par": 72, "day": 1, "tier": 1, "owner": false,
		})
	toolbar._refresh_golfer_lists()
	assert_eq(toolbar._visitor_shelf.get_child_count(), 4,
		"Twelve visitors fill four columns of three")

	await _settle_layout()
	var available := float(UIConstants.BOTTOM_BAR_HEIGHT) \
			- TerrainToolbar.HEADER_HEIGHT
	var content := toolbar.page_content(TerrainToolbar.Tab.GOLFERS)
	assert_gt(content.get_combined_minimum_size().y, 0.0, "The Golfers tab is measured")
	assert_lte(content.get_combined_minimum_size().y, available,
		"Three visitors deep fit under the tab bar")

	# The profile that opens over the register is held to the same height.
	toolbar.show_visitor_profile("Golfer1")
	await _settle_layout()
	assert_true(toolbar._visitor_detail.visible, "The profile opened")
	assert_lte(content.get_combined_minimum_size().y, available,
		"An open visitor profile fits under the tab bar too")

## A card opens that visitor's profile in place of the register, and the way
## back puts the register up again. Locate is the separate action: it centres
## the camera and leaves the register alone.
func test_a_card_opens_the_visitor_profile_over_the_register() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	_provide_golfers(1)
	toolbar._refresh_golfer_lists()
	assert_true(toolbar._visitor_register.visible, "The register leads the tab")
	assert_false(toolbar._visitor_detail.visible, "with no profile over it")

	watch_signals(toolbar)
	var card := toolbar._visitor_shelf.get_child(0).get_child(0) as HBoxContainer
	(card.get_child(1) as Button).pressed.emit()
	assert_eq(toolbar._selected_visitor, "Golfer1", "The card names the visitor it opens")
	assert_true(toolbar._visitor_detail.visible, "The profile takes the page")
	assert_false(toolbar._visitor_register.visible, "and the register steps aside")
	assert_signal_not_emitted(toolbar, "golfer_row_clicked",
		"Reading a profile does not move the camera")

	(toolbar._visitor_detail.get_child(0) as Button).pressed.emit()
	assert_eq(toolbar._selected_visitor, "", "The way back closes the profile")
	assert_true(toolbar._visitor_register.visible, "and the register is up again")

	card = toolbar._visitor_shelf.get_child(0).get_child(0) as HBoxContainer
	(card.get_child(2) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "golfer_row_clicked", [1])
	assert_true(toolbar._visitor_register.visible,
		"Locate centres the camera and leaves the register up")

## A refresh replaces the columns it drew last time instead of stacking the
## fresh ones beside them: the tab refreshes once a second while it is open, so
## stale columns would pile up until they crowded the register out. Leaving the
## course does not strike a golfer off it — they stay on as a past visitor.
func test_golfer_refresh_replaces_the_columns_it_drew_last_time() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	_provide_golfers(6)
	toolbar._refresh_golfer_lists()
	toolbar._refresh_golfer_lists()

	var shelf := toolbar._visitor_shelf
	assert_eq(shelf.get_child_count(), 2,
		"Six golfers still take two columns after a second refresh")
	_assert_column_holds(shelf.get_child(0), ["Golfer1", "Golfer2", "Golfer3"])
	_assert_column_holds(shelf.get_child(1), ["Golfer4", "Golfer5", "Golfer6"])

	_provide_golfers(2)
	toolbar._refresh_golfer_lists()
	assert_eq(shelf.get_child_count(), 2,
		"The columns are redrawn in place, not added to")
	_assert_column_holds(shelf.get_child(0), ["Golfer1", "Golfer2", "Golfer3"])
	_assert_column_holds(shelf.get_child(1), ["Golfer4", "Golfer5", "Golfer6"])
	var still_playing := shelf.get_child(0).get_child(0).get_child(1) as Button
	assert_string_contains(still_playing.text, "PLAYING",
		"The two still out there keep their on-course cards")
	var gone_home := shelf.get_child(1).get_child(2) as HBoxContainer
	assert_eq(gone_home.get_child_count(), 2,
		"The four who left lose their Locate button")
	assert_string_contains((gone_home.get_child(1) as Button).text, "PAST VISITOR",
		"and read as past visitors instead")

## With nobody on the course and no rounds played, the register keeps its
## single column and shows its empty message in it.
func test_an_empty_register_keeps_one_column() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	toolbar.golfer_data_provider = func() -> Array:
		return []
	toolbar._refresh_golfer_lists()

	var shelf := toolbar._visitor_shelf
	assert_eq(shelf.get_child_count(), 1, "The empty message takes a single column")
	var column := shelf.get_child(0) as VBoxContainer
	assert_not_null(column, "The message still sits in a column of its own")
	assert_eq(column.get_child_count(), 1, "That column holds only the message")
	var message := column.get_child(0) as Label
	assert_not_null(message, "The message is a plain label, not a card")
	assert_string_contains(message.text, "Golfers will appear",
		"It says what the empty register is waiting for")

## The Feed button moved out of the Club tab into the left control stack
## (between Menu and Inspect, built in main.gd), so the toolbar no longer
## builds one or tracks its unread count.
func test_feed_button_no_longer_lives_on_the_club_tab() -> void:
	assert_false(TerrainToolbar.TOOL_TAB_MAP.has("feed"),
		"The toolbar no longer maps a feed tool to a tab")
	var tool_types: Array = []
	for card in _club_cards():
		tool_types.append(card.tool_type)
	assert_eq(tool_types, ["course_map", "world_map", "aura_map", "finance",
		"course_milestones", "world_milestones", "achievements"],
		"The Club tab's operations no longer include feed")

## The World Map button moved from the pause menu into the Club tab's
## operations, so it is the tab that opens the company's atlas. The Course Map
## leads the row - it is this course, one tap away - with the atlas beside it.
func test_the_club_tab_opens_the_course_map_and_the_world_map() -> void:
	for tool_type in ["course_map", "world_map"]:
		assert_eq(TerrainToolbar.TOOL_TAB_MAP.get(tool_type), TerrainToolbar.Tab.CLUB,
			"%s belongs to the Club tab" % tool_type)
		assert_true(toolbar._is_menu_action(tool_type),
			"The %s action opens a screen, so it is never a paint tool" % tool_type)
		assert_false(toolbar._tool_buttons.has(tool_type),
			"A menu action holds no terrain tool selection")

	var cards := _club_cards()
	assert_eq(cards[0].tool_type, "course_map",
		"The Course Map leads the Maps column")
	assert_eq(cards[1].tool_type, "world_map",
		"with the company's atlas beside it")

	var course_map: ToolButton = cards[0]
	assert_string_contains(course_map.text, "Land Parcels", "The button reads Land Parcels")
	assert_eq(course_map.hotkey, "Shift+M", "and says which key opens it")
	assert_string_contains(course_map.tool_description, "isometric")
	var world_map: ToolButton = cards[1]
	assert_eq(world_map.text, "World Maps", "The button reads World Maps")
	assert_string_contains(world_map.tool_description, "course sites")

	watch_signals(toolbar)
	toolbar._on_tool_button_pressed("course_map")
	assert_signal_emitted(toolbar, "course_map_pressed")
	toolbar._on_tool_button_pressed("world_map")
	assert_signal_emitted(toolbar, "world_map_pressed")
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.CLUB,
		"Both buttons keep the Club tab open behind them")

func test_action_signals() -> void:
	watch_signals(toolbar)

	toolbar._on_tool_button_pressed("open_hole")
	assert_signal_emitted(toolbar, "open_hole_pressed")

	# Woodland is ordinary paint terrain now: a species tile selects the terrain
	# tool the way Rocks or Wild Flowers do, with no placement mode of its own.
	var first_tree: int = CourseTheme.get_tree_types(GameManager.current_theme)[0]
	toolbar._on_tool_button_pressed(first_tree)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [first_tree])

	toolbar._on_tool_button_pressed("building")
	assert_signal_emitted(toolbar, "building_placement_pressed")

	toolbar._on_tool_button_pressed("decoration")
	assert_signal_emitted(toolbar, "decoration_placement_pressed")

	toolbar._on_tool_button_pressed("vertex")
	assert_signal_emitted_with_parameters(toolbar, "elevation_tool_pressed", ["vertex"])

	toolbar._on_tool_button_pressed("flat")
	assert_signal_emitted_with_parameters(toolbar, "elevation_tool_pressed", ["flat"])

	toolbar._on_tool_button_pressed("gradual")
	assert_signal_emitted_with_parameters(toolbar, "elevation_tool_pressed", ["gradual"])

	toolbar._on_tool_button_pressed("bulldozer")
	assert_signal_emitted(toolbar, "bulldozer_pressed")

	toolbar._on_tool_button_pressed("play_course")
	assert_signal_emitted(toolbar, "play_course_pressed")

	toolbar._on_tool_button_pressed("tournaments")
	assert_signal_emitted(toolbar, "tournaments_pressed")

	toolbar._on_tool_button_pressed("marketing")
	assert_signal_emitted(toolbar, "marketing_pressed")

	toolbar._on_tool_button_pressed("course_milestones")
	assert_signal_emitted(toolbar, "course_milestones_pressed")

	toolbar._on_tool_button_pressed("world_milestones")
	assert_signal_emitted(toolbar, "world_milestones_pressed")

	toolbar._on_tool_button_pressed("achievements")
	assert_signal_emitted(toolbar, "achievements_pressed")

func test_open_hole_button_is_disabled_until_a_pair_is_ready() -> void:
	toolbar.set_open_hole_state(false, "Paint a tee box to go with the waiting green.")
	for button in toolbar._open_hole_buttons:
		assert_true(button.disabled, "Open Hole must wait for a tee box and a cup")
		assert_string_contains(button.tool_description, "Paint a tee box")

	toolbar.set_open_hole_state(true, "")
	for button in toolbar._open_hole_buttons:
		assert_false(button.disabled)

func test_brush_limit_caps_the_brush_for_the_selected_tool() -> void:
	toolbar.set_brush_size(5)
	assert_eq(toolbar.effective_brush_size(), 5)

	toolbar.set_brush_limit(1)
	assert_eq(toolbar.effective_brush_size(), 1)
	assert_eq(toolbar._brush_labels[0].text, "1x1")
	for button in toolbar._brush_buttons:
		assert_true(button.disabled, "A 1x1 cap leaves nothing to change")

	toolbar.set_brush_limit(HoleLayout.UNLIMITED_BRUSH)
	assert_eq(toolbar.effective_brush_size(), 5)
	assert_eq(toolbar._brush_labels[0].text, "5x5")
	for button in toolbar._brush_buttons:
		assert_false(button.disabled)

func test_staff_tab_embeds_staff_management() -> void:
	assert_false(toolbar.has_signal("staff_pressed"),
		"Staff management is inline in the tab; it should not open a popup")
	assert_false(toolbar._tool_buttons.has("staff"),
		"Staff tab should not keep a Staff Management launcher button")
	assert_not_null(toolbar._staff_panel, "Staff tab should embed a StaffPanel")
	assert_true(toolbar._staff_panel is StaffPanel)
	assert_eq(toolbar._staff_panel.get_parent().get_parent(), toolbar.page_scroll(TerrainToolbar.Tab.STAFF),
		"StaffPanel should live on the Staff tab page")

	var labels: Array[String] = []
	for label in toolbar._staff_panel.find_children("*", "Label", true, false):
		labels.append(label.text)
	assert_true(labels.has("HIRE STAFF"), "Staff tab should show hire buttons")
	assert_true(labels.has("CURRENT STAFF"), "Staff tab should show the roster")
	assert_false(labels.has("CONDITION"), "Staff tab keeps only the two required sections")
	assert_false(labels.has("EFFECTS"), "Staff tab keeps only the two required sections")
	assert_eq(toolbar._staff_panel._hire_buttons.size(), 8,
		"Every job type offers a standard and a premium hire")

	# Selecting the Staff tab refreshes the embedded panel rather than emitting a popup signal.
	toolbar.select_tab(TerrainToolbar.Tab.STAFF)
	assert_true(toolbar._pages[TerrainToolbar.Tab.STAFF].visible)
	assert_true(toolbar._staff_panel.visible)

func test_mouse_wheel_horizontal_scroll_input() -> void:
	var scroll: ScrollContainer = toolbar.page_scroll(TerrainToolbar.Tab.TERRAIN)
	scroll.scroll_horizontal = 100

	# Mouse wheel down -> scroll right (increase horizontal offset)
	var event_down = InputEventMouseButton.new()
	event_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event_down.pressed = true
	toolbar._on_scroll_gui_input(event_down, scroll)
	assert_eq(scroll.scroll_horizontal, 150)

	# Mouse wheel up -> scroll left (decrease horizontal offset)
	var event_up = InputEventMouseButton.new()
	event_up.button_index = MOUSE_BUTTON_WHEEL_UP
	event_up.pressed = true
	toolbar._on_scroll_gui_input(event_up, scroll)
	assert_eq(scroll.scroll_horizontal, 100)

func test_flower_bed_boulders_and_trees_are_terrain_tiles_in_course_terrain_tab() -> void:
	# Wild Flowers is a TerrainTileButton in the Course Terrain tab
	var fb_btn: ToolButton = toolbar._tool_buttons[TerrainTypes.Type.FLOWER_BED]
	assert_true(fb_btn is TerrainTileButton, "Wild Flowers should be a TerrainTileButton")
	assert_eq(TerrainToolbar.TOOL_TAB_MAP[TerrainTypes.Type.FLOWER_BED], TerrainToolbar.Tab.TERRAIN,
		"Wild Flowers should belong to the Course Terrain tab")
	assert_eq(fb_btn.tool_name, "Wild Flowers")
	assert_eq(fb_btn.get_parent(), toolbar._course_tiles,
		"Wild Flowers should live on the unified honeycomb in Course Terrain tab")

	# Small and Large Boulders are plain terrain tiles on the same honeycomb.
	for b_type in [TerrainTypes.Type.SMALL_BOULDERS, TerrainTypes.Type.LARGE_BOULDERS]:
		var b_btn: ToolButton = toolbar._tool_buttons[b_type]
		assert_true(b_btn is TerrainTileButton,
			"%s should be a TerrainTileButton" % TerrainTypes.get_type_name(b_type))
		assert_eq(b_btn.get_parent(), toolbar._course_tiles,
			"%s should live on the unified honeycomb in Course Terrain tab" % TerrainTypes.get_type_name(b_type))

	assert_eq(toolbar._tool_buttons[TerrainTypes.Type.SMALL_BOULDERS].tool_name, "Small Boulders")
	assert_eq(toolbar._tool_buttons[TerrainTypes.Type.LARGE_BOULDERS].tool_name, "Large Boulders")

	# The theme's trees are ordinary paint tiles on the same honeycomb as the rest.
	var theme_trees: Array = CourseTheme.get_tree_types(CourseTheme.Type.PARKLAND)
	for tree_type in theme_trees:
		var t_btn: ToolButton = toolbar._tool_buttons[tree_type]
		assert_true(t_btn is TerrainTileButton,
			"%s should be a TerrainTileButton" % TerrainTypes.get_type_name(tree_type))
		assert_eq(t_btn.tool_type, tree_type, "The tile carries its own terrain id")
		assert_eq(t_btn.get_parent(), toolbar._course_tiles,
			"%s should live on the unified honeycomb in Course Terrain tab" % TerrainTypes.get_type_name(tree_type))

	# The unified honeycomb itself sits inside Course Terrain page and has 2 interlocking rows
	assert_not_null(toolbar._course_tiles)
	assert_eq(toolbar._course_tiles.get_parent().get_parent(),
		toolbar.page_content(TerrainToolbar.Tab.TERRAIN),
		"Unified honeycomb should live in Course Terrain tab")
	var total_landscape_tiles: int = 1 + theme_trees.size()
	assert_eq(toolbar._course_tiles.columns, TOP_ROW.size() + ceili(float(total_landscape_tiles) / 2.0),
		"Unified honeycomb should be laid out in two interlocking rows")
	var course_group: Control = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent().get_parent()
	var landscape_group: Control = toolbar._course_tiles.get_parent()
	assert_eq(landscape_group, course_group,
		"Nature & Landscaping should share the course tile group")

func test_improvements_tab_holds_paths_and_every_decoration_tile() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/decorations.json"))["decorations"]
	toolbar.set_decoration_registry(registry)

	var imp_hbox: HBoxContainer = toolbar.page_content(TerrainToolbar.Tab.IMPROVEMENTS)

	# Verify Trees, Boulders, Wild Flowers are NOT in Improvements tab
	var tool_names: Array[String] = []
	for btn in imp_hbox.find_children("*", "ToolButton", true, false):
		tool_names.append(btn.tool_name)

	assert_false(tool_names.has("Trees"), "Improvements tab must not contain Trees")
	assert_false(tool_names.has("Small Boulders"), "Improvements tab must not contain Small Boulders")
	assert_false(tool_names.has("Large Boulders"), "Improvements tab must not contain Large Boulders")
	assert_false(tool_names.has("Wild Flowers"), "Improvements tab must not contain Wild Flowers")
	assert_true(tool_names.has("Path"), "Improvements tab should contain Path")
	assert_false(tool_names.has("Decorations"),
		"The Garden Shed's Decorations button is replaced by the decoration tiles")

	# The garden shed catalogue now lives in the tab as tiles, with the walking
	# path sharing their honeycomb.
	assert_eq(toolbar._decoration_shelf.get_child_count(),
		registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES,
		"Every decoration from the garden shed should be a tile")
	for dec_type in registry:
		var tile: DecorationTileButton = toolbar._decoration_tiles[dec_type]
		assert_not_null(tile, "%s should have a tile" % dec_type)
		assert_eq(tile.get_parent(), toolbar._decoration_shelf)
		assert_eq(tile.decoration_type, dec_type)
		assert_eq(tile.tool_name, registry[dec_type]["name"])
		assert_eq(tile.get_parent().get_parent().get_parent(), imp_hbox,
			"The decoration shelf should sit in the Improvements tab")

func test_path_tile_leads_the_improvements_honeycomb() -> void:
	# The path is no longer a lone button in a PATHS box: it sits in the tile
	# honeycomb on the right of the tab, in slot 0 — the first tile of the top row.
	var shelf: TileHoneycomb = toolbar._decoration_shelf
	var path_tile: TerrainTileButton = toolbar._path_tile
	assert_true(path_tile is TerrainTileButton, "The path is drawn as a course tile")
	assert_eq(path_tile.get_parent(), shelf, "The path belongs to the improvements honeycomb")
	assert_eq(path_tile.get_index(), 0, "The path is the honeycomb's first tile")
	assert_same(toolbar._tool_buttons[TerrainTypes.WALKING_PATH_TOOL], path_tile,
		"The path tile is what the toolbar highlights when the tool is selected")

	toolbar.set_decoration_registry({"bench": {"name": "Bench", "category": "furniture"},
		"statue": {"name": "Statue", "category": "sculptures"},
		"bed": {"name": "Bed", "category": "landscaping"},
		"pool": {"name": "Pool", "category": "water"}})
	assert_eq(shelf.get_child(0), path_tile,
		"Rebuilding the catalogue puts the path back at the head of the top row")
	await _settle_layout()
	var top_row_y: float = path_tile.position.y
	assert_almost_eq(shelf.get_child(1).position.y, top_row_y, 0.01,
		"The first decoration follows the path along the top row")
	assert_gt(shelf.get_child(3).position.y, top_row_y,
		"The row below sits in the notches under the path's row")

	var imp_hbox: HBoxContainer = toolbar.page_content(TerrainToolbar.Tab.IMPROVEMENTS)
	assert_false(imp_hbox.find_children("*", "Label", true, false)
		.any(func(label): return label.text == "PATHS"),
		"The path has no box of its own now it shares the tile shelf")

	# Picking the tile selects the tool and keeps the Improvements tab open.
	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	watch_signals(toolbar)
	path_tile.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.WALKING_PATH_TOOL])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.WALKING_PATH_TOOL)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.IMPROVEMENTS)

func test_path_tile_previews_the_trail_over_the_ground_it_crosses() -> void:
	# A path is a thin trail laid on top of the ground, so its tile shows turf
	# with a ribbon across it instead of a full tile of paving.
	var path_tile: TerrainTileButton = toolbar._path_tile
	var image: Image = path_tile._surface_material.get_shader_parameter("terrain_data").get_image()
	assert_eq(roundi(image.get_pixel(1, 1).r * 255.0), TerrainTypes.Type.ROUGH,
		"The tile previews the rough a walking path is cut through, not cart-path paving")
	assert_eq(roundi(image.get_pixel(0, 1).r * 255.0), TerrainTypes.Type.ROUGH,
		"The turf runs to the edges of the tile: the path paints no patch of ground")
	assert_eq(roundi(image.get_pixel(2, 2).r * 255.0), TerrainTypes.Type.ROUGH,
		"The whole tile is ground the trail crosses")

	# The tile wears the same three passes the overlay draws: a trodden verge,
	# the packed earth and its worn centre, tied together by a pad in the middle.
	var art: Node2D = path_tile.get_node("WalkingPathPreviewArt")
	assert_eq(art.get_child_count(), 5, "Verge and pad, earth and pad, then the centre")
	var center := TerrainTileButton.BUTTON_SIZE * 0.5
	var along := Vector2(TerrainTileButton.TILE_SIZE.x * 0.5, TerrainTileButton.TILE_SIZE.y * 0.5)
	for child in art.get_children():
		for corner in (child as Polygon2D).polygon:
			assert_true(TerrainTileButton.point_on_tile(corner),
				"The trail stays inside the diamond: %s" % corner)
	var verge: Polygon2D = art.get_child(0)
	assert_eq(verge.color, WalkingPathOverlay.DIRT_VERGE,
		"The trodden verge is laid first, so the trail sits on it")
	var band: Polygon2D = art.get_child(2)
	# The ribbon's ends are the midpoints of the two tile edges it joins, so a
	# lone tile reads as a piece of one continuous trail.
	assert_eq((band.polygon[0] + band.polygon[3]) * 0.5, center - along * 0.5,
		"The trail starts at the shared edge with the neighbour up-left")
	assert_eq((band.polygon[1] + band.polygon[2]) * 0.5, center + along * 0.5,
		"and ends at the shared edge with the neighbour down-right")
	assert_eq(band.color, WalkingPathOverlay.DIRT_COLOR,
		"The preview uses the overlay's own dirt colours")
	assert_eq((art.get_child(3) as Polygon2D).color, WalkingPathOverlay.DIRT_COLOR,
		"The pad is drawn in the same earth as the ribbon")
	assert_eq((art.get_child(4) as Polygon2D).color, WalkingPathOverlay.DIRT_LIGHT,
		"and the worn centre line ends up on top")

func test_decoration_tiles_use_the_course_tile_design() -> void:
	var registry := {
		"park_bench": {"name": "Park Bench", "category": "furniture", "cost": 80,
			"daily_upkeep": 0, "description": "A shady seat for the walks."},
		"fountain": {"name": "Fountain", "category": "water", "cost": 500,
			"daily_upkeep": 15, "description": "A sparkling water feature.",
			"unlock": {"type": "reputation", "value": 99}},
	}
	toolbar.set_decoration_registry(registry)

	assert_true(toolbar._decoration_shelf is TileHoneycomb)
	assert_eq(toolbar._decoration_shelf.columns, TerrainToolbar.tile_columns(
		registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES),
		"The shelf's rows count the leading path tile as well as the catalogue")
	assert_eq(toolbar._decoration_shelf.get_child_count(),
		registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES)
	assert_eq(toolbar._decoration_shelf.v_padding, TerrainToolbar.TILE_V_PADDING,
		"The decoration shelf keeps the same breathing room as the other tile tabs")

	for button in _catalogue_tiles():
		assert_true(button is DecorationTileButton, "Decorations should use isometric tile buttons")
		assert_true(button is TerrainTileButton, "Decoration tiles share the Course Terrain button base")
		assert_eq(button.custom_minimum_size, TerrainTileButton.BUTTON_SIZE)
		assert_eq(button.text, "", "Decoration names should be drawn on the tile")
		assert_eq(button._name_label.size, TerrainTileButton.BUTTON_SIZE)
		assert_eq(button.tooltip_text, "", "Only the rich TooltipManager popup should appear")
		assert_not_null(button._decoration_art, "Each tile previews the artwork used on the course")
		assert_false(button.accessibility_description.is_empty())

	var bench: DecorationTileButton = toolbar._decoration_tiles["park_bench"]
	assert_eq(bench.cost, 80)
	assert_eq(bench.maintenance, 0, "Daily upkeep reaches the tooltip footer")
	assert_string_contains(bench.tool_description, "Furniture")
	assert_string_contains(bench.tool_description, "A shady seat for the walks.")

	watch_signals(toolbar)
	bench.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "decoration_selected", ["park_bench"])

func test_decoration_shelf_keeps_the_garden_shed_category_order() -> void:
	var registry := {
		"statue": {"name": "Statue", "category": "sculptures"},
		"bench": {"name": "Bench", "category": "furniture"},
		"bed": {"name": "Bed", "category": "landscaping"},
		"pool": {"name": "Pool", "category": "water"},
		"unknown": {"name": "Oddity"},
	}
	toolbar.set_decoration_registry(registry)

	var order: Array[String] = []
	for child in _catalogue_tiles():
		order.append(child.decoration_type)
	assert_eq(order, ["bed", "pool", "bench", "statue", "unknown"],
		"Decorations should be listed category by category, in shed order")
	assert_eq(toolbar._decoration_shelf.get_child(0), toolbar._path_tile,
		"The path still leads the row the catalogue is laid out in")

func test_locked_decorations_stay_on_the_shelf_until_earned() -> void:
	var registry := {
		"park_bench": {"name": "Park Bench", "category": "furniture", "cost": 80, "daily_upkeep": 0},
		"statue": {"name": "Golfer Statue", "category": "sculptures", "cost": 1000,
			"daily_upkeep": 10, "unlock": {"type": "star_rating", "value": 5}},
	}
	toolbar.set_decoration_registry(registry)

	var open_tile: DecorationTileButton = toolbar._decoration_tiles["park_bench"]
	var locked_tile: DecorationTileButton = toolbar._decoration_tiles["statue"]
	assert_false(open_tile.disabled, "Decorations without a requirement are selectable")
	assert_true(locked_tile.disabled, "Locked decorations stay on the shelf, greyed out")
	assert_true(locked_tile.locked, "The tile knows it is locked")
	assert_almost_eq(locked_tile.modulate.a, 0.65, 0.001, "A locked tile is dimmed like a disabled tool")
	assert_string_contains(locked_tile.tool_description, "Locked")
	assert_string_contains(locked_tile.tool_description, "5★ rating")
	assert_string_contains(locked_tile.tool_description, "Sculptures")

	# Clicking a locked tile never starts a placement.
	watch_signals(toolbar)
	toolbar._on_decoration_card_pressed("statue")
	assert_signal_not_emitted(toolbar, "decoration_selected")

	# A course that earns the fifth star unlocks it on the next refresh.
	var stars: int = GameManager.course_rating.get("stars", 0)
	GameManager.course_rating["stars"] = 5
	toolbar.refresh_decoration_unlocks()
	assert_false(locked_tile.disabled, "Meeting the requirement unlocks the tile")
	assert_false(locked_tile.tool_description.contains("Locked"))
	GameManager.course_rating["stars"] = stars
	toolbar.refresh_decoration_unlocks()
	assert_true(locked_tile.disabled, "Losing the rating locks the tile again")

func test_decoration_unlocks_follow_the_live_course_state() -> void:
	var registry := {
		"bench": {"name": "Bench", "category": "furniture", "unlock":
			{"type": "holes_built", "value": 99}},
	}
	toolbar.set_decoration_registry(registry)
	var tile: DecorationTileButton = toolbar._decoration_tiles["bench"]
	assert_true(tile.disabled, "A course with fewer than 99 holes starts locked")
	assert_string_contains(tile.tool_description, "99 holes")

func test_improvements_decorations_fill_the_page_without_overflowing() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/decorations.json"))["decorations"]
	toolbar.set_decoration_registry(registry)
	toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	await _settle_layout()

	var tile := TerrainTileButton.BUTTON_SIZE
	var two_rows := tile.y * 1.5 + TerrainToolbar.TILE_V_SEPARATION \
			+ 2.0 * TerrainToolbar.TILE_V_PADDING
	assert_almost_eq(toolbar._decoration_shelf.get_combined_minimum_size().y, two_rows, 0.01,
		"The five remaining decorations plus the path fill exactly two interlocking rows")
	assert_eq(toolbar._decoration_shelf.columns,
		ceili(float(registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES) / 2.0))
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT),
		"The Improvements tab must fit inside the bottom bar")

func test_every_decoration_tile_shows_course_artwork() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/decorations.json"))["decorations"]
	for dec_type in registry:
		assert_true(DecorationTileArt.has_art(dec_type),
			"%s should have artwork for its tile" % dec_type)

func test_decoration_shelf_rebuild_leaves_no_stale_tiles() -> void:
	var first := {"a": {"name": "A", "category": "landscaping"}}
	var second := {"b": {"name": "B", "category": "water"}, "c": {"name": "C", "category": "water"}}
	toolbar.set_decoration_registry(first)
	toolbar.set_decoration_registry(second)

	assert_eq(toolbar._decoration_shelf.get_child_count(), 3,
		"Replacing the catalogue should immediately drop the old tiles")
	assert_false(toolbar._decoration_tiles.has("a"))
	assert_eq(toolbar._decoration_shelf.columns, 2,
		"Two decorations plus the leading path tile need two columns")
	assert_eq(toolbar._decoration_shelf.get_child(0), toolbar._path_tile,
		"The path survives the rebuild, at the head of the top row")

func test_theme_change_updates_tree_tiles_in_course_terrain_tab() -> void:
	# Switch theme to DESERT
	GameManager.current_theme = CourseTheme.Type.DESERT
	EventBus.theme_changed.emit(CourseTheme.Type.DESERT)

	var desert_trees: Array = CourseTheme.get_tree_types(CourseTheme.Type.DESERT)
	for tree_type in desert_trees:
		assert_true(toolbar._tool_buttons.has(tree_type),
			"Course Terrain tab should contain Desert %s" % TerrainTypes.get_type_name(tree_type))
		assert_true(toolbar._tool_buttons[tree_type] is TerrainTileButton,
			"%s is a paint tile like every other tile on the tab" % TerrainTypes.get_type_name(tree_type))
	# A species the desert does not grow gives up its tile straight away.
	for tree_type in CourseTheme.get_tree_types(CourseTheme.Type.PARKLAND):
		if tree_type in desert_trees:
			continue
		assert_false(toolbar._tool_buttons.has(tree_type),
			"%s is not on the tab in the desert" % TerrainTypes.get_type_name(tree_type))

	# Reset theme back to PARKLAND
	GameManager.current_theme = CourseTheme.Type.PARKLAND
	EventBus.theme_changed.emit(CourseTheme.Type.PARKLAND)

func test_tree_and_boulder_tile_selection_signals() -> void:
	watch_signals(toolbar)

	# Selecting a tree tile emits tool_selected with its terrain id, as any other
	# paint tile does.
	toolbar._on_tool_button_pressed(TerrainTypes.Type.OAK)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.OAK])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.OAK)
	assert_true(toolbar.has_selection())

	# The boulder tiles are ordinary terrain tiles: they select the terrain tool.
	toolbar._on_tool_button_pressed(TerrainTypes.Type.SMALL_BOULDERS)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.SMALL_BOULDERS])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.SMALL_BOULDERS)
	toolbar._on_tool_button_pressed(TerrainTypes.Type.LARGE_BOULDERS)
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.LARGE_BOULDERS)
	assert_true(toolbar.has_selection())

	# Selecting Wild Flowers selects tool TerrainTypes.Type.FLOWER_BED
	toolbar._on_tool_button_pressed(TerrainTypes.Type.FLOWER_BED)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.FLOWER_BED])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.FLOWER_BED)

func test_theme_changes_keep_one_honeycomb_without_stale_tiles() -> void:
	var original_theme: int = GameManager.current_theme
	var tee: ToolButton = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]
	var grid := toolbar._course_tiles
	for theme in [CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND,
			CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND]:
		GameManager.current_theme = theme
		EventBus.theme_changed.emit(theme)
		var trees: Array = CourseTheme.get_tree_types(theme)
		assert_eq(grid.flow_children().size(), 17 + trees.size(),
			"Theme refresh must immediately remove old tiles, even within one frame")
		assert_eq(grid.columns, ceili(float(grid.flow_children().size()) / 2.0))
		assert_same(toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX], tee,
			"Theme changes must preserve course tile state")
		for key in toolbar._tool_buttons:
			if key is int and TerrainTypes.is_tree(key):
				assert_has(trees, key, "No stale tree tools")
		var tiles: Array[Control] = grid.flow_children()
		for slot in BOTTOM_ROW.size():
			assert_eq(tiles.find(toolbar._tool_buttons[BOTTOM_ROW[slot]]), grid.columns + slot)
		assert_eq(toolbar._pages[TerrainToolbar.Tab.TERRAIN].find_children(
			"*", "TileHoneycomb", true, false).size(), 1)
	GameManager.current_theme = original_theme
	EventBus.theme_changed.emit(original_theme)


# ---------------------------------------------------------------------------
# Elevation tab: selector tools + the separate Elevation Brush
# ---------------------------------------------------------------------------

func test_elevation_tab_has_the_three_selector_tools() -> void:
	for tool_name in ["vertex", "flat", "gradual"]:
		assert_true(tool_name in toolbar._tool_buttons, "%s selector button exists" % tool_name)
		assert_eq(toolbar.TOOL_TAB_MAP[tool_name], TerrainToolbar.Tab.ELEVATION,
				"%s lives on the Elevation tab" % tool_name)
	for old_tool in ["mound", "hollow", "raise", "lower"]:
		assert_false(old_tool in toolbar._tool_buttons, "old tool %s is gone" % old_tool)

func test_elevation_selectors_are_terrain_tile_previews() -> void:
	for tool_name in ["vertex", "flat", "gradual"]:
		var btn = toolbar._tool_buttons[tool_name]
		assert_true(btn is ElevationSelectorButton, "%s is a diamond of terrain tiles" % tool_name)
		assert_not_null(btn.get_node_or_null("ElevationPreviewArt"), "%s shows its example" % tool_name)
	# A grid of tiles has an integer middle row/column: whole-tile maths.
	@warning_ignore("integer_division")
	var mid := ElevationSelectorButton.GRID_TILES / 2
	var vertex: Array = ElevationSelectorButton.example_heights("vertex")
	assert_eq(vertex[mid][mid], 1, "vertex example lifts one vertex")
	assert_eq(vertex[mid][mid + 1], 0, "only one vertex moves")
	var flat: Array = ElevationSelectorButton.example_heights("flat")
	assert_eq(flat[mid - 1][mid - 1], flat[mid][mid], "flat example is level on top")
	var gradual: Array = ElevationSelectorButton.example_heights("gradual")
	assert_gt(gradual[mid][mid], gradual[mid - 1][mid - 1], "gradual example peaks in the middle")

func test_circle_selector_examples_show_the_3x3_brush_as_a_cross() -> void:
	var flat: Array = ElevationSelectorButton.example_heights("flat", false)
	var gradual: Array = ElevationSelectorButton.example_heights("gradual", false)
	var selected_tiles := 0
	for y in ElevationSelectorButton.GRID_TILES:
		for x in ElevationSelectorButton.GRID_TILES:
			var selected: bool = flat[y][x] > 0 and flat[y][x + 1] > 0 and flat[y + 1][x] > 0 and flat[y + 1][x + 1] > 0
			var expected: bool = (x == 2 and y in [1, 2, 3]) or (y == 2 and x in [1, 2, 3])
			assert_eq(selected, expected, "round 3x3 example selects a five-tile cross")
			if selected:
				selected_tiles += 1
	assert_eq(selected_tiles, 5, "the circle's 3x3 footprint contains five tiles")
	assert_eq(gradual[2][2], 2, "the round gradual example keeps its middle vertex raised")
	assert_eq(gradual[3][3], 2, "the round gradual example raises all four middle vertices")
	assert_eq(gradual[1][2], 1, "the cross arms slope down from the middle")
	assert_eq(gradual[1][1], 0, "the round gradual example leaves diagonal corners flat")

func test_square_selector_examples_are_5x5_grids_with_3x3_selected() -> void:
	assert_eq(ElevationSelectorButton.GRID_TILES, 5, "the examples draw 5x5 tile grids")
	assert_eq(ElevationSelectorButton.SELECTED_TILES, 3, "the examples select 3x3 tiles")
	var n: int = ElevationSelectorButton.GRID_TILES + 1
	# Tile indices are whole numbers: the margin is half the leftover tiles.
	@warning_ignore("integer_division")
	var lo: int = (ElevationSelectorButton.GRID_TILES - ElevationSelectorButton.SELECTED_TILES) / 2
	var hi: int = lo + ElevationSelectorButton.SELECTED_TILES

	# Flat: exactly the selected block's corner vertices lift, so the central
	# 3x3 tiles rise together into one level slab and nothing else moves.
	var flat: Array = ElevationSelectorButton.example_heights("flat")
	assert_eq(flat.size(), n, "the flat example spans the whole 5x5 grid")
	for y in n:
		assert_eq(flat[y].size(), n, "each row of the flat example spans the whole 5x5 grid")
		for x in n:
			var on_slab: bool = x >= lo and x <= hi and y >= lo and y <= hi
			assert_eq(flat[y][x], 1 if on_slab else 0,
					"flat example lifts exactly the selected tiles' corners")
	for y in ElevationSelectorButton.GRID_TILES:
		for x in ElevationSelectorButton.GRID_TILES:
			var slab: bool = flat[y][x] > 0 and flat[y][x + 1] > 0 and flat[y + 1][x] > 0 and flat[y + 1][x + 1] > 0
			assert_eq(slab, x >= lo and x < hi and y >= lo and y < hi,
					"flat example selects exactly the central 3x3 tiles")

	# Gradual: the same central 3x3 tiles rise as a smooth hill — one step up
	# at the selection's rim, two over the middle, never more than one step of
	# slope between neighbouring vertices.
	var gradual: Array = ElevationSelectorButton.example_heights("gradual")
	assert_eq(gradual.size(), n, "the gradual example spans the whole 5x5 grid")
	assert_eq(gradual[lo][lo], 1, "the hill's rim on the selection edge is one step up")
	assert_eq(gradual[lo + 1][lo + 1], 2, "the hill peaks over the middle of the selection")
	for y in n:
		for x in n:
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx < n and ny < n:
					assert_lte(absi(gradual[ny][nx] - gradual[y][x]), 1,
							"gradual example keeps at most one step of slope")

func test_elevation_selectors_are_twice_the_catalogue_tile_size() -> void:
	var doubled := TerrainTileButton.BUTTON_SIZE * 2.0
	for tool_name in ["vertex", "flat", "gradual"]:
		var btn = toolbar._tool_buttons[tool_name]
		assert_eq(btn.button_size(), doubled, "%s selector is double size" % tool_name)
		assert_eq(btn.custom_minimum_size, doubled, "%s selector lays out at double size" % tool_name)
		assert_true(btn._has_point(doubled * 0.5), "the centre of the big diamond is clickable")
		assert_true(btn._has_point(Vector2(doubled.x * 0.9, doubled.y * 0.5)),
				"the whole doubled diamond answers to the mouse")

func test_elevation_brush_sizes_are_shared_by_the_square_tools() -> void:
	toolbar.set_elevation_tool("flat")
	assert_eq(toolbar._elevation_brush_sizes(), [1, 2, 3, 4, 5, 6, 7, 8, 9],
			"Flat offers 1x1 through 9x9")
	toolbar.set_elevation_tool("gradual")
	assert_eq(toolbar._elevation_brush_sizes(), [1, 2, 3, 4, 5, 6, 7, 8, 9],
			"Gradual offers the same 1x1 through 9x9")
	toolbar.set_elevation_tool("vertex")
	assert_eq(toolbar._elevation_brush_sizes(), [1, 2, 3, 4, 5, 6, 7, 8, 9],
			"The stepper keeps the shared sizes while Vertex is selected")
	toolbar.set_elevation_tool("")
	assert_eq(toolbar._elevation_brush_sizes(), [1, 2, 3, 4, 5, 6, 7, 8, 9],
			"The stepper keeps the shared sizes with no Square tool selected")

func test_elevation_brush_controls_stay_enabled_without_a_square_tool() -> void:
	toolbar.set_elevation_tool("flat")
	for button in toolbar._elevation_brush_buttons:
		assert_false(button.disabled, "flat: size buttons enabled")
	assert_false(toolbar._elevation_brush_shape_buttons[0].disabled, "flat: shape enabled")
	toolbar.set_elevation_tool("vertex")
	for button in toolbar._elevation_brush_buttons:
		assert_false(button.disabled, "vertex: size buttons stay enabled")
	assert_false(toolbar._elevation_brush_shape_buttons[0].disabled, "vertex: shape stays enabled")
	assert_false(toolbar._elevation_brush_size_notches[0].disabled, "vertex: size stepper stays on")
	toolbar.set_elevation_tool("")
	for button in toolbar._elevation_brush_buttons:
		assert_false(button.disabled, "none: size buttons stay enabled")
	assert_false(toolbar._elevation_brush_shape_buttons[0].disabled, "none: shape stays enabled")
	assert_false(toolbar._elevation_brush_size_notches[0].disabled, "none: size stepper stays on")
	toolbar._set_elevation_brush_size(2)
	toolbar._on_elevation_brush_shape_toggled()
	assert_eq(toolbar.get_elevation_brush_size(), 2, "size can change with no Square tool")
	assert_false(toolbar.get_elevation_brush_square(), "shape can change with no Square tool")

## The Elevation Brush belongs to the two Square Selectors, so its controls sit
## in the notch between the Flat Square and Gradual Square tiles instead of in a
## group of their own beside the row — the same treatment the Open Hole action
## gets on the Course Terrain tab.
func test_elevation_brush_nestles_between_the_two_square_selectors() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._elevation_selectors
	var vertex: Control = toolbar._tool_buttons["vertex"]
	var flat: Control = toolbar._tool_buttons["flat"]
	var gradual: Control = toolbar._tool_buttons["gradual"]
	var size_notch: ElevationBrushSizeNotch = toolbar._elevation_brush_size_notches[0]
	var shape_notch: ElevationBrushNotchButton = toolbar._elevation_brush_shape_buttons[0]

	# The selectors share one honeycomb of a single row, and the brush controls
	# take no slot along it.
	var tiles: Array[Control] = grid.flow_children()
	assert_eq(tiles.size(), 3, "The tab is the three selectors, nothing else")
	assert_eq(tiles[0], vertex, "Vertex opens the row")
	assert_eq(tiles[1], flat, "Flat Square follows it")
	assert_eq(tiles[2], gradual, "Gradual Square closes it")
	for cell in [size_notch, shape_notch]:
		assert_eq(cell.get_parent(), grid, "%s lives on the selector honeycomb" % cell.name)
		assert_true(grid.is_notch_child(cell), "%s fills a notch instead of a tile slot" % cell.name)
		assert_false(grid.flow_children().has(cell), "%s takes no slot along the row" % cell.name)
	assert_eq(grid.notch_slot(size_notch), toolbar.ELEVATION_BRUSH_NOTCH_SLOT,
		"The brush sits to the right of the Flat Square tile")
	assert_eq(grid.notch_slot(shape_notch), toolbar.ELEVATION_BRUSH_NOTCH_SLOT)

	# Where the two Square tiles face each other across the honeycomb's gap.
	var meet := (flat.position + Vector2(flat.size.x, flat.size.y * 0.5)
		+ gradual.position + Vector2(0.0, gradual.size.y * 0.5)) * 0.5
	var half := ElevationSelectorButton.SELECTOR_TILE_SIZE * 0.5
	for cell in [size_notch, shape_notch]:
		assert_eq(cell.size, half, "%s is half a selector diamond" % cell.name)
		assert_almost_eq(cell.size.x, cell.size.y * 2.0, 0.01,
			"%s is an isometric diamond, like the tiles" % cell.name)
		var centre: Vector2 = cell.position + cell.size * 0.5
		assert_almost_eq(centre.x, meet.x, 0.01,
			"%s is centred between the two Square tiles" % cell.name)
		assert_almost_eq(
			(grid.notch_centre(grid.notch_slot(cell), grid.notch_is_above(cell)) - centre).length(),
			0.0, 0.01, "The honeycomb centres %s in its notch" % cell.name)
		for tile in [flat, gradual]:
			for point in _diamond_samples(cell.size):
				assert_false(TerrainTileButton.point_on_tile(
					cell.position + point - tile.position, tile.size),
					"The %s diamond stays clear of the %s tile" % [cell.name, tile.tool_name])

	# The size stepper takes the V above the point where the tiles meet, the
	# shape toggle the V below it — the two gaps either side of that point.
	assert_true(grid.notch_is_above(size_notch), "The size stepper sits above the Square tiles")
	assert_false(grid.notch_is_above(shape_notch), "The shape toggle sits below them")
	assert_almost_eq(size_notch.position.y + size_notch.size.y, meet.y, 0.01,
		"The stepper's bottom point sits on the point where the Square tiles meet")
	assert_almost_eq(shape_notch.position.y, meet.y, 0.01,
		"The shape toggle's top point sits on the point where the Square tiles meet")

	# Only the diamonds answer to the mouse: a click in the empty corner of
	# either bounding box falls through to the tile underneath.
	assert_true(shape_notch._has_point(shape_notch.size * 0.5), "The middle of the shape cell is clickable")
	assert_false(shape_notch._has_point(Vector2(1, 1)),
		"The empty corner of the shape cell's box falls through to the tiles")

## The stepper's three cells sit inside the diamond, so the whole stepper reads
## as one control in the notch rather than three loose buttons.
func test_elevation_brush_size_stepper_cells_stay_inside_the_diamond() -> void:
	await _settle_layout()
	var notch: ElevationBrushSizeNotch = toolbar._elevation_brush_size_notches[0]
	for cell in [notch.decrease_button, notch.size_label, notch.increase_button]:
		for corner in [Vector2.ZERO, Vector2(cell.size.x, 0.0), cell.size, Vector2(0.0, cell.size.y)]:
			assert_true(TerrainTileButton.point_on_tile(cell.position + corner, notch.size),
				"The %s cell stays inside the notch diamond" % cell.name)
	assert_lt(notch.decrease_button.position.x, notch.size_label.position.x,
		"Smaller comes first")
	assert_lt(notch.size_label.position.x, notch.increase_button.position.x,
		"The size it paints with sits between the two steps")

## The shape cell carries the brush's state as a glyph over a word naming it,
## both small enough to stay inside the diamond.
func test_elevation_brush_shape_cell_shows_the_shape_it_paints_with() -> void:
	await _settle_layout()
	var shape: ElevationBrushNotchButton = toolbar._elevation_brush_shape_buttons[0]
	toolbar.set_elevation_tool("flat")
	assert_eq(shape.caption, "□", "A square brush shows the square glyph")
	assert_string_contains(shape.tooltip_text, "Square elevation brush",
		"The hover tooltip still names the control")
	toolbar._on_elevation_brush_shape_toggled()
	assert_eq(shape.caption, "○", "A round brush shows the round glyph")
	assert_false(toolbar._tool_buttons["flat"]._brush_square,
		"The Flat Square example follows the round brush shape")
	assert_false(toolbar._tool_buttons["gradual"]._brush_square,
		"The Gradual Square example follows the round brush shape")

	var font := shape.get_theme_font("font")
	var word := font.get_string_size(ElevationBrushNotchButton.LABEL_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ElevationBrushNotchButton.LABEL_FONT_SIZE)
	# The word's far corner must stay inside the diamond: |x|/a + |y|/b <= 1.
	var corner := Vector2(word.x * 0.5, ElevationBrushNotchButton.LABEL_DROP + word.y * 0.5)
	assert_lte(corner.x / (shape.size.x * 0.5) + corner.y / (shape.size.y * 0.5), 1.0,
		"The word under the glyph stays inside the diamond at the height it rides at")

## Moving the controls into the notch leaves the brush itself working exactly as
## it did in its own group.
func test_elevation_brush_notch_cells_still_change_the_brush() -> void:
	await _settle_layout()
	toolbar.set_elevation_tool("flat")
	var notch: ElevationBrushSizeNotch = toolbar._elevation_brush_size_notches[0]
	var shape: ElevationBrushNotchButton = toolbar._elevation_brush_shape_buttons[0]
	watch_signals(toolbar)

	notch.increase_button.pressed.emit()
	assert_signal_emitted(toolbar, "elevation_brush_size_changed")
	assert_eq(toolbar.get_elevation_brush_size(), 4, "Bigger paints one size up")
	assert_eq(notch.size_label.text, "4x4", "The readout keeps up with the tool")
	notch.decrease_button.pressed.emit()
	assert_eq(toolbar.get_elevation_brush_size(), 3, "Smaller paints one size down")

	shape.pressed.emit()
	assert_signal_emitted(toolbar, "elevation_brush_shape_changed")
	assert_false(toolbar.get_elevation_brush_square(), "The shape toggle still flips the brush")

## The selectors' single row of doubled diamonds fills the same page height as
## the two interlocking course rows, so the toolbar never changes height with
## the tab.
func test_elevation_selectors_fill_the_same_page_height_as_the_course_tiles() -> void:
	await _settle_layout()
	assert_almost_eq(toolbar._elevation_selectors.get_combined_minimum_size().y,
		toolbar._course_tiles.get_combined_minimum_size().y, 0.01,
		"One row of doubled selector diamonds fills the page two course rows fill")

func test_elevation_tab_is_just_the_selector_honeycomb() -> void:
	var content: HBoxContainer = toolbar.page_content(TerrainToolbar.Tab.ELEVATION)
	assert_eq(content.get_child_count(), 1,
		"The Elevation tab is just the selector honeycomb — the brush rides in its notch")
	assert_eq(content.get_child(0).get_child(0), toolbar._elevation_selectors,
		"The honeycomb is the tab's only group")

func test_elevation_brush_shares_settings_between_square_tools() -> void:
	toolbar.set_elevation_tool("flat")
	toolbar._set_elevation_brush_size(7)
	toolbar._on_elevation_brush_shape_toggled()  # square -> round
	assert_eq(toolbar.get_elevation_brush_size(), 7)
	assert_false(toolbar.get_elevation_brush_square())

	toolbar.set_elevation_tool("gradual")
	# Gradual uses the same size and shape Flat just set.
	assert_eq(toolbar.get_elevation_brush_size(), 7)
	assert_false(toolbar.get_elevation_brush_square())

	toolbar.set_elevation_tool("vertex")
	assert_eq(toolbar.get_elevation_brush_size(), 7, "Vertex keeps the shared size")
	assert_false(toolbar.get_elevation_brush_square(), "Vertex keeps the shared shape")

	toolbar.set_elevation_tool("flat")
	assert_eq(toolbar.get_elevation_brush_size(), 7, "flat still has the shared size")
	assert_false(toolbar.get_elevation_brush_square(), "flat still has the shared shape")

func test_elevation_brush_size_1x1_is_shared_with_gradual() -> void:
	toolbar.set_elevation_tool("flat")
	toolbar._set_elevation_brush_size(1)
	toolbar.set_elevation_tool("gradual")
	assert_eq(toolbar.get_elevation_brush_size(), 1, "Gradual can use the shared 1x1 size")
	toolbar.set_elevation_tool("vertex")
	assert_eq(toolbar.get_elevation_brush_size(), 1, "1x1 stays set without a Square tool")
	var sizes: Array = toolbar._elevation_brush_sizes()
	for size in sizes:
		assert_true(size in ElevationTool.BRUSH_SIZES)

func test_elevation_brush_signals_report_the_new_settings() -> void:
	watch_signals(toolbar)
	toolbar.set_elevation_tool("flat")
	toolbar._set_elevation_brush_size(5)
	assert_signal_emitted_with_parameters(toolbar, "elevation_brush_size_changed", [5])
	toolbar._on_elevation_brush_shape_toggled()
	assert_signal_emitted_with_parameters(toolbar, "elevation_brush_shape_changed", [false])

func test_section_navigation_remembers_tabs_and_shows_only_its_rail() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.ELEVATION)
	toolbar.select_section(TerrainToolbar.Section.MANAGE)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.CLUB,
		"Manage opens on its front page")
	toolbar.select_tab(TerrainToolbar.Tab.HOLES)
	toolbar.select_section(TerrainToolbar.Section.BUILD)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.ELEVATION)
	toolbar.select_section(TerrainToolbar.Section.MANAGE)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.HOLES,
		"Manage comes back to the tab last used in it")
	for index in toolbar._tab_buttons:
		var button: PixelCircleButton = toolbar._tab_buttons[index]
		assert_eq(button.visible, index in TerrainToolbar.SECTION_TABS[TerrainToolbar.Section.MANAGE])
		assert_eq(button.button_pressed, index == TerrainToolbar.Tab.HOLES)
	toolbar.select_tab(-1)
	toolbar.select_section(50)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.HOLES, "Invalid navigation is ignored")

func test_section_button_hides_the_open_section_and_reopens_it() -> void:
	watch_signals(toolbar)
	toolbar.select_section(TerrainToolbar.Section.BUILD)

	toolbar.toggle_section(TerrainToolbar.Section.BUILD)
	assert_true(toolbar.section_collapsed)
	assert_false(toolbar.visible, "The open section's shelf is hidden")
	assert_signal_emitted_with_parameters(toolbar, "section_visibility_changed", [false])

	toolbar.toggle_section(TerrainToolbar.Section.BUILD)
	assert_false(toolbar.section_collapsed)
	assert_true(toolbar.visible, "Pressing the section again shows it")

	toolbar.toggle_section(TerrainToolbar.Section.MANAGE)
	assert_eq(toolbar.current_section, TerrainToolbar.Section.MANAGE)
	assert_true(toolbar.visible, "Another section's button opens its shelf")

	toolbar.toggle_section(TerrainToolbar.Section.MANAGE)
	assert_false(toolbar.visible)
	toolbar.toggle_section(TerrainToolbar.Section.MANAGE)
	toolbar.collapse_section()
	toolbar.select_tab(TerrainToolbar.Tab.CLUB)
	assert_true(toolbar.visible, "Choosing a tab reopens the collapsed section")
	assert_false(toolbar.section_collapsed)

func test_golfer_tabs_share_the_persistent_player_without_nested_navigation() -> void:
	var player := toolbar.player_tab
	assert_false(player.navigation.visible)
	for index in TerrainToolbar.PLAYER_TABS.size():
		toolbar.select_player_section(index)
		assert_eq(toolbar.current_section, TerrainToolbar.Section.GOLFERS)
		assert_eq(toolbar.current_tab, TerrainToolbar.PLAYER_TABS[index])
		assert_eq(player.selected, index)
		assert_true(player.pages[index].get_parent().is_visible_in_tree())
		assert_eq(toolbar._pages.filter(func(page): return page.visible).size(), 1)
	assert_eq(player.skill_badge.get_parent(), toolbar._tab_buttons[TerrainToolbar.Tab.PLAYER_SKILLS])
	player.select(PlayerTab.PAGE_PLAY)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.PLAYER, "Round setup updates the circular rail")
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	player.select(PlayerTab.PAGE_EDIT)
	assert_eq(toolbar.current_section, TerrainToolbar.Section.BUILD, "Background updates never hijack building")

## The Club tab folds the old Maps, Review and Milestone tabs into
## one shelf. Each former tab keeps its labelled column, so its actions still
## read as the group they were.
func test_the_club_tab_gathers_the_former_manage_tabs_in_labelled_groups() -> void:
	var expected := [
		["MAPS", ["course_map", "world_map"]],
		["REVIEW", ["aura_map", "finance"]],
		["MILESTONES", ["course_milestones", "world_milestones", "achievements"]],
	]
	var groups := toolbar.page_content(TerrainToolbar.Tab.CLUB).get_children()
	assert_eq(groups.size(), expected.size(), "One column per folded tab")
	watch_signals(toolbar)
	for i in expected.size():
		var group: VBoxContainer = groups[i]
		assert_not_null(group, "The folded tab is a labelled column")
		assert_eq((group.get_child(0) as Label).text, expected[i][0],
			"The column keeps the name of the tab it folded")
		var buttons := group.get_child(1).get_children()
		assert_eq(buttons.map(func(button): return button.tool_type), expected[i][1],
			"%s holds the actions of the tab it folded" % expected[i][0])
		for button in buttons:
			assert_true(button is DockActionButton)
			assert_true(PixelCircleButton.ICONS.has(button.glyph),
				"%s draws the icon it asks for" % button.tool_name)
			button.pressed.emit()
			assert_eq(toolbar.current_tab, TerrainToolbar.Tab.CLUB)
			assert_eq(toolbar.current_section, TerrainToolbar.Section.MANAGE)
	for signal_name in ["course_map_pressed", "world_map_pressed", "aura_map_pressed",
			"financial_overview_pressed", "course_milestones_pressed",
			"world_milestones_pressed", "achievements_pressed"]:
		assert_signal_emitted(toolbar, signal_name)

func test_the_club_tab_has_no_marketing_button() -> void:
	for card in _club_cards():
		assert_ne(card.tool_type, "marketing", "Marketing is not a Club tab action")

## The Club tab's three labelled columns fit under the tab bar: one row of
## action cards plus its heading, with no vertical scroll.
func test_the_club_tab_fits_inside_the_bottom_bar() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.CLUB)
	await _settle_layout()
	var content := toolbar.page_content(TerrainToolbar.Tab.CLUB)
	var available := float(UIConstants.BOTTOM_BAR_HEIGHT) - TerrainToolbar.HEADER_HEIGHT
	assert_gt(content.get_combined_minimum_size().y, 0.0, "The Club tab is measured")
	assert_lte(content.get_combined_minimum_size().y, available,
		"The headings and the action cards fit under the tab bar")

## Every action card on the Club tab, in reading order: Maps, Review,
## Milestones.
func _club_cards() -> Array[DockActionButton]:
	var cards: Array[DockActionButton] = []
	for group in toolbar.page_content(TerrainToolbar.Tab.CLUB).get_children():
		for child in group.get_child(1).get_children():
			if child is DockActionButton:
				cards.append(child)
	return cards
